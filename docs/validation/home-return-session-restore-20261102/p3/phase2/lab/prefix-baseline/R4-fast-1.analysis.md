# Analysis R4-fast-1

- driver: `launch=fresh method=F sleep=0 pkg=com.example.media_kit_hdr_lab`
- app pid: 26247; log lines: 1892
- t_home_send_begin (device): 20:17:28.648; return_sent: 20:17:30.456

## Pre-HOME hardware-decode starting point

- HDR_SESSION_REPORT hwdecCurrent=surfacetexture: L1117 20:17:14.115
- mkst_create_decoder_window exit result=ok: L941 20:17:13.217 owner_key=6372643666194613512 generation=2
- time-pos samples before HOME: L1138 20:17:15.696 PERF 2.102, L1159 20:17:17.701 P5 4.071, L1213 20:17:25.697 PERF 12.079, L1233 20:17:27.702 P5 14.081
- frozen time-pos at first sample after HOME: L1869 16.250 s
- swap-success before HOME: 3 lines, max frame_id=45; last MKS-FUSION committed: L1198 `] error: MKS-FUSION committed=300 attempted=307 generation=2`
- playback ≥15 s before HOME: True; **pre-HOME start-point pass: True**

## C1 time chain after HOME (same identity)

| anchor | line | device time | Δprev (ms) |
|---|---|---|---|
| vo_null_property_complete | L1485 | 20:17:29.857 | — |
| dart_authorize_begin | MISSING | — | — |
| java_authorize_enter | MISSING | — | — |
| java_authorize_result | MISSING | — | — |
| dart_authorize_result | MISSING | — | — |
| native_ensure_init_exit | L1774 | 20:17:32.133 | 2276 |
| native_create_decoder_window_exit | MISSING | — | — |
| MediaCodec_create | MISSING | — | — |
| OMX_hevc_Now_Loaded(after create) | MISSING | — | — |

- ordered: True; same wid across dart/java authorize: False (wid=None); owner_key same as pre-HOME: False (pre=6372643666194613512, ensure_init=0)
- identity: dart_begin=None java_result=None ensure_init={'initialized': '0', 'owner_key': '0', 'generation': '0', 'ready': '0', 'egl_ctx': '0x7407afe600'} create_window=None
- java factory.create after HOME: 0; java bridge.ensureInitialized after HOME: 0
- **C1 pass: False**

## C2 after return

- surfaceCreated enter: L1581 20:17:30.216
- `bridge not initialized`: 1 (lines [1776]); `yuv420p10`: 10 (lines [1813, 1829, 1855, 1856, 1857])
- VIDEOPARAMS pixelformat: mediacodec: MISSING
- active-importer registered: MISSING
- last HDR_SESSION_REPORT hwdecCurrent after return: None (LNone)
- **C2 pass: False**

## C3 playback after return

- observation window after surfaceCreated: 7.5 s
- time-pos samples: L1869 20:17:35.697 PERF 16.250, L1887 20:17:37.704 P5 16.250
- PERF pause samples: L1874 t=28 pause=yes
- swap-success after return: 2 lines; unique frame_id=[34]; first={'line': 1864, 't': 1793621855068, 'gen': '2', 'frame_id': '34', 'pts': '16.249566667', 'still': '0', 'route': 'rgb-final'}; last={'line': 1866, 't': 1793621855096, 'gen': '2', 'frame_id': '34', 'pts': '16.249566667', 'still': '1', 'route': 'rgb-final'}
- last MKS-FUSION committed after return: —
- time-pos advanced ≥15 s after return: False

## C4 errors (whole log)

- BridgeActivationIssue: 0 []
- authorize failed/stale/skipped/abandoned or non-ok result: 0 []
- HdrErrorEvent total=2 (noDisplayCapabilityReport single-open pre-existing=2, other=0 [])
- **C4 pass: True**

## C5 process

- pid before=26247 after=26247 same=True; am_proc_start(pkg)=[122]; am_proc_died(pkg)=[]
- FATAL/tombstone text lines=0 []; F-level lines=0; ANR/am_crash lines=0 []
- **C5 pass: True**

## C6 HDR

- MKSURF-E1 dataspace applied: pre-HOME ['L913']; after HOME ['L1758']
- HDR decision applied pre-HOME: {'line': 1113, 'phase': 'applied', 'gen': '1', 'class': 'dvP84', 'selected': 'baseLayerConvert', 'presentation': 'nativeHdr', 'vo': 'gpu-next', 'hwdec': 'surfacetexture', 'output': 'pq', 'topology': 'platformView'}
- HDR decision applied after HOME: None (decision lines after HOME: 0)
- route consistent: True — no new HDR decision line after HOME (route unchanged, decision not re-run)
- HDR_SESSION_REPORT hwdecCurrent: pre-HOME=surfacetexture; reports after HOME=[]; last in log={'line': 1117, 'time': '20:17:14.115', 'hwdecCurrent': 'surfacetexture'}; all surfacetexture=True
- SF dumps: pre-home=False post-return=False
- **C6 pass: True**

## C7 HOME cycle intervals (Java level)

| sd line | sd time | sc line | sc time | sd→sc (ms) | shutdown exit vs surfaceCreated |
|---|---|---|---|---|---|
| L1372 | 20:17:29.480 | L1581 | 20:17:30.216 | 736 | shutdown_exit BEFORE surfaceCreated by 500 ms (L1460) |

- SurfaceFailed/RuntimeFailed: 0

## Teardown window errors

- surfaceDestroyed enter: L1372 20:17:29.480; shutdown exit: L1460 20:17:29.716 (Δ=236 ms); vo=null ack: L1485 20:17:29.857
- am_pause_activity: L1264 20:17:29.213; am_on_stop_called: L1402 20:17:29.550; am_resume_activity: L1568 20:17:30.144
- window: 20:17:28.480 .. 20:17:30.716

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
| yuv420p10 | 10 |
| MKSURF-E1: dataspace applied | 2 |
| Mediacodec create | 2 |
| mkst_ensure_init(lc_verify) exit | 2 |
| mkst_create_decoder_window exit | 1 |
| authorize begin | 0 |
| event=swap-success | 5 |

