# MK-ROUTING-20261011 / DEVICE 首轮候选构建输入向量（DV-BUILD-01，整改后 r2）

日期：2026-10-11。构建根：`/Users/wuweiwei1/src/mk-device-20261011/`（独立 worktree + APFS clonefile 复制缓存，不触碰既有可写工作树）。
**r2（同日整改）**：按用户指令「本地有代码的组件一律从最新代码构建」修正 mpv/libplacebo 钉定滞后；构建仓配方修正以 device/MK-ROUTING-20261011/DV001（Goodwu/libmpv-android-video-build-dv-experiment PR#1）登记。

## 源码向量（r2）

| 组件 | 仓库/位置 | ref | SHA | dirty |
| --- | --- | --- | --- | --- |
| media-kit | Goodwu/media-kit `routing/MK-ROUTING-20261011` | 远端 HEAD | d68871f7bad52264955500ad8dde8adb34f0a100 | 0 |
| PiliPlusX | Goodwu/PiliPlusX `routing/MK-ROUTING-20261011` | 远端 HEAD | b8303a9c2ce0c07b19bc85528dd1b1d93f72f61a | 0 |
| FFmpeg | Goodwu/FFmpeg `routing/MK-ROUTING-20261011` | 远端 HEAD | 9aba43cfbee182ade060cdccbe15340a0fbe3e83（含 e8df200c） | 2（patch.sh：ffmpeg-hls-kazumi-combined.patch） |
| mpv | Goodwu/mpv `media-kit/android` | **远端 tip（r2 更新）** | c11426b67a96747c74dfd2a1b0a0340af9696103 | 1（既有 CONFIGURATION 置空修改，已保存 manifests/mpv-configuration-empty-preserve.patch 并重放） |
| libplacebo | Goodwu/libplacebo `optimize/dovi-linear-decode` | **重写后远端 tip（r2 更新）** | ea700489fbf27703d8c1f64874a1c6138f17ad28 | 2（fix_gles + fix_shaderc 两补丁干净应用） |
| helper | Predidit/media-kit-android-helper `main` | pin==远端 tip（已核对） | b768ce102cfa9b5ddec618bb939d689d1b0899fa | 0 |
| 构建仓 | Goodwu/libmpv-android-video-build-dv-experiment | device/MK-ROUTING-20261011/DV001 | 77fc823（72c574d + 配方修正） | 0 |
| 其余 deps | dav1d 676a864 / mbedtls 1873d3b / libxml2 f507d16 / libass e8ad72a / shaderc（非 git 快照）/ fftools_ffi 10070ac 等 | 按 depinfo.sh（upstream 第三方钉定） | — | 补丁后 |

## 相对已发布 v2026.013 的输入差异

- FFmpeg：b4d2ea4ffb → 9aba43cf（routing 全部修复）。
- mpv：d24c59905b → c11426b67a（media-kit/android 6 个产品提交）。
- libplacebo：c9fd8798 → ea700489（重写线；external YUV/r32f/DV linear/ gamut clip 已收编为提交；fix_gles、fix_shaderc 仍以补丁应用）。
- helper 及其余 upstream deps 不变。

## 工具链

- macOS arm64（darwin 27）；NDK **27.2.12479018**（FFmpeg/mpv/libplacebo/helper 全部同一 NDK；helper 的 AGP 8.4.2 默认 NDK 26.1 因磁盘未装，已在 helper 工作树本地覆盖 ndkVersion=27.2.12479018——DEPS clone 本地修改，记录于此）；API level 26 crossfile。
- adb 37.0.0；Flutter 3.47.2 stable；Gradle 9.5.0 + AGP 9.0.1 + openjdk 27；helper/gradle 用 openjdk@17（17.0.20.1，同上轮正式包）。

## 构建过程（arm64-v8a 子集）

1. `bash patch.sh`（r2 重跑：ffmpeg already applied；libplacebo 新线 fix_gles/fix_shaderc 干净应用，两个旧补丁已移 patches-archived）。
2. `cp flavors/default.sh scripts/ffmpeg.sh`。
3. `bash build.sh --clean --arch arm64 ffmpeg`（含 deps 干净重建）✓
4. r2：deps/mpv checkout c11426b67a + 重放 CONFIGURATION 修改；deps/libplacebo checkout ea700489 + 补丁应用；`bash build.sh -n --clean --arch arm64 libplacebo` + `bash build.sh -n --clean --arch arm64 mpv`。
5. helper：`./gradlew assembleRelease`（JDK17 + NDK 27.2 覆盖）→ APK 提取 .so。
6. JAR 组装（manifests/assemble-jar-arm64.sh）：libmpv.so（新构建）+ libmediakitandroidhelper.so（helper 构建）+ libc++_shared.so（NDK 27.2 sysroot，与对照包字节一致 1794776B）→ vkweak 弱化 → 固定时间戳 → zip。
7. 产物哈希 + ELF Build ID + 符号核对；对照样本 v2026.013（SHA 0e06f383…，reference/）。

## 审计发现（已登记）

1. 构建仓钉定滞后（mpv 6 提交、libplacebo 整线重写）→ DV001 修正。
2. bundle_default.sh 的 JAR 组成步骤不完备：helper .so 与 libc++_shared.so 未由配方显式产出进 JAR 路径（历史 JAR 由更早世代的产物拼接）；本轮以显式步骤补齐并记录来源。建议 CORE 在 DV001 合入评估把三件套组成固化进 bundle 脚本。
3. JAR 对照包含 META-INF/MANIFEST.MF（历史派生残留）；bundle 配方只打 lib/，本轮按配方（无 MANIFEST）。

## r2 产物哈希（2026-10-11 21:58 构建）

- artifacts/default-arm64-v8a.jar SHA-256 `cd5fe26befeb6e9f96627692f5883abe860381853bac997f45806139c9851622`
- 成员 md5：libmpv.so 4cea0005162e529744d527351d239a51；libmediakitandroidhelper.so 8cdab12fce31dfd847b508292f8ff1be；libc++_shared.so ab695376e7624c39a72aac8ad5210ba1（== NDK sysroot 原件）
- libmpv.so 指纹：native_dv/nativeDV 字符串×39、dovi-p5-pipeline、render-mode（mpv c11426b67a）、符号 avformat_complete_initial_dovi_hvcc（FFmpeg 9aba43cf）、未定义导入仅 4 个 Vulkan 1.0 符号（**两个 1.1 导入已由 mpv 12030b9c39 经实例解析正规消除，无需 vkweak 弱化**）
- libplacebo.a 2,286,984B（ea700489 + fix_gles + fix_shaderc）；libmpv.so 22,979,344B
- 对照：v2026.013 JAR SHA-256 0e06f383…（reference/，含 2 个 w 弱符号）
