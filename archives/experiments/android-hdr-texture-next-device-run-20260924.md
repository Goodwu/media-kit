# Android HDR 素材 Texture SDR 实机运行清单

本清单独立于 [原生视图四包运行清单](android-hdr-transaction-next-device-run-20260924.md)。当前只完成离线构建与校验；用户已明确要求继续安装。

三个有效候选包及 SHA-256、固定源、构建参数见 [包清单](android-hdr-transaction-apks-20260924.json)。APK 实际 versionCode 为 6230/6231/6232（Flutter arm64 split 比 build number 增加 2000）；JDK17、同一 arm64 JAR、`gpu-next`、硬解及控制器显式 OpenGL 配置。每包的 aapt 版本、ZIP 完整性、arm64-only 和 APK 内 libmpv SHA 均已核验。4224/4225/4226 未显式选择 OpenGL，已被取代，不用于运行。

安装前只读重核设备序列/API、当前已装版本、候选 APK SHA、三份固定源 SHA、P5 三个诊断属性、两项系统设置及 4154 恢复包 SHA。按 6230→6231→6232 升序执行；每包记录启动时间/PID、私有暂存 SHA、VO/hwdec/GPU API、滤镜与输出色彩参数、RPU/mapper 统计、time-pos 与掉帧、跨时可见画面、SurfaceFlinger 图层及终态。P5 按实验要求设置 `p5_rpu_probe=2`、`p5_raw_yuv=1`，保持 `p5_raw_perf` 关闭；结束后恢复原值并回读。

| 包 | 关键验收与边界 |
| --- | --- |
| 6230 HDR10 Texture SDR | 固定 HDR10；验证持续播放、音画、seek/后台返回、帧进度与颜色。Texture SDR 不以 HDR 图层激活作为本包目标。 |
| 6231 P8.4 Texture SDR | 固定 P8.4；确认 HLG 基础层解释、RPU 不应用、SDR tone mapping 与连续播放。与此前 2089 明显卡顿结果比较，不能仅凭解码或截图判流畅。 |
| 6232 P5 Texture SDR | 固定 P5；运行属性门禁必须通过，逐帧核对 PTS/RPU 附着、raw-YUV/R32F mapper、像素参考、持续播放及用户可见颜色。任一证据缺失判 `INCONCLUSIVE`，不能仅凭有画面判 DV reshape 正确。 |

三个包均需分别记录人工可见的流畅度和颜色观察；机器日志、截图、aapt/构建结果不替代可见验收。恢复 4154 时保留数据，回读版本、P5 属性与系统设置，并确认原基线仍有视频。若恢复包校验失败，停止实验并保留日志。
