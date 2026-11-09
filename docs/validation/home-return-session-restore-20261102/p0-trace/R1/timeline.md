# Timeline R1

App PID filter: 17022 (ActivityManager am_pause/resume lines kept from system_server).

Source: `R1/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 17:20:00.474 | 0 | L0 |
| home_sent(host probe after cmd returned) | 17:20:02.845 | 2371 | L0 |
| am_pause_lab | 17:20:01.855 | 1381 | L1461 |
| java_surfaceDestroyed_enter | 17:20:02.194 | 1720 | L1507 |
| java_send_SurfaceDestroyed | 17:20:02.202 | 1728 | L1510 |
| dart_event_SurfaceDestroyed | 17:20:02.209 | 1735 | L1513 |
| dart_detach_lock_acquired | 17:20:02.213 | 1739 | L1515 |
| dart_detach_vo_null_begin | 17:20:02.213 | 1739 | L1518 |
| native_shutdown_enter | 17:20:02.344 | 1870 | L1549 |
| native_shutdown_exit | 17:20:02.345 | 1871 | L1551 |
| dart_detach_vo_null_ack | 17:20:02.456 | 1982 | L1578 |
| dart_detach_wid0_ack | 17:20:03.540 | 3066 | L1678 |
| dart_detach_apply_complete | 17:20:04.570 | 4096 | L1699 |
| dart_detach_lock_released | 17:20:04.579 | 4105 | L1705 |
| return_sent | 17:20:13.684 | 13210 | L0 |
| am_resume_lab | 17:20:13.657 | 13183 | L1812 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | — | — | — |
| java_surfaceCreated_enter | 17:20:13.755 | 13281 | L1835 |
| java_send_SurfaceAvailable | 17:20:13.761 | 13287 | L1852 |
| dart_event_SurfaceAvailable | 17:20:13.761 | 13287 | L1853 |
| dart_bind_requested | 17:20:13.761 | 13287 | L1854 |
| dart_bind_lock_acquired | 17:20:13.761 | 13287 | L1855 |
| dart_bind_vo_gpu_next_begin | 17:20:13.855 | 13381 | L1891 |
| native_ensure_init_exit | 17:20:13.908 | 13434 | L1910 |
| native_create_exit | — | — | — |
| mpv_egl_window_surface | 17:20:13.911 | 13437 | L1915 |
| mpv_bridge_not_initialized | 17:20:14.004 | 13530 | L1950 |
| dart_bind_complete | 17:20:13.924 | 13450 | L1927 |
| first_videoparams_after_return | 17:20:14.579 | 14105 | L1995 |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 11410 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 111 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 2225 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 11563 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 151 |
| dart_vo_null_begin -> shutdown_enter (ms) | 131 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 6 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 9182 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | -9182 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | 96 |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | 824 |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 1720 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | 71 |

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
| 17:19:36.468 | -24006 | host-cmd |  | round_begin launch=fresh home=normal pkg=com.example.media_kit_hdr_lab |  |
| 17:19:38.275 | -22199 | host-cmd |  | force_stop pid_after= |  |
| 17:19:38.410 | -22064 | host-cmd |  | logcat_cleared |  |
| 17:19:39.145 | -21329 | host-cmd |  | am_start_fresh pid=17022 |  |
| 17:19:43.861 | -16613 | java | 17022 | mono=399632737 tid=17022 thr=main java factory.create enter handle=499363203152 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L502 |
| 17:19:43.862 | -16612 | java | 17022 | mono=399632739 tid=17022 thr=main java factory.create view constructed handle=499363203152 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L503 |
| 17:19:43.862 | -16612 | java | 17022 | mono=399632739 tid=17022 thr=main java setLgExperimentOwner enter handle=499363203152 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L504 |
| 17:19:43.862 | -16612 | java | 17022 | mono=399632739 tid=17022 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=-5327812099474220025 libraryLoaded=false | L505 |
| 17:19:43.863 | -16611 | native | 17022 | mono=399632740 tid=17022 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=13118931974235331591 req_generation=1 | L506 |
| 17:19:43.865 | -16609 | native | 17022 | mono=399632742 tid=17022 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=13118931974235331591 req_generation=1 resources_ready=1 | L508 |
| 17:19:43.865 | -16609 | native | 17022 | mono=399632742 tid=17022 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=13118931974235331591 generation=1 rc=0 | L510 |
| 17:19:43.865 | -16609 | java | 17022 | mono=399632742 tid=17022 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=-5327812099474220025 | L511 |
| 17:19:43.865 | -16609 | java | 17022 | mono=399632742 tid=17022 thr=main java setLgExperimentOwner exit handle=499363203152 viewId=0 ownerGeneration=1 ensureInitialized=ok | L512 |
| 17:19:43.866 | -16608 | java | 17022 | mono=399632742 tid=17022 thr=main java factory.create setLgExperimentOwner returned handle=499363203152 viewId=0 | L513 |
| 17:19:43.866 | -16608 | java | 17022 | mono=399632742 tid=17022 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=499363203152 viewId=0 ownerGeneration=1 creationSerial=1 | L514 |
| 17:19:43.867 | -16607 | java | 17022 | mono=399632743 tid=17022 thr=main java factory.create exit handle=499363203152 viewId=0 | L516 |
| 17:19:43.909 | -16565 | java-log | 17022 | PlatformVideoView: surfaceCreated: handle=499363203152, width=668, height=360, viewIdentity=235825235 | L517 |
| 17:19:43.909 | -16565 | java | 17022 | mono=399632786 tid=17022 thr=main java surfaceCreated enter handle=499363203152 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L518 |
| 17:19:43.920 | -16554 | java-log | 17022 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L520 |
| 17:19:43.920 | -16554 | java | 17022 | mono=399632796 tid=17022 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499363203152 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L521 |
| 17:19:43.920 | -16554 | java | 17022 | mono=399632797 tid=17022 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499363203152 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L522 |
| 17:19:43.921 | -16553 | java | 17022 | mono=399632798 tid=17022 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499363203152 viewId=0 surfaceGeneration=1 wid=2099350 | L527 |
| 17:19:43.921 | -16553 | java | 17022 | mono=399632798 tid=17022 thr=main java surfaceCreated exit handle=499363203152 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L528 |
| 17:19:43.929 | -16545 | host-cmd |  | tap_open x=1440 y=720 |  |
| 17:19:45.109 | -15365 | java | 17022 | mono=399633985 tid=17022 thr=main java factory.create enter handle=499363203152 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L959 |
| 17:19:45.110 | -15364 | java | 17022 | mono=399633987 tid=17022 thr=main java factory.create view constructed handle=499363203152 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L961 |
| 17:19:45.110 | -15364 | java | 17022 | mono=399633987 tid=17022 thr=main java setLgExperimentOwner enter handle=499363203152 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L962 |
| 17:19:45.111 | -15363 | java | 17022 | mono=399633987 tid=17022 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-5327812099474220025 libraryLoaded=true | L963 |
| 17:19:45.111 | -15363 | native | 17022 | mono=399633987 tid=17022 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=13118931974235331591 generation=1 req_owner_key=13118931974235331591 req_generation=2 | L964 |
| 17:19:45.111 | -15363 | native | 17022 | mono=399633987 tid=17022 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=13118931974235331591 generation=1 req_owner_key=13118931974235331591 req_generation=2 resources_ready=1 | L965 |
| 17:19:45.111 | -15363 | native | 17022 | mono=399633987 tid=17022 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=13118931974235331591 generation=2 rc=0 | L967 |
| 17:19:45.111 | -15363 | java | 17022 | mono=399633987 tid=17022 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-5327812099474220025 | L968 |
| 17:19:45.111 | -15363 | java | 17022 | mono=399633987 tid=17022 thr=main java setLgExperimentOwner exit handle=499363203152 viewId=1 ownerGeneration=2 ensureInitialized=ok | L969 |
| 17:19:45.111 | -15363 | java | 17022 | mono=399633987 tid=17022 thr=main java factory.create setLgExperimentOwner returned handle=499363203152 viewId=1 | L970 |
| 17:19:45.111 | -15363 | java | 17022 | mono=399633987 tid=17022 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=499363203152 viewId=1 ownerGeneration=2 creationSerial=2 | L971 |
| 17:19:45.112 | -15362 | java | 17022 | mono=399633988 tid=17022 thr=main java factory.create exit handle=499363203152 viewId=1 | L973 |
| 17:19:45.157 | -15317 | java-log | 17022 | PlatformVideoView: surfaceCreated: handle=499363203152, width=668, height=360, viewIdentity=207085198 | L977 |
| 17:19:45.157 | -15317 | java | 17022 | mono=399634034 tid=17022 thr=main java surfaceCreated enter handle=499363203152 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L978 |
| 17:19:45.168 | -15306 | java-log | 17022 | PlatformVideoView: surfaceCreated initial dataspace: handle=499363203152, transfer=pq, applied=true | L991 |
| 17:19:45.169 | -15305 | java-log | 17022 | PlatformVideoView: surfaceCreated: created new wid=2242 | L993 |
| 17:19:45.169 | -15305 | java | 17022 | mono=399634045 tid=17022 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499363203152 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=2242 | L994 |
| 17:19:45.169 | -15305 | java | 17022 | mono=399634045 tid=17022 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499363203152 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2242 | L995 |
| 17:19:45.169 | -15305 | java | 17022 | mono=399634046 tid=17022 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499363203152 viewId=1 surfaceGeneration=1 wid=2242 | L1000 |
| 17:19:45.170 | -15304 | java | 17022 | mono=399634046 tid=17022 thr=main java surfaceCreated exit handle=499363203152 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2242 | L1001 |
| 17:19:45.413 | -15061 | native | 17100 | mono=399634289 tid=17100 egl_ctx=0x741a2de780 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=13118931974235331591 generation=2  | L1049 |
| 17:19:45.413 | -15061 | native | 17100 | mono=399634289 tid=17100 egl_ctx=0x741a2de780 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=13118931974235331591 generation=2 ready=1 | L1050 |
| 17:19:45.413 | -15061 | native | 17100 | mono=399634289 tid=17100 egl_ctx=0x741a2de780 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=13118931974235331591 generation=2  | L1051 |
| 17:19:45.415 | -15059 | native | 17100 | mono=399634292 tid=17100 egl_ctx=0x741a2de780 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=13118931974235331591 generation=2 result=ok window=0x7418e21c10 | L1053 |
| 17:20:00.204 | -270 | host-cmd |  | interim_dump lines=    1381 |  |
| 17:20:00.386 | -88 | host-cmd |  | pid_before pid=17022 |  |
| 17:20:00.474 | 0 | host-cmd |  | home_send_begin |  |
| 17:20:01.855 | 1381 | activity | 2062 | am_pause_activity: [0,189838829,com.example.media_kit_hdr_lab/.MainActivity] | L1461 |
| 17:20:01.859 | 1385 | activity | 17022 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1462 |
| 17:20:02.042 | 1568 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1487 |
| 17:20:02.194 | 1720 | java-log | 17022 | PlatformVideoView: surfaceDestroyed: handle=499363203152, wid=2242 | L1506 |
| 17:20:02.194 | 1720 | java | 17022 | mono=399651070 tid=17022 thr=main java surfaceDestroyed enter handle=499363203152 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2242 disposed=false | L1507 |
| 17:20:02.200 | 1726 | java | 17022 | mono=399651077 tid=17022 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=499363203152 viewId=1 surfaceGeneration=1 wid=2242 | L1509 |
| 17:20:02.202 | 1728 | java | 17022 | mono=399651078 tid=17022 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=499363203152 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2242 | L1510 |
| 17:20:02.209 | 1735 | dart | 17022 | dart event SurfaceDestroyed handle=499363203152 wid=2242 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=2242 boundSurfaceGeneration=1 | L1513 |
| 17:20:02.213 | 1739 | dart | 17022 | dart detach requested wid=2242 surfaceGeneration=1 generation=2 viewId=1 | L1514 |
| 17:20:02.213 | 1739 | dart | 17022 | dart detach lock acquired wid=2242 surfaceGeneration=1 generation=2 viewId=1 boundWid=2242 boundSurfaceGeneration=1 | L1515 |
| 17:20:02.213 | 1739 | dart | 17022 | dart detach decision wid=2242 isCurrentOutput=true isInFlightOutput=false | L1516 |
| 17:20:02.213 | 1739 | dart | 17022 | dart apply begin wid=0 vo=null vid=no | L1517 |
| 17:20:02.213 | 1739 | dart | 17022 | dart property begin vo=null | L1518 |
| 17:20:02.216 | 1742 | codec | 17106 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 11/16 output). | L1519 |
| 17:20:02.217 | 1743 | codec | 17106 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1520 |
| 17:20:02.221 | 1747 | codec | 17106 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1524 |
| 17:20:02.225 | 1751 | java | 17022 | mono=399651101 tid=17022 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=499363203152 viewId=1 surfaceGeneration=1 wid=2242 | L1526 |
| 17:20:02.225 | 1751 | java | 17022 | mono=399651101 tid=17022 thr=main java surfaceDestroyed exit handle=499363203152 viewId=1 sentEvent=true wid=0 | L1527 |
| 17:20:02.231 | 1757 | codec | 17106 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1528 |
| 17:20:02.287 | 1813 | codec | 17106 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1536 |
| 17:20:02.289 | 1815 | codec | 17106 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1537 |
| 17:20:02.327 | 1853 | codec | 17106 | ACodec  : Now uninitialized | L1545 |
| 17:20:02.344 | 1870 | activity | 17022 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1548 |
| 17:20:02.344 | 1870 | native | 17100 | mono=399651221 tid=17100 egl_ctx=0x741a2de780 native mkst_shutdown enter initialized=1 window_active=1 owner_key=13118931974235331591 generation=2  | L1549 |
| 17:20:02.345 | 1871 | native | 17100 | mono=399651221 tid=17100 egl_ctx=0x741a2de780 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=482 latched=482 | L1551 |
| 17:20:02.456 | 1982 | dart | 17022 | dart property complete vo=null | L1578 |
| 17:20:02.456 | 1982 | dart | 17022 | dart property begin android-surface-size=2672x1336 | L1579 |
| 17:20:02.845 | 2371 | host-cmd |  | home_sent |  |
| 17:20:02.969 | 2495 | dart | 17022 | dart property complete android-surface-size=2672x1336 | L1672 |
| 17:20:02.969 | 2495 | dart | 17022 | dart property begin wid=0 | L1673 |
| 17:20:02.977 | 2503 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1674 |
| 17:20:03.540 | 3066 | dart | 17022 | dart property complete wid=0 | L1678 |
| 17:20:03.540 | 3066 | dart | 17022 | dart property begin vo=null | L1679 |
| 17:20:04.032 | 3558 | dart | 17022 | dart property complete vo=null | L1696 |
| 17:20:04.033 | 3559 | dart | 17022 | dart property begin vid=no | L1697 |
| 17:20:04.570 | 4096 | dart | 17022 | dart property complete vid=no | L1698 |
| 17:20:04.570 | 4096 | dart | 17022 | dart apply complete wid=0 | L1699 |
| 17:20:04.570 | 4096 | dart | 17022 | dart detach producer stopped wid=2242 | L1700 |
| 17:20:04.577 | 4103 | java-log | 17022 | PlatformVideoView: releaseSurface generation=1 wid=2242 result=released | L1702 |
| 17:20:04.579 | 4105 | dart | 17022 | dart detach reference released wid=2242 | L1704 |
| 17:20:04.579 | 4105 | dart | 17022 | dart detach lock released wid=2242 surfaceGeneration=1 | L1705 |
| 17:20:12.946 | 12472 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity |  |
| 17:20:13.526 | 13052 | activity | 19184 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1776 |
| 17:20:13.657 | 13183 | activity | 2535 | am_resume_activity: [0,189838829,1020,com.example.media_kit_hdr_lab/.MainActivity] | L1812 |
| 17:20:13.680 | 13206 | activity | 17022 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1817 |
| 17:20:13.684 | 13210 | host-cmd |  | return_sent |  |
| 17:20:13.755 | 13281 | java-log | 17022 | PlatformVideoView: surfaceCreated: handle=499363203152, width=668, height=360, viewIdentity=207085198 | L1834 |
| 17:20:13.755 | 13281 | java | 17022 | mono=399662632 tid=17022 thr=main java surfaceCreated enter handle=499363203152 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1835 |
| 17:20:13.761 | 13287 | java-log | 17022 | PlatformVideoView: surfaceCreated initial dataspace: handle=499363203152, transfer=pq, applied=true | L1848 |
| 17:20:13.761 | 13287 | java-log | 17022 | PlatformVideoView: surfaceCreated: created new wid=2162 | L1850 |
| 17:20:13.761 | 13287 | java | 17022 | mono=399662637 tid=17022 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499363203152 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2162 | L1851 |
| 17:20:13.761 | 13287 | java | 17022 | mono=399662637 tid=17022 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499363203152 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2162 | L1852 |
| 17:20:13.761 | 13287 | dart | 17022 | dart event SurfaceAvailable handle=499363203152 wid=2162 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1853 |
| 17:20:13.761 | 13287 | dart | 17022 | dart bind requested wid=2162 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1854 |
| 17:20:13.761 | 13287 | dart | 17022 | dart bind lock acquired wid=2162 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1855 |
| 17:20:13.761 | 13287 | dart | 17022 | dart bind branch=rebind wid=2162 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1856 |
| 17:20:13.762 | 13288 | java | 17022 | mono=399662638 tid=17022 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499363203152 viewId=1 surfaceGeneration=2 wid=2162 | L1857 |
| 17:20:13.762 | 13288 | java | 17022 | mono=399662638 tid=17022 thr=main java surfaceCreated exit handle=499363203152 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2162 | L1858 |
| 17:20:13.762 | 13288 | java-log | 17022 | PlatformVideoView: surfaceChanged: handle=499363203152, format=43, width=2672, height=1336, wid=2162 | L1859 |
| 17:20:13.788 | 13314 | java-log | 17022 | PlatformVideoView: surfaceChanged: handle=499363203152, format=43, width=2672, height=1440, wid=2162 | L1867 |
| 17:20:13.791 | 13317 | dart | 17022 | dart apply begin wid=2162 vo=gpu-next vid=auto | L1868 |
| 17:20:13.791 | 13317 | dart | 17022 | dart property begin vo=null | L1869 |
| 17:20:13.804 | 13330 | dart | 17022 | dart property complete vo=null | L1874 |
| 17:20:13.805 | 13331 | dart | 17022 | dart property begin android-surface-size=2672x1336 | L1875 |
| 17:20:13.832 | 13358 | dart | 17022 | dart property complete android-surface-size=2672x1336 | L1880 |
| 17:20:13.832 | 13358 | dart | 17022 | dart property begin wid=2162 | L1881 |
| 17:20:13.854 | 13380 | dart | 17022 | dart property complete wid=2162 | L1890 |
| 17:20:13.855 | 13381 | dart | 17022 | dart property begin vo=gpu-next | L1891 |
| 17:20:13.904 | 13430 | dart | 17022 | dart property complete vo=gpu-next | L1901 |
| 17:20:13.904 | 13430 | dart | 17022 | dart property begin vid=auto | L1902 |
| 17:20:13.908 | 13434 | native | 17188 | mono=399662784 tid=17188 egl_ctx=0x741dbfc600 native mkst_ensure_init(lc_verify) enter initialized=0 window_active=0 owner_key=0 generation=0  | L1908 |
| 17:20:13.908 | 13434 | native | 17188 | mono=399662785 tid=17188 egl_ctx=0x741dbfc600 native mkst_ensure_init(lc_verify) exit initialized=0 window_active=0 owner_key=0 generation=0 ready=0 | L1910 |
| 17:20:13.911 | 13437 | mpv | 17022 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1915 |
| 17:20:13.924 | 13450 | dart | 17022 | dart property complete vid=auto | L1925 |
| 17:20:13.924 | 13450 | dart | 17022 | dart apply complete wid=2162 | L1926 |
| 17:20:13.924 | 13450 | dart | 17022 | dart bind complete wid=2162 surfaceGeneration=2 | L1927 |
| 17:20:13.924 | 13450 | dart | 17022 | dart bind lock released wid=2162 surfaceGeneration=2 | L1928 |
| 17:20:14.004 | 13530 | mpv | 17022 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1949 |
| 17:20:14.004 | 13530 | mpv | 17022 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: bridge not initialized (verify-only ensure_init; Java side owns init) | L1950 |
| 17:20:14.439 | 13965 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1983 |
| 17:20:14.579 | 14105 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L1995 |
| 17:20:14.584 | 14110 | dart | 17022 | dart size property complete android-surface-size=2672x1336 | L1997 |
| 17:20:14.633 | 14159 | java-log | 17022 | PlatformVideoView: surfaceChanged: handle=499363203152, format=43, width=2672, height=1336, wid=2162 | L2011 |
| 17:20:14.761 | 14287 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L2020 |
| 17:20:15.015 | 14541 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L2021 |
| 17:20:15.126 | 14652 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L2022 |
| 17:20:15.497 | 15023 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L2023 |
| 17:20:15.662 | 15188 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L2030 |
| 17:20:15.957 | 15483 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L2032 |
| 17:20:16.263 | 15789 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L2034 |
| 17:20:16.619 | 16145 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L2035 |
| 17:20:16.979 | 16505 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L2036 |
| 17:20:17.105 | 16631 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L2037 |
| 17:20:17.495 | 17021 | dart-videoparams | 17022 | VIDEOPARAMS VideoParams(pixelformat: yuv420p10, ...) | L2038 |
| 17:20:33.941 | 33467 | host-cmd |  | pid_after pid_before=17022 pid_after=17022 |  |
| 17:20:34.527 | 34053 | host-cmd |  | full_dump lines=    2079 |  |
| 17:20:34.690 | 34216 | host-cmd |  | round_end |  |
