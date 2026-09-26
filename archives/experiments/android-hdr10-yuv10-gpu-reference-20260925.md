# HDR10 硬解 PRIVATE→GPU 原始 YUV10 与软件同帧对照（2026-09-25）

## 结论

用与P8.4相同的独立 `MediaCodec→ImageReader.PRIVATE→GL_EXT_YUV_target` 探针，HDR10完整源的3帧×5位置×Y/U/V共45个GPU 10-bit读数，全部等于`round(软件HEVC码值×1023/1020)`；直接差均为0–2码值。至此HDR10和P8.4两个Texture必验输入都已有本机PRIVATE→GPU **原始基层10-bit可得**的数值证据。正式mpv仍通过普通OES RGB映射，不能据此宣布最终SDR色彩或渲染链10-bit保真。

## 证据

- 设备源`/data/local/tmp/media-kit-hdr10-full.mp4`临时拉取后SHA-256`e4f869b140e3ef322b7fc63fefe015593708f6443fc79060fa3e7f2234816937`，542755228字节；比对后删除主机临时副本，设备源保留。
- 11077 APK SHA-256`fa057da928ec1bc6ef4c1fec2fceeefeb512a558c3d14d8384717cb018a7cad2`，同已有探针，关闭媒体播放入口，16×16初始Reader/max3/GPU_SAMPLED、实际输出3840×1920、厂商format805、BT.2020/PQ；250输出帧、RPU输入0。Image时间戳0、3,437,000、6,840,000 µs均匹配输出PTS，软件显示帧编号分别0、103、205。
- FFmpeg从同源选择上述帧，输出`yuv420p10le`；使用`android-p84-yuv10-compare.py`的`--indices 0 103 205 --pts-us 0 3437000 6840000`比较。逐点值见`artifacts/android-hdr10-yuv10-20260925/compare.txt`，完整日志压缩于同目录`11077-logcat.txt.gz`。软件参考原始帧和拉取源已删除，可按脚本注释与设备保留源重建。
- 同一探针的普通OES RGB 8-bit/10-bit FBO样本中，27个可对齐RGB分量有14个10-bit值与`round(8-bit值×1023/255)`不同，差在-2到+2。这排除机械放大解释，但仍不能排除颜色转换舍入/抖动，不能当作正式mpv OES精度证明。

本轮仅为输入与GPU导入数值诊断，不存在视频可见播放验收。完成后手机恢复基线`versionCode=10369`。
