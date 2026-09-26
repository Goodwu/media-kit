# P3 GPU PlatformView HLG Surface 门禁（2026-09-24）

目标机 LYA-AL00/API29，前台解锁。原生 P8.4 设备源 `/data/local/tmp/media-kit-p84-full.mp4` SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`。已安装 6238 固定 P8.4、gpu-next/PlatformView HLG 候选 APK `/tmp/media-kit-p84-gpu-platform-hlg-6238-arm64.apk` SHA `48d302de5457bab8eadb736c0291e7763842b4f8286e660da6ffb5a2fdbc31c6`，设备 versionCode 回读 6238。同轮 P5 属性 `p5_rpu_probe=0/raw_yuv=0`；该候选不依赖它们。测试后应用强停，包仍安装。

测试页报告 `displayHdrTypes={2,3}`、`simulateNoHlgForP84=false`。当前候选 Surface 请求 `RGBA_1010102` (`format=43`)、1440×810，在 `surfaceCreated` 中调用 `ANativeWindow_setBuffersDataSpace` 设置 HLG `168165376` (`0x0a060000`) 返回 `-22`，实际 dataspace=0；同 JNI 诊断的 sRGB 探针与 UNKNOWN 复位成功（均返回0）。日志标记 `transfer=hlg, applied=false`，10秒后样本自动打开超时，无有效 `ANDROID_HDR_OPEN` 或该候选的 HLG 视频层。因入口严格拒绝未设置 dataspace 的 Surface，此轮没有运行到 P8.4 基层滤镜、GPU 色彩转换、首帧或性能验收；不据此推断这些后续环节好坏。

这与同机 [6237/6310 PQ Surface 失败](android-hdr-p2-6233-6237-device-20260924.md)构成 PQ/HLG 两个 HDR dataspace 的受控阴性证据，但不能推广到所有安卓设备，也不能确定是 `format=43`、设置时机、Surface usage 或厂商实现中的哪一项。系统播放器与原生直出均可在 HWC 层提交 HDR，说明设备 HWC 能力阳性，不证明应用自建 EGL/ANativeWindow HDR 输入可用。

原始日志 `/tmp/media-kit-p3-p84-6238-logcat.txt` SHA `19164c332a39f522eb52951cb548cf3076e1196260b5e21f2149bdb5c177631c`；SF `/tmp/media-kit-p3-p84-6238-sf.txt` SHA `fd29c1929ca1188250fe4f5369bb02334d6e6144f1da0b7eb9203127d5430c8b`；截图 `/tmp/media-kit-p3-p84-6238-screen.png` SHA `890f0adcd21e76e321974af296b38812f7a9b7bbe2f55edf2fe48b3c94c18a41`。下一步用最小 Surface 实验隔离 format、buffer 已连接前后与 dataspace 设置顺序；必要时寻找受支持的 HDR 生产路径。不能以放开门禁让 UNKNOWN dataspace 呈现来宣称 P3 通过。
