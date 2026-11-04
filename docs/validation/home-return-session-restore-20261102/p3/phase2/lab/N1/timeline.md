# Timeline N1

App PID filter: 493 (ActivityManager am_pause/resume lines kept from system_server).

Source: `N1/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 22:48:11.736 | 0 | L0 |
| home_sent(host probe after cmd returned) | 22:48:12.892 | 1156 | L0 |
| am_pause_lab | 22:48:12.318 | 582 | L1341 |
| java_surfaceDestroyed_enter | 22:48:12.573 | 837 | L1424 |
| java_send_SurfaceDestroyed | 22:48:12.573 | 837 | L1426 |
| dart_event_SurfaceDestroyed | 22:48:12.574 | 838 | L1427 |
| dart_detach_lock_acquired | 22:48:12.574 | 838 | L1429 |
| dart_detach_vo_null_begin | 22:48:12.574 | 838 | L1432 |
| native_shutdown_enter | 22:48:12.647 | 911 | L1475 |
| native_shutdown_exit | 22:48:12.648 | 912 | L1477 |
| dart_detach_vo_null_ack | 22:48:12.715 | 979 | L1507 |
| dart_detach_wid0_ack | 22:48:13.597 | 1861 | L1556 |
| dart_detach_apply_complete | 22:48:14.575 | 2839 | L1581 |
| dart_detach_lock_released | 22:48:14.577 | 2841 | L1587 |
| return_sent | 22:48:23.692 | 11956 | L0 |
| am_resume_lab | 22:48:23.645 | 11909 | L1697 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | 22:48:23.857 | 12121 | L1777 |
| java_surfaceCreated_enter | 22:48:23.736 | 12000 | L1720 |
| java_send_SurfaceAvailable | 22:48:23.742 | 12006 | L1739 |
| dart_event_SurfaceAvailable | 22:48:23.742 | 12006 | L1740 |
| dart_bind_requested | 22:48:23.742 | 12006 | L1741 |
| dart_bind_lock_acquired | 22:48:23.742 | 12006 | L1742 |
| dart_bind_vo_gpu_next_begin | 22:48:23.891 | 12155 | L1794 |
| native_ensure_init_exit | 22:48:23.931 | 12195 | L1838 |
| native_create_exit | 22:48:23.933 | 12197 | L1841 |
| mpv_egl_window_surface | 22:48:23.895 | 12159 | L1807 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 22:48:24.038 | 12302 | L1893 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 11088 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 67 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 1927 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 11283 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 75 |
| dart_vo_null_begin -> shutdown_enter (ms) | 73 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 6 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 9165 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | -9165 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 837 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | 44 |

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
| 22:47:42.250 | -29486 | host-cmd |  | round_begin mode=normal pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=1 open_home_delay=0.5 pre_home_key= resume_key= |  |
| 22:47:42.664 | -29072 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 22:47:44.646 | -27090 | host-cmd |  | force_stop pid_after= |  |
| 22:47:45.488 | -26248 | host-cmd |  | logcat_cleared per-buffer |  |
| 22:47:46.235 | -25501 | host-cmd |  | am_start_fresh pid=493 |  |
| 22:47:50.761 | -20975 | java | 493 | mono=415291137 tid=493 thr=main java factory.create enter handle=498743536208 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L419 |
| 22:47:50.762 | -20974 | java | 493 | mono=415291138 tid=493 thr=main java factory.create view constructed handle=498743536208 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L420 |
| 22:47:50.762 | -20974 | java | 493 | mono=415291138 tid=493 thr=main java setLgExperimentOwner enter handle=498743536208 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L421 |
| 22:47:50.763 | -20973 | java | 493 | mono=415291139 tid=493 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=8793159320474925283 libraryLoaded=false | L422 |
| 22:47:50.764 | -20972 | native | 493 | mono=415291139 tid=493 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=8793159320474925283 req_generation=1 | L423 |
| 22:47:50.767 | -20969 | native | 493 | mono=415291143 tid=493 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=8793159320474925283 req_generation=1 resources_ready=1 | L425 |
| 22:47:50.767 | -20969 | native | 493 | mono=415291143 tid=493 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=8793159320474925283 generation=1 rc=0 | L427 |
| 22:47:50.768 | -20968 | java | 493 | mono=415291143 tid=493 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=8793159320474925283 | L428 |
| 22:47:50.768 | -20968 | java | 493 | mono=415291143 tid=493 thr=main java setLgExperimentOwner exit handle=498743536208 viewId=0 ownerGeneration=1 ensureInitialized=ok | L429 |
| 22:47:50.768 | -20968 | java | 493 | mono=415291144 tid=493 thr=main java factory.create setLgExperimentOwner returned handle=498743536208 viewId=0 | L430 |
| 22:47:50.768 | -20968 | java | 493 | mono=415291144 tid=493 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743536208 viewId=0 ownerGeneration=1 creationSerial=1 | L431 |
| 22:47:50.769 | -20967 | java | 493 | mono=415291145 tid=493 thr=main java factory.create exit handle=498743536208 viewId=0 | L433 |
| 22:47:50.807 | -20929 | java-log | 493 | PlatformVideoView: surfaceCreated: handle=498743536208, width=668, height=360, viewIdentity=235825235 | L443 |
| 22:47:50.807 | -20929 | java | 493 | mono=415291183 tid=493 thr=main java surfaceCreated enter handle=498743536208 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L444 |
| 22:47:50.812 | -20924 | host-cmd |  | tap_open x=1440 y=720 |  |
| 22:47:50.827 | -20909 | java-log | 493 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L446 |
| 22:47:50.827 | -20909 | java | 493 | mono=415291203 tid=493 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743536208 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L447 |
| 22:47:50.827 | -20909 | java | 493 | mono=415291203 tid=493 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743536208 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L448 |
| 22:47:50.829 | -20907 | java | 493 | mono=415291204 tid=493 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743536208 viewId=0 surfaceGeneration=1 wid=2099350 | L453 |
| 22:47:50.829 | -20907 | java | 493 | mono=415291204 tid=493 thr=main java surfaceCreated exit handle=498743536208 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L454 |
| 22:47:51.950 | -19786 | java | 493 | mono=415292326 tid=493 thr=main java factory.create enter handle=498743536208 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L831 |
| 22:47:51.953 | -19783 | java | 493 | mono=415292328 tid=493 thr=main java factory.create view constructed handle=498743536208 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L833 |
| 22:47:51.953 | -19783 | java | 493 | mono=415292328 tid=493 thr=main java setLgExperimentOwner enter handle=498743536208 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L834 |
| 22:47:51.953 | -19783 | java | 493 | mono=415292329 tid=493 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=8793159320474925283 libraryLoaded=true | L835 |
| 22:47:51.953 | -19783 | native | 493 | mono=415292329 tid=493 egl_ctx=0x7427534280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=8793159320474925283 generation=1 req_owner_key=8793159320474925283 req_generation=2 | L836 |
| 22:47:51.953 | -19783 | native | 493 | mono=415292329 tid=493 egl_ctx=0x7427534280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=8793159320474925283 generation=1 req_owner_key=8793159320474925283 req_generation=2 resources_ready=1 | L837 |
| 22:47:51.953 | -19783 | native | 493 | mono=415292329 tid=493 egl_ctx=0x7427534280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=8793159320474925283 generation=2 rc=0 | L839 |
| 22:47:51.953 | -19783 | java | 493 | mono=415292329 tid=493 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=8793159320474925283 | L840 |
| 22:47:51.953 | -19783 | java | 493 | mono=415292329 tid=493 thr=main java setLgExperimentOwner exit handle=498743536208 viewId=1 ownerGeneration=2 ensureInitialized=ok | L841 |
| 22:47:51.954 | -19782 | java | 493 | mono=415292330 tid=493 thr=main java factory.create setLgExperimentOwner returned handle=498743536208 viewId=1 | L842 |
| 22:47:51.954 | -19782 | java | 493 | mono=415292330 tid=493 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743536208 viewId=1 ownerGeneration=2 creationSerial=2 | L843 |
| 22:47:51.957 | -19779 | java | 493 | mono=415292333 tid=493 thr=main java factory.create exit handle=498743536208 viewId=1 | L845 |
| 22:47:52.019 | -19717 | java-log | 493 | PlatformVideoView: surfaceCreated: handle=498743536208, width=668, height=360, viewIdentity=218943113 | L846 |
| 22:47:52.019 | -19717 | java | 493 | mono=415292395 tid=493 thr=main java surfaceCreated enter handle=498743536208 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L847 |
| 22:47:52.024 | -19712 | java-log | 493 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743536208, transfer=pq, applied=true | L860 |
| 22:47:52.024 | -19712 | java-log | 493 | PlatformVideoView: surfaceCreated: created new wid=1946 | L862 |
| 22:47:52.024 | -19712 | java | 493 | mono=415292400 tid=493 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743536208 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=1946 | L863 |
| 22:47:52.024 | -19712 | java | 493 | mono=415292400 tid=493 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743536208 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1946 | L864 |
| 22:47:52.025 | -19711 | java | 493 | mono=415292400 tid=493 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743536208 viewId=1 surfaceGeneration=1 wid=1946 | L869 |
| 22:47:52.025 | -19711 | java | 493 | mono=415292401 tid=493 thr=main java surfaceCreated exit handle=498743536208 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1946 | L870 |
| 22:47:52.065 | -19671 | java | 493 | mono=415292440 tid=493 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=8793159320474925283 libraryLoaded=true | L877 |
| 22:47:52.065 | -19671 | native | 493 | mono=415292441 tid=493 egl_ctx=0x7427534280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=8793159320474925283 generation=2 req_owner_key=8793159320474925283 req_generation=2 | L878 |
| 22:47:52.065 | -19671 | native | 493 | mono=415292441 tid=493 egl_ctx=0x7427534280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=8793159320474925283 generation=2 req_owner_key=8793159320474925283 req_generation=2 resources_ready=1 | L879 |
| 22:47:52.065 | -19671 | native | 493 | mono=415292441 tid=493 egl_ctx=0x7427534280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=8793159320474925283 generation=2 rc=0 | L881 |
| 22:47:52.065 | -19671 | java | 493 | mono=415292441 tid=493 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=8793159320474925283 | L882 |
| 22:47:52.193 | -19543 | native | 612 | mono=415292569 tid=612 egl_ctx=0x741d8df900 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=8793159320474925283 generation=2  | L940 |
| 22:47:52.193 | -19543 | native | 612 | mono=415292569 tid=612 egl_ctx=0x741d8df900 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=8793159320474925283 generation=2 ready=1 | L941 |
| 22:47:52.193 | -19543 | native | 612 | mono=415292569 tid=612 egl_ctx=0x741d8df900 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=8793159320474925283 generation=2  | L942 |
| 22:47:52.195 | -19541 | native | 612 | mono=415292571 tid=612 egl_ctx=0x741d8df900 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=8793159320474925283 generation=2 result=ok window=0x7444595610 | L945 |
| 22:48:11.094 | -642 | host-cmd |  | sf_dump sf-pre-home.txt lines=     364 |  |
| 22:48:11.372 | -364 | host-cmd |  | interim_dump lines=    1283 |  |
| 22:48:11.609 | -127 | host-cmd |  | pid_before pid=493 |  |
| 22:48:11.736 | 0 | host-cmd |  | home_send_begin |  |
| 22:48:12.318 | 582 | activity | 2062 | am_pause_activity: [0,205522370,com.example.media_kit_hdr_lab/.MainActivity] | L1341 |
| 22:48:12.321 | 585 | activity | 493 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1342 |
| 22:48:12.453 | 717 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1366 |
| 22:48:12.544 | 808 | activity | 493 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1400 |
| 22:48:12.573 | 837 | java-log | 493 | PlatformVideoView: surfaceDestroyed: handle=498743536208, wid=1946 | L1423 |
| 22:48:12.573 | 837 | java | 493 | mono=415312949 tid=493 thr=main java surfaceDestroyed enter handle=498743536208 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1946 disposed=false | L1424 |
| 22:48:12.573 | 837 | java | 493 | mono=415312949 tid=493 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743536208 viewId=1 surfaceGeneration=1 wid=1946 | L1425 |
| 22:48:12.573 | 837 | java | 493 | mono=415312949 tid=493 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743536208 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1946 | L1426 |
| 22:48:12.574 | 838 | dart | 493 | dart event SurfaceDestroyed handle=498743536208 wid=1946 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=1946 boundSurfaceGeneration=1 | L1427 |
| 22:48:12.574 | 838 | dart | 493 | dart detach requested wid=1946 surfaceGeneration=1 generation=2 viewId=1 | L1428 |
| 22:48:12.574 | 838 | dart | 493 | dart detach lock acquired wid=1946 surfaceGeneration=1 generation=2 viewId=1 boundWid=1946 boundSurfaceGeneration=1 | L1429 |
| 22:48:12.574 | 838 | dart | 493 | dart detach decision wid=1946 isCurrentOutput=true isInFlightOutput=false | L1430 |
| 22:48:12.574 | 838 | dart | 493 | dart apply begin wid=0 vo=null vid=no | L1431 |
| 22:48:12.574 | 838 | dart | 493 | dart property begin vo=null | L1432 |
| 22:48:12.574 | 838 | java | 493 | mono=415312950 tid=493 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743536208 viewId=1 surfaceGeneration=1 wid=1946 | L1433 |
| 22:48:12.575 | 839 | java | 493 | mono=415312950 tid=493 thr=main java surfaceDestroyed exit handle=498743536208 viewId=1 sentEvent=true wid=0 | L1434 |
| 22:48:12.576 | 840 | codec | 619 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 10/16 output). | L1435 |
| 22:48:12.576 | 840 | codec | 619 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1436 |
| 22:48:12.578 | 842 | codec | 619 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1437 |
| 22:48:12.579 | 843 | codec | 619 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1438 |
| 22:48:12.618 | 882 | codec | 619 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1449 |
| 22:48:12.618 | 882 | codec | 619 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1450 |
| 22:48:12.640 | 904 | codec | 619 | ACodec  : Now uninitialized | L1473 |
| 22:48:12.647 | 911 | native | 612 | mono=415313023 tid=612 egl_ctx=0x741d8df900 native mkst_shutdown enter initialized=1 window_active=1 owner_key=8793159320474925283 generation=2  | L1475 |
| 22:48:12.648 | 912 | native | 612 | mono=415313023 tid=612 egl_ctx=0x741d8df900 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=598 latched=598 | L1477 |
| 22:48:12.715 | 979 | dart | 493 | dart property complete vo=null | L1507 |
| 22:48:12.715 | 979 | dart | 493 | dart property begin android-surface-size=2672x1336 | L1508 |
| 22:48:12.892 | 1156 | host-cmd |  | home_sent |  |
| 22:48:13.112 | 1376 | dart | 493 | dart property complete android-surface-size=2672x1336 | L1523 |
| 22:48:13.112 | 1376 | dart | 493 | dart property begin wid=0 | L1524 |
| 22:48:13.115 | 1379 | dart-videoparams | 493 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1525 |
| 22:48:13.597 | 1861 | dart | 493 | dart property complete wid=0 | L1556 |
| 22:48:13.597 | 1861 | dart | 493 | dart property begin vo=null | L1557 |
| 22:48:14.121 | 2385 | dart | 493 | dart property complete vo=null | L1571 |
| 22:48:14.121 | 2385 | dart | 493 | dart property begin vid=no | L1572 |
| 22:48:14.574 | 2838 | dart | 493 | dart property complete vid=no | L1580 |
| 22:48:14.575 | 2839 | dart | 493 | dart apply complete wid=0 | L1581 |
| 22:48:14.575 | 2839 | dart | 493 | dart detach producer stopped wid=1946 | L1582 |
| 22:48:14.576 | 2840 | java-log | 493 | PlatformVideoView: releaseSurface generation=1 wid=1946 result=released | L1584 |
| 22:48:14.577 | 2841 | dart | 493 | dart detach reference released wid=1946 | L1586 |
| 22:48:14.577 | 2841 | dart | 493 | dart detach lock released wid=1946 surfaceGeneration=1 | L1587 |
| 22:48:23.035 | 11299 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity |  |
| 22:48:23.547 | 11811 | activity | 12129 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1661 |
| 22:48:23.645 | 11909 | activity | 2613 | am_resume_activity: [0,205522370,1039,com.example.media_kit_hdr_lab/.MainActivity] | L1697 |
| 22:48:23.667 | 11931 | activity | 493 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1709 |
| 22:48:23.692 | 11956 | host-cmd |  | return_sent |  |
| 22:48:23.736 | 12000 | java-log | 493 | PlatformVideoView: surfaceCreated: handle=498743536208, width=668, height=360, viewIdentity=218943113 | L1719 |
| 22:48:23.736 | 12000 | java | 493 | mono=415324112 tid=493 thr=main java surfaceCreated enter handle=498743536208 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1720 |
| 22:48:23.741 | 12005 | java-log | 493 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743536208, transfer=pq, applied=true | L1735 |
| 22:48:23.741 | 12005 | java-log | 493 | PlatformVideoView: surfaceCreated: created new wid=1050522 | L1737 |
| 22:48:23.742 | 12006 | java | 493 | mono=415324117 tid=493 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743536208 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=1050522 | L1738 |
| 22:48:23.742 | 12006 | java | 493 | mono=415324117 tid=493 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743536208 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=1050522 | L1739 |
| 22:48:23.742 | 12006 | dart | 493 | dart event SurfaceAvailable handle=498743536208 wid=1050522 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1740 |
| 22:48:23.742 | 12006 | dart | 493 | dart bind requested wid=1050522 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1741 |
| 22:48:23.742 | 12006 | dart | 493 | dart bind lock acquired wid=1050522 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1742 |
| 22:48:23.742 | 12006 | dart | 493 | dart bind branch=rebind wid=1050522 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1743 |
| 22:48:23.742 | 12006 | java | 493 | mono=415324118 tid=493 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743536208 viewId=1 surfaceGeneration=2 wid=1050522 | L1744 |
| 22:48:23.743 | 12007 | java | 493 | mono=415324118 tid=493 thr=main java surfaceCreated exit handle=498743536208 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=1050522 | L1745 |
| 22:48:23.743 | 12007 | java-log | 493 | PlatformVideoView: surfaceChanged: handle=498743536208, format=43, width=2672, height=1336, wid=1050522 | L1746 |
| 22:48:23.774 | 12038 | dart | 493 | dart apply begin wid=1050522 vo=gpu-next vid=auto | L1753 |
| 22:48:23.774 | 12038 | dart | 493 | dart property begin vo=null | L1754 |
| 22:48:23.808 | 12072 | dart | 493 | dart property complete vo=null | L1759 |
| 22:48:23.808 | 12072 | dart | 493 | dart authorize begin wid=1050522 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1760 |
| 22:48:23.836 | 12100 | java-log | 493 | PlatformVideoView: surfaceChanged: handle=498743536208, format=43, width=2672, height=1440, wid=1050522 | L1773 |
| 22:48:23.857 | 12121 | java | 493 | mono=415324233 tid=493 thr=main java authorize enter handle=498743536208 generation=2 viewId=1 surfaceGeneration=2 wid=1050522 ownerTokenPresent=true | L1776 |
| 22:48:23.857 | 12121 | java | 493 | mono=415324233 tid=493 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=8793159320474925283 libraryLoaded=true | L1777 |
| 22:48:23.857 | 12121 | native | 493 | mono=415324233 tid=493 egl_ctx=0x7427534280 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=8793159320474925283 req_generation=2 | L1778 |
| 22:48:23.857 | 12121 | native | 493 | mono=415324233 tid=493 egl_ctx=0x7427534280 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=8793159320474925283 req_generation=2 resources_ready=1 | L1779 |
| 22:48:23.858 | 12122 | native | 493 | mono=415324233 tid=493 egl_ctx=0x7427534280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=8793159320474925283 generation=2 rc=0 | L1781 |
| 22:48:23.858 | 12122 | java | 493 | mono=415324233 tid=493 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=8793159320474925283 | L1782 |
| 22:48:23.858 | 12122 | java | 493 | mono=415324233 tid=493 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=1050522 | L1783 |
| 22:48:23.886 | 12150 | dart | 493 | dart authorize result epoch=2 wid=1050522 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1789 |
| 22:48:23.886 | 12150 | dart | 493 | dart property begin android-surface-size=2672x1336 | L1790 |
| 22:48:23.889 | 12153 | dart | 493 | dart property complete android-surface-size=2672x1336 | L1791 |
| 22:48:23.890 | 12154 | dart | 493 | dart property begin wid=1050522 | L1792 |
| 22:48:23.891 | 12155 | dart | 493 | dart property complete wid=1050522 | L1793 |
| 22:48:23.891 | 12155 | dart | 493 | dart property begin vo=gpu-next | L1794 |
| 22:48:23.895 | 12159 | mpv | 493 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1807 |
| 22:48:23.916 | 12180 | dart | 493 | dart property complete vo=gpu-next | L1824 |
| 22:48:23.916 | 12180 | dart | 493 | dart property begin vid=auto | L1825 |
| 22:48:23.931 | 12195 | native | 726 | mono=415324307 tid=726 egl_ctx=0x7414a76280 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=8793159320474925283 generation=2  | L1837 |
| 22:48:23.931 | 12195 | native | 726 | mono=415324307 tid=726 egl_ctx=0x7414a76280 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=8793159320474925283 generation=2 ready=1 | L1838 |
| 22:48:23.931 | 12195 | native | 726 | mono=415324307 tid=726 egl_ctx=0x7414a76280 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=8793159320474925283 generation=2  | L1839 |
| 22:48:23.933 | 12197 | native | 726 | mono=415324309 tid=726 egl_ctx=0x7414a76280 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=8793159320474925283 generation=2 result=ok window=0x741f772210 | L1841 |
| 22:48:23.935 | 12199 | codec | 538 | ACodec  : Now uninitialized | L1844 |
| 22:48:23.937 | 12201 | mpv | 493 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1847 |
| 22:48:23.953 | 12217 | codec | 729 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1861 |
| 22:48:23.963 | 12227 | codec | 729 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1881 |
| 22:48:24.016 | 12280 | codec | 729 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1884 |
| 22:48:24.027 | 12291 | codec | 729 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1889 |
| 22:48:24.027 | 12291 | codec | 729 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1890 |
| 22:48:24.038 | 12302 | dart | 493 | dart property complete vid=auto | L1891 |
| 22:48:24.038 | 12302 | dart | 493 | dart apply complete wid=1050522 | L1892 |
| 22:48:24.038 | 12302 | dart | 493 | dart bind complete wid=1050522 surfaceGeneration=2 | L1893 |
| 22:48:24.038 | 12302 | dart | 493 | dart bind lock released wid=1050522 surfaceGeneration=2 | L1894 |
| 22:48:24.039 | 12303 | dart-videoparams | 493 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1895 |
| 22:48:24.064 | 12328 | codec | 729 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1898 |
| 22:48:24.073 | 12337 | codec | 729 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1900 |
| 22:48:24.143 | 12407 | codec | 729 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1901 |
| 22:48:24.195 | 12459 | dart-videoparams | 493 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1906 |
| 22:48:24.201 | 12465 | dart | 493 | dart size property complete android-surface-size=2672x1336 | L1908 |
| 22:48:24.252 | 12516 | java-log | 493 | PlatformVideoView: surfaceChanged: handle=498743536208, format=43, width=2672, height=1336, wid=1050522 | L1909 |
| 22:48:45.894 | 34158 | host-cmd |  | pid_after pid_before=493 pid_after=493 |  |
| 22:48:46.070 | 34334 | host-cmd |  | sf_dump sf-post-return.txt lines=     365 |  |
| 22:48:47.349 | 35613 | host-cmd |  | full_dump lines=    1986 |  |
| 22:48:48.107 | 36371 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 22:48:50.046 | 38310 | host-cmd |  | round_end |  |
