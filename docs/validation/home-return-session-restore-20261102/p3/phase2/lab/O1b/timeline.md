# Timeline O1b

App PID filter: 4521 (ActivityManager am_pause/resume lines kept from system_server).

Source: `O1b/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 23:02:23.763 | 0 | L0 |
| home_sent(host probe after cmd returned) | 23:02:24.728 | 965 | L0 |
| am_pause_lab | 23:02:24.241 | 478 | L825 |
| java_surfaceDestroyed_enter | 23:02:24.443 | 680 | L927 |
| java_send_SurfaceDestroyed | — | — | — |
| dart_event_SurfaceDestroyed | — | — | — |
| dart_detach_lock_acquired | — | — | — |
| dart_detach_vo_null_begin | 23:02:24.311 | 548 | L853 |
| native_shutdown_enter | — | — | — |
| native_shutdown_exit | — | — | — |
| dart_detach_vo_null_ack | 23:02:24.329 | 566 | L863 |
| dart_detach_wid0_ack | 23:02:24.390 | 627 | L892 |
| dart_detach_apply_complete | 23:02:24.395 | 632 | L898 |
| dart_detach_lock_released | — | — | — |
| return_sent | 23:02:35.465 | 11702 | L0 |
| am_resume_lab | 23:02:35.394 | 11631 | L1169 |
| java_factory_create_after_home | 23:02:24.620 | 857 | L988 |
| java_ensureInitialized_after_home | 23:02:24.621 | 858 | L992 |
| java_surfaceCreated_enter | — | — | — |
| java_send_SurfaceAvailable | — | — | — |
| dart_event_SurfaceAvailable | — | — | — |
| dart_bind_requested | — | — | — |
| dart_bind_lock_acquired | — | — | — |
| dart_bind_vo_gpu_next_begin | — | — | — |
| native_ensure_init_exit | — | — | — |
| native_create_exit | — | — | — |
| mpv_egl_window_surface | — | — | — |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | — | — | — |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | — |
| shutdown_exit -> dart_vo_null_ACK (ms) | — |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | — |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | — |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | — |
| dart_vo_null_begin -> shutdown_enter (ms) | — |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | — |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | — |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | — |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 680 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | — |

## Counts (whole dump)

| counter | n |
|---|---|
| ensureInitialized_total_in_log | 2 |
| ensureInitialized_after_home_sent | 1 |
| factory_create_total_in_log | 2 |
| factory_create_after_home_sent | 1 |
| mkst_shutdown_exit_total | 0 |
| mkst_create_exit_total | 0 |
| surfaceCreated_enter_total | 1 |
| surfaceDestroyed_enter_total | 1 |

## Events (time-sorted; HOME window and after, plus pre-HOME bridge lifecycle)

| device time | Δhome (ms) | layer | tid | event | line |
|---|---|---|---|---|---|
| 23:02:15.608 | -8155 | host-cmd |  | round_begin mode=openhome pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0 pre_home_key= resume_key= |  |
| 23:02:15.892 | -7871 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 23:02:17.635 | -6128 | host-cmd |  | force_stop pid_after= |  |
| 23:02:18.142 | -5621 | host-cmd |  | logcat_cleared per-buffer |  |
| 23:02:18.862 | -4901 | host-cmd |  | am_start_fresh pid=4521 |  |
| 23:02:23.365 | -398 | dart-videoparams | 4521 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L416 |
| 23:02:23.420 | -343 | java | 4521 | mono=416163796 tid=4521 thr=main java factory.create enter handle=499362809936 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L421 |
| 23:02:23.422 | -341 | java | 4521 | mono=416163798 tid=4521 thr=main java factory.create view constructed handle=499362809936 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L422 |
| 23:02:23.422 | -341 | java | 4521 | mono=416163798 tid=4521 thr=main java setLgExperimentOwner enter handle=499362809936 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L423 |
| 23:02:23.423 | -340 | java | 4521 | mono=416163798 tid=4521 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=2345734981501617636 libraryLoaded=false | L424 |
| 23:02:23.425 | -338 | native | 4521 | mono=416163800 tid=4521 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=2345734981501617636 req_generation=1 | L425 |
| 23:02:23.428 | -335 | native | 4521 | mono=416163804 tid=4521 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=2345734981501617636 req_generation=1 resources_ready=1 | L427 |
| 23:02:23.429 | -334 | native | 4521 | mono=416163804 tid=4521 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=2345734981501617636 generation=1 rc=0 | L429 |
| 23:02:23.429 | -334 | java | 4521 | mono=416163805 tid=4521 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=2345734981501617636 | L430 |
| 23:02:23.429 | -334 | java | 4521 | mono=416163805 tid=4521 thr=main java setLgExperimentOwner exit handle=499362809936 viewId=0 ownerGeneration=1 ensureInitialized=ok | L431 |
| 23:02:23.429 | -334 | java | 4521 | mono=416163805 tid=4521 thr=main java factory.create setLgExperimentOwner returned handle=499362809936 viewId=0 | L432 |
| 23:02:23.430 | -333 | java | 4521 | mono=416163806 tid=4521 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=499362809936 viewId=0 ownerGeneration=1 creationSerial=1 | L433 |
| 23:02:23.432 | -331 | dart | 4521 | dart event ViewCreated handle=499362809936 generation=1 viewId=0 creationSerial=1 controllerPresent=true | L434 |
| 23:02:23.433 | -330 | java | 4521 | mono=416163809 tid=4521 thr=main java factory.create exit handle=499362809936 viewId=0 | L435 |
| 23:02:23.462 | -301 | host-cmd |  | tap_open x=1440 y=720 |  |
| 23:02:23.492 | -271 | java-log | 4521 | PlatformVideoView: surfaceCreated: handle=499362809936, width=668, height=360, viewIdentity=235825235 | L437 |
| 23:02:23.492 | -271 | java | 4521 | mono=416163868 tid=4521 thr=main java surfaceCreated enter handle=499362809936 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L438 |
| 23:02:23.500 | -263 | java-log | 4521 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L440 |
| 23:02:23.500 | -263 | java | 4521 | mono=416163876 tid=4521 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499362809936 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L441 |
| 23:02:23.501 | -262 | java | 4521 | mono=416163876 tid=4521 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499362809936 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L442 |
| 23:02:23.501 | -262 | dart | 4521 | dart event SurfaceAvailable handle=499362809936 wid=2099350 generation=1 viewId=0 creationSerial=1 surfaceGeneration=1 controllerPresent=true isCurrentView=true | L443 |
| 23:02:23.501 | -262 | dart | 4521 | dart bind requested wid=2099350 surfaceGeneration=1 generation=1 viewId=0 intentSerial=1 | L444 |
| 23:02:23.501 | -262 | dart | 4521 | dart bind lock acquired wid=2099350 surfaceGeneration=1 generation=1 viewId=0 boundWid=null boundSurfaceGeneration=0 inFlight=null | L445 |
| 23:02:23.501 | -262 | dart | 4521 | dart bind branch=rebind wid=2099350 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L446 |
| 23:02:23.502 | -261 | java | 4521 | mono=416163877 tid=4521 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499362809936 viewId=0 surfaceGeneration=1 wid=2099350 | L447 |
| 23:02:23.502 | -261 | java | 4521 | mono=416163878 tid=4521 thr=main java surfaceCreated exit handle=499362809936 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L448 |
| 23:02:23.503 | -260 | java-log | 4521 | PlatformVideoView: surfaceChanged: handle=499362809936, format=4, width=2672, height=1440, wid=2099350 | L449 |
| 23:02:23.524 | -239 | dart | 4521 | dart apply begin wid=2099350 vo=mediacodec_embed vid=auto | L450 |
| 23:02:23.525 | -238 | dart | 4521 | dart property begin vo=null | L451 |
| 23:02:23.529 | -234 | dart | 4521 | dart property complete vo=null | L452 |
| 23:02:23.529 | -234 | dart | 4521 | dart property begin android-surface-size=1x1 | L453 |
| 23:02:23.535 | -228 | dart | 4521 | dart property complete android-surface-size=1x1 | L454 |
| 23:02:23.535 | -228 | dart | 4521 | dart property begin wid=2099350 | L455 |
| 23:02:23.538 | -225 | dart | 4521 | dart property complete wid=2099350 | L456 |
| 23:02:23.538 | -225 | dart | 4521 | dart property begin vo=mediacodec_embed | L457 |
| 23:02:23.539 | -224 | dart | 4521 | dart property complete vo=mediacodec_embed | L458 |
| 23:02:23.540 | -223 | dart | 4521 | dart property begin vid=auto | L459 |
| 23:02:23.540 | -223 | dart | 4521 | dart property complete vid=auto | L460 |
| 23:02:23.540 | -223 | dart | 4521 | dart apply complete wid=2099350 | L461 |
| 23:02:23.540 | -223 | dart | 4521 | dart bind complete wid=2099350 surfaceGeneration=1 | L462 |
| 23:02:23.540 | -223 | dart | 4521 | dart bind lock released wid=2099350 surfaceGeneration=1 | L463 |
| 23:02:23.542 | -221 | host-cmd |  | openhome_delay_done delay=0 |  |
| 23:02:23.563 | -200 | dart-videoparams | 4521 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L464 |
| 23:02:23.667 | -96 | codec | 4552 | ACodec  : Now uninitialized | L470 |
| 23:02:23.683 | -80 | host-cmd |  | pid_before pid=4521 |  |
| 23:02:23.685 | -78 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L480 |
| 23:02:23.698 | -65 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L497 |
| 23:02:23.716 | -47 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 12 meta buffers on output port | L499 |
| 23:02:23.724 | -39 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L500 |
| 23:02:23.725 | -38 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L501 |
| 23:02:23.763 | 0 | host-cmd |  | home_send_begin |  |
| 23:02:23.766 | 3 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L506 |
| 23:02:23.774 | 11 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 15 meta buffers on output port | L508 |
| 23:02:23.838 | 75 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L511 |
| 23:02:23.898 | 135 | dart-videoparams | 4521 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L594 |
| 23:02:23.904 | 141 | dart | 4521 | dart size property complete android-surface-size=3840x1920 | L633 |
| 23:02:23.965 | 202 | java-log | 4521 | PlatformVideoView: surfaceChanged: handle=499362809936, format=4, width=2672, height=1336, wid=2099350 | L728 |
| 23:02:24.147 | 384 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 3/4 input, 10/15 output). | L755 |
| 23:02:24.148 | 385 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L756 |
| 23:02:24.172 | 409 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L762 |
| 23:02:24.175 | 412 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L763 |
| 23:02:24.195 | 432 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L771 |
| 23:02:24.195 | 432 | codec | 4588 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L772 |
| 23:02:24.207 | 444 | codec | 4588 | ACodec  : Now uninitialized | L795 |
| 23:02:24.223 | 460 | dart-videoparams | 4521 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L813 |
| 23:02:24.232 | 469 | dart-videoparams | 4521 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L816 |
| 23:02:24.241 | 478 | activity | 2062 | am_pause_activity: [0,245982513,com.example.media_kit_hdr_lab/.MainActivity] | L825 |
| 23:02:24.251 | 488 | activity | 4521 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L832 |
| 23:02:24.277 | 514 | java-log | 4521 | PlatformVideoView: surfaceChanged: handle=499362809936, format=4, width=2672, height=1440, wid=2099350 | L842 |
| 23:02:24.310 | 547 | dart | 4521 | dart apply begin wid=0 vo=null vid=no | L852 |
| 23:02:24.311 | 548 | dart | 4521 | dart property begin vo=null | L853 |
| 23:02:24.329 | 566 | dart | 4521 | dart property complete vo=null | L863 |
| 23:02:24.329 | 566 | dart | 4521 | dart property begin android-surface-size=3840x1920 | L864 |
| 23:02:24.330 | 567 | dart | 4521 | dart property complete android-surface-size=3840x1920 | L865 |
| 23:02:24.330 | 567 | dart | 4521 | dart property begin wid=0 | L866 |
| 23:02:24.377 | 614 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L885 |
| 23:02:24.390 | 627 | dart | 4521 | dart property complete wid=0 | L892 |
| 23:02:24.390 | 627 | dart | 4521 | dart property begin vo=null | L893 |
| 23:02:24.394 | 631 | dart | 4521 | dart property complete vo=null | L895 |
| 23:02:24.394 | 631 | dart | 4521 | dart property begin vid=no | L896 |
| 23:02:24.395 | 632 | dart | 4521 | dart property complete vid=no | L897 |
| 23:02:24.395 | 632 | dart | 4521 | dart apply complete wid=0 | L898 |
| 23:02:24.397 | 634 | java-log | 4521 | PlatformVideoView: releaseSurface generation=1 wid=2099350 result=released | L900 |
| 23:02:24.443 | 680 | java-log | 4521 | PlatformVideoView: surfaceDestroyed: handle=499362809936, wid=0 | L926 |
| 23:02:24.443 | 680 | java | 4521 | mono=416164819 tid=4521 thr=main java surfaceDestroyed enter handle=499362809936 viewId=0 ownerGeneration=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=0 disposed=false | L927 |
| 23:02:24.443 | 680 | java | 4521 | mono=416164819 tid=4521 thr=main java surfaceDestroyed exit handle=499362809936 viewId=0 sentEvent=false wid=0 | L928 |
| 23:02:24.483 | 720 | activity | 4521 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L937 |
| 23:02:24.514 | 751 | java-log | 4521 | PlatformVideoView: dispose: handle=499362809936 | L953 |
| 23:02:24.514 | 751 | java | 4521 | mono=416164889 tid=4521 thr=main java dispose enter handle=499362809936 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=0 alreadyDisposed=false pendingSurfaceRefs=0 | L954 |
| 23:02:24.514 | 751 | java | 4521 | mono=416164889 tid=4521 thr=main java dispose exit handle=499362809936 viewId=0 | L955 |
| 23:02:24.620 | 857 | java | 4521 | mono=416164996 tid=4521 thr=main java factory.create enter handle=499362809936 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L988 |
| 23:02:24.621 | 858 | java | 4521 | mono=416164996 tid=4521 thr=main java factory.create view constructed handle=499362809936 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L990 |
| 23:02:24.621 | 858 | java | 4521 | mono=416164996 tid=4521 thr=main java setLgExperimentOwner enter handle=499362809936 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L991 |
| 23:02:24.621 | 858 | java | 4521 | mono=416164996 tid=4521 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=2345734981501617636 libraryLoaded=true | L992 |
| 23:02:24.621 | 858 | native | 4521 | mono=416164996 tid=4521 egl_ctx=0x744b9ff280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=2345734981501617636 generation=1 req_owner_key=2345734981501617636 req_generation=2 | L993 |
| 23:02:24.621 | 858 | native | 4521 | mono=416164996 tid=4521 egl_ctx=0x744b9ff280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=2345734981501617636 generation=1 req_owner_key=2345734981501617636 req_generation=2 resources_ready=1 | L994 |
| 23:02:24.621 | 858 | native | 4521 | mono=416164997 tid=4521 egl_ctx=0x744b9ff280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=2345734981501617636 generation=2 rc=0 | L996 |
| 23:02:24.621 | 858 | java | 4521 | mono=416164997 tid=4521 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=2345734981501617636 | L997 |
| 23:02:24.621 | 858 | java | 4521 | mono=416164997 tid=4521 thr=main java setLgExperimentOwner exit handle=499362809936 viewId=1 ownerGeneration=2 ensureInitialized=ok | L998 |
| 23:02:24.621 | 858 | java | 4521 | mono=416164997 tid=4521 thr=main java factory.create setLgExperimentOwner returned handle=499362809936 viewId=1 | L999 |
| 23:02:24.621 | 858 | java | 4521 | mono=416164997 tid=4521 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=499362809936 viewId=1 ownerGeneration=2 creationSerial=2 | L1000 |
| 23:02:24.621 | 858 | dart | 4521 | dart event ViewCreated handle=499362809936 generation=2 viewId=1 creationSerial=2 controllerPresent=true | L1001 |
| 23:02:24.622 | 859 | java | 4521 | mono=416164997 tid=4521 thr=main java factory.create exit handle=499362809936 viewId=1 | L1002 |
| 23:02:24.728 | 965 | host-cmd |  | home_sent |  |
| 23:02:34.530 | 10767 | dart | 4521 | dart apply begin wid=0 vo=null vid=no | L1079 |
| 23:02:34.531 | 10768 | dart | 4521 | dart property begin vo=null | L1080 |
| 23:02:34.534 | 10771 | dart | 4521 | dart property complete vo=null | L1081 |
| 23:02:34.535 | 10772 | dart | 4521 | dart property begin android-surface-size=1x1 | L1082 |
| 23:02:34.538 | 10775 | dart | 4521 | dart property complete android-surface-size=1x1 | L1083 |
| 23:02:34.539 | 10776 | dart | 4521 | dart property begin wid=0 | L1084 |
| 23:02:34.541 | 10778 | dart | 4521 | dart property complete wid=0 | L1085 |
| 23:02:34.541 | 10778 | dart | 4521 | dart property begin vo=null | L1086 |
| 23:02:34.543 | 10780 | dart | 4521 | dart property complete vo=null | L1087 |
| 23:02:34.543 | 10780 | dart | 4521 | dart property begin vid=no | L1088 |
| 23:02:34.545 | 10782 | dart | 4521 | dart property complete vid=no | L1089 |
| 23:02:34.546 | 10783 | dart | 4521 | dart apply complete wid=0 | L1090 |
| 23:02:34.553 | 10790 | dart-videoparams | 4521 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1092 |
| 23:02:34.849 | 11086 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity |  |
| 23:02:35.321 | 11558 | activity | 2611 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1134 |
| 23:02:35.394 | 11631 | activity | 2615 | am_resume_activity: [0,245982513,1049,com.example.media_kit_hdr_lab/.MainActivity] | L1169 |
| 23:02:35.416 | 11653 | activity | 4521 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1177 |
| 23:02:35.465 | 11702 | host-cmd |  | return_sent |  |
| 23:02:35.507 | 11744 | java-log | 4521 | PlatformVideoView: dispose: handle=499362809936 | L1215 |
| 23:02:35.507 | 11744 | java | 4521 | mono=416175882 tid=4521 thr=main java dispose enter handle=499362809936 viewId=1 ownerGeneration=2 surfaceGeneration=0 wid=0 alreadyDisposed=false pendingSurfaceRefs=0 | L1216 |
| 23:02:35.507 | 11744 | java | 4521 | mono=416175883 tid=4521 thr=main java dispose exit handle=499362809936 viewId=1 | L1217 |
| 23:02:57.728 | 33965 | host-cmd |  | pid_after pid_before=4521 pid_after=4521 |  |
| 23:02:58.288 | 34525 | host-cmd |  | full_dump lines=    1295 |  |
| 23:02:58.549 | 34786 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 23:02:58.749 | 34986 | host-cmd |  | round_end |  |
