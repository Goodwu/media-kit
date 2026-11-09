# Analysis N2

- driver: `mode=normal pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key=`
- app pid: 1013; log lines: 1962
- t_home_send_begin (device): 22:49:23.530; return_sent: 22:49:36.347

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1138 22:49:05.098
- mkst_create_decoder_window exit result=ok: L970 22:49:04.224 owner_key=3373717545738814617 generation=2
- time-pos samples before HOME: L1157 22:49:06.247 PERF 1.668, L1181 22:49:08.250 P5 3.637, L1230 22:49:16.249 PERF 11.645, L1252 22:49:18.251 P5 13.647
- frozen time-pos at first sample after HOME: L1550 20.000 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1218 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1471 | 22:49:24.558 | — |
| dart_authorize_begin | L1733 | 22:49:36.315 | 11757 |
| java_authorize_enter | L1746 | 22:49:36.346 | 31 |
| java_authorize_result | L1753 | 22:49:36.346 | 0 |
| dart_authorize_result | L1754 | 22:49:36.351 | 5 |
| native_ensure_init_exit | L1809 | 22:49:36.455 | 104 |
| native_create_decoder_window_exit | L1813 | 22:49:36.456 | 1 |
| MediaCodec_create | L1814 | 22:49:36.458 | 2 |
| OMX_hevc_Now_Loaded(after create) | L1825 | 22:49:36.475 | 17 |

- ordered: True; same wid across dart/java authorize: True (wid=1986); owner_key same as pre-HOME: True (pre=3373717545738814617, ensure_init=3373717545738814617)
- identity: dart_begin={'wid': '1986', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '2', 'intentSerial': '3'} java_result={'wid': '1986', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '2', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '3373717545738814617', 'generation': '2', 'ready': '1', 'egl_ctx': '0x742556fa80'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '3373717545738814617', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 1
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L1692 22:49:36.268
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1877 22:49:36.699
- active-importer=surfacetexture device_registered=1: L1918 22:49:39.684
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 22.0 s
- time-pos samples: L1899 22:49:38.356 P5 20.000, L1937 22:49:48.252 P5 20.020, L1952 22:49:58.242 PERF 20.020, L1958 22:49:58.259 P5 20.020
- PERF pause samples: L1957 t=60 pause=yes
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1922, 't': 1793630979716, 'gen': '2', 'frame_id': '34', 'pts': '20.020000000', 'still': '0', 'route': 'fused'}; last={'line': 1923, 't': 1793630979727, 'gen': '2', 'frame_id': '34', 'pts': '20.020000000', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L1921 `engl] error: MKS-FUSION committed=1 attempted=2 generation=2`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=1013 after=1013 same=True; am_proc_start(pkg)=[199]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L937']; after HOME ['L1786']
- HDR decision applied pre-HOME: {'line': 1134, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1138, 'time': '22:49:05.098', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1391 | 22:49:24.381 | L1692 | 22:49:36.268 | 11887 | shutdown_exit BEFORE surfaceCreated by 11782 ms (L1454) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1391 22:49:24.381; shutdown exit: L1454 22:49:24.486 (Δ=105 ms); vo=null ack: L1471 22:49:24.558
- am_pause_activity: L1340 22:49:24.163; am_on_stop_called: L1420 22:49:24.436; am_resume_activity: L1669 22:49:36.187
- window: 22:49:23.381 .. 22:49:25.486

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

