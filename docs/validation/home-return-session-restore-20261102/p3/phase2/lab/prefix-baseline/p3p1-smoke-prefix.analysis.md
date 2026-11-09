# Analysis smoke-prefix

- driver: `launch=fresh home=normal pkg=com.example.media_kit_hdr_lab`
- app pid: 29015; log lines: 2048
- t_home_send_begin (device): 20:58:23.123; return_sent: 20:58:36.133

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1149 20:58:08.253
- mkst_create_decoder_window exit result=ok: L943 20:58:07.408 owner_key=12189156743110968328 generation=2
- time-pos samples before HOME: L1175 20:58:10.015 PERF 1.435, L1193 20:58:11.307 P5 3.437, L1244 20:58:19.295 PERF 11.445, L1312 20:58:21.299 P5 13.413
- frozen time-pos at first sample after HOME: L1669 17.250 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1237 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1524 | 20:58:24.937 | — |
| dart_authorize_begin | L1801 | 20:58:36.159 | 11222 |
| java_authorize_enter | L1812 | 20:58:36.213 | 54 |
| java_authorize_result | L1819 | 20:58:36.213 | 0 |
| dart_authorize_result | L1824 | 20:58:36.227 | 14 |
| native_ensure_init_exit | L1882 | 20:58:36.310 | 83 |
| native_create_decoder_window_exit | L1886 | 20:58:36.311 | 1 |
| MediaCodec_create | L1887 | 20:58:36.317 | 6 |
| OMX_hevc_Now_Loaded(after create) | L1907 | 20:58:36.335 | 18 |

- ordered: True; same wid across dart/java authorize: True (wid=2162); owner_key same as pre-HOME: True (pre=12189156743110968328, ensure_init=12189156743110968328)
- identity: dart_begin={'wid': '2162', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '2', 'intentSerial': '3'} java_result={'wid': '2162', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '2', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '12189156743110968328', 'generation': '2', 'ready': '1', 'egl_ctx': '0x7418f19d80'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '12189156743110968328', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 1
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L1765 20:58:36.125
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1953 20:58:36.554
- active-importer=surfacetexture device_registered=1: L1975 20:58:37.891
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 15.2 s
- time-pos samples: L2001 20:58:41.297 P5 17.251, L2021 20:58:51.300 P5 17.251
- PERF pause samples: none
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1979, 't': 1793624317937, 'gen': '2', 'frame_id': '34', 'pts': '17.250566667', 'still': '0', 'route': 'fused'}; last={'line': 1980, 't': 1793624317948, 'gen': '2', 'frame_id': '34', 'pts': '17.250566667', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L1978 `engl] error: MKS-FUSION committed=1 attempted=2 generation=2`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=29015 after=29015 same=True; am_proc_start(pkg)=[210]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L923']; after HOME ['L1858']
- HDR decision applied pre-HOME: {'line': 1145, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1149, 'time': '20:58:08.253', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1425 | 20:58:24.659 | L1765 | 20:58:36.125 | 11466 | shutdown_exit BEFORE surfaceCreated by 11271 ms (L1483) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1425 20:58:24.659; shutdown exit: L1483 20:58:24.854 (Δ=195 ms); vo=null ack: L1524 20:58:24.937
- am_pause_activity: L1386 20:58:24.391; am_on_stop_called: L1461 20:58:24.817; am_resume_activity: L1745 20:58:36.070
- window: 20:58:23.659 .. 20:58:25.854

| pattern | in window | whole log | pre-HOME | lines (window) |
|---|---|---|---|---|
| latch_timeout | 1 | 1 | 0 | [1462] |
| mapping_failed | 2 | 2 | 0 | [1464, 1480] |
| fusion_disabled_after_failure | 1 | 1 | 0 | [1468] |
| horizon_overflow | 1 | 1 | 0 | [1469] |
| failed_rendering_frame | 1 | 1 | 0 | [1494] |

## Whole-log counts

| key | n |
|---|---|
| bridge not initialized | 0 |
| yuv420p10 | 0 |
| MKSURF-E1: dataspace applied | 2 |
| Mediacodec create | 3 |
| mkst_ensure_init(lc_verify) exit | 2 |
| mkst_create_decoder_window exit | 2 |
| authorize begin | 3 |
| event=swap-success | 5 |

