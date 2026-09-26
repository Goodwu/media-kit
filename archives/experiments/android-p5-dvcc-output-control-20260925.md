# P5 DV 配置对 ByteBuffer 输出的控制实验（2026-09-25）

目标：消除先前同帧 ByteBuffer 对照中的封装差别，分别用**同一个携带 DV 配置的文件**走华为硬解 ByteBuffer 8-bit 与 PRIVATE/OES→GPU packed10 路径。

输入仍为原 P5 前 512 个 HEVC 压缩包，无重编码。先用 GPAC MP4Box 的 `dvp=5` 给既有 10.2 秒 `hvc1` 样本增加 Profile 5 `dvcC`，MP4Box 自动将 sample entry 改为 `dvh1`；为让 Android 10 `MediaExtractor` 枚举视频轨，仅把临时文件 `stsd` 中唯一的 `dvh1` 四字节标识改回 `hvc1`，保留 `dvcC`。所得诊断文件 `/tmp/media-kit-p5-probe-hvc1-with-dvcc-10s.mp4` SHA-256 `55a6151fcf2f8de3bffad2259199fac212d065d2a5befaee97dcf25f49d66e47`。FFprobe 和 MP4Box 均能读出 `hvc1`、DV Profile 5/RPU/BL flags；512 个视频包的 size/SHA 与无 DV 配置的重封装文件逐项相同，第 500 包 PTS 10.000、SHA-256 `0030ffab4d9d435adaa0fa834fa3a366c9ec75a18c5dc23e593a6306b6c47363`。这是刻意构造的诊断组合，不宣称其封装符合正式 DV 交付规范。

同机 LYA-AL00/API29 上，独立 `BufferProbe.java` 的 `MediaExtractor` 接受该文件，目标 `OMX.hisi.video.decoder.hevc` 实际输出 `color-format=21`、`YUV_420_888` 三平面。显示序号 500/PTS 10.000 的完整 12,441,600 字节输出 `/tmp/media-kit-p5-bytebuffer-dvcc-n500.yuv` SHA-256 `f2402e49039c7ba871e8a31ded03c7fac0873ba861c555e17b7bc226866fabcf`，与此前**无 DV 配置**的同包 ByteBuffer 输出逐字节一致；也即与软件/VideoToolbox 10-bit 参考右移 2 位后全样本一致。运行日志 `artifacts/android-p5-hevc-decoder-probe/buffer-hvc1-dvcc-n500.txt` SHA-256 `1e564c21eda3c9fd74584093961aae8f6f42a59a78f39a362bf4c36037b88c4f`。

测试页原8386包的源文件 SHA 白名单最初拒绝新文件 (`OPEN_SELECTED_SOURCE error=Bad state: Unknown sample SHA-256: 55a615...`)。为避免重编及改动渲染逻辑，仅在**隔离APK副本**的 `libapp.so` 中把唯一一次原P5哈希字符串等长替换为新文件哈希，保持其余字节原样，zipalign/重新签名/验签。包 `/tmp/media-kit-p5-dvcc-whitelist-8387.apk` SHA-256 `ca5de73168471d5bdcc7110ffc9414feb6bf764cbee3df444215b3d90206abbc`。这只改变诊断文件识别，不应把它作为产品修改。

手机 GPU 轮成功打开同一个 `hvc1+dvcC` 文件，PTS10.000 的日志显示 `src_dovi=1`、两平面 `chroma_location=1`、AHardwareBuffer `format=0x325`、GL 导入错误0、Y/UV完整读回写入；日志 `artifacts/android-p5-hevc-decoder-probe/gpu-hvc1-dvcc-n500-filtered.txt` SHA-256 `cbecd792d2e1848a5d338b049fc2fd10b515d2aafdb9e0e374c3137d0c65165c`。Y读回 SHA `b04220ef51629371d77e5d5eccd9ca773ae063e462d1c3499fcb5a37f048e81f`，UV读回 SHA `21fe4dc1afe8bcfcfaf9b1193e4e8d98278d4e7dca7b6d1e81b95da3d8918bd1`，**分别与原 `dvh1` 文件8386同PTS读回逐字节相同**。同文件三路完整比较结果 `artifacts/android-p5-output-mode-n500-dvcc-compare.json` SHA `91d1543c2bfcadbb62bbd9e52938d6af7304a703fcb217feb26dd9d835b40a22`：ByteBuffer8对软件10>>2三个平面均0差；GPU10>>2对ByteBuffer8分别Y19,653、Cb4,131、Cr5,500点不同，最大8-bit码值差23/5/14。这复现了原实验，且本次**两种硬解输出模式使用完全同一个输入文件**；封装文件差别不是当前局部GPU差异的解释。

限制：Android `MediaExtractor` 给ByteBuffer探针的 `MediaFormat` 没有显式显示 DV 配置，不能证明 `dvcC` 已传给 `MediaCodec` 或两种输出模式内部处理完全一致。8-bit 会遮蔽低2位。GPU读回位于PRIVATE/OES取样和packed10写入之后，不能区分 Surface 模式内部解码/后处理与外部取样/打包。GPU日志未单独保留本轮RPU payload hash；同文件PTS、`src_dovi=1`及同原dvh1逐字节相同的GPU Y/UV可支撑基层对照，不能据此声明Dolby颜色已通过。下一步需要在PRIVATE缓冲与OES取样之间增加可观察检查点，或更换外部采样方式做同buffer A/B。

实验后原始 243 MB P5 文件已按 SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e` 恢复到应用源路径；手机恢复基线 APK versionCode 10369，相关诊断属性全 0、应用无进程，设备临时探针文件删除。新Y/UV读回与原8386文件相同，保留原文件即可复算；本轮重复副本可删除。

随后按用户要求清理了本轮`hvc1+dvcC`临时MP4及8387诊断APK；其输入/输出SHA、同帧比较JSON和构造方法保留，本记录中的`/tmp`路径是历史产物身份。见`android-tmp-cleanup-20260925.md`。
