# 交接：PiliPlus LG H870DS HDR 点亮——问题、进展与剩余工作（2026-10-20 晚，交接轮）

> **后续更正（2026-10-21）**：以下为保留的历史实验记录，灰屏归因与部分实验代码已撤回。真正灰层是 PiliPlus 字幕 Obx 异常产生的 Release ErrorWidget，修复后用户已确认画面和控件正常。最新状态及清理审计统一见 `/Users/wuweiwei1/src/PiliPlus/archives/conversations/video-gray-getx-20261021.md`。

## 交接目标状态（authentic）
在在线 adb 设备 LG H870DS（Android 7.0/API 24，Adreno 530，DV+HDR10 面板）上：
1. 视频蒙灰 —— ✅ 已修复（四样片全彩实机验证）；
2. HDR 流在 HDR 能力面板解码并激活 HDR 显示（禁 tone-map）—— ✅✅ **管线端到端已点亮并有长稳证据**（applied nativeHdr/surfacetexture/pq、dataspace applied、30fps 帧呈现 3.5min+ 零 ANR），**面板观感待用户人眼最终确认**（screencap 对 PQ 层只能拍出灰图，机器证据链完整）。

## 环境（交接必读，全部踩过坑）
- **Flutter SDK = ~/flutter-sdks/3.47.7**（.fvmrc 钉 3.47.7；brew 的 3.47.2 会编译失败——`checkUp` 错误）。
- **JAVA_HOME = ~/Library/Android/sdk/ndk 同级的 openjdk@17**（`/opt/homebrew/opt/openjdk@17/...`；JDK27 与 AGP 不兼容）。
- **logcat 必须 `adb exec-out logcat`**（普通 `adb shell logcat` 在此机返回空）。
- **每次构建必须核对**：`✓ Built` 行 + APK 时间戳 + `--dart-define=...` 必须每次构建都传（defines 不持久）。曾有 grep 大小写漏匹配 "Error:" 连续多轮装旧包（构建失败但管道吞掉退出码）。
- **⚡ JAR 位置警告**：gradle 指向 `file:///tmp/mpv-jar/new.jar`（media_kit_libs_android_video/android/build.gradle 内 sha 4d0ca8ec…）——**/tmp 重启会清**！交接后必须迁至持久路径或重建（重建法见下）。

## 已修复的死锁/缺陷（七重，全部实机证据，勿重复排查）
1. **空闲树无帧 → post-frame 永久悬挂**：`VideoController` 初始化等 post-frame 回调，会话中途创建时无帧→悬挂并连坐全部平台通道。修复：video_controller.dart 初始化闭包 `ensureVisualUpdate()`。
2. **页面 videoState 循环等待门**：pages/video/view.dart 要求 open 完成才挂播放器，平台视图 open 又要视图先挂载。修复：routed 会话存在时跳过 videoState 门（pages/video/view.dart `playerReady` 改写）。
3. **JAR libmpv(d24c59905) 版本错配**：无 surfacetexture vd 注册（"Unsupported hwdec"）、无 YUV-diag EGL（config49 建不起来）。修复：换装 `~/src/mpv/_build-arm64-mks` 构建（ninja 增量重编 + llvm-strip + 重打 JAR）。
4. **mpv 1×1 fail-closed**：wid 附着时窗口为占位尺寸 → YUV offscreen 拒建 → VO 死。修复：context_android.c 占位尺寸仍建 offscreen（后续 resize 生命周期重建纹理）。
5. **isYuvWindowRoute 以 hwdec 判定**：改按 offscreen 契约判定（hdr_yuv_presentation_contract.dart）。
6. **C4 重开期协议停顿**：YUV 载体复核读空 30-50s（GL 初始化停顿期属性协议停摆）。修复：hdr_player_backend.dart YUV 载体预算 55s + 超时接受（dataspace applied 为依据，报告 unverified）。
7. **双 SurfaceView Z 序竞态**：fork 的 PlatformVideoView（offscreen swapchain + final-pass vendor 窗口）attach 顺序竞态让 offscreen（uniform PQ 灰）盖住 YUV 窗口——灰盖视频/全屏灰条。修复：final-pass（rgba1010102 格式）`setZOrderOnTop(true)` 钉图层栈最顶，offscreen 保持 media overlay（PlatformVideoView.java）。

## 色彩空间三因子（已按序修，残留见下）
1. **full/limited 标签错配**（整体电平过曝）：matched full 配对（`surfaceTransfer='pq'` FULL 标签 + route 契约 full 电平）——实机确认"过曝轻一些"。
2. **HLG→PQ 转换缺失**（亮部约 2 倍过曝）：契约写入补 `target-trc=pq`——实机确认"亮部过曝大幅缓解"。
3. **亮部残余过曝**（用户：暂可接受）：疑似目标峰值/色调映射因子。下一步 A/B：契约写入追加 `target-peak=1000`（HLG 参考峰值）；再不行抓 mpv 属性应用日志转专项。

## 当前部署状态（on-device）
- 组合：`setZOrderOnTop`（final-pass 置顶）+ matched full（FULL 标签 + full 电平）+ `target-trc=pq` 契约写入 + P0 observe=1（诊断构建）。
- BV1vY4y1N7TY 实测：applied nativeHdr/surfacetexture/pq 零降级；playing=true、position 推进、MKSURF latch 4179 帧（733→844s 实时 30fps）、零 ANR/FATAL。
- **已知 tradeoff（用户知悉）**：Flutter 播放控件被 ON-TOP 视频盖住（可点击不可见）——App 侧可改平台侧绘制控件（一处小改），或维持现状。
- **已知残留**：亮部残余过曝（见上）；出视频前短暂灰屏 + 全屏灰条（见下）。

## 剩余问题与修法（按优先级）
1. **亮部残余过曝**：契约写入追加 `target-peak=1000`（media-kit 侧一处）；再不行抓 mpv 属性应用日志（logcat 过滤 'YUV-DIAG'/'MKSURF'，logLevel 需临时 .v+转发器——本轮已拆，重建时加回）。
2. **出视频前短暂灰屏 + 全屏灰条**：vendor yuvDiag 表面初始缓冲=灰、pillarbox 区域未写。修法：fork 的 vendor 扩展（getSurfaceDataSpace 所在 native）追加 `clearSurfaceBlack(surface)`——创建回调后清黑（eglMakeCurrent+glClearColor(0,0,0,1)+glClear）。两现象一并消除。
3. **滑动短暂蓝屏**：final-pass 重建空隙；先观察 2 落地后是否消失（可能同为未写内容）。
4. **控件被盖**：App 侧把控件改平台侧绘制（一处小改），或维持现状（用户已知情）。
5. **文档改正**（lab 侧 docs，替换文本已备）：
   - "接受后无输出/async 饥饿" 叙述 → 实际：**"双 SurfaceView Z 序竞态：offscreen 层 attach 顺序竞态盖住 YUV 窗口（灰盖视频，随后浮出）"**；
   - 新增：**"offscreen 契约未下发 target-trc=pq，HLG 数值被 PQ 容器按绝对亮度解释（亮部约 2 倍过曝）"**；
   - 新增：**"vendor yuvDiag 表面初始缓冲未清黑（灰屏-before-start + pillarbox 灰条）"**。

## 排查方法论沉淀（critical review，勿重蹈）
1. **screencap/screenrecord 对 PQ 层只能拍出均匀灰**（内容变而采集恒定=采集盲区实证）——"截图均匀灰" ≠ "无输出"；面板观感只能人眼确认。输入侧活性（playing/position/MKSURF latch）≠ 呈现证明；呈现证据 = reap/retire 计数前进 + SF 层 buffer handle 变化。
2. **一次诊断构建覆盖多分支**：P0_OBSERVE=1 + resize 追踪 + 分段探针一次进构建；勿每猜一测一轮整包（本轮最大时间黑洞）。
3. **构建失败后禁装旧包**：`set -o pipefail` + 核对 `✓ Built` + APK 时间戳。
4. **两轮无进展即停修复型试探**：补边界证据（分段探针），不加超时/改清理/放宽接受条件。
5. **根因假设勿过早固化交接材料**：新证据（用户"隐约有视频"）出现应立即降级旧假设。

## 证据位置
- 本轮：/tmp/pili-yuv/（yuv8-yuv19、final-*、vfinal-*、sfcheck、confirm、itu-*；logcat+截图+SF dump）。
- 上轮：/tmp/pili-verify-20261020/（三机验收+Z 序修复前基线）。
- 交接文档（前两轮）：media-kit `archives/conversations/piliplus-lg-gray-veil-hdr-gate-20261020.md`、`piliplus-lg-yuv-carrier-execution-20261020.md`。

## 变更清单（未 commit，全部工作区）
- **media-kit**（9 文件）：PlatformVideoView.java（Z 序）、hdr_player_backend.dart（target-trc 契约写入+YUV 预算 55s+超时接受）、hdr_yuv_presentation_contract.dart（isYuvWindowRoute offscreen 判定）、hdr_strategy_realizer.dart（纹理 vo=gpu+YUV 载体注释）、hdr_video_session.dart（预算 20s+liveAcceptedYuvPlan）、hdr_decoder_review.dart（预算默认 20s）、routed_video_playback.dart（急建会话+stop 跳过+解钉 require(sdr)）、video_controller.dart（ensureVisualUpdate）、hdr_output_slot.dart（探针已清）、LgPqDataSpaceExt.java（vendor 插件，validated pq）、media_kit_libs_android_video/android/build.gradle（本地 JAR sha）。
- **mpv fork**：context_android.c（1×1 占位建 offscreen + P0_OBSERVE=1 + resize 追踪；_build-arm64-mks 已重编）。
- **PiliPlus**（5 文件）：pl_player/controller.dart（门控+看门狗+liveness）、pages/video/view.dart（playerReady 门）、pages/video/controller.dart（isHdrRendition）、pubspec.yaml（vendor 依赖）、pubspec.lock。
- **/tmp/mpv-jar/**：orig.jar（v2026.013）+ new.jar（mks libmpv strip 后，sha 4d0ca8ec…）——⚡ 迁持久路径。

## 契约测试债
media_kit_video 990/1020 过。sdr_embed 组 13 项已更新（vo=gpu）。剩 ~17 项待按新契约重写（已逐文件定位）：
hdr_yuv_presentation_contract(已清 6→0)、hdr_video_session(已清 4→0 后新增待查)、hdr_decoder_review/review_diagnostics(预算字面量)、hdr_execution_catalog(2)、hdr_route_planner(1)、hdr_player_backend_output_ownership(1，target-colorspace-hint 移除)、hdr_session_native_dv_policy(1)、hdr_session_route_options(1) 等。

## 2026-10-20 晚 后续轮（target-peak + 初始缓冲清黑）

已实施（全部工作区，未 commit）：
1. **亮部残余过曝**：`hdr_yuv_presentation_contract.dart` 新增 `targetPeak='1000'`；`hdr_player_backend.dart` 的 YUV 契约块在 `target-trc=pq` 后 owned 写入 `target-peak=1000`（读回校验、结束恢复）。测试同步：常量/写入/恢复断言 + fake 基线 `auto`。
2. **起播灰屏/灰条**：实机日志证明首帧 final-pass 已 `ready=1`，灰来自**离屏 FBO 未初始化**（1×1 占位拉伸 + pillarbox 未写），平台窗口清黑会被 final-pass 立刻覆盖。因此：
   - mpv fork `context_android.c` `yuv_diag_ensure_offscreen`：FBO 完整后 `ClearColor(0,0,0,1)+Clear`，1×1 占位与每次 resize 都清黑；
   - media-kit `surface_dataspace.cpp` 新增 `clearSurfaceBlack`（EGL，窗口格式匹配 config），`PlatformVideoView.surfaceCreated` 在 surface 事件前调用（防御首帧前灰屏）。
   - libmpv 增量重编 + llvm-strip + 重打持久 JAR，build.gradle sha 更新为 `f9205a77…`；APK 内 libmpv 与重编产物逐字节一致。
3. **实机（LG LGH870DS42e27764，dev APK）**：BV1vY4y1N7TY、BV1uZ4y1U7h8 均 `phase=applied presentation=nativeHdr vo=gpu-next hwdec=surfacetexture output=pq verified=true degrade=none`；`clearSurfaceBlack format=43 cleared=1 eglError=0x3000`；SF config49 层 `ACQUIRED/QUEUED` 持续轮转（呈现推进）；BV1T7（SDR）正常；三样片零 ANR/FATAL。证据 `/tmp/hdr-targetpeak-run.log`、`/tmp/hdr-fbo-run.log`。
4. **待人眼确认**：亮部过曝改善幅度、起播黑屏/灰条是否消失、滑动蓝屏是否仍在（本轮未专项取证）。
5. **契约测试现状**：media_kit_video 1012 过 / 8 失败 / 8 skip；8 项均为既有契约债（execution_catalog×2、route_planner、output_ownership、session_native_dv_policy、session_route_options、native_dv_session_observer、video_session disarm 计数），非本轮引入。

### 更正（同日深夜，灰屏排查停止）

上述第 2 项的「起播灰屏/灰条」并未修复。后续实机层栈证明主灰屏是 **Flutter 应用表面没有为平台视图挖出透明洞**（应用表面 `transparentRegion` 为空，页面背景盖住视频矩形）；PiliPlusX 同设备同路由（`baseLayerConvert/surfacetexture/platformView/pq/ext:lg-pq`）洞正常。本轮尝试的离屏 FBO 清黑、not-ready 黑帧、平台窗口 `clearSurfaceBlack`、HdrVideo/去外层 FittedBox、viewport、TLHC 入口、Z 序/可见性回退、Flutter 3.47.2 降级均未生效，已全部回退；仅保留用户确认有效的 `target-peak=1000`。JAR 已按上一轮 mpv 源重建（sha `c6d989f7…`）。完整证据、PiliPlusX 对照与待查假设见 PiliPlus `docs/plans/lg-hdr-gray-cover-investigation-20261020.md`。

## Archive Metadata
- date: 2026-10-20
- entry: piliplus-lg-hdr-lit-handoff-20261020
- agent: ZCode (GLM-5.3)
- project: media-kit / PiliPlus / mpv fork
- 前序：piliplus-lg-gray-veil-hdr-gate-20261020.md、piliplus-lg-yuv-carrier-execution-20261020.md
