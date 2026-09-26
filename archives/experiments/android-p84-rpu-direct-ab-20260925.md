# P8.4 原生 HLG 路线 RPU 阴性对照（2026-09-25）

结论限定在两处采样帧：同一华为 LYA-AL00 的原生 MediaCodec→SurfaceView 路线上，**有 RPU 的 Profile 8.4 输入与逐帧相同、只去掉 RPU 的 HLG 输入，在 5.038367 秒及 8.041367 秒冻结后，系统截图视频区域 RGB 字节完全相同**；两轮均保持 BT.2020/HLG 图层。结果强烈支持这两个位置没有可见的 RPU 处理差异，但系统截图是 SDR 映射，不能证明厂商解码器内部从未解析/应用 RPU、HDR 高精度输出逐像素相等，亦不能外推全片所有场景。

## 输入身份与同底层证明

设备上既有 12.012 秒诊断对 `media-kit-p84-rpu-12s-control.mp4` SHA-256 `f437056aa6ca67ddf7740b042833869c31f9ca3729c62b858688218d81240429`、`media-kit-p84-no-rpu-12s-control.mp4` SHA-256 `5f7cdd9769068f6e9b0a9a1cf5ecedcd3f47a51d68172ed0fb1469d6e91750f7`。这两个短文件本身都失去了 MP4 Dolby Vision 配置盒。用 FFmpeg `hevc_mp4toannexb` 抽出视频 NAL 后，带 RPU 版共1834个 NAL，其中type62 RPU 362个；去RPU版1472个、type62为0。去掉前者所有type62后，剩余 NAL 类型、顺序和逐条 SHA-256 **全相同**。FFmpeg 软件解码的362帧 framemd5 文件也完全相同，三份 framemd5 SHA-256 均为 `e653330c65a017f960322418d225b13295a3f6491f6497ec81379818138cfe71`。

为让带RPU分支仍按P8.4身份进入测试事务，用 `MP4Box -add '/tmp/media-kit-p84-rpu-12s-current.mp4#video:dvp=8.hlg2100' -new /tmp/media-kit-p84-rpu-12s-dovi-signaled.mp4` 仅重封装；生成文件 SHA-256 `1755cf6a2ea575816f5f0ab403b9cc47b9577c838289251f7c14b5e33622c2f5`。MP4Box 报 DolbyVision 1.0/profile8/level7/RPU1/BL1/EL0/Compatibility4；软件 framemd5 与重封装前和无RPU版一致。测试页给两文件不同身份：前者 `dolbyVisionP84`，后者 `hlgBaseControl`；后者只准原生 HLG 直出，不允许借 PQ fallback 或称为 DV。原设备上两份12秒源保留；新重封装临时文件在测试后从设备移除，可按上述命令重建。

## 设备对照

两轮均使用当前工作树、HDR事务、PlatformView、默认原生 MediaCodec、相同固定显示区域与 `MEDIA_KIT_ANDROID_HDR_PAUSE_AT_MEDIA_SECONDS`；仅输入和目标PTS分两对改变。每次打开后先等媒体位置到目标秒，执行 pause 和绝对 seek，1秒后回读 `time-pos` 与 `pause`，再截图。5秒无RPU APK11053 SHA-256 `8fa0b6d35df81d405d5b292575c1f769ec4b1148bd7ac4c0355abcefda1609e8`、有RPU APK11054 `b1e45a62d2bc89de82a2b22079c3c651436b8c3afd6aca5c0012ea31ad102fbe`；8秒无RPU APK11055 `b0843c68868b603af4705a3aa668f7c294493d22eafb239822ae3762cb677f10`、有RPU APK11056 `3e4bb91511c18fba243dad554e937c72d1b0ecd1b72c0da4d5f6f11f1b30246f`。四轮均通过样本白名单/新文件加载/硬解验证；有RPU回读profile8，无RPU回读空profile，两个分支视频参数均 BT.2020 limited/HLG，SF 同为 `BT2020_ITU_HLG`。

| 目标 | 无RPU / 有RPU最终回读 | 视频ROI RGB SHA-256，两轮相同 | 区域内容检查 |
|---|---|---|---|
| 5秒 | `timePos=5.038367 pause=yes` | `1e78a5a156b0d1ae67b5f240c9f7b384481a1ad31ce9f79e4116acc927a7c695` | RGB均值约(98,94,82)、标准差约(63,59,58)、隔8像素约9058种颜色 |
| 8秒 | `timePos=8.041367 pause=yes` | `e0b028814ef43ce535debb60dbaf1b9e2b1621957c5149aa7b2382bcd492fa76` | RGB均值约(100,104,106)、标准差约(64,65,69)、隔8像素约4836种颜色 |

ROI 固定为 SurfaceFlinger 可见视频区域 `[0,326,1440,1136]`，以各截图解成RGB8后比较。5秒每轮相隔两秒的重复截图ROI自身也完全一致，排除了当时仍在播放；8秒两轮回读暂停和精确相同的 `time-pos`，截图ROI再次完全一致。两处均非纯黑或纯色帧。截图差异为0不能证明显示器光学亮度一致，也不构成所有RPU metadata帧的遍历门禁。

证据在 `artifacts/android-p84-rpu-direct-ab-20260925/`：5秒两轮各两图、原生日志和SF dump；8秒两轮各一图及日志。运行结束强停、清本轮私有暂存、恢复10369基线包；设备 `/data` 空闲约71 GiB、无诊断属性或应用进程残留。后续要把“忽略 RPU”提升到全片或高精度定量结论，还需跨镜头抽样与读取解码后高精度像素或可证明的厂商处理状态；此两帧结果不可替代 GPU HLG 路线的独立验证。
