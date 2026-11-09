# Analysis T0-mediakey

- driver: `mode=pause pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key=KEYCODE_MEDIA_PAUSE resume_key=KEYCODE_MEDIA_PLAY`
- app pid: 32101; log lines: 2097
- t_home_send_begin (device): 22:31:50.659; return_sent: 22:32:02.704

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1112 22:31:31.237
- mkst_create_decoder_window exit result=ok: L913 22:31:30.343 owner_key=2180508694999579996 generation=2
- time-pos samples before HOME: L1140 22:31:32.712 PERF 1.835, L1159 22:31:34.718 P5 3.837, L1212 22:31:42.741 PERF 11.879, L1233 22:31:44.765 P5 13.881
- frozen time-pos at first sample after HOME: L1628 20.750 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1199 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1550 | 22:31:51.794 | — |
| dart_authorize_begin | L1850 | 22:32:02.735 | 10941 |
| java_authorize_enter | L1864 | 22:32:02.782 | 47 |
| java_authorize_result | L1871 | 22:32:02.782 | 0 |
| dart_authorize_result | L1873 | 22:32:02.783 | 1 |
| native_ensure_init_exit | L1921 | 22:32:02.846 | 63 |
| native_create_decoder_window_exit | L1925 | 22:32:02.847 | 1 |
| MediaCodec_create | L1931 | 22:32:02.849 | 2 |
| OMX_hevc_Now_Loaded(after create) | L1943 | 22:32:02.867 | 18 |

- ordered: True; same wid across dart/java authorize: True (wid=1982); owner_key same as pre-HOME: True (pre=2180508694999579996, ensure_init=2180508694999579996)
- identity: dart_begin={'wid': '1982', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '2', 'intentSerial': '3'} java_result={'wid': '1982', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '2', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '2180508694999579996', 'generation': '2', 'ready': '1', 'egl_ctx': '0x741dde9c80'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '2180508694999579996', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 1
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L1810 22:32:02.663
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1996 22:32:03.098
- active-importer=surfacetexture device_registered=1: L2031 22:32:06.510
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 22.1 s
- time-pos samples: L2018 22:32:04.826 P5 20.750, L2073 22:32:14.716 P5 20.754, L2083 22:32:24.712 PERF 20.754, L2089 22:32:24.720 P5 20.754
- PERF pause samples: L2088 t=60 pause=yes
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 2035, 't': 1793629926550, 'gen': '2', 'frame_id': '34', 'pts': '20.754066667', 'still': '0', 'route': 'fused'}; last={'line': 2036, 't': 1793629926559, 'gen': '2', 'frame_id': '34', 'pts': '20.754066667', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L2034 `engl] error: MKS-FUSION committed=1 attempted=2 generation=2`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=32101 after=32101 same=True; am_proc_start(pkg)=[192]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L889']; after HOME ['L1903']
- HDR decision applied pre-HOME: {'line': 1108, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1112, 'time': '22:31:31.237', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1421 | 22:31:51.590 | L1810 | 22:32:02.663 | 11073 | shutdown_exit BEFORE surfaceCreated by 10974 ms (L1491) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1421 22:31:51.590; shutdown exit: L1491 22:31:51.689 (Δ=99 ms); vo=null ack: L1550 22:31:51.794
- am_pause_activity: L1347 22:31:51.221; am_on_stop_called: L1408 22:31:51.554; am_resume_activity: L1787 22:32:02.596
- window: 22:31:50.590 .. 22:31:52.689

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

