# Smoke A：未通过，保留失败现场证据

- 使用源码wrapper VERIFIED包SHA256 `5347a6c9e1638a65f7ac96272f16f966866c4967e23d84b47dbaf357ecceac1d`，设备完整回读一致，见上一级build-and-install.json。
- 15:14:04.372 PID26385输出`THERMAL_JSON phase=prepared`，mode=display-resample；约1.2秒后phase=end，未出现start。
- end日志被底层截断于video-out-params/primar，完整JSON不可解析；可见字段time-pos/path/hwdec-current/video-codec皆空、hwdec-software-fallback=3，旧video-out=960x540/srgb。不能用这些字段认定实际持续播放路线。
- 采样器等待30秒无start，判invalid并停止hdr_lab。未达到60秒有效播放窗，也未做B/长窗。
- 运行中panel读数hdr_mode=1/背光255/thermald_status=0；SF有lab视频层activeBuffer3840x1920/7FA30C06，视口2672x1440，HWC合成。它不证明期望的convert+GPU链，尤其没有MKS-THERMAL或有效runtime report。
- 事后logcat两种有界/标签过滤读取均没有PID26385的flutter错误（仅ActivityManager Start/Killing），无法仅从现有日志定位open早退。thermal-logcat.txt保留实时prepared与截断end。
- finally各恢复写均成功，hdr_lab已停；原旋转0/autoRotation0、timeout30000、两个debug属性空值、屏幕ON均恢复。原自动亮度模式1已恢复，但screen_brightness标量由原162变163，strict整体字典比对因此标restoration-failed。commands.ndjson明确记录先恢复mode1、再写162且返回0；系统自动模式可后续调整标量。未为凑一致而固定回162或关闭自动亮度。该情况交Lead/critical审查恢复验收口径，B暂不执行。

此轮是测试前提/观测失败，不能形成发热或优化效果结论。
