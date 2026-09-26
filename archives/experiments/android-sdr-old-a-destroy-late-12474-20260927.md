# Android SDR 旧 A SurfaceDestroyed 晚到，12474

## Current State

2026-09-27，华为 LYA-AL00/API29，固定本地 SDR H.264，自动亮度。10474 Release 诊断 APK SHA-256 `ba0fd6f8fdef713d5db7d6757a3d47ebe9af37715ede4e5d97898589e7596708`。保持原双视图相位：先 A、再 A+B、再仅 B；仅在 Java Factory 临时延迟旧 A 创建序号 1 的真实 Destroy 事件 1500ms，完整身份不变，重复 Destroy 均延迟。该临时源码补丁在实验后已移除，未作为产品改动提交。

第二轮日志 `/tmp/media-kit-12474-old-a-destroy2.log`：A `viewId=0, creationSerial=1, wid=11078` 的 `SurfaceAvailable` 先到达；05:17:43.084 B 的 `SurfaceAvailable` 到达（`wid=11270`）；05:17:48.013/.017 A 的两个 Destroy 被扣留，05:17:49.514/.518 放行，本轮只观察到一次 `deleteGlobalObjectRef ref=11078`。双视图阶段媒体位置在 phase1/phase2/phase3 分别约 4.838/9.592/14.597 秒，播放状态为 true。A 放行后采得的 05:17:49.647 系统截图中，phase2 布局仅剩 B 且有视频；05:17:54.212 的截图画面已变化，但此时 phase3 已重新挂载 A，故第二张图不能单独证明仅 B 的连续帧。旧 A 晚到后没有观察到清空 B 画面或 B 引用删除；本轮没有独立的 mpv WID 回读。

首次截图的设备采集耗时超过 1.5 秒延迟，因此没有放行前的截图；本轮证明真实旧 Destroy 晚到后的精确 A 引用删除及 B 在随后的一个采样点可见，不能据此声称中间每帧连续或全局资源闭合。晚到 Failed、Release ACK 回复丢失、P5、任意 FlutterEngine.destroy 仍待验。

本机截图 SHA-256：`/tmp/media-kit-12474-b-before2.png` 为 `b85414c35935093263b78722f253d8eb284ba1bdb7c78ae8e25d195589f65849`；`/tmp/media-kit-12474-b-after2.png` 为 `d033d1f7a6f7be5cd71670ecc3b768c7ef6547271fe44c59cf94413a0dc07745`。结束强停进程，恢复 APK10420，自动亮度模式回读 `1`，屏幕状态 OFF。实验前已有的两处未知 Java/C++ 修改及图片未动。
