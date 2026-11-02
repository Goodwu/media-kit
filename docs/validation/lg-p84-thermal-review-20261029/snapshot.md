# LG DV P8.4 发热审查：只读现场快照

## 范围与基线

- 2026-10-29 14:41:48–14:41:50（Asia/Shanghai）采集主体，14:42:22 起额外流式读取现装APK身份。
- 设备 `LGH870DS42e27764`，fingerprint见 `device.txt`；本仓 HEAD `3bdf2c6cd21860c1c258d0b75f807b743d373e4a`；开始时 `git status --short` 为空。
- 未启动、暂停、退出或唤醒App，未安装、改设置或重放视频；未持续压力测试；仅ADB只读查询。现装APK流式读取未落盘二进制。
- 各命令参数、采样时间、返回码与过滤策略由 `snapshot-metadata.json` 和本摘要说明。`power/window/ps/package/cpuinfo/sf/route.txt` 是相关字段筛选输出，并非完整原始dump；URL均替换为 `<URL_REDACTED>`。`top/thermal/freq/battery/device.txt` 保留本次命令输出。

## 观察事实

- 前台是 `com.example.piliplus.dev/com.example.piliplus.MainActivity`，进程 PID 23382。
- 现装包 versionName `2.1.6`，versionCode `1`，lastUpdateTime `2026-10-29 13:43:56`。base.apk为27,644,837字节，SHA-256 `f92e9ad8e9d2e2a4475fbfd171ced8c42fa898a97c48d3bf3cba2914e57b3bd0`；见 `installed-identity.json`。没有来源receipt，不能把此包绑定到当前源码HEAD或历史验收包。
- 电池温度37.3°C（battery temperature=373）；电量100%、AC powered、status=5(full)。近期系统日志明确`charging=false`、chargingCurrent=0；因此是外接电源，不等同于当时正在给电池充电。
- 屏幕ON，Awake；系统亮度设定162、自动亮度模式1；这不是实际背光功率或HDR峰值。
- 当前SF视频外形只见RGBA_8888 UI层与HWC合成，未见convert对应YUV视频层；最近2000条logcat中无HdrDiag/MKST/MKSURF当前路由证据。无法确认采样时仍在播放P8.4，亦无法从这些证据区分停播、暂停或页面状态。
- `dumpsys cpuinfo`报告的是14:41:00–14:41:30历史区间，TOTAL 1.8%，PiliPlus没有出现在列表；不是与SF同一瞬间的帧级证据。`top -n1`采样被top自身占用主导，不能据此量化播放线程开销。
- GPU时钟读取214MHz；gpubusy返回0/0，不能计算GPU利用率。cpu2/3瞬时2.1504GHz不能单独证明长期CPU高负载。
- thermal sysfs可读取，单位混杂：bms/battery=37300，pm8994_tz=40519，tsens原值最高491，vts=385；不统一换算所有节点，也不把电池温度当SoC温度。

## 最近可见热事件

- `route.txt:1`：14:30:34.493，LGPowerManagerHelper报告`thermalType=vts`值48.5并发送`check_hot`。
- 同一日志随后47.9、47.2、46.7等逐步下降，至14:39:50.176的38.5。
- 14:31:08.490与14:31:12.795，SDM各报告一次`Setting HDR color mode = hal_hdr`。
- 这是设备曾出现热状态与HDR模式日志的证据，但未与同一时间的App route/source、解码器、进程负载关联；不能认定该vts就是SoC/面板/机壳实测温度，不能据此确定DV P8.4发热根因或发热峰值。

## 判定与限制

只读快照采集成功；发热复现未执行，优化效果未验证。现有日志支持近期存在热事件，但采样时已较热事件降温。当前现场缺少P8.4在播、同源同亮度/布局、稳定负载、功率及温度时间序列；不能从本次低负载快照反驳用户的严重发热报告。

结束时新增文件只位于本证据目录；未修改被验证实现。主任务可能同时更新记录，最终状态由Lead整合。

## 补查：热事件附近的硬解失败/软解回退日志

Lead提示当前配置存在硬解失败后软件回退可能性，14:43:29再次做一次有界logcat筛选（命令请求最后4000记录，实际返回13374文本行；可见时间14:23:00–14:43:28）。`hwdec/fallback/software decoder/mediacodec/OMX/ACodec/CCodec/ffmpeg/codec error/fatal/vidc`相关匹配0条，见 `decoder-log-filter-metadata.json`。该时间窗口覆盖14:30热事件，但此设备/App没有相关输出，**无法确认或排除播放中途转软解**；也不能把空日志当成未发生错误。未进一步采大dump或启动播放。
