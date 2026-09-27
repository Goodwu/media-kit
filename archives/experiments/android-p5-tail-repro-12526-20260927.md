# Glass P5 尾段紫屏短轮复现（12526，2026-09-27）

华为 LYA-AL00/API29，自动亮度；指定 Glass P5 原片 `/data/local/tmp/media-kit-p5-glassblowing2-4k5994.mp4`，已核身份 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`。APK 12526 仅 arm64、自建 arm64 JAR，SHA-256 `449e9b60c5878a96c9275f1349728b1f2530b550f28c0cc06d952114d621c248`。黑底物理全屏 Texture 转 SDR，诊断性 `Media(start=170s)`；这不是正常从片头播放的等价条件，也不是首帧优化。

两轮新进程、同 APK：

| 轮次 | 尾段取图/画面 |
| --- | --- |
| 1 | PTS 170.003 初次 `acquireLatestImage -30001` 后恢复出帧；PTS **174.958116667** 再次 `-30001`，随后 `Mapping hardware decoded surface failed` / `Failed rendering frame`；约片尾后截图为整块紫色。 |
| 2 | PTS 170.003 同样一次初次取图失败后恢复；PTS 174.240 时图像计数达250，前后截图均为 Dolby Vision 片尾画面；本轮选摘日志没有尾段第二次 `-30001`，最终截图没有紫屏。 |

`run1-purple.jpg`、`run2-before.jpg`、`run2-after.jpg` 与同名日志保留现场。两轮说明尾段紫屏在短轮可复现但非必现，且与 PTS174.958 的渲染失败同轮相邻；不能仅凭此判定同一 codec buffer 被重复 release，亦未取得 `end-file` 同时刻事件或 Buffer 身份。起播 PTS170.003 的错误两轮均有，须与尾段错误分开。

下一步在失败路径保存最近 map 的 reader 代次、源帧与 codec buffer 身份、PTS、release 返回、AImage 时间戳及 callback 序号，并补 `end-file` 事件；再区分重复映射、尾帧重绘、EOS 状态与清屏策略。不要仅用延长取图 retry 或掩盖紫色作为根因修复。实验后恢复日常 APK 12492、P5诊断属性0、自动亮度并熄屏。
