# P5 主机色度位置诊断（2026-09-24）

**后续纠正**：本文件早先两张`video`截图都是sRGB目标，不能称与手机BT.1886同目标。改用BT.1886 `window`截图后，左侧/居中对手机MAE为7.44/7.37，最大均35；结论仍限于色度位置标签的九点影响，见`android-p5-screenshot-target-correction-20260924.md`。

手机硬解外部YUV采样后写为3840×2160 4:4:4 packed10，主机mpv默认从yuv420p10源平面采样；原尺寸PTS10 RPU后九点RGB对手机MAE7.52/最大35个8-bit级。为测试色度采样位置，主机mpv0.41/libplacebo7.360.1同原片从头顺序解码到PTS10，保持3840×2160、BT.709/BT.1886、bt.2390、bilinear、dither=no、hdr-compute-peak=no等前轮设置，仅加`--vf=format:chroma-location=mpeg1/jpeg`，把主机默认`mpeg2/4/h264`左侧位置改为居中。该过滤器会改帧标签；PNG相对基线在全图有变化，说明设置实际影响渲染，但这不是硬件外部sampler的严格等价模拟。

同九点主机RGB仅中间行两个分量各变化1级：中心由`(118,114,116)`变`(117,114,117)`，右中由`(26,44,69)`变`(26,45,69)`；对手机九点MAE由7.52变7.56，最大仍35。故简单色度位置标签差异不足以解释当前九点色差；仍未排除两端不同色度上采样滤镜、邻域或硬件采样实现。主机居中截图`/tmp/media-kit-p5-mac-chroma-center-pts10.png` SHA-256 `64341d84dccadf1242117f0b0dea07b4ef5d6f65d3cd7bac0e9bf530ce2251cc`，生成脚本`/tmp/media-kit-p5-match-host-chroma-center.py`；基线`/tmp/media-kit-p5-mac-native-options-pts10.png` SHA `f9bbdb400cd4634befae7b2578b1cd8fd275571678c1f2026532395c1d8444d8`。另试主机`--vf=format:fmt=yuv444p10`，PNG全图有变化但九点值与基线相同；未核实过滤后RPU元数据与实际平面格式，不将其作为4:4:4等价证明。此轮不涉及手机、性能或可见画质验收。

后续核实补充：主机 `--vf=format:fmt=yuv444p10` 的 `video-out-params` 确为 `yuv444p10`，并保留 Dolby Vision/full/BT.2020/PQ；同目标 BT.1886 `window` 九点与未加滤镜 27/27 相同，整图 PNG 不同。见`android-p5-full-frame-rpu-20260924.md`。这纠正上段“未核实格式/元数据”的当时状态，仍不证明与手机外部 sampler 等价。
