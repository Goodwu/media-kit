# LG P8.4 热态单变量对照方案（准备阶段，未执行）

## 已核对前置

- 主机原片fresh SHA256为`7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`，1,232,790,317字节；HEVC Main10、3840×1920、30000/1001fps、BT.2020/HLG/limited、DV8 compat4，1170.73秒。详见`thermal-source-preflight.json`。
- 设备既有app可读候选`/sdcard/Android/data/com.example.media_kit_hdr_lab/files/hokkaido-p84.mp4`（同size）；另有`original-p84-hlg.mp4`与`/data/local/tmp/media-kit-p84-7626cac2.mp4`。**未fresh全字节校验设备文件**；实际播放前先完整流式核对SHA256，不能用文件名或size当同源证据。
- 标准构建入口`tool/build-android-test.sh --platform-view --local-source <app-scoped-file>`。必须当前源码native→JAR→APK verified并装机回读hash；本阶段未构建或安装。
- AndroidServiceProbe仅debug可用，release不适合直接复用其VM service入口。同APK运行时模式选择/读回、低频状态文件和原生提交计数需要harness提供。
- sysfs实际背光`/sys/class/leds/lcd-backlight/brightness`和`max_brightness`可读（max=255）；当前spot read亮度10，不能当作后续播放期背光。`/proc/<app_pid>/stat`可读，`io`不可得。thermal VTS=`thermal_zone39`，battery=`thermal_zone0/30`，PMIC=`thermal_zone23`，仍保留type和值避免节点错配。
- 历史`sample-lg-playback-context.py`绑定旧N1/anchor、时长≤120s，不能直接拿来做本轮8分钟convert对照；只能复用低开销batch sysfs读法。

## 待Lead串行派发的执行步骤

1. 冻结各仓HEAD/dirty、native receipt/JAR/APK及设备现装hash。记录系统亮度/自动模式、旋转、screen timeout及App窗口亮度覆盖，结束恢复原值；不要求恢复旧测试APK或清理片源。
2. 同一APK提供A=`display-resample`、B=`audio`；仅video-sync改变。两者同为LG convert/hwdec=surfacetexture/gpu-next/PQ/peak1000/gamma0、无额外曲线和像素readback、相同缩放/FBO/YUV/HWC设置；保留声音输出、同一音量/路由。启动后读回实际video-sync及display-sync-active，不接受只看选择标签。
3. 每轮fresh session从同一PTS开始，横屏全屏同一几何与视频输出尺寸；系统手动亮度255，并在运行中采实际背光确认。保持同一外接电源/电池状态，不把full+plugged当正在充电。若电池进入充电状态/实际背光变化，标记对照失配。
4. 每轮至少8分钟，覆盖用户“几分钟后”热窗；A、B之间停止播放自然冷却，电池初温相差≤0.5°C、VTS相差≤1°C后开始。若无法匹配则记录不可比，不靠删掉不利时间段达标。建议首轮A/B、必要时反序B/A复核顺序效应；不一次并行多个播放器。
5. 低开销持续monitor：每5秒一次ADB batch读取uptime、battery/VTS/PMIC原值、GPU频率、CPU频率、实际背光、/proc/app/stat与/proc/stat。每30秒dumpsys battery核对插电/charging状态；SF只在稳定开播后和结束各一次，不每秒dump。top、全像素readback、大量trace、录屏均关闭。
6. Harness每10秒输出固定小状态：runId/session/source/epoch、video-sync/display-sync-active、hwdec-current/video-codec/vo、time-pos、pause/eof/buffering、decoder/vo drop、frame-count或可用提交计数、avsync。身份前后校验、防重入/不堆积，状态写App可读小JSON；readback缺项如实保留。旧PERF_PROBE每30秒可辅助，但它缺少hwdec-current及sync读回，不能独立证明热态仍硬解。
7. 统计按有效同源时间窗比较温升斜率、峰值/平台温度、CPU累计时间差、GPU频点停留占比、提交/源帧比、丢帧/AV漂移；GPU时钟不是GPU功耗，CPU stat不是总机功耗。没有功率仪只称温度/负载改善，不报节能百分比。

## 停止与判定

- 为避免重演严重热态，暂建议本轮操作阈值：电池≥43°C、VTS≥48°C、系统热警告/关机倾向、画面停滞或明显解码错误时停止该轮；这是本轮保守测试停止条件，**不是设备厂商温度规范**，由Lead在执行前冻结。用户提出过热即立即停止。阈值触发必须保留失败轮与实际时长，不能声称完成8分钟验收。
- 若hwdec-current丢失/变成软件帧、PQ/HWC路线变化、源身份漂移、APK读回不符，则该轮判为前提失败/路线失败；不自动降SDR或软解继续凑热窗。
- API24热状态公共API不可用时不拿0当正常。丢帧/位置推进和原生提交计数不等于面板逐帧呈现或光学亮度测量。
- 结束停止本轮播放并恢复亮度/自动亮度、旋转、timeout等原系统设置，复读确认；测试App和本地片源可保留。

## 当前状态

仅完成读取与方案设计，未启动播放、未更改设置、未实施采样脚本、未构建。等待Lead串行派发实际操作；需先拿到同APK模式选择与状态入口。
