# Analysis F5

- driver: `mode=fast pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key=`
- app pid: 3565; log lines: 1921
- t_home_send_begin (device): 22:55:57.163; return_sent: 22:55:59.159

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1114 22:55:38.336
- mkst_create_decoder_window exit result=ok: L935 22:55:37.443 owner_key=1159170726756832773 generation=2
- time-pos samples before HOME: L1134 22:55:39.872 PERF 2.035, L1152 22:55:41.881 P5 4.037, L1218 22:55:49.885 PERF 12.045, L1237 22:55:51.873 P5 14.047
- frozen time-pos at first sample after HOME: L1646 20.367 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1204 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1425 | 22:55:58.150 | — |
| dart_authorize_begin | L1694 | 22:56:00.217 | 2067 |
| java_authorize_enter | L1696 | 22:56:00.218 | 1 |
| java_authorize_result | L1703 | 22:56:00.218 | 0 |
| dart_authorize_result | L1705 | 22:56:00.219 | 1 |
| native_ensure_init_exit | L1743 | 22:56:00.277 | 58 |
| native_create_decoder_window_exit | L1747 | 22:56:00.279 | 2 |
| MediaCodec_create | L1748 | 22:56:00.281 | 2 |
| OMX_hevc_Now_Loaded(after create) | L1767 | 22:56:00.302 | 21 |

- ordered: True; same wid across dart/java authorize: True (wid=2258); owner_key same as pre-HOME: True (pre=1159170726756832773, ensure_init=1159170726756832773)
- identity: dart_begin={'wid': '2258', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '2', 'intentSerial': '3'} java_result={'wid': '2258', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '2', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '1159170726756832773', 'generation': '2', 'ready': '1', 'egl_ctx': '0x74110b8180'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '1159170726756832773', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 1
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L1522 22:55:58.635
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1811 22:56:00.546
- active-importer=surfacetexture device_registered=1: L1862 22:56:03.733
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 13.2 s
- time-pos samples: L1646 22:55:59.987 PERF 20.367, L1851 22:56:01.976 P5 20.367, L1897 22:56:11.871 P5 20.387
- PERF pause samples: L1695 t=28 pause=yes
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1866, 't': 1793631363770, 'gen': '4', 'frame_id': '34', 'pts': '20.387033333', 'still': '0', 'route': 'fused'}; last={'line': 1867, 't': 1793631363781, 'gen': '4', 'frame_id': '34', 'pts': '20.387033333', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L1865 `engl] error: MKS-FUSION committed=1 attempted=4 generation=4`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=3565 after=3565 same=True; am_proc_start(pkg)=[206]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L910']; after HOME ['L1726']
- HDR decision applied pre-HOME: {'line': 1110, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1114, 'time': '22:55:38.336', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1340 | 22:55:57.946 | L1522 | 22:55:58.635 | 689 | shutdown_exit BEFORE surfaceCreated by 568 ms (L1398) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1340 22:55:57.946; shutdown exit: L1398 22:55:58.067 (Δ=121 ms); vo=null ack: L1425 22:55:58.150
- am_pause_activity: L1292 22:55:57.756; am_on_stop_called: L1381 22:55:58.044; am_resume_activity: L1497 22:55:58.512
- window: 22:55:56.946 .. 22:55:59.067

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

