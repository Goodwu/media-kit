# 架构审查整改（2026-09-30 起）

## Current State

- **任务**：按 `archives/reviews/goodwu-commits-architecture-review-20260930.md`（只读审查，P0×3 / P1×6 / P2×5）整改。整改按审查第 5 节投入产出顺序分批执行，每批独立提交。
- **批次进度**：
  - [x] 批次A（P2-3 止血）：OHOS 隔离入口 analyzer 排除（analysis_options.yaml 注明 CI 分工）、macos 契约测试缩进无关化修复、ci.yml 恢复 push→main 触发 package tests（手动分发保留按需开关）、ohos.yml 触发分支由已归档分支改为 main。验收：media_kit_video analyze 0 error（18 info/warning，与审查记录一致）、`flutter test` 全过（含先前加载失败的 macos 契约测试）。
  - [x] 批次B（P1-4）：`MpvOwnerBroker` 改为按 BinaryMessenger（引擎）分组登记（`HashMap<BinaryMessenger, HashSet<Long>>`），`onEngineDetach(messenger)` 只终结本引擎句柄，多引擎场景不再误杀；media_kit 新增公开窄接口 `NativeHandleLifecycle`（`observer` + `liveHandleAddresses`，`@internal` 通知方法）并从 `media_kit.dart` 导出，`InitializerNativeCallable` 私有注册字段移除，`mpv_owner_broker.dart` 改走公开 API（implementation_imports 消除）；登记/注销失败改为 debugPrint 显式可见。验收：两包 analyze 0 error、media_kit_video 13 个测试文件全过、JDK17 gradle `compileDebugJavaWithJavac` 通过。遗留（与审查一致）：多引擎行为未实机复验（原 P1-4 即代码路径推断）；音频宿主接线属长期项（需 media_kit_libs_android 原生层钩子）。
  - [x] 批次C（P0-1/P1-5）：① `surface_dataspace.cpp` 移除 LYA 私有 ABI（fingerprint + 偏移 0x98 perform op19）与全部诊断探针（late_pq/egl_hdr/vk_hdr），bridge 仅剩公开 NDK setter/getter 与 owner broker JNI；② `PlatformVideoView` 新增公开 `SurfaceDataSpaceExt` 扩展点（`applyDataSpace`/`onSurfaceAvailable`/`onDataSpaceApplyFailed`），`needsPqResetMonitoring` 由指纹门禁改为"已注册扩展 + SDK29 + pq + rgba1010102"；③ 私有 ABI 与探针原样迁入测试 App（`LyaPqDataSpaceExt.java` + `dataspace_ext.cpp`，指纹门禁留在 App 侧），MainActivity 注册；④ `Android.Capabilities`（含 eglInitialize/eglTerminate 默认 display 与 HEVC 解码器枚举）整体移入测试 App `CapabilitiesChannel`（`media_kit_test/capabilities` 通道），Dart 两处调用改走新通道；⑤ Android 控制器 MethodChannel 每消息 debugPrint 改 `kDebugMode` 门禁；⑥ MetalSurfaceBlitter 帧采样统计包进 `#if DEBUG`（release 不编译，debug 保留 PILIPLUSX_HDR_SAMPLE 能力）。验收：两包 analyze 0 error、media_kit_video 测试全过、gradle Java/Kotlin/原生编译通过、bridge .so 符号表仅余 4 个公开 JNI 函数、探针库含全部 LyaPq 符号（arm64 确认）、Swift parse 通过。遗留：P5 PQ 产品路径（12582 等验收）现依赖 App 侧注册扩展，需下轮实机回归确认行为等价（LYA 设备在位）；`MEDIA_KIT_*` fromEnvironment 开关归批次G处理。
  - [ ] 批次D（P0-2）：Goodwu libmpv release 发布并设为默认下载源；lock/CHANGELOG 记录 mpv/FFmpeg/libplacebo commit；CI 校验 JAR 版本标识。
  - [ ] 批次E（P0-3）：HdrOutputPolicy 提炼进 media_kit_video + 单测矩阵。
  - [ ] 批次F（P1-1/P1-2）：SurfaceOwnerLedger 抽取 + NativeOutputOwner 统一生命周期。
  - [ ] 批次G（P1-3/P1-6）：公开配置 API 收敛；Darwin DisplayLink 驱动 + 异步完成通知。
  - [ ] 批次H（P2-2/P2-4）：硬编码路径改环境变量、.vscode 忽略、测试 App 拆分（诊断平台另立）。
- **授权边界**：`git filter-repo` 仓库瘦身（P2-1）审查明确需要单独授权，本次整改不执行；Git LFS/证据外置的仓库结构调整同样待用户确认方案后另行处理。
- **整改原则**：不改已实机验收过的行为语义（P0–P5 验收结论依赖当前行为）；重构以"行为等价 + 可单测化"为门槛；每批提交前跑 analyze/test 回归。

## 关键依据（历史区）

- 审查文档对 OHOS 文件的裁定：`platform_view_video_ohos.dart` 仅被契约测试以文本引用，编译发生在隔离 OHOS 构建（flutter_ohos fork SDK）；方案 B（analyzer 排除 + CI 分工）为审查认可的整改路径。共享入口不泄漏 OHOS API 由 `test/platform_view_entry_contract_test.dart` 守护。
- macos 契约测试失败根因：上游合并（`a886f556`）改变 `video_texture.dart` 嵌套缩进深度，测试第 29-34 行按精确缩进逐字符匹配 `if (nativeSurface && ...)` 断裂；组合顺序本身（候选挂载→Texture 回退→激活挂载，736/764/773 行）未变。
- ci.yml 原状：package tests 仅 `pull_request || inputs.run_package_tests`；上游基准为 `on: [push, pull_request]` 无条件运行。
