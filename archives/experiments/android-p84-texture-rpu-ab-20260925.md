# P8.4 Texture SDR 的有/无 RPU 定点对照（2026-09-25）

本对照运行在8-bit NV12 的 `mediacodec-copy` 诊断路径；当前工作树已把该路径限于显式诊断开关。像素相等不证明10-bit输入保真，详见 `android-texture-copy-bitdepth-gate-20260925.md`。

使用先前已核实的 12.012 秒成对源：原带 RPU 文件 SHA `f437056aa6ca67ddf7740b042833869c31f9ca3729c62b858688218d81240429`，无 RPU 基层 SHA `5f7cdd9769068f6e9b0a9a1cf5ecedcd3f47a51d68172ed0fb1469d6e91750f7`；两者去 type62 RPU 后的 1472 条非 RPU HEVC NAL 类型/顺序/逐条 SHA 相同，362 帧 FFmpeg framemd5 相同。原带 RPU MP4 缺 DV 配置盒，直接作为 P8.4 打开时 11061 被身份门禁拒绝，未进入播放，不作 A/B 结果。

用 `MP4Box -add '<原文件>#video:dvp=8.hlg2100' -new <重封装文件>` 重封装，得到新 SHA `d12546647bb9dbb12c00162f3e75f8e1125a7645dc8ba75cd40e39f4a55416e9`。MP4Box/ffprobe 回读 Profile8、RPU1/BL1/EL0、compatibility4，FFmpeg 全362帧 framemd5 SHA `e653330c65a017f960322418d225b13295a3f6491f6497ec81379818138cfe71`，与原带/无RPU两个文件一致。新SHA加入固定样本身份白名单。新重封装与旧记录的另一次重封装整文件SHA不同，故本轮以**当前**文件的 profile/帧输出和SHA为身份，不沿用旧封装哈希。

11062 带 RPU APK SHA `25fac7a53b92969a5ae5444ad3bc38d3e2318522ee321b89b452f8dbffc4a080`，11063 无 RPU APK SHA `588648c050d1eeffe0ffbd90c7214dc32db4a7a21673acab572a28809a2037c4`。两轮仅样本身份/文件不同，均 `gpu-next`→Flutter Texture、`mediacodec-copy`、BT.709/BT.1886+`bt.2390`、最大纹理宽1440，媒体目标5秒暂停；带 RPU 轮次按P8.4策略配置并检查 `format=dolbyvision=no` 滤镜。两轮日志均为 BT.2020/HLG、`nv12`、3840×1920源，并在 `timePos=5.038367`、`pause=yes` 停下。

系统截图视频ROI `(0,370,1440,1090)`：两轮各拍两张；四张ROI RGB SHA **全部相同**，为 `205eaaeb18f54378b595bf2bd93601825817e5786973a63b96daf8bc6b90379f`，逐字节MAE=0。该ROI约119650种RGB像素值，并非纯色/全黑。原始四图与两轮日志在 `artifacts/android-p84-texture-rpu-ab-20260925/`。

结果强力支持此采样帧的 Texture SDR 输出不受 RPU 可见影响，与“忽略 P8.4 DV 元数据、使用 HLG 基层”策略一致；不证明滤镜在所有时间点都有效、厂商内部从未读RPU、10-bit/HDR输出完全相等、真实显示颜色或长期稳定。完整S2颜色验收仍需独立参考。设备测试后停止应用，删除当前应用可重建暂存及新推送的重封装副本，恢复官方10369基线；原始成对源保留。
