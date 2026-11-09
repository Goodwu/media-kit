# HOME 返回后会话恢复失败（surfacetexture bridge 未重初始化）修复方案（2026-11-02）

状态：**P0 完成；A2 设计稿 V2 有条件可实施（C1–C5）；用户裁决 C5 = A + 显式重开（2026-11-02）；实施中（Java ∥ Dart 两工作包）。** 任务入口 `TASKS.md` → `HOME-RETURN-SESSION-RESTORE-20261102`；context `archives/conversations/home-return-session-restore-20261102.md`。

## 背景与已证前提

- 现象（LG G6 / API24 / DV P8.4 / hwdec=surfacetexture / platformView / gpu-next）：按 HOME 再返回后，mpv 新 VO `eglCreateWindowSurface ok` 约 90ms 后打印 `MKSURF: bridge not initialized (verify-only ensure_init; Java side owns init)`，随后解码回软解 `yuv420p10`，`hwdec-current='no'`、`route=rgb-final`、2 次 swap 后 `still=1`。表开（life22）与表+融合全关（home-control-tableoff）两轮签名一致 → 与 UV 表/融合无关，是独立的会话恢复缺陷。原始证据：`docs/validation/lg-p84-thermal-review-20261029/{life22-lifecycle,home-control-tableoff}/`。
- 注意：`yuv420p10` 只证明**软解**，日志仍报 BT.2020/PQ/DV，不能据此宣称已回 SDR 显示（critical review 修正）。

## 根因链（源码事实，已经 V2 逐条核实）

| # | 事实 | 位置 |
|---|---|---|
| 1 | HOME → Java `surfaceDestroyed` → Dart `SurfaceDestroyed` → `_detachPlatformSurface` → `_applyWidLocked('0')` 写 `vo=null/wid=0/vid=no`（`mpv_set_property_async` + await reply） | `PlatformVideoView.java:652-661`；`android_video_controller/real.dart:2049-2087, 865-950, 812-863` |
| 2 | mpv `UPDATE_VO` 回调同步执行 `uninit_video_out`：销毁 decoder → 销毁 VO 并 join → gpu-next 拆 hwdec → importer `uninit()` → `owns_decoder_window && mkst_shutdown()` | `player/video.c:129-148`、`vo.c:370-375`、`vo_gpu_next.c:4053-4065`、`hwdec_surfacetexture.c:506-544`（:531） |
| 3 | bridge `mkst_lc_shutdown_locked` 清 `initialized=false / owner_key=0 / generation=0` | `mediakit_surfacetexture_bridge.cpp:229-236, 996-1007` |
| 4 | 返回 → Java `surfaceCreated` `++surfaceGeneration`，只重 arm vendor YUV diag 对（故 `MKSURF-E1 dataspace applied` 仍成功），**不调** `MediaCodecSurfaceTextureBridge.ensureInitialized`；该初始化唯一入口 `setLgExperimentOwner` 仅在 `PlatformVideoViewFactory.create` 调一次，且传入的是 **controller/topology generation**（非 surfaceGeneration） | `PlatformVideoView.java:533-588, 368-389, 447`；`PlatformVideoViewFactory.java:249-260`；`real.dart:1466-1470` |
| 5 | Dart `SurfaceAvailable` → `_bindPlatformViewSurface`（先 stop 再 activate）→ 新 wid → 新 VO → `ra_hwdec_ctx_init` → importer `init()` → `ensure_init()` verify-only 返回 0 → fail-closed → 设备未注册 → vd_lavc 软解 | `real.dart:1179-1336（:1255-1282）`；`vo_gpu_next.c:4271-4279`；`hwdec_surfacetexture.c:435-499（:439-443）`；`vd_lavc.c:522-538, 672-679` |
| 6 | 回退：`hwdec_fail_count/hwdec_failed` 在 `uninit_avctx` 重置，重试还受 `attempted_hwdecs` 约束（`reinit()` 才清）。完整拆建 VO 会销毁 decoder，允许新尝试；**桥就绪本身不会让已存在的软解 decoder 自愈** | `vd_lavc.c:954-972, 711-746, 588-616` |
| 7 | 生产接线：PiliPlus 不显式传 token，`HdrVideoSession` 经 `AndroidHdrBackend.withManagedOutputOwner` 注入 `mk-owner-…` → 同一 creationParams 初始化机制。**同一 view 重建 Surface 则同缺陷条件；生产是否经 capability 处理重建整个 controller/view 尚未现场复现**（条件性推断） | `hdr_video_session.dart:215-219, 264`；`hdr_player_backend.dart:72-86`；PiliPlus `pl_player/controller.dart:102-109` |
| 8 | 日志中 `HdrErrorEvent(noDisplayCapabilityReport … LG single-open experiment rejects configuration controls)`：policy 消费调用方**原始** configuration，Lab 显式 token → `singleOpen=true` 拒绝；生产无显式 token 不走。不清桥，但会中止 Lab 的 capability 重规划——可能改变 Lab 恢复路径，非纯噪声 | `hdr_video_session.dart:273, 1640-1675`；`hdr_output_request_policy.dart:6-27` |
| 9 | 竞态可能：Java 发事件不等待 Dart/native teardown，快速返回时 `surfaceCreated` 可先于旧 VO shutdown；`mkst_lc_init` 在 `initialized && window_active && 不同 tuple` 时拒绝，同 tuple init 成功后会被随后的 shutdown 清掉。**既有日志证明后果，不证明 Java 时序** | `PlatformVideoViewFactory.java:308-310`；`real.dart:884-910`；`bridge.cpp:181-197, 229-235` |

App 侧（PiliPlus）返回后仅 `play()`（`pl_player/view/view.dart:352-360`，`.inactive` 即触发），无需也不存在重新协商动作；修复收敛在 media-kit SDK 层。

## 路线评审结论（V2 critical review，2026-11-02）

| 路线 | 结论 | 核心理由 |
|---|---|---|
| **A1** Java `surfaceCreated` 重 init + bridge supersede | **不批准** | ① generation 计数域混用：现 init 传 controller/topology generation，surfaceGeneration 每 view 从 0 起，"更高 generation 则 supersede" 无合法比较域（切全屏新 view 首 Surface=1 会被拒；同 Surface 再次拆建 VO 无新 surfaceCreated 授权）；② `mkst_shutdown(void)` 无参、桥单全局 `BridgeState`/布尔 `window_active`，无法按调用者区分 stale/当前窗口，闭合需"授权 tuple+窗口 tuple"双记录并继续拒绝第二窗口，否则改 ABI；③ "dispose 仍完整 shutdown"不是现状（Java 从不调桥 shutdown，`PlatformVideoView.java:372-380, 988-1001`），未消费授权会泄漏，需撤销语义。 |
| **A2 激活屏障版** Dart bind 事务内 stop ACK 后触发 Java init | **推荐** | 屏障天然存在：`_applyWidLocked` 走 `mpv_set_property_async` 并 await reply（`media_kit/.../player/native/player/real.dart:3125-3162`，默认 `async=true` `platform_player.dart:725`）；mpv 执行完属性后才 reply（`player/client.c:1302-1311`）；`vo/wid` 带 `UPDATE_VO`（`options.c:126,177`）同步跑 `uninit_video_out`→`vo_destroy` 并 join → importer uninit → `mkst_shutdown`。**await 成功 ⇒ 旧 VO 的 shutdown 已完成**。bind/detach 共用 controller `lock`（`real.dart:439/884/1198`），bind 自带 stop 前序（`:1255-1266`）。不需要同步 FFI，不改桥释放语义，不改 shutdown ABI。 |
| **B** 所有权整体挪到 Java、importer 只 acquire/release | **不选** | API24 `SurfaceTexture.detach/attachToGLContext` 存在但 LG 驱动迁移未实测；importer 仍删 OES 名/释放 ANW（`:517-544`），桥 `window_active` 不清则下次 create 被拒（`bridge.cpp:211-214`）；`uninit_video_out` 先销毁 decoder——跨 VO 保窗口也保不住 MediaCodec；改写契约最多。 |

其他被否候选：仅在 `surfaceDestroyed` 重 init（Java 回调先于异步 teardown，同 tuple 会被清、不同 tuple 被拒）；importer uninit 区分"换代/真销毁"（uninit 只收 `ra_hwdec*`，无销毁原因；若只跳过 shutdown 则窗口 active 而纹理已删）；destroy ACK 后再 init（需知后继 owner，旧 ACK 可能迟到，不优于 A2）；重建整个 controller/view（扩大所有权/review/capability 影响面，仅作恢复实验）。

## A2 激活屏障版：设计要点（据 P0 定稿后再过 V2）

1. **插入点**：`_bindPlatformViewSurface` 事务内，严格顺序 **停旧 producer 并拿到 ACK → 核验目标身份仍有效（viewId/surfaceGeneration/wid 与当前事件一致、controller 未 dispose）→ 经 method channel 请求 Java `ensureInitialized` → 写新 wid/vo**。注意 `_applyWidLocked` 第一步本身写 `vo=null`（`real.dart:833-850`），须把"停旧"与"激活新"显式拆开，不能只在调用前插一行。
2. **Java 侧授权入口**：新增/复用 channel 方法，**按完整身份**（owner token、viewId、surfaceGeneration、wid）定位目标 `PlatformVideoView` 并调用 `MediaCodecSurfaceTextureBridge.ensureInitialized(token, generation)`；不按 handle 找"最近 view"。generation 参数沿用 controller/topology generation 语义，surfaceGeneration 另作校验字段，**两个计数域不混用**。
3. **factory 提前 init 复查**：`PlatformVideoViewFactory.create` 的首次 init（`:260, 297-305`）与激活间隙的关系须明确：首次创建路径行为不变；仅"同一 view 的 Surface 重建"走新授权。
4. **失败封闭**：init 返回非 1、ACK 为负/超时、身份核验失败 → 不写新 wid、不发布"已绑定"，按既有 `SurfaceFailed`/错误链上报；不重试风暴。
5. **例外保持**：gpu-next fatal-cleanup-deferred 分支（`vo_gpu_next.c:4025-4048`）提前返回不拆 hwdec，ACK 不能伪装为资源已释放——该路径维持终止故障语义，不强行重绑。
6. **桥与 importer 不变**：`mkst_shutdown(void)` ABI、verify-only `ensure_init`、importer 独占释放、单活动窗口、Java 不调桥 shutdown、W2 "无 owner fail-closed / 显式授权" 契约全部保留。

### 不变量（实施与测试必须钉住）
- 任一时刻最多一个活动 decoder window；只有成功取得窗口的 importer 可释放；部分获取失败必清理；拒绝取得者不得清他人。
- Java 不释放活动 GL/JNI 消费端；native 不自行制造授权。
- controller generation 与 surfaceGeneration 分开校验；旧回调、旧 ACK 不得覆盖新输出。
- 测试覆盖：destroy/available 交错、bind 期间再次 destroy、同 Surface 重绑、全屏多 view 切换、dispose-before-create、部分 init 失败、重复 cleanup。

## P0 取证（已完成 2026-11-02，结论：实机时序支持静态链）

结果摘要（详见 `docs/validation/home-return-session-restore-20261102/p0-trace/summary.md`）：五轮（Lab 正常 ×1、Lab 快速 ×3、PiliPlus dev ×1）全部复现；`mkst_shutdown` 退出 → Dart `vo=null` ACK +64/+111/+84 ms（**屏障成立**）→ `wid=0` 链 +2.2–2.7 s → detach 释放锁；返回 `surfaceCreated` ≥1276 ms 后；HOME 后 `ensureInitialized` 0 次；同 view/同 ownerGeneration/同 token，仅 surfaceGeneration/wid 变；快速 HOME 下 `SurfaceAvailable` 在 detach 持锁期到达、bind 释放后 0–1 ms 拿锁、分支 `rebind boundWid=null stopPreviousFirst=false`——**缺入口非竞态**。R3 PiliPlus managed 宿主链路一致 → 生产受影响实机确认（软解为推断）。叙述修正："egl ok 后 90 ms" 为日志转发延迟。缺口：返回后帧推进未截图、`hwdec-current` 未进程外读、R2-2/3 起点已软解、Java 级快速间隔最小 1.28 s。

原始取证要求（保留备查）：

目的：把 Java / native bridge / Dart-mpv 三层事件放到同一时间轴，证实或推翻上表 #1-#9 与竞态假设。临时插桩统一前缀 `MKS-HOME-TRACE`（Java `PlatformVideoView`/`Factory`/`MediaCodecSurfaceTextureBridge`；native `mkst_lc_init/verify/create/shutdown` 进出含 tuple、`window_active`、tid、EGL ctx；Dart SurfaceEvent 到达、detach/bind 进出与拿锁、每个属性写 begin/ACK），不改控制流；mpv 侧优先用既有 `MKSURF:` 行。

轮次（LG 源码构建 Lab，全量 `exec-out logcat -d -v threadtime -b all`）：R1 正常 HOME ×1；R2 快速 HOME（<1s 返回）×3；R3 **普通 managed token/policy 宿主**正常 HOME ×1（Lab 无显式 token 场景，否则 PiliPlus dev 构建）。

必须回答：(1) `mkst_shutdown` 退出 vs Java `surfaceCreated` 先后与间隔（正常/快速）；(2) Dart `vo=null/wid=0` ACK 是否严格晚于 `mkst_shutdown` 退出（屏障成立性）；(3) 全程是否出现第二次 `ensureInitialized`；(4) factory init 与首个 `surfaceCreated` 先后；(5) 每事件身份值（controller generation / surfaceGeneration / viewId / wid）；(6) 快速 HOME 下 destroy/available 是否交错进入 bind 事务。目标序：`旧 shutdown 完成 < stop ACK < （新 init）< 新 create`。

产出：`docs/validation/home-return-session-restore-20261102/p0-trace/{R1,R2-1..3,R3}/{logcat-full.txt,timeline.md}`、`summary.md`、`build-identity.json`（APK SHA、三仓 HEAD 与 dirty 摘要、define 集）、`instrumentation.diff`。

## 验收门槛（实机）

- 返回后：无 `bridge not initialized`、无软解回退；`hwdec-current` 为 surfacetexture 硬解**实跑**；route decision 与 HOME 前一致；resume 后 `time-pos` 持续推进、swap/帧计数推进；真实 HDR 输出（dataspace/SF 层）与画面正常（用户观感）；同 PID；零 FATAL/ANR。**软解继续播放、或仅 report 陈旧 applied/verified 均不算通过。**
- 压力矩阵：快速 HOME/返回 ×5（<1s）、慢 ×3（10s）、暂停中 HOME、open 后立即 HOME、`continuePlayInBackground` 两态、全屏多 view 切换后 HOME。
- 生产默认（无表融合）下融合在新 VO 内重新 `committed` 推进（表为 VO 作用域，重建属预期）。
- PiliPlus 生产包：DV P8.4 HOME 返回 HDR 路由恢复 + 观感；SDR `mediacodec_embed` 路径回归不受影响。
- 全量：JVM/dart/tool 测试、analyze 零新增；V2 复审实施。

## 非阻断事项与既有问题（另列，不夹带）

- 材料修正：`life22-lifecycle/summary.json` `HOMEReturn: PASS / fusionResumed` 与 `home-round-logcat.txt:198,200` 冲突（committed 数据来自 HOME 前 :105-107）；`home-control-tableoff/summary.json` 的 "SDR fallback" 收窄为"软解回退"。本任务已改写。
- 既有问题（非本轮根因）：vendor managed arm `nativeArmYuvDiag` 后紧接 `nativeSetYuvDiagEnabled(1)` 把 owner tuple 清为 0/0（`lg_fw_adapter.cpp:352-363`，`LgPqDataSpaceExt.java:449-450`）；桥 SurfaceTexture 清理靠 GC、frame token 永不释放（`bridge.cpp:109-120, 1034-1044`）——连续多轮 HOME 需观察资源趋势。
- App 侧观察项：`pl_player/view/view.dart:351` 在 `.inactive` 即 resume（早于 `.resumed`），无证据不改。

## 复审触发条件

P0 时序与静态链不符；拟改 shutdown ABI / 单窗口约束 / Java GL 拆除；新增 supersede；跳过严格 ACK；放宽软解/HDR 通过门；把 A2 扩为跨 VO 保活——任一出现须重做 V2，不得沿用本次条件性推荐。

---

## 设计稿：A2 激活屏障版（Specialist，2026-11-02；状态：待 V2 复审，失败策略待用户裁决，默认按 A 送审）

### 设计摘要
- 保留既有停旧顺序，在激活新输出的首个 `vo=null` 成功 ACK 后，经 Java 重授权，再写新 `wid/vo/vid`。
- Java 按完整输出身份定位 view；桥初始化仍使用 **owner/controller generation**，不使用 surfaceGeneration。
- HOME、首次 bind、全屏换 view、同 Surface 再激活共用授权入口；不在 `surfaceCreated` 增加 init。
- 推荐严格 fail-closed（A）；降级继续（B）仅作待裁决选项，不能作为 HDR 恢复验收通过。
- 最小新增授权失败/降级状态接线，避免 HOME 后 `HdrOutputReport.verified` 保留成功假象。
- 不改 native bridge、mpv、shutdown ABI、窗口释放权；fatal-cleanup-deferred 明确排除恢复承诺。
- 引用基线为 media-kit **HEAD `761e29a8`**；工作树临时插桩不计入源码行号。

### 引用约定
- `C` = `media_kit_video/lib/src/video_controller/android_video_controller/real.dart`
- `J` = `media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/platformview/PlatformVideoView.java`
- `F` = `…/platformview/PlatformVideoViewFactory.java`
- `P` = `media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/MediaKitVideoPlugin.java`
- `B` = `…/platformview/MediaCodecSurfaceTextureBridge.java`
- `N` = `media_kit_video/android/src/main/cpp/mediakit_surfacetexture_bridge.cpp`
- `S` = `media_kit_video/lib/src/hdr/hdr_video_session.dart`；`H` = `…/hdr/hdr_player_backend.dart`；`R` = `…/hdr/hdr_output_report.dart`
- `M` = `media_kit/lib/src/player/native/player/real.dart`
- `I` = `~/src/mpv/video/out/hwdec/hwdec_surfacetexture.c`；`G` = `~/src/mpv/video/out/vo_gpu_next.c`

### 1. 插入点与事务拆分

**[设计建议]** 选择"`_applyWidLocked` 内插入授权阶段"，而非复制其属性写入代码：
1. 在 `C:812-815` 增加私有可选 activation guard/callback；在 `C:834-835` 首个 `vo=null` **成功 ACK 后**、`:836-850` 激活属性序列前执行。
2. 在 `_bindPlatformViewSurface` 的 `C:1282` 传入捕获 `incoming + outputIntentSerial` 的授权 callback；**不能在该调用之前直接 init**，否则其内部首个 `vo=null` 仍可能清掉授权。
3. `C:824-832` 可选 `vid=no` 前序、`:834` 停旧、`:838-846` 属性顺序及 seek 条件保持原样。`wid=0` 调用绝不授权。
4. 在 callback 前后及激活序列每次 await 后重检：controller 未 disposed/terminated、controller generation 一致、ledger live、完整 owner 与 output intent serial 仍匹配（身份依据 `C:1224-1230,1290-1292,965-979`）。
5. 在 `C:1282` 完成后、`:1283` 发布 bound 前再重检；过期事务不得写 Dart bound 身份或完成 waiter。

| bind 分支 | 执行顺序及依据 |
|---|---|
| `stopPreviousFirst=true` | 保留 `C:1255-1266` 完整旧输出 stop 与清 owner；随后 `C:1282` 内再次 `vo=null` ACK → 核验 → authorize → size/wid/vo/vid。保留重复 stop，不顺带改属性语义。 |
| HOME：`boundWid=null` | 不依赖"曾 detach 成功"的缓存证明；`C:1282 → :834` 自身仍提供 stop ACK，随后授权。P0 §3(6) 已确认该分支真实发生。 |
| 冷启首次 bind | 保留 `F:260` 提前 init，再在激活屏障内重复授权；同 token、同 ownerGeneration 对 `N:181-186` 为幂等 no-op。若中间发生 teardown，新调用负责重新绑定，不缓存"已 init"跳过。 |
| 同 Surface 再激活 | 真实 VO 重建仍须授权；`widListener` 的 `C:803-807` 对 token/surfacetexture PlatformView 捕获当前完整 owner 并走相同 helper。单纯尺寸更新 `C:744-747` 不拆 VO，不加授权。 |
| 已绑定重复事件 | `C:1232-1243` 没有 VO 重建，保持原 no-op。 |

**[设计建议]** 激活过程区分 `stopped / authorized / mayHaveWrittenWid / applied`，用于取消与失败清理：
- `C:1278` 的 in-flight 保留；它保护可能发生的部分 native 写入。
- 陈旧发生在新 wid 写入前：清除本次 in-flight，不发布、不报错、不启动 bind retry；活 Surface 仍留 ledger，只有 destroy/dispose 才授权 JNI release（`C:1204-1208`）。
- 陈旧发生在新 wid 已开始写入后：保留 in-flight/释放债务，先严格 stop，再按原 owner 生命周期回收；不释放仍可能被 mpv 引用的 Surface（`C:903-925`）。
- **[限制]** 主线程 Java 校验与 Dart 后续 native 写入不是跨语言原子操作；晚到 destroy 仍靠保留 JNI ref、in-flight 与 detach 串行化收尾，不宣称消除了所有瞬时激活。

### 2. Java 授权入口

**[设计建议]** 新方法 `PlatformVideoView.AuthorizeBridgeActivation`，沿用 `P:91` 的 `com.alexmercerind/media_kit_video` channel，在 `P:188-198` 同组分派到 factory。
- 参数：`handle`、`generation`、`viewId`、`surfaceGeneration`、`wid`；`handle/wid` 沿用现有 release channel 的编码方式（`P:224-240`）。
- 可选 `ownerToken`：若传入，必须与目标 view 的 `lgOwnerToken` 精确相等；不得把 token 写日志或回传。
- `generation` 明确表示 controller/topology generation；native 的参数取 **view 自身 `lgOwnerGeneration`**，请求值仅用于匹配。

**[事实]** `F:32` 的 `views` 仅按 handle 索引，不足以授权；完整 view 注册表为 `F:33,70-92` 的 `surfaceOwners[SurfaceOwner(handle,generation,viewId)]`，在 `F:263-264` 注册。

**[设计建议]** factory 新 `authorizeBridgeActivation(...)`：
1. 拒绝缺字段/非法类型；检查 `terminatedControllers`，按 `surfaceOwners` 精确找 view，不取"最近 view"。
2. 要求 `liveSurfaceGenerations[owner] == surfaceGeneration`，再进入 view 的同步检查/init 方法；注册表更新见 `F:289,301-305`。
3. view 检查 `!disposed`、handle/ownerGeneration/viewId 一致、`activeSurfaceGeneration == surfaceGeneration`、当前 `wid == requestedWid != 0`、`surfaceReferences[generation] == wid`、holder Surface 有效（`J:340-353,447-453,981-983`）。
4. `lgOwnerToken == null` 返回 `applicable=false, ok=true, code=notApplicable`，不得加载/初始化桥。空 token、非法 ownerGeneration 属无效授权。
5. 校验通过后同步调用共享私有 `_ensureOwnerBridgeInitialized()`；从 `J:381-388` 抽出实际 init，**不缓存 initialized 布尔值**。
6. `setLgExperimentOwner` 保留原"冷启异常记录但不抛出"的兼容行为；新授权入口把异常变成结构化失败，不吞掉。

返回结构：`{applicable, ok, ownerGeneration, surfaceGeneration, code}`，`code ∈ {ok, notApplicable, staleIdentity, invalidArguments, tokenMismatch, invalidOwner, initFailed}`。
- `staleIdentity` 包含 view 缺失、disposed/terminated、Surface 已变化；它不是可降级的 init 失败。
- `ok=true` 仅表示显式 init 成功，**不表示 decoder window 已创建、硬解已运行或 HDR verified**（`I:439-499`）。
- `B:95-113` 实际返回 `void`，通过异常报告失败；`1` 是 importer verify-only 的成功值，勿混淆。

**[事实/设计依据]** `P:91,137` 使用普通 MethodChannel（平台主线程）；新 handler 同步完成检查/init/result，不另开线程。JNI `nativeInit` 做 JNI 资源解析、锁与 tuple 状态绑定（`N:263-266,540-563,604-611`），不创建 GL texture，不要求当前 GL context；P0 §3(4) 的主线程 `mkst_init egl_ctx=0x0` 是已验证路径。**[推断]** HOME 同 view 保留 token/ownerGeneration → 同 tuple；shutdown 已清空时重新绑定，未清空时幂等（`N:181-197`）。

### 3. 失败策略、错误与 report 接线

**[待用户裁决，默认 A]** 推荐 **A：严格 fail-closed**。B 改变既有 V2 的失败封闭要求，须显式批准。

| 选择 | 行为 | waiter / 用户体验 / 验收 |
|---|---|---|
| **A：fail-closed（推荐）** | 当前有效身份的 `initFailed/tokenMismatch/invalidOwner` 或 channel 异常：不写新 wid、不发布 bound、产生 typed activation failure。 | `waitUntilCurrentOutputBound` 返回错误；PiliPlus 可能无视频/黑屏，但是明确错误而非静默卡住。符合"不冒充恢复"。 |
| B：降级继续 | 仅 stop ACK 成功、身份仍有效时，授权失败后继续原 wid/vo/vid；发布 **bound-but-degraded** 状态和错误。 | waiter 完成只代表绑定；现状常表现软解，继续有画面但无保证。必须 `verified=false`，不计入 HDR 恢复 PASS。 |

ACK 失败、staleIdentity、dispose、fatal 终止边界不适用 B；"降级"不能绕过停旧屏障或身份校验（`C:1255-1282`、`M:3141-3152`）。

**[事实]** 现有错误链：Java `SurfaceFailed/SurfaceRuntimeFailed` 发出点 `F:284-294`；Dart 接线 `C:1985-2045`；无 wid 失败走 `_markPlatformSurfaceFailed`，有 producer 的 runtime failure 还会 detach（`C:310-355,1997-2045`）；bind catch `C:1310-1327` 失败 waiter 后重建 completer 并安排重试；session 等待点 `S:252-258` 仅在相关流程执行，open catch 才发布 `HdrErrorEvent` 与 `verified=false`（`S:702-723`）——**HOME runtime 授权失败不会自动进入该 catch**。

**[设计建议]** 最小增量，不重构 `SurfaceRuntimeFailed`：
1. Android controller 增加 instance-scoped `ValueNotifier<BridgeActivationIssue?>`，payload `{owner: AndroidSurfaceAccountId, outputIntentSerial, kind: failed|degraded, code, error}`；在 `C:1282` 授权结果分类处写入。
2. 发布前验证当前 intent；旧 view/旧结果不得污染新 session。
3. A 新增专门 catch 分支，记录 `_pendingSurfaceFailure` 并保留可观察的 failed waiter；不照搬 `C:1316-1317` 立即换空 waiter。复用 `C:280-307` 的失败发布，下一真实 Surface attempt 才按 `C:257-276` 清理。
4. A/B 对相同 owner+intent 授权失败不自动 bind retry（防 `C:1325` 把永久 init 失败变重复 init）；现有非授权类属性错误重试保留。
5. session 在 `S:245-258` slot `publish` 接线当前 controller 的 notifier，异步取得 platform 后核验 controller 仍是当前 slot；订阅时回放已有 issue；替换/dispose 时解除订阅。
6. handler 用当前 session serial 发布 `HdrErrorEvent`，经 `S:1807-1817` generation gate；令 report `verified=false` 并记录 error/code。
7. 不把旧 `hwdecCurrent`、dataspace readback 当作当前证据；必要时构造新 report 清空观察字段（`R:149-189` 的 `copyWith(null)` **不会清空旧字段**）。
8. 成功授权/bound 不清除 unverified 结论；只有当前输出重新 review 才可恢复 verified。`S:623-640` 成功 report 写入须检查当前授权 issue。
9. B 还须在 `H:1495` review 入口读取当前 scoped issue，阻止该输出被判 verified。

**[待定]** 授权 channel 超时预算建议 5 s（独立于 `M:3146` 30 s 属性 ACK 与 `S:256` 10 s bind 等待）。超时不代表 Java 操作取消：保留原 Future，迟到回复不得激活或发布；未决期间禁止同 controller 再发授权。

### 4. 边界场景

| 场景 | 行为与依据 |
|---|---|
| bind 期间再次 `SurfaceDestroyed` | `C:2071-2084` 在等待 detach 锁前更新销毁意图；授权前后检查放弃陈旧事务。已开始 native 写入则保留 in-flight，严格 stop 后清理；Java 不提前删 JNI ref（`J:581-585,993-1000`）。 |
| dispose-before-create | 维持 `C:1212-1222`、`C:1950-1964` 释放路径；Java disposed/missing 返回 stale，不 init、不报新错误。 |
| 全屏新 view | `F:245-264` 原 factory init 不变；真正激活仍须 A2 授权。旧 view live 但已失去 Dart intent 时，迟到授权结果不激活、不释放活 Surface。 |
| 同 tuple 冷启/重复授权 | native 不新增窗口，只接受同 tuple；窗口创建仍独立受 gate（`N:181-197,211-220`）。 |
| `_applyWidLocked` ACK 负值/超时 | 严格 setter 抛出（`M:3136-3152`）；不运行授权 callback，不发布 bound；按既有 cleanup/retry（`C:923-927,1257-1265`）。迟到 ACK 不恢复已失败事务。 |
| 授权成功后部分激活失败 | 沿用 in-flight → stop → release；Java 不补偿性 shutdown。init 成功但未取得窗口不是窗口所有权（`I:451-460,522-536`）。 |
| 非 token / texture / mediacodec_embed | 授权门限于有非空 owner token、PlatformView、显式 surfacetexture 路由；其它调用不给 callback，原语义不变（`C:824-846,1477-1485,1524-1544`）。Java 无 token 直接 notApplicable。 |
| YUV arm / output resources | 不把 bridge init 当重新 arm；保留 `J:547-562` arm 顺序，不改 `hdr_yuv_window_arm.dart:563-604` 与 `hdr_output_resources.dart:1-13`。 |

**[显式 V2 边界] fatal-cleanup-deferred**：`G:4025-4048` 可在拆 hwdec 前提前 return，资源保留至进程退出——此时 **ACK 不是旧 bridge window 已释放的证明**。`window_active` 仍在时同 tuple init 由 `N:183-186` 幂等成功，随后 create 被 `N:211-214` 拒绝，importer 在 `I:445-448` 失败，拒绝者无 shutdown 权。本接口无可靠同步 fatal 状态；**不新增 native 查询、不 supersede、不强制清桥、不为该失败新增重试**。走既有 importer/decoder 失败链；本设计不覆盖该终止故障的恢复，目标"不劣于现状"。若要求 fatal 后禁止任何 bind 或必须同步上报，需另立契约。

### 5. 不变量对照表

| 原不变量 | 保证点 |
|---|---|
| 最多一个活动 decoder window | 不改 `N:211-220` create gate；Java init 不是 create；同 controller bind/detach 共锁（`C:439,884,1198`）。 |
| 仅成功取得窗口的 importer 可释放 | 不改 `I:451-460,522-536`；新 Java 方法无 shutdown。 |
| 部分获取失败必清理；拒绝者不得清别人 | 保留 importer partial-acquire 所有权；Dart partial activation 保留 in-flight（`C:1275-1279`）。 |
| Java 不释放活动 GL/JNI 消费端 | 新入口只 init；JNI 引用仍依 producer stop/ACK 回收（`J:665-680,988-1001`）。 |
| native 不自行制造授权 | 保留 `N:199-205` verify-only、`I:435-443`；授权仅由匹配 view 的 Java 方法发出。 |
| controller generation 与 surfaceGeneration 分离 | factory 查 `(handle,generation,viewId)`；view 校验 Surface 代数；init 传 `lgOwnerGeneration`（`F:70-92`、`J:349-352,447-450`）。 |
| 旧回调/旧 ACK 不覆盖新输出 | owner+intent 在授权前后、属性 await 后、bound/report 发布前验证（`C:242-255,1289-1292`、`S:1807-1817`）。 |

### 6. 测试清单与最低实机验证

**[事实]** 现有 Dart 测试基础：`test/platform_surface_release_test.dart:6-43`（fake channel）、`test/platform_video_view_dataspace_report_test.dart:7-29`（mock method handler）、`test/current_bound_output_identity_test.dart:13-34`、`test/surface_owner_ledger_test.dart:6-45,138-220`、`test/platform_view_entry_contract_test.dart:11`（lifecycle model，不能单独证明真实事务顺序）。

**Dart**：把 `_applyWidLocked` 真正使用的 stop/authorize/apply 协议抽为可注入 helper（不新写平行模型）；断言 `stop begin → stop ACK → authorize → success → wid/vo/vid`（旧输出分支与 HOME 空 bound 分支）；stop 未 ACK/负 ACK/超时 → 零 authorize/零新 wid/零 bound；授权期间 destroy/新 view/dispose → stale 放弃无风暴，部分写入后取消保留 cleanup 债务；staleIdentity/tokenMismatch/initFailed/异常/超时迟到成功分别覆盖；冷启重复授权、同 Surface 重建、重复已绑定事件、无 token/texture/embed 零新增 channel 调用；session：HOME 时无 active open waiter 仍发 `HdrErrorEvent`、清 verified，旧 controller issue 不污染新输出，成功 bound 不替代 review。

**JVM**（**[事实]** 本模块 `android/build.gradle:25-62` 未配置 JUnit/Robolectric；`android/src/test/mkst_lifecycle_host_test.py` 是 native host test；既有等价方式 `tool/test_lya_diagnostics_delegate.py:105-140`：JDK17 + Android stubs + javac 真实源码后运行）：新增 `tool/test_platform_bridge_activation.py`，stub JNI bridge 记录参数/模拟抛错；覆盖参数解析、完整身份匹配/逐字段不匹配、销毁后 retained owner、无 token、token 不匹配、Surface 无效、重复授权、异常映射；**断言传给 ensureInitialized 的是 ownerGeneration**（owner=7/surface=2 必须传 7）。

**最低实机验证**：复用 `p0-trace/run_round.sh:59-75` R1/R2，每次快速轮起点确认仍为硬解；返回后同 identity 时间链 `stop ACK < Java 授权成功 < importer ensure_init ready=1 < mkst_create_decoder_window ok < MediaCodec 创建`，随后无 `yuv420p10`、`hwdec-current=surfacetexture`、帧/swap/time-pos 推进；Java 级快速间隔实测须 <1 s；追加慢 ×3、快 ×5、暂停/open 立即 HOME、后台播放两态、全屏后 HOME；Lab 显式 token 与 PiliPlus managed token 均测；route/HDR dataspace/SF 层与观感符合原验收门、同 PID、无 FATAL/ANR。源码构建走 `tool/build-android-test.sh`。

### 7. 改动清单（推荐 A 估算，不含临时插桩）

| 文件 | 职责 | 预计行数 |
|---|---|---:|
| `C` | `_applyWidLocked`、bind、widListener、typed failure、scoped issue | 120–190 |
| `…/android_video_controller/bridge_activation.dart`（新） | 授权结果/issue 类型、可测试激活协议 | 90–140 |
| `P` | method channel 新 case | 20–30 |
| `F` | 完整 owner 查找与授权转发 | 25–45 |
| `J` | 抽共享 init、活动 Surface 核验、结构化结果 | 65–100 |
| `S` | 当前 controller issue 订阅/解绑、错误/report 门控 | 55–90 |
| `H` | 仅 B：review 拒绝 degraded verified | 10–25 |
| `test/bridge_activation_test.dart`（新）+ 既有测试 | 顺序、取消、失败/report 回归 | 220–350 |
| `tool/test_platform_bridge_activation.py`（新） | JVM 真实实现与 channel 适配测试 | 250–400 |

**明确不改**：`N`、`I`、`G` 及 mpv 其它源码；`mkst_shutdown(void)` ABI；importer shutdown 所有权；Java 不调桥 shutdown；YUV arm/资源结束协议；不重建整 controller 规避问题；`B` 功能签名不变。

### 8. 插桩处置建议

- 唯一差异清单 `p0-trace/instrumentation.diff`（`C/J/F/B/N` 五文件）；不得整体 reset。
- **P3 取证前保留**五文件临时插桩；新增 authorize begin/result/identity 与 stale-discard 锚点，复用 P0 时间轴。
- **可门控保留** `C` 的 stop begin/ACK、bind/detach 身份与阶段日志，统一挂既有 `MEDIA_KIT_ANDROID_SURFACE_TIMELINE`（`C:760-770`）；不记录 raw token。
- **Java 保留最小诊断**：授权结果 code/ownerGeneration/surfaceGeneration/viewId/wid；成功时间轴仅在显式诊断门开启；删除无条件逐回调噪声与重复 bridge enter/exit。
- **native 临时插桩最终删除**：功能提交 native 零变更；保留既有 MKSURF 日志。
- 更新 `J:372-375` 过时注释（"ensureInitialized 仅在 owner setter 调用"）。
- Worker 按 hunk 操作并保留 P0 原始 diff/日志；Reviewer 独立核验最终 native/mpv 无功能差异、诊断默认关闭。

## V2 复审结论（2026-11-02）：有条件可实施，C1–C5

声称核实：§1 插入点/屏障、§2 factory 注册表与 view 身份字段/channel/JNI 无 GL 要求、§3 既有错误链、§4 destroy/dispose/全屏/YUV arm 独立、P0 R2-1 原始日志（`logcat-full.txt:1306-1321` shutdown 退出后 64ms 才 ACK；`:1565-1579` detach 释放后空 bound 分支再 stop）——**全部确认**。勘误与硬条件：

- **C1（闭合停止后状态）**：同 Surface/widListener 授权失败后，`_failPlatformSurfaceIfNoAlternative → _promoteCompatibleBoundFallback`（`C:219-237`）**不检查 bindFailed**，可把失败 owner 重新完成 waiter；重复已绑定事件（`C:1232-1243`）也可清失败。必须清除已停止的确认绑定或加不可提升状态，widListener 同样覆盖；保留活 Surface JNI 引用。
- **C2（issue/review/输出共享作用域）**：最低键 = controller 实例 + 完整 owner + intent/激活 epoch；回放与每次处理重检。仅用当前 `_serial` 发事件挡不住旧 issue 标成新 session（`S:1816` 不足）。规定清除/替换/历史失效：新真实 attempt 使旧 issue 不再阻断新输出，但**不能直接恢复 verified**；同 owner/intent 重复失败不重试不重复发布。成功 report 不仅要查"有无 issue"，还要确认 review 对应的输出/激活 epoch 未变（旧 review 可在新 Surface 成功绑定后返回旧证据）。
- **C3（订阅与超时生命周期）**：publish(null) 立即解绑；异步 platform 完成后检查订阅 epoch/当前 slot/disposed；session dispose 开始即解绑；5s channel timeout **不能取消 JNI 或防主线程 ANR**，未决闸门的解除规则必须明确（不留永远 pending waiter）。
- **C4（执行级测试）**：widListener 授权失败零虚假 bound/零 fallback 提升；ViewCreated 已到新 Surface 未到、旧 ACK 迟到；每个 await 切点取消（wid 已提交未 ACK、vo 激活后、listener seek 期间）；并行 open 与 HOME 交错、issue 回放与 slot 替换交错；channel timeout 迟到失败/成功/永不返回/新 Surface 到来；Managed/Routed 集成测试区分 open 失败与 HOME runtime 失败（fallback 开关、ready、play 实际行为）；Java 加 terminated retained owner、释放后有效 holder、整数溢出、owner=7/surface=2 传 7、无 token 零 init。host javac+stubs 可行但**完整夹具未证明可编译**，必须执行真实参数解析/factory 定位/view 校验，不能只测抽出模型；原 native lifecycle/partial-acquire 测试保留。P0 脚本未实现 Java 级 <1s 快速返回，需改进驱动并实测。
- **C5（用户裁决，未裁决不得默认批准）**：**A 在 PiliPlus 的真实后果 = 黑屏/冻结直至显式 reopen**——App `onError` 仅 debugPrint（App:119-121）；legacy fallback 仅在 `await route.open` 抛错且 `allowLegacyFallback=true`（默认 false）时进入（Managed:180-221、data_source.dart:14,22）；HOME runtime issue 只走 report → Routed.errors → onError，**不进 open catch**；report unverified 后 `Routed.ready=false` → `play()` 的 `_applyIntent`（279-285）直接退出。**B 同样不能保证"继续播放"**（清 verified 后 play 意图同样被 ready 门拦截）。若要自动恢复，须先补有界恢复契约（另设计另审）。

其他勘误（实施时执行）：
- `surfaceReferences` 的键是 **surfaceGeneration**，不能误用 controller generation；参数解析拒绝浮点/截断/溢出；对预期 token/surfacetexture 路由，`notApplicable` 不得当授权成功（两端契约不一致）。
- fatal-cleanup-deferred "不劣于现状"仅限**同 tuple 且已有活动窗口**子情形；不同 tuple 时新入口更早 fail-closed（A 不写 wid），是行为差异非完全等价；不得把"资源行为不劣于现状"写成"状态可信性已解决"。
- §前半"仅同 view 重建走新授权"与末尾"所有实际激活走授权"矛盾——**以后者为准**：全部实际进入 `_applyWidLocked` 的非零激活分支都走授权，但 SurfaceProducer 准备（`C:668`）、texture 首绑（`C:1537`）、dispose（`C:1696`）等调用点不得误加；`wid=0` 在 helper 内硬性禁止授权。
- 正常 HOME 授权成功不触发 session review，verified 仍描述 HOME 前输出——本次只承诺"授权失败清 verified"，验收靠新鲜硬解/帧/HDR 证据。
- seek 语义：正常 bind 不新增 seek，listener 原 seek 保留并纳入失效检查；`androidAttachSurfaceAfterVideoParameters` 无 Android 消费点，不依赖、不顺带修。Slot（`hdr_output_slot.dart:67-117`）的 waitReady 失败重建是真实恢复入口，订阅/issue 必须覆盖。
- bridge 进程单全局、controller lock 非跨 controller 互斥；多 session 并发恢复不在本次结论内。raw token 不进日志。

**重做 V2 触发**：引入 supersede、shutdown/单窗口语义变化、跨 controller 授权承诺、放宽 ACK、自动恢复重开、B 降级策略、fatal 恢复承诺，或实测时序推翻屏障。

### 实施复核检查点（设计级 V2 给出，实施级复审逐项核对）
- [ ] 严格顺序 stop ACK → 身份复验 → authorize → size/wid/vo/vid；wid=0 零授权。
- [ ] 所有调用者门控正确；旧 view、迟到结果、无 token、**非 surfacetexture 路由**不会误激活。
- [ ] 停止后不存在虚假 bound 或 fallback 提升；部分写入债务不提前释放（bind 与 widListener 两路径）。
- [ ] notifier/report/waiter 同作用域（controller+owner+intent/activationEpoch），旧 review 不覆盖新输出，失败无重试风暴。
- [ ] 用户体验与 A 裁决一致，runtime 错误不被误称自动 legacy 恢复。
- [ ] 真源码测试通过，实机新鲜证据满足原验收门，native/mpv 无功能修改，日志无 raw token。

## 实施级 V2 复审（2026-11-02 晚）：修复后通过；当前版本不作 P3 验收候选

**确认成立**：首个 `vo=null` ACK 后授权（`real.dart:912-923`，`bridge_activation.dart:393-423` 硬排 wid=0）；无 callback 调用方零变化；普通 bind 硬失败的 C1（保留 in-flight → `_promoteCompatibleBoundFallback:242` 返回 false，waiter completed-with-error 不换 Completer，无 retry）；失败 report 构造新对象清观察字段；订阅生命周期与 5 s 闸门三结局解除、迟到回复不激活；Java 严格解析/精确定位/`surfaceReferences[surfaceGeneration]`/无缓存 init/零 shutdown；contract 六键七码对齐；`bridge.cpp` 与 `MediaCodecSurfaceTextureBridge.java` 完整 diff 与 P0 `instrumentation.diff` 精确相等（功能零变更）；mpv 工作树干净。

**阻断（修复后复审）**：
- **B1 授权门越界**：`real.dart:945-947` 门限仅 `usePlatformView && token != null`；session 对所有 Android 会话注 token（`hdr_video_session.dart:217-221`）、`hdr_output_contract.dart:68-85` 每路线保留 token → managed `mediacodec_embed` 等非桥 PlatformView 路线被新增授权与 fail-closed。修：门限加"真实目标 hwdec == surfacetexture"，补零授权测试（embed/非 surfacetexture GPU/texture/无 token）。
- **B2 widListener 事务不完整**：`real.dart:850-864` 未 invalidate/markInFlight（授权悬挂期 `waitUntilCurrentOutputBound:169-173` 可立即成功）；`:873-874` best-effort stop 吞失败（`:886-892`）后无条件清 owner → 部分激活债务丢失，detach（`:1164-1185`）可不 stop 直接释放 JNI；seek await 后（`:934`）无复检；同 Surface stale-before-wid（`:1541-1546` 保留 bound 而 `:1030-1033` 清 in-flight）可让 `:241-259` 提升已停止旧 owner。
- **B3 C2 作用域与旧 review**：`isCurrentBridgeActivationIssue`（`:1119-1123`）只核 controller/disposed/epoch，缺 owner/intent/latest-view/terminated；`hdr_video_session.dart:624-665` 成功 report 只查"当前有无 issue"，未捕获并比较 review 所属 controller+owner+activationEpoch → 旧 review 可在新 attempt 使旧 issue 失效后写回 verified 并复用旧证据；epoch 递增点应移至实际 channel 派发处（`bridge_activation.dart:473`）。
- **B4 C4 不足**：`surface_owner_ledger_test.dart:238-271` 仅账本断言，不执行 promote/waiter/widListener；`hdr_video_session_test.dart:2642-2654` 用手动布尔替代真实 currency；`:2578-2623` 未测交错。须补：真实 controller 路径（listener 失败、pending waiter、fallback 提升、重复事件、严格 stop 失败后 JNI 不释放）、held ACK 系列、旧 review+新 epoch 交错、platform 未解析时 replace/dispose、真实 Slot waitReady 重建、Java（release 后有效 holder 拒绝、registry 与 views 冲突、兜底 Throwable、无 token+wid=0）。

**条件项（最终收口前）**：Dart 解析严格化（`bridge_activation.dart:148-210` 允许缺 generation/message、接受整数值 double、`isOk` 不查 applicable、不比较返回代数）并补 Java 真实 `notApplicable={applicable:false, ok:true}` 组合测试；日志脱敏（`PlatformVideoView.java:411-413` 冷启 catch 原样输出 Throwable；JVM 测试 token 相等断言失败会打印实际值；Log stub 应捕获日志断言）；修复后补真实执行记录/构建身份/analyze 基线对照/唯一失败基线证明。**契约措辞收窄**：wid=0 仅在 view 有 token 时返回 staleIdentity；无 token 时 notApplicable 优先（Dart 本地硬禁 wid=0，实际不可达）。

**建议项**：修正 "ok=true only for code=ok" 注释（notApplicable 返回 ok=true/applicable=false）；顺序测试改共享事件序列断言；最终提交前移除 native 插桩、门控 Java 成功日志并做无插桩回归。

**P3 后最终收口核验**：修后源码构建身份；每轮新鲜硬解起点且同 identity `stop ACK < authorize ok < verify ready=1 < decoder window < MediaCodec 实跑`；快速 ×5 Java 实测 <1 s、慢 ×3、暂停、open 后立即、后台两态、全屏多 view；实时 hwdec-current/time-pos/帧/swap + SF/dataspace + 观感；真授权失败不自动重开、ready=false、显式 reopen 可恢复、Slot 失败重建；managed `mediacodec_embed`/无 token/texture 零新增授权；同 PID、零 FATAL/ANR、多轮资源趋势；插桩处置后 native/mpv 零差异、日志脱敏。
