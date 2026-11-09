# Timeline smoke-prefix

App PID filter: 29015 (ActivityManager am_pause/resume lines kept from system_server).

Source: `smoke-prefix/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 20:58:23.123 | 0 | L0 |
| home_sent(host probe after cmd returned) | 20:58:25.084 | 1961 | L0 |
| am_pause_lab | 20:58:24.391 | 1268 | L1386 |
| java_surfaceDestroyed_enter | 20:58:24.659 | 1536 | L1425 |
| java_send_SurfaceDestroyed | 20:58:24.676 | 1553 | L1428 |
| dart_event_SurfaceDestroyed | 20:58:24.724 | 1601 | L1432 |
| dart_detach_lock_acquired | 20:58:24.724 | 1601 | L1434 |
| dart_detach_vo_null_begin | 20:58:24.724 | 1601 | L1437 |
| native_shutdown_enter | 20:58:24.852 | 1729 | L1481 |
| native_shutdown_exit | 20:58:24.854 | 1731 | L1483 |
| dart_detach_vo_null_ack | 20:58:24.937 | 1814 | L1524 |
| dart_detach_wid0_ack | 20:58:26.049 | 2926 | L1606 |
| dart_detach_apply_complete | 20:58:26.988 | 3865 | L1630 |
| dart_detach_lock_released | 20:58:26.998 | 3875 | L1636 |
| return_sent | 20:58:36.133 | 13010 | L0 |
| am_resume_lab | 20:58:36.070 | 12947 | L1745 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | 20:58:36.213 | 13090 | L1813 |
| java_surfaceCreated_enter | 20:58:36.125 | 13002 | L1765 |
| java_send_SurfaceAvailable | 20:58:36.131 | 13008 | L1783 |
| dart_event_SurfaceAvailable | 20:58:36.132 | 13009 | L1784 |
| dart_bind_requested | 20:58:36.132 | 13009 | L1785 |
| dart_bind_lock_acquired | 20:58:36.132 | 13009 | L1786 |
| dart_bind_vo_gpu_next_begin | 20:58:36.257 | 13134 | L1837 |
| native_ensure_init_exit | 20:58:36.310 | 13187 | L1882 |
| native_create_exit | 20:58:36.311 | 13188 | L1886 |
| mpv_egl_window_surface | 20:58:36.276 | 13153 | L1857 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 20:58:36.385 | 13262 | L1936 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 11271 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 83 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 2134 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 11456 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 195 |
| dart_vo_null_begin -> shutdown_enter (ms) | 128 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 7 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 9134 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | -9134 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 1536 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -8 |

## Counts (whole dump)

| counter | n |
|---|---|
| ensureInitialized_total_in_log | 5 |
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
| 20:57:57.610 | -25513 | host-cmd |  | round_begin launch=fresh home=normal pkg=com.example.media_kit_hdr_lab |  |
| 20:57:59.569 | -23554 | host-cmd |  | force_stop pid_after= |  |
| 20:58:00.209 | -22914 | host-cmd |  | logcat_cleared per-buffer |  |
| 20:58:01.460 | -21663 | host-cmd |  | am_start_fresh pid=29015 |  |
| 20:58:06.026 | -17097 | java | 29015 | mono=408706402 tid=29015 thr=main java factory.create enter handle=498743682640 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L434 |
| 20:58:06.028 | -17095 | java | 29015 | mono=408706403 tid=29015 thr=main java factory.create view constructed handle=498743682640 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L435 |
| 20:58:06.028 | -17095 | java | 29015 | mono=408706403 tid=29015 thr=main java setLgExperimentOwner enter handle=498743682640 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L436 |
| 20:58:06.028 | -17095 | java | 29015 | mono=408706404 tid=29015 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=-6257587330598583288 libraryLoaded=false | L437 |
| 20:58:06.029 | -17094 | native | 29015 | mono=408706405 tid=29015 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=12189156743110968328 req_generation=1 | L438 |
| 20:58:06.030 | -17093 | native | 29015 | mono=408706406 tid=29015 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=12189156743110968328 req_generation=1 resources_ready=1 | L440 |
| 20:58:06.030 | -17093 | native | 29015 | mono=408706406 tid=29015 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=12189156743110968328 generation=1 rc=0 | L442 |
| 20:58:06.030 | -17093 | java | 29015 | mono=408706406 tid=29015 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=-6257587330598583288 | L443 |
| 20:58:06.030 | -17093 | java | 29015 | mono=408706406 tid=29015 thr=main java setLgExperimentOwner exit handle=498743682640 viewId=0 ownerGeneration=1 ensureInitialized=ok | L444 |
| 20:58:06.030 | -17093 | java | 29015 | mono=408706406 tid=29015 thr=main java factory.create setLgExperimentOwner returned handle=498743682640 viewId=0 | L445 |
| 20:58:06.031 | -17092 | java | 29015 | mono=408706406 tid=29015 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743682640 viewId=0 ownerGeneration=1 creationSerial=1 | L446 |
| 20:58:06.032 | -17091 | java | 29015 | mono=408706407 tid=29015 thr=main java factory.create exit handle=498743682640 viewId=0 | L448 |
| 20:58:06.078 | -17045 | java-log | 29015 | PlatformVideoView: surfaceCreated: handle=498743682640, width=668, height=360, viewIdentity=235825235 | L449 |
| 20:58:06.078 | -17045 | java | 29015 | mono=408706454 tid=29015 thr=main java surfaceCreated enter handle=498743682640 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L450 |
| 20:58:06.085 | -17038 | java-log | 29015 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L452 |
| 20:58:06.085 | -17038 | java | 29015 | mono=408706460 tid=29015 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743682640 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L453 |
| 20:58:06.085 | -17038 | java | 29015 | mono=408706461 tid=29015 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743682640 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L454 |
| 20:58:06.087 | -17036 | java | 29015 | mono=408706463 tid=29015 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743682640 viewId=0 surfaceGeneration=1 wid=2099350 | L459 |
| 20:58:06.087 | -17036 | java | 29015 | mono=408706463 tid=29015 thr=main java surfaceCreated exit handle=498743682640 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L460 |
| 20:58:06.128 | -16995 | java | 29015 | mono=408706504 tid=29015 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=-6257587330598583288 libraryLoaded=true | L468 |
| 20:58:06.128 | -16995 | native | 29015 | mono=408706504 tid=29015 egl_ctx=0x742352f280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=12189156743110968328 generation=1 req_owner_key=12189156743110968328 req_generation=1 | L469 |
| 20:58:06.128 | -16995 | native | 29015 | mono=408706504 tid=29015 egl_ctx=0x742352f280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=12189156743110968328 generation=1 req_owner_key=12189156743110968328 req_generation=1 resources_ready=1 | L470 |
| 20:58:06.128 | -16995 | native | 29015 | mono=408706504 tid=29015 egl_ctx=0x742352f280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=12189156743110968328 generation=1 rc=0 | L472 |
| 20:58:06.128 | -16995 | java | 29015 | mono=408706504 tid=29015 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=-6257587330598583288 | L473 |
| 20:58:06.413 | -16710 | host-cmd |  | tap_open x=1440 y=720 |  |
| 20:58:07.111 | -16012 | java | 29015 | mono=408707487 tid=29015 thr=main java factory.create enter handle=498743682640 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L851 |
| 20:58:07.122 | -16001 | java | 29015 | mono=408707498 tid=29015 thr=main java factory.create view constructed handle=498743682640 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L853 |
| 20:58:07.122 | -16001 | java | 29015 | mono=408707498 tid=29015 thr=main java setLgExperimentOwner enter handle=498743682640 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L854 |
| 20:58:07.122 | -16001 | java | 29015 | mono=408707498 tid=29015 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-6257587330598583288 libraryLoaded=true | L855 |
| 20:58:07.122 | -16001 | native | 29015 | mono=408707498 tid=29015 egl_ctx=0x0 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=12189156743110968328 generation=1 req_owner_key=12189156743110968328 req_generation=2 | L856 |
| 20:58:07.122 | -16001 | native | 29015 | mono=408707498 tid=29015 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=12189156743110968328 generation=1 req_owner_key=12189156743110968328 req_generation=2 resources_ready=1 | L857 |
| 20:58:07.122 | -16001 | native | 29015 | mono=408707498 tid=29015 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=12189156743110968328 generation=2 rc=0 | L859 |
| 20:58:07.122 | -16001 | java | 29015 | mono=408707498 tid=29015 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-6257587330598583288 | L860 |
| 20:58:07.122 | -16001 | java | 29015 | mono=408707498 tid=29015 thr=main java setLgExperimentOwner exit handle=498743682640 viewId=1 ownerGeneration=2 ensureInitialized=ok | L861 |
| 20:58:07.122 | -16001 | java | 29015 | mono=408707498 tid=29015 thr=main java factory.create setLgExperimentOwner returned handle=498743682640 viewId=1 | L862 |
| 20:58:07.122 | -16001 | java | 29015 | mono=408707498 tid=29015 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743682640 viewId=1 ownerGeneration=2 creationSerial=2 | L863 |
| 20:58:07.123 | -16000 | java | 29015 | mono=408707499 tid=29015 thr=main java factory.create exit handle=498743682640 viewId=1 | L865 |
| 20:58:07.170 | -15953 | java-log | 29015 | PlatformVideoView: surfaceCreated: handle=498743682640, width=668, height=360, viewIdentity=207085198 | L866 |
| 20:58:07.171 | -15952 | java | 29015 | mono=408707547 tid=29015 thr=main java surfaceCreated enter handle=498743682640 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L867 |
| 20:58:07.176 | -15947 | java-log | 29015 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743682640, transfer=pq, applied=true | L880 |
| 20:58:07.177 | -15946 | java-log | 29015 | PlatformVideoView: surfaceCreated: created new wid=2170 | L882 |
| 20:58:07.177 | -15946 | java | 29015 | mono=408707552 tid=29015 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743682640 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=2170 | L883 |
| 20:58:07.177 | -15946 | java | 29015 | mono=408707553 tid=29015 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743682640 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2170 | L884 |
| 20:58:07.178 | -15945 | java | 29015 | mono=408707553 tid=29015 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743682640 viewId=1 surfaceGeneration=1 wid=2170 | L889 |
| 20:58:07.178 | -15945 | java | 29015 | mono=408707553 tid=29015 thr=main java surfaceCreated exit handle=498743682640 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2170 | L890 |
| 20:58:07.230 | -15893 | java | 29015 | mono=408707606 tid=29015 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-6257587330598583288 libraryLoaded=true | L897 |
| 20:58:07.231 | -15892 | native | 29015 | mono=408707606 tid=29015 egl_ctx=0x742352f280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=12189156743110968328 generation=2 req_owner_key=12189156743110968328 req_generation=2 | L898 |
| 20:58:07.231 | -15892 | native | 29015 | mono=408707606 tid=29015 egl_ctx=0x742352f280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=12189156743110968328 generation=2 req_owner_key=12189156743110968328 req_generation=2 resources_ready=1 | L899 |
| 20:58:07.231 | -15892 | native | 29015 | mono=408707606 tid=29015 egl_ctx=0x742352f280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=12189156743110968328 generation=2 rc=0 | L901 |
| 20:58:07.231 | -15892 | java | 29015 | mono=408707606 tid=29015 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-6257587330598583288 | L902 |
| 20:58:07.406 | -15717 | native | 29099 | mono=408707782 tid=29099 egl_ctx=0x741d4e4600 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=12189156743110968328 generation=2  | L939 |
| 20:58:07.406 | -15717 | native | 29099 | mono=408707782 tid=29099 egl_ctx=0x741d4e4600 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=12189156743110968328 generation=2 ready=1 | L940 |
| 20:58:07.406 | -15717 | native | 29099 | mono=408707782 tid=29099 egl_ctx=0x741d4e4600 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=12189156743110968328 generation=2  | L941 |
| 20:58:07.408 | -15715 | native | 29099 | mono=408707783 tid=29099 egl_ctx=0x741d4e4600 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=12189156743110968328 generation=2 result=ok window=0x741fb2d210 | L943 |
| 20:58:22.742 | -381 | host-cmd |  | interim_dump lines=    1319 |  |
| 20:58:22.987 | -136 | host-cmd |  | pid_before pid=29015 |  |
| 20:58:23.123 | 0 | host-cmd |  | home_send_begin |  |
| 20:58:24.391 | 1268 | activity | 2062 | am_pause_activity: [0,100593138,com.example.media_kit_hdr_lab/.MainActivity] | L1386 |
| 20:58:24.398 | 1275 | activity | 29015 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1387 |
| 20:58:24.596 | 1473 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1408 |
| 20:58:24.654 | 1531 | java-log | 29015 | PlatformVideoView: surfaceDestroyed: handle=498743682640, wid=2170 | L1422 |
| 20:58:24.659 | 1536 | java | 29015 | mono=408725035 tid=29015 thr=main java surfaceDestroyed enter handle=498743682640 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2170 disposed=false | L1425 |
| 20:58:24.667 | 1544 | java | 29015 | mono=408725043 tid=29015 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743682640 viewId=1 surfaceGeneration=1 wid=2170 | L1427 |
| 20:58:24.676 | 1553 | java | 29015 | mono=408725051 tid=29015 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743682640 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=2170 | L1428 |
| 20:58:24.724 | 1601 | dart | 29015 | dart event SurfaceDestroyed handle=498743682640 wid=2170 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=2170 boundSurfaceGeneration=1 | L1432 |
| 20:58:24.724 | 1601 | dart | 29015 | dart detach requested wid=2170 surfaceGeneration=1 generation=2 viewId=1 | L1433 |
| 20:58:24.724 | 1601 | dart | 29015 | dart detach lock acquired wid=2170 surfaceGeneration=1 generation=2 viewId=1 boundWid=2170 boundSurfaceGeneration=1 | L1434 |
| 20:58:24.724 | 1601 | dart | 29015 | dart detach decision wid=2170 isCurrentOutput=true isInFlightOutput=false | L1435 |
| 20:58:24.724 | 1601 | dart | 29015 | dart apply begin wid=0 vo=null vid=no | L1436 |
| 20:58:24.724 | 1601 | dart | 29015 | dart property begin vo=null | L1437 |
| 20:58:24.736 | 1613 | codec | 29105 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 2/4 input, 9/16 output). | L1438 |
| 20:58:24.737 | 1614 | java | 29015 | mono=408725113 tid=29015 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743682640 viewId=1 surfaceGeneration=1 wid=2170 | L1439 |
| 20:58:24.737 | 1614 | java | 29015 | mono=408725113 tid=29015 thr=main java surfaceDestroyed exit handle=498743682640 viewId=1 sentEvent=true wid=0 | L1440 |
| 20:58:24.739 | 1616 | codec | 29105 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1441 |
| 20:58:24.766 | 1643 | codec | 29105 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1446 |
| 20:58:24.786 | 1663 | codec | 29105 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1448 |
| 20:58:24.817 | 1694 | activity | 29015 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1461 |
| 20:58:24.823 | 1700 | codec | 29105 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1465 |
| 20:58:24.823 | 1700 | codec | 29105 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1466 |
| 20:58:24.839 | 1716 | codec | 29105 | ACodec  : Now uninitialized | L1474 |
| 20:58:24.852 | 1729 | native | 29099 | mono=408725228 tid=29099 egl_ctx=0x741d4e4600 native mkst_shutdown enter initialized=1 window_active=1 owner_key=12189156743110968328 generation=2  | L1481 |
| 20:58:24.854 | 1731 | native | 29099 | mono=408725230 tid=29099 egl_ctx=0x741d4e4600 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=501 latched=501 | L1483 |
| 20:58:24.937 | 1814 | dart | 29015 | dart property complete vo=null | L1524 |
| 20:58:24.937 | 1814 | dart | 29015 | dart property begin android-surface-size=2672x1336 | L1525 |
| 20:58:25.084 | 1961 | host-cmd |  | home_sent |  |
| 20:58:25.525 | 2402 | dart | 29015 | dart property complete android-surface-size=2672x1336 | L1583 |
| 20:58:25.526 | 2403 | dart | 29015 | dart property begin wid=0 | L1584 |
| 20:58:25.536 | 2413 | dart-videoparams | 29015 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1585 |
| 20:58:26.049 | 2926 | dart | 29015 | dart property complete wid=0 | L1606 |
| 20:58:26.049 | 2926 | dart | 29015 | dart property begin vo=null | L1607 |
| 20:58:26.486 | 3363 | dart | 29015 | dart property complete vo=null | L1624 |
| 20:58:26.486 | 3363 | dart | 29015 | dart property begin vid=no | L1625 |
| 20:58:26.988 | 3865 | dart | 29015 | dart property complete vid=no | L1629 |
| 20:58:26.988 | 3865 | dart | 29015 | dart apply complete wid=0 | L1630 |
| 20:58:26.988 | 3865 | dart | 29015 | dart detach producer stopped wid=2170 | L1631 |
| 20:58:26.990 | 3867 | java-log | 29015 | PlatformVideoView: releaseSurface generation=1 wid=2170 result=released | L1633 |
| 20:58:26.998 | 3875 | dart | 29015 | dart detach reference released wid=2170 | L1635 |
| 20:58:26.998 | 3875 | dart | 29015 | dart detach lock released wid=2170 surfaceGeneration=1 | L1636 |
| 20:58:35.272 | 12149 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity |  |
| 20:58:35.953 | 12830 | activity | 19360 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1707 |
| 20:58:36.070 | 12947 | activity | 3297 | am_resume_activity: [0,100593138,1037,com.example.media_kit_hdr_lab/.MainActivity] | L1745 |
| 20:58:36.088 | 12965 | activity | 29015 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1755 |
| 20:58:36.125 | 13002 | java-log | 29015 | PlatformVideoView: surfaceCreated: handle=498743682640, width=668, height=360, viewIdentity=207085198 | L1764 |
| 20:58:36.125 | 13002 | java | 29015 | mono=408736500 tid=29015 thr=main java surfaceCreated enter handle=498743682640 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1765 |
| 20:58:36.128 | 13005 | java-log | 29015 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743682640, transfer=pq, applied=true | L1778 |
| 20:58:36.128 | 13005 | java-log | 29015 | PlatformVideoView: surfaceCreated: created new wid=2162 | L1780 |
| 20:58:36.128 | 13005 | java | 29015 | mono=408736504 tid=29015 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743682640 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2162 | L1781 |
| 20:58:36.131 | 13008 | java | 29015 | mono=408736507 tid=29015 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743682640 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2162 | L1783 |
| 20:58:36.132 | 13009 | dart | 29015 | dart event SurfaceAvailable handle=498743682640 wid=2162 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1784 |
| 20:58:36.132 | 13009 | dart | 29015 | dart bind requested wid=2162 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1785 |
| 20:58:36.132 | 13009 | dart | 29015 | dart bind lock acquired wid=2162 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1786 |
| 20:58:36.132 | 13009 | dart | 29015 | dart bind branch=rebind wid=2162 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1787 |
| 20:58:36.132 | 13009 | java | 29015 | mono=408736508 tid=29015 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743682640 viewId=1 surfaceGeneration=2 wid=2162 | L1788 |
| 20:58:36.132 | 13009 | java | 29015 | mono=408736508 tid=29015 thr=main java surfaceCreated exit handle=498743682640 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2162 | L1789 |
| 20:58:36.133 | 13010 | host-cmd |  | return_sent |  |
| 20:58:36.134 | 13011 | java-log | 29015 | PlatformVideoView: surfaceChanged: handle=498743682640, format=43, width=2672, height=1336, wid=2162 | L1790 |
| 20:58:36.153 | 13030 | dart | 29015 | dart apply begin wid=2162 vo=gpu-next vid=auto | L1798 |
| 20:58:36.153 | 13030 | dart | 29015 | dart property begin vo=null | L1799 |
| 20:58:36.159 | 13036 | dart | 29015 | dart property complete vo=null | L1800 |
| 20:58:36.159 | 13036 | dart | 29015 | dart authorize begin wid=2162 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1801 |
| 20:58:36.182 | 13059 | java-log | 29015 | PlatformVideoView: surfaceChanged: handle=498743682640, format=43, width=2672, height=1440, wid=2162 | L1806 |
| 20:58:36.213 | 13090 | java | 29015 | mono=408736588 tid=29015 thr=main java authorize enter handle=498743682640 generation=2 viewId=1 surfaceGeneration=2 wid=2162 ownerTokenPresent=true | L1812 |
| 20:58:36.213 | 13090 | java | 29015 | mono=408736589 tid=29015 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=-6257587330598583288 libraryLoaded=true | L1813 |
| 20:58:36.213 | 13090 | native | 29015 | mono=408736589 tid=29015 egl_ctx=0x742352f280 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=12189156743110968328 req_generation=2 | L1814 |
| 20:58:36.213 | 13090 | native | 29015 | mono=408736589 tid=29015 egl_ctx=0x742352f280 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=12189156743110968328 req_generation=2 resources_ready=1 | L1815 |
| 20:58:36.213 | 13090 | native | 29015 | mono=408736589 tid=29015 egl_ctx=0x742352f280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=12189156743110968328 generation=2 rc=0 | L1817 |
| 20:58:36.213 | 13090 | java | 29015 | mono=408736589 tid=29015 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=-6257587330598583288 | L1818 |
| 20:58:36.213 | 13090 | java | 29015 | mono=408736589 tid=29015 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=2162 | L1819 |
| 20:58:36.227 | 13104 | dart | 29015 | dart authorize result epoch=2 wid=2162 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1824 |
| 20:58:36.227 | 13104 | dart | 29015 | dart property begin android-surface-size=2672x1336 | L1825 |
| 20:58:36.232 | 13109 | dart | 29015 | dart property complete android-surface-size=2672x1336 | L1831 |
| 20:58:36.232 | 13109 | dart | 29015 | dart property begin wid=2162 | L1832 |
| 20:58:36.256 | 13133 | dart | 29015 | dart property complete wid=2162 | L1836 |
| 20:58:36.257 | 13134 | dart | 29015 | dart property begin vo=gpu-next | L1837 |
| 20:58:36.276 | 13153 | mpv | 29015 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1857 |
| 20:58:36.288 | 13165 | dart | 29015 | dart property complete vo=gpu-next | L1867 |
| 20:58:36.289 | 13166 | dart | 29015 | dart property begin vid=auto | L1868 |
| 20:58:36.310 | 13187 | native | 29186 | mono=408736686 tid=29186 egl_ctx=0x7418f19d80 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=12189156743110968328 generation=2  | L1881 |
| 20:58:36.310 | 13187 | native | 29186 | mono=408736686 tid=29186 egl_ctx=0x7418f19d80 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=12189156743110968328 generation=2 ready=1 | L1882 |
| 20:58:36.310 | 13187 | native | 29186 | mono=408736686 tid=29186 egl_ctx=0x7418f19d80 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=12189156743110968328 generation=2  | L1883 |
| 20:58:36.311 | 13188 | mpv | 29015 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1885 |
| 20:58:36.311 | 13188 | native | 29186 | mono=408736687 tid=29186 egl_ctx=0x7418f19d80 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=12189156743110968328 generation=2 result=ok window=0x7411395c10 | L1886 |
| 20:58:36.318 | 13195 | codec | 29047 | ACodec  : Now uninitialized | L1889 |
| 20:58:36.335 | 13212 | codec | 29189 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1907 |
| 20:58:36.344 | 13221 | codec | 29189 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1927 |
| 20:58:36.378 | 13255 | codec | 29189 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1930 |
| 20:58:36.383 | 13260 | codec | 29189 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1931 |
| 20:58:36.383 | 13260 | codec | 29189 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1932 |
| 20:58:36.385 | 13262 | dart | 29015 | dart property complete vid=auto | L1934 |
| 20:58:36.385 | 13262 | dart | 29015 | dart apply complete wid=2162 | L1935 |
| 20:58:36.385 | 13262 | dart | 29015 | dart bind complete wid=2162 surfaceGeneration=2 | L1936 |
| 20:58:36.385 | 13262 | dart | 29015 | dart bind lock released wid=2162 surfaceGeneration=2 | L1937 |
| 20:58:36.389 | 13266 | dart-videoparams | 29015 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1942 |
| 20:58:36.422 | 13299 | codec | 29189 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1945 |
| 20:58:36.431 | 13308 | codec | 29189 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1947 |
| 20:58:36.505 | 13382 | codec | 29189 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1948 |
| 20:58:36.554 | 13431 | dart-videoparams | 29015 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1953 |
| 20:58:36.573 | 13450 | dart | 29015 | dart size property complete android-surface-size=2672x1336 | L1955 |
| 20:58:36.597 | 13474 | java-log | 29015 | PlatformVideoView: surfaceChanged: handle=498743682640, format=43, width=2672, height=1336, wid=2162 | L1956 |
| 20:58:56.449 | 33326 | host-cmd |  | pid_after pid_before=29015 pid_after=29015 |  |
| 20:58:57.111 | 33988 | host-cmd |  | full_dump lines=    2048 |  |
| 20:58:57.310 | 34187 | host-cmd |  | round_end |  |
