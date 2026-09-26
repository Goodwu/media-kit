# P5 硬解输出到 CPU 可读 ImageReader 的边界实验（2026-09-25）

## 目的与输入

尝试在现有 ByteBuffer8 与 PRIVATE/OES→GPU packed10 之间增加一个检查点：同一台 LYA-AL00（Android 10）的 `OMX.hisi.video.decoder.hevc` 输出到公开 `ImageReader(YUV_420_888)` Surface，读取 PTS 10.000 s / 第 500 帧的原生整数平面。该测试不修改产品代码。

输入为先前同文件输出模式对照所用的前 512 个 HEVC 包、`hvc1` 样本条目带 P5 `dvcC` 诊断组合。重新封装的容器 SHA-256 为 `6e89e45c6799fbc3f61128d7cec294a8bde57e9ac1d2b3f1892506d7b8a7e580`，不同于上次容器 SHA；目标第 500 包 PTS `10.000000`、大小 `263461`、SHA-256 `0030ffab4d9d435adaa0fa834fa3a366c9ec75a18c5dc23e593a6306b6c47363` 与上次记录相同。这里只确认了目标包身份，不把整段容器宣称为逐字节相同。

探针源码：`artifacts/android-p5-hevc-decoder-probe/SurfaceYuvProbe.java`，SHA-256 `ec1b39a37582c3abb69f444d4e3e3a8fe7ed989a638132ecdd25bf056976163d`。

## 实测结果

- `maxImages=4`：codec `configure/start` 成功，但首帧前输出端口 buffer 数请求降到 18 仍失败（`UnsupportedSetting -1010`），3 秒后 `MediaCodec.dequeueOutputBuffer` 抛 `IllegalStateException`。这轮无帧，不能用于判断格式。
- `maxImages=2`：codec 输出格式变化为 `color-format=805`，即 `0x325`。在未检查底层格式的探针中，对首帧调用 `Image.getPlanes()` 触发系统 `libmedia_jni` / ART JNI abort：`non-zero capacity for nullptr pointer: 1`。这不是有效的 YUV 读回。
- 加入底层格式门禁后，同一路径取得第 0 帧和 PTS 10.000 s（输出序号 501）的 Image。两帧 `Image.getFormat()` 都报告公开的 `35`（`YUV_420_888`），但 `Image.getHardwareBuffer().getFormat()` 均为 `805`（`0x325`）；目标 Image 时间戳 `10000000000 ns`、crop `0,0–3840,2160`。探针在 `getPlanes()` 前停下，未生成 YUV 文件。

这说明**请求 YUV_420_888 Surface 并未迫使这台设备的 Surface 输出改为 CPU 可读的通用 YUV 格式**。Java Image 格式值不能代替底层 HardwareBuffer 格式核验。与 ByteBuffer 模式得到的公开 8-bit 三平面输出不同，此 Surface 路线仍落在厂商 `0x325`。本实验没有取得 Surface 原生整数样本，不能判定 0x325 解码重构是否有错，也不能把既有 GPU 局部差异单独归因于 OES 采样或解码器。

原始 stdout：`artifacts/android-p5-hevc-decoder-probe/surface-yuv-max4.log`、`surface-yuv-max2-unguarded.log`、`surface-yuv-max2-guarded.log`；关键设备日志：同目录 `surface-yuv-logcat-filtered.txt`。未保护的 `getPlanes()` 探针导致一次 `app_process` 本地崩溃；未动系统/产品安装包。设备实验文件结束后删除，产品保持 10369 基线、诊断属性 0。

## 下一步

该公开 API 检查点不可用。下一轮应在现有 PRIVATE/`0x325` → OES 路径上分别隔离 GPU 外部纹理取样和 packed10 写入，例如同一 AImage 以独立的采样/读回方式对照，或核查厂商公开可用的 buffer lock/format conversion 接口。每一条仍需保留同帧、同 RPU、目标包和输出格式证据；在读出真正原生整数平面前，L1 硬解输出标记为未直接观察。
