# Timeline T0-mediakey

App PID filter: 32101 (ActivityManager am_pause/resume lines kept from system_server).

Source: `T0-mediakey/logcat-full.txt` (+ `host-events.ndjson`). Device wall clock (Asia/Shanghai). Event time = `rt=` embedded by the emitting layer for MKS-HOME-TRACE lines; logcat stamp otherwise. Δhome is relative to the host probe taken just before `input keyevent KEYCODE_HOME` was issued (home_send_begin).

## Anchors

| anchor | device time | Δhome (ms) | line |
|---|---|---|---|
| home_send_begin(host probe) | 22:31:50.659 | 0 | L0 |
| home_sent(host probe after cmd returned) | 22:31:51.809 | 1150 | L0 |
| am_pause_lab | 22:31:51.221 | 562 | L1347 |
| java_surfaceDestroyed_enter | 22:31:51.590 | 931 | L1421 |
| java_send_SurfaceDestroyed | 22:31:51.591 | 932 | L1423 |
| dart_event_SurfaceDestroyed | 22:31:51.591 | 932 | L1424 |
| dart_detach_lock_acquired | 22:31:51.592 | 933 | L1426 |
| dart_detach_vo_null_begin | 22:31:51.592 | 933 | L1429 |
| native_shutdown_enter | 22:31:51.688 | 1029 | L1489 |
| native_shutdown_exit | 22:31:51.689 | 1030 | L1491 |
| dart_detach_vo_null_ack | 22:31:51.794 | 1135 | L1550 |
| dart_detach_wid0_ack | 22:31:52.752 | 2093 | L1626 |
| dart_detach_apply_complete | 22:31:53.580 | 2921 | L1648 |
| dart_detach_lock_released | 22:31:53.582 | 2923 | L1656 |
| return_sent | 22:32:02.704 | 12045 | L0 |
| am_resume_lab | 22:32:02.596 | 11937 | L1787 |
| java_factory_create_after_home | — | — | — |
| java_ensureInitialized_after_home | 22:32:02.782 | 12123 | L1865 |
| java_surfaceCreated_enter | 22:32:02.663 | 12004 | L1810 |
| java_send_SurfaceAvailable | 22:32:02.670 | 12011 | L1828 |
| dart_event_SurfaceAvailable | 22:32:02.670 | 12011 | L1829 |
| dart_bind_requested | 22:32:02.670 | 12011 | L1830 |
| dart_bind_lock_acquired | 22:32:02.670 | 12011 | L1831 |
| dart_bind_vo_gpu_next_begin | 22:32:02.810 | 12151 | L1883 |
| native_ensure_init_exit | 22:32:02.846 | 12187 | L1921 |
| native_create_exit | 22:32:02.847 | 12188 | L1925 |
| mpv_egl_window_surface | 22:32:02.825 | 12166 | L1902 |
| mpv_bridge_not_initialized | — | — | — |
| dart_bind_complete | 22:32:02.934 | 12275 | L1979 |
| first_videoparams_after_return | — | — | — |

## Deltas

| delta | ms |
|---|---|
| shutdown_exit -> java_surfaceCreated_enter (ms) | 10974 |
| shutdown_exit -> dart_vo_null_ACK (ms) | 105 |
| shutdown_exit -> dart_detach_apply_complete(wid=0 chain) (ms) | 1891 |
| shutdown_exit -> native_ensure_init_exit (new importer) (ms) | 11157 |
| java_surfaceDestroyed_enter -> shutdown_exit (ms) | 99 |
| dart_vo_null_begin -> shutdown_enter (ms) | 96 |
| java_surfaceCreated_enter -> dart_bind_lock_acquired (ms) | 7 |
| dart_detach_lock_released -> dart_bind_lock_acquired (ms) | 9088 |
| dart_event_SurfaceAvailable -> dart_detach_lock_released (ms; >0 means available arrived while detach held lock) | -9088 |
| native_ensure_init_exit -> mpv_bridge_not_initialized(logcat relay) (ms) | — |
| java_surfaceCreated_enter -> first_videoparams_yuv420p10 (ms) | — |
| home_send_begin(host probe) -> java_surfaceDestroyed_enter (ms) | 931 |
| return_sent(host probe) -> java_surfaceCreated_enter (ms) | -41 |

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
| 22:31:21.049 | -29610 | host-cmd |  | round_begin mode=pause pkg=com.example.media_kit_hdr_lab pre_home_wait=20 post_wait=22 sf_dump=0 open_home_delay=0.5 pre_home_key=KEYCODE_MEDIA_PAUSE resume_key=KEYCODE_MEDIA_PLAY |  |
| 22:31:21.357 | -29302 | host-cmd |  | dropbox_before crash_entries=0 |  |
| 22:31:23.048 | -27611 | host-cmd |  | force_stop pid_after= |  |
| 22:31:23.568 | -27091 | host-cmd |  | logcat_cleared per-buffer |  |
| 22:31:24.297 | -26362 | host-cmd |  | am_start_fresh pid=32101 |  |
| 22:31:28.861 | -21798 | java | 32101 | mono=414309237 tid=32101 thr=main java factory.create enter handle=499363190864 viewId=0 ownerGeneration=1 creationSerial=1 tokenPresent=true managedYuvCarrier=false | L411 |
| 22:31:28.862 | -21797 | java | 32101 | mono=414309238 tid=32101 thr=main java factory.create view constructed handle=499363190864 viewId=0 -> calling setLgExperimentOwner(ownerGeneration=1) | L412 |
| 22:31:28.862 | -21797 | java | 32101 | mono=414309238 tid=32101 thr=main java setLgExperimentOwner enter handle=499363190864 viewId=0 ownerGeneration=1 tokenPresent=true surfaceGeneration=0 wid=0 | L413 |
| 22:31:28.862 | -21797 | java | 32101 | mono=414309238 tid=32101 thr=main java bridge.ensureInitialized enter generation=1 tokenPresent=true ownerKey=2180508694999579996 libraryLoaded=false | L414 |
| 22:31:28.863 | -21796 | native | 32101 | mono=414309239 tid=32101 egl_ctx=0x0 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=2180508694999579996 req_generation=1 | L415 |
| 22:31:28.864 | -21795 | native | 32101 | mono=414309240 tid=32101 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=2180508694999579996 req_generation=1 resources_ready=1 | L417 |
| 22:31:28.864 | -21795 | native | 32101 | mono=414309240 tid=32101 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=2180508694999579996 generation=1 rc=0 | L419 |
| 22:31:28.865 | -21794 | java | 32101 | mono=414309240 tid=32101 thr=main java bridge.ensureInitialized nativeInit returned=true generation=1 ownerKey=2180508694999579996 | L420 |
| 22:31:28.865 | -21794 | java | 32101 | mono=414309240 tid=32101 thr=main java setLgExperimentOwner exit handle=499363190864 viewId=0 ownerGeneration=1 ensureInitialized=ok | L421 |
| 22:31:28.865 | -21794 | java | 32101 | mono=414309241 tid=32101 thr=main java factory.create setLgExperimentOwner returned handle=499363190864 viewId=0 | L422 |
| 22:31:28.869 | -21790 | java | 32101 | mono=414309245 tid=32101 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=499363190864 viewId=0 ownerGeneration=1 creationSerial=1 | L423 |
| 22:31:28.871 | -21788 | java | 32101 | mono=414309247 tid=32101 thr=main java factory.create exit handle=499363190864 viewId=0 | L425 |
| 22:31:28.921 | -21738 | host-cmd |  | tap_open x=1440 y=720 |  |
| 22:31:28.926 | -21733 | java-log | 32101 | PlatformVideoView: surfaceCreated: handle=499363190864, width=668, height=360, viewIdentity=235825235 | L426 |
| 22:31:28.926 | -21733 | java | 32101 | mono=414309302 tid=32101 thr=main java surfaceCreated enter handle=499363190864 viewId=0 ownerGeneration=1 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L427 |
| 22:31:28.942 | -21717 | java-log | 32101 | PlatformVideoView: surfaceCreated: created new wid=2099350 | L429 |
| 22:31:28.942 | -21717 | java | 32101 | mono=414309318 tid=32101 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499363190864 viewId=0 ownerGeneration=1 surfaceGeneration=1 wid=2099350 | L430 |
| 22:31:28.943 | -21716 | java | 32101 | mono=414309318 tid=32101 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499363190864 viewId=0 ownerGeneration=1 creationSerial=1 surfaceGeneration=1 wid=2099350 | L431 |
| 22:31:28.943 | -21716 | java | 32101 | mono=414309319 tid=32101 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499363190864 viewId=0 surfaceGeneration=1 wid=2099350 | L436 |
| 22:31:28.944 | -21715 | java | 32101 | mono=414309319 tid=32101 thr=main java surfaceCreated exit handle=499363190864 viewId=0 surfaceGeneration=1 activeSurfaceGeneration=1 wid=2099350 | L437 |
| 22:31:30.078 | -20581 | java | 32101 | mono=414310454 tid=32101 thr=main java factory.create enter handle=499363190864 viewId=1 ownerGeneration=2 creationSerial=2 tokenPresent=true managedYuvCarrier=true | L814 |
| 22:31:30.079 | -20580 | java | 32101 | mono=414310455 tid=32101 thr=main java factory.create view constructed handle=499363190864 viewId=1 -> calling setLgExperimentOwner(ownerGeneration=2) | L816 |
| 22:31:30.079 | -20580 | java | 32101 | mono=414310455 tid=32101 thr=main java setLgExperimentOwner enter handle=499363190864 viewId=1 ownerGeneration=2 tokenPresent=true surfaceGeneration=0 wid=0 | L817 |
| 22:31:30.079 | -20580 | java | 32101 | mono=414310455 tid=32101 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=2180508694999579996 libraryLoaded=true | L818 |
| 22:31:30.079 | -20580 | native | 32101 | mono=414310455 tid=32101 egl_ctx=0x0 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=2180508694999579996 generation=1 req_owner_key=2180508694999579996 req_generation=2 | L819 |
| 22:31:30.079 | -20580 | native | 32101 | mono=414310455 tid=32101 egl_ctx=0x0 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=2180508694999579996 generation=1 req_owner_key=2180508694999579996 req_generation=2 resources_ready=1 | L820 |
| 22:31:30.079 | -20580 | native | 32101 | mono=414310455 tid=32101 egl_ctx=0x0 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=2180508694999579996 generation=2 rc=0 | L822 |
| 22:31:30.079 | -20580 | java | 32101 | mono=414310455 tid=32101 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=2180508694999579996 | L823 |
| 22:31:30.079 | -20580 | java | 32101 | mono=414310455 tid=32101 thr=main java setLgExperimentOwner exit handle=499363190864 viewId=1 ownerGeneration=2 ensureInitialized=ok | L824 |
| 22:31:30.079 | -20580 | java | 32101 | mono=414310455 tid=32101 thr=main java factory.create setLgExperimentOwner returned handle=499363190864 viewId=1 | L825 |
| 22:31:30.079 | -20580 | java | 32101 | mono=414310455 tid=32101 thr=main java factory channel.invokeMethod PlatformVideoView.ViewCreated handle=499363190864 viewId=1 ownerGeneration=2 creationSerial=2 | L826 |
| 22:31:30.080 | -20579 | java | 32101 | mono=414310456 tid=32101 thr=main java factory.create exit handle=499363190864 viewId=1 | L828 |
| 22:31:30.123 | -20536 | java-log | 32101 | PlatformVideoView: surfaceCreated: handle=499363190864, width=668, height=360, viewIdentity=207085198 | L829 |
| 22:31:30.123 | -20536 | java | 32101 | mono=414310499 tid=32101 thr=main java surfaceCreated enter handle=499363190864 viewId=1 ownerGeneration=2 surfaceGenerationBefore=0 activeSurfaceGeneration=0 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L830 |
| 22:31:30.133 | -20526 | java-log | 32101 | PlatformVideoView: surfaceCreated initial dataspace: handle=499363190864, transfer=pq, applied=true | L846 |
| 22:31:30.133 | -20526 | java-log | 32101 | PlatformVideoView: surfaceCreated: created new wid=1050822 | L848 |
| 22:31:30.133 | -20526 | java | 32101 | mono=414310509 tid=32101 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499363190864 viewId=1 ownerGeneration=2 surfaceGeneration=1 wid=1050822 | L849 |
| 22:31:30.134 | -20525 | java | 32101 | mono=414310509 tid=32101 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499363190864 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050822 | L850 |
| 22:31:30.134 | -20525 | java | 32101 | mono=414310510 tid=32101 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499363190864 viewId=1 surfaceGeneration=1 wid=1050822 | L855 |
| 22:31:30.134 | -20525 | java | 32101 | mono=414310510 tid=32101 thr=main java surfaceCreated exit handle=499363190864 viewId=1 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050822 | L856 |
| 22:31:30.183 | -20476 | java | 32101 | mono=414310559 tid=32101 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=2180508694999579996 libraryLoaded=true | L863 |
| 22:31:30.183 | -20476 | native | 32101 | mono=414310559 tid=32101 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=1 window_active=0 owner_key=2180508694999579996 generation=2 req_owner_key=2180508694999579996 req_generation=2 | L864 |
| 22:31:30.183 | -20476 | native | 32101 | mono=414310559 tid=32101 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=1 window_active=0 owner_key=2180508694999579996 generation=2 req_owner_key=2180508694999579996 req_generation=2 resources_ready=1 | L865 |
| 22:31:30.183 | -20476 | native | 32101 | mono=414310559 tid=32101 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=2180508694999579996 generation=2 rc=0 | L867 |
| 22:31:30.183 | -20476 | java | 32101 | mono=414310559 tid=32101 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=2180508694999579996 | L868 |
| 22:31:30.342 | -20317 | native | 32178 | mono=414310718 tid=32178 egl_ctx=0x741dbf5880 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=2180508694999579996 generation=2  | L909 |
| 22:31:30.342 | -20317 | native | 32178 | mono=414310718 tid=32178 egl_ctx=0x741dbf5880 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=2180508694999579996 generation=2 ready=1 | L910 |
| 22:31:30.342 | -20317 | native | 32178 | mono=414310718 tid=32178 egl_ctx=0x741dbf5880 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=2180508694999579996 generation=2  | L911 |
| 22:31:30.343 | -20316 | native | 32178 | mono=414310719 tid=32178 egl_ctx=0x741dbf5880 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=2180508694999579996 generation=2 result=ok window=0x741ddc0010 | L913 |
| 22:31:46.098 | -4561 | host-cmd |  | pre_home_key_begin key=KEYCODE_MEDIA_PAUSE |  |
| 22:31:47.071 | -3588 | host-cmd |  | pre_home_key_sent key=KEYCODE_MEDIA_PAUSE |  |
| 22:31:50.315 | -344 | host-cmd |  | interim_dump lines=    1285 |  |
| 22:31:50.544 | -115 | host-cmd |  | pid_before pid=32101 |  |
| 22:31:50.659 | 0 | host-cmd |  | home_send_begin |  |
| 22:31:51.221 | 562 | activity | 2062 | am_pause_activity: [0,232988152,com.example.media_kit_hdr_lab/.MainActivity] | L1347 |
| 22:31:51.223 | 564 | activity | 32101 | am_on_paused_called: [0,com.example.media_kit_hdr_lab.MainActivity,handlePauseActivity] | L1348 |
| 22:31:51.414 | 755 | activity | 2062 | am_resume_activity: [0,58848380,744,com.lge.launcher3/.LauncherExtension] | L1372 |
| 22:31:51.554 | 895 | activity | 32101 | am_on_stop_called: [0,com.example.media_kit_hdr_lab.MainActivity,handleStopActivity] | L1408 |
| 22:31:51.590 | 931 | java-log | 32101 | PlatformVideoView: surfaceDestroyed: handle=499363190864, wid=1050822 | L1420 |
| 22:31:51.590 | 931 | java | 32101 | mono=414331966 tid=32101 thr=main java surfaceDestroyed enter handle=499363190864 viewId=1 ownerGeneration=2 surfaceGeneration=1 activeSurfaceGeneration=1 wid=1050822 disposed=false | L1421 |
| 22:31:51.591 | 932 | java | 32101 | mono=414331966 tid=32101 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed begin handle=499363190864 viewId=1 surfaceGeneration=1 wid=1050822 | L1422 |
| 22:31:51.591 | 932 | java | 32101 | mono=414331967 tid=32101 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceDestroyed handle=499363190864 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=1 wid=1050822 | L1423 |
| 22:31:51.591 | 932 | dart | 32101 | dart event SurfaceDestroyed handle=499363190864 wid=1050822 generation=2 viewId=1 surfaceGeneration=1 controllerPresent=true boundWid=1050822 boundSurfaceGeneration=1 | L1424 |
| 22:31:51.591 | 932 | dart | 32101 | dart detach requested wid=1050822 surfaceGeneration=1 generation=2 viewId=1 | L1425 |
| 22:31:51.592 | 933 | dart | 32101 | dart detach lock acquired wid=1050822 surfaceGeneration=1 generation=2 viewId=1 boundWid=1050822 boundSurfaceGeneration=1 | L1426 |
| 22:31:51.592 | 933 | dart | 32101 | dart detach decision wid=1050822 isCurrentOutput=true isInFlightOutput=false | L1427 |
| 22:31:51.592 | 933 | dart | 32101 | dart apply begin wid=0 vo=null vid=no | L1428 |
| 22:31:51.592 | 933 | dart | 32101 | dart property begin vo=null | L1429 |
| 22:31:51.592 | 933 | java | 32101 | mono=414331968 tid=32101 thr=main java surfaceDestroyed sendSurfaceEvent=SurfaceDestroyed done handle=499363190864 viewId=1 surfaceGeneration=1 wid=1050822 | L1430 |
| 22:31:51.592 | 933 | java | 32101 | mono=414331968 tid=32101 thr=main java surfaceDestroyed exit handle=499363190864 viewId=1 sentEvent=true wid=0 | L1431 |
| 22:31:51.601 | 942 | codec | 32184 | ACodec  : [OMX.qcom.video.decoder.hevc] ExecutingState flushing now (codec owns 0/4 input, 11/16 output). | L1436 |
| 22:31:51.606 | 947 | codec | 32184 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Flushing | L1437 |
| 22:31:51.610 | 951 | codec | 32184 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1438 |
| 22:31:51.612 | 953 | codec | 32184 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing->Idle | L1440 |
| 22:31:51.645 | 986 | codec | 32184 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Loaded | L1459 |
| 22:31:51.647 | 988 | codec | 32184 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1461 |
| 22:31:51.675 | 1016 | codec | 32184 | ACodec  : Now uninitialized | L1483 |
| 22:31:51.688 | 1029 | native | 32178 | mono=414332064 tid=32178 egl_ctx=0x741dbf5880 native mkst_shutdown enter initialized=1 window_active=1 owner_key=2180508694999579996 generation=2  | L1489 |
| 22:31:51.689 | 1030 | native | 32178 | mono=414332064 tid=32178 egl_ctx=0x741dbf5880 native mkst_shutdown exit initialized=0 window_active=0 owner_key=0 generation=0 result=complete frames=618 latched=618 | L1491 |
| 22:31:51.794 | 1135 | dart | 32101 | dart property complete vo=null | L1550 |
| 22:31:51.795 | 1136 | dart | 32101 | dart property begin android-surface-size=2672x1336 | L1553 |
| 22:31:51.809 | 1150 | host-cmd |  | home_sent |  |
| 22:31:52.171 | 1512 | dart | 32101 | dart property complete android-surface-size=2672x1336 | L1602 |
| 22:31:52.172 | 1513 | dart | 32101 | dart property begin wid=0 | L1603 |
| 22:31:52.173 | 1514 | dart-videoparams | 32101 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1604 |
| 22:31:52.752 | 2093 | dart | 32101 | dart property complete wid=0 | L1626 |
| 22:31:52.752 | 2093 | dart | 32101 | dart property begin vo=null | L1627 |
| 22:31:53.092 | 2433 | dart | 32101 | dart property complete vo=null | L1638 |
| 22:31:53.093 | 2434 | dart | 32101 | dart property begin vid=no | L1639 |
| 22:31:53.580 | 2921 | dart | 32101 | dart property complete vid=no | L1647 |
| 22:31:53.580 | 2921 | dart | 32101 | dart apply complete wid=0 | L1648 |
| 22:31:53.580 | 2921 | dart | 32101 | dart detach producer stopped wid=1050822 | L1649 |
| 22:31:53.580 | 2921 | java-log | 32101 | PlatformVideoView: releaseSurface generation=1 wid=1050822 result=released | L1651 |
| 22:31:53.582 | 2923 | dart | 32101 | dart detach reference released wid=1050822 | L1655 |
| 22:31:53.582 | 2923 | dart | 32101 | dart detach lock released wid=1050822 surfaceGeneration=1 | L1656 |
| 22:32:01.954 | 11295 | host-cmd |  | return_send_begin cmd=am start -n com.example.media_kit_hdr_lab/.MainActivity |  |
| 22:32:02.496 | 11837 | activity | 2595 | am_pause_activity: [0,58848380,com.lge.launcher3/.LauncherExtension] | L1751 |
| 22:32:02.596 | 11937 | activity | 19361 | am_resume_activity: [0,232988152,1038,com.example.media_kit_hdr_lab/.MainActivity] | L1787 |
| 22:32:02.616 | 11957 | activity | 32101 | am_on_resume_called: [0,com.example.media_kit_hdr_lab.MainActivity,RESUME_ACTIVITY] | L1793 |
| 22:32:02.663 | 12004 | java-log | 32101 | PlatformVideoView: surfaceCreated: handle=499363190864, width=668, height=360, viewIdentity=207085198 | L1809 |
| 22:32:02.663 | 12004 | java | 32101 | mono=414343039 tid=32101 thr=main java surfaceCreated enter handle=499363190864 viewId=1 ownerGeneration=2 surfaceGenerationBefore=1 activeSurfaceGeneration=1 widBefore=0 disposed=false tokenPresent=true ensureInitializedCalledHere=false | L1810 |
| 22:32:02.669 | 12010 | java-log | 32101 | PlatformVideoView: surfaceCreated initial dataspace: handle=499363190864, transfer=pq, applied=true | L1824 |
| 22:32:02.669 | 12010 | java-log | 32101 | PlatformVideoView: surfaceCreated: created new wid=1982 | L1826 |
| 22:32:02.669 | 12010 | java | 32101 | mono=414343045 tid=32101 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable begin handle=499363190864 viewId=1 ownerGeneration=2 surfaceGeneration=2 wid=1982 | L1827 |
| 22:32:02.670 | 12011 | java | 32101 | mono=414343045 tid=32101 thr=main java factory channel.invokeMethod PlatformVideoView.SurfaceAvailable handle=499363190864 viewId=1 ownerGeneration=2 creationSerial=2 surfaceGeneration=2 wid=1982 | L1828 |
| 22:32:02.670 | 12011 | dart | 32101 | dart event SurfaceAvailable handle=499363190864 wid=1982 generation=2 viewId=1 creationSerial=2 surfaceGeneration=2 controllerPresent=true isCurrentView=true | L1829 |
| 22:32:02.670 | 12011 | dart | 32101 | dart bind requested wid=1982 surfaceGeneration=2 generation=2 viewId=1 intentSerial=3 | L1830 |
| 22:32:02.670 | 12011 | dart | 32101 | dart bind lock acquired wid=1982 surfaceGeneration=2 generation=2 viewId=1 boundWid=null boundSurfaceGeneration=0 inFlight=null | L1831 |
| 22:32:02.670 | 12011 | dart | 32101 | dart bind branch=rebind wid=1982 boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false | L1832 |
| 22:32:02.673 | 12014 | java | 32101 | mono=414343048 tid=32101 thr=main java surfaceCreated sendSurfaceEvent=SurfaceAvailable done handle=499363190864 viewId=1 surfaceGeneration=2 wid=1982 | L1833 |
| 22:32:02.673 | 12014 | java | 32101 | mono=414343049 tid=32101 thr=main java surfaceCreated exit handle=499363190864 viewId=1 surfaceGeneration=2 activeSurfaceGeneration=2 wid=1982 | L1834 |
| 22:32:02.676 | 12017 | java-log | 32101 | PlatformVideoView: surfaceChanged: handle=499363190864, format=43, width=2672, height=1336, wid=1982 | L1835 |
| 22:32:02.697 | 12038 | dart | 32101 | dart apply begin wid=1982 vo=gpu-next vid=auto | L1843 |
| 22:32:02.697 | 12038 | dart | 32101 | dart property begin vo=null | L1844 |
| 22:32:02.704 | 12045 | host-cmd |  | return_sent |  |
| 22:32:02.735 | 12076 | dart | 32101 | dart property complete vo=null | L1849 |
| 22:32:02.735 | 12076 | dart | 32101 | dart authorize begin wid=1982 generation=2 viewId=1 surfaceGeneration=2 intentSerial=3 | L1850 |
| 22:32:02.760 | 12101 | java-log | 32101 | PlatformVideoView: surfaceChanged: handle=499363190864, format=43, width=2672, height=1440, wid=1982 | L1863 |
| 22:32:02.782 | 12123 | java | 32101 | mono=414343158 tid=32101 thr=main java authorize enter handle=499363190864 generation=2 viewId=1 surfaceGeneration=2 wid=1982 ownerTokenPresent=true | L1864 |
| 22:32:02.782 | 12123 | java | 32101 | mono=414343158 tid=32101 thr=main java bridge.ensureInitialized enter generation=2 tokenPresent=true ownerKey=2180508694999579996 libraryLoaded=true | L1865 |
| 22:32:02.782 | 12123 | native | 32101 | mono=414343158 tid=32101 egl_ctx=0x744b9fe280 native nativeInit(JNI) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=2180508694999579996 req_generation=2 | L1866 |
| 22:32:02.782 | 12123 | native | 32101 | mono=414343158 tid=32101 egl_ctx=0x744b9fe280 native mkst_init(lc_init) enter initialized=0 window_active=0 owner_key=0 generation=0 req_owner_key=2180508694999579996 req_generation=2 resources_ready=1 | L1867 |
| 22:32:02.782 | 12123 | native | 32101 | mono=414343158 tid=32101 egl_ctx=0x744b9fe280 native mkst_init(lc_init) exit initialized=1 window_active=0 owner_key=2180508694999579996 generation=2 rc=0 | L1869 |
| 22:32:02.782 | 12123 | java | 32101 | mono=414343158 tid=32101 thr=main java bridge.ensureInitialized nativeInit returned=true generation=2 ownerKey=2180508694999579996 | L1870 |
| 22:32:02.782 | 12123 | java | 32101 | mono=414343158 tid=32101 thr=main java authorize result code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 viewId=1 wid=1982 | L1871 |
| 22:32:02.783 | 12124 | dart | 32101 | dart authorize result epoch=2 wid=1982 code=ok applicable=true ok=true ownerGeneration=2 surfaceGeneration=2 | L1873 |
| 22:32:02.784 | 12125 | dart | 32101 | dart property begin android-surface-size=2672x1336 | L1874 |
| 22:32:02.788 | 12129 | dart | 32101 | dart property complete android-surface-size=2672x1336 | L1875 |
| 22:32:02.788 | 12129 | dart | 32101 | dart property begin wid=1982 | L1876 |
| 22:32:02.810 | 12151 | dart | 32101 | dart property complete wid=1982 | L1882 |
| 22:32:02.810 | 12151 | dart | 32101 | dart property begin vo=gpu-next | L1883 |
| 22:32:02.825 | 12166 | mpv | 32101 | MPVLOG [vo/gpu-next/opengl] error: YUV-DIAG: eglCreateWindowSurface ok (config49) | L1902 |
| 22:32:02.831 | 12172 | dart | 32101 | dart property complete vo=gpu-next | L1912 |
| 22:32:02.832 | 12173 | dart | 32101 | dart property begin vid=auto | L1913 |
| 22:32:02.846 | 12187 | native | 32281 | mono=414343222 tid=32281 egl_ctx=0x741dde9c80 native mkst_ensure_init(lc_verify) enter initialized=1 window_active=0 owner_key=2180508694999579996 generation=2  | L1920 |
| 22:32:02.846 | 12187 | native | 32281 | mono=414343222 tid=32281 egl_ctx=0x741dde9c80 native mkst_ensure_init(lc_verify) exit initialized=1 window_active=0 owner_key=2180508694999579996 generation=2 ready=1 | L1921 |
| 22:32:02.846 | 12187 | native | 32281 | mono=414343222 tid=32281 egl_ctx=0x741dde9c80 native mkst_create_decoder_window enter initialized=1 window_active=0 owner_key=2180508694999579996 generation=2  | L1922 |
| 22:32:02.846 | 12187 | mpv | 32101 | MPVLOG [vo/gpu-next/surfacetexture] error: MKSURF: version surfacetexture-poc-r2 | L1923 |
| 22:32:02.847 | 12188 | native | 32281 | mono=414343223 tid=32281 egl_ctx=0x741dde9c80 native mkst_create_decoder_window exit initialized=1 window_active=1 owner_key=2180508694999579996 generation=2 result=ok window=0x741ddc0e10 | L1925 |
| 22:32:02.850 | 12191 | codec | 32133 | ACodec  : Now uninitialized | L1933 |
| 22:32:02.867 | 12208 | codec | 32284 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded | L1943 |
| 22:32:02.877 | 12218 | codec | 32284 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Loaded->Idle | L1967 |
| 22:32:02.912 | 12253 | codec | 32284 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 13 meta buffers on output port | L1973 |
| 22:32:02.926 | 12267 | codec | 32284 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Idle->Executing | L1974 |
| 22:32:02.927 | 12268 | codec | 32284 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1975 |
| 22:32:02.934 | 12275 | dart | 32101 | dart property complete vid=auto | L1977 |
| 22:32:02.934 | 12275 | dart | 32101 | dart apply complete wid=1982 | L1978 |
| 22:32:02.934 | 12275 | dart | 32101 | dart bind complete wid=1982 surfaceGeneration=2 | L1979 |
| 22:32:02.934 | 12275 | dart | 32101 | dart bind lock released wid=1982 surfaceGeneration=2 | L1980 |
| 22:32:02.944 | 12285 | dart-videoparams | 32101 | VIDEOPARAMS VideoParams(pixelformat: null, ...) | L1981 |
| 22:32:02.956 | 12297 | codec | 32284 | ACodec  : [OMX.qcom.video.decoder.hevc] Now handling output port settings change | L1984 |
| 22:32:02.969 | 12310 | codec | 32284 | ACodec  : [OMX.qcom.video.decoder.hevc] Allocating 16 meta buffers on output port | L1986 |
| 22:32:03.050 | 12391 | codec | 32284 | ACodec  : [OMX.qcom.video.decoder.hevc] Now Executing | L1991 |
| 22:32:03.098 | 12439 | dart-videoparams | 32101 | VIDEOPARAMS VideoParams(pixelformat: mediacodec, ...) | L1996 |
| 22:32:03.101 | 12442 | dart | 32101 | dart size property complete android-surface-size=2672x1336 | L1998 |
| 22:32:03.140 | 12481 | java-log | 32101 | PlatformVideoView: surfaceChanged: handle=499363190864, format=43, width=2672, height=1336, wid=1982 | L1999 |
| 22:32:07.850 | 17191 | host-cmd |  | resume_key_begin key=KEYCODE_MEDIA_PLAY |  |
| 22:32:08.472 | 17813 | host-cmd |  | resume_key_sent key=KEYCODE_MEDIA_PLAY |  |
| 22:32:25.728 | 35069 | host-cmd |  | pid_after pid_before=32101 pid_after=32101 |  |
| 22:32:26.348 | 35689 | host-cmd |  | full_dump lines=    2097 |  |
| 22:32:26.569 | 35910 | host-cmd |  | dropbox_after crash_entries_before=0 after=0 |  |
| 22:32:26.728 | 36069 | host-cmd |  | round_end |  |
