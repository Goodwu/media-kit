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
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from analyze_lg_p84_frame_gpu import parse_log_file, classify_tickets, compute_s0_median_ms

WINDOW_MIN_PTS = 5.0
TARGET_LEASE = '2672x1336'
SOURCE_LEASE = '3840x1920'


def round_stats(round_dir: Path) -> dict:
    log = round_dir / 'fgpu-device.log'
    records = parse_log_file(log)
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

    freqs = []
    for line in (round_dir / 'samples.ndjson').read_text().splitlines():
        d = json.loads(line)
        hz = (d.get('raw') or {}).get('gpu_hz')
        try:
            hz = float(hz)
        except (TypeError, ValueError):
            continue
        if hz > 0:
            freqs.append(hz)
    freqs.sort()
    med_hz = freqs[len(freqs) // 2] if freqs else None

    c_lease = [rec.get('lease', '') for rec in records['C']]
    c_win = [rec for rec in records['C']
             if _pts_of(rec) >= WINDOW_MIN_PTS]
    tgt = sum(1 for rec in c_win if rec.get('lease') == TARGET_LEASE)
    src = sum(1 for rec in c_win if rec.get('lease') == SOURCE_LEASE)

    return {
        's0_total': len(s0),
        'window_frames': n,
        'median_elapsed_ms': med_ns / 1e6 if med_ns is not None else None,
        'median_gpu_hz': med_hz,
        'mcycles_median': (med_ns * med_hz / 1e9 / 1e6) if (med_ns and med_hz) else None,
        'g10_target_fraction': tgt / len(c_win) if c_win else None,
        'g10_source_fraction': src / len(c_win) if c_win else None,
        'freq_method': 'window-median (design-declared fallback; no per-frame anchor in T lines)',
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
        out['pairs'][label] = {'A': a_dir, 'B': b_dir, 'reduction': pair_reduction(sa, sb)}
    print(json.dumps(out, indent=1, sort_keys=True))


if __name__ == '__main__':
    main()
