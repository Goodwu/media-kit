# Analysis R4-fast-3

- driver: `launch=fresh method=F sleep=0 pkg=com.example.media_kit_hdr_lab`
- app pid: 26737; log lines: 1935
- t_home_send_begin (device): 20:19:00.792; return_sent: 20:19:02.951

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1063 20:18:46.889
- mkst_create_decoder_window exit result=ok: L896 20:18:45.532 owner_key=16652840049318014755 generation=2
- time-pos samples before HOME: L1084 20:18:47.942 PERF 2.035, L1101 20:18:49.926 P5 4.004, L1159 20:18:57.928 PERF 12.012, L1179 20:18:59.925 P5 14.014
- frozen time-pos at first sample after HOME: L1861 15.975 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1144 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1447 | 20:19:01.798 | — |
| dart_authorize_begin | MISSING | — | — |
| java_authorize_enter | MISSING | — | — |
| java_authorize_result | MISSING | — | — |
| dart_authorize_result | MISSING | — | — |
| native_ensure_init_exit | L1728 | 20:19:03.372 | 1574 |
| native_create_decoder_window_exit | MISSING | — | — |
| MediaCodec_create | MISSING | — | — |
| OMX_hevc_Now_Loaded(after create) | MISSING | — | — |

- ordered: True; same wid across dart/java authorize: False (wid=None); owner_key same as pre-HOME: False (pre=16652840049318014755, ensure_init=0)
- identity: dart_begin=None java_result=None ensure_init={'initialized': '0', 'owner_key': '0', 'generation': '0', 'ready': '0', 'egl_ctx': '0x7418034f80'} create_window=None
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 0
- **C1 pass: False**

## C2 after return

- surfaceCreated enter: L1592 20:19:02.370
- `bridge not initialized`: 1 (lines [1730]); `yuv420p10`: 82 (lines [1760, 1775, 1776, 1777, 1782])
- VIDEOPARAMS pixelformat: mediacodec: MISSING
- active-importer registered: MISSING
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: False**

## C3 playback after return

- observation window after surfaceCreated: 13.3 s
- time-pos samples: L1861 20:19:07.956 PERF 15.975, L1898 20:19:10.275 P5 15.975
- PERF pause samples: L1869 t=28 pause=yes
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1932, 't': 1793621955622, 'gen': '2', 'frame_id': '34', 'pts': '15.982633333', 'still': '0', 'route': 'rgb-final'}; last={'line': 1935, 't': 1793621955649, 'gen': '2', 'frame_id': '34', 'pts': '15.982633333', 'still': '1', 'route': 'rgb-final'}
- last MKS-FUSION committed after return: —
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=26737 after=26737 same=True; am_proc_start(pkg)=[133]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L857']; after HOME ['L1711']
- HDR decision applied pre-HOME: {'line': 1059, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1063, 'time': '20:18:46.889', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1301 | 20:19:01.529 | L1592 | 20:19:02.370 | 841 | shutdown_exit BEFORE surfaceCreated by 615 ms (L1443) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1301 20:19:01.529; shutdown exit: L1443 20:19:01.755 (Δ=226 ms); vo=null ack: L1447 20:19:01.798
- am_pause_activity: L1237 20:19:01.323; am_on_stop_called: L1362 20:19:01.618; am_resume_activity: L1540 20:19:02.255
- window: 20:19:00.529 .. 20:19:02.755

| pattern | in window | whole log | pre-HOME | lines (window) |
|---|---|---|---|---|
| latch_timeout | 1 | 1 | 0 | [1375] |
| mapping_failed | 2 | 2 | 0 | [1377, 1383] |
| fusion_disabled_after_failure | 1 | 1 | 0 | [1379] |
| horizon_overflow | 1 | 1 | 0 | [1382] |
| failed_rendering_frame | 1 | 1 | 0 | [1384] |

## Whole-log counts

| key | n |
|---|---|
| bridge not initialized | 1 |
| yuv420p10 | 82 |
| MKSURF-E1: dataspace applied | 2 |
| Mediacodec create | 2 |
| mkst_ensure_init(lc_verify) exit | 2 |
| mkst_create_decoder_window exit | 1 |
| authorize begin | 0 |
| event=swap-success | 5 |

