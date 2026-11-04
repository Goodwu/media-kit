# Timeline R4-fast-2

App PID filter: 26505 (ActivityManager am_pause/resume lines kept from system_server).

Source: `R4-fast-2/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 20:18:13.983 | 0 | L0 |
| home_sent(host probe after cmd returned) | 20:18:15.448 | 1465 | L0 |
| am_pause_lab | 20:18:14.540 | 557 | L1261 |
| java_surfaceDestroyed_enter | 20:18:14.781 | 798 | L1358 |
| java_send_SurfaceDestroyed | 20:18:14.781 | 798 | L1360 |
| dart_event_SurfaceDestroyed | 20:18:14.782 | 799 | L1361 |
| dart_detach_lock_acquired | 20:18:14.782 | 799 | L1363 |
| dart_detach_vo_null_begin | 20:18:14.782 | 799 | L1366 |
| native_shutdown_enter | 20:18:14.914 | 931 | L1417 |
| native_shutdown_exit | 20:18:14.915 | 932 | L1419 |
| dart_detach_vo_null_ack | 20:18:15.050 | 1067 | L1466 |
| dart_detach_wid0_ack | 20:18:16.182 | 2199 | L1685 |
| dart_detach_apply_complete | 20:18:17.102 | 3119 | L1700 |
| dart_detach_lock_released | 20:18:17.107 | 3124 | L1708 |
| return_sent | 20:18:15.702 | 1719 | L0 |
| am_resume_lab | 20:18:15.345 | 1362 | L1526 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | — | — | — |
| java_surfaceCreated_enter | 20:18:15.378 | 1395 | L1531 |
| java_send_SurfaceAvailable | 20:18:15.383 | 1400 | L1548 |
| dart_event_SurfaceAvailable | 20:18:15.383 | 1400 | L1549 |
| dart_bind_requested | 20:18:15.383 | 1400 | L1550 |
| dart_bind_lock_acquired | 20:18:17.107 | 3124 | L1706 |
| dart_bind_vo_gpu_next_begin | 20:18:17.113 | 3130 | L1716 |
| native_ensure_init_exit | 20:18:17.155 | 3172 | L1746 |
| native_create_exit | — | — | — |
| mpv_egl_window_surface | 20:18:17.122 | 3139 | L1729 |
| mpv_bridge_not_initialized | 20:18:17.156 | 3173 | L1748 |
| dart_bind_complete | 20:18:17.159 | 3176 | L1751 |
| first_videoparams_after_return | 20:18:17.601 | 3618 | L1775 |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 463 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 135 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 2187 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 2240 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 134 |
| dart_vo_null_begin -> shutdown_enter (ms) | 132 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 1729 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 0 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 1724 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | 1 |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | 2223 |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 798 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -324 |

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
| 20:17:49.599 | -24384 | host-cmd |  | round_begin launch=fresh method=F sleep=0 pkg=com.example.media_kit_hdr_lab |  |
| 20:17:51.650 | -22333 | host-cmd |  | force_stop pid_after= |  |
| 20:17:51.848 | -22135 | host-cmd |  | logcat_cleared |  |
| 20:17:52.690 | -21293 | host-cmd |  | am_start_fresh pid=26505 |  |
| 20:17:57.319 | -16664 | java | 26505 | mono=406297695 tid=26505 thr=main java factory.create enter handle=498759562832 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L389 |
| 20:17:57.320 | -16663 | java | 26505 | mono=406297696 tid=26505 thr=main java factory.create view constructed handle=498759562832 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L390 |
| 20:17:57.320 | -16663 | java | 26505 | mono=406297696 tid=26505 thr=main java setLgExperimentOwner enter handle=498759562832 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L391 |
| 20:17:57.320 | -16663 | java | 26505 | mono=406297696 tid=26505 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=-7295491033130421039 libraryLoaded=false | L392 |
| 20:17:57.321 | -16662 | native | 26505 | mono=406297697 tid=26505 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=11151253040579130577 req_generation=1 | L393 |
| 20:17:57.322 | -16661 | native | 26505 | mono=406297698 tid=26505 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=11151253040579130577 req_generation=1 resources_ready=1 | L395 |
| 20:17:57.322 | -16661 | native | 26505 | mono=406297698 tid=26505 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=11151253040579130577 generation=1 rc=0 | L397 |
| 20:17:57.322 | -16661 | java | 26505 | mono=406297698 tid=26505 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=-7295491033130421039 | L398 |
| 20:17:57.322 | -16661 | java | 26505 | mono=406297698 tid=26505 thr=main java setLgExperimentOwner exit handle=498759562832 viewId=0 ownerGeneration=1 ensureInitialized=ok | L399 |
| 20:17:57.322 | -16661 | java | 26505 | mono=406297698 tid=26505 thr=main java factory.create setLgExperimentOwner returned handle=498759562832 viewId=0 | L400 |
| 20:17:57.323 | -16660 | java | 26505 | mono=406297699 tid=26505 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498759562832 viewId=0 ownerGeneration=1 creationSerial=1 | L401 |
| 20:17:57.324 | -16659 | java | 26505 | mono=406297700 tid=26505 thr=main java factory.create exit handle=498759562832 viewId=0 | L403 |
| 20:17:57.362 | -16621 | java-log | 26505 | PlatformVideoView: surfaceCreated: handle=498759562832, width=668, height=360, viewIdentity=235825235 | L404 |
| 20:17:57.362 | -16621 | java | 26505 | mono=406297737 tid=26505 thr=main java surfaceCreated enter handle=498759562832 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L405 |
| 20:17:57.370 | -16613 | java-log | 26505 | PlatformVideoView: surfaceCreated: created new wid=2099322 | L407 |
| 20:17:57.370 | -16613 | java | 26505 | mono=406297746 tid=26505 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498759562832 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099322 | L408 |
| 20:17:57.370 | -16613 | java | 26505 | mono=406297746 tid=26505 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498759562832 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099322 | L409 |
| 20:17:57.372 | -16611 | java | 26505 | mono=406297747 tid=26505 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498759562832 viewId=0 surfaceGeneration=1 wid=2099322 | L414 |
| 20:17:57.372 | -16611 | java | 26505 | mono=406297747 tid=26505 thr=main java surfaceCreated exit handle=498759562832 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099322 | L415 |
| 20:17:57.486 | -16497 | host-cmd |  | tap_open x=1440 y=720 |  |
| 20:17:58.307 | -15676 | java | 26505 | mono=406298683 tid=26505 thr=main java factory.create enter handle=498759562832 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L794 |
| 20:17:58.308 | -15675 | java | 26505 | mono=406298684 tid=26505 thr=main java factory.create view constructed handle=498759562832 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L796 |
| 20:17:58.308 | -15675 | java | 26505 | mono=406298684 tid=26505 thr=main java setLgExperimentOwner enter handle=498759562832 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L797 |
| 20:17:58.308 | -15675 | java | 26505 | mono=406298684 tid=26505 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-7295491033130421039 libraryLoaded=true | L798 |
| 20:17:58.308 | -15675 | native | 26505 | mono=406298684 tid=26505 egl_ctx=0x744b9ff280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=11151253040579130577 generation=1 req_owner_key=11151253040579130577 req_generation=2 | L799 |
| 20:17:58.308 | -15675 | native | 26505 | mono=406298684 tid=26505 egl_ctx=0x744b9ff280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=11151253040579130577 generation=1 req_owner_key=11151253040579130577 req_generation=2 resources_ready=1 | L800 |
| 20:17:58.309 | -15674 | native | 26505 | mono=406298684 tid=26505 egl_ctx=0x744b9ff280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=11151253040579130577 generation=2 rc=0 | L802 |
| 20:17:58.309 | -15674 | java | 26505 | mono=406298684 tid=26505 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-7295491033130421039 | L803 |
| 20:17:58.309 | -15674 | java | 26505 | mono=406298685 tid=26505 thr=main java setLgExperimentOwner exit handle=498759562832 viewId=1 ownerGeneration=2 ensureInitialized=ok | L804 |
| 20:17:58.309 | -15674 | java | 26505 | mono=406298685 tid=26505 thr=main java factory.create setLgExperimentOwner returned handle=498759562832 viewId=1 | L805 |
| 20:17:58.309 | -15674 | java | 26505 | mono=406298685 tid=26505 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498759562832 viewId=1 ownerGeneration=2 creationSerial=2 | L806 |
| 20:17:58.310 | -15673 | java | 26505 | mono=406298685 tid=26505 thr=main java factory.create exit handle=498759562832 viewId=1 | L808 |
| 20:17:58.362 | -15621 | java-log | 26505 | PlatformVideoView: surfaceCreated: handle=498759562832, width=668, height=360, viewIdentity=207085198 | L809 |
| 20:17:58.362 | -15621 | java | 26505 | mono=406298738 tid=26505 thr=main java surfaceCreated enter handle=498759562832 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L810 |
| 20:17:58.367 | -15616 | java-log | 26505 | PlatformVideoView: surfaceCreated initial dataspace: handle=498759562832, transfer=pq, applied=true | L823 |
| 20:17:58.367 | -15616 | java-log | 26505 | PlatformVideoView: surfaceCreated: created new wid=2099138 | L825 |
| 20:17:58.367 | -15616 | java | 26505 | mono=406298743 tid=26505 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498759562832 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=2099138 | L826 |
| 20:17:58.368 | -15615 | java | 26505 | mono=406298743 tid=26505 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498759562832 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2099138 | L827 |
| 20:17:58.368 | -15615 | java | 26505 | mono=406298744 tid=26505 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498759562832 viewId=1 surfaceGeneration=1 wid=2099138 | L832 |
| 20:17:58.368 | -15615 | java | 26505 | mono=406298744 tid=26505 thr=main java surfaceCreated exit handle=498759562832 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099138 | L833 |
| 20:17:58.554 | -15429 | native | 26577 | mono=406298930 tid=26577 egl_ctx=0x741c3dc300 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=11151253040579130577 generation=2  | L879 |
| 20:17:58.554 | -15429 | native | 26577 | mono=406298930 tid=26577 egl_ctx=0x741c3dc300 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=11151253040579130577 generation=2 ready=1 | L880 |
| 20:17:58.554 | -15429 | native | 26577 | mono=406298930 tid=26577 egl_ctx=0x741c3dc300 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=11151253040579130577 generation=2  | L881 |
| 20:17:58.556 | -15427 | native | 26577 | mono=406298932 tid=26577 egl_ctx=0x741c3dc300 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=11151253040579130577 generation=2 result=ok window=0x744cb55410 | L883 |
| 20:18:13.720 | -263 | host-cmd |  | interim_dump lines=    1237 |  |
| 20:18:13.900 | -83 | host-cmd |  | pid_before pid=26505 |  |
| 20:18:13.983 | 0 | host-cmd |  | home_send_begin cmd=adb shell: am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n com.example.media_kit_hdr_lab/.MainActivity --activity-no-animation |  |
| 20:18:14.540 | 557 | activity | 2593 | am_pause_activity: [0,9508203,com.example.media_kit_hdr_lab/.MainActivity] | L1261 |
| 20:18:14.541 | 558 | activity | 26505 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1262 |
| 20:18:14.664 | 681 | activity | 2593 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1285 |
| 20:18:14.781 | 798 | java-log | 26505 | PlatformVideoView: surfaceDestroyed: handle=498759562832, wid=2099138 | L1357 |
| 20:18:14.781 | 798 | java | 26505 | mono=406315157 tid=26505 thr=main java surfaceDestroyed enter handle=498759562832 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099138 disposed=false | L1358 |
| 20:18:14.781 | 798 | java | 26505 | mono=406315157 tid=26505 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498759562832 viewId=1 surfaceGeneration=1 wid=2099138 | L1359 |
| 20:18:14.781 | 798 | java | 26505 | mono=406315157 tid=26505 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498759562832 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2099138 | L1360 |
| 20:18:14.782 | 799 | dart | 26505 | dart event SurfaceDestroyed handle=498759562832 wid=2099138 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=2099138 boundSurfaceGeneration=1 | L1361 |
| 20:18:14.782 | 799 | dart | 26505 | dart detach requested wid=2099138 surfaceGeneration=1 generation=2 viewId=1 | L1362 |
| 20:18:14.782 | 799 | dart | 26505 | dart detach lock acquired wid=2099138 surfaceGeneration=1 generation=2 viewId=1 boundWid=2099138 boundSurfaceGeneration=1 | L1363 |
| 20:18:14.782 | 799 | dart | 26505 | dart detach decision wid=2099138 isCurrentOutput=true isInFlightOutput=false | L1364 |
| 20:18:14.782 | 799 | dart | 26505 | dart apply begin wid=0 vo=null vid=no | L1365 |
| 20:18:14.782 | 799 | dart | 26505 | dart property begin vo=null | L1366 |
| 20:18:14.782 | 799 | java | 26505 | mono=406315158 tid=26505 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498759562832 viewId=1 surfaceGeneration=1 wid=2099138 | L1367 |
| 20:18:14.782 | 799 | java | 26505 | mono=406315158 tid=26505 thr=main java surfaceDestroyed exit handle=498759562832 viewId=1 sentEvent=true wid=0 | L1368 |
| 20:18:14.802 | 819 | codec | 26582 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 9/16 output). | L1376 |
| 20:18:14.802 | 819 | codec | 26582 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1377 |
| 20:18:14.809 | 826 | codec | 26582 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1381 |
| 20:18:14.845 | 862 | codec | 26582 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1388 |
| 20:18:14.878 | 895 | codec | 26582 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1398 |
| 20:18:14.878 | 895 | codec | 26582 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1399 |
| 20:18:14.893 | 910 | codec | 26582 | ACodec  : Now uninitialized | L1411 |
| 20:18:14.914 | 931 | native | 26577 | mono=406315290 tid=26577 egl_ctx=0x741c3dc300 native mkst_shutdown enter initialized=1 window_active=1 owner_key=11151253040579130577 generation=2  | L1417 |
| 20:18:14.915 | 932 | native | 26577 | mono=406315290 tid=26577 egl_ctx=0x741c3dc300 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=472 latched=472 | L1419 |
| 20:18:14.917 | 934 | activity | 26505 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1422 |
| 20:18:15.050 | 1067 | dart | 26505 | dart property complete vo=null | L1466 |
| 20:18:15.050 | 1067 | dart | 26505 | dart property begin android-surface-size=2672x1336 | L1467 |
| 20:18:15.323 | 1340 | activity | 2612 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1512 |
| 20:18:15.345 | 1362 | activity | 19184 | am_resume_activity: [0,9508203,1035,com.example.media_kit_hdr_lab/.MainActivity] | L1526 |
| 20:18:15.354 | 1371 | activity | 26505 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1528 |
| 20:18:15.378 | 1395 | java-log | 26505 | PlatformVideoView: surfaceCreated: handle=498759562832, width=668, height=360, viewIdentity=207085198 | L1530 |
| 20:18:15.378 | 1395 | java | 26505 | mono=406315753 tid=26505 thr=main java surfaceCreated enter handle=498759562832 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1531 |
| 20:18:15.382 | 1399 | java-log | 26505 | PlatformVideoView: surfaceCreated initial dataspace: handle=498759562832, transfer=pq, applied=true | L1544 |
| 20:18:15.382 | 1399 | java-log | 26505 | PlatformVideoView: surfaceCreated: created new wid=2258 | L1546 |
| 20:18:15.382 | 1399 | java | 26505 | mono=406315758 tid=26505 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498759562832 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2258 | L1547 |
| 20:18:15.383 | 1400 | java | 26505 | mono=406315758 tid=26505 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498759562832 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2258 | L1548 |
| 20:18:15.383 | 1400 | dart | 26505 | dart event SurfaceAvailable handle=498759562832 wid=2258 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1549 |
| 20:18:15.383 | 1400 | dart | 26505 | dart bind requested wid=2258 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1550 |
| 20:18:15.383 | 1400 | java | 26505 | mono=406315759 tid=26505 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498759562832 viewId=1 surfaceGeneration=2 wid=2258 | L1551 |
| 20:18:15.383 | 1400 | java | 26505 | mono=406315759 tid=26505 thr=main java surfaceCreated exit handle=498759562832 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2258 | L1552 |
| 20:18:15.384 | 1401 | java-log | 26505 | PlatformVideoView: surfaceChanged: handle=498759562832, format=43, width=2672, height=1336, wid=2258 | L1553 |
| 20:18:15.448 | 1465 | host-cmd |  | home_sent chained home+return shell returned |  |
| 20:18:15.514 | 1531 | java-log | 26505 | PlatformVideoView: surfaceChanged: handle=498759562832, format=43, width=1440, height=720, wid=2258 | L1584 |
| 20:18:15.574 | 1591 | host-cmd |  | return_send_begin note-only: return was chained in the same shell as home (no separate adb round trip) |  |
| 20:18:15.630 | 1647 | dart | 26505 | dart property complete android-surface-size=2672x1336 | L1603 |
| 20:18:15.630 | 1647 | dart | 26505 | dart property begin wid=0 | L1604 |
| 20:18:15.702 | 1719 | host-cmd |  | return_sent chained shell done |  |
| 20:18:15.715 | 1732 | java-log | 26505 | PlatformVideoView: surfaceChanged: handle=498759562832, format=43, width=1440, height=720, wid=2258 | L1640 |
| 20:18:15.753 | 1770 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1643 |
| 20:18:15.908 | 1925 | java-log | 26505 | PlatformVideoView: surfaceChanged: handle=498759562832, format=43, width=2672, height=1440, wid=2258 | L1669 |
| 20:18:16.182 | 2199 | dart | 26505 | dart property complete wid=0 | L1685 |
| 20:18:16.182 | 2199 | dart | 26505 | dart property begin vo=null | L1686 |
| 20:18:16.600 | 2617 | dart | 26505 | dart property complete vo=null | L1697 |
| 20:18:16.601 | 2618 | dart | 26505 | dart property begin vid=no | L1698 |
| 20:18:17.102 | 3119 | dart | 26505 | dart property complete vid=no | L1699 |
| 20:18:17.102 | 3119 | dart | 26505 | dart apply complete wid=0 | L1700 |
| 20:18:17.103 | 3120 | dart | 26505 | dart detach producer stopped wid=2099138 | L1701 |
| 20:18:17.105 | 3122 | java-log | 26505 | PlatformVideoView: releaseSurface generation=1 wid=2099138 result=released | L1703 |
| 20:18:17.107 | 3124 | dart | 26505 | dart detach reference released wid=2099138 | L1705 |
| 20:18:17.107 | 3124 | dart | 26505 | dart bind lock acquired wid=2258 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1706 |
| 20:18:17.107 | 3124 | dart | 26505 | dart bind branch=rebind wid=2258 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1707 |
| 20:18:17.107 | 3124 | dart | 26505 | dart detach lock released wid=2099138 surfaceGeneration=1 | L1708 |
| 20:18:17.107 | 3124 | dart | 26505 | dart apply begin wid=2258 vo=gpu-next vid=auto | L1709 |
| 20:18:17.107 | 3124 | dart | 26505 | dart property begin vo=null | L1710 |
| 20:18:17.109 | 3126 | dart | 26505 | dart property complete vo=null | L1711 |
| 20:18:17.109 | 3126 | dart | 26505 | dart property begin android-surface-size=2672x1336 | L1712 |
| 20:18:17.110 | 3127 | dart | 26505 | dart property complete android-surface-size=2672x1336 | L1713 |
| 20:18:17.110 | 3127 | dart | 26505 | dart property begin wid=2258 | L1714 |
| 20:18:17.112 | 3129 | dart | 26505 | dart property complete wid=2258 | L1715 |
| 20:18:17.113 | 3130 | dart | 26505 | dart property begin vo=gpu-next | L1716 |
| 20:18:17.122 | 3139 | mpv | 26505 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1729 |
| 20:18:17.139 | 3156 | dart | 26505 | dart property complete vo=gpu-next | L1738 |
| 20:18:17.139 | 3156 | dart | 26505 | dart property begin vid=auto | L1739 |
| 20:18:17.155 | 3172 | native | 26655 | mono=406317531 tid=26655 egl_ctx=0x7418b0d500 native mkst_ensure_init(lc_verify) enter initialized=0 window_active=0 owner_key=0 generation=0  | L1745 |
| 20:18:17.155 | 3172 | native | 26655 | mono=406317531 tid=26655 egl_ctx=0x7418b0d500 native mkst_ensure_init(lc_verify) exit initialized=0 window_active=0 owner_key=0 generation=0 ready=0 | L1746 |
| 20:18:17.156 | 3173 | mpv | 26505 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1747 |
| 20:18:17.156 | 3173 | mpv | 26505 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: bridge not initialized (verify-only ensure_init; Java side owns init) | L1748 |
| 20:18:17.159 | 3176 | dart | 26505 | dart property complete vid=auto | L1749 |
| 20:18:17.159 | 3176 | dart | 26505 | dart apply complete wid=2258 | L1750 |
| 20:18:17.159 | 3176 | dart | 26505 | dart bind complete wid=2258 surfaceGeneration=2 | L1751 |
| 20:18:17.160 | 3177 | dart | 26505 | dart bind lock released wid=2258 surfaceGeneration=2 | L1753 |
| 20:18:17.539 | 3556 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1772 |
| 20:18:17.541 | 3558 | dart | 26505 | dart size property complete android-surface-size=1440x720 | L1773 |
| 20:18:17.601 | 3618 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1775 |
| 20:18:17.613 | 3630 | dart | 26505 | dart size property complete android-surface-size=2672x1336 | L1778 |
| 20:18:17.658 | 3675 | java-log | 26505 | PlatformVideoView: surfaceChanged: handle=498759562832, format=43, width=2672, height=1336, wid=2258 | L1788 |
| 20:18:17.673 | 3690 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1791 |
| 20:18:17.811 | 3828 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1795 |
| 20:18:17.918 | 3935 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1796 |
| 20:18:18.058 | 4075 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1798 |
| 20:18:18.181 | 4198 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1820 |
| 20:18:18.336 | 4353 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1825 |
| 20:18:18.512 | 4529 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1826 |
| 20:18:18.597 | 4614 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1827 |
| 20:18:18.715 | 4732 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1828 |
| 20:18:18.932 | 4949 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1829 |
| 20:18:19.084 | 5101 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1830 |
| 20:18:19.221 | 5238 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1832 |
| 20:18:19.295 | 5312 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1834 |
| 20:18:19.349 | 5366 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1835 |
| 20:18:19.515 | 5532 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1836 |
| 20:18:19.580 | 5597 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1837 |
| 20:18:19.831 | 5848 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1838 |
| 20:18:19.932 | 5949 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1839 |
| 20:18:20.116 | 6133 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1840 |
| 20:18:20.227 | 6244 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1842 |
| 20:18:20.319 | 6336 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1846 |
| 20:18:20.460 | 6477 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1847 |
| 20:18:20.522 | 6539 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1849 |
| 20:18:20.583 | 6600 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1850 |
| 20:18:20.689 | 6706 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1851 |
| 20:18:20.836 | 6853 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1852 |
| 20:18:20.900 | 6917 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1853 |
| 20:18:20.972 | 6989 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1855 |
| 20:18:21.034 | 7051 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1859 |
| 20:18:21.279 | 7296 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1865 |
| 20:18:21.442 | 7459 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1866 |
| 20:18:21.588 | 7605 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1868 |
| 20:18:21.677 | 7694 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1869 |
| 20:18:21.776 | 7793 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1870 |
| 20:18:21.856 | 7873 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1871 |
| 20:18:21.917 | 7934 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1872 |
| 20:18:22.018 | 8035 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1873 |
| 20:18:22.093 | 8110 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1874 |
| 20:18:22.235 | 8252 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1875 |
| 20:18:22.307 | 8324 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1878 |
| 20:18:22.514 | 8531 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1880 |
| 20:18:22.708 | 8725 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1881 |
| 20:18:22.807 | 8824 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1882 |
| 20:18:22.923 | 8940 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1883 |
| 20:18:23.055 | 9072 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1884 |
| 20:18:23.274 | 9291 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1890 |
| 20:18:23.343 | 9360 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1891 |
| 20:18:23.561 | 9578 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1893 |
| 20:18:23.664 | 9681 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1894 |
| 20:18:23.814 | 9831 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1895 |
| 20:18:23.884 | 9901 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1896 |
| 20:18:24.318 | 10335 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1898 |
| 20:18:24.747 | 10764 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1903 |
| 20:18:24.807 | 10824 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1904 |
| 20:18:25.121 | 11138 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1906 |
| 20:18:25.229 | 11246 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1907 |
| 20:18:25.376 | 11393 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1918 |
| 20:18:25.539 | 11556 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1919 |
| 20:18:25.625 | 11642 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1920 |
| 20:18:25.808 | 11825 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1921 |
| 20:18:25.928 | 11945 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1922 |
| 20:18:26.072 | 12089 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1923 |
| 20:18:26.292 | 12309 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1924 |
| 20:18:26.402 | 12419 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1925 |
| 20:18:26.699 | 12716 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1927 |
| 20:18:27.138 | 13155 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1928 |
| 20:18:27.549 | 13566 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1934 |
| 20:18:27.664 | 13681 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1935 |
| 20:18:27.911 | 13928 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1936 |
| 20:18:27.978 | 13995 | host-cmd |  | pid_after pid_before=26505 pid_after=26505 |  |
| 20:18:28.168 | 14185 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1937 |
| 20:18:28.471 | 14488 | dart-videoparams | 26505 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1938 |
| 20:18:28.813 | 14830 | host-cmd |  | full_dump lines=    1938 |  |
| 20:18:29.008 | 15025 | host-cmd |  | round_end |  |
