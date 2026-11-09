#!/usr/bin/env python3
"""phase3-poc analyzer: keyframe-resume PoC rounds (KN/KF/KP/KS).
Parses dense-samples.txt + logcat-full.txt + host-events.ndjson -> analysis.json,
presents.csv, intervals.csv.
Per V2 acceptance protocol it reports:
  - authorize-chain closure (dart authorize begin/result, java authorize,
    mkst window, MediaCodec rebuild, bridge-not-initialized count)
  - recovery-seek begin/complete/skip/fail (positionSeconds, intent, reason)
  - trigger -> first new video frame present (AMS marker basis; also
    surfaceCreated -> first frame)
  - rollback vs recovery-seek complete positionSeconds and vs pre-restore
    media-session position (first advancing position after restore)
  - post-first-frame present cadence (>=15 s window), max freeze/buffering
  - pid stability, FATAL/ANR counts
Usage: analyze_poc.py <round_dir> <type:kn|kf|kp|ks>
All times in device epoch ms (CLOCK_REALTIME)."""
import json, os, re, statistics, sys
from datetime import datetime

ROUND = sys.argv[1] if len(sys.argv) > 1 else None
TYPE = sys.argv[2] if len(sys.argv) > 2 else "kn"

def read(p):
    fp = os.path.join(ROUND, p)
    if not os.path.exists(fp):
        return None
    with open(fp, "r", errors="replace") as f:
        return f.read()

# ---------- dense sampler ----------
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

# ---------- logcat ----------
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
        wall_ms = None
        try:
            dt = datetime.strptime("2026-" + mmdd + " " + hms, "%Y-%m-%d %H:%M:%S.%f")
            wall_ms = int(dt.timestamp() * 1000)
        except ValueError:
            continue
        rtm, mom = RT_RE.search(msg), MONO_RE.search(msg)
        rt = int(rtm.group(1)) if rtm else None
        if rt is not None and mom:
            offs.append(rt - int(mom.group(1)))
        epoch = rt if rt is not None else wall_ms
        events.append({"epoch_ms": epoch, "wall_ms": wall_ms, "pid": int(pid), "tag": tag, "msg": msg})
    return events, offs

def find(evts, pattern, after=None, before=None, last=False):
    rx = re.compile(pattern)
    hits = [e for e in evts if rx.search(e["msg"])
            and (after is None or e["epoch_ms"] >= after)
            and (before is None or e["epoch_ms"] <= before)]
    if not hits:
        return None
    return (hits[-1] if last else hits[0])["epoch_ms"]

def findall(evts, pattern, after=None, before=None):
    rx = re.compile(pattern)
    return [e for e in evts if rx.search(e["msg"])
            and (after is None or e["epoch_ms"] >= after)
            and (before is None or e["epoch_ms"] <= before)]

def dt(a, b):
    if a is None or b is None:
        return None
    return b - a

def cadence(presents_ms, t_start, t_end, label):
    w = [p for p in presents_ms if t_start <= p <= t_end]
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
    out = {"round": ROUND, "type": TYPE}
    logcat = read("logcat-full.txt")
    evts, offs = parse_logcat(logcat)
    wall_cal = None
    cals = []
    for e in evts:
        if e["wall_ms"] is not None:
            rtm = RT_RE.search(e["msg"])
            if rtm:
                cals.append(int(rtm.group(1)) - e["wall_ms"])
    if cals:
        wall_cal = statistics.median(cals)
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

    iters, markers = parse_dense(read("dense-samples.txt"))
    periods = [b["epoch_ms"] - a["epoch_ms"] for a, b in zip(iters, iters[1:])]
    out["sampler"] = {"iterations": len(iters),
                      "period_ms_median": round(statistics.median(periods), 1) if periods else None,
                      "period_ms_max": max(periods) if periods else None,
                      "markers_epoch_ms": markers}
    allp = sorted({p for it in iters for p in it["presents"]})
    presents_ms = [p // 1000000 + mono_off for p in allp] if mono_off is not None else [p // 1000000 for p in allp]
    states_raw = [{"epoch_ms": it["epoch_ms"], "state": it["state"], "pos": it["pos"]}
                  for it in iters if it["state"] is not None]
    sser = []
    for s in states_raw:
        if not sser or sser[-1]["state"] != s["state"]:
            sser.append(dict(s))
    out["media_state_series"] = sser

    with open(os.path.join(ROUND, "presents.csv"), "w") as f:
        f.write("present_epoch_ms,mono_ns\n")
        for p, pm in zip(allp, presents_ms):
            f.write(f"{pm},{p}\n")
    with open(os.path.join(ROUND, "intervals.csv"), "w") as f:
        f.write("label,present_a_ms,present_b_ms,interval_ms\n")

    # ---- trigger marker per type ----
    t0 = markers.get({"kn": "RETURN_CMD", "kp": "RETURN_CMD", "kf": "KF_CMD", "ks": "SK_SEEK_CMD"}[TYPE])

    # ---- PoC: recovery-seek events ----
    rec = {"begin": [], "complete": [], "skip": [], "fail": []}
    for e in findall(evts, r"recovery-seek (begin|complete|skip|fail)"):
        m = re.search(r"recovery-seek (begin|complete|skip|fail) (.*)", e["msg"])
        if not m:
            continue
        kind, rest = m.group(1), m.group(2)
        d = {"epoch_ms": e["epoch_ms"], "detail": rest[:220]}
        pm = re.search(r"positionSeconds=([\d.eE+-]+)", rest)
        if pm:
            d["positionSeconds"] = float(pm.group(1))
        am = re.search(r"audioPts=(\S+)", rest)
        if am:
            d["audioPts"] = am.group(1)
        rm = re.search(r"reason=(\S+)", rest)
        if rm:
            d["reason"] = rm.group(1)
        im = re.search(r"intent=(\d+)", rest)
        if im:
            d["intent"] = int(im.group(1))
        rec[kind].append(d)
    out["recovery_seek"] = rec

    # ---- authorize chain closure + guards ----
    A = {}
    A["sd_exit"] = find(evts, r"surfaceDestroyed exit", after=t0) or find(evts, r"surfaceDestroyed exit")
    A["sc_enter"] = find(evts, r"surfaceCreated enter", after=t0) if TYPE != "ks" else find(evts, r"surfaceCreated enter")
    A["auth_begin_dart"] = find(evts, r"authorize begin", after=t0)
    A["auth_result_dart"] = find(evts, r"authorize result .*code=ok", after=t0)
    A["auth_result_java"] = find(evts, r"java authorize result code=ok", after=t0)
    A["window_exit"] = find(evts, r"mkst_create_decoder_window exit .*window_active=1", after=t0)
    A["make_component"] = find(evts, r"makeComponentInstance", after=t0)
    A["acodec_executing"] = find(evts, r"Now Executing", after=A.get("make_component") or t0)
    A["kf_sd_to_sc_ms"] = dt(find(evts, r"surfaceDestroyed enter"), A["sc_enter"]) if TYPE == "kf" else None
    out["anchors"] = A
    out["guards"] = {
        "dart_authorize_begin_count": len(findall(evts, r"authorize begin")),
        "dart_authorize_ok_count": len(findall(evts, r"authorize result .*code=ok")),
        "java_authorize_ok_count": len(findall(evts, r"java authorize result code=ok")),
        "bridge_not_initialized_count": len(findall(evts, r"bridge not initialized")),
        "makeComponentInstance_count_total": len(findall(evts, r"makeComponentInstance")),
        "dvP84_class_count": len(findall(evts, r"class=dvP84")),
        "fatal_count": len(findall(evts, r"FATAL EXCEPTION|Fatal signal")),
        "anr_count": len(findall(evts, r"ANR in com\.example\.piliplus")),
    }
    pids = sorted({e["pid"] for e in evts if e["tag"] == "flutter"})
    out["guards"]["flutter_pids"] = pids

    # ---- first new video frame present ----
    if TYPE == "ks":
        # phase2 ff-seek method: longest present-free gap (>=150 ms) in
        # [t0, t0+20s]; first new frame = present ending that gap (sustained
        # run required). Fallback: first sustained run after cmd.
        pre = [p for p in presents_ms if p <= t0]
        last_before = max(pre) if pre else None
        win = [p for p in presents_ms if t0 is not None and t0 <= p <= t0 + 20000]
        iv = [(b - a, a, b) for a, b in zip(win, win[1:])]
        gaps = sorted([x for x in iv if x[0] >= 150], reverse=True)
        vp, freeze = None, None
        if gaps:
            d, a, b = gaps[0]
            nxt = [q for q in win if b <= q <= b + 800]
            if len(nxt) >= 5:
                vp, freeze = b, [a, b, d]
            else:
                A["note_longest_gap_not_sustained"] = True
        if vp is None:
            for p in win:
                nxt = [q for q in win if p <= q <= p + 800]
                if len(nxt) >= 5:
                    vp = p
                    break
        A["last_present_before_cmd"] = last_before
        A["presents_in_20s_after_cmd"] = len(win)
        A["gaps_ge_150ms"] = [[a, b, d] for d, a, b in gaps]
        A["first_new_frame_present"] = vp
        A["freeze_gap"] = freeze
        A["cmd_to_first_new_frame_ms"] = dt(t0, vp)
        if freeze:
            A["old_frame_tail_ms"] = freeze[0] - t0
        seg = {"cmd_to_first_new_frame_ms": dt(t0, vp)}
        if freeze:
            seg["old_frame_tail_ms"] = freeze[0] - t0
            seg["freeze_gap_ms"] = freeze[2]
        out["segments_ms"] = seg
        if vp:
            out["cadence"] = [cadence(presents_ms, vp, vp + 5000, "first5s"),
                              cadence(presents_ms, vp + 5000, vp + 15000, "5to15s")]
            with open(os.path.join(ROUND, "intervals.csv"), "a") as f:
                w = [p for p in presents_ms if vp <= p <= vp + 15000]
                for a, b in zip(w, w[1:]):
                    f.write(f"post_seek,{a},{b},{b-a}\n")
    else:
        post = [p for p in presents_ms if t0 is not None and p > t0]
        sc = A["sc_enter"]
        vp = None
        for p in post:
            if sc is not None and p < sc:
                continue
            nxt = [q for q in post if p <= q <= p + 800]
            if len(nxt) >= 5:
                vp = p
                break
        A["first_present_after_return"] = min(post) if post else None
        A["first_video_present_after_return"] = vp
        if A["first_present_after_return"] and vp:
            A["isolated_bg_presents_before_video"] = [p for p in post if p < vp]
        out["segments_ms"] = seg = {
            "trigger_to_surfaceCreated_enter": dt(t0, sc),
            "surfaceCreated_to_first_video_present": dt(sc, vp),
            "auth_begin_to_auth_result": dt(A["auth_begin_dart"], A["auth_result_java"]),
            "auth_result_to_window_exit": dt(A["auth_result_java"], A["window_exit"]),
            "window_exit_to_acodec_executing": dt(A["window_exit"], A["acodec_executing"]),
            "acodec_executing_to_first_video_present": dt(A["acodec_executing"], vp),
            "TOTAL_trigger_cmd_to_first_video_present": dt(t0, vp),
        }
        if vp:
            w = [p for p in presents_ms if vp <= p <= vp + 22000]
            iv = [b - a for a, b in zip(w, w[1:])]
            med = statistics.median(iv) if iv else 33
            run = 0
            A["cadence_stable_from"] = None
            for a, b in zip(w, w[1:]):
                if b - a <= 1.5 * med + 10:
                    run += 1
                    if run >= 10:
                        A["cadence_stable_from"] = b - 10 * (b - a)
                        break
                else:
                    run = 0
            seg["TOTAL_trigger_cmd_to_cadence_stable"] = dt(t0, A.get("cadence_stable_from"))
            out["cadence"] = [cadence(presents_ms, vp, vp + 5000, "first5s"),
                              cadence(presents_ms, vp + 5000, vp + 15000, "5to15s"),
                              cadence(presents_ms, vp + 15000, vp + 22000, "15to22s")]
            with open(os.path.join(ROUND, "intervals.csv"), "a") as f:
                w = [p for p in presents_ms if vp <= p <= vp + 22000]
                for a, b in zip(w, w[1:]):
                    f.write(f"post_return,{a},{b},{b-a}\n")

    # ---- rollback (kn/kf/kp): complete positionSeconds vs first advancing pos ----
    if TYPE in ("kn", "kf", "kp"):
        rb = {}
        comp = rec["complete"][0] if rec["complete"] else None
        rb["recovery_complete_positionSeconds"] = comp["positionSeconds"] if comp else None
        rb["recovery_complete_audioPts"] = comp.get("audioPts") if comp else None
        # pre-restore: last pos at/before trigger
        pre = [s for s in states_raw if s["pos"] is not None and s["epoch_ms"] <= t0]
        rb["pre_restore_media_pos_ms"] = pre[-1]["pos"] if pre else None
        rb["pre_restore_media_state"] = pre[-1]["state"] if pre else None
        # first advancing pos after trigger
        post_s = [s for s in states_raw if s["pos"] is not None and s["epoch_ms"] > t0]
        first_adv = None
        prev = rb["pre_restore_media_pos_ms"]
        for s in post_s:
            if prev is not None and s["pos"] > prev:
                first_adv = s
                break
            if prev is None:
                prev = s["pos"]
        rb["first_advancing_pos_ms"] = first_adv["pos"] if first_adv else None
        rb["first_advancing_epoch_ms"] = first_adv["epoch_ms"] if first_adv else None
        rb["first_advancing_state"] = first_adv["state"] if first_adv else None
        if comp and comp.get("positionSeconds") is not None and first_adv:
            rb["rollback_vs_complete_ms"] = first_adv["pos"] - comp["positionSeconds"] * 1000
        if rb["pre_restore_media_pos_ms"] is not None and first_adv:
            rb["rollback_vs_pre_restore_ms"] = first_adv["pos"] - rb["pre_restore_media_pos_ms"]
        # max buffering window (state 6) in dense window
        runs6 = []
        for s in states_raw:
            if s["state"] == 6:
                if runs6 and s["epoch_ms"] - runs6[-1][1] < 1500:
                    runs6[-1][1] = s["epoch_ms"]
                else:
                    runs6.append([s["epoch_ms"], s["epoch_ms"]])
        rb["buffering_windows"] = [[a, b, b - a] for a, b in runs6]
        # KP: post-return pause persistence (states until play dispatch)
        if TYPE == "kp":
            play_dev = (host.get("play_dispatched") or {}).get("device_ms")
            win = [s for s in states_raw if t0 is not None and s["epoch_ms"] > t0
                   and (play_dev is None or s["epoch_ms"] < play_dev)]
            rb["kp_states_between_return_and_play"] = sorted({s["state"] for s in win})
            rb["kp_positions_between_return_and_play"] = sorted({s["pos"] for s in win})
        out["rollback"] = rb

    with open(os.path.join(ROUND, "analysis.json"), "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    slim = {k: v for k, v in out.items() if k not in ("media_state_series",)}
    print(json.dumps(slim, indent=1, ensure_ascii=False)[:7000])

main()
