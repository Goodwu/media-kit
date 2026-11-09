# Timeline F2

App PID filter: 2320 (ActivityManager am_pause/resume lines kept from system_server).

Source: `F2/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 22:53:16.647 | 0 | L0 |
| home_sent(host probe after cmd returned) | 22:53:18.083 | 1436 | L0 |
| am_pause_lab | 22:53:17.209 | 562 | L1312 |
| java_surfaceDestroyed_enter | 22:53:17.410 | 763 | L1366 |
| java_send_SurfaceDestroyed | 22:53:17.410 | 763 | L1368 |
| dart_event_SurfaceDestroyed | 22:53:17.411 | 764 | L1369 |
| dart_detach_lock_acquired | 22:53:17.411 | 764 | L1371 |
| dart_detach_vo_null_begin | 22:53:17.411 | 764 | L1374 |
| native_shutdown_enter | 22:53:17.493 | 846 | L1410 |
| native_shutdown_exit | 22:53:17.494 | 847 | L1412 |
| dart_detach_vo_null_ack | 22:53:17.676 | 1029 | L1471 |
| dart_detach_wid0_ack | 22:53:18.683 | 2036 | L1650 |
| dart_detach_apply_complete | 22:53:19.609 | 2962 | L1667 |
| dart_detach_lock_released | 22:53:19.619 | 2972 | L1675 |
| return_sent | 22:53:18.369 | 1722 | L0 |
| am_resume_lab | 22:53:17.973 | 1326 | L1530 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | 22:53:19.621 | 2974 | L1681 |
| java_surfaceCreated_enter | 22:53:18.020 | 1373 | L1535 |
| java_send_SurfaceAvailable | 22:53:18.030 | 1383 | L1552 |
| dart_event_SurfaceAvailable | 22:53:18.031 | 1384 | L1553 |
| dart_bind_requested | 22:53:18.031 | 1384 | L1554 |
| dart_bind_lock_acquired | 22:53:19.618 | 2971 | L1673 |
| dart_bind_vo_gpu_next_begin | 22:53:19.626 | 2979 | L1693 |
| native_ensure_init_exit | 22:53:19.679 | 3032 | L1724 |
| native_create_exit | 22:53:19.680 | 3033 | L1728 |
| mpv_egl_window_surface | 22:53:19.639 | 2992 | L1706 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 22:53:19.730 | 3083 | L1776 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 526 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 182 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 2115 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 2185 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 84 |
| dart_vo_null_begin -> shutdown_enter (ms) | 82 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 1598 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | -1 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 1588 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 763 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -349 |

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
| 22:52:48.024 | -28623 | host-cmd |  | round_begin mode=fast pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key= |  |
| 22:52:48.486 | -28161 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 22:52:50.300 | -26347 | host-cmd |  | force_stop pid_after= |  |
| 22:52:50.756 | -25891 | host-cmd |  | logcat_cleared per-buffer |  |
| 22:52:51.432 | -25215 | host-cmd |  | am_start_fresh pid=2320 |  |
| 22:52:56.002 | -20645 | java | 2320 | mono=415596378 tid=2320 thr=main java factory.create enter handle=498743565392 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L424 |
| 22:52:56.003 | -20644 | java | 2320 | mono=415596379 tid=2320 thr=main java factory.create view constructed handle=498743565392 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L425 |
| 22:52:56.004 | -20643 | java | 2320 | mono=415596379 tid=2320 thr=main java setLgExperimentOwner enter handle=498743565392 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L426 |
| 22:52:56.004 | -20643 | java | 2320 | mono=415596380 tid=2320 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=-1577103693296012 libraryLoaded=false | L427 |
| 22:52:56.007 | -20640 | native | 2320 | mono=415596382 tid=2320 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=18445166970016255604 req_generation=1 | L428 |
| 22:52:56.010 | -20637 | native | 2320 | mono=415596385 tid=2320 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=18445166970016255604 req_generation=1 resources_ready=1 | L430 |
| 22:52:56.010 | -20637 | native | 2320 | mono=415596386 tid=2320 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=18445166970016255604 generation=1 rc=0 | L432 |
| 22:52:56.010 | -20637 | java | 2320 | mono=415596386 tid=2320 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=-1577103693296012 | L433 |
| 22:52:56.010 | -20637 | java | 2320 | mono=415596386 tid=2320 thr=main java setLgExperimentOwner exit handle=498743565392 viewId=0 ownerGeneration=1 ensureInitialized=ok | L434 |
| 22:52:56.010 | -20637 | java | 2320 | mono=415596386 tid=2320 thr=main java factory.create setLgExperimentOwner returned handle=498743565392 viewId=0 | L435 |
| 22:52:56.011 | -20636 | java | 2320 | mono=415596387 tid=2320 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743565392 viewId=0 ownerGeneration=1 creationSerial=1 | L436 |
| 22:52:56.014 | -20633 | java | 2320 | mono=415596389 tid=2320 thr=main java factory.create exit handle=498743565392 viewId=0 | L438 |
| 22:52:56.073 | -20574 | host-cmd |  | tap_open x=1440 y=720 |  |
| 22:52:56.095 | -20552 | java-log | 2320 | PlatformVideoView: surfaceCreated: handle=498743565392, width=668, height=360, viewIdentity=235825235 | L440 |
| 22:52:56.095 | -20552 | java | 2320 | mono=415596471 tid=2320 thr=main java surfaceCreated enter handle=498743565392 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L441 |
| 22:52:56.102 | -20545 | java-log | 2320 | PlatformVideoView: surfaceCreated: created new wid=2099322 | L443 |
| 22:52:56.102 | -20545 | java | 2320 | mono=415596478 tid=2320 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743565392 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099322 | L444 |
| 22:52:56.102 | -20545 | java | 2320 | mono=415596478 tid=2320 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743565392 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099322 | L445 |
| 22:52:56.103 | -20544 | java | 2320 | mono=415596479 tid=2320 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743565392 viewId=0 surfaceGeneration=1 wid=2099322 | L450 |
| 22:52:56.103 | -20544 | java | 2320 | mono=415596479 tid=2320 thr=main java surfaceCreated exit handle=498743565392 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099322 | L451 |
| 22:52:57.054 | -19593 | java | 2320 | mono=415597430 tid=2320 thr=main java factory.create enter handle=498743565392 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L836 |
| 22:52:57.055 | -19592 | java | 2320 | mono=415597431 tid=2320 thr=main java factory.create view constructed handle=498743565392 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L838 |
| 22:52:57.055 | -19592 | java | 2320 | mono=415597431 tid=2320 thr=main java setLgExperimentOwner enter handle=498743565392 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L839 |
| 22:52:57.055 | -19592 | java | 2320 | mono=415597431 tid=2320 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-1577103693296012 libraryLoaded=true | L840 |
| 22:52:57.055 | -19592 | native | 2320 | mono=415597431 tid=2320 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=18445166970016255604 generation=1 req_owner_key=18445166970016255604 req_generation=2 | L841 |
| 22:52:57.055 | -19592 | native | 2320 | mono=415597431 tid=2320 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=18445166970016255604 generation=1 req_owner_key=18445166970016255604 req_generation=2 resources_ready=1 | L842 |
| 22:52:57.055 | -19592 | native | 2320 | mono=415597431 tid=2320 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=18445166970016255604 generation=2 rc=0 | L844 |
| 22:52:57.055 | -19592 | java | 2320 | mono=415597431 tid=2320 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-1577103693296012 | L845 |
| 22:52:57.055 | -19592 | java | 2320 | mono=415597431 tid=2320 thr=main java setLgExperimentOwner exit handle=498743565392 viewId=1 ownerGeneration=2 ensureInitialized=ok | L846 |
| 22:52:57.055 | -19592 | java | 2320 | mono=415597431 tid=2320 thr=main java factory.create setLgExperimentOwner returned handle=498743565392 viewId=1 | L847 |
| 22:52:57.056 | -19591 | java | 2320 | mono=415597431 tid=2320 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743565392 viewId=1 ownerGeneration=2 creationSerial=2 | L848 |
| 22:52:57.056 | -19591 | java | 2320 | mono=415597432 tid=2320 thr=main java factory.create exit handle=498743565392 viewId=1 | L850 |
| 22:52:57.093 | -19554 | java-log | 2320 | PlatformVideoView: surfaceCreated: handle=498743565392, width=668, height=360, viewIdentity=218943113 | L852 |
| 22:52:57.093 | -19554 | java | 2320 | mono=415597469 tid=2320 thr=main java surfaceCreated enter handle=498743565392 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L853 |
| 22:52:57.097 | -19550 | java-log | 2320 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743565392, transfer=pq, applied=true | L866 |
| 22:52:57.098 | -19549 | java-log | 2320 | PlatformVideoView: surfaceCreated: created new wid=1946 | L868 |
| 22:52:57.098 | -19549 | java | 2320 | mono=415597473 tid=2320 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743565392 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=1946 | L869 |
| 22:52:57.098 | -19549 | java | 2320 | mono=415597473 tid=2320 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743565392 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1946 | L870 |
| 22:52:57.098 | -19549 | java | 2320 | mono=415597474 tid=2320 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743565392 viewId=1 surfaceGeneration=1 wid=1946 | L875 |
| 22:52:57.098 | -19549 | java | 2320 | mono=415597474 tid=2320 thr=main java surfaceCreated exit handle=498743565392 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1946 | L876 |
| 22:52:57.143 | -19504 | java | 2320 | mono=415597519 tid=2320 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-1577103693296012 libraryLoaded=true | L883 |
| 22:52:57.143 | -19504 | native | 2320 | mono=415597519 tid=2320 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=18445166970016255604 generation=2 req_owner_key=18445166970016255604 req_generation=2 | L884 |
| 22:52:57.143 | -19504 | native | 2320 | mono=415597519 tid=2320 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=18445166970016255604 generation=2 req_owner_key=18445166970016255604 req_generation=2 resources_ready=1 | L885 |
| 22:52:57.144 | -19503 | native | 2320 | mono=415597519 tid=2320 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=18445166970016255604 generation=2 rc=0 | L887 |
| 22:52:57.144 | -19503 | java | 2320 | mono=415597519 tid=2320 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-1577103693296012 | L888 |
| 22:52:57.269 | -19378 | native | 2430 | mono=415597645 tid=2430 egl_ctx=0x741c335700 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=18445166970016255604 generation=2  | L933 |
| 22:52:57.269 | -19378 | native | 2430 | mono=415597645 tid=2430 egl_ctx=0x741c335700 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=18445166970016255604 generation=2 ready=1 | L934 |
| 22:52:57.269 | -19378 | native | 2430 | mono=415597645 tid=2430 egl_ctx=0x741c335700 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=18445166970016255604 generation=2  | L935 |
| 22:52:57.270 | -19377 | native | 2430 | mono=415597646 tid=2430 egl_ctx=0x741c335700 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=18445166970016255604 generation=2 result=ok window=0x744cb55410 | L937 |
| 22:53:16.301 | -346 | host-cmd |  | interim_dump lines=    1284 |  |
| 22:53:16.507 | -140 | host-cmd |  | pid_before pid=2320 |  |
| 22:53:16.647 | 0 | host-cmd |  | home_send_begin cmd=adb shell: am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n com.example.media_kit_hdr_lab/.MainActivity --activity-no-animation |  |
| 22:53:17.209 | 562 | activity | 19183 | am_pause_activity: [0,239877201,com.example.media_kit_hdr_lab/.MainActivity] | L1312 |
| 22:53:17.214 | 567 | activity | 2320 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1313 |
| 22:53:17.323 | 676 | activity | 19183 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1335 |
| 22:53:17.410 | 763 | java-log | 2320 | PlatformVideoView: surfaceDestroyed: handle=498743565392, wid=1946 | L1365 |
| 22:53:17.410 | 763 | java | 2320 | mono=415617786 tid=2320 thr=main java surfaceDestroyed enter handle=498743565392 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1946 disposed=false | L1366 |
| 22:53:17.410 | 763 | java | 2320 | mono=415617786 tid=2320 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743565392 viewId=1 surfaceGeneration=1 wid=1946 | L1367 |
| 22:53:17.410 | 763 | java | 2320 | mono=415617786 tid=2320 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743565392 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1946 | L1368 |
| 22:53:17.411 | 764 | dart | 2320 | dart event SurfaceDestroyed handle=498743565392 wid=1946 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=1946 boundSurfaceGeneration=1 | L1369 |
| 22:53:17.411 | 764 | dart | 2320 | dart detach requested wid=1946 surfaceGeneration=1 generation=2 viewId=1 | L1370 |
| 22:53:17.411 | 764 | dart | 2320 | dart detach lock acquired wid=1946 surfaceGeneration=1 generation=2 viewId=1 boundWid=1946 boundSurfaceGeneration=1 | L1371 |
| 22:53:17.411 | 764 | dart | 2320 | dart detach decision wid=1946 isCurrentOutput=true isInFlightOutput=false | L1372 |
| 22:53:17.411 | 764 | dart | 2320 | dart apply begin wid=0 vo=null vid=no | L1373 |
| 22:53:17.411 | 764 | dart | 2320 | dart property begin vo=null | L1374 |
| 22:53:17.412 | 765 | java | 2320 | mono=415617787 tid=2320 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743565392 viewId=1 surfaceGeneration=1 wid=1946 | L1375 |
| 22:53:17.412 | 765 | java | 2320 | mono=415617787 tid=2320 thr=main java surfaceDestroyed exit handle=498743565392 viewId=1 sentEvent=true wid=0 | L1376 |
| 22:53:17.416 | 769 | codec | 2439 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 11/16 output). | L1377 |
| 22:53:17.417 | 770 | codec | 2439 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1378 |
| 22:53:17.421 | 774 | codec | 2439 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1379 |
| 22:53:17.436 | 789 | codec | 2439 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1383 |
| 22:53:17.450 | 803 | codec | 2439 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1390 |
| 22:53:17.451 | 804 | codec | 2439 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1391 |
| 22:53:17.470 | 823 | codec | 2439 | ACodec  : Now uninitialized | L1401 |
| 22:53:17.493 | 846 | native | 2430 | mono=415617869 tid=2430 egl_ctx=0x741c335700 native mkst_shutdown enter initialized=1 window_active=1 owner_key=18445166970016255604 generation=2  | L1410 |
| 22:53:17.494 | 847 | native | 2430 | mono=415617869 tid=2430 egl_ctx=0x741c335700 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=594 latched=594 | L1412 |
| 22:53:17.542 | 895 | activity | 2320 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1416 |
| 22:53:17.676 | 1029 | dart | 2320 | dart property complete vo=null | L1471 |
| 22:53:17.676 | 1029 | dart | 2320 | dart property begin android-surface-size=2672x1336 | L1472 |
| 22:53:17.947 | 1300 | activity | 2607 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1516 |
| 22:53:17.973 | 1326 | activity | 1738 | am_resume_activity: [0,239877201,1043,com.example.media_kit_hdr_lab/.MainActivity] | L1530 |
| 22:53:17.988 | 1341 | activity | 2320 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1532 |
| 22:53:18.019 | 1372 | java-log | 2320 | PlatformVideoView: surfaceCreated: handle=498743565392, width=668, height=360, viewIdentity=218943113 | L1534 |
| 22:53:18.020 | 1373 | java | 2320 | mono=415618395 tid=2320 thr=main java surfaceCreated enter handle=498743565392 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1535 |
| 22:53:18.030 | 1383 | java-log | 2320 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743565392, transfer=pq, applied=true | L1548 |
| 22:53:18.030 | 1383 | java-log | 2320 | PlatformVideoView: surfaceCreated: created new wid=2258 | L1550 |
| 22:53:18.030 | 1383 | java | 2320 | mono=415618406 tid=2320 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743565392 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2258 | L1551 |
| 22:53:18.030 | 1383 | java | 2320 | mono=415618406 tid=2320 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743565392 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2258 | L1552 |
| 22:53:18.031 | 1384 | dart | 2320 | dart event SurfaceAvailable handle=498743565392 wid=2258 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1553 |
| 22:53:18.031 | 1384 | dart | 2320 | dart bind requested wid=2258 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1554 |
| 22:53:18.032 | 1385 | java | 2320 | mono=415618407 tid=2320 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743565392 viewId=1 surfaceGeneration=2 wid=2258 | L1555 |
| 22:53:18.032 | 1385 | java | 2320 | mono=415618408 tid=2320 thr=main java surfaceCreated exit handle=498743565392 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2258 | L1556 |
| 22:53:18.032 | 1385 | java-log | 2320 | PlatformVideoView: surfaceChanged: handle=498743565392, format=43, width=2672, height=1336, wid=2258 | L1557 |
| 22:53:18.083 | 1436 | host-cmd |  | home_sent chained home+return shell returned |  |
| 22:53:18.135 | 1488 | dart | 2320 | dart property complete android-surface-size=2672x1336 | L1575 |
| 22:53:18.135 | 1488 | dart | 2320 | dart property begin wid=0 | L1576 |
| 22:53:18.215 | 1568 | java-log | 2320 | PlatformVideoView: surfaceChanged: handle=498743565392, format=43, width=1440, height=720, wid=2258 | L1592 |
| 22:53:18.273 | 1626 | java-log | 2320 | PlatformVideoView: surfaceChanged: handle=498743565392, format=43, width=1440, height=720, wid=2258 | L1602 |
| 22:53:18.275 | 1628 | host-cmd |  | return_send_begin note-only: return was chained in the same shell as home (method F, sleep 0) |  |
| 22:53:18.357 | 1710 | dart-videoparams | 2320 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1607 |
| 22:53:18.369 | 1722 | host-cmd |  | return_sent chained shell done |  |
| 22:53:18.493 | 1846 | java-log | 2320 | PlatformVideoView: surfaceChanged: handle=498743565392, format=43, width=1440, height=2672, wid=2258 | L1626 |
| 22:53:18.612 | 1965 | java-log | 2320 | PlatformVideoView: surfaceChanged: handle=498743565392, format=43, width=2672, height=1440, wid=2258 | L1638 |
| 22:53:18.683 | 2036 | dart | 2320 | dart property complete wid=0 | L1650 |
| 22:53:18.683 | 2036 | dart | 2320 | dart property begin vo=null | L1651 |
| 22:53:19.076 | 2429 | dart | 2320 | dart property complete vo=null | L1664 |
| 22:53:19.077 | 2430 | dart | 2320 | dart property begin vid=no | L1665 |
| 22:53:19.609 | 2962 | dart | 2320 | dart property complete vid=no | L1666 |
| 22:53:19.609 | 2962 | dart | 2320 | dart apply complete wid=0 | L1667 |
| 22:53:19.609 | 2962 | dart | 2320 | dart detach producer stopped wid=1946 | L1668 |
| 22:53:19.612 | 2965 | java-log | 2320 | PlatformVideoView: releaseSurface generation=1 wid=1946 result=released | L1670 |
| 22:53:19.618 | 2971 | dart | 2320 | dart detach reference released wid=1946 | L1672 |
| 22:53:19.618 | 2971 | dart | 2320 | dart bind lock acquired wid=2258 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1673 |
| 22:53:19.618 | 2971 | dart | 2320 | dart bind branch=rebind wid=2258 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1674 |
| 22:53:19.619 | 2972 | dart | 2320 | dart detach lock released wid=1946 surfaceGeneration=1 | L1675 |
| 22:53:19.619 | 2972 | dart | 2320 | dart apply begin wid=2258 vo=gpu-next vid=auto | L1676 |
| 22:53:19.619 | 2972 | dart | 2320 | dart property begin vo=null | L1677 |
| 22:53:19.620 | 2973 | dart | 2320 | dart property complete vo=null | L1678 |
| 22:53:19.620 | 2973 | dart | 2320 | dart authorize begin wid=2258 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1679 |
| 22:53:19.621 | 2974 | java | 2320 | mono=415619996 tid=2320 thr=main java authorize enter handle=498743565392 generation=2 viewId=1 surfaceGeneration=2 wid=2258 ownerTokenPresent=true | L1680 |
| 22:53:19.621 | 2974 | java | 2320 | mono=415619997 tid=2320 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-1577103693296012 libraryLoaded=true | L1681 |
| 22:53:19.621 | 2974 | native | 2320 | mono=415619997 tid=2320 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=18445166970016255604 req_generation=2 | L1682 |
| 22:53:19.621 | 2974 | native | 2320 | mono=415619997 tid=2320 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=18445166970016255604 req_generation=2 resources_ready=1 | L1683 |
| 22:53:19.621 | 2974 | native | 2320 | mono=415619997 tid=2320 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=18445166970016255604 generation=2 rc=0 | L1685 |
| 22:53:19.621 | 2974 | java | 2320 | mono=415619997 tid=2320 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-1577103693296012 | L1686 |
| 22:53:19.621 | 2974 | java | 2320 | mono=415619997 tid=2320 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=2258 | L1687 |
| 22:53:19.622 | 2975 | dart | 2320 | dart authorize result epoch=2 wid=2258 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1688 |
| 22:53:19.622 | 2975 | dart | 2320 | dart property begin android-surface-size=2672x1336 | L1689 |
| 22:53:19.623 | 2976 | dart | 2320 | dart property complete android-surface-size=2672x1336 | L1690 |
| 22:53:19.623 | 2976 | dart | 2320 | dart property begin wid=2258 | L1691 |
| 22:53:19.626 | 2979 | dart | 2320 | dart property complete wid=2258 | L1692 |
| 22:53:19.626 | 2979 | dart | 2320 | dart property begin vo=gpu-next | L1693 |
| 22:53:19.639 | 2992 | mpv | 2320 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1706 |
| 22:53:19.657 | 3010 | dart | 2320 | dart property complete vo=gpu-next | L1716 |
| 22:53:19.657 | 3010 | dart | 2320 | dart property begin vid=auto | L1717 |
| 22:53:19.679 | 3032 | native | 2583 | mono=415620054 tid=2583 egl_ctx=0x7418d9e780 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=18445166970016255604 generation=2  | L1723 |
| 22:53:19.679 | 3032 | native | 2583 | mono=415620054 tid=2583 egl_ctx=0x7418d9e780 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=18445166970016255604 generation=2 ready=1 | L1724 |
| 22:53:19.679 | 3032 | native | 2583 | mono=415620054 tid=2583 egl_ctx=0x7418d9e780 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=18445166970016255604 generation=2  | L1725 |
| 22:53:19.679 | 3032 | mpv | 2320 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1726 |
| 22:53:19.680 | 3033 | native | 2583 | mono=415620056 tid=2583 egl_ctx=0x7418d9e780 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=18445166970016255604 generation=2 result=ok window=0x74180b6e10 | L1728 |
| 22:53:19.683 | 3036 | codec | 2355 | ACodec  : Now uninitialized | L1738 |
| 22:53:19.700 | 3053 | codec | 2609 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1752 |
| 22:53:19.714 | 3067 | codec | 2609 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1769 |
| 22:53:19.722 | 3075 | codec | 2609 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1771 |
| 22:53:19.727 | 3080 | codec | 2609 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1772 |
| 22:53:19.728 | 3081 | codec | 2609 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1773 |
| 22:53:19.730 | 3083 | dart | 2320 | dart property complete vid=auto | L1774 |
| 22:53:19.730 | 3083 | dart | 2320 | dart apply complete wid=2258 | L1775 |
| 22:53:19.730 | 3083 | dart | 2320 | dart bind complete wid=2258 surfaceGeneration=2 | L1776 |
| 22:53:19.730 | 3083 | dart | 2320 | dart bind lock released wid=2258 surfaceGeneration=2 | L1778 |
| 22:53:19.761 | 3114 | codec | 2609 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1781 |
| 22:53:19.767 | 3120 | codec | 2609 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1783 |
| 22:53:19.860 | 3213 | codec | 2609 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1784 |
| 22:53:19.911 | 3264 | dart-videoparams | 2320 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1789 |
| 22:53:19.913 | 3266 | dart | 2320 | dart size property complete android-surface-size=1440x720 | L1791 |
| 22:53:19.942 | 3295 | dart | 2320 | dart size property complete android-surface-size=2672x1336 | L1798 |
| 22:53:19.978 | 3331 | java-log | 2320 | PlatformVideoView: surfaceChanged: handle=498743565392, format=43, width=2672, height=1336, wid=2258 | L1809 |
| 22:53:40.666 | 24019 | host-cmd |  | pid_after pid_before=2320 pid_after=2320 |  |
| 22:53:41.325 | 24678 | host-cmd |  | full_dump lines=    1896 |  |
| 22:53:41.586 | 24939 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 22:53:41.787 | 25140 | host-cmd |  | round_end |  |
