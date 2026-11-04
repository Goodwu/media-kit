# Analysis P1

- driver: `mode=pause pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key=KEYCODE_MEDIA_PAUSE resume_key=KEYCODE_MEDIA_PLAY`
- app pid: 3907; log lines: 2057
- t_home_send_begin (device): 22:57:35.448; return_sent: 22:57:47.637

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1131 22:57:16.204
- mkst_create_decoder_window exit result=ok: L931 22:57:15.322 owner_key=6554548817045129073 generation=2
- time-pos samples before HOME: L1154 22:57:17.803 PERF 2.035, L1175 22:57:19.811 P5 4.037, L1229 22:57:27.832 PERF 12.079, L1254 22:57:29.808 P5 14.047
- frozen time-pos at first sample after HOME: L1574 20.500 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1219 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1503 | 22:57:36.394 | — |
| dart_authorize_begin | L1754 | 22:57:47.647 | 11253 |
| java_authorize_enter | L1771 | 22:57:47.710 | 63 |
| java_authorize_result | L1778 | 22:57:47.711 | 1 |
| dart_authorize_result | L1779 | 22:57:47.712 | 1 |
| native_ensure_init_exit | L1828 | 22:57:47.789 | 77 |
| native_create_decoder_window_exit | L1832 | 22:57:47.790 | 1 |
| MediaCodec_create | L1833 | 22:57:47.793 | 3 |
| OMX_hevc_Now_Loaded(after create) | L1860 | 22:57:47.813 | 20 |

- ordered: True; same wid across dart/java authorize: True (wid=1050738); owner_key same as pre-HOME: True (pre=6554548817045129073, ensure_init=6554548817045129073)
- identity: dart_begin={'wid': '1050738', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '2', 'intentSerial': '3'} java_result={'wid': '1050738', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '2', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '6554548817045129073', 'generation': '2', 'ready': '1', 'egl_ctx': '0x741234a880'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '6554548817045129073', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 1
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L1720 22:57:47.621
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1913 22:57:48.061
- active-importer=surfacetexture device_registered=1: L1956 22:57:51.336
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 22.2 s
- time-pos samples: L1945 22:57:49.914 P5 20.500, L1989 22:57:59.805 P5 20.520, L2048 22:58:09.800 PERF 20.520, L2054 22:58:09.813 P5 20.520
- PERF pause samples: L2053 t=60 pause=yes
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1960, 't': 1793631471363, 'gen': '2', 'frame_id': '34', 'pts': '20.520500000', 'still': '0', 'route': 'fused'}; last={'line': 1961, 't': 1793631471375, 'gen': '2', 'frame_id': '34', 'pts': '20.520500000', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L1959 `engl] error: MKS-FUSION committed=1 attempted=2 generation=2`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=3907 after=3907 same=True; am_proc_start(pkg)=[213]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L907']; after HOME ['L1810']
- HDR decision applied pre-HOME: {'line': 1127, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1131, 'time': '22:57:16.204', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1436 | 22:57:36.292 | L1720 | 22:57:47.621 | 11329 | shutdown_exit BEFORE surfaceCreated by 11275 ms (L1484) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1436 22:57:36.292; shutdown exit: L1484 22:57:36.346 (Δ=54 ms); vo=null ack: L1503 22:57:36.394
- am_pause_activity: L1358 22:57:35.998; am_on_stop_called: L1416 22:57:36.266; am_resume_activity: L1694 22:57:47.525
- window: 22:57:35.292 .. 22:57:37.346

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

