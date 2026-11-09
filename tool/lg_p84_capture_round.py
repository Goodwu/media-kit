#!/usr/bin/env python3
"""Collect one default-off LG GPU float diagnostic transaction, then analyze.

Never installs/builds an APK. ROI is producer-fixed central min(64,w/h).
--repeat explicitly selects schema2 B1/A1/B2/A2; A1 half/YUV are not captured.
--sample-tap additionally selects schema3 instrumented UV/RGB capture; it
requires --repeat and archives the original body as a sixth UTF-8 file.
--invariant-b requires both options, selects schema4, and archives B vertex as
a seventh file. A0 versus an earlier control remains an independent review.
--oracle-triplet collects schema5 original/oracle/original with one framework,
identical sources and explicit 0/1/0 runtime selection. It validates evidence,
not production equivalence, panel output, or a hardware/compiler root cause.
--oracle-probe selects schema6 and preserves dedicated diagnostic-invalid
artifacts as failure evidence. Invalid diagnostics never advance a triplet.
--single-pair selects schema7 A1/B1 with one barrier and no within-capture
repeatability measurement; each triplet round still starts a fresh process.
--quad-mode/--quad-triplet select schema8 B-only full vertex record order,
keeping original UV selection and requiring archived A/B submission bytes.
The process displays ordinary A during this diagnostic. Log receive order is
correlation only, not a native/hardware synchronized timestamp. Captured shader
floats cannot prove raw YUV, scanout, panel equality, or performance benefit.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import shlex
import signal
import subprocess
import struct
import time
from typing import Any

import analyze_lg_yuv_capture as analyzer
import lg_p84_quality_round as quality

thermal = quality.thermal
REMOTE = f'/sdcard/Android/data/{thermal.PACKAGE}/files/'
COMPARE_PROPERTIES = ('debug.mks.yuv_compare', 'debug.mks.yuv_compare_pts')
REPEAT_PROPERTY = 'debug.mks.yuv_compare_repeat'
TAP_PROPERTY = 'debug.mks.yuv_tap'
INVARIANT_PROPERTY = 'debug.mks.yuv_inv'
ORACLE_PROPERTY = 'debug.mks.yuv_oracle'
ORACLE_MODE_PROPERTY = 'debug.mks.yuv_oracle_a'
PROBE_PROPERTY = 'debug.mks.yuv_probe'
SINGLE_PROPERTY = 'debug.mks.yuv_single'
QUAD_PROPERTY = 'debug.mks.yuv_quad'
QUAD_REVERSE_PROPERTY = 'debug.mks.yuv_rev'
ATLAS_PROPERTY = 'debug.mks.yuv_atlas'
ATLAS_REUSE_PROPERTY = 'debug.mks.atlas_reuse'
ATLAS_PTS2_PROPERTY = 'debug.mks.atlas_pts2'
ATLAS_NONCE_PROPERTY = 'debug.mks.atlas_nonce'
ATLAS_ACK_PROPERTY = 'debug.mks.atlas_ack'
COMPARE_PROPERTIES += (REPEAT_PROPERTY, TAP_PROPERTY, INVARIANT_PROPERTY, ORACLE_PROPERTY, ORACLE_MODE_PROPERTY, PROBE_PROPERTY, SINGLE_PROPERTY, QUAD_PROPERTY, QUAD_REVERSE_PROPERTY, ATLAS_PROPERTY,
                       'debug.mks.yuv_fusion_table',
                       ATLAS_REUSE_PROPERTY, ATLAS_PTS2_PROPERTY, ATLAS_NONCE_PROPERTY, ATLAS_ACK_PROPERTY)
SUFFIXES = {'lib': '.lib.bin', 'android': '.android.bin',
            'candidate': '.candidate.glsl', 'baseline': '.baseline.glsl', 'vertex': '.vertex.glsl'}


class CaptureAdb(quality.QualityAdb):
    def properties(self):
        return {**super().properties(), **{k: self.call(['shell', 'getprop', k]).strip()
                                         for k in COMPARE_PROPERTIES}}

    def read_file(self, remote: str, maximum: int, timeout: float = 15) -> bytes:
        # No remote globbing; every path is obtained from a strictly checked
        # identity basename (or the verified installed APK path).
        quoted = shlex.quote(remote)
        size = self.shell(f'test -f {quoted} && test ! -L {quoted} && stat -c %s {quoted}').strip()
        if not re.fullmatch(r'[1-9]\d*', size) or int(size) > maximum:
            raise RuntimeError('remote-file-size-or-type-invalid:' + remote)
        started = thermal.now()
        result = subprocess.run(self.prefix + ['exec-out', 'cat', remote], capture_output=True, timeout=timeout)
        with self.receipts.open('a') as out:
            out.write(json.dumps({'time': started, 'argv': self.prefix + ['exec-out', 'cat', remote],
                                  'returncode': result.returncode, 'bytes': len(result.stdout),
                                  'stderr': result.stderr.decode(errors='replace')[:2000]}) + '\n')
        if result.returncode or len(result.stdout) != int(size):
            raise RuntimeError('remote-file-incomplete:' + remote)
        return result.stdout

    def source_hash(self, remote):
        data = self.read_file(remote, 256 * 1024 * 1024, timeout=45)
        return {'path': remote, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def positive(value: str) -> bool:
    return isinstance(value, str) and re.fullmatch(r'[1-9]\d*', value) is not None


def exact_pts(value, target) -> bool:
    return type(value) in (float, int) and math.isfinite(value) and abs(value - target) <= 2e-6


class NativeCaptureFailure(RuntimeError):
    def __init__(self, prefix, fields, diagnostics):
        super().__init__('native-' + ('lib-' if prefix.endswith('-LIB') else '') + fields['event'])
        self.fields = fields
        self.diagnostics = diagnostics


class DiagnosticCaptureEvent(RuntimeError):
    """Dedicated failure endpoint, never a capture-complete return value."""
    def __init__(self, event, diagnostics):
        super().__init__('native-capture-diagnostic-invalid')
        self.event, self.diagnostics = event, diagnostics


def compare_rows(lines, pid):
    rows = []
    for index, line in enumerate(lines):
        header = re.match(r'\S+\s+\S+\s+(\d+)\s+\d+\s+', line)
        if not header or header[1] != pid:
            continue
        # The LIB producer has its own namespace. Never parse its events as VO
        # transaction markers merely because their prefixes share characters.
        marker = re.search(r'(?<![\w-])(MKS-YUV-COMPARE(?:-LIB)?)\s+', line)
        if not marker:
            continue
        pairs = re.findall(r'([A-Za-z_][\w-]*)=([^\s]+)', line[marker.end():])
        fields = dict(pairs)
        if len(fields) != len(pairs) or 'event' not in fields:
            raise RuntimeError('malformed-compare-event-fields')
        rows.append((index, marker[1], fields))
    return rows


def completion(lines: list[str], pid: str, seek_index: int, target: float, repeat: bool = False,
               sample_tap: bool = False, invariant_b: bool = False, oracle_mode: int | None = None,
               uv_probe: bool = False, single_pair: bool = False, quad_reverse: int | None = None):
    """Require this fresh process's single armed -> complete transaction."""
    rows = compare_rows(lines, pid)
    diagnostics = [{'logIndex': i, 'prefix': p, **f} for i, p, f in rows]
    # A complete log snapshot can contain diagnostic lines before the terminal
    # failure. Report that failure first, preserving all diagnostic fields.
    for _, prefix, fields in rows:
        if prefix == 'MKS-YUV-COMPARE' and fields['event'] in (
                'capture-failed', 'config-invalid', 'fatal-cleanup-deferred', 'cleanup-deferred',
                'egl-owner-rejected'):
            raise NativeCaptureFailure(prefix, fields, diagnostics)
    for _, prefix, fields in rows:
        if prefix == 'MKS-YUV-COMPARE-LIB' and fields['event'] in (
                'arm-rejected', 'caps-rejected', 'ssbo-binding-rejected', 'sample-tap-rejected', 'invariant-b-rejected',
                'uv-oracle-rejected'):
            raise NativeCaptureFailure(prefix, fields, diagnostics)
    events = []
    for index, prefix, fields in rows:
        if prefix == 'MKS-YUV-COMPARE-LIB':
            if fields['event'] not in ('arm-format', 'arm-owner', 'arm-limits', 'arm-storage', 'caps-ready',
                                      'readback-counts', 'readback-first-invalid'):
                raise RuntimeError('unknown-lib-compare-event')
            continue
        if fields['event'] == 'egl-owner-configured':
            # Initialization runs before any seek and has no capture id. It is
            # informational only; never append it to the transaction markers.
            continue
        if fields['event'] in ('arm-input', 'arm-input-gl'):
            if not positive(fields.get('id')):
                raise RuntimeError('malformed-compare-diagnostic-identity')
            continue
        if fields.get('event') not in ('armed', 'capture-complete', 'capture-diagnostic-invalid'):
            raise RuntimeError('unknown-compare-event')
        if index <= seek_index:
            raise RuntimeError('compare-event-before-current-seek-marker')
        if not positive(fields.get('id')) or not positive(fields.get('generation')):
            raise RuntimeError('malformed-compare-identity')
        try:
            pts = float(fields.get('source_pts', 'nan'))
        except ValueError:
            pts = float('nan')
        if not exact_pts(pts, target):
            raise RuntimeError('compare-event-source-PTS-mismatch')
        events.append(fields)
    arms = [e for e in events if e['event'] == 'armed']
    ends = [e for e in events if e['event'] in ('capture-complete', 'capture-diagnostic-invalid')]
    if len(arms) > 1 or len(ends) > 1:
        raise RuntimeError('multiple-capture-transactions')
    if arms and (arms[0].get('android') != '1' or arms[0].get('lib') != '1'):
        raise RuntimeError('capture-arm-failed')
    if not ends:
        return None
    end = ends[0]
    if not arms or events != [arms[0], end] or any(end[k] != arms[0][k] for k in ('id', 'generation', 'source_pts')):
        raise RuntimeError('capture-complete-without-matching-arm')
    diagnostic = end['event'] == 'capture-diagnostic-invalid'
    expected = REMOTE + f'mks-yuv-compare-{pid}-{end["id"]}' + ('.diagnostic-invalid' if diagnostic else '') + '.json'
    if end.get('file') != expected or end.get('comparison_pass') != ('refused' if diagnostic else 'unknown'):
        raise RuntimeError('capture-complete-path-or-scope-mismatch')
    if end.get('repetitions') not in (('1',) if single_pair else ('2',) if repeat else (None, '1')):
        raise RuntimeError('capture-complete-repetitions-mismatch')
    if sample_tap and not repeat:
        raise RuntimeError('sample-tap-requires-repeat')
    if end.get('sample_tap') not in (('1',) if sample_tap else (None, '0')):
        raise RuntimeError('capture-complete-sample-tap-mismatch')
    if invariant_b and not (repeat and sample_tap):
        raise RuntimeError('invariant-b-requires-repeat-and-sample-tap')
    if end.get('invariant_b') not in (('1',) if invariant_b else (None, '0')):
        raise RuntimeError('capture-complete-invariant-b-mismatch')
    capture_schema(repeat, sample_tap, invariant_b, oracle_mode, uv_probe, single_pair, quad_reverse)
    if (end.get('uv_oracle') not in (('1',) if oracle_mode is not None else (None, '0')) or
            end.get('uv_oracle_use_a') not in ((str(oracle_mode),) if oracle_mode is not None else (None, '0'))):
        raise RuntimeError('capture-complete-oracle-mode-mismatch')
    if end.get('uv_oracle_probe') not in (('1',) if uv_probe else (None, '0')):
        raise RuntimeError('capture-oracle-probe-mode-mismatch')
    if end.get('uv_oracle_single_pair') not in (('1',) if single_pair else (None, '0')):
        raise RuntimeError('capture-single-pair-mode-mismatch')
    if (end.get('quad_order') not in (('1',) if quad_reverse is not None else (None, '0')) or
            end.get('quad_order_reverse') not in ((str(quad_reverse),) if quad_reverse is not None else (None, '0'))):
        raise RuntimeError('capture-quad-order-mode-mismatch')
    if diagnostic:
        if not uv_probe:
            raise RuntimeError('diagnostic-invalid-requires-explicit-schema6-probe')
        raise DiagnosticCaptureEvent(end, diagnostics)
    return end


def capture_schema(repeat=False, sample_tap=False, invariant_b=False, oracle_mode=None, uv_probe=False, single_pair=False,
                   quad_reverse=None):
    if quad_reverse is not None:
        if type(quad_reverse) is not int or quad_reverse not in (0,1):
            raise RuntimeError('quad-reverse-must-be-explicit-0-or-1')
        if not (repeat and sample_tap and uv_probe and single_pair) or invariant_b or type(oracle_mode) is not int or oracle_mode != 0:
            raise RuntimeError('quad-order-requires-single-probe-repeat-tap-original-UV-excludes-invariant')
        return 8
    if single_pair and not uv_probe:
        raise RuntimeError('single-pair-requires-oracle-probe')
    if uv_probe and oracle_mode is None:
        raise RuntimeError('oracle-probe-requires-explicit-oracle-mode')
    if oracle_mode is not None:
        if type(oracle_mode) is not int or oracle_mode not in (0, 1):
            raise RuntimeError('oracle-mode-must-be-explicit-0-or-1')
        if not repeat or not sample_tap or invariant_b:
            raise RuntimeError('oracle-requires-repeat-and-sample-tap-excludes-invariant')
        return 7 if single_pair else 6 if uv_probe else 5
    return 4 if invariant_b else 3 if sample_tap else 2 if repeat else 1


def validate_manifest(m, event, pid, target, repeat: bool = False, sample_tap: bool = False,
                      invariant_b: bool = False, oracle_mode: int | None = None, uv_probe: bool = False,
                      single_pair: bool = False, quad_reverse: int | None = None):
    diagnostic = event.get('event') == 'capture-diagnostic-invalid'
    if invariant_b and not (repeat and sample_tap):
        raise RuntimeError('invariant-b-requires-repeat-and-sample-tap')
    if sample_tap and not repeat:
        raise RuntimeError('sample-tap-requires-repeat')
    if (not isinstance(m, dict) or type(m.get('schema')) is not int or
            m['schema'] != capture_schema(repeat, sample_tap, invariant_b, oracle_mode, uv_probe, single_pair, quad_reverse) or
            m.get('status') != ('diagnostic-invalid' if diagnostic else 'complete')):
        raise RuntimeError('manifest-schema-or-completion-mismatch')
    if diagnostic and not uv_probe:
        raise RuntimeError('diagnostic-invalid-requires-explicit-schema6-probe')
    if single_pair:
        analyzer.single_pair_metadata(m)
    elif repeat:
        analyzer.repeat_metadata(m)
    if sample_tap:
        analyzer.sample_tap_metadata(m)
    if invariant_b:
        analyzer.invariant_metadata(m)
    if oracle_mode is not None:
        analyzer.oracle_metadata(m)
        if m.get('uv_oracle_use_a') is not bool(oracle_mode):
            raise RuntimeError('manifest-oracle-uniform-mode-mismatch')
    if uv_probe:
        analyzer.oracle_probe_metadata(m)
    if quad_reverse is not None:
        analyzer.quad_order_metadata(m)
        if m.get('quad_order_reverse') is not bool(quad_reverse):
            raise RuntimeError('manifest-quad-order-selection-mismatch')
    for key, expected in [('pid', int(pid)), ('capture_id', int(event['id'])), ('generation', int(event['generation']))]:
        if type(m.get(key)) is not int or m[key] != expected:
            raise RuntimeError('manifest-identity-mismatch:' + key)
    for key in ('source_pts', 'current_pts', 'target_pts'):
        if not exact_pts(m.get(key), target):
            raise RuntimeError('manifest-PTS-mismatch:' + key)
    if m.get('scope') != 'capture-only-not-comparison-pass':
        raise RuntimeError('manifest-scope-mismatch')
    for key in ('frame_id', 'frame_token', 'target_width', 'target_height'):
        if type(m.get(key)) is not int or m[key] <= 0:
            raise RuntimeError('manifest-invalid:' + key)
    w, h = min(64, m['target_width']), min(64, m['target_height'])
    expected_roi = {'x': (m['target_width']-w)//2, 'y': (m['target_height']-h)//2, 'w': w, 'h': h}
    if m.get('roi') != expected_roi or any(type(v) is not int for v in m['roi'].values()):
        raise RuntimeError('manifest-ROI-not-producer-fixed-center')
    repetitions = 1 if single_pair else 2 if repeat else 1
    for key, expected in (('lib_words', w*h*(26 if sample_tap else 14)*repetitions), ('android_words', w*h*7)):
        if type(m.get(key)) is not int or m[key] != expected:
            raise RuntimeError('manifest-word-count-mismatch:' + key)
    prefix = f'mks-yuv-compare-{pid}-{event["id"]}'
    if diagnostic:
        prefix += '.diagnostic-invalid'
    suffixes = {**SUFFIXES, **({'original_body': '.original-body.glsl'} if sample_tap else {})}
    if invariant_b:
        suffixes['candidate_vertex'] = '.candidate-vertex.glsl'
    if uv_probe:
        if m.get('uv_oracle_probe_words') != w*h*10*repetitions:
            raise RuntimeError('manifest-word-count-mismatch:oracle-probe')
        suffixes['oracle_probe'] = '.oracle-probe.bin'
    if quad_reverse is not None:
        suffixes.update(baseline_vertices='.baseline-vertices.bin',candidate_vertices='.candidate-vertices.bin')
    files = {key: prefix + suffix for key, suffix in suffixes.items()}
    if m.get('files') != files:
        raise RuntimeError('manifest-file-identity-mismatch')
    return files


def collect(adb, event, pid, target, directory, guard, repeat: bool = False, sample_tap: bool = False,
            invariant_b: bool = False, oracle_mode: int | None = None, uv_probe: bool = False,
            single_pair: bool = False, quad_reverse: int | None = None):
    directory.mkdir(exist_ok=False)
    raw = adb.read_file(event['file'], 16 * 1024)
    manifest_path = directory / Path(event['file']).name
    manifest_path.write_bytes(raw)
    m = analyzer.load_json(manifest_path)
    files = validate_manifest(m, event, pid, target, repeat, sample_tap, invariant_b, oracle_mode, uv_probe, single_pair, quad_reverse)
    pixels = m['roi']['w'] * m['roi']['h']
    receipts = {}
    repetitions = 1 if single_pair else 2 if repeat else 1
    for key, name in files.items():
        guard()
        maximum = (pixels * (10*repetitions if key == 'oracle_probe' else (26 if sample_tap else 14)*repetitions if key == 'lib' else 7) * 4
                   if key in ('lib', 'android', 'oracle_probe') else 256 * 1024 if key == 'original_body' else 4 * 1024 * 1024)
        if key in ('baseline_vertices','candidate_vertices'):
            maximum=m['quad_vertex_layout']['byte_size']
            if type(maximum) is not int or not 1<=maximum<=4096:
                raise RuntimeError('quad-vertex-payload-size-out-of-bound')
        data = adb.read_file(REMOTE + name, maximum)
        if key in ('lib', 'android', 'oracle_probe','baseline_vertices','candidate_vertices') and len(data) != maximum:
            raise RuntimeError('payload-byte-size-mismatch:' + key)
        (directory / name).write_bytes(data)
        receipts[key] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    # Producer uses O_EXCL + fsync and writes manifest last. Check immutability
    # again rather than pretending raw words contain their own frame identity.
    for key, name in files.items():
        guard()
        data = adb.read_file(REMOTE + name, receipts[key]['bytes'])
        if len(data) != receipts[key]['bytes'] or hashlib.sha256(data).hexdigest() != receipts[key]['sha256']:
            raise RuntimeError('remote-file-changed-during-collection:' + key)
    if adb.read_file(event['file'], 16 * 1024) != raw:
        raise RuntimeError('manifest-changed-during-collection')
    guard()
    thermal.write_json(directory / 'collection.json', {'files': receipts, 'manifestSha256': hashlib.sha256(raw).hexdigest(),
        'identityScope': 'Fresh-process endpoint event and exclusive identity filenames bind payload/shaders; raw words have no embedded PID/PTS. Local SHA archives bytes; no producer SHA claim.',
        'timestampScope': 'Log receive order is correlation only; not hardware or native-clock synchronization.'})
    try:
        analysis = analyzer.analyze(manifest_path)
    except analyzer.InvalidCapture as error:
        rejected = {'schema': m['schema'], 'status': 'invalid-capture', 'reason': str(error), 'causal_conclusion_allowed': False}
        if getattr(error, 'diagnostic', None) is not None:
            rejected['diagnostic'] = error.diagnostic
        thermal.write_json(directory / 'analysis.json', rejected)
        raise
    thermal.write_json(directory / 'analysis.json', analysis)
    if event.get('event') == 'capture-diagnostic-invalid':
        if analysis['status'] != 'diagnostic-invalid' or analysis.get('causal_conclusion_allowed') is not False:
            raise RuntimeError('analyzer-diagnostic-endpoint-status-mismatch')
        if analysis.get('numeric_status') not in ('captured-floats-bit-equal', 'captured-float-differences'):
            raise RuntimeError('diagnostic-output-hard-finite-gate-failed')
        return analysis
    if analysis['status'] not in ('captured-floats-bit-equal', 'captured-float-differences'):
        raise RuntimeError('analyzer-invalid:' + analysis['status'])
    return analysis


def controls(target, repeat: bool = False, sample_tap: bool = False, invariant_b: bool = False,
             oracle_mode: int | None = None, st_fbo: str | None = None, uv_probe: bool = False,
             single_pair: bool = False, quad_reverse: int | None = None,
             lease_target: bool = False):
    capture_schema(repeat, sample_tap, invariant_b, oracle_mode, uv_probe, single_pair, quad_reverse)
    if invariant_b and not (repeat and sample_tap):
        raise RuntimeError('invariant-b-requires-repeat-and-sample-tap')
    if sample_tap and not repeat:
        raise RuntimeError('sample-tap-requires-repeat')
    if st_fbo not in (None, '0', '1'):
        raise RuntimeError('input-fbo-must-be-explicit-0-or-1')
    return {'debug.mks.thermal_sync': 'display-resample', 'debug.mks.thermal_trace': '1',
            'debug.mks.defer_publish_flush': '0', 'debug.mks.gpu_timing': '0',
            'debug.mks.yuv_fusion': '1', 'debug.mks.yuv_fail_commit': '0', 'debug.mks.yuv_fail_gl': '0',
            'debug.mks.yuv_frame_trace': '1', 'debug.mks.quality_pts': str(target),
            'debug.mks.yuv_compare': '1', 'debug.mks.yuv_compare_pts': str(target),
            REPEAT_PROPERTY: '1' if repeat else '0', TAP_PROPERTY: '1' if sample_tap else '0',
            INVARIANT_PROPERTY: '1' if invariant_b else '0', ORACLE_PROPERTY: '1' if oracle_mode is not None else '0',
            ORACLE_MODE_PROPERTY: str(oracle_mode) if oracle_mode is not None else '0',
            thermal.INPUT_FBO_PROPERTY: st_fbo or '0', PROBE_PROPERTY: '1' if uv_probe else '0',
            SINGLE_PROPERTY: '1' if single_pair else '0',QUAD_PROPERTY:'1' if quad_reverse is not None else '0',
            QUAD_REVERSE_PROPERTY:str(quad_reverse) if quad_reverse is not None else '0', ATLAS_PROPERTY:'0',
            ATLAS_REUSE_PROPERTY:'0',ATLAS_PTS2_PROPERTY:'',ATLAS_NONCE_PROPERTY:'',ATLAS_ACK_PROPERTY:'',
            'debug.mks.st_lease_target': '1' if lease_target else '0'}


def current_seek_index(lines, pid, target):
    starts = [(i, row) for i, row in quality.quality_rows(lines, pid) if row.get('status') == 'seek-started']
    if not starts:
        return None
    if len(starts) != 1:
        raise RuntimeError('multiple-quality-seeks-in-single-round')
    index, row = starts[0]
    if (row.get('ordinal') != 1 or row.get('requestedPTS') != target or row.get('requestedFusionMode') != '1' or
            not isinstance(row.get('runId'), str) or not row['runId'].startswith(pid+':')):
        raise RuntimeError('quality-seek-identity-mismatch')
    return index


def run(args):
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    adb = CaptureAdb(args.serial, output)
    repeat = bool(getattr(args, 'repeat', False))
    sample_tap = bool(getattr(args, 'sample_tap', False))
    invariant_b = bool(getattr(args, 'invariant_b', False))
    oracle_mode = getattr(args, 'oracle_mode', None)
    st_fbo = getattr(args, 'st_fbo', None)
    uv_probe = bool(getattr(args, 'oracle_probe', False))
    single_pair = bool(getattr(args, 'single_pair', False))
    quad_reverse = getattr(args,'quad_reverse',None)
    result = {'schema': 1, 'status': 'failed', 'serial': args.serial, 'startedAt': thermal.now(),
              'requestedPTS': args.pts, 'framesRequested': 1,
              'repeatRequested': repeat, 'sampleTapRequested': sample_tap,
              'invariantBRequested': invariant_b,
              'oracleMode': oracle_mode,
              'oracleProbeRequested': uv_probe,
              'singlePairRequested': single_pair,
              'quadReverse':quad_reverse,'quadOrderRequested':quad_reverse is not None,
              'requestedInputFbo': st_fbo,
              'displayControls': {'brightness': args.brightness, 'expectedBacklight': args.expected_backlight,
                                  'expectedPanelThermalStatus': args.expected_panel_thermal_status},
              'expectedCaptureSchema': 8 if quad_reverse is not None else 7 if single_pair else 6 if uv_probe else 5 if oracle_mode is not None else 4 if invariant_b else 3 if sample_tap else 2 if repeat else 1,
              'scope': 'GPU shader floats only; not raw YUV, panel, or performance acceptance'}
    settings, props, screen = {}, {}, {}
    capture = None
    touched = launched = False
    try:
        settings, props, screen = adb.settings(), adb.properties(), adb.screen_state()
        thermal.write_json(output / 'original-state.json', {'settings': settings, 'properties': props, 'screen': screen})
        result['initial'] = adb.snapshot()
        quality.thermal_gate(result['initial'], {}, args.expected_panel_thermal_status)
        receipt = json.loads(Path(args.source_receipt).read_text())
        size = quality.validate_source_receipt(receipt, args.serial, args.source)
        if adb.shell('stat -c %s ' + shlex.quote(args.source)).strip() != str(size):
            raise RuntimeError('source-current-size-mismatch')
        result.update(sourceReceipt=receipt, sourceIdentityScope='Historical full-byte SHA receipt plus current size; not a fresh source hash.')
        package = adb.call(['shell', 'pm', 'path', thermal.PACKAGE]).strip()
        if not re.fullmatch(r'package:/data/app/[^\s]+/base\.apk', package):
            raise RuntimeError('unexpected-APK-path-or-splits')
        result['apk'] = adb.source_hash(package[len('package:'):])
        if result['apk']['sha256'] != args.expected_apk_sha256.lower():
            raise RuntimeError('installed-APK-hash-mismatch')
        quality.thermal_gate(adb.snapshot(), {}, args.expected_panel_thermal_status)
        touched = True
        adb.wake_unprotected(screen, args.allow_unprotected_menu)
        for key, value in [('screen_brightness_mode', 0), ('screen_brightness', args.brightness),
                           ('accelerometer_rotation', 0), ('user_rotation', 1),
                           ('screen_off_timeout', int((args.timeout+120)*1000))]:
            adb.call(['shell', 'settings', 'put', 'system', key, str(value)])
        result['controls'] = controls(args.pts, repeat, sample_tap, invariant_b, oracle_mode, st_fbo, uv_probe, single_pair, quad_reverse,
                                      bool(getattr(args, 'lease_target', False)))
        for key, value in result['controls'].items():
            # An empty value must survive the device shell; adb.call with ''
            # drops the argument and setprop fails with "Need 2 arguments".
            adb.shell(f'setprop {shlex.quote(key)} {shlex.quote(value)}')
        for key, name in ((REPEAT_PROPERTY, 'repeat'), (TAP_PROPERTY, 'sample-tap'), (INVARIANT_PROPERTY, 'invariant-b'),
                          (ORACLE_PROPERTY, 'oracle-framework'), (ORACLE_MODE_PROPERTY, 'oracle-mode'), (PROBE_PROPERTY, 'oracle-probe'),
                          (SINGLE_PROPERTY,'single-pair'),(QUAD_PROPERTY,'quad-order'),(QUAD_REVERSE_PROPERTY,'quad-reverse'),
                          (ATLAS_PROPERTY,'atlas-disabled'),(ATLAS_REUSE_PROPERTY,'atlas-reuse-disabled'),
                          (ATLAS_PTS2_PROPERTY,'atlas-pts2-disabled'),(ATLAS_NONCE_PROPERTY,'atlas-nonce-disabled'),
                          (ATLAS_ACK_PROPERTY,'atlas-ack-disabled')):
            if adb.call(['shell', 'getprop', key]).strip() != result['controls'][key]:
                raise RuntimeError(name + '-control-readback-mismatch')
        if adb.call(['shell', 'getprop', thermal.INPUT_FBO_PROPERTY]).strip() != result['controls'][thermal.INPUT_FBO_PROPERTY]:
            raise RuntimeError('input-fbo-control-readback-mismatch')
        old_pid = adb.lab_pid()
        adb.call(['shell', 'am', 'force-stop', thermal.PACKAGE])
        if adb.lab_pid() is not None:
            raise RuntimeError('old-process-survived-force-stop')
        capture = thermal.LogCapture(adb, output)
        capture.start()
        launched = True
        result['launchOutput'] = adb.call(['shell', 'am', 'start', '-n', thermal.ACTIVITY])
        pid = adb.lab_pid()
        if not pid or pid == old_pid:
            raise RuntimeError('fresh-process-PID-not-established')
        result['pid'] = pid
        capture.set_expected_pid(pid)
        deadline = time.monotonic() + args.timeout
        def guard(brightness=True):
            if time.monotonic() >= deadline:
                raise RuntimeError('capture-round-timeout')
            if adb.lab_pid() != pid:
                raise RuntimeError('capture-process-restarted-or-exited')
            state = capture.state()
            if state.get('logcatAlive') is not True:
                raise RuntimeError('capture-logcat-exited')
            if st_fbo is not None:
                fbo_error = thermal.input_fbo_error(state, st_fbo, strict=False)
                if fbo_error:
                    raise RuntimeError(fbo_error)
            sample = adb.snapshot()
            quality.thermal_gate(sample, state, args.expected_panel_thermal_status,
                                 args.expected_backlight if brightness else None)
            with (output / 'samples.ndjson').open('a') as out:
                out.write(json.dumps(sample) + '\n')
            if time.monotonic() >= deadline:
                raise RuntimeError('capture-round-read-exceeded-deadline')
        if args.tap:
            # Keep thermal monitoring active while waiting for the fullscreen tap.
            until = time.monotonic() + args.tap_delay
            while time.monotonic() < until:
                guard(False)
                time.sleep(min(.2, max(0, until-time.monotonic())))
            adb.call(['shell', 'input', 'tap', str(args.tap[0]), str(args.tap[1])])
        logfile = output / 'flutter-logcat.txt'
        while True:
            guard(False)
            lines = logfile.read_text().splitlines() if logfile.exists() else []
            seek_index = current_seek_index(lines, pid, args.pts)
            try:
                event = completion(lines, pid, seek_index if seek_index is not None else -1, args.pts,
                                   repeat, sample_tap, invariant_b, oracle_mode, uv_probe, single_pair, quad_reverse)
            except DiagnosticCaptureEvent as diagnostic:
                if seek_index is None:
                    raise RuntimeError('diagnostic-endpoint-without-current-seek')
                result['diagnosticEvent'] = diagnostic.event
                result['nativeDiagnostics'] = diagnostic.diagnostics
                result['causal_conclusion_allowed'] = False
                result['diagnosticDirectory'] = str(output/'diagnostic-invalid')
                # This is failure evidence collection. Do not require historical
                # helper-ready or turn it into displayed-frame/pause acceptance.
                # Process/logcat/thermal/deadline guards remain active for every
                # bounded transfer and all native/manifest identities stay strict.
                result['analysis'] = collect(adb, diagnostic.event, pid, args.pts, output/'diagnostic-invalid', guard,
                                             repeat, sample_tap, invariant_b, oracle_mode, uv_probe, single_pair, quad_reverse)
                result.update(status='diagnostic-invalid', reason='native-capture-diagnostic-invalid',
                              diagnosticFilesCollected=True)
                break
            pair = quality.observation_pair(lines, pid, args.pts, '1')
            heartbeats = [] if pair is None else [r for _, r in quality.quality_rows(lines, pid)
                if r.get('runId') == pair[2]['runId'] and r.get('ordinal') == 1 and r.get('status') == 'observation-heartbeat']
            if pair and event and heartbeats:
                disk = REMOTE + f'p84-quality-{pid}.ndjson'
                def load_heartbeat():
                    guard()
                    text = adb.call(['exec-out', 'cat', disk])
                    (output / 'persistent-quality-latest.ndjson').write_text(text)
                    row = quality.validate_persistent([json.loads(l) for l in text.splitlines() if l.strip()],
                                                     pair[2], pid, args.source, args.pts, '1')
                    guard()
                    return row
                # ready alone does not prove paused current state; monitor must
                # keep progressing before and after pulling the complete files.
                before = load_heartbeat()
                result['qualityBefore'] = quality.fresh_heartbeat(load_heartbeat, before['heartbeat'])
                result['captureEvent'] = event
                result['analysis'] = collect(adb, event, pid, args.pts, output / 'capture', guard, repeat, sample_tap, invariant_b, oracle_mode, uv_probe, single_pair, quad_reverse)
                watermark, after = quality.post_screenshot_heartbeat(load_heartbeat)
                result.update(postCollectionHeartbeatWatermark=watermark, qualityAfter=after)
                final_lines = logfile.read_text().splitlines()
                final_pair = quality.observation_pair(final_lines, pid, args.pts, '1')
                if not final_pair or final_pair[2]['runId'] != pair[2]['runId'] or completion(final_lines, pid, pair[0], args.pts, repeat, sample_tap, invariant_b, oracle_mode, uv_probe, single_pair, quad_reverse) != event:
                    raise RuntimeError('capture-evidence-changed-during-collection')
                guard()
                if st_fbo is not None:
                    fbo_state = capture.state()
                    result['inputFbo'] = fbo_state.get('inputFbo')
                    fbo_error = thermal.input_fbo_error(fbo_state, st_fbo)
                    if fbo_error:
                        raise RuntimeError(fbo_error)
                    # Current native reports only startup/each 300 copies and
                    # carry no frame PTS. A prior hit cannot certify the later
                    # paused target copy; preserve collected files but fail.
                    raise RuntimeError('input-fbo-target-frame-proof-unavailable-native-report-has-no-PTS')
                result['status'] = 'completed-capture'
                break
            time.sleep(.5)
    except KeyboardInterrupt:
        result['reason'] = 'interrupted'
    except Exception as error:
        result['reason'] = str(error)
        if isinstance(error, NativeCaptureFailure):
            result['nativeFailure'] = error.fields
            result['nativeDiagnostics'] = error.diagnostics
        if isinstance(error, analyzer.InvalidCapture) and getattr(error, 'diagnostic', None) is not None:
            result['analyzerDiagnostic'] = error.diagnostic
    finally:
        # Preserve the capture result before stop/restore can replace status.
        result['captureStatusBeforeCleanup'] = result['status']
        handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGINT, signal.SIGTERM)}
        if launched:
            try:
                adb.call(['shell', 'am', 'force-stop', thermal.PACKAGE])
                result['hdrLabStopped'] = True
            except Exception as error:
                result.update(status='stop-failed', stopError=str(error))
        if capture:
            try:
                capture.close()
            except Exception as error:
                result.update(status='capture-close-failed', captureCloseError=str(error))
        errors = adb.restore(settings, props) if touched else []
        if touched and screen:
            try:
                adb.call(['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP' if screen.get('on') else 'KEYCODE_SLEEP'])
                if adb.screen_state()['on'] != screen.get('on'):
                    errors.append('screen-state-not-restored')
            except Exception as error:
                errors.append(str(error))
        try:
            after_settings, after_props = adb.settings(), adb.properties()
            result['restored'] = {'settings': after_settings, 'properties': after_props}
            ok, auto = thermal.restoration_matches(settings, after_settings, props, after_props, errors)
            result.update(restorationVerified=ok, automaticBrightnessScalarChanged=auto)
            if not ok:
                result['status'] = 'restoration-failed'
        except Exception as error:
            result.update(status='restoration-failed', restorationError=str(error))
        result.update(restoreErrors=errors, finishedAt=thermal.now())
        if result.get('diagnosticDirectory'):
            result['diagnosticFilesCollected'] = (Path(result['diagnosticDirectory'])/'collection.json').is_file()
        thermal.write_json(output / 'summary.json', result)
        for sig, handler in handlers.items():
            signal.signal(sig, handler)
    return result


def validate_oracle_triplet(rounds):
    return _validate_triplet(rounds,False)


def validate_quad_triplet(rounds):
    return _validate_triplet(rounds,True)


def _validate_triplet(rounds,quad):
    """Pure, strict three-round byte/provenance gate; B effects stay measured."""
    if len(rounds) != 3:
        raise RuntimeError('oracle-triplet-requires-three-complete-rounds')
    manifests, analyses, payloads = [], [], []
    pids, ids = set(), set()
    for index, (directory, result) in enumerate(rounds):
        mode = 0 if quad else (0, 1, 0)[index]
        quad_reverse = (0,1,0)[index] if quad else None
        uv_probe = bool(result.get('oracleProbeRequested', False))
        single_pair = bool(result.get('singlePairRequested', False))
        if (result.get('status') != 'completed-capture' or result.get('restorationVerified') is not True or
                result.get('oracleMode') != mode or result.get('expectedCaptureSchema') != (8 if quad else 7 if single_pair else 6 if uv_probe else 5) or
                result.get('quadOrderRequested',False) is not quad or result.get('quadReverse') != quad_reverse):
            raise RuntimeError('oracle-triplet-incomplete-mode-or-restore:' + str(index+1))
        event = result['captureEvent']
        manifest_path = directory/'capture'/Path(event['file']).name
        m = analyzer.load_json(manifest_path)
        validate_manifest(m, event, str(result['pid']), result['requestedPTS'], True, True, False, mode, uv_probe, single_pair,quad_reverse)
        if (event.get('uv_oracle') != '1' or event.get('uv_oracle_use_a') != str(mode) or
                str(m['pid']) != str(result['pid'])):
            raise RuntimeError('oracle-triplet-event-mode-or-PID-mismatch')
        if quad and (type(result.get('quadReverse')) is not int or event.get('quad_order')!='1' or
                     event.get('quad_order_reverse')!=str(quad_reverse)):
            raise RuntimeError('quad-triplet-event-order-mismatch')
        if str(result['pid']) in pids or m['capture_id'] in ids:
            raise RuntimeError('oracle-triplet-reused-process-or-capture-id')
        pids.add(str(result['pid']));ids.add(m['capture_id'])
        apk = result.get('apk', {})
        if (not re.fullmatch(r'[0-9a-f]{64}', apk.get('sha256', '')) or
                type(apk.get('bytes')) is not int or apk['bytes'] <= 0):
            raise RuntimeError('oracle-triplet-APK-provenance-missing')
        quality.validate_source_receipt(result['sourceReceipt'], result['serial'], result['sourceReceipt']['deviceSource'])
        analysis = analyzer.analyze(manifest_path)
        if analysis['status'] not in ('captured-floats-bit-equal', 'captured-float-differences'):
            raise RuntimeError('oracle-triplet-invalid-numeric-capture')
        manifests.append(m);analyses.append(analysis)
        payloads.append({key: (manifest_path.parent/name).read_bytes() for key, name in m['files'].items()})
        if any(hashlib.sha256(data).hexdigest() != analysis['files'][key]['sha256'] for key, data in payloads[-1].items()):
            raise RuntimeError('oracle-triplet-local-file-changed-during-verification')
        if result['controls'] != controls(result['requestedPTS'], True, True, False, mode, result.get('requestedInputFbo'), uv_probe, single_pair,quad_reverse):
            raise RuntimeError('oracle-triplet-unexpected-control-properties')
    baseline = rounds[0][1]
    for index in (1, 2):
        other = rounds[index][1]
        if (other['serial'] != baseline['serial'] or other['requestedPTS'] != baseline['requestedPTS'] or
                other.get('oracleProbeRequested', False) != baseline.get('oracleProbeRequested', False) or
                other.get('singlePairRequested', False) != baseline.get('singlePairRequested', False) or
                other.get('displayControls') != baseline.get('displayControls') or
                any(other['apk'][k] != baseline['apk'][k] for k in ('sha256', 'bytes')) or
                any(other['sourceReceipt'][k] != baseline['sourceReceipt'][k] for k in
                    ('serial', 'deviceSource', 'deviceSha256', 'deviceBytes', 'hostSha256', 'hostBytes'))):
            raise RuntimeError('oracle-triplet-device-APK-media-or-target-drift')
        if any(manifests[index][k] != manifests[0][k] for k in
               ('source_pts', 'current_pts', 'target_pts', 'roi', 'target_width', 'target_height')):
            raise RuntimeError('oracle-triplet-PTS-ROI-or-extent-drift')
        varying_property=QUAD_REVERSE_PROPERTY if quad else ORACLE_MODE_PROPERTY
        before_controls = {k: v for k, v in baseline['controls'].items() if k != varying_property}
        after_controls = {k: v for k, v in other['controls'].items() if k != varying_property}
        if before_controls != after_controls or other['controls'].get(varying_property) != str((0,1,0)[index]):
            raise RuntimeError('oracle-triplet-more-than-runtime-mode-changed')
        if any(payloads[index][key] != payloads[0][key] for key in ('candidate', 'baseline', 'vertex', 'original_body')):
            raise RuntimeError('oracle-triplet-actual-source-bytes-differ')
        if quad:
            if manifests[index]['quad_vertex_layout'] != manifests[0]['quad_vertex_layout']:
                raise RuntimeError('quad-triplet-vertex-layout-drift')
            if payloads[index]['baseline_vertices'] != payloads[0]['baseline_vertices']:
                raise RuntimeError('quad-triplet-A-vertex-payload-drift')
    original_payload_keys = ('lib', 'android', 'oracle_probe') if baseline.get('oracleProbeRequested') else ('lib', 'android')
    if quad:
        original_payload_keys += ('baseline_vertices','candidate_vertices')
    if any(payloads[2][key] != payloads[0][key] for key in original_payload_keys):
        raise RuntimeError('oracle-triplet-original-controls-not-bit-stable')
    if payloads[1]['android'] != payloads[0]['android']:
        raise RuntimeError('oracle-triplet-A1-CSC-anchor-drift' if baseline.get('singlePairRequested') else 'oracle-triplet-A2-CSC-anchor-drift')
    original, oracle = (struct.unpack('<' + str(len(payloads[i]['lib'])//4) + 'I', payloads[i]['lib']) for i in (0,1))
    # Schema7 has one chunk/final A1; other oracle modes have two chunks/final
    # A2. Anchor every captured A count/preRGB/UV/sampleRGB/site-count word.
    a_offsets = (*range(10,14), *range(20,26))
    if any(original[base+offset] != oracle[base+offset]
           for base in range(0, len(original), 26) for offset in a_offsets):
        raise RuntimeError('oracle-triplet-A-sample-or-preRGB-anchor-drift')
    if quad:
        stride=manifests[0]['quad_vertex_layout']['stride']
        original_vertices=payloads[0]['baseline_vertices']
        reversed_vertices=b''.join(original_vertices[i*stride:(i+1)*stride] for i in (3,2,1,0))
        if payloads[1]['candidate_vertices']!=reversed_vertices or payloads[0]['candidate_vertices']!=original_vertices:
            raise RuntimeError('quad-triplet-B-payload-is-not-exact-record-reversal')
    return {'status': 'validated-quad-triplet-evidence' if quad else 'validated-triplet-evidence', 'modes': [0,1,0],
        'controlledVariable':'B complete vertex record order' if quad else 'B UV runtime selection',
        'checks': {'sameActualSources': True, 'originalRawBytesRepeat': True, 'allCapturedABytesStable': True,
                   'sameAPKMediaReceiptPTSROI': True, 'freshProcessesAndCaptures': True},
        'captureStatuses': [a['status'] for a in analyses],
        'programInstanceScope': 'Each round uses a fresh process. Archived B shader source equality does not mean the same GL program instance.',
        'withinCaptureRepeatability': 'not measured: one A/B pair' if baseline.get('singlePairRequested') else 'see each capture repeat analysis',
        'quadVertexRequirement':'A submitted bytes stay fixed; original B equals A, reverse B is exactly four complete stride records reversed.' if quad else None,
        'oracleUVRequirement': 'use_a remains 0; B uses its original varying UV. UV changes remain measured differences.' if quad else 'Oracle-mode B UV words equal the corresponding captured A UV words; independently checked by the single-capture analyzer.',
        'scope': 'One diagnostic triplet with fixed archived shader source bytes. Media identity uses the historical full-byte SHA receipt plus current per-round file size, not a fresh whole-media hash. B RGB/pre/YUV remain measured differences, not accepted equivalence. Producer barriers/uniform assertions are not independent hardware synchronization proof; no panel or compiler root cause claim.'}


def run_oracle_triplet(args):
    return _run_triplet(args,False)


def run_quad_triplet(args):
    return _run_triplet(args,True)


def _run_triplet(args,quad):
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    result = {'schema': 1, 'status': 'failed', 'startedAt': thermal.now(), 'rounds': [],
              'scope': 'Diagnostic original/reverse/original evidence, not production or panel acceptance' if quad
                       else 'Diagnostic original/oracle/original evidence, not production or panel acceptance'}
    rounds = []
    active_round = False
    try:
        if not args.repeat or not args.sample_tap or getattr(args, 'invariant_b', False):
            raise RuntimeError('oracle-triplet-requires-repeat-and-sample-tap-excludes-invariant')
        if quad and (not getattr(args,'oracle_probe',False) or not getattr(args,'single_pair',False) or getattr(args,'oracle_mode',None)!=0):
            raise RuntimeError('quad-triplet-requires-single-probe-and-original-UV')
        for index, mode in enumerate((0, 1, 0), 1):
            child = copy.copy(args)
            child.oracle_mode = 0 if quad else mode
            if quad:child.quad_reverse=mode
            child.output = str(output/f'{index:02d}-{"reverse" if quad and mode else "oracle" if mode else "original"}')
            active_round = True
            one = run(child)  # This function owns stop+restore on every exit.
            active_round = False
            rounds.append((Path(child.output), one))
            result['rounds'].append({'directory': child.output, 'mode': mode, 'status': one['status'],
                                     'reason': one.get('reason'), 'restorationVerified': one.get('restorationVerified')})
            if one['status'] != 'completed-capture' or one.get('restorationVerified') is not True:
                raise RuntimeError(f'{"quad" if quad else "oracle"}-triplet-round-{index}-incomplete:' + str(one.get('reason')))
        result['verification'] = validate_quad_triplet(rounds) if quad else validate_oracle_triplet(rounds)
        result['restorationVerified'] = True
        result['status'] = 'completed-quad-triplet' if quad else 'completed-oracle-triplet'
    except KeyboardInterrupt:
        result['reason'] = 'interrupted'
    except Exception as error:
        result['reason'] = str(error)
    finally:
        result['restorationVerified'] = not active_round and bool(rounds) and all(one.get('restorationVerified') is True for _, one in rounds)
        result['finishedAt'] = thermal.now()
        thermal.write_json(output/'summary.json', result)
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--pts', type=float, choices=quality.POINTS, required=True)
    p.add_argument('--repeat', action='store_true', help='Opt in to schema2 B1/A1/B2/A2; A1 half/YUV are not captured.')
    p.add_argument('--sample-tap', action='store_true', help='Requires --repeat; schema3 captures instrumented sample site UV/RGB and original body.')
    p.add_argument('--invariant-b', action='store_true', help='Requires --repeat --sample-tap; schema4 archives separate B and A0 vertex sources.')
    p.add_argument('--oracle-mode', choices=('original', 'oracle'), help='Schema5 same framework, explicit B runtime UV choice; requires repeat+sample-tap and excludes invariant.')
    p.add_argument('--oracle-triplet', action='store_true', help='Schema5/6/7 according to explicit probe/single options: original/oracle/original in three fresh processes with strict source/raw/provenance checks.')
    p.add_argument('--oracle-probe', action='store_true', help='Schema6 (schema7 with --single-pair) GPU dependency sidecar; requires oracle mode/triplet. diagnostic-invalid artifacts are archived but always fail and stop subsequent rounds.')
    p.add_argument('--single-pair', action='store_true', help='Schema7: requires oracle-probe, oracle, repeat and sample-tap; execute one A1/B1 pair with no within-capture repeat measurement.')
    p.add_argument('--quad-mode',choices=('original','reverse'),help='Schema8 B-only submitted vertex order; requires single/probe/repeat/tap and --oracle-mode original.')
    p.add_argument('--quad-triplet',action='store_true',help='Schema8 original/reverse/original in fresh processes, with actual source/A vertex/raw and whole-record B reversal checks.')
    p.add_argument('--st-fbo', choices=('0','1'), help='Explicit diagnostic mapper path. Current reports lack target PTS, so requested fixed-frame FBO capture remains invalid.')
    p.add_argument('--lease-target', action='store_true', help='target-size lease for this capture (debug.mks.st_lease_target=1); recorded in controls and restored after the round')
    p.add_argument('--source', default=REMOTE + 'hokkaido-p84.mp4')
    p.add_argument('--source-receipt', required=True)
    p.add_argument('--expected-apk-sha256', required=True)
    p.add_argument('--brightness', type=int, default=64)
    p.add_argument('--expected-backlight', type=int, default=64)
    p.add_argument('--expected-panel-thermal-status', required=True)
    p.add_argument('--timeout', type=float, default=60)
    p.add_argument('--tap', type=int, nargs=2, default=[1440, 720])
    p.add_argument('--tap-delay', type=float, default=4)
    p.add_argument('--allow-unprotected-menu', action='store_true')
    args = p.parse_args()
    if args.sample_tap and not args.repeat:
        p.error('--sample-tap requires --repeat')
    if args.invariant_b and not (args.repeat and args.sample_tap):
        p.error('--invariant-b requires --repeat --sample-tap')
    if (args.oracle_mode or args.oracle_triplet) and (not args.repeat or not args.sample_tap or args.invariant_b):
        p.error('oracle requires --repeat --sample-tap and excludes --invariant-b')
    if args.oracle_mode and args.oracle_triplet:
        p.error('--oracle-mode and --oracle-triplet are mutually exclusive')
    if args.oracle_probe and not (args.oracle_mode or args.oracle_triplet):
        p.error('--oracle-probe requires --oracle-mode or --oracle-triplet')
    if args.single_pair and not args.oracle_probe:
        p.error('--single-pair requires --oracle-probe')
    if args.quad_mode and args.quad_triplet:
        p.error('--quad-mode and --quad-triplet are mutually exclusive')
    if (args.quad_mode or args.quad_triplet) and (not args.single_pair or not args.oracle_probe or
            not args.repeat or not args.sample_tap or args.invariant_b or args.oracle_mode!='original' or args.oracle_triplet):
        p.error('quad order requires single/probe/repeat/tap and --oracle-mode original; excludes invariant/oracle-triplet')
    args.quad_reverse={'original':0,'reverse':1}.get(args.quad_mode)
    args.oracle_mode = {'original': 0, 'oracle': 1}.get(args.oracle_mode)
    if not re.fullmatch(r'[0-9a-fA-F]{64}', args.expected_apk_sha256):
        p.error('expected APK SHA256 must be 64 hex characters')
    if (not 1 <= args.brightness <= 255 or not 1 <= args.expected_backlight <= 255 or
            not 15 <= args.timeout <= 180 or not 0 <= args.tap_delay <= 15):
        p.error('brightness 1..255, timeout 15..180, tap delay 0..15 only')
    def terminate(signum, frame):
        raise KeyboardInterrupt(f'termination-signal-{signum}')
    signal.signal(signal.SIGTERM, terminate)
    result = run_quad_triplet(args) if args.quad_triplet else run_oracle_triplet(args) if args.oracle_triplet else run(args)
    print(json.dumps({k: result.get(k) for k in ('status', 'reason', 'restorationVerified', 'captureEvent', 'verification')}))
    # Differences are valid acquisition results, but never yield success exit.
    equal = (result['analysis']['status'] == 'captured-floats-bit-equal' if 'analysis' in result else
             all(s == 'captured-floats-bit-equal' for s in result.get('verification', {}).get('captureStatuses', [])) and
             result['status'] in ('completed-oracle-triplet','completed-quad-triplet'))
    return 0 if result['status'] in ('completed-capture', 'completed-oracle-triplet','completed-quad-triplet') and result.get('restorationVerified') and equal else 2


if __name__ == '__main__':
    raise SystemExit(main())
