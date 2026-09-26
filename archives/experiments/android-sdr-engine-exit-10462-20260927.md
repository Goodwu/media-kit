# SDR 双视图根页面正常退出屏障：10462

- 10461 正常 Android Back 导致 engine detach 先于播放器终止，Factory 保留 3 个 owner。10462 在显式双视图诊断页的根 Back 上等待 `_disposeTestPlayer()` 成功后才调用 `SystemNavigator.pop()`；重复 Back 共享同一退出 Future。此改动只作用于诊断页，不是任意宿主直接 `FlutterEngine.destroy()` 的库层保证。
- LYA-AL00/API29，同一固定 SDR 片源、PlatformView/`mediacodec_embed`、A→A+B→B→A+B→B。10462 APK SHA-256 `9a8670ea87fea92da64288d3b8ae9763f016d05caa48ff30a12ed3305047803a`。两轮都在 phase4 后正常 Back，第二轮连续发送两次 Back；同进程 PID `31914` 重入，正常播放。两轮 `AUTO_PLAYER_DISPOSE completed` 与 `ANDROID_DUAL_VIEW exit player disposed` 分别在 03:02:08.268/.269、03:03:22.285/.285，随后 Activity 返回 launcher；整轮未出现 `Retaining Surface owner without producer-termination proof` 或 crash。
- 代码路径上 `NativePlayer.dispose` 必须等 `mpv_terminate_destroy` 返回，再等待 `postTermination`；Android controller 的终止回调要求 `PlatformVideoView.PlayerTerminated` 返回 `true`，否则 Future 报错。因此这两次 `AUTO_PLAYER_DISPOSE completed` 证明正常退出协议的终止/owner release ACK 已返回；日志中没有 Java registry 数量的单独采样。原始 logcat `android-sdr-engine-exit-10462-20260927.log.gz` SHA-256 `d0f73fe77630bdda9f3727678d8a0121f145d7a06bc71035908e84f218b8a011`。
- 10462 构建后，源码额外增加 HDR disposal report 的退出前检查，故这份 APK 不覆盖该检查；最终源码需要复审和构建。任意宿主绕过页面直接 destroy engine、释放失败重试及多轮 owner/global-ref 定量计数仍待验证。测试结束恢复原 APK 10420、自动亮度模式 1/设置值 37，并删除手机测试源副本。

## 10463：并发自动停止与 Back

- 独立 V1 首审指出 10462 的 `_autoPlayerDisposed` 布尔位会让 Back 在另一个销毁已开始时提前返回，且诊断页也可能是嵌套路由。修订为所有 `_disposeTestPlayer()` 调用共享 Future，`dispose()` 也加入该 Future；PopScope 只包裹 `MEDIA_KIT_AUTO_SINGLE_PLAYER` 根诊断页，HDR disposal report 不干净时阻止退出。修订版 V1 代码复审 PASS，Dart 单文件 analyze 无问题。
- 10463 APK SHA-256 `ed8728e2f34e35174ea13ec82c5dc635e49f3b5def25eeeb7fe6bee4197947fe`，同一 SDR 源与自动亮度。`MEDIA_KIT_ANDROID_VO_SUMMARY_STOP_SECONDS=24` 于 03:07:32.014 启动自动停止，.087 完成 `vo=null` 并进入 Player 销毁；监测到 begin 后立刻由 ADB 发送 Back。直到 03:07:37.169 才同时记录 `AUTO_PLAYER_DISPOSE completed` 和 `ANDROID_DUAL_VIEW exit player disposed`，随后 Activity 已返回 launcher；没有 owner 保留告警。5 秒等待来自现有 native dispose grace period，本轮证明 Back 加入了正在进行的销毁 Future。
- 原始 logcat `android-sdr-engine-exit-10463-20260927.log.gz` SHA-256 `f3d65dc08c145a270b48ec48fe1274d2833733322bb646ef33f1e9b5503aadb2`。正常退出的 Java owner release ACK 由 `PlayerTerminated` 的 `true` 返回及完成的 `player.dispose()` 代码路径间接证明，未做独立 Java registry/global-ref 计数。任意宿主直接 `FlutterEngine.destroy()` 仍可绕过页面屏障；现有 Factory fail-closed 保留引用，不能宣称该路径已资源闭合。失败 disposal 的重试/恢复也未验收。
- 结束恢复原 APK 10420、自动亮度模式 1/设置值 37，并删除手机测试源副本。
