# Timeline F1

App PID filter: 1862 (ActivityManager am_pause/resume lines kept from system_server).

Source: `F1/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 22:52:21.858 | 0 | L0 |
| home_sent(host probe after cmd returned) | 22:52:23.455 | 1597 | L0 |
| am_pause_lab | 22:52:22.470 | 612 | L1326 |
| java_surfaceDestroyed_enter | 22:52:22.729 | 871 | L1406 |
| java_send_SurfaceDestroyed | 22:52:22.729 | 871 | L1408 |
| dart_event_SurfaceDestroyed | 22:52:22.730 | 872 | L1409 |
| dart_detach_lock_acquired | 22:52:22.730 | 872 | L1411 |
| dart_detach_vo_null_begin | 22:52:22.730 | 872 | L1414 |
| native_shutdown_enter | 22:52:22.898 | 1040 | L1501 |
| native_shutdown_exit | 22:52:22.898 | 1040 | L1503 |
| dart_detach_vo_null_ack | 22:52:22.945 | 1087 | L1510 |
| dart_detach_wid0_ack | 22:52:24.263 | 2405 | L1704 |
| dart_detach_apply_complete | 22:52:25.265 | 3407 | L1728 |
| dart_detach_lock_released | 22:52:25.271 | 3413 | L1739 |
| return_sent | 22:52:24.000 | 2142 | L0 |
| am_resume_lab | 22:52:23.341 | 1483 | L1570 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | 22:52:25.273 | 3415 | L1747 |
| java_surfaceCreated_enter | 22:52:23.441 | 1583 | L1583 |
| java_send_SurfaceAvailable | 22:52:23.461 | 1603 | L1603 |
| dart_event_SurfaceAvailable | 22:52:23.462 | 1604 | L1604 |
| dart_bind_requested | 22:52:23.464 | 1606 | L1605 |
| dart_bind_lock_acquired | 22:52:25.271 | 3413 | L1737 |
| dart_bind_vo_gpu_next_begin | 22:52:25.279 | 3421 | L1759 |
| native_ensure_init_exit | 22:52:25.326 | 3468 | L1790 |
| native_create_exit | 22:52:25.327 | 3469 | L1794 |
| mpv_egl_window_surface | 22:52:25.286 | 3428 | L1772 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 22:52:25.397 | 3539 | L1846 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 543 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 47 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 2367 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 2428 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 169 |
| dart_vo_null_begin -> shutdown_enter (ms) | 168 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 1830 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 0 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 1809 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 871 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -559 |

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
| 22:51:52.487 | -29371 | host-cmd |  | round_begin mode=fast pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=1 open_home_delay=0.5 pre_home_key= resume_key= |  |
| 22:51:52.809 | -29049 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 22:51:54.628 | -27230 | host-cmd |  | force_stop pid_after= |  |
| 22:51:55.228 | -26630 | host-cmd |  | logcat_cleared per-buffer |  |
| 22:51:55.989 | -25869 | host-cmd |  | am_start_fresh pid=1862 |  |
| 22:52:00.691 | -21167 | java | 1862 | mono=415541067 tid=1862 thr=main java factory.create enter handle=498743522384 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L457 |
| 22:52:00.692 | -21166 | java | 1862 | mono=415541068 tid=1862 thr=main java factory.create view constructed handle=498743522384 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L458 |
| 22:52:00.692 | -21166 | java | 1862 | mono=415541068 tid=1862 thr=main java setLgExperimentOwner enter handle=498743522384 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L459 |
| 22:52:00.693 | -21165 | java | 1862 | mono=415541068 tid=1862 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=5544324211490475549 libraryLoaded=false | L460 |
| 22:52:00.693 | -21165 | native | 1862 | mono=415541069 tid=1862 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=5544324211490475549 req_generation=1 | L461 |
| 22:52:00.699 | -21159 | native | 1862 | mono=415541075 tid=1862 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=5544324211490475549 req_generation=1 resources_ready=1 | L463 |
| 22:52:00.699 | -21159 | native | 1862 | mono=415541075 tid=1862 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=5544324211490475549 generation=1 rc=0 | L465 |
| 22:52:00.699 | -21159 | java | 1862 | mono=415541075 tid=1862 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=5544324211490475549 | L466 |
| 22:52:00.700 | -21158 | java | 1862 | mono=415541075 tid=1862 thr=main java setLgExperimentOwner exit handle=498743522384 viewId=0 ownerGeneration=1 ensureInitialized=ok | L467 |
| 22:52:00.700 | -21158 | java | 1862 | mono=415541075 tid=1862 thr=main java factory.create setLgExperimentOwner returned handle=498743522384 viewId=0 | L468 |
| 22:52:00.700 | -21158 | java | 1862 | mono=415541076 tid=1862 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743522384 viewId=0 ownerGeneration=1 creationSerial=1 | L469 |
| 22:52:00.702 | -21156 | java | 1862 | mono=415541078 tid=1862 thr=main java factory.create exit handle=498743522384 viewId=0 | L471 |
| 22:52:00.734 | -21124 | java-log | 1862 | PlatformVideoView: surfaceCreated: handle=498743522384, width=668, height=360, viewIdentity=235825235 | L472 |
| 22:52:00.734 | -21124 | java | 1862 | mono=415541110 tid=1862 thr=main java surfaceCreated enter handle=498743522384 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L473 |
| 22:52:00.747 | -21111 | java-log | 1862 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L475 |
| 22:52:00.747 | -21111 | java | 1862 | mono=415541123 tid=1862 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743522384 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L476 |
| 22:52:00.748 | -21110 | java | 1862 | mono=415541124 tid=1862 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743522384 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L477 |
| 22:52:00.749 | -21109 | java | 1862 | mono=415541125 tid=1862 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743522384 viewId=0 surfaceGeneration=1 wid=2099350 | L482 |
| 22:52:00.749 | -21109 | java | 1862 | mono=415541125 tid=1862 thr=main java surfaceCreated exit handle=498743522384 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L483 |
| 22:52:00.819 | -21039 | host-cmd |  | tap_open x=1440 y=720 |  |
| 22:52:01.628 | -20230 | java | 1862 | mono=415542004 tid=1862 thr=main java factory.create enter handle=498743522384 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L862 |
| 22:52:01.629 | -20229 | java | 1862 | mono=415542004 tid=1862 thr=main java factory.create view constructed handle=498743522384 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L864 |
| 22:52:01.629 | -20229 | java | 1862 | mono=415542004 tid=1862 thr=main java setLgExperimentOwner enter handle=498743522384 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L865 |
| 22:52:01.629 | -20229 | java | 1862 | mono=415542005 tid=1862 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=5544324211490475549 libraryLoaded=true | L866 |
| 22:52:01.629 | -20229 | native | 1862 | mono=415542005 tid=1862 egl_ctx=0x742693c280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=5544324211490475549 generation=1 req_owner_key=5544324211490475549 req_generation=2 | L867 |
| 22:52:01.629 | -20229 | native | 1862 | mono=415542005 tid=1862 egl_ctx=0x742693c280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=5544324211490475549 generation=1 req_owner_key=5544324211490475549 req_generation=2 resources_ready=1 | L868 |
| 22:52:01.629 | -20229 | native | 1862 | mono=415542005 tid=1862 egl_ctx=0x742693c280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=5544324211490475549 generation=2 rc=0 | L870 |
| 22:52:01.629 | -20229 | java | 1862 | mono=415542005 tid=1862 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=5544324211490475549 | L871 |
| 22:52:01.629 | -20229 | java | 1862 | mono=415542005 tid=1862 thr=main java setLgExperimentOwner exit handle=498743522384 viewId=1 ownerGeneration=2 ensureInitialized=ok | L872 |
| 22:52:01.629 | -20229 | java | 1862 | mono=415542005 tid=1862 thr=main java factory.create setLgExperimentOwner returned handle=498743522384 viewId=1 | L873 |
| 22:52:01.629 | -20229 | java | 1862 | mono=415542005 tid=1862 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743522384 viewId=1 ownerGeneration=2 creationSerial=2 | L874 |
| 22:52:01.631 | -20227 | java | 1862 | mono=415542007 tid=1862 thr=main java factory.create exit handle=498743522384 viewId=1 | L876 |
| 22:52:01.680 | -20178 | java-log | 1862 | PlatformVideoView: surfaceCreated: handle=498743522384, width=668, height=360, viewIdentity=207085198 | L877 |
| 22:52:01.680 | -20178 | java | 1862 | mono=415542056 tid=1862 thr=main java surfaceCreated enter handle=498743522384 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L878 |
| 22:52:01.684 | -20174 | java-log | 1862 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743522384, transfer=pq, applied=true | L891 |
| 22:52:01.684 | -20174 | java-log | 1862 | PlatformVideoView: surfaceCreated: created new wid=2170 | L893 |
| 22:52:01.684 | -20174 | java | 1862 | mono=415542060 tid=1862 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743522384 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=2170 | L894 |
| 22:52:01.684 | -20174 | java | 1862 | mono=415542060 tid=1862 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743522384 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2170 | L895 |
| 22:52:01.685 | -20173 | java | 1862 | mono=415542061 tid=1862 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743522384 viewId=1 surfaceGeneration=1 wid=2170 | L900 |
| 22:52:01.685 | -20173 | java | 1862 | mono=415542061 tid=1862 thr=main java surfaceCreated exit handle=498743522384 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2170 | L901 |
| 22:52:01.731 | -20127 | java | 1862 | mono=415542107 tid=1862 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=5544324211490475549 libraryLoaded=true | L908 |
| 22:52:01.732 | -20126 | native | 1862 | mono=415542107 tid=1862 egl_ctx=0x742693c280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=5544324211490475549 generation=2 req_owner_key=5544324211490475549 req_generation=2 | L909 |
| 22:52:01.732 | -20126 | native | 1862 | mono=415542107 tid=1862 egl_ctx=0x742693c280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=5544324211490475549 generation=2 req_owner_key=5544324211490475549 req_generation=2 resources_ready=1 | L910 |
| 22:52:01.732 | -20126 | native | 1862 | mono=415542107 tid=1862 egl_ctx=0x742693c280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=5544324211490475549 generation=2 rc=0 | L912 |
| 22:52:01.732 | -20126 | java | 1862 | mono=415542107 tid=1862 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=5544324211490475549 | L913 |
| 22:52:01.870 | -19988 | native | 1954 | mono=415542246 tid=1954 egl_ctx=0x741daf1700 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=5544324211490475549 generation=2  | L958 |
| 22:52:01.870 | -19988 | native | 1954 | mono=415542246 tid=1954 egl_ctx=0x741daf1700 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=5544324211490475549 generation=2 ready=1 | L959 |
| 22:52:01.870 | -19988 | native | 1954 | mono=415542246 tid=1954 egl_ctx=0x741daf1700 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=5544324211490475549 generation=2  | L960 |
| 22:52:01.872 | -19986 | native | 1954 | mono=415542248 tid=1954 egl_ctx=0x741daf1700 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=5544324211490475549 generation=2 result=ok window=0x741f7d7210 | L962 |
| 22:52:21.127 | -731 | host-cmd |  | sf_dump sf-pre-home.txt lines=     365 |  |
| 22:52:21.433 | -425 | host-cmd |  | interim_dump lines=    1296 |  |
| 22:52:21.717 | -141 | host-cmd |  | pid_before pid=1862 |  |
| 22:52:21.858 | 0 | host-cmd |  | home_send_begin cmd=adb shell: am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n com.example.media_kit_hdr_lab/.MainActivity --activity-no-animation |  |
| 22:52:22.470 | 612 | activity | 2611 | am_pause_activity: [0,32216363,com.example.media_kit_hdr_lab/.MainActivity] | L1326 |
| 22:52:22.477 | 619 | activity | 1862 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1327 |
| 22:52:22.581 | 723 | activity | 2611 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1351 |
| 22:52:22.688 | 830 | activity | 1862 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1384 |
| 22:52:22.729 | 871 | java-log | 1862 | PlatformVideoView: surfaceDestroyed: handle=498743522384, wid=2170 | L1405 |
| 22:52:22.729 | 871 | java | 1862 | mono=415563105 tid=1862 thr=main java surfaceDestroyed enter handle=498743522384 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2170 disposed=false | L1406 |
| 22:52:22.729 | 871 | java | 1862 | mono=415563105 tid=1862 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743522384 viewId=1 surfaceGeneration=1 wid=2170 | L1407 |
| 22:52:22.729 | 871 | java | 1862 | mono=415563105 tid=1862 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743522384 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2170 | L1408 |
| 22:52:22.730 | 872 | dart | 1862 | dart event SurfaceDestroyed handle=498743522384 wid=2170 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=2170 boundSurfaceGeneration=1 | L1409 |
| 22:52:22.730 | 872 | dart | 1862 | dart detach requested wid=2170 surfaceGeneration=1 generation=2 viewId=1 | L1410 |
| 22:52:22.730 | 872 | dart | 1862 | dart detach lock acquired wid=2170 surfaceGeneration=1 generation=2 viewId=1 boundWid=2170 boundSurfaceGeneration=1 | L1411 |
| 22:52:22.730 | 872 | dart | 1862 | dart detach decision wid=2170 isCurrentOutput=true isInFlightOutput=false | L1412 |
| 22:52:22.730 | 872 | dart | 1862 | dart apply begin wid=0 vo=null vid=no | L1413 |
| 22:52:22.730 | 872 | dart | 1862 | dart property begin vo=null | L1414 |
| 22:52:22.730 | 872 | java | 1862 | mono=415563106 tid=1862 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743522384 viewId=1 surfaceGeneration=1 wid=2170 | L1415 |
| 22:52:22.730 | 872 | java | 1862 | mono=415563106 tid=1862 thr=main java surfaceDestroyed exit handle=498743522384 viewId=1 sentEvent=true wid=0 | L1416 |
| 22:52:22.759 | 901 | codec | 2029 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 3/4 input, 10/16 output). | L1430 |
| 22:52:22.765 | 907 | codec | 2029 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1434 |
| 22:52:22.781 | 923 | codec | 2029 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1439 |
| 22:52:22.791 | 933 | codec | 2029 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1443 |
| 22:52:22.818 | 960 | codec | 2029 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1455 |
| 22:52:22.818 | 960 | codec | 2029 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1456 |
| 22:52:22.832 | 974 | codec | 2029 | ACodec  : Now uninitialized | L1473 |
| 22:52:22.898 | 1040 | native | 1954 | mono=415563274 tid=1954 egl_ctx=0x741daf1700 native mkst_shutdown enter initialized=1 window_active=1 owner_key=5544324211490475549 generation=2  | L1501 |
| 22:52:22.898 | 1040 | native | 1954 | mono=415563274 tid=1954 egl_ctx=0x741daf1700 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=613 latched=613 | L1503 |
| 22:52:22.945 | 1087 | dart | 1862 | dart property complete vo=null | L1510 |
| 22:52:22.945 | 1087 | dart | 1862 | dart property begin android-surface-size=2672x1336 | L1511 |
| 22:52:23.283 | 1425 | activity | 2613 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1547 |
| 22:52:23.341 | 1483 | activity | 1738 | am_resume_activity: [0,32216363,1042,com.example.media_kit_hdr_lab/.MainActivity] | L1570 |
| 22:52:23.358 | 1500 | activity | 1862 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1572 |
| 22:52:23.441 | 1583 | java-log | 1862 | PlatformVideoView: surfaceCreated: handle=498743522384, width=668, height=360, viewIdentity=207085198 | L1581 |
| 22:52:23.441 | 1583 | java | 1862 | mono=415563817 tid=1862 thr=main java surfaceCreated enter handle=498743522384 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1583 |
| 22:52:23.455 | 1597 | host-cmd |  | home_sent chained home+return shell returned |  |
| 22:52:23.461 | 1603 | java-log | 1862 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743522384, transfer=pq, applied=true | L1599 |
| 22:52:23.461 | 1603 | java-log | 1862 | PlatformVideoView: surfaceCreated: created new wid=2258 | L1601 |
| 22:52:23.461 | 1603 | java | 1862 | mono=415563837 tid=1862 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743522384 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2258 | L1602 |
| 22:52:23.461 | 1603 | java | 1862 | mono=415563837 tid=1862 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743522384 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2258 | L1603 |
| 22:52:23.462 | 1604 | dart | 1862 | dart event SurfaceAvailable handle=498743522384 wid=2258 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1604 |
| 22:52:23.464 | 1606 | dart | 1862 | dart bind requested wid=2258 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1605 |
| 22:52:23.464 | 1606 | java | 1862 | mono=415563840 tid=1862 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743522384 viewId=1 surfaceGeneration=2 wid=2258 | L1606 |
| 22:52:23.464 | 1606 | java | 1862 | mono=415563840 tid=1862 thr=main java surfaceCreated exit handle=498743522384 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2258 | L1607 |
| 22:52:23.466 | 1608 | java-log | 1862 | PlatformVideoView: surfaceChanged: handle=498743522384, format=43, width=2672, height=1336, wid=2258 | L1608 |
| 22:52:23.591 | 1733 | dart | 1862 | dart property complete android-surface-size=2672x1336 | L1635 |
| 22:52:23.591 | 1733 | dart | 1862 | dart property begin wid=0 | L1636 |
| 22:52:23.622 | 1764 | java-log | 1862 | PlatformVideoView: surfaceChanged: handle=498743522384, format=43, width=1440, height=720, wid=2258 | L1638 |
| 22:52:23.854 | 1996 | host-cmd |  | return_send_begin note-only: return was chained in the same shell as home (method F, sleep 0) |  |
| 22:52:23.863 | 2005 | java-log | 1862 | PlatformVideoView: surfaceChanged: handle=498743522384, format=43, width=2672, height=1336, wid=2258 | L1676 |
| 22:52:24.000 | 2142 | host-cmd |  | return_sent chained shell done |  |
| 22:52:24.063 | 2205 | dart-videoparams | 1862 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1702 |
| 22:52:24.128 | 2270 | java-log | 1862 | PlatformVideoView: surfaceChanged: handle=498743522384, format=43, width=2672, height=1440, wid=2258 | L1703 |
| 22:52:24.263 | 2405 | dart | 1862 | dart property complete wid=0 | L1704 |
| 22:52:24.263 | 2405 | dart | 1862 | dart property begin vo=null | L1705 |
| 22:52:24.734 | 2876 | dart | 1862 | dart property complete vo=null | L1719 |
| 22:52:24.734 | 2876 | dart | 1862 | dart property begin vid=no | L1720 |
| 22:52:25.264 | 3406 | dart | 1862 | dart property complete vid=no | L1727 |
| 22:52:25.265 | 3407 | dart | 1862 | dart apply complete wid=0 | L1728 |
| 22:52:25.265 | 3407 | dart | 1862 | dart detach producer stopped wid=2170 | L1729 |
| 22:52:25.268 | 3410 | java-log | 1862 | PlatformVideoView: releaseSurface generation=1 wid=2170 result=released | L1732 |
| 22:52:25.270 | 3412 | dart | 1862 | dart detach reference released wid=2170 | L1736 |
| 22:52:25.271 | 3413 | dart | 1862 | dart bind lock acquired wid=2258 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1737 |
| 22:52:25.271 | 3413 | dart | 1862 | dart bind branch=rebind wid=2258 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1738 |
| 22:52:25.271 | 3413 | dart | 1862 | dart detach lock released wid=2170 surfaceGeneration=1 | L1739 |
| 22:52:25.271 | 3413 | dart | 1862 | dart apply begin wid=2258 vo=gpu-next vid=auto | L1740 |
| 22:52:25.271 | 3413 | dart | 1862 | dart property begin vo=null | L1741 |
| 22:52:25.272 | 3414 | dart | 1862 | dart property complete vo=null | L1743 |
| 22:52:25.272 | 3414 | dart | 1862 | dart authorize begin wid=2258 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1744 |
| 22:52:25.273 | 3415 | java | 1862 | mono=415565648 tid=1862 thr=main java authorize enter handle=498743522384 generation=2 viewId=1 surfaceGeneration=2 wid=2258 ownerTokenPresent=true | L1746 |
| 22:52:25.273 | 3415 | java | 1862 | mono=415565649 tid=1862 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=5544324211490475549 libraryLoaded=true | L1747 |
| 22:52:25.273 | 3415 | native | 1862 | mono=415565649 tid=1862 egl_ctx=0x742693c280 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=5544324211490475549 req_generation=2 | L1748 |
| 22:52:25.273 | 3415 | native | 1862 | mono=415565649 tid=1862 egl_ctx=0x742693c280 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=5544324211490475549 req_generation=2 resources_ready=1 | L1749 |
| 22:52:25.273 | 3415 | native | 1862 | mono=415565649 tid=1862 egl_ctx=0x742693c280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=5544324211490475549 generation=2 rc=0 | L1751 |
| 22:52:25.273 | 3415 | java | 1862 | mono=415565649 tid=1862 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=5544324211490475549 | L1752 |
| 22:52:25.273 | 3415 | java | 1862 | mono=415565649 tid=1862 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=2258 | L1753 |
| 22:52:25.274 | 3416 | dart | 1862 | dart authorize result epoch=2 wid=2258 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1754 |
| 22:52:25.274 | 3416 | dart | 1862 | dart property begin android-surface-size=2672x1336 | L1755 |
| 22:52:25.275 | 3417 | dart | 1862 | dart property complete android-surface-size=2672x1336 | L1756 |
| 22:52:25.275 | 3417 | dart | 1862 | dart property begin wid=2258 | L1757 |
| 22:52:25.279 | 3421 | dart | 1862 | dart property complete wid=2258 | L1758 |
| 22:52:25.279 | 3421 | dart | 1862 | dart property begin vo=gpu-next | L1759 |
| 22:52:25.286 | 3428 | mpv | 1862 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1772 |
| 22:52:25.305 | 3447 | dart | 1862 | dart property complete vo=gpu-next | L1781 |
| 22:52:25.305 | 3447 | dart | 1862 | dart property begin vid=auto | L1782 |
| 22:52:25.325 | 3467 | native | 2133 | mono=415565701 tid=2133 egl_ctx=0x7418ce3980 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=5544324211490475549 generation=2  | L1789 |
| 22:52:25.326 | 3468 | native | 2133 | mono=415565701 tid=2133 egl_ctx=0x7418ce3980 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=5544324211490475549 generation=2 ready=1 | L1790 |
| 22:52:25.326 | 3468 | native | 2133 | mono=415565701 tid=2133 egl_ctx=0x7418ce3980 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=5544324211490475549 generation=2  | L1791 |
| 22:52:25.326 | 3468 | mpv | 1862 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1792 |
| 22:52:25.327 | 3469 | native | 2133 | mono=415565703 tid=2133 egl_ctx=0x7418ce3980 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=5544324211490475549 generation=2 result=ok window=0x74183bdc10 | L1794 |
| 22:52:25.330 | 3472 | codec | 1895 | ACodec  : Now uninitialized | L1798 |
| 22:52:25.352 | 3494 | codec | 2139 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1822 |
| 22:52:25.366 | 3508 | codec | 2139 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1839 |
| 22:52:25.384 | 3526 | codec | 2139 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1841 |
| 22:52:25.389 | 3531 | codec | 2139 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1842 |
| 22:52:25.389 | 3531 | codec | 2139 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1843 |
| 22:52:25.396 | 3538 | dart | 1862 | dart property complete vid=auto | L1844 |
| 22:52:25.396 | 3538 | dart | 1862 | dart apply complete wid=2258 | L1845 |
| 22:52:25.397 | 3539 | dart | 1862 | dart bind complete wid=2258 surfaceGeneration=2 | L1846 |
| 22:52:25.397 | 3539 | dart | 1862 | dart bind lock released wid=2258 surfaceGeneration=2 | L1848 |
| 22:52:25.411 | 3553 | codec | 2139 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1851 |
| 22:52:25.417 | 3559 | codec | 2139 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1853 |
| 22:52:25.508 | 3650 | codec | 2139 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1854 |
| 22:52:25.557 | 3699 | dart-videoparams | 1862 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1859 |
| 22:52:25.558 | 3700 | dart | 1862 | dart size property complete android-surface-size=1440x720 | L1860 |
| 22:52:25.573 | 3715 | dart | 1862 | dart size property complete android-surface-size=2672x1336 | L1864 |
| 22:52:25.610 | 3752 | java-log | 1862 | PlatformVideoView: surfaceChanged: handle=498743522384, format=43, width=2672, height=1336, wid=2258 | L1875 |
| 22:52:25.623 | 3765 | dart | 1862 | dart size property complete android-surface-size=2672x1336 | L1876 |
| 22:52:46.267 | 24409 | host-cmd |  | pid_after pid_before=1862 pid_after=1862 |  |
| 22:52:46.527 | 24669 | host-cmd |  | sf_dump sf-post-return.txt lines=     364 |  |
| 22:52:47.108 | 25250 | host-cmd |  | full_dump lines=    1950 |  |
| 22:52:47.329 | 25471 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 22:52:47.510 | 25652 | host-cmd |  | round_end |  |
