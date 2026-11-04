# Timeline F5

App PID filter: 3565 (ActivityManager am_pause/resume lines kept from system_server).

Source: `F5/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 22:55:57.163 | 0 | L0 |
| home_sent(host probe after cmd returned) | 22:55:58.804 | 1641 | L0 |
| am_pause_lab | 22:55:57.756 | 593 | L1292 |
| java_surfaceDestroyed_enter | 22:55:57.946 | 783 | L1340 |
| java_send_SurfaceDestroyed | 22:55:57.946 | 783 | L1342 |
| dart_event_SurfaceDestroyed | 22:55:57.947 | 784 | L1343 |
| dart_detach_lock_acquired | 22:55:57.948 | 785 | L1345 |
| dart_detach_vo_null_begin | 22:55:57.948 | 785 | L1348 |
| native_shutdown_enter | 22:55:58.066 | 903 | L1396 |
| native_shutdown_exit | 22:55:58.067 | 904 | L1398 |
| dart_detach_vo_null_ack | 22:55:58.150 | 987 | L1425 |
| dart_detach_wid0_ack | 22:55:59.242 | 2079 | L1631 |
| dart_detach_apply_complete | 22:56:00.212 | 3049 | L1679 |
| dart_detach_lock_released | 22:56:00.216 | 3053 | L1689 |
| return_sent | 22:55:59.159 | 1996 | L0 |
| am_resume_lab | 22:55:58.512 | 1349 | L1497 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | 22:56:00.218 | 3055 | L1697 |
| java_surfaceCreated_enter | 22:55:58.635 | 1472 | L1522 |
| java_send_SurfaceAvailable | 22:55:58.653 | 1490 | L1541 |
| dart_event_SurfaceAvailable | 22:55:58.654 | 1491 | L1542 |
| dart_bind_requested | 22:55:58.654 | 1491 | L1543 |
| dart_bind_lock_acquired | 22:56:00.216 | 3053 | L1687 |
| dart_bind_vo_gpu_next_begin | 22:56:00.226 | 3063 | L1712 |
| native_ensure_init_exit | 22:56:00.277 | 3114 | L1743 |
| native_create_exit | 22:56:00.279 | 3116 | L1747 |
| mpv_egl_window_surface | 22:56:00.236 | 3073 | L1725 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 22:56:00.339 | 3176 | L1798 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 568 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 83 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 2145 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 2210 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 121 |
| dart_vo_null_begin -> shutdown_enter (ms) | 118 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 1581 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 0 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 1562 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 783 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -524 |

## Counts (whole dump)

| counter | n |
|---|---|
| ensureInitialized_total_in_log | 4 |
| ensureInitialized_after_home_sent | 1 |
| factory_create_total_in_log | 2 |
| factory_create_after_home_sent | 0 |
| mkst_shutdown_exit_total | 1 |
| mkst_create_exit_total | 2 |
| surfaceCreated_enter_total | 3 |
| surfaceDestroyed_enter_total | 2 |

## Events (time-sorted; HOME window and after, plus pre-HOME bridge lifecycle)

| device time | Δhome (ms) | layer | tid | event | line |
|---|---|---|---|---|---|
| 22:55:28.427 | -28736 | host-cmd |  | round_begin mode=fast pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key= |  |
| 22:55:28.722 | -28441 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 22:55:30.484 | -26679 | host-cmd |  | force_stop pid_after= |  |
| 22:55:30.920 | -26243 | host-cmd |  | logcat_cleared per-buffer |  |
| 22:55:31.569 | -25594 | host-cmd |  | am_start_fresh pid=3565 |  |
| 22:55:36.112 | -21051 | java | 3565 | mono=415756488 tid=3565 thr=main java factory.create enter handle=498743520336 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L429 |
| 22:55:36.113 | -21050 | java | 3565 | mono=415756489 tid=3565 thr=main java factory.create view constructed handle=498743520336 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L430 |
| 22:55:36.114 | -21049 | java | 3565 | mono=415756489 tid=3565 thr=main java setLgExperimentOwner enter handle=498743520336 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L431 |
| 22:55:36.114 | -21049 | java | 3565 | mono=415756490 tid=3565 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=1159170726756832773 libraryLoaded=false | L432 |
| 22:55:36.116 | -21047 | native | 3565 | mono=415756491 tid=3565 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=1159170726756832773 req_generation=1 | L433 |
| 22:55:36.118 | -21045 | native | 3565 | mono=415756493 tid=3565 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=1159170726756832773 req_generation=1 resources_ready=1 | L435 |
| 22:55:36.118 | -21045 | native | 3565 | mono=415756494 tid=3565 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=1159170726756832773 generation=1 rc=0 | L437 |
| 22:55:36.118 | -21045 | java | 3565 | mono=415756494 tid=3565 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=1159170726756832773 | L438 |
| 22:55:36.118 | -21045 | java | 3565 | mono=415756494 tid=3565 thr=main java setLgExperimentOwner exit handle=498743520336 viewId=0 ownerGeneration=1 ensureInitialized=ok | L439 |
| 22:55:36.118 | -21045 | java | 3565 | mono=415756494 tid=3565 thr=main java factory.create setLgExperimentOwner returned handle=498743520336 viewId=0 | L440 |
| 22:55:36.119 | -21044 | java | 3565 | mono=415756495 tid=3565 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743520336 viewId=0 ownerGeneration=1 creationSerial=1 | L441 |
| 22:55:36.120 | -21043 | java | 3565 | mono=415756496 tid=3565 thr=main java factory.create exit handle=498743520336 viewId=0 | L443 |
| 22:55:36.175 | -20988 | host-cmd |  | tap_open x=1440 y=720 |  |
| 22:55:36.175 | -20988 | java-log | 3565 | PlatformVideoView: surfaceCreated: handle=498743520336, width=668, height=360, viewIdentity=235825235 | L444 |
| 22:55:36.175 | -20988 | java | 3565 | mono=415756550 tid=3565 thr=main java surfaceCreated enter handle=498743520336 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L445 |
| 22:55:36.186 | -20977 | java-log | 3565 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L447 |
| 22:55:36.186 | -20977 | java | 3565 | mono=415756562 tid=3565 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743520336 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L448 |
| 22:55:36.187 | -20976 | java | 3565 | mono=415756563 tid=3565 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743520336 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L449 |
| 22:55:36.188 | -20975 | java | 3565 | mono=415756564 tid=3565 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743520336 viewId=0 surfaceGeneration=1 wid=2099350 | L454 |
| 22:55:36.188 | -20975 | java | 3565 | mono=415756564 tid=3565 thr=main java surfaceCreated exit handle=498743520336 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L455 |
| 22:55:37.182 | -19981 | java | 3565 | mono=415757557 tid=3565 thr=main java factory.create enter handle=498743520336 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L834 |
| 22:55:37.183 | -19980 | java | 3565 | mono=415757558 tid=3565 thr=main java factory.create view constructed handle=498743520336 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L836 |
| 22:55:37.183 | -19980 | java | 3565 | mono=415757558 tid=3565 thr=main java setLgExperimentOwner enter handle=498743520336 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L837 |
| 22:55:37.183 | -19980 | java | 3565 | mono=415757558 tid=3565 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=1159170726756832773 libraryLoaded=true | L838 |
| 22:55:37.183 | -19980 | native | 3565 | mono=415757558 tid=3565 egl_ctx=0x7424133280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=1159170726756832773 generation=1 req_owner_key=1159170726756832773 req_generation=2 | L839 |
| 22:55:37.183 | -19980 | native | 3565 | mono=415757559 tid=3565 egl_ctx=0x7424133280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=1159170726756832773 generation=1 req_owner_key=1159170726756832773 req_generation=2 resources_ready=1 | L840 |
| 22:55:37.183 | -19980 | native | 3565 | mono=415757559 tid=3565 egl_ctx=0x7424133280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=1159170726756832773 generation=2 rc=0 | L842 |
| 22:55:37.183 | -19980 | java | 3565 | mono=415757559 tid=3565 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=1159170726756832773 | L843 |
| 22:55:37.183 | -19980 | java | 3565 | mono=415757559 tid=3565 thr=main java setLgExperimentOwner exit handle=498743520336 viewId=1 ownerGeneration=2 ensureInitialized=ok | L844 |
| 22:55:37.183 | -19980 | java | 3565 | mono=415757559 tid=3565 thr=main java factory.create setLgExperimentOwner returned handle=498743520336 viewId=1 | L845 |
| 22:55:37.183 | -19980 | java | 3565 | mono=415757559 tid=3565 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743520336 viewId=1 ownerGeneration=2 creationSerial=2 | L846 |
| 22:55:37.183 | -19980 | java | 3565 | mono=415757559 tid=3565 thr=main java factory.create exit handle=498743520336 viewId=1 | L848 |
| 22:55:37.226 | -19937 | java-log | 3565 | PlatformVideoView: surfaceCreated: handle=498743520336, width=668, height=360, viewIdentity=218943113 | L849 |
| 22:55:37.226 | -19937 | java | 3565 | mono=415757602 tid=3565 thr=main java surfaceCreated enter handle=498743520336 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L850 |
| 22:55:37.232 | -19931 | java-log | 3565 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743520336, transfer=pq, applied=true | L863 |
| 22:55:37.232 | -19931 | java-log | 3565 | PlatformVideoView: surfaceCreated: created new wid=2170 | L865 |
| 22:55:37.232 | -19931 | java | 3565 | mono=415757608 tid=3565 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743520336 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=2170 | L866 |
| 22:55:37.232 | -19931 | java | 3565 | mono=415757608 tid=3565 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743520336 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2170 | L867 |
| 22:55:37.233 | -19930 | java | 3565 | mono=415757608 tid=3565 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743520336 viewId=1 surfaceGeneration=1 wid=2170 | L872 |
| 22:55:37.233 | -19930 | java | 3565 | mono=415757608 tid=3565 thr=main java surfaceCreated exit handle=498743520336 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2170 | L873 |
| 22:55:37.285 | -19878 | java | 3565 | mono=415757661 tid=3565 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=1159170726756832773 libraryLoaded=true | L880 |
| 22:55:37.285 | -19878 | native | 3565 | mono=415757661 tid=3565 egl_ctx=0x7424133280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=1159170726756832773 generation=2 req_owner_key=1159170726756832773 req_generation=2 | L881 |
| 22:55:37.285 | -19878 | native | 3565 | mono=415757661 tid=3565 egl_ctx=0x7424133280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=1159170726756832773 generation=2 req_owner_key=1159170726756832773 req_generation=2 resources_ready=1 | L882 |
| 22:55:37.285 | -19878 | native | 3565 | mono=415757661 tid=3565 egl_ctx=0x7424133280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=1159170726756832773 generation=2 rc=0 | L884 |
| 22:55:37.285 | -19878 | java | 3565 | mono=415757661 tid=3565 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=1159170726756832773 | L885 |
| 22:55:37.441 | -19722 | native | 3667 | mono=415757817 tid=3667 egl_ctx=0x7425898b00 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=1159170726756832773 generation=2  | L931 |
| 22:55:37.441 | -19722 | native | 3667 | mono=415757817 tid=3667 egl_ctx=0x7425898b00 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=1159170726756832773 generation=2 ready=1 | L932 |
| 22:55:37.441 | -19722 | native | 3667 | mono=415757817 tid=3667 egl_ctx=0x7425898b00 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=1159170726756832773 generation=2  | L933 |
| 22:55:37.443 | -19720 | native | 3667 | mono=415757818 tid=3667 egl_ctx=0x7425898b00 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=1159170726756832773 generation=2 result=ok window=0x74182ffe10 | L935 |
| 22:55:56.646 | -517 | host-cmd |  | interim_dump lines=    1261 |  |
| 22:55:57.009 | -154 | host-cmd |  | pid_before pid=3565 |  |
| 22:55:57.163 | 0 | host-cmd |  | home_send_begin cmd=adb shell: am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n com.example.media_kit_hdr_lab/.MainActivity --activity-no-animation |  |
| 22:55:57.756 | 593 | activity | 2534 | am_pause_activity: [0,178113246,com.example.media_kit_hdr_lab/.MainActivity] | L1292 |
| 22:55:57.759 | 596 | activity | 3565 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1293 |
| 22:55:57.877 | 714 | activity | 2534 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1316 |
| 22:55:57.946 | 783 | java-log | 3565 | PlatformVideoView: surfaceDestroyed: handle=498743520336, wid=2170 | L1339 |
| 22:55:57.946 | 783 | java | 3565 | mono=415778322 tid=3565 thr=main java surfaceDestroyed enter handle=498743520336 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2170 disposed=false | L1340 |
| 22:55:57.946 | 783 | java | 3565 | mono=415778322 tid=3565 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743520336 viewId=1 surfaceGeneration=1 wid=2170 | L1341 |
| 22:55:57.946 | 783 | java | 3565 | mono=415778322 tid=3565 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743520336 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2170 | L1342 |
| 22:55:57.947 | 784 | dart | 3565 | dart event SurfaceDestroyed handle=498743520336 wid=2170 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=2170 boundSurfaceGeneration=1 | L1343 |
| 22:55:57.948 | 785 | dart | 3565 | dart detach requested wid=2170 surfaceGeneration=1 generation=2 viewId=1 | L1344 |
| 22:55:57.948 | 785 | dart | 3565 | dart detach lock acquired wid=2170 surfaceGeneration=1 generation=2 viewId=1 boundWid=2170 boundSurfaceGeneration=1 | L1345 |
| 22:55:57.948 | 785 | dart | 3565 | dart detach decision wid=2170 isCurrentOutput=true isInFlightOutput=false | L1346 |
| 22:55:57.948 | 785 | dart | 3565 | dart apply begin wid=0 vo=null vid=no | L1347 |
| 22:55:57.948 | 785 | dart | 3565 | dart property begin vo=null | L1348 |
| 22:55:57.948 | 785 | java | 3565 | mono=415778324 tid=3565 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743520336 viewId=1 surfaceGeneration=1 wid=2170 | L1349 |
| 22:55:57.948 | 785 | java | 3565 | mono=415778324 tid=3565 thr=main java surfaceDestroyed exit handle=498743520336 viewId=1 sentEvent=true wid=0 | L1350 |
| 22:55:57.972 | 809 | codec | 3673 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 9/16 output). | L1353 |
| 22:55:57.973 | 810 | codec | 3673 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1359 |
| 22:55:57.977 | 814 | codec | 3673 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1360 |
| 22:55:57.981 | 818 | codec | 3673 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1364 |
| 22:55:58.033 | 870 | codec | 3673 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1374 |
| 22:55:58.038 | 875 | codec | 3673 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1375 |
| 22:55:58.044 | 881 | activity | 3565 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1381 |
| 22:55:58.049 | 886 | codec | 3673 | ACodec  : Now uninitialized | L1386 |
| 22:55:58.066 | 903 | native | 3667 | mono=415778442 tid=3667 egl_ctx=0x7425898b00 native mkst_shutdown enter initialized=1 window_active=1 owner_key=1159170726756832773 generation=2  | L1396 |
| 22:55:58.067 | 904 | native | 3667 | mono=415778443 tid=3667 egl_ctx=0x7425898b00 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=603 latched=603 | L1398 |
| 22:55:58.150 | 987 | dart | 3565 | dart property complete vo=null | L1425 |
| 22:55:58.150 | 987 | dart | 3565 | dart property begin android-surface-size=2672x1336 | L1426 |
| 22:55:58.500 | 1337 | activity | 2615 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1483 |
| 22:55:58.512 | 1349 | activity | 2603 | am_resume_activity: [0,178113246,1046,com.example.media_kit_hdr_lab/.MainActivity] | L1497 |
| 22:55:58.519 | 1356 | dart | 3565 | dart property complete android-surface-size=2672x1336 | L1498 |
| 22:55:58.519 | 1356 | dart | 3565 | dart property begin wid=0 | L1499 |
| 22:55:58.545 | 1382 | activity | 3565 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1507 |
| 22:55:58.635 | 1472 | java-log | 3565 | PlatformVideoView: surfaceCreated: handle=498743520336, width=668, height=360, viewIdentity=218943113 | L1521 |
| 22:55:58.635 | 1472 | java | 3565 | mono=415779011 tid=3565 thr=main java surfaceCreated enter handle=498743520336 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1522 |
| 22:55:58.653 | 1490 | java-log | 3565 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743520336, transfer=pq, applied=true | L1537 |
| 22:55:58.653 | 1490 | java-log | 3565 | PlatformVideoView: surfaceCreated: created new wid=2258 | L1539 |
| 22:55:58.653 | 1490 | java | 3565 | mono=415779029 tid=3565 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743520336 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2258 | L1540 |
| 22:55:58.653 | 1490 | java | 3565 | mono=415779029 tid=3565 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743520336 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2258 | L1541 |
| 22:55:58.654 | 1491 | dart | 3565 | dart event SurfaceAvailable handle=498743520336 wid=2258 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1542 |
| 22:55:58.654 | 1491 | dart | 3565 | dart bind requested wid=2258 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1543 |
| 22:55:58.654 | 1491 | java | 3565 | mono=415779030 tid=3565 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743520336 viewId=1 surfaceGeneration=2 wid=2258 | L1544 |
| 22:55:58.654 | 1491 | java | 3565 | mono=415779030 tid=3565 thr=main java surfaceCreated exit handle=498743520336 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2258 | L1545 |
| 22:55:58.655 | 1492 | java-log | 3565 | PlatformVideoView: surfaceChanged: handle=498743520336, format=43, width=2672, height=1336, wid=2258 | L1546 |
| 22:55:58.804 | 1641 | host-cmd |  | home_sent chained home+return shell returned |  |
| 22:55:58.923 | 1760 | dart-videoparams | 3565 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1588 |
| 22:55:58.970 | 1807 | java-log | 3565 | PlatformVideoView: surfaceChanged: handle=498743520336, format=43, width=1440, height=720, wid=2258 | L1591 |
| 22:55:59.025 | 1862 | host-cmd |  | return_send_begin note-only: return was chained in the same shell as home (method F, sleep 0) |  |
| 22:55:59.071 | 1908 | java-log | 3565 | PlatformVideoView: surfaceChanged: handle=498743520336, format=43, width=2672, height=1440, wid=2258 | L1605 |
| 22:55:59.159 | 1996 | host-cmd |  | return_sent chained shell done |  |
| 22:55:59.242 | 2079 | dart | 3565 | dart property complete wid=0 | L1631 |
| 22:55:59.242 | 2079 | dart | 3565 | dart property begin vo=null | L1632 |
| 22:55:59.635 | 2472 | dart | 3565 | dart property complete vo=null | L1644 |
| 22:55:59.636 | 2473 | dart | 3565 | dart property begin vid=no | L1645 |
| 22:56:00.212 | 3049 | dart | 3565 | dart property complete vid=no | L1678 |
| 22:56:00.212 | 3049 | dart | 3565 | dart apply complete wid=0 | L1679 |
| 22:56:00.212 | 3049 | dart | 3565 | dart detach producer stopped wid=2170 | L1680 |
| 22:56:00.213 | 3050 | java-log | 3565 | PlatformVideoView: releaseSurface generation=1 wid=2170 result=released | L1682 |
| 22:56:00.216 | 3053 | dart | 3565 | dart detach reference released wid=2170 | L1686 |
| 22:56:00.216 | 3053 | dart | 3565 | dart bind lock acquired wid=2258 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1687 |
| 22:56:00.216 | 3053 | dart | 3565 | dart bind branch=rebind wid=2258 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1688 |
| 22:56:00.216 | 3053 | dart | 3565 | dart detach lock released wid=2170 surfaceGeneration=1 | L1689 |
| 22:56:00.216 | 3053 | dart | 3565 | dart apply begin wid=2258 vo=gpu-next vid=auto | L1690 |
| 22:56:00.216 | 3053 | dart | 3565 | dart property begin vo=null | L1691 |
| 22:56:00.217 | 3054 | dart | 3565 | dart property complete vo=null | L1693 |
| 22:56:00.217 | 3054 | dart | 3565 | dart authorize begin wid=2258 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1694 |
| 22:56:00.218 | 3055 | java | 3565 | mono=415780594 tid=3565 thr=main java authorize enter handle=498743520336 generation=2 viewId=1 surfaceGeneration=2 wid=2258 ownerTokenPresent=true | L1696 |
| 22:56:00.218 | 3055 | java | 3565 | mono=415780594 tid=3565 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=1159170726756832773 libraryLoaded=true | L1697 |
| 22:56:00.218 | 3055 | native | 3565 | mono=415780594 tid=3565 egl_ctx=0x7424133280 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=1159170726756832773 req_generation=2 | L1698 |
| 22:56:00.218 | 3055 | native | 3565 | mono=415780594 tid=3565 egl_ctx=0x7424133280 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=1159170726756832773 req_generation=2 resources_ready=1 | L1699 |
| 22:56:00.218 | 3055 | native | 3565 | mono=415780594 tid=3565 egl_ctx=0x7424133280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=1159170726756832773 generation=2 rc=0 | L1701 |
| 22:56:00.218 | 3055 | java | 3565 | mono=415780594 tid=3565 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=1159170726756832773 | L1702 |
| 22:56:00.218 | 3055 | java | 3565 | mono=415780594 tid=3565 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=2258 | L1703 |
| 22:56:00.219 | 3056 | dart | 3565 | dart authorize result epoch=2 wid=2258 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1705 |
| 22:56:00.219 | 3056 | dart | 3565 | dart property begin android-surface-size=2672x1336 | L1706 |
| 22:56:00.223 | 3060 | dart | 3565 | dart property complete android-surface-size=2672x1336 | L1708 |
| 22:56:00.223 | 3060 | dart | 3565 | dart property begin wid=2258 | L1709 |
| 22:56:00.226 | 3063 | dart | 3565 | dart property complete wid=2258 | L1711 |
| 22:56:00.226 | 3063 | dart | 3565 | dart property begin vo=gpu-next | L1712 |
| 22:56:00.236 | 3073 | mpv | 3565 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1725 |
| 22:56:00.258 | 3095 | dart | 3565 | dart property complete vo=gpu-next | L1735 |
| 22:56:00.258 | 3095 | dart | 3565 | dart property begin vid=auto | L1736 |
| 22:56:00.277 | 3114 | native | 3758 | mono=415780653 tid=3758 egl_ctx=0x74110b8180 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=1159170726756832773 generation=2  | L1742 |
| 22:56:00.277 | 3114 | native | 3758 | mono=415780653 tid=3758 egl_ctx=0x74110b8180 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=1159170726756832773 generation=2 ready=1 | L1743 |
| 22:56:00.277 | 3114 | native | 3758 | mono=415780653 tid=3758 egl_ctx=0x74110b8180 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=1159170726756832773 generation=2  | L1744 |
| 22:56:00.277 | 3114 | mpv | 3565 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1745 |
| 22:56:00.279 | 3116 | native | 3758 | mono=415780654 tid=3758 egl_ctx=0x74110b8180 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=1159170726756832773 generation=2 result=ok window=0x7418301a10 | L1747 |
| 22:56:00.281 | 3118 | codec | 3615 | ACodec  : Now uninitialized | L1750 |
| 22:56:00.302 | 3139 | codec | 3761 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1767 |
| 22:56:00.316 | 3153 | codec | 3761 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1787 |
| 22:56:00.326 | 3163 | codec | 3761 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1792 |
| 22:56:00.333 | 3170 | codec | 3761 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1793 |
| 22:56:00.333 | 3170 | codec | 3761 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1794 |
| 22:56:00.339 | 3176 | dart | 3565 | dart property complete vid=auto | L1796 |
| 22:56:00.339 | 3176 | dart | 3565 | dart apply complete wid=2258 | L1797 |
| 22:56:00.339 | 3176 | dart | 3565 | dart bind complete wid=2258 surfaceGeneration=2 | L1798 |
| 22:56:00.339 | 3176 | dart | 3565 | dart bind lock released wid=2258 surfaceGeneration=2 | L1800 |
| 22:56:00.376 | 3213 | codec | 3761 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1803 |
| 22:56:00.383 | 3220 | codec | 3761 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1805 |
| 22:56:00.496 | 3333 | codec | 3761 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1806 |
| 22:56:00.546 | 3383 | dart-videoparams | 3565 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1811 |
| 22:56:00.548 | 3385 | dart | 3565 | dart size property complete android-surface-size=1440x720 | L1812 |
| 22:56:00.604 | 3441 | java-log | 3565 | PlatformVideoView: surfaceChanged: handle=498743520336, format=43, width=2672, height=1336, wid=2258 | L1820 |
| 22:56:00.621 | 3458 | dart | 3565 | dart size property complete android-surface-size=2672x1336 | L1821 |
| 22:56:21.368 | 24205 | host-cmd |  | pid_after pid_before=3565 pid_after=3565 |  |
| 22:56:21.887 | 24724 | host-cmd |  | full_dump lines=    1921 |  |
| 22:56:22.127 | 24964 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 22:56:22.306 | 25143 | host-cmd |  | round_end |  |
