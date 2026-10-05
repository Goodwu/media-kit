# ~/src 实验目录清理评估与 flutter-ohos-e3 归档

## Current State

2026-10-06：用户要求评估 `~/src` 下 8 个 OHOS E3 期目录的保留必要性（flutter-ohos-e3、
flutter-packages-e3、luna_flutter_e3/e4、luna_video_player_e3、luna-ohos-e1/e3、
PiliPlusX-e3，合计约 2.2G）。评估结论与最终决策：

- **全部保留，本轮不删除**。初轮建议删 6 个（约 1.19G），用户因另一会话在
  luna-ohos-e1 下找到早期测试经验叫停删除；目录处置留待后续统一。
- **flutter-ohos-e3 已完成未提交改动归档**（本轮唯一交付）：experiments 库提交
  `4a43068`，含 framework `TargetPlatform.ohos` 扫尾 patch（81 文件 +465/-110）、
  HCPP 输入阻断 epoch 变体 engine patch（9 文件 +1012/-147）、设计文档与契约测试
  脚本副本。两个 patch 经 `git apply --check --reverse` 校验与工作区逐字节一致。
  记录：`~/src/media-kit-experiments/ohos-flutter-e3-archive-20261006.md`。

关键事实（后续接手用）：

- flutter-ohos-e3 是 CPF-Flutter fork（基线 `4f1a4267`，分支 oh-3.44.9-dev，09-06
  clone 后 HEAD 未动），与本仓 CI/产品 patch 线的 openharmony-tpc `aa76d9bb` 不是
  同一 fork；产品 HCPP patch（media-kit-build 产品树 `tool/ohos/flutter_embedding/`，
  由 `PiliPlusX/scripts/prepare_ohos_embedding.py` 应用）**未覆盖** framework 扫尾
  与 epoch 方案，回溯以 experiments 归档为唯一依据。
- flutter-ohos-e3 是本机唯一 OHOS Flutter SDK：media-kit_test 本地 `pubspec.ohos.lock`
  再生（CI 注释要求 OHOS 工具链解析）与后续 OHOS 实验依赖它，1.1G 保留。
- luna-ohos-e3（59M）为 10-05 分支归一明确保留的 OHOS 工作树；未跟踪 32M
  libmpv.so 来源未对上 media-kit 追踪 zip，需要时从 ohos-native-build 重出。
- 5 个非 git 实验副本（luna_flutter_e3/e4、luna_video_player_e3、PiliPlusX-e3、
  flutter-packages-e3）与 luna-ohos-e1 均无版本化内容；E3 期结论在产品文档
  （media-kit-build 产品树 `docs/status/ohos-runtime-status.md`：Texture 基线可播放、
  HCPP 未验收不得默认启用）。

未提交推送（media-kit 本提交为登记性质；experiments 库无远端）。

## 评估过程摘录

- 依赖链：luna_flutter_e3/e4 与 PiliPlusX-e3 path 依赖 → luna-ohos-e3（media-kit
  旧检出，HEAD 已在 main 历史）+ flutter-ohos-e3；luna_video_player_e3 →
  flutter-packages-e3（video_player_ohos 对照路线）；luna-ohos-e1 为 E1 原生 ArkUI
  App 实验（108M 为构建产物）。
- flutter-ohos-e3 工作区 90 文件改动构成：framework 81 + engine 9（其中 3 个
  native 文件仅补行尾换行）；另有 2 个未跟踪文件（设计文档、契约测试脚本）。
- 全盘检索（media-kit/media-kit-build/media-kit-experiments/ConfigFiles）确认
  framework 扫尾与 epoch 变体无任何其它存档。
