# Timeline P1

App PID filter: 3907 (ActivityManager am_pause/resume lines kept from system_server).

Source: `P1/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 22:57:35.448 | 0 | L0 |
| home_sent(host probe after cmd returned) | 22:57:36.753 | 1305 | L0 |
| am_pause_lab | 22:57:35.998 | 550 | L1358 |
| java_surfaceDestroyed_enter | 22:57:36.292 | 844 | L1436 |
| java_send_SurfaceDestroyed | 22:57:36.292 | 844 | L1438 |
| dart_event_SurfaceDestroyed | 22:57:36.293 | 845 | L1439 |
| dart_detach_lock_acquired | 22:57:36.293 | 845 | L1441 |
| dart_detach_vo_null_begin | 22:57:36.293 | 845 | L1444 |
| native_shutdown_enter | 22:57:36.346 | 898 | L1482 |
| native_shutdown_exit | 22:57:36.346 | 898 | L1484 |
| dart_detach_vo_null_ack | 22:57:36.394 | 946 | L1503 |
| dart_detach_wid0_ack | 22:57:37.279 | 1831 | L1557 |
| dart_detach_apply_complete | 22:57:38.295 | 2847 | L1583 |
| dart_detach_lock_released | 22:57:38.297 | 2849 | L1591 |
| return_sent | 22:57:47.637 | 12189 | L0 |
| am_resume_lab | 22:57:47.525 | 12077 | L1694 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | 22:57:47.711 | 12263 | L1772 |
| java_surfaceCreated_enter | 22:57:47.621 | 12173 | L1720 |
| java_send_SurfaceAvailable | 22:57:47.626 | 12178 | L1737 |
| dart_event_SurfaceAvailable | 22:57:47.626 | 12178 | L1738 |
| dart_bind_requested | 22:57:47.626 | 12178 | L1739 |
| dart_bind_lock_acquired | 22:57:47.626 | 12178 | L1740 |
| dart_bind_vo_gpu_next_begin | 22:57:47.754 | 12306 | L1789 |
| native_ensure_init_exit | 22:57:47.789 | 12341 | L1828 |
| native_create_exit | 22:57:47.790 | 12342 | L1832 |
| mpv_egl_window_surface | 22:57:47.764 | 12316 | L1809 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 22:57:47.879 | 12431 | L1896 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 11275 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 48 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 1949 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 11443 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 54 |
| dart_vo_null_begin -> shutdown_enter (ms) | 53 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 5 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 9329 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | -9329 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 844 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -16 |

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
| 22:57:05.567 | -29881 | host-cmd |  | round_begin mode=pause pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key=KEYCODE_MEDIA_PAUSE resume_key=KEYCODE_MEDIA_PLAY |  |
| 22:57:06.248 | -29200 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 22:57:08.187 | -27261 | host-cmd |  | force_stop pid_after= |  |
| 22:57:08.810 | -26638 | host-cmd |  | logcat_cleared per-buffer |  |
| 22:57:09.560 | -25888 | host-cmd |  | am_start_fresh pid=3907 |  |
| 22:57:14.097 | -21351 | java | 3907 | mono=415854473 tid=3907 thr=main java factory.create enter handle=498743520336 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L427 |
| 22:57:14.098 | -21350 | java | 3907 | mono=415854474 tid=3907 thr=main java factory.create view constructed handle=498743520336 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L428 |
| 22:57:14.098 | -21350 | java | 3907 | mono=415854474 tid=3907 thr=main java setLgExperimentOwner enter handle=498743520336 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L429 |
| 22:57:14.099 | -21349 | java | 3907 | mono=415854475 tid=3907 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=6554548817045129073 libraryLoaded=false | L430 |
| 22:57:14.100 | -21348 | native | 3907 | mono=415854475 tid=3907 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=6554548817045129073 req_generation=1 | L431 |
| 22:57:14.102 | -21346 | native | 3907 | mono=415854478 tid=3907 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=6554548817045129073 req_generation=1 resources_ready=1 | L433 |
| 22:57:14.102 | -21346 | native | 3907 | mono=415854478 tid=3907 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=6554548817045129073 generation=1 rc=0 | L435 |
| 22:57:14.103 | -21345 | java | 3907 | mono=415854478 tid=3907 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=6554548817045129073 | L436 |
| 22:57:14.103 | -21345 | java | 3907 | mono=415854478 tid=3907 thr=main java setLgExperimentOwner exit handle=498743520336 viewId=0 ownerGeneration=1 ensureInitialized=ok | L437 |
| 22:57:14.103 | -21345 | java | 3907 | mono=415854478 tid=3907 thr=main java factory.create setLgExperimentOwner returned handle=498743520336 viewId=0 | L438 |
| 22:57:14.103 | -21345 | java | 3907 | mono=415854479 tid=3907 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743520336 viewId=0 ownerGeneration=1 creationSerial=1 | L439 |
| 22:57:14.104 | -21344 | java | 3907 | mono=415854480 tid=3907 thr=main java factory.create exit handle=498743520336 viewId=0 | L441 |
| 22:57:14.140 | -21308 | java-log | 3907 | PlatformVideoView: surfaceCreated: handle=498743520336, width=668, height=360, viewIdentity=235825235 | L442 |
| 22:57:14.140 | -21308 | java | 3907 | mono=415854516 tid=3907 thr=main java surfaceCreated enter handle=498743520336 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L443 |
| 22:57:14.149 | -21299 | java-log | 3907 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L445 |
| 22:57:14.149 | -21299 | java | 3907 | mono=415854525 tid=3907 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743520336 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L446 |
| 22:57:14.150 | -21298 | java | 3907 | mono=415854526 tid=3907 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743520336 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L447 |
| 22:57:14.151 | -21297 | java | 3907 | mono=415854527 tid=3907 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743520336 viewId=0 surfaceGeneration=1 wid=2099350 | L452 |
| 22:57:14.151 | -21297 | java | 3907 | mono=415854527 tid=3907 thr=main java surfaceCreated exit handle=498743520336 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L453 |
| 22:57:14.180 | -21268 | host-cmd |  | tap_open x=1440 y=720 |  |
| 22:57:15.083 | -20365 | java | 3907 | mono=415855459 tid=3907 thr=main java factory.create enter handle=498743520336 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L832 |
| 22:57:15.084 | -20364 | java | 3907 | mono=415855459 tid=3907 thr=main java factory.create view constructed handle=498743520336 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L834 |
| 22:57:15.084 | -20364 | java | 3907 | mono=415855460 tid=3907 thr=main java setLgExperimentOwner enter handle=498743520336 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L835 |
| 22:57:15.084 | -20364 | java | 3907 | mono=415855460 tid=3907 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=6554548817045129073 libraryLoaded=true | L836 |
| 22:57:15.084 | -20364 | native | 3907 | mono=415855460 tid=3907 egl_ctx=0x744b9ff280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=6554548817045129073 generation=1 req_owner_key=6554548817045129073 req_generation=2 | L837 |
| 22:57:15.084 | -20364 | native | 3907 | mono=415855460 tid=3907 egl_ctx=0x744b9ff280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=6554548817045129073 generation=1 req_owner_key=6554548817045129073 req_generation=2 resources_ready=1 | L838 |
| 22:57:15.084 | -20364 | native | 3907 | mono=415855460 tid=3907 egl_ctx=0x744b9ff280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=6554548817045129073 generation=2 rc=0 | L840 |
| 22:57:15.084 | -20364 | java | 3907 | mono=415855460 tid=3907 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=6554548817045129073 | L841 |
| 22:57:15.084 | -20364 | java | 3907 | mono=415855460 tid=3907 thr=main java setLgExperimentOwner exit handle=498743520336 viewId=1 ownerGeneration=2 ensureInitialized=ok | L842 |
| 22:57:15.084 | -20364 | java | 3907 | mono=415855460 tid=3907 thr=main java factory.create setLgExperimentOwner returned handle=498743520336 viewId=1 | L843 |
| 22:57:15.084 | -20364 | java | 3907 | mono=415855460 tid=3907 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743520336 viewId=1 ownerGeneration=2 creationSerial=2 | L844 |
| 22:57:15.085 | -20363 | java | 3907 | mono=415855461 tid=3907 thr=main java factory.create exit handle=498743520336 viewId=1 | L846 |
| 22:57:15.129 | -20319 | java-log | 3907 | PlatformVideoView: surfaceCreated: handle=498743520336, width=668, height=360, viewIdentity=207085198 | L847 |
| 22:57:15.129 | -20319 | java | 3907 | mono=415855505 tid=3907 thr=main java surfaceCreated enter handle=498743520336 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L848 |
| 22:57:15.136 | -20312 | java-log | 3907 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743520336, transfer=pq, applied=true | L861 |
| 22:57:15.136 | -20312 | java-log | 3907 | PlatformVideoView: surfaceCreated: created new wid=1050746 | L863 |
| 22:57:15.136 | -20312 | java | 3907 | mono=415855512 tid=3907 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743520336 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=1050746 | L864 |
| 22:57:15.136 | -20312 | java | 3907 | mono=415855512 tid=3907 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743520336 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050746 | L865 |
| 22:57:15.137 | -20311 | java | 3907 | mono=415855512 tid=3907 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743520336 viewId=1 surfaceGeneration=1 wid=1050746 | L870 |
| 22:57:15.137 | -20311 | java | 3907 | mono=415855512 tid=3907 thr=main java surfaceCreated exit handle=498743520336 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050746 | L871 |
| 22:57:15.170 | -20278 | java | 3907 | mono=415855546 tid=3907 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=6554548817045129073 libraryLoaded=true | L878 |
| 22:57:15.170 | -20278 | native | 3907 | mono=415855546 tid=3907 egl_ctx=0x744b9ff280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=6554548817045129073 generation=2 req_owner_key=6554548817045129073 req_generation=2 | L879 |
| 22:57:15.170 | -20278 | native | 3907 | mono=415855546 tid=3907 egl_ctx=0x744b9ff280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=6554548817045129073 generation=2 req_owner_key=6554548817045129073 req_generation=2 resources_ready=1 | L880 |
| 22:57:15.170 | -20278 | native | 3907 | mono=415855546 tid=3907 egl_ctx=0x744b9ff280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=6554548817045129073 generation=2 rc=0 | L882 |
| 22:57:15.170 | -20278 | java | 3907 | mono=415855546 tid=3907 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=6554548817045129073 | L883 |
| 22:57:15.318 | -20130 | native | 3979 | mono=415855694 tid=3979 egl_ctx=0x741c3daa00 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=6554548817045129073 generation=2  | L927 |
| 22:57:15.319 | -20129 | native | 3979 | mono=415855695 tid=3979 egl_ctx=0x741c3daa00 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=6554548817045129073 generation=2 ready=1 | L928 |
| 22:57:15.319 | -20129 | native | 3979 | mono=415855695 tid=3979 egl_ctx=0x741c3daa00 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=6554548817045129073 generation=2  | L929 |
| 22:57:15.322 | -20126 | native | 3979 | mono=415855698 tid=3979 egl_ctx=0x741c3daa00 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=6554548817045129073 generation=2 result=ok window=0x744cb55410 | L931 |
| 22:57:31.291 | -4157 | host-cmd |  | pre_home_key_begin key=KEYCODE_MEDIA_PAUSE |  |
| 22:57:31.956 | -3492 | host-cmd |  | pre_home_key_sent key=KEYCODE_MEDIA_PAUSE |  |
| 22:57:35.182 | -266 | host-cmd |  | interim_dump lines=    1297 |  |
| 22:57:35.353 | -95 | host-cmd |  | pid_before pid=3907 |  |
| 22:57:35.448 | 0 | host-cmd |  | home_send_begin |  |
| 22:57:35.998 | 550 | activity | 2062 | am_pause_activity: [0,256584446,com.example.media_kit_hdr_lab/.MainActivity] | L1358 |
| 22:57:36.000 | 552 | activity | 3907 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1359 |
| 22:57:36.122 | 674 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1380 |
| 22:57:36.266 | 818 | activity | 3907 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1416 |
| 22:57:36.292 | 844 | java-log | 3907 | PlatformVideoView: surfaceDestroyed: handle=498743520336, wid=1050746 | L1435 |
| 22:57:36.292 | 844 | java | 3907 | mono=415876668 tid=3907 thr=main java surfaceDestroyed enter handle=498743520336 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050746 disposed=false | L1436 |
| 22:57:36.292 | 844 | java | 3907 | mono=415876668 tid=3907 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743520336 viewId=1 surfaceGeneration=1 wid=1050746 | L1437 |
| 22:57:36.292 | 844 | java | 3907 | mono=415876668 tid=3907 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743520336 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050746 | L1438 |
| 22:57:36.293 | 845 | dart | 3907 | dart event SurfaceDestroyed handle=498743520336 wid=1050746 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=1050746 boundSurfaceGeneration=1 | L1439 |
| 22:57:36.293 | 845 | dart | 3907 | dart detach requested wid=1050746 surfaceGeneration=1 generation=2 viewId=1 | L1440 |
| 22:57:36.293 | 845 | dart | 3907 | dart detach lock acquired wid=1050746 surfaceGeneration=1 generation=2 viewId=1 boundWid=1050746 boundSurfaceGeneration=1 | L1441 |
| 22:57:36.293 | 845 | dart | 3907 | dart detach decision wid=1050746 isCurrentOutput=true isInFlightOutput=false | L1442 |
| 22:57:36.293 | 845 | dart | 3907 | dart apply begin wid=0 vo=null vid=no | L1443 |
| 22:57:36.293 | 845 | dart | 3907 | dart property begin vo=null | L1444 |
| 22:57:36.293 | 845 | java | 3907 | mono=415876669 tid=3907 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743520336 viewId=1 surfaceGeneration=1 wid=1050746 | L1445 |
| 22:57:36.293 | 845 | java | 3907 | mono=415876669 tid=3907 thr=main java surfaceDestroyed exit handle=498743520336 viewId=1 sentEvent=true wid=0 | L1446 |
| 22:57:36.304 | 856 | codec | 3986 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 11/16 output). | L1452 |
| 22:57:36.305 | 857 | codec | 3986 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1454 |
| 22:57:36.307 | 859 | codec | 3986 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1455 |
| 22:57:36.313 | 865 | codec | 3986 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1457 |
| 22:57:36.323 | 875 | codec | 3986 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1459 |
| 22:57:36.324 | 876 | codec | 3986 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1460 |
| 22:57:36.339 | 891 | codec | 3986 | ACodec  : Now uninitialized | L1476 |
| 22:57:36.346 | 898 | native | 3979 | mono=415876721 tid=3979 egl_ctx=0x741c3daa00 native mkst_shutdown enter initialized=1 window_active=1 owner_key=6554548817045129073 generation=2  | L1482 |
| 22:57:36.346 | 898 | native | 3979 | mono=415876722 tid=3979 egl_ctx=0x741c3daa00 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=614 latched=614 | L1484 |
| 22:57:36.394 | 946 | dart | 3907 | dart property complete vo=null | L1503 |
| 22:57:36.394 | 946 | dart | 3907 | dart property begin android-surface-size=2672x1336 | L1504 |
| 22:57:36.727 | 1279 | dart | 3907 | dart property complete android-surface-size=2672x1336 | L1525 |
| 22:57:36.727 | 1279 | dart | 3907 | dart property begin wid=0 | L1526 |
| 22:57:36.729 | 1281 | dart-videoparams | 3907 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1527 |
| 22:57:36.753 | 1305 | host-cmd |  | home_sent |  |
| 22:57:37.279 | 1831 | dart | 3907 | dart property complete wid=0 | L1557 |
| 22:57:37.280 | 1832 | dart | 3907 | dart property begin vo=null | L1558 |
| 22:57:37.756 | 2308 | dart | 3907 | dart property complete vo=null | L1572 |
| 22:57:37.756 | 2308 | dart | 3907 | dart property begin vid=no | L1573 |
| 22:57:38.294 | 2846 | dart | 3907 | dart property complete vid=no | L1582 |
| 22:57:38.295 | 2847 | dart | 3907 | dart apply complete wid=0 | L1583 |
| 22:57:38.295 | 2847 | dart | 3907 | dart detach producer stopped wid=1050746 | L1584 |
| 22:57:38.295 | 2847 | java-log | 3907 | PlatformVideoView: releaseSurface generation=1 wid=1050746 result=released | L1586 |
| 22:57:38.297 | 2849 | dart | 3907 | dart detach reference released wid=1050746 | L1590 |
| 22:57:38.297 | 2849 | dart | 3907 | dart detach lock released wid=1050746 surfaceGeneration=1 | L1591 |
| 22:57:46.950 | 11502 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity |  |
| 22:57:47.452 | 12004 | activity | 2300 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1659 |
| 22:57:47.525 | 12077 | activity | 3297 | am_resume_activity: [0,256584446,1047,com.example.media_kit_hdr_lab/.MainActivity] | L1694 |
| 22:57:47.551 | 12103 | activity | 3907 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1700 |
| 22:57:47.621 | 12173 | java-log | 3907 | PlatformVideoView: surfaceCreated: handle=498743520336, width=668, height=360, viewIdentity=207085198 | L1719 |
| 22:57:47.621 | 12173 | java | 3907 | mono=415887996 tid=3907 thr=main java surfaceCreated enter handle=498743520336 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1720 |
| 22:57:47.625 | 12177 | java-log | 3907 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743520336, transfer=pq, applied=true | L1733 |
| 22:57:47.626 | 12178 | java-log | 3907 | PlatformVideoView: surfaceCreated: created new wid=1050738 | L1735 |
| 22:57:47.626 | 12178 | java | 3907 | mono=415888001 tid=3907 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743520336 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=1050738 | L1736 |
| 22:57:47.626 | 12178 | java | 3907 | mono=415888002 tid=3907 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743520336 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=1050738 | L1737 |
| 22:57:47.626 | 12178 | dart | 3907 | dart event SurfaceAvailable handle=498743520336 wid=1050738 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1738 |
| 22:57:47.626 | 12178 | dart | 3907 | dart bind requested wid=1050738 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1739 |
| 22:57:47.626 | 12178 | dart | 3907 | dart bind lock acquired wid=1050738 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1740 |
| 22:57:47.626 | 12178 | dart | 3907 | dart bind branch=rebind wid=1050738 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1741 |
| 22:57:47.627 | 12179 | java | 3907 | mono=415888002 tid=3907 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743520336 viewId=1 surfaceGeneration=2 wid=1050738 | L1742 |
| 22:57:47.627 | 12179 | java | 3907 | mono=415888003 tid=3907 thr=main java surfaceCreated exit handle=498743520336 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=1050738 | L1743 |
| 22:57:47.627 | 12179 | java-log | 3907 | PlatformVideoView: surfaceChanged: handle=498743520336, format=43, width=2672, height=1336, wid=1050738 | L1744 |
| 22:57:47.637 | 12189 | host-cmd |  | return_sent |  |
| 22:57:47.643 | 12195 | dart | 3907 | dart apply begin wid=1050738 vo=gpu-next vid=auto | L1751 |
| 22:57:47.643 | 12195 | dart | 3907 | dart property begin vo=null | L1752 |
| 22:57:47.647 | 12199 | dart | 3907 | dart property complete vo=null | L1753 |
| 22:57:47.647 | 12199 | dart | 3907 | dart authorize begin wid=1050738 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1754 |
| 22:57:47.670 | 12222 | java-log | 3907 | PlatformVideoView: surfaceChanged: handle=498743520336, format=43, width=2672, height=1440, wid=1050738 | L1759 |
| 22:57:47.710 | 12262 | java | 3907 | mono=415888086 tid=3907 thr=main java authorize enter handle=498743520336 generation=2 viewId=1 surfaceGeneration=2 wid=1050738 ownerTokenPresent=true | L1771 |
| 22:57:47.711 | 12263 | java | 3907 | mono=415888087 tid=3907 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=6554548817045129073 libraryLoaded=true | L1772 |
| 22:57:47.711 | 12263 | native | 3907 | mono=415888087 tid=3907 egl_ctx=0x744b9ff280 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=6554548817045129073 req_generation=2 | L1773 |
| 22:57:47.711 | 12263 | native | 3907 | mono=415888087 tid=3907 egl_ctx=0x744b9ff280 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=6554548817045129073 req_generation=2 resources_ready=1 | L1774 |
| 22:57:47.711 | 12263 | native | 3907 | mono=415888087 tid=3907 egl_ctx=0x744b9ff280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=6554548817045129073 generation=2 rc=0 | L1776 |
| 22:57:47.711 | 12263 | java | 3907 | mono=415888087 tid=3907 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=6554548817045129073 | L1777 |
| 22:57:47.711 | 12263 | java | 3907 | mono=415888087 tid=3907 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=1050738 | L1778 |
| 22:57:47.712 | 12264 | dart | 3907 | dart authorize result epoch=2 wid=1050738 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1779 |
| 22:57:47.712 | 12264 | dart | 3907 | dart property begin android-surface-size=2672x1336 | L1780 |
| 22:57:47.729 | 12281 | dart | 3907 | dart property complete android-surface-size=2672x1336 | L1783 |
| 22:57:47.729 | 12281 | dart | 3907 | dart property begin wid=1050738 | L1784 |
| 22:57:47.754 | 12306 | dart | 3907 | dart property complete wid=1050738 | L1788 |
| 22:57:47.754 | 12306 | dart | 3907 | dart property begin vo=gpu-next | L1789 |
| 22:57:47.764 | 12316 | mpv | 3907 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1809 |
| 22:57:47.774 | 12326 | dart | 3907 | dart property complete vo=gpu-next | L1819 |
| 22:57:47.774 | 12326 | dart | 3907 | dart property begin vid=auto | L1820 |
| 22:57:47.789 | 12341 | native | 4078 | mono=415888164 tid=4078 egl_ctx=0x741234a880 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=6554548817045129073 generation=2  | L1827 |
| 22:57:47.789 | 12341 | native | 4078 | mono=415888165 tid=4078 egl_ctx=0x741234a880 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=6554548817045129073 generation=2 ready=1 | L1828 |
| 22:57:47.789 | 12341 | native | 4078 | mono=415888165 tid=4078 egl_ctx=0x741234a880 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=6554548817045129073 generation=2  | L1829 |
| 22:57:47.789 | 12341 | mpv | 3907 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1830 |
| 22:57:47.790 | 12342 | native | 4078 | mono=415888166 tid=4078 egl_ctx=0x741234a880 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=6554548817045129073 generation=2 result=ok window=0x744455f810 | L1832 |
| 22:57:47.794 | 12346 | codec | 3939 | ACodec  : Now uninitialized | L1835 |
| 22:57:47.813 | 12365 | codec | 4081 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1860 |
| 22:57:47.823 | 12375 | codec | 4081 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1880 |
| 22:57:47.859 | 12411 | codec | 4081 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1889 |
| 22:57:47.868 | 12420 | codec | 4081 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1892 |
| 22:57:47.868 | 12420 | codec | 4081 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1893 |
| 22:57:47.879 | 12431 | dart | 3907 | dart property complete vid=auto | L1894 |
| 22:57:47.879 | 12431 | dart | 3907 | dart apply complete wid=1050738 | L1895 |
| 22:57:47.879 | 12431 | dart | 3907 | dart bind complete wid=1050738 surfaceGeneration=2 | L1896 |
| 22:57:47.879 | 12431 | dart | 3907 | dart bind lock released wid=1050738 surfaceGeneration=2 | L1897 |
| 22:57:47.881 | 12433 | dart-videoparams | 3907 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1898 |
| 22:57:47.937 | 12489 | codec | 4081 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1901 |
| 22:57:47.944 | 12496 | codec | 4081 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1907 |
| 22:57:48.011 | 12563 | codec | 4081 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1908 |
| 22:57:48.061 | 12613 | dart-videoparams | 3907 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1913 |
| 22:57:48.076 | 12628 | dart | 3907 | dart size property complete android-surface-size=2672x1336 | L1915 |
| 22:57:48.101 | 12653 | java-log | 3907 | PlatformVideoView: surfaceChanged: handle=498743520336, format=43, width=2672, height=1336, wid=1050738 | L1916 |
| 22:57:52.768 | 17320 | host-cmd |  | resume_key_begin key=KEYCODE_MEDIA_PLAY |  |
| 22:57:53.366 | 17918 | host-cmd |  | resume_key_sent key=KEYCODE_MEDIA_PLAY |  |
| 22:58:10.629 | 35181 | host-cmd |  | pid_after pid_before=3907 pid_after=3907 |  |
| 22:58:11.326 | 35878 | host-cmd |  | full_dump lines=    2057 |  |
| 22:58:11.568 | 36120 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 22:58:11.786 | 36338 | host-cmd |  | round_end |  |
