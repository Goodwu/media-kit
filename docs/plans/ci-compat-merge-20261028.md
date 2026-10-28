# CI verified-native-packages + compat App 修复集成（2026-10-28）

## Review 与集成策略

原始分支：

- `ci/verified-native-packages-20261023` @ `d76622180dc9d082c9e690dd7d355f418627fb4a`，独有 5 提交，包含跨平台原生包校验/消费、Darwin 与 Win32 修复。
- `compat/piliplus-zero-change-20261018` @ `c8c5aaab3ee777bcf1f2b87166695a9814c24772`，独有 8 提交，包含 Android HDR、pre-29 解码器分类、原生构建校验、色彩诊断、HLG→PQ 参考亮度和启动跟踪清理。
- 共同祖先 `6de37476db0a55a2af7fc01348e33fc4eca04b78`。

采用**真正双亲 merge**，第一父为 CI，第二父为 compat。文件级审查表明，唯一双方都修改的文件为 `libs/android/media_kit_libs_android_video/android/build.gradle`。其余两侧独有修改逐文件完整保留，不覆盖整棵 Dart 目录、不丢失原生测试/证据与跨平台脚本。

## Gradle 唯一冲突的语义裁定

1. 采用 CI 机制分支的普通任务及 Gradle 7.5+ `providers.exec` 配置期验证（兼容 Gradle 9），显式 package 在失败时**禁止回退**下载发布件。
2. `MEDIA_KIT_NATIVE_PACKAGE_ROOT/MANIFEST/MANIFEST_SHA256` 三项中任一被定义，即进入显式验证路径；若同时提供 `mediaKitLocalArm64Jar`，按 CI 原保护逻辑直接报错。
3. 保留 compat 的 `-Pdev` 失败关闭策略，但兼容两种**显式**输入：受审 package，或本地构建的 `mediaKitLocalArm64Jar`。未提供两者时直接失败，不静默读取旧版发布包。
4. 非 dev、未提供显式 package 的正式发行构建继续执行原本带 SHA-256 的 pinned JAR 下载；老测试入口 `tool/build-android-test.sh` 的本地源码编译与 APK 三库一致性核验不变。
5. package 完整性≠源码新鲜度≠硬件实机通过；关注能力（如 demux-color getter、native DV bridge）时还需核对原生构建来源、manifest identity/capabilities 和设备证据。

## 需要执行的回归

- `python3 -m unittest discover -s tool/native_package/tests -v`（若有 Gradle 则运行配置期真实测试，验证 verified dev、无输入 dev 失败、本地 JAR dev、两个输入冲突）
- `python3 -m unittest tool.test_build_android_native tool.test_verify_android_test_apk -v`
- `cd media_kit_video && flutter pub get && flutter test test/hdr_route_planner_test.dart test/hdr_player_backend_output_ownership_test.dart test/hdr_video_session_test.dart test/playback_color_diagnostics_test.dart test/video_route_capabilities_test.dart`
- 合并分支与双方比较须 `behind_by=0`；双亲提交应能从两个分支完整追溯。
- Android LG API24/LYA API29 的 SDR/HDR10/P8.4/P5/HLG、横竖屏叠层与 pre-29 能力误灰须使用**本次新编译的整包**回归；仅历史设备证据不能充当本次集成验收。

## 保持不变的边界

本次没有重建、更新或验证原生 mpv 二进制。新 Dart 片源色彩诊断涉及 mpv 的 `current-tracks/video/demux-color-*` getter（参见 `8b548a2a` 中的原生依赖 `cd2995e1`）；正式包若仍使用旧 JAR，不能将“有 Dart API”宣称为“有片源码元数据”。

此合并只建立跨分支共享源码基线；不自动变更 `main`、不声称多平台 CI 或设备验证已经通过。
