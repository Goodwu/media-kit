# Android HDR 事务与显示出口下一轮实体机运行清单

截至 2026-09-24 的只读预检：目标是 `3EP7N18C28016072`（LYA-AL00/API29），现装 `com.example.media_kit_test` versionCode 4154，`/data` 可用约 26 GiB。`debug.media_kit.p5_rpu_probe=0`，`debug.media_kit.p5_raw_yuv` 和 `debug.media_kit.p5_raw_perf` 为空；`touch_disable_mode=1`、`stay_on_while_plugged_in=0`。四个当前候选包 6233–6236、SHA、固定源、编译条件和被取代版本见 [包清单](android-hdr-transaction-apks-20260924.json)。4154 恢复包 `/tmp/media-kit-p84-platform-full-2154.apk` 的 SHA-256 为 `40b471cd49d95ab02dee299b76945c2e1177e983b80deb7e2c31cd1d2c8f5740`，本轮已复核。

同轮只读重算设备三份固定源 SHA-256：HDR10 `e4f869b140e3ef322b7fc63fefe015593708f6443fc79060fa3e7f2234816937`、P5 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`、P8.4 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`，均与本轮固定样本记录一致。安装前仍须复核设备和文件未变。

用户已明确要求继续安装。旧 4218/4220/4222/4223 与 4219/4221 均不用于运行。

每包启动前核对 APK SHA/versionCode、设备序列/API/已装版本、固定源 SHA、当前三个诊断属性及两项系统设置。四包均由同一 4217 本地 arm64 JAR 构建，JAR SHA `e7b4cfefed60052277519a39d4834eb33d35f08342c59610279232878d1036bd`。按版本升序安装；保留应用数据，不卸载。限定采集从启动时间/PID 开始的 logcat、mpv 属性、Surface/VO 事件、SurfaceFlinger 图层 dataspace、视频区域跨时图像和终态，记录设备热状态与可见性；日志与截图不能替代用户的流畅度、颜色观察，也不能单独证明 HDR 激活。

| 顺序 | 包 | 受控条件与关键判据 |
| --- | --- | --- |
| 1 | 6233 HDR10 原生事务 | 固定 HDR10、原生视图、实际能力报告；确认私有暂存 SHA、首个控制器重建、当前 Surface 绑定、`mediacodec_embed`/硬解、第一幅可见画面、PQ 图层与稳定播放。执行后台返回及重复切源时检查不黑屏、不跳回、不误用旧 Surface。 |
| 2 | 6234 P5 原生事务 | 先设置 `p5_rpu_probe=2`、`p5_raw_yuv=1`，保持 `p5_raw_perf` 关闭；确认应用通道回读成功、RPU 附帧在 320 帧后持续、raw YUV/R32F mapper、`gpu-next`/OpenGL、PQ/10-bit Surface、实际画面/颜色/50fps 性能。任一门禁缺失即记失败，不把可辨认画面视为 DV reshape 通过。结束后恢复三个属性原值并回读。 |
| 3 | 6235 P8.4 强制 PQ | 属性为原值；固定 P8.4，日志必须同时有实际 `displayHdrTypes` 与 `simulateNoHlgForP84=true`。预期剥离 RPU、`gpu-next`/OpenGL、PQ/10-bit Surface；核验像素、图层信令、持续播放与丢帧。此轮是支持 HLG 手机上的策略模拟，不计真实无 HLG 设备兼容验收。 |
| 4 | 6236 P8.4 自然 HLG | 同一 P8.4 素材与本地 libmpv，`simulateNoHlgForP84=false`；预期 `mediacodec_embed`、HLG 图层、无 RPU 应用。与 6235 比较时记录安装顺序、热状态和时间；完成全片及后台返回、音画/seek 与长播门禁，不能把顺序差异直接归因于色彩路径。 |

每轮结果分别判定：源码/包身份、原生链路与第一帧、连续视频与音频、实际图层精度/dataspace、可见流畅度/颜色、HDR 激活、生命周期与长播。任何一项证据不充分记 `INCONCLUSIVE`，异常或门禁失败记 `FAIL`，不以单轮通过推出所有素材和双视图稳定。P5 的 RPU 处理须有同 PTS 附帧、reshape/像素参考和真实输出证据。Texture SDR 的 HDR10/P8.4/P5 路径仍是独立验收项，四个原生包不覆盖它。

结束后以保留数据的降级安装恢复 4154，不卸载/清数据；回读 versionCode、属性原值 `0`/空/空、系统设置 `1`/`0`，并确认原基线有可见视频。若安装前预检失败或恢复包身份不符，停止实验并记录原因。
