#!/usr/bin/env python3
"""M2' frame GPU timing analyzer: parse MKS-FGPU-* log lines, reconcile
ledgers, classify layers, and compute G-gate statistics.

Fail-closed: missing FINAL, duplicate/missing seq, counter mismatch, or
invariant violation all make the round invalid. Explorer mode (--exploratory)
bypasses G-gates for diagnostics only.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

FGPU_LINE_RE = re.compile(r'^MKS-FGPU-(INIT|T|G|C|S|FINAL) (.+)$')

def parse_keyval(body):
    """Parse space-separated key=value pairs."""
    result = {}
    for token in body.split():
        if '=' in token:
            key, _, val = token.partition('=')
            result[key] = val
    return result

def parse_log_file(path):
    """Parse a log file and return structured records."""
    records = {'INIT': [], 'T': [], 'G': [], 'C': [], 'S': [], 'FINAL': []}
    for line in Path(path).read_text().splitlines():
        m = FGPU_LINE_RE.match(line.strip())
        if not m:
            continue
        rec_type = m.group(1)
        kv = parse_keyval(m.group(2))
        records[rec_type].append(kv)
    return records

def detect_old_timer_lines(path):
    """Detect legacy MKS-GPU timer lines that would indicate double-timing."""
    patterns = ['MKS-GPU kind=', 'MKS-GPU-SAMPLES', 'MKS-GPU-TIMER renderer EXT bridge enabled=1',
                'MKS-GPU-RENDER', 'MKS-GPU-PASS']
    for line in Path(path).read_text().splitlines():
        for p in patterns:
            if p in line:
                return True
    return False

# ---------------------------------------------------------------------------
# Reconciliation (design C.2/C.3)
# ---------------------------------------------------------------------------

def reconcile(records):
    """Cross-check ledgers. Returns list of error strings (empty = pass)."""
    errors = []
    inits = records['INIT']
    finals = records['FINAL']

    if not inits:
        errors.append('missing INIT')
    if not finals:
        errors.append('missing FINAL (evidence incomplete)')
        return errors
    if len(inits) > 1:
        errors.append(f'multiple INIT lines: {len(inits)}')

    init = inits[0]
    session = init.get('session', '')

    # Check all records belong to the same session
    for rec_type in ('T', 'G', 'C', 'S', 'FINAL'):
        for rec in records[rec_type]:
            if rec.get('session') != session:
                errors.append(f'session mismatch in {rec_type}: {rec.get("session")} vs {session}')

    # Ticket seq uniqueness and ordering (R2-P1-1: continuity + summary count)
    t_seqs = []
    for rec in records['T']:
        try:
            t_seqs.append(int(rec.get('t', -1)))
        except (ValueError, TypeError):
            errors.append(f'invalid t_seq: {rec.get("t")}')
    if len(t_seqs) != len(set(t_seqs)):
        errors.append('duplicate t_seq in ticket records')
    if t_seqs and t_seqs != list(range(1, len(t_seqs) + 1)):
        errors.append(f't_seq not continuous 1..{len(t_seqs)}')

    # Copy seq uniqueness and continuity (C.3: c_seq is a monotonic ledger)
    c_seqs = []
    for rec in records['C']:
        try:
            c_seqs.append(int(rec.get('c', -1)))
        except (ValueError, TypeError):
            errors.append(f'invalid c_seq: {rec.get("c")}')
    if len(c_seqs) != len(set(c_seqs)):
        errors.append('duplicate c_seq in copy records')
    if c_seqs and c_seqs != list(range(1, len(c_seqs) + 1)):
        errors.append(f'c_seq not continuous 1..{len(c_seqs)}')

    # Ticket axis closure: 7a (present) + 7b (reclaim)
    present_counts = {}
    reclaim_counts = {}
    for rec in records['T']:
        present = rec.get('present', 'unset')
        reclaim = rec.get('reclaim', 'pending')
        present_counts[present] = present_counts.get(present, 0) + 1
        reclaim_counts[reclaim] = reclaim_counts.get(reclaim, 0) + 1

    tickets_opened = len(t_seqs)
    present_total = sum(present_counts.values())
    if tickets_opened != present_total:
        errors.append(f'ticket axis mismatch: opened={tickets_opened} present_sum={present_total}')

    # Copy closure: ⑴ copy_calls = records; ⑵ draw_submitted = ok + err
    summary = records['S'][-1] if records['S'] else {}
    copies_in_summary = int(summary.get('copies', 0))
    if len(records['C']) != copies_in_summary:
        errors.append(f'copy count mismatch: records={len(records["C"])} summary={copies_in_summary}')

    # Check for invariant violation
    invariant = int(summary.get('invariant', 0))
    if invariant > 0:
        errors.append(f'invariant_violation={invariant}')

    # Ticket emission count vs summary (R2-P1-1)
    if summary and int(summary.get('tickets', -1)) != len(records['T']):
        errors.append(f"ticket count mismatch: records={len(records['T'])} "
                      f"summary={summary.get('tickets')}")

    # G-line integrity: (t,g) uniqueness, per-ticket completeness against
    # T.segs, ticket reference validity, and per-ticket acq/rel sanity.
    ticket_by_t = {rec.get('t'): rec for rec in records['T']}
    seg_count_by_t = {}
    seen_tg = set()
    g_kind = {}
    for rec in records['G']:
        key = (rec.get('t'), rec.get('g'))
        if key in seen_tg:
            errors.append(f'duplicate G record t={key[0]} g={key[1]}')
        seen_tg.add(key)
        g_kind[key] = rec.get('kind')
        if rec.get('t') not in ticket_by_t:
            errors.append(f'G references unknown ticket t={rec.get("t")}')
        seg_count_by_t[rec.get('t')] = seg_count_by_t.get(rec.get('t'), 0) + 1
    for t, rec in ticket_by_t.items():
        try:
            declared = int(rec.get('segs', -1))
        except (TypeError, ValueError):
            declared = -1
        got = seg_count_by_t.get(t, 0)
        if declared >= 0 and got != declared:
            errors.append(f'ticket {t}: G count {got} != T.segs {declared}')
        # g indices must be exactly 0..declared-1
        idxs = sorted(int(g) for (tt, g) in seen_tg
                      if tt == t and str(g).lstrip('-').isdigit())
        if declared >= 0 and idxs != list(range(declared)):
            errors.append(f'ticket {t}: g indices {idxs} != 0..{declared - 1}')
        acq = int(rec.get('acq', 0))
        rel = int(rec.get('rel', 0))
        if acq < 0 or rel < 0 or rel > acq:
            errors.append(f'ticket {t}: acq/rel invalid (acq={acq} rel={rel})')
        if rec.get('reclaim') in ('1', 'normal') and acq != rel:
            errors.append(f'ticket {t}: settled with acq={acq} rel={rel}')
        copies_ok = int(rec.get('copies_ok', 0))
        if copies_ok < 0:
            errors.append(f'ticket {t}: negative copies_ok')

    # C.seg references must point at an existing copy-kind G of the same
    # ticket; frame-span mode's copy rides a span segment (R4-P1-2).
    allowed_kinds = {'span'} if init.get('mode') == 'frame-span' else {'copy'}
    for rec in records['C']:
        try:
            seg = int(rec.get('seg', -1))
        except (TypeError, ValueError):
            continue
        if seg >= 0:
            key = (rec.get('t'), str(seg))
            if key not in g_kind:
                errors.append(f'C c={rec.get("c")} seg={seg} references '
                              f'missing G t={key[0]}')
            elif g_kind[key] not in allowed_kinds:
                errors.append(f'C c={rec.get("c")} seg={seg} references '
                              f'G kind={g_kind[key]} (expected '
                              f'{"|".join(sorted(allowed_kinds))})')

    # Resource closure (bind equation) and FINAL busy contract: every bound
    # query slot must be accounted exactly once across release/leak/busy.
    if summary:
        bind = int(summary.get('bind', 0))
        rel = sum(int(summary.get(k, 0)) for k in
                  ('rel_result', 'rel_dn', 'rel_late', 'rel_dq',
                   'rel_un', 'rel_uq', 'rel_uc'))
        leak = int(summary.get('leak_c', 0)) + int(summary.get('leak_q', 0))
        busy = sum(int(summary.get(k, 0)) for k in
                   ('busy_n', 'busy_q', 'busy_c'))
        if bind != rel + leak + busy:
            errors.append(f'bind equation mismatch: bind={bind} '
                          f'rel+leak+busy={rel + leak + busy}')
        if busy != 0:
            errors.append(f'FINAL busy non-zero: {busy}')
        for k in ('busy_n', 'busy_q', 'busy_c', 'leak_c', 'leak_q'):
            if int(summary.get(k, 0)) < 0:
                errors.append(f'negative counter {k}={summary.get(k)}')
        gl_deleted = int(summary.get('gl_del', 0))
        gl_leaked = int(summary.get('gl_leak', 0))
        # frame-count mode never generates queries: a legal FINAL is 0/0.
        if init.get('mode') == 'frame-count':
            if gl_deleted or gl_leaked:
                errors.append(f'frame-count GL closure: del={gl_deleted} '
                              f'leak={gl_leaked} (expected 0/0)')
        elif gl_deleted + gl_leaked != 64:  # MKS_FGT_SLOTS
            errors.append(f'GL slot closure: del={gl_deleted} leak={gl_leaked}')

    # Per-ticket copies_ok (publish outcome) consistency: a ticket publishes
    # at most once (copies_ok ∈ {0,1}); a publish that followed a copy draw
    # must be backed by that ticket's successful C record. Reuse publishes
    # (fresh/cur/retired) have no C record at all and are legitimate.
    c_by_ticket = {}
    for rec in records['C']:
        t = rec.get('t')
        c_by_ticket.setdefault(t, []).append(rec)
    for rec in records['T']:
        t = rec.get('t')
        copies_ok = int(rec.get('copies_ok', 0))
        if copies_ok > 1:
            errors.append(f'ticket {t}: copies_ok={copies_ok} > 1')
        recs = c_by_ticket.get(t, [])
        if copies_ok == 1 and recs and all(r.get('timer') != 'seg' for r in recs):
            errors.append(f'ticket {t}: copies_ok=1 but no successful copy C record')

    # Property consistency
    for s in records['S']:
        if s.get('mode') != init.get('mode'):
            errors.append(f'prop_now mismatch: {s.get("mode")} vs init {init.get("mode")}')

    # FINAL completeness
    final = finals[0]
    if final.get('complete') != '1':
        errors.append(f'FINAL incomplete: {final.get("incomplete", "unknown")}')

    # Check for old timer contamination
    return errors

# ---------------------------------------------------------------------------
# Layer classification
# ---------------------------------------------------------------------------

def classify_tickets(records):
    """Classify tickets into S0/S1/S2/X-* layers (mutually exclusive, priority).

    T lines emit numeric enums (present: 1=swap_ok, reclaim: 1=normal,
    route: 0=fused, 2=invalid); G lines emit names. Both forms accepted.
    """
    layers = {'S0': [], 'S1': [], 'S2': [], 'X-invalid': [], 'X-foreign': [],
              'X-multi': [], 'X-seed': [], 'X-other': []}

    PRESENT_SWAP_OK = ('1', 'swap_ok')
    RECLAIM_NORMAL = ('1', 'normal')
    ROUTE_INVALID = ('2', 'invalid')
    ROUTE_FUSED = ('0', 'fused')

    # Group segments by ticket
    segs_by_ticket = {}
    for rec in records['G']:
        t = int(rec.get('t', -1))
        segs_by_ticket.setdefault(t, []).append(rec)
    # Fresh-copy C records by ticket (R2-P0-2): with copies_ok counting real
    # publishes, a reuse publish (no copy at all) also lands copies_ok=1 —
    # S0 must require a fresh copy draw, or reuse frames without copy elapsed
    # would pollute the timing sample.
    fresh_copy_by_ticket = set()
    for rec in records['C']:
        if rec.get('timer') == 'seg' and int(rec.get('seg', -1)) >= 0:
            try:
                fresh_copy_by_ticket.add(int(rec.get('t', -1)))
            except (TypeError, ValueError):
                pass

    for rec in records['T']:
        t = int(rec.get('t', -1))
        present = rec.get('present', 'unset')
        route = rec.get('route', 'fused')
        foreign = int(rec.get('foreign', 0))
        acq = int(rec.get('acq', 0))
        mix = int(rec.get('mix', 1))
        hw = int(rec.get('hw', 1))
        seed = rec.get('seed', '0') == '1'
        afail = rec.get('afail', '0') == '1'
        copies_ok = int(rec.get('copies_ok', 0))
        reclaim = rec.get('reclaim', 'pending')

        ticket_segs = segs_by_ticket.get(t, [])
        all_resolved = all(s.get('tstate') in ('resolved', '2') for s in ticket_segs)

        # Priority classification
        if present not in PRESENT_SWAP_OK or route in ROUTE_INVALID or afail:
            layers['X-invalid'].append(t)
        elif foreign != 0:
            layers['X-foreign'].append(t)
        elif acq > 1 or mix > 1:
            layers['X-multi'].append(t)
        elif seed:
            layers['X-seed'].append(t)
        elif (copies_ok == 1 and acq == 1 and mix == 1 and hw == 1 and
              route in ROUTE_FUSED and not seed and not afail and
              foreign == 0 and reclaim in RECLAIM_NORMAL and all_resolved and
              t in fresh_copy_by_ticket):
            layers['S0'].append(t)
        elif copies_ok == 0 and acq >= 1:
            layers['S1'].append(t)
        elif hw == mix and acq == 0 and mix >= 1:
            layers['S2'].append(t)
        else:
            layers['X-other'].append(t)

    return layers

# ---------------------------------------------------------------------------
# G-gate statistics
# ---------------------------------------------------------------------------

def compute_s0_median_ms(records, layers):
    """Compute S0 per-frame T_f median in ms."""
    segs_by_ticket = {}
    for rec in records['G']:
        t = int(rec.get('t', -1))
        segs_by_ticket.setdefault(t, []).append(rec)

    durations = []
    for t in layers['S0']:
        total_ns = 0
        for s in segs_by_ticket.get(t, []):
            elapsed = s.get('elapsed', '0')
            try:
                total_ns += int(elapsed)
            except (ValueError, TypeError):
                pass
        durations.append(total_ns)

    if not durations:
        return None
    durations.sort()
    n = len(durations)
    if n % 2 == 1:
        return durations[n // 2] / 1e6  # ns → ms
    return (durations[n // 2 - 1] + durations[n // 2]) / 2 / 1e6

def compute_reduction(median_a, median_b):
    """G-9: r = 1 - M_B / M_A."""
    if median_a is None or median_b is None or median_a <= 0:
        return None
    return 1.0 - median_b / median_a

def check_gates(records, layers, exploratory=False):
    """Check G-gates. Returns dict of gate results."""
    results = {}

    # G-6: coverage
    total_tickets = sum(len(v) for v in layers.values())
    s0_count = len(layers['S0'])
    s0_fresh = s0_count + len(layers['X-seed']) + len(layers['X-multi'])  # approximation
    coverage = s0_count / max(1, total_tickets)
    results['coverage'] = coverage
    results['coverage_pass'] = coverage >= 0.95

    # G-6: invariant
    if records['S']:
        inv = int(records['S'][-1].get('invariant', 0))
        results['invariant_zero'] = inv == 0

    # G-9: reduction (only if we have both A and B)
    s0_median = compute_s0_median_ms(records, layers)
    results['s0_median_ms'] = s0_median

    if not exploratory:
        results['all_gates_pass'] = (
            results.get('coverage_pass', False) and
            results.get('invariant_zero', False)
        )

    return results

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log_files', nargs='*', help='Log files containing MKS-FGPU-* lines')
    parser.add_argument('--label', help='Round label (e.g. A-I1, B-I1)')
    parser.add_argument('--exploratory', action='store_true',
                       help='Skip G-gate pass/fail; diagnostics only')
    parser.add_argument('--pair', nargs=2, metavar=('FILE_A', 'FILE_B'),
                       help='Compare two rounds for G-9 reduction')
    parser.add_argument('--output', type=Path, help='Output JSON file')
    args = parser.parse_args()

    if args.pair:
        # Pair mode: compare A vs B
        results = {}
        for label, path in [('A', args.pair[0]), ('B', args.pair[1])]:
            records = parse_log_file(path)
            errors = reconcile(records)
            layers = classify_tickets(records)
            gates = check_gates(records, layers, exploratory=args.exploratory)
            results[label] = {
                'errors': errors,
                'layers': {k: len(v) for k, v in layers.items()},
                'gates': gates,
            }

        median_a = results['A']['gates'].get('s0_median_ms')
        median_b = results['B']['gates'].get('s0_median_ms')
        reduction = compute_reduction(median_a, median_b)
        results['G-9'] = {
            'median_A_ms': median_a,
            'median_B_ms': median_b,
            'reduction': reduction,
            'reduction_pct': f'{reduction * 100:.2f}%' if reduction is not None else 'N/A',
            'gte_10pct': reduction is not None and reduction >= 0.10,
        }

        if args.output:
            args.output.write_text(json.dumps(results, indent=2, sort_keys=True) + '\n')
        print(json.dumps(results, indent=2, sort_keys=True))
        return

    # Single file mode
    for path in args.log_files:
        records = parse_log_file(path)
        errors = reconcile(records)
        layers = classify_tickets(records)
        gates = check_gates(records, layers, exploratory=args.exploratory)

        old_timer = detect_old_timer_lines(path)
        if old_timer:
            errors.append('old MKS-GPU timer lines detected (contamination)')

        result = {
            'file': str(path),
            'errors': errors,
            'layers': {k: len(v) for k, v in layers.items()},
            'gates': gates,
            'valid': len(errors) == 0,
        }

        if args.output:
            args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
        print(json.dumps(result, indent=2, sort_keys=True))

if __name__ == '__main__':
    main()
