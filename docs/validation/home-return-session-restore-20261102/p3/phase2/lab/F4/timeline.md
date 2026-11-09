# Timeline F4

App PID filter: 3225 (ActivityManager am_pause/resume lines kept from system_server).

Source: `F4/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 22:55:03.830 | 0 | L0 |
| home_sent(host probe after cmd returned) | 22:55:05.181 | 1351 | L0 |
| am_pause_lab | 22:55:04.355 | 525 | L1314 |
| java_surfaceDestroyed_enter | 22:55:04.567 | 737 | L1371 |
| java_send_SurfaceDestroyed | 22:55:04.567 | 737 | L1373 |
| dart_event_SurfaceDestroyed | 22:55:04.568 | 738 | L1374 |
| dart_detach_lock_acquired | 22:55:04.568 | 738 | L1376 |
| dart_detach_vo_null_begin | 22:55:04.568 | 738 | L1379 |
| native_shutdown_enter | 22:55:04.638 | 808 | L1413 |
| native_shutdown_exit | 22:55:04.652 | 822 | L1417 |
| dart_detach_vo_null_ack | 22:55:04.745 | 915 | L1450 |
| dart_detach_wid0_ack | 22:55:05.446 | 1616 | L1618 |
| dart_detach_apply_complete | 22:55:06.186 | 2356 | L1682 |
| dart_detach_lock_released | 22:55:06.188 | 2358 | L1690 |
| return_sent | 22:55:05.376 | 1546 | L0 |
| am_resume_lab | 22:55:05.085 | 1255 | L1539 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | 22:55:06.190 | 2360 | L1696 |
| java_surfaceCreated_enter | 22:55:05.142 | 1312 | L1544 |
| java_send_SurfaceAvailable | 22:55:05.194 | 1364 | L1575 |
| dart_event_SurfaceAvailable | 22:55:05.194 | 1364 | L1576 |
| dart_bind_requested | 22:55:05.194 | 1364 | L1577 |
| dart_bind_lock_acquired | 22:55:06.188 | 2358 | L1688 |
| dart_bind_vo_gpu_next_begin | 22:55:06.205 | 2375 | L1708 |
| native_ensure_init_exit | 22:55:06.249 | 2419 | L1739 |
| native_create_exit | 22:55:06.250 | 2420 | L1743 |
| mpv_egl_window_surface | 22:55:06.213 | 2383 | L1721 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 22:55:06.301 | 2471 | L1791 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 490 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 93 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 1534 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 1597 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 85 |
| dart_vo_null_begin -> shutdown_enter (ms) | 70 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 1046 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 0 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 994 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 737 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -234 |

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
| 22:54:35.448 | -28382 | host-cmd |  | round_begin mode=fast pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key= |  |
| 22:54:35.721 | -28109 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 22:54:37.573 | -26257 | host-cmd |  | force_stop pid_after= |  |
| 22:54:38.029 | -25801 | host-cmd |  | logcat_cleared per-buffer |  |
| 22:54:38.749 | -25081 | host-cmd |  | am_start_fresh pid=3225 |  |
| 22:54:43.363 | -20467 | host-cmd |  | tap_open x=1440 y=720 |  |
| 22:54:43.374 | -20456 | java | 3225 | mono=415703749 tid=3225 thr=main java factory.create enter handle=499362560080 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L434 |
| 22:54:43.375 | -20455 | java | 3225 | mono=415703751 tid=3225 thr=main java factory.create view constructed handle=499362560080 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L435 |
| 22:54:43.375 | -20455 | java | 3225 | mono=415703751 tid=3225 thr=main java setLgExperimentOwner enter handle=499362560080 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L436 |
| 22:54:43.375 | -20455 | java | 3225 | mono=415703751 tid=3225 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=-2618625001885470403 libraryLoaded=false | L437 |
| 22:54:43.376 | -20454 | native | 3225 | mono=415703752 tid=3225 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=15828119071824081213 req_generation=1 | L438 |
| 22:54:43.378 | -20452 | native | 3225 | mono=415703753 tid=3225 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=15828119071824081213 req_generation=1 resources_ready=1 | L440 |
| 22:54:43.378 | -20452 | native | 3225 | mono=415703754 tid=3225 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=15828119071824081213 generation=1 rc=0 | L442 |
| 22:54:43.378 | -20452 | java | 3225 | mono=415703754 tid=3225 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=-2618625001885470403 | L443 |
| 22:54:43.378 | -20452 | java | 3225 | mono=415703754 tid=3225 thr=main java setLgExperimentOwner exit handle=499362560080 viewId=0 ownerGeneration=1 ensureInitialized=ok | L444 |
| 22:54:43.378 | -20452 | java | 3225 | mono=415703754 tid=3225 thr=main java factory.create setLgExperimentOwner returned handle=499362560080 viewId=0 | L445 |
| 22:54:43.378 | -20452 | java | 3225 | mono=415703754 tid=3225 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=499362560080 viewId=0 ownerGeneration=1 creationSerial=1 | L446 |
| 22:54:43.379 | -20451 | java | 3225 | mono=415703755 tid=3225 thr=main java factory.create exit handle=499362560080 viewId=0 | L448 |
| 22:54:43.433 | -20397 | java-log | 3225 | PlatformVideoView: surfaceCreated: handle=499362560080, width=668, height=360, viewIdentity=235825235 | L449 |
| 22:54:43.433 | -20397 | java | 3225 | mono=415703809 tid=3225 thr=main java surfaceCreated enter handle=499362560080 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L450 |
| 22:54:43.441 | -20389 | java-log | 3225 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L452 |
| 22:54:43.441 | -20389 | java | 3225 | mono=415703817 tid=3225 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499362560080 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L453 |
| 22:54:43.442 | -20388 | java | 3225 | mono=415703818 tid=3225 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499362560080 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L454 |
| 22:54:43.444 | -20386 | java | 3225 | mono=415703820 tid=3225 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499362560080 viewId=0 surfaceGeneration=1 wid=2099350 | L459 |
| 22:54:43.444 | -20386 | java | 3225 | mono=415703820 tid=3225 thr=main java surfaceCreated exit handle=499362560080 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L460 |
| 22:54:44.393 | -19437 | java | 3225 | mono=415704769 tid=3225 thr=main java factory.create enter handle=499362560080 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L839 |
| 22:54:44.394 | -19436 | java | 3225 | mono=415704770 tid=3225 thr=main java factory.create view constructed handle=499362560080 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L841 |
| 22:54:44.395 | -19435 | java | 3225 | mono=415704770 tid=3225 thr=main java setLgExperimentOwner enter handle=499362560080 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L842 |
| 22:54:44.395 | -19435 | java | 3225 | mono=415704770 tid=3225 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-2618625001885470403 libraryLoaded=true | L843 |
| 22:54:44.395 | -19435 | native | 3225 | mono=415704770 tid=3225 egl_ctx=0x7424133280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=15828119071824081213 generation=1 req_owner_key=15828119071824081213 req_generation=2 | L844 |
| 22:54:44.395 | -19435 | native | 3225 | mono=415704771 tid=3225 egl_ctx=0x7424133280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=15828119071824081213 generation=1 req_owner_key=15828119071824081213 req_generation=2 resources_ready=1 | L845 |
| 22:54:44.395 | -19435 | native | 3225 | mono=415704771 tid=3225 egl_ctx=0x7424133280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=15828119071824081213 generation=2 rc=0 | L847 |
| 22:54:44.395 | -19435 | java | 3225 | mono=415704771 tid=3225 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-2618625001885470403 | L848 |
| 22:54:44.395 | -19435 | java | 3225 | mono=415704771 tid=3225 thr=main java setLgExperimentOwner exit handle=499362560080 viewId=1 ownerGeneration=2 ensureInitialized=ok | L849 |
| 22:54:44.395 | -19435 | java | 3225 | mono=415704771 tid=3225 thr=main java factory.create setLgExperimentOwner returned handle=499362560080 viewId=1 | L850 |
| 22:54:44.395 | -19435 | java | 3225 | mono=415704771 tid=3225 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=499362560080 viewId=1 ownerGeneration=2 creationSerial=2 | L851 |
| 22:54:44.396 | -19434 | java | 3225 | mono=415704772 tid=3225 thr=main java factory.create exit handle=499362560080 viewId=1 | L853 |
| 22:54:44.465 | -19365 | java-log | 3225 | PlatformVideoView: surfaceCreated: handle=499362560080, width=668, height=360, viewIdentity=207085198 | L854 |
| 22:54:44.465 | -19365 | java | 3225 | mono=415704840 tid=3225 thr=main java surfaceCreated enter handle=499362560080 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L855 |
| 22:54:44.469 | -19361 | java-log | 3225 | PlatformVideoView: surfaceCreated initial dataspace: handle=499362560080, transfer=pq, applied=true | L868 |
| 22:54:44.469 | -19361 | java-log | 3225 | PlatformVideoView: surfaceCreated: created new wid=2170 | L870 |
| 22:54:44.469 | -19361 | java | 3225 | mono=415704845 tid=3225 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499362560080 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=2170 | L871 |
| 22:54:44.469 | -19361 | java | 3225 | mono=415704845 tid=3225 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499362560080 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2170 | L872 |
| 22:54:44.470 | -19360 | java | 3225 | mono=415704846 tid=3225 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499362560080 viewId=1 surfaceGeneration=1 wid=2170 | L877 |
| 22:54:44.470 | -19360 | java | 3225 | mono=415704846 tid=3225 thr=main java surfaceCreated exit handle=499362560080 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2170 | L878 |
| 22:54:44.502 | -19328 | java | 3225 | mono=415704878 tid=3225 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-2618625001885470403 libraryLoaded=true | L885 |
| 22:54:44.502 | -19328 | native | 3225 | mono=415704878 tid=3225 egl_ctx=0x7424133280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=15828119071824081213 generation=2 req_owner_key=15828119071824081213 req_generation=2 | L886 |
| 22:54:44.502 | -19328 | native | 3225 | mono=415704878 tid=3225 egl_ctx=0x7424133280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=15828119071824081213 generation=2 req_owner_key=15828119071824081213 req_generation=2 resources_ready=1 | L887 |
| 22:54:44.502 | -19328 | native | 3225 | mono=415704878 tid=3225 egl_ctx=0x7424133280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=15828119071824081213 generation=2 rc=0 | L889 |
| 22:54:44.502 | -19328 | java | 3225 | mono=415704878 tid=3225 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-2618625001885470403 | L890 |
| 22:54:44.654 | -19176 | native | 3347 | mono=415705030 tid=3347 egl_ctx=0x741dbeb780 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=15828119071824081213 generation=2  | L948 |
| 22:54:44.655 | -19175 | native | 3347 | mono=415705030 tid=3347 egl_ctx=0x741dbeb780 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=15828119071824081213 generation=2 ready=1 | L949 |
| 22:54:44.655 | -19175 | native | 3347 | mono=415705030 tid=3347 egl_ctx=0x741dbeb780 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=15828119071824081213 generation=2  | L950 |
| 22:54:44.656 | -19174 | native | 3347 | mono=415705032 tid=3347 egl_ctx=0x741dbeb780 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=15828119071824081213 generation=2 result=ok window=0x74256f6210 | L952 |
| 22:55:03.588 | -242 | host-cmd |  | interim_dump lines=    1291 |  |
| 22:55:03.751 | -79 | host-cmd |  | pid_before pid=3225 |  |
| 22:55:03.830 | 0 | host-cmd |  | home_send_begin cmd=adb shell: am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n com.example.media_kit_hdr_lab/.MainActivity --activity-no-animation |  |
| 22:55:04.355 | 525 | activity | 18606 | am_pause_activity: [0,234312560,com.example.media_kit_hdr_lab/.MainActivity] | L1314 |
| 22:55:04.359 | 529 | activity | 3225 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1315 |
| 22:55:04.473 | 643 | activity | 18606 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1339 |
| 22:55:04.567 | 737 | java-log | 3225 | PlatformVideoView: surfaceDestroyed: handle=499362560080, wid=2170 | L1370 |
| 22:55:04.567 | 737 | java | 3225 | mono=415724943 tid=3225 thr=main java surfaceDestroyed enter handle=499362560080 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2170 disposed=false | L1371 |
| 22:55:04.567 | 737 | java | 3225 | mono=415724943 tid=3225 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=499362560080 viewId=1 surfaceGeneration=1 wid=2170 | L1372 |
| 22:55:04.567 | 737 | java | 3225 | mono=415724943 tid=3225 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=499362560080 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2170 | L1373 |
| 22:55:04.568 | 738 | dart | 3225 | dart event SurfaceDestroyed handle=499362560080 wid=2170 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=2170 boundSurfaceGeneration=1 | L1374 |
| 22:55:04.568 | 738 | dart | 3225 | dart detach requested wid=2170 surfaceGeneration=1 generation=2 viewId=1 | L1375 |
| 22:55:04.568 | 738 | dart | 3225 | dart detach lock acquired wid=2170 surfaceGeneration=1 generation=2 viewId=1 boundWid=2170 boundSurfaceGeneration=1 | L1376 |
| 22:55:04.568 | 738 | dart | 3225 | dart detach decision wid=2170 isCurrentOutput=true isInFlightOutput=false | L1377 |
| 22:55:04.568 | 738 | dart | 3225 | dart apply begin wid=0 vo=null vid=no | L1378 |
| 22:55:04.568 | 738 | dart | 3225 | dart property begin vo=null | L1379 |
| 22:55:04.568 | 738 | java | 3225 | mono=415724944 tid=3225 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=499362560080 viewId=1 surfaceGeneration=1 wid=2170 | L1380 |
| 22:55:04.568 | 738 | java | 3225 | mono=415724944 tid=3225 thr=main java surfaceDestroyed exit handle=499362560080 viewId=1 sentEvent=true wid=0 | L1381 |
| 22:55:04.572 | 742 | codec | 3362 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 11/16 output). | L1382 |
| 22:55:04.573 | 743 | codec | 3362 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1384 |
| 22:55:04.582 | 752 | codec | 3362 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1392 |
| 22:55:04.585 | 755 | codec | 3362 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1393 |
| 22:55:04.602 | 772 | codec | 3362 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1396 |
| 22:55:04.607 | 777 | codec | 3362 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1398 |
| 22:55:04.621 | 791 | codec | 3362 | ACodec  : Now uninitialized | L1407 |
| 22:55:04.638 | 808 | native | 3347 | mono=415725014 tid=3347 egl_ctx=0x741dbeb780 native mkst_shutdown enter initialized=1 window_active=1 owner_key=15828119071824081213 generation=2  | L1413 |
| 22:55:04.648 | 818 | activity | 3225 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1414 |
| 22:55:04.652 | 822 | native | 3347 | mono=415725028 tid=3347 egl_ctx=0x741dbeb780 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=584 latched=584 | L1417 |
| 22:55:04.745 | 915 | dart | 3225 | dart property complete vo=null | L1450 |
| 22:55:04.745 | 915 | dart | 3225 | dart property begin android-surface-size=2672x1336 | L1451 |
| 22:55:04.749 | 919 | dart | 3225 | dart property complete android-surface-size=2672x1336 | L1453 |
| 22:55:04.749 | 919 | dart | 3225 | dart property begin wid=0 | L1454 |
| 22:55:05.072 | 1242 | activity | 2615 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1525 |
| 22:55:05.085 | 1255 | activity | 2535 | am_resume_activity: [0,234312560,1045,com.example.media_kit_hdr_lab/.MainActivity] | L1539 |
| 22:55:05.100 | 1270 | activity | 3225 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1541 |
| 22:55:05.142 | 1312 | java-log | 3225 | PlatformVideoView: surfaceCreated: handle=499362560080, width=668, height=360, viewIdentity=207085198 | L1543 |
| 22:55:05.142 | 1312 | java | 3225 | mono=415725518 tid=3225 thr=main java surfaceCreated enter handle=499362560080 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1544 |
| 22:55:05.181 | 1351 | host-cmd |  | home_sent chained home+return shell returned |  |
| 22:55:05.193 | 1363 | java-log | 3225 | PlatformVideoView: surfaceCreated initial dataspace: handle=499362560080, transfer=pq, applied=true | L1571 |
| 22:55:05.194 | 1364 | java-log | 3225 | PlatformVideoView: surfaceCreated: created new wid=2258 | L1573 |
| 22:55:05.194 | 1364 | java | 3225 | mono=415725569 tid=3225 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499362560080 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2258 | L1574 |
| 22:55:05.194 | 1364 | java | 3225 | mono=415725570 tid=3225 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499362560080 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2258 | L1575 |
| 22:55:05.194 | 1364 | dart | 3225 | dart event SurfaceAvailable handle=499362560080 wid=2258 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1576 |
| 22:55:05.194 | 1364 | dart | 3225 | dart bind requested wid=2258 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1577 |
| 22:55:05.195 | 1365 | java | 3225 | mono=415725570 tid=3225 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499362560080 viewId=1 surfaceGeneration=2 wid=2258 | L1578 |
| 22:55:05.195 | 1365 | java | 3225 | mono=415725570 tid=3225 thr=main java surfaceCreated exit handle=499362560080 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2258 | L1579 |
| 22:55:05.195 | 1365 | java-log | 3225 | PlatformVideoView: surfaceChanged: handle=499362560080, format=43, width=2672, height=1336, wid=2258 | L1580 |
| 22:55:05.262 | 1432 | host-cmd |  | return_send_begin note-only: return was chained in the same shell as home (method F, sleep 0) |  |
| 22:55:05.365 | 1535 | java-log | 3225 | PlatformVideoView: surfaceChanged: handle=499362560080, format=43, width=1440, height=720, wid=2258 | L1606 |
| 22:55:05.376 | 1546 | host-cmd |  | return_sent chained shell done |  |
| 22:55:05.446 | 1616 | dart | 3225 | dart property complete wid=0 | L1618 |
| 22:55:05.446 | 1616 | dart | 3225 | dart property begin vo=null | L1619 |
| 22:55:05.496 | 1666 | java-log | 3225 | PlatformVideoView: surfaceChanged: handle=499362560080, format=43, width=1440, height=720, wid=2258 | L1628 |
| 22:55:05.673 | 1843 | java-log | 3225 | PlatformVideoView: surfaceChanged: handle=499362560080, format=43, width=2672, height=1336, wid=2258 | L1658 |
| 22:55:05.768 | 1938 | dart | 3225 | dart property complete vo=null | L1665 |
| 22:55:05.768 | 1938 | dart | 3225 | dart property begin vid=no | L1666 |
| 22:55:05.770 | 1940 | dart-videoparams | 3225 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1667 |
| 22:55:05.829 | 1999 | java-log | 3225 | PlatformVideoView: surfaceChanged: handle=499362560080, format=43, width=2672, height=1440, wid=2258 | L1668 |
| 22:55:06.186 | 2356 | dart | 3225 | dart property complete vid=no | L1681 |
| 22:55:06.186 | 2356 | dart | 3225 | dart apply complete wid=0 | L1682 |
| 22:55:06.186 | 2356 | dart | 3225 | dart detach producer stopped wid=2170 | L1683 |
| 22:55:06.187 | 2357 | java-log | 3225 | PlatformVideoView: releaseSurface generation=1 wid=2170 result=released | L1685 |
| 22:55:06.188 | 2358 | dart | 3225 | dart detach reference released wid=2170 | L1687 |
| 22:55:06.188 | 2358 | dart | 3225 | dart bind lock acquired wid=2258 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1688 |
| 22:55:06.188 | 2358 | dart | 3225 | dart bind branch=rebind wid=2258 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1689 |
| 22:55:06.188 | 2358 | dart | 3225 | dart detach lock released wid=2170 surfaceGeneration=1 | L1690 |
| 22:55:06.188 | 2358 | dart | 3225 | dart apply begin wid=2258 vo=gpu-next vid=auto | L1691 |
| 22:55:06.188 | 2358 | dart | 3225 | dart property begin vo=null | L1692 |
| 22:55:06.189 | 2359 | dart | 3225 | dart property complete vo=null | L1693 |
| 22:55:06.189 | 2359 | dart | 3225 | dart authorize begin wid=2258 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1694 |
| 22:55:06.190 | 2360 | java | 3225 | mono=415726565 tid=3225 thr=main java authorize enter handle=499362560080 generation=2 viewId=1 surfaceGeneration=2 wid=2258 ownerTokenPresent=true | L1695 |
| 22:55:06.190 | 2360 | java | 3225 | mono=415726566 tid=3225 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-2618625001885470403 libraryLoaded=true | L1696 |
| 22:55:06.190 | 2360 | native | 3225 | mono=415726566 tid=3225 egl_ctx=0x7424133280 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=15828119071824081213 req_generation=2 | L1697 |
| 22:55:06.190 | 2360 | native | 3225 | mono=415726566 tid=3225 egl_ctx=0x7424133280 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=15828119071824081213 req_generation=2 resources_ready=1 | L1698 |
| 22:55:06.190 | 2360 | native | 3225 | mono=415726566 tid=3225 egl_ctx=0x7424133280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=15828119071824081213 generation=2 rc=0 | L1700 |
| 22:55:06.190 | 2360 | java | 3225 | mono=415726566 tid=3225 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-2618625001885470403 | L1701 |
| 22:55:06.190 | 2360 | java | 3225 | mono=415726566 tid=3225 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=2258 | L1702 |
| 22:55:06.191 | 2361 | dart | 3225 | dart authorize result epoch=2 wid=2258 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1703 |
| 22:55:06.191 | 2361 | dart | 3225 | dart property begin android-surface-size=2672x1336 | L1704 |
| 22:55:06.192 | 2362 | dart | 3225 | dart property complete android-surface-size=2672x1336 | L1705 |
| 22:55:06.192 | 2362 | dart | 3225 | dart property begin wid=2258 | L1706 |
| 22:55:06.205 | 2375 | dart | 3225 | dart property complete wid=2258 | L1707 |
| 22:55:06.205 | 2375 | dart | 3225 | dart property begin vo=gpu-next | L1708 |
| 22:55:06.213 | 2383 | mpv | 3225 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1721 |
| 22:55:06.231 | 2401 | dart | 3225 | dart property complete vo=gpu-next | L1731 |
| 22:55:06.231 | 2401 | dart | 3225 | dart property begin vid=auto | L1732 |
| 22:55:06.248 | 2418 | native | 3450 | mono=415726624 tid=3450 egl_ctx=0x7418e63a80 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=15828119071824081213 generation=2  | L1738 |
| 22:55:06.249 | 2419 | native | 3450 | mono=415726624 tid=3450 egl_ctx=0x7418e63a80 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=15828119071824081213 generation=2 ready=1 | L1739 |
| 22:55:06.249 | 2419 | native | 3450 | mono=415726624 tid=3450 egl_ctx=0x7418e63a80 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=15828119071824081213 generation=2  | L1740 |
| 22:55:06.249 | 2419 | mpv | 3225 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1741 |
| 22:55:06.250 | 2420 | native | 3450 | mono=415726626 tid=3450 egl_ctx=0x7418e63a80 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=15828119071824081213 generation=2 result=ok window=0x7414e62010 | L1743 |
| 22:55:06.252 | 2422 | codec | 3260 | ACodec  : Now uninitialized | L1746 |
| 22:55:06.266 | 2436 | codec | 3453 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1763 |
| 22:55:06.280 | 2450 | codec | 3453 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1784 |
| 22:55:06.288 | 2458 | codec | 3453 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1786 |
| 22:55:06.295 | 2465 | codec | 3453 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1787 |
| 22:55:06.295 | 2465 | codec | 3453 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1788 |
| 22:55:06.301 | 2471 | dart | 3225 | dart property complete vid=auto | L1789 |
| 22:55:06.301 | 2471 | dart | 3225 | dart apply complete wid=2258 | L1790 |
| 22:55:06.301 | 2471 | dart | 3225 | dart bind complete wid=2258 surfaceGeneration=2 | L1791 |
| 22:55:06.301 | 2471 | dart | 3225 | dart bind lock released wid=2258 surfaceGeneration=2 | L1793 |
| 22:55:06.318 | 2488 | codec | 3453 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1796 |
| 22:55:06.323 | 2493 | codec | 3453 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1798 |
| 22:55:06.389 | 2559 | codec | 3453 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1800 |
| 22:55:06.431 | 2601 | dart-videoparams | 3225 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1805 |
| 22:55:06.440 | 2610 | dart | 3225 | dart size property complete android-surface-size=1440x720 | L1806 |
| 22:55:06.447 | 2617 | dart | 3225 | dart size property complete android-surface-size=2672x1336 | L1810 |
| 22:55:06.479 | 2649 | java-log | 3225 | PlatformVideoView: surfaceChanged: handle=499362560080, format=43, width=2672, height=1336, wid=2258 | L1818 |
| 22:55:06.490 | 2660 | dart | 3225 | dart size property complete android-surface-size=2672x1336 | L1819 |
| 22:55:27.545 | 23715 | host-cmd |  | pid_after pid_before=3225 pid_after=3225 |  |
| 22:55:27.942 | 24112 | host-cmd |  | full_dump lines=    1906 |  |
| 22:55:28.085 | 24255 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 22:55:28.189 | 24359 | host-cmd |  | round_end |  |
