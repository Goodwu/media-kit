# Timeline O1

App PID filter: 4207 (ActivityManager am_pause/resume lines kept from system_server).

Source: `O1/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 22:58:21.600 | 0 | L0 |
| home_sent(host probe after cmd returned) | 22:58:22.499 | 899 | L0 |
| am_pause_lab | 22:58:22.096 | 496 | L1031 |
| java_surfaceDestroyed_enter | 22:58:21.719 | 119 | L842 |
| java_send_SurfaceDestroyed | 22:58:22.357 | 757 | L1185 |
| dart_event_SurfaceDestroyed | 22:58:22.357 | 757 | L1266 |
| dart_detach_lock_acquired | 22:58:22.358 | 758 | L1268 |
| dart_detach_vo_null_begin | 22:58:21.690 | 90 | L825 |
| native_shutdown_enter | 22:58:22.434 | 834 | L1216 |
| native_shutdown_exit | 22:58:22.434 | 834 | L1218 |
| dart_detach_vo_null_ack | 22:58:21.692 | 92 | L826 |
| dart_detach_wid0_ack | 22:58:21.695 | 95 | L830 |
| dart_detach_apply_complete | 22:58:21.697 | 97 | L835 |
| dart_detach_lock_released | 22:58:23.778 | 2178 | L1343 |
| return_sent | 22:58:33.268 | 11668 | L0 |
| am_resume_lab | 22:58:33.181 | 11581 | L1457 |
| java_factory_create_after_home | 22:58:21.762 | 162 | L852 |
| java_ensureInitialized_after_home | 22:58:21.764 | 164 | L856 |
| java_surfaceCreated_enter | 22:58:21.804 | 204 | L868 |
| java_send_SurfaceAvailable | 22:58:21.809 | 209 | L885 |
| dart_event_SurfaceAvailable | 22:58:21.809 | 209 | L886 |
| dart_bind_requested | 22:58:21.809 | 209 | L887 |
| dart_bind_lock_acquired | 22:58:21.809 | 209 | L888 |
| dart_bind_vo_gpu_next_begin | 22:58:21.871 | 271 | L913 |
| native_ensure_init_exit | 22:58:21.995 | 395 | L950 |
| native_create_exit | 22:58:21.996 | 396 | L953 |
| mpv_egl_window_surface | 22:58:21.877 | 277 | L921 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 22:58:21.903 | 303 | L1256 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | -630 |
| shutdown_exit -> dart_vo_null_ACK (ms) | -742 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | -737 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | -439 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 715 |
| dart_vo_null_begin -> shutdown_enter (ms) | 744 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 5 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | -1969 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | 1969 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 119 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -11464 |

## Counts (whole dump)

| counter | n |
|---|---|
| ensureInitialized_total_in_log | 4 |
| ensureInitialized_after_home_sent | 3 |
| factory_create_total_in_log | 2 |
| factory_create_after_home_sent | 1 |
| mkst_shutdown_exit_total | 1 |
| mkst_create_exit_total | 2 |
| surfaceCreated_enter_total | 3 |
| surfaceDestroyed_enter_total | 2 |

## Events (time-sorted; HOME window and after, plus pre-HOME bridge lifecycle)

| device time | Δhome (ms) | layer | tid | event | line |
|---|---|---|---|---|---|
| 22:58:12.283 | -9317 | host-cmd |  | round_begin mode=openhome pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key= resume_key= |  |
| 22:58:12.749 | -8851 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 22:58:14.648 | -6952 | host-cmd |  | force_stop pid_after= |  |
| 22:58:15.437 | -6163 | host-cmd |  | logcat_cleared per-buffer |  |
| 22:58:16.193 | -5407 | host-cmd |  | am_start_fresh pid=4207 |  |
| 22:58:20.760 | -840 | java | 4207 | mono=415921136 tid=4207 thr=main java factory.create enter handle=498743452752 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L449 |
| 22:58:20.761 | -839 | java | 4207 | mono=415921137 tid=4207 thr=main java factory.create view constructed handle=498743452752 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L450 |
| 22:58:20.761 | -839 | java | 4207 | mono=415921137 tid=4207 thr=main java setLgExperimentOwner enter handle=498743452752 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L451 |
| 22:58:20.761 | -839 | java | 4207 | mono=415921137 tid=4207 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=7113845237141439577 libraryLoaded=false | L452 |
| 22:58:20.762 | -838 | native | 4207 | mono=415921138 tid=4207 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=7113845237141439577 req_generation=1 | L453 |
| 22:58:20.764 | -836 | native | 4207 | mono=415921139 tid=4207 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=7113845237141439577 req_generation=1 resources_ready=1 | L455 |
| 22:58:20.764 | -836 | native | 4207 | mono=415921139 tid=4207 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=7113845237141439577 generation=1 rc=0 | L457 |
| 22:58:20.764 | -836 | java | 4207 | mono=415921140 tid=4207 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=7113845237141439577 | L458 |
| 22:58:20.764 | -836 | java | 4207 | mono=415921140 tid=4207 thr=main java setLgExperimentOwner exit handle=498743452752 viewId=0 ownerGeneration=1 ensureInitialized=ok | L459 |
| 22:58:20.764 | -836 | java | 4207 | mono=415921140 tid=4207 thr=main java factory.create setLgExperimentOwner returned handle=498743452752 viewId=0 | L460 |
| 22:58:20.765 | -835 | java | 4207 | mono=415921141 tid=4207 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743452752 viewId=0 ownerGeneration=1 creationSerial=1 | L461 |
| 22:58:20.766 | -834 | java | 4207 | mono=415921142 tid=4207 thr=main java factory.create exit handle=498743452752 viewId=0 | L463 |
| 22:58:20.782 | -818 | host-cmd |  | tap_open x=1440 y=720 |  |
| 22:58:20.811 | -789 | java-log | 4207 | PlatformVideoView: surfaceCreated: handle=498743452752, width=668, height=360, viewIdentity=235825235 | L464 |
| 22:58:20.811 | -789 | java | 4207 | mono=415921187 tid=4207 thr=main java surfaceCreated enter handle=498743452752 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L465 |
| 22:58:20.819 | -781 | java-log | 4207 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L467 |
| 22:58:20.819 | -781 | java | 4207 | mono=415921194 tid=4207 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743452752 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L468 |
| 22:58:20.819 | -781 | java | 4207 | mono=415921195 tid=4207 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743452752 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L469 |
| 22:58:20.820 | -780 | java | 4207 | mono=415921196 tid=4207 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743452752 viewId=0 surfaceGeneration=1 wid=2099350 | L474 |
| 22:58:20.821 | -779 | java | 4207 | mono=415921196 tid=4207 thr=main java surfaceCreated exit handle=498743452752 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L475 |
| 22:58:21.123 | -477 | codec | 4268 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L531 |
| 22:58:21.132 | -468 | codec | 4268 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 15 meta buffers on output port | L533 |
| 22:58:21.207 | -393 | codec | 4268 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L536 |
| 22:58:21.270 | -330 | dart-videoparams | 4207 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L584 |
| 22:58:21.292 | -308 | dart | 4207 | dart size property complete android-surface-size=3840x1920 | L661 |
| 22:58:21.330 | -270 | java-log | 4207 | PlatformVideoView: surfaceChanged: handle=498743452752, format=4, width=2672, height=1336, wid=2099350 | L754 |
| 22:58:21.367 | -233 | host-cmd |  | openhome_delay_done delay=0.5 |  |
| 22:58:21.503 | -97 | codec | 4268 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 3/4 input, 10/15 output). | L780 |
| 22:58:21.504 | -96 | codec | 4268 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L783 |
| 22:58:21.516 | -84 | codec | 4268 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L784 |
| 22:58:21.518 | -82 | host-cmd |  | pid_before pid=4207 |  |
| 22:58:21.520 | -80 | codec | 4268 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L785 |
| 22:58:21.537 | -63 | codec | 4268 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L786 |
| 22:58:21.538 | -62 | codec | 4268 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L787 |
| 22:58:21.551 | -49 | codec | 4268 | ACodec  : Now uninitialized | L792 |
| 22:58:21.566 | -34 | dart-videoparams | 4207 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L795 |
| 22:58:21.600 | 0 | host-cmd |  | home_send_begin |  |
| 22:58:21.620 | 20 | java-log | 4207 | PlatformVideoView: surfaceChanged: handle=498743452752, format=4, width=2672, height=1440, wid=2099350 | L805 |
| 22:58:21.640 | 40 | dart-videoparams | 4207 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L814 |
| 22:58:21.690 | 90 | dart | 4207 | dart apply begin wid=0 vo=null vid=no | L824 |
| 22:58:21.690 | 90 | dart | 4207 | dart property begin vo=null | L825 |
| 22:58:21.692 | 92 | dart | 4207 | dart property complete vo=null | L826 |
| 22:58:21.692 | 92 | dart | 4207 | dart property begin android-surface-size=3840x1920 | L827 |
| 22:58:21.693 | 93 | dart | 4207 | dart property complete android-surface-size=3840x1920 | L828 |
| 22:58:21.693 | 93 | dart | 4207 | dart property begin wid=0 | L829 |
| 22:58:21.695 | 95 | dart | 4207 | dart property complete wid=0 | L830 |
| 22:58:21.695 | 95 | dart | 4207 | dart property begin vo=null | L831 |
| 22:58:21.696 | 96 | dart | 4207 | dart property complete vo=null | L832 |
| 22:58:21.696 | 96 | dart | 4207 | dart property begin vid=no | L833 |
| 22:58:21.697 | 97 | dart | 4207 | dart property complete vid=no | L834 |
| 22:58:21.697 | 97 | dart | 4207 | dart apply complete wid=0 | L835 |
| 22:58:21.699 | 99 | java-log | 4207 | PlatformVideoView: releaseSurface generation=1 wid=2099350 result=released | L837 |
| 22:58:21.718 | 118 | java-log | 4207 | PlatformVideoView: surfaceDestroyed: handle=498743452752, wid=0 | L841 |
| 22:58:21.719 | 119 | java | 4207 | mono=415922094 tid=4207 thr=main java surfaceDestroyed enter handle=498743452752 viewId=0 ownerGeneration=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=0 disposed=false | L842 |
| 22:58:21.719 | 119 | java | 4207 | mono=415922094 tid=4207 thr=main java surfaceDestroyed exit handle=498743452752 viewId=0 sentEvent=false wid=0 | L843 |
| 22:58:21.721 | 121 | java-log | 4207 | PlatformVideoView: dispose: handle=498743452752 | L844 |
| 22:58:21.721 | 121 | java | 4207 | mono=415922097 tid=4207 thr=main java dispose enter handle=498743452752 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=0 alreadyDisposed=false pendingSurfaceRefs=0 | L845 |
| 22:58:21.721 | 121 | java | 4207 | mono=415922097 tid=4207 thr=main java dispose exit handle=498743452752 viewId=0 | L846 |
| 22:58:21.762 | 162 | java | 4207 | mono=415922138 tid=4207 thr=main java factory.create enter handle=498743452752 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L852 |
| 22:58:21.764 | 164 | java | 4207 | mono=415922139 tid=4207 thr=main java factory.create view constructed handle=498743452752 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L854 |
| 22:58:21.764 | 164 | java | 4207 | mono=415922140 tid=4207 thr=main java setLgExperimentOwner enter handle=498743452752 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L855 |
| 22:58:21.764 | 164 | java | 4207 | mono=415922140 tid=4207 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=7113845237141439577 libraryLoaded=true | L856 |
| 22:58:21.764 | 164 | native | 4207 | mono=415922140 tid=4207 egl_ctx=0x744b9ff480 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=7113845237141439577 generation=1 req_owner_key=7113845237141439577 req_generation=2 | L857 |
| 22:58:21.764 | 164 | native | 4207 | mono=415922140 tid=4207 egl_ctx=0x744b9ff480 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=7113845237141439577 generation=1 req_owner_key=7113845237141439577 req_generation=2 resources_ready=1 | L858 |
| 22:58:21.764 | 164 | native | 4207 | mono=415922140 tid=4207 egl_ctx=0x744b9ff480 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=7113845237141439577 generation=2 rc=0 | L860 |
| 22:58:21.764 | 164 | java | 4207 | mono=415922140 tid=4207 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=7113845237141439577 | L861 |
| 22:58:21.764 | 164 | java | 4207 | mono=415922140 tid=4207 thr=main java setLgExperimentOwner exit handle=498743452752 viewId=1 ownerGeneration=2 ensureInitialized=ok | L862 |
| 22:58:21.765 | 165 | java | 4207 | mono=415922140 tid=4207 thr=main java factory.create setLgExperimentOwner returned handle=498743452752 viewId=1 | L863 |
| 22:58:21.765 | 165 | java | 4207 | mono=415922140 tid=4207 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=498743452752 viewId=1 ownerGeneration=2 creationSerial=2 | L864 |
| 22:58:21.765 | 165 | dart | 4207 | dart event ViewCreated handle=498743452752 generation=2 viewId=1 creationSerial=2 controllerPresent=true | L865 |
| 22:58:21.765 | 165 | java | 4207 | mono=415922141 tid=4207 thr=main java factory.create exit handle=498743452752 viewId=1 | L866 |
| 22:58:21.804 | 204 | java-log | 4207 | PlatformVideoView: surfaceCreated: handle=498743452752, width=668, height=360, viewIdentity=207085198 | L867 |
| 22:58:21.804 | 204 | java | 4207 | mono=415922179 tid=4207 thr=main java surfaceCreated enter handle=498743452752 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L868 |
| 22:58:21.808 | 208 | java-log | 4207 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743452752, transfer=pq, applied=true | L881 |
| 22:58:21.809 | 209 | java-log | 4207 | PlatformVideoView: surfaceCreated: created new wid=1050746 | L883 |
| 22:58:21.809 | 209 | java | 4207 | mono=415922184 tid=4207 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743452752 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=1050746 | L884 |
| 22:58:21.809 | 209 | java | 4207 | mono=415922185 tid=4207 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743452752 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050746 | L885 |
| 22:58:21.809 | 209 | dart | 4207 | dart event SurfaceAvailable handle=498743452752 wid=1050746 generation=2 viewId=1 creationSerial=2 surfaceGeneration=1 controllerPresent=true isCurrentView=true | L886 |
| 22:58:21.809 | 209 | dart | 4207 | dart bind requested wid=1050746 surfaceGeneration=1 generation=2 viewId=1 intentSerial=1 | L887 |
| 22:58:21.809 | 209 | dart | 4207 | dart bind lock acquired wid=1050746 surfaceGeneration=1 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L888 |
| 22:58:21.809 | 209 | dart | 4207 | dart bind branch=rebind wid=1050746 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L889 |
| 22:58:21.809 | 209 | java | 4207 | mono=415922185 tid=4207 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743452752 viewId=1 surfaceGeneration=1 wid=1050746 | L890 |
| 22:58:21.810 | 210 | java | 4207 | mono=415922185 tid=4207 thr=main java surfaceCreated exit handle=498743452752 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050746 | L891 |
| 22:58:21.810 | 210 | java-log | 4207 | PlatformVideoView: surfaceChanged: handle=498743452752, format=43, width=2672, height=1440, wid=1050746 | L892 |
| 22:58:21.836 | 236 | dart | 4207 | dart apply begin wid=1050746 vo=gpu-next vid=auto | L893 |
| 22:58:21.836 | 236 | dart | 4207 | dart property begin vo=null | L894 |
| 22:58:21.845 | 245 | dart | 4207 | dart property complete vo=null | L895 |
| 22:58:21.845 | 245 | dart | 4207 | dart authorize begin wid=1050746 generation=2 viewId=1 surfaceGeneration=1 intentSerial=1 | L896 |
| 22:58:21.866 | 266 | java | 4207 | mono=415922242 tid=4207 thr=main java authorize enter handle=498743452752 generation=2 viewId=1 surfaceGeneration=1 wid=1050746 ownerTokenPresent=true | L897 |
| 22:58:21.867 | 267 | java | 4207 | mono=415922242 tid=4207 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=7113845237141439577 libraryLoaded=true | L898 |
| 22:58:21.867 | 267 | native | 4207 | mono=415922243 tid=4207 egl_ctx=0x744b9ff480 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=7113845237141439577 generation=2 req_owner_key=7113845237141439577 req_generation=2 | L899 |
| 22:58:21.867 | 267 | native | 4207 | mono=415922243 tid=4207 egl_ctx=0x744b9ff480 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=7113845237141439577 generation=2 req_owner_key=7113845237141439577 req_generation=2 resources_ready=1 | L900 |
| 22:58:21.867 | 267 | native | 4207 | mono=415922243 tid=4207 egl_ctx=0x744b9ff480 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=7113845237141439577 generation=2 rc=0 | L902 |
| 22:58:21.867 | 267 | java | 4207 | mono=415922243 tid=4207 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=7113845237141439577 | L903 |
| 22:58:21.867 | 267 | java | 4207 | mono=415922243 tid=4207 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=1 viewId=1 wid=1050746 | L904 |
| 22:58:21.868 | 268 | dart | 4207 | dart authorize result epoch=1 wid=1050746 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=1 | L908 |
| 22:58:21.868 | 268 | dart | 4207 | dart property begin android-surface-size=1x1 | L909 |
| 22:58:21.869 | 269 | dart | 4207 | dart property complete android-surface-size=1x1 | L910 |
| 22:58:21.869 | 269 | dart | 4207 | dart property begin wid=1050746 | L911 |
| 22:58:21.871 | 271 | dart | 4207 | dart property complete wid=1050746 | L912 |
| 22:58:21.871 | 271 | dart | 4207 | dart property begin vo=gpu-next | L913 |
| 22:58:21.877 | 277 | mpv | 4207 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L921 |
| 22:58:21.893 | 293 | dart | 4207 | dart property complete vo=gpu-next | L1246 |
| 22:58:21.893 | 293 | dart | 4207 | dart property begin vid=auto | L1247 |
| 22:58:21.903 | 303 | dart | 4207 | dart property complete vid=auto | L1254 |
| 22:58:21.903 | 303 | dart | 4207 | dart apply complete wid=1050746 | L1255 |
| 22:58:21.903 | 303 | dart | 4207 | dart bind complete wid=1050746 surfaceGeneration=1 | L1256 |
| 22:58:21.903 | 303 | dart | 4207 | dart bind lock released wid=1050746 surfaceGeneration=1 | L1257 |
| 22:58:21.995 | 395 | native | 4288 | mono=415922370 tid=4288 egl_ctx=0x741c30c380 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=7113845237141439577 generation=2  | L949 |
| 22:58:21.995 | 395 | native | 4288 | mono=415922371 tid=4288 egl_ctx=0x741c30c380 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=7113845237141439577 generation=2 ready=1 | L950 |
| 22:58:21.995 | 395 | native | 4288 | mono=415922371 tid=4288 egl_ctx=0x741c30c380 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=7113845237141439577 generation=2  | L951 |
| 22:58:21.996 | 396 | native | 4288 | mono=415922372 tid=4288 egl_ctx=0x741c30c380 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=7113845237141439577 generation=2 result=ok window=0x744cb55410 | L953 |
| 22:58:21.999 | 399 | codec | 4239 | ACodec  : Now uninitialized | L956 |
| 22:58:22.011 | 411 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L967 |
| 22:58:22.025 | 425 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L984 |
| 22:58:22.039 | 439 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L986 |
| 22:58:22.045 | 445 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L991 |
| 22:58:22.046 | 446 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L992 |
| 22:58:22.058 | 458 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 1/4 input, 1/13 output). | L994 |
| 22:58:22.064 | 464 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L996 |
| 22:58:22.096 | 496 | activity | 2062 | am_pause_activity: [0,138032399,com.example.media_kit_hdr_lab/.MainActivity] | L1031 |
| 22:58:22.101 | 501 | activity | 4207 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1032 |
| 22:58:22.117 | 517 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1033 |
| 22:58:22.123 | 523 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 8/13 output). | L1034 |
| 22:58:22.123 | 523 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1035 |
| 22:58:22.126 | 526 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1036 |
| 22:58:22.149 | 549 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1048 |
| 22:58:22.162 | 562 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1050 |
| 22:58:22.220 | 620 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1065 |
| 22:58:22.257 | 657 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1081 |
| 22:58:22.316 | 716 | activity | 4207 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1154 |
| 22:58:22.357 | 757 | java-log | 4207 | PlatformVideoView: surfaceDestroyed: handle=498743452752, wid=1050746 | L1182 |
| 22:58:22.357 | 757 | java | 4207 | mono=415922732 tid=4207 thr=main java surfaceDestroyed enter handle=498743452752 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050746 disposed=false | L1183 |
| 22:58:22.357 | 757 | java | 4207 | mono=415922733 tid=4207 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=498743452752 viewId=1 surfaceGeneration=1 wid=1050746 | L1184 |
| 22:58:22.357 | 757 | java | 4207 | mono=415922733 tid=4207 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=498743452752 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050746 | L1185 |
| 22:58:22.357 | 757 | dart | 4207 | dart event SurfaceDestroyed handle=498743452752 wid=1050746 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=1050746 boundSurfaceGeneration=1 | L1266 |
| 22:58:22.357 | 757 | dart | 4207 | dart detach requested wid=1050746 surfaceGeneration=1 generation=2 viewId=1 | L1267 |
| 22:58:22.358 | 758 | java | 4207 | mono=415922734 tid=4207 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=498743452752 viewId=1 surfaceGeneration=1 wid=1050746 | L1186 |
| 22:58:22.358 | 758 | java | 4207 | mono=415922734 tid=4207 thr=main java surfaceDestroyed exit handle=498743452752 viewId=1 sentEvent=true wid=0 | L1187 |
| 22:58:22.358 | 758 | dart | 4207 | dart detach lock acquired wid=1050746 surfaceGeneration=1 generation=2 viewId=1 boundWid=1050746 boundSurfaceGeneration=1 | L1268 |
| 22:58:22.358 | 758 | dart | 4207 | dart detach decision wid=1050746 isCurrentOutput=true isInFlightOutput=false | L1269 |
| 22:58:22.358 | 758 | dart | 4207 | dart apply begin wid=0 vo=null vid=no | L1270 |
| 22:58:22.358 | 758 | dart | 4207 | dart property begin vo=null | L1271 |
| 22:58:22.360 | 760 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 4/16 output). | L1188 |
| 22:58:22.360 | 760 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1189 |
| 22:58:22.382 | 782 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1196 |
| 22:58:22.384 | 784 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1197 |
| 22:58:22.397 | 797 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1205 |
| 22:58:22.397 | 797 | codec | 4294 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1206 |
| 22:58:22.413 | 813 | codec | 4294 | ACodec  : Now uninitialized | L1212 |
| 22:58:22.434 | 834 | native | 4288 | mono=415922810 tid=4288 egl_ctx=0x741c30c380 native mkst_shutdown enter initialized=1 window_active=1 owner_key=7113845237141439577 generation=2  | L1216 |
| 22:58:22.434 | 834 | native | 4288 | mono=415922810 tid=4288 egl_ctx=0x741c30c380 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=1 latched=1 | L1218 |
| 22:58:22.465 | 865 | dart | 4207 | dart property complete vo=null | L1289 |
| 22:58:22.465 | 865 | dart | 4207 | dart property begin android-surface-size=1x1 | L1290 |
| 22:58:22.499 | 899 | host-cmd |  | home_sent |  |
| 22:58:22.788 | 1188 | dart | 4207 | dart property complete android-surface-size=1x1 | L1299 |
| 22:58:22.788 | 1188 | dart | 4207 | dart property begin wid=0 | L1300 |
| 22:58:22.895 | 1295 | dart-videoparams | 4207 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1259 |
| 22:58:22.895 | 1295 | mpv | 4207 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1260 |
| 22:58:22.895 | 1295 | dart-videoparams | 4207 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1272 |
| 22:58:22.895 | 1295 | dart-videoparams | 4207 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1301 |
| 22:58:23.213 | 1613 | dart | 4207 | dart property complete wid=0 | L1315 |
| 22:58:23.213 | 1613 | dart | 4207 | dart property begin vo=null | L1316 |
| 22:58:23.214 | 1614 | dart | 4207 | dart property complete vo=null | L1317 |
| 22:58:23.214 | 1614 | dart | 4207 | dart property begin vid=no | L1318 |
| 22:58:23.774 | 2174 | dart | 4207 | dart property complete vid=no | L1335 |
| 22:58:23.774 | 2174 | dart | 4207 | dart apply complete wid=0 | L1336 |
| 22:58:23.774 | 2174 | dart | 4207 | dart detach producer stopped wid=1050746 | L1337 |
| 22:58:23.775 | 2175 | java-log | 4207 | PlatformVideoView: releaseSurface generation=1 wid=1050746 result=released | L1339 |
| 22:58:23.778 | 2178 | dart | 4207 | dart detach reference released wid=1050746 | L1341 |
| 22:58:23.778 | 2178 | dart | 4207 | dart detach lock released wid=1050746 surfaceGeneration=1 | L1343 |
| 22:58:32.610 | 11010 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity |  |
| 22:58:33.089 | 11489 | activity | 3284 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1421 |
| 22:58:33.181 | 11581 | activity | 2594 | am_resume_activity: [0,138032399,1048,com.example.media_kit_hdr_lab/.MainActivity] | L1457 |
| 22:58:33.221 | 11621 | activity | 4207 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1465 |
| 22:58:33.258 | 11658 | java-log | 4207 | PlatformVideoView: surfaceCreated: handle=498743452752, width=668, height=360, viewIdentity=207085198 | L1475 |
| 22:58:33.258 | 11658 | java | 4207 | mono=415933634 tid=4207 thr=main java surfaceCreated enter handle=498743452752 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1476 |
| 22:58:33.263 | 11663 | java-log | 4207 | PlatformVideoView: surfaceCreated initial dataspace: handle=498743452752, transfer=pq, applied=true | L1489 |
| 22:58:33.263 | 11663 | java-log | 4207 | PlatformVideoView: surfaceCreated: created new wid=2099314 | L1491 |
| 22:58:33.263 | 11663 | java | 4207 | mono=415933639 tid=4207 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=498743452752 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=2099314 | L1492 |
| 22:58:33.263 | 11663 | java | 4207 | mono=415933639 tid=4207 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=498743452752 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=2099314 | L1494 |
| 22:58:33.264 | 11664 | dart | 4207 | dart event SurfaceAvailable handle=498743452752 wid=2099314 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1495 |
| 22:58:33.264 | 11664 | dart | 4207 | dart bind requested wid=2099314 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1496 |
| 22:58:33.264 | 11664 | dart | 4207 | dart bind lock acquired wid=2099314 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1497 |
| 22:58:33.264 | 11664 | dart | 4207 | dart bind branch=rebind wid=2099314 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1498 |
| 22:58:33.264 | 11664 | java | 4207 | mono=415933640 tid=4207 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=498743452752 viewId=1 surfaceGeneration=2 wid=2099314 | L1499 |
| 22:58:33.265 | 11665 | java | 4207 | mono=415933640 tid=4207 thr=main java surfaceCreated exit handle=498743452752 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=2099314 | L1500 |
| 22:58:33.265 | 11665 | java-log | 4207 | PlatformVideoView: surfaceChanged: handle=498743452752, format=43, width=2672, height=1440, wid=2099314 | L1501 |
| 22:58:33.268 | 11668 | host-cmd |  | return_sent |  |
| 22:58:33.291 | 11691 | java-log | 4207 | PlatformVideoView: surfaceChanged: handle=498743452752, format=43, width=2672, height=1336, wid=2099314 | L1508 |
| 22:58:33.295 | 11695 | dart | 4207 | dart apply begin wid=2099314 vo=gpu-next vid=auto | L1510 |
| 22:58:33.295 | 11695 | dart | 4207 | dart property begin vo=null | L1511 |
| 22:58:33.297 | 11697 | dart | 4207 | dart property complete vo=null | L1512 |
| 22:58:33.297 | 11697 | dart | 4207 | dart authorize begin wid=2099314 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1513 |
| 22:58:33.324 | 11724 | java-log | 4207 | PlatformVideoView: surfaceChanged: handle=498743452752, format=43, width=2672, height=1440, wid=2099314 | L1518 |
| 22:58:33.360 | 11760 | java | 4207 | mono=415933736 tid=4207 thr=main java authorize enter handle=498743452752 generation=2 viewId=1 surfaceGeneration=2 wid=2099314 ownerTokenPresent=true | L1528 |
| 22:58:33.360 | 11760 | java | 4207 | mono=415933736 tid=4207 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=7113845237141439577 libraryLoaded=true | L1529 |
| 22:58:33.360 | 11760 | native | 4207 | mono=415933736 tid=4207 egl_ctx=0x744b9ff480 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=7113845237141439577 req_generation=2 | L1530 |
| 22:58:33.360 | 11760 | native | 4207 | mono=415933736 tid=4207 egl_ctx=0x744b9ff480 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=7113845237141439577 req_generation=2 resources_ready=1 | L1531 |
| 22:58:33.360 | 11760 | native | 4207 | mono=415933736 tid=4207 egl_ctx=0x744b9ff480 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=7113845237141439577 generation=2 rc=0 | L1533 |
| 22:58:33.360 | 11760 | java | 4207 | mono=415933736 tid=4207 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=7113845237141439577 | L1534 |
| 22:58:33.360 | 11760 | java | 4207 | mono=415933736 tid=4207 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=2099314 | L1535 |
| 22:58:33.370 | 11770 | dart | 4207 | dart authorize result epoch=2 wid=2099314 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1540 |
| 22:58:33.370 | 11770 | dart | 4207 | dart property begin android-surface-size=2672x1336 | L1541 |
| 22:58:33.381 | 11781 | dart | 4207 | dart property complete android-surface-size=2672x1336 | L1548 |
| 22:58:33.382 | 11782 | dart | 4207 | dart property begin wid=2099314 | L1549 |
| 22:58:33.422 | 11822 | dart | 4207 | dart property complete wid=2099314 | L1559 |
| 22:58:33.423 | 11823 | dart | 4207 | dart property begin vo=gpu-next | L1560 |
| 22:58:33.431 | 11831 | mpv | 4207 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1580 |
| 22:58:33.444 | 11844 | dart | 4207 | dart property complete vo=gpu-next | L1590 |
| 22:58:33.444 | 11844 | dart | 4207 | dart property begin vid=auto | L1591 |
| 22:58:33.463 | 11863 | native | 4355 | mono=415933838 tid=4355 egl_ctx=0x7443d4e480 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=7113845237141439577 generation=2  | L1597 |
| 22:58:33.463 | 11863 | native | 4355 | mono=415933839 tid=4355 egl_ctx=0x7443d4e480 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=7113845237141439577 generation=2 ready=1 | L1598 |
| 22:58:33.463 | 11863 | native | 4355 | mono=415933839 tid=4355 egl_ctx=0x7443d4e480 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=7113845237141439577 generation=2  | L1599 |
| 22:58:33.463 | 11863 | mpv | 4207 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1600 |
| 22:58:33.464 | 11864 | native | 4355 | mono=415933840 tid=4355 egl_ctx=0x7443d4e480 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=7113845237141439577 generation=2 result=ok window=0x741f778c10 | L1602 |
| 22:58:33.467 | 11867 | codec | 4239 | ACodec  : Now uninitialized | L1605 |
| 22:58:33.487 | 11887 | codec | 4362 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1618 |
| 22:58:33.498 | 11898 | codec | 4362 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1637 |
| 22:58:33.519 | 11919 | codec | 4362 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1649 |
| 22:58:33.528 | 11928 | codec | 4362 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1650 |
| 22:58:33.528 | 11928 | codec | 4362 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1651 |
| 22:58:33.551 | 11951 | dart | 4207 | dart property complete vid=auto | L1653 |
| 22:58:33.551 | 11951 | dart | 4207 | dart apply complete wid=2099314 | L1654 |
| 22:58:33.551 | 11951 | dart | 4207 | dart bind complete wid=2099314 surfaceGeneration=2 | L1655 |
| 22:58:33.551 | 11951 | dart | 4207 | dart bind lock released wid=2099314 surfaceGeneration=2 | L1656 |
| 22:58:33.558 | 11958 | dart-videoparams | 4207 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1657 |
| 22:58:33.568 | 11968 | codec | 4362 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1660 |
| 22:58:33.577 | 11977 | codec | 4362 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1662 |
| 22:58:33.635 | 12035 | codec | 4362 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1663 |
| 22:58:33.686 | 12086 | dart-videoparams | 4207 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1668 |
| 22:58:33.687 | 12087 | dart | 4207 | dart size property complete android-surface-size=2672x1336 | L1670 |
| 22:58:33.755 | 12155 | java-log | 4207 | PlatformVideoView: surfaceChanged: handle=498743452752, format=43, width=2672, height=1336, wid=2099314 | L1671 |
| 22:58:55.454 | 33854 | host-cmd |  | pid_after pid_before=4207 pid_after=4207 |  |
| 22:58:55.863 | 34263 | host-cmd |  | full_dump lines=    1791 |  |
| 22:58:56.011 | 34411 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 22:58:56.130 | 34530 | host-cmd |  | round_end |  |
