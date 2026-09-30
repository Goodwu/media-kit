# media-kit 主仓合并上游 main 冲突策略评估（2026-09-30）

## 范围与方法

对 `fix/darwin-video-output-rebuild-barrier`（a8c7ac2d，233 提交领先分叉点）合并 `main`（d310049，上游 236 提交领先）做只读评估：`git merge-tree --write-tree` 得冲突树 `b6dc90b4`，从中统计冲突块并抽查语义。未产生任何合并提交。

## 总量：63 处冲突（52 content + 7 modify/delete + 2 rename/delete + 2 add/add）

### A 层：机械解决（约 35 处，半天）

- Flutter/Gradle 生成物与工具链元数据（generated_plugins.cmake、GeneratedPluginRegistrant、generated_plugin_registrant.cc、gradle-wrapper.properties、.metadata、Podfile.lock、gradle.properties、AndroidManifest、README.md 等）→ **全取 HEAD**（我方构建环境已实机验证定型）。
- pubspec 版本冲突（media_kit / media_kit_video / media_kit_test / video_player_media_kit / libs/universal×2 / overrides×2）→ **语义合并**：版本号随上游，本地路径/依赖 pin 保留我方。

### B 层：结构性决策（9 处，半天，含核对）

- **OHOS libs**（`libs/ohos/*` rename/delete、modify/delete）→ 假冲突：上游根本没有 OHOS 目录，系我方新增。**保留我方**。
- **`media_kit_test/android` groovy→kts**（app/build.gradle、build.gradle、settings.gradle deleted in HEAD）→ 我方已迁移 Kotlin DSL（`.kts`）。**保留我方 kts**，逐项核对上游 groovy 改动是否含需带入的依赖/插件更新。
- **`angle_surface_manager.cc/.h`**（deleted in HEAD, modified in main）→ 我方 Windows native output 重写已删。**维持删除**，核对上游改动无回归修复需移植；`windows/video_output.cc` 仅 1 冲突块。

### C 层：核心代码（17 文件、74 冲突块，1–2 天 + 审查）

| 文件 | 冲突块 | 性质与策略 |
|---|---|---|
| `media_kit/lib/src/player/native/player/real.dart` | 20 | 双侧同区不同功能：上游 shuffle 流/playlist 状态/screenshot 选项/seek 修复 vs 我方 dispose 屏障/严格属性/隔离执行。逐块双侧保留；**dispose 屏障语义（P3 实机验证过）为重点核对对象** |
| `android_video_controller/real.dart` | 8 | 上游 a7cec615 实为小重构（17+/54-），我方整篇重写（dataspace/PQ 事务/输出绑定机器）。**以我方为基底**，仅移植上游有价值修复的意图 |
| Java 三件（VideoOutput/Manager/Plugin） | 14 | 同上：我方大改 + 上游小改，我方为基底 |
| native_video_controller / platform_video_controller | 13 | 双侧加料，逐块合并 |
| initializer 系列 + execmem/temp_file | 8 | 我方 isolate 拆卸/NativeCallable 工作区，上游小改 |
| linux texture_gl/video_output、video_texture、player.dart | 10 | 逐块合并 |

**d310049（上游 android seek-to-position 修复）专项**：修复落在上游 `widListener` 的 wid 重配+seek 路径；我方重写后不再走该路径（P3 的 seek/重开验收 12639 已覆盖我方路径行为）。合并时需确认我方路径无同类「Surface 重配跳回开头」问题再决定是否吸收。

### 验证门槛（合并后，约半天设备轮次）

Dart analyze + Android JAR 链构建 + 例程构建通过后，复跑 P5 关键实机验收：颜色数值（Sol f240 ≤100）、片尾回退、EOS、直接 Engine 销毁、PQ 首帧；通过后 `main` 快进至合并结果成为唯一维护线。

## 结论

上游侧重 Android 的实际改动很小（重度改动是我方），风险集中在 `real.dart` 生命周期语义与 74 块的合并纪律，属**可执行但需专门排期**的任务（估 2–3 个工作日含实机回归）。近期发布（v2026.09）不受影响——发布链已固定在当前分支状态。
