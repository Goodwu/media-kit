# Analysis N3

- driver: `mode=normal pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key=`
- app pid: 1543; log lines: 1968
- t_home_send_begin (device): 22:50:28.478; return_sent: 22:50:40.457

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1103 22:50:09.732
- mkst_create_decoder_window exit result=ok: L932 22:50:08.830 owner_key=17098553269247067201 generation=2
- time-pos samples before HOME: L1130 22:50:11.260 PERF 2.069, L1150 22:50:13.266 P5 4.071, L1202 22:50:21.259 PERF 12.079, L1225 22:50:23.275 P5 14.081
- frozen time-pos at first sample after HOME: L1538 20.250 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1190 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1462 | 22:50:29.578 | — |
| dart_authorize_begin | L1703 | 22:50:40.499 | 10921 |
| java_authorize_enter | L1719 | 22:50:40.568 | 69 |
| java_authorize_result | L1726 | 22:50:40.569 | 1 |
| dart_authorize_result | L1736 | 22:50:40.578 | 9 |
| native_ensure_init_exit | L1793 | 22:50:40.653 | 75 |
| native_create_decoder_window_exit | L1797 | 22:50:40.654 | 1 |
| MediaCodec_create | L1798 | 22:50:40.659 | 5 |
| OMX_hevc_Now_Loaded(after create) | L1809 | 22:50:40.676 | 17 |

- ordered: True; same wid across dart/java authorize: True (wid=2099314); owner_key same as pre-HOME: True (pre=17098553269247067201, ensure_init=17098553269247067201)
- identity: dart_begin={'wid': '2099314', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '2', 'intentSerial': '3'} java_result={'wid': '2099314', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '2', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '17098553269247067201', 'generation': '2', 'ready': '1', 'egl_ctx': '0x741327fe80'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '17098553269247067201', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 1
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L1668 22:50:40.467
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1857 22:50:40.881
- active-importer=surfacetexture device_registered=1: L1889 22:50:44.006
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 12.8 s
- time-pos samples: L1881 22:50:43.372 P5 20.250, L1909 22:50:53.265 P5 20.254
- PERF pause samples: none
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1893, 't': 1793631044040, 'gen': '2', 'frame_id': '34', 'pts': '20.253566667', 'still': '0', 'route': 'fused'}; last={'line': 1895, 't': 1793631044050, 'gen': '2', 'frame_id': '34', 'pts': '20.253566667', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L1892 `engl] error: MKS-FUSION committed=1 attempted=2 generation=2`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=1543 after=1543 same=True; am_proc_start(pkg)=[207]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L907']; after HOME ['L1773']
- HDR decision applied pre-HOME: {'line': 1099, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1103, 'time': '22:50:09.732', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1409 | 22:50:29.458 | L1668 | 22:50:40.467 | 11009 | shutdown_exit BEFORE surfaceCreated by 10967 ms (L1446) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1409 22:50:29.458; shutdown exit: L1446 22:50:29.500 (Δ=42 ms); vo=null ack: L1462 22:50:29.578
- am_pause_activity: L1315 22:50:29.134; am_on_stop_called: L1380 22:50:29.421; am_resume_activity: L1650 22:50:40.388
- window: 22:50:28.458 .. 22:50:30.500

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

