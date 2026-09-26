# HDR10 独立 ImageReader 的普通 OES 精度对照（2026-09-25）

## 结果

在现有 `P5CodecProbe` 的**同一张** HDR10 MediaCodec/PRIVATE AImage 上，依次读回普通 OES 默认 `mediump float`、显式 `highp float + highp samplerExternalOES`、`GL_EXT_YUV_target` raw YUV。诊断探针把原先仅 raw YUV 使用的浮点 FBO 与禁用 dither/blend 扩展到普通 OES，并把每张图像的日志分段，避免 Android/Flutter 单行截断。11084 有效三张图像的时间戳为 0、3.403、6.773 秒，实际格式 805、BT.2020/PQ，AImage timestamp 与 codec 输出 PTS 对应；三种读回的 FBO 均完整，GL error 均为 0。完整日志压缩文件 `artifacts/android-hdr10-oes-precision-20260925/11084-logcat.txt.gz` SHA-256 `1ee68940e3aeddcc1fe62d69d13c32ebbb836bba94f1638fe4364025a9a1c9ab`；APK SHA-256 `7c85964487a8ba7a38e55ad0cfe0bcddffb1aaa107c4bd2716c3b83fce1ef7f3`。

默认与 highp 普通 OES 在 x=0.1/0.3/0.5/0.7 宽处的 RGB10 差异多为 0–1 级；x=0.9 处同图差别较大：三帧 highp 减默认分别为 `(19,14,4)`、`(2,4,-6)`、`(-11,-14,8)` /1023。float FBO 同方向有差别，例如首帧 x=0.9 默认 `(0.210327,0.192139,0.140259)`，highp `(0.229980,0.206543,0.145142)`。这表明取样 shader 的精度条件会影响结果，尤其近右侧采样点；由于当前 A/B **同时**改变 float 与 external sampler 精度，不能断定差异来自位深、UV 坐标量化还是 YUV→RGB，亦不能把任一组直接叫作产品路径。已知 libplacebo 为 float 默认设 highp（设备支持时），但 external sampler 声明没有显式 highp。

raw YUV 同 AImage 也读回 10-bit/FBO 与浮点值。本轮未重新将这些 PTS 对应的软件帧抽出，raw 结果只用于证明取样同图与仪器工作，**不扩展**先前其他三帧的软件同帧 45/45 对照。自然画面的普通 OES RGB10 与 RGB8 扩展不同，仍不足以证明产品 mpv 链 10-bit 保真；色度转换、插值和坐标精度均可造成非 8-bit 格点。

## 失效轮与后续

11082 直接使用 `/sdcard/Download/HDR10.mp4`，应用无读取权限，MediaExtractor 创建失败；不计数值测试。将源复制到应用专属外部文件目录后，11083 成功取样，但旧 Dart 单行日志截断 highp/raw 段；不据截断文本比较。11084 加分段日志后是完整有效轮。诊断 C++ `-fsyntax-only` 通过。测试后删除应用专属外部源副本及诊断截图，恢复设备基线 APK `versionCode=10369`；未做播放性能验收。

下一步应先将 `highp float` 与 external sampler 精度拆成独立变量，再在**产品 mpv 当前 mapper/渲染器**同一 AImage 上记录 timestamp/crop 并作浮点读回，最好用编码后仍保留连续 10-bit 灰阶的固定图样检验是否先降为 8-bit。固定目标 SDR golden/显示验收仍是另一门禁。

## 11085 单变量精度拆分

探针新增第三种普通 OES shader，依次比较：(A) `mediump float` + 默认 sampler，(B) `highp float` + 默认 sampler，(C) `highp float` + 显式 highp sampler。三种在**同一 AImage**依次读回 8-bit、RGB10_A2 与 RGBA16F；禁用 dither/blend，其余条件相同。三张图像 timestamp 0、3.470、6.873 秒，各组 FBO complete、GL error 0，raw YUV 仍可读。APK SHA-256 `bfeed41c292e7d863d3c5acefd221036aa1dbd2ba8e32c676e73b34e77dc9db4`；压缩日志 `artifacts/android-hdr10-oes-precision-20260925/11085-logcat.txt.gz` SHA-256 `a5f0ba3c50e76e6c0f935fe897a15a46c4c2795e0c0961e04a3beecb0687b51f`。

右侧 x=0.9 的 RGB10 读数：

| AImage PTS | A mediump | B highp float | C highp sampler |
| --- | --- | --- | --- |
| 0 | 216,197,144 | 235,211,149 | 235,211,148 |
| 3.470 s | 149,119,63 | 147,119,65 | 147,119,65 |
| 6.873 s | 394,363,344 | 382,346,340 | 382,346,340 |

前轮最大的右侧差异在 **A→B** 即 float/UV 精度变化时出现，B→C 为 0–1 码值；其它四个横向位置三组多在 0–1 级。这使“external sampler 精度本身造成十余级差异”的解释不成立；4K 纹理的归一化坐标在 mediump 下落入邻像素是更符合现象的推断，仍未以逐像素坐标追踪直接证明。固定 libplacebo `src/dispatch.c` 在支持 `GL_FRAGMENT_PRECISION_HIGH` 时使用 highp float、但未显式声明 external sampler highp；B 比 A 更接近产品 shader 的精度条件，**依然不是产品 mpv mapper 的实际读回**。这三组自然画面样本不能证明产品保留 10-bit，下一步直接在其当前映射链抓同一 AImage，并另用编码后核对过的灰阶码值测试。

11085 完成后删除应用专属外部源副本，手机恢复基线 10369。前述“下一步先拆变量”已由本轮完成，余项仍开放。

## 11088 与产品 mpv PTS 0 的同坐标对照

独立探针增加 `highp float + 默认 sampler + GL_LINEAR` 一组，保持同 AImage 的其它三组不变；目标是匹配固定 mpv `hwdec_aimagereader.c` 的外部纹理线性过滤及 libplacebo 的默认 highp float 条件。11088 完整 HDR10 源的首张 Image timestamp=0、codec 输出 PTS=0，五点 `RGBA16F` FBO/读回 GL error 0。APK SHA-256 `931170590a10ad7047c0ecdd3dfbddd067272ab3be417d3adcfa76c6d2a009`，压缩日志 `artifacts/android-hdr10-oes-precision-20260925/11088-logcat.txt.gz` SHA-256 `7936168d8ca4bb79ba4127faf86e92804a7a2fe689734b8f224bd8a4bded9c06`。

把 11088 线性组日志中的十进制浮点值编码回 half bits，与产品 11087 的**有效 PTS 0、AImage timestamp 0** 五点 RGB 共15分量逐个比较：**9 个 bit-exact、5 个差 1 ULP、1 个差 2 ULP**。0秒中心 `(1920,960)` 独立探针为约 `(0.204834,0.169067,0.122620)`，产品为约 `(0.204956,0.169189,0.122742)`；前两点 RGB 三分量都 bit-exact。此前独立 NEAREST 与产品 LINEAR 的多级差异主要来自过滤条件不一致，不能再作为产品位深损失线索。

这项对照验证**两种仪器在同 PTS/坐标/高精度线性 OES 取样条件下高度一致**。它仍不证明 Dolby/HDR 最终 RGB 真值或 10-bit 信息全保留：同一厂商 OES YUV→RGB 转换被两边共同使用，且 PTS0 的两次解码并非同一物理 AImage。测试后已删除临时源副本、恢复 APK 10369。
