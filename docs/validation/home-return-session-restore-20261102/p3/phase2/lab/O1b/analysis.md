# Analysis O1b

- driver: `mode=openhome pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0 pre_home_key= resume_key=`
- app pid: 4521; log lines: 1295
- t_home_send_begin (device): 23:02:23.763; return_sent: 23:02:35.465

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: MISSING
- mkst_create_decoder_window exit result=ok: MISSING
- time-pos samples before HOME: 
- frozen time-pos at first sample after HOME: —
- swap-success before HOME: 0 lines, max frame_id=None; last MKS-FUSION committed: —
- playback ≥15 s before HOME: False; **pre-HOME start-point pass: False**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L863 | 23:02:24.329 | — |
| dart_authorize_begin | MISSING | — | — |
| java_authorize_enter | MISSING | — | — |
| java_authorize_result | MISSING | — | — |
| dart_authorize_result | MISSING | — | — |
| native_ensure_init_exit | MISSING | — | — |
| native_create_decoder_window_exit | MISSING | — | — |
| MediaCodec_create | MISSING | — | — |
| OMX_hevc_Now_Loaded(after create) | MISSING | — | — |

- ordered: True; same wid across dart/java authorize: False (wid=None); owner_key same as pre-HOME: False (pre=None, ensure_init=None)
- identity: dart_begin=None java_result=None ensure_init=None create_window=None
- java factory.create after HOME: 1; java bridge.ensureInitialized after HOME: 1
- **C1 pass: False**

## C2 after return

- surfaceCreated enter: MISSING
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: MISSING
- active-importer registered: MISSING
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: False**

## C3 playback after return

- observation window after surfaceCreated: 13.7 s
- time-pos samples: none
- PERF pause samples: L1249 t=18 pause=no, L1277 t=28 pause=no
- swap-success after return: 0 lines; unique frame_id=[]; first=None; last=None
- last MKS-FUSION committed after return: —
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=1, other=1 [1113])
- **C4 pass: False**

## C5 process

- pid before=4521 after=4521 same=True; am_proc_start(pkg)=[208]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME []; after HOME []
- HDR decision applied pre-HOME: None
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: False — see fields
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=null; reports after HOME=[{'line': 1094, 'time': '23:02:34.575', 'hwdecCurrent': 'null'}, {'line': 1095, 'time': '23:02:34.576', 'hwdecCurrent': 'null'}]; last in log={'line': 1095, 'time': '23:02:34.576', 'hwdecCurrent': 'null'}; all surfacetexture=False
- SF dumps: pre-home=False post-return=False
- **C6 pass: False**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L927 | 23:02:24.443 | — | — | — | n/a (LNone) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L927 23:02:24.443; shutdown exit: MISSING (Δ=None ms); vo=null ack: L863 23:02:24.329
- am_pause_activity: L825 23:02:24.241; am_on_stop_called: L937 23:02:24.483; am_resume_activity: L1169 23:02:35.394

## Whole-log counts

| key | n |
|---|---|
| bridge not initialized | 0 |
| yuv420p10 | 0 |
| MKSURF-E1: dataspace applied | 0 |
| Mediacodec create | 1 |
| mkst_ensure_init(lc_verify) exit | 0 |
| mkst_create_decoder_window exit | 0 |
| authorize begin | 0 |
| event=swap-success | 0 |

