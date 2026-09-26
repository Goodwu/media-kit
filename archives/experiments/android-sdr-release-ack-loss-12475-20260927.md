# Android SDR 旧 A Release ACK 回复延迟，12475

## Current State

2026-09-27，华为 LYA-AL00/API29，固定本地 SDR H.264，自动亮度。10475 Release 诊断 APK SHA-256 `7d2cbddad8aec1fd650ee35329f881f004498781c50d0525cfec0317dc279fd3`。临时让双视图在初始阶段同时创建 A/B，并延迟旧 A 的真实 Available 1500ms，使 B 先到达。Java 处理 A `ReleaseSurfaceOwner` 后，仅将首次成功 ACK 的方法回复延迟 2500ms，超过 Dart 的 2 秒等待；后续调用正常返回。三个临时源码注入均已移除，不作为产品改动提交。

日志 `/tmp/media-kit-12475-ack-loss.log`：05:22:15.623 旧 A `wid=11078` global ref 删除一次；05:22:15.624 首次 ReleaseSurface 返回 `released`；05:22:15.626 Java ACK=true。05:22:17.626 Dart 等待 ACK 超时；首次 ACK 回复 05:22:18.127 才到；05:22:18.628 重试 ReleaseSurface 返回 `alreadyReleased`，05:22:18.629 同身份 ACK=true。已捕获日志中无第二次删除 A 引用。这个序列验证的是**Java 已处理但回复晚到**，不是 Java 完全没有收到 ACK。

05:22:28.960 系统截图处于 phase2、页面仅 B 有视频；05:22:33.445 的右半屏 B 区域仍有不同视频画面（右半屏 RGB 差异均值约 44.7/43.1/34.9），但当时 phase3 已重新挂载 A，不能由两图推断 B 在整个间隔内逐帧连续。没有独立的 Dart 重试完成日志、mpv WID 回读、全局 owner 定量闭合或任意 FlutterEngine.destroy 证据；P5/HDR 与晚到 Failed 仍待验。后来 phase3 新 A 复用了数值 `11078`，引用计数结论只针对本次旧 A 完整身份。

本机截图 SHA-256：`/tmp/media-kit-12475-b-a.png` 为 `b4e2133f9d7d611a28627b01b150e6be91a4487926a823c0650aac754bff78cd`；`/tmp/media-kit-12475-b-b.png` 为 `025df98477f031133051af6f7b91665657e2f7f3c0cee8b701e90a57239c8416`。结束强停测试进程，恢复 APK10420，自动亮度模式回读 `1`，屏幕状态 OFF；已有未知改动与图片未动。
