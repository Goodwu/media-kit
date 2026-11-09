#!/usr/bin/env python3
"""Quick Java-level interval check for fast HOME rounds.

Prints, from <round>/logcat-full.txt (MKS-HOME-TRACE rt= values, device ms):
  - every java surfaceDestroyed/surfaceCreated enter (rt, viewId, generation)
  - every native mkst_shutdown enter/exit (rt)
  - for each HOME-cycle (surfaceDestroyed followed by a later surfaceCreated):
      interval surfaceDestroyed enter -> surfaceCreated enter
      ordering of surfaceCreated vs mkst_shutdown exit + delta
"""
import re, sys, pathlib

RT = re.compile(r'\brt=(\d{13})\b')
fmt = lambda t: __import__('datetime').datetime.fromtimestamp(t/1000).strftime('%H:%M:%S.%f')[:-3]

def main(rd):
    events = []
    p = pathlib.Path(rd) / 'logcat-full.txt'
    for i, line in enumerate(p.open(errors='replace'), 1):
        if 'MKS-HOME-TRACE' not in line:
            continue
        m = RT.search(line)
        if not m:
            continue
        t = int(m.group(1))
        kind = None
        if 'surfaceDestroyed enter' in line: kind = 'sd'
        elif 'surfaceCreated enter' in line: kind = 'sc'
        elif 'mkst_shutdown enter' in line: kind = 'sh_in'
        elif 'mkst_shutdown exit' in line: kind = 'sh_out'
        if kind:
            vid = re.search(r'viewId=(\d+)', line)
            events.append((t, kind, vid.group(1) if vid else '', i))
    events.sort()
    print(f"{p}: {len(events)} trace events")
    for t, kind, vid, ln in events:
        print(f"  {fmt(t)} rt={t} {kind:5s} viewId={vid} L{ln}")
    # pair each sd with the next sc after it
    print('--- HOME cycles ---')
    n = 0
    for idx, (t, kind, vid, ln) in enumerate(events):
        if kind != 'sd':
            continue
        nxt_sc = next((e for e in events[idx+1:] if e[1] == 'sc'), None)
        if not nxt_sc:
            print(f"  sd@{fmt(t)} -> no later surfaceCreated")
            continue
        n += 1
        # bound the cycle at the next surfaceDestroyed so shutdowns of a later
        # cycle (e.g. the cold-start view0->view1 swap) are not misattributed
        nxt_sd = next((e for e in events[idx+1:] if e[1] == 'sd'), None)
        cyc_end = min(nxt_sd[0], 10**13) if nxt_sd else 10**13
        sh_out = next((e for e in events[idx+1:] if e[1] == 'sh_out' and e[0] <= min(nxt_sc[0], cyc_end)), None)
        sh_out_any = next((e for e in events[idx+1:] if e[1] == 'sh_out' and e[0] < cyc_end), None)
        d = nxt_sc[0] - t
        order = ''
        if sh_out:
            order = f"shutdown_exit {('BEFORE' if sh_out[0] < nxt_sc[0] else 'AFTER')} surfaceCreated by {abs(nxt_sc[0]-sh_out[0])} ms (sh_exit rt={sh_out[0]})"
        elif sh_out_any:
            order = f"surfaceCreated BEFORE shutdown_exit by {sh_out_any[0]-nxt_sc[0]} ms  <<< surfaceCreated first (sh_exit rt={sh_out_any[0]} L{sh_out_any[3]})"
        else:
            order = 'no shutdown in log'
        print(f"  cycle{n}: sd rt={t} (L{ln}) -> sc rt={nxt_sc[0]} (L{nxt_sc[3]}): interval {d} ms | {order}")

if __name__ == '__main__':
    for a in sys.argv[1:]:
        main(a)
