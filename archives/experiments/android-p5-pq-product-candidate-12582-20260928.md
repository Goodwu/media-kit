# P5→PQ 产品链路候选 12582（2026-09-28）

P0 Texture→SDR 的真人动态画质确认仍待进行；本轮只准备 P1 的隔离候选，没有安装或播放 12582。手机检查时连接正常，仍为原版 12492、自动亮度、熄屏。

## 实现与边界

- 代码仅在隔离工作树 `/private/tmp/media-kit-p5-pq-product`，分支 `feature/android-p5-pq-product`，基线主库 `721cc9c`；主工作树原有 Java/C++ 诊断修改未覆盖、未暂存。
- `ANativeWindow_setBuffersDataSpace` 仍先调用公开接口；仅当其明确返回 `-EINVAL`，且为 arm64、API29、精确固件指纹、RGBA1010102 与 BT.2020/PQ 时，才走此前实机反汇编核过的 window `perform` 操作码 19。成功必须精确回读 PQ dataspace。
- 对该固件的 PQ Surface，初始 10 秒每 200 ms、此后每秒持续检查 dataspace，覆盖同 Surface producer 重建。失效且不能重设时发送带当前 WID/代次的 `SurfaceRuntimeFailed`，Dart 记录明确错误并沿既有 stop→release→ACK 路径回收；尚未做故障注入或实机证实。
- 测试页移除旧的 `p5_rpu_probe=2`/`p5_raw_yuv=1` 调试属性门禁；`P5_RPU_PIPELINE_BUILT` 仍只是编译配置，不是独立的打包 JAR 来源证明。

## 静态与打包证据

- NDK arm64 C++ 语法、Java 目标编译及 `git diff --check` 通过；隔离 Dart 控制器分析只有原有 5 条 info，测试页四个相关 Dart 文件分析无问题。独立 V2 初审指出监测 10 秒结束和运行中失败只发 destroy 两个阻断项；修订后独立静态复审未发现新增阻断，确认错误事件会保存原因、按同代 owner 走 stop→ReleaseSurface→ACK，失败保留引用重试，后续等待者仍能收到错误。实机故障注入未做；每秒监测不能保证检测间隔内逐帧PQ正确。
- 使用自建 arm64 JAR SHA-256 `eac6514fd1b3409574f0b77014c9b29989e0d0868d40048cc199a822d94c660f`、隔离代码拷贝和 `MEDIA_KIT_ANDROID_PLATFORM_VIEW=true`、HDR transaction、P5 RPU build flag、预建横屏全屏、命名本地 Mystery Box 源，离线 Gradle release 构建成功。12582 APK SHA-256 `3f9c180fa55df10d0df5b80e9d2a7b8de8e2dec1ab5a34d964834e0bdb700a64`；APK 只含 arm64 native 库，HDR bridge 二进制有新 fallback 日志符号。APK 内 strip 后 libmpv SHA-256 `3350c910d9de2d38838bb3874f23a84ea5ecf764b8d18162b065bbe2b209fa75`。
- `flutter test --no-pub` 首轮在主机剩余约 117 MiB 时因 Objective-C native asset 链接 `No space left on device` 未运行测试体；清理生成中间文件后补轮，起初隔离构建目录仍使用旧测试文件而编译失败，复制同候选的策略测试文件后 `flutter test --no-pub test/android_hdr_playback_policy_test.dart` 通过 10 项。构建、策略测试与静态检查均不证明 PQ 出画、真实首帧或资源释放。

## 下一步

2026-09-28 P0 Glass 真人动态观察已通过。12582 首次 Mystery Box 实机短轮由正常入口启动，t8/t20 截图都有不同的实际画面；Java 创建当前 `viewId=1`、`generation=2`、RGBA1010102/PQ Surface。公开 setter 返回 `-22`，精确固件回退后回读 `163971072`；播放中 SurfaceFlinger 视频层 `BT2020_PQ (163971072)`、HWC dataspace `0x09c60000`、format `0x2b`、DEVICE 合成，mpv `mediacodec`、目标PQ。系统截图偏淡，不能代替面板真人观感。SF 显示该层 `hdr metadata types=0`；ffprobe 的源视频 side data 仅列 DOVI configuration record，无 HDR10 mastering/content-light 元数据，输出策略及元数据门槛仍待厘清。测试页 FirstFramePixelCopy 选到了已失效的旧 Surface，连续 status=3、samples=0，不能给首帧时间；隔离工作树已将同尺寸候选选择改为较后一个，未重建实测。设备已恢复原12492、自动亮度、熄屏。证据在 `/private/tmp/media-kit-p5-pq-candidate-12582-device.log`、`-sf.txt`、`-t8.png`、`-t20.png`。

下一步：修正并重测当前 View/Surface 首帧探针，核清 P5→PQ 静态元数据的来源与输出策略，测 SDR 复位和运行中故障恢复；故障注入覆盖 PQ 重设失败、stop/ACK 首次失败后重试、旧代失败与新代交错、超过 10 秒 producer 重建。未完成这些门槛前不合入候选。

## 12587–12593 续测（2026-09-28）

- 12587 构建漏启用自动单播放器，落入双视图示例页，剔除；12588 首帧探针仍默认选 Flutter Surface，零样本，剔除。12589 传入 platform 目标并记录 View identity；探针从旧 View 切换到当前 PQ View 后，三独立短轮触摸按下→首个可辨 Surface 内容 **1.144/1.214/1.057 秒**，对应新 View identity、PQ `SurfaceCreated`、`gpu-next`/`mediacodec`。第四轮12590约1.084秒、12591约1.133秒；均是 Surface PixelCopy，不等于面板光学计时。
- 12590 故障发现：同 PID 从 P5→PQ 转为 `/data/local/tmp/media-kit-sdr-control.mp4` 后，解码已 BT.709/BT.1886，但原 10 位 PQ Surface 继续存在，SF/HWC 仍 `0x09c60000`/format `0x2b`。测试页协调器重置 mpv 属性，却没有重建输出。
- 12591 修正：在 SDR 打开前调用输出槽 `ensure` 重建无 HDR transfer 的 `gpu-next` Surface，同时仅对 HDR transfer 请求 RGBA1010102。实机 SDR 帧持续出画，SF/HWC 原 PQ 层消失，现有视频层 dataspace UNKNOWN/default、format `0x2`，mpv 视频参数 BT.709/BT.1886；屏幕截图为正常 SDR 内容。12590/12591 同源对照表明此前 PQ 残留已消失。
- 12592 测试包在第20次监测强制注入 `pqDataSpaceLost`，事件到 Dart 后解码停下、AImage 137/137 闭合，但 PQ 末帧仍停留屏幕。12593 增加精确失败代次在 `ReleaseSurface` 成功后隐藏失效 View，注入复测记录 `SurfaceRuntimeFailed`、约1.74秒后 `releaseSurface ... result=released` 与 `acknowledgeSurfaceRelease ... acknowledged`，之后 SF 不再合成 PQ 层，t8截图全黑，无进程崩溃。正式候选已删除第20次强制故障分支，保留失败时隐藏及释放日志；仍需首轮 ACK 丢失和旧代交错注入。
- Mystery Box 的 `ffprobe` 容器/流只有 Dolby Vision 配置，首帧有 RPU 动态元数据而无 HDR10 SMPTE2086/CTA861.3 静态母版字段；SF 的 `hdr metadata types=0` 与此一致。Android AOSP [HDR playback](https://source.android.com/docs/core/display/hdr) 将 Dolby Vision 归为动态元数据、HDR10归为静态元数据。本轮不伪造未知母版参数；尚需明确 P5→PQ 转换的显示峰值策略和真人观感。
- 每轮结束均恢复原版12492、自动亮度、熄屏。P1尚未验收；用户 PQ 动态观感回复待收取。12589 APK SHA `7582700e1e5fd43bfb9fcb0ece084b9dca95e42264b274986916a3665f4804c1`，12591 SDR 修复包 SHA `5a1ad20bea6cb886d86816eaf05bcffd62bedc616b3b92f7be66d3f8fd4979a0`，12593故障注入包 SHA `d7102a237e7772f0f7a4718e35ad3498d33e3ae6518b25c798f87c7dc301329b`。原始日志及SF快照在对应 `/private/tmp/media-kit-p5-pq-candidate-<编号>*`。
- 12594 已在删除强制故障分支后的同版代码重建并短轮复核：触摸→当前PQ Surface可辨内容1.084秒；随后自动切SDR，视频参数BT.709/BT.1886、SF/HWC已无PQ dataspace或10位buffer，实际截图持续出画。APK SHA `20ff6bbe24d948bccca66dede46be390f071a3cabbd174e1cb40bd34847e1075`。该包仍启用了只供验证的10秒自动切SDR；正式候选默认不启用。手机恢复12492、自动亮度、熄屏。

## 12595–12598 故障交错与正式长播（2026-09-28）

- 12595 受控 PQ 失效并让首次 Release ACK 返回失败：日志记录同一 `generation=1,wid=10438` 的运行中失效、生产者停止、`ReleaseSurface result=released`、首次 `DIAG_PQ_ACK_FAIL_ONCE`、Dart 明确错误，以及约 250ms 后重试 `acknowledgeSurfaceRelease result=acknowledged`。失效 PQ 层被隐藏，进程未崩溃。注入代码已撤销；这只验证一次受控 ACK 失败与重试，不能证明所有通信故障。
- 12596 首次旧代故障注入挂在 View dispose，释放时已无活动引用，因此未实际发出事件，不计验证。12597 改为在旧 PQ `ReleaseSurface` 后延迟五秒注入，日志在新 SDR 打开并出画后记录 `DIAG_PQ_STALE_FAIL generation=1 wid=11062`；Dart 收到的仍为旧 `viewId=1,creationSerial=2,surfaceGeneration=1`，只对旧代完成 ACK，未见当前 SDR producer 停止。t20 截图为 SDR 实际内容，SF 当前层为 8 位/默认 dataspace、无 PQ 层。延迟注入代码已撤销。
- 12598 是删除所有诊断注入后的正式候选，不启用自动切 SDR。自建 arm64 JAR SHA `eac6514fd1b3409574f0b77014c9b29989e0d0868d40048cc199a822d94c660f`；APK SHA `e2389c27f189455cbe47b4502ff03dd4f8ba3c0af13b2f8ead0beb66529a85bf`。正常入口、预建横屏全屏 Mystery Box 长播约一分钟；当前 PQ View 的 PixelCopy 触摸按下→可辨内容 `1.090s`，不是面板光学计时。t8 SF 当前视频层 `BT2020_PQ`/`RGBA_1010102`，HWC `BT2020_PQ`，HDR metadata types=0；视频参数为 `mediacodec`、Dolby Vision、BT.2020/PQ。画面截图与日志不能替代用户眼见观感，已请求现场回复。结束恢复原应用12492、自动亮度、熄屏。
- 用户前两次未看见播放，未计人工验收。收到用户明确“现在看”后，12598 同 APK 再次重播约 40 秒；播放中同步提问，用户答复“画面良好，无异常”。这一条只证明用户所见亮暗、颜色、流畅性和无明显印记/紫屏的人工观感，不代替定量色准或光学亮度测量。两次播放后都恢复原应用12492、自动亮度模式1、屏幕 Asleep。
- V1 独立代码复核无确定性阻断，确认产品文件无强制故障注入，ACK失败与旧代事件受控日志成立；复核未重新构建或操作设备。P1仍须实测真正运行中PQ失效后的同进程重试，并在最终无注入代码上完成PQ→SDR复位；P2全片到EOS另立。

## 12599–12601 同路重试（2026-09-28）

- 12599 用 `d94a25a` 产品代码重新构建、只启用测试页10秒自动切SDR。当前PQ Surface触摸按下→可辨内容1.113秒；切换后 `ANDROID_HDR_SDR_RECOVERY_OPEN`、实际SDR视频参数BT.709/BT.1886，t20截图继续出画，SF已无PQ/10位旧层。APK SHA `9cefdaea07b8c963111a365757e8abd1ea75311a32d2ad9841d1f8297cfb2f6c`。这是最终产品代码的复位验证，自动切源只用于测试。
- 12593旧注入包在失效后按Back并点击未触发重新打开；不能据此判同进程重试。12600在当前产品代码仅临时增加一次运行中PQ失败与8秒后同源显式重试：首层成功出画后 `pqDataSpaceLost`、stop→ReleaseSurface→ACK；同路重试立即因旧 `pendingSurfaceFailure` 失败，未新建层。根因是通用 `AndroidHdrOutputSlot.ensure` 在VO/格式/transfer不变时直接 `waitReady(old)` 并传播失败，没有沿正常barrier淘汰已失败输出。12600注入APK SHA `8e8bc1c7f378a3880c96c75c83fc543806defb9552fca316b19d1000f4d6b12d`，日志保留。
- 12601 仅将通用输出槽的显式同路重试改为：`waitReady(old)` 失败后执行既有 `disposeForRebuild(old)` 屏障、发布空槽、创建新控制器并等待绑定。相同一次故障注入后，旧WID释放/ACK，日志 `DIAG_PQ_RETRY_BEGIN`→第二次 `ANDROID_HDR_OPEN`→`DIAG_PQ_RETRY_DONE`；t20截图为新视频帧，SF/HWC新层BT.2020/PQ、RGBA1010102。APK SHA `c30fedbd44aa25c730ed6471f476b81cd5d7030eed8d6a0abc264c00916c4fbe`。临时故障与自动重试注入已从工作树撤销，仅保留通用输出槽修复；仍待无注入最终包和独立复核。
- 各轮结束原应用12492、自动亮度、熄屏。系统截图的HDR转换观感不能替代已取得的12598真人观察。
- V1 独立复核通用输出槽修复，无确定性阻断；`waitReady` 失败后先完成旧输出释放屏障，释放失败仍保留旧 owner 并传播错误。就绪超时也会触发一次新建，可能多一次清理，但不会跳过屏障。
- 12602 删除临时注入后以同一最终代码构建，测试页仅启用10秒PQ→SDR切换。当前PQ View触摸按下→可辨内容1.168秒；切换后SDR参数BT.709/BT.1886、t20截图为实际画面，SF无PQ/10位旧层。APK SHA `a8725c2d301b159378414775b93fb68b7c3780c450d30b803f8543b13e60f83a`。结束恢复12492、自动亮度、熄屏。它和12598真人PQ视觉验收合起来关闭P1短播/复位/重试门禁；全片PQ性能另在P2。
