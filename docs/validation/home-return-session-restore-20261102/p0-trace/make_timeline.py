#!/usr/bin/env python3
"""Build a cross-layer timeline (Java / native bridge / Dart / mpv / ActivityManager)
from one round's logcat-full.txt + host-events.ndjson.

Authoritative device time:
  * MKS-HOME-TRACE lines carry rt=<CLOCK_REALTIME ms> written by the emitting
    layer itself (Java System.currentTimeMillis, native clock_gettime, Dart
    DateTime.now). That value is used as the event time.
  * Other lines use the logcat threadtime stamp (device local wall clock,
    Asia/Shanghai, ms resolution). MPVLOG lines are relayed through the Dart
    log stream, so their logcat stamp lags the real native event.
Output: timeline.md, timeline.json (anchors + deltas).
"""
import json, re, sys, datetime, pathlib

TZ = datetime.timezone(datetime.timedelta(hours=8))
LOG_RE = re.compile(r'^(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\.(\d\d\d)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+(.*)$')
RT_RE = re.compile(r'\brt=(\d{13})\b')
YEAR = 2026

KEEP = [
    (re.compile(r'MKS-HOME-TRACE'), None),
    (re.compile(r'\bI MKSURF\s*:'), 'native-mksurf'),
    (re.compile(r'MPVLOG .*MKSURF: (version|bridge not initialized|bridge create|auto probe)'), 'mpv'),
    (re.compile(r'MPVLOG .*(eglCreateWindowSurface|YUV-DIAG: eglCreate|Using hardware decoding|Could not open codec|hwdec|Opening video decoder|VO: \[|uninit)'), 'mpv'),
    (re.compile(r'\bam_(pause_activity|resume_activity|on_paused_called|on_resume_called|on_stop_called)\b'), 'activity'),
    (re.compile(r'PlatformVideoView: (surfaceCreated|surfaceDestroyed|dispose|releaseSurface|surfaceChanged)'), 'java-log'),
    (re.compile(r'ACodec\s*: (Now uninitialized|\[OMX)'), 'codec'),
    (re.compile(r'VIDEOPARAMS VideoParams\(pixelformat: (yuv420p10|mediacodec|null)'), 'dart-videoparams'),
]
SKIP = re.compile(r'latch-timeout-diag|HDR_SESSION|HdrDiag|MKS-THERMAL|MKS-INPUT-FBO')


def layer_of(msg, default):
    if 'MKS-HOME-TRACE' in msg:
        if ' java ' in msg: return 'java'
        if ' native ' in msg: return 'native'
        if ' dart ' in msg: return 'dart'
        return 'trace'
    return default


def main(round_dir):
    rd = pathlib.Path(round_dir)
    rows = []
    # PID filter: the app pid recorded by the driver at launch (fresh) or at logcat clear (continue).
    app_pid = None
    hp0 = rd / 'host-events.ndjson'
    if hp0.exists():
        for l in hp0.read_text().splitlines():
            m0 = re.search(r'"note":"[^"]*pid=(\d+)', l)
            if m0 and ('am_start_fresh' in l or 'logcat_cleared' in l or 'pid_before' in l):
                app_pid = int(m0.group(1)); break
    with (rd / 'logcat-full.txt').open(errors='replace') as f:
        for lineno, line in enumerate(f, 1):
            line = line.rstrip('\n')
            m = LOG_RE.match(line)
            if not m: continue
            mo, d, hh, mm, ss, ms, pid, tid, lvl, msg = m.groups()
            if SKIP.search(msg): continue
            if app_pid is not None and int(pid) != app_pid and not re.search(r'\bam_(pause_activity|resume_activity)\b', msg):
                continue
            layer = None
            for rx, lay in KEEP:
                if rx.search(msg):
                    layer = layer_of(msg, lay); break
            if layer is None: continue
            logcat_ms = int(datetime.datetime(YEAR, int(mo), int(d), int(hh), int(mm), int(ss), int(ms) * 1000, tzinfo=TZ).timestamp() * 1000)
            rt = RT_RE.search(msg)
            t = int(rt.group(1)) if rt else logcat_ms
            # trim message
            msg2 = re.sub(r'^(MKS-HOME-TRACE: |flutter : MKS-HOME-TRACE |flutter : )', '', msg)
            msg2 = re.sub(r'SURFACE_TIMELINE \S+ ', '', msg2)
            msg2 = re.sub(r'\brt=\d+ ', '', msg2)
            if layer == 'dart-videoparams':
                msg2 = re.sub(r', hwPixelformat.*$', ', ...)', msg2)
            rows.append({'t': t, 'logcat_ms': logcat_ms, 'line': lineno, 'pid': int(pid), 'tid': int(tid), 'layer': layer, 'msg': msg2[:260]})

    # host events -> device time (device_ms recorded by the driver probe)
    host = []
    hp = rd / 'host-events.ndjson'
    if hp.exists():
        for l in hp.read_text().splitlines():
            if not l.strip(): continue
            e = json.loads(l)
            host.append({'t': e['device_ms'], 'logcat_ms': e['device_ms'], 'line': 0, 'pid': 0, 'tid': 0, 'layer': 'host-cmd', 'msg': f"{e['event']} {e.get('note','')}".strip()})
    rows += host
    rows.sort(key=lambda r: (r['t'], r['line']))

    def first(pred, after=None):
        for r in rows:
            if after is not None and r['t'] < after: continue
            if pred(r): return r
        return None

    def all_(pred):
        return [r for r in rows if pred(r)]

    home_sent = first(lambda r: r['layer'] == 'host-cmd' and r['msg'].startswith('home_sent'))
    return_sent = first(lambda r: r['layer'] == 'host-cmd' and r['msg'].startswith('return_sent'))
    # Only consider the HOME/return window (after home_send_begin) for anchors.
    begin = first(lambda r: r['layer'] == 'host-cmd' and r['msg'].startswith('home_send_begin'))
    t0 = begin['t'] if begin else (rows[0]['t'] if rows else 0)
    t_home = t0  # Δ reference: device time of the host probe taken just BEFORE `input keyevent KEYCODE_HOME` was issued

    A = {}
    A['home_send_begin(host probe)'] = begin
    A['home_sent(host probe after cmd returned)'] = home_sent
    A['am_pause_lab'] = first(lambda r: r['layer'] == 'activity' and 'am_pause_activity' in r['msg'] and 'hdr_lab' in r['msg'] or (r['layer']=='activity' and 'am_pause_activity' in r['msg'] and 'piliplus' in r['msg']), t0)
    A['java_surfaceDestroyed_enter'] = first(lambda r: r['layer'] == 'java' and 'surfaceDestroyed enter' in r['msg'], t0)
    A['java_send_SurfaceDestroyed'] = first(lambda r: r['layer'] == 'java' and 'channel.invokeMethod PlatformVideoView.SurfaceDestroyed' in r['msg'], t0)
    A['dart_event_SurfaceDestroyed'] = first(lambda r: r['layer'] == 'dart' and 'event SurfaceDestroyed' in r['msg'], t0)
    A['dart_detach_lock_acquired'] = first(lambda r: r['layer'] == 'dart' and 'detach lock acquired' in r['msg'], t0)
    A['dart_detach_vo_null_begin'] = first(lambda r: r['layer'] == 'dart' and 'property begin vo=null' in r['msg'], t0)
    A['native_shutdown_enter'] = first(lambda r: r['layer'] == 'native' and 'mkst_shutdown enter' in r['msg'], t0)
    A['native_shutdown_exit'] = first(lambda r: r['layer'] == 'native' and 'mkst_shutdown exit' in r['msg'], t0)
    A['dart_detach_vo_null_ack'] = first(lambda r: r['layer'] == 'dart' and 'property complete vo=null' in r['msg'], t0)
    A['dart_detach_wid0_ack'] = first(lambda r: r['layer'] == 'dart' and 'property complete wid=0' in r['msg'], t0)
    A['dart_detach_apply_complete'] = first(lambda r: r['layer'] == 'dart' and 'apply complete wid=0' in r['msg'], t0)
    A['dart_detach_lock_released'] = first(lambda r: r['layer'] == 'dart' and 'detach lock released' in r['msg'], t0)
    A['return_sent'] = return_sent
    A['am_resume_lab'] = first(lambda r: r['layer'] == 'activity' and 'am_resume_activity' in r['msg'] and ('hdr_lab' in r['msg'] or 'piliplus' in r['msg']), t0)
    A['java_factory_create_after_home'] = first(lambda r: r['layer'] == 'java' and 'factory.create enter' in r['msg'], t0)
    A['java_ensureInitialized_after_home'] = first(lambda r: r['layer'] == 'java' and 'bridge.ensureInitialized enter' in r['msg'], t0)
    A['java_surfaceCreated_enter'] = first(lambda r: r['layer'] == 'java' and 'surfaceCreated enter' in r['msg'], t0)
    A['java_send_SurfaceAvailable'] = first(lambda r: r['layer'] == 'java' and 'channel.invokeMethod PlatformVideoView.SurfaceAvailable' in r['msg'], t0)
    A['dart_event_SurfaceAvailable'] = first(lambda r: r['layer'] == 'dart' and 'event SurfaceAvailable' in r['msg'], t0)
    A['dart_bind_requested'] = first(lambda r: r['layer'] == 'dart' and 'bind requested' in r['msg'], t0)
    A['dart_bind_lock_acquired'] = first(lambda r: r['layer'] == 'dart' and 'bind lock acquired' in r['msg'], t0)
    A['dart_bind_vo_gpu_next_begin'] = first(lambda r: r['layer'] == 'dart' and 'property begin vo=gpu-next' in r['msg'], t0)
    A['native_ensure_init_exit'] = first(lambda r: r['layer'] == 'native' and 'mkst_ensure_init(lc_verify) exit' in r['msg'], t0)
    A['native_create_exit'] = first(lambda r: r['layer'] == 'native' and 'mkst_create_decoder_window exit' in r['msg'], t0)
    A['mpv_egl_window_surface'] = first(lambda r: r['layer'] == 'mpv' and 'eglCreateWindowSurface' in r['msg'], t0)
    A['mpv_bridge_not_initialized'] = first(lambda r: r['layer'] == 'mpv' and 'bridge not initialized' in r['msg'], t0)
    A['dart_bind_complete'] = first(lambda r: r['layer'] == 'dart' and 'bind complete' in r['msg'], t0)
    A['first_videoparams_after_return'] = first(lambda r: r['layer'] == 'dart-videoparams' and 'yuv420p10' in r['msg'], A['java_surfaceCreated_enter']['t'] if A['java_surfaceCreated_enter'] else t0)

    counts = {
        'ensureInitialized_total_in_log': len(all_(lambda r: r['layer'] == 'java' and 'bridge.ensureInitialized enter' in r['msg'])),
        'ensureInitialized_after_home_sent': len(all_(lambda r: r['layer'] == 'java' and 'bridge.ensureInitialized enter' in r['msg'] and r['t'] >= t0)),
        'factory_create_total_in_log': len(all_(lambda r: r['layer'] == 'java' and 'factory.create enter' in r['msg'])),
        'factory_create_after_home_sent': len(all_(lambda r: r['layer'] == 'java' and 'factory.create enter' in r['msg'] and r['t'] >= t0)),
        'mkst_shutdown_exit_total': len(all_(lambda r: r['layer'] == 'native' and 'mkst_shutdown exit' in r['msg'])),
        'mkst_create_exit_total': len(all_(lambda r: r['layer'] == 'native' and 'mkst_create_decoder_window exit' in r['msg'])),
        'surfaceCreated_enter_total': len(all_(lambda r: r['layer'] == 'java' and 'surfaceCreated enter' in r['msg'])),
        'surfaceDestroyed_enter_total': len(all_(lambda r: r['layer'] == 'java' and 'surfaceDestroyed enter' in r['msg'])),
    }

    def d(a, b):
        if A.get(a) and A.get(b): return A[b]['t'] - A[a]['t']
        return None
    deltas = {
        'shutdown_exit -> java_surfaceCreated_enter (ms)': d('native_shutdown_exit', 'java_surfaceCreated_enter'),
        'shutdown_exit -> dart_vo_null_ACK (ms)': d('native_shutdown_exit', 'dart_detach_vo_null_ack'),
        'shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms)': d('native_shutdown_exit', 'dart_detach_apply_complete'),
        'shutdown_exit -> native_ensure_init_exit (new importer) (ms)': d('native_shutdown_exit', 'native_ensure_init_exit'),
        'java_surfaceDestroyed_enter -> shutdown_exit (ms)': d('java_surfaceDestroyed_enter', 'native_shutdown_exit'),
        'dart_vo_null_begin -> shutdown_enter (ms)': d('dart_detach_vo_null_begin', 'native_shutdown_enter'),
        'java_surfaceCreated_enter -> dart_bind_lock_acquired (ms)': d('java_surfaceCreated_enter', 'dart_bind_lock_acquired'),
        'dart_detach_lock_released -> dart_bind_lock_acquired (ms)': d('dart_detach_lock_released', 'dart_bind_lock_acquired'),
        'dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock)': d('dart_event_SurfaceAvailable', 'dart_detach_lock_released'),
        'native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms)': d('native_ensure_init_exit', 'mpv_bridge_not_initialized'),
        'java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms)': d('java_surfaceCreated_enter', 'first_videoparams_after_return'),
        'home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms)': d('home_send_begin(host probe)', 'java_surfaceDestroyed_enter'),
        'return_sent(host probe) -> java_surfaceCreated_enter (ms)': d('return_sent', 'java_surfaceCreated_enter'),
    }

    def fmt(t):
        return datetime.datetime.fromtimestamp(t / 1000, TZ).strftime('%H:%M:%S.%f')[:-3]

    out = [f'# Timeline {rd.name}', '', f'App PID filter: {app_pid} (ActivityManager am_pause/resume lines kept from system_server).', '',
           f'Source: `{rd.name}/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). '
           'Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. '
           'Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).', '',
           '## Anchors', '', '| anchor | device time | Δhome (ms) | line |', '|---|---|---|---|']
    for k, r in A.items():
        if r is None:
            out.append(f'| {k} | — | — | — |')
        else:
            dh = (r['t'] - t_home) if t_home else None
            out.append(f"| {k} | {fmt(r['t'])} | {dh if dh is not None else '—'} | L{r['line']} |")
    out += ['', '## Deltas', '', '| delta | ms |', '|---|---|']
    for k, v in deltas.items():
        out.append(f'| {k} | {v if v is not None else "—"} |')
    out += ['', '## Counts (whole dump)', '', '| counter | n |', '|---|---|']
    for k, v in counts.items():
        out.append(f'| {k} | {v} |')
    out += ['', '## Events (time-sorted; HOME window and after, plus pre-HOME bridge lifecycle)', '',
            '| device time | Δhome (ms) | layer | tid | event | line |', '|---|---|---|---|---|---|']
    for r in rows:
        pre = r['t'] < t0 - 500
        if pre and r['layer'] not in ('java', 'native', 'host-cmd', 'java-log') : continue
        if pre and r['layer'] in ('java', 'java-log') and not any(s in r['msg'] for s in ('factory', 'setLgExperimentOwner', 'ensureInitialized', 'surfaceCreated', 'ViewCreated')): continue
        dh = (r['t'] - t_home) if t_home else None
        out.append(f"| {fmt(r['t'])} | {dh if dh is not None else '—'} | {r['layer']} | {r['tid'] or ''} | {r['msg'].replace('|', '\\|')} | {('L'+str(r['line'])) if r['line'] else ''} |")
    (rd / 'timeline.md').write_text('\n'.join(out) + '\n')
    (rd / 'timeline.json').write_text(json.dumps({'anchors': {k: (None if v is None else {'t': v['t'], 'time': fmt(v['t']), 'line': v['line'], 'tid': v['tid'], 'msg': v['msg']}) for k, v in A.items()}, 'deltas_ms': deltas, 'counts': counts}, indent=1, ensure_ascii=False))
    print(f'{rd.name}: rows={len(rows)}')
    for k, v in deltas.items(): print(f'  {k}: {v}')
    for k, v in counts.items(): print(f'  {k}: {v}')


if __name__ == '__main__':
    for arg in sys.argv[1:]:
        main(arg)
