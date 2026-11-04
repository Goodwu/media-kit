#!/usr/bin/env python3
"""ff-seek analyzer: UI seek -> first NEW video frame.
Parses dense SF/media_session samples (ff_sample.sh format) + logcat anchors.
Usage: analyze_seek.py <round_dir>
Reads: dense-samples.txt, logcat-full.txt, host-events.ndjson
Writes: analysis.json, presents.csv, intervals.csv, segments.md
All times -> device epoch ms (CLOCK_REALTIME), same base as ff-attr analyze_ff.py.

First-new-frame definition (operationalized for in-place seek, decoder not
rebuilt): after SK_SEEK_CMD marker t0, old-GOP presents continue; the decoder
flushes; a present-free freeze gap follows; the present TERMINATING the longest
gap in [t0, t0+20s] is the first new-frame candidate, cross-checked against
post-seek run cadence (must start a sustained run >=5 presents/800ms).
"""
import json, os, re, statistics, sys
from datetime import datetime

ROUND = sys.argv[1] if len(sys.argv) > 1 else None

def read(p):
    fp = os.path.join(ROUND, p)
    if not os.path.exists(fp):
        return None
    with open(fp, "r", errors="replace") as f:
        return f.read()

def parse_dense(text):
    if text is None:
        return [], {}
    lines = text.splitlines()
    iters, markers, cur = [], {}, None
    num3 = re.compile(r"^(\d+)\s+(\d+)\s+(\d+)$")
    st = re.compile(r"state=PlaybackState \{state=(\d+), position=(\d+)")
    sf_done = False
    for ln in lines:
        if ln.startswith("S|"):
            p = ln.split("|")
            cur = {"i": int(p[1]), "uptime": p[2], "epoch_ms": int(float(p[3]) * 1000),
                   "presents": [], "state": None, "pos": None}
            iters.append(cur)
            sf_done = False
            continue
        if "|" in ln:
            tok = ln.split("|", 1)[0]
            if tok not in ("S", "E") and re.fullmatch(r"[A-Z][A-Z0-9_]*", tok):
                p = ln.split("|")
                if len(p) >= 3:
                    try:
                        markers[tok] = int(float(p[2]) * 1000)
                        continue
                    except ValueError:
                        pass
        if cur is None:
            continue
        m = num3.match(ln.strip())
        if m and not sf_done:
            d, a, r = int(m.group(1)), int(m.group(2)), int(m.group(3))
            if a != 0:
                cur["presents"].append(a)
            continue
        if m:
            continue
        ms = st.search(ln)
        if ms:
            cur["state"], cur["pos"] = int(ms.group(1)), int(ms.group(2))
            sf_done = True
    return iters, markers

LINE_RE = re.compile(r"^(\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2}\.\d{3})\s+(\d+)\s+(\d+)\s+([A-Z])\s+(\S+)\s*: (.*)$")
RT_RE = re.compile(r"\brt=(\d+)")
MONO_RE = re.compile(r"\bmono=(\d+)")

def parse_logcat(text):
    events, offs = [], []
    if text is None:
        return events, offs
    for ln in text.splitlines():
        m = LINE_RE.match(ln)
        if not m:
            continue
        mmdd, hms, pid, tid, lvl, tag, msg = m.groups()
        try:
            dt = datetime.strptime("2026-" + mmdd + " " + hms, "%Y-%m-%d %H:%M:%S.%f")
            wall_ms = int(dt.timestamp() * 1000)
        except ValueError:
            continue
        rtm, mom = RT_RE.search(msg), MONO_RE.search(msg)
        rt = int(rtm.group(1)) if rtm else None
        if rt is not None and mom:
            offs.append(rt - int(mom.group(1)))
        events.append({"epoch_ms": rt if rt is not None else wall_ms, "wall_ms": wall_ms,
                       "pid": int(pid), "tag": tag, "msg": msg})
    return events, offs

def cadence(presents_ms, t0, t1, label):
    w = [p for p in presents_ms if t0 <= p <= t1]
    iv = [(b - a, a, b) for a, b in zip(w, w[1:])]
    if not iv:
        return {"label": label, "frames": len(w), "intervals": 0}
    med = statistics.median([d for d, _, _ in iv])
    good = [d for d, _, _ in iv if d <= max(1.5 * med, med + 20)]
    med2 = statistics.median(good) if good else med
    judder = [x for x in iv if x[0] > 2 * med2]
    wins = []
    for d, a, b in judder:
        if wins and a - wins[-1][1] <= 2 * med2:
            wins[-1][1] = b
        else:
            wins.append([a, b])
    return {"label": label, "frames": len(w), "intervals": len(iv), "median_iv_ms": round(med2, 1),
            "max_iv_ms": max(d for d, _, _ in iv), "mean_iv_ms": round(sum(d for d, _, _ in iv) / len(iv), 1),
            "judder_events": len(judder), "judder_windows": [[a, b] for a, b in wins]}

def main():
    out = {"round": ROUND}
    evts, offs = parse_logcat(read("logcat-full.txt"))
    cals = []
    for e in evts:
        if e["wall_ms"] is not None:
            rtm = RT_RE.search(e["msg"])
            if rtm:
                cals.append(int(rtm.group(1)) - e["wall_ms"])
    wall_cal = statistics.median(cals) if cals else None
    if wall_cal is not None:
        for e in evts:
            if e["wall_ms"] is not None and RT_RE.search(e["msg"]) is None:
                e["epoch_ms"] = e["wall_ms"] + wall_cal
    mono_off = statistics.median(offs) if offs else None
    out["logcat"] = {"events": len(evts), "rt_mono_offset_ms": mono_off, "wall_cal_ms": wall_cal}

    host = {}
    hev = read("host-events.ndjson")
    if hev:
        for ln in hev.splitlines():
            try:
                j = json.loads(ln)
            except json.JSONDecodeError:
                continue
            if "device_ms" in j and j.get("event"):
                host.setdefault(j["event"], j)
    out["host_events"] = {k: v.get("device_ms") for k, v in host.items() if v.get("device_ms")}
    notes = {k: v.get("note") for k, v in host.items() if v.get("note")}
    if notes:
        out["host_event_notes"] = notes

    iters, markers = parse_dense(read("dense-samples.txt"))
    periods = [b["epoch_ms"] - a["epoch_ms"] for a, b in zip(iters, iters[1:])]
    out["sampler"] = {"iterations": len(iters),
                      "period_ms_median": round(statistics.median(periods), 1) if periods else None,
                      "period_ms_max": max(periods) if periods else None,
                      "markers_epoch_ms": markers}
    allp = sorted({p for it in iters for p in it["presents"]})
    if mono_off is not None:
        presents_ms = [p // 1000000 + mono_off for p in allp]
    else:
        presents_ms = [p // 1000000 for p in allp]
    states = [{"epoch_ms": it["epoch_ms"], "state": it["state"], "pos": it["pos"]}
              for it in iters if it["state"] is not None]
    sser = []
    for s in states:
        if not sser or (sser[-1]["state"], sser[-1]["pos"]) != (s["state"], s["pos"]):
            sser.append(s)
    out["media_state_series"] = sser

    with open(os.path.join(ROUND, "presents.csv"), "w") as f:
        f.write("present_epoch_ms,mono_ns\n")
        for p, pm in zip(allp, presents_ms):
            f.write(f"{pm},{p}\n")

    t0 = markers.get("SK_SEEK_RELEASE") or markers.get("SK_SEEK_CMD")
    A = {"seek_cmd_ms": markers.get("SK_SEEK_CMD"), "t0_release_ms": t0}
    A["last_present_before_cmd"] = max([p for p in presents_ms if t0 is not None and p <= t0], default=None)
    win = [p for p in presents_ms if t0 is not None and t0 <= p <= t0 + 20000]
    A["presents_in_20s_after_cmd"] = len(win)
    # freeze gap: longest interval within [t0, t0+20s] (>=150ms to count as freeze)
    iv = [(b - a, a, b) for a, b in zip(win, win[1:])]
    gaps = sorted([x for x in iv if x[0] >= 150], reverse=True)
    A["gaps_ge_150ms"] = [[a, b, d] for d, a, b in gaps]
    first_new = None
    freeze = None
    if gaps:
        d, a, b = gaps[0]
        # first new frame = present ending the longest gap, if it starts a sustained run
        nxt = [q for q in win if b <= q <= b + 800]
        if len(nxt) >= 5:
            first_new, freeze = b, [a, b, d]
        else:
            A["note_longest_gap_not_sustained"] = True
    if first_new is None:
        # fallback: first present after cmd starting a sustained run
        for p in win:
            nxt = [q for q in win if p <= q <= p + 800]
            if len(nxt) >= 5:
                first_new = p
                break
    A["first_new_frame_present"] = first_new
    A["freeze_gap"] = freeze  # [start, end, dur]
    if t0 is not None and first_new is not None:
        A["cmd_to_first_new_frame_ms"] = first_new - t0
        # old-frame tail: presents between t0 and freeze start (stale-GOP frames)
        if freeze:
            A["old_frame_tail_ms"] = freeze[0] - t0
        # cadence stability after first new frame
        w2 = [p for p in presents_ms if first_new <= p <= first_new + 15000]
        iv2 = [b - a for a, b in zip(w2, w2[1:])]
        med = statistics.median(iv2) if iv2 else 33
        run, stable = 0, None
        for a, b in zip(w2, w2[1:]):
            if b - a <= 1.5 * med + 10:
                run += 1
                if run >= 10:
                    stable = b - 10 * (b - a)
                    break
            else:
                run = 0
        A["cadence_stable_from"] = stable
        A["first_new_to_stable_ms"] = (stable - first_new) if stable else None
        out["cadence"] = [cadence(presents_ms, first_new, first_new + 5000, "first5s"),
                          cadence(presents_ms, first_new + 5000, first_new + 12000, "5to12s")]
        with open(os.path.join(ROUND, "intervals.csv"), "w") as f:
            f.write("label,present_a_ms,present_b_ms,interval_ms\n")
            for a, b in zip(w2, w2[1:]):
                f.write(f"post_first_new,{a},{b},{b-a}\n")
    # codec-side events in window (seek flushes; rebuild control lines expected 0)
    t_end = (iters[-1]["epoch_ms"] if iters else (t0 or 0) + 25000)
    codec = []
    for e in evts:
        if t0 is None:
            continue
        if not (t0 - 500 <= e["epoch_ms"] <= t_end):
            continue
        for pat, name in ((r"ExecutingState flushing now \(codec owns (\d+)/(\d+) input", "flush_input"),
                          (r"Now Flushing", "now_flushing"), (r"Now Executing", "now_executing"),
                          (r"Now handling output port settings change", "port_change"),
                          (r"Allocating (\d+) meta buffers", "meta_buffers"),
                          (r"makeComponentInstance", "make_component"),
                          (r"authorize (begin|result)", "authorize"),
                          (r"mkst_create_decoder_window|mkst_shutdown", "mkst_bridge"),
                          (r"surfaceCreated enter|surfaceDestroyed enter", "surface_events")):
            m = re.search(pat, e["msg"])
            if m:
                codec.append({"at_ms": e["epoch_ms"] - t0, "event": name,
                              "detail": m.group(0)[:80]})
                break
    A["codec_events_rel_ms"] = codec
    out["anchors"] = A
    with open(os.path.join(ROUND, "analysis.json"), "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    # human summary
    with open(os.path.join(ROUND, "segments.md"), "w") as f:
        f.write(f"# {os.path.basename(ROUND.rstrip('/'))} segments\n\n")
        f.write(f"- seek_cmd t0 = {t0}\n")
        f.write(f"- first_new_frame_present = {first_new} (cmd+{A.get('cmd_to_first_new_frame_ms')} ms)\n")
        if freeze:
            f.write(f"- freeze gap = {freeze[2]} ms ({freeze[0]} -> {freeze[1]}), old-frame tail {A.get('old_frame_tail_ms')} ms\n")
        f.write(f"- codec events (rel t0): " + "; ".join(f"{int(c['at_ms']):+d}ms {c['event']} {c['detail']}" for c in codec[:20]) + "\n")
    print(json.dumps({k: v for k, v in out.items() if k not in ("media_state_series", "host_event_notes")}, indent=1, ensure_ascii=False)[:5000])

if __name__ == "__main__":
    main()
