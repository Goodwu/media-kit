# tool/ 使用说明

## 目标 App（2026-10-01 起）

HDR/验收轮次脚本（`matrix-*`、`merge-accept-*`、`decode-probe-round`）构建并操作 **`media_kit_hdr_lab`**（包名 `com.example.media_kit_hdr_lab`）——诊断 App 拆分自 media_kit_test（见 P2-4 整改）。`media_kit_test` 已还原为上游示例 App，不再承载 AUTO/HDR define 面。

## 环境变量（脚本不含本机路径/设备序列号）

- `ANDROID_SERIAL` — 目标设备序列号；未设置时使用 `adb` 唯一连接设备。
- `MEDIA_KIT_ORIGINAL_APK` — 轮次结束要恢复的原包路径（必填，按轮次环境设置）。
- `MEDIA_KIT_TEST_CLIPS` — 测试 App 本地素材根目录（macOS 本地源、对照片）。

Android 实机验收与构建链的常用脚本。2026-09-30 起把此前散落在 `/tmp` 的可复用脚本收编至此（原轮次记录见 `archives/experiments/`）；`/tmp` 重启即清，脚本产物（日志/截图）默认仍写 `/tmp/<tag>-*`，重要证据须及时归档到 `archives/experiments/artifacts/`。

## 构建链

### `matrix-build.sh` — 播放矩阵六包构建

P5/HDR10/P8.4 × SDR/HDR 六个 arm64 APK 批量构建（基础 define 集 = 12632 去起播偏移；HDR 轮加 `PLATFORM_VIEW`，P5 PQ 另加 `GPU_PLATFORM_HDR`）。产物 `/tmp/matrix-<tag>.apk` + 构建日志 `/tmp/matrix-build-<tag>.log`，末尾打印各包 SHA-256。

- 前置：JDK17（脚本内已 export `/opt/homebrew/opt/openjdk@17`）；`ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 指向当期发布基线 JAR —— 脚本内硬编码 `/tmp/media-kit-p5-colorfix-398d0c3-arm64.jar`，换 JAR 必须改这一行（教训：误链旧世代 libavcodec 会复演 `direct=0`）。
- `MEDIA_KIT_ANDROID_LOCAL_SOURCE` 指向设备侧素材路径（`/data/local/tmp/...`），换素材需改 `build` 调用参数。
- define 集与六轮验收依据：`archives/experiments/android-playback-matrix-12703-12708-20260930.md`。

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
