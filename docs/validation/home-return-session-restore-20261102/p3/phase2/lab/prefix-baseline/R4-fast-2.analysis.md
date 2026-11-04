# Analysis R4-fast-2

- driver: `launch=fresh method=F sleep=0 pkg=com.example.media_kit_hdr_lab`
- app pid: 26505; log lines: 1938
- t_home_send_begin (device): 20:18:13.983; return_sent: 20:18:15.702

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1083 20:17:59.437
- mkst_create_decoder_window exit result=ok: L883 20:17:58.556 owner_key=11151253040579130577 generation=2
- time-pos samples before HOME: L1134 20:18:00.888 PERF 1.835, L1155 20:18:02.891 P5 3.837, L1209 20:18:10.888 PERF 11.845, L1231 20:18:12.895 P5 13.847
- frozen time-pos at first sample after HOME: L1854 16.000 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1199 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1466 | 20:18:15.050 | — |
| dart_authorize_begin | MISSING | — | — |
| java_authorize_enter | MISSING | — | — |
| java_authorize_result | MISSING | — | — |
| dart_authorize_result | MISSING | — | — |
| native_ensure_init_exit | L1746 | 20:18:17.155 | 2105 |
| native_create_decoder_window_exit | MISSING | — | — |
| MediaCodec_create | MISSING | — | — |
| OMX_hevc_Now_Loaded(after create) | MISSING | — | — |

- ordered: True; same wid across dart/java authorize: False (wid=None); owner_key same as pre-HOME: False (pre=11151253040579130577, ensure_init=0)
- identity: dart_begin=None java_result=None ensure_init={'initialized': '0', 'owner_key': '0', 'generation': '0', 'ready': '0', 'egl_ctx': '0x7418b0d500'} create_window=None
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 0
- **C1 pass: False**

## C2 after return

- surfaceCreated enter: L1531 20:18:15.378
- `bridge not initialized`: 1 (lines [1748]); `yuv420p10`: 72 (lines [1775, 1791, 1795, 1796, 1798])
- VIDEOPARAMS pixelformat: mediacodec: MISSING
- active-importer registered: MISSING
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: False**

## C3 playback after return

- observation window after surfaceCreated: 13.1 s
- time-pos samples: L1854 20:18:20.901 PERF 16.000, L1885 20:18:23.067 P5 16.000
- PERF pause samples: L1861 t=28 pause=yes
- swap-success after return: 0 lines; unique frame_id=[]; first=None; last=None
- last MKS-FUSION committed after return: —
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=26505 after=26505 same=True; am_proc_start(pkg)=[131]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L856']; after HOME ['L1730']
- HDR decision applied pre-HOME: {'line': 1079, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1083, 'time': '20:17:59.437', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1358 | 20:18:14.781 | L1531 | 20:18:15.378 | 597 | shutdown_exit BEFORE surfaceCreated by 463 ms (L1419) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1358 20:18:14.781; shutdown exit: L1419 20:18:14.915 (Δ=134 ms); vo=null ack: L1466 20:18:15.050
- am_pause_activity: L1261 20:18:14.540; am_on_stop_called: L1422 20:18:14.917; am_resume_activity: L1526 20:18:15.345
- window: 20:18:13.781 .. 20:18:15.915

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
| bridge not initialized | 1 |
| yuv420p10 | 72 |
| MKSURF-E1: dataspace applied | 2 |
| Mediacodec create | 2 |
| mkst_ensure_init(lc_verify) exit | 2 |
| mkst_create_decoder_window exit | 1 |
| authorize begin | 0 |
| event=swap-success | 3 |

