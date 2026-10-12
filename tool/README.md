# tool/ 使用说明

## 目标 App（2026-10-01 起）

HDR/验收轮次脚本（`matrix-*`、`merge-accept-*`、`decode-probe-round`）构建并操作 **`media_kit_hdr_lab`**（包名 `com.example.media_kit_hdr_lab`）——诊断 App 拆分自 media_kit_test（见 P2-4 整改）。`media_kit_test` 已还原为上游示例 App，不再承载 AUTO/HDR define 面。

## 环境变量（脚本不含本机路径/设备序列号）

- `ANDROID_SERIAL` — 目标设备序列号；未设置时使用 `adb` 唯一连接设备。
- `MEDIA_KIT_ORIGINAL_APK` — 轮次结束要恢复的原包路径（必填，按轮次环境设置）。
- `MEDIA_KIT_TEST_CLIPS` — 测试 App 本地素材根目录（macOS 本地源、对照片）。

Android 实机验收与构建链的常用脚本。2026-09-30 起把此前散落在 `/tmp` 的可复用脚本收编至此（原轮次记录见 `archives/experiments/`）；`/tmp` 重启即清，脚本产物（日志/截图）默认仍写 `/tmp/<tag>-*`，重要证据须及时归档到 `archives/experiments/artifacts/`。

## 构建链

### `build-android-test.sh` — 测试版默认构建（最新源码）

**测试版构建的默认入口**：从最新源码构建 libmpv JAR 并构建 Android 测试 APK。三步全自动化——①ninja 增量编译 `~/src/mpv/_build-arm64-mks`（media-kit/android HEAD，含未推送提交）；②`build-mks-r1.py` 历史链接配方 + genbump token 重指 → strip → 换装 r22 钉定基础 JAR（helper 库保持钉定），产出带 `native-candidate.json` 溯源的 JAR；③经 gradle 内建 `ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 属性（`media_kit_libs_android_video/android/build.gradle` 正式支持的本地 JAR 验证通道，非文件系统 hack）构建 APK。JAR-only 阶段可用管线环境开关 `MKS_SKIP_APK=1`。

```
tool/build-android-test.sh --tag mytest --local-source /data/local/tmp/media-kit-p5-mystery-box.mp4
tool/build-android-test.sh --tag mytest-pv --platform-view --local-source /data/local/tmp/media-kit-hdr10-full.mp4
```

产物：`media_kit_hdr_lab/build/app/outputs/flutter-apk/<tag>-release.apk` + 同名构建日志；JAR/溯源在 `~/src/media-kit-build/lg-api24/lg-api24-realtime-gpu-mks-<tag>-build/`。发布构建不走此脚本（gradle 钉定下载链保持默认）。

### `matrix-build.sh` — 受审 native 输入的八行路由矩阵

沿用 PR #5 的矩阵运行职责，改为 P5/P8.4/HDR10/HLG × `MEDIA_KIT_ANDROID_HDR_GATE_OPEN=true/false` 八个 serial `media_kit_hdr_lab` APK。gate=false 行对应 Lab `allowExperimental=false`；gate=true 行对应 Lab `allowExperimental=true`。八行均将独立的 `MEDIA_KIT_ANDROID_HDR_POLICY_EXPERIMENTAL=false` 固定，避免 P8.4 元数据路线重排；这不覆盖 gate=true 的准入语义。receipt 分别记录 `allowExperimental` 和 `hdrPolicyExperimental`。以 `--target-platform android-arm64` 和 `mediaKitArm64Only=true` 构建。实验 SurfaceTexture define 不传；矩阵不强制 decoder、VO、颜色 hint 或 LG YUV 路线。App 产品默认仍 false，矩阵不改变产品默认值。

入口要求 App 精确 checkout、空输出目录、Flutter、JDK、Android SDK、`llvm-readelf`、`llvm-nm`、`apksigner`、`ffprobe` 和四种真实 fixture 的证据文件：

```sh
tool/matrix-build.sh \
  --app-root /path/to/PiliPlusX \
  --output /absolute/path/to/new-empty-matrix-dir \
  --flutter /path/to/flutter/bin/flutter \
  --java-home /path/to/jdk \
  --android-sdk /path/to/android-sdk \
  --bootstrap-dir /path/to/current/private-bootstrap-receipts \
  --readelf /path/to/ndk/llvm-readelf \
  --nm /path/to/ndk/llvm-nm \
  --apksigner /path/to/android-sdk/build-tools/VERSION/apksigner \
  --ffprobe /path/to/ffprobe \
  --fixtures /path/to/verified-fixtures.json
```

`--fixtures` 是 JSON 对象：`schemaVersion: 1`，`fixtures` 恰含 `p5`、`p84`、`hdr10`、`hlg` 四项。每项字段为 `path`（本机真实媒体文件）、`sha256`（当前 lab 字节身份表中的摘要）、`devicePath`（`/data/local/tmp/media-kit-<kind>-<suffix>.mp4`）、`probeEvidence`（先前探测 JSON）。sidecar 形如 `{"schemaVersion":1,"fixtureSha256":"...","probe":{...}}`。工具会用指定 `ffprobe` 对本机文件实际运行 `-show_streams -show_format`，记录命令、输出摘要，并要求其 stream 语义投影与 SHA 绑定 sidecar 一致；sidecar 不能替代实际探测。P5 以实际 DOVI profile 5/compatibility 0/EL=false/RPU与BL存在分类；颜色 VUI 可以缺失，但存在时不能矛盾。P8.4 要求 profile 8/compatibility 4/EL=false/RPU与BL存在、HLG兼容 transfer 及 BT.2020 primaries/matrix；HDR10/HLG分别要求无DOVI、PQ/HLG transfer和BT.2020。未知或冲突均在 prebuild 拒绝。字节身份表仍是独立准入门；未收录的实测文件（包括 review 中报告的未知 P5 SHA）不会因 ffprobe 分类正确而自动进入表。

`--bootstrap-dir` 必须是同一 runner 产生的受审 bootstrap 输出目录，含 `bootstrap.json`、`source-resolution-before.json` 和 `patched-sdk-diff.log`。脚本检查 bootstrap 的 App/media-kit HEAD/tree 与当前 tracking remote，调用现有 `prepare_routing_ci.py --finalize` 再核 package/source freshness，要求当前 `--flutter` 正是 receipt 中打过 SDK/package 补丁的私有 SDK，并记录 patch 输入、SDK commit/tree/diff。`verify_routing_sources.py` 也会在真实 App checkout 上核对 App package_config。

在该前置通过后，脚本把精确 media-kit Git tree archive 到输出副本；每行从这个 archive 复制独立完整源码副本，在副本内执行自己的 `flutter pub get`，并将 `PUB_CACHE` 指向该行新建的专属缓存，避免前一行插件 `.cxx` 输出成为下一行输入。package_config 必须逐包绑定十个 media-kit library 与它自己的 `media_kit_hdr_lab` pubspec/source；其他 package 只能来自该行副本、专属 pub cache 或私有 Flutter SDK。构建调用使用 Flutter 支持的正常 lab 输出目录和 `--no-pub`，每行只从新副本的 `build/app/outputs/flutter-apk/app-release.apk` 取 APK，不传无效 `--build-dir`，也不从旧行或源 checkout 回退。Git archive 的逐路径 blob、普通文件/链接类型及执行模式在 pub get 前后和构建后复核；pub get 修改原 tracked 文件、删除文件或新增未认可源码均拒绝，不能重抓变化后的基线。所有已解析依赖包的 asset/font/shader 另行按实际声明冻结内容，优先于普通输出目录排除（例如依赖的合法 `build/review.bin`），资源 URI 与 `packages/<name>/...` 按实际 Flutter 的 packageUriRoot 解析并绑定精确包内目标；沿当前 SDK `asset.dart` 的一层 resolution variant 规则同时冻结隐式成员及集合变化；目录 asset 只读取直接文件及其真实 variants，不把整个依赖 `build/` 的 Gradle 子树视为资源。fonts 保持实际文件语义。遗漏、跨包逃逸、循环链接或读取错误均失败。资源声明通过 App 原有 `prepare_android_variant.py` 和锁定 yaml 3.1.3 的实际 Dart parser 解析；生成文件、根输出目录及按包绑定的 plugin symlink 使用精确路径契约，`assets/build/` 仍作为资源输入。构建前后冻结比较该行 package_config、pubspec/lock、resolved package roots及全部源码/resource/generator文件树。

脚本通过 App 精确 checkout 的原有 `acquire_routing_native_inputs.py` 读取固定 CORE accepted ledger，并调用原 `verify_routing_native_inputs.py` 验证选中 artifact；空 selector 在 Flutter APK build 前拒绝。App verifier 保持对 APK 中受审 JAR 三成员的原始哈希/ELF门。矩阵再从接受的 JAR manifest、Flutter engine/AOT 契约、当前 lab/依赖 Android Gradle 实际配置引用的 CMake shared targets 与 arm64 `jniLibs` 源输入推导 APK native closure（当前七成员，包括 `libmedia_kit_dataspace_vendor.so`）；按 Lab 的真实 `build/<project name>` 重定向及各精确模块 `.cxx` 查找当前输出；未知 native member、foreign ABI、非 ELF64/AArch64/DYN、缺少当前 SDK engine/本行 AOT/CMake 输出逐项拒绝。接受 native 输入后实际执行 Android precache，再冻结 engine cache、Dart/compiler/tool snapshot、engine.version/stamp 和 SDK tools config/lock；SDK Git patch 与被忽略的 engine 字节在每行构建前后重新核对；合法 SDK 内部目录/父路径链接同时绑定 link、canonical target 及递归实际内容，拒绝逃逸、循环和读取失败。YAML parser/锁及实现哈希同时复核。每行 AOT 绑定该行精确 archive、defines、构建命令及冻结输入；不同 defines 的 AOT 不要求相同字节，JAR 三成员仍严格相同。receipt 分别记录 JAR、SDK engine、Flutter AOT 和每个 lab/vendor native member 的真实来源和 SHA，并记录 apksigner证书；八行证书必须一致。APK、日志和最终/失败 `matrix-receipt.json` 写入各行隔离目录，最终全绿状态也会持久写回磁盘。命令失败保留部分 receipt 并立即以失败码退出。可用空间低于 512 MiB 时拒绝启动下一条命令；工具不删除任何缓存。

receipt 将 `localContentVerified=true` 与 `deviceFixtureVerified=false` 分开记录；脚本不运行 adb、不安装、不播放，也不宣称画面/HDR/性能验收。DEVICE 后续须在实机核对文件映射，再单独完成真实 Session、可见输出和持续播放验收。PR #5 原脚本来源/哈希见 `docs/plans/core-pr5-script-inventory-20261012.json`；其中 `assemble-jar-arm64.sh` 是 native bundler 的重复配方，不在此导入，由 DV001 原配方唯一维护。

### `mk-pack-jar.sh <src.jar> <new_libmpv.so> <out.jar>` — JAR 重打包

解开既有 arm64 JAR、替换 `lib/arm64-v8a/libmpv.so` 后重新压缩并打印 SHA-256。用于只换了 libmpv.so、其余依赖不变的场景；全量重建仍走 NDK 构建链。

## 设备轮次脚本

共同流程：安装指定 APK → 唤醒解锁 → 关自动亮度/最高亮度 → 起 logcat → 启动 app 打开素材 → 定时截图（30/45/90/150/240s，45s 处另存 SurfaceFlinger dump）→ 关键证据 grep → BACK 退出并恢复设备原状态（trap 保证中断也恢复）。

**换设备前必查的硬编码项**（Redmi 轮教训）：`serial`、恢复用的原 APK 路径、tap 坐标（竖屏/横屏中心不同）、解锁校验字段（EMUI 用 `isStatusBarKeyguard`，AOSP 用 `isKeyguardShowing`）、恢复亮度值。

| 脚本 | 设备 | 说明 |
| --- | --- | --- |
| `matrix-round.sh <apk> <tag> <dur> <sample_enum>` | 目标设备（`ANDROID_SERIAL`） | 标准播放轮；结束恢复 `MEDIA_KIT_ORIGINAL_APK` |
| `matrix-round-jason.sh <apk> <tag> <dur> <sample_enum>` | Mi Note 3（`5b79aada`） | 含旋转竞态修正：tap 后验证 `ANDROID_DIRECT_OPEN trigger`，未命中换横/竖坐标重试；结束卸载测试包、亮度恢复 50 |
| `matrix-round-ugg.sh <apk> <tag> <dur> <sample_enum>` | Redmi Note 5A（`a869cea9`） | 亮度恢复 43；已知问题：`PREOPEN_FULLSCREEN` 旋转过渡期内竖屏 tap 可能落空（修正方向见矩阵记录 ugg 节） |
| `decode-probe-round.sh` | Mi Note 3（`5b79aada`） | 纯解码吞吐探针轮（`P5_CODEC_PROBE` surface 即取即弃，无渲染）；完成标志 logcat 出现 `P5_CODEC_PROBE outputFps`，APK 硬编码为 `/tmp/matrix-decode-probe.apk` |
| `merge-accept-round.sh <apk> <tag> [dur=230]` | 目标设备 | 合并验收轮：Glass SDR 全片，采集 EOS/片尾回退/direct+RESCALE/资源闭合证据；恢复 `MEDIA_KIT_ORIGINAL_APK` |
| `merge-accept-destroy-round.sh <apk> <tag>` | 华为 LYA-AL00 | 播放中直接 Engine 销毁验收：零崩溃、mpv 线程退出、`P5_IMAGE_FINAL` 闭环、进程存活 |

`<sample_enum>` 为 demo app 素材枚举（如 `AndroidHdrSample.dolbyVisionP5`），用于校验 `ANDROID_HDR_OPEN sample=` 命中。

## 截图/日志分析

### `pixel-judge.py <png> [...]` — 截图像素判定

降采样后统计 RGB 均值/亮度/方差，输出判定：正常画面 / 黑屏 / 白屏 / 疑似紫屏 / 纯色落版（需人工确认）。验收轮的标准第一道筛。

### `analyze_shots.py <png> [...]` — 绿色偏色/撕裂形态分析

深度分析：绿色像素占比及行/列/40px 块聚集、断点 x-y 相关性（对角撕裂趋势）、边缘能量、高频热点。来源为 Mi Note 3 HDR10 绿块/斜线撕裂诊断轮，`analyze2/analyze3` 等一次性迭代版已被此版覆盖，未收编。

### `resolve_conflicts.py <file> <hunk序号,逗号分隔> <HEAD|main>` — 冲突批量裁定

按 1 起始的冲突块序号批量取 HEAD 或 main 一侧，未列出的块保留标记原样。适合上游合并时"整块按侧裁定"的分层处理（63 冲突合并即用此法）。

## 既有脚本

- `extract_android_p5_policy.py` — 从完整 VO 日志冻结 P5 映射契约（JSON）。
- `sample_android_gpu_frequency.py` — 按主机/设备双时间戳采样 GPU 频率（NDJSON）。
- `verify_android_p5_fullscreen_log.py` — 校验 LYA-AL00 P5 全屏轮的日志可观测项。
- `update_darwin_libmpv_artifacts.sh` — 按 GitHub release 摘要更新 Darwin libmpv 产物版本/校验和。
