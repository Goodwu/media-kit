# Timeline R2-3

App PID filter: 17295 (ActivityManager am_pause/resume lines kept from system_server).

Source: `R2-3/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 17:23:52.968 | 0 | L0 |
| home_sent(host probe after cmd returned) | 17:23:54.278 | 1310 | L0 |
| am_pause_lab | 17:23:53.618 | 650 | L58 |
| java_surfaceDestroyed_enter | 17:23:53.889 | 921 | L136 |
| java_send_SurfaceDestroyed | 17:23:53.889 | 921 | L138 |
| dart_event_SurfaceDestroyed | 17:23:53.890 | 922 | L139 |
| dart_detach_lock_acquired | 17:23:53.890 | 922 | L142 |
| dart_detach_vo_null_begin | 17:23:53.890 | 922 | L145 |
| native_shutdown_enter | — | — | — |
| native_shutdown_exit | — | — | — |
| dart_detach_vo_null_ack | 17:23:54.017 | 1049 | L175 |
| dart_detach_wid0_ack | 17:23:54.558 | 1590 | L207 |
| dart_detach_apply_complete | 17:23:55.942 | 2974 | L364 |
| dart_detach_lock_released | 17:23:55.945 | 2977 | L370 |
| return_sent | 17:23:55.267 | 2299 | L0 |
| am_resume_lab | 17:23:55.134 | 2166 | L263 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | — | — | — |
| java_surfaceCreated_enter | 17:23:55.262 | 2294 | L278 |
| java_send_SurfaceAvailable | 17:23:55.268 | 2300 | L295 |
| dart_event_SurfaceAvailable | 17:23:55.269 | 2301 | L296 |
| dart_bind_requested | 17:23:55.269 | 2301 | L297 |
| dart_bind_lock_acquired | 17:23:55.946 | 2978 | L371 |
| dart_bind_vo_gpu_next_begin | 17:23:55.963 | 2995 | L381 |
| native_ensure_init_exit | 17:23:56.012 | 3044 | L411 |
| native_create_exit | — | — | — |
| mpv_egl_window_surface | 17:23:55.979 | 3011 | L389 |
| mpv_bridge_not_initialized | 17:23:56.013 | 3045 | L413 |
| dart_bind_complete | 17:23:56.017 | 3049 | L417 |
| first_videoparams_after_return | 17:23:56.481 | 3513 | L444 |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | — |
| shutdown_exit -> dart_vo_null_ACK (ms) | — |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | — |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | — |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | — |
| dart_vo_null_begin -> shutdown_enter (ms) | — |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 684 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 1 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 676 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | 1 |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | 1219 |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 921 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -5 |

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
| 17:23:52.110 | -858 | host-cmd |  | round_begin launch=continue home=fast pkg=com.example.media_kit_hdr_lab |  |
| 17:23:52.577 | -391 | host-cmd |  | logcat_cleared pid=17295 |  |
| 17:23:52.829 | -139 | host-cmd |  | pid_before pid=17295 |  |
| 17:23:52.968 | 0 | host-cmd |  | home_send_begin |  |
| 17:23:53.618 | 650 | activity | 2062 | am_pause_activity: [0,40726506,com.example.media_kit_hdr_lab/.MainActivity] | L58 |
| 17:23:53.620 | 652 | activity | 17295 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L59 |
| 17:23:53.714 | 746 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L79 |
| 17:23:53.819 | 851 | activity | 17295 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L113 |
| 17:23:53.889 | 921 | java-log | 17295 | PlatformVideoView: surfaceDestroyed: handle=498743551568, wid=2254 | L135 |
| 17:23:53.889 | 921 | java | 17295 | mono=399882765 tid=17295 thr=main java surfaceDestroyed enter handle=498743551568 viewId=1 ownerGeneration=2 surfaceGeneration=3 activeSurfaceGeneration=3 wid=2254 disposed=false | L136 |
| 17:23:53.889 | 921 | java | 17295 | mono=399882765 tid=17295 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743551568 viewId=1 surfaceGeneration=3 wid=2254 | L137 |
| 17:23:53.889 | 921 | java | 17295 | mono=399882766 tid=17295 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743551568 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=3 wid=2254 | L138 |
| 17:23:53.890 | 922 | dart | 17295 | dart event SurfaceDestroyed handle=498743551568 wid=2254 generation=2 viewId=1 surfaceGeneration=3 controllerPresent=true boundWid=2254 boundSurfaceGeneration=3 | L139 |
| 17:23:53.890 | 922 | dart | 17295 | dart detach requested wid=2254 surfaceGeneration=3 generation=2 viewId=1 | L141 |
| 17:23:53.890 | 922 | dart | 17295 | dart detach lock acquired wid=2254 surfaceGeneration=3 generation=2 viewId=1 boundWid=2254 boundSurfaceGeneration=3 | L142 |
| 17:23:53.890 | 922 | dart | 17295 | dart detach decision wid=2254 isCurrentOutput=true isInFlightOutput=false | L143 |
| 17:23:53.890 | 922 | dart | 17295 | dart apply begin wid=0 vo=null vid=no | L144 |
| 17:23:53.890 | 922 | dart | 17295 | dart property begin vo=null | L145 |
| 17:23:53.891 | 923 | java | 17295 | mono=399882767 tid=17295 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743551568 viewId=1 surfaceGeneration=3 wid=2254 | L147 |
| 17:23:53.891 | 923 | java | 17295 | mono=399882767 tid=17295 thr=main java surfaceDestroyed exit handle=498743551568 viewId=1 sentEvent=true wid=0 | L148 |
| 17:23:54.017 | 1049 | dart | 17295 | dart property complete vo=null | L175 |
| 17:23:54.017 | 1049 | dart | 17295 | dart property begin android-surface-size=2672x1336 | L176 |
| 17:23:54.278 | 1310 | host-cmd |  | home_sent |  |
| 17:23:54.416 | 1448 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity (immediately) |  |
| 17:23:54.478 | 1510 | dart | 17295 | dart property complete android-surface-size=2672x1336 | L203 |
| 17:23:54.478 | 1510 | dart | 17295 | dart property begin wid=0 | L204 |
| 17:23:54.479 | 1511 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L205 |
| 17:23:54.558 | 1590 | dart | 17295 | dart property complete wid=0 | L207 |
| 17:23:54.558 | 1590 | dart | 17295 | dart property begin vo=null | L208 |
| 17:23:55.040 | 2072 | activity | 1739 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L231 |
| 17:23:55.040 | 2072 | dart | 17295 | dart property complete vo=null | L232 |
| 17:23:55.040 | 2072 | dart | 17295 | dart property begin vid=no | L233 |
| 17:23:55.134 | 2166 | activity | 19361 | am_resume_activity: [0,40726506,1021,com.example.media_kit_hdr_lab/.MainActivity] | L263 |
| 17:23:55.150 | 2182 | activity | 17295 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L266 |
| 17:23:55.262 | 2294 | java-log | 17295 | PlatformVideoView: surfaceCreated: handle=498743551568, width=668, height=360, viewIdentity=207085198 | L277 |
| 17:23:55.262 | 2294 | java | 17295 | mono=399884139 tid=17295 thr=main java surfaceCreated enter handle=498743551568 viewId=1 ownerGeneration=2 surfaceGenerationBefore=3 activeSurfaceGeneration=3 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L278 |
| 17:23:55.267 | 2299 | host-cmd |  | return_sent |  |
| 17:23:55.268 | 2300 | java-log | 17295 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743551568, transfer=pq, applied=true | L291 |
| 17:23:55.268 | 2300 | java-log | 17295 | PlatformVideoView: surfaceCreated: created new wid=2099394 | L293 |
| 17:23:55.268 | 2300 | java | 17295 | mono=399884144 tid=17295 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743551568 viewId=1 ownerGeneration=2 surfaceGeneration=4 wid=2099394 | L294 |
| 17:23:55.268 | 2300 | java | 17295 | mono=399884145 tid=17295 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743551568 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=4 wid=2099394 | L295 |
| 17:23:55.269 | 2301 | dart | 17295 | dart event SurfaceAvailable handle=498743551568 wid=2099394 generation=2 viewId=1 creationSerial=2 surfaceGeneration=4 controllerPresent=true isCurrentView=true | L296 |
| 17:23:55.269 | 2301 | dart | 17295 | dart bind requested wid=2099394 surfaceGeneration=4 generation=2 viewId=1 intentSerial=7 | L297 |
| 17:23:55.269 | 2301 | java | 17295 | mono=399884145 tid=17295 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743551568 viewId=1 surfaceGeneration=4 wid=2099394 | L298 |
| 17:23:55.269 | 2301 | java | 17295 | mono=399884145 tid=17295 thr=main java surfaceCreated exit handle=498743551568 viewId=1 surfaceGeneration=4 activeSurfaceGeneration=4 wid=2099394 | L299 |
| 17:23:55.269 | 2301 | java-log | 17295 | PlatformVideoView: surfaceChanged: handle=498743551568, format=43, width=2672, height=1336, wid=2099394 | L300 |
| 17:23:55.358 | 2390 | java-log | 17295 | PlatformVideoView: surfaceChanged: handle=498743551568, format=43, width=2672, height=1440, wid=2099394 | L312 |
| 17:23:55.942 | 2974 | dart | 17295 | dart property complete vid=no | L363 |
| 17:23:55.942 | 2974 | dart | 17295 | dart apply complete wid=0 | L364 |
| 17:23:55.942 | 2974 | dart | 17295 | dart detach producer stopped wid=2254 | L365 |
| 17:23:55.944 | 2976 | java-log | 17295 | PlatformVideoView: releaseSurface generation=3 wid=2254 result=released | L367 |
| 17:23:55.945 | 2977 | dart | 17295 | dart detach reference released wid=2254 | L369 |
| 17:23:55.945 | 2977 | dart | 17295 | dart detach lock released wid=2254 surfaceGeneration=3 | L370 |
| 17:23:55.946 | 2978 | dart | 17295 | dart bind lock acquired wid=2099394 surfaceGeneration=4 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L371 |
| 17:23:55.946 | 2978 | dart | 17295 | dart bind branch=rebind wid=2099394 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L372 |
| 17:23:55.946 | 2978 | dart | 17295 | dart apply begin wid=2099394 vo=gpu-next vid=auto | L373 |
| 17:23:55.946 | 2978 | dart | 17295 | dart property begin vo=null | L374 |
| 17:23:55.953 | 2985 | dart | 17295 | dart property complete vo=null | L376 |
| 17:23:55.953 | 2985 | dart | 17295 | dart property begin android-surface-size=2672x1336 | L377 |
| 17:23:55.953 | 2985 | dart | 17295 | dart property complete android-surface-size=2672x1336 | L378 |
| 17:23:55.953 | 2985 | dart | 17295 | dart property begin wid=2099394 | L379 |
| 17:23:55.963 | 2995 | dart | 17295 | dart property complete wid=2099394 | L380 |
| 17:23:55.963 | 2995 | dart | 17295 | dart property begin vo=gpu-next | L381 |
| 17:23:55.979 | 3011 | mpv | 17295 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L389 |
| 17:23:55.997 | 3029 | dart | 17295 | dart property complete vo=gpu-next | L403 |
| 17:23:55.997 | 3029 | dart | 17295 | dart property begin vid=auto | L404 |
| 17:23:56.012 | 3044 | native | 17882 | mono=399884889 tid=17882 egl_ctx=0x7413b94600 native mkst_ensure_init(lc_verify) enter initialized=0 window_active=0 owner_key=0 generation=0  | L410 |
| 17:23:56.012 | 3044 | native | 17882 | mono=399884889 tid=17882 egl_ctx=0x7413b94600 native mkst_ensure_init(lc_verify) exit initialized=0 window_active=0 owner_key=0 generation=0 ready=0 | L411 |
| 17:23:56.013 | 3045 | mpv | 17295 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L412 |
| 17:23:56.013 | 3045 | mpv | 17295 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: bridge not initialized (verify-only ensure_init; Java side owns init) | L413 |
| 17:23:56.017 | 3049 | dart | 17295 | dart property complete vid=auto | L415 |
| 17:23:56.017 | 3049 | dart | 17295 | dart apply complete wid=2099394 | L416 |
| 17:23:56.017 | 3049 | dart | 17295 | dart bind complete wid=2099394 surfaceGeneration=4 | L417 |
| 17:23:56.018 | 3050 | dart | 17295 | dart bind lock released wid=2099394 surfaceGeneration=4 | L418 |
| 17:23:56.409 | 3441 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L433 |
| 17:23:56.481 | 3513 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L444 |
| 17:23:56.504 | 3536 | dart | 17295 | dart size property complete android-surface-size=2672x1336 | L446 |
| 17:23:56.529 | 3561 | java-log | 17295 | PlatformVideoView: surfaceChanged: handle=498743551568, format=43, width=2672, height=1336, wid=2099394 | L453 |
| 17:23:56.785 | 3817 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L464 |
| 17:23:56.850 | 3882 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L465 |
| 17:23:56.923 | 3955 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L466 |
| 17:23:57.023 | 4055 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L467 |
| 17:23:57.083 | 4115 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L472 |
| 17:23:57.148 | 4180 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L473 |
| 17:23:57.307 | 4339 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L474 |
| 17:23:57.419 | 4451 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L475 |
| 17:23:57.493 | 4525 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L476 |
| 17:23:57.545 | 4577 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L478 |
| 17:23:57.617 | 4649 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L479 |
| 17:23:57.806 | 4838 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L487 |
| 17:23:57.900 | 4932 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L488 |
| 17:23:58.026 | 5058 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L489 |
| 17:23:58.101 | 5133 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L490 |
| 17:23:58.291 | 5323 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L491 |
| 17:23:58.407 | 5439 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L492 |
| 17:23:58.527 | 5559 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L493 |
| 17:23:58.689 | 5721 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L494 |
| 17:23:58.855 | 5887 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L495 |
| 17:23:59.018 | 6050 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L496 |
| 17:23:59.132 | 6164 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L497 |
| 17:23:59.217 | 6249 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L498 |
| 17:23:59.302 | 6334 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L499 |
| 17:23:59.358 | 6390 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L500 |
| 17:23:59.461 | 6493 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L501 |
| 17:23:59.514 | 6546 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L502 |
| 17:23:59.594 | 6626 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L503 |
| 17:23:59.834 | 6866 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L504 |
| 17:23:59.918 | 6950 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L506 |
| 17:24:00.089 | 7121 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L524 |
| 17:24:00.177 | 7209 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L536 |
| 17:24:00.400 | 7432 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L539 |
| 17:24:00.541 | 7573 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L540 |
| 17:24:00.741 | 7773 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L546 |
| 17:24:00.814 | 7846 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L548 |
| 17:24:00.905 | 7937 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L549 |
| 17:24:01.002 | 8034 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L550 |
| 17:24:01.087 | 8119 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L551 |
| 17:24:01.193 | 8225 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L552 |
| 17:24:01.273 | 8305 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L553 |
| 17:24:01.336 | 8368 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L554 |
| 17:24:01.445 | 8477 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L555 |
| 17:24:01.559 | 8591 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L556 |
| 17:24:01.793 | 8825 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L566 |
| 17:24:01.883 | 8915 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L568 |
| 17:24:01.945 | 8977 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L569 |
| 17:24:02.053 | 9085 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L570 |
| 17:24:02.190 | 9222 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L576 |
| 17:24:02.294 | 9326 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L577 |
| 17:24:02.426 | 9458 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L578 |
| 17:24:02.507 | 9539 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L579 |
| 17:24:02.672 | 9704 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L580 |
| 17:24:02.815 | 9847 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L582 |
| 17:24:02.872 | 9904 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L584 |
| 17:24:02.995 | 10027 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L585 |
| 17:24:03.523 | 10555 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L586 |
| 17:24:03.855 | 10887 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L588 |
| 17:24:04.046 | 11078 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L589 |
| 17:24:04.374 | 11406 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L590 |
| 17:24:04.470 | 11502 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L591 |
| 17:24:04.566 | 11598 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L592 |
| 17:24:04.636 | 11668 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L593 |
| 17:24:04.792 | 11824 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L594 |
| 17:24:04.901 | 11933 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L595 |
| 17:24:05.097 | 12129 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L596 |
| 17:24:05.302 | 12334 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L600 |
| 17:24:05.603 | 12635 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L605 |
| 17:24:05.853 | 12885 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L613 |
| 17:24:06.376 | 13408 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L615 |
| 17:24:06.647 | 13679 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L617 |
| 17:24:06.901 | 13933 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L618 |
| 17:24:07.211 | 14243 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L619 |
| 17:24:07.408 | 14440 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L620 |
| 17:24:07.534 | 14566 | host-cmd |  | pid_after pid_before=17295 pid_after=17295 |  |
| 17:24:07.833 | 14865 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L621 |
| 17:24:08.038 | 15070 | host-cmd |  | full_dump lines=     621 |  |
| 17:24:08.152 | 15184 | host-cmd |  | round_end |  |
