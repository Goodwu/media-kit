#!/usr/bin/env python3
"""G-9 pair reduction for S6 same-sync rounds (fgpu-device.log channel).

Primary metric per design (frame-gpu-timing-design-20261108:449): S0 per-frame
GPU Mcycles median, r = 1 - M_B/M_A. Per-frame frequency alignment needs a
per-frame monotonic anchor the current T lines do not carry, so the design's
declared fallback applies: window MEDIAN frequency x window median elapsed,
explicitly annotated. ms direction gate: ms median must not increase.

Deviation note: the design's pts 20-55 window assumes ~1x playback; at the
observed ~0.32x rate a 60s round reaches pts ~19, so the window is pts >= 5
(post-warmup), recorded here and in the round report.

G-10: B-side copy records >=99% target-size lease, A-side >=99% source-size.
"""
from __future__ import annotations
import base64
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from analyze_lg_p84_frame_gpu import parse_log_file, classify_tickets, compute_s0_median_ms, reconcile

WINDOW_MIN_PTS = 5.0
TARGET_LEASE = '2672x1336'
SOURCE_LEASE = '3840x1920'


def round_stats(round_dir: Path) -> dict:
    # Fail-closed entry (P1-4): the round must be completed-observation with
    # restoration verified and the device log actually pulled, and its ledger
    # must pass the full reconcile before any statistic is computed.
    summary = json.loads((round_dir / 'summary.json').read_text())
    gate_fail = []
    if summary.get('status') != 'completed-observation':
        gate_fail.append(f"status={summary.get('status')}")
    if not summary.get('restorationVerified'):
        gate_fail.append('restoration-unverified')
    if not summary.get('fgpuFilePulled'):
        gate_fail.append('fgpu-file-not-pulled')
    log = round_dir / 'fgpu-device.log'
    records = parse_log_file(log)
    errors = reconcile(records)
    if gate_fail or errors:
        return {'valid': False,
                'reason': gate_fail + errors}
    layers = classify_tickets(records)
    s0 = set(layers['S0'])

    segs = {}
    for rec in records['G']:
        t = int(rec.get('t', -1))
        if t in s0:
            e = rec.get('elapsed', '0')
            try:
                segs.setdefault(t, []).append(int(e))
            except ValueError:
                pass
    t_pts = {}
    for rec in records['T']:
        t = int(rec.get('t', -1))
        if t in s0:
            try:
                t_pts[t] = float(rec.get('pts', 'nan'))
            except ValueError:
                pass
    win = {t: v for t, v in segs.items() if t_pts.get(t, -1) >= WINDOW_MIN_PTS}
    elapsed_ns = sorted(sum(v) for v in win.values())
    n = len(elapsed_ns)
    med_ns = elapsed_ns[n // 2] if n % 2 else (elapsed_ns[n // 2 - 1] + elapsed_ns[n // 2]) / 2 if n else None

    # Frequency window (R2-P1-3): anchor to the probe's own pts>=5 samples
    # (assembled from thermal-logcat THERMAL_JSON[_PART]) so the frequency
    # window matches the elapsed window; fall back to the summary snapshot
    # range only if no probe sample carries a usable time-pos. Median rule
    # identical to elapsed (two-middle average for even counts).
    from datetime import datetime
    def _t(s):
        return datetime.fromisoformat(s)
    probe_ts = []
    tlog = round_dir / 'thermal-logcat.txt'
    if tlog.exists():
        groups = {}
        for l in tlog.read_text(errors='ignore').splitlines():
            if 'THERMAL_JSON_PART' not in l:
                continue
            try:
                tail = l.split('THERMAL_JSON_PART', 1)[1]
                p = json.loads(tail[tail.index('{'):])
                groups.setdefault((p['r'], p['n']), []).append(p)
            except (ValueError, KeyError):
                continue
        for parts in groups.values():
            if len(parts) != max(p['c'] for p in parts):
                continue
            parts = sorted(parts, key=lambda p: p['i'])
            try:
                row = json.loads(base64.b64decode(
                    ''.join(p['d'] for p in parts), validate=True))
            except Exception:
                continue
            tp = (row.get('properties') or {}).get('time-pos')
            try:
                if float(tp) >= WINDOW_MIN_PTS:
                    probe_ts.append(_t(row['wallTime']))
            except (KeyError, TypeError, ValueError):
                continue
    if probe_ts:
        f0, f1 = min(probe_ts), max(probe_ts)
        anchor_note = f'probe pts>=5 window ({len(probe_ts)} samples)'
    else:
        f0, f1 = _t(summary['initial']['hostTime']), _t(summary['final']['hostTime'])
        anchor_note = 'fallback: summary snapshot range'
    freqs = []
    for line in (round_dir / 'samples.ndjson').read_text().splitlines():
        d = json.loads(line)
        try:
            ts = _t(d['hostTime'])
        except (KeyError, ValueError):
            continue
        if not (f0 <= ts <= f1):
            continue
        hz = (d.get('raw') or {}).get('gpu_hz')
        try:
            hz = float(hz)
        except (TypeError, ValueError):
            continue
        if hz > 0:
            freqs.append(hz)
    freqs.sort()
    if freqs:
        med_hz = (freqs[(len(freqs) - 1) // 2] + freqs[len(freqs) // 2]) / 2
    else:
        med_hz = None

    c_lease = [rec.get('lease', '') for rec in records['C']]
    c_win = [rec for rec in records['C']
             if _pts_of(rec) >= WINDOW_MIN_PTS]
    tgt = sum(1 for rec in c_win if rec.get('lease') == TARGET_LEASE)
    src = sum(1 for rec in c_win if rec.get('lease') == SOURCE_LEASE)

    return {
        'valid': True,
        's0_total': len(s0),
        'window_frames': n,
        'median_elapsed_ms': med_ns / 1e6 if med_ns is not None else None,
        'median_gpu_hz': med_hz,
        'mcycles_median': (med_ns * med_hz / 1e9 / 1e6) if (med_ns and med_hz) else None,
        'g10_target_fraction': tgt / len(c_win) if c_win else None,
        'g10_source_fraction': src / len(c_win) if c_win else None,
        'freq_samples': len(freqs),
        'freq_method': f'round-window-median ({anchor_note}; design-declared fallback, no per-frame anchor in T lines)',
        'freq_window': {'from': f0.isoformat(), 'to': f1.isoformat(),
                        'source': 'probe-pts>=5' if probe_ts else 'summary-snapshot-fallback'},
    }


def _pts_of(rec):
    try:
        return float(rec.get('pts', 'nan'))
    except ValueError:
        return -1.0


def pair_reduction(a: dict, b: dict) -> dict:
    def r(ma, mb):
        if ma is None or mb is None or ma <= 0:
            return None
        return 1.0 - mb / ma
    r_cyc = r(a['mcycles_median'], b['mcycles_median'])
    r_ms = r(a['median_elapsed_ms'], b['median_elapsed_ms'])
    ms_direction_ok = (r_ms is not None and r_ms > 0)
    g10_ok = (a['g10_source_fraction'] is not None and a['g10_source_fraction'] >= 0.99
              and b['g10_target_fraction'] is not None and b['g10_target_fraction'] >= 0.99)
    # Pre-declared clean-pair rule (TASKS.md 2026-11-10 ruling, registered
    # before any supplementary round ran): both rounds pinned at the 214MHz
    # low corner (window median <= 220MHz), G-10 valid, ms direction positive.
    freq_ok = (a['median_gpu_hz'] is not None and a['median_gpu_hz'] <= 220e6 and
               b['median_gpu_hz'] is not None and b['median_gpu_hz'] <= 220e6)
    clean = bool(freq_ok and g10_ok and ms_direction_ok)
    return {
        'r_mcycles': r_cyc,
        'r_ms': r_ms,
        'ms_direction_ok': ms_direction_ok,
        'g10_ok': g10_ok,
        'freq_ok': freq_ok,
        'clean': clean,
        # Primary metric per ruling: ms. A clean pair passes at r_ms >= 10%.
        'gate_pass': bool(clean and r_ms is not None and r_ms >= 0.10),
    }


def main():
    base = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')
    # A/B identity follows the LEASE (A=source-size, B=target-size), not the
    # run order (P2 ran B first; identity unchanged).
    pairs = [('P1', 'P1A', 'P1B'), ('P2', 'P2A', 'P2B'), ('P3', 'P3A', 'P3B'),
             ('P4', 'P4A', 'P4B'), ('P5', 'P5A', 'P5B')]
    out = {'rounds': {}, 'pairs': {}, 'notes': [
        'window pts>=5 (design pts20-55 unreachable at 0.32x playback; deviation recorded)',
        'Mcycles uses design-declared window-median-frequency fallback (no per-frame anchor)',
        'APK lgp84-s5h, same sync (display-resample), only lease switches (G-9 same-sync protocol)',
    ]}
    for label, a_dir, b_dir in pairs:
        da, db = base / f'S6-G9ss-{a_dir}', base / f'S6-G9ss-{b_dir}'
        if not (da / 'fgpu-device.log').exists() or not (db / 'fgpu-device.log').exists():
            continue
        sa, sb = round_stats(da), round_stats(db)
        out['rounds'][a_dir], out['rounds'][b_dir] = sa, sb
        if not (sa.get('valid') and sb.get('valid')):
            out['pairs'][label] = {'A': a_dir, 'B': b_dir,
                                   'excluded': 'round failed fail-closed gates',
                                   'A_valid': sa.get('valid'), 'B_valid': sb.get('valid')}
            continue
        out['pairs'][label] = {'A': a_dir, 'B': b_dir, 'reduction': pair_reduction(sa, sb)}
    print(json.dumps(out, indent=1, sort_keys=True))


if __name__ == '__main__':
    main()
