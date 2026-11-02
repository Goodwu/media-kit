#!/usr/bin/env python3
"""One paused LG P8.4 observation: property-ready plus native swapped frame.

Never installs an APK. Uses the thermal controller's settings/restore and log
capture; output screenshots are compositor observations, not panel acceptance.
Frame trace schema must be confirmed against this source's native implementation.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import shlex
import json
import math
from pathlib import Path
import re
import signal
import subprocess
import time
from typing import Any

from PIL import Image

import lg_p84_thermal_round as thermal

POINTS = (35.035, 600.032766667, 720.052666667)
EXTRA_PROPERTIES = ('debug.mks.yuv_frame_trace', 'debug.mks.quality_pts')
QUALITY_NODES = {
    'battery_type': '/sys/class/thermal/thermal_zone30/type',
    'battery_temp': '/sys/class/thermal/thermal_zone30/temp',
    'vts_type': '/sys/class/thermal/thermal_zone39/type',
    'vts_temp': '/sys/class/thermal/thermal_zone39/temp',
    'gpu_thermal_pwrlevel': '/sys/class/kgsl/kgsl-3d0/thermal_pwrlevel',
    'hdr_mode': '/sys/devices/virtual/panel/img_tune/hdr_mode',
    'backlight': '/sys/class/leds/lcd-backlight/brightness',
    'panel_thermal_status': '/sys/class/leds/lcd-backlight/thermald_status',
}


class QualityAdb(thermal.Adb):
    def properties(self) -> dict[str, str]:
        return {key: self.call(['shell', 'getprop', key]).strip()
                for key in (*thermal.PROPERTIES, *EXTRA_PROPERTIES)}

    def snapshot(self) -> dict[str, Any]:
        raw = thermal.parse_blocks(self.shell('\n'.join(
            f'echo "@@ {key}"; cat {path} 2>/dev/null || true'
            for key, path in QUALITY_NODES.items())))
        battery, vts = thermal.temperature(raw)
        return {'hostTime': thermal.now(), 'batteryC': battery, 'vtsC': vts, 'raw': raw}

    def screenshot(self, destination: Path) -> dict[str, Any]:
        start = thermal.now()
        result = subprocess.run(self.prefix + ['exec-out', 'screencap', '-p'],
                                capture_output=True, timeout=15)
        with self.receipts.open('a') as out:
            out.write(json.dumps({'time': start, 'argv': self.prefix + ['exec-out', 'screencap', '-p'],
                                  'returncode': result.returncode,
                                  'stderr': result.stderr.decode(errors='replace')[:2000]}) + '\n')
        data = result.stdout
        if (result.returncode or len(data) < 45 or data[:8] != b'\x89PNG\r\n\x1a\n' or
                data[12:16] != b'IHDR' or data[-12:] != b'\x00\x00\x00\x00IEND\xaeB`\x82' or b'IDAT' not in data):
            raise RuntimeError('screenshot-failed-or-not-PNG')
        try:
            with Image.open(io.BytesIO(data)) as image:
                if image.format != 'PNG':
                    raise RuntimeError('screenshot-not-PNG')
                image.verify()
            with Image.open(io.BytesIO(data)) as image:
                image.load()
                w, h = image.size
                if not w or not h:
                    raise RuntimeError('screenshot-empty-dimensions')
        except Exception as error:
            raise RuntimeError('screenshot-full-decode-failed') from error
        destination.write_bytes(data)
        return {'path': str(destination), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                'width': w, 'height': h, 'scope': 'compositor-only-not-panel-or-raw-YUV'}


def quality_rows(lines: list[str], pid: str) -> list[tuple[int, dict[str, Any]]]:
    found = []
    for index, line in enumerate(lines):
        header = re.match(r'\S+\s+\S+\s+(\d+)\s+\d+\s+', line)
        if not header or header[1] != pid or 'P84_QUALITY ' not in line:
            continue
        try:
            row = json.loads(line.split('P84_QUALITY ', 1)[1].strip())
        except (ValueError, TypeError):
            continue
        if isinstance(row, dict) and str(row.get('pid')) == pid:
            found.append((index, row))
    return found


def observation_pair(lines: list[str], pid: str, target: float, fusion: str) -> tuple[int, int, dict[str, Any]] | None:
    rows = quality_rows(lines, pid)
    starts = [(i, r) for i, r in rows if r.get('status') == 'seek-started']
    # This tool owns a fresh process and exactly one auto observation. Multiple
    # seeks/ordinals cannot be silently reinterpreted as the current round.
    if len(starts) > 1:
        raise RuntimeError('multiple-quality-seeks-in-single-round')
    if not starts:
        return None
    start_index, start = starts[0]
    if (start.get('ordinal') != 1 or not isinstance(start.get('runId'), str) or
            not start['runId'].startswith(pid + ':') or
            start.get('requestedFusionMode') != fusion or
            thermal.number(start.get('requestedPTS')) != target):
        raise RuntimeError('quality-seek-identity-mismatch')
    current = [(i, r) for i, r in rows if r.get('runId') == start['runId'] and r.get('ordinal') == 1]
    for _, row in current:
        if row.get('status') in ('failed', 'cancelled', 'invalidated'):
            raise RuntimeError('quality-harness-' + row['status'])
    ready = [(i, r) for i, r in current if r.get('status') == 'ready-for-observation']
    if len(ready) > 1:
        raise RuntimeError('duplicate-quality-ready')
    if not ready:
        return None
    ready_index, row = ready[0]
    if ready_index <= start_index or row.get('requestedFusionMode') != fusion or thermal.number(row.get('requestedPTS')) != target:
        raise RuntimeError('quality-ready-identity-mismatch')
    return start_index, ready_index, row


def validate_persistent(rows: list[dict[str, Any]], ready: dict[str, Any], pid: str,
                        source: str, target: float, fusion: str) -> dict[str, Any]:
    selected = [r for r in rows if r.get('runId') == ready['runId'] and r.get('ordinal') == 1]
    if any(r.get('status') in ('failed', 'cancelled', 'invalidated') for r in selected):
        raise RuntimeError('persistent-quality-invalidated')
    if not selected or selected[-1].get('status') != 'observation-heartbeat':
        raise RuntimeError('persistent-quality-not-final-ready')
    row = selected[-1]
    if not isinstance(row.get('heartbeat'), int) or row['heartbeat'] <= 0:
        raise RuntimeError('persistent-heartbeat-sequence-invalid')
    values, report = row.get('properties', {}), row.get('report', {})
    if str(row.get('pid')) != pid or row.get('requestedFusionMode') != fusion or row.get('requestedPTS') != target:
        raise RuntimeError('persistent-quality-identity-mismatch')
    if row.get('owner', {}).get('sourcePath') != source:
        raise RuntimeError('persistent-quality-source-mismatch')
    expected = {'path': source, 'pause': 'yes', 'seeking': 'no', 'hwdec-current': 'surfacetexture', 'vo': 'gpu-next',
                'target-trc': 'pq', 'target-prim': 'bt.2020',
                'current-tracks/video/dolby-vision-profile': '8',
                'current-tracks/video/dolby-vision-compatibility-id': '4',
                'video-params/gamma': 'hlg', 'video-params/primaries': 'bt.2020'}
    if any(values.get(k) != v for k, v in expected.items()):
        raise RuntimeError('persistent-current-property-mismatch')
    if thermal.number(values.get('target-peak')) != 1000 or thermal.number(values.get('gamma')) != 0:
        raise RuntimeError('persistent-PQ-mapping-mismatch')
    for key in ('video-params/w', 'video-params/h'):
        if not re.fullmatch(r'[1-9]\d*', values.get(key, '')):
            raise RuntimeError('persistent-dimensions-invalid')
    if (report.get('verified') is not True or report.get('error') is not None or
            report.get('generation') != row.get('owner', {}).get('generation') or
            report.get('source', {}).get('kind') != 'dolbyVisionP84' or
            report.get('source', {}).get('dvProfile') != 8 or
            report.get('source', {}).get('dvCompatibilityId') != 4 or
            report.get('actual', {}).get('strategy') != 'baseLayerConvert'):
        raise RuntimeError('persistent-route-mismatch')
    fps, position = thermal.number(values.get('container-fps')), thermal.number(values.get('time-pos'))
    if fps is None or fps <= 0 or position is None or abs(position-target) > min(0.001002, 0.25/fps):
        raise RuntimeError('persistent-paused-position-mismatch')
    if fusion == '1':
        for name in ('faultPropertiesBefore', 'faultPropertiesAfter'):
            faults = row.get(name, {})
            if any(k not in faults or faults[k] not in ('', '0') for k in ('debug.mks.yuv_fail_commit', 'debug.mks.yuv_fail_gl')):
                raise RuntimeError('persistent-fault-residue-or-missing')
    return row


def thermal_gate(sample: dict[str, Any], state: dict[str, Any], panel: str,
                 brightness: int | None = None) -> None:
    reason = thermal.gpu_thermal_cap_reason(sample) or thermal.abort_reason(sample, state)
    if reason or sample.get('batteryC') is None or sample.get('vtsC') is None:
        raise RuntimeError(reason or 'temperature-unavailable')
    if sample.get('raw', {}).get('panel_thermal_status') != panel:
        raise RuntimeError('panel-thermal-status-not-approved-normal')
    if brightness is not None and (sample['raw'].get('hdr_mode') != '1' or sample['raw'].get('backlight') != str(brightness)):
        raise RuntimeError('HDR-or-backlight-contract-lost')



def native_swap(lines: list[str], pid: str, seek_index: int, target: float,
                fusion: str, fps: float = 30000 / 1001) -> dict[str, Any] | None:
    if not math.isfinite(fps) or fps <= 0:
        raise RuntimeError('invalid-native-match-fps')
    traces = []
    for index, line in enumerate(lines):
        if index <= seek_index or 'MKS-FUSION-FRAME ' not in line:
            continue
        header = re.match(r'\S+\s+\S+\s+(\d+)\s+\d+\s+', line)
        if not header or header[1] != pid:
            continue
        fields = dict(re.findall(r'(\w+)=([^\s]+)', line.split('MKS-FUSION-FRAME ', 1)[1]))
        required = ('event', 'route', 'pid', 'instance', 'token', 'generation', 'frame_id',
                    'source_pts', 'current_pts', 'mono_ns', 'gpu_draw_confirmed', 'still')
        if any(k not in fields for k in required) or fields['event'] != 'swap-success' or fields['pid'] != pid:
            raise RuntimeError('malformed-native-frame-trace')
        for key in ('token', 'generation', 'frame_id', 'mono_ns'):
            if not re.fullmatch(r'[1-9]\d*', fields[key]):
                raise RuntimeError('invalid-native-frame-identity')
        if thermal.number(fields['source_pts']) is None or thermal.number(fields['current_pts']) is None:
            raise RuntimeError('invalid-native-frame-PTS')
        if fields['still'] not in ('0', '1'):
            raise RuntimeError('invalid-native-still-flag')
        traces.append({'logIndex': index, **fields})
    if not traces:
        return None
    # Only the latest successfully swapped decoded frame is eligible. An earlier
    # matching event cannot hide a later unrelated frame or fallback route.
    last = traces[-1]
    expected_route = 'fused' if fusion == '1' else 'rgb-final'
    # VO still means still-image/frame-step/redraw semantics, not player pause.
    # A newly decoded frame displayed by a paused seek may validly have still=0.
    # Pause and unchanged position are independently proven by fresh heartbeat.
    if last['route'] != expected_route or last['gpu_draw_confirmed'] != ('1' if fusion == '1' else '0'):
        return None
    tolerance = 0.000002
    if abs(float(last['source_pts'])-target) > tolerance or abs(float(last['current_pts'])-target) > tolerance:
        return None
    return last


def same_native_source(before: dict[str, Any], after: dict[str, Any]) -> bool:
    return (before['instance'] == after['instance'] and before['generation'] == after['generation'] and
            before['route'] == after['route'] and
            abs(float(before['source_pts'])-float(after['source_pts'])) <= 0.000002 and
            abs(float(before['current_pts'])-float(after['current_pts'])) <= 0.000002)


def fresh_heartbeat(load, previous: int, timeout: float = 5) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        row = load()
        if time.monotonic() >= deadline:
            raise RuntimeError('quality-heartbeat-read-exceeded-deadline')
        if row['heartbeat'] > previous:
            return row
        time.sleep(0.1)
    raise RuntimeError('quality-heartbeat-stale-or-stopped')


def post_screenshot_heartbeat(load) -> tuple[int, dict[str, Any]]:
    # Read a new watermark only AFTER screencap has returned. Require two later
    # monitor iterations, so a read already in flight at watermark cannot alone
    # provide the post-capture observation proof.
    watermark = load()['heartbeat']
    return watermark, fresh_heartbeat(load, watermark + 1)


def foreground_matches(text: str) -> bool:
    line = next((line for line in text.splitlines() if 'mCurrentFocus=' in line), '')
    return thermal.PACKAGE + '/' in line


def validate_source_receipt(receipt: dict[str, Any], serial: str, source: str) -> int:
    if receipt.get('verified') is not True or receipt.get('serial') != serial or receipt.get('deviceSource') != source:
        raise RuntimeError('source-receipt-identity-or-verification-mismatch')
    sha, size = receipt.get('deviceSha256', ''), receipt.get('deviceBytes')
    if (not isinstance(sha, str) or not re.fullmatch(r'[0-9a-fA-F]{64}', sha) or
            not isinstance(size, int) or isinstance(size, bool) or size <= 0 or
            receipt.get('hostSha256') != sha or receipt.get('hostBytes') != size or receipt.get('returncode') != 0):
        raise RuntimeError('source-receipt-hash-or-size-invalid')
    return size


def run(args: argparse.Namespace) -> dict[str, Any]:
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    adb = QualityAdb(args.serial, output)
    result: dict[str, Any] = {'schema': 1, 'startedAt': thermal.now(), 'serial': args.serial,
                             'fusion': args.fusion, 'requestedPTS': args.pts,
                             'status': 'failed', 'scope': 'paused-observation-not-panel-acceptance',
                             'nativeStillSemantics': 'VO still is not pause; pause/position require fresh pre/post screenshot heartbeat.'}
    settings: dict[str, str] = {}
    props: dict[str, str] = {}
    screen: dict[str, Any] = {}
    capture = None
    touched = launched = False
    try:
        settings, props, screen = adb.settings(), adb.properties(), adb.screen_state()
        thermal.write_json(output/'original-state.json', {'settings': settings, 'properties': props, 'screen': screen})
        initial = adb.snapshot()
        thermal_gate(initial, {}, args.expected_panel_thermal_status)
        result['initial'] = initial
        receipt = json.loads(Path(args.source_receipt).read_text())
        size = validate_source_receipt(receipt, args.serial, args.source)
        actual_size = adb.shell('stat -c %s ' + shlex.quote(args.source)).strip()
        if actual_size != str(size):
            raise RuntimeError('source-current-size-mismatch')
        result['sourceReceipt'] = receipt
        result['sourceIdentityScope'] = 'Historical full-byte SHA receipt plus current file size; no fresh full-byte source hash this round.'
        package = adb.call(['shell', 'pm', 'path', thermal.PACKAGE]).strip()
        if not re.fullmatch(r'package:/data/app/[^\s]+/base\.apk', package):
            raise RuntimeError('unexpected-APK-path-or-splits')
        identity = adb.source_hash(package[len('package:'):])
        result['apk'] = identity
        thermal.write_json(output/'apk-identity.json', identity)
        if identity['sha256'] != args.expected_apk_sha256.lower():
            raise RuntimeError('installed-APK-hash-mismatch')
        thermal_gate(adb.snapshot(), {}, args.expected_panel_thermal_status)
        touched = True
        adb.wake_unprotected(screen, args.allow_unprotected_menu)
        for key, value in [('screen_brightness_mode', 0), ('screen_brightness', args.brightness),
                           ('accelerometer_rotation', 0), ('user_rotation', 1),
                           ('screen_off_timeout', int((args.timeout+120)*1000))]:
            adb.call(['shell', 'settings', 'put', 'system', key, str(value)])
        control = {'debug.mks.thermal_sync': 'display-resample', 'debug.mks.thermal_trace': '1',
                   'debug.mks.defer_publish_flush': '0', 'debug.mks.gpu_timing': '0',
                   'debug.mks.yuv_fusion': args.fusion, 'debug.mks.yuv_fail_commit': '0',
                   'debug.mks.yuv_fail_gl': '0', 'debug.mks.yuv_frame_trace': '1',
                   'debug.mks.quality_pts': str(args.pts)}
        for key, value in control.items():
            adb.call(['shell', 'setprop', key, value])
        result['controls'] = control
        adb.call(['shell', 'am', 'force-stop', thermal.PACKAGE])
        capture = thermal.LogCapture(adb, output)
        capture.start()
        launched = True
        result['launchOutput'] = adb.call(['shell', 'am', 'start', '-n', thermal.ACTIVITY])
        pid = adb.lab_pid()
        if pid is None:
            raise RuntimeError('quality-process-not-running')
        result['pid'] = pid
        capture.set_expected_pid(pid)
        if args.tap:
            time.sleep(args.tap_delay)
            adb.call(['shell', 'input', 'tap', str(args.tap[0]), str(args.tap[1])])
        deadline = time.monotonic()+args.timeout
        disk_path = f'/sdcard/Android/data/{thermal.PACKAGE}/files/p84-quality-{pid}.ndjson'
        while True:
            if time.monotonic() >= deadline:
                raise RuntimeError('quality-native-swap-timeout')
            if adb.lab_pid() != pid:
                raise RuntimeError('quality-process-restarted-or-exited')
            state = capture.state()
            if not state['logcatAlive']:
                raise RuntimeError('quality-logcat-exited')
            sample = adb.snapshot()
            thermal_gate(sample, state, args.expected_panel_thermal_status)
            with (output/'samples.ndjson').open('a') as out:
                out.write(json.dumps(sample)+'\n')
            lines = (output/'flutter-logcat.txt').read_text().splitlines() if (output/'flutter-logcat.txt').exists() else []
            pair = observation_pair(lines, pid, args.pts, args.fusion)
            heartbeats = [] if pair is None else [r for _, r in quality_rows(lines, pid)
                    if r.get('runId') == pair[2]['runId'] and r.get('ordinal') == 1 and
                    r.get('status') == 'observation-heartbeat']
            if pair and heartbeats:
                data = adb.call(['exec-out', 'cat', disk_path])
                (output/'persistent-quality.ndjson').write_text(data)
                rows = [json.loads(line) for line in data.splitlines() if line.strip()]
                persistent = validate_persistent(rows, pair[2], pid, args.source, args.pts, args.fusion)
                native = native_swap(lines, pid, pair[0], args.pts, args.fusion,
                                     float(persistent['properties']['container-fps']))
                if native:
                    thermal_gate(sample, state, args.expected_panel_thermal_status, args.expected_backlight)
                    def load_heartbeat():
                        if adb.lab_pid() != pid:
                            raise RuntimeError('quality-process-changed-during-heartbeat')
                        heartbeat_state = capture.state()
                        if not heartbeat_state['logcatAlive']:
                            raise RuntimeError('quality-logcat-exited-during-heartbeat')
                        thermal_gate(adb.snapshot(), heartbeat_state, args.expected_panel_thermal_status, args.expected_backlight)
                        text = adb.call(['exec-out', 'cat', disk_path])
                        (output/'persistent-quality-latest.ndjson').write_text(text)
                        return validate_persistent([json.loads(l) for l in text.splitlines() if l.strip()],
                                                   pair[2], pid, args.source, args.pts, args.fusion)
                    persistent = fresh_heartbeat(load_heartbeat, persistent['heartbeat'])
                    result['quality'] = persistent
                    result['nativeSwap'] = native
                    focus = adb.call(['shell', 'dumpsys', 'window'])
                    (output/'window-before-screenshot.txt').write_text(focus)
                    if not foreground_matches(focus):
                        raise RuntimeError('quality-app-not-foreground')
                    result['screenshot'] = adb.screenshot(output/'observation.png')
                    # Recheck final ordinal after screenshot. A cancelled record
                    # supersedes an earlier ready record even if write was in flight.
                    watermark, after_heartbeat = post_screenshot_heartbeat(load_heartbeat)
                    result['screenshotHeartbeatWatermark'] = watermark
                    result['qualityAfterScreenshot'] = after_heartbeat
                    final = adb.call(['exec-out', 'cat', disk_path])
                    (output/'persistent-quality-final.ndjson').write_text(final)
                    validate_persistent([json.loads(l) for l in final.splitlines() if l.strip()],
                                        pair[2], pid, args.source, args.pts, args.fusion)
                    if adb.lab_pid() != pid:
                        raise RuntimeError('process-changed-during-screenshot')
                    after_lines = (output/'flutter-logcat.txt').read_text().splitlines()
                    after_pair = observation_pair(after_lines, pid, args.pts, args.fusion)
                    after_native = native_swap(after_lines, pid, pair[0], args.pts, args.fusion,
                                               float(persistent['properties']['container-fps']))
                    if after_pair is None or after_native is None or not same_native_source(native, after_native):
                        raise RuntimeError('quality-frame-invalidated-during-screenshot')
                    focus_after = adb.call(['shell', 'dumpsys', 'window'])
                    (output/'window-after-screenshot.txt').write_text(focus_after)
                    if not foreground_matches(focus_after):
                        raise RuntimeError('quality-app-left-foreground-during-screenshot')
                    result['nativeSwapAfterScreenshot'] = after_native
                    result['final'] = adb.snapshot()
                    final_state = capture.state()
                    if not final_state['logcatAlive']:
                        raise RuntimeError('quality-logcat-exited-before-completion')
                    thermal_gate(result['final'], final_state, args.expected_panel_thermal_status, args.expected_backlight)
                    result['status'] = 'completed-observation'
                    break
            time.sleep(1)
    except KeyboardInterrupt:
        result['reason'] = 'interrupted'
    except Exception as error:
        result['reason'] = str(error)
    finally:
        handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGINT, signal.SIGTERM)}
        if launched:
            try:
                adb.call(['shell', 'am', 'force-stop', thermal.PACKAGE])
                result['hdrLabStopped'] = True
            except Exception as error:
                result['stopError'] = str(error)
                result['status'] = 'stop-failed'
        if capture:
            try:
                capture.close()
            except Exception as error:
                result['captureCloseError'] = str(error)
                result['status'] = 'capture-close-failed'
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
            result['restorationVerified'], result['automaticBrightnessScalarChanged'] = ok, auto
            if not ok:
                result['status'] = 'restoration-failed'
        except Exception as error:
            result.update(status='restoration-failed', restorationError=str(error))
        result['restoreErrors'] = errors
        result['finishedAt'] = thermal.now()
        thermal.write_json(output/'summary.json', result)
        for sig, handler in handlers.items():
            signal.signal(sig, handler)
    return result


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--fusion', choices=('0', '1'), required=True)
    p.add_argument('--pts', type=float, choices=POINTS, required=True)
    p.add_argument('--source', default='/sdcard/Android/data/com.example.media_kit_hdr_lab/files/hokkaido-p84.mp4')
    p.add_argument('--source-receipt', required=True)
    p.add_argument('--expected-apk-sha256', required=True)
    p.add_argument('--brightness', type=int, default=255)
    p.add_argument('--expected-backlight', type=int, default=255)
    p.add_argument('--expected-panel-thermal-status', required=True)
    p.add_argument('--timeout', type=float, default=60)
    p.add_argument('--tap', type=int, nargs=2, default=[1440, 720])
    p.add_argument('--tap-delay', type=float, default=4)
    p.add_argument('--allow-unprotected-menu', action='store_true')
    args = p.parse_args()
    if not re.fullmatch('[0-9a-fA-F]{64}', args.expected_apk_sha256):
        p.error('expected APK SHA256 must be 64 hex characters')
    if not 1 <= args.brightness <= 255 or not 1 <= args.expected_backlight <= 255 or not 15 <= args.timeout <= 180:
        p.error('brightness 1..255, timeout15..180 only')
    def terminate(signum, frame):
        raise KeyboardInterrupt(f'termination-signal-{signum}')
    signal.signal(signal.SIGTERM, terminate)
    result = run(args)
    print(json.dumps({k: result.get(k) for k in ('status', 'reason', 'restorationVerified', 'nativeSwap')}))
    return 0 if result['status'] == 'completed-observation' and result.get('restorationVerified') else 2


if __name__ == '__main__':
    raise SystemExit(main())
