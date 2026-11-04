# Timeline R2-2

App PID filter: 17295 (ActivityManager am_pause/resume lines kept from system_server).

Source: `R2-2/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 17:23:34.669 | 0 | L0 |
| home_sent(host probe after cmd returned) | 17:23:35.897 | 1228 | L0 |
| am_pause_lab | 17:23:35.233 | 564 | L66 |
| java_surfaceDestroyed_enter | 17:23:35.422 | 753 | L108 |
| java_send_SurfaceDestroyed | 17:23:35.423 | 754 | L110 |
| dart_event_SurfaceDestroyed | 17:23:35.425 | 756 | L111 |
| dart_detach_lock_acquired | 17:23:35.425 | 756 | L113 |
| dart_detach_vo_null_begin | 17:23:35.425 | 756 | L116 |
| native_shutdown_enter | — | — | — |
| native_shutdown_exit | — | — | — |
| dart_detach_vo_null_ack | 17:23:35.612 | 943 | L180 |
| dart_detach_wid0_ack | 17:23:36.195 | 1526 | L220 |
| dart_detach_apply_complete | 17:23:37.236 | 2567 | L365 |
| dart_detach_lock_released | 17:23:37.240 | 2571 | L372 |
| return_sent | 17:23:36.820 | 2151 | L0 |
| am_resume_lab | 17:23:36.716 | 2047 | L275 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | — | — | — |
| java_surfaceCreated_enter | 17:23:36.812 | 2143 | L290 |
| java_send_SurfaceAvailable | 17:23:36.834 | 2165 | L307 |
| dart_event_SurfaceAvailable | 17:23:36.835 | 2166 | L308 |
| dart_bind_requested | 17:23:36.835 | 2166 | L309 |
| dart_bind_lock_acquired | 17:23:37.240 | 2571 | L373 |
| dart_bind_vo_gpu_next_begin | 17:23:37.247 | 2578 | L382 |
| native_ensure_init_exit | 17:23:37.299 | 2630 | L416 |
| native_create_exit | — | — | — |
| mpv_egl_window_surface | 17:23:37.260 | 2591 | L399 |
| mpv_bridge_not_initialized | 17:23:37.301 | 2632 | L418 |
| dart_bind_complete | 17:23:37.306 | 2637 | L421 |
| first_videoparams_after_return | 17:23:37.784 | 3115 | L457 |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | — |
| shutdown_exit -> dart_vo_null_ACK (ms) | — |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | — |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | — |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | — |
| dart_vo_null_begin -> shutdown_enter (ms) | — |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 428 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 0 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 405 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | 2 |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | 972 |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 753 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -8 |

## Counts (whole dump)

| counter | n |
|---|---|
| ensureInitialized_total_in_log | 0 |
| ensureInitialized_after_home_sent | 0 |
| factory_create_total_in_log | 0 |
| factory_create_after_home_sent | 0 |
| mkst_shutdown_exit_total | 0 |
| mkst_create_exit_total | 0 |
| surfaceCreated_enter_total | 1 |
| surfaceDestroyed_enter_total | 1 |

## Events (time-sorted; HOME window and after, plus pre-HOME bridge lifecycle)

| device time | Δhome (ms) | layer | tid | event | line |
|---|---|---|---|---|---|
| 17:23:33.951 | -718 | host-cmd |  | round_begin launch=continue home=fast pkg=com.example.media_kit_hdr_lab |  |
| 17:23:34.399 | -270 | host-cmd |  | logcat_cleared pid=17295 |  |
| 17:23:34.570 | -99 | host-cmd |  | pid_before pid=17295 |  |
| 17:23:34.669 | 0 | host-cmd |  | home_send_begin |  |
| 17:23:35.233 | 564 | activity | 2062 | am_pause_activity: [0,40726506,com.example.media_kit_hdr_lab/.MainActivity] | L66 |
| 17:23:35.234 | 565 | activity | 17295 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L67 |
| 17:23:35.350 | 681 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L90 |
| 17:23:35.422 | 753 | java-log | 17295 | PlatformVideoView: surfaceDestroyed: handle=498743551568, wid=2258 | L107 |
| 17:23:35.422 | 753 | java | 17295 | mono=399864299 tid=17295 thr=main java surfaceDestroyed enter handle=498743551568 viewId=1 ownerGeneration=2 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2258 disposed=false | L108 |
| 17:23:35.423 | 754 | java | 17295 | mono=399864299 tid=17295 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743551568 viewId=1 surfaceGeneration=2 wid=2258 | L109 |
| 17:23:35.423 | 754 | java | 17295 | mono=399864299 tid=17295 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743551568 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2258 | L110 |
| 17:23:35.425 | 756 | dart | 17295 | dart event SurfaceDestroyed handle=498743551568 wid=2258 generation=2 viewId=1 surfaceGeneration=2 controllerPresent=true boundWid=2258 boundSurfaceGeneration=2 | L111 |
| 17:23:35.425 | 756 | dart | 17295 | dart detach requested wid=2258 surfaceGeneration=2 generation=2 viewId=1 | L112 |
| 17:23:35.425 | 756 | dart | 17295 | dart detach lock acquired wid=2258 surfaceGeneration=2 generation=2 viewId=1 boundWid=2258 boundSurfaceGeneration=2 | L113 |
| 17:23:35.425 | 756 | dart | 17295 | dart detach decision wid=2258 isCurrentOutput=true isInFlightOutput=false | L114 |
| 17:23:35.425 | 756 | dart | 17295 | dart apply begin wid=0 vo=null vid=no | L115 |
| 17:23:35.425 | 756 | dart | 17295 | dart property begin vo=null | L116 |
| 17:23:35.426 | 757 | java | 17295 | mono=399864303 tid=17295 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743551568 viewId=1 surfaceGeneration=2 wid=2258 | L117 |
| 17:23:35.426 | 757 | java | 17295 | mono=399864303 tid=17295 thr=main java surfaceDestroyed exit handle=498743551568 viewId=1 sentEvent=true wid=0 | L118 |
| 17:23:35.466 | 797 | activity | 17295 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L126 |
| 17:23:35.612 | 943 | dart | 17295 | dart property complete vo=null | L180 |
| 17:23:35.613 | 944 | dart | 17295 | dart property begin android-surface-size=2672x1336 | L181 |
| 17:23:35.897 | 1228 | host-cmd |  | home_sent |  |
| 17:23:35.990 | 1321 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity (immediately) |  |
| 17:23:36.121 | 1452 | dart | 17295 | dart property complete android-surface-size=2672x1336 | L217 |
| 17:23:36.121 | 1452 | dart | 17295 | dart property begin wid=0 | L218 |
| 17:23:36.125 | 1456 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L219 |
| 17:23:36.195 | 1526 | dart | 17295 | dart property complete wid=0 | L220 |
| 17:23:36.196 | 1527 | dart | 17295 | dart property begin vo=null | L221 |
| 17:23:36.605 | 1936 | activity | 2613 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L242 |
| 17:23:36.618 | 1949 | dart | 17295 | dart property complete vo=null | L258 |
| 17:23:36.618 | 1949 | dart | 17295 | dart property begin vid=no | L259 |
| 17:23:36.716 | 2047 | activity | 3296 | am_resume_activity: [0,40726506,1021,com.example.media_kit_hdr_lab/.MainActivity] | L275 |
| 17:23:36.736 | 2067 | activity | 17295 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L278 |
| 17:23:36.812 | 2143 | java-log | 17295 | PlatformVideoView: surfaceCreated: handle=498743551568, width=668, height=360, viewIdentity=207085198 | L289 |
| 17:23:36.812 | 2143 | java | 17295 | mono=399865689 tid=17295 thr=main java surfaceCreated enter handle=498743551568 viewId=1 ownerGeneration=2 surfaceGenerationBefore=2 activeSurfaceGeneration=2 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L290 |
| 17:23:36.820 | 2151 | host-cmd |  | return_sent |  |
| 17:23:36.834 | 2165 | java-log | 17295 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743551568, transfer=pq, applied=true | L303 |
| 17:23:36.834 | 2165 | java-log | 17295 | PlatformVideoView: surfaceCreated: created new wid=2254 | L305 |
| 17:23:36.834 | 2165 | java | 17295 | mono=399865710 tid=17295 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743551568 viewId=1 ownerGeneration=2 surfaceGeneration=3 wid=2254 | L306 |
| 17:23:36.834 | 2165 | java | 17295 | mono=399865711 tid=17295 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743551568 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=3 wid=2254 | L307 |
| 17:23:36.835 | 2166 | dart | 17295 | dart event SurfaceAvailable handle=498743551568 wid=2254 generation=2 viewId=1 creationSerial=2 surfaceGeneration=3 controllerPresent=true isCurrentView=true | L308 |
| 17:23:36.835 | 2166 | dart | 17295 | dart bind requested wid=2254 surfaceGeneration=3 generation=2 viewId=1 intentSerial=5 | L309 |
| 17:23:36.835 | 2166 | java | 17295 | mono=399865711 tid=17295 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743551568 viewId=1 surfaceGeneration=3 wid=2254 | L310 |
| 17:23:36.835 | 2166 | java | 17295 | mono=399865711 tid=17295 thr=main java surfaceCreated exit handle=498743551568 viewId=1 surfaceGeneration=3 activeSurfaceGeneration=3 wid=2254 | L311 |
| 17:23:36.835 | 2166 | java-log | 17295 | PlatformVideoView: surfaceChanged: handle=498743551568, format=43, width=2672, height=1336, wid=2254 | L312 |
| 17:23:36.950 | 2281 | java-log | 17295 | PlatformVideoView: surfaceChanged: handle=498743551568, format=43, width=2672, height=1440, wid=2254 | L330 |
| 17:23:37.236 | 2567 | dart | 17295 | dart property complete vid=no | L364 |
| 17:23:37.236 | 2567 | dart | 17295 | dart apply complete wid=0 | L365 |
| 17:23:37.236 | 2567 | dart | 17295 | dart detach producer stopped wid=2258 | L366 |
| 17:23:37.237 | 2568 | java-log | 17295 | PlatformVideoView: releaseSurface generation=2 wid=2258 result=released | L368 |
| 17:23:37.240 | 2571 | dart | 17295 | dart detach reference released wid=2258 | L371 |
| 17:23:37.240 | 2571 | dart | 17295 | dart detach lock released wid=2258 surfaceGeneration=2 | L372 |
| 17:23:37.240 | 2571 | dart | 17295 | dart bind lock acquired wid=2254 surfaceGeneration=3 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L373 |
| 17:23:37.240 | 2571 | dart | 17295 | dart bind branch=rebind wid=2254 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L374 |
| 17:23:37.240 | 2571 | dart | 17295 | dart apply begin wid=2254 vo=gpu-next vid=auto | L375 |
| 17:23:37.240 | 2571 | dart | 17295 | dart property begin vo=null | L376 |
| 17:23:37.242 | 2573 | dart | 17295 | dart property complete vo=null | L377 |
| 17:23:37.242 | 2573 | dart | 17295 | dart property begin android-surface-size=2672x1336 | L378 |
| 17:23:37.242 | 2573 | dart | 17295 | dart property complete android-surface-size=2672x1336 | L379 |
| 17:23:37.242 | 2573 | dart | 17295 | dart property begin wid=2254 | L380 |
| 17:23:37.246 | 2577 | dart | 17295 | dart property complete wid=2254 | L381 |
| 17:23:37.247 | 2578 | dart | 17295 | dart property begin vo=gpu-next | L382 |
| 17:23:37.260 | 2591 | mpv | 17295 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L399 |
| 17:23:37.278 | 2609 | dart | 17295 | dart property complete vo=gpu-next | L408 |
| 17:23:37.278 | 2609 | dart | 17295 | dart property begin vid=auto | L409 |
| 17:23:37.299 | 2630 | native | 17758 | mono=399866175 tid=17758 egl_ctx=0x7418e15500 native mkst_ensure_init(lc_verify) enter initialized=0 window_active=0 owner_key=0 generation=0  | L415 |
| 17:23:37.299 | 2630 | native | 17758 | mono=399866176 tid=17758 egl_ctx=0x7418e15500 native mkst_ensure_init(lc_verify) exit initialized=0 window_active=0 owner_key=0 generation=0 ready=0 | L416 |
| 17:23:37.300 | 2631 | mpv | 17295 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L417 |
| 17:23:37.301 | 2632 | mpv | 17295 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: bridge not initialized (verify-only ensure_init; Java side owns init) | L418 |
| 17:23:37.306 | 2637 | dart | 17295 | dart property complete vid=auto | L419 |
| 17:23:37.306 | 2637 | dart | 17295 | dart apply complete wid=2254 | L420 |
| 17:23:37.306 | 2637 | dart | 17295 | dart bind complete wid=2254 surfaceGeneration=3 | L421 |
| 17:23:37.306 | 2637 | dart | 17295 | dart bind lock released wid=2254 surfaceGeneration=3 | L422 |
| 17:23:37.650 | 2981 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L446 |
| 17:23:37.784 | 3115 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L457 |
| 17:23:37.786 | 3117 | dart | 17295 | dart size property complete android-surface-size=2672x1336 | L459 |
| 17:23:37.831 | 3162 | java-log | 17295 | PlatformVideoView: surfaceChanged: handle=498743551568, format=43, width=2672, height=1336, wid=2254 | L466 |
| 17:23:37.875 | 3206 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L470 |
| 17:23:38.064 | 3395 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L474 |
| 17:23:38.137 | 3468 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L475 |
| 17:23:38.258 | 3589 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L477 |
| 17:23:38.373 | 3704 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L478 |
| 17:23:38.520 | 3851 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L479 |
| 17:23:38.647 | 3978 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L480 |
| 17:23:38.731 | 4062 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L485 |
| 17:23:38.844 | 4175 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L486 |
| 17:23:38.962 | 4293 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L487 |
| 17:23:39.084 | 4415 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L488 |
| 17:23:39.298 | 4629 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L490 |
| 17:23:39.447 | 4778 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L492 |
| 17:23:39.526 | 4857 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L493 |
| 17:23:39.679 | 5010 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L495 |
| 17:23:39.746 | 5077 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L496 |
| 17:23:39.988 | 5319 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L497 |
| 17:23:40.185 | 5516 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L498 |
| 17:23:40.370 | 5701 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L499 |
| 17:23:40.451 | 5782 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L500 |
| 17:23:40.562 | 5893 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L501 |
| 17:23:40.625 | 5956 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L502 |
| 17:23:40.684 | 6015 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L505 |
| 17:23:40.767 | 6098 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L507 |
| 17:23:40.850 | 6181 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L508 |
| 17:23:40.930 | 6261 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L509 |
| 17:23:41.031 | 6362 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L510 |
| 17:23:41.133 | 6464 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L511 |
| 17:23:41.213 | 6544 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L512 |
| 17:23:41.375 | 6706 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L513 |
| 17:23:41.548 | 6879 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L514 |
| 17:23:41.676 | 7007 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L515 |
| 17:23:41.825 | 7156 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L516 |
| 17:23:41.908 | 7239 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L517 |
| 17:23:42.036 | 7367 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L518 |
| 17:23:42.192 | 7523 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L520 |
| 17:23:42.344 | 7675 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L523 |
| 17:23:42.391 | 7722 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L524 |
| 17:23:42.479 | 7810 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L525 |
| 17:23:42.583 | 7914 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L526 |
| 17:23:42.673 | 8004 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L528 |
| 17:23:42.731 | 8062 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L529 |
| 17:23:42.797 | 8128 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L530 |
| 17:23:42.857 | 8188 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L531 |
| 17:23:42.991 | 8322 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L532 |
| 17:23:43.092 | 8423 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L533 |
| 17:23:43.216 | 8547 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L534 |
| 17:23:43.345 | 8676 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L535 |
| 17:23:43.484 | 8815 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L537 |
| 17:23:43.623 | 8954 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L538 |
| 17:23:43.752 | 9083 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L539 |
| 17:23:43.927 | 9258 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L540 |
| 17:23:44.119 | 9450 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L541 |
| 17:23:44.223 | 9554 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L542 |
| 17:23:44.820 | 10151 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L545 |
| 17:23:45.152 | 10483 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L546 |
| 17:23:45.303 | 10634 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L547 |
| 17:23:45.527 | 10858 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L548 |
| 17:23:45.644 | 10975 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L551 |
| 17:23:45.733 | 11064 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L555 |
| 17:23:45.821 | 11152 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L556 |
| 17:23:45.911 | 11242 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L557 |
| 17:23:46.143 | 11474 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L558 |
| 17:23:46.279 | 11610 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L559 |
| 17:23:46.610 | 11941 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L562 |
| 17:23:46.771 | 12102 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L563 |
| 17:23:46.986 | 12317 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L564 |
| 17:23:47.119 | 12450 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L565 |
| 17:23:47.570 | 12901 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L566 |
| 17:23:47.968 | 13299 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L567 |
| 17:23:48.136 | 13467 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L568 |
| 17:23:48.405 | 13736 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L569 |
| 17:23:48.627 | 13958 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L570 |
| 17:23:48.921 | 14252 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L572 |
| 17:23:49.126 | 14457 | host-cmd |  | pid_after pid_before=17295 pid_after=17295 |  |
| 17:23:49.229 | 14560 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L573 |
| 17:23:49.465 | 14796 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L574 |
| 17:23:49.778 | 15109 | host-cmd |  | full_dump lines=     574 |  |
| 17:23:49.925 | 15256 | host-cmd |  | round_end |  |
