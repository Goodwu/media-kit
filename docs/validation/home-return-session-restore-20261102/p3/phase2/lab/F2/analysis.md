# Analysis F2

- driver: `mode=fast pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key=`
- app pid: 2320; log lines: 1896
- t_home_send_begin (device): 22:53:16.647; return_sent: 22:53:18.369

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1108 22:52:58.176
- mkst_create_decoder_window exit result=ok: L937 22:52:57.270 owner_key=18445166970016255604 generation=2
- time-pos samples before HOME: L1127 22:52:59.752 PERF 2.169, L1177 22:53:01.746 P5 4.137, L1233 22:53:09.733 PERF 12.145, L1254 22:53:11.735 P5 14.147
- frozen time-pos at first sample after HOME: L1790 20.118 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1219 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1471 | 22:53:17.676 | — |
| dart_authorize_begin | L1679 | 22:53:19.620 | 1944 |
| java_authorize_enter | L1680 | 22:53:19.621 | 1 |
| java_authorize_result | L1687 | 22:53:19.621 | 0 |
| dart_authorize_result | L1688 | 22:53:19.622 | 1 |
| native_ensure_init_exit | L1724 | 22:53:19.679 | 57 |
| native_create_decoder_window_exit | L1728 | 22:53:19.680 | 1 |
| MediaCodec_create | L1731 | 22:53:19.683 | 3 |
| OMX_hevc_Now_Loaded(after create) | L1752 | 22:53:19.700 | 17 |

- ordered: True; same wid across dart/java authorize: True (wid=2258); owner_key same as pre-HOME: True (pre=18445166970016255604, ensure_init=18445166970016255604)
- identity: dart_begin={'wid': '2258', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '2', 'intentSerial': '3'} java_result={'wid': '2258', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '2', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '18445166970016255604', 'generation': '2', 'ready': '1', 'egl_ctx': '0x7418d9e780'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '18445166970016255604', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 1
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L1535 22:53:18.020
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1789 22:53:19.911
- active-importer=surfacetexture device_registered=1: L1858 22:53:22.948
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 13.7 s
- time-pos samples: L1790 22:53:19.912 PERF 20.118, L1852 22:53:21.822 P5 20.118, L1876 22:53:31.739 P5 20.120
- PERF pause samples: L1816 t=28 pause=yes
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1862, 't': 1793631202980, 'gen': '4', 'frame_id': '34', 'pts': '20.120100000', 'still': '0', 'route': 'fused'}; last={'line': 1863, 't': 1793631202990, 'gen': '4', 'frame_id': '34', 'pts': '20.120100000', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L1861 `engl] error: MKS-FUSION committed=1 attempted=4 generation=4`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=2320 after=2320 same=True; am_proc_start(pkg)=[208]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L912']; after HOME ['L1707']
- HDR decision applied pre-HOME: {'line': 1104, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1108, 'time': '22:52:58.176', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1366 | 22:53:17.410 | L1535 | 22:53:18.020 | 610 | shutdown_exit BEFORE surfaceCreated by 526 ms (L1412) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1366 22:53:17.410; shutdown exit: L1412 22:53:17.494 (Δ=84 ms); vo=null ack: L1471 22:53:17.676
- am_pause_activity: L1312 22:53:17.209; am_on_stop_called: L1416 22:53:17.542; am_resume_activity: L1530 22:53:17.973
- window: 22:53:16.410 .. 22:53:18.494

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

