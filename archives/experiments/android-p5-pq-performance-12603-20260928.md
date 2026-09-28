# P5→PQ Mystery Box 全片性能（2026-09-28）

P1已确认 Mystery Box 在本机真实PQ视频层可见且用户人工观感良好。P2使用同一自建 arm64 JAR SHA-256 `eac6514fd1b3409574f0b77014c9b29989e0d0868d40048cc199a822d94c660f`、`gpu-next`/`mediacodec`、横屏全屏、默认电池模式/自动亮度。源3840×2160、60000/1001 fps、约98.944秒；视频层10位 BT.2020/PQ。仅测试页启用分段性能日志与EOS掉帧读回，GPU用主机1Hz采样。每轮结束恢复原应用12492、自动亮度、熄屏。

## 12603 原始 3840×2160 PQ 输出

- 第一次到媒体约86.5秒时VO掉帧1897、decoder0，随后主机写诊断快照遇到空间不足，脚本提前恢复，**不计EOS**。第二次到媒体43.8秒时设备进入最近任务/桌面，播放器停下，**不计EOS**。两轮日志保留为 `...12603-perf-partial*` 和 `...12603-eos-interrupted*`，不能用于完整吞吐结论。
- 第三次轻量轮从头到 `AUTO_COMPLETED completed=true`，EOS即时 `time-pos=98.731967`、`frame-drop-count=2204`、`decoder-frame-drop-count=0`。t8/18/28/60/90的媒体时刻分别约4.39/14.38/24.39/56.39/86.37秒，对应VO累计104/321/539/1232/1914、decoder始终0。以源约5930帧粗算，约3726帧呈现、平均约37.7 fps；mpv VO计数口径不等于独立光学测量。
- GPU 110个1Hz样本中位720MHz，720MHz 82个、682MHz 12个、644MHz 14个、586/415MHz各1个；分段热状态均为1。`android-surface-size=3840x2160`，片源4K，但横屏显示的视频内容区约2560×1440。不能仅凭频率判定过热；当前VO掉帧主要发生在渲染/输出侧，硬解drop=0。
- 原始证据 `/private/tmp/media-kit-p5-pq-candidate-12603-eos-device.log`、`...-gpu.ndjson`。为了释放主机空间，12603 APK副本已删除，测试包由最终P1分支代码加测试页EOS计数日志和性能Dart define构建。

## 12604 输出宽度 2560 候选

- 仅新增 `MEDIA_KIT_ANDROID_PLATFORM_OUTPUT_MAX_WIDTH=2560`，不改变自建JAR或PQ链路。短轮日志确认源3840×2160、请求输出2560×1440、mpv属性同值；SF实际buffer旋转为1440×2560 `RGBA_1010102`，HWC `BT2020_PQ`。触摸→当前Surface首个可辨内容约1.129秒，非面板光学；t8/t18 VO累计19/19、decoder0，热状态1。短轮不证明全片收益，现进行EOS复测。
- 同包轻量全片轮到 `AUTO_COMPLETED completed=true`，EOS即时 `time-pos=98.798700`、VO **30**、decoder0。t8/18/28/60/90的媒体时刻约4.59/14.60/24.59/56.59/86.59秒，VO累计28/28/30/30/30，decoder均0；热状态各段1。GPU110个1Hz样本中位586MHz，586MHz 87个、644MHz20个，余277/415/538MHz各1。对同片4K PQ基线VO2204，少2174帧（约98.6%）；GPU中位720→586MHz。两个包性能探针一致、输出尺寸之外同JAR/源/路径，跨轮热分布仍需谨慎解释。证据 `/private/tmp/media-kit-p5-pq-candidate-12604-size-eos-device.log`、`...-gpu.ndjson`。
- 固定2560是诊断A/B参数，尚未产品化。主库正接入已有按物理布局/BoxFit计算的尺寸规则，使GPU HDR PlatformView按实际视频显示区域选缓冲；布局缺失时保留源尺寸回退，非GPU/SDR原路径不变。需确认布局事件、PQ信令、EOS性能和用户对最终画质的观感。

## 12605 按物理布局选择 HDR PlatformView 输出尺寸

- 产品候选在GPU HDR PlatformView复用现有 `Video` 布局上报与 `calculateAndroidTextureOutputSizeForLayouts`：用物理像素、BoxFit和多个布局owner的最大需求决定输出，保持不超过源分辨率；无有效布局时沿用源尺寸。Texture和非GPU PlatformView仍按原路径。此包无固定宽度诊断Dart define，APK SHA `a8c2ce983997f1cf49e7e25acdf987fe0cf1ec44a98f60e49fae71147a0ad0da`。
- Mystery Box短轮实际记录物理SurfaceView `3120×1440`、视频源3840×2160、布局输出 **2560×1440**，mpv属性同值。SF buffer 1440×2560 `RGBA_1010102`，HWC `BT2020_PQ`；当前Surface触摸→可辨内容约0.962秒，非光学；t8/t18 VO18/18、decoder0。无预先固定尺寸的布局路径已命中。完整EOS/GPU轮和独立审查进行中。
- 首次全片轮t60 VO26、decoder0，GPU完整110样本已取得，但主机在写收尾电池快照时空间耗尽，logcat早停且缺EOS，**不计全片完成**。清理仅隔离工作树的生成中间产物后，保留12605 APK（SHA如上）重跑轻量轮。
- 第二次同包到 `AUTO_COMPLETED completed=true`，EOS即时 `time-pos=98.798700`、VO **20**、decoder0。t8/18/28/60/90的媒体时刻约4.60/14.61/24.62/56.62/86.62秒，VO累计19/19/20/20/20，decoder始终0；热状态各段1。GPU110个1Hz样本中位586MHz，586MHz72个、644MHz35个，余332/415/538MHz各1个。正式布局路径相对4K PQ基线VO2204少2184帧（约99.1%），仍需用户确认缩放后的实际画质。证据 `/private/tmp/media-kit-p5-pq-candidate-12605-layout-eos2-device.log`、`...-gpu.ndjson`。结束原应用12492、自动亮度、熄屏。
- V1只读复核未发现确定性代码阻断；布局事件只作用于GPU HDR PlatformView，多个布局owner选最高分辨率需求，尺寸未变不会重复写原生属性。审查指出 `ANDROID_PLATFORM_LAYOUT_OUTPUT_SIZE` 曾在每次参数事件重复打印，已移到尺寸变化之后；此日志位置调整尚未重新打包。BoxFit视觉/多视图转场和HDR10/P8.4回退仍需实机核验。

## 12606–12608 非P5边界回归

- 12606 HDR10、同一通用布局代码：源3840×1920，输出尺寸2880×1440；SF视频层buffer旋转为1440×2880 `RGBA_1010102`、BT.2020/PQ，HWC `BT2020_PQ`。日志 `/private/tmp/media-kit-p5-pq-candidate-12606-hdr10-device.log` 及同前缀 `-sf.txt`。
- 12607 强制 P8.4 走 `gpu-next` HLG PlatformView：本机公开 `ANativeWindow_setBuffersDataSpace` 返回 -22、actualDataspace=0，预建报 `initialDataSpaceRejected`。这是强制实验路径，不能作为普通 P8.4 播放回归通过的证据。
- 12608 去掉强制 `MEDIA_KIT_ANDROID_GPU_PLATFORM_HDR`，保留同代码：P8.4 正常选择 `mediacodec_embed`，`android-surface-size=3840x1920`，SF视频层 `BT2020 STD-B67 Limited range`、实际buffer3840×1920。t8/t20系统截图不同，t8可辨画面；该通用gpu-next HDR布局策略没有触及正常HLG硬解Surface路径。日志和快照 `/private/tmp/media-kit-p5-pq-candidate-12608-p84-sdr-*`（文件名sdr是临时命名，实际输出为HLG）。
- 各轮测试脚本退出均恢复原APK12492、自动亮度mode1和熄屏。12606/12608仅为短时回归，不代替完整HDR10/P8.4任务的冷/热、重入与人眼验收。P5最终尺寸仍待用户同步看实际画面。

## 12609–12610 双视图诊断

- 12609漏传 `MEDIA_KIT_ANDROID_P5_RPU_PIPELINE_BUILT=true`，预建因产品门禁拒绝，未进入播放；不计双视图结果。
- 12610修正参数，Mystery Box PQ正常出画，布局初次设为2560×1440，播放器持续到探针phase1–4，截图每阶段均有不同实画。该诊断同时启用预建全屏，系统截图看起来全屏视频覆盖双视图 Row，布局尺寸未因phase变化再次上报；因此**不能据此判定两个独立视图的BoxFit/尺寸切换正确**，只证明此组合没有立即停止出帧。证据 `/private/tmp/media-kit-p5-pq-candidate-12610-dual-device.log`及同前缀p1–p4截图。结束恢复原APK、自动亮度并熄屏。
- 12611关闭预建全屏，竖屏Row探针在phase1–4报告输出1440×810→720×405→1440×810→720×405→1440×810；但截图中视频被拉长至半屏高度。根因是HDR PlatformView子控件仍被赋予整个viewport宽高，外层FittedBox得不到视频原始宽高比，尺寸上报正确而显示几何错误。
- 仅对Android `gpu-next` 且有HDR transfer的PlatformView，让视频参数aspect决定子控件宽高比，保留外层既有BoxFit；其它PlatformView不改。12612相同竖屏Row探针：phase1/2截图中的视频保持16:9比例，输出尺寸仍随布局缩放，播放器继续出帧。该探针同一播放器的两个Video同时挂载时截图只见一个活动视频Surface，不能据此声明两个副本可同时显示；P3继续处理双视图Surface生命周期。12613最终几何代码横屏全屏短轮仍输出2560×1440，截图视频居中、无拉伸，SF buffer1440×2560 `RGBA_1010102`、HWC `BT2020_PQ`。12614同代码全片到媒体98.782秒时VO42、decoder0，GPU110样本中位586MHz；构建漏开EOS事件日志，严格EOS再次用12615复测。所有轮结束恢复原12492、自动亮度并熄屏。
- 12615启用EOS事件日志，其余最终几何代码/自建JAR/源/输出相同：`AUTO_COMPLETED completed=true`后即时`time-pos=98.782017`、VO **11**、decoder0。媒体6.79/16.80/26.79/36.80/46.80/56.79/66.80/76.79/86.79/96.80秒各段VO均11，解码drop均0。GPU110个1Hz样本中位586MHz，586MHz84个、644MHz24个、538/415MHz各1；电池温度34→37°C。相对原4K PQ VO2204减少2193帧，约99.5%。与12605 VO20的差异是跨轮波动，不能归因于宽高比修正。证据 `/private/tmp/media-kit-p5-pq-candidate-12615-aspect-eos-device.log`、同前缀`-gpu.ndjson`与电池快照；结束原12492、自动亮度、熄屏。
- 第二次V1只读复核未发现确定性阻断；提醒热切源可能短暂使用上一源aspect，双视图同时输出/生命周期由P3继续验。用户回复“稍后再看”，故最终布局版本的人眼锐度、亮暗、颜色、流畅性尚未验收。
- 为用户稍后复看准备了无性能探针的同代码arm64包12616，SHA-256 `2bcb25d9c37ef5e5deeba50c3f60c3a4f6f12274542cc53f4ca0dc9c9779b0dc`，路径 `/private/tmp/media-kit-p5-pq-candidate-12616-visual.apk`。短播脚本 `/private/tmp/media-kit-p5-pq-candidate-12616-visual.sh` 已通过shell语法检查：播放时最高亮度约30秒，trap恢复原APK与进入前亮度设置并熄屏。**尚未运行12616、不得写成人眼通过**；收到用户“现在看”后才启动。
- 用户回复“现在看”后首次12616运行：应用启动时锁屏仍遮挡，日志只有`ANDROID_DIRECT_OPEN awaiting_tap`，无P5打开事件，故不计验收。随后确认设备`isStatusBarKeyguard=false`，脚本加入锁屏/前台门禁并同步重播；日志显示`gpu-next`/`mediacodec`、P5打开与2560×1440布局请求，最高亮度约30秒。用户回复“整体良好，无异常”，针对锐度、亮暗、颜色、流畅性及拉伸/残影均无问题。脚本恢复原12492、原亮度设置、熄屏。P2人工门禁完成；P3跟踪双视图/热切源的剩余生命周期问题。
