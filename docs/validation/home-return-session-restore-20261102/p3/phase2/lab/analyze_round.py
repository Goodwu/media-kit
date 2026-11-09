#!/usr/bin/env python3
"""P3 phase2 (b) per-round analyzer (Lab, LG H870DS).

Reads <round>/logcat-full.txt + <round>/host-events.ndjson, writes <round>/analysis.json
and <round>/analysis.md. Pure extraction + rule evaluation; every reported item carries
the 1-based line number of logcat-full.txt. Event time = rt= (device CLOCK_REALTIME ms)
when the line carries one (MKS-HOME-TRACE), else the logcat threadtime stamp (Asia/Shanghai).

usage: analyze_round.py <round_dir> [<round_dir> ...]
"""
import json, re, sys, datetime, pathlib

TZ = datetime.timezone(datetime.timedelta(hours=8))
YEAR = 2026
LOG_RE = re.compile(r'^(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\.(\d\d\d)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+(.*)$')
RT_RE = re.compile(r'\brt=(\d{13})\b')
PKG = 'com.example.media_kit_hdr_lab'

TEARDOWN_PATTERNS = {
    'latch_timeout': re.compile(r'MKSURF: latch timeout'),
    'mapping_failed': re.compile(r'Mapping hardware decoded surface failed'),
    'fusion_disabled_after_failure': re.compile(r'MKS-FUSION disabled-after-failure'),
    'horizon_overflow': re.compile(r'horizon-overflow'),
    'failed_rendering_frame': re.compile(r'Failed rendering frame'),
}


def fmt(t):
    return datetime.datetime.fromtimestamp(t / 1000, TZ).strftime('%H:%M:%S.%f')[:-3]


def load(rd):
    rows = []
    with (rd / 'logcat-full.txt').open(errors='replace') as f:
        for ln, line in enumerate(f, 1):
            line = line.rstrip('\n')
            m = LOG_RE.match(line)
            if not m:
                continue
            mo, d, hh, mm, ss, ms, pid, tid, lvl, msg = m.groups()
            lc = int(datetime.datetime(YEAR, int(mo), int(d), int(hh), int(mm), int(ss), int(ms) * 1000, tzinfo=TZ).timestamp() * 1000)
            rt = RT_RE.search(msg)
            rows.append({'ln': ln, 'lc': lc, 't': int(rt.group(1)) if rt else lc, 'pid': int(pid), 'tid': int(tid), 'lvl': lvl, 'msg': msg})
    host = {}
    hp = rd / 'host-events.ndjson'
    if hp.exists():
        for l in hp.read_text().splitlines():
            if l.strip():
                e = json.loads(l)
                host.setdefault(e['event'], []).append(e)
    return rows, host


def hostev(host, name, idx=0):
    v = host.get(name)
    return v[idx] if v and len(v) > idx else None


def hnote(e, key):
    if not e:
        return None
    m = re.search(r'\b' + key + r'=(\S*)', e.get('note', ''))
    return m.group(1) if m else None


def first(rows, pred, after=None, before=None):
    for r in rows:
        if after is not None and r['t'] < after:
            continue
        if before is not None and r['t'] > before:
            continue
        if pred(r['msg']):
            return r
    return None


def last(rows, pred, after=None, before=None):
    out = None
    for r in rows:
        if after is not None and r['t'] < after:
            continue
        if before is not None and r['t'] > before:
            continue
        if pred(r['msg']):
            out = r
    return out


def allr(rows, pred, after=None, before=None):
    return [r for r in rows if (after is None or r['t'] >= after) and (before is None or r['t'] <= before) and pred(r['msg'])]


def ref(r, maxlen=200):
    if r is None:
        return None
    return {'line': r['ln'], 'time': fmt(r['t']), 't': r['t'], 'msg': r['msg'][:maxlen]}


def kv(msg, key):
    m = re.search(r'\b' + key + r'=([^\s,)]+)', msg)
    return m.group(1) if m else None


def analyze(rd):
    rd = pathlib.Path(rd)
    rows, host = load(rd)
    out = {'round': rd.name}
    rb = hostev(host, 'round_begin')
    out['driver'] = {'round_begin_note': rb.get('note') if rb else None}
    app_pid = None
    for k in ('am_start_fresh', 'logcat_cleared', 'pid_before'):
        e = hostev(host, k)
        p = hnote(e, 'pid')
        if p and p.isdigit():
            app_pid = int(p); break
    out['app_pid'] = app_pid
    hs = hostev(host, 'home_send_begin')
    t_home = hs['device_ms'] if hs else None
    rs = hostev(host, 'return_sent')
    t_return = rs['device_ms'] if rs else None
    out['t_home_send_begin'] = t_home
    out['t_return_sent'] = t_return
    if t_home is None:
        out['error'] = 'no home_send_begin in host-events'
        return out
    app = [r for r in rows if app_pid is None or r['pid'] == app_pid]
    sysr = rows

    # ---- 5. identity / crash ----
    pb = hnote(hostev(host, 'pid_before'), 'pid')
    pa = hnote(hostev(host, 'pid_after'), 'pid_after')
    proc_start = allr(sysr, lambda m: m.startswith('am_proc_start:') and PKG in m)
    proc_died = allr(sysr, lambda m: m.startswith('am_proc_died:') and PKG in m)
    fatal = allr(sysr, lambda m: 'FATAL EXCEPTION' in m or 'Fatal signal' in m or 'Tombstone written' in m or ('*** ***' in m))
    fatal_lvl = [r for r in rows if r['lvl'] == 'F']
    anr = allr(sysr, lambda m: m.startswith('ANR in') or m.startswith('am_anr:') or m.startswith('am_crash:'))
    out['identity'] = {
        'pid_before': pb, 'pid_after': pa, 'same_pid': (pb == pa and pb not in (None, '')),
        'am_proc_start_pkg': [ref(r, 120) for r in proc_start],
        'am_proc_died_pkg': [ref(r, 120) for r in proc_died],
        'fatal_lines': [ref(r, 160) for r in fatal[:5]], 'fatal_count': len(fatal),
        'F_level_lines': len(fatal_lvl), 'anr_crash_lines': [ref(r, 160) for r in anr[:5]], 'anr_crash_count': len(anr),
    }

    # ---- pre-HOME hwdec starting point ----
    pre_report = last(app, lambda m: 'HDR_SESSION_REPORT' in m and 'hwdecCurrent=surfacetexture' in m, before=t_home)
    pre_create = last(app, lambda m: 'mkst_create_decoder_window exit' in m and 'result=ok' in m, before=t_home)
    pre_owner_key = kv(pre_create['msg'], 'owner_key') if pre_create else None
    pre_gen = kv(pre_create['msg'], 'generation') if pre_create else None
    tp = []
    for r in app:
        m = re.search(r'PERF t=(\d+) time-pos=([0-9.]+)', r['msg'])
        if m:
            tp.append({'line': r['ln'], 'time': fmt(r['t']), 't': r['t'], 'src': 'PERF', 'perf_t': int(m.group(1)), 'time_pos': float(m.group(2))}); continue
        m = re.search(r'ANDROID_P5_COUNTERS \{time-pos: ([0-9.]+)', r['msg'])
        if m:
            tp.append({'line': r['ln'], 'time': fmt(r['t']), 't': r['t'], 'src': 'P5', 'time_pos': float(m.group(1))})
    pause_lines = []
    for r in app:
        m = re.search(r'PERF t=(\d+) pause=(\w+)', r['msg'])
        if m:
            pause_lines.append({'line': r['ln'], 'time': fmt(r['t']), 't': r['t'], 'perf_t': int(m.group(1)), 'pause': m.group(2)})
    swaps = []
    for r in app:
        if 'event=swap-success' in r['msg']:
            swaps.append({'line': r['ln'], 't': r['t'], 'gen': kv(r['msg'], 'generation'), 'frame_id': kv(r['msg'], 'frame_id'), 'pts': kv(r['msg'], 'source_pts'), 'still': kv(r['msg'], 'still'), 'route': kv(r['msg'], 'route')})
    pre_tp = [x for x in tp if x['t'] < t_home]
    post_home_first_tp = next((x for x in tp if x['t'] >= t_home), None)
    pre_swaps = [s for s in swaps if s['t'] < t_home]
    fusion_pre = last(app, lambda m: 'MKS-FUSION committed=' in m, before=t_home)
    frozen = post_home_first_tp['time_pos'] if post_home_first_tp else None
    last_pre = pre_tp[-1]['time_pos'] if pre_tp else None
    out['pre_home'] = {
        'hdr_report_hwdec_surfacetexture': ref(pre_report, 120),
        'create_decoder_window_ok': ref(pre_create, 230),
        'owner_key': pre_owner_key, 'generation': pre_gen,
        'time_pos_samples': pre_tp,
        'first_time_pos_after_home(frozen_value)': post_home_first_tp,
        'playback_ge_15s_before_home': (frozen is not None and frozen >= 15.0) or (last_pre is not None and last_pre >= 15.0),
        'swap_success_count': len(pre_swaps),
        'swap_frame_id_max': max((int(s['frame_id']) for s in pre_swaps if s['frame_id']), default=None),
        'fusion_committed_last': ref(fusion_pre, 140),
        'pass': pre_report is not None and pre_create is not None and ((frozen is not None and frozen >= 15.0) or (last_pre is not None and last_pre >= 15.0)),
    }

    # ---- teardown window ----
    sd = first(app, lambda m: 'java surfaceDestroyed enter' in m, after=t_home)
    sh_in = first(app, lambda m: 'native mkst_shutdown enter' in m, after=t_home)
    sh_out = first(app, lambda m: 'native mkst_shutdown exit' in m, after=t_home)
    vo_null_ack = first(app, lambda m: 'property complete vo=null' in m, after=t_home)
    sc = first(app, lambda m: 'java surfaceCreated enter' in m, after=t_home)
    am_pause = first(sysr, lambda m: m.startswith('am_pause_activity') and PKG in m, after=t_home - 500)
    am_stop = first(sysr, lambda m: m.startswith('am_on_stop_called') and PKG in m, after=t_home - 500)
    am_resume = first(sysr, lambda m: m.startswith('am_resume_activity') and PKG in m, after=t_home)
    teardown = {'surfaceDestroyed_enter': ref(sd, 230), 'shutdown_enter': ref(sh_in, 230), 'shutdown_exit': ref(sh_out, 230), 'vo_null_ack': ref(vo_null_ack, 120),
                'am_pause_activity': ref(am_pause, 100), 'am_on_stop_called': ref(am_stop, 100), 'am_resume_activity': ref(am_resume, 100)}
    if sd and sh_out:
        w0, w1 = sd['t'] - 1000, sh_out['t'] + 1000
        teardown['window'] = {'from': fmt(w0), 'to': fmt(w1), 'from_t': w0, 'to_t': w1}
        teardown['shutdown_exit_minus_sd_ms'] = sh_out['t'] - sd['t']
        counts = {}
        for k, rx in TEARDOWN_PATTERNS.items():
            inwin = allr(app, lambda m, rx=rx: bool(rx.search(m)), after=w0, before=w1)
            whole = allr(app, lambda m, rx=rx: bool(rx.search(m)))
            pre = allr(app, lambda m, rx=rx: bool(rx.search(m)), before=t_home)
            counts[k] = {'in_window': len(inwin), 'in_window_lines': [r['ln'] for r in inwin[:6]], 'whole_log': len(whole), 'pre_home': len(pre), 'whole_lines': [r['ln'] for r in whole[:6]]}
        teardown['error_counts'] = counts
    else:
        teardown['window'] = None
    out['teardown'] = teardown

    # ---- 1. time chain after HOME (same identity) ----
    a_begin = first(app, lambda m: ' dart ' in m and 'authorize begin' in m, after=t_home)
    wid = kv(a_begin['msg'], 'wid') if a_begin else None
    j_enter = first(app, lambda m: ' java authorize enter' in m and (wid is None or f'wid={wid}' in m), after=t_home)
    j_result = first(app, lambda m: ' java authorize result' in m and (wid is None or f'wid={wid}' in m), after=t_home)
    d_result = first(app, lambda m: ' dart ' in m and 'authorize result' in m and (wid is None or f'wid={wid}' in m), after=t_home)
    ens = first(app, lambda m: 'mkst_ensure_init(lc_verify) exit' in m, after=t_home)
    crt = first(app, lambda m: 'mkst_create_decoder_window exit' in m, after=t_home)
    mc = first(app, lambda m: m.startswith('Mediacodec create') or 'MediaCodec: Mediacodec create' in m or 'Mediacodec create pid=' in m, after=t_home)
    # OMX instantiation strictly after the post-return MediaCodec create (ACodec also prints "Now Loaded" while tearing down)
    omx = first(app, lambda m: '[OMX.qcom.video.decoder.hevc] Now Loaded' in m and 'Loaded->' not in m, after=mc['t']) if mc else None
    chain = [('vo_null_property_complete', vo_null_ack), ('dart_authorize_begin', a_begin), ('java_authorize_enter', j_enter), ('java_authorize_result', j_result),
             ('dart_authorize_result', d_result), ('native_ensure_init_exit', ens), ('native_create_decoder_window_exit', crt), ('MediaCodec_create', mc), ('OMX_hevc_Now_Loaded(after create)', omx)]
    chain_out, prev_t, ordered = [], None, True
    for name, r in chain:
        d = (r['t'] - prev_t) if (r and prev_t is not None) else None
        if r and prev_t is not None and r['t'] < prev_t:
            ordered = False
        chain_out.append({'anchor': name, 'line': r['ln'] if r else None, 'time': fmt(r['t']) if r else None, 't': r['t'] if r else None, 'delta_prev_ms': d, 'msg': r['msg'][:170] if r else None})
        if r:
            prev_t = r['t']
    idn = {
        'wid': wid,
        'dart_begin': {k: kv(a_begin['msg'], k) for k in ('wid', 'generation', 'viewId', 'surfaceGeneration', 'intentSerial')} if a_begin else None,
        'java_enter': {k: kv(j_enter['msg'], k) for k in ('wid', 'generation', 'viewId', 'surfaceGeneration', 'ownerTokenPresent')} if j_enter else None,
        'java_result': {k: kv(j_result['msg'], k) for k in ('wid', 'code', 'applicable', 'ok', 'ownerGeneration', 'surfaceGeneration', 'viewId')} if j_result else None,
        'dart_result': {k: kv(d_result['msg'], k) for k in ('wid', 'code', 'ok', 'ownerGeneration', 'surfaceGeneration', 'epoch')} if d_result else None,
        'ensure_init': {k: kv(ens['msg'], k) for k in ('initialized', 'owner_key', 'generation', 'ready', 'egl_ctx')} if ens else None,
        'create_window': {k: kv(crt['msg'], k) for k in ('initialized', 'window_active', 'owner_key', 'generation', 'result')} if crt else None,
        'pre_home_owner_key': pre_owner_key, 'pre_home_generation': pre_gen,
    }
    same_wid = bool(a_begin and j_enter and j_result and d_result)
    same_owner = bool(ens and crt and pre_owner_key and kv(ens['msg'], 'owner_key') == pre_owner_key and kv(crt['msg'], 'owner_key') == pre_owner_key)
    c1_ok = all(r is not None for _, r in chain[:8]) and ordered and same_wid and (j_result is not None and kv(j_result['msg'], 'code') == 'ok') and (ens is not None and kv(ens['msg'], 'ready') == '1') and (crt is not None and kv(crt['msg'], 'result') == 'ok')
    out['c1_time_chain'] = {'anchors': chain_out, 'ordered': ordered, 'same_wid_across_authorize': same_wid, 'owner_key_same_as_pre_home': same_owner, 'identity': idn, 'pass': c1_ok}
    factory_after = allr(app, lambda m: 'java factory.create enter' in m, after=t_home)
    ensure_java_after = allr(app, lambda m: 'bridge.ensureInitialized enter' in m, after=t_home)
    out['c1_time_chain']['java_factory_create_after_home'] = [ref(r, 150) for r in factory_after]
    out['c1_time_chain']['java_ensureInitialized_after_home'] = [ref(r, 150) for r in ensure_java_after]

    # ---- 2. after return ----
    t_sc = sc['t'] if sc else (t_return or t_home)
    bni = allr(app, lambda m: 'bridge not initialized' in m, after=t_sc)
    yuv = allr(app, lambda m: 'yuv420p10' in m, after=t_sc)
    vp = allr(app, lambda m: 'VIDEOPARAMS VideoParams(pixelformat: mediacodec' in m, after=t_sc)
    imp = allr(app, lambda m: 'active-importer=surfacetexture device_registered=1' in m, after=t_sc)
    rep_after = last(app, lambda m: 'HDR_SESSION_REPORT' in m and 'hwdecCurrent=' in m, after=t_sc)
    out['c2_after_return'] = {'surfaceCreated_enter': ref(sc, 230), 'bridge_not_initialized': len(bni), 'bridge_not_initialized_lines': [r['ln'] for r in bni[:5]],
                              'yuv420p10': len(yuv), 'yuv420p10_lines': [r['ln'] for r in yuv[:5]],
                              'videoparams_mediacodec': [ref(r, 90) for r in vp[:3]], 'active_importer_registered': [ref(r, 120) for r in imp[:3]],
                              'last_hdr_report_hwdecCurrent': kv(rep_after['msg'], 'hwdecCurrent') if rep_after else None, 'last_hdr_report_line': rep_after['ln'] if rep_after else None,
                              'pass': len(bni) == 0 and len(yuv) == 0 and len(vp) > 0 and len(imp) > 0}

    # ---- 3. playback after return ----
    post_tp = [x for x in tp if x['t'] >= t_sc]
    post_pause = [x for x in pause_lines if x['t'] >= t_sc]
    post_swaps = [s for s in swaps if s['t'] >= t_sc]
    fids = [int(s['frame_id']) for s in post_swaps if s['frame_id']]
    fusion_post = last(app, lambda m: 'MKS-FUSION committed=' in m, after=t_sc)
    advancing = len(post_tp) >= 2 and (post_tp[-1]['time_pos'] - post_tp[0]['time_pos']) >= 15.0
    out['c3_playback_after_return'] = {'time_pos_samples': post_tp, 'pause_samples': post_pause, 'swap_success_count': len(post_swaps),
                                      'swap_frame_ids_unique': sorted(set(fids)), 'swap_first': post_swaps[0] if post_swaps else None, 'swap_last': post_swaps[-1] if post_swaps else None,
                                      'fusion_committed_last': ref(fusion_post, 140), 'time_pos_advanced_ge_15s': advancing,
                                      'observation_window_s': round((app[-1]['t'] - t_sc) / 1000, 1) if app else None}

    # ---- 4. errors ----
    bai = allr(app, lambda m: 'BridgeActivationIssue' in m)
    auth_bad = allr(app, lambda m: bool(re.search(r'authorize (failed|stale|skipped|abandoned)', m)) or (('authorize result' in m) and 'code=ok' not in m))
    herr = allr(app, lambda m: 'HdrErrorEvent' in m)
    herr_other = [r for r in herr if 'noDisplayCapabilityReport' not in r['msg']]
    out['c4_errors'] = {'BridgeActivationIssue': len(bai), 'BridgeActivationIssue_lines': [ref(r, 200) for r in bai[:5]],
                        'authorize_failed_stale_skipped_abandoned_or_non_ok': len(auth_bad), 'authorize_bad_lines': [ref(r, 200) for r in auth_bad[:5]],
                        'HdrErrorEvent_total': len(herr), 'HdrErrorEvent_noDisplayCapabilityReport(single-open, pre-existing)': len(herr) - len(herr_other),
                        'HdrErrorEvent_other': len(herr_other), 'HdrErrorEvent_other_lines': [ref(r, 200) for r in herr_other[:5]],
                        'pass': len(bai) == 0 and len(auth_bad) == 0 and len(herr_other) == 0}
    out['c5_process'] = {'pass': out['identity']['same_pid'] and len(proc_died) == 0 and len(fatal) == 0 and len(anr) == 0 and len(fatal_lvl) == 0}

    # ---- 6. HDR ----
    e1_pre = allr(app, lambda m: 'MKSURF-E1: dataspace applied' in m, before=t_home)
    e1_post = allr(app, lambda m: 'MKSURF-E1: dataspace applied' in m, after=t_home)
    dec_pre = last(app, lambda m: 'HdrDiag HDR decision: phase=applied' in m, before=t_home)
    dec_post = last(app, lambda m: 'HdrDiag HDR decision: phase=applied' in m, after=t_home)
    dec_post_any = allr(app, lambda m: 'HdrDiag HDR decision:' in m, after=t_home)
    keys = ('phase', 'gen', 'class', 'selected', 'presentation', 'vo', 'hwdec', 'output', 'topology')
    dp = {k: kv(dec_pre['msg'], k) for k in keys} if dec_pre else None
    dq = {k: kv(dec_post['msg'], k) for k in keys} if dec_post else None
    rep_pre = last(app, lambda m: 'HDR_SESSION_REPORT' in m and 'hwdecCurrent=' in m, before=t_home)
    rep_last = last(app, lambda m: 'HDR_SESSION_REPORT' in m and 'hwdecCurrent=' in m)
    rep_post_all = allr(app, lambda m: 'HDR_SESSION_REPORT' in m and 'hwdecCurrent=' in m, after=t_home)
    out['c6_hdr'] = {'e1_dataspace_pre_home': [ref(r, 110) for r in e1_pre], 'e1_dataspace_after_home': [ref(r, 110) for r in e1_post],
                     'decision_applied_pre_home': {'line': dec_pre['ln'], **dp} if dec_pre else None,
                     'decision_applied_after_home': {'line': dec_post['ln'], **dq} if dec_post else None,
                     'decision_lines_after_home': len(dec_post_any),
                     'hdr_report_hwdec_pre_home': kv(rep_pre['msg'], 'hwdecCurrent') if rep_pre else None,
                     'hdr_report_last_in_log': {'line': rep_last['ln'], 'time': fmt(rep_last['t']), 'hwdecCurrent': kv(rep_last['msg'], 'hwdecCurrent')} if rep_last else None,
                     'hdr_reports_after_home': [{'line': r['ln'], 'time': fmt(r['t']), 'hwdecCurrent': kv(r['msg'], 'hwdecCurrent')} for r in rep_post_all],
                     'sf_pre_home': (rd / 'sf-pre-home.txt').exists(), 'sf_post_return': (rd / 'sf-post-return.txt').exists()}
    route_same = (dp is not None and dq is not None and all(dp[k] == dq[k] for k in ('class', 'selected', 'presentation', 'vo', 'hwdec', 'output', 'topology'))) or (dp is not None and dq is None and len(dec_post_any) == 0)
    out['c6_hdr']['route_decision_consistent'] = route_same
    out['c6_hdr']['route_note'] = ('post-HOME decision identical to pre-HOME' if (dp and dq and route_same) else ('no new HDR decision line after HOME (route unchanged, decision not re-run)' if (dp and not dq) else 'see fields'))
    hw_ok = rep_last is not None and kv(rep_last['msg'], 'hwdecCurrent') == 'surfacetexture' and all(kv(r['msg'], 'hwdecCurrent') == 'surfacetexture' for r in rep_post_all)
    out['c6_hdr']['hwdec_reports_all_surfacetexture_from_pre_home_on'] = hw_ok
    out['c6_hdr']['pass'] = len(e1_post) >= 1 and route_same and hw_ok and dp is not None and dp.get('hwdec') == 'surfacetexture'

    # ---- 7. fast interval ----
    sds = allr(app, lambda m: 'java surfaceDestroyed enter' in m)
    scs = allr(app, lambda m: 'java surfaceCreated enter' in m)
    shs = allr(app, lambda m: 'native mkst_shutdown exit' in m)
    cycles = []
    for s in sds:
        if s['t'] < t_home - 1000:
            continue
        nsc = next((x for x in scs if x['t'] >= s['t']), None)
        nsh = next((x for x in shs if x['t'] >= s['t']), None)
        cycles.append({'sd_line': s['ln'], 'sd_t': fmt(s['t']), 'sc_line': nsc['ln'] if nsc else None, 'sc_t': fmt(nsc['t']) if nsc else None,
                       'sd_to_sc_ms': (nsc['t'] - s['t']) if nsc else None,
                       'shutdown_exit_line': nsh['ln'] if nsh else None, 'shutdown_exit_vs_sc': (('shutdown_exit BEFORE surfaceCreated by %d ms' % (nsc['t'] - nsh['t'])) if (nsh and nsc and nsh['t'] <= nsc['t']) else (('surfaceCreated BEFORE shutdown_exit by %d ms' % (nsh['t'] - nsc['t'])) if (nsh and nsc) else 'n/a'))})
    sf_fail = allr(app, lambda m: 'SurfaceFailed' in m or 'RuntimeFailed' in m)
    out['c7_fast'] = {'home_cycles': cycles, 'SurfaceFailed_or_RuntimeFailed': len(sf_fail), 'lines': [ref(r, 160) for r in sf_fail[:5]]}

    # whole-log misc counts
    out['counts'] = {k: len(allr(app, lambda m, k=k: k in m)) for k in ('bridge not initialized', 'yuv420p10', 'MKSURF-E1: dataspace applied', 'Mediacodec create', 'mkst_ensure_init(lc_verify) exit', 'mkst_create_decoder_window exit', 'authorize begin', 'event=swap-success')}
    out['log_lines'] = rows[-1]['ln'] if rows else 0
    return out


def md(a):
    L = [f"# Analysis {a['round']}", '', f"- driver: `{a['driver']['round_begin_note']}`", f"- app pid: {a['app_pid']}; log lines: {a.get('log_lines')}",
         f"- t_home_send_begin (device): {fmt(a['t_home_send_begin']) if a.get('t_home_send_begin') else '—'}; return_sent: {fmt(a['t_return_sent']) if a.get('t_return_sent') else '—'}", '']
    if 'error' in a:
        L.append(f"ERROR: {a['error']}"); return '\n'.join(L) + '\n'
    ph = a['pre_home']
    L += ['## Pre-HOME hardware-decode starting point', '',
          f"- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: {('L%d %s' % (ph['hdr_report_hwdec_surfacetexture']['line'], ph['hdr_report_hwdec_surfacetexture']['time'])) if ph['hdr_report_hwdec_surfacetexture'] else 'MISSING'}",
          f"- mkst_create_decoder_window exit result=ok: {('L%d %s owner_key=%s generation=%s' % (ph['create_decoder_window_ok']['line'], ph['create_decoder_window_ok']['time'], ph['owner_key'], ph['generation'])) if ph['create_decoder_window_ok'] else 'MISSING'}",
          f"- time-pos samples before HOME: " + ', '.join(f"L{x['line']} {x['time']} {x['src']} {x['time_pos']:.3f}" for x in ph['time_pos_samples']),
          f"- frozen time-pos at first sample after HOME: " + (f"L{ph['first_time_pos_after_home(frozen_value)']['line']} {ph['first_time_pos_after_home(frozen_value)']['time_pos']:.3f} s" if ph['first_time_pos_after_home(frozen_value)'] else '—'),
          f"- swap-success before HOME: {ph['swap_success_count']} lines, max frame_id={ph['swap_frame_id_max']}; last MKS-FUSION committed: " + (f"L{ph['fusion_committed_last']['line']} `{ph['fusion_committed_last']['msg'][-60:]}`" if ph['fusion_committed_last'] else '—'),
          f"- playback ≥15 s before HOME: {ph['playback_ge_15s_before_home']}; **pre-HOME start-point pass: {ph['pass']}**", '']
    c1 = a['c1_time_chain']
    L += ['## C1 time chain after HOME (same identity)', '', '| anchor | line | device time | Δprev (ms) |', '|---|---|---|---|']
    for x in c1['anchors']:
        L.append(f"| {x['anchor']} | {('L%d' % x['line']) if x['line'] else 'MISSING'} | {x['time'] or '—'} | {x['delta_prev_ms'] if x['delta_prev_ms'] is not None else '—'} |")
    L += ['', f"- ordered: {c1['ordered']}; same wid across dart/java authorize: {c1['same_wid_across_authorize']} (wid={c1['identity']['wid']}); owner_key same as pre-HOME: {c1['owner_key_same_as_pre_home']} (pre={c1['identity']['pre_home_owner_key']}, ensure_init={c1['identity']['ensure_init']['owner_key'] if c1['identity']['ensure_init'] else None})",
          f"- identity: dart_begin={c1['identity']['dart_begin']} java_result={c1['identity']['java_result']} ensure_init={c1['identity']['ensure_init']} create_window={c1['identity']['create_window']}",
          f"- java factory.create after HOME: {len(c1['java_factory_create_after_home'])}; java bridge.ensureInitialized after HOME: {len(c1['java_ensureInitialized_after_home'])}",
          f"- **C1 pass: {c1['pass']}**", '']
    c2 = a['c2_after_return']
    L += ['## C2 after return', '',
          f"- surfaceCreated enter: {('L%d %s' % (c2['surfaceCreated_enter']['line'], c2['surfaceCreated_enter']['time'])) if c2['surfaceCreated_enter'] else 'MISSING'}",
          f"- `bridge not initialized`: {c2['bridge_not_initialized']} (lines {c2['bridge_not_initialized_lines']}); `yuv420p10`: {c2['yuv420p10']} (lines {c2['yuv420p10_lines']})",
          f"- VIDEOPARAMS pixelformat: mediacodec: " + ', '.join(f"L{r['line']} {r['time']}" for r in c2['videoparams_mediacodec']) if c2['videoparams_mediacodec'] else '- VIDEOPARAMS pixelformat: mediacodec: MISSING',
          f"- active-importer=surfacetexture device_registered=1: " + ', '.join(f"L{r['line']} {r['time']}" for r in c2['active_importer_registered']) if c2['active_importer_registered'] else '- active-importer registered: MISSING',
          f"- last HDR_SESSION_REPORT hwdecCurrent after return: {c2['last_hdr_report_hwdecCurrent']} (L{c2['last_hdr_report_line']})",
          f"- **C2 pass: {c2['pass']}**", '']
    c3 = a['c3_playback_after_return']
    L += ['## C3 playback after return', '',
          f"- observation window after surfaceCreated: {c3['observation_window_s']} s",
          f"- time-pos samples: " + (', '.join(f"L{x['line']} {x['time']} {x['src']} {x['time_pos']:.3f}" for x in c3['time_pos_samples']) or 'none'),
          f"- PERF pause samples: " + (', '.join(f"L{x['line']} t={x['perf_t']} pause={x['pause']}" for x in c3['pause_samples']) or 'none'),
          f"- swap-success after return: {c3['swap_success_count']} lines; unique frame_id={c3['swap_frame_ids_unique']}; first={c3['swap_first']}; last={c3['swap_last']}",
          f"- last MKS-FUSION committed after return: " + (f"L{c3['fusion_committed_last']['line']} `{c3['fusion_committed_last']['msg'][-60:]}`" if c3['fusion_committed_last'] else '—'),
          f"- time-pos advanced ≥15 s after return: {c3['time_pos_advanced_ge_15s']}", '']
    c4 = a['c4_errors']
    L += ['## C4 errors (whole log)', '',
          f"- BridgeActivationIssue: {c4['BridgeActivationIssue']} {[r['line'] for r in c4['BridgeActivationIssue_lines']]}",
          f"- authorize failed/stale/skipped/abandoned or non-ok result: {c4['authorize_failed_stale_skipped_abandoned_or_non_ok']} {[r['line'] for r in c4['authorize_bad_lines']]}",
          f"- HdrErrorEvent total={c4['HdrErrorEvent_total']} (noDisplayCapabilityReport single-open pre-existing={c4['HdrErrorEvent_noDisplayCapabilityReport(single-open, pre-existing)']}, other={c4['HdrErrorEvent_other']} {[r['line'] for r in c4['HdrErrorEvent_other_lines']]})",
          f"- **C4 pass: {c4['pass']}**", '']
    i = a['identity']
    L += ['## C5 process', '',
          f"- pid before={i['pid_before']} after={i['pid_after']} same={i['same_pid']}; am_proc_start(pkg)={[r['line'] for r in i['am_proc_start_pkg']]}; am_proc_died(pkg)={[r['line'] for r in i['am_proc_died_pkg']]}",
          f"- FATAL/tombstone text lines={i['fatal_count']} {[r['line'] for r in i['fatal_lines']]}; F-level lines={i['F_level_lines']}; ANR/am_crash lines={i['anr_crash_count']} {[r['line'] for r in i['anr_crash_lines']]}",
          f"- **C5 pass: {a['c5_process']['pass']}**", '']
    c6 = a['c6_hdr']
    L += ['## C6 HDR', '',
          f"- MKSURF-E1 dataspace applied: pre-HOME {[('L%d' % r['line']) for r in c6['e1_dataspace_pre_home']]}; after HOME {[('L%d' % r['line']) for r in c6['e1_dataspace_after_home']]}",
          f"- HDR decision applied pre-HOME: {c6['decision_applied_pre_home']}",
          f"- HDR decision applied after HOME: {c6['decision_applied_after_home']} (decision lines after HOME: {c6['decision_lines_after_home']})",
          f"- route consistent: {c6['route_decision_consistent']} — {c6['route_note']}",
          f"- HDR_SESSION_REPORT hwdecCurrent: pre-HOME={c6['hdr_report_hwdec_pre_home']}; reports after HOME={c6['hdr_reports_after_home']}; last in log={c6['hdr_report_last_in_log']}; all surfacetexture={c6['hwdec_reports_all_surfacetexture_from_pre_home_on']}",
          f"- SF dumps: pre-home={c6['sf_pre_home']} post-return={c6['sf_post_return']}",
          f"- **C6 pass: {c6['pass']}**", '']
    c7 = a['c7_fast']
    L += ['## C7 HOME cycle intervals (Java level)', '', '| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |', '|---|---|---|---|---|---|']
    for c in c7['home_cycles']:
        L.append(f"| L{c['sd_line']} | {c['sd_t']} | {('L%d' % c['sc_line']) if c['sc_line'] else '—'} | {c['sc_t'] or '—'} | {c['sd_to_sc_ms'] if c['sd_to_sc_ms'] is not None else '—'} | {c['shutdown_exit_vs_sc']} (L{c['shutdown_exit_line']}) |")
    L += ['', f"- SurfaceFailed/RuntimeFailed: {c7['SurfaceFailed_or_RuntimeFailed']}", '']
    td = a['teardown']
    L += ['## Teardown window errors', '',
          f"- surfaceDestroyed enter: {('L%d %s' % (td['surfaceDestroyed_enter']['line'], td['surfaceDestroyed_enter']['time'])) if td['surfaceDestroyed_enter'] else 'MISSING'}; shutdown exit: {('L%d %s' % (td['shutdown_exit']['line'], td['shutdown_exit']['time'])) if td['shutdown_exit'] else 'MISSING'} (Δ={td.get('shutdown_exit_minus_sd_ms')} ms); vo=null ack: {('L%d %s' % (td['vo_null_ack']['line'], td['vo_null_ack']['time'])) if td['vo_null_ack'] else 'MISSING'}",
          f"- am_pause_activity: {('L%d %s' % (td['am_pause_activity']['line'], td['am_pause_activity']['time'])) if td['am_pause_activity'] else '—'}; am_on_stop_called: {('L%d %s' % (td['am_on_stop_called']['line'], td['am_on_stop_called']['time'])) if td['am_on_stop_called'] else '—'}; am_resume_activity: {('L%d %s' % (td['am_resume_activity']['line'], td['am_resume_activity']['time'])) if td['am_resume_activity'] else '—'}"]
    if td.get('window'):
        L += [f"- window: {td['window']['from']} .. {td['window']['to']}", '', '| pattern | in window | whole log | pre-HOME | lines (window) |', '|---|---|---|---|---|']
        for k, v in td['error_counts'].items():
            L.append(f"| {k} | {v['in_window']} | {v['whole_log']} | {v['pre_home']} | {v['in_window_lines']} |")
    L += ['', '## Whole-log counts', '', '| key | n |', '|---|---|'] + [f"| {k} | {v} |" for k, v in a['counts'].items()] + ['']
    return '\n'.join(L) + '\n'


if __name__ == '__main__':
    args = sys.argv[1:]
    outdir = None
    if args and args[0] == '--outdir':
        outdir = pathlib.Path(args[1]); args = args[2:]
        outdir.mkdir(parents=True, exist_ok=True)
    for arg in args:
        rd = pathlib.Path(arg)
        a = analyze(rd)
        if outdir is not None:  # do not write into foreign evidence dirs (pre-fix rounds)
            name = rd.name if rd.name != 'smoke-prefix' else 'p3p1-smoke-prefix'
            (outdir / f'{name}.analysis.json').write_text(json.dumps(a, indent=1, ensure_ascii=False))
            (outdir / f'{name}.analysis.md').write_text(md(a))
        else:
            (rd / 'analysis.json').write_text(json.dumps(a, indent=1, ensure_ascii=False))
            (rd / 'analysis.md').write_text(md(a))
        p = {k: a.get(k, {}).get('pass') for k in ('pre_home', 'c1_time_chain', 'c2_after_return', 'c4_errors', 'c5_process', 'c6_hdr')}
        print(f"{rd.name}: pid={a.get('app_pid')} lines={a.get('log_lines')} pass={p} c3_adv={a.get('c3_playback_after_return', {}).get('time_pos_advanced_ge_15s')} teardown={ {k: v['in_window'] for k, v in a.get('teardown', {}).get('error_counts', {}).items()} }")
