# P5 音频时钟与 Texture 布局尺寸 A/B（2026-09-25）

## 结论

在华为 LYA-AL00/API29、同一 4K/50fps P5 视频包和同一 arm64 `libmpv.so`（APK 内 SHA-256 `68fffaee57c85c74b811ebb8e0ade76eb1e3b5a2f047edadbd9ed1189f605a28`）上，Texture SDR 的输出缓冲尺寸是本轮巨大吞吐差异的可控因素。11014 启用 `mediaKitTextureMaxWidth=960` 但未打开按布局设置纹理尺寸时，实际 `android-surface-size=3840x2160`，原无音轨片到 t28 累计掉帧 811；11015 只增 `MEDIA_KIT_ANDROID_TEXTURE_LAYOUT_SIZE=true`，请求变为1440×810，实际限为960×540，同原片 t8/18/28 累计掉帧均0。旧8367 APK在当前设备同原片再次运行，t18/28累计掉帧均11，复现历史低掉帧轮。故不能把此前新包高掉帧归因于音轨、GPU DV颜色算法或设备当前热状态；**4K输出目标而非4K输入解码**是这组构建差异中的关键条件。尚未独立测出 GPU/合成各段成本，亦不把 960×540 的成功外推至 4K 输出。

11015 再换入带AAC时钟、视频包与原片逐包相同的隔离样本，固定 `vo=gpu-next`、`hwdec-current=mediacodec`，视频参数为 Dolby Vision/BT.2020/PQ，PTS10.000 源和映射帧均 `dovi=1`，目标为 BT.709/BT.1886。`android-surface-size=960x540`；t8/18/28/60/90/120 的内容时间为7.5/17.5/27.5/59.5/89.5/119.5秒，六个时点播放器及解码器累计掉帧均0。t60/90/120 `avsync` 分别为0.000021/0.000023/0.000024秒，热状态1；t120仍 `pause=no,eof-reached=no`，SurfaceTexture消费回调累计5970，滚动4096样本的纹理时间戳间隔中位约20.03ms、p95约21.14ms、回退0。回调是 Flutter 消费侧，**不是 SurfaceFlinger present/显示扫描**；`avsync` 是 mpv 内部读数，连续测试音没有视觉事件对应，不能据其极小值宣称物理音画差≤100ms。120秒不满足计划中的10分钟/30分钟长期稳定性门禁。

## 有效对照和排除

| 包/配置 | 输入与 DOVI | 实际输出 | t28 累计 VO/解码掉帧 | 解释 |
| --- | --- | --- | --- | --- |
| 11012，默认 SurfaceProducer，`code_scale=1` | 带音轨，同4K P5，显式 `p5_rpu_probe=2` 后帧上DOVI=1 | 4K | 763/0，t60为1741/0 | 有效但性能失败；`avsync`约10ms不抵消掉帧 |
| 11012，`code_scale=0` | 带音轨 | 4K | 816/0 | 关闭代码值缩放未改善 |
| 11012，`code_scale=0` | 原无音轨P5 | 4K | 783/0 | 高掉帧并非AAC音轨引入 |
| 11013，SurfaceTexture，未按布局定尺寸 | 原无音轨P5 | 4K | 815/0 | 单改SurfaceProducer拓扑未改善 |
| 11014，SurfaceTexture，Gradle最大宽960，但未按布局定尺寸 | 原无音轨P5 | `android-surface-size=3840x2160` | 811/0 | 只设Java上限不足以使当前输出申请变小 |
| 11015，在11014上仅增加布局尺寸开关 | 原无音轨P5 | 请求1440×810，实际960×540 | 0/0 | 同包配置单变量确认尺寸路径影响 |
| 11015，同配置 | 带AAC时钟P5 | 实际960×540 | 0/0；t120仍0/0 | 有音轨内部同步与120秒吞吐初筛通过 |

11010 漏设 `gpu-next`，实际 `vo=gpu`/`mediacodec-copy`；11011虽设 `gpu-next`，仍自动选 `mediacodec-copy`；11012首次漏设 `debug.media_kit.p5_rpu_probe=2`，帧上无DOVI。这些轮次**均不作P5性能结果**。对11012同APK回填原始无音轨MP4时也复现无DOVI，说明该失败来自缺少本隔离FFmpeg硬解分支的显式RPU附帧开关，不能归咎于MP4Box重封装；补设后原片和带音轨包均回读Dolby Vision、PTS10帧`dovi=1`。带音轨包的全部6609个视频packet PTS/DTS/大小/SHA与原片一致，详见[样本制作记录](android-p5-avsync-fixture-20260925.md)。

11012 APK SHA-256 `903488520d1375f68148fb326a8b40c5492cccce987171da330842f30aa6dd8a`，11014 APK SHA-256 `f4c0053a47b6d4f05d016bc599493ef34379555e3a9b6d145aae0cf61bf66e85`，11015 APK SHA-256 `afaf790e529421ea8d5a9a7cf61450b9130345bd78525d10c9fb0d2f3cfca8c4`；11015 120秒logcat `/tmp/media-kit-p5-avsync-11015-logcat-120s.txt` SHA-256 `f9e0937db33c8383ebcbab01823188c837fb3655999d4cb1297445d5859eb835`，含启动参数回读、PTS10 DOVI及各PERF时点。11012高掉帧日志 `/tmp/media-kit-p5-avsync-11012-logcat.txt` SHA-256 `08f98b964395830db296242c867336ae3fe9e73a8cd47e4f6a82611a26553b4c`。旧8367包内相同libmpv，旧包本次需手动进入单视频页；不把启动到页面的延迟纳入它的t值比较。A/B重点使用11014→11015的同构建参数单变量结果。

运行结束后强停应用、七项诊断属性逐项回读0、恢复已核SHA的10369基线APK并确认versionCode；设备上的两个诊断文件副本已移除，原`/sdcard/Download/DV-P5.mp4` SHA仍为`328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`。项目只新增诊断样本的哈希映射，未把960限幅设成通用产品默认，也未改libmpv/libplacebo。

## 1440×810 输出补测（11016）

在 11015 的带 AAC 时钟输入、Texture 布局定尺寸、SurfaceTexture、`gpu-next`/`mediacodec` 和诊断属性配置上，只把 Gradle `mediaKitTextureMaxWidth` 从 960 改为 1440，构建 11016。两个 APK 内 arm64 `libmpv.so` SHA 均为 `68fffaee57c85c74b811ebb8e0ade76eb1e3b5a2f047edadbd9ed1189f605a28`。11016 回读 `android-surface-size=1440x810`、输入 3840×2160 Dolby Vision/PQ、目标 BT.709/BT.1886，仍为 P5 硬解与 RPU 路径。

同一设备本轮 t18/28/60/90/120 的内容时间约 17.44/27.42/59.44/89.44/119.42 秒；播放器累计掉帧分别为 1/1/1/1/1，解码掉帧始终 0。t120 `avsync=0.000021` 秒、`pause=no`、`eof-reached=no`、thermal status 1；SurfaceTexture 消费回调累计 5966，滚动 4096 个纹理时间戳间隔中位 20.013ms、p95 21.095ms，无倒退。相对 960×540 的 11015 本轮 120 秒累计 0 掉帧，1440×810 仍达到本次播放器侧短时吞吐目标；但仅各一轮，不能判断两者 0 与 1 帧的微小差别有统计意义，也不证明 SurfaceFlinger 实际 present、肉眼流畅、物理音画同步或 10/30 分钟热稳。

11016 APK `/tmp/media-kit-p5-avsync-11016.apk` SHA-256 `021cb003fde9affea415e3e6a1317afe52116557d8162d0ad716fb443125f8aa`；本轮 PID 8893 日志 `/tmp/media-kit-p5-avsync-11016-logcat-120s.txt` SHA-256 `d6c85bf6cf69d249b057ea747a03421cfc90e27380bf452f7d984fe988b1d67d`。测试后已强停、移除设备诊断副本，使用 `adb install -r -d` 恢复 10369（普通 `-r` 因降级被拒，未卸载/清数据）；七项 P5 属性均回读 0，应用无进程。下一步可在保留 1440×810 清晰度的条件下做 10/30 分钟重复与可见节奏验收，再评估是否把布局定尺寸纳入产品默认。

## 10 分钟循环初筛（11017）

测试入口新增默认关闭的 `MEDIA_KIT_ANDROID_LOOP_SOURCE`：Android 固定源打开前设置 `PlaylistMode.single`（底层 `loop-file=yes`），以便同一 132.18 秒 P5/AAC 样本覆盖 600 秒；不改变生产默认。11017 保持 11016 的 1440×810 Texture、同一 arm64 libmpv SHA、硬解和 `p5_rpu_probe=2`。设备回读 `ANDROID_LOOP_SOURCE mode=single`、`vo=gpu-next`、`hwdec-current=mediacodec`、`android-surface-size=1440x810`；PTS10 源与映射均 `dovi=1`，目标 BT.709/BT.1886。设备唤醒及 keyguard 状态核对后启动，连续采集同 PID logcat 至 600 秒。

内容时间在 t120/150 为 119.46/17.22 秒，在 t240/270 为 107.22/4.96 秒，在 t390/420 为 124.96/22.72 秒，在 t510/540 为 112.70/10.46 秒，确认四次回环后仍推进。各轮最后或较晚的样本累计 VO 掉帧为首轮 t120=2、次轮 t240=14、第三轮 t390=0、第四轮 t510=1、第五轮 t600=1；所有采样点 decoder 掉帧均 0、热状态均 1。**`frame-drop-count` 每回环重置**，这些离散读数不能相加当作严格十分钟总掉帧数，也未覆盖每轮片尾最后数秒。t600 内容时间70.46秒、`pause=no`、`eof-reached=no`、内部 `avsync=0.000023` 秒；SurfaceTexture 消费回调累计 29920、滚动时间戳中位20.020ms/p95 21.122ms、倒退0。每次回环后的滚动最大纹理时间戳间隔约147–199ms，低于计划的500ms停顿门槛，但此指标仅是消费侧，不能排除显示端卡顿；与未回环的持续长片也不等价。最后两张间隔约3秒的 `screencap` 在 `(0,350,1440,1150)` 视频区域 RGB 绝对差均值约 `(84.4,76.0,72.9)`/255，证实两个时刻画面不同，不证明每帧显示节奏或颜色正确。

11017 APK `/tmp/media-kit-p5-avsync-11017.apk` SHA-256 `c618b5486f040efb0165441d9a434c536937f48df41586a41964796c42459ecc`；PID10048 日志 `/tmp/media-kit-p5-avsync-11017-logcat-10min.txt` SHA-256 `e204de3ce5640390bf78862800299c5ef35a7b07df21f4509105078f4237a02c`；末段截图 `/tmp/media-kit-p5-avsync-11017-t600a.png`、`t600b.png` SHA 分别为 `c7b26735c449caeb1bcaf65e1e1edf168b846427235c11a63ec112a7fe8eef84`、`6a38bc308ccc84cdf6f7d4b4215e565967559356bf4bc9b23c7ebe4071c3db11`。已强停、移除设备诊断媒体，恢复 10369 且进程未运行；七项 P5 属性均回读 0。此轮满足**机器侧循环10分钟初筛**，并未完成计划中的同一内容连续片30分钟、实际present cadence、音画物理差、真人观感或最终色彩/HDR验收。
