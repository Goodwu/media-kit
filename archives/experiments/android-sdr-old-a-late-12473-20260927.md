# Android SDR 旧 A SurfaceAvailable 晚到新 B，12473

## Current State

2026-09-27，在华为 LYA-AL00/API29 上完成两轮临时受控事件交错。10473 Release 诊断 APK SHA-256 `5fa2b447ee7734826fea0c1da49541ab188fee803d46c47fe1db796587f0c833`，固定本地 SDR H.264 素材，自动亮度。诊断页初始同时创建 A/B 两个 PlatformView；仅把创建序号 1 的 **真实** A SurfaceAvailable 事件在 Java 侧延迟 1500ms，保持原来的完整身份，再发给 Dart。新 B 正常发送。两个临时源码补丁在实验后均已移除，未作为产品改动提交。

第二轮：A `viewId=0, creationSerial=1, surfaceGeneration=1, wid=11078` 于 05:11:07.139 扣留；B `viewId=1, creationSerial=2, surfaceGeneration=1, wid=11094` 于 05:11:07.141 到达。A 于 05:11:08.639 放行，05:11:08.643 仅其 global reference `11078` 在已捕获日志内删除一次。B 的可见区域在 A 放行前与约 3.3 秒后两张截图均有视频且内容变化；RGB 裁剪差异 `(720,500)-(1440,2600)` 均值约 59.4/52.2/43.2。第一轮也观察到同身份 A 延迟到达及 A 引用删除。没有观察到 A 重新抢占 B。

这证明本 SDR 路径的旧 **Available** 晚到由 orphan 分支精确回收，B 在两个采样点均有不同的视频画面。B 的 mpv WID 绑定在本轮没有独立属性回读，由事件顺序、代码路径与可见 B 视频共同支持，不能从两张图推出中间每帧均连续。它不覆盖旧 Failed/Destroyed 晚到、Release ACK 回复丢失、P5、全屏显示、任意 FlutterEngine.destroy 或全局资源定量闭合。当前音视频属性日志显示 `vo=gpu, hwdec-current=mediacodec-copy`，不能把它算作 P5/HDR 原生路径验收。

## 证据与复原

- 两轮完整 logcat：`/tmp/media-kit-12473-old-a-first-run.log`、`/tmp/media-kit-12473-old-a-second-run.log`。
- 第二轮 B 截图：`/tmp/media-kit-12473-b-before.png` SHA-256 `02c3013b6505b2cf33e8f82fd9e633dcb5215e217b7de4969646f62c5a3d8299`；`/tmp/media-kit-12473-b-after.png` SHA-256 `2adc129243655430cf89196bc71673e2fcde43d1330ce5b04502a11`。截图仅存本机，不提交视频画面。
- 结束强停进程，恢复原 APK10420，自动亮度模式回读 `1`，屏幕状态 OFF。临时补丁反向移除后 `git status` 仅保留实验前已有的两处未知 Java/C++ 修改与图片。
