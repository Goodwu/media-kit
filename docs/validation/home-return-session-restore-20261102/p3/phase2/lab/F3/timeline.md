# Timeline F3

App PID filter: 2807 (ActivityManager am_pause/resume lines kept from system_server).

Source: `F3/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 22:54:10.504 | 0 | L0 |
| home_sent(host probe after cmd returned) | 22:54:11.956 | 1452 | L0 |
| am_pause_lab | 22:54:11.045 | 541 | L1334 |
| java_surfaceDestroyed_enter | 22:54:11.264 | 760 | L1403 |
| java_send_SurfaceDestroyed | 22:54:11.267 | 763 | L1405 |
| dart_event_SurfaceDestroyed | 22:54:11.269 | 765 | L1406 |
| dart_detach_lock_acquired | 22:54:11.269 | 765 | L1410 |
| dart_detach_vo_null_begin | 22:54:11.270 | 766 | L1414 |
| native_shutdown_enter | 22:54:11.365 | 861 | L1462 |
| native_shutdown_exit | 22:54:11.365 | 861 | L1464 |
| dart_detach_vo_null_ack | 22:54:11.483 | 979 | L1495 |
| dart_detach_wid0_ack | 22:54:12.511 | 2007 | L1693 |
| dart_detach_apply_complete | 22:54:13.425 | 2921 | L1722 |
| dart_detach_lock_released | 22:54:13.431 | 2927 | L1730 |
| return_sent | 22:54:12.302 | 1798 | L0 |
| am_resume_lab | 22:54:11.804 | 1300 | L1559 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | 22:54:13.436 | 2932 | L1736 |
| java_surfaceCreated_enter | 22:54:11.890 | 1386 | L1573 |
| java_send_SurfaceAvailable | 22:54:11.893 | 1389 | L1590 |
| dart_event_SurfaceAvailable | 22:54:11.893 | 1389 | L1591 |
| dart_bind_requested | 22:54:11.893 | 1389 | L1592 |
| dart_bind_lock_acquired | 22:54:13.430 | 2926 | L1728 |
| dart_bind_vo_gpu_next_begin | 22:54:13.445 | 2941 | L1748 |
| native_ensure_init_exit | 22:54:13.493 | 2989 | L1779 |
| native_create_exit | 22:54:13.495 | 2991 | L1783 |
| mpv_egl_window_surface | 22:54:13.453 | 2949 | L1761 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 22:54:13.574 | 3070 | L1834 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 525 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 118 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 2060 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 2128 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 101 |
| dart_vo_null_begin -> shutdown_enter (ms) | 95 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 1540 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | -1 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 1538 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 760 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -412 |

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
| 22:53:42.147 | -28357 | host-cmd |  | round_begin mode=fast pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key= |  |
| 22:53:42.526 | -27978 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 22:53:44.288 | -26216 | host-cmd |  | force_stop pid_after= |  |
| 22:53:44.776 | -25728 | host-cmd |  | logcat_cleared per-buffer |  |
| 22:53:45.442 | -25062 | host-cmd |  | am_start_fresh pid=2807 |  |
| 22:53:49.976 | -20528 | java | 2807 | mono=415650352 tid=2807 thr=main java factory.create enter handle=498853791824 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L433 |
| 22:53:49.977 | -20527 | java | 2807 | mono=415650353 tid=2807 thr=main java factory.create view constructed handle=498853791824 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L434 |
| 22:53:49.977 | -20527 | java | 2807 | mono=415650353 tid=2807 thr=main java setLgExperimentOwner enter handle=498853791824 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L435 |
| 22:53:49.978 | -20526 | java | 2807 | mono=415650353 tid=2807 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=-1725104245035745346 libraryLoaded=false | L436 |
| 22:53:49.978 | -20526 | native | 2807 | mono=415650354 tid=2807 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=16721639828673806270 req_generation=1 | L437 |
| 22:53:49.979 | -20525 | native | 2807 | mono=415650355 tid=2807 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=16721639828673806270 req_generation=1 resources_ready=1 | L439 |
| 22:53:49.979 | -20525 | native | 2807 | mono=415650355 tid=2807 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=16721639828673806270 generation=1 rc=0 | L441 |
| 22:53:49.980 | -20524 | java | 2807 | mono=415650355 tid=2807 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=-1725104245035745346 | L442 |
| 22:53:49.980 | -20524 | java | 2807 | mono=415650355 tid=2807 thr=main java setLgExperimentOwner exit handle=498853791824 viewId=0 ownerGeneration=1 ensureInitialized=ok | L443 |
| 22:53:49.980 | -20524 | java | 2807 | mono=415650356 tid=2807 thr=main java factory.create setLgExperimentOwner returned handle=498853791824 viewId=0 | L444 |
| 22:53:49.980 | -20524 | java | 2807 | mono=415650356 tid=2807 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498853791824 viewId=0 ownerGeneration=1 creationSerial=1 | L445 |
| 22:53:49.981 | -20523 | java | 2807 | mono=415650357 tid=2807 thr=main java factory.create exit handle=498853791824 viewId=0 | L447 |
| 22:53:50.019 | -20485 | java-log | 2807 | PlatformVideoView: surfaceCreated: handle=498853791824, width=668, height=360, viewIdentity=235825235 | L448 |
| 22:53:50.019 | -20485 | java | 2807 | mono=415650395 tid=2807 thr=main java surfaceCreated enter handle=498853791824 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L449 |
| 22:53:50.027 | -20477 | java-log | 2807 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L451 |
| 22:53:50.027 | -20477 | java | 2807 | mono=415650403 tid=2807 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498853791824 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L452 |
| 22:53:50.027 | -20477 | java | 2807 | mono=415650403 tid=2807 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498853791824 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L453 |
| 22:53:50.028 | -20476 | java | 2807 | mono=415650404 tid=2807 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498853791824 viewId=0 surfaceGeneration=1 wid=2099350 | L458 |
| 22:53:50.029 | -20475 | java | 2807 | mono=415650404 tid=2807 thr=main java surfaceCreated exit handle=498853791824 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L459 |
| 22:53:50.032 | -20472 | host-cmd |  | tap_open x=1440 y=720 |  |
| 22:53:50.978 | -19526 | java | 2807 | mono=415651354 tid=2807 thr=main java factory.create enter handle=498853791824 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L837 |
| 22:53:50.978 | -19526 | java | 2807 | mono=415651354 tid=2807 thr=main java factory.create view constructed handle=498853791824 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L839 |
| 22:53:50.978 | -19526 | java | 2807 | mono=415651354 tid=2807 thr=main java setLgExperimentOwner enter handle=498853791824 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L840 |
| 22:53:50.978 | -19526 | java | 2807 | mono=415651354 tid=2807 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-1725104245035745346 libraryLoaded=true | L841 |
| 22:53:50.978 | -19526 | native | 2807 | mono=415651354 tid=2807 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=16721639828673806270 generation=1 req_owner_key=16721639828673806270 req_generation=2 | L842 |
| 22:53:50.978 | -19526 | native | 2807 | mono=415651354 tid=2807 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=16721639828673806270 generation=1 req_owner_key=16721639828673806270 req_generation=2 resources_ready=1 | L843 |
| 22:53:50.979 | -19525 | native | 2807 | mono=415651354 tid=2807 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=16721639828673806270 generation=2 rc=0 | L845 |
| 22:53:50.979 | -19525 | java | 2807 | mono=415651354 tid=2807 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-1725104245035745346 | L846 |
| 22:53:50.979 | -19525 | java | 2807 | mono=415651354 tid=2807 thr=main java setLgExperimentOwner exit handle=498853791824 viewId=1 ownerGeneration=2 ensureInitialized=ok | L847 |
| 22:53:50.979 | -19525 | java | 2807 | mono=415651354 tid=2807 thr=main java factory.create setLgExperimentOwner returned handle=498853791824 viewId=1 | L848 |
| 22:53:50.979 | -19525 | java | 2807 | mono=415651354 tid=2807 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498853791824 viewId=1 ownerGeneration=2 creationSerial=2 | L849 |
| 22:53:50.979 | -19525 | java | 2807 | mono=415651355 tid=2807 thr=main java factory.create exit handle=498853791824 viewId=1 | L851 |
| 22:53:51.016 | -19488 | java-log | 2807 | PlatformVideoView: surfaceCreated: handle=498853791824, width=668, height=360, viewIdentity=218943113 | L852 |
| 22:53:51.016 | -19488 | java | 2807 | mono=415651392 tid=2807 thr=main java surfaceCreated enter handle=498853791824 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L853 |
| 22:53:51.022 | -19482 | java-log | 2807 | PlatformVideoView: surfaceCreated initial dataspace: handle=498853791824, transfer=pq, applied=true | L866 |
| 22:53:51.022 | -19482 | java-log | 2807 | PlatformVideoView: surfaceCreated: created new wid=2186 | L868 |
| 22:53:51.022 | -19482 | java | 2807 | mono=415651398 tid=2807 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498853791824 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=2186 | L869 |
| 22:53:51.022 | -19482 | java | 2807 | mono=415651398 tid=2807 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498853791824 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2186 | L870 |
| 22:53:51.023 | -19481 | java | 2807 | mono=415651399 tid=2807 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498853791824 viewId=1 surfaceGeneration=1 wid=2186 | L875 |
| 22:53:51.023 | -19481 | java | 2807 | mono=415651399 tid=2807 thr=main java surfaceCreated exit handle=498853791824 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2186 | L876 |
| 22:53:51.080 | -19424 | java | 2807 | mono=415651456 tid=2807 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-1725104245035745346 libraryLoaded=true | L883 |
| 22:53:51.080 | -19424 | native | 2807 | mono=415651456 tid=2807 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=16721639828673806270 generation=2 req_owner_key=16721639828673806270 req_generation=2 | L884 |
| 22:53:51.080 | -19424 | native | 2807 | mono=415651456 tid=2807 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=16721639828673806270 generation=2 req_owner_key=16721639828673806270 req_generation=2 resources_ready=1 | L885 |
| 22:53:51.080 | -19424 | native | 2807 | mono=415651456 tid=2807 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=16721639828673806270 generation=2 rc=0 | L887 |
| 22:53:51.080 | -19424 | java | 2807 | mono=415651456 tid=2807 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-1725104245035745346 | L888 |
| 22:53:51.221 | -19283 | native | 2890 | mono=415651597 tid=2890 egl_ctx=0x74188ecc00 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=16721639828673806270 generation=2  | L948 |
| 22:53:51.221 | -19283 | native | 2890 | mono=415651597 tid=2890 egl_ctx=0x74188ecc00 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=16721639828673806270 generation=2 ready=1 | L949 |
| 22:53:51.221 | -19283 | native | 2890 | mono=415651597 tid=2890 egl_ctx=0x74188ecc00 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=16721639828673806270 generation=2  | L950 |
| 22:53:51.223 | -19281 | native | 2890 | mono=415651598 tid=2890 egl_ctx=0x74188ecc00 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=16721639828673806270 generation=2 result=ok window=0x74185e2010 | L952 |
| 22:54:10.246 | -258 | host-cmd |  | interim_dump lines=    1310 |  |
| 22:54:10.415 | -89 | host-cmd |  | pid_before pid=2807 |  |
| 22:54:10.504 | 0 | host-cmd |  | home_send_begin cmd=adb shell: am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n com.example.media_kit_hdr_lab/.MainActivity --activity-no-animation |  |
| 22:54:11.045 | 541 | activity | 2535 | am_pause_activity: [0,22078653,com.example.media_kit_hdr_lab/.MainActivity] | L1334 |
| 22:54:11.047 | 543 | activity | 2807 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1335 |
| 22:54:11.159 | 655 | activity | 2535 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1360 |
| 22:54:11.263 | 759 | java-log | 2807 | PlatformVideoView: surfaceDestroyed: handle=498853791824, wid=2186 | L1402 |
| 22:54:11.264 | 760 | java | 2807 | mono=415671639 tid=2807 thr=main java surfaceDestroyed enter handle=498853791824 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2186 disposed=false | L1403 |
| 22:54:11.266 | 762 | java | 2807 | mono=415671642 tid=2807 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498853791824 viewId=1 surfaceGeneration=1 wid=2186 | L1404 |
| 22:54:11.267 | 763 | java | 2807 | mono=415671643 tid=2807 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498853791824 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2186 | L1405 |
| 22:54:11.269 | 765 | dart | 2807 | dart event SurfaceDestroyed handle=498853791824 wid=2186 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=2186 boundSurfaceGeneration=1 | L1406 |
| 22:54:11.269 | 765 | dart | 2807 | dart detach requested wid=2186 surfaceGeneration=1 generation=2 viewId=1 | L1407 |
| 22:54:11.269 | 765 | dart | 2807 | dart detach lock acquired wid=2186 surfaceGeneration=1 generation=2 viewId=1 boundWid=2186 boundSurfaceGeneration=1 | L1410 |
| 22:54:11.270 | 766 | dart | 2807 | dart detach decision wid=2186 isCurrentOutput=true isInFlightOutput=false | L1412 |
| 22:54:11.270 | 766 | dart | 2807 | dart apply begin wid=0 vo=null vid=no | L1413 |
| 22:54:11.270 | 766 | dart | 2807 | dart property begin vo=null | L1414 |
| 22:54:11.270 | 766 | java | 2807 | mono=415671646 tid=2807 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498853791824 viewId=1 surfaceGeneration=1 wid=2186 | L1415 |
| 22:54:11.271 | 767 | java | 2807 | mono=415671646 tid=2807 thr=main java surfaceDestroyed exit handle=498853791824 viewId=1 sentEvent=true wid=0 | L1416 |
| 22:54:11.284 | 780 | codec | 2896 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 9/16 output). | L1423 |
| 22:54:11.285 | 781 | codec | 2896 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1424 |
| 22:54:11.287 | 783 | codec | 2896 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1425 |
| 22:54:11.311 | 807 | codec | 2896 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1431 |
| 22:54:11.326 | 822 | codec | 2896 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1435 |
| 22:54:11.326 | 822 | codec | 2896 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1436 |
| 22:54:11.344 | 840 | activity | 2807 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1447 |
| 22:54:11.351 | 847 | codec | 2896 | ACodec  : Now uninitialized | L1453 |
| 22:54:11.365 | 861 | native | 2890 | mono=415671740 tid=2890 egl_ctx=0x74188ecc00 native mkst_shutdown enter initialized=1 window_active=1 owner_key=16721639828673806270 generation=2  | L1462 |
| 22:54:11.365 | 861 | native | 2890 | mono=415671741 tid=2890 egl_ctx=0x74188ecc00 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=587 latched=587 | L1464 |
| 22:54:11.483 | 979 | dart | 2807 | dart property complete vo=null | L1495 |
| 22:54:11.483 | 979 | dart | 2807 | dart property begin android-surface-size=2672x1336 | L1496 |
| 22:54:11.795 | 1291 | activity | 2534 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1547 |
| 22:54:11.804 | 1300 | activity | 19183 | am_resume_activity: [0,22078653,1044,com.example.media_kit_hdr_lab/.MainActivity] | L1559 |
| 22:54:11.830 | 1326 | activity | 2807 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1567 |
| 22:54:11.890 | 1386 | java-log | 2807 | PlatformVideoView: surfaceCreated: handle=498853791824, width=668, height=360, viewIdentity=218943113 | L1572 |
| 22:54:11.890 | 1386 | java | 2807 | mono=415672266 tid=2807 thr=main java surfaceCreated enter handle=498853791824 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1573 |
| 22:54:11.893 | 1389 | java-log | 2807 | PlatformVideoView: surfaceCreated initial dataspace: handle=498853791824, transfer=pq, applied=true | L1586 |
| 22:54:11.893 | 1389 | java-log | 2807 | PlatformVideoView: surfaceCreated: created new wid=2258 | L1588 |
| 22:54:11.893 | 1389 | java | 2807 | mono=415672269 tid=2807 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498853791824 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2258 | L1589 |
| 22:54:11.893 | 1389 | java | 2807 | mono=415672269 tid=2807 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498853791824 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2258 | L1590 |
| 22:54:11.893 | 1389 | dart | 2807 | dart event SurfaceAvailable handle=498853791824 wid=2258 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1591 |
| 22:54:11.893 | 1389 | dart | 2807 | dart bind requested wid=2258 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1592 |
| 22:54:11.894 | 1390 | java | 2807 | mono=415672269 tid=2807 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498853791824 viewId=1 surfaceGeneration=2 wid=2258 | L1593 |
| 22:54:11.894 | 1390 | java | 2807 | mono=415672269 tid=2807 thr=main java surfaceCreated exit handle=498853791824 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2258 | L1594 |
| 22:54:11.894 | 1390 | java-log | 2807 | PlatformVideoView: surfaceChanged: handle=498853791824, format=43, width=2672, height=1336, wid=2258 | L1595 |
| 22:54:11.956 | 1452 | host-cmd |  | home_sent chained home+return shell returned |  |
| 22:54:12.118 | 1614 | dart | 2807 | dart property complete android-surface-size=2672x1336 | L1632 |
| 22:54:12.118 | 1614 | dart | 2807 | dart property begin wid=0 | L1633 |
| 22:54:12.165 | 1661 | host-cmd |  | return_send_begin note-only: return was chained in the same shell as home (method F, sleep 0) |  |
| 22:54:12.205 | 1701 | java-log | 2807 | PlatformVideoView: surfaceChanged: handle=498853791824, format=43, width=1440, height=720, wid=2258 | L1647 |
| 22:54:12.302 | 1798 | host-cmd |  | return_sent chained shell done |  |
| 22:54:12.397 | 1893 | java-log | 2807 | PlatformVideoView: surfaceChanged: handle=498853791824, format=43, width=2672, height=1336, wid=2258 | L1665 |
| 22:54:12.408 | 1904 | dart-videoparams | 2807 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1667 |
| 22:54:12.484 | 1980 | java-log | 2807 | PlatformVideoView: surfaceChanged: handle=498853791824, format=43, width=2672, height=1440, wid=2258 | L1691 |
| 22:54:12.511 | 2007 | dart | 2807 | dart property complete wid=0 | L1693 |
| 22:54:12.511 | 2007 | dart | 2807 | dart property begin vo=null | L1694 |
| 22:54:12.915 | 2411 | dart | 2807 | dart property complete vo=null | L1716 |
| 22:54:12.915 | 2411 | dart | 2807 | dart property begin vid=no | L1717 |
| 22:54:13.425 | 2921 | dart | 2807 | dart property complete vid=no | L1721 |
| 22:54:13.425 | 2921 | dart | 2807 | dart apply complete wid=0 | L1722 |
| 22:54:13.425 | 2921 | dart | 2807 | dart detach producer stopped wid=2186 | L1723 |
| 22:54:13.426 | 2922 | java-log | 2807 | PlatformVideoView: releaseSurface generation=1 wid=2186 result=released | L1725 |
| 22:54:13.430 | 2926 | dart | 2807 | dart detach reference released wid=2186 | L1727 |
| 22:54:13.430 | 2926 | dart | 2807 | dart bind lock acquired wid=2258 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1728 |
| 22:54:13.431 | 2927 | dart | 2807 | dart bind branch=rebind wid=2258 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1729 |
| 22:54:13.431 | 2927 | dart | 2807 | dart detach lock released wid=2186 surfaceGeneration=1 | L1730 |
| 22:54:13.431 | 2927 | dart | 2807 | dart apply begin wid=2258 vo=gpu-next vid=auto | L1731 |
| 22:54:13.431 | 2927 | dart | 2807 | dart property begin vo=null | L1732 |
| 22:54:13.433 | 2929 | dart | 2807 | dart property complete vo=null | L1733 |
| 22:54:13.433 | 2929 | dart | 2807 | dart authorize begin wid=2258 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1734 |
| 22:54:13.435 | 2931 | java | 2807 | mono=415673811 tid=2807 thr=main java authorize enter handle=498853791824 generation=2 viewId=1 surfaceGeneration=2 wid=2258 ownerTokenPresent=true | L1735 |
| 22:54:13.436 | 2932 | java | 2807 | mono=415673811 tid=2807 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-1725104245035745346 libraryLoaded=true | L1736 |
| 22:54:13.436 | 2932 | native | 2807 | mono=415673811 tid=2807 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=16721639828673806270 req_generation=2 | L1737 |
| 22:54:13.436 | 2932 | native | 2807 | mono=415673812 tid=2807 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=16721639828673806270 req_generation=2 resources_ready=1 | L1738 |
| 22:54:13.436 | 2932 | native | 2807 | mono=415673812 tid=2807 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=16721639828673806270 generation=2 rc=0 | L1740 |
| 22:54:13.436 | 2932 | java | 2807 | mono=415673812 tid=2807 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-1725104245035745346 | L1741 |
| 22:54:13.436 | 2932 | java | 2807 | mono=415673812 tid=2807 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=2258 | L1742 |
| 22:54:13.438 | 2934 | dart | 2807 | dart authorize result epoch=2 wid=2258 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1743 |
| 22:54:13.438 | 2934 | dart | 2807 | dart property begin android-surface-size=2672x1336 | L1744 |
| 22:54:13.439 | 2935 | dart | 2807 | dart property complete android-surface-size=2672x1336 | L1745 |
| 22:54:13.439 | 2935 | dart | 2807 | dart property begin wid=2258 | L1746 |
| 22:54:13.445 | 2941 | dart | 2807 | dart property complete wid=2258 | L1747 |
| 22:54:13.445 | 2941 | dart | 2807 | dart property begin vo=gpu-next | L1748 |
| 22:54:13.453 | 2949 | mpv | 2807 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1761 |
| 22:54:13.471 | 2967 | dart | 2807 | dart property complete vo=gpu-next | L1771 |
| 22:54:13.471 | 2967 | dart | 2807 | dart property begin vid=auto | L1772 |
| 22:54:13.493 | 2989 | native | 2993 | mono=415673869 tid=2993 egl_ctx=0x741da5c400 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=16721639828673806270 generation=2  | L1778 |
| 22:54:13.493 | 2989 | native | 2993 | mono=415673869 tid=2993 egl_ctx=0x741da5c400 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=16721639828673806270 generation=2 ready=1 | L1779 |
| 22:54:13.493 | 2989 | native | 2993 | mono=415673869 tid=2993 egl_ctx=0x741da5c400 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=16721639828673806270 generation=2  | L1780 |
| 22:54:13.493 | 2989 | mpv | 2807 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1781 |
| 22:54:13.495 | 2991 | native | 2993 | mono=415673870 tid=2993 egl_ctx=0x741da5c400 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=16721639828673806270 generation=2 result=ok window=0x742608f010 | L1783 |
| 22:54:13.497 | 2993 | codec | 2839 | ACodec  : Now uninitialized | L1786 |
| 22:54:13.519 | 3015 | codec | 2996 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1806 |
| 22:54:13.533 | 3029 | codec | 2996 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1826 |
| 22:54:13.565 | 3061 | codec | 2996 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1829 |
| 22:54:13.570 | 3066 | codec | 2996 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1830 |
| 22:54:13.570 | 3066 | codec | 2996 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1831 |
| 22:54:13.573 | 3069 | dart | 2807 | dart property complete vid=auto | L1832 |
| 22:54:13.574 | 3070 | dart | 2807 | dart apply complete wid=2258 | L1833 |
| 22:54:13.574 | 3070 | dart | 2807 | dart bind complete wid=2258 surfaceGeneration=2 | L1834 |
| 22:54:13.574 | 3070 | dart | 2807 | dart bind lock released wid=2258 surfaceGeneration=2 | L1836 |
| 22:54:13.600 | 3096 | codec | 2996 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1839 |
| 22:54:13.607 | 3103 | codec | 2996 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1841 |
| 22:54:13.700 | 3196 | codec | 2996 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1842 |
| 22:54:13.757 | 3253 | dart-videoparams | 2807 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1848 |
| 22:54:13.759 | 3255 | dart | 2807 | dart size property complete android-surface-size=1440x720 | L1850 |
| 22:54:13.781 | 3277 | dart | 2807 | dart size property complete android-surface-size=2672x1336 | L1856 |
| 22:54:13.807 | 3303 | java-log | 2807 | PlatformVideoView: surfaceChanged: handle=498853791824, format=43, width=2672, height=1336, wid=2258 | L1858 |
| 22:54:13.820 | 3316 | dart | 2807 | dart size property complete android-surface-size=2672x1336 | L1860 |
| 22:54:34.507 | 24003 | host-cmd |  | pid_after pid_before=2807 pid_after=2807 |  |
| 22:54:34.967 | 24463 | host-cmd |  | full_dump lines=    1942 |  |
| 22:54:35.127 | 24623 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 22:54:35.230 | 24726 | host-cmd |  | round_end |  |
