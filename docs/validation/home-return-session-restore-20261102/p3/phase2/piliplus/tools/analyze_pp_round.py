#!/usr/bin/env python3
"""P3 phase2 (c) PiliPlus per-round analyzer (LG H870DS, Android 7).

Reads <round>/logcat-full.txt (+ logcat-pre-home.txt), host-events.ndjson and
sample-* evidence files; writes <round>/timeline.json + timeline.md.
Pure extraction; every log item carries the 1-based line number in
logcat-full.txt. Event time = rt= (CLOCK_REALTIME ms) when present, else the
threadtime wallclock stamp (both comparable; device TZ Asia/Shanghai).

usage: analyze_pp_round.py <round_dir> [<round_dir> ...]
"""
import json, re, sys, datetime, pathlib

TZ = datetime.timezone(datetime.timedelta(hours=8))
YEAR = 2026
PKG = 'com.example.piliplus.dev'
LOG_RE = re.compile(r'^(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\.(\d\d\d)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+(.*)$')
RT_RE = re.compile(r'\brt=(\d{13})\b')

ANCHORS = [
    # (key, tag regex on msg) -- specific first, catch-alls LAST
    ('dart_authorize_begin', re.compile(r'MKS-HOME-TRACE rt=\d+ dart .* authorize begin ')),
    ('dart_authorize_result', re.compile(r'MKS-HOME-TRACE rt=\d+ dart .* authorize result ')),
    ('java_authorize_enter', re.compile(r'MKS-HOME-TRACE: .* java authorize enter ')),
    ('java_authorize_result', re.compile(r'MKS-HOME-TRACE: .* java authorize result ')),
    ('java_surface_created', re.compile(r'MKS-HOME-TRACE: .* java surfaceCreated ')),
    ('java_surface_destroyed', re.compile(r'MKS-HOME-TRACE: .* java surfaceDestroyed ')),
    ('native_ensure_init', re.compile(r'MKS-HOME-TRACE: .* native mkst_ensure_init')),
    ('native_create_window', re.compile(r'MKS-HOME-TRACE: .* native mkst_create_decoder_window')),
    ('native_shutdown', re.compile(r'MKS-HOME-TRACE: .* native mkst_shutdown')),
    ('native_latch', re.compile(r'MKS-HOME-TRACE: .* native mkst_latch')),
    ('hdrdiag', re.compile(r'flutter : HdrDiag')),
    ('mksurf_e1', re.compile(r'MKSURF-E1|lgPqApply stage=perform|lgDataSpaceBinding stage=public-bridge')),
    ('mediacodec_create', re.compile(r'MediaCodec: Mediacodec create pid=')),
    ('make_component', re.compile(r'OMXMaster: makeComponentInstance')),
    ('now_executing', re.compile(r'ACodec  : \[.*\] Now Executing$')),
    ('acodec_die', re.compile(r'ACodec  : \[.*\] Now Executing->Idle|\[\w+\] uninitialized|Now uninitialized')),
    ('dart_other', re.compile(r'MKS-HOME-TRACE rt=\d+ dart ')),
    ('java_other', re.compile(r'MKS-HOME-TRACE: ')),
]
FATAL_RE = re.compile(r'FATAL EXCEPTION|FATAL: |beginning of crash|ANR in ')


def parse_time(mo, d, hh, mm, ss, ms):
    try:
        return int(datetime.datetime(YEAR, int(mo), int(d), int(hh), int(mm), int(ss), int(ms) * 1000, tzinfo=TZ).timestamp() * 1000)
    except ValueError:
        return None


def load_log(path):
    rows = []
    with path.open(errors='replace') as f:
        for ln, line in enumerate(f, 1):
            line = line.rstrip('\n')
            m = LOG_RE.match(line)
            if not m:
                continue
            mo, d, hh, mm, ss, ms, pid, tid, lvl, msg = m.groups()
            lc = parse_time(mo, d, hh, mm, ss, ms)
            if lc is None:
                continue
            rt = RT_RE.search(msg)
            rows.append({'ln': ln, 'lc': lc, 't': int(rt.group(1)) if rt else lc,
                         'pid': int(pid), 'tid': int(tid), 'lvl': lvl, 'msg': msg})
    return rows


def kv(msg, key):
    m = re.search(r'\b' + key + r'=([^\s,)]+)', msg)
    return m.group(1) if m else None


def fmt(t):
    if t is None or t > 4102444800000:  # sentinel / beyond 2100
        return None
    return datetime.datetime.fromtimestamp(t / 1000, TZ).strftime('%H:%M:%S.%f')[:-3]


def phase_of(t, phases):
    for name, t0, t1 in phases:
        if t0 <= t <= t1:
            return name
    if t < phases[0][1]:
        return 'pre_round'
    return 'post_round'


def analyze(rd):
    rd = pathlib.Path(rd)
    rows = load_log(rd / 'logcat-full.txt')
    host = []
    for l in (rd / 'host-events.ndjson').read_text().splitlines():
        if l.strip():
            host.append(json.loads(l))
    hv = {}
    for e in host:
        hv.setdefault(e['event'], []).append(e)

    def devms(name, idx=0):
        v = hv.get(name)
        return v[idx]['device_ms'] if v and len(v) > idx else None

    t_launch = devms('am_start_deeplink') or devms('am_start_cold')
    t_home = devms('home_send_begin')
    t_return = devms('return_sent')
    phases = [
        ('startup', t_launch or 0, (t_home or 0) - 1),
        ('home_window', t_home or 0, (t_return or 0) - 1),
        ('post_return', t_return or 0, 10 ** 15),
    ]

    app_pid = None
    for k in ('am_start_deeplink', 'am_start_cold', 'pid_before'):
        for e in hv.get(k, []):
            m = re.search(r'pid=(\d+)', e.get('note', ''))
            if m:
                app_pid = int(m.group(1)); break
        if app_pid:
            break

    events = []
    for r in rows:
        for key, rx in ANCHORS:
            if rx.search(r['msg']):
                e = {'key': key, 'ln': r['ln'], 't': r['t'], 'wall': fmt(r['lc']),
                     'pid': r['pid'], 'tid': r['tid'], 'phase': phase_of(r['t'], phases),
                     'msg': r['msg'][:260]}
                for f in ('wid', 'generation', 'surfaceGeneration', 'viewId', 'owner_key', 'code', 'ready', 'window_active', 'handle', 'initialized'):
                    v = kv(r['msg'], f)
                    if v is not None:
                        e[f] = v
                events.append(e)
                break
    fatals = [{'ln': r['ln'], 'wall': fmt(r['lc']), 'pid': r['pid'], 'msg': r['msg'][:200]}
              for r in rows if FATAL_RE.search(r['msg'])]

    # frame evidence from samples
    samples = []
    for e in host:
        if e['event'] != 'sample':
            continue
        lbl = e['label']
        s = {'label': lbl, 'device_ms': e['device_ms']}
        ms_path = rd / f'sample-{lbl}-mediasession.txt'
        if ms_path.exists():
            txt = ms_path.read_text(errors='replace')
            m = re.search(r'state=PlaybackState \{state=(\d+), position=(\d+).*?updated=(\d+)', txt)
            if m:
                s['playback_state'] = int(m.group(1))
                s['position_ms'] = int(m.group(2))
                s['state_updated'] = int(m.group(3))
        sf_path = rd / f'sample-{lbl}-sflatency.txt'
        if sf_path.exists():
            last_present = 0
            nframes = 0
            for line in sf_path.read_text(errors='replace').splitlines():
                parts = line.split()
                if len(parts) == 3 and parts != ['0', '0', '0']:
                    try:
                        ap = int(parts[1])
                        if ap > 0:
                            last_present = max(last_present, ap)
                            nframes += 1
                    except ValueError:
                        pass
            s['sf_last_present_ns'] = last_present
            s['sf_frame_count'] = nframes
        th_path = rd / f'sample-{lbl}-threads.txt'
        if th_path.exists():
            threads = {}
            for line in th_path.read_text(errors='replace').splitlines():
                parts = line.split()
                if len(parts) >= 4:
                    try:
                        threads[int(parts[0])] = (parts[1], int(parts[2]) + int(parts[3]))
                    except ValueError:
                        pass
            s['threads'] = threads
        samples.append(s)

    # utime deltas between consecutive samples for threads active at end
    thread_activity = []
    for a, b in zip(samples, samples[1:]):
        ta, tb = a.get('threads'), b.get('threads')
        if not ta or not tb:
            continue
        gap_ms = b['device_ms'] - a['device_ms']
        deltas = []
        for tid, (comm, cpu) in tb.items():
            if tid in ta and cpu - ta[tid][1] > 0:
                deltas.append({'tid': tid, 'comm': comm, 'cpu_delta_ticks': cpu - ta[tid][1]})
        deltas.sort(key=lambda d: -d['cpu_delta_ticks'])
        thread_activity.append({'from': a['label'], 'to': b['label'], 'gap_ms': gap_ms,
                                'top_threads': deltas[:6]})
        a.pop('threads', None)  # keep json small; deltas recorded instead
    for s in samples:
        s.pop('threads', None)

    out = {
        'round': rd.name,
        'app_pid': app_pid,
        'pids_seen_on_anchors': sorted({e['pid'] for e in events if e['pid'] == app_pid or True}),
        'phases': {k: {'from': fmt(v[1]), 'to': fmt(v[2])} for k, v in zip([p[0] for p in phases], phases)},
        'events': events,
        'fatal_or_anr': fatals,
        'samples': samples,
        'thread_activity': thread_activity,
        'host_events': host,
    }
    (rd / 'timeline.json').write_text(json.dumps(out, ensure_ascii=False, indent=1))

    md = [f"# {rd.name} timeline", '',
          f"app_pid={app_pid} launch={fmt(t_launch)} home={fmt(t_home)} return={fmt(t_return)}", '',
          '## anchor events (chronologic)']
    for e in sorted(events, key=lambda x: x['t']):
        ident = ' '.join(f"{k}={e[k]}" for k in ('wid', 'generation', 'viewId', 'surfaceGeneration', 'code', 'ready', 'window_active') if k in e)
        md.append(f"- {e['wall']} [{e['phase']}] pid={e['pid']} {e['key']} {ident} (ln {e['ln']})")
    md += ['', '## frame-advance samples']
    for s in samples:
        md.append(f"- {s['label']}: state={s.get('playback_state')} pos={s.get('position_ms')} "
                  f"sf_last_present={s.get('sf_last_present_ns')} sf_frames={s.get('sf_frame_count')}")
    md += ['', '## thread cpu deltas (ticks, 10ms)']
    for ta in thread_activity:
        tops = ', '.join(f"{d['comm']}({d['tid']})+{d['cpu_delta_ticks']}" for d in ta['top_threads'])
        md.append(f"- {ta['from']} -> {ta['to']} (+{ta['gap_ms']}ms): {tops}")
    if fatals:
        md += ['', '## FATAL/ANR']
        md += [f"- ln{f['ln']} {f['wall']} {f['msg']}" for f in fatals]
    (rd / 'timeline.md').write_text('\n'.join(md) + '\n')
    print(f"{rd.name}: {len(events)} anchors, {len(samples)} samples, {len(fatals)} fatal/anr lines")


if __name__ == '__main__':
    for a in sys.argv[1:]:
        analyze(a)
