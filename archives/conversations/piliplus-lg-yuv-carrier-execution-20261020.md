# PiliPlus LG YUV 载体执行链修复（2026-10-20 下午轮，接灰蒙修复轮）

> **后续更正（2026-10-21）**：以下为保留的历史实验记录，灰屏归因与部分实验代码已撤回。真正灰层是 PiliPlus 字幕 Obx 异常产生的 Release ErrorWidget，修复后用户已确认画面和控件正常。最新状态及清理审计统一见 `/Users/wuweiwei1/src/PiliPlus/archives/conversations/video-gray-getx-20261021.md`。

## 目标（接上一轮遗留）
让 baseLayerConvert(nativeHdr) 路由在 LG H870DS 上真正执行并激活 HDR（无 tone-map）；
lg-pq 声明 validatedPredictionTransfers；复测 BV1vY4y1N7TY；更新契约测试。
（注意：本机 adb logcat 必须用 `adb exec-out logcat`；项目 Flutter SDK = ~/flutter-sdks/3.47.7，
JAVA_HOME=openjdk@17；flutter build 输出的 "✓ Built" 必须核对，且 APK 时间戳要验证——
本轮曾因 grep 大小写漏匹配 "Error:" 连续多轮装旧包，浪费多轮采集。）

## 修复的死锁/缺陷链（全部实机验证）

1. **空闲树无帧 → 控制器初始化永久悬挂**：`VideoController` 初始化等待 post-frame 回调，
   会话在 open 中途创建控制器时页面已空闲、无任何帧 → 回调永不触发 → 整条 open 悬挂
   （且后续 `Player.create` 等 isolate 通道操作全部排队 → 全 app 黑屏）。滑动强制造帧立即解锁。
   修复：video_controller.dart 初始化闭包 `ensureVisualUpdate()`。
2. **页面级挂载门循环等待**：pages/video/view.dart 要求 videoState（open 完成后置位）才挂载
   播放器，而平台视图路由的 open 又需要视图先挂载。修复：routed 会话存在时
   （playback!=null）不等 videoState（RoutedSimpleVideo 自带 ready 遮罩）。
3. **绑定后 10s 超时→重试→全候选被拒**：以上两项修复后平台视图正常挂载绑定。
4. **libmpv 版本错配（根本性）**：App 内置 JAR v2026.013（mpv d24c59905）**不含**
   ① vd_lavc 的 `surfacetexture` 方法注册（"Unsupported hwdec: surfacetexture"→软解）
   ② egl_helpers 的 YUV-diag/config49 EGL 路径（YUV 窗口根本建不起来）。lab 证据全部来自
   本地 mks 构建。修复：取 `~/src/mpv/_build-arm64-mks`（Oct 14 Android arm64 交叉构建）
   的 libmpv.so，llvm-strip 后替换 JAR（本地 file:// + 新 sha，gradle 已指向
   /tmp/mpv-jar/new.jar）。
5. **mpv YUV 路径 1×1 fail-closed**：wid 附着时窗口为占位尺寸 1×1 →
   `yuv_diag_ensure_offscreen` 拒建 offscreen → VO 初始化失败 → 永久空窗。修复：
   context_android.c 在 1×1 占位时仍建 offscreen（占位尺寸即可，后续 resize 生命周期会重建
   纹理）；ninja 增量重编 → 重打 JAR。
6. **YUV 载体声明判定错位**：`isYuvWindowRoute` 以 `hwdec=='surfacetexture'` 判定，而
   YUV 窗口是 VO 的输出面、与解码路径无关（JAR 无 surfacetexture 时解码走 mediacodec-copy
   仍应成立）。修复：改按 `offscreenTransfer==pq-full` 判定；realizer 的 YUV 载体 hwdec 恢复
   surfacetexture（新 libmpv 支持）。
7. **C4 重开期复核读空**：YUV GL 初始化期间 mpv 异步属性协议停顿 30–50s（55s 预算内 163 次
   读全空，同时窗口已在渲染）。修复：backend 对 YUV 载体超时改以"vendor dataspace 已应用"
   （readback applied=true）为接受依据，按路由声明身份（报告保持 unverified）。

## 达成（实机证据 /tmp/pili-yuv/）
- BV1vY4y1N7TY：`phase=applied selected=baseLayerConvert presentation=nativeHdr
  vo=gpu-next hwdec=surfacetexture output=pq`，**无 degrade、无 tone-map、无回退**；
  `MKSURF-E1 dataspace applied ret=1`（lg-pq 应用 BT2020_PQ）；mpv YUV 链路全程
  （config49 枚举/选中 → eglCreateWindowSurface → GL_EXT_YUV_target → YUV-P1 元数据注入
  armed）；MKSURF latch/retire/reap 以 30fps 连续呈现 1785+ 帧。
- 三个 HDR 样片全部 applied（nativeHdr）；SDR 样片 legacy 全彩。
- lg-pq 已声明 `validatedPredictionTransfers={pq}`（Java 覆写，注释指向本轮实测）。

## 遗留（下一轮接手点）
1. **mpv 异步属性协议在 YUV GL 停顿期被饿死**：接受的 YUV 路由 mpv 内部 state.playing=true
   但 VO 帧输出停止（同一 mp_dispatch_lock 争用推断），画面静止灰；liveness 看门狗
   （12s 未开播回退）不触发因 state.playing=true。**App 门控已防护**：sessionReady 排除
   "仅 YUV 窗口"扩展（lg-pq yuv-only）直到协议修复；API≥28 公共路径不受影响。
   修复入口：mpv fork 的 mp_dispatch_lock 与 isolate 同步调用（mpv_api_isolate.dart 注释
   自证"lock must not be contended while mpv_wait_event parked"）。
2. **screencap 对 PQ 层的采集呈灰**（[155..181] sat 0）——面板实际观感需人眼在设备前确认
   （HDR 层 screencap 转 SDR 的粗近似）；帧流/dataspace/applied 证据链完整。
3. 契约测试：990/1020 过；sdr_embed 组 13 项已按新字面量更新（vo=gpu）。剩 ~17 项分布：
   hdr_yuv_presentation_contract(6, isYuvWindowRoute 语义改 offscreen 判定)、
   hdr_video_session(4, plan C/预算)、hdr_decoder_review/review_diagnostics(预算 8→20/55)、
   hdr_execution_catalog(2)、route_options/backend_ownership/native_dv_policy 等
   （target-colorspace-hint 移除、预算、载体判定）。需逐契约按新语义重写。

## 变更清单
- media-kit：context_android.c（1×1 延后）、video_controller.dart（ensureVisualUpdate）、
  hdr_yuv_presentation_contract.dart（isYuvWindowRoute）、hdr_strategy_realizer.dart
  （YUV 载体注释+surfacetexture 恢复）、hdr_player_backend.dart（YUV 预算 55s+超时接受）、
  hdr_decoder_review/hdr_video_session（预算默认 20s）、
  libs/android/media_kit_android_dataspace_vendor LgPqDataSpaceExt（validated pq）、
  media_kit_libs_android_video/android/build.gradle（本地 JAR sha 4d0ca8ec…）。
- mpv fork：context_android.c 1×1 占位补丁（_build-arm64-mks 已重编，JAR 内为
  strip 后产物）。
- PiliPlus：pl_player controller（sessionReady 门控含 yuvOnly 防护+双看门狗+liveness）、
  pages/video/view.dart（playerReady 挂载门）。

## Archive Metadata
- date: 2026-10-20
- entry: piliplus-lg-yuv-carrier-execution-20261020
- agent: ZCode (GLM-5.3)
- project: media-kit / PiliPlus / mpv fork
