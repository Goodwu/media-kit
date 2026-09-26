# SDR 双视图正常返回后的 engine detach 缺口：10461

- LYA-AL00/API29，10461 SDR 双视图测试包、源及 SHA 见`android-sdr-dual-view-10461-20260927.md`。自动亮度 1/设置值 37。播放到 phase4、B 重绑完成后，ADB 发送正常 Android Back；这是 Activity/Flutter engine 退出，不是 `am force-stop`。
- 原进程 PID `30690` 在返回后继续存活。02:58:50.792 当前 B `wid=11286` 的 SurfaceDestroyed 触发 Dart detach，并开始严格 `vid=no`；02:58:50.868 `PlatformVideoViewFactory.onEngineDetached` 记录 viewId 0/1/2 均 `Retaining Surface owner without producer-termination proof`。截至重入前的 logcat 没有 `AUTO_PLAYER_DISPOSE completed` 或该 handle 的 PlayerTerminated 记录。Engine detach 早于可证明的 Player/producer 终止，Factory 按 fail-closed 规则保留 owner；此轮不能证明 JNI 引用最终释放。
- 02:59:18.671 从 launcher 重开，进程仍为 PID `30690`；新 Flutter engine 于 .901 绑定新 Surface、再次打开相同视频，并在后续双视图阶段继续绑定。新画面可见不能证明旧 engine 的三个 owner 已回收。重入截图 `android-sdr-engine-detach-10461-reentry.png` SHA-256 `83473be6f2debbb65fa21361ae74b7e394f1072f4e2aa1ae46e8312fb1ee16c7`；完整日志 `android-sdr-engine-detach-10461-20260927.log.gz` SHA-256 `c9eae168e5cded5d11f3a5a2194fc6819b8a876589a0811a5690e7f481657865`。
- 这是资源闭合验收失败，需解决 Activity/engine 正常销毁前的 Player 终止屏障或等效安全所有权转移，并用同进程多轮返回/重入证明旧 owner 最终回收。测试结束以 `am force-stop` 清除进程，恢复原 APK 10420、自动亮度 1/设置值 37并删除手机测试源副本。
