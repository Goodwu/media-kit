#!/usr/bin/env python3
"""ff-attr analyzer: parse dense SF/media_session samples + logcat anchors ->
per-round segment timeline (return -> first frame), present-cadence stats,
judder windows. Usage: analyze_ff.py <round_dir> [--home-mode|--base-mode]
Reads: dense-samples.txt (home) or dense-a.txt+dense-b.txt (base),
       logcat-full.txt, host-events.ndjson
Writes: analysis.json, presents.csv, intervals.csv, segments.md
All times normalized to device epoch ms (CLOCK_REALTIME, same as logcat wall
time and MKS-HOME-TRACE rt=)."""
import json, os, re, statistics, sys
from datetime import datetime

ROUND = sys.argv[1] if len(sys.argv) > 1 else None
MODE = "home" if "--home-mode" in sys.argv else ("base" if "--base-mode" in sys.argv else "home")

def read(p):
    fp = os.path.join(ROUND, p)
    if not os.path.exists(fp):
        return None
    with open(fp, "r", errors="replace") as f:
        return f.read()

# ---------- parse dense sampler file ----------
def parse_dense(text):
    """-> (iterations, markers) ; iteration = dict(i, uptime, epoch_ms, presents=[ns...], state, pos)"""
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
            if tok != "S" and re.fullmatch(r"[A-Z][A-Z0-9_]*", tok):
                p = ln.split("|")
                if p[0] != "E" and len(p) >= 3:
                    try:
                        markers[p[0]] = int(float(p[2]) * 1000)
                        continue
                    except ValueError:
                        pass
        if cur is None:
            continue
        m = num3.match(ln.strip())
        if m and not sf_done:
            d, a, r = int(m.group(1)), int(m.group(2)), int(m.group(3))
            if a != 0:  # nonzero actualPresent = presented frame
                cur["presents"].append(a)
            continue
        if m:  # all-zero row after media session started: ignore
            continue
        ms = st.search(ln)
        if ms:
            cur["state"], cur["pos"] = int(ms.group(1)), int(ms.group(2))
            sf_done = True
    return iters, markers

# ---------- logcat anchors ----------
LINE_RE = re.compile(r"^(\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2}\.\d{3})\s+(\d+)\s+(\d+)\s+([A-Z])\s+(\S+)\s*: (.*)$")
RT_RE = re.compile(r"\brt=(\d+)")
MONO_RE = re.compile(r"\bmono=(\d+)")

def parse_logcat(text):
    """-> (events, rt_mono_offsets) ; events = list of dict(epoch_ms, pid, tag, msg)"""
    events, offs = [], []
    if text is None:
        return events, offs
    for ln in text.splitlines():
        m = LINE_RE.match(ln)
        if not m:
            continue
        mmdd, hms, pid, tid, lvl, tag, msg = m.groups()
        wall_ms = None
        try:
            dt = datetime.strptime("2026-" + mmdd + " " + hms, "%Y-%m-%d %H:%M:%S.%f")
            wall_ms = int(dt.timestamp() * 1000)  # local TZ; calibrated below via rt=
        except ValueError:
            continue
        rtm, mom = RT_RE.search(msg), MONO_RE.search(msg)
        rt = int(rtm.group(1)) if rtm else None
        if rt is not None and mom:
            offs.append(rt - int(mom.group(1)))  # epoch_ms - mono_ms (constant while awake)
        epoch = rt if rt is not None else wall_ms
        events.append({"epoch_ms": epoch, "wall_ms": wall_ms, "pid": int(pid), "tag": tag, "msg": msg})
    return events, offs

def find(evts, pattern, after=None, before=None, last=False, sub=r""):
    rx = re.compile(pattern)
    hits = [e for e in evts if rx.search(e["msg"])
            and (after is None or e["epoch_ms"] >= after)
            and (before is None or e["epoch_ms"] <= before)]
    if not hits:
        return None
    return (hits[-1] if last else hits[0])["epoch_ms"]

# ---------- cadence ----------
def cadence(presents_ms, t_start, t_end, label):
    w = [p for p in presents_ms if t_start <= p <= t_end]
    iv = [(b - a, a, b) for a, b in zip(w, w[1:])]
    if not iv:
        return {"label": label, "frames": len(w), "intervals": 0}
    med = statistics.median([d for d, _, _ in iv])
    good = [d for d, _, _ in iv if d <= max(1.5 * med, med + 20)]
    med2 = statistics.median(good) if good else med
    judder = [x for x in iv if x[0] > 2 * med2]
    # contiguous judder windows
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
    out = {"round": ROUND, "mode": MODE}
    logcat = read("logcat-full.txt")
    evts, offs = parse_logcat(logcat)
    wall_cal = None
    # calibrate wall->epoch using rt-bearing lines (TZ independent)
    cals = []
    for e in evts:
        if e["wall_ms"] is not None:
            # find rt from same msg if present
            rtm = RT_RE.search(e["msg"])
            if rtm:
                cals.append(int(rtm.group(1)) - e["wall_ms"])
    if cals:
        wall_cal = statistics.median(cals)
        for e in evts:
            if e["wall_ms"] is not None and RT_RE.search(e["msg"]) is None:
                e["epoch_ms"] = e["wall_ms"] + wall_cal
    mono_off = statistics.median(offs) if offs else None  # epoch_ms - mono_ms
    out["logcat"] = {"events": len(evts), "rt_mono_offset_ms": mono_off, "wall_cal_ms": wall_cal,
                     "rt_mono_offset_spread_ms": (max(offs) - min(offs)) if len(offs) > 1 else 0}
    # pull host events (home_sent device_ms etc.)
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

    if MODE == "home":
        iters, markers = parse_dense(read("dense-samples.txt"))
    else:
        itA, mkA = parse_dense(read("dense-a.txt"))
        itB, mkB = parse_dense(read("dense-b.txt"))
        iters, markers = itA + itB, {**mkA, **mkB}
    periods = [b["epoch_ms"] - a["epoch_ms"] for a, b in zip(iters, iters[1:])]
    out["sampler"] = {"iterations": len(iters),
                      "period_ms_median": round(statistics.median(periods), 1) if periods else None,
                      "period_ms_max": max(periods) if periods else None,
                      "markers_epoch_ms": markers}
    # merged present series (mono ns -> epoch ms via mono_off; fallback: per-iteration offset)
    allp = sorted({p for it in iters for p in it["presents"]})
    if mono_off is not None:
        presents_ms = [p // 1000000 + mono_off for p in allp]
    else:
        presents_ms = [p // 1000000 for p in allp]
    # state series
    states = [{"epoch_ms": it["epoch_ms"], "state": it["state"], "pos": it["pos"]}
              for it in iters if it["state"] is not None]
    # dedupe consecutive same-state
    sser = []
    for s in states:
        if not sser or sser[-1]["state"] != s["state"]:
            sser.append(s)
    out["media_state_series"] = sser
    with open(os.path.join(ROUND, "presents.csv"), "w") as f:
        f.write("present_epoch_ms,mono_ns\n")
        for p, pm in zip(allp, presents_ms):
            f.write(f"{pm},{p}\n")

    with open(os.path.join(ROUND, "intervals.csv"), "w") as f:
        f.write("label,present_a_ms,present_b_ms,interval_ms\n")
    if MODE == "home":
        home(out, evts, markers, presents_ms, iters, host)
    else:
        base(out, evts, markers, presents_ms, iters, itA, itB, host)
    with open(os.path.join(ROUND, "analysis.json"), "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    print(json.dumps({k: v for k, v in out.items() if k not in ("media_state_series",)}, indent=1, ensure_ascii=False)[:6000])

def ivcsv(round_dir, presents_ms, t0, t1, label):
    with open(os.path.join(round_dir, "intervals.csv"), "a") as f:
        w = [p for p in presents_ms if t0 <= p <= t1]
        for a, b in zip(w, w[1:]):
            f.write(f"{label},{a},{b},{b-a}\n")

def home(out, evts, markers, presents_ms, iters, host):
    t0 = markers.get("RETURN_CMD")
    hb = host.get("home_send_begin") or {}
    home_dev = hb.get("device_ms") if isinstance(hb, dict) else hb  # before keyevent processed
    if home_dev is None:
        h2 = host.get("home_sent") or {}
        home_dev = (h2.get("device_ms") - 2000) if isinstance(h2, dict) else None
    A = {}
    A["sd_exit"] = find(evts, r"surfaceDestroyed exit", after=home_dev)
    A["mkst_shutdown_exit"] = find(evts, r"mkst_shutdown exit", after=home_dev)
    A["am_start_line"] = find(evts, r"START u0 \{flg=0x10000000 cmp=com\.example\.piliplus\.dev", after=home_dev)
    A["surfaceCreated_enter"] = find(evts, r"surfaceCreated enter", after=t0)
    A["surfaceCreated_exit"] = find(evts, r"surfaceCreated exit", after=t0)
    A["auth_begin_dart"] = find(evts, r"authorize begin", after=t0)
    A["auth_enter_java"] = find(evts, r"java authorize enter", after=t0)
    A["auth_result_java"] = find(evts, r"java authorize result code=ok", after=t0)
    A["ensure_init_exit"] = find(evts, r"mkst_ensure_init\(lc_verify\) exit", after=t0)
    A["window_exit"] = find(evts, r"mkst_create_decoder_window exit .*window_active=1", after=t0)
    A["mediacodec_create"] = find(evts, r"Mediacodec create pid=", after=t0)
    A["make_component"] = find(evts, r"makeComponentInstance", after=t0)
    A["acodec_loaded"] = find(evts, r"Now Loaded$", after=A.get("make_component") or t0)
    A["acodec_executing"] = find(evts, r"Now Executing", after=A.get("make_component") or t0)
    # later flush cycles (post-return, beyond first Executing)
    flushes = [e["epoch_ms"] for e in evts if re.search(r"Now Flushing|output port settings change", e["msg"])
               and e["epoch_ms"] > (A.get("acodec_executing") or 0)]
    A["post_executing_flushes"] = flushes
    post = [p for p in presents_ms if t0 is not None and p > t0]
    A["first_present_after_return"] = min(post) if post else None  # may be isolated bg frame
    # first VIDEO present: first present that begins a sustained run (>=5 presents
    # in the following 800 ms) at/after surfaceCreated (isolated background/
    # placeholder presents on the recreated surface are excluded)
    sc = A["surfaceCreated_enter"]
    vp = None
    for p in post:
        if sc is not None and p < sc:
            continue
        nxt = [q for q in post if p <= q <= p + 800]
        if len(nxt) >= 5:
            vp = p
            break
    A["first_video_present_after_return"] = vp
    if A["first_present_after_return"] and vp:
        A["isolated_bg_presents_before_video"] = [p for p in post if p < vp]
    out["anchors"] = A
    if t0 is not None and vp:
        fp = vp
        # steady cadence start: 10 consecutive intervals within 1.5x of global median
        w = [p for p in presents_ms if fp <= p <= fp + 25000]
        iv = [b - a for a, b in zip(w, w[1:])]
        med = statistics.median(iv) if iv else 33
        A["cadence_stable_from"] = None
        run = 0
        for a, b in zip(w, w[1:]):
            if b - a <= 1.5 * med + 10:
                run += 1
                if run >= 10:
                    A["cadence_stable_from"] = b - 10 * (b - a)
                    break
            else:
                run = 0
        # last codec re-Executing before first video present (flush/port-change cycle)
        last_exec = A["acodec_executing"]
        for e in evts:
            if re.search(r"Now Executing", e["msg"]) and last_exec is not None and last_exec <= e["epoch_ms"] < fp:
                last_exec = e["epoch_ms"]
        A["last_executing_before_video"] = last_exec
        out["segments_ms"] = seg = {
            "return_cmd_to_am_start_line": dt(t0, A["am_start_line"]),
            "am_start_to_surfaceCreated_enter": dt(A["am_start_line"], A["surfaceCreated_enter"]),
            "surfaceCreated_to_auth_begin": dt(A["surfaceCreated_enter"], A["auth_begin_dart"]),
            "auth_begin_to_auth_result": dt(A["auth_begin_dart"], A["auth_result_java"]),
            "auth_result_to_window_exit": dt(A["auth_result_java"], A["window_exit"]),
            "window_exit_to_acodec_executing": dt(A["window_exit"], A["acodec_executing"]),
            "acodec_executing_to_first_video_present": dt(A["acodec_executing"], fp),
            "  of_which_last_reconfig_executing_to_video": dt(last_exec, fp) if last_exec else None,
            "TOTAL_return_cmd_to_first_video_present": dt(t0, fp),
            "TOTAL_return_cmd_to_cadence_stable": dt(t0, A.get("cadence_stable_from")),
        }
        if A["auth_begin_dart"] and A["window_exit"]:
            b_val = dt(A["surfaceCreated_enter"], A["auth_begin_dart"]) + dt(A["window_exit"], A["acodec_executing"])
            a_val = dt(A["auth_begin_dart"], A["window_exit"])
        else:  # SDR zero-auth path: whole surfaceCreated..Executing is bridge-free rebuild
            b_val = dt(A["surfaceCreated_enter"], A["acodec_executing"])
            a_val = 0
        out["attribution"] = {
            "a_auth_bridge(auth_begin..window_exit)": a_val,
            "b_decoder_rebuild(surfaceCreated..auth_begin + window_exit..Executing)": b_val,
            "c_gop_catchup(Executing..first_video_present)": dt(A["acodec_executing"], fp),
            "d_activity_surface(return_cmd..surfaceCreated)": dt(t0, A["surfaceCreated_enter"]),
        }
        out["cadence"] = [cadence(presents_ms, fp, fp + 5000, "first5s"),
                          cadence(presents_ms, fp + 5000, fp + 15000, "5to15s"),
                          cadence(presents_ms, fp + 15000, fp + 22000, "15to22s")]
        ivcsv(ROUND, presents_ms, fp, fp + 22000, "post_return")
    # sampler-internal offset cross-check
    offs2 = []
    prevmax = 0
    for it in iters:
        if it["presents"] and max(it["presents"]) > prevmax:
            pm = max(it["presents"]) // 1000000
            offs2.append(it["epoch_ms"] - pm)
            prevmax = max(it["presents"])
        elif it["presents"]:
            prevmax = max(prevmax, max(it["presents"]))
    if offs2:
        out["sampler"]["sf_epoch_offset_ms_median"] = statistics.median(offs2)
        out["sampler"]["sf_epoch_offset_ms_spread"] = max(offs2) - min(offs2)
        if out["logcat"]["rt_mono_offset_ms"] is not None:
            out["sampler"]["offset_vs_logcat_delta"] = round(
                statistics.median(offs2) - out["logcat"]["rt_mono_offset_ms"], 1)

def base(out, evts, markers, presents_ms, iters, itA, itB, host):
    out["anchors"] = {}
    for phase, iters_ in (("A", itA), ("B", itB)):
        if not iters_:
            continue
        t0 = markers.get(("A_RESUME_CMD" if phase == "A" else "B_SEEK_CMD"))
        t_cmd_pause = markers.get("A_PAUSE_CMD")
        base_t = iters_[0]["epoch_ms"]
        end_t = iters_[-1]["epoch_ms"]
        pre = [p // 1000000 + (out["logcat"]["rt_mono_offset_ms"] or 0) for it in iters_ for p in it["presents"]]
        pre = sorted(set(pre))
        post = [p for p in pre if t0 is not None and p > t0]
        anc = {"cmd_ms": t0, "window": [base_t, end_t],
               "last_present_before_cmd": max([p for p in pre if t0 and p <= t0], default=None),
               "first_present_after_cmd": min(post) if post else None}
        if anc["first_present_after_cmd"]:
            fp = anc["first_present_after_cmd"]
            w = [p for p in pre if fp <= p <= fp + 10000]
            iv = [b - a for a, b in zip(w, w[1:])]
            med = statistics.median(iv) if iv else 33
            run, stable = 0, None
            for a, b in zip(w, w[1:]):
                if b - a <= 1.5 * med + 10:
                    run += 1
                    if run >= 10:
                        stable = b - 10 * (b - a)
                        break
                else:
                    run = 0
            anc["cadence_stable_from"] = stable
            anc["cmd_to_first_present_ms"] = fp - t0
            anc["cadence"] = cadence(pre, fp, fp + 8000, "post_cmd_8s")
            ivcsv(ROUND, pre, fp, fp + 8000, f"phase{phase}")
        out["anchors"][phase] = anc
    # control: decoder-rebuild lines anywhere between phase A start and end of B
    t_first = itA[0]["epoch_ms"] if itA else None
    t_last = itB[-1]["epoch_ms"] if itB else None
    ctrl = {}
    for name, pat in (("authorize", r"authorize (begin|result)"), ("mkst_window", r"mkst_create_decoder_window"),
                      ("mkst_shutdown", r"mkst_shutdown exit"), ("surface_events", r"surfaceCreated enter|surfaceDestroyed enter"),
                      ("codec_instantiate", r"makeComponentInstance"), ("acodec_state", r"Now (Executing|Idle|Loaded)")):
        hits = [e["epoch_ms"] for e in evts if re.search(pat, e["msg"])
                and t_first is not None and t_last is not None and t_first <= e["epoch_ms"] <= t_last]
        ctrl[name] = len(hits)
    out["control_lines_in_phase_window"] = ctrl

def dt(a, b):
    if a is None or b is None:
        return None
    return b - a

if __name__ == "__main__":
    main()
