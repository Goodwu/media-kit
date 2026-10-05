#!/usr/bin/env python3
"""Bind one opt-in Release diagnostic report to installed APK/lib/source bytes.
Capture success is not playback, performance, or display acceptance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import time
import zipfile

PACKAGE = 'com.example.media_kit_hdr_lab'
SOURCE = '/data/local/tmp/media-kit-lg-dv-p5-2160p.mp4'
REPORT = ('/storage/emulated/0/Android/data/' + PACKAGE +
          '/files/media-kit-hdr-diagnostic/native-dv-release-diagnostic.json')
SOURCE_SHA = 'dacfd04518accd6367530b650dfeea429227df2be171bd99b4bdad36d31bbf9f'
SDR_SOURCE = '/data/local/tmp/media-kit-sdr-control.mp4'
SDR_SHA = '664ad7d5f38db11266a4ee8b9ce650d989548901531d85193d01d1d09f101c44'


def digest_file(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def validate_lifecycle_bounds(report):
    limits = {'segments': 24, 'actionEvents': 128,
              'routeAppliedHistory': 48, 'consumerProofHistory': 48}
    for name, limit in limits.items():
        values = report.get(name)
        if not isinstance(values, list) or len(values) > limit or any(not isinstance(v, dict) for v in values):
            raise ValueError('Invalid lifecycle bounded history: ' + name)
    segment_ids = [s.get('segmentId') for s in report['segments']]
    if any(not isinstance(v, str) or not v for v in segment_ids) or len(set(segment_ids)) != len(segment_ids):
        raise ValueError('Invalid lifecycle segment IDs')
    counts = {v: 0 for v in segment_ids}
    for row in report.get('rows', []):
        if not isinstance(row, dict) or row.get('segmentId') not in counts:
            raise ValueError('Lifecycle row has no segment')
        counts[row['segmentId']] += 1
    for segment in report['segments']:
        count = segment.get('rowCount')
        if type(count) is not int or count != counts[segment['segmentId']]:
            raise ValueError('Lifecycle segment row count differs')
    seconds = report.get('durationLimitSeconds')
    if type(seconds) is not int or not 1 <= seconds <= 900:
        raise ValueError('Invalid lifecycle duration budget')


def expected_report_schema(identity):
    route = identity.get('diagnosticRoute', 'direct')
    mode = identity.get('diagnosticMode', 'healthy')
    if route not in ('direct', 'session') or mode not in ('healthy', 'lifecycle'):
        raise ValueError('Invalid diagnostic route/mode')
    if mode == 'lifecycle' and route != 'session':
        raise ValueError('Lifecycle capture requires Session route')
    return 2 if mode == 'lifecycle' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', default='LGH870DS42e27764')
    parser.add_argument('--apk-identity', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9._:-]+', args.serial):
        raise ValueError('Invalid device serial')
    identity = json.loads(args.apk_identity.read_text())
    expected_schema = expected_report_schema(identity)
    lifecycle = expected_schema == 2
    route = identity.get('diagnosticRoute', 'direct')
    if route not in ('direct', 'session'):
        raise ValueError('Invalid diagnostic route')
    report_path = REPORT if route == 'direct' else REPORT.replace(
        'native-dv-release-diagnostic.json', 'native-dv-session-diagnostic.json')
    for key in ('apkSha256', 'libmpvSha256'):
        if not re.fullmatch(r'[0-9a-f]{64}', identity[key]):
            raise ValueError('Invalid expected hash: ' + key)
    args.output.mkdir(parents=True, exist_ok=False)
    prefix = ['adb', '-s', args.serial]
    started = time.monotonic_ns()
    receipt = {'serial': args.serial, 'startMonotonicNs': started,
               'reportRemotePath': report_path, 'diagnosticRoute': route, 'expectedIdentity': identity,
               'acceptance': 'capture only; no playback/display/performance verdict'}
    try:
        remote = subprocess.check_output(
            prefix + ['shell', 'pm', 'path', PACKAGE], text=True, timeout=15).strip()
        if not remote.startswith('package:/data/app/') or '\n' in remote:
            raise RuntimeError('Expected a single installed base APK')
        with tempfile.TemporaryDirectory(prefix='lg-release-apk-') as tmp:
            local = Path(tmp) / 'installed.apk'
            subprocess.run(prefix + ['pull', remote[8:], str(local)],
                           check=True, timeout=90)
            actual_apk = digest_file(local)
            with zipfile.ZipFile(local) as z:
                actual_lib = hashlib.sha256(
                    z.read('lib/arm64-v8a/libmpv.so')).hexdigest()
        receipt.update(apkSha256=actual_apk, libmpvSha256=actual_lib)
        if actual_apk != identity['apkSha256'] or actual_lib != identity['libmpvSha256']:
            raise RuntimeError('Installed APK/lib differs from expected artifact')
        h = hashlib.sha256()
        receipt['sourceReadStartMonotonicNs'] = time.monotonic_ns()
        with subprocess.Popen(prefix + ['exec-out', 'cat', SOURCE],
                              stdout=subprocess.PIPE) as proc:
            watchdog = threading.Timer(120, proc.kill)
            watchdog.daemon = True
            watchdog.start()
            try:
                for chunk in iter(lambda: proc.stdout.read(1024 * 1024), b''):
                    h.update(chunk)
                if proc.wait() != 0:
                    raise RuntimeError('Source read failed or exceeded 120 seconds')
            finally:
                watchdog.cancel()
        receipt['sourceReadEndMonotonicNs'] = time.monotonic_ns()
        receipt['sourceSha256'] = h.hexdigest()
        if h.hexdigest() != SOURCE_SHA:
            raise RuntimeError('Original official P5 source differs')
        receipt['reportReadStartMonotonicNs'] = time.monotonic_ns()
        raw = subprocess.check_output(prefix + ['exec-out', 'cat', report_path], timeout=15)
        (args.output / 'app-report.json').write_bytes(raw)
        receipt['reportReadEndMonotonicNs'] = time.monotonic_ns()
        report = json.loads(raw)
        if type(report.get('schema')) is not int or report.get('schema') != expected_schema or report.get('diagnosticOnly') is not True:
            raise RuntimeError('Unexpected report schema/mode')
        if route == 'session' and report.get('diagnosticRoute') != 'session':
            raise RuntimeError('Expected a real Session diagnostic report')
        if lifecycle:
            if route != 'session' or report.get('diagnosticMode') != 'lifecycle':
                raise RuntimeError('Expected lifecycle Session report')
            # Independently read the second fixed asset, never trust app SHA labels.
            sdr_raw = subprocess.check_output(prefix + ['exec-out', 'cat', SDR_SOURCE], timeout=30)
            actual_sdr = hashlib.sha256(sdr_raw).hexdigest()
            receipt['sdrSourceSha256'] = actual_sdr
            receipt['sdrSourceBytes'] = len(sdr_raw)
            if actual_sdr != SDR_SHA:
                raise RuntimeError('Fixed SDR control differs')
        label = identity.get('diagnosticIdentityLabel')
        if not isinstance(label, str) or not label or report.get('externalIdentityLabel') != label:
            raise RuntimeError('Report candidate label differs from expected artifact')
        run_id = report.get('runId')
        if not isinstance(run_id, str) or not run_id:
            raise RuntimeError('Report has no unique run ID')
        receipt['reportRunId'] = run_id
        receipt['reportStartUtc'] = report.get('startUtc')
        if report.get('sourcePath') != SOURCE:
            raise RuntimeError('Report belongs to another source')
        rows = report.get('rows')
        if not isinstance(rows, list) or len(rows) > 300 or type(report.get('rowCount')) is not int or report.get('rowCount') != len(rows):
            raise RuntimeError('Invalid report row count')
        if lifecycle:
            validate_lifecycle_bounds(report)
        # App-supplied SHA labels deliberately remain untrusted in app-report.
        receipt.update(reportSha256=hashlib.sha256(raw).hexdigest(),
                       reportPhase=report.get('phase'), reportError=report.get('error'),
                       rowCount=len(rows), captureVerified=True)
    except BaseException as error:
        receipt.update(captureVerified=False, error=repr(error))
        raise
    finally:
        receipt['endMonotonicNs'] = time.monotonic_ns()
        (args.output / 'capture-receipt.json').write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: receipt.get(key) for key in
                     ('captureVerified', 'rowCount', 'reportPhase', 'reportError')},
                     ensure_ascii=False))


if __name__ == '__main__':
    main()
