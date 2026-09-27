# P5 Glass 首帧 VO mix/提交与 Surface 采样，12496

## Current State

2026-09-27，LYA-AL00/API29，指定 Glass P5 本地源 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`。隔离构建的 12496 arm64 APK SHA-256 `ba11ad33fd0ede37baced43ee185b23a5e7f2745893b86a545235298582d1160`，只把精确链接基线 JAR 内 arm64 `libmpv.so` 换成默认关闭的限量 VO mix 探针；JAR SHA-256 `f745146332b532d8baeb162b7a33ddefa03ae8dc0a7731f13a9584ef7e6fa3f9`。同包新进程短轮按探针关闭→开启→关闭，P5 raw/direct/RPU/retire 属性均为 1/1/2/1。沿用 80 ms PixelCopy、100 ms 媒体位置和预验证固定源诊断；点击回调内启动采样，不含物理触摸至 Dart 回调。竖屏测试页，非真全屏。

| 轮次 | VO 探针 | PixelCopy 首次黑底 | Surface 采样区首次内容 | 首个 AImage PTS | 启动 HEVC 缺参考 POC 行数 |
| --- | --- | ---: | ---: | ---: | ---: |
| off1 | 关 | 2.228 s | 4.490 s | 0.250250 s | 17 |
| on1 | 开 | 2.138 s | 4.385 s | 0.250250 s | 17 |
| off2 | 关 | 2.606 s | 4.975 s | 0.050050 s | 18 |

开启探针一轮，在相同 logcat 设备时钟下，`media_opened` 是采样开始后约 0.313 s，首个 AImage 约 2.020 s；VO `queue` 第一个有效 mix 帧 PTS 0.250250 在约 2.010 s。媒体 PTS 2.102100 的 `seq=61` 在 logcat epoch `1790475149.396` 进入 mix，`draw_done` 在 `.399` 且 `render_ok=1 valid=1`，`flip` 在 `.415` 且 `submit_called=1 submit_ok=1 swap_returned=1`。PixelCopy 在 `.693` 才于固定区域超过旧内容阈值，即相对该 `flip` 约 278 ms。**12497逐次采样已证实旧阈值显著晚于首个非零像素**，这个差值不能作为 GPU/显示延迟；见`android-p5-glass-precontent-12497-20260927.md`。`flip` 返回也不证明物理面板呈现。

探针开启轮 4.385 s 落在此前同 JAR 四轮 4.282–4.525 s 区间内；off2 的 4.975 s 显示轮间变动，不支持把差异解释为探针性能收益。三轮 POC 错误仍复现，尚无错误与输出等待的因果证据。此实验已经排除“`stream.position` 等于已呈现帧 PTS”的错误口径，确认 VO 实际拿到 PTS 2.102 s 并完成本地提交调用；首帧瓶颈仍需继续拆成打开至首个解码输出、VO 至 Flutter Surface 消费、片源采样区域三部分。

原始进程日志在 `artifacts/android-firstframe-vo-mix-12496/`：`off1.log.gz` SHA-256 `4a88631e5030964c7388035436a645ae1d94ff570e6587b65acda323a9036f1c`，`on1.log.gz` SHA-256 `b42f5e403e8236a3c2e92d62bcd89346c54fe38d95fa2fc472b291f2749ffc44`，`off2.log.gz` SHA-256 `5b60c6379c0364d798b874a4a12f36f3e3ed2550c7b3ae28d2d2411dca301557`。VO 探针压缩补丁 `vo-mix-trace.patch.gz` SHA-256 `fa6c98ee3cb72e63e185c0f8c78c09f7c010f1359169f4786ae2e010e7cb8b04`，解压原文 SHA-256 `34256467c87fb43ab25b536ccb34e5f9cabea1e9c4a3a4a8ca371f3f27bea31e`。该补丁只在隔离构建生效，未进入产品源树。历史 AImageReader object 仍是精确链接基线所必需，见 `android-p5-jar-exact-baseline-20260927.md`。

结束后强停应用，五个 P5/VO 属性归零；重装原 12492 APK，自动亮度模式 1、屏幕 OFF。下一步先核对 2.1–2.4 s 在设备实际采样矩形对应的源像素，再决定是否加入同帧图像身份/Surface 消费事件；同时继续追踪 `media_opened` 至首个解码输出约 1.7 s。正式 2 秒目标仍未通过，须无探针真全屏物理屏幕冷/热重复验收，覆盖 SDR/HDR10/P8.4/P5。
