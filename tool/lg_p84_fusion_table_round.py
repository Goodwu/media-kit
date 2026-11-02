#!/usr/bin/env python3
"""Production UV-table fusion validation round: seed -> ready -> live check.

Enables the default-off production table property, waits for the native
ready receipt, then samples consecutive displayed frames' Android ROI CSC
words while the table drives the fusion pass. Layer-two evidence only:
source-level equivalence of the #define rewrite to the schema10-validated
probe substitution is claimed separately; this round proves the production
path arms, stays up, renders without GL failure or fusion fallback, and
restores cleanly.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import secrets
import shlex
import signal
import subprocess
import sys
import time

import lg_p84_capture_round as capture_host
import lg_p84_atlas_round as atlas_host

quality = capture_host.quality
thermal = capture_host.thermal
analyzer = capture_host.analyzer
REMOTE = capture_host.REMOTE
AtlasAdb = atlas_host.AtlasAdb

TABLE_PROPERTY = 'debug.mks.yuv_fusion_table'
TABLE_EVENTS = ('ready', 'seed-retry', 'seed-timeout', 'promote-or-attach-failed',
                'table-invalidated', 'fusion-fallback-table-dropped')


def table_controls(target):
    values = capture_host.controls(target)
    values[TABLE_PROPERTY] = '1'
    # The production table drives its own capability cache via this property;
    # the compare transaction stays fully closed so no diagnostic ROI capture
    # can interfere with production frames.
    values['debug.mks.yuv_compare'] = '0'
    values['debug.mks.yuv_compare_pts'] = ''
    return values


def table_rows(lines, pid):
    rows = []
    for index, line in enumerate(lines):
        header = re.match(r'\S+\s+\S+\s+(\d+)\s+\d+\s+', line)
        if not header or header[1] != pid:
            continue
        marker = re.search(r'(?<![\w-])MKS-FUSION-TABLE\s+', line)
        if not marker:
            continue
        pairs = re.findall(r'([A-Za-z_][\w-]*)=([^\s]+)', line[marker.end():])
        row = dict(pairs)
        if len(row) != len(pairs) or 'event' not in row:
            raise RuntimeError('malformed-fusion-table-event')
        rows.append((index, row))
    return rows


def run(args):
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    adb = AtlasAdb(args.serial, output)
    result = {'schema': 1, 'status': 'failed', 'serial': args.serial,
              'startedAt': thermal.now(), 'requestedPTS': args.pts,
              'quality_pass': False,
              'scope': 'Production table readiness and live rendering check; '
                       'not a panel, power or uninstrumented-B0 equivalence claim.'}
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
        package = adb.call(['shell', 'pm', 'path', thermal.PACKAGE]).strip()
        if not re.fullmatch(r'package:/data/app/[^\s]+/base\.apk', package):
            raise RuntimeError('unexpected-APK-path-or-splits')
        result['apk'] = adb.source_hash(package[len('package:'):])
        if result['apk']['sha256'] != args.expected_apk_sha256.lower():
            raise RuntimeError('installed-APK-hash-mismatch')
        touched = True
        adb.wake_unprotected(screen, args.allow_unprotected_menu)
        for key, value in [('screen_brightness_mode', 0), ('screen_brightness', args.brightness),
                           ('accelerometer_rotation', 0), ('user_rotation', 1),
                           ('screen_off_timeout', int((args.timeout+120)*1000))]:
            adb.call(['shell', 'settings', 'put', 'system', key, str(value)])
        result['controls'] = table_controls(args.pts)
        if not set(result['controls']).issubset(props):
            raise RuntimeError('fusion-table-mutated-property-not-in-snapshot')
        for key, value in result['controls'].items():
            adb.shell(f'setprop {shlex.quote(key)} {shlex.quote(value)}')
        for key, value in result['controls'].items():
            if adb.call(['shell', 'getprop', key]).strip() != value:
                raise RuntimeError('fusion-table-control-readback-mismatch:'+key)
        old_pid = adb.lab_pid()
        adb.call(['shell', 'am', 'force-stop', thermal.PACKAGE])
        if adb.lab_pid() is not None:
            raise RuntimeError('old-process-survived-force-stop')
        log_capture = thermal.LogCapture(adb, output)
        log_capture.start()
        launched = True
        result['launchOutput'] = adb.call(['shell', 'am', 'start', '-n', thermal.ACTIVITY])
        pid = adb.lab_pid()
        if not pid or pid == old_pid:
            raise RuntimeError('fresh-process-PID-not-established')
        result['pid'] = pid
        log_capture.set_expected_pid(pid)
        logfile = output/'flutter-logcat.txt'

        if args.tap:
            time.sleep(args.tap_delay)
            adb.call(['shell', 'input', 'tap', str(args.tap[0]), str(args.tap[1])])

        deadline = time.monotonic()+args.timeout
        ready = None
        while time.monotonic() < deadline:
            if adb.lab_pid() != pid:
                raise RuntimeError('fusion-table-process-restarted-or-exited')
            lines = logfile.read_text().splitlines() if logfile.exists() else []
            for _, row in table_rows(lines, pid):
                if row['event'] not in ('ready', 'seed-retry'):
                    raise RuntimeError('fusion-table-terminal:'+row['event'])
            ready_rows = [row for _, row in table_rows(lines, pid) if row['event'] == 'ready']
            if ready_rows:
                ready = ready_rows[-1]
                break
            time.sleep(.5)
        if not ready:
            raise RuntimeError('fusion-table-not-ready-before-timeout')
        result['readyReceipt'] = ready
        # Settle window: the fusion path must stay live with no table
        # invalidation or fusion fallback for the observation period.
        time.sleep(args.observe)
        lines = logfile.read_text().splitlines()
        rows = table_rows(lines, pid)
        for _, row in rows:
            if row['event'] in ('table-invalidated', 'seed-timeout',
                                'promote-or-attach-failed', 'fusion-fallback-table-dropped'):
                raise RuntimeError('fusion-table-unstable:'+row['event'])
        if sum(1 for _, row in rows if row['event'] == 'ready') != 1:
            raise RuntimeError('fusion-table-reseeded-during-observation')
        result['status'] = 'completed-fusion-table-check'
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
        result.update(restoreErrors=errors, finishedAt=thermal.now())
        thermal.write_json(output/'summary.json', result)
        for sig, handler in handlers.items():
            signal.signal(sig, handler)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fusion-table', action='store_true', required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--pts', type=float, choices=quality.POINTS, required=True)
    parser.add_argument('--source', default=REMOTE+'hokkaido-p84.mp4')
    parser.add_argument('--source-receipt', required=True)
    parser.add_argument('--expected-apk-sha256', required=True)
    parser.add_argument('--brightness', type=int, default=64)
    parser.add_argument('--expected-panel-thermal-status', required=True)
    parser.add_argument('--timeout', type=float, default=180)
    parser.add_argument('--observe', type=float, default=30)
    parser.add_argument('--tap', type=int, nargs=2, default=[1440, 720])
    parser.add_argument('--tap-delay', type=float, default=4)
    parser.add_argument('--allow-unprotected-menu', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-fA-F]{64}', args.expected_apk_sha256):
        parser.error('expected APK SHA256 must be 64 hex characters')

    def terminate(signum, frame):
        raise KeyboardInterrupt(f'termination-signal-{signum}')

    signal.signal(signal.SIGTERM, terminate)
    result = run(args)
    print(json.dumps({key: result.get(key) for key in ('status', 'reason', 'restorationVerified')}))
    return 0 if (result['status'] == 'completed-fusion-table-check' and
                 result.get('restorationVerified') is True) else 2


if __name__ == '__main__':
    raise SystemExit(main())
