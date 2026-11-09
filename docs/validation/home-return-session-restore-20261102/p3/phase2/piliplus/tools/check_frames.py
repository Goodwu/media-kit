#!/usr/bin/env python3
"""P3 phase2 (c) frame-advance verdict from <round>/timeline.json samples.

Writes <round>/frames.md. Frame evidence = SurfaceFlinger --latency
actualPresentTime (max non-zero per sample) on the app SurfaceView layer;
supporting: media_session PlaybackState and per-thread cpu deltas.

usage: check_frames.py <round_dir>
"""
import json, sys, pathlib


def main(rd):
    rd = pathlib.Path(rd)
    d = json.loads((rd / 'timeline.json').read_text())
    S = {s['label']: s for s in d['samples']}
    lines = [f"# {rd.name} frame-advance check", '']
    checks = []

    def chk(name, ok, detail=''):
        checks.append((name, ok))
        lines.append(f"- [{'PASS' if ok else 'FAIL'}] {name} {detail}")

    def sf(lbl):
        s = S.get(lbl)
        return s.get('sf_last_present_ns') if s else None

    def st(lbl):
        s = S.get(lbl)
        return s.get('playback_state') if s else None

    def devms(lbl):
        return S[lbl]['device_ms'] if lbl in S else None

    # pre-home advancing
    if 'play_start' in S and 'pre_home_1' in S:
        a, b = sf('play_start'), sf('pre_home_1')
        gap = devms('pre_home_1') - devms('play_start')
        ok = a is not None and b is not None and (b - a) > 0.5 * gap * 1e6
        chk('prehome_frames_advance', ok, f"present {a}->{b} ns (+{(b - a)/1e9:.1f}s frames / {gap/1000:.1f}s wall), state {st('play_start')}->{st('pre_home_1')}")
    # during home frozen (normal mode only)
    if 'during_home_1' in S and 'during_home_2' in S:
        a, b = sf('during_home_1'), sf('during_home_2')
        lines.append(f"- during-home sf: {a} -> {b} (layer gone = 0 expected; states {st('during_home_1')}/{st('during_home_2')})")
    # post-return advancing
    prs = [l for l in ('post_return_1', 'post_return_2', 'post_return_3') if l in S]
    for a, b in zip(prs, prs[1:]):
        va, vb = sf(a), sf(b)
        gap = devms(b) - devms(a)
        ok = va is not None and vb is not None and (vb - va) > 0.5 * gap * 1e6
        chk(f'postreturn_frames_advance[{a}->{b}]', ok,
            f"present {va}->{vb} ns (+{(vb - va)/1e9:.1f}s frames / {gap/1000:.1f}s wall), state {st(b)}")
    # resume state
    if prs:
        last_st = st(prs[-1])
        chk('playback_resumed', last_st == 3, f"final state={last_st} (3=playing)")
    # thread activity support
    for ta in d.get('thread_activity', []):
        if ta['from'].startswith('post_return'):
            names = {t['comm'] for t in ta['top_threads']}
            media_active = bool(names & {'(demux)', 'MediaCodec_loop', 'JNISurfaceTextu', 'Thread-9', 'Thread-7', 'Thread-8'})
            chk(f"threads_active[{ta['from']}->{ta['to']}]", media_active, f"top={sorted(names)[:5]}")
    ok = all(c[1] for c in checks)
    lines.append(f"## verdict: {'PASS' if ok else 'FAIL'} ({sum(1 for c in checks if c[1])}/{len(checks)})")
    (rd / 'frames.md').write_text('\n'.join(lines) + '\n')
    print(lines[-1])
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
