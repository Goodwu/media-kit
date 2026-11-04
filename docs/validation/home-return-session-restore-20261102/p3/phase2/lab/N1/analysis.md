# Analysis N1

- driver: `mode=normal pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=1 open_home_delay=0.5 pre_home_key= resume_key=`
- app pid: 493; log lines: 1986
- t_home_send_begin (device): 22:48:11.736; return_sent: 22:48:23.692

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1115 22:47:53.600
- mkst_create_decoder_window exit result=ok: L945 22:47:52.195 owner_key=8793159320474925283 generation=2
- time-pos samples before HOME: L1133 22:47:54.772 PERF 2.169, L1152 22:47:56.760 P5 4.171, L1234 22:48:04.760 PERF 12.145, L1255 22:48:06.765 P5 14.147
- frozen time-pos at first sample after HOME: L1589 20.000 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1218 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1507 | 22:48:12.715 | — |
| dart_authorize_begin | L1760 | 22:48:23.808 | 11093 |
| java_authorize_enter | L1776 | 22:48:23.857 | 49 |
| java_authorize_result | L1783 | 22:48:23.858 | 1 |
| dart_authorize_result | L1789 | 22:48:23.886 | 28 |
| native_ensure_init_exit | L1838 | 22:48:23.931 | 45 |
| native_create_decoder_window_exit | L1841 | 22:48:23.933 | 2 |
| MediaCodec_create | L1842 | 22:48:23.934 | 1 |
| OMX_hevc_Now_Loaded(after create) | L1861 | 22:48:23.953 | 19 |

- ordered: True; same wid across dart/java authorize: True (wid=1050522); owner_key same as pre-HOME: True (pre=8793159320474925283, ensure_init=8793159320474925283)
- identity: dart_begin={'wid': '1050522', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '2', 'intentSerial': '3'} java_result={'wid': '1050522', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '2', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '8793159320474925283', 'generation': '2', 'ready': '1', 'egl_ctx': '0x7414a76280'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '8793159320474925283', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 1
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L1720 22:48:23.736
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1906 22:48:24.195
- active-importer=surfacetexture device_registered=1: L1937 22:48:27.171
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 13.0 s
- time-pos samples: L1931 22:48:26.862 P5 20.000, L1958 22:48:36.763 P5 20.020
- PERF pause samples: none
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1941, 't': 1793630907207, 'gen': '2', 'frame_id': '34', 'pts': '20.020000000', 'still': '0', 'route': 'fused'}; last={'line': 1942, 't': 1793630907217, 'gen': '2', 'frame_id': '34', 'pts': '20.020000000', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L1940 `engl] error: MKS-FUSION committed=1 attempted=2 generation=2`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=493 after=493 same=True; am_proc_start(pkg)=[212]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L906']; after HOME ['L1809']
- HDR decision applied pre-HOME: {'line': 1111, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1115, 'time': '22:47:53.600', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=True post-return=True
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1424 | 22:48:12.573 | L1720 | 22:48:23.736 | 11163 | shutdown_exit BEFORE surfaceCreated by 11088 ms (L1477) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1424 22:48:12.573; shutdown exit: L1477 22:48:12.648 (Δ=75 ms); vo=null ack: L1507 22:48:12.715
- am_pause_activity: L1341 22:48:12.318; am_on_stop_called: L1400 22:48:12.544; am_resume_activity: L1697 22:48:23.645
- window: 22:48:11.573 .. 22:48:13.648

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

