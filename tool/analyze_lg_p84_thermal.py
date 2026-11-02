#!/usr/bin/env python3
"""Analyze opt-in MKS-THERMAL call counters without editing raw evidence.

Counters measure internal pipeline calls, never actual displayed frames. Rates
are derived only within one PID/kind/instance/start_ns identity. The initial
warm-up and intervals containing a resize/reset/counter rollback are excluded.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import re
import sys

COUNTERS = (
    'queue_frames', 'queue_resets', 'draw', 'redraw', 'display_synced',
    'submit', 'flip', 'lease_copy', 'lease_reuse', 'latch',
    'final_pass', 'swap', 'swap_ok',
)
KINDS = ('import', 'vo', 'yuv')
KEY_VALUE = re.compile(r'(\w+)=([^\s]+)')


def parse_record(line):
    marker = 'MKS-THERMAL '
    if marker not in line:
        return None
    values = dict(KEY_VALUE.findall(line.split(marker, 1)[1]))
    try:
        if values['kind'] not in KINDS:
            return None
        result = {key: values[key] for key in ('kind', 'instance')}
        for key in ('pid', 'mono_ns', 'start_ns', 'final', 'w', 'h',
                    'frame_id', *COUNTERS):
            result[key] = int(values[key])
        pts = float(values['pts'])
        result['pts'] = pts if math.isfinite(pts) else None
        if result['mono_ns'] < result['start_ns']:
            return None
        return result
    except (KeyError, ValueError):
        return None


def identity(row):
    return tuple(row[key] for key in ('pid', 'kind', 'instance', 'start_ns'))


def stable_segments(rows, warmup_seconds, max_gap_seconds):
    """No interpolation across resets; intervals are bounded by real samples."""
    cutoff = rows[0]['start_ns'] + int(warmup_seconds * 1e9)
    segments, current, rejected = [], [], []
    previous = None
    previous_size = None
    for row in rows:
        size = row['w'], row['h']
        reason = None
        if previous is not None:
            dt = (row['mono_ns'] - previous['mono_ns']) / 1e9
            if dt <= 0:
                reason = 'non-increasing-time'
            elif dt > max_gap_seconds:
                reason = 'sampling-gap'
            elif any(row[key] < previous[key] for key in COUNTERS):
                reason = 'counter-rollback'
            elif (row['queue_resets'] != previous['queue_resets'] and
                  row['mono_ns'] >= cutoff):
                reason = 'queue-reset'
            elif (previous_size is not None and size != previous_size and
                  min(size) > 0):
                reason = 'size-change'
        if reason:
            if len(current) >= 2:
                segments.append(current)
            current = []
            rejected.append({'mono_ns': row['mono_ns'], 'reason': reason})
            cutoff = row['mono_ns'] + int(warmup_seconds * 1e9)
        if min(size) > 0:
            previous_size = size
        if row['mono_ns'] >= cutoff and min(size) > 0:
            current.append(row)
        previous = row
    if len(current) >= 2:
        segments.append(current)
    return segments, rejected


def window_stats(rows):
    first, last = rows[0], rows[-1]
    seconds = (last['mono_ns'] - first['mono_ns']) / 1e9
    delta = {key: last[key] - first[key] for key in COUNTERS}
    return {
        'startMonoNs': first['mono_ns'], 'endMonoNs': last['mono_ns'],
        'seconds': seconds, 'samples': len(rows),
        'firstPts': first['pts'], 'lastPts': last['pts'],
        'width': last['w'], 'height': last['h'],
        'delta': delta,
        'perSecond': {key: value / seconds for key, value in delta.items()},
    }


def span(rows):
    return rows[-1]['mono_ns'] - rows[0]['mono_ns']


def analyze_run(path, warmup_seconds=20, max_gap_seconds=25,
                min_window_seconds=10):
    path = Path(path)
    logfile = path if path.is_file() else path / 'thermal-logcat.txt'
    content = logfile.read_text(errors='replace')
    grouped, unique = defaultdict(list), {}
    duplicates, malformed = 0, 0
    for line in content.splitlines():
        row = parse_record(line)
        if row is None:
            malformed += 'MKS-THERMAL ' in line
            continue
        key = identity(row), row['mono_ns']
        if key in unique:
            if unique[key] != row:
                raise ValueError(f'Conflicting counter record: {key}')
            duplicates += 1
            continue
        unique[key] = row
        grouped[identity(row)].append(row)

    report = {
        'directory': str(logfile.parent.resolve()),
        'logSha256': hashlib.sha256(logfile.read_bytes()).hexdigest(),
        'duplicateRecordsRemoved': duplicates, 'malformedRecords': malformed,
        'groups': [], 'cohorts': [], 'warnings': [],
    }
    if not grouped:
        report['warnings'].append('No complete MKS-THERMAL records.')
        return report
    choices = defaultdict(lambda: defaultdict(list))
    for key, rows in sorted(grouped.items()):
        rows.sort(key=lambda row: row['mono_ns'])
        segments, rejected = stable_segments(rows, warmup_seconds,
                                              max_gap_seconds)
        pid, kind, instance, start = key
        group = {
            'pid': pid, 'kind': kind, 'instance': instance, 'startNs': start,
            'records': len(rows), 'ended': any(row['final'] for row in rows),
            'excludedTransitions': rejected,
            'stableWindows': [window_stats(segment) for segment in segments],
        }
        report['groups'].append(group)
        for segment in segments:
            choices[pid][kind].append((key, segment))

    for pid, kinds in sorted(choices.items()):
        missing = [kind for kind in KINDS if not kinds[kind]]
        if missing:
            report['warnings'].append(f'PID {pid}: no stable {missing} window.')
            continue
        # Retain identities rather than summing across re-created contexts.
        selected = {kind: max(kinds[kind], key=lambda item: span(item[1]))
                    for kind in KINDS}
        lower = max(item[1][0]['mono_ns'] for item in selected.values())
        upper = min(item[1][-1]['mono_ns'] for item in selected.values())
        windows, issue = {}, None
        for kind, (key, rows) in selected.items():
            bounded = [row for row in rows if lower <= row['mono_ns'] <= upper]
            if (len(bounded) < 2 or
                    span(bounded) / 1e9 < min_window_seconds):
                issue = 'Insufficient common stable sample window.'
                break
            windows[kind] = {'identity': list(key), **window_stats(bounded)}
        cohort = {'pid': pid, 'requestedCommonStartNs': lower,
                  'requestedCommonEndNs': upper, 'valid': issue is None,
                  'reason': issue, 'windows': windows}
        if issue is None:
            max_start = max(window['startMonoNs'] for window in windows.values())
            min_start = min(window['startMonoNs'] for window in windows.values())
            max_end = max(window['endMonoNs'] for window in windows.values())
            min_end = min(window['endMonoNs'] for window in windows.values())
            cohort['endpointSkewSeconds'] = {
                'start': (max_start - min_start) / 1e9,
                'end': (max_end - min_end) / 1e9,
            }
            rate = {kind: window['perSecond'] for kind, window in windows.items()}
            source_rate = rate['import']['lease_copy']
            queue_rate = rate['vo']['queue_frames']
            cohort['ratios'] = {
                'finalPassPerLeaseCopy': rate['yuv']['final_pass'] / source_rate
                if source_rate else None,
                'drawPerQueuedFrame': rate['vo']['draw'] / queue_rate
                if queue_rate else None,
                'swapPerLeaseCopy': rate['yuv']['swap'] / source_rate
                if source_rate else None,
            }
        report['cohorts'].append(cohort)

    summary = logfile.parent / 'summary.json'
    if summary.is_file():
        data = json.loads(summary.read_text())
        report['roundStatus'] = {key: data.get(key) for key in (
            'status', 'reason', 'completeWindow', 'durationSeconds', 'mode')}
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runs', type=Path, nargs='+', help='Round directory or log file')
    parser.add_argument('--warmup-seconds', type=float, default=20)
    parser.add_argument('--max-gap-seconds', type=float, default=25)
    parser.add_argument('--min-window-seconds', type=float, default=10)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args(argv)
    if (args.warmup_seconds < 0 or args.max_gap_seconds <= 0 or
            args.min_window_seconds <= 0):
        parser.error('Warmup must be nonnegative; gap and window must be positive.')
    data = {
        'schemaVersion': 1,
        'semantics': 'Internal pipeline call counts; not actual display frame rate or thermal improvement proof.',
        'warmupSeconds': args.warmup_seconds,
        'maxGapSeconds': args.max_gap_seconds,
        'minWindowSeconds': args.min_window_seconds,
        'runs': [analyze_run(path, args.warmup_seconds, args.max_gap_seconds,
                             args.min_window_seconds) for path in args.runs],
    }
    encoded = json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
    if args.output:
        for run in args.runs:
            raw = run if run.is_file() else run / 'thermal-logcat.txt'
            if args.output.resolve() == raw.resolve():
                parser.error('Output cannot overwrite a raw input log.')
        args.output.write_text(encoded)
    else:
        sys.stdout.write(encoded)


if __name__ == '__main__':
    main()
