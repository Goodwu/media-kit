# Android HDR10 旧 A SurfaceFailed 晚到，12476/12477

## Current State

2026-09-27，华为 LYA-AL00/API29，自动亮度、固定本地 HDR10 完整 MP4，正确 arm64 libmpv JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`。两个 Release 诊断包均在初始相位显示 A+B；Factory 为旧 A 的**真实已创建 Surface**先调用原 `releaseSurface` 释放 JNI 引用，随后发送明确标记为 `tempInjectedOldFailure` 的合成 SurfaceFailed，保留完整 controller/view/attempt 身份。B 的真实 SurfaceAvailable 暂缓 600ms。全部注入源码在实验后已移除，没有产品改动。

10476 首次注入命中暂存前的初始 controller generation 1；约22秒后 HDR10 输出重建为 generation 2 才打开，所以 10476 不能证明正式 HDR 输出的 B waiter 未被旧失败打断。10477 APK SHA-256 `43e8511c1613012047a0e0121fdbfab1f668feb49fc6dfd5186daa07be43013d` 将注入精确限定到重建后的 generation 2、A `creationSerial=3`、B `creationSerial=4`。

10477 第二次运行日志 `/tmp/media-kit-12477-old-failed-second.log`：05:33:11.124 A `viewId=2,wid=11142` 引用释放返回 `released`；05:33:11.132 B `viewId=3,wid=11146` 真实 Available 被扣住；05:33:11.224 合成旧 A Failed 送达 Dart；05:33:11.734 B 真实 Available 放行；05:33:12.188 HDR10 `ANDROID_HDR_OPEN` 成功，没有本次 `open_failed`。故 B 已有 ViewCreated 但尚未有 SurfaceAvailable 的窗口中，旧 A 失败未提前结束 HDR10 打开等待。

同一重跑的两张截图采于 05:33:13.854 和 05:33:16.489，均早于成功打开后 5 秒的 phase1 轮换；左半屏是黑底及启动器图标，右半屏有不同的 HDR10 视频画面。右半屏 RGB 差异均值约 23.47/22.33/22.24。截图本身不能独立归属 A/B Surface，右侧属于 B 的判断结合初始双视图布局与事件身份。另一轮同 APK 的 SurfaceFlinger 快照 `/tmp/media-kit-12477-old-failed-sf.txt` 在后续相位记录 BT.2020/PQ 与 HDR metadata types=3；这证明同包该路径可进入系统 PQ 合成，但快照不是初始 B 的同步图层证明。没有独立 mpv WID 回读或逐帧连续性证据。该失败事件是受控注入，不冒充真实 dataspace 拒绝。

本机截图 SHA-256：`/tmp/media-kit-12477-b-before-phase-a.png` 为 `acd1da4a1b1499eca6de9f8da846f2bd384c4b390ccd3de1c5b0dc1bfa6d656f`；`/tmp/media-kit-12477-b-before-phase-b.png` 为 `3d76343fad4c31735aa8f84fd68daf2921c7835fa1f666387b0b740a4e22f50a`。测试后恢复 APK10420、自动亮度模式 `1`、屏幕 OFF，三个 P5 诊断属性均回读 `0`；已有未知 Java/C++ 修改及图片未动。
