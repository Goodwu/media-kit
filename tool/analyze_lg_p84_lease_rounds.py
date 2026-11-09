#!/usr/bin/env python3
"""Compare same-branch schema3 capture words across target-lease rounds.

This is exploratory evidence only. A matching PTS and historical media receipt
are not a cross-process input-pixel identity proof, even with an A/B/A anchor.
No result from this tool is a quality, lifecycle, or panel acceptance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analyze_lg_yuv_capture as analyzer
import lg_p84_capture_round as capture


LEASE_PROPERTY = 'debug.mks.st_lease_target'
SHADER_KEYS = ('baseline', 'candidate', 'vertex', 'original_body')
MEDIA_KEYS = ('serial', 'deviceSource', 'deviceSha256', 'deviceBytes',
              'hostSha256', 'hostBytes')
LIMITATIONS = [
    'Exploratory only; never a quality, lifecycle, performance, or panel acceptance.',
    'Matching PTS and a historical media SHA receipt do not prove identical decoded input pixels across processes.',
    'An A/B/A output anchor cannot prove that the intervening B input pixels are identical.',
    'Captured floats cover only a centered ROI of instrumented shaders; not uninstrumented output, raw YUV, scanout, the panel, full-screen, or motion quality.',
    'Collection hashes are local archive-integrity receipts, not independently authenticated producer hashes.',
    'Shader sources may differ; differences are reported and prevent a simple numerical attribution to the lease alone.',
    'Float ULP distances are float32 ULPs, not binary16 ULPs.',
    'A/B/A anchor compares only A2/B2; A1/B1 and A1 half/YUV are not all represented in that anchor.',
    'Round order is supplied by the caller; capture chronology is not independently verified.',
]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify_round(directory: Path, expected: int, allow_restore_failure: bool = False):
    directory = directory.resolve()
    summary = analyzer.load_json(directory / 'summary.json')
    require(isinstance(summary, dict), 'summary-not-object')
    status = summary.get('status')
    restored = summary.get('restorationVerified') is True
    require(not any(key in summary for key in ('reason', 'stopError', 'captureCloseError',
                                               'restorationError', 'nativeFailure')) and
            summary.get('hdrLabStopped') is True, 'round-has-non-restoration-failure')
    prior = summary.get('captureStatusBeforeCleanup')
    require(prior in (None, 'completed-capture'), 'capture-did-not-complete-before-cleanup')
    if not (status == 'completed-capture' and restored):
        require(allow_restore_failure and status == 'restoration-failed' and
                summary.get('restorationVerified') is False and
                isinstance(summary.get('restoreErrors'), list) and bool(summary['restoreErrors']),
                'round-not-complete-and-restored')
        # Older summaries have no pre-cleanup status. Do not infer completion
        # from the overwritten final status without post-collection evidence.
        if prior is None:
            before, after = summary.get('qualityBefore'), summary.get('qualityAfter')
            mark = summary.get('postCollectionHeartbeatWatermark')
            require(isinstance(before, dict) and isinstance(after, dict) and
                    before.get('status') == after.get('status') == 'observation-heartbeat' and
                    type(mark) is int and type(before.get('heartbeat')) is int and
                    type(after.get('heartbeat')) is int and
                    before['heartbeat'] < mark < after['heartbeat'] and
                    before.get('runId') == after.get('runId') and bool(before.get('runId')) and
                    str(before.get('pid')) == str(summary.get('pid')) == str(after.get('pid')),
                    'legacy-round-missing-post-collection-evidence')
    require(summary.get('expectedCaptureSchema') == 3 and summary.get('repeatRequested') is True and
            summary.get('sampleTapRequested') is True and summary.get('invariantBRequested') is False and
            summary.get('oracleMode') is None and summary.get('oracleProbeRequested') is False and
            summary.get('singlePairRequested') is False and summary.get('quadOrderRequested') is False and
            summary.get('quadReverse') is None, 'round-not-schema3-repeat-sample-tap')
    pts = summary.get('requestedPTS')
    require(type(pts) in (int, float) and math.isfinite(pts) and pts >= 0, 'invalid-requested-PTS')
    serial = summary.get('serial')
    require(isinstance(serial, str) and bool(serial), 'invalid-serial')
    apk = summary.get('apk')
    require(isinstance(apk, dict) and isinstance(apk.get('sha256'), str) and
            re.fullmatch(r'[0-9a-f]{64}', apk['sha256']) is not None and
            type(apk.get('bytes')) is int and apk['bytes'] > 0, 'invalid-APK-receipt')
    media = summary.get('sourceReceipt')
    require(isinstance(media, dict) and isinstance(media.get('deviceSource'), str) and
            bool(media['deviceSource']), 'missing-media-receipt')
    capture.quality.validate_source_receipt(media, serial, media['deviceSource'])
    display = summary.get('displayControls')
    require(isinstance(display, dict) and set(display) ==
            {'brightness', 'expectedBacklight', 'expectedPanelThermalStatus'}, 'invalid-display-controls')
    expected_controls = capture.controls(pts, True, True, False, None,
                                        summary.get('requestedInputFbo'), lease_target=bool(expected))
    require(summary.get('controls') == expected_controls, 'unexpected-controls')
    pid = summary.get('pid')
    event = summary.get('captureEvent')
    require(isinstance(pid, str) and capture.positive(pid) and isinstance(event, dict) and
            event.get('event') == 'capture-complete' and capture.positive(event.get('id')) and
            capture.positive(event.get('generation')) and event.get('comparison_pass') == 'unknown' and
            event.get('repetitions') == '2' and event.get('sample_tap') == '1' and
            all(event.get(k) in (None, '0') for k in
                ('invariant_b', 'uv_oracle', 'uv_oracle_use_a', 'uv_oracle_probe',
                 'uv_oracle_single_pair', 'quad_order', 'quad_order_reverse')),
            'invalid-capture-event')
    try:
        event_pts = float(event.get('source_pts', 'nan'))
    except (TypeError, ValueError):
        event_pts = float('nan')
    require(capture.exact_pts(event_pts, pts), 'event-PTS-mismatch')
    basename = f'mks-yuv-compare-{pid}-{event["id"]}.json'
    require(event.get('file') == capture.REMOTE + basename, 'event-path-mismatch')
    root = directory / 'capture'
    manifest_path = analyzer.safe_file(root, basename)
    manifest = analyzer.load_json(manifest_path)
    files = capture.validate_manifest(manifest, event, pid, pts, True, True)
    receipt = analyzer.load_json(analyzer.safe_file(root, 'collection.json'))
    require(isinstance(receipt, dict) and isinstance(receipt.get('files'), dict) and
            set(receipt['files']) == set(files), 'invalid-collection-receipt')
    raw_manifest = manifest_path.read_bytes()
    require(hashlib.sha256(raw_manifest).hexdigest() == receipt.get('manifestSha256'),
            'manifest-collection-hash-mismatch')
    result = analyzer.analyze(manifest_path)
    require(result['status'] in ('captured-floats-bit-equal', 'captured-float-differences'),
            'invalid-numeric-capture')
    payloads = {}
    for key, name in files.items():
        data = analyzer.safe_file(root, name).read_bytes()
        info = receipt['files'].get(key)
        digest = hashlib.sha256(data).hexdigest()
        require(isinstance(info, dict) and type(info.get('bytes')) is int and
                info['bytes'] == len(data) and info.get('sha256') == digest and
                result['files'][key]['sha256'] == digest, 'collection-payload-mismatch:' + key)
        payloads[key] = data
    require(hashlib.sha256(manifest_path.read_bytes()).hexdigest() == receipt['manifestSha256'],
            'manifest-changed-during-verification')
    return {'directory': str(directory), 'summary': summary, 'manifest': manifest,
            'analysis': result, 'payloads': payloads, 'restored': restored}


def vectors(round_data):
    m = round_data['manifest']
    pixels = m['roi']['w'] * m['roi']['h']
    lib_bytes = round_data['payloads']['lib']
    android_bytes = round_data['payloads']['android']
    lib = struct.unpack('<' + str(len(lib_bytes)//4) + 'I', lib_bytes)
    android = struct.unpack('<' + str(len(android_bytes)//4) + 'I', android_bytes)
    base = pixels * 26  # second repetition: A2 and B2
    def vec(words, stride, offset, n=3, start=0):
        return [words[start + i*stride + offset + c] for i in range(pixels) for c in range(n)]
    return {
        'A2': {'pre_rgb': vec(lib, 26, 11, start=base),
               'half_rgb': vec(android, 7, 1), 'yuv': vec(android, 7, 4),
               'sample_uv': vec(lib, 26, 20, 2, base), 'sample_rgb': vec(lib, 26, 22, start=base)},
        'B2': {'pre_rgb': vec(lib, 26, 1, start=base),
               'half_rgb': vec(lib, 26, 4, start=base), 'yuv': vec(lib, 26, 7, start=base),
               'sample_uv': vec(lib, 26, 14, 2, base), 'sample_rgb': vec(lib, 26, 16, start=base)},
    }


def compare(left, right):
    roi = left['manifest']['roi']
    a, b = vectors(left), vectors(right)
    comparisons = {}
    for branch in ('A2', 'B2'):
        comparisons[branch] = {}
        for stage in ('pre_rgb', 'half_rgb', 'yuv', 'sample_uv', 'sample_rgb'):
            channels = ('Y', 'Cb', 'Cr') if stage == 'yuv' else ('U', 'V') if stage == 'sample_uv' else 'RGB'
            result = analyzer.compare_vectors(a[branch][stage], b[branch][stage], roi['w'],
                                              (roi['x'], roi['y']), channels)
            require(result['nonfinite_components'] == 0, 'cross-round-nonfinite:' + branch + ':' + stage)
            comparisons[branch][stage] = result
    return comparisons


def analyze_rounds(directories, allow_restore_failure=False):
    require(len(directories) in (2, 3), 'requires-off-on-or-off-on-off')
    paths = [Path(p).resolve() for p in directories]
    require(len(set(paths)) == len(paths), 'duplicate-round-directory')
    rounds = [verify_round(path, mode, allow_restore_failure)
              for path, mode in zip(paths, (0, 1, 0))]
    first = rounds[0]
    serial = first['summary']['serial']
    require(len({r['summary']['pid'] for r in rounds}) == len(rounds) and
            len({r['manifest']['capture_id'] for r in rounds}) == len(rounds), 'reused-process-or-capture-id')
    for other in rounds[1:]:
        a, b = first['summary'], other['summary']
        require(b['serial'] == serial and b['requestedPTS'] == a['requestedPTS'] and
                b['displayControls'] == a['displayControls'] and
                all(b['apk'][k] == a['apk'][k] for k in ('sha256', 'bytes')) and
                all(b['sourceReceipt'][k] == a['sourceReceipt'][k] for k in MEDIA_KEYS),
                'device-APK-media-PTS-or-display-drift')
        require(all(other['manifest'][k] == first['manifest'][k] for k in
                    ('source_pts', 'current_pts', 'target_pts', 'roi', 'target_width', 'target_height')),
                'capture-PTS-ROI-or-extent-drift')
        require({k: v for k, v in b['controls'].items() if k != LEASE_PROPERTY} ==
                {k: v for k, v in a['controls'].items() if k != LEASE_PROPERTY}, 'extra-control-drift')
    shader_hashes = [{k: r['analysis']['files'][k]['sha256'] for k in SHADER_KEYS} for r in rounds]
    cross = compare(rounds[0], rounds[1])
    anchor = compare(rounds[0], rounds[2]) if len(rounds) == 3 else None
    anchor_equal = (all(stage['bit_mismatches'] == 0 for branch in anchor.values()
                        for stage in branch.values()) if anchor is not None else None)
    return {'schema': 1, 'status': 'exploratory-cross-round-comparison',
            'acceptance': False, 'input_pixel_identity_proven': False,
            'lease_sequence': [0, 1] + ([0] if anchor is not None else []),
            'rounds': [{'directory': r['directory'], 'pid': r['summary']['pid'],
                        'capture_id': r['manifest']['capture_id'], 'status': r['summary']['status'],
                        'restorationVerified': r['restored'],
                        'restoreErrors': r['summary'].get('restoreErrors', []),
                        'captureStatusBeforeCleanup': r['summary'].get('captureStatusBeforeCleanup'),
                        'captureCompletionScope': ('explicit-pre-cleanup-status' if r['summary'].get('captureStatusBeforeCleanup')
                                                   else 'legacy-final-success-status' if r['restored']
                                                   else 'legacy-post-collection-evidence-not-explicit-status'),
                        'captureStatus': r['analysis']['status']} for r in rounds],
            'device': serial, 'requestedPTS': first['summary']['requestedPTS'],
            'roi': first['manifest']['roi'],
            'targetExtent': [first['manifest']['target_width'], first['manifest']['target_height']],
            'apk': {k: first['summary']['apk'][k] for k in ('sha256', 'bytes')},
            'mediaReceipt': {k: first['summary']['sourceReceipt'][k] for k in MEDIA_KEYS},
            'sourceIdentityScope': 'Historical full-byte receipt and producer-reported current size check; not a fresh source hash.',
            'shaderSha256': shader_hashes,
            'shaderSourcesIdentical': all(item == shader_hashes[0] for item in shader_hashes[1:]),
            'off_vs_on': cross,
            'off_vs_off_anchor': anchor,
            'off_anchor_A2_B2_stages_bit_equal': anchor_equal,
            'limitations': LIMITATIONS}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('off', type=Path, help='First target-lease-off round directory')
    parser.add_argument('on', type=Path, help='Target-lease-on round directory')
    parser.add_argument('--off-anchor', type=Path, help='Optional caller-supplied later off round; chronology is not verified')
    parser.add_argument('--include-restoration-failures', action='store_true',
                        help='Explicitly include capture-complete rounds whose system restoration failed; exploratory only')
    parser.add_argument('--output', type=Path, help='New output file; never overwrites')
    args = parser.parse_args()
    try:
        result = analyze_rounds([args.off, args.on] + ([args.off_anchor] if args.off_anchor else []),
                                args.include_restoration_failures)
        code = 0
    except (ValueError, RuntimeError, OSError, KeyError, TypeError) as error:
        result = {'schema': 1, 'status': 'invalid-or-incomparable', 'acceptance': False,
                  'reason': str(error), 'limitations': LIMITATIONS}
        code = 2
    rendered = json.dumps(result, indent=2, allow_nan=False) + '\n'
    if args.output:
        with args.output.open('x') as output:
            output.write(rendered)
    print(rendered, end='')
    return code


if __name__ == '__main__':
    sys.exit(main())
