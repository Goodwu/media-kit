# Timeline R2-1

App PID filter: 17295 (ActivityManager am_pause/resume lines kept from system_server).

Source: `R2-1/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 17:21:55.739 | 0 | L0 |
| home_sent(host probe after cmd returned) | 17:21:56.756 | 1017 | L0 |
| am_pause_lab | 17:21:56.275 | 536 | L1169 |
| java_surfaceDestroyed_enter | 17:21:56.550 | 811 | L1249 |
| java_send_SurfaceDestroyed | 17:21:56.550 | 811 | L1251 |
| dart_event_SurfaceDestroyed | 17:21:56.551 | 812 | L1252 |
| dart_detach_lock_acquired | 17:21:56.551 | 812 | L1254 |
| dart_detach_vo_null_begin | 17:21:56.551 | 812 | L1257 |
| native_shutdown_enter | 17:21:56.620 | 881 | L1306 |
| native_shutdown_exit | 17:21:56.620 | 881 | L1308 |
| dart_detach_vo_null_ack | 17:21:56.684 | 945 | L1321 |
| dart_detach_wid0_ack | 17:21:58.096 | 2357 | L1488 |
| dart_detach_apply_complete | 17:21:59.016 | 3277 | L1563 |
| dart_detach_lock_released | 17:21:59.019 | 3280 | L1569 |
| return_sent | 17:21:57.716 | 1977 | L0 |
| am_resume_lab | 17:21:57.784 | 2045 | L1417 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | — | — | — |
| java_surfaceCreated_enter | 17:21:57.896 | 2157 | L1434 |
| java_send_SurfaceAvailable | 17:21:57.922 | 2183 | L1453 |
| dart_event_SurfaceAvailable | 17:21:57.922 | 2183 | L1454 |
| dart_bind_requested | 17:21:57.923 | 2184 | L1455 |
| dart_bind_lock_acquired | 17:21:59.019 | 3280 | L1570 |
| dart_bind_vo_gpu_next_begin | 17:21:59.025 | 3286 | L1579 |
| native_ensure_init_exit | 17:21:59.081 | 3342 | L1611 |
| native_create_exit | — | — | — |
| mpv_egl_window_surface | 17:21:59.034 | 3295 | L1587 |
| mpv_bridge_not_initialized | 17:21:59.084 | 3345 | L1613 |
| dart_bind_complete | 17:21:59.125 | 3386 | L1631 |
| first_videoparams_after_return | 17:21:59.700 | 3961 | L1680 |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 1276 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 64 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 2396 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 2461 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 70 |
| dart_vo_null_begin -> shutdown_enter (ms) | 69 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 1123 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 0 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 1097 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | 3 |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | 1804 |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 811 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | 180 |

## Counts (whole dump)

| counter | n |
|---|---|
| ensureInitialized_total_in_log | 2 |
| ensureInitialized_after_home_sent | 0 |
| factory_create_total_in_log | 2 |
| factory_create_after_home_sent | 0 |
| mkst_shutdown_exit_total | 1 |
| mkst_create_exit_total | 1 |
| surfaceCreated_enter_total | 3 |
| surfaceDestroyed_enter_total | 2 |

## Events (time-sorted; HOME window and after, plus pre-HOME bridge lifecycle)

| device time | Δhome (ms) | layer | tid | event | line |
|---|---|---|---|---|---|
| 17:21:31.730 | -24009 | host-cmd |  | round_begin launch=fresh home=fast pkg=com.example.media_kit_hdr_lab |  |
| 17:21:33.829 | -21910 | host-cmd |  | force_stop pid_after= |  |
| 17:21:33.973 | -21766 | host-cmd |  | logcat_cleared |  |
| 17:21:34.663 | -21076 | host-cmd |  | am_start_fresh pid=17295 |  |
| 17:21:39.193 | -16546 | java | 17295 | mono=399748069 tid=17295 thr=main java factory.create enter handle=498743551568 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L233 |
| 17:21:39.194 | -16545 | java | 17295 | mono=399748070 tid=17295 thr=main java factory.create view constructed handle=498743551568 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L234 |
| 17:21:39.194 | -16545 | java | 17295 | mono=399748070 tid=17295 thr=main java setLgExperimentOwner enter handle=498743551568 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L235 |
| 17:21:39.194 | -16545 | java | 17295 | mono=399748071 tid=17295 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=-1190632043793703878 libraryLoaded=false | L236 |
| 17:21:39.196 | -16543 | native | 17295 | mono=399748072 tid=17295 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=17256112029915847738 req_generation=1 | L237 |
| 17:21:39.200 | -16539 | native | 17295 | mono=399748076 tid=17295 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=17256112029915847738 req_generation=1 resources_ready=1 | L239 |
| 17:21:39.200 | -16539 | native | 17295 | mono=399748076 tid=17295 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=17256112029915847738 generation=1 rc=0 | L241 |
| 17:21:39.200 | -16539 | java | 17295 | mono=399748077 tid=17295 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=-1190632043793703878 | L242 |
| 17:21:39.200 | -16539 | java | 17295 | mono=399748077 tid=17295 thr=main java setLgExperimentOwner exit handle=498743551568 viewId=0 ownerGeneration=1 ensureInitialized=ok | L243 |
| 17:21:39.200 | -16539 | java | 17295 | mono=399748077 tid=17295 thr=main java factory.create setLgExperimentOwner returned handle=498743551568 viewId=0 | L244 |
| 17:21:39.201 | -16538 | java | 17295 | mono=399748077 tid=17295 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743551568 viewId=0 ownerGeneration=1 creationSerial=1 | L245 |
| 17:21:39.202 | -16537 | java | 17295 | mono=399748078 tid=17295 thr=main java factory.create exit handle=498743551568 viewId=0 | L247 |
| 17:21:39.242 | -16497 | java-log | 17295 | PlatformVideoView: surfaceCreated: handle=498743551568, width=668, height=360, viewIdentity=235825235 | L251 |
| 17:21:39.243 | -16496 | java | 17295 | mono=399748119 tid=17295 thr=main java surfaceCreated enter handle=498743551568 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L252 |
| 17:21:39.258 | -16481 | host-cmd |  | tap_open x=1440 y=720 |  |
| 17:21:39.275 | -16464 | java-log | 17295 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L254 |
| 17:21:39.275 | -16464 | java | 17295 | mono=399748152 tid=17295 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743551568 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L255 |
| 17:21:39.275 | -16464 | java | 17295 | mono=399748152 tid=17295 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743551568 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L256 |
| 17:21:39.276 | -16463 | java | 17295 | mono=399748153 tid=17295 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743551568 viewId=0 surfaceGeneration=1 wid=2099350 | L261 |
| 17:21:39.276 | -16463 | java | 17295 | mono=399748153 tid=17295 thr=main java surfaceCreated exit handle=498743551568 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L262 |
| 17:21:40.182 | -15557 | java | 17295 | mono=399749058 tid=17295 thr=main java factory.create enter handle=498743551568 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L643 |
| 17:21:40.182 | -15557 | java | 17295 | mono=399749059 tid=17295 thr=main java factory.create view constructed handle=498743551568 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L645 |
| 17:21:40.183 | -15556 | java | 17295 | mono=399749059 tid=17295 thr=main java setLgExperimentOwner enter handle=498743551568 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L646 |
| 17:21:40.183 | -15556 | java | 17295 | mono=399749059 tid=17295 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-1190632043793703878 libraryLoaded=true | L647 |
| 17:21:40.183 | -15556 | native | 17295 | mono=399749059 tid=17295 egl_ctx=0x0 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=17256112029915847738 generation=1 req_owner_key=17256112029915847738 req_generation=2 | L648 |
| 17:21:40.183 | -15556 | native | 17295 | mono=399749059 tid=17295 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=17256112029915847738 generation=1 req_owner_key=17256112029915847738 req_generation=2 resources_ready=1 | L649 |
| 17:21:40.183 | -15556 | native | 17295 | mono=399749059 tid=17295 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=17256112029915847738 generation=2 rc=0 | L651 |
| 17:21:40.183 | -15556 | java | 17295 | mono=399749059 tid=17295 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-1190632043793703878 | L652 |
| 17:21:40.183 | -15556 | java | 17295 | mono=399749059 tid=17295 thr=main java setLgExperimentOwner exit handle=498743551568 viewId=1 ownerGeneration=2 ensureInitialized=ok | L653 |
| 17:21:40.183 | -15556 | java | 17295 | mono=399749059 tid=17295 thr=main java factory.create setLgExperimentOwner returned handle=498743551568 viewId=1 | L654 |
| 17:21:40.183 | -15556 | java | 17295 | mono=399749060 tid=17295 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743551568 viewId=1 ownerGeneration=2 creationSerial=2 | L655 |
| 17:21:40.185 | -15554 | java | 17295 | mono=399749061 tid=17295 thr=main java factory.create exit handle=498743551568 viewId=1 | L657 |
| 17:21:40.237 | -15502 | java-log | 17295 | PlatformVideoView: surfaceCreated: handle=498743551568, width=668, height=360, viewIdentity=207085198 | L658 |
| 17:21:40.237 | -15502 | java | 17295 | mono=399749113 tid=17295 thr=main java surfaceCreated enter handle=498743551568 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L659 |
| 17:21:40.242 | -15497 | java-log | 17295 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743551568, transfer=pq, applied=true | L672 |
| 17:21:40.242 | -15497 | java-log | 17295 | PlatformVideoView: surfaceCreated: created new wid=2242 | L674 |
| 17:21:40.242 | -15497 | java | 17295 | mono=399749119 tid=17295 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743551568 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=2242 | L675 |
| 17:21:40.242 | -15497 | java | 17295 | mono=399749119 tid=17295 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743551568 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2242 | L676 |
| 17:21:40.244 | -15495 | java | 17295 | mono=399749121 tid=17295 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743551568 viewId=1 surfaceGeneration=1 wid=2242 | L681 |
| 17:21:40.244 | -15495 | java | 17295 | mono=399749121 tid=17295 thr=main java surfaceCreated exit handle=498743551568 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2242 | L682 |
| 17:21:40.415 | -15324 | native | 17369 | mono=399749291 tid=17369 egl_ctx=0x741d3ffc00 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=17256112029915847738 generation=2  | L754 |
| 17:21:40.415 | -15324 | native | 17369 | mono=399749292 tid=17369 egl_ctx=0x741d3ffc00 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=17256112029915847738 generation=2 ready=1 | L755 |
| 17:21:40.415 | -15324 | native | 17369 | mono=399749292 tid=17369 egl_ctx=0x741d3ffc00 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=17256112029915847738 generation=2  | L756 |
| 17:21:40.417 | -15322 | native | 17369 | mono=399749294 tid=17369 egl_ctx=0x741d3ffc00 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=17256112029915847738 generation=2 result=ok window=0x741fb26c10 | L759 |
| 17:21:55.474 | -265 | host-cmd |  | interim_dump lines=    1060 |  |
| 17:21:55.658 | -81 | host-cmd |  | pid_before pid=17295 |  |
| 17:21:55.739 | 0 | host-cmd |  | home_send_begin |  |
| 17:21:56.275 | 536 | activity | 2062 | am_pause_activity: [0,40726506,com.example.media_kit_hdr_lab/.MainActivity] | L1169 |
| 17:21:56.277 | 538 | activity | 17295 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1170 |
| 17:21:56.391 | 652 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1190 |
| 17:21:56.512 | 773 | activity | 17295 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1230 |
| 17:21:56.550 | 811 | java-log | 17295 | PlatformVideoView: surfaceDestroyed: handle=498743551568, wid=2242 | L1248 |
| 17:21:56.550 | 811 | java | 17295 | mono=399765426 tid=17295 thr=main java surfaceDestroyed enter handle=498743551568 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2242 disposed=false | L1249 |
| 17:21:56.550 | 811 | java | 17295 | mono=399765427 tid=17295 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743551568 viewId=1 surfaceGeneration=1 wid=2242 | L1250 |
| 17:21:56.550 | 811 | java | 17295 | mono=399765427 tid=17295 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743551568 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2242 | L1251 |
| 17:21:56.551 | 812 | dart | 17295 | dart event SurfaceDestroyed handle=498743551568 wid=2242 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=2242 boundSurfaceGeneration=1 | L1252 |
| 17:21:56.551 | 812 | dart | 17295 | dart detach requested wid=2242 surfaceGeneration=1 generation=2 viewId=1 | L1253 |
| 17:21:56.551 | 812 | dart | 17295 | dart detach lock acquired wid=2242 surfaceGeneration=1 generation=2 viewId=1 boundWid=2242 boundSurfaceGeneration=1 | L1254 |
| 17:21:56.551 | 812 | dart | 17295 | dart detach decision wid=2242 isCurrentOutput=true isInFlightOutput=false | L1255 |
| 17:21:56.551 | 812 | dart | 17295 | dart apply begin wid=0 vo=null vid=no | L1256 |
| 17:21:56.551 | 812 | dart | 17295 | dart property begin vo=null | L1257 |
| 17:21:56.551 | 812 | java | 17295 | mono=399765428 tid=17295 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743551568 viewId=1 surfaceGeneration=1 wid=2242 | L1258 |
| 17:21:56.551 | 812 | java | 17295 | mono=399765428 tid=17295 thr=main java surfaceDestroyed exit handle=498743551568 viewId=1 sentEvent=true wid=0 | L1259 |
| 17:21:56.553 | 814 | codec | 17374 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 10/16 output). | L1260 |
| 17:21:56.554 | 815 | codec | 17374 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1262 |
| 17:21:56.557 | 818 | codec | 17374 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1264 |
| 17:21:56.573 | 834 | codec | 17374 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1275 |
| 17:21:56.593 | 854 | codec | 17374 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1285 |
| 17:21:56.593 | 854 | codec | 17374 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1287 |
| 17:21:56.603 | 864 | codec | 17374 | ACodec  : Now uninitialized | L1301 |
| 17:21:56.620 | 881 | native | 17369 | mono=399765496 tid=17369 egl_ctx=0x741d3ffc00 native mkst_shutdown enter initialized=1 window_active=1 owner_key=17256112029915847738 generation=2  | L1306 |
| 17:21:56.620 | 881 | native | 17369 | mono=399765496 tid=17369 egl_ctx=0x741d3ffc00 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=474 latched=474 | L1308 |
| 17:21:56.684 | 945 | dart | 17295 | dart property complete vo=null | L1321 |
| 17:21:56.685 | 946 | dart | 17295 | dart property begin android-surface-size=2672x1336 | L1322 |
| 17:21:56.756 | 1017 | host-cmd |  | home_sent |  |
| 17:21:56.850 | 1111 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity (immediately) |  |
| 17:21:57.136 | 1397 | dart | 17295 | dart property complete android-surface-size=2672x1336 | L1356 |
| 17:21:57.137 | 1398 | dart | 17295 | dart property begin wid=0 | L1357 |
| 17:21:57.147 | 1408 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1358 |
| 17:21:57.564 | 1825 | activity | 2610 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1382 |
| 17:21:57.716 | 1977 | host-cmd |  | return_sent |  |
| 17:21:57.784 | 2045 | activity | 10278 | am_resume_activity: [0,40726506,1021,com.example.media_kit_hdr_lab/.MainActivity] | L1417 |
| 17:21:57.819 | 2080 | activity | 17295 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1423 |
| 17:21:57.896 | 2157 | java-log | 17295 | PlatformVideoView: surfaceCreated: handle=498743551568, width=668, height=360, viewIdentity=207085198 | L1433 |
| 17:21:57.896 | 2157 | java | 17295 | mono=399766772 tid=17295 thr=main java surfaceCreated enter handle=498743551568 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1434 |
| 17:21:57.922 | 2183 | java-log | 17295 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743551568, transfer=pq, applied=true | L1449 |
| 17:21:57.922 | 2183 | java-log | 17295 | PlatformVideoView: surfaceCreated: created new wid=2258 | L1451 |
| 17:21:57.922 | 2183 | java | 17295 | mono=399766798 tid=17295 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743551568 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2258 | L1452 |
| 17:21:57.922 | 2183 | java | 17295 | mono=399766799 tid=17295 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743551568 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2258 | L1453 |
| 17:21:57.922 | 2183 | dart | 17295 | dart event SurfaceAvailable handle=498743551568 wid=2258 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1454 |
| 17:21:57.923 | 2184 | dart | 17295 | dart bind requested wid=2258 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1455 |
| 17:21:57.923 | 2184 | java | 17295 | mono=399766799 tid=17295 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743551568 viewId=1 surfaceGeneration=2 wid=2258 | L1456 |
| 17:21:57.923 | 2184 | java | 17295 | mono=399766799 tid=17295 thr=main java surfaceCreated exit handle=498743551568 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2258 | L1457 |
| 17:21:57.923 | 2184 | java-log | 17295 | PlatformVideoView: surfaceChanged: handle=498743551568, format=43, width=2672, height=1336, wid=2258 | L1458 |
| 17:21:57.994 | 2255 | java-log | 17295 | PlatformVideoView: surfaceChanged: handle=498743551568, format=43, width=2672, height=1440, wid=2258 | L1469 |
| 17:21:58.096 | 2357 | dart | 17295 | dart property complete wid=0 | L1488 |
| 17:21:58.096 | 2357 | dart | 17295 | dart property begin vo=null | L1489 |
| 17:21:58.469 | 2730 | dart | 17295 | dart property complete vo=null | L1523 |
| 17:21:58.469 | 2730 | dart | 17295 | dart property begin vid=no | L1524 |
| 17:21:59.016 | 3277 | dart | 17295 | dart property complete vid=no | L1562 |
| 17:21:59.016 | 3277 | dart | 17295 | dart apply complete wid=0 | L1563 |
| 17:21:59.016 | 3277 | dart | 17295 | dart detach producer stopped wid=2242 | L1564 |
| 17:21:59.017 | 3278 | java-log | 17295 | PlatformVideoView: releaseSurface generation=1 wid=2242 result=released | L1566 |
| 17:21:59.019 | 3280 | dart | 17295 | dart detach reference released wid=2242 | L1568 |
| 17:21:59.019 | 3280 | dart | 17295 | dart detach lock released wid=2242 surfaceGeneration=1 | L1569 |
| 17:21:59.019 | 3280 | dart | 17295 | dart bind lock acquired wid=2258 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1570 |
| 17:21:59.019 | 3280 | dart | 17295 | dart bind branch=rebind wid=2258 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1571 |
| 17:21:59.019 | 3280 | dart | 17295 | dart apply begin wid=2258 vo=gpu-next vid=auto | L1572 |
| 17:21:59.019 | 3280 | dart | 17295 | dart property begin vo=null | L1573 |
| 17:21:59.020 | 3281 | dart | 17295 | dart property complete vo=null | L1574 |
| 17:21:59.020 | 3281 | dart | 17295 | dart property begin android-surface-size=2672x1336 | L1575 |
| 17:21:59.021 | 3282 | dart | 17295 | dart property complete android-surface-size=2672x1336 | L1576 |
| 17:21:59.021 | 3282 | dart | 17295 | dart property begin wid=2258 | L1577 |
| 17:21:59.025 | 3286 | dart | 17295 | dart property complete wid=2258 | L1578 |
| 17:21:59.025 | 3286 | dart | 17295 | dart property begin vo=gpu-next | L1579 |
| 17:21:59.034 | 3295 | mpv | 17295 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1587 |
| 17:21:59.057 | 3318 | dart | 17295 | dart property complete vo=gpu-next | L1603 |
| 17:21:59.057 | 3318 | dart | 17295 | dart property begin vid=auto | L1604 |
| 17:21:59.081 | 3342 | native | 17482 | mono=399767958 tid=17482 egl_ctx=0x74181fd980 native mkst_ensure_init(lc_verify) enter initialized=0 window_active=0 owner_key=0 generation=0  | L1610 |
| 17:21:59.081 | 3342 | native | 17482 | mono=399767958 tid=17482 egl_ctx=0x74181fd980 native mkst_ensure_init(lc_verify) exit initialized=0 window_active=0 owner_key=0 generation=0 ready=0 | L1611 |
| 17:21:59.083 | 3344 | mpv | 17295 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1612 |
| 17:21:59.084 | 3345 | mpv | 17295 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: bridge not initialized (verify-only ensure_init; Java side owns init) | L1613 |
| 17:21:59.125 | 3386 | dart | 17295 | dart property complete vid=auto | L1629 |
| 17:21:59.125 | 3386 | dart | 17295 | dart apply complete wid=2258 | L1630 |
| 17:21:59.125 | 3386 | dart | 17295 | dart bind complete wid=2258 surfaceGeneration=2 | L1631 |
| 17:21:59.125 | 3386 | dart | 17295 | dart bind lock released wid=2258 surfaceGeneration=2 | L1632 |
| 17:21:59.622 | 3883 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1646 |
| 17:21:59.700 | 3961 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1680 |
| 17:21:59.709 | 3970 | dart | 17295 | dart size property complete android-surface-size=2672x1336 | L1682 |
| 17:21:59.754 | 4015 | java-log | 17295 | PlatformVideoView: surfaceChanged: handle=498743551568, format=43, width=2672, height=1336, wid=2258 | L1689 |
| 17:21:59.770 | 4031 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1694 |
| 17:21:59.979 | 4240 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1699 |
| 17:22:00.064 | 4325 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1714 |
| 17:22:00.155 | 4416 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1719 |
| 17:22:00.357 | 4618 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1726 |
| 17:22:00.421 | 4682 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1728 |
| 17:22:00.493 | 4754 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1729 |
| 17:22:00.570 | 4831 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1732 |
| 17:22:00.686 | 4947 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1735 |
| 17:22:00.771 | 5032 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1737 |
| 17:22:00.878 | 5139 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1743 |
| 17:22:01.011 | 5272 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1755 |
| 17:22:01.185 | 5446 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1757 |
| 17:22:01.315 | 5576 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1761 |
| 17:22:01.519 | 5780 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1764 |
| 17:22:01.627 | 5888 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1779 |
| 17:22:01.792 | 6053 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1792 |
| 17:22:01.857 | 6118 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1793 |
| 17:22:01.944 | 6205 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1794 |
| 17:22:02.200 | 6461 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1806 |
| 17:22:02.276 | 6537 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1807 |
| 17:22:02.479 | 6740 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1808 |
| 17:22:02.570 | 6831 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1812 |
| 17:22:02.664 | 6925 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1813 |
| 17:22:02.754 | 7015 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1814 |
| 17:22:02.808 | 7069 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1815 |
| 17:22:02.931 | 7192 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1817 |
| 17:22:03.034 | 7295 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1818 |
| 17:22:03.120 | 7381 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1819 |
| 17:22:03.213 | 7474 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1820 |
| 17:22:03.381 | 7642 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1823 |
| 17:22:03.466 | 7727 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1826 |
| 17:22:03.644 | 7905 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1832 |
| 17:22:03.746 | 8007 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1835 |
| 17:22:03.991 | 8252 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1870 |
| 17:22:04.171 | 8432 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1898 |
| 17:22:04.223 | 8484 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1899 |
| 17:22:04.300 | 8561 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1902 |
| 17:22:04.424 | 8685 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1903 |
| 17:22:04.619 | 8880 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1907 |
| 17:22:04.709 | 8970 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1908 |
| 17:22:04.761 | 9022 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1910 |
| 17:22:04.879 | 9140 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1911 |
| 17:22:04.996 | 9257 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1913 |
| 17:22:05.066 | 9327 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1916 |
| 17:22:05.136 | 9397 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1917 |
| 17:22:05.203 | 9464 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1918 |
| 17:22:05.303 | 9564 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1919 |
| 17:22:05.434 | 9695 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1920 |
| 17:22:05.539 | 9800 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1922 |
| 17:22:05.641 | 9902 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1926 |
| 17:22:05.781 | 10042 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1928 |
| 17:22:05.873 | 10134 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1930 |
| 17:22:06.002 | 10263 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1932 |
| 17:22:06.092 | 10353 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1934 |
| 17:22:06.147 | 10408 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1938 |
| 17:22:06.201 | 10462 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1941 |
| 17:22:06.420 | 10681 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1949 |
| 17:22:06.487 | 10748 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1950 |
| 17:22:06.615 | 10876 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1952 |
| 17:22:06.774 | 11035 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1953 |
| 17:22:07.223 | 11484 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1956 |
| 17:22:07.618 | 11879 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1958 |
| 17:22:07.747 | 12008 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1959 |
| 17:22:08.031 | 12292 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1963 |
| 17:22:08.112 | 12373 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1964 |
| 17:22:08.199 | 12460 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1965 |
| 17:22:08.335 | 12596 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1966 |
| 17:22:08.435 | 12696 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1967 |
| 17:22:08.550 | 12811 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1968 |
| 17:22:08.734 | 12995 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1969 |
| 17:22:08.822 | 13083 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1970 |
| 17:22:08.995 | 13256 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1971 |
| 17:22:09.405 | 13666 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1972 |
| 17:22:09.538 | 13799 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1973 |
| 17:22:09.631 | 13892 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1975 |
| 17:22:10.018 | 14279 | host-cmd |  | pid_after pid_before=17295 pid_after=17295 |  |
| 17:22:10.160 | 14421 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1983 |
| 17:22:10.544 | 14805 | dart-videoparams | 17295 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1989 |
| 17:22:10.857 | 15118 | host-cmd |  | full_dump lines=    1993 |  |
| 17:22:10.982 | 15243 | host-cmd |  | round_end |  |
