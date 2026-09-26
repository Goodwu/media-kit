# 当前工作树 P8.4 原生 HLG 对照（2026-09-25）

在华为 LYA-AL00 Android 10/API29，当前工作树构建 versionCode 11051（APK SHA-256 `acca794be24b4abd95d68a4d4dc2c352cdc074c81336f4ff98c94d8ce093de98`），开启 HDR transaction、PlatformView、固定 Android 本地源，未开启 GPU Platform HDR 或模拟无HLG。输入为设备原始 `/data/local/tmp/media-kit-p84-full.mp4`，SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`，同本机副本；原文件 MP4Box 报 Dolby Vision Profile 8/level 7、RPU=1/BL=1/EL=0/Compatibility=4，HEVC Main10、3840×1920、30000/1001 fps、BT.2020/HLG，时长1170.730秒。未改动源文件。

`ANDROID_HDR_OPEN` 回报 `sample=dolbyVisionP84`、`gpuPlatformHdr=false`、`presentationVerified=false`。当前策略选择 `mediacodec_embed`/`mediacodec` 原生直出，但本轮未在打开后单独回读 VO 名称；运行时 `VIDEOPARAMS` 为 `pixelformat=mediacodec`、BT.2020 limited/HLG，ACodec 用 `OMX.hisi.video.decoder.hevc`，最终 color aspects BT2020/BT2020/HLG，dataspace `0x12060000`。活动 SurfaceView#1 的 buffer 3840×1920、vendor format 325，SurfaceFlinger 层 `BT2020_ITU_HLG (302383104)`、HDR metadata types=0；可见视频区域 `[0,326,1440,1136]`，HWC `composition=DEVICE`。HLG 无 HDR10 静态 metadata 是预期，不能据此推断屏幕亮度。

同一 PID 的视频层三次主机 monotonic 采样：`699653.915→1814`、`699659.015→1968`、`699664.119→2120`，每约5.1秒增154/152 buffer，约30 buffer/s。两张相隔约3秒的整屏截图，其视频 ROI RGB 字节 SHA-256 分别为 `a6a2578cfb591e265729e6f267cfc78bafa2a6adcf4938fab774f9ac39c75cbe`、`26d7fbc8a58e13c3d8597d9ecd3fadad637767b8ba9508e1a38785c244cdb648`。计数证明SF持续接收，截图证明采样到不同内容；两者都不是逐帧物理present、HLG亮度或独立颜色验收。

本轮证据只支持**本机完整P8.4文件可由当前原生硬解Surface路线按HLG兼容底层持续提交约30fps buffer**。它没有证明厂商解码器是否内部使用/忽略RPU；应用路径没有gpu-next/libplacebo DV重塑，但不能把后端行为推定为已验证的“忽略RPU”。P3仍需该阴性门禁、独立HLG参考、长播/生命周期和gpu-next→PlatformView HLG/Texture SDR验证。短截取的45秒文件虽保持HEVC Main10/HLG，却丢失MP4的DV封装声明，因此未加入样本白名单、未用于本轮身份验收。

测试前 `/data` 仅余约1.8 GiB；运行时最低观察到约803 MiB。停止应用后检查其私有目录，发现过去多轮测试累积 `files/android-hdr-staged` 约36 GiB、`cache/file_picker` 约34 GiB，均为测试页生成的暂存/缓存副本。已在应用停止后以 debug 包 `run-as` 清除这两个**可从原始媒体重建**的目录；设备原始 `/data/local/tmp` 中HDR10/P8.4文件保持存在，P8.4 SHA复核不变，`/data` 空闲升至约71 GiB。随后恢复10369基线包、诊断属性0且应用不运行。这个缓存生命周期问题仍需在测试入口修复，不能以本轮手工清理作为产品策略。

原始日志与SF dump在 `artifacts/android-p84-direct-11051/`。SHA-256：`logcat.txt` `5659a7c8896cb136ee11a83b62ef13c601fcee743a3b71257dadee0773bced83`；`surfaceflinger.txt` `73ef99c43580eb25ce946ab94ff1f3625d41aa5b4160e88ba57d32fd4d477a03`；`counter-window.txt` `a22a3d531a2618a3f794c191ea5f22b8955ca234374ae4c0d374c3efd722d8ac`；`screen-a.png` `74f9021ca44edf485dc9e9e5d525c96b94ead43519356dad575a8b37b594bdcb`；`screen-b.png` `57d0260c69edef0de6d7e30296f547c559e8bcfb0fb7125b38e6bb8fb23b6ba3`。
