# Glass P5→Texture SDR 修复版全片（12570）

与 Mystery Box 12569 同一自建 arm64 JAR（SHA-256 `cc6d651935031091c57f9f40098b1164c4e84941e02e4919ead7709457262491`）；12570 APK SHA-256 `ccc6ddc05ab22aa5a3e766362cd89ed8abb0036dd48202c33ce195310851e9ea`。本地 Glass P5 4K59.94，从片头预建横屏全屏 Texture、实际 `setSurfaceSize 2560 1440`、`vo=gpu-next`、`hwdec-current=mediacodec`、默认电池模式、自动亮度，P5 调试属性均为 0。

媒体时间 5.556/25.559/57.558/87.554/117.551/147.547/177.482 秒时，VO 累计为 2/2/2/8/16/32/41，解码掉帧始终 0。t180 后 `AUTO_COMPLETED completed=true`，片尾截图为正常 Dolby Vision logo、没有紫屏。GPU 1Hz 共 190 样本，中位 415MHz（415:178、332:9、277:1、139:2）。全片未见 `acquireLatestImage failed` 或 `Failed rendering frame`。正常 `vo=null` 后 `P5_RETIRE_FINAL maps=10434 reaped=10433 held_after=0`、`P5_IMAGE_FINAL acquired=10433 deleted=10433 retired=0 empty_acquires=0`，Player dispose 完成。

本轮 t180 VO41，旧同片优化轮 EOS VO516，满足用户指定的“相近即可”的门槛；与上一产品候选12564的 t180 VO20 属不同运行轮次，不能把差值归因于单行普通 OES 修复。EOS 精确 VO 仍未在 completed 回调瞬间采集，已知 t180 与 EOS 间约0.15秒。证据在 `artifacts/android-p5-product-12570-glass/`。轮后恢复原 APK versionCode12492、P5 调试属性0、自动亮度并熄屏。片尾截图、EOS与资源计数是单轮证据；旧紫屏偶发问题仍需针对性重入/seek/重复尾段复现，不宣称根因已解决。
