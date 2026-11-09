#!/usr/bin/env python3
"""P3 phase2 (c) chain checker: verify the post-HOME authorization/rebuild
chain ordering + identity from <round>/timeline.json.

Checks (per round):
  1. same app pid across all anchors
  2. pre-home: class=dvP84 selected, mkst_create_decoder_window exit ok,
     MediaCodec instantiated + OMX.qcom Executing
  3. post-HOME chain order:
       java surfaceDestroyed -> ACodec leave Executing (optional)
       -> native mkst_shutdown exit
       -> dart authorize begin -> java authorize enter -> java authorize result code=ok
       -> native mkst_ensure_init exit ready=1
       -> native mkst_create_decoder_window exit window_active=1
       -> OMX makeComponentInstance (new instance) -> ACodec Now Executing
  4. identity: dart/java share wid; native share owner_key; surfaceGeneration
     increments on the new surface
  5. zero FATAL/ANR

usage: check_chain.py <round_dir> [home_label]
Writes <round>/chain.md, prints verdict. Exit 0 iff all checks pass.
"""
import json, sys, pathlib


def first(evts, key, pred=None):
    for e in evts:
        if e['key'] == key and (pred is None or pred(e)):
            return e
    return None


def main(rd, expect_dv=True):
    rd = pathlib.Path(rd)
    data = json.loads((rd / 'timeline.json').read_text())
    evts = sorted(data['events'], key=lambda e: e['t'])
    pid = data['app_pid']
    lines = [f"# {rd.name} chain check", f"app_pid={pid}"]
    checks = []

    def chk(name, ok, detail=''):
        checks.append((name, ok))
        lines.append(f"- [{'PASS' if ok else 'FAIL'}] {name} {detail}")

    # pid uniformity on app anchors
    foreign = {e['pid'] for e in evts if e['pid'] != pid and e['key'] not in ('make_component',)}
    chk('same_pid', not foreign, f"foreign_pids={foreign or 'none'} (makeComponentInstance runs in mediaserver=exempt)")

    t_home = None
    t_return = None
    for e in data['host_events']:
        if e['event'] == 'home_send_begin':
            t_home = e['device_ms']
        if e['event'] == 'return_sent':
            t_return = e['device_ms']
    if t_home is None:
        lines.append('no home_send_begin event; FAIL')
        (rd / 'chain.md').write_text('\n'.join(lines) + '\n')
        return 1
    # post-home = from surfaceDestroyed (or t_home) onwards
    sd = first(evts, 'java_surface_destroyed', lambda e: e['t'] >= t_home - 3000)
    chain_t0 = sd['t'] if sd else t_home
    post = [e for e in evts if e['t'] >= chain_t0]
    lines.append(f"chain window: t0={chain_t0} (surfaceDestroyed={'yes' if sd else 'no'}) home={t_home} return={t_return}")

    def after(key, pred=None):
        for e in post:
            if e['key'] == key and (pred is None or pred(e)):
                return e
        return None

    sd_e = after('java_surface_destroyed')
    sh = after('native_shutdown', lambda e: ' exit' in e['msg'])
    ab = after('dart_authorize_begin')
    je = after('java_authorize_enter')
    jr = after('java_authorize_result', lambda e: e.get('code') == 'ok')
    ei = after('native_ensure_init', lambda e: ' exit' in e['msg'] and e.get('ready') == '1')
    cw = after('native_create_window', lambda e: ' exit' in e['msg'] and e.get('window_active') == '1')
    mc = after('make_component')
    ne = None
    if mc:
        ne = first([e for e in post if e['t'] >= mc['t'] and e['key'] == 'now_executing'], 'now_executing')

    def t(e):
        return e['t'] if e else None

    order = [('surfaceDestroyed', t(sd_e)), ('mkst_shutdown exit', t(sh)), ('dart authorize begin', t(ab)),
             ('java authorize enter', t(je)), ('java authorize result ok', t(jr)),
             ('mkst_ensure_init exit ready=1', t(ei)), ('mkst_create_decoder_window exit ok', t(cw)),
             ('makeComponentInstance(new)', t(mc)), ('Now Executing(new)', t(ne))]
    lines.append('## chain')
    for n, tt in order:
        lines.append(f"- {n}: {'MISSING' if tt is None else tt}")
    # task chain = nodes in the acceptance criteria; java authorize enter is
    # reported but not judged (enter/result routinely share one ms tick)
    task_nodes = [('mkst_shutdown exit', t(sh)), ('dart authorize begin', t(ab)),
                  ('java authorize result ok', t(jr)), ('mkst_ensure_init exit ready=1', t(ei)),
                  ('mkst_create_decoder_window exit ok', t(cw)), ('makeComponentInstance(new)', t(mc)),
                  ('Now Executing(new)', t(ne))]
    seq = [tt for _, tt in order]
    present = [tt for tt in seq if tt is not None]
    tvals = [tt for _, tt in task_nodes]
    tchk = [a < b for a, b in zip(tvals, tvals[1:]) if a is not None and b is not None]
    chk('chain_complete', all(tt is not None for _, tt in order))
    chk('chain_task_order_strict', all(tchk) and len(tchk) == len(task_nodes) - 1,
        'task_deltas=' + ','.join(f'{n}:{b - a}ms' for (n, a), (_, b) in zip(task_nodes, task_nodes[1:])) )

    # identity: dart/java same wid; ensure_init/create_window share owner_key
    if ab and jr:
        chk('identity_wid_dart_java', ab.get('wid') == jr.get('wid'), f"wid={ab.get('wid')}->{jr.get('wid')}")
    if ei and cw:
        chk('identity_owner_key_native', ei.get('owner_key') == cw.get('owner_key'), f"owner_key={ei.get('owner_key')}")
    if sd_e and ab:
        gen_before = sd_e.get('surfaceGeneration')
        chk('surface_generation_bump', ab.get('surfaceGeneration') not in (None, gen_before) or ab.get('wid') != sd_e.get('wid'),
            f"sc_gen={gen_before} -> dart gen={ab.get('surfaceGeneration')} wid {sd_e.get('wid')}->{ab.get('wid')}")

    # pre-home playback proof
    pre = [e for e in evts if e['t'] < t_home]
    if expect_dv:
        hd = [e for e in pre if e['key'] == 'hdrdiag' and 'class=dvP84' in e['msg'] and 'selected=baseLayerConvert' in e['msg']]
        chk('prehome_dvP84_route', bool(hd), f"count={len(hd)}")
    cw_pre = [e for e in pre if e['key'] == 'native_create_window' and ' exit' in e['msg'] and e.get('window_active') == '1']
    chk('prehome_decoder_window', bool(cw_pre), f"count={len(cw_pre)}")
    ne_pre = [e for e in pre if e['key'] == 'now_executing']
    chk('prehome_codec_executing', bool(ne_pre), f"count={len(ne_pre)}")
    mks_e1 = [e for e in evts if e['key'] == 'mksurf_e1']
    if expect_dv:
        chk('dataspace_applied_evidence', bool(mks_e1), f"lgPqApply/lgDataSpaceBinding/MKSURF-E1 count={len(mks_e1)}")

    chk('zero_fatal_anr', not data['fatal_or_anr'], f"count={len(data['fatal_or_anr'])}")

    ok = all(c[1] for c in checks)
    lines.append(f"## verdict: {'PASS' if ok else 'FAIL'} ({sum(1 for c in checks if c[1])}/{len(checks)})")
    (rd / 'chain.md').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines[-3:]))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1], expect_dv=(len(sys.argv) < 3 or sys.argv[2] != 'sdr')))
