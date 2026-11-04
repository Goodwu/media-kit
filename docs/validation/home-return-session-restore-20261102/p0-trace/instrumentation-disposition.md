# P0 插桩处置（instrumentation disposition）

日期：2026-11-03（插桩处置收尾 Worker；仓库 HEAD `761e29a8`，处置针对工作树）。

原始插桩快照：`instrumentation.diff`（618 行，P0 五文件取证插桩）。本文件记录每个文件每条 `MKS-HOME-TRACE` / 失败日志的最终去向：**删除 / 门控 / 保留**，以及验证证据。

## 处置总原则（plan §8）

- 删除无条件逐回调噪声行与相邻重复锚点；
- 保留授权/初始化**失败路径**的无条件 `Log.w`（内容经 `describeThrowable` 脱敏，raw token 永不出现在任何日志或 result）；
- 授权成功结果与其余时间轴锚点统一挂**默认关的诊断门** `HomeTrace.ENABLED`（新文件 `platformview/HomeTrace.java`）；
- 功能代码零改动：所有编辑仅包裹/移动/删除日志调用，控制流、状态机、channel 协议不变。

## 诊断门机制（HomeTrace）

- 文件：`media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/platformview/HomeTrace.java`（package-private，新文件）。
- `static final boolean ENABLED`：类加载时**只读一次** `android.os.SystemProperties.get("debug.mks.home_trace")`（hidden API，经反射读取以保持公共 SDK 可编译），`=="1"` 时开启；任何异常（含 JVM 宿主无此类）默认关闭。静态 final 缓存 + 调用点 `if (HomeTrace.ENABLED)` 包裹，关闭时热路径零字符串拼接开销。
- 开关方式：app 进程启动前 `adb shell setprop debug.mks.home_trace 1`；进程生命周期内固定（不再轮询）。
- `HomeTrace.emit(msg)` 即原 `PlatformVideoView.homeTrace` 的输出格式不变：`Log.i("MKS-HOME-TRACE", "rt=<epoch_ms> mono=<uptime_ms> tid= thr= java ...")`，与 `instrumentation.diff` 时期采集的 P0/R4 时间轴行格式兼容（`make_timeline.py`、`fast_interval_check.py`、`analyze_pp_round.py` 等解析器无需改动即可解析重开的诊断）。
- 所有门控行只输出 `tokenPresent=`/脱敏描述，**永不输出 raw owner token**。

## 逐文件处置

### 1. `platformview/PlatformVideoView.java`

原 `homeTrace` 静态方法**移除**（机制整体移入 `HomeTrace.java`）。

| 行（原 P0 锚点） | 处置 | 理由 |
|---|---|---|
| `setLgExperimentOwner enter`（owner tuple、tokenPresent、surfaceGeneration、wid） | 门控 | 冷启动初始化入口锚点，重开诊断仍需 |
| `setLgExperimentOwner exit ensureInitialized=skipped(no owner)` | 门控 | 无 owner 跳过路径锚点 |
| `setLgExperimentOwner exit ensureInitialized=ok` | 门控 | 冷启动初始化成功锚点 |
| `setLgExperimentOwner exit ensureInitialized=threw <redacted>` | 门控 | 时间轴版本；其旁**无条件** `Log.w("MKSURF","bridge init failed…"+redacted)` **保留**（原 HEAD 即有无条件 Log.w，本次仅追加脱敏描述） |
| `surfaceCreated enter`（generations/wid/disposed/tokenPresent 快照） | 门控 | 关键状态迁移锚点（P0 判定"surfaceCreated 不再初始化"依据） |
| `surfaceCreated … SurfaceFailed(initialDataSpaceRejected)` | 门控 | 失败发布锚点 |
| `surfaceCreated SurfaceAvailable begin/done` | 门控 | 括住 `onSurfaceEvent.accept`（含 channel 发送），P3 需测发送耗时 |
| `surfaceCreated exit`（函数尾） | **删除** | 与 begin/done 发送锚点相邻重复，无独立信息 |
| `surfaceDestroyed enter`（generations/wid 快照） | 门控 | 关键状态迁移锚点 |
| `surfaceDestroyed SurfaceDestroyed begin/done` | 门控 | 括住 destroy 事件发布 |
| `surfaceDestroyed exit` | **删除** | `sentEvent` 可由 send 锚点推得，相邻重复 |
| `dispose enter`（pendingSurfaceRefs 等） | 门控 | dispose 语义锚点 |
| `dispose sendSurfaceEvent=SurfaceDestroyed`（逐引用） | 门控 | 逐代际引用释放锚点 |
| `dispose exit` | **删除** | 纯出口标记，与 enter/逐引用锚点重复 |

保留不变（非插桩）：既有 `Log.i(TAG, "surfaceCreated/surfaceDestroyed/dispose…")` 等常规日志。

### 2. `platformview/PlatformVideoViewFactory.java`

| 行（原 P0 锚点） | 处置 | 理由 |
|---|---|---|
| `authorize enter`（request 身份、ownerTokenPresent） | 门控 | 授权入口锚点（"授权相关 trace"，挂诊断门） |
| `authorize result code/applicable/ok/ownerGeneration/surfaceGeneration/viewId/wid` | 门控 | 授权**成功/失败**结构化结果的时间轴锚点；channel 返回的 result map 本身是功能载荷，不受门控 |
| `factory.create enter`（creationSerial、tokenPresent、managedYuvCarrier） | 门控 | 视图创建入口锚点 |
| `factory.create view constructed` | **删除** | 与紧随的 `setLgExperimentOwner enter` 相邻重复 |
| `factory.create setLgExperimentOwner returned` | **删除** | 与后续锚点相邻重复 |
| `factory.create exit` | **删除** | `ViewCreated` 发送锚点已覆盖 |
| `factory surfaceEvent swallowed(controller terminated)` | 门控 | 事件吞噬路径锚点（P3 专项断言点） |
| `factory channel.invokeMethod SurfaceAvailable/SurfaceDestroyed` | 门控 | Java→Dart 事件发送点锚点 |
| `factory channel.invokeMethod ViewCreated` | 门控 | 创建意图发送点锚点 |

### 3. `MediaKitVideoPlugin.java`

无插桩日志（工作树 diff 仅含功能性的 `PlatformVideoView.AuthorizeBridgeActivation` channel case 分派）。**无需处置，零改动**。

### 4. `platformview/MediaCodecSurfaceTextureBridge.java`（cpp 侧同批）

**已回 HEAD**（前一轮完成，Lead 已核实 `git diff HEAD --stat` 为空）：native 侧 `mkst_lc_init/verify/create/shutdown` 进出、`window_active`、tid、EGL ctx 等全部 P0 临时插桩随 cpp/Bridge.java 还原删除；诊断能力由既有 `MKSURF:` 行保留。本次未再触碰。

### 5. Dart 侧（`android_video_controller/real.dart` 等）

Dart 追踪保持编译期 dart-define 门控 `bool.fromEnvironment('MEDIA_KIT_ANDROID_SURFACE_TIMELINE')`（`real.dart` `_surfaceTimeline`），默认关闭；P0 期间行为不变，本次未改动（该文件属 keyframe-resume PoC 工作包，不在本任务改动范围）。

## 诊断门与测试的交互（`tool/test_platform_bridge_activation.py`）

- JVM 宿主无 `android.os.SystemProperties`：测试桩表新增 `android/os/SystemProperties.java` 桩（`get()` 恒返回 `"1"`），使 `HomeTrace.ENABLED` 在宿主为 true——驱动因此**实跑**全部门控锚点，且全量 raw-token 红扫（`Log.RECORDS` × `RAW_TOKENS`）覆盖面比门控关闭时更宽（未削弱、反而加强；扫描逻辑与 result 断言零改动）。
- `REAL_SOURCES` 编译清单机械性追加 `HomeTrace.java`（javac 仅编译列出文件）。
- 结果：**20 scenarios / 560 checks PASS**（断言数量与门控前完全一致）。

## 验证证据（2026-11-03，本 Worker 实跑）

| 命令 | 结果 |
|---|---|
| `python3 tool/test_platform_bridge_activation.py` | `PASS: 20 activation scenarios, 560 checks (real plugin/factory/view/authorizer chain)` |
| `python3 media_kit_video/android/src/test/mkst_lifecycle_host_test.py` | `mkst lifecycle core: … passed`（init idem/refuse/rebind、create、verify-only、shutdown idem、latch refusal、竞态矩阵、forbidden 负锁） |
| `python3 tool/test_lya_diagnostics_delegate.py` | `PASS: 40 capability/lifecycle delegation cases` |
| `git diff HEAD --stat` | cpp / `MediaCodecSurfaceTextureBridge.java` **不出现**（grep 验证）；Java 三文件 + 新 `HomeTrace.java` |
| `git diff --check` | 干净 |

## 遗留与边界

- `HomeTrace.ENABLED` 进程生命周期固定；设备上验证重开诊断需重启 app 进程（setprop 在进程启动前）。
- 门控行的实机格式兼容性（`rt=/mono=` 双钟行）以 `emit()` 输出与 P0 完全一致保证；未在本次实机重跑（属 P3 复测范围）。
- 未提交 Git；keyframe-resume PoC 的 Dart 文件未触碰。
