# Analysis F3

- driver: `mode=fast pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key=`
- app pid: 2807; log lines: 1942
- t_home_send_begin (device): 22:54:10.504; return_sent: 22:54:12.302

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1139 22:53:52.224
- mkst_create_decoder_window exit result=ok: L952 22:53:51.223 owner_key=16721639828673806270 generation=2
- time-pos samples before HOME: L1160 22:53:53.752 PERF 2.102, L1178 22:53:55.761 P5 4.104, L1263 22:54:03.750 PERF 12.079, L1287 22:54:05.761 P5 14.081
- frozen time-pos at first sample after HOME: L1847 19.902 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1250 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1495 | 22:54:11.483 | — |
| dart_authorize_begin | L1734 | 22:54:13.433 | 1950 |
| java_authorize_enter | L1735 | 22:54:13.435 | 2 |
| java_authorize_result | L1742 | 22:54:13.436 | 1 |
| dart_authorize_result | L1743 | 22:54:13.438 | 2 |
| native_ensure_init_exit | L1779 | 22:54:13.493 | 55 |
| native_create_decoder_window_exit | L1783 | 22:54:13.495 | 2 |
| MediaCodec_create | L1784 | 22:54:13.497 | 2 |
| OMX_hevc_Now_Loaded(after create) | L1806 | 22:54:13.519 | 22 |

- ordered: True; same wid across dart/java authorize: True (wid=2258); owner_key same as pre-HOME: True (pre=16721639828673806270, ensure_init=16721639828673806270)
- identity: dart_begin={'wid': '2258', 'generation': '2', 'viewId': '1', 'surfaceGeneration': '2', 'intentSerial': '3'} java_result={'wid': '2258', 'code': 'ok', 'applicable': 'true', 'ok': 'true', 'ownerGeneration': '2', 'surfaceGeneration': '2', 'viewId': '1'} ensure_init={'initialized': '1', 'owner_key': '16721639828673806270', 'generation': '2', 'ready': '1', 'egl_ctx': '0x741da5c400'} create_window={'initialized': '1', 'window_active': '1', 'owner_key': '16721639828673806270', 'generation': '2', 'result': 'ok'}
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 1
- **C1 pass: True**

## C2 after return

- surfaceCreated enter: L1573 22:54:11.890
- `bridge not initialized`: 0 (lines []); `yuv420p10`: 0 (lines [])
- VIDEOPARAMS pixelformat: mediacodec: L1848 22:54:13.757
- active-importer=surfacetexture device_registered=1: L1910 22:54:16.678
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: True**

## C3 playback after return

- observation window after surfaceCreated: 13.9 s
- time-pos samples: L1847 22:54:13.756 PERF 19.902, L1903 22:54:15.868 P5 19.902, L1931 22:54:25.756 P5 19.920
- PERF pause samples: L1861 t=28 pause=yes
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1914, 't': 1793631256715, 'gen': '4', 'frame_id': '34', 'pts': '19.919900000', 'still': '0', 'route': 'fused'}; last={'line': 1915, 't': 1793631256723, 'gen': '4', 'frame_id': '34', 'pts': '19.919900000', 'still': '1', 'route': 'fused'}
- last MKS-FUSION committed after return: L1913 `engl] error: MKS-FUSION committed=1 attempted=4 generation=4`
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=2807 after=2807 same=True; am_proc_start(pkg)=[210]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L912']; after HOME ['L1762']
- HDR decision applied pre-HOME: {'line': 1135, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1139, 'time': '22:53:52.224', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1403 | 22:54:11.264 | L1573 | 22:54:11.890 | 626 | shutdown_exit BEFORE surfaceCreated by 525 ms (L1464) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1403 22:54:11.264; shutdown exit: L1464 22:54:11.365 (Δ=101 ms); vo=null ack: L1495 22:54:11.483
- am_pause_activity: L1334 22:54:11.045; am_on_stop_called: L1447 22:54:11.344; am_resume_activity: L1559 22:54:11.804
- window: 22:54:10.264 .. 22:54:12.365

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

