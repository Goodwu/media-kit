# Android SurfaceProducer 尺寸回调与 JNI 引用（2026-09-25）

`VideoOutput.setSurfaceSize` 调用 `SurfaceProducer.setSize` 后还显式调用 `onSurfaceAvailable`。旧实现每次回调都对 `getSurface()` 创建新的 JNI global ref 并覆盖 `wid`；只在 cleanup 释放当前 `wid`，同一 Surface 上反复调整尺寸会遗失先前引用。现在记录当前 Java `Surface` 身份，同对象回调复用 `wid`；若 Surface 对象更换，旧引用进入待释放集合，在 cleanup 一并延迟释放。cleanup 后把当前 `wid` 清零，避免重复 cleanup 重复安排释放。保留原有 5 秒释放窗口，未改变 Dart 的 Surface 绑定协议。

真机隔离测试：11038 Debug APK 临时在测试页启用 SurfaceProducer，打开应用私有目录中的 10 秒 HDR10 源，播放中调用两次 `VideoOutputManager.SetSurfaceSize`（810×405、1440×720）。日志显示初次 3840×1920 创建 `wid=11418` 和一次 `newGlobalRef`；两次尺寸回调均为同一 `wid=11418`，没有第二次 `newGlobalRef`。退出页面后 `VideoOutputManager.dispose`/`onSurfaceCleanup` 执行，5 秒后该唯一引用被 `deleteGlobalObjectRef` 释放。APK SHA-256 `702658b0af98a547a6c24d5a610411411d154f855bf09a22c322e28fd859ba47`，完整日志 `/tmp/media-kit-producer-ref-11038-full-logcat.txt` SHA-256 `fe63e5cdb2fe1404ca547affe508deb761e02359472b118338a7862ac23dee93`。构建使用 JDK17，`flutter build apk --debug` 成功。

测试页临时探针已撤回，`13.android_surface_texture.dart` 无工作树差异；设备恢复 10369、应用强停，私有媒体及 `/data/local/tmp` 副本删除。本轮覆盖同一 Surface 的重复尺寸回调和正常 dispose；真实 Surface 对象更换、回调乱序、强制进程退出及长播资源稳定性仍需独立验证。此证据不证明 HDR 激活或可见帧质量。
