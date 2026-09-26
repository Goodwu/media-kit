# T1/T2 GPU→PlatformView 实机实验清单

这两包专门补 [总计划验收矩阵](../conversations/android-hdr-dv-display-plan-20260922.md) 的 T1/T2；并非先前七包的替代。候选身份见 [APK 清单](android-hdr-transaction-apks-20260924.json)：6237 固定 HDR10、gpu-next/BT.2020/PQ；6238 固定 P8.4、`dolbyvision=no`、gpu-next/BT.2020/HLG。实验开关 `MEDIA_KIT_ANDROID_GPU_PLATFORM_HDR=true` 仅在 HDR 事务与 PlatformView 模式生效；两包均固定 `hwdec=mediacodec`，不覆盖软解对照。

两包已完成 JDK17 同 JAR arm64 Release 构建，aapt versionCode、SHA-256、ZIP、arm64-only、APK 内 libmpv 身份校验。静态策略/输出所有权审核未发现新确定性代码阻断，43 项 HDR 定向测试通过。目标设备此前在同类 `RGBA_1010102` Surface 上请求 PQ dataspace 返回 `-22`；当前代码在创建 Surface 时设置失败便不发布 WID，因此首要运行目标是复现或推翻该反例，**不能预先视为可播放包**。HLG 也走同一 NDK dataspace 设置链，需单独验证。

用户已明确要求继续安装。安装前只读重核目标设备、当前已装版本、候选与固定源 SHA、4154 恢复包和系统/诊断属性原值；预检不符即停止并记录。

先单独运行 6237：记录 Surface 创建时的 `ANativeWindow_setBuffersDataSpace` 参数/结果、是否发布当前 generation WID、VO 初始化与首帧，并回读 `gpu-api=opengl`、实际 `gpu-context=android`；编译期指定 OpenGL 不能代替运行时上下文回读。若仍返回 `-22`，判 T1 `FAIL` 并停止播放验收；保留完整日志，不通过放宽错误门禁继续。6238 同样先过 HLG Surface 创建门禁；若成功，再回读当前 Surface 的 `RGBA_1010102`/HLG dataspace、gpu-next/MediaCodec/BT.2020/HLG、实际滤镜参数和出帧后的图层状态，并覆盖 Surface 重建。`SetColorSpace=true`、层标签或初帧截图都不能单独证明 HDR 激活。

设备门禁通过后才进入同源 PTS 的完整画面、连续进度/丢帧、人工流畅度和独立颜色参考检查。P8.4 还需滤镜后/renderer 输入证据证明 RPU 未被应用；当前 `vf` 文本回读仅证明请求被接受。两包当前都只覆盖硬解开；计划要求的软解对照、完整长播和显示阳性仍另行完成。结束时装回 4154，复核属性/系统设置和可见 SDR 基线；任何恢复校验失败均记录并停止后续实验。
