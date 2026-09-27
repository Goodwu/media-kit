# P5 映射器原始读回实验分支清理与回归（12574–12576）

2026-09-28 在隔离 Goodwu/mpv 产品分支 `33a212e` 之后，仅修改 `video/out/hwdec/hwdec_aimagereader.c`、`video/img_format.c`、`video/img_format.h`：删除 property-gated 原始 YUV FBO/MRT/PACK10/half、sidecar、像素读回与 raw perf 探针；保留默认 P5 外部 YUV/10-bit DOVI、同帧复用、fence 退休、EGL 导入、普通 OES 回退和必要的时间线/RPU 诊断。`git diff --check`、arm64 `ninja -C _build-arm64 libmpv.so` 通过；独立只读审查未发现相对 `33a212e` 的默认路径阻断回归。已提交 `8e7c23e` 并推送 Goodwu/mpv `feature/android-p5-sdr-direct-yuv`。`P5_DIRECT_RETIRE enabled=1` 日志在能力回退检查前输出，验收仍须结合实际帧和资源计数。

自建 `libmpv.so` SHA-256 `4fdb63241e547dcbacca209dcc18dfb81afab22adefe6c720011adc0288ff08d`；arm64 JAR SHA-256 `eac6514fd1b3409574f0b77014c9b29989e0d0868d40048cc199a822d94c660f`。手机 Huawei LYA-AL00，默认电池模式、自动亮度，预建横屏全屏 Texture→SDR，输出 2560×1440，`gpu-next`/`mediacodec`。每轮结束恢复原 12492 APK、诊断属性0、自动亮度并熄屏。

| 版本 / 源 | 结果 | 资源与限制 |
| --- | --- | --- |
| 12574 Mystery Box 短轮 | 截图为真实沙滩画面；t8 解码掉帧0，未见 AImage/渲染错误 | 退出 acquired/deleted 1483/1483、retired0、Player 销毁 |
| 12575 Mystery Box 全片 | `AUTO_COMPLETED completed=true`；t90 VO34、解码0；GPU 104 样本中位415 MHz | 退出 5886/5886、retired0，无 AImage/渲染错误。停止前无 EOS 点 VO 快照，不能把 t90 的34称为最终 EOS 值；前一版12569 EOS VO2，同片未优化基准 VO54 |
| 12576 Glass 全片 | t180 媒体175.382秒 VO22、解码0，片尾截图为正常 Dolby Vision 标志，之后 `AUTO_COMPLETED completed=true` | 片尾 PTS174.958 仍有一次 `acquireLatestImage failed -30001` 和 `Failed rendering frame!`，纳入 P3；退出 10454/10454、retired0。主机临时分区满使 GPU 仅留下前37样本，不作为全片中位数。旧同片优化轮 EOS VO516，12570 EOS VO41；此轮未取得 EOS 点 VO 快照 |

12576 首次日志文件导出和自动恢复因主机临时分区空间不足失败；清理明确属于本轮旧生成产物后，补取设备环形日志中的核心事件，并手动确认原 12492 APK、自动亮度和熄屏。片尾截图 `/private/tmp/media-kit-p5-12576-tail.png` SHA-256 `865c4e73b606bb2065a9a1c312ea9bae9f32edf78153e6c788133ca9d1c3c7d0`；补取日志 `/private/tmp/media-kit-p5-12576-filtered.log`。这些临时路径不是长期归档。

结论：清理版基本出画、全片播放完成及退出资源闭合；Glass 尾段无图像偶发故障仍在，不能宣布 P3 修复。P0 还须最终版非 P5 回退、seek/重入及真人动态观感；若要求精确最终 VO/GPU，全片需在留足磁盘空间后再测。
