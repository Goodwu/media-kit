#!/usr/bin/env python3
"""Default-off same-player seed/read1 -> host ACK -> seek/read2 diagnostic.

No APK build/install, no production enablement. Full-screen instrumented UV/
half RGB is measured; uninstrumented B0 and full YUV equality are unmeasured.
"""
from __future__ import annotations
import argparse
import copy
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

import lg_p84_atlas_round as atlas

capture_host, quality, thermal, analyzer = atlas.capture_host, atlas.quality, atlas.thermal, atlas.analyzer
REMOTE = atlas.REMOTE
REUSE = capture_host.ATLAS_REUSE_PROPERTY
PTS2 = capture_host.ATLAS_PTS2_PROPERTY
NONCE = capture_host.ATLAS_NONCE_PROPERTY
ACK = capture_host.ATLAS_ACK_PROPERTY
HANDSHAKE_KEYS = ('nonce','cache_id','cache_generation','renderer_id','renderer_generation',
                  'signature','seed_capture_id','seed_pts','t2_pts','stage','ordinal')
READ_EVENTS = ('seed-promoted','armed','capture-complete','capture-diagnostic-invalid',
               'promoted-ready','ack-accepted','capture-failed','config-invalid','cleanup-deferred')
AtlasAdb = atlas.AtlasAdb


def controls(first, second, nonce):
    if (not re.fullmatch('[0-9a-f]{32}', nonce) or first not in quality.POINTS or
            second not in quality.POINTS or abs(first-second) <= 2e-6):
        raise ValueError('two distinct preset PTS and a fresh 32-lowerhex nonce required')
    return {**atlas.controls(first), REUSE:'1', PTS2:str(second), NONCE:nonce, ACK:''}


def read_rows(lines, pid):
    rows = []
    for index, line in enumerate(lines):
        header = re.match(r'\S+\s+\S+\s+(\d+)\s+\d+\s+', line)
        if not header or header[1] != pid:
            continue
        marker = re.search(r'(?<![\w-])(MKS-UV-ATLAS-READ(?:-LIB)?)\s+', line)
        if not marker:
            continue
        pairs = re.findall(r'([A-Za-z_][\w-]*)=([^\s]+)', line[marker.end():])
        row = dict(pairs)
        if len(row) != len(pairs) or 'event' not in row:
            raise RuntimeError('malformed-atlas-read-event')
        rows.append((index, marker[1], row))
    diagnostics = [{'logIndex': i, 'prefix': p, **r} for i,p,r in rows]
    for _, prefix, row in rows:
        if prefix == 'MKS-UV-ATLAS-READ' and row['event'] in ('capture-failed','config-invalid','cleanup-deferred'):
            raise capture_host.NativeCaptureFailure(prefix, row, diagnostics)
    if any(prefix != 'MKS-UV-ATLAS-READ' or row['event'] not in READ_EVENTS for _,prefix,row in rows):
        raise RuntimeError('unknown-atlas-read-event')
    return rows


def handshake(row, nonce, first, second):
    if row.get('nonce') != nonce or row.get('stage') != '1' or row.get('ordinal') != '1':
        raise RuntimeError('atlas-handshake-session-or-stage-mismatch')
    for key in ('cache_id','cache_generation','renderer_id','renderer_generation','seed_capture_id'):
        if not capture_host.positive(row.get(key)) or int(row[key]) > 2**64-1:
            raise RuntimeError('atlas-handshake-identity-invalid:'+key)
    if not re.fullmatch('[0-9a-f]{64}', row.get('signature','')):
        raise RuntimeError('atlas-handshake-signature-invalid')
    for key,target in (('seed_pts',first),('t2_pts',second)):
        try:
            value = float(row.get(key,'nan'))
        except ValueError:
            value = float('nan')
        if not capture_host.exact_pts(value, target):
            raise RuntimeError('atlas-handshake-PTS-mismatch:'+key)
    return {key:row[key] for key in HANDSHAKE_KEYS}


def evidence(lines, pid, targets, nonce, seek_indices, acked=False):
    rows = read_rows(lines,pid)
    promoted = [(i,r) for i,_,r in rows if r['event'] == 'seed-promoted']
    ready = [(i,r) for i,_,r in rows if r['event'] == 'promoted-ready']
    accepted = [(i,r) for i,_,r in rows if r['event'] == 'ack-accepted']
    if any(len(values) > 1 for values in (promoted,ready,accepted)):
        raise RuntimeError('duplicate-atlas-promotion-or-ACK')
    if accepted and (not acked or not ready or accepted[0][0] <= ready[0][0]):
        raise RuntimeError('atlas-native-ACK-before-current-host-ACK')
    result = {'stages':{}}
    if promoted:
        index,row = promoted[0]
        if (not seek_indices or index <= seek_indices[0] or row.get('nonce') != nonce or
                any(not capture_host.positive(row.get(key)) for key in ('seed_capture_id','cache_id','cache_generation'))):
            raise RuntimeError('atlas-seed-promotion-identity-mismatch')
        try:
            pts = float(row.get('seed_pts','nan'))
        except ValueError:
            pts = float('nan')
        if not capture_host.exact_pts(pts,targets[0]):
            raise RuntimeError('atlas-seed-promotion-PTS-mismatch')
        result['seedPromoted'] = row
    for ordinal in (1,2):
        arms = [(i,r) for i,_,r in rows if r['event'] == 'armed' and r.get('ordinal') == str(ordinal)]
        ends = [(i,r) for i,_,r in rows if r['event'] in ('capture-complete','capture-diagnostic-invalid') and r.get('ordinal') == str(ordinal)]
        if len(arms) > 1 or len(ends) > 1:
            raise RuntimeError('multiple-atlas-read-transactions')
        if arms:
            index,arm = arms[0]
            if (len(seek_indices) < ordinal or index <= seek_indices[ordinal-1] or not promoted or index <= promoted[0][0] or
                    (ordinal == 2 and (not acked or not accepted or index <= accepted[0][0])) or
                    arm.get('android') != '1' or arm.get('lib') != '1' or
                    any(not capture_host.positive(arm.get(key)) for key in ('id','generation','cache_id')) or
                    arm.get('cache_id') != promoted[0][1]['cache_id']):
                raise RuntimeError('atlas-read-arm-identity-or-seek-mismatch')
        if not ends:
            continue
        index,end = ends[0]
        if (not arms or index <= arms[0][0] or
                any(end.get(key) != arms[0][1].get(key) for key in ('id','generation','cache_id','source_pts'))):
            raise RuntimeError('atlas-read-endpoint-without-current-arm')
        try:
            pts = float(end.get('source_pts','nan'))
        except ValueError:
            pts = float('nan')
        diagnostic = end['event'] == 'capture-diagnostic-invalid'
        basename = f'mks-uv-atlas-read-{pid}-{end["id"]}'+('.diagnostic-invalid' if diagnostic else '')
        mask = end.get('read_validation_mask','')
        if (not capture_host.exact_pts(pts,targets[ordinal-1]) or end.get('file') != REMOTE+basename+'.json' or
                end.get('comparison_pass') != ('refused' if diagnostic else 'unknown') or
                mask not in (('1','2','3') if diagnostic else ('0',))):
            raise RuntimeError('atlas-read-endpoint-PTS-path-or-scope-mismatch')
        result['stages'][ordinal] = end
    if any(row['event'] in ('armed','capture-complete','capture-diagnostic-invalid') and row.get('ordinal') not in ('1','2') for _,_,row in rows):
        raise RuntimeError('invalid-atlas-read-ordinal')
    if ready:
        index,row = ready[0]
        receipt = handshake(row,nonce,*targets)
        first = result['stages'].get(1)
        if (not first or first['event'] != 'capture-complete' or not promoted or
                index <= next(i for i,_,r in rows if r is first) or
                any(row[key] != promoted[0][1].get(key) for key in ('cache_id','cache_generation','seed_capture_id','nonce','seed_pts'))):
            raise RuntimeError('atlas-promotion-ready-before-valid-first-read')
        result['promotion'] = receipt
    if accepted:
        receipt = handshake(accepted[0][1],nonce,*targets)
        if receipt != result.get('promotion'):
            raise RuntimeError('atlas-native-ACK-identity-changed')
        if len(seek_indices) == 2 and accepted[0][0] >= seek_indices[1]:
            raise RuntimeError('second-seek-before-native-ACK')
        result['accepted'] = receipt
    return result


def validate_manifest(manifest,event,pid,target,ordinal,seed_root):
    analyzer.atlas_read_metadata(manifest)
    diagnostic = event['event'] == 'capture-diagnostic-invalid'
    for key,expected in (('pid',int(pid)),('capture_id',int(event['id'])),('generation',int(event['generation'])),
                         ('cache_id',int(event['cache_id'])),('ordinal',ordinal),('read_validation_mask',int(event['read_validation_mask']))):
        if type(manifest.get(key)) is not int or manifest[key] != expected:
            raise RuntimeError('atlas-read-manifest-identity-mismatch:'+key)
    if manifest['status'] != ('diagnostic-invalid' if diagnostic else 'complete') or manifest['signature'] != event.get('signature'):
        raise RuntimeError('atlas-read-manifest-endpoint-status-or-signature-mismatch')
    for key in ('source_pts','current_pts','target_pts'):
        if not capture_host.exact_pts(manifest[key],target):
            raise RuntimeError('atlas-read-manifest-requested-PTS-mismatch:'+key)
    w,h = min(64,manifest['width']),min(64,manifest['height'])
    if manifest['android_roi'] != {'x':(manifest['width']-w)//2,'y':(manifest['height']-h)//2,'w':w,'h':h}:
        raise RuntimeError('atlas-read-Android-ROI-not-fixed-center')
    basename = f'mks-uv-atlas-read-{pid}-{event["id"]}'+('.diagnostic-invalid' if diagnostic else '')
    expected = {key:basename+suffix for key,suffix in analyzer.ATLAS_READ_SUFFIXES.items()}
    if manifest.get('files') != expected:
        raise RuntimeError('atlas-read-manifest-file-identity-mismatch')
    reference = manifest['seed_reference']
    seed = analyzer.safe_file(Path(seed_root),reference['manifest'])
    if hashlib.sha256(seed.read_bytes()).hexdigest() != reference['sha256']:
        raise RuntimeError('atlas-read-seed-manifest-hash-mismatch')
    return expected


PAIR_CODE = '''import json,sys
from pathlib import Path
sys.path.insert(0,sys.argv[1])
import analyze_lg_yuv_capture as a
try:
 r=a.validate_atlas_read_pair(Path(sys.argv[2]),Path(sys.argv[3]),Path(sys.argv[4]));code=0
except (a.InvalidCapture,OSError) as e:
 r={'status':'invalid-capture','reason':str(e),'quality_pass':False};code=2
with open(sys.argv[5],'x') as out:json.dump(r,out,allow_nan=False)
sys.exit(code)
'''


def run_analysis(command,path,directory,guard):
    before = hashlib.sha256(Path(analyzer.__file__).read_bytes()).hexdigest()
    with (directory/(path.stem+'.stdout')).open('wb') as stdout, (directory/(path.stem+'.stderr')).open('wb') as stderr:
        proc = subprocess.Popen(command,stdout=stdout,stderr=stderr)
        try:
            while proc.poll() is None:
                guard();time.sleep(.2)
            guard()
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill();proc.wait(timeout=2)
    if hashlib.sha256(Path(analyzer.__file__).read_bytes()).hexdigest() != before:
        raise RuntimeError('atlas-analyzer-source-changed-during-transaction')
    result = analyzer.load_json(path)
    if proc.returncode == 2 and result.get('status') == 'invalid-capture':
        raise analyzer.InvalidCapture(result.get('reason','atlas-read-invalid'),result.get('diagnostic'))
    if (proc.returncode,result.get('status')) not in ((0,'captured-floats-bit-equal'),(3,'diagnostic-invalid')):
        raise RuntimeError('atlas-read-analyzer-exit-or-status-mismatch')
    if result.get('quality_pass') is not False:
        raise RuntimeError('atlas-read-analyzer-quality-scope-mismatch')
    return result


def collect_read(adb,event,pid,target,ordinal,seed_root,directory,guard):
    directory.mkdir(exist_ok=False)
    guard();raw = adb.read_file(event['file'],32*1024)
    path = directory/Path(event['file']).name;path.write_bytes(raw)
    manifest = analyzer.load_json(path)
    files = validate_manifest(manifest,event,pid,target,ordinal,seed_root)
    sizes = {key:manifest['rgba_words']*4 for key in ('a0','uv','half')}
    sizes.update(seed_atlas=manifest['atlas_words']*4,android=manifest['android_words']*4,
                 baseline_vertices=manifest['vertex_layout']['byte_size'])
    receipts = {}
    for key,name in files.items():
        guard()
        maximum = sizes[key] if key in sizes else 256*1024 if key in ('original_body','seed_material','current_material') else 4*1024*1024
        data = adb.read_file(REMOTE+name,maximum);(directory/name).write_bytes(data)
        if not data or len(data) > maximum or (key in sizes and len(data) != maximum):
            raise RuntimeError('atlas-read-payload-byte-size-mismatch:'+key)
        receipts[key] = {'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    for key,name in files.items():
        guard();data = adb.read_file(REMOTE+name,receipts[key]['bytes'])
        if len(data) != receipts[key]['bytes'] or hashlib.sha256(data).hexdigest() != receipts[key]['sha256']:
            raise RuntimeError('atlas-read-file-changed:'+key)
    guard()
    if adb.read_file(event['file'],32*1024) != raw:
        raise RuntimeError('atlas-read-manifest-changed')
    thermal.write_json(directory/'collection.json',{'files':receipts,'manifestSha256':hashlib.sha256(raw).hexdigest(),
        'identityScope':'Fresh PID/current stage endpoint and exclusive filenames; raw payloads carry no embedded frame identity.',
        'timestampScope':'Log receive order is correlation only, not synchronized native/hardware timing.'})
    analysis_path = directory/'analysis.json'
    command = [sys.executable,str(Path(analyzer.__file__).resolve()),str(path),'--seed-root',str(seed_root),'--output',str(analysis_path)]
    analysis = run_analysis(command,analysis_path,directory,guard)
    diagnostic = event['event'] == 'capture-diagnostic-invalid'
    if (analysis['status'] != ('diagnostic-invalid' if diagnostic else 'captured-floats-bit-equal') or
            analysis.get('cross_pts_reuse_validated') is not False or
            analysis.get('yuv_equality_measured') is not False or
            analysis.get('b0_numerical_equivalence_established') is not False):
        raise RuntimeError('atlas-read-analysis-endpoint-or-scope-mismatch')
    return path,manifest,analysis


def verify_pair(first,second,seed_root,output,guard):
    path = output/'pair-analysis.json'
    command = [sys.executable,'-c',PAIR_CODE,str(Path(analyzer.__file__).parent),str(first),str(second),str(seed_root),str(path)]
    result = run_analysis(command,path,output,guard)
    if result.get('cross_pts_reuse_validated') is not True or result.get('yuv_equality_measured') is not False:
        raise RuntimeError('atlas-read-pair-did-not-validate-scoped-reuse')
    return result


def bind_promotion(promotion,seed_manifest,read_manifest):
    mapping = {'cache_id':'cache_id','cache_generation':'cache_generation','renderer_id':'renderer_id',
               'renderer_generation':'renderer_generation','signature':'signature','seed_capture_id':'seed_capture_id'}
    if any(promotion[key] != str(read_manifest[value]) for key,value in mapping.items()):
        raise RuntimeError('atlas-promotion-does-not-match-first-archive')
    if (read_manifest['seed_capture_id'] != seed_manifest['capture_id'] or
            not capture_host.exact_pts(float(promotion['seed_pts']),seed_manifest['source_pts'])):
        raise RuntimeError('atlas-promotion-does-not-match-seed')


def validate_runner(rows,pid,run_id,nonce,owner,promotion):
    selected = [row for row in rows if row.get('runId') == run_id]
    if (not selected or any(str(row.get('pid')) != pid or row.get('nonce') != nonce or row.get('owner') != owner for row in selected) or
            any(row.get('status') in ('failed','cancelled') for row in selected) or
            selected[-1].get('status') != 'awaiting-host-ack' or
            selected[-1].get('promotion') != promotion):
        raise RuntimeError('atlas-lab-runner-not-currently-awaiting-valid-host-ACK')
    return selected[-1]


def collect_seed(adb, pid, promotion, directory, guard):
    """Pull and independently analyze the promoted schema9 seed archive."""
    name = f"mks-yuv-atlas-{pid}-{promotion['seed_capture_id']}"
    target = float(promotion['seed_pts'])
    event = {'event': 'capture-complete', 'id': promotion['seed_capture_id'],
             'generation': promotion['cache_generation'],
             'file': REMOTE+name+'.json', 'comparison_pass': 'unknown'}
    return atlas.collect(adb, event, pid, target, directory, guard)


def load_runner_rows(adb, pid, guard):
    # The atlas-reuse runner (nonce/promotion rows) writes its own ndjson;
    # the quality probe's p84-quality file has no nonce field.
    disk = REMOTE+f'p84-atlas-reuse-{pid}.ndjson'
    guard()
    text = adb.call(['exec-out', 'cat', disk])
    rows = [json.loads(line) for line in text.splitlines() if line.strip()]
    guard()
    return rows


def run(args):
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    adb = AtlasAdb(args.serial, output)
    nonce = args.nonce or secrets.token_hex(16)
    result = {'schema': 1, 'status': 'failed', 'serial': args.serial, 'startedAt': thermal.now(),
              'requestedPTS': [args.first, args.second], 'nonce': nonce,
              'quality_pass': False, 'production_equivalence_established': False,
              'displayControls': {'brightness': args.brightness, 'expectedBacklight': args.expected_backlight,
                                  'expectedPanelThermalStatus': args.expected_panel_thermal_status},
              'scope': 'One default-off same-player seed/read1->ACK->seek/read2 diagnostic; '
                       'no production enablement, uninstrumented B0, YUV, panel or power acceptance.'}
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
        result['controls'] = controls(args.first, args.second, nonce)
        if not set(result['controls']).issubset(props):
            raise RuntimeError('atlas-reuse-mutated-property-not-in-snapshot')
        for key, value in result['controls'].items():
            # An empty value must survive the device shell; adb.call with ''
            # drops the argument and setprop fails with "Need 2 arguments".
            adb.shell(f'setprop {shlex.quote(key)} {shlex.quote(value)}')
        for key, value in result['controls'].items():
            if adb.call(['shell', 'getprop', key]).strip() != value:
                raise RuntimeError('atlas-reuse-control-readback-mismatch:'+key)
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
                raise RuntimeError('atlas-reuse-process-restarted-or-exited')
            state = log_capture.state()
            if state.get('logcatAlive') is not True:
                raise RuntimeError('atlas-reuse-logcat-exited')
            # Terminal errors remain sticky even while pulling the large
            # full-screen archives or running the offline analysis.
            live_lines = logfile.read_text().splitlines() if logfile.exists() else []
            read_rows(live_lines, pid)
            sample = adb.snapshot()
            quality.thermal_gate(sample, state, args.expected_panel_thermal_status,
                                 args.expected_backlight if brightness else None)
            with (output/'samples.ndjson').open('a') as out:
                out.write(json.dumps(sample)+'\n')
            adb.remaining(15)

        if args.tap:
            # The lab test page needs one manual tap to open the local source;
            # the seek/native transactions only start after playback begins.
            until = time.monotonic()+args.tap_delay
            while time.monotonic() < until:
                guard(False)
                time.sleep(min(.2, max(0, until-time.monotonic())))
            adb.call(['shell', 'input', 'tap', str(args.tap[0]), str(args.tap[1])])

        def check_seeks(lines):
            starts = [(i, row) for i, row in quality.quality_rows(lines, pid)
                      if row.get('status') == 'seek-started']
            if len(starts) > 2:
                raise RuntimeError('unexpected-quality-seek-in-atlas-reuse')
            for number, (index, row) in enumerate(starts, 1):
                if (row.get('ordinal') != number or row.get('requestedPTS') != (args.first, args.second)[number-1] or
                        row.get('requestedFusionMode') != '1' or not isinstance(row.get('runId'), str) or
                        not row['runId'].startswith(pid+':') or row['runId'] != starts[0][1]['runId']):
                    raise RuntimeError('atlas-reuse-quality-seek-identity-mismatch')
            if any(row.get('status') in ('failed', 'cancelled', 'invalidated')
                   for _, row in quality.quality_rows(lines, pid)):
                raise RuntimeError('atlas-reuse-quality-observation-invalidated')
            return [index for index, _ in starts]

        def stage_rows(lines, ordinal):
            return [(i, r) for i, _, r in read_rows(lines, pid)
                    if r['event'] in ('capture-complete', 'capture-diagnostic-invalid')
                    and r.get('ordinal') == str(ordinal)]

        seed_root = stage1 = stage2 = promotion = accepted = None
        while True:
            guard(False)
            lines = logfile.read_text().splitlines() if logfile.exists() else []
            indices = check_seeks(lines)
            rows = read_rows(lines, pid)
            ready = [(i, r) for i, _, r in rows if r['event'] == 'promoted-ready']
            accepted_rows = [(i, r) for i, _, r in rows if r['event'] == 'ack-accepted']
            ends1 = [(i, r) for i, r in stage_rows(lines, 1)]
            ends2 = [(i, r) for i, r in stage_rows(lines, 2)]
            if not ready:
                time.sleep(.5)
                continue
            if promotion is None:
                promotion = handshake(ready[0][1], nonce, args.first, args.second)
                if not indices or ready[0][0] <= indices[0]:
                    raise RuntimeError('atlas-reuse-promotion-before-first-seek')
                # The analyzer requires the complete schema9 seed on disk
                # before either stage archive can be validated.
                seed_root = output/'seed'
                # Paused-wait phases: the panel deterministically leaves HDR
                # during the long still wait, so collection/analysis guards
                # only check thermal health; the HDR/backlight contract stays
                # enforced while playback is actually running.
                quiet_guard = lambda: guard(False)
                collect_seed(adb, pid, promotion, seed_root, quiet_guard)
                seed_manifest = analyzer.load_json(
                    seed_root/f"mks-yuv-atlas-{pid}-{promotion['seed_capture_id']}.json")
            if not ends1:
                time.sleep(.5)
                continue
            if stage1 is None:
                if ends1[0][1]['event'] != 'capture-complete':
                    raise RuntimeError('atlas-reuse-first-stage-diagnostic-invalid')
                stage1_path, manifest, stage1 = collect_read(adb, ends1[0][1], pid, args.first, 1,
                                                             seed_root, output/'stage1', quiet_guard)
                bind_promotion(promotion, seed_manifest, manifest)
                # The lab runner must still be awaiting this exact promotion
                # before the host writes the one-shot ACK property.
                runner_rows = load_runner_rows(adb, pid, quiet_guard)
                mine = [row for row in runner_rows if row.get('nonce') == nonce]
                if not mine:
                    raise RuntimeError('atlas-reuse-lab-runner-rows-missing')
                validate_runner(runner_rows, pid, mine[0].get('runId'), nonce,
                                mine[0].get('owner'), promotion)
                ack = f"{nonce}:{promotion['cache_id']}"
                adb.call(['shell', 'setprop', ACK, ack])
                if adb.call(['shell', 'getprop', ACK]).strip() != ack:
                    raise RuntimeError('atlas-reuse-ack-readback-mismatch')
                result['ackWritten'] = ack
            if not accepted_rows:
                time.sleep(.5)
                continue
            accepted = handshake(accepted_rows[0][1], nonce, args.first, args.second)
            if accepted != promotion:
                raise RuntimeError('atlas-reuse-native-ACK-identity-changed')
            if not ends2:
                time.sleep(.5)
                continue
            if stage2 is None:
                if ends2[0][1]['event'] != 'capture-complete':
                    raise RuntimeError('atlas-reuse-second-stage-diagnostic-invalid')
                stage2_path, manifest, stage2 = collect_read(adb, ends2[0][1], pid, args.second, 2,
                                                             seed_root, output/'stage2', quiet_guard)
                final_lines = logfile.read_text().splitlines()
                final_indices = check_seeks(final_lines)
                result['evidence'] = evidence(final_lines, pid, [args.first, args.second],
                                              nonce, final_indices, acked=True)
                result['pair'] = verify_pair(stage1_path, stage2_path, seed_root, output, quiet_guard)
                result['stage1'] = {'ordinal': 1, 'status': stage1['status'],
                                    'signature': stage1['signature']}
                result['stage2'] = {'ordinal': 2, 'status': stage2['status'],
                                    'signature': stage2['signature']}
                result['status'] = 'completed-atlas-reuse'
            break
    except KeyboardInterrupt:
        result['reason'] = 'interrupted'
    except Exception as error:
        result['reason'] = str(error)
        if isinstance(error, capture_host.NativeCaptureFailure):
            result.update(nativeFailure=error.fields, nativeDiagnostics=error.diagnostics)
        if isinstance(error, analyzer.InvalidCapture) and getattr(error, 'diagnostic', None) is not None:
            result['analyzerDiagnostic'] = error.diagnostic
    finally:
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
        result.update(restoreErrors=errors, finishedAt=thermal.now())
        thermal.write_json(output/'summary.json', result)
        for sig, handler in handlers.items():
            signal.signal(sig, handler)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--atlas-reuse', action='store_true', required=True,
                        help='Explicit opt-in; one seed/read1/ACK/read2 transaction only.')
    parser.add_argument('--serial', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--first', type=float, choices=quality.POINTS, required=True)
    parser.add_argument('--second', type=float, choices=quality.POINTS, required=True)
    parser.add_argument('--nonce', help='Fresh 32-lowerhex nonce; generated when omitted.')
    parser.add_argument('--source', default=REMOTE+'hokkaido-p84.mp4')
    parser.add_argument('--source-receipt', required=True)
    parser.add_argument('--expected-apk-sha256', required=True)
    parser.add_argument('--brightness', type=int, default=64)
    parser.add_argument('--expected-backlight', type=int, default=64)
    parser.add_argument('--expected-panel-thermal-status', required=True)
    parser.add_argument('--timeout', type=float, default=600)
    parser.add_argument('--tap', type=int, nargs=2, default=[1440, 720])
    parser.add_argument('--tap-delay', type=float, default=4)
    parser.add_argument('--allow-unprotected-menu', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-fA-F]{64}', args.expected_apk_sha256):
        parser.error('expected APK SHA256 must be 64 hex characters')
    if args.nonce is not None and not re.fullmatch(r'[0-9a-f]{32}', args.nonce):
        parser.error('nonce must be 32 lowercase hex characters')
    if (args.first == args.second or not 1 <= args.brightness <= 255 or
            not 1 <= args.expected_backlight <= 255 or not 240 <= args.timeout <= 900 or
            not 0 <= args.tap_delay <= 15):
        parser.error('distinct PTS, brightness 1..255, timeout 240..900, tap delay 0..15 only')

    def terminate(signum, frame):
        raise KeyboardInterrupt(f'termination-signal-{signum}')

    signal.signal(signal.SIGTERM, terminate)
    result = run(args)
    pair = result.get('pair') or {}
    print(json.dumps({key: result.get(key) for key in
                      ('status', 'reason', 'restorationVerified', 'quality_pass', 'pair')}))
    return 0 if (result['status'] == 'completed-atlas-reuse' and
                 result.get('restorationVerified') is True and
                 pair.get('cross_pts_reuse_validated') is True and
                 result.get('quality_pass') is False) else 2


if __name__ == '__main__':
    raise SystemExit(main())
