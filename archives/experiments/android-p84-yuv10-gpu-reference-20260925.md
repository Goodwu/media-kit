# P8.4 硬解 PRIVATE→GPU 原始 YUV10 与软件基层同帧对照（2026-09-25）

## 结论

华为 LYA-AL00 对完整 P8.4 4K/29.97fps 源的独立 MediaCodec→`ImageReader.PRIVATE` 探针，在 `GL_EXT_YUV_target` 原始 YUV 采样后读回 `GL_RGB10_A2`。按 AImage 时间戳对齐软件 HEVC 基层，3帧×5像素×Y/U/V=45个分量的 GPU 数值均等于 `round(软件10-bit码值 × 1023/1020)`；未缩放直接差为0–2码值。这个结果强力证明**本机该独立输出路径可把10-bit基层送到GPU**，也说明此前 ByteBuffer `nv12` 8-bit 不能代表所有 MediaCodec 输出。它仍不证明 mpv 当前普通 OES RGB mapper 是否保留该精度、SDR tone mapping颜色或显示端输出。

## 输入与方法

- 设备源 `/data/local/tmp/media-kit-p84-full.mp4`，主机临时拉取后 SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`，1232790317字节；比对后删除临时主机副本，设备原始源保留。
- 11076 APK SHA-256 `cfa34db2be4c64814101a34a605a8ce181026020d30c94cb19c79e1b76c33f0f`，用已有 `P5CodecProbe`/`p5_gpu_import_probe.cpp` 诊断入口，关闭媒体播放器入口；`MediaExtractor`→`OMX.hisi.video.decoder.hevc`→16×16初始 `ImageReader.PRIVATE`/maxImages3/GPU_SAMPLED。输出实际3840×1920、厂商color-format805、BT.2020/HLG；250帧输出均有同PTS的RPU输入，所取3张Image的timestamp均匹配输出PTS。JNI探针创建ES3/EGLImage/OES，`GL_EXT_YUV_target` 原始YUV纹理采样至10-bit FBO并读回；不是产品 mpv mapper。
- 选中 Image timestamp 0、3,436,766、6,806,800 µs，ffprobe对应软件解码显示帧编号0、103、204（时间0、3.436767、6.806800秒，µs舍入差1）。FFmpeg从**相同源文件**选择这3帧，输出 `yuv420p10le` 原始平面；比较坐标x=0.1/0.3/0.5/0.7/0.9宽度、y=高度一半，4:2:0色度坐标除2。命令及可复现脚本见`android-p84-yuv10-compare.py`。
- 完整日志压缩于 `artifacts/android-p84-yuv10-20260925/11076-logcat.txt.gz`；逐点数值及差异在同目录`compare.txt`。15个采样点的45个YUV分量直接差集合`{0,1,2}`，按`round(code×1023/1020)`缩放后45/45严格相等。这个缩放是观测到的纹理归一化关系，不擅自解释为源数据被改写。

## 普通 OES 路径边界

同一探针的普通 `samplerExternalOES` 也读到RGB 8-bit和10-bit FBO样本；在3帧×3位置×RGB的27个分量中，18个10-bit值不等于把同位8-bit读数简单扩展为`round(code×1023/255)`（差-2到+2）。这排除“10-bit读回只是8-bit FBO码值机械放大”的简单解释，但颜色转换、舍入/抖动及采样链未隔离，不能单凭此判普通OES达到10-bit输入精度。产品 mpv `hwdec_aimagereader.c` 把该外部纹理声明为`IMGFMT_RGB0`/UNORM，需直接对其渲染输入或固定帧SDR输出做数值比对。

## 启动取图错误

NDK头文件将 `-30001` 定义为 `AMEDIA_IMGREADER_NO_BUFFER_AVAILABLE`；`AImageReader` 文档明确允许回调触发后`acquireLatestImage`仍返回此值（例如先前latest调用已回收排队图像）。因此11074/11075各一次启动日志不能单独判Reader故障；产品路径仍需验证首次可见画面/重复冷启动，并区分普通竞态与真正的首帧丢失。相关头文件为NDK 27.2的`media/NdkMediaError.h`和`media/NdkImageReader.h`。

实验完成后安装基线`versionCode=10369`，临时拉取的1.23GB源及63MB原始解码帧已删除；只保留可复现脚本、对比结果和压缩日志。
