#!/usr/bin/env python3
"""Collect one explicitly requested, default-off LG full-screen A0/atlas/A0 diagnostic.

Never installs/builds an APK or enables a production path. RGBA/FLOAT readback
is not physical half-storage bytes, raw YUV, panel output, or a power result.
The fusion property only enables the Android transaction/swap guard here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import time

import lg_p84_capture_round as capture_host

quality = capture_host.quality
thermal = capture_host.thermal
analyzer = capture_host.analyzer
REMOTE = capture_host.REMOTE
ATLAS_PROPERTY = capture_host.ATLAS_PROPERTY
MAX_PIXELS = 4 * 1024 * 1024
SUFFIXES = {
    'a0_before': '.a0-before.f32', 'atlas_a': '.atlas-a.f32',
    'a0_after': '.a0-after.f32', 'atlas': '.atlas.bin',
    'a0_fragment': '.a0.frag.glsl', 'atlas_fragment': '.atlas.frag.glsl',
    'vertex': '.vertex.glsl', 'original_body': '.original-body.glsl',
    'baseline_vertices': '.baseline-vertices.bin', 'android': '.android.bin',
}


class AtlasAdb(capture_host.CaptureAdb):
    """Reuse reviewed device controls; constrain live transfers to one deadline."""
    deadline = None

    def remaining(self, maximum):
        remaining = maximum if self.deadline is None else min(maximum, self.deadline-time.monotonic())
        if remaining <= 0:
            raise RuntimeError('atlas-round-timeout')
        return remaining

    def call(self, args, timeout=15, check=True):
        result = super().call(args, timeout=self.remaining(timeout), check=check)
        self.remaining(timeout)
        return result

    def read_file(self, remote, maximum, timeout=45):
        # A shared local deadline covers stat and binary transfer together.
        until = time.monotonic()+self.remaining(timeout)
        quoted = shlex.quote(remote)
        size = self.shell(f'test -f {quoted} && test ! -L {quoted} && stat -c %s {quoted}',
                          timeout=self.remaining(min(15, max(0, until-time.monotonic())))).strip()
        if type(maximum) is not int or maximum <= 0 or not re.fullmatch(r'[1-9]\d*', size) or int(size) > maximum:
            raise RuntimeError('remote-file-size-or-type-invalid:'+remote)
        started = thermal.now()
        budget = self.remaining(max(0, until-time.monotonic()))
        result = subprocess.run(self.prefix+['exec-out', 'cat', remote], capture_output=True, timeout=budget)
        with self.receipts.open('a') as out:
            out.write(json.dumps({'time': started, 'argv': self.prefix+['exec-out', 'cat', remote],
                                  'returncode': result.returncode, 'bytes': len(result.stdout),
                                  'stderr': result.stderr.decode(errors='replace')[:2000]})+'\n')
        self.remaining(max(0, until-time.monotonic()))
        if result.returncode or len(result.stdout) != int(size):
            raise RuntimeError('remote-file-incomplete:'+remote)
        return result.stdout


def controls(target):
    # Explicitly disable every legacy experiment, including the mapper FBO
    # variant. The independent atlas protocol owns this one transaction.
    values = capture_host.controls(target)
    values[ATLAS_PROPERTY] = '1'
    return values


class AtlasDiagnosticEvent(RuntimeError):
    def __init__(self, event, diagnostics):
        super().__init__('native-atlas-diagnostic-invalid')
        self.event, self.diagnostics = event, diagnostics


def atlas_rows(lines, pid):
    rows = []
    for index, line in enumerate(lines):
        header = re.match(r'\S+\s+\S+\s+(\d+)\s+\d+\s+', line)
        if not header or header[1] != pid:
            continue
        marker = re.search(r'(?<![\w-])(MKS-YUV-ATLAS(?:-LIB)?)\s+', line)
        if not marker:
            continue
        pairs = re.findall(r'([A-Za-z_][\w-]*)=([^\s]+)', line[marker.end():])
        fields = dict(pairs)
        if len(fields) != len(pairs) or 'event' not in fields:
            raise RuntimeError('malformed-atlas-event')
        rows.append((index, marker[1], fields))
    return rows


def completion(lines, pid, seek_index, target):
    # Shared frame/context failures still use the earlier compare namespace.
    # It may supply initialization diagnostics, never an atlas transaction.
    old_rows = capture_host.compare_rows(lines, pid)
    capture_host.completion(lines, pid, seek_index, target)
    if any(row['event'] in ('armed', 'capture-complete', 'capture-diagnostic-invalid') for _, _, row in old_rows):
        raise RuntimeError('mixed-atlas-and-legacy-compare-transactions')
    rows = atlas_rows(lines, pid)
    diagnostics = [{'logIndex': i, 'prefix': prefix, **row} for i, prefix, row in rows]
    for _, prefix, row in rows:
        if ((prefix == 'MKS-YUV-ATLAS' and row['event'] in ('capture-failed', 'config-invalid', 'cleanup-deferred')) or
                (prefix == 'MKS-YUV-ATLAS-LIB' and row['event'] == 'rejected')):
            raise capture_host.NativeCaptureFailure(prefix, row, diagnostics)
    events = []
    for index, prefix, row in rows:
        if prefix != 'MKS-YUV-ATLAS' or row['event'] not in ('armed', 'capture-complete', 'capture-diagnostic-invalid'):
            raise RuntimeError('unknown-atlas-event')
        if index <= seek_index:
            raise RuntimeError('atlas-event-before-current-seek-marker')
        if not capture_host.positive(row.get('id')) or not capture_host.positive(row.get('generation')):
            raise RuntimeError('malformed-atlas-identity')
        try:
            pts = float(row.get('source_pts', 'nan'))
        except ValueError:
            pts = float('nan')
        if not capture_host.exact_pts(pts, target):
            raise RuntimeError('atlas-event-source-PTS-mismatch')
        events.append(row)
    arms = [row for row in events if row['event'] == 'armed']
    ends = [row for row in events if row['event'] != 'armed']
    if len(arms) > 1 or len(ends) > 1:
        raise RuntimeError('multiple-atlas-transactions')
    if arms and (arms[0].get('android') != '1' or arms[0].get('lib') != '1'):
        raise RuntimeError('atlas-arm-failed')
    if not ends:
        return None
    end = ends[0]
    if not arms or events != [arms[0], end] or any(end[key] != arms[0][key] for key in ('id', 'generation', 'source_pts')):
        raise RuntimeError('atlas-complete-without-matching-arm')
    diagnostic = end['event'] == 'capture-diagnostic-invalid'
    prefix = f'mks-yuv-atlas-{pid}-{end["id"]}' + ('.diagnostic-invalid' if diagnostic else '')
    if end.get('file') != REMOTE+prefix+'.json' or end.get('comparison_pass') != ('refused' if diagnostic else 'unknown'):
        raise RuntimeError('atlas-endpoint-path-or-scope-mismatch')
    if diagnostic:
        raise AtlasDiagnosticEvent(end, diagnostics)
    return end


def validate_manifest(manifest, event, pid, target):
    info = analyzer.atlas_metadata(manifest)
    diagnostic = event.get('event') == 'capture-diagnostic-invalid'
    if info['status'] != ('diagnostic-invalid' if diagnostic else 'complete'):
        raise RuntimeError('atlas-manifest-endpoint-status-mismatch')
    for key, expected in (('pid', int(pid)), ('capture_id', int(event['id'])), ('generation', int(event['generation']))):
        if type(manifest.get(key)) is not int or manifest[key] != expected:
            raise RuntimeError('atlas-manifest-identity-mismatch:'+key)
    for key in ('source_pts', 'current_pts', 'target_pts'):
        if not capture_host.exact_pts(manifest.get(key), target):
            raise RuntimeError('atlas-manifest-requested-PTS-mismatch:'+key)
    w, h = min(64, manifest['width']), min(64, manifest['height'])
    if manifest['android_roi'] != {'x': (manifest['width']-w)//2, 'y': (manifest['height']-h)//2, 'w': w, 'h': h}:
        raise RuntimeError('atlas-Android-ROI-not-fixed-center')
    prefix = f'mks-yuv-atlas-{pid}-{event["id"]}' + ('.diagnostic-invalid' if diagnostic else '')
    expected = {key: prefix+suffix for key, suffix in SUFFIXES.items()}
    if manifest.get('files') != expected:
        raise RuntimeError('atlas-manifest-file-identity-mismatch')
    return expected


def analyze_with_guard(manifest_path, directory, guard):
    """Keep device/error guards active while the large offline analysis runs."""
    analysis_path = directory/'analysis.json'
    command = [sys.executable, str(Path(analyzer.__file__).resolve()), str(manifest_path), '--output', str(analysis_path)]
    with (directory/'analyzer.stdout.json').open('wb') as stdout, (directory/'analyzer.stderr').open('wb') as stderr:
        proc = subprocess.Popen(command, stdout=stdout, stderr=stderr)
        try:
            while proc.poll() is None:
                guard()
                time.sleep(.2)
            guard()
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)
    result = analyzer.load_json(analysis_path)
    if proc.returncode == 2 and result.get('status') == 'invalid-capture':
        raise analyzer.InvalidCapture(result.get('reason', 'atlas-analyzer-invalid'), result.get('diagnostic'))
    if (proc.returncode, result.get('status')) not in ((0, 'captured-floats-bit-equal'), (3, 'diagnostic-invalid')):
        raise RuntimeError('atlas-analyzer-process-or-status-mismatch')
    return result


def collect(adb, event, pid, target, directory, guard):
    directory.mkdir(exist_ok=False)
    guard()
    raw = adb.read_file(event['file'], 32*1024)
    manifest_path = directory/Path(event['file']).name
    manifest_path.write_bytes(raw)
    manifest = analyzer.load_json(manifest_path)
    files = validate_manifest(manifest, event, pid, target)
    exact_sizes = {key: manifest['rgba_words']*4 for key in ('a0_before', 'atlas_a', 'a0_after')}
    exact_sizes.update(atlas=manifest['atlas_words']*4, android=manifest['android_words']*4,
                       baseline_vertices=manifest['vertex_layout']['byte_size'])
    receipts = {}
    for key, name in files.items():
        guard()
        maximum = exact_sizes[key] if key in exact_sizes else 256*1024 if key == 'original_body' else 4*1024*1024
        data = adb.read_file(REMOTE+name, maximum)
        # Retain even a truncated payload for failure inspection.
        (directory/name).write_bytes(data)
        if key in exact_sizes and len(data) != maximum:
            raise RuntimeError('atlas-payload-byte-size-mismatch:'+key)
        if not data or len(data) > maximum:
            raise RuntimeError('atlas-source-byte-size-mismatch:'+key)
        receipts[key] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    for key, name in files.items():
        guard()
        data = adb.read_file(REMOTE+name, receipts[key]['bytes'])
        if len(data) != receipts[key]['bytes'] or hashlib.sha256(data).hexdigest() != receipts[key]['sha256']:
            raise RuntimeError('atlas-remote-file-changed:'+key)
    guard()
    if adb.read_file(event['file'], 32*1024) != raw:
        raise RuntimeError('atlas-manifest-changed-during-collection')
    guard()
    thermal.write_json(directory/'collection.json', {
        'files': receipts, 'manifestSha256': hashlib.sha256(raw).hexdigest(),
        'identityScope': 'Fresh PID endpoint plus exclusive identity filenames; payloads contain no embedded PID/PTS. Local SHA archives received bytes.',
        'timestampScope': 'Log receive order is correlation, not hardware or native clock synchronization.',
    })
    try:
        analysis = analyze_with_guard(manifest_path, directory, guard)
    except analyzer.InvalidCapture as error:
        rejected = {'status': 'invalid-capture', 'reason': str(error), 'quality_pass': False,
                    'production_equivalence_established': False}
        if getattr(error, 'diagnostic', None) is not None:
            rejected['diagnostic'] = error.diagnostic
        thermal.write_json(directory/'analysis.json', rejected)
        raise
    thermal.write_json(directory/'analysis.json', analysis)
    diagnostic = event['event'] == 'capture-diagnostic-invalid'
    if (analysis.get('status') != ('diagnostic-invalid' if diagnostic else 'captured-floats-bit-equal') or
            analysis.get('quality_pass') is not False or analysis.get('diagnostic_only') is not True or
            analysis.get('production_equivalence_established') is not False or
            (diagnostic and analysis.get('numeric_status') != 'captured-float-differences')):
        raise RuntimeError('atlas-analysis-endpoint-or-scope-mismatch')
    guard()
    return analysis


def run(args):
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    adb = AtlasAdb(args.serial, output)
    result = {'schema': 1, 'status': 'failed', 'serial': args.serial, 'startedAt': thermal.now(),
              'requestedPTS': args.pts, 'framesRequested': 1, 'atlasRequested': True,
              'quality_pass': False, 'production_equivalence_established': False,
              'displayControls': {'brightness': args.brightness, 'expectedBacklight': args.expected_backlight,
                                  'expectedPanelThermalStatus': args.expected_panel_thermal_status},
              'scope': 'One default-off RGB anchor diagnostic; no production enablement, panel or power acceptance.',
              'fusionPropertyScope': 'Android transaction/swap guard only; all three draws use the original RGB FBO route.'}
    settings, props, screen = {}, {}, {}
    log_capture = None
    touched = launched = False
    try:
        settings, props, screen = adb.settings(), adb.properties(), adb.screen_state()
        thermal.write_json(output/'original-state.json', {'settings': settings, 'properties': props, 'screen': screen})
        result['initial'] = adb.snapshot()
        quality.thermal_gate(result['initial'], {}, args.expected_panel_thermal_status)
        receipt = analyzer.load_json(Path(args.source_receipt))
        size = quality.validate_source_receipt(receipt, args.serial, args.source)
        if adb.shell('stat -c %s '+shlex.quote(args.source)).strip() != str(size):
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
        result['controls'] = controls(args.pts)
        if not set(result['controls']).issubset(props):
            raise RuntimeError('atlas-mutated-property-not-in-snapshot')
        for key, value in result['controls'].items():
            # An empty value must survive the device shell; adb.call with ''
            # drops the argument and setprop fails with "Need 2 arguments".
            adb.shell(f'setprop {shlex.quote(key)} {shlex.quote(value)}')
        for key, value in result['controls'].items():
            if adb.call(['shell', 'getprop', key]).strip() != value:
                raise RuntimeError('atlas-control-readback-mismatch:'+key)
        old_pid = adb.lab_pid()
        adb.call(['shell', 'am', 'force-stop', thermal.PACKAGE])
        if adb.lab_pid() is not None:
            raise RuntimeError('old-process-survived-force-stop')
        log_capture = thermal.LogCapture(adb, output)
        log_capture.start()
        launched = True
        adb.deadline = time.monotonic()+args.timeout
        result['launchOutput'] = adb.call(['shell', 'am', 'start', '-n', thermal.ACTIVITY])
        pid = adb.lab_pid()
        if not pid or pid == old_pid:
            raise RuntimeError('fresh-process-PID-not-established')
        result['pid'] = pid
        log_capture.set_expected_pid(pid)
        logfile = output/'flutter-logcat.txt'

        def guard(brightness=True):
            adb.remaining(15)
            if adb.lab_pid() != pid:
                raise RuntimeError('atlas-process-restarted-or-exited')
            state = log_capture.state()
            if state.get('logcatAlive') is not True:
                raise RuntimeError('atlas-logcat-exited')
            # Terminal errors remain sticky even if they arrive while pulling
            # files or analyzing the archived full-screen data.
            live_lines = logfile.read_text().splitlines() if logfile.exists() else []
            seek = capture_host.current_seek_index(live_lines, pid, args.pts)
            try:
                completion(live_lines, pid, seek if seek is not None else -1, args.pts)
            except AtlasDiagnosticEvent:
                pass  # This failed anchor may still archive its failure data.
            sample = adb.snapshot()
            quality.thermal_gate(sample, state, args.expected_panel_thermal_status,
                                 args.expected_backlight if brightness else None)
            with (output/'samples.ndjson').open('a') as out:
                out.write(json.dumps(sample)+'\n')
            adb.remaining(15)

        if args.tap:
            until = time.monotonic()+args.tap_delay
            while time.monotonic() < until:
                guard(False)
                time.sleep(min(.2, max(0, until-time.monotonic())))
            adb.call(['shell', 'input', 'tap', str(args.tap[0]), str(args.tap[1])])
        while True:
            guard(False)
            lines = logfile.read_text().splitlines() if logfile.exists() else []
            seek_index = capture_host.current_seek_index(lines, pid, args.pts)
            try:
                event = completion(lines, pid, seek_index if seek_index is not None else -1, args.pts)
            except AtlasDiagnosticEvent as diagnostic:
                if seek_index is None:
                    raise RuntimeError('atlas-diagnostic-without-current-seek')
                result.update(diagnosticEvent=diagnostic.event, nativeDiagnostics=diagnostic.diagnostics,
                              diagnosticDirectory=str(output/'diagnostic-invalid'))
                result['analysis'] = collect(adb, diagnostic.event, pid, args.pts, output/'diagnostic-invalid', guard)
                final_lines = logfile.read_text().splitlines()
                try:
                    completion(final_lines, pid, seek_index, args.pts)
                except AtlasDiagnosticEvent as final:
                    if final.event != diagnostic.event:
                        raise RuntimeError('atlas-diagnostic-evidence-changed')
                else:
                    raise RuntimeError('atlas-diagnostic-endpoint-disappeared')
                # A dedicated failed anchor can only archive evidence; no
                # historical ready/heartbeat can convert it into acceptance.
                result.update(status='diagnostic-invalid', reason='native-atlas-diagnostic-invalid')
                break
            pair = quality.observation_pair(lines, pid, args.pts, '1')
            if event and pair:
                disk = REMOTE+f'p84-quality-{pid}.ndjson'

                def load_heartbeat():
                    guard()
                    text = adb.call(['exec-out', 'cat', disk])
                    (output/'persistent-quality-latest.ndjson').write_text(text)
                    row = quality.validate_persistent([json.loads(line) for line in text.splitlines() if line.strip()],
                                                      pair[2], pid, args.source, args.pts, '1')
                    guard()
                    return row

                before = load_heartbeat()
                result['qualityBefore'] = quality.fresh_heartbeat(load_heartbeat, before['heartbeat'])
                result['captureEvent'] = event
                result['analysis'] = collect(adb, event, pid, args.pts, output/'capture', guard)
                watermark, after = quality.post_screenshot_heartbeat(load_heartbeat)
                result.update(postCollectionHeartbeatWatermark=watermark, qualityAfter=after)
                final_lines = logfile.read_text().splitlines()
                final_pair = quality.observation_pair(final_lines, pid, args.pts, '1')
                if (not final_pair or final_pair[2]['runId'] != pair[2]['runId'] or
                        completion(final_lines, pid, pair[0], args.pts) != event):
                    raise RuntimeError('atlas-evidence-changed-during-collection')
                guard()
                result['status'] = 'completed-atlas-diagnostic'
                break
            time.sleep(.5)
    except KeyboardInterrupt:
        result['reason'] = 'interrupted'
    except Exception as error:
        result['reason'] = str(error)
        if isinstance(error, capture_host.NativeCaptureFailure):
            result.update(nativeFailure=error.fields, nativeDiagnostics=error.diagnostics)
        if isinstance(error, analyzer.InvalidCapture) and getattr(error, 'diagnostic', None) is not None:
            result['analyzerDiagnostic'] = error.diagnostic
    finally:
        # Cleanup is required even when the live evidence deadline expired.
        adb.deadline = None
        handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGINT, signal.SIGTERM)}
        if launched:
            try:
                adb.call(['shell', 'am', 'force-stop', thermal.PACKAGE])
                result['hdrLabStopped'] = True
            except Exception as error:
                result.update(status='stop-failed', stopError=str(error))
        if log_capture:
            try:
                log_capture.close()
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
        if result.get('diagnosticDirectory'):
            result['diagnosticFilesCollected'] = (Path(result['diagnosticDirectory'])/'collection.json').is_file()
        result.update(restoreErrors=errors, finishedAt=thermal.now())
        thermal.write_json(output/'summary.json', result)
        for sig, handler in handlers.items():
            signal.signal(sig, handler)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--atlas', action='store_true', required=True, help='Explicit opt-in; one diagnostic transaction only.')
    parser.add_argument('--serial', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--pts', type=float, choices=quality.POINTS, required=True)
    parser.add_argument('--source', default=REMOTE+'hokkaido-p84.mp4')
    parser.add_argument('--source-receipt', required=True)
    parser.add_argument('--expected-apk-sha256', required=True)
    parser.add_argument('--brightness', type=int, default=64)
    parser.add_argument('--expected-backlight', type=int, default=64)
    parser.add_argument('--expected-panel-thermal-status', required=True)
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('--tap', type=int, nargs=2, default=[1440, 720])
    parser.add_argument('--tap-delay', type=float, default=4)
    parser.add_argument('--allow-unprotected-menu', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-fA-F]{64}', args.expected_apk_sha256):
        parser.error('expected APK SHA256 must be 64 hex characters')
    if (not 1 <= args.brightness <= 255 or not 1 <= args.expected_backlight <= 255 or
            not 15 <= args.timeout <= 180 or not 0 <= args.tap_delay <= 15):
        parser.error('brightness 1..255, timeout 15..180, tap delay 0..15 only')

    def terminate(signum, frame):
        raise KeyboardInterrupt(f'termination-signal-{signum}')

    signal.signal(signal.SIGTERM, terminate)
    result = run(args)
    print(json.dumps({key: result.get(key) for key in ('status', 'reason', 'restorationVerified', 'quality_pass')}))
    return 0 if (result['status'] == 'completed-atlas-diagnostic' and result.get('restorationVerified') is True and
                 result.get('analysis', {}).get('status') == 'captured-floats-bit-equal' and
                 result.get('quality_pass') is False) else 2


if __name__ == '__main__':
    raise SystemExit(main())
