# P5 默认优化候选对 HDR10 / P8.4 的 Texture→SDR 回退（12571–12572）

两轮均使用与 P5 全片12569/12570相同的自建arm64 JAR（SHA-256 `cc6d651935031091c57f9f40098b1164c4e84941e02e4919ead7709457262491`），预建横屏全屏Texture、`gpu-next`、`mediacodec`、SDR目标、自动亮度，调试属性0。样片本身是HDR输入；此处仅验候选未把非P5误送进P5专用外部YUV/退休路径，以及普通回退能出画，不代表原生HDR输出验收。

- 12571 HDR10：APK SHA-256 `c3cc744a4ff160f698eb4708a6ef79d2dd6e0a1cf4b94e47c4ff3d411debf575`。首次启动的点击太早，只有`awaiting_tap`没有`AUTO_SOURCE`，黑屏短轮作废。重新启动、页面就绪后点击，固定本地HDR10全片源实际打开，Texture `setSurfaceSize 2560 1280`，截图为正常 HDR ON 片头画面；t8媒体3.036秒VO0、decoder0。退出 `P5_IMAGE_FINAL acquired=543 deleted=543 retired=0 retire=0`，Player dispose完成。首帧普通 OES 重绘累计空取10次，但没有AImage/render错误。
- 12572 P8.4：APK SHA-256 `03ac03dc4641e17b9fa45159fef0dad5b083c7f6b81ca8497aab33ad015ade41`。固定本地P8.4全片源实际打开，Texture `setSurfaceSize 2560 1280`，截图为正常摄影画面；t8媒体3.537秒VO0、decoder0。实际输出参数报告 `pixelformat=mediacodec`、BT.2020/HLG；这是SDR回退测试，不主张逐帧RPU或原生HDR链路在此成立。退出 `P5_IMAGE_FINAL acquired=761 deleted=761 retired=0 retire=0`，Player dispose完成。首帧普通 OES 重绘累计空取10次，没有AImage/render错误。

证据在 `artifacts/android-p5-product-nonp5-fallback-12571-12572/`。两轮后均恢复原APK versionCode12492、自动亮度和熄屏。尚未覆盖 seek/flush、同进程重入、长时间非P5播放或其它设备；非P5短轮只证明当前手机上的基本回退与资源闭环。
