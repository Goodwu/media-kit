# HDR10 Texture SDR 解码路径对照（2026-09-25）

后续位深复核确认本轮 `mediacodec-copy` 为8-bit NV12；当前工作树已将其限于显式 `MEDIA_KIT_ANDROID_TEXTURE_COPY_DIAGNOSTIC=true`。本轮APK构建于收紧前；该结果仅供吞吐诊断，见 `android-texture-copy-bitdepth-gate-20260925.md`。

固定真机 LYA-AL00、已登记的 `/data/local/tmp/media-kit-hdr10-full.mp4`（3840×1920、29.97 fps、BT.2020/PQ），测试应用 `gpu-next`→Flutter Texture、BT.709/BT.1886、`bt.2390`、最大纹理宽 1440。全程使用同一源；诊断包分别为 11057、11058、11059，均为当前工作树本地 debug 构建。11059 APK SHA-256 `2d48f456f6989ef6d14f4255d13b5408bd3afa7808bb8f713240e7b26aa32c84`。

11057 请求 `hwdec=mediacodec`，Texture buffer 最初 3840×1920；厂商 HEVC 解码器在输出端口重配置时报 `Failed to allocate output port buffers ... (-1010)`，之后 `hwdec-current=no`、回退软件输出 `yuv420p10`，事务按硬解要求失败。11058只增加最大纹理宽1440，日志确认目标1440×720，但同样在源分辨率的解码器输出端口重配置失败，排除单纯缩小最终 Texture buffer 就足够的假设。两轮软件回退还出现 `r16u` 不支持线性采样的 scaler 错误；它是回退后的另一问题，不能解释先发生的 MediaCodec 端口错误。

11059 将**非 P5 Texture**策略明确改为 `mediacodec-copy`，P5 原有 raw/RPU 直解策略不变；轨道验收按策略检查 `hwdec-current`。真机事务成功打开 HDR10，日志输入 `nv12`、BT.2020/PQ、`sigPeak=49.261085`，纹理输出请求1440×720；没有上述端口分配或 scaler 错误。t28/60/90/120 的视频时间分别1.568/33.567/63.563/93.560秒，后3段每30秒推进约30秒，播放器与解码器掉帧计数均0、pause=no/idle=no。两张相隔约5秒的系统截图在视频 ROI `(0,370,1440,1090)` 内 RGB SHA 不同，差异覆盖几乎整个 ROI，支持视频内容持续变化。SurfaceFlinger 应用主层 dataspace `UNKNOWN (0)`、HDR metadata types0；Texture 并非独立 HDR Surface。原始日志、两图、SF dump 在 `artifacts/android-hdr10-texture-copy-20260925/`。

这证明当前 S1 HDR10 Texture SDR 候选在机器侧短时持续播放、无报告掉帧；**不是**独立颜色真值、真人可见流畅、实际物理 present、30分钟热稳或完整 SDR 色彩验收。BT.709/BT.1886 与 tone mapping 由测试策略设置，仍应加实际回读/像素对照。`mediacodec-copy` 的 8-bit `nv12` 路径也可能损失 HDR10 的 10-bit 精度，不能把这一轮当作色彩正确性通过；须确认厂商输出位深或以独立参考量化误差。P8.4 S2、P5 S3 和 Platform HDR T1/T2/T4 仍分别开放。

测试后停止应用，清理其可重建的 `android-hdr-staged` / `file_picker` 缓存，恢复官方基线 APK 10369。
