#!/usr/bin/env python3
"""One LG hdr_lab thermal round; never installs an APK or changes other apps.

Example (only after the current-source APK and source were verified):
  python3 tool/lg_p84_thermal_round.py --serial SERIAL --output RESULT_DIR \
      --mode baseline --duration 360 --tap 1440 720

The same installed APK reads debug.mks.thermal_sync at startup. Baseline uses
`display-resample`, candidate uses `audio`. Every exit restores the captured
system settings/properties; hdr_lab is stopped rather than restored. A stopped
or invalid run is never reported as a complete thermal window.
"""
from __future__ import annotations

import argparse
import base64
from collections import deque
import datetime as dt
import hashlib
import json
import math
import signal
from pathlib import Path
import re
import shlex
import subprocess
import threading
import time
from typing import Any

PACKAGE = 'com.example.media_kit_hdr_lab'
ACTIVITY = PACKAGE + '/.MainActivity'
MODES = {'baseline': 'display-resample', 'candidate': 'audio'}
SETTINGS = ('screen_brightness_mode', 'screen_brightness',
            'accelerometer_rotation', 'user_rotation', 'screen_off_timeout')
PROPERTIES = ('debug.mks.thermal_sync', 'debug.mks.thermal_trace', 'debug.mks.defer_publish_flush')
LOG_PATTERN = re.compile(r'THERMAL_JSON|THERMAL_ERROR|MKS-THERMAL|check_hot|thermal.*(shutdown|critical)|FATAL EXCEPTION|Fatal signal', re.I)


def now() -> str:
    return dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).isoformat()


def write_json(path: Path, value: Any) -> None:
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temp.replace(path)


def parse_blocks(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    key = None
    for line in text.splitlines():
        if line.startswith('@@ '):
            key = line[3:]
            result[key] = ''
        elif key is not None:
            result[key] += line + '\n'
    return {k: v.strip() for k, v in result.items()}


def number(value: str | None) -> float | None:
    try:
        parsed = float(str(value).strip()) if value is not None else None
        return parsed if parsed is not None and math.isfinite(parsed) else None
    except (ValueError, TypeError):
        return None


def temperature(raw: dict[str, str]) -> tuple[float | None, float | None]:
    battery = number(raw.get('battery_temp'))
    vts = number(raw.get('vts_temp'))
    # These are explicit LG-H870DS node contracts, not a unit heuristic applied
    # to every thermal zone. Keep the raw values in each sample.
    battery_c = battery / 1000 if battery is not None and raw.get('battery_type') == 'battery' else None
    vts_c = vts / 10 if vts is not None and raw.get('vts_type') == 'vts' else None
    return battery_c, vts_c


def parse_thermal_json(line: str) -> dict[str, Any] | None:
    if 'THERMAL_JSON_PART' in line or 'THERMAL_JSON' not in line:
        return None
    tail = line.split('THERMAL_JSON', 1)[1]
    pos = tail.find('{')
    if pos < 0:
        return None
    try:
        value, _ = json.JSONDecoder().raw_decode(tail[pos:])
        return value if isinstance(value, dict) else None
    except json.JSONDecodeError:
        return None


class ThermalLogAssembler:
    """Bounded multipart reassembly. Partial rows never become live samples."""
    def __init__(self, ttl: float = 20):
        self.ttl = ttl
        self.groups: dict[tuple[str, str, int], dict[str, Any]] = {}
        self.expired_groups = 0
        self.rejected_parts = 0
        self.accepted_ordinals: dict[tuple[str, str, int], int] = {}

    def _accept(self, row: dict[str, Any] | None, pid: str) -> dict[str, Any] | None:
        if (not isinstance(row, dict) or row.get('schemaVersion') != 1 or
                not isinstance(row.get('runId'), str) or not row['runId'] or
                str(row.get('pid', '')) != pid or type(row.get('serial')) is not int or
                type(row.get('sampleOrdinal')) is not int or row['sampleOrdinal'] < 0):
            self.rejected_parts += 1
            return None
        identity = (pid, row['runId'], row['serial'])
        if row['sampleOrdinal'] <= self.accepted_ordinals.get(identity, -1):
            self.rejected_parts += 1
            return None
        if len(self.accepted_ordinals) >= 16 and identity not in self.accepted_ordinals:
            del self.accepted_ordinals[next(iter(self.accepted_ordinals))]
        self.accepted_ordinals[identity] = row['sampleOrdinal']
        return row

    def feed(self, line: str, pid: str, at: float) -> dict[str, Any] | None:
        for key in list(self.groups):
            if at - self.groups[key]['created'] > self.ttl:
                del self.groups[key]
                self.expired_groups += 1
        if 'THERMAL_JSON_PART' not in line:
            return self._accept(parse_thermal_json(line), pid) if 'THERMAL_JSON' in line else None
        try:
            tail = line.split('THERMAL_JSON_PART', 1)[1]
            part = json.loads(tail[tail.index('{'):])
            rid, ordinal = part['r'], part['n']
            index, count, data = part['i'], part['c'], part['d']
            if (not isinstance(rid, str) or not rid or len(rid) > 160 or
                    type(ordinal) is not int or ordinal < 0 or
                    type(index) is not int or type(count) is not int or
                    not 1 <= count <= 128 or not 0 <= index < count or
                    not isinstance(data, str) or len(data) > 600 or
                    not re.fullmatch(r'[A-Za-z0-9+/=]*', data)):
                raise ValueError('bad multipart envelope')
            key = (pid, rid, ordinal)
            if key not in self.groups:
                if len(self.groups) >= 8:
                    raise ValueError('too many incomplete samples')
                self.groups[key] = {'created': at, 'count': count, 'parts': {}}
            group = self.groups[key]
            if group['count'] != count:
                del self.groups[key]
                raise ValueError('part count changed')
            prior = group['parts'].get(index)
            if prior is not None and prior != data:
                del self.groups[key]
                raise ValueError('part data conflict')
            group['parts'][index] = data
            if len(group['parts']) != count:
                return None
            del self.groups[key]
            encoded = ''.join(group['parts'][i] for i in range(count))
            row = json.loads(base64.b64decode(encoded, validate=True).decode('utf-8'))
            if (not isinstance(row, dict) or row.get('runId') != rid or
                    row.get('sampleOrdinal') != ordinal or str(row.get('pid', '')) != pid or
                    type(row.get('serial')) is not int):
                raise ValueError('assembled identity mismatch')
            return self._accept(row, pid)
        except (ValueError, KeyError, TypeError, UnicodeDecodeError, json.JSONDecodeError):
            self.rejected_parts += 1
            return None


def restoration_matches(original: dict[str, str], restored: dict[str, str],
                        original_props: dict[str, str], restored_props: dict[str, str],
                        write_errors: list[str]) -> tuple[bool, bool]:
    before, after = dict(original), dict(restored)
    auto_changed = False
    if before.get('screen_brightness_mode') == '1' and after.get('screen_brightness_mode') == '1':
        auto_changed = before.get('screen_brightness') != after.get('screen_brightness')
        before.pop('screen_brightness', None)
        after.pop('screen_brightness', None)
    return not write_errors and before == after and original_props == restored_props, auto_changed


def proc_cpu_ticks(stat: str) -> int | None:
    # comm may contain spaces or ')'; numeric fields follow the last ')'.
    try:
        fields = stat.rsplit(')', 1)[1].split()
        return int(fields[11]) + int(fields[12])  # /proc fields 14 and 15
    except (ValueError, IndexError):
        return None


class Adb:
    def __init__(self, serial: str, output: Path):
        self.prefix = ['adb', '-s', serial]
        self.output = output
        self.receipts = output / 'commands.ndjson'

    def call(self, args: list[str], timeout: float = 15, check: bool = True) -> str:
        started = now()
        r = subprocess.run(self.prefix + args, capture_output=True, text=True, timeout=timeout)
        with self.receipts.open('a') as f:
            f.write(json.dumps({'time': started, 'argv': self.prefix + args,
                                'returncode': r.returncode, 'stderr': r.stderr[:2000]}) + '\n')
        if check and r.returncode:
            raise RuntimeError(f'ADB failed ({r.returncode}): {args!r}: {r.stderr[:500]}')
        return r.stdout

    def shell(self, script: str, **kwargs: Any) -> str:
        return self.call(['shell', script], **kwargs)

    def source_hash(self, path: str) -> dict[str, Any]:
        started = now()
        proc = subprocess.Popen(self.prefix + ['exec-out', 'cat', path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        digest = hashlib.sha256()
        size = 0
        assert proc.stdout is not None
        for block in iter(lambda: proc.stdout.read(1024 * 1024), b''):
            digest.update(block)
            size += len(block)
        stderr = proc.stderr.read().decode(errors='replace') if proc.stderr else ''
        code = proc.wait()
        if code:
            raise RuntimeError(f'Source read failed: {stderr[:500]}')
        return {'time': started, 'serial': self.prefix[-1], 'path': path,
                'bytes': size, 'sha256': digest.hexdigest()}

    def settings(self) -> dict[str, str]:
        script = '\n'.join(f'echo "@@ {key}"; settings get system {key}' for key in SETTINGS)
        return parse_blocks(self.shell(script))

    def properties(self) -> dict[str, str]:
        return {key: self.call(['shell', 'getprop', key]).strip() for key in PROPERTIES}

    def restore(self, settings: dict[str, str], properties: dict[str, str]) -> list[str]:
        errors = []
        # Restore all entries even when one write fails.
        # Restore scalar first, then allow the original auto mode to own it.
        setting_order = sorted(settings, key=lambda key: key == 'screen_brightness_mode')
        for key in setting_order:
            value = settings[key]
            try:
                if value in ('null', ''):
                    self.call(['shell', 'settings', 'delete', 'system', key])
                else:
                    self.call(['shell', 'settings', 'put', 'system', key, value])
            except Exception as error:
                errors.append(f'{key}: {error}')
        for key, value in properties.items():
            try:
                self.shell(f'setprop {shlex.quote(key)} {shlex.quote(value)}')
            except Exception as error:
                errors.append(f'{key}: {error}')
        return errors

    def screen_state(self) -> dict[str, Any]:
        power = self.call(['shell', 'dumpsys', 'power'])
        window = self.call(['shell', 'dumpsys', 'window'])
        match = re.search(r'isStatusBarKeyguard=(true|false)', window)
        secure = re.search(r'mKeyguardDelegate[\s\S]{0,1800}?secure=(true|false)', window)
        return {'on': 'Display Power: state=ON' in power,
                'awake': 'mWakefulness=Awake' in power,
                'keyguard': None if not match else match.group(1) == 'true',
                'keyguardSecure': None if not secure else secure.group(1) == 'true'}

    def wake_unprotected(self, original: dict[str, Any], allow_unprotected: bool) -> dict[str, Any]:
        self.call(['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'])
        awake = self.screen_state()
        if not awake['on']:
            raise RuntimeError('screen-not-ON-after-WAKEUP')
        if awake['keyguard'] is True:
            if awake['keyguardSecure'] is not False and not allow_unprotected:
                raise RuntimeError('protected-or-unknown-keyguard-refuse-MENU')
            if awake['keyguardSecure'] is True:
                raise RuntimeError('protected-keyguard-refuse-MENU')
            self.call(['shell', 'input', 'keyevent', 'KEYCODE_MENU'])
            awake = self.screen_state()
        if not awake['on'] or awake['keyguard'] is not False:
            raise RuntimeError('screen-or-keyguard-precondition-failed')
        return awake

    def lab_pid(self) -> str | None:
        ps = self.call(['shell', 'ps'])
        return next((line.split()[1] for line in ps.splitlines()
                     if line.split() and line.split()[-1] == PACKAGE), None)

    def snapshot(self) -> dict[str, Any]:
        pid = self.lab_pid()
        nodes = {
            'uptime': '/proc/uptime', 'cpu_total': '/proc/stat',
            'battery_type': '/sys/class/thermal/thermal_zone30/type',
            'battery_temp': '/sys/class/thermal/thermal_zone30/temp',
            'vts_type': '/sys/class/thermal/thermal_zone39/type',
            'vts_temp': '/sys/class/thermal/thermal_zone39/temp',
            'pmic_type': '/sys/class/thermal/thermal_zone23/type',
            'pmic_temp': '/sys/class/thermal/thermal_zone23/temp',
            'backlight': '/sys/class/leds/lcd-backlight/brightness',
            'backlight_max': '/sys/class/leds/lcd-backlight/max_brightness',
            'gpu_hz': '/sys/class/kgsl/kgsl-3d0/gpuclk',
            'gpu_busy': '/sys/class/kgsl/kgsl-3d0/gpubusy',
            'battery_status': '/sys/class/power_supply/battery/status',
            'battery_current_now': '/sys/class/power_supply/battery/current_now',
            'battery_capacity': '/sys/class/power_supply/battery/capacity',
            'usb_online': '/sys/class/power_supply/usb/online',
            'ac_online': '/sys/class/power_supply/ac/online',
        }
        for n in range(4):
            nodes[f'cpu{n}_khz'] = f'/sys/devices/system/cpu/cpu{n}/cpufreq/scaling_cur_freq'
        if pid and pid.isdigit():
            nodes['app_stat'] = f'/proc/{pid}/stat'
        script = '\n'.join(f'echo "@@ {key}"; cat {shlex.quote(path)} 2>/dev/null || true'
                           for key, path in nodes.items())
        if pid and pid.isdigit():
            script += f'\necho "@@ threads"; for f in /proc/{pid}/task/*/stat; do cat "$f" 2>/dev/null; done\n'
        raw = parse_blocks(self.shell(script))
        battery_c, vts_c = temperature(raw)
        return {'hostTime': now(), 'hostMonotonic': time.monotonic(), 'pid': pid,
                'batteryC': battery_c, 'vtsC': vts_c,
                'appCpuTicks': proc_cpu_ticks(raw.get('app_stat', '')), 'raw': raw, 'screen': self.screen_state()}


class LogCapture:
    def __init__(self, adb: Adb, output: Path):
        self.adb, self.output = adb, output
        self.proc: subprocess.Popen | None = None
        self.thread: threading.Thread | None = None
        self.lock = threading.Lock()
        self.latest_lab: dict[str, Any] | None = None
        self.latest_lab_at: float | None = None
        self.playback_start_at: float | None = None
        self.playback_serial: Any = None
        self.playback_run_id: str | None = None
        self.playback_pid: str | None = None
        self.lab_pid: str | None = None
        self.cutoff = dt.datetime.fromtimestamp(float(adb.shell('date +%s').strip()), dt.timezone(dt.timedelta(hours=8)))
        self.native = deque(maxlen=30)
        self.native_import_identity: dict[str, str] | None = None
        self.native_import_changed = False
        self.hot_events: deque[float] = deque(maxlen=50)
        self.fatal_events: deque[str] = deque(maxlen=10)
        self.harness_errors: deque[str] = deque(maxlen=10)
        self.assembler = ThermalLogAssembler()
        self.expected_pid: str | None = None
        self.flutter_pending: deque[tuple[str, str]] = deque(maxlen=1000)
        self.flutter_stream: Any = None
        self.start_at = time.monotonic()

    def set_expected_pid(self, pid: str | None) -> None:
        if not pid or not pid.isdigit():
            raise RuntimeError('cannot-bind-current-lab-log-pid')
        with self.lock:
            self.expected_pid = pid
            self._flush_flutter_pending()

    def _flush_flutter_pending(self) -> None:
        if self.flutter_stream is None or self.expected_pid is None:
            return
        for pid, line in self.flutter_pending:
            if pid == self.expected_pid:
                self.flutter_stream.write(line)
        self.flutter_pending.clear()
        self.flutter_stream.flush()

    def start(self) -> None:
        # Follow without clearing the user's log buffers. -T 1 limits replay.
        self.proc = subprocess.Popen(self.adb.prefix + ['exec-out', 'logcat', '-v', 'threadtime', '-T', '1'],
                                     stdout=subprocess.PIPE, stderr=(self.output / 'logcat.stderr').open('w'), text=True)
        def consume() -> None:
            assert self.proc and self.proc.stdout
            with (self.output / 'thermal-logcat.txt').open('w') as stream, (self.output / 'flutter-logcat.txt').open('w') as flutter:
                self.flutter_stream = flutter
                for line in self.proc.stdout:
                    header = re.match(r'(\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\s+(\d+)\s+(\d+)', line)
                    if not header:
                        continue
                    stamp = dt.datetime.strptime(str(self.cutoff.year) + '-' + header.group(1), '%Y-%m-%d %H:%M:%S.%f').replace(tzinfo=self.cutoff.tzinfo)
                    if stamp < self.cutoff:
                        continue
                    line = re.sub(r'(?:https?|file|content)://[^\s\"\\]+', '<URL_REDACTED>', line)
                    if re.search(r'\bflutter\s*:', line):
                        with self.lock:
                            if self.expected_pid is None:
                                self.flutter_pending.append((header.group(2), line))
                            elif header.group(2) == self.expected_pid:
                                self._flush_flutter_pending()
                                flutter.write(line); flutter.flush()
                    if not LOG_PATTERN.search(line):
                        continue
                    if ('THERMAL_JSON' in line or 'THERMAL_ERROR' in line or 'MKS-THERMAL' in line or re.search(r'FATAL EXCEPTION|Fatal signal', line)) and (self.expected_pid is None or header.group(2) != self.expected_pid):
                        continue
                    stream.write(line)
                    stream.flush()
                    at = time.monotonic()
                    value = self.assembler.feed(line, header.group(2), at)
                    with self.lock:
                        if value:
                            self.latest_lab, self.latest_lab_at = value, at
                            self.lab_pid = header.group(2)
                            if value.get('phase') == 'start' and self.playback_start_at is None:
                                self.playback_start_at = at
                                self.playback_serial = value.get('serial')
                                self.playback_run_id = value.get('runId')
                                self.playback_pid = header.group(2)
                        if 'THERMAL_ERROR' in line:
                            self.harness_errors.append(line.strip())
                        if 'MKS-THERMAL' in line:
                            fields = dict(re.findall(r'(\w+)=([^\s]+)', line.split('MKS-THERMAL',1)[1]))
                            if fields.get('kind') == 'import':
                                identity = {key: fields.get(key, '') for key in ('instance', 'start_ns')}
                                if self.native_import_identity is None:
                                    self.native_import_identity = identity
                                elif identity != self.native_import_identity:
                                    self.native_import_changed = True
                            self.native.append({'hostMonotonic': at, 'line': line.strip()})
                        if 'check_hot' in line and ('has been sent' in line or 'will has been send' in line):
                            self.hot_events.append(at)
                        if re.search(r'FATAL EXCEPTION|Fatal signal|thermal.*(shutdown|critical)', line, re.I):
                            self.fatal_events.append(line.strip())
        self.thread = threading.Thread(target=consume, daemon=True)
        self.thread.start()

    def state(self) -> dict[str, Any]:
        with self.lock:
            at = time.monotonic()
            return {'hostMonotonic': at, 'nativeImportIdentity': self.native_import_identity, 'nativeImportChanged': self.native_import_changed, 'lab': self.latest_lab, 'labAgeSeconds': None if self.latest_lab_at is None else at - self.latest_lab_at,
                    'playbackStartAt': self.playback_start_at, 'playbackSerial': self.playback_serial, 'playbackRunId': self.playback_run_id, 'playbackPid': self.playback_pid, 'labPid': self.lab_pid, 'native': list(self.native),
                    'hotEventsLast30s': sum(t >= at - 30 for t in self.hot_events),
                    'fatalEvents': list(self.fatal_events), 'harnessErrors': list(self.harness_errors),
                    'multipartExpiredGroups': self.assembler.expired_groups, 'multipartRejectedParts': self.assembler.rejected_parts,
                    'logcatAlive': self.proc is not None and self.proc.poll() is None}

    def close(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=3)
        if self.thread:
            self.thread.join(timeout=3)


def abort_reason(sample: dict[str, Any], state: dict[str, Any]) -> str | None:
    if sample.get('batteryC') is not None and sample['batteryC'] >= 45:
        return 'battery-at-or-above-45C'
    if sample.get('vtsC') is not None and sample['vtsC'] >= 48.5:
        return 'vts-at-or-above-48.5C'
    if state.get('hotEventsLast30s', 0) >= 1:
        return 'fresh-system-check-hot'
    if state.get('fatalEvents'):
        return 'fatal-or-critical-log-observed'
    return None


def runtime_error(state: dict[str, Any], mode: str, pid: str | None = None, source: str | None = None) -> str | None:
    lab = state.get('lab')
    if not lab or state.get('labAgeSeconds') is None or state['labAgeSeconds'] >= 30:
        return 'missing-or-stale-THERMAL_JSON'
    if lab.get('phase') not in ('start', 'sample'):
        return 'unexpected-harness-phase'
    if state.get('playbackSerial') is None:
        return 'missing-playback-generation'
    if lab.get('serial') != state['playbackSerial']:
        return 'playback-generation-drift'
    if not state.get('playbackRunId') or lab.get('runId') != state['playbackRunId']:
        return 'playback-run-id-drift-or-missing'
    if lab.get('sampleInvalidReason'):
        return 'harness-invalid-sample:' + str(lab['sampleInvalidReason'])
    frozen_pid = state.get('playbackPid')
    if not frozen_pid or str(lab.get('pid', '')) != frozen_pid or state.get('labPid') != frozen_pid:
        return 'harness-frozen-pid-mismatch'
    if pid is not None and pid != frozen_pid:
        return 'harness-current-process-pid-mismatch'
    if lab.get('mode') != mode:
        return 'harness-mode-mismatch'
    props = lab.get('properties', {})
    required = {'video-sync': mode, 'hwdec-current': 'surfacetexture',
                'vo': 'gpu-next', 'target-trc': 'pq', 'target-peak': '1000',
                'target-prim': 'bt.2020', 'gamma': '0'}
    if source is not None:
        required['path'] = source
    for key, expected in required.items():
        if key in ('gamma', 'target-peak'):
            actual_number = number(props.get(key))
            accepted = actual_number is not None and actual_number == float(expected)
        else:
            accepted = str(props.get(key, '')).strip() == expected
        if not accepted:
            return 'runtime-property-mismatch:' + key
    if str(props.get('pause', '')).strip() not in ('no', 'false', 'False'):
        return 'playback-not-running'
    report = lab.get('report', {})
    if report.get('verified') is not True:
        return 'route-not-verified'
    if report.get('source', {}).get('kind') != 'dolbyVisionP84':
        return 'source-is-not-dolbyVisionP84'
    actual = report.get('actual') or {}
    if actual.get('strategy') != 'baseLayerConvert':
        return 'actual-route-is-not-baseLayerConvert'
    if source is not None and report.get('sourcePath') != source:
        return 'report-source-path-mismatch'
    if report.get('error'):
        return 'route-error'
    return None


def publish_policy_error(state: dict[str, Any], expected: str) -> str | None:
    if state.get('nativeImportChanged'):
        return 'native-import-instance-rebuilt'
    frozen = state.get('nativeImportIdentity')
    if not frozen or not all(frozen.get(key) for key in ('instance', 'start_ns')):
        return 'missing-native-import-identity'
    imports = [entry for entry in state.get('native', []) if 'kind=import ' in entry['line']]
    if len(imports) < 2:
        return 'insufficient-native-import-policy-reports'
    latest = imports[-1]
    if state.get('hostMonotonic', time.monotonic()) - latest['hostMonotonic'] >= 20:
        return 'stale-native-import-policy'
    parsed = [(entry, dict(re.findall(r'(\w+)=([^\s]+)', entry['line']))) for entry in imports]
    for entry, fields in parsed:
        if any(fields.get(key) != frozen[key] for key in ('instance', 'start_ns')):
            return 'native-import-instance-rebuilt'
        if fields.get('defer_publish_flush') != expected:
            return 'native-import-publish-policy-mismatch'
        for key in ('publish_flush', 'publish_deferred', 'retire_flush', 'fence_create_failed', 'reap_stuck', 'latch_timeout', 'stale_drop'):
            if not str(fields.get(key, '')).isdigit():
                return 'missing-native-publish-counter:' + key
    active = 'publish_deferred' if expected == '1' else 'publish_flush'
    inactive = 'publish_flush' if expected == '1' else 'publish_deferred'
    last_fields = parsed[-1][1]
    if int(last_fields[inactive]) != 0 or int(last_fields[active]) <= 0 or int(last_fields['retire_flush']) <= 0:
        return 'native-publish-policy-has-no-effective-work'
    previous = next(((entry, fields) for entry, fields in reversed(parsed[:-1])
                     if latest['hostMonotonic']-entry['hostMonotonic'] >= 1), None)
    if previous is None or int(last_fields[active]) <= int(previous[1][active]):
        return 'native-publish-policy-no-counter-increment'
    return None


def native_failure_reason(state: dict[str, Any]) -> str | None:
    # The controller creates a fresh process/mapper for every run. Counters
    # are cumulative from that init zero, so any positive value is a failure
    # increment in this run, even when MP_WARN was suppressed.
    for entry in state.get('native', []):
        fields = dict(re.findall(r'(\w+)=([^\s]+)', entry['line']))
        if fields.get('kind') != 'import':
            continue
        for key in ('fence_create_failed', 'reap_stuck', 'latch_timeout', 'stale_drop'):
            value = fields.get(key)
            if value is not None and (not value.isdigit() or int(value) > 0):
                return 'native-import-failure-counter:' + key
    return None


def run(args: argparse.Namespace) -> dict[str, Any]:
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    adb = Adb(args.serial, output)
    experiment = getattr(args, 'experiment', 'sync')
    expected_sync = 'display-resample' if experiment == 'publish-flush' else MODES[args.mode]
    expected_defer = '1' if experiment == 'publish-flush' and args.mode == 'candidate' else '0'
    result: dict[str, Any] = {'schema': 1, 'experiment': experiment, 'requestedDeferPublishFlush': expected_defer, 'startedAt': now(), 'mode': args.mode,
                             'requestedVideoSync': expected_sync, 'requestedDurationSeconds': args.duration,
                             'status': 'preflight', 'completeWindow': False, 'samples': 0,
                             'thresholds': {'batteryC': 45, 'vtsC': 48.5, 'systemHotEventsIn30s': 1}}
    original_settings: dict[str, str] = {}
    original_props: dict[str, str] = {}
    original_screen: dict[str, Any] = {}
    progress: deque[tuple[float, float]] = deque()
    capture: LogCapture | None = None
    touched = False
    launched = False
    started = None
    try:
        original_settings = adb.settings()
        original_props = adb.properties()
        original_screen = adb.screen_state()
        write_json(output / 'original-state.json', {'settings': original_settings, 'properties': original_props, 'screen': original_screen})
        result['device'] = adb.call(['shell', 'getprop', 'ro.build.fingerprint']).strip()
        result['package'] = adb.call(['shell', 'dumpsys', 'package', PACKAGE])
        result['initial'] = adb.snapshot()
        if result['initial']['batteryC'] is None or result['initial']['vtsC'] is None:
            raise RuntimeError('required-temperature-node-contract-unavailable')
        reason = abort_reason(result['initial'], {})
        if reason:
            raise RuntimeError('initial-temperature-above-stop-threshold:' + reason)
        if args.source_receipt:
            receipt = json.loads(Path(args.source_receipt).read_text())
            if not receipt.get('verified') or receipt.get('serial') != args.serial or receipt.get('deviceSource') != args.source:
                raise RuntimeError('source-receipt-not-verified-or-identity-mismatch')
            result['sourceReceipt'] = receipt
        if args.source_hash:
            identity = adb.source_hash(args.source)
            write_json(output / 'source-identity.json', identity)
            if identity['sha256'] != args.source_hash:
                raise RuntimeError('source-hash-mismatch')
        # Hashing is outside the thermal window; refresh the initial state
        # afterwards so transfer-related warming is not hidden.
        result['initial'] = adb.snapshot()
        if args.reference_start:
            reference = json.loads(Path(args.reference_start).read_text())
            reference = reference.get('initial', reference)
            deadline = time.monotonic() + args.cooldown_timeout
            while True:
                current = adb.snapshot()
                matched = all(current.get(key) is not None and reference.get(key) is not None and
                              abs(current[key] - reference[key]) <= tolerance
                              for key, tolerance in [('batteryC', args.battery_tolerance), ('vtsC', args.vts_tolerance)])
                if matched:
                    result['initial'] = current
                    break
                if time.monotonic() >= deadline:
                    raise RuntimeError('cooldown-temperature-match-timeout')
                print(json.dumps({'phase': 'cooldown', 'batteryC': current['batteryC'], 'vtsC': current['vtsC']}), flush=True)
                time.sleep(min(10, max(0, deadline-time.monotonic())))
        result['initial'] = adb.snapshot()
        if getattr(args, 'instant_enabled', False):
            result['expectedPanelThermalStatus'] = args.expected_panel_thermal_status
            if result['initial']['raw'].get('panel_thermal_status') != args.expected_panel_thermal_status:
                raise RuntimeError('prelaunch-panel-thermal-status-unknown-or-not-approved-normal')
        prelaunch_reason = abort_reason(result['initial'], {})
        if prelaunch_reason:
            raise RuntimeError('prelaunch-temperature-above-threshold:' + prelaunch_reason)
        if args.reference_start:
            for key, tolerance in [('batteryC', args.battery_tolerance), ('vtsC', args.vts_tolerance)]:
                if result['initial'][key] is None or abs(result['initial'][key] - reference[key]) > tolerance:
                    raise RuntimeError('prelaunch-reference-temperature-drift:' + key)
        touched = True
        result['awakeState'] = adb.wake_unprotected(original_screen, args.allow_unprotected_menu)
        for key, value in [('screen_brightness_mode', 0), ('screen_brightness', 255),
                           ('accelerometer_rotation', 0), ('user_rotation', 1),
                           ('screen_off_timeout', int((args.duration + 120) * 1000))]:
            adb.call(['shell', 'settings', 'put', 'system', key, str(value)])
        adb.call(['shell', 'setprop', 'debug.mks.thermal_sync', expected_sync])
        adb.call(['shell', 'setprop', 'debug.mks.defer_publish_flush', expected_defer])
        adb.call(['shell', 'setprop', 'debug.mks.thermal_trace', '1'])
        adb.call(['shell', 'am', 'force-stop', PACKAGE])
        capture = LogCapture(adb, output)
        capture.start()
        launched = True
        result['launchOutput'] = adb.call(['shell', 'am', 'start', '-n', ACTIVITY])
        capture.set_expected_pid(adb.lab_pid())
        if args.tap:
            time.sleep(args.tap_delay)
            adb.call(['shell', 'input', 'tap', str(args.tap[0]), str(args.tap[1])])
        launch_wait_started = time.monotonic()
        result['status'] = 'waiting-for-playback-start'
        with (output / 'samples.ndjson').open('w') as stream:
            while True:
                sample = adb.snapshot()
                state = capture.state()
                if started is None and state.get('playbackStartAt') is not None:
                    started = state['playbackStartAt']
                    result['status'] = 'running'
                sample['elapsedSeconds'] = time.monotonic() - started if started is not None else 0
                sample['launchWaitSeconds'] = time.monotonic() - launch_wait_started
                sample['runtime'] = state
                stream.write(json.dumps(sample) + '\n'); stream.flush()
                result['samples'] += 1
                reason = abort_reason(sample, state)
                if reason:
                    result['status'], result['reason'] = 'aborted', reason
                    break
                if getattr(args, 'instant_enabled', False) and sample['raw'].get('panel_thermal_status') != args.expected_panel_thermal_status:
                    result['status'], result['reason'] = 'invalid', 'panel-thermal-status-unknown-or-not-approved-normal'
                    break
                native_failure = native_failure_reason(state)
                if native_failure:
                    result['status'], result['reason'] = 'invalid', native_failure
                    break
                if state.get('harnessErrors'):
                    result['status'], result['reason'] = 'invalid', 'harness-open-error-see-live-log'
                    break
                if sample['batteryC'] is None or sample['vtsC'] is None:
                    result['status'], result['reason'] = 'invalid', 'required-temperature-node-unavailable'
                    break
                if not state['logcatAlive']:
                    result['status'], result['reason'] = 'invalid', 'logcat-stream-ended'
                    break
                if started is None and sample['launchWaitSeconds'] > 30:
                    result['status'], result['reason'] = 'invalid', 'no-THERMAL_JSON-playback-start-within-30s'
                    break
                if sample['launchWaitSeconds'] > 30 and not sample['pid']:
                    result['status'], result['reason'] = 'invalid', 'hdr-lab-process-missing'
                    break
                if not sample['screen']['on'] or sample['screen']['keyguard'] is not False:
                    result['status'], result['reason'] = 'invalid', 'screen-OFF-or-keyguard-not-cleared'
                    break
                if sample['elapsedSeconds'] > 30:
                    evidence_error = runtime_error(state, expected_sync, sample['pid'], args.source)
                    if evidence_error:
                        result['status'], result['reason'] = 'invalid', evidence_error
                        break
                    if experiment == 'publish-flush':
                        policy_error = publish_policy_error(state, expected_defer)
                        if policy_error:
                            result['status'], result['reason'] = 'invalid', policy_error
                            break
                    if getattr(args, 'instant_enabled', False) and (sample['raw'].get('hdr_mode') != '1' or sample['raw'].get('backlight') != '255'):
                        result['status'], result['reason'] = 'invalid', 'instant-HDR-or-backlight-contract-lost'
                        break
                    position = number(state['lab'].get('properties', {}).get('time-pos'))
                    if position is None:
                        result['status'], result['reason'] = 'invalid', 'time-pos-unavailable'
                        break
                    progress.append((sample['elapsedSeconds'], position))
                    while len(progress) > 1 and progress[1][0] <= sample['elapsedSeconds'] - 30:
                        progress.popleft()
                    if progress and sample['elapsedSeconds'] - progress[0][0] >= 25 and position - progress[0][1] < 1:
                        result['status'], result['reason'] = 'invalid', 'time-pos-stalled-for-30s'
                        break
                if sample['elapsedSeconds'] >= args.duration:
                    result['status'] = 'completed-observation'
                    result['completeWindow'] = True
                    # Runtime route acceptance is separate from time elapsed.
                    result['runtimeEvidenceAvailable'] = state['lab'] is not None and state['labAgeSeconds'] < 30
                    if not result['runtimeEvidenceAvailable']:
                        result['status'] = 'invalid'
                        result['reason'] = 'no-recent-THERMAL_JSON-runtime-evidence'
                        result['completeWindow'] = False
                    break
                write_json(output / 'summary.json', result)
                print(json.dumps({'phase': 'running', 'elapsedSeconds': sample['elapsedSeconds'],
                                  'batteryC': sample['batteryC'], 'vtsC': sample['vtsC'],
                                  'backlight': sample['raw'].get('backlight'), 'labAgeSeconds': state['labAgeSeconds']}), flush=True)
                time.sleep(min(args.interval, max(0, args.duration-sample['elapsedSeconds'])))
        result['final'] = adb.snapshot()
        result['surfaceFlingerFinal'] = adb.call(['shell', 'dumpsys', 'SurfaceFlinger'])
    except KeyboardInterrupt:
        result['status'], result['reason'] = 'aborted', 'interrupted-by-user'
    except Exception as error:
        result['status'], result['reason'] = 'failed', str(error)
    finally:
        # Repeated termination while cleaning up must not skip restoration.
        cleanup_signals = {}
        if threading.current_thread() is threading.main_thread():
            for signum in (signal.SIGTERM, signal.SIGINT):
                cleanup_signals[signum] = signal.signal(signum, signal.SIG_IGN)
        result['observedDurationSeconds'] = time.monotonic() - started if started is not None else 0
        if launched:
            try:
                adb.call(['shell', 'am', 'force-stop', PACKAGE])
                result['hdrLabStopped'] = True
            except Exception as error:
                result['hdrLabStopped'] = False
                result['stopError'] = str(error)
        if capture:
            try:
                capture.close()
            except Exception as error:
                result['logCaptureCloseError'] = str(error)
        try:
            errors = adb.restore(original_settings, original_props) if touched else []
        except Exception as error:
            errors = ['unexpected-restore-error: ' + str(error)]
        if touched and original_screen:
            try:
                key = 'KEYCODE_WAKEUP' if original_screen.get('on') else 'KEYCODE_SLEEP'
                adb.call(['shell', 'input', 'keyevent', key])
                result['restoredScreen'] = adb.screen_state()
                if result['restoredScreen']['on'] != original_screen.get('on'):
                    errors.append('screen-ON/OFF-state-not-restored')
            except Exception as error:
                errors.append('screen-restore-error: ' + str(error))
        result['restoreErrors'] = errors
        try:
            restored_settings, restored_props = adb.settings(), adb.properties()
            result['restoredState'] = {'settings': restored_settings, 'properties': restored_props}
            verified, auto_changed = restoration_matches(original_settings, restored_settings, original_props, restored_props, errors)
            result['restorationVerified'] = verified
            result['automaticBrightnessScalarChanged'] = auto_changed
        except Exception as error:
            result['restorationVerified'], result['restoreReadError'] = False, str(error)
        if errors or result.get('restorationVerified') is False:
            result['completeWindow'] = False
            result['status'] = 'restoration-failed'
        result['finishedAt'] = now()
        write_json(output / 'summary.json', result)
        for signum, handler in cleanup_signals.items():
            signal.signal(signum, handler)
    return result


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--mode', choices=MODES, required=True)
    p.add_argument('--experiment', choices=('sync', 'publish-flush'), default='sync')
    p.add_argument('--duration', type=float, default=360)
    p.add_argument('--interval', type=float, default=10)
    p.add_argument('--tap', type=int, nargs=2, metavar=('X', 'Y'))
    p.add_argument('--tap-delay', type=float, default=3)
    p.add_argument('--allow-unprotected-menu', action='store_true', help='Caller has independently confirmed this LG has no protected lock; never overrides a secure=true report')
    p.add_argument('--source', default='/sdcard/Android/data/com.example.media_kit_hdr_lab/files/hokkaido-p84.mp4')
    source_identity = p.add_mutually_exclusive_group(required=True)
    source_identity.add_argument('--source-hash', help='Freshly stream/hash source before changing settings')
    source_identity.add_argument('--source-receipt', help='Verified local-source.json from a prior full byte read of this exact device/path')
    p.add_argument('--reference-start', help='Previous summary.json or initial sample for matched cooldown')
    p.add_argument('--cooldown-timeout', type=float, default=1800)
    p.add_argument('--battery-tolerance', type=float, default=0.5)
    p.add_argument('--vts-tolerance', type=float, default=1)
    args = p.parse_args()
    if not 30 <= args.duration <= 1200 or not 5 <= args.interval <= 30:
        p.error('duration must be 30..1200 seconds and interval 5..30 seconds')
    if args.source_hash and not re.fullmatch(r'[0-9a-fA-F]{64}', args.source_hash):
        p.error('--source-hash must be SHA-256 hex')
    def terminate(signum, frame):
        raise KeyboardInterrupt('termination-signal-' + str(signum))
    signal.signal(signal.SIGTERM, terminate)
    result = run(args)
    print(json.dumps({k: result.get(k) for k in ['status', 'reason', 'completeWindow', 'observedDurationSeconds', 'restorationVerified']}), flush=True)
    return 0 if result['status'] == 'completed-observation' and result['restorationVerified'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
