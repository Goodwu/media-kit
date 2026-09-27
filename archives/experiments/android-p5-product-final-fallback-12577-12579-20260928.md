# P5 默认优化最终 JAR 的非 P5 Texture→SDR 回退（12577–12579）

2026-09-28 使用已推送 Goodwu/mpv `8e7c23e` 的自建 arm64 JAR（SHA-256 `eac6514fd1b3409574f0b77014c9b29989e0d0868d40048cc199a822d94c660f`），在 Huawei LYA-AL00、自动亮度、预建横屏全屏 Texture、`gpu-next`/`mediacodec`、SDR 目标和 2560 限宽下各播放约30秒。三轮均确认固定本地源实际打开；P5 专用退休路径日志 `enabled=0`；截图有正常视频画面，t8 VO/解码掉帧均0，日志未见 `acquireLatestImage failed` 或 `Failed rendering frame`。

| APK版本 | 输入及截图 | 退出资源 |
| --- | --- | --- |
| 12577 | 普通 SDR 854×480 BT.709，企鹅画面 `/private/tmp/media-kit-p5-12577-sdr.png` | `P5_IMAGE_FINAL acquired=642 deleted=642 retired=0 retire=0` |
| 12578 | HDR10 3840×1920 BT.2020/PQ，HDR ON 片头 `/private/tmp/media-kit-p5-12578-hdr10.png` | `acquired=742 deleted=742 retired=0 retire=0` |
| 12579 | DV P8.4 3840×1920，当前输出参数为 BT.2020/HLG，摄影画面 `/private/tmp/media-kit-p5-12579-p84.png` | `acquired=764 deleted=764 retired=0 retire=0` |

诊断日志分别在 `/private/tmp/media-kit-p5-12577-sdr-filtered.log`、`/private/tmp/media-kit-p5-12578-hdr10-filtered.log`、`/private/tmp/media-kit-p5-12579-p84-filtered.log`，均为临时文件。每轮后确认手机恢复原 APK versionCode12492、自动亮度及熄屏。本轮只验证非 P5 输入不会误入 P5 专用直接 YUV 处理且基本播放/退出正常；HDR10/P8.4 均为 Texture→SDR 输出，不证明原生 HDR 显示，也不覆盖长时播放或 seek。
