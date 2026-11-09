# Timeline R4-fast-3

App PID filter: 26737 (ActivityManager am_pause/resume lines kept from system_server).

Source: `R4-fast-3/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 20:19:00.792 | 0 | L0 |
| home_sent(host probe after cmd returned) | 20:19:02.321 | 1529 | L0 |
| am_pause_lab | 20:19:01.323 | 531 | L1237 |
| java_surfaceDestroyed_enter | 20:19:01.529 | 737 | L1301 |
| java_send_SurfaceDestroyed | 20:19:01.529 | 737 | L1303 |
| dart_event_SurfaceDestroyed | 20:19:01.530 | 738 | L1304 |
| dart_detach_lock_acquired | 20:19:01.530 | 738 | L1306 |
| dart_detach_vo_null_begin | 20:19:01.530 | 738 | L1309 |
| native_shutdown_enter | 20:19:01.754 | 962 | L1440 |
| native_shutdown_exit | 20:19:01.755 | 963 | L1443 |
| dart_detach_vo_null_ack | 20:19:01.798 | 1006 | L1447 |
| dart_detach_wid0_ack | 20:19:02.579 | 1787 | L1640 |
| dart_detach_apply_complete | 20:19:03.328 | 2536 | L1681 |
| dart_detach_lock_released | 20:19:03.330 | 2538 | L1687 |
| return_sent | 20:19:02.951 | 2159 | L0 |
| am_resume_lab | 20:19:02.255 | 1463 | L1540 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | — | — | — |
| java_surfaceCreated_enter | 20:19:02.370 | 1578 | L1592 |
| java_send_SurfaceAvailable | 20:19:02.427 | 1635 | L1616 |
| dart_event_SurfaceAvailable | 20:19:02.427 | 1635 | L1617 |
| dart_bind_requested | 20:19:02.427 | 1635 | L1618 |
| dart_bind_lock_acquired | 20:19:03.330 | 2538 | L1688 |
| dart_bind_vo_gpu_next_begin | 20:19:03.335 | 2543 | L1697 |
| native_ensure_init_exit | 20:19:03.372 | 2580 | L1728 |
| native_create_exit | — | — | — |
| mpv_egl_window_surface | 20:19:03.342 | 2550 | L1710 |
| mpv_bridge_not_initialized | 20:19:03.374 | 2582 | L1730 |
| dart_bind_complete | 20:19:03.380 | 2588 | L1733 |
| first_videoparams_after_return | 20:19:03.831 | 3039 | L1760 |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 615 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 43 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 1573 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 1617 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 226 |
| dart_vo_null_begin -> shutdown_enter (ms) | 224 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 960 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 0 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 903 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | 2 |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | 1461 |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 737 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -581 |

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
| 20:18:36.488 | -24304 | host-cmd |  | round_begin launch=fresh method=F sleep=0 pkg=com.example.media_kit_hdr_lab |  |
| 20:18:38.666 | -22126 | host-cmd |  | force_stop pid_after= |  |
| 20:18:38.847 | -21945 | host-cmd |  | logcat_cleared |  |
| 20:18:39.584 | -21208 | host-cmd |  | am_start_fresh pid=26737 |  |
| 20:18:44.214 | -16578 | java | 26737 | mono=406344590 tid=26737 thr=main java factory.create enter handle=498743358032 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L386 |
| 20:18:44.215 | -16577 | java | 26737 | mono=406344591 tid=26737 thr=main java factory.create view constructed handle=498743358032 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L387 |
| 20:18:44.215 | -16577 | java | 26737 | mono=406344591 tid=26737 thr=main java setLgExperimentOwner enter handle=498743358032 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L388 |
| 20:18:44.216 | -16576 | java | 26737 | mono=406344592 tid=26737 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=-1793904024391536861 libraryLoaded=false | L389 |
| 20:18:44.217 | -16575 | native | 26737 | mono=406344593 tid=26737 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=16652840049318014755 req_generation=1 | L390 |
| 20:18:44.218 | -16574 | native | 26737 | mono=406344594 tid=26737 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=16652840049318014755 req_generation=1 resources_ready=1 | L392 |
| 20:18:44.218 | -16574 | native | 26737 | mono=406344594 tid=26737 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=16652840049318014755 generation=1 rc=0 | L394 |
| 20:18:44.219 | -16573 | java | 26737 | mono=406344594 tid=26737 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=-1793904024391536861 | L395 |
| 20:18:44.219 | -16573 | java | 26737 | mono=406344594 tid=26737 thr=main java setLgExperimentOwner exit handle=498743358032 viewId=0 ownerGeneration=1 ensureInitialized=ok | L396 |
| 20:18:44.219 | -16573 | java | 26737 | mono=406344594 tid=26737 thr=main java factory.create setLgExperimentOwner returned handle=498743358032 viewId=0 | L397 |
| 20:18:44.219 | -16573 | java | 26737 | mono=406344595 tid=26737 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743358032 viewId=0 ownerGeneration=1 creationSerial=1 | L398 |
| 20:18:44.220 | -16572 | java | 26737 | mono=406344596 tid=26737 thr=main java factory.create exit handle=498743358032 viewId=0 | L400 |
| 20:18:44.247 | -16545 | host-cmd |  | tap_open x=1440 y=720 |  |
| 20:18:44.263 | -16529 | java-log | 26737 | PlatformVideoView: surfaceCreated: handle=498743358032, width=668, height=360, viewIdentity=235825235 | L401 |
| 20:18:44.263 | -16529 | java | 26737 | mono=406344639 tid=26737 thr=main java surfaceCreated enter handle=498743358032 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L402 |
| 20:18:44.275 | -16517 | java-log | 26737 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L404 |
| 20:18:44.276 | -16516 | java | 26737 | mono=406344651 tid=26737 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743358032 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L405 |
| 20:18:44.276 | -16516 | java | 26737 | mono=406344652 tid=26737 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743358032 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L406 |
| 20:18:44.278 | -16514 | java | 26737 | mono=406344654 tid=26737 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743358032 viewId=0 surfaceGeneration=1 wid=2099350 | L411 |
| 20:18:44.278 | -16514 | java | 26737 | mono=406344654 tid=26737 thr=main java surfaceCreated exit handle=498743358032 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L412 |
| 20:18:45.283 | -15509 | java | 26737 | mono=406345659 tid=26737 thr=main java factory.create enter handle=498743358032 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L795 |
| 20:18:45.284 | -15508 | java | 26737 | mono=406345660 tid=26737 thr=main java factory.create view constructed handle=498743358032 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L797 |
| 20:18:45.284 | -15508 | java | 26737 | mono=406345660 tid=26737 thr=main java setLgExperimentOwner enter handle=498743358032 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L798 |
| 20:18:45.284 | -15508 | java | 26737 | mono=406345660 tid=26737 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-1793904024391536861 libraryLoaded=true | L799 |
| 20:18:45.284 | -15508 | native | 26737 | mono=406345660 tid=26737 egl_ctx=0x744b9fc480 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=16652840049318014755 generation=1 req_owner_key=16652840049318014755 req_generation=2 | L800 |
| 20:18:45.284 | -15508 | native | 26737 | mono=406345660 tid=26737 egl_ctx=0x744b9fc480 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=16652840049318014755 generation=1 req_owner_key=16652840049318014755 req_generation=2 resources_ready=1 | L801 |
| 20:18:45.284 | -15508 | native | 26737 | mono=406345660 tid=26737 egl_ctx=0x744b9fc480 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=16652840049318014755 generation=2 rc=0 | L803 |
| 20:18:45.284 | -15508 | java | 26737 | mono=406345660 tid=26737 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-1793904024391536861 | L804 |
| 20:18:45.284 | -15508 | java | 26737 | mono=406345660 tid=26737 thr=main java setLgExperimentOwner exit handle=498743358032 viewId=1 ownerGeneration=2 ensureInitialized=ok | L805 |
| 20:18:45.284 | -15508 | java | 26737 | mono=406345660 tid=26737 thr=main java factory.create setLgExperimentOwner returned handle=498743358032 viewId=1 | L806 |
| 20:18:45.285 | -15507 | java | 26737 | mono=406345660 tid=26737 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743358032 viewId=1 ownerGeneration=2 creationSerial=2 | L807 |
| 20:18:45.285 | -15507 | java | 26737 | mono=406345661 tid=26737 thr=main java factory.create exit handle=498743358032 viewId=1 | L809 |
| 20:18:45.338 | -15454 | java-log | 26737 | PlatformVideoView: surfaceCreated: handle=498743358032, width=668, height=360, viewIdentity=207085198 | L810 |
| 20:18:45.338 | -15454 | java | 26737 | mono=406345714 tid=26737 thr=main java surfaceCreated enter handle=498743358032 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L811 |
| 20:18:45.342 | -15450 | java-log | 26737 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743358032, transfer=pq, applied=true | L824 |
| 20:18:45.343 | -15449 | java-log | 26737 | PlatformVideoView: surfaceCreated: created new wid=1050746 | L826 |
| 20:18:45.343 | -15449 | java | 26737 | mono=406345719 tid=26737 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743358032 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=1050746 | L827 |
| 20:18:45.343 | -15449 | java | 26737 | mono=406345719 tid=26737 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743358032 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050746 | L828 |
| 20:18:45.344 | -15448 | java | 26737 | mono=406345719 tid=26737 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743358032 viewId=1 surfaceGeneration=1 wid=1050746 | L833 |
| 20:18:45.344 | -15448 | java | 26737 | mono=406345719 tid=26737 thr=main java surfaceCreated exit handle=498743358032 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050746 | L834 |
| 20:18:45.530 | -15262 | native | 26810 | mono=406345906 tid=26810 egl_ctx=0x741236ff80 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=16652840049318014755 generation=2  | L891 |
| 20:18:45.530 | -15262 | native | 26810 | mono=406345906 tid=26810 egl_ctx=0x741236ff80 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=16652840049318014755 generation=2 ready=1 | L892 |
| 20:18:45.530 | -15262 | native | 26810 | mono=406345906 tid=26810 egl_ctx=0x741236ff80 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=16652840049318014755 generation=2  | L893 |
| 20:18:45.532 | -15260 | native | 26810 | mono=406345908 tid=26810 egl_ctx=0x741236ff80 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=16652840049318014755 generation=2 result=ok window=0x74185bde10 | L896 |
| 20:19:00.503 | -289 | host-cmd |  | interim_dump lines=    1213 |  |
| 20:19:00.708 | -84 | host-cmd |  | pid_before pid=26737 |  |
| 20:19:00.792 | 0 | host-cmd |  | home_send_begin cmd=adb shell: am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n com.example.media_kit_hdr_lab/.MainActivity --activity-no-animation |  |
| 20:19:01.323 | 531 | activity | 10278 | am_pause_activity: [0,240883401,com.example.media_kit_hdr_lab/.MainActivity] | L1237 |
| 20:19:01.327 | 535 | activity | 26737 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1238 |
| 20:19:01.431 | 639 | activity | 10278 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1261 |
| 20:19:01.529 | 737 | java-log | 26737 | PlatformVideoView: surfaceDestroyed: handle=498743358032, wid=1050746 | L1300 |
| 20:19:01.529 | 737 | java | 26737 | mono=406361905 tid=26737 thr=main java surfaceDestroyed enter handle=498743358032 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050746 disposed=false | L1301 |
| 20:19:01.529 | 737 | java | 26737 | mono=406361905 tid=26737 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743358032 viewId=1 surfaceGeneration=1 wid=1050746 | L1302 |
| 20:19:01.529 | 737 | java | 26737 | mono=406361905 tid=26737 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743358032 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050746 | L1303 |
| 20:19:01.530 | 738 | dart | 26737 | dart event SurfaceDestroyed handle=498743358032 wid=1050746 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=1050746 boundSurfaceGeneration=1 | L1304 |
| 20:19:01.530 | 738 | dart | 26737 | dart detach requested wid=1050746 surfaceGeneration=1 generation=2 viewId=1 | L1305 |
| 20:19:01.530 | 738 | dart | 26737 | dart detach lock acquired wid=1050746 surfaceGeneration=1 generation=2 viewId=1 boundWid=1050746 boundSurfaceGeneration=1 | L1306 |
| 20:19:01.530 | 738 | dart | 26737 | dart detach decision wid=1050746 isCurrentOutput=true isInFlightOutput=false | L1307 |
| 20:19:01.530 | 738 | dart | 26737 | dart apply begin wid=0 vo=null vid=no | L1308 |
| 20:19:01.530 | 738 | dart | 26737 | dart property begin vo=null | L1309 |
| 20:19:01.530 | 738 | java | 26737 | mono=406361906 tid=26737 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743358032 viewId=1 surfaceGeneration=1 wid=1050746 | L1310 |
| 20:19:01.530 | 738 | java | 26737 | mono=406361906 tid=26737 thr=main java surfaceDestroyed exit handle=498743358032 viewId=1 sentEvent=true wid=0 | L1311 |
| 20:19:01.618 | 826 | activity | 26737 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1362 |
| 20:19:01.682 | 890 | codec | 26815 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 10/16 output). | L1401 |
| 20:19:01.683 | 891 | codec | 26815 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1404 |
| 20:19:01.688 | 896 | codec | 26815 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1409 |
| 20:19:01.694 | 902 | codec | 26815 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1417 |
| 20:19:01.708 | 916 | codec | 26815 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1422 |
| 20:19:01.709 | 917 | codec | 26815 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1423 |
| 20:19:01.733 | 941 | codec | 26815 | ACodec  : Now uninitialized | L1434 |
| 20:19:01.754 | 962 | native | 26810 | mono=406362129 tid=26810 egl_ctx=0x741236ff80 native mkst_shutdown enter initialized=1 window_active=1 owner_key=16652840049318014755 generation=2  | L1440 |
| 20:19:01.755 | 963 | native | 26810 | mono=406362130 tid=26810 egl_ctx=0x741236ff80 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=468 latched=468 | L1443 |
| 20:19:01.798 | 1006 | dart | 26737 | dart property complete vo=null | L1447 |
| 20:19:01.799 | 1007 | dart | 26737 | dart property begin android-surface-size=2672x1336 | L1448 |
| 20:19:01.800 | 1008 | dart | 26737 | dart property complete android-surface-size=2672x1336 | L1449 |
| 20:19:01.800 | 1008 | dart | 26737 | dart property begin wid=0 | L1450 |
| 20:19:02.152 | 1360 | activity | 2612 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1503 |
| 20:19:02.216 | 1424 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1528 |
| 20:19:02.255 | 1463 | activity | 2616 | am_resume_activity: [0,240883401,1036,com.example.media_kit_hdr_lab/.MainActivity] | L1540 |
| 20:19:02.271 | 1479 | activity | 26737 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1543 |
| 20:19:02.321 | 1529 | host-cmd |  | home_sent chained home+return shell returned |  |
| 20:19:02.370 | 1578 | java-log | 26737 | PlatformVideoView: surfaceCreated: handle=498743358032, width=668, height=360, viewIdentity=207085198 | L1591 |
| 20:19:02.370 | 1578 | java | 26737 | mono=406362745 tid=26737 thr=main java surfaceCreated enter handle=498743358032 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1592 |
| 20:19:02.426 | 1634 | java-log | 26737 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743358032, transfer=pq, applied=true | L1612 |
| 20:19:02.427 | 1635 | java-log | 26737 | PlatformVideoView: surfaceCreated: created new wid=2258 | L1614 |
| 20:19:02.427 | 1635 | java | 26737 | mono=406362802 tid=26737 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743358032 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2258 | L1615 |
| 20:19:02.427 | 1635 | java | 26737 | mono=406362803 tid=26737 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743358032 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2258 | L1616 |
| 20:19:02.427 | 1635 | dart | 26737 | dart event SurfaceAvailable handle=498743358032 wid=2258 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1617 |
| 20:19:02.427 | 1635 | dart | 26737 | dart bind requested wid=2258 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1618 |
| 20:19:02.427 | 1635 | java | 26737 | mono=406362803 tid=26737 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743358032 viewId=1 surfaceGeneration=2 wid=2258 | L1619 |
| 20:19:02.428 | 1636 | java | 26737 | mono=406362803 tid=26737 thr=main java surfaceCreated exit handle=498743358032 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2258 | L1620 |
| 20:19:02.428 | 1636 | java-log | 26737 | PlatformVideoView: surfaceChanged: handle=498743358032, format=43, width=2672, height=1336, wid=2258 | L1621 |
| 20:19:02.523 | 1731 | java-log | 26737 | PlatformVideoView: surfaceChanged: handle=498743358032, format=43, width=2672, height=1440, wid=2258 | L1631 |
| 20:19:02.579 | 1787 | dart | 26737 | dart property complete wid=0 | L1640 |
| 20:19:02.579 | 1787 | dart | 26737 | dart property begin vo=null | L1642 |
| 20:19:02.781 | 1989 | host-cmd |  | return_send_begin note-only: return was chained in the same shell as home (no separate adb round trip) |  |
| 20:19:02.783 | 1991 | dart | 26737 | dart property complete vo=null | L1673 |
| 20:19:02.784 | 1992 | dart | 26737 | dart property begin vid=no | L1674 |
| 20:19:02.951 | 2159 | host-cmd |  | return_sent chained shell done |  |
| 20:19:03.327 | 2535 | dart | 26737 | dart property complete vid=no | L1680 |
| 20:19:03.328 | 2536 | dart | 26737 | dart apply complete wid=0 | L1681 |
| 20:19:03.328 | 2536 | dart | 26737 | dart detach producer stopped wid=1050746 | L1682 |
| 20:19:03.328 | 2536 | java-log | 26737 | PlatformVideoView: releaseSurface generation=1 wid=1050746 result=released | L1684 |
| 20:19:03.330 | 2538 | dart | 26737 | dart detach reference released wid=1050746 | L1686 |
| 20:19:03.330 | 2538 | dart | 26737 | dart detach lock released wid=1050746 surfaceGeneration=1 | L1687 |
| 20:19:03.330 | 2538 | dart | 26737 | dart bind lock acquired wid=2258 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1688 |
| 20:19:03.330 | 2538 | dart | 26737 | dart bind branch=rebind wid=2258 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1689 |
| 20:19:03.330 | 2538 | dart | 26737 | dart apply begin wid=2258 vo=gpu-next vid=auto | L1690 |
| 20:19:03.330 | 2538 | dart | 26737 | dart property begin vo=null | L1691 |
| 20:19:03.331 | 2539 | dart | 26737 | dart property complete vo=null | L1692 |
| 20:19:03.331 | 2539 | dart | 26737 | dart property begin android-surface-size=2672x1336 | L1693 |
| 20:19:03.332 | 2540 | dart | 26737 | dart property complete android-surface-size=2672x1336 | L1694 |
| 20:19:03.332 | 2540 | dart | 26737 | dart property begin wid=2258 | L1695 |
| 20:19:03.335 | 2543 | dart | 26737 | dart property complete wid=2258 | L1696 |
| 20:19:03.335 | 2543 | dart | 26737 | dart property begin vo=gpu-next | L1697 |
| 20:19:03.342 | 2550 | mpv | 26737 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1710 |
| 20:19:03.357 | 2565 | dart | 26737 | dart property complete vo=gpu-next | L1719 |
| 20:19:03.357 | 2565 | dart | 26737 | dart property begin vid=auto | L1720 |
| 20:19:03.372 | 2580 | native | 26898 | mono=406363748 tid=26898 egl_ctx=0x7418034f80 native mkst_ensure_init(lc_verify) enter initialized=0 window_active=0 owner_key=0 generation=0  | L1727 |
| 20:19:03.372 | 2580 | native | 26898 | mono=406363748 tid=26898 egl_ctx=0x7418034f80 native mkst_ensure_init(lc_verify) exit initialized=0 window_active=0 owner_key=0 generation=0 ready=0 | L1728 |
| 20:19:03.374 | 2582 | mpv | 26737 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1729 |
| 20:19:03.374 | 2582 | mpv | 26737 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: bridge not initialized (verify-only ensure_init; Java side owns init) | L1730 |
| 20:19:03.380 | 2588 | dart | 26737 | dart property complete vid=auto | L1731 |
| 20:19:03.380 | 2588 | dart | 26737 | dart apply complete wid=2258 | L1732 |
| 20:19:03.380 | 2588 | dart | 26737 | dart bind complete wid=2258 surfaceGeneration=2 | L1733 |
| 20:19:03.380 | 2588 | dart | 26737 | dart bind lock released wid=2258 surfaceGeneration=2 | L1734 |
| 20:19:03.761 | 2969 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1749 |
| 20:19:03.831 | 3039 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1760 |
| 20:19:03.847 | 3055 | dart | 26737 | dart size property complete android-surface-size=2672x1336 | L1762 |
| 20:19:03.884 | 3092 | java-log | 26737 | PlatformVideoView: surfaceChanged: handle=498743358032, format=43, width=2672, height=1336, wid=2258 | L1772 |
| 20:19:03.923 | 3131 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1775 |
| 20:19:04.079 | 3287 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1776 |
| 20:19:04.178 | 3386 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1777 |
| 20:19:04.262 | 3470 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1782 |
| 20:19:04.316 | 3524 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1783 |
| 20:19:04.463 | 3671 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1785 |
| 20:19:04.589 | 3797 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1786 |
| 20:19:04.716 | 3924 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1788 |
| 20:19:04.865 | 4073 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1789 |
| 20:19:04.938 | 4146 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1793 |
| 20:19:05.040 | 4248 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1817 |
| 20:19:05.212 | 4420 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1819 |
| 20:19:05.295 | 4503 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1820 |
| 20:19:05.380 | 4588 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1822 |
| 20:19:05.459 | 4667 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1823 |
| 20:19:05.651 | 4859 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1825 |
| 20:19:05.712 | 4920 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1826 |
| 20:19:05.779 | 4987 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1827 |
| 20:19:05.895 | 5103 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1828 |
| 20:19:05.952 | 5160 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1829 |
| 20:19:06.140 | 5348 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1830 |
| 20:19:06.217 | 5425 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1832 |
| 20:19:06.423 | 5631 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1833 |
| 20:19:06.546 | 5754 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1834 |
| 20:19:06.646 | 5854 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1835 |
| 20:19:06.724 | 5932 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1836 |
| 20:19:06.784 | 5992 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1837 |
| 20:19:06.838 | 6046 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1838 |
| 20:19:06.935 | 6143 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1839 |
| 20:19:07.009 | 6217 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1840 |
| 20:19:07.066 | 6274 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1841 |
| 20:19:07.150 | 6358 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1842 |
| 20:19:07.234 | 6442 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1852 |
| 20:19:07.307 | 6515 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1853 |
| 20:19:07.465 | 6673 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1856 |
| 20:19:07.538 | 6746 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1857 |
| 20:19:07.654 | 6862 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1858 |
| 20:19:07.742 | 6950 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1859 |
| 20:19:07.955 | 7163 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1860 |
| 20:19:08.048 | 7256 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1864 |
| 20:19:08.123 | 7331 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1867 |
| 20:19:08.192 | 7400 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1868 |
| 20:19:08.275 | 7483 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1871 |
| 20:19:08.332 | 7540 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1874 |
| 20:19:08.439 | 7647 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1876 |
| 20:19:08.548 | 7756 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1878 |
| 20:19:08.621 | 7829 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1879 |
| 20:19:08.726 | 7934 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1880 |
| 20:19:08.849 | 8057 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1881 |
| 20:19:08.992 | 8200 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1882 |
| 20:19:09.133 | 8341 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1884 |
| 20:19:09.201 | 8409 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1885 |
| 20:19:09.308 | 8516 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1886 |
| 20:19:09.440 | 8648 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1887 |
| 20:19:09.551 | 8759 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1888 |
| 20:19:09.632 | 8840 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1889 |
| 20:19:09.734 | 8942 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1890 |
| 20:19:09.800 | 9008 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1891 |
| 20:19:09.953 | 9161 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1894 |
| 20:19:10.110 | 9318 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1895 |
| 20:19:10.191 | 9399 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1896 |
| 20:19:10.275 | 9483 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1897 |
| 20:19:10.762 | 9970 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1900 |
| 20:19:11.185 | 10393 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1901 |
| 20:19:11.286 | 10494 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1902 |
| 20:19:11.666 | 10874 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1905 |
| 20:19:11.856 | 11064 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1906 |
| 20:19:11.928 | 11136 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1907 |
| 20:19:12.111 | 11319 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1908 |
| 20:19:12.295 | 11503 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1909 |
| 20:19:12.619 | 11827 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1916 |
| 20:19:12.838 | 12046 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1917 |
| 20:19:13.008 | 12216 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1918 |
| 20:19:13.566 | 12774 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1919 |
| 20:19:13.904 | 13112 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1920 |
| 20:19:13.966 | 13174 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1921 |
| 20:19:14.495 | 13703 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1925 |
| 20:19:14.577 | 13785 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1927 |
| 20:19:14.857 | 14065 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1928 |
| 20:19:15.065 | 14273 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1929 |
| 20:19:15.231 | 14439 | host-cmd |  | pid_after pid_before=26737 pid_after=26737 |  |
| 20:19:15.388 | 14596 | dart-videoparams | 26737 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1931 |
| 20:19:15.968 | 15176 | host-cmd |  | full_dump lines=    1935 |  |
| 20:19:16.148 | 15356 | host-cmd |  | round_end |  |
