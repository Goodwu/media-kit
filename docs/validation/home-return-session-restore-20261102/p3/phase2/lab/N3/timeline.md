# Timeline N3

App PID filter: 1543 (ActivityManager am_pause/resume lines kept from system_server).

Source: `N3/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 22:50:28.478 | 0 | L0 |
| home_sent(host probe after cmd returned) | 22:50:29.648 | 1170 | L0 |
| am_pause_lab | 22:50:29.134 | 656 | L1315 |
| java_surfaceDestroyed_enter | 22:50:29.458 | 980 | L1409 |
| java_send_SurfaceDestroyed | 22:50:29.459 | 981 | L1411 |
| dart_event_SurfaceDestroyed | 22:50:29.459 | 981 | L1412 |
| dart_detach_lock_acquired | 22:50:29.460 | 982 | L1414 |
| dart_detach_vo_null_begin | 22:50:29.460 | 982 | L1417 |
| native_shutdown_enter | 22:50:29.499 | 1021 | L1444 |
| native_shutdown_exit | 22:50:29.500 | 1022 | L1446 |
| dart_detach_vo_null_ack | 22:50:29.578 | 1100 | L1462 |
| dart_detach_wid0_ack | 22:50:30.505 | 2027 | L1517 |
| dart_detach_apply_complete | 22:50:31.487 | 3009 | L1540 |
| dart_detach_lock_released | 22:50:31.490 | 3012 | L1547 |
| return_sent | 22:50:40.457 | 11979 | L0 |
| am_resume_lab | 22:50:40.388 | 11910 | L1650 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | 22:50:40.568 | 12090 | L1720 |
| java_surfaceCreated_enter | 22:50:40.467 | 11989 | L1668 |
| java_send_SurfaceAvailable | 22:50:40.472 | 11994 | L1686 |
| dart_event_SurfaceAvailable | 22:50:40.472 | 11994 | L1687 |
| dart_bind_requested | 22:50:40.472 | 11994 | L1688 |
| dart_bind_lock_acquired | 22:50:40.472 | 11994 | L1689 |
| dart_bind_vo_gpu_next_begin | 22:50:40.609 | 12131 | L1753 |
| native_ensure_init_exit | 22:50:40.653 | 12175 | L1793 |
| native_create_exit | 22:50:40.654 | 12176 | L1797 |
| mpv_egl_window_surface | 22:50:40.621 | 12143 | L1772 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 22:50:40.727 | 12249 | L1844 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 10967 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 78 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 1987 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 11153 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 42 |
| dart_vo_null_begin -> shutdown_enter (ms) | 39 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 5 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 8982 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | -8982 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 980 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | 10 |

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
| 22:49:59.648 | -28830 | host-cmd |  | round_begin mode=normal pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key= |  |
| 22:49:59.951 | -28527 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 22:50:01.846 | -26632 | host-cmd |  | force_stop pid_after= |  |
| 22:50:02.310 | -26168 | host-cmd |  | logcat_cleared per-buffer |  |
| 22:50:02.980 | -25498 | host-cmd |  | am_start_fresh pid=1543 |  |
| 22:50:07.546 | -20932 | java | 1543 | mono=415427922 tid=1543 thr=main java factory.create enter handle=498743232592 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L425 |
| 22:50:07.547 | -20931 | java | 1543 | mono=415427923 tid=1543 thr=main java factory.create view constructed handle=498743232592 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L426 |
| 22:50:07.548 | -20930 | java | 1543 | mono=415427923 tid=1543 thr=main java setLgExperimentOwner enter handle=498743232592 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L427 |
| 22:50:07.548 | -20930 | java | 1543 | mono=415427924 tid=1543 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=-1348190804462484415 libraryLoaded=false | L428 |
| 22:50:07.549 | -20929 | native | 1543 | mono=415427925 tid=1543 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=17098553269247067201 req_generation=1 | L429 |
| 22:50:07.551 | -20927 | native | 1543 | mono=415427927 tid=1543 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=17098553269247067201 req_generation=1 resources_ready=1 | L431 |
| 22:50:07.551 | -20927 | native | 1543 | mono=415427927 tid=1543 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=17098553269247067201 generation=1 rc=0 | L433 |
| 22:50:07.551 | -20927 | java | 1543 | mono=415427927 tid=1543 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=-1348190804462484415 | L434 |
| 22:50:07.551 | -20927 | java | 1543 | mono=415427927 tid=1543 thr=main java setLgExperimentOwner exit handle=498743232592 viewId=0 ownerGeneration=1 ensureInitialized=ok | L435 |
| 22:50:07.551 | -20927 | java | 1543 | mono=415427927 tid=1543 thr=main java factory.create setLgExperimentOwner returned handle=498743232592 viewId=0 | L436 |
| 22:50:07.552 | -20926 | java | 1543 | mono=415427928 tid=1543 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743232592 viewId=0 ownerGeneration=1 creationSerial=1 | L437 |
| 22:50:07.553 | -20925 | java | 1543 | mono=415427929 tid=1543 thr=main java factory.create exit handle=498743232592 viewId=0 | L439 |
| 22:50:07.596 | -20882 | java-log | 1543 | PlatformVideoView: surfaceCreated: handle=498743232592, width=668, height=360, viewIdentity=235825235 | L440 |
| 22:50:07.596 | -20882 | java | 1543 | mono=415427972 tid=1543 thr=main java surfaceCreated enter handle=498743232592 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L441 |
| 22:50:07.603 | -20875 | java-log | 1543 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L443 |
| 22:50:07.603 | -20875 | java | 1543 | mono=415427979 tid=1543 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743232592 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L444 |
| 22:50:07.604 | -20874 | java | 1543 | mono=415427980 tid=1543 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743232592 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L445 |
| 22:50:07.607 | -20871 | java | 1543 | mono=415427983 tid=1543 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743232592 viewId=0 surfaceGeneration=1 wid=2099350 | L450 |
| 22:50:07.607 | -20871 | java | 1543 | mono=415427983 tid=1543 thr=main java surfaceCreated exit handle=498743232592 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L451 |
| 22:50:07.645 | -20833 | host-cmd |  | tap_open x=1440 y=720 |  |
| 22:50:08.596 | -19882 | java | 1543 | mono=415428972 tid=1543 thr=main java factory.create enter handle=498743232592 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L831 |
| 22:50:08.597 | -19881 | java | 1543 | mono=415428973 tid=1543 thr=main java factory.create view constructed handle=498743232592 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L833 |
| 22:50:08.597 | -19881 | java | 1543 | mono=415428973 tid=1543 thr=main java setLgExperimentOwner enter handle=498743232592 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L834 |
| 22:50:08.597 | -19881 | java | 1543 | mono=415428973 tid=1543 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-1348190804462484415 libraryLoaded=true | L835 |
| 22:50:08.597 | -19881 | native | 1543 | mono=415428973 tid=1543 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=17098553269247067201 generation=1 req_owner_key=17098553269247067201 req_generation=2 | L836 |
| 22:50:08.597 | -19881 | native | 1543 | mono=415428973 tid=1543 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=17098553269247067201 generation=1 req_owner_key=17098553269247067201 req_generation=2 resources_ready=1 | L837 |
| 22:50:08.597 | -19881 | native | 1543 | mono=415428973 tid=1543 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=17098553269247067201 generation=2 rc=0 | L839 |
| 22:50:08.598 | -19880 | java | 1543 | mono=415428973 tid=1543 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-1348190804462484415 | L840 |
| 22:50:08.598 | -19880 | java | 1543 | mono=415428973 tid=1543 thr=main java setLgExperimentOwner exit handle=498743232592 viewId=1 ownerGeneration=2 ensureInitialized=ok | L841 |
| 22:50:08.598 | -19880 | java | 1543 | mono=415428973 tid=1543 thr=main java factory.create setLgExperimentOwner returned handle=498743232592 viewId=1 | L842 |
| 22:50:08.598 | -19880 | java | 1543 | mono=415428974 tid=1543 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743232592 viewId=1 ownerGeneration=2 creationSerial=2 | L843 |
| 22:50:08.599 | -19879 | java | 1543 | mono=415428974 tid=1543 thr=main java factory.create exit handle=498743232592 viewId=1 | L845 |
| 22:50:08.637 | -19841 | java-log | 1543 | PlatformVideoView: surfaceCreated: handle=498743232592, width=668, height=360, viewIdentity=218943113 | L846 |
| 22:50:08.637 | -19841 | java | 1543 | mono=415429013 tid=1543 thr=main java surfaceCreated enter handle=498743232592 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L847 |
| 22:50:08.641 | -19837 | java-log | 1543 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743232592, transfer=pq, applied=true | L860 |
| 22:50:08.641 | -19837 | java-log | 1543 | PlatformVideoView: surfaceCreated: created new wid=2170 | L862 |
| 22:50:08.641 | -19837 | java | 1543 | mono=415429017 tid=1543 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743232592 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=2170 | L863 |
| 22:50:08.642 | -19836 | java | 1543 | mono=415429017 tid=1543 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743232592 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2170 | L864 |
| 22:50:08.642 | -19836 | java | 1543 | mono=415429018 tid=1543 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743232592 viewId=1 surfaceGeneration=1 wid=2170 | L869 |
| 22:50:08.642 | -19836 | java | 1543 | mono=415429018 tid=1543 thr=main java surfaceCreated exit handle=498743232592 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2170 | L870 |
| 22:50:08.700 | -19778 | java | 1543 | mono=415429076 tid=1543 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-1348190804462484415 libraryLoaded=true | L878 |
| 22:50:08.700 | -19778 | native | 1543 | mono=415429076 tid=1543 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=17098553269247067201 generation=2 req_owner_key=17098553269247067201 req_generation=2 | L879 |
| 22:50:08.700 | -19778 | native | 1543 | mono=415429076 tid=1543 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=17098553269247067201 generation=2 req_owner_key=17098553269247067201 req_generation=2 resources_ready=1 | L880 |
| 22:50:08.700 | -19778 | native | 1543 | mono=415429076 tid=1543 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=17098553269247067201 generation=2 rc=0 | L882 |
| 22:50:08.700 | -19778 | java | 1543 | mono=415429076 tid=1543 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-1348190804462484415 | L883 |
| 22:50:08.829 | -19649 | native | 1642 | mono=415429204 tid=1642 egl_ctx=0x7412dfcb80 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=17098553269247067201 generation=2  | L928 |
| 22:50:08.829 | -19649 | native | 1642 | mono=415429204 tid=1642 egl_ctx=0x7412dfcb80 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=17098553269247067201 generation=2 ready=1 | L929 |
| 22:50:08.829 | -19649 | native | 1642 | mono=415429204 tid=1642 egl_ctx=0x7412dfcb80 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=17098553269247067201 generation=2  | L930 |
| 22:50:08.830 | -19648 | native | 1642 | mono=415429206 tid=1642 egl_ctx=0x7412dfcb80 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=17098553269247067201 generation=2 result=ok window=0x7419545e10 | L932 |
| 22:50:28.060 | -418 | host-cmd |  | interim_dump lines=    1252 |  |
| 22:50:28.331 | -147 | host-cmd |  | pid_before pid=1543 |  |
| 22:50:28.478 | 0 | host-cmd |  | home_send_begin |  |
| 22:50:29.134 | 656 | activity | 2062 | am_pause_activity: [0,99173527,com.example.media_kit_hdr_lab/.MainActivity] | L1315 |
| 22:50:29.137 | 659 | activity | 1543 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1316 |
| 22:50:29.291 | 813 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1341 |
| 22:50:29.421 | 943 | activity | 1543 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1380 |
| 22:50:29.458 | 980 | java-log | 1543 | PlatformVideoView: surfaceDestroyed: handle=498743232592, wid=2170 | L1408 |
| 22:50:29.458 | 980 | java | 1543 | mono=415449834 tid=1543 thr=main java surfaceDestroyed enter handle=498743232592 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2170 disposed=false | L1409 |
| 22:50:29.458 | 980 | java | 1543 | mono=415449834 tid=1543 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743232592 viewId=1 surfaceGeneration=1 wid=2170 | L1410 |
| 22:50:29.459 | 981 | java | 1543 | mono=415449835 tid=1543 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743232592 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2170 | L1411 |
| 22:50:29.459 | 981 | dart | 1543 | dart event SurfaceDestroyed handle=498743232592 wid=2170 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=2170 boundSurfaceGeneration=1 | L1412 |
| 22:50:29.459 | 981 | dart | 1543 | dart detach requested wid=2170 surfaceGeneration=1 generation=2 viewId=1 | L1413 |
| 22:50:29.460 | 982 | dart | 1543 | dart detach lock acquired wid=2170 surfaceGeneration=1 generation=2 viewId=1 boundWid=2170 boundSurfaceGeneration=1 | L1414 |
| 22:50:29.460 | 982 | dart | 1543 | dart detach decision wid=2170 isCurrentOutput=true isInFlightOutput=false | L1415 |
| 22:50:29.460 | 982 | dart | 1543 | dart apply begin wid=0 vo=null vid=no | L1416 |
| 22:50:29.460 | 982 | dart | 1543 | dart property begin vo=null | L1417 |
| 22:50:29.460 | 982 | java | 1543 | mono=415449836 tid=1543 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743232592 viewId=1 surfaceGeneration=1 wid=2170 | L1418 |
| 22:50:29.460 | 982 | java | 1543 | mono=415449836 tid=1543 thr=main java surfaceDestroyed exit handle=498743232592 viewId=1 sentEvent=true wid=0 | L1419 |
| 22:50:29.461 | 983 | codec | 1647 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 1/4 input, 9/16 output). | L1421 |
| 22:50:29.462 | 984 | codec | 1647 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1423 |
| 22:50:29.468 | 990 | codec | 1647 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1426 |
| 22:50:29.472 | 994 | codec | 1647 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1428 |
| 22:50:29.486 | 1008 | codec | 1647 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1433 |
| 22:50:29.486 | 1008 | codec | 1647 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1434 |
| 22:50:29.495 | 1017 | codec | 1647 | ACodec  : Now uninitialized | L1443 |
| 22:50:29.499 | 1021 | native | 1642 | mono=415449875 tid=1642 egl_ctx=0x7412dfcb80 native mkst_shutdown enter initialized=1 window_active=1 owner_key=17098553269247067201 generation=2  | L1444 |
| 22:50:29.500 | 1022 | native | 1642 | mono=415449875 tid=1642 egl_ctx=0x7412dfcb80 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=608 latched=608 | L1446 |
| 22:50:29.578 | 1100 | dart | 1543 | dart property complete vo=null | L1462 |
| 22:50:29.578 | 1100 | dart | 1543 | dart property begin android-surface-size=2672x1336 | L1463 |
| 22:50:29.648 | 1170 | host-cmd |  | home_sent |  |
| 22:50:30.002 | 1524 | dart | 1543 | dart property complete android-surface-size=2672x1336 | L1494 |
| 22:50:30.002 | 1524 | dart | 1543 | dart property begin wid=0 | L1495 |
| 22:50:30.004 | 1526 | dart-videoparams | 1543 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1496 |
| 22:50:30.505 | 2027 | dart | 1543 | dart property complete wid=0 | L1517 |
| 22:50:30.505 | 2027 | dart | 1543 | dart property begin vo=null | L1518 |
| 22:50:30.984 | 2506 | dart | 1543 | dart property complete vo=null | L1532 |
| 22:50:30.984 | 2506 | dart | 1543 | dart property begin vid=no | L1533 |
| 22:50:31.487 | 3009 | dart | 1543 | dart property complete vid=no | L1539 |
| 22:50:31.487 | 3009 | dart | 1543 | dart apply complete wid=0 | L1540 |
| 22:50:31.487 | 3009 | dart | 1543 | dart detach producer stopped wid=2170 | L1541 |
| 22:50:31.488 | 3010 | java-log | 1543 | PlatformVideoView: releaseSurface generation=1 wid=2170 result=released | L1543 |
| 22:50:31.490 | 3012 | dart | 1543 | dart detach reference released wid=2170 | L1546 |
| 22:50:31.490 | 3012 | dart | 1543 | dart detach lock released wid=2170 surfaceGeneration=1 | L1547 |
| 22:50:39.769 | 11291 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity |  |
| 22:50:40.286 | 11808 | activity | 2610 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1614 |
| 22:50:40.388 | 11910 | activity | 2616 | am_resume_activity: [0,99173527,1041,com.example.media_kit_hdr_lab/.MainActivity] | L1650 |
| 22:50:40.411 | 11933 | activity | 1543 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1659 |
| 22:50:40.457 | 11979 | host-cmd |  | return_sent |  |
| 22:50:40.467 | 11989 | java-log | 1543 | PlatformVideoView: surfaceCreated: handle=498743232592, width=668, height=360, viewIdentity=218943113 | L1667 |
| 22:50:40.467 | 11989 | java | 1543 | mono=415460843 tid=1543 thr=main java surfaceCreated enter handle=498743232592 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1668 |
| 22:50:40.471 | 11993 | java-log | 1543 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743232592, transfer=pq, applied=true | L1682 |
| 22:50:40.471 | 11993 | java-log | 1543 | PlatformVideoView: surfaceCreated: created new wid=2099314 | L1684 |
| 22:50:40.472 | 11994 | java | 1543 | mono=415460847 tid=1543 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743232592 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2099314 | L1685 |
| 22:50:40.472 | 11994 | java | 1543 | mono=415460848 tid=1543 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743232592 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2099314 | L1686 |
| 22:50:40.472 | 11994 | dart | 1543 | dart event SurfaceAvailable handle=498743232592 wid=2099314 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1687 |
| 22:50:40.472 | 11994 | dart | 1543 | dart bind requested wid=2099314 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1688 |
| 22:50:40.472 | 11994 | dart | 1543 | dart bind lock acquired wid=2099314 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1689 |
| 22:50:40.472 | 11994 | dart | 1543 | dart bind branch=rebind wid=2099314 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1690 |
| 22:50:40.473 | 11995 | java | 1543 | mono=415460848 tid=1543 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743232592 viewId=1 surfaceGeneration=2 wid=2099314 | L1691 |
| 22:50:40.473 | 11995 | java | 1543 | mono=415460849 tid=1543 thr=main java surfaceCreated exit handle=498743232592 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2099314 | L1692 |
| 22:50:40.473 | 11995 | java-log | 1543 | PlatformVideoView: surfaceChanged: handle=498743232592, format=43, width=2672, height=1336, wid=2099314 | L1693 |
| 22:50:40.491 | 12013 | dart | 1543 | dart apply begin wid=2099314 vo=gpu-next vid=auto | L1699 |
| 22:50:40.491 | 12013 | dart | 1543 | dart property begin vo=null | L1700 |
| 22:50:40.499 | 12021 | dart | 1543 | dart property complete vo=null | L1702 |
| 22:50:40.499 | 12021 | dart | 1543 | dart authorize begin wid=2099314 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1703 |
| 22:50:40.532 | 12054 | java-log | 1543 | PlatformVideoView: surfaceChanged: handle=498743232592, format=43, width=2672, height=1440, wid=2099314 | L1708 |
| 22:50:40.568 | 12090 | java | 1543 | mono=415460944 tid=1543 thr=main java authorize enter handle=498743232592 generation=2 viewId=1 surfaceGeneration=2 wid=2099314 ownerTokenPresent=true | L1719 |
| 22:50:40.568 | 12090 | java | 1543 | mono=415460944 tid=1543 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-1348190804462484415 libraryLoaded=true | L1720 |
| 22:50:40.568 | 12090 | native | 1543 | mono=415460944 tid=1543 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=17098553269247067201 req_generation=2 | L1721 |
| 22:50:40.569 | 12091 | native | 1543 | mono=415460944 tid=1543 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=17098553269247067201 req_generation=2 resources_ready=1 | L1722 |
| 22:50:40.569 | 12091 | native | 1543 | mono=415460944 tid=1543 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=17098553269247067201 generation=2 rc=0 | L1724 |
| 22:50:40.569 | 12091 | java | 1543 | mono=415460944 tid=1543 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-1348190804462484415 | L1725 |
| 22:50:40.569 | 12091 | java | 1543 | mono=415460944 tid=1543 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=2099314 | L1726 |
| 22:50:40.578 | 12100 | dart | 1543 | dart authorize result epoch=2 wid=2099314 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1736 |
| 22:50:40.578 | 12100 | dart | 1543 | dart property begin android-surface-size=2672x1336 | L1737 |
| 22:50:40.589 | 12111 | dart | 1543 | dart property complete android-surface-size=2672x1336 | L1745 |
| 22:50:40.589 | 12111 | dart | 1543 | dart property begin wid=2099314 | L1746 |
| 22:50:40.609 | 12131 | dart | 1543 | dart property complete wid=2099314 | L1752 |
| 22:50:40.609 | 12131 | dart | 1543 | dart property begin vo=gpu-next | L1753 |
| 22:50:40.621 | 12143 | mpv | 1543 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1772 |
| 22:50:40.637 | 12159 | dart | 1543 | dart property complete vo=gpu-next | L1785 |
| 22:50:40.638 | 12160 | dart | 1543 | dart property begin vid=auto | L1786 |
| 22:50:40.653 | 12175 | native | 1729 | mono=415461028 tid=1729 egl_ctx=0x741327fe80 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=17098553269247067201 generation=2  | L1792 |
| 22:50:40.653 | 12175 | native | 1729 | mono=415461029 tid=1729 egl_ctx=0x741327fe80 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=17098553269247067201 generation=2 ready=1 | L1793 |
| 22:50:40.653 | 12175 | native | 1729 | mono=415461029 tid=1729 egl_ctx=0x741327fe80 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=17098553269247067201 generation=2  | L1794 |
| 22:50:40.653 | 12175 | mpv | 1543 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1795 |
| 22:50:40.654 | 12176 | native | 1729 | mono=415461030 tid=1729 egl_ctx=0x741327fe80 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=17098553269247067201 generation=2 result=ok window=0x7419545e10 | L1797 |
| 22:50:40.660 | 12182 | codec | 1592 | ACodec  : Now uninitialized | L1800 |
| 22:50:40.676 | 12198 | codec | 1733 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1809 |
| 22:50:40.688 | 12210 | codec | 1733 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1833 |
| 22:50:40.718 | 12240 | codec | 1733 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1839 |
| 22:50:40.724 | 12246 | codec | 1733 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1840 |
| 22:50:40.724 | 12246 | codec | 1733 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1841 |
| 22:50:40.727 | 12249 | dart | 1543 | dart property complete vid=auto | L1842 |
| 22:50:40.727 | 12249 | dart | 1543 | dart apply complete wid=2099314 | L1843 |
| 22:50:40.727 | 12249 | dart | 1543 | dart bind complete wid=2099314 surfaceGeneration=2 | L1844 |
| 22:50:40.727 | 12249 | dart | 1543 | dart bind lock released wid=2099314 surfaceGeneration=2 | L1845 |
| 22:50:40.734 | 12256 | dart-videoparams | 1543 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1846 |
| 22:50:40.755 | 12277 | codec | 1733 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1849 |
| 22:50:40.760 | 12282 | codec | 1733 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1851 |
| 22:50:40.831 | 12353 | codec | 1733 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1852 |
| 22:50:40.881 | 12403 | dart-videoparams | 1543 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1857 |
| 22:50:40.889 | 12411 | dart | 1543 | dart size property complete android-surface-size=2672x1336 | L1859 |
| 22:50:40.929 | 12451 | java-log | 1543 | PlatformVideoView: surfaceChanged: handle=498743232592, format=43, width=2672, height=1336, wid=2099314 | L1860 |
| 22:51:02.686 | 34208 | host-cmd |  | pid_after pid_before=1543 pid_after=1543 |  |
| 22:51:03.146 | 34668 | host-cmd |  | full_dump lines=    1968 |  |
| 22:51:03.307 | 34829 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 22:51:03.444 | 34966 | host-cmd |  | round_end |  |
