# Timeline N2

App PID filter: 1013 (ActivityManager am_pause/resume lines kept from system_server).

Source: `N2/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 22:49:23.530 | 0 | L0 |
| home_sent(host probe after cmd returned) | 22:49:24.746 | 1216 | L0 |
| am_pause_lab | 22:49:24.163 | 633 | L1340 |
| java_surfaceDestroyed_enter | 22:49:24.381 | 851 | L1391 |
| java_send_SurfaceDestroyed | 22:49:24.381 | 851 | L1393 |
| dart_event_SurfaceDestroyed | 22:49:24.382 | 852 | L1394 |
| dart_detach_lock_acquired | 22:49:24.382 | 852 | L1396 |
| dart_detach_vo_null_begin | 22:49:24.382 | 852 | L1399 |
| native_shutdown_enter | 22:49:24.485 | 955 | L1452 |
| native_shutdown_exit | 22:49:24.486 | 956 | L1454 |
| dart_detach_vo_null_ack | 22:49:24.558 | 1028 | L1471 |
| dart_detach_wid0_ack | 22:49:25.432 | 1902 | L1529 |
| dart_detach_apply_complete | 22:49:26.404 | 2874 | L1552 |
| dart_detach_lock_released | 22:49:26.411 | 2881 | L1560 |
| return_sent | 22:49:36.347 | 12817 | L0 |
| am_resume_lab | 22:49:36.187 | 12657 | L1669 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | 22:49:36.346 | 12816 | L1747 |
| java_surfaceCreated_enter | 22:49:36.268 | 12738 | L1692 |
| java_send_SurfaceAvailable | 22:49:36.277 | 12747 | L1711 |
| dart_event_SurfaceAvailable | 22:49:36.277 | 12747 | L1712 |
| dart_bind_requested | 22:49:36.277 | 12747 | L1713 |
| dart_bind_lock_acquired | 22:49:36.277 | 12747 | L1714 |
| dart_bind_vo_gpu_next_begin | 22:49:36.417 | 12887 | L1766 |
| native_ensure_init_exit | 22:49:36.455 | 12925 | L1809 |
| native_create_exit | 22:49:36.456 | 12926 | L1813 |
| mpv_egl_window_surface | 22:49:36.426 | 12896 | L1785 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 22:49:36.544 | 13014 | L1864 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 11782 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 72 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 1918 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 11969 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 105 |
| dart_vo_null_begin -> shutdown_enter (ms) | 103 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 9 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 9866 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | -9866 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 851 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -79 |

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
| 22:48:51.008 | -32522 | host-cmd |  | round_begin mode=normal pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key= |  |
| 22:48:51.948 | -31582 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 22:48:55.488 | -28042 | host-cmd |  | force_stop pid_after= |  |
| 22:48:57.148 | -26382 | host-cmd |  | logcat_cleared per-buffer |  |
| 22:48:58.282 | -25248 | host-cmd |  | am_start_fresh pid=1013 |  |
| 22:49:02.939 | -20591 | java | 1013 | mono=415363315 tid=1013 thr=main java factory.create enter handle=499362888784 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L458 |
| 22:49:02.942 | -20588 | java | 1013 | mono=415363318 tid=1013 thr=main java factory.create view constructed handle=499362888784 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L459 |
| 22:49:02.943 | -20587 | java | 1013 | mono=415363318 tid=1013 thr=main java setLgExperimentOwner enter handle=499362888784 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L460 |
| 22:49:02.944 | -20586 | java | 1013 | mono=415363319 tid=1013 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=3373717545738814617 libraryLoaded=false | L461 |
| 22:49:02.948 | -20582 | native | 1013 | mono=415363324 tid=1013 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=3373717545738814617 req_generation=1 | L462 |
| 22:49:02.956 | -20574 | native | 1013 | mono=415363332 tid=1013 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=3373717545738814617 req_generation=1 resources_ready=1 | L464 |
| 22:49:02.957 | -20573 | native | 1013 | mono=415363333 tid=1013 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=3373717545738814617 generation=1 rc=0 | L466 |
| 22:49:02.957 | -20573 | java | 1013 | mono=415363333 tid=1013 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=3373717545738814617 | L467 |
| 22:49:02.958 | -20572 | java | 1013 | mono=415363333 tid=1013 thr=main java setLgExperimentOwner exit handle=499362888784 viewId=0 ownerGeneration=1 ensureInitialized=ok | L468 |
| 22:49:02.958 | -20572 | java | 1013 | mono=415363334 tid=1013 thr=main java factory.create setLgExperimentOwner returned handle=499362888784 viewId=0 | L469 |
| 22:49:02.960 | -20570 | java | 1013 | mono=415363335 tid=1013 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=499362888784 viewId=0 ownerGeneration=1 creationSerial=1 | L470 |
| 22:49:02.963 | -20567 | java | 1013 | mono=415363339 tid=1013 thr=main java factory.create exit handle=499362888784 viewId=0 | L472 |
| 22:49:03.010 | -20520 | host-cmd |  | tap_open x=1440 y=720 |  |
| 22:49:03.038 | -20492 | java-log | 1013 | PlatformVideoView: surfaceCreated: handle=499362888784, width=668, height=360, viewIdentity=235825235 | L473 |
| 22:49:03.038 | -20492 | java | 1013 | mono=415363414 tid=1013 thr=main java surfaceCreated enter handle=499362888784 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L474 |
| 22:49:03.047 | -20483 | java-log | 1013 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L476 |
| 22:49:03.047 | -20483 | java | 1013 | mono=415363423 tid=1013 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499362888784 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L477 |
| 22:49:03.048 | -20482 | java | 1013 | mono=415363424 tid=1013 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499362888784 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L478 |
| 22:49:03.049 | -20481 | java | 1013 | mono=415363425 tid=1013 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499362888784 viewId=0 surfaceGeneration=1 wid=2099350 | L483 |
| 22:49:03.049 | -20481 | java | 1013 | mono=415363425 tid=1013 thr=main java surfaceCreated exit handle=499362888784 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L484 |
| 22:49:03.952 | -19578 | java | 1013 | mono=415364328 tid=1013 thr=main java factory.create enter handle=499362888784 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L862 |
| 22:49:03.953 | -19577 | java | 1013 | mono=415364328 tid=1013 thr=main java factory.create view constructed handle=499362888784 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L864 |
| 22:49:03.953 | -19577 | java | 1013 | mono=415364328 tid=1013 thr=main java setLgExperimentOwner enter handle=499362888784 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L865 |
| 22:49:03.953 | -19577 | java | 1013 | mono=415364328 tid=1013 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=3373717545738814617 libraryLoaded=true | L866 |
| 22:49:03.953 | -19577 | native | 1013 | mono=415364329 tid=1013 egl_ctx=0x0 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=3373717545738814617 generation=1 req_owner_key=3373717545738814617 req_generation=2 | L867 |
| 22:49:03.953 | -19577 | native | 1013 | mono=415364329 tid=1013 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=3373717545738814617 generation=1 req_owner_key=3373717545738814617 req_generation=2 resources_ready=1 | L868 |
| 22:49:03.953 | -19577 | native | 1013 | mono=415364329 tid=1013 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=3373717545738814617 generation=2 rc=0 | L870 |
| 22:49:03.953 | -19577 | java | 1013 | mono=415364329 tid=1013 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=3373717545738814617 | L871 |
| 22:49:03.953 | -19577 | java | 1013 | mono=415364329 tid=1013 thr=main java setLgExperimentOwner exit handle=499362888784 viewId=1 ownerGeneration=2 ensureInitialized=ok | L872 |
| 22:49:03.953 | -19577 | java | 1013 | mono=415364329 tid=1013 thr=main java factory.create setLgExperimentOwner returned handle=499362888784 viewId=1 | L873 |
| 22:49:03.953 | -19577 | java | 1013 | mono=415364329 tid=1013 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=499362888784 viewId=1 ownerGeneration=2 creationSerial=2 | L874 |
| 22:49:03.955 | -19575 | java | 1013 | mono=415364330 tid=1013 thr=main java factory.create exit handle=499362888784 viewId=1 | L876 |
| 22:49:04.005 | -19525 | java-log | 1013 | PlatformVideoView: surfaceCreated: handle=499362888784, width=668, height=360, viewIdentity=207085198 | L877 |
| 22:49:04.005 | -19525 | java | 1013 | mono=415364381 tid=1013 thr=main java surfaceCreated enter handle=499362888784 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L878 |
| 22:49:04.011 | -19519 | java-log | 1013 | PlatformVideoView: surfaceCreated initial dataspace: handle=499362888784, transfer=pq, applied=true | L891 |
| 22:49:04.012 | -19518 | java-log | 1013 | PlatformVideoView: surfaceCreated: created new wid=1050738 | L893 |
| 22:49:04.012 | -19518 | java | 1013 | mono=415364388 tid=1013 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499362888784 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=1050738 | L894 |
| 22:49:04.012 | -19518 | java | 1013 | mono=415364388 tid=1013 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499362888784 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050738 | L895 |
| 22:49:04.012 | -19518 | java | 1013 | mono=415364388 tid=1013 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499362888784 viewId=1 surfaceGeneration=1 wid=1050738 | L900 |
| 22:49:04.013 | -19517 | java | 1013 | mono=415364388 tid=1013 thr=main java surfaceCreated exit handle=499362888784 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050738 | L901 |
| 22:49:04.055 | -19475 | java | 1013 | mono=415364430 tid=1013 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=3373717545738814617 libraryLoaded=true | L908 |
| 22:49:04.055 | -19475 | native | 1013 | mono=415364430 tid=1013 egl_ctx=0x744b9ff280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=3373717545738814617 generation=2 req_owner_key=3373717545738814617 req_generation=2 | L909 |
| 22:49:04.055 | -19475 | native | 1013 | mono=415364430 tid=1013 egl_ctx=0x744b9ff280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=3373717545738814617 generation=2 req_owner_key=3373717545738814617 req_generation=2 resources_ready=1 | L910 |
| 22:49:04.055 | -19475 | native | 1013 | mono=415364430 tid=1013 egl_ctx=0x744b9ff280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=3373717545738814617 generation=2 rc=0 | L912 |
| 22:49:04.055 | -19475 | java | 1013 | mono=415364430 tid=1013 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=3373717545738814617 | L913 |
| 22:49:04.220 | -19310 | native | 1102 | mono=415364595 tid=1102 egl_ctx=0x742556fd80 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=3373717545738814617 generation=2  | L966 |
| 22:49:04.220 | -19310 | native | 1102 | mono=415364595 tid=1102 egl_ctx=0x742556fd80 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=3373717545738814617 generation=2 ready=1 | L967 |
| 22:49:04.220 | -19310 | native | 1102 | mono=415364595 tid=1102 egl_ctx=0x742556fd80 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=3373717545738814617 generation=2  | L968 |
| 22:49:04.224 | -19306 | native | 1102 | mono=415364600 tid=1102 egl_ctx=0x742556fd80 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=3373717545738814617 generation=2 result=ok window=0x742549e410 | L970 |
| 22:49:23.263 | -267 | host-cmd |  | interim_dump lines=    1282 |  |
| 22:49:23.444 | -86 | host-cmd |  | pid_before pid=1013 |  |
| 22:49:23.530 | 0 | host-cmd |  | home_send_begin |  |
| 22:49:24.163 | 633 | activity | 2062 | am_pause_activity: [0,188407700,com.example.media_kit_hdr_lab/.MainActivity] | L1340 |
| 22:49:24.165 | 635 | activity | 1013 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1341 |
| 22:49:24.299 | 769 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1364 |
| 22:49:24.381 | 851 | java-log | 1013 | PlatformVideoView: surfaceDestroyed: handle=499362888784, wid=1050738 | L1390 |
| 22:49:24.381 | 851 | java | 1013 | mono=415384757 tid=1013 thr=main java surfaceDestroyed enter handle=499362888784 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050738 disposed=false | L1391 |
| 22:49:24.381 | 851 | java | 1013 | mono=415384757 tid=1013 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=499362888784 viewId=1 surfaceGeneration=1 wid=1050738 | L1392 |
| 22:49:24.381 | 851 | java | 1013 | mono=415384757 tid=1013 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=499362888784 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050738 | L1393 |
| 22:49:24.382 | 852 | dart | 1013 | dart event SurfaceDestroyed handle=499362888784 wid=1050738 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=1050738 boundSurfaceGeneration=1 | L1394 |
| 22:49:24.382 | 852 | dart | 1013 | dart detach requested wid=1050738 surfaceGeneration=1 generation=2 viewId=1 | L1395 |
| 22:49:24.382 | 852 | dart | 1013 | dart detach lock acquired wid=1050738 surfaceGeneration=1 generation=2 viewId=1 boundWid=1050738 boundSurfaceGeneration=1 | L1396 |
| 22:49:24.382 | 852 | dart | 1013 | dart detach decision wid=1050738 isCurrentOutput=true isInFlightOutput=false | L1397 |
| 22:49:24.382 | 852 | dart | 1013 | dart apply begin wid=0 vo=null vid=no | L1398 |
| 22:49:24.382 | 852 | dart | 1013 | dart property begin vo=null | L1399 |
| 22:49:24.382 | 852 | java | 1013 | mono=415384758 tid=1013 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=499362888784 viewId=1 surfaceGeneration=1 wid=1050738 | L1400 |
| 22:49:24.382 | 852 | java | 1013 | mono=415384758 tid=1013 thr=main java surfaceDestroyed exit handle=499362888784 viewId=1 sentEvent=true wid=0 | L1401 |
| 22:49:24.396 | 866 | codec | 1109 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 3/4 input, 11/16 output). | L1402 |
| 22:49:24.401 | 871 | codec | 1109 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1403 |
| 22:49:24.408 | 878 | codec | 1109 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1405 |
| 22:49:24.410 | 880 | codec | 1109 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1406 |
| 22:49:24.430 | 900 | codec | 1109 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1417 |
| 22:49:24.430 | 900 | codec | 1109 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1418 |
| 22:49:24.436 | 906 | activity | 1013 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1420 |
| 22:49:24.459 | 929 | codec | 1109 | ACodec  : Now uninitialized | L1435 |
| 22:49:24.485 | 955 | native | 1102 | mono=415384861 tid=1102 egl_ctx=0x742556fd80 native mkst_shutdown enter initialized=1 window_active=1 owner_key=3373717545738814617 generation=2  | L1452 |
| 22:49:24.486 | 956 | native | 1102 | mono=415384861 tid=1102 egl_ctx=0x742556fd80 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=594 latched=594 | L1454 |
| 22:49:24.558 | 1028 | dart | 1013 | dart property complete vo=null | L1471 |
| 22:49:24.558 | 1028 | dart | 1013 | dart property begin android-surface-size=2672x1336 | L1472 |
| 22:49:24.746 | 1216 | host-cmd |  | home_sent |  |
| 22:49:24.953 | 1423 | dart | 1013 | dart property complete android-surface-size=2672x1336 | L1514 |
| 22:49:24.953 | 1423 | dart | 1013 | dart property begin wid=0 | L1515 |
| 22:49:24.955 | 1425 | dart-videoparams | 1013 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1516 |
| 22:49:25.432 | 1902 | dart | 1013 | dart property complete wid=0 | L1529 |
| 22:49:25.432 | 1902 | dart | 1013 | dart property begin vo=null | L1530 |
| 22:49:25.907 | 2377 | dart | 1013 | dart property complete vo=null | L1543 |
| 22:49:25.907 | 2377 | dart | 1013 | dart property begin vid=no | L1544 |
| 22:49:26.404 | 2874 | dart | 1013 | dart property complete vid=no | L1551 |
| 22:49:26.404 | 2874 | dart | 1013 | dart apply complete wid=0 | L1552 |
| 22:49:26.404 | 2874 | dart | 1013 | dart detach producer stopped wid=1050738 | L1553 |
| 22:49:26.406 | 2876 | java-log | 1013 | PlatformVideoView: releaseSurface generation=1 wid=1050738 result=released | L1555 |
| 22:49:26.411 | 2881 | dart | 1013 | dart detach reference released wid=1050738 | L1559 |
| 22:49:26.411 | 2881 | dart | 1013 | dart detach lock released wid=1050738 surfaceGeneration=1 | L1560 |
| 22:49:35.170 | 11640 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity |  |
| 22:49:36.103 | 12573 | activity | 19182 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1633 |
| 22:49:36.187 | 12657 | activity | 1738 | am_resume_activity: [0,188407700,1040,com.example.media_kit_hdr_lab/.MainActivity] | L1669 |
| 22:49:36.209 | 12679 | activity | 1013 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1674 |
| 22:49:36.268 | 12738 | java-log | 1013 | PlatformVideoView: surfaceCreated: handle=499362888784, width=668, height=360, viewIdentity=207085198 | L1691 |
| 22:49:36.268 | 12738 | java | 1013 | mono=415396643 tid=1013 thr=main java surfaceCreated enter handle=499362888784 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1692 |
| 22:49:36.276 | 12746 | java-log | 1013 | PlatformVideoView: surfaceCreated initial dataspace: handle=499362888784, transfer=pq, applied=true | L1707 |
| 22:49:36.276 | 12746 | java-log | 1013 | PlatformVideoView: surfaceCreated: created new wid=1986 | L1709 |
| 22:49:36.276 | 12746 | java | 1013 | mono=415396652 tid=1013 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499362888784 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=1986 | L1710 |
| 22:49:36.277 | 12747 | java | 1013 | mono=415396652 tid=1013 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499362888784 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=1986 | L1711 |
| 22:49:36.277 | 12747 | dart | 1013 | dart event SurfaceAvailable handle=499362888784 wid=1986 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1712 |
| 22:49:36.277 | 12747 | dart | 1013 | dart bind requested wid=1986 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1713 |
| 22:49:36.277 | 12747 | dart | 1013 | dart bind lock acquired wid=1986 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1714 |
| 22:49:36.277 | 12747 | dart | 1013 | dart bind branch=rebind wid=1986 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1715 |
| 22:49:36.277 | 12747 | java | 1013 | mono=415396653 tid=1013 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499362888784 viewId=1 surfaceGeneration=2 wid=1986 | L1716 |
| 22:49:36.277 | 12747 | java | 1013 | mono=415396653 tid=1013 thr=main java surfaceCreated exit handle=499362888784 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=1986 | L1717 |
| 22:49:36.278 | 12748 | java-log | 1013 | PlatformVideoView: surfaceChanged: handle=499362888784, format=43, width=2672, height=1336, wid=1986 | L1718 |
| 22:49:36.301 | 12771 | java-log | 1013 | PlatformVideoView: surfaceChanged: handle=499362888784, format=43, width=2672, height=1440, wid=1986 | L1725 |
| 22:49:36.305 | 12775 | dart | 1013 | dart apply begin wid=1986 vo=gpu-next vid=auto | L1726 |
| 22:49:36.305 | 12775 | dart | 1013 | dart property begin vo=null | L1727 |
| 22:49:36.315 | 12785 | dart | 1013 | dart property complete vo=null | L1732 |
| 22:49:36.315 | 12785 | dart | 1013 | dart authorize begin wid=1986 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1733 |
| 22:49:36.346 | 12816 | java | 1013 | mono=415396722 tid=1013 thr=main java authorize enter handle=499362888784 generation=2 viewId=1 surfaceGeneration=2 wid=1986 ownerTokenPresent=true | L1746 |
| 22:49:36.346 | 12816 | java | 1013 | mono=415396722 tid=1013 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=3373717545738814617 libraryLoaded=true | L1747 |
| 22:49:36.346 | 12816 | native | 1013 | mono=415396722 tid=1013 egl_ctx=0x744b9ff280 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=3373717545738814617 req_generation=2 | L1748 |
| 22:49:36.346 | 12816 | native | 1013 | mono=415396722 tid=1013 egl_ctx=0x744b9ff280 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=3373717545738814617 req_generation=2 resources_ready=1 | L1749 |
| 22:49:36.346 | 12816 | native | 1013 | mono=415396722 tid=1013 egl_ctx=0x744b9ff280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=3373717545738814617 generation=2 rc=0 | L1751 |
| 22:49:36.346 | 12816 | java | 1013 | mono=415396722 tid=1013 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=3373717545738814617 | L1752 |
| 22:49:36.346 | 12816 | java | 1013 | mono=415396722 tid=1013 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=1986 | L1753 |
| 22:49:36.347 | 12817 | host-cmd |  | return_sent |  |
| 22:49:36.351 | 12821 | dart | 1013 | dart authorize result epoch=2 wid=1986 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1754 |
| 22:49:36.351 | 12821 | dart | 1013 | dart property begin android-surface-size=2672x1336 | L1755 |
| 22:49:36.371 | 12841 | dart | 1013 | dart property complete android-surface-size=2672x1336 | L1758 |
| 22:49:36.371 | 12841 | dart | 1013 | dart property begin wid=1986 | L1759 |
| 22:49:36.417 | 12887 | dart | 1013 | dart property complete wid=1986 | L1765 |
| 22:49:36.417 | 12887 | dart | 1013 | dart property begin vo=gpu-next | L1766 |
| 22:49:36.426 | 12896 | mpv | 1013 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1785 |
| 22:49:36.439 | 12909 | dart | 1013 | dart property complete vo=gpu-next | L1795 |
| 22:49:36.439 | 12909 | dart | 1013 | dart property begin vid=auto | L1796 |
| 22:49:36.455 | 12925 | native | 1265 | mono=415396831 tid=1265 egl_ctx=0x742556fa80 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=3373717545738814617 generation=2  | L1808 |
| 22:49:36.455 | 12925 | native | 1265 | mono=415396831 tid=1265 egl_ctx=0x742556fa80 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=3373717545738814617 generation=2 ready=1 | L1809 |
| 22:49:36.455 | 12925 | native | 1265 | mono=415396831 tid=1265 egl_ctx=0x742556fa80 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=3373717545738814617 generation=2  | L1810 |
| 22:49:36.456 | 12926 | mpv | 1013 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1811 |
| 22:49:36.456 | 12926 | native | 1265 | mono=415396832 tid=1265 egl_ctx=0x742556fa80 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=3373717545738814617 generation=2 result=ok window=0x7419343a10 | L1813 |
| 22:49:36.459 | 12929 | codec | 1047 | ACodec  : Now uninitialized | L1816 |
| 22:49:36.475 | 12945 | codec | 1272 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1825 |
| 22:49:36.485 | 12955 | codec | 1272 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1849 |
| 22:49:36.530 | 13000 | codec | 1272 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1859 |
| 22:49:36.540 | 13010 | codec | 1272 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1860 |
| 22:49:36.541 | 13011 | codec | 1272 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1861 |
| 22:49:36.543 | 13013 | dart | 1013 | dart property complete vid=auto | L1862 |
| 22:49:36.544 | 13014 | dart | 1013 | dart apply complete wid=1986 | L1863 |
| 22:49:36.544 | 13014 | dart | 1013 | dart bind complete wid=1986 surfaceGeneration=2 | L1864 |
| 22:49:36.544 | 13014 | dart | 1013 | dart bind lock released wid=1986 surfaceGeneration=2 | L1865 |
| 22:49:36.545 | 13015 | dart-videoparams | 1013 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1866 |
| 22:49:36.580 | 13050 | codec | 1272 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1869 |
| 22:49:36.584 | 13054 | codec | 1272 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1871 |
| 22:49:36.649 | 13119 | codec | 1272 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1872 |
| 22:49:36.699 | 13169 | dart-videoparams | 1013 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1877 |
| 22:49:36.708 | 13178 | dart | 1013 | dart size property complete android-surface-size=2672x1336 | L1879 |
| 22:49:36.763 | 13233 | java-log | 1013 | PlatformVideoView: surfaceChanged: handle=499362888784, format=43, width=2672, height=1336, wid=1986 | L1880 |
| 22:49:58.668 | 35138 | host-cmd |  | pid_after pid_before=1013 pid_after=1013 |  |
| 22:49:59.155 | 35625 | host-cmd |  | full_dump lines=    1962 |  |
| 22:49:59.307 | 35777 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 22:49:59.426 | 35896 | host-cmd |  | round_end |  |
