# HDR10 产品 mpv OES 输入直接读回（2026-09-25）

## 范围与方法

在固定 mpv `32a164c` + 发布兼容补丁 + ImageReader maxImages=3 的隔离构建里，加默认关闭的 `debug.media_kit.oes_sample_probe=1`。`hwdec_aimagereader.c::mapper_map` 成功取得 AImage 后记录其纳秒时间戳与 AHB 实际格式；`vo_gpu_next.c::hwdec_acquire` 在产品 mapper 绑定 OES、`pl_opengl_wrap` 创建产品 `pl_tex` 后，使用**同一 libplacebo GPU**的 `pl_shader_sample_direct`，在五个像素中心分别渲染到 1×1 `rgba16hf` 纹理并同步下载。取样发生于正常色彩处理之前；同步下载有明显扰动，不用于性能/首帧计时验收。

11087 完整 HDR10、Texture SDR、默认直 MediaCodec、3840×1920 BT.2020/PQ 输入。JAR SHA-256 `7a2d1e4b9159d0311b7af79a17eae20c07c38adc01167b0f5bf06e897c4e1edb`，APK SHA-256 `623c6e29dd1b02b61085a5d961b5af0bb934bd023fc3073d16792d9d5022c182`；诊断库补丁 `android-hdr10-product-oes-probe-20260925.patch` SHA-256 `bb54b5d695237c785c2e7e5190346a944e5341aaafc038105e072931bac374ee`（含基础 Reader 5→3 diff）。完整日志 `artifacts/android-hdr10-product-oes-20260925/11087-logcat.txt.gz` SHA-256 `2f655b8f5c018e9e556808fc9039e23c513b2e2ffde1b31f1a9be3f37852044a`。

## 有效与无效帧

| mpv 帧 PTS | AImage timestamp | 取样结果 |
| ---: | ---: | --- |
| 0 s | 0 ns | 五点 `rgba16hf` 读回全部 `ok=111` |
| 0.033 s | 33,000,000 ns | 五点 `rgba16hf` 读回全部 `ok=111` |
| 0.066 s | **未取得新 Image**；`acquireLatestImage=-30001` | 虽有五点 `ok=111`，**无同帧资格**，不能拿其数值对照 0.066 s 软件帧 |

前两帧 AHB format=805、尺寸3840×1920，帧 PTS 与独立 AImage timestamp 严格相同。例如 0 秒中心 `(1920,960)` 的 RGBA half bits 为 `(0x328f,0x316a,0x2fdb,0x3c00)`，相应 float 约 `(0.2050,0.1692,0.1227,1)`。证明产品实际 OES→libplacebo 直接采样能提供高精度 FBO 数值；**不证明输入全 10-bit 信息得以保留**：普通 OES 的 YUV→RGB 可能对 8-bit 数据产生非 8-bit 格点，且尚未与同图 raw YUV/软件解码建立确定的 RGB 真值。

0.066 秒样本揭示一个重要验收边界：当前 mapper 遇 `NO_BUFFER_AVAILABLE` 时按原有逻辑返回成功以避免闪帧，此时 renderer 仍可能读到旧 OES 内容。诊断只按 `mpi->pts` 计数不足以认定同帧，必须同时看到新 AImage 时间戳。该单次启动回调竞态不能据此宣称稳定播放故障，也不能用其数值判断颜色。

## 状态与后续

11086 首轮已确认相同 API 路径能编译并读回，但起始 PTS 不固定且探针按重复 PTS 计数；11087 改跳过重复 PTS，仍需以上述 AImage 时间戳过滤无效图像。后续应在相同固定 PTS 上将产品 highp OES 输入与独立 raw YUV10/编码后核过的灰阶码值对照；普通自然画面及不同 GL filter/坐标规则的探针结果不可直接作 bit-exact 判断。再分别验证最终 Texture SDR 的目标色彩与稳定性。

诊断源码已从隔离 mpv 撤回，重建 libmpv SHA-256 恢复 `56e48164a70159849821ca16f45aad09c4e09386b1b8fe6f1ba4abf96fdd0d05`。设备探针属性归零、源副本删除、APK 恢复 `versionCode=10369`；项目中的探针包未作为产品依赖提交。

后续 11088 独立探针补齐 highp float/默认 sampler/**线性过滤**，与本轮产品有效 PTS0 五点 RGB16F 15分量对照为 9项完全相同、5项差1 half-float ULP、1项差2 ULP。见 `android-hdr10-oes-precision-20260925.md`。这提升了产品读回工具可信度，仍不是独立颜色真值。
