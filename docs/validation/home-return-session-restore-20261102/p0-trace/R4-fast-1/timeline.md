# Timeline R4-fast-1

App PID filter: 26247 (ActivityManager am_pause/resume lines kept from system_server).

Source: `R4-fast-1/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 20:17:28.648 | 0 | L0 |
| home_sent(host probe after cmd returned) | 20:17:30.202 | 1554 | L0 |
| am_pause_lab | 20:17:29.213 | 565 | L1264 |
| java_surfaceDestroyed_enter | 20:17:29.480 | 832 | L1372 |
| java_send_SurfaceDestroyed | 20:17:29.481 | 833 | L1374 |
| dart_event_SurfaceDestroyed | 20:17:29.481 | 833 | L1375 |
| dart_detach_lock_acquired | 20:17:29.481 | 833 | L1377 |
| dart_detach_vo_null_begin | 20:17:29.481 | 833 | L1380 |
| native_shutdown_enter | 20:17:29.716 | 1068 | L1458 |
| native_shutdown_exit | 20:17:29.716 | 1068 | L1460 |
| dart_detach_vo_null_ack | 20:17:29.857 | 1209 | L1485 |
| dart_detach_wid0_ack | 20:17:31.001 | 2353 | L1706 |
| dart_detach_apply_complete | 20:17:32.042 | 3394 | L1724 |
| dart_detach_lock_released | 20:17:32.057 | 3409 | L1732 |
| return_sent | 20:17:30.456 | 1808 | L0 |
| am_resume_lab | 20:17:30.144 | 1496 | L1568 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | — | — | — |
| java_surfaceCreated_enter | 20:17:30.216 | 1568 | L1581 |
| java_send_SurfaceAvailable | 20:17:30.228 | 1580 | L1598 |
| dart_event_SurfaceAvailable | 20:17:30.229 | 1581 | L1599 |
| dart_bind_requested | 20:17:30.232 | 1584 | L1600 |
| dart_bind_lock_acquired | 20:17:32.056 | 3408 | L1730 |
| dart_bind_vo_gpu_next_begin | 20:17:32.067 | 3419 | L1740 |
| native_ensure_init_exit | 20:17:32.133 | 3485 | L1774 |
| native_create_exit | — | — | — |
| mpv_egl_window_surface | 20:17:32.080 | 3432 | L1757 |
| mpv_bridge_not_initialized | 20:17:32.134 | 3486 | L1776 |
| dart_bind_complete | 20:17:32.143 | 3495 | L1780 |
| first_videoparams_after_return | 20:17:32.632 | 3984 | L1813 |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 500 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 141 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 2326 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 2417 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 236 |
| dart_vo_null_begin -> shutdown_enter (ms) | 235 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 1840 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | -1 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 1828 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | 1 |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | 2416 |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 832 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -240 |

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
| 20:17:04.511 | -24137 | host-cmd |  | round_begin launch=fresh method=F sleep=0 pkg=com.example.media_kit_hdr_lab |  |
| 20:17:06.560 | -22088 | host-cmd |  | force_stop pid_after= |  |
| 20:17:06.723 | -21925 | host-cmd |  | logcat_cleared |  |
| 20:17:07.396 | -21252 | host-cmd |  | am_start_fresh pid=26247 |  |
| 20:17:11.941 | -16707 | java | 26247 | mono=406252316 tid=26247 thr=main java factory.create enter handle=498743506512 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L445 |
| 20:17:11.942 | -16706 | java | 26247 | mono=406252318 tid=26247 thr=main java factory.create view constructed handle=498743506512 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L446 |
| 20:17:11.942 | -16706 | java | 26247 | mono=406252318 tid=26247 thr=main java setLgExperimentOwner enter handle=498743506512 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L447 |
| 20:17:11.943 | -16705 | java | 26247 | mono=406252318 tid=26247 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=6372643666194613512 libraryLoaded=false | L448 |
| 20:17:11.944 | -16704 | native | 26247 | mono=406252320 tid=26247 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=6372643666194613512 req_generation=1 | L449 |
| 20:17:11.945 | -16703 | native | 26247 | mono=406252321 tid=26247 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=6372643666194613512 req_generation=1 resources_ready=1 | L451 |
| 20:17:11.945 | -16703 | native | 26247 | mono=406252321 tid=26247 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=6372643666194613512 generation=1 rc=0 | L453 |
| 20:17:11.945 | -16703 | java | 26247 | mono=406252321 tid=26247 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=6372643666194613512 | L454 |
| 20:17:11.946 | -16702 | java | 26247 | mono=406252321 tid=26247 thr=main java setLgExperimentOwner exit handle=498743506512 viewId=0 ownerGeneration=1 ensureInitialized=ok | L455 |
| 20:17:11.946 | -16702 | java | 26247 | mono=406252321 tid=26247 thr=main java factory.create setLgExperimentOwner returned handle=498743506512 viewId=0 | L456 |
| 20:17:11.946 | -16702 | java | 26247 | mono=406252322 tid=26247 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743506512 viewId=0 ownerGeneration=1 creationSerial=1 | L457 |
| 20:17:11.947 | -16701 | java | 26247 | mono=406252323 tid=26247 thr=main java factory.create exit handle=498743506512 viewId=0 | L459 |
| 20:17:11.993 | -16655 | java-log | 26247 | PlatformVideoView: surfaceCreated: handle=498743506512, width=668, height=360, viewIdentity=235825235 | L460 |
| 20:17:11.993 | -16655 | java | 26247 | mono=406252369 tid=26247 thr=main java surfaceCreated enter handle=498743506512 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L461 |
| 20:17:12.002 | -16646 | java-log | 26247 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L463 |
| 20:17:12.002 | -16646 | java | 26247 | mono=406252378 tid=26247 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743506512 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L464 |
| 20:17:12.002 | -16646 | java | 26247 | mono=406252378 tid=26247 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743506512 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L465 |
| 20:17:12.003 | -16645 | java | 26247 | mono=406252379 tid=26247 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743506512 viewId=0 surfaceGeneration=1 wid=2099350 | L470 |
| 20:17:12.003 | -16645 | java | 26247 | mono=406252379 tid=26247 thr=main java surfaceCreated exit handle=498743506512 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L471 |
| 20:17:12.024 | -16624 | host-cmd |  | tap_open x=1440 y=720 |  |
| 20:17:12.993 | -15655 | java | 26247 | mono=406253369 tid=26247 thr=main java factory.create enter handle=498743506512 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L850 |
| 20:17:12.993 | -15655 | java | 26247 | mono=406253369 tid=26247 thr=main java factory.create view constructed handle=498743506512 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L852 |
| 20:17:12.993 | -15655 | java | 26247 | mono=406253369 tid=26247 thr=main java setLgExperimentOwner enter handle=498743506512 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L853 |
| 20:17:12.993 | -15655 | java | 26247 | mono=406253369 tid=26247 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=6372643666194613512 libraryLoaded=true | L854 |
| 20:17:12.993 | -15655 | native | 26247 | mono=406253369 tid=26247 egl_ctx=0x744b9ff280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=6372643666194613512 generation=1 req_owner_key=6372643666194613512 req_generation=2 | L855 |
| 20:17:12.993 | -15655 | native | 26247 | mono=406253369 tid=26247 egl_ctx=0x744b9ff280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=6372643666194613512 generation=1 req_owner_key=6372643666194613512 req_generation=2 resources_ready=1 | L856 |
| 20:17:12.994 | -15654 | native | 26247 | mono=406253369 tid=26247 egl_ctx=0x744b9ff280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=6372643666194613512 generation=2 rc=0 | L858 |
| 20:17:12.994 | -15654 | java | 26247 | mono=406253369 tid=26247 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=6372643666194613512 | L859 |
| 20:17:12.994 | -15654 | java | 26247 | mono=406253369 tid=26247 thr=main java setLgExperimentOwner exit handle=498743506512 viewId=1 ownerGeneration=2 ensureInitialized=ok | L860 |
| 20:17:12.994 | -15654 | java | 26247 | mono=406253369 tid=26247 thr=main java factory.create setLgExperimentOwner returned handle=498743506512 viewId=1 | L861 |
| 20:17:12.994 | -15654 | java | 26247 | mono=406253369 tid=26247 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743506512 viewId=1 ownerGeneration=2 creationSerial=2 | L862 |
| 20:17:12.994 | -15654 | java | 26247 | mono=406253370 tid=26247 thr=main java factory.create exit handle=498743506512 viewId=1 | L864 |
| 20:17:13.037 | -15611 | java-log | 26247 | PlatformVideoView: surfaceCreated: handle=498743506512, width=668, height=360, viewIdentity=218943113 | L865 |
| 20:17:13.037 | -15611 | java | 26247 | mono=406253413 tid=26247 thr=main java surfaceCreated enter handle=498743506512 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L866 |
| 20:17:13.043 | -15605 | java-log | 26247 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743506512, transfer=pq, applied=true | L879 |
| 20:17:13.044 | -15604 | java-log | 26247 | PlatformVideoView: surfaceCreated: created new wid=1050746 | L881 |
| 20:17:13.044 | -15604 | java | 26247 | mono=406253419 tid=26247 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743506512 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=1050746 | L882 |
| 20:17:13.044 | -15604 | java | 26247 | mono=406253419 tid=26247 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743506512 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050746 | L883 |
| 20:17:13.044 | -15604 | java | 26247 | mono=406253420 tid=26247 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743506512 viewId=1 surfaceGeneration=1 wid=1050746 | L888 |
| 20:17:13.044 | -15604 | java | 26247 | mono=406253420 tid=26247 thr=main java surfaceCreated exit handle=498743506512 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050746 | L889 |
| 20:17:13.215 | -15433 | native | 26322 | mono=406253591 tid=26322 egl_ctx=0x7411dfdd00 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=6372643666194613512 generation=2  | L937 |
| 20:17:13.215 | -15433 | native | 26322 | mono=406253591 tid=26322 egl_ctx=0x7411dfdd00 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=6372643666194613512 generation=2 ready=1 | L938 |
| 20:17:13.215 | -15433 | native | 26322 | mono=406253591 tid=26322 egl_ctx=0x7411dfdd00 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=6372643666194613512 generation=2  | L939 |
| 20:17:13.217 | -15431 | native | 26322 | mono=406253593 tid=26322 egl_ctx=0x7411dfdd00 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=6372643666194613512 generation=2 result=ok window=0x7418541e10 | L941 |
| 20:17:28.262 | -386 | host-cmd |  | interim_dump lines=    1236 |  |
| 20:17:28.501 | -147 | host-cmd |  | pid_before pid=26247 |  |
| 20:17:28.648 | 0 | host-cmd |  | home_send_begin cmd=adb shell: am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n com.example.media_kit_hdr_lab/.MainActivity --activity-no-animation |  |
| 20:17:29.213 | 565 | activity | 2603 | am_pause_activity: [0,267653204,com.example.media_kit_hdr_lab/.MainActivity] | L1264 |
| 20:17:29.215 | 567 | activity | 26247 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1265 |
| 20:17:29.324 | 676 | activity | 2603 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1286 |
| 20:17:29.480 | 832 | java-log | 26247 | PlatformVideoView: surfaceDestroyed: handle=498743506512, wid=1050746 | L1371 |
| 20:17:29.480 | 832 | java | 26247 | mono=406269856 tid=26247 thr=main java surfaceDestroyed enter handle=498743506512 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050746 disposed=false | L1372 |
| 20:17:29.481 | 833 | java | 26247 | mono=406269856 tid=26247 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743506512 viewId=1 surfaceGeneration=1 wid=1050746 | L1373 |
| 20:17:29.481 | 833 | java | 26247 | mono=406269856 tid=26247 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743506512 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050746 | L1374 |
| 20:17:29.481 | 833 | dart | 26247 | dart event SurfaceDestroyed handle=498743506512 wid=1050746 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=1050746 boundSurfaceGeneration=1 | L1375 |
| 20:17:29.481 | 833 | dart | 26247 | dart detach requested wid=1050746 surfaceGeneration=1 generation=2 viewId=1 | L1376 |
| 20:17:29.481 | 833 | dart | 26247 | dart detach lock acquired wid=1050746 surfaceGeneration=1 generation=2 viewId=1 boundWid=1050746 boundSurfaceGeneration=1 | L1377 |
| 20:17:29.481 | 833 | dart | 26247 | dart detach decision wid=1050746 isCurrentOutput=true isInFlightOutput=false | L1378 |
| 20:17:29.481 | 833 | dart | 26247 | dart apply begin wid=0 vo=null vid=no | L1379 |
| 20:17:29.481 | 833 | dart | 26247 | dart property begin vo=null | L1380 |
| 20:17:29.484 | 836 | java | 26247 | mono=406269860 tid=26247 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743506512 viewId=1 surfaceGeneration=1 wid=1050746 | L1381 |
| 20:17:29.484 | 836 | java | 26247 | mono=406269860 tid=26247 thr=main java surfaceDestroyed exit handle=498743506512 viewId=1 sentEvent=true wid=0 | L1382 |
| 20:17:29.550 | 902 | activity | 26247 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1402 |
| 20:17:29.577 | 929 | codec | 26328 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 9/16 output). | L1417 |
| 20:17:29.577 | 929 | codec | 26328 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1418 |
| 20:17:29.580 | 932 | codec | 26328 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1419 |
| 20:17:29.597 | 949 | codec | 26328 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1429 |
| 20:17:29.623 | 975 | codec | 26328 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1434 |
| 20:17:29.623 | 975 | codec | 26328 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1435 |
| 20:17:29.650 | 1002 | codec | 26328 | ACodec  : Now uninitialized | L1449 |
| 20:17:29.716 | 1068 | native | 26322 | mono=406270091 tid=26322 egl_ctx=0x7411dfdd00 native mkst_shutdown enter initialized=1 window_active=1 owner_key=6372643666194613512 generation=2  | L1458 |
| 20:17:29.716 | 1068 | native | 26322 | mono=406270092 tid=26322 egl_ctx=0x7411dfdd00 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=473 latched=473 | L1460 |
| 20:17:29.857 | 1209 | dart | 26247 | dart property complete vo=null | L1485 |
| 20:17:29.858 | 1210 | dart | 26247 | dart property begin android-surface-size=2672x1336 | L1486 |
| 20:17:30.000 | 1352 | activity | 2595 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1533 |
| 20:17:30.144 | 1496 | activity | 2612 | am_resume_activity: [0,267653204,1034,com.example.media_kit_hdr_lab/.MainActivity] | L1568 |
| 20:17:30.171 | 1523 | activity | 26247 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1572 |
| 20:17:30.202 | 1554 | host-cmd |  | home_sent chained home+return shell returned |  |
| 20:17:30.216 | 1568 | java-log | 26247 | PlatformVideoView: surfaceCreated: handle=498743506512, width=668, height=360, viewIdentity=218943113 | L1580 |
| 20:17:30.216 | 1568 | java | 26247 | mono=406270592 tid=26247 thr=main java surfaceCreated enter handle=498743506512 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1581 |
| 20:17:30.228 | 1580 | java-log | 26247 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743506512, transfer=pq, applied=true | L1594 |
| 20:17:30.228 | 1580 | java-log | 26247 | PlatformVideoView: surfaceCreated: created new wid=2258 | L1596 |
| 20:17:30.228 | 1580 | java | 26247 | mono=406270604 tid=26247 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743506512 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2258 | L1597 |
| 20:17:30.228 | 1580 | java | 26247 | mono=406270604 tid=26247 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743506512 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2258 | L1598 |
| 20:17:30.229 | 1581 | dart | 26247 | dart event SurfaceAvailable handle=498743506512 wid=2258 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1599 |
| 20:17:30.232 | 1584 | dart | 26247 | dart bind requested wid=2258 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1600 |
| 20:17:30.232 | 1584 | java | 26247 | mono=406270608 tid=26247 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743506512 viewId=1 surfaceGeneration=2 wid=2258 | L1601 |
| 20:17:30.232 | 1584 | java | 26247 | mono=406270608 tid=26247 thr=main java surfaceCreated exit handle=498743506512 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2258 | L1602 |
| 20:17:30.233 | 1585 | java-log | 26247 | PlatformVideoView: surfaceChanged: handle=498743506512, format=43, width=2672, height=1336, wid=2258 | L1603 |
| 20:17:30.361 | 1713 | host-cmd |  | return_send_begin note-only: return was chained in the same shell as home (no separate adb round trip) |  |
| 20:17:30.425 | 1777 | dart | 26247 | dart property complete android-surface-size=2672x1336 | L1674 |
| 20:17:30.425 | 1777 | dart | 26247 | dart property begin wid=0 | L1675 |
| 20:17:30.440 | 1792 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1679 |
| 20:17:30.456 | 1808 | host-cmd |  | return_sent chained shell done |  |
| 20:17:30.483 | 1835 | java-log | 26247 | PlatformVideoView: surfaceChanged: handle=498743506512, format=43, width=2672, height=1440, wid=2258 | L1683 |
| 20:17:31.001 | 2353 | dart | 26247 | dart property complete wid=0 | L1706 |
| 20:17:31.001 | 2353 | dart | 26247 | dart property begin vo=null | L1707 |
| 20:17:31.462 | 2814 | dart | 26247 | dart property complete vo=null | L1721 |
| 20:17:31.463 | 2815 | dart | 26247 | dart property begin vid=no | L1722 |
| 20:17:32.042 | 3394 | dart | 26247 | dart property complete vid=no | L1723 |
| 20:17:32.042 | 3394 | dart | 26247 | dart apply complete wid=0 | L1724 |
| 20:17:32.042 | 3394 | dart | 26247 | dart detach producer stopped wid=1050746 | L1725 |
| 20:17:32.047 | 3399 | java-log | 26247 | PlatformVideoView: releaseSurface generation=1 wid=1050746 result=released | L1727 |
| 20:17:32.055 | 3407 | dart | 26247 | dart detach reference released wid=1050746 | L1729 |
| 20:17:32.056 | 3408 | dart | 26247 | dart bind lock acquired wid=2258 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1730 |
| 20:17:32.056 | 3408 | dart | 26247 | dart bind branch=rebind wid=2258 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1731 |
| 20:17:32.057 | 3409 | dart | 26247 | dart detach lock released wid=1050746 surfaceGeneration=1 | L1732 |
| 20:17:32.057 | 3409 | dart | 26247 | dart apply begin wid=2258 vo=gpu-next vid=auto | L1733 |
| 20:17:32.058 | 3410 | dart | 26247 | dart property begin vo=null | L1734 |
| 20:17:32.061 | 3413 | dart | 26247 | dart property complete vo=null | L1735 |
| 20:17:32.061 | 3413 | dart | 26247 | dart property begin android-surface-size=2672x1336 | L1736 |
| 20:17:32.063 | 3415 | dart | 26247 | dart property complete android-surface-size=2672x1336 | L1737 |
| 20:17:32.063 | 3415 | dart | 26247 | dart property begin wid=2258 | L1738 |
| 20:17:32.066 | 3418 | dart | 26247 | dart property complete wid=2258 | L1739 |
| 20:17:32.067 | 3419 | dart | 26247 | dart property begin vo=gpu-next | L1740 |
| 20:17:32.080 | 3432 | mpv | 26247 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1757 |
| 20:17:32.109 | 3461 | dart | 26247 | dart property complete vo=gpu-next | L1766 |
| 20:17:32.110 | 3462 | dart | 26247 | dart property begin vid=auto | L1767 |
| 20:17:32.133 | 3485 | native | 26412 | mono=406272509 tid=26412 egl_ctx=0x7407afe600 native mkst_ensure_init(lc_verify) enter initialized=0 window_active=0 owner_key=0 generation=0  | L1773 |
| 20:17:32.133 | 3485 | native | 26412 | mono=406272509 tid=26412 egl_ctx=0x7407afe600 native mkst_ensure_init(lc_verify) exit initialized=0 window_active=0 owner_key=0 generation=0 ready=0 | L1774 |
| 20:17:32.134 | 3486 | mpv | 26247 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1775 |
| 20:17:32.134 | 3486 | mpv | 26247 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: bridge not initialized (verify-only ensure_init; Java side owns init) | L1776 |
| 20:17:32.143 | 3495 | dart | 26247 | dart property complete vid=auto | L1778 |
| 20:17:32.143 | 3495 | dart | 26247 | dart apply complete wid=2258 | L1779 |
| 20:17:32.143 | 3495 | dart | 26247 | dart bind complete wid=2258 surfaceGeneration=2 | L1780 |
| 20:17:32.143 | 3495 | dart | 26247 | dart bind lock released wid=2258 surfaceGeneration=2 | L1781 |
| 20:17:32.522 | 3874 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1802 |
| 20:17:32.632 | 3984 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1813 |
| 20:17:32.707 | 4059 | java-log | 26247 | PlatformVideoView: surfaceChanged: handle=498743506512, format=43, width=2672, height=1336, wid=2258 | L1827 |
| 20:17:32.722 | 4074 | dart | 26247 | dart size property complete android-surface-size=2672x1336 | L1828 |
| 20:17:32.793 | 4145 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1829 |
| 20:17:33.028 | 4380 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1855 |
| 20:17:33.319 | 4671 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1856 |
| 20:17:33.470 | 4822 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1857 |
| 20:17:33.839 | 5191 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1858 |
| 20:17:34.158 | 5510 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1860 |
| 20:17:34.297 | 5649 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1861 |
| 20:17:34.644 | 5996 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1862 |
| 20:17:34.882 | 6234 | dart-videoparams | 26247 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1863 |
| 20:17:42.668 | 14020 | host-cmd |  | pid_after pid_before=26247 pid_after=26247 |  |
| 20:17:43.092 | 14444 | host-cmd |  | full_dump lines=    1892 |  |
| 20:17:43.208 | 14560 | host-cmd |  | round_end |  |
