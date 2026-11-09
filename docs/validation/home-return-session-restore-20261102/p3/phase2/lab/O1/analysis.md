# Analysis O1

- driver: `mode=openhome pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key=`
- app pid: 4207; log lines: 1791
- t_home_send_begin (device): 22:58:21.600; return_sent: 22:58:33.268

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: MISSING
- mkst_create_decoder_window exit result=ok: MISSING
- time-pos samples before HOME: 
- frozen time-pos at first sample after HOME: L1351 0.213 s
- swap-success before HOME: 0 lines, max frame_id=None; last MKS-FUSION committed: —
- playback ≥15 s before HOME: False; **pre-HOME start-point pass: False**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L826 | 22:58:21.692 | — |
| dart_authorize_begin | L896 | 22:58:21.845 | 153 |
| java_authorize_enter | L897 | 22:58:21.866 | 21 |
| java_authorize_result | L904 | 22:58:21.867 | 1 |
| dart_authorize_result | L908 | 22:58:21.868 | 1 |
| native_ensure_init_exit | L950 | 22:58:21.995 | 127 |
| native_create_decoder_window_exit | L953 | 22:58:21.996 | 1 |
| MediaCodec_create | L954 | 22:58:21.998 | 2 |
| OMX_hevc_Now_Loaded(after create) | L967 | 22:58:22.011 | 13 |

- ordered: True; same wid across dart/java authorize: True (wid=1050746); owner_key same as pre-HOME: False (pre=None, ensure_init=7113845237141439577)
- identity: dart_begin={'wid': '1050746', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '1', 'intentSerial': '1'} java_result={'wid': '1050746', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '1', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '7113845237141439577', 'generation': '2', 'ready': '1', 'egl_ctx': '0x741c30c380'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '7113845237141439577', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 1; java bridge.ensureInitialized after HOME: 3
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L868 22:58:21.804
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1272 22:58:22.895, L1668 22:58:33.686
- active-importer=surfacetexture device_registered=1: L1279 22:58:22.895, L1688 22:58:33.825
- last HDR_SESSION_REPORT hwdecCurrent after return: null (L1711)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 24.6 s
- time-pos samples: L1351 22:58:24.438 PERF 0.213, L1392 22:58:26.450 P5 0.213, L1720 22:58:34.899 PERF 0.234, L1736 22:58:36.445 P5 0.234, L1762 22:58:44.441 PERF 0.234, L1777 22:58:46.442 P5 0.234
- PERF pause samples: L1356 t=8 pause=yes, L1725 t=18 pause=yes, L1767 t=28 pause=yes
- swap-success after return: 4 lines; unique frame_id=[34, 45]; first={'line': 1282, 't': 1793631502895, 'gen': '1', 'frame_id': '45', 'pts': '0.000000000', 'still': '0', 'route': 'rgb-final'}; last={'line': 1693, 't': 1793631513848, 'gen': '2', 'frame_id': '34', 'pts': '0.233566667', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L1691 `engl] error: MKS-FUSION committed=1 attempted=2 generation=2`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=4207 after=4207 same=True; am_proc_start(pkg)=[223]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME []; after HOME ['L927', 'L1582']
- HDR decision applied pre-HOME: None
- HDR decision applied after HOME: {'line': 1707, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'} (decision lines after HOME: 1)
- route consistent: False — see fields
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=null; reports after HOME=[{'line': 1697, 'time': '22:58:33.897', 'hwdecCurrent': 'null'}, {'line': 1711, 'time': '22:58:34.899', 'hwdecCurrent': 'null'}]; last in log={'line': 1711, 'time': '22:58:34.899', 'hwdecCurrent': 'null'}; all surfacetexture=False
- SF dumps: pre-home=False post-return=False
- **C6 pass: False**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L842 | 22:58:21.719 | L868 | 22:58:21.804 | 85 | surfaceCreated BEFORE shutdown_exit by 630 ms (L1218) |
| L1183 | 22:58:22.357 | L1476 | 22:58:33.258 | 10901 | shutdown_exit BEFORE surfaceCreated by 10824 ms (L1218) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L842 22:58:21.719; shutdown exit: L1218 22:58:22.434 (Δ=715 ms); vo=null ack: L826 22:58:21.692
- am_pause_activity: L1031 22:58:22.096; am_on_stop_called: L1154 22:58:22.316; am_resume_activity: L1457 22:58:33.181
- window: 22:58:20.719 .. 22:58:23.434

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
| event=swap-success | 4 |

