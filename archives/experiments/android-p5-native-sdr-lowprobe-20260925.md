# 官方 4K P5 原生 SDR 1440 低诊断负载复跑（2026-09-25）

复用11044 APK SHA-256 `a11a48eb057f0dbe6aa67d993345817e8471450fcb32f2ef6ce6f29b4e27e979`、同一Dolby官方Sol Levante 4K/24fps P5、原生SurfaceView SDR、1440×810输出、同隔离P5 RPU/raw packed10原生库；关闭上一轮原生`p5_vo_summary`和`p5_swap_probe`，保留测试页默认关闭的每10秒mpv计数读取以及P5 raw/retire所需的运行属性。这是较低诊断负载，不是完全无日志的正式发行包。测试页在约25秒发生一次打开重建（日志有第一实例RPU flush/close和time-pos重回8.79秒），因此只统计第二个完整播放实例，不跨实例累计计数。

第二实例每10秒的`frame-drop-count`和`decoder-frame-drop-count`从time-pos 8.791667秒到258.791667秒持续为0；片尾time-pos 262.750000秒的多次读取仍为0，`vo-delayed-frame-count`亦为0。RPU close汇总 `inputs=6314, outputs=6307, matched=6307, errors=0, discarded=7, unconsumed=0`；尾部7条PTS 262.791667–263.041667秒在flush时被丢弃。两张合成屏幕截图分别出现蓝色树木与橙色火焰的正常场景，内容明显不同；这只证明两个采样时刻有可见画面，不证明逐帧呈现、流畅观感、母版颜色或HDR亮度。设备这轮SurfaceView输出为SDR，不应称为HDR激活。

完整日志及两张截图位于`archives/experiments/artifacts/android-p5-native-sdr-1440-11044-lowprobe/`，SHA-256依次为`e71b9aa8a88817ccb1362c74e64db94b49518ccac209c2212e6b6c012da98026`、`3be10f362e96dc5de297a2f6123a233f3dc1f81f96c51a48c4876a34611a6cf7`、`c15f431814b8ec0baa1a9a681d96931cbc53850919df9817ce1c36f2431fe3e2`。与前轮原生VO直出1次deadline丢帧不矛盾：原生VO与mpv属性有不同重建/统计起点，本轮只报告完整第二实例的属性读数。下一步仍需真人可见约20秒流畅/颜色观察、真实present cadence、尾帧差额定位、带音轨同步、30分钟热稳及P5 HDR输出路线。媒体移除，属性清零，官方10369安装并强停；未提交。
