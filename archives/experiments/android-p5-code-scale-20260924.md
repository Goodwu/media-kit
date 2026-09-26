# P5 packed10 原始代码尺度校正（2026-09-24）

目标：验证目标机 `GL_EXT_YUV_target` 输出在先前中心28帧、九宫格1帧中观察到的 `software_code=round(GPU_float×1020)`，能否在单张 RGB10_A2 中间纹理写入前校正为通常的 10-bit `code/1023`。此处只处理 **P5 raw prepass 的数值表示**，不把 raw 分量验收等同 Dolby Vision reshape、最终 SDR/PQ 颜色或面板 HDR 验收。

隔离 mpv `/tmp/media-kit-mpv-clean-2194/video/out/hwdec/hwdec_aimagereader.c` 新增默认关闭的 `debug.media_kit.p5_raw_code_scale=1`，仅在 `p5_raw_yuv=1,p5_raw_packed10=1` 时有效。packed10 片段着色器以 `uniform code_scale` 将 sampler 的 Y/U/V 乘 `1020.0/1023.0` 后写入 RGB10_A2；关闭为乘 1.0。其他 R32F/MRT、原生直出、HDR10/P8.4 路线不受此开关控制。整合 mpv 补丁 `android-p5-scale-8345-integrated-mpv-20260924.patch` SHA-256 `fc7e4df7ba66c00fb38562ddb9fc3189e01d6ca65013ee76ebcdec1fd01864b5`，包含前序 raw/packed/空间诊断，不是仅本轮增量。FFmpeg RPU/stage-probe 合并及 libplacebo 格式库沿用前一实验记录。

arm64 增量编译/链接、`git diff --check`、APK zipalign/签名/验签及包内库 SHA 对照通过。APK `/tmp/media-kit-p5-scale-8345-arm64.apk` SHA-256 `7fe39b6483b935514e40dcf92ae6d739c4df7abfd479ac353b35e2d06d4ff48f`；stripped libmpv SHA-256 `4c46c5b88ba306c34ce52c723af38689e892828596673ccd7743ee3613513bf5`。`8345` 仅是包标签，APK 内 versionCode 仍为 8340。

同一 APK、同一 P5 原片、MediaCodec/gpu-next/Texture SDR、逐帧 RPU (`p5_rpu_probe=2`)、raw packed10 (`p5_raw_yuv=1,p5_raw_packed10=1`)、单帧九宫格读回 (`p5_raw_pixel_probe=1,p5_raw_spatial_probe=1`)；只切 `p5_raw_code_scale=0/1`。两组视频参数均为 3840×2160 Dolby Vision/full/BT.2020/PQ，PTS 10.000 秒九点均 `GL error=0`。对软件解码第500帧的相同坐标：

| 开关 | 九点×YUV 共27个分量 | 示例中心 `(1920,1080)` |
| --- | --- | --- |
| 关 | 27/27 等于 `round(software_code×1023/1020)`；0/27 直接等于源代码 | 源 `(415,514,508)` → GPU `(416,516,509)` |
| 开 | 27/27 **直接等于软件源10-bit代码**；0/27 等于未校正预测 | GPU `(415,514,508)` |

两轮均各见一次启动附近 `Failed rendering frame!`，之后继续到 PTS10 并读回成功；这一次错误尚未归因，不以这些带读回的轮次评估性能或可见稳定。原始日志 `/tmp/media-kit-p5-scale-8345-off-logcat.txt` SHA-256 `85051902d03af2a345ccf5689f26470361938a2e8c06ceb0e30939d1e597b8b4`、`/tmp/media-kit-p5-scale-8345-on-logcat.txt` SHA-256 `f7af079d28c0d7e4c8746ccf9c7581ede5472ec6fc889706ba20b9d794d138c8`。

保持校正开启、关闭九宫格单帧模式，中心 `(1920,1080)` 在 PTS 10–11 秒读回 40 个有效帧；按 PTS 对齐逐帧 FFmpeg 软件解码，Y/U/V 共120个值全部与源代码严格相等，最大绝对差 `(0,0,0)`，GL 错误0。日志 `/tmp/media-kit-p5-scale-8345-on-timeseries-logcat.txt` SHA-256 `71313ad364972829c13b4d5a47cfcdfcdc0a8aff31b15ccde438521a04fca36b`。这验证了已测区域与时间窗的校正，不覆盖整片、边缘或完整 10-bit 代码范围。

用 FFmpeg 软件解码全片并每50帧取一帧做 `signalstats`（133个样本帧），所测 Y/U/V 最大值分别为 852/859/892，均未到1020。命令：

```sh
ffmpeg -hide_banner -loglevel error -threads 8 -i /tmp/media-kit-DV-P5.mp4 -vf "select='not(mod(n,50))',signalstats,metadata=print:file=/tmp/media-kit-p5-1fps-signalstats-20260924.txt" -an -f null -
```

元数据文件 SHA-256 `44c8edce5553995ed1f313066452916aacacdec989e60a053d77a8ad3c319cec`。每秒抽样不能排除未抽样帧含 1021–1023：若设备 sampler 先将 `code/1020` 截到1，这些高端值将不可逆地合并为1020；不能仅凭当前精确匹配宣布全10-bit范围无损。主机 float32 模拟在假定 `code/1020` 且代码范围0–1020时，校正量化对所有1021个值均能返回原代码；这是数学检查，不是设备全范围验证。

随后对**同一原始文件的所有视频帧**做 `signalstats`，不再每50帧抽样：

```sh
ffmpeg -hide_banner -loglevel error -nostats -progress /tmp/media-kit-p5-full-signalstats-progress-20260924.txt -threads 8 -i /tmp/media-kit-DV-P5.mp4 -vf "signalstats,metadata=print:file=/tmp/media-kit-p5-full-signalstats-20260924.txt" -an -f null -
```

FFmpeg 正常退出，进度末尾 `frame=6609,progress=end`；帧 PTS 范围 0.00–132.16 秒，对应视频 50 fps、duration 132.18 秒。输出逐帧元数据也是6609组，Y/U/V 全片最大分别为 **883（PTS56.62）/888（PTS18.40）/902（PTS62.56）**，没有一帧任一分量最大值达到或超过1020。完整元数据 `/tmp/media-kit-p5-full-signalstats-20260924.txt` SHA-256 `a421b935fdbd663ff95f5435979fe0a2c7c02b93baf5178f6ef226bbc647fb5c`。因此这条固定 P5 素材的软件解码原始分量没有 1021–1023，消除了**本素材**在该极端代码区间触发 sampler 截断的担忧；不证明设备在该区间的行为，也不泛化至别的素材。当前真机校正读回只覆盖中心40帧与单帧九宫格，尚未逐像素扫描硬件输出全片。

后续门禁：在本素材较高的代码值位置/PTS复核硬件采样尺度；直接比较 RPU reshape 后的输出数值/图像；在无热路径读回的相同包 A/B 性能轮确认没有退化；真人可见颜色、流畅及 PQ HDR 激活分别验收。校正保持**默认关闭**。

设备清理状态：完成连续时间窗实验后，目标机与另一台设备曾同时从 `adb devices` 消失，首次强停应用与属性归零命令均返回 `device not found`。稍后目标机 `3EP7N18C28016072` 重新出现；已明确指定该序列号强停 `com.example.media_kit_test`，并逐项置0、回读确认 `p5_rpu_probe,p5_raw_yuv,p5_raw_mrt,p5_raw_packed10,p5_raw_pixel_probe,p5_raw_spatial_probe,p5_raw_code_scale` 均为0，`pidof` 无应用进程。手机保留已安装8345包，未误操作另一台设备。
