# Analysis F4

- driver: `mode=fast pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key=`
- app pid: 3225; log lines: 1906
- t_home_send_begin (device): 22:55:03.830; return_sent: 22:55:05.376

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1119 22:54:45.661
- mkst_create_decoder_window exit result=ok: L952 22:54:44.656 owner_key=15828119071824081213 generation=2
- time-pos samples before HOME: L1137 22:54:47.021 PERF 1.902, L1158 22:54:49.025 P5 3.904, L1204 22:54:57.022 PERF 11.912, L1226 22:54:59.026 P5 13.914
- frozen time-pos at first sample after HOME: L1827 19.739 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1193 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1450 | 22:55:04.745 | — |
| dart_authorize_begin | L1694 | 22:55:06.189 | 1444 |
| java_authorize_enter | L1695 | 22:55:06.190 | 1 |
| java_authorize_result | L1702 | 22:55:06.190 | 0 |
| dart_authorize_result | L1703 | 22:55:06.191 | 1 |
| native_ensure_init_exit | L1739 | 22:55:06.249 | 58 |
| native_create_decoder_window_exit | L1743 | 22:55:06.250 | 1 |
| MediaCodec_create | L1744 | 22:55:06.252 | 2 |
| OMX_hevc_Now_Loaded(after create) | L1763 | 22:55:06.266 | 14 |

- ordered: True; same wid across dart/java authorize: True (wid=2258); owner_key same as pre-HOME: True (pre=15828119071824081213, ensure_init=15828119071824081213)
- identity: dart_begin={'wid': '2258', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '2', 'intentSerial': '3'} java_result={'wid': '2258', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '2', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '15828119071824081213', 'generation': '2', 'ready': '1', 'egl_ctx': '0x7418e63a80'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '15828119071824081213', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 1
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L1544 22:55:05.142
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1805 22:55:06.431
- active-importer=surfacetexture device_registered=1: L1880 22:55:09.261
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 13.9 s
- time-pos samples: L1827 22:55:07.039 PERF 19.739, L1874 22:55:09.121 P5 19.739, L1897 22:55:19.032 P5 19.753
- PERF pause samples: L1836 t=28 pause=yes
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1884, 't': 1793631309293, 'gen': '4', 'frame_id': '34', 'pts': '19.753066667', 'still': '0', 'route': 'fused'}; last={'line': 1885, 't': 1793631309305, 'gen': '4', 'frame_id': '34', 'pts': '19.753066667', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L1883 `engl] error: MKS-FUSION committed=1 attempted=4 generation=4`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=3225 after=3225 same=True; am_proc_start(pkg)=[209]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L914']; after HOME ['L1722']
- HDR decision applied pre-HOME: {'line': 1115, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1119, 'time': '22:54:45.661', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1371 | 22:55:04.567 | L1544 | 22:55:05.142 | 575 | shutdown_exit BEFORE surfaceCreated by 490 ms (L1417) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1371 22:55:04.567; shutdown exit: L1417 22:55:04.652 (Δ=85 ms); vo=null ack: L1450 22:55:04.745
- am_pause_activity: L1314 22:55:04.355; am_on_stop_called: L1414 22:55:04.648; am_resume_activity: L1539 22:55:05.085
- window: 22:55:03.567 .. 22:55:05.652

| pattern | in window | whole log | pre-HOME | lines (window) |
|---|---|---|---|---|
| latch_timeout | 0 | 0 | 0 | [] |
| mapping_failed | 0 | 0 | 0 | [] |
| fusion_disabled_after_failure | 0 | 0 | 0 | [] |
| horizon_overflow | 0 | 0 | 0 | [] |
| failed_rendering_frame | 0 | 0 | 0 | [] |

## Whole-log counts

| key | n |
|---|---|
| bridge not initialized | 0 |
| yuv420p10 | 0 |
| MKSURF-E1: dataspace applied | 2 |
| Mediacodec create | 3 |
| mkst_ensure_init(lc_verify) exit | 2 |
| mkst_create_decoder_window exit | 2 |
| authorize begin | 2 |
| event=swap-success | 5 |

