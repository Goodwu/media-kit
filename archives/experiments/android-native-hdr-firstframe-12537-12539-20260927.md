# Android 原生 HDR 首帧与 P5→PQ 输出短轮（2026-09-27）

## 方法与口径

- 设备 LYA-AL00/API29，物理屏幕 3120×1440；自动亮度，短时打开后熄屏。固定 `/data/local/tmp/media-kit-p84-full.mp4`、`.../media-kit-hdr10-full.mp4`、`.../media-kit-p5-full.mp4`，使用按文件名识别的受控本地入口，不做每次整片哈希与复制。仅支持 arm64，JAR 为本地自建 `f745146332b532d8baeb162b7a33ddefa03ae8dc0a7731f13a9584ef7e6fa3f9`。
- APK 12537 为 P8.4，12538 为 HDR10，12539 为 P5；均为普通列表 `Video 0` 触摸后先进入横屏全屏、再打开源的 HDR transaction，PlatformView 原生输出，`gpuPlatformHdr=false`。原生探针直接 PixelCopy `android.view.SurfaceView` 的视频 Surface，采样中心 400×250 区域，非页面 Flutter Surface。从 Activity `ACTION_DOWN` 到首次明显内容读回计时。首个成功样本已含内容，所以该值是首帧到达该 Surface 的**读回上界**，不是首个 buffer 的精确提交时间，也不是屏幕面板光学时延。
- 构建过程曾有 12536 首次 copy 失败即停止探针；12537 改为失败后重试。12538 首次脚本遇锁屏、另一次误入多视频页，两次作废；下列数字仅来自进入正确单视频页且日志源身份匹配的独立进程。

## 结果

| 路径 | 三次独立进程 ACTION_DOWN→视频 Surface 内容 | 系统/画面证据 |
| --- | --- | --- |
| P8.4 → 原生 HLG | 670.384、676.313、623.041 ms | 一轮真横屏全屏截图有实际 P8.4 画面；SF 视频层 `BT2020_ITU_HLG`、HDR metadata types=0。 |
| HDR10 → 原生 PQ | 652.716、648.122、630.297 ms | 一轮真横屏全屏截图有实际 HDR10 画面；SF 视频层 `BT2020_ITU_PQ`、HDR metadata types=3。 |
| P5 → PQ HDR | **无首帧** | 12539 正确启用 `p5_rpu_probe=2`、`p5_raw_yuv=1`、私有 dataspace 探针0；公开 PQ Surface 设置遭系统拒绝，`wid=0`，`initialDataSpaceRejected`。`requested`→`open_failed` 为 422.334 ms，其中 `validated` 331.294 ms、`configuration_reset` 332.994 ms；失败 ACK 约在触摸按下后 614 ms。此路径不满足 P5 HDR 出图门槛。 |

PixelCopy 视频 Surface 内容只能证明 buffer 已到视频 Surface；Surface 可被遮挡、未被合成或尚未扫描到面板。因此可作为自动化首帧时延门槛，需同时核验正确视频层、SF/HWC dataspace、真全屏合成截图，并保留一次真实观看验收。截图/SF 是首帧读回数秒后的状态，不能把它们的时间戳倒推成面板首帧时间。P5 的权限失败也不能用 HDR10/P8.4 的成绩代替。

此轮没有同步回读 mpv 的实际 `vo` 属性，也没有采集两张间隔截图或面板光学时间；原生后端依据配置策略及此前同路径证据，实际后端与连续画面列入后续复核。以上首帧数字仅评价固定设备、素材和受控入口。

证据位于 `artifacts/android-native-hdr-firstframe-12537-12539/`：七份 logcat 压缩包、两份 SF 压缩包、P8.4/HDR10/P5 截图。12539 APK SHA-256 `76546af5cb72315ac4821432506830130a0bc9b220c4ac714abc74b83532a825`；先前安装的 12492 原包 SHA-256 `39493d184b48e055a2c61babe97047c2865b02f9986aaf7399872c3435ace706`。实验结束已恢复 12492，P5 三项属性为0、自动亮度1、屏幕 Asleep。
