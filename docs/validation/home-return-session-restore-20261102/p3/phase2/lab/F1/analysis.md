# Analysis F1

- driver: `mode=fast pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=1 open_home_delay=0.5 pre_home_key= resume_key=`
- app pid: 1862; log lines: 1950
- t_home_send_begin (device): 22:52:21.858; return_sent: 22:52:24.000

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1138 22:52:02.762
- mkst_create_decoder_window exit result=ok: L962 22:52:01.872 owner_key=5544324211490475549 generation=2
- time-pos samples before HOME: L1160 22:52:04.292 PERF 2.035, L1183 22:52:06.299 P5 4.037, L1238 22:52:14.300 PERF 12.045, L1266 22:52:16.308 P5 14.047
- frozen time-pos at first sample after HOME: L1718 20.500 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1220 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1510 | 22:52:22.945 | — |
| dart_authorize_begin | L1744 | 22:52:25.272 | 2327 |
| java_authorize_enter | L1746 | 22:52:25.273 | 1 |
| java_authorize_result | L1753 | 22:52:25.273 | 0 |
| dart_authorize_result | L1754 | 22:52:25.274 | 1 |
| native_ensure_init_exit | L1790 | 22:52:25.326 | 52 |
| native_create_decoder_window_exit | L1794 | 22:52:25.327 | 1 |
| MediaCodec_create | L1795 | 22:52:25.329 | 2 |
| OMX_hevc_Now_Loaded(after create) | L1822 | 22:52:25.352 | 23 |

- ordered: True; same wid across dart/java authorize: True (wid=2258); owner_key same as pre-HOME: True (pre=5544324211490475549, ensure_init=5544324211490475549)
- identity: dart_begin={'wid': '2258', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '2', 'intentSerial': '3'} java_result={'wid': '2258', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '2', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '5544324211490475549', 'generation': '2', 'ready': '1', 'egl_ctx': '0x7418ce3980'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '5544324211490475549', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 1
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L1583 22:52:23.441
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1859 22:52:25.557
- active-importer=surfacetexture device_registered=1: L1921 22:52:28.832
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 22.9 s
- time-pos samples: L1718 22:52:24.732 PERF 20.500, L1911 22:52:26.399 P5 20.500, L1932 22:52:36.292 P5 20.520, L1948 22:52:46.293 P5 20.520
- PERF pause samples: L1733 t=28 pause=yes
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1925, 't': 1793631148870, 'gen': '4', 'frame_id': '34', 'pts': '20.520500000', 'still': '0', 'route': 'fused'}; last={'line': 1926, 't': 1793631148880, 'gen': '4', 'frame_id': '34', 'pts': '20.520500000', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L1924 `engl] error: MKS-FUSION committed=1 attempted=4 generation=4`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=1862 after=1862 same=True; am_proc_start(pkg)=[210]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L937']; after HOME ['L1773']
- HDR decision applied pre-HOME: {'line': 1134, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1138, 'time': '22:52:02.762', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=True post-return=True
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1406 | 22:52:22.729 | L1583 | 22:52:23.441 | 712 | shutdown_exit BEFORE surfaceCreated by 543 ms (L1503) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1406 22:52:22.729; shutdown exit: L1503 22:52:22.898 (Δ=169 ms); vo=null ack: L1510 22:52:22.945
- am_pause_activity: L1326 22:52:22.470; am_on_stop_called: L1384 22:52:22.688; am_resume_activity: L1570 22:52:23.341
- window: 22:52:21.729 .. 22:52:23.898

| pattern | in window | whole log | pre-HOME | lines (window) |
|---|---|---|---|---|
| latch_timeout | 1 | 1 | 0 | [1458] |
| mapping_failed | 2 | 2 | 0 | [1467, 1474] |
| fusion_disabled_after_failure | 1 | 1 | 0 | [1468] |
| horizon_overflow | 1 | 1 | 0 | [1472] |
| failed_rendering_frame | 1 | 1 | 0 | [1486] |

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

