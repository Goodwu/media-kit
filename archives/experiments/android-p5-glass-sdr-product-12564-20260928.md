# Glass P5→Texture SDR 产品候选全片（12564）

与12563相同的清洁FFmpeg+隔离mpv/libplacebo自建arm64 JAR，APK SHA-256 `3df362b33abf2d6699681aee6626d9c369784de683669504bf446d3e2ebdfd01`；本地原Glass P5 4K59.94，预建横屏全屏Texture，`setSurfaceSize 2560 1440`，四个P5调试属性0、自动亮度、默认电池模式。未重复读取设备视频全片哈希。

从片头播放至 `AUTO_COMPLETED completed=true`，t28/60/90/120/150/180约对应媒体25.5/57.5/87.5/117.5/147.5/177.48秒；VO累计11/11/11/11/18/20、decoder全为0。t180仍在播放，约0.24秒后显式完成；因完成前未再取VO，最终EOS精确计数未知，但末段可确认至少20。GPU 1Hz 180样本中位415MHz，173个415MHz、7个332MHz，各30秒窗口中位均415MHz。旧同片优化轮EOS VO516、t90→t180新增342；此轮相应新增9，远低于用户接受的“与旧优化结果相近”口径，但热态/日志及依赖并非严格同包对照，不能归结为单一改动。

EOS截图为正常DV logo，无可见紫色片尾；单张截图不能证明所有尾帧正确。片头同一PTS=0.05005重复映射时仍有两次无新AImage `-30001` / render失败，之后未见同类报错。尚缺真人动态画质、Glass精确EOS VO、完整资源/回退验收；此轮不能关闭P0/P3。

证据在 `artifacts/android-p5-glass-sdr-product-12564/`：全量日志gzip、GPU NDJSON、EOS截图。轮后恢复原12492 APK、四属性0、自动亮度和熄屏。
