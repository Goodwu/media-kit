# P5 同帧：ByteBuffer 8-bit 与 PRIVATE/OES→GPU 10-bit 输出（2026-09-25）

目的：区分华为 HEVC 硬解本身与 PRIVATE/AHardwareBuffer `0x325`→OES→packed10 适配链的局部 YUV 差异。**这是跨输出模式诊断，不是10-bit原生硬解 bit-exact 一致性认证。**

手机 LYA-AL00/API29、`OMX.hisi.video.decoder.hevc`，原片`/tmp/media-kit-DV-P5.mp4` SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`。由于 Android `MediaExtractor` 无法识别原 `dvh1` 视频轨，将前10.2秒 **无重编码**封为 `hvc1`：`/tmp/media-kit-p5-probe-hvc1-10s.mp4` SHA `08dfce089257b824e60bf38164093691f941edfd29bf2de29df9924f4cfea5a5`，512个视频压缩包的`size,SHA-256`与原片前512包逐项完全一致，清单SHA `72db312901585f11282190b81e6eb8f02403771538894eb2f3ff73e6b3a78b3b`。remux不带原`dvh1`的Dolby Vision configuration record；它仅用于比较HEVC基础层样本，不能验证RPU/最终DV颜色。

独立 `BufferProbe.java` 对 remux 码流调用同机硬解，Surface=null，按输出Image的row/pixel stride导出PTS10.000、显示序号500的`yuv420p8`三平面；默认和显式请求 flexible YUV 两轮均为`color-format=21`、`ImageFormat.YUV_420_888`、尺寸12,441,600字节，两个导出文件逐字节同SHA `f2402e49039c7ba871e8a31ded03c7fac0873ba861c555e17b7bc226866fabcf`。默认轮日志`artifacts/android-p5-hevc-decoder-probe/buffer-hvc1-n500.txt` SHA `498d6f7243f35f365155a7d1e659f249ae683066d1e86dd4b338220e18e0ef35`；flexible轮日志`.../buffer-hvc1-n500-flexible.txt` SHA `526d4b89bc961b2c37831f412e65910dbef54ca63f024bf087b6172cf9b11cd2`。保留一份 `/tmp/media-kit-p5-bytebuffer-n500.yuv`。

与 FFmpeg 软件和 macOS VideoToolbox均逐字节同一的第500帧10-bit YUV SHA `8a41d06c8b14a313864d04907bf3cca667d6f732fa2b2db281d105c3b833fe44` 比较，ByteBuffer 8-bit **全部12,441,600个 Y/Cb/Cr 样本精确等于软件10-bit码值右移2位**。同一原片原封装、同PTS的手机 PRIVATE/OES→GPU 双平面 packed10读回则不完全相同：

| 平面 | 样本数 | ByteBuffer8 对`软件10>>2`不同数 | `GPU10>>2`对ByteBuffer8不同数 | 8-bit最大差 |
| --- | ---: | ---: | ---: | ---: |
| Y | 8,294,400 | **0** | 19,653 | 23 |
| Cb | 2,073,600 | **0** | 4,131 | 5 |
| Cr | 2,073,600 | **0** | 5,500 | 14 |

GPU 10-bit 直接对软件10-bit仍有 Y24,348/Cb6,017/Cr6,313个不同样本，详见`android-p5-420-sidecar-20260925.md`。本轮比较器`tools/p5_output_mode_compare.py`经2×2相等和故意改单码值自检；完整JSON `artifacts/android-p5-output-mode-n500-compare.json`。它按三个平面全帧逐样本比较，没有裁切、配准或曝光拟合。

这证明局部差异**不是这台硬解器在所有输出模式下都不可避免**：CPU可读8-bit输出在其可表达的精度内与两个独立参考一致，而PRIVATE/OES→GPU链在8-bit量化后仍留有局部差异。证据把问题定位到**输出模式相关的解码/后处理，或PRIVATE/OES外部取样及我们的GPU打包**；还不能在这两者之间进一步定责。8-bit结果会遮蔽低2位差异，因此“ByteBuffer8全对”不能证明该路径存在可读的10-bit正确输出。也不能忽略原`dvh1`与诊断`hvc1`配置差别；压缩包虽相同，decoder可能因封装元数据采用不同模式。下一步优先在同机取得**同一输出模式前后**的第二检查点，或验证hvc1与dvh1配置造成的差异，然后再决定是否调整packed10取样。实验后手机恢复10369基线、相关属性0/无应用进程，设备公开下载区副本与探针jar均清理。
