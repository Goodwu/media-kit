# LYA 本地 DV P8.4 播放复测

## Current State（2026-10-23 已完成本轮构建与本地播放验证）

- 标准构建链已修复并实际跑通；LYA 已安装本地源码构建的 media-kit HDR Lab Release，实际播放本地 DV P8.4 样片。未使用 B 站入口，未以旧 APK/JAR 替代。证据 JSON 中 builder 哈希绑定的是产出该 APK/JAR 的初版工具；本次归档审查加严了链接输入解析，尚未用最终工具版本重跑构建或测试，不能把先前实机证据视为最终工具版本的重建验收。
- 可复用工具在仓内 `tool/build_android_native.py`，标准入口仍为 `tool/build-android-test.sh`。同步依赖源码构建树、mpv 及 helper 后生成新三成员 JAR；来源冻结、配置源码根/NDK 绑定、实际 archive 归因、ELF 检查通过。初版5项单测曾通过；归档审查后加严链接参数归因，本次未重跑测试。独立 V1 审核已复核修订。用户新增 `media-kit-build/` 不得长期存放需复用工具资料的规则已落实。
- APK SHA256 `66b7cc459fb84f5e314d09541188da66ac3d25d4abc2d4ebd854d8371ceed627`，装机回读一致；JAR `46bba27c9f416362017936c62a2aa4bad722f4967852487af5b0ae7b0c974bc1`。mpv/helper 与JAR逐字节一致，libc++ 经正常 NDK strip 后与APK一致。当前mpv `c42549b5`含既有本地修改；“当前”表示实际本地源码，不声明所有依赖追平远程HEAD。
- LYA API29，原样片 `/sdcard/Download/DV-P8.4.mp4` 保持，复制到 App 专属 files 后 SHA256 仍为 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`。实际本地 open 确认为 HEVC、DV profile8/compat4、HLG 输入；海思硬解，metadataReshape→PQ，10-bit RGBA1010102/BT2020_PQ 视频层。
- 120.005秒 SF 样本 frame-counter 1207→4804（+3597，约29.97fps），五点格式/PQ保持；mpv采样解码/输出drop均0，无FATAL/ANR。三段短latency环窗约29.95–30.05fps，不将其扩展为完整区间逐帧零抖动证明。三张截图独立视觉复核均有不同可读画面，无明显黑屏/破损/UI残留。
- 验收边界：选中候选仍标 experimental/confidence=unverified，日志 verified=true 为路由/输出观测；本轮不是原生 DV 直通或面板色彩/亮度验收。未写亮度/旋转设置；自动亮度模式保持，标量39→53的原因未单独测量。设备保留本地播放。
- 接手入口：可复用构建说明 `tool/README.md`；持久摘要证据 `docs/validation/lya-local-p84-playback-20261023.json`；完整实机报告 `/tmp/lya-local-p84-20261023/REPORT.md`；完整构建日志 `/tmp/lya-local-p84-full-build-20261023.log`；原生receipt `build/android-native/lya-local-p84-20261023-final-20261023-180817-79486/`。

## Findings

- 2026-10-23 用户新增持久规则：禁止在 `media-kit-build/` 长期保存需要复用的工具与资料。规则写入 `AGENTS.local.md`，构建工具和说明在仓内，临时产物在仓库 `build/android-native/`。已不再依赖被删除scratch中的唯一脚本。
- 最终完整构建日志 `/tmp/lya-local-p84-full-build-20261023.log`；首轮native日志 `/tmp/media-kit-native-repair-second.log`；最终原生receipt包括16组source records、22个archive输入（含NDK工具链库）、三成员ELF/哈希。helper从当前native-lib.cpp编译，libc++来自所选NDK运行库；无发布JAR输入。
- 设备样片SHA256已读为 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`，与仓内P8.4登记一致。预检 `/tmp/lya-local-p84-20261023/PREFLIGHT.md`，初始亮度39/自动1、自动旋转1/user_rotation0；后续全轮未写设置，自动模式下亮度标量有变化。

- 初轮误选 PiliPlus/B站深链入口，用户纠正后立即停止；这轮材料 `/tmp/lya-p84-playback-20261023-174708/REPORT.md` 不满足本地播放请求，不纳入验收。未改应用设置、源码，未安装APK。
- 实查 `~/src/media-kit-build` 为空目录。2026-10-22保留资产 README 说明原目录由用户决定删除，仅保留部分文本工具；保留目录及 `/tmp` 的定向检查没有找到 `build-mks-r1.py`。现存其它 native-DV 脚本引用已失效构建树，不能当作可直接运行替代。
- mpv `filters/f_decoder_wrapper.c` 存在其它任务的未提交修改，本轮未编辑或撤销；标准 wrapper 的 ninja 步骤使用当前构建树。

## 本轮执行结果（2026-10-23）

- 构建命令：`tool/build-android-test.sh --tag lya-local-p84-20261023-final --platform-view --local-source /sdcard/Android/data/com.example.media_kit_hdr_lab/files/DV-P8.4.mp4 -- --dart-define=MEDIA_KIT_ANDROID_HDR_DIAGNOSTICS=true --dart-define=MEDIA_KIT_ANDROID_PROP_SNAPSHOT=true`，exit0。原生26条命令成功；Flutter assembleRelease 63.8秒。
- 18:12:21.801 本地open，`OMX.hisi.video.decoder.hevc`，3840×1920/29.97003fps。18:13:02.357→18:15:02.362 SF五点帧计数1207/2107/3006/3905/4804；源position 1.835→143.844 随墙钟等速推进。独立Verifier报告与原始命令/数据保留在上述证据目录。
- 三成员APK验证的初始逐字节比较发现libc++不同；进一步以所选NDK的 `llvm-strip --strip-unneeded` 处理JAR输入后与APK逐字节一致，确认为正常AGP打包剥离，不是异源运行库替换。mpv/helper原始比较均一致；细节在原生输出 `apk-native-verification.json`。
- 首次构建失败的原因（仅历史）：旧wrapper在ninja后调用已删除的 `media-kit-build/lg-api24/lg-api24-realtime-gpu-phase0-20261008/build-mks-r1.py`。新实现不复活scratch路径、不重用发布JAR、不修改其它仓库源码；使用现存配置好的依赖构建树，不能作为全新机器bootstrap。
