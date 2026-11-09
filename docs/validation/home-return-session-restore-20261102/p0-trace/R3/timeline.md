# Timeline R3

App PID filter: 18812 (ActivityManager am_pause/resume lines kept from system_server).

Source: `R3/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 17:41:17.399 | 0 | L0 |
| home_sent(host probe after cmd returned) | 17:41:19.121 | 1722 | L0 |
| am_pause_lab | 17:41:18.813 | 1414 | L2623 |
| java_surfaceDestroyed_enter | 17:41:18.951 | 1552 | L2652 |
| java_send_SurfaceDestroyed | 17:41:18.963 | 1564 | L2654 |
| dart_event_SurfaceDestroyed | 17:41:18.965 | 1566 | L2655 |
| dart_detach_lock_acquired | 17:41:18.966 | 1567 | L2657 |
| dart_detach_vo_null_begin | 17:41:18.966 | 1567 | L2660 |
| native_shutdown_enter | 17:41:19.042 | 1643 | L2690 |
| native_shutdown_exit | 17:41:19.043 | 1644 | L2692 |
| dart_detach_vo_null_ack | 17:41:19.127 | 1728 | L2702 |
| dart_detach_wid0_ack | 17:41:20.716 | 3317 | L2826 |
| dart_detach_apply_complete | 17:41:21.759 | 4360 | L2836 |
| dart_detach_lock_released | 17:41:21.776 | 4377 | L2842 |
| return_sent | 17:41:30.106 | 12707 | L0 |
| am_resume_lab | 17:41:29.980 | 12581 | L2947 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | — | — | — |
| java_surfaceCreated_enter | 17:41:30.013 | 12614 | L3001 |
| java_send_SurfaceAvailable | 17:41:30.018 | 12619 | L3026 |
| dart_event_SurfaceAvailable | 17:41:30.018 | 12619 | L3054 |
| dart_bind_requested | 17:41:30.018 | 12619 | L3058 |
| dart_bind_lock_acquired | 17:41:30.018 | 12619 | L3059 |
| dart_bind_vo_gpu_next_begin | 17:41:30.211 | 12812 | L3177 |
| native_ensure_init_exit | 17:41:30.260 | 12861 | L3190 |
| native_create_exit | — | — | — |
| mpv_egl_window_surface | — | — | — |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 17:41:30.265 | 12866 | L3193 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 10970 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 84 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 2716 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 11217 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 92 |
| dart_vo_null_begin -> shutdown_enter (ms) | 76 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 5 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 8242 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | -8242 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 1552 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -93 |

## Counts (whole dump)

| counter | n |
|---|---|
| ensureInitialized_total_in_log | 1 |
| ensureInitialized_after_home_sent | 0 |
| factory_create_total_in_log | 1 |
| factory_create_after_home_sent | 0 |
| mkst_shutdown_exit_total | 1 |
| mkst_create_exit_total | 1 |
| surfaceCreated_enter_total | 2 |
| surfaceDestroyed_enter_total | 1 |

## Events (time-sorted; HOME window and after, plus pre-HOME bridge lifecycle)

| device time | Δhome (ms) | layer | tid | event | line |
|---|---|---|---|---|---|
| 17:40:39.851 | -37548 | host-cmd |  | round_begin launch=fresh home=normal pkg=com.example.piliplus.dev |  |
| 17:40:41.828 | -35571 | host-cmd |  | force_stop pid_after= |  |
| 17:40:41.982 | -35417 | host-cmd |  | logcat_cleared |  |
| 17:40:42.800 | -34599 | host-cmd |  | am_start_fresh pid=18812 cmd=am start -a android.intent.action.VIEW -d https://www.bilibili.com/video/BV1vY4y1N7TY -p com.example.piliplus.dev |  |
| 17:40:47.367 | -30032 | java | 18812 | mono=400896243 tid=18812 thr=main java factory.create enter handle=498686539344 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=true | L468 |
| 17:40:47.368 | -30031 | java | 18812 | mono=400896245 tid=18812 thr=main java factory.create view constructed handle=498686539344 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L470 |
| 17:40:47.369 | -30030 | java | 18812 | mono=400896245 tid=18812 thr=main java setLgExperimentOwner enter handle=498686539344 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L471 |
| 17:40:47.369 | -30030 | java | 18812 | mono=400896245 tid=18812 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=-7887552963589693771 libraryLoaded=false | L472 |
| 17:40:47.370 | -30029 | native | 18812 | mono=400896246 tid=18812 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=10559191110119857845 req_generation=1 | L473 |
| 17:40:47.377 | -30022 | native | 18812 | mono=400896253 tid=18812 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=10559191110119857845 req_generation=1 resources_ready=1 | L475 |
| 17:40:47.377 | -30022 | native | 18812 | mono=400896253 tid=18812 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=10559191110119857845 generation=1 rc=0 | L477 |
| 17:40:47.377 | -30022 | java | 18812 | mono=400896254 tid=18812 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=-7887552963589693771 | L478 |
| 17:40:47.377 | -30022 | java | 18812 | mono=400896254 tid=18812 thr=main java setLgExperimentOwner exit handle=498686539344 viewId=0 ownerGeneration=1 ensureInitialized=ok | L479 |
| 17:40:47.377 | -30022 | java | 18812 | mono=400896254 tid=18812 thr=main java factory.create setLgExperimentOwner returned handle=498686539344 viewId=0 | L480 |
| 17:40:47.378 | -30021 | java | 18812 | mono=400896254 tid=18812 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498686539344 viewId=0 ownerGeneration=1 creationSerial=1 | L481 |
| 17:40:47.379 | -30020 | java | 18812 | mono=400896255 tid=18812 thr=main java factory.create exit handle=498686539344 viewId=0 | L483 |
| 17:40:47.457 | -29942 | java-log | 18812 | PlatformVideoView: surfaceCreated: handle=498686539344, width=1, height=1, viewIdentity=226585448 | L484 |
| 17:40:47.457 | -29942 | java | 18812 | mono=400896334 tid=18812 thr=main java surfaceCreated enter handle=498686539344 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L485 |
| 17:40:47.467 | -29932 | java-log | 18812 | PlatformVideoView: surfaceCreated initial dataspace: handle=498686539344, transfer=pq, applied=true | L498 |
| 17:40:47.508 | -29891 | java-log | 18812 | PlatformVideoView: surfaceCreated: created new wid=1050978 | L500 |
| 17:40:47.508 | -29891 | java | 18812 | mono=400896385 tid=18812 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498686539344 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=1050978 | L501 |
| 17:40:47.509 | -29890 | java | 18812 | mono=400896385 tid=18812 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498686539344 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=1050978 | L502 |
| 17:40:47.510 | -29889 | java | 18812 | mono=400896386 tid=18812 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498686539344 viewId=0 surfaceGeneration=1 wid=1050978 | L507 |
| 17:40:47.510 | -29889 | java | 18812 | mono=400896386 tid=18812 thr=main java surfaceCreated exit handle=498686539344 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050978 | L508 |
| 17:40:48.498 | -28901 | native | 18946 | mono=400897374 tid=18946 egl_ctx=0x74118eb880 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=10559191110119857845 generation=1  | L568 |
| 17:40:48.498 | -28901 | native | 18946 | mono=400897375 tid=18946 egl_ctx=0x74118eb880 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=10559191110119857845 generation=1 ready=1 | L569 |
| 17:40:48.498 | -28901 | native | 18946 | mono=400897375 tid=18946 egl_ctx=0x74118eb880 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=10559191110119857845 generation=1  | L570 |
| 17:40:48.500 | -28899 | native | 18946 | mono=400897377 tid=18946 egl_ctx=0x74118eb880 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=10559191110119857845 generation=1 result=ok window=0x74119e0210 | L572 |
| 17:41:17.124 | -275 | host-cmd |  | interim_dump lines=    2328 |  |
| 17:41:17.325 | -74 | host-cmd |  | pid_before pid=18812 |  |
| 17:41:17.399 | 0 | host-cmd |  | home_send_begin |  |
| 17:41:18.813 | 1414 | activity | 2062 | am_pause_activity: [0,222140912,com.example.piliplus.dev/com.example.piliplus.MainActivity] | L2623 |
| 17:41:18.820 | 1421 | activity | 18812 | am_on_paused_called: [0,com.example.piliplus.MainActivity,handlePauseActivity] | L2624 |
| 17:41:18.898 | 1499 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L2632 |
| 17:41:18.929 | 1530 | activity | 18812 | am_on_stop_called: [0,com.example.piliplus.MainActivity,handleStopActivity] | L2642 |
| 17:41:18.951 | 1552 | java-log | 18812 | PlatformVideoView: surfaceDestroyed: handle=498686539344, wid=1050978 | L2651 |
| 17:41:18.951 | 1552 | java | 18812 | mono=400927827 tid=18812 thr=main java surfaceDestroyed enter handle=498686539344 viewId=0 ownerGeneration=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050978 disposed=false | L2652 |
| 17:41:18.953 | 1554 | java | 18812 | mono=400927829 tid=18812 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498686539344 viewId=0 surfaceGeneration=1 wid=1050978 | L2653 |
| 17:41:18.963 | 1564 | java | 18812 | mono=400927839 tid=18812 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498686539344 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=1050978 | L2654 |
| 17:41:18.965 | 1566 | dart | 18812 | dart event SurfaceDestroyed handle=498686539344 wid=1050978 generation=1 viewId=0 surfaceGeneration=1 controllerPresent=true boundWid=1050978 boundSurfaceGeneration=1 | L2655 |
| 17:41:18.966 | 1567 | dart | 18812 | dart detach requested wid=1050978 surfaceGeneration=1 generation=1 viewId=0 | L2656 |
| 17:41:18.966 | 1567 | dart | 18812 | dart detach lock acquired wid=1050978 surfaceGeneration=1 generation=1 viewId=0 boundWid=1050978 boundSurfaceGeneration=1 | L2657 |
| 17:41:18.966 | 1567 | dart | 18812 | dart detach decision wid=1050978 isCurrentOutput=true isInFlightOutput=false | L2658 |
| 17:41:18.966 | 1567 | dart | 18812 | dart apply begin wid=0 vo=null vid=no | L2659 |
| 17:41:18.966 | 1567 | dart | 18812 | dart property begin vo=null | L2660 |
| 17:41:18.969 | 1570 | codec | 18954 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 9/16 output). | L2661 |
| 17:41:18.970 | 1571 | codec | 18954 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L2662 |
| 17:41:18.970 | 1571 | java | 18812 | mono=400927847 tid=18812 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498686539344 viewId=0 surfaceGeneration=1 wid=1050978 | L2663 |
| 17:41:18.970 | 1571 | java | 18812 | mono=400927847 tid=18812 thr=main java surfaceDestroyed exit handle=498686539344 viewId=0 sentEvent=true wid=0 | L2664 |
| 17:41:18.978 | 1579 | codec | 18954 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L2666 |
| 17:41:18.984 | 1585 | codec | 18954 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L2669 |
| 17:41:19.010 | 1611 | codec | 18954 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L2674 |
| 17:41:19.010 | 1611 | codec | 18954 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L2675 |
| 17:41:19.031 | 1632 | codec | 18954 | ACodec  : Now uninitialized | L2683 |
| 17:41:19.042 | 1643 | native | 18946 | mono=400927919 tid=18946 egl_ctx=0x74118eb880 native mkst_shutdown enter initialized=1 window_active=1 owner_key=10559191110119857845 generation=1  | L2690 |
| 17:41:19.043 | 1644 | native | 18946 | mono=400927919 tid=18946 egl_ctx=0x74118eb880 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=737 latched=737 | L2692 |
| 17:41:19.121 | 1722 | host-cmd |  | home_sent |  |
| 17:41:19.127 | 1728 | dart | 18812 | dart property complete vo=null | L2702 |
| 17:41:19.127 | 1728 | dart | 18812 | dart property begin android-surface-size=1440x720 | L2703 |
| 17:41:20.073 | 2674 | dart | 18812 | dart property complete android-surface-size=1440x720 | L2812 |
| 17:41:20.073 | 2674 | dart | 18812 | dart property begin wid=0 | L2813 |
| 17:41:20.716 | 3317 | dart | 18812 | dart property complete wid=0 | L2826 |
| 17:41:20.716 | 3317 | dart | 18812 | dart property begin vo=null | L2827 |
| 17:41:21.131 | 3732 | dart | 18812 | dart property complete vo=null | L2832 |
| 17:41:21.132 | 3733 | dart | 18812 | dart property begin vid=no | L2833 |
| 17:41:21.759 | 4360 | dart | 18812 | dart property complete vid=no | L2835 |
| 17:41:21.759 | 4360 | dart | 18812 | dart apply complete wid=0 | L2836 |
| 17:41:21.760 | 4361 | dart | 18812 | dart detach producer stopped wid=1050978 | L2837 |
| 17:41:21.773 | 4374 | java-log | 18812 | PlatformVideoView: releaseSurface generation=1 wid=1050978 result=released | L2839 |
| 17:41:21.776 | 4377 | dart | 18812 | dart detach reference released wid=1050978 | L2841 |
| 17:41:21.776 | 4377 | dart | 18812 | dart detach lock released wid=1050978 surfaceGeneration=1 | L2842 |
| 17:41:29.232 | 11833 | host-cmd |  | return_send_begin cmd=am start -n com.example.piliplus.dev/com.example.piliplus.MainActivity |  |
| 17:41:29.961 | 12562 | activity | 3298 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L2930 |
| 17:41:29.980 | 12581 | activity | 2615 | am_resume_activity: [0,222140912,1022,com.example.piliplus.dev/com.example.piliplus.MainActivity] | L2947 |
| 17:41:29.993 | 12594 | activity | 18812 | am_on_resume_called: [0,com.example.piliplus.MainActivity,RESUME_ACTIVITY] | L2949 |
| 17:41:30.013 | 12614 | java-log | 18812 | PlatformVideoView: surfaceCreated: handle=498686539344, width=1, height=1, viewIdentity=226585448 | L3000 |
| 17:41:30.013 | 12614 | java | 18812 | mono=400938890 tid=18812 thr=main java surfaceCreated enter handle=498686539344 viewId=0 ownerGeneration=1 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L3001 |
| 17:41:30.017 | 12618 | java-log | 18812 | PlatformVideoView: surfaceCreated initial dataspace: handle=498686539344, transfer=pq, applied=true | L3014 |
| 17:41:30.017 | 12618 | java-log | 18812 | PlatformVideoView: surfaceCreated: created new wid=1051082 | L3022 |
| 17:41:30.017 | 12618 | java | 18812 | mono=400938894 tid=18812 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498686539344 viewId=0 ownerGeneration=1 surfaceGeneration=2 wid=1051082 | L3023 |
| 17:41:30.018 | 12619 | java | 18812 | mono=400938894 tid=18812 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498686539344 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=2 wid=1051082 | L3026 |
| 17:41:30.018 | 12619 | dart | 18812 | dart event SurfaceAvailable handle=498686539344 wid=1051082 generation=1 viewId=0 creationSerial=1 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L3054 |
| 17:41:30.018 | 12619 | dart | 18812 | dart bind requested wid=1051082 surfaceGeneration=2 generation=1 viewId=0 intentSerial=3 | L3058 |
| 17:41:30.018 | 12619 | dart | 18812 | dart bind lock acquired wid=1051082 surfaceGeneration=2 generation=1 viewId=0 boundWid=null boundSurfaceGeneration=0 inFlight=null | L3059 |
| 17:41:30.019 | 12620 | dart | 18812 | dart bind branch=rebind wid=1051082 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L3060 |
| 17:41:30.019 | 12620 | java | 18812 | mono=400938895 tid=18812 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498686539344 viewId=0 surfaceGeneration=2 wid=1051082 | L3061 |
| 17:41:30.019 | 12620 | java | 18812 | mono=400938896 tid=18812 thr=main java surfaceCreated exit handle=498686539344 viewId=0 surfaceGeneration=2 activeSurfaceGeneration=2 wid=1051082 | L3062 |
| 17:41:30.020 | 12621 | java-log | 18812 | PlatformVideoView: surfaceChanged: handle=498686539344, format=43, width=1440, height=720, wid=1051082 | L3063 |
| 17:41:30.031 | 12632 | dart | 18812 | dart apply begin wid=1051082 vo=gpu-next vid=auto | L3071 |
| 17:41:30.031 | 12632 | dart | 18812 | dart property begin vo=null | L3072 |
| 17:41:30.083 | 12684 | dart | 18812 | dart property complete vo=null | L3161 |
| 17:41:30.084 | 12685 | dart | 18812 | dart property begin android-surface-size=1440x720 | L3162 |
| 17:41:30.106 | 12707 | host-cmd |  | return_sent |  |
| 17:41:30.123 | 12724 | dart | 18812 | dart property complete android-surface-size=1440x720 | L3166 |
| 17:41:30.123 | 12724 | dart | 18812 | dart property begin wid=1051082 | L3167 |
| 17:41:30.158 | 12759 | java-log | 18812 | PlatformVideoView: surfaceChanged: handle=498686539344, format=43, width=1440, height=810, wid=1051082 | L3170 |
| 17:41:30.211 | 12812 | dart | 18812 | dart property complete wid=1051082 | L3176 |
| 17:41:30.211 | 12812 | dart | 18812 | dart property begin vo=gpu-next | L3177 |
| 17:41:30.249 | 12850 | dart | 18812 | dart property complete vo=gpu-next | L3187 |
| 17:41:30.249 | 12850 | dart | 18812 | dart property begin vid=auto | L3188 |
| 17:41:30.260 | 12861 | native | 19187 | mono=400939137 tid=19187 egl_ctx=0x74116d6e80 native mkst_ensure_init(lc_verify) enter initialized=0 window_active=0 owner_key=0 generation=0  | L3189 |
| 17:41:30.260 | 12861 | native | 19187 | mono=400939137 tid=19187 egl_ctx=0x74116d6e80 native mkst_ensure_init(lc_verify) exit initialized=0 window_active=0 owner_key=0 generation=0 ready=0 | L3190 |
| 17:41:30.265 | 12866 | dart | 18812 | dart property complete vid=auto | L3191 |
| 17:41:30.265 | 12866 | dart | 18812 | dart apply complete wid=1051082 | L3192 |
| 17:41:30.265 | 12866 | dart | 18812 | dart bind complete wid=1051082 surfaceGeneration=2 | L3193 |
| 17:41:30.265 | 12866 | dart | 18812 | dart bind lock released wid=1051082 surfaceGeneration=2 | L3194 |
| 17:41:32.101 | 14702 | java-log | 18812 | PlatformVideoView: surfaceChanged: handle=498686539344, format=43, width=1440, height=720, wid=1051082 | L3282 |
| 17:41:32.219 | 14820 | dart | 18812 | dart size property complete android-surface-size=1440x720 | L3284 |
| 17:41:50.381 | 32982 | host-cmd |  | pid_after pid_before=18812 pid_after=18812 |  |
| 17:41:51.654 | 34255 | host-cmd |  | full_dump lines=    4027 |  |
| 17:41:51.766 | 34367 | host-cmd |  | round_end |  |
