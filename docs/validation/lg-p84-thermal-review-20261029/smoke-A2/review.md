# Smoke A2：前置准入失败，定位完成

- ab2 APK SHA256 `fb6af4c69dea62c6fb2e83cb86fff4e33d70fc986e3a19e8bde7612a38821e48`已安装且完整回读一致，见`../build-ab2/install.json`。
- 本轮PID27231、runId `27231:1793258705980299`、serial1；15:25:06.866捕获完整THERMAL_ERROR：

`HdrOutputPreparationFailure(yuvWindowArmUnavailable, vendor YUV arm capability gate refused (ext=lg-pq, applicable=true, yuvWindowArmApi=0, required=1))`

- 原异常与完整堆栈已通过当轮runId匹配持久文件取回，保存在`thermal-open-error.json`；不是读旧文件。原文件在本轮前不存在。
- 失败发生在`HdrYuvWindowArm.assertRouteAdmission:357`→`AndroidHdrBackend.validate:282`→`HdrSessionReviewBackend.validate:183`→`HdrOpenCoordinator.openSource:511`，尚未形成source/actual/verified事实。
- 新分段日志4片完整重组成功，保存在`assembled-last-thermal-row.json`。phase=end、elapsedMs0；vo=mediacodec_embed、target auto、fallback3和旧video-out参数来自失败回滚后的状态，不能误记为convert已经运行。
- 工具收到错误后判invalid并停止hdr_lab，completeWindow=false，有效播放窗0秒。未运行B或长窗。
- finally恢复检查通过，restoreErrors为空；旋转/亮度模式标量/timeout/debug属性/原屏幕ON全部还原。完整本PID实时日志见`flutter-logcat.txt`。
- 本轮无温控或节能效果结论。下一步交Lead定位vendor YUV arm API为何报告0，再构建复测。
