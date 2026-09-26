# AImageReader 持图上限 3→2：HDR10/P8.4 Texture 直解隔离试验（2026-09-25）

**后续纠正：**同一隔离库只把maxImages改回3的11066也成功直接硬解HDR10并推进到视频62.762秒，因此不能把11064成功归因于降为2，亦不能将2作为必要修复。严格A/B见`android-aimagereader-maximages-ab-20260925.md`。

前轮11057/11058在本机 HDR10 4K、`hwdec=mediacodec`/`gpu-next` Texture 的厂商 HEVC 输出端口重配置时报 `-1010`，随后回退软件；缩最终纹理到1440并未解决。当前隔离mpv的 `video/out/hwdec/hwdec_aimagereader.c` 以 `AImageReader_newWithUsage(..., maxImages=3)` 创建PRIVATE/GPU_SAMPLED_IMAGE Reader。本轮**仅**把该参数降到2，使用一致的 `_build-isolated-arm64` 重链，libmpv SHA `23bd9a3c0ea521f28240f8a3eb7a2196ec4a993fd55e982d1c6a6e464d4792d8`，与固定helper包装的本地arm64 JAR SHA `0763b095983cf2b98e4363320d8d69baa4580c9c4a4c436f883075fa29d454f8`。该隔离库含此前P5/FFmpeg试验修改，不与11057 pinned库只差一个参数；结论只能是新候选在两素材可运行，不能严格把改善全部因果归于maxImages。隔离差异如下：

```diff
-        3, &p->reader);
+        2, &p->reader);
```

两轮测试应用均是当前树、`gpu-next`→Flutter Texture、默认直`mediacodec`、输出最大宽1440、BT.709/BT.1886和`bt.2390`，未启用8-bit copy诊断。

| 轮次 | 源 | APK SHA-256 | 真机输入与进度 |
| --- | --- | --- | --- |
| 11064 | 登记的完整HDR10/3840×1920/29.97 | `6408fa79bc72e9ae74098842784dc5e763f88ea9c974bad246060ae63f116a75` | `pixelformat=mediacodec`、BT.2020/PQ；t28/60/90/120 视频位置0.967/32.966/62.963/92.959秒，所有采样VO/decoder报告掉帧0 |
| 11065 | 登记的完整P8.4/3840×1920/29.97 | `c479f5fc5ab42e644915039fa0036407cdf8d160a9f1e33ff32b9c0fd1df5c01` | 滤镜前短暂见Dolby Vision参数，打开后`pixelformat=mediacodec`、BT.2020/HLG；t60/90/120视频位置3.336667/33.333300/63.329933秒，VO/decoder报告掉帧0 |

两轮均在输出端口重配置时仍有较高 `nBufferCountActual` 请求被`-1010`拒绝，但退到可分配的数量后**没有**`Failed to allocate output port buffers`，事务成功且持续播放。两轮开头各出现**一次** `acquireLatestImage failed after retry: -30001` / `Mapping hardware decoded surface failed`，之后日志未再出现，时间持续前进；这说明 maxImages=2 还有启动持图压力，不能称无错误。HDR10、P8.4各拍两张相隔约5秒的系统截图，视频ROI `(0,370,1440,1090)` 内 RGB SHA 不同、差异覆盖几乎整个区域。原日志、截图、SF dump 在 `artifacts/android-hdr10-reader-max2-20260925/` 与 `artifacts/android-p84-reader-max2-20260925/`。

此试验把 S1/S2 从8-bit ByteBuffer copy 推进到 opaque MediaCodec Surface + GPU 路径，仍**未证明10-bit代码值保真**。当前非raw mapper将外部OES纹理作为 `IMGFMT_RGB0`/四通道UNORM输入，可能经过厂商YUV→RGB及位深/传递处理；`pixelformat=mediacodec` 本身不等于数值正确。下一步需读取 AHardwareBuffer 实际格式/代码值，与独立源帧在相同色域比较；同时解决 maxImages=2 的首帧持图错误并做启动/重建/长稳验收。P5 raw mapper目前要求DV元数据，不能直接复用到HDR10/P8.4。PQ/HLG最终显示和颜色门禁仍开放。

运行后测试应用强停，清应用私有可重建暂存，恢复设备官方10369；隔离改动留在 `/tmp/media-kit-mpv-clean-2194` 供后续复核，未进入产品依赖。
