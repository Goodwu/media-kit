# P5 音频时钟诊断样片（2026-09-25）

计划 P5 性能门槛要求绝对音画差 ≤100ms；当前设备 4K/50fps `DV-P5.mp4` 与 Dolby 官方 24fps Sol Levante P5 文件经 ffprobe 都只有视频轨，故先前运行中的 `avsync` 属性为空是预期的，不能据此判同步通过或失败。

为建立可测的音频时钟，基于固定设备样本的本机副本 `/tmp/media-kit-DV-P5.mp4`（SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`）生成 132.18秒、48kHz、低音量440Hz AAC 测试轨，以 GPAC MP4Box 26.07.0_1 从原 MP4 复制视频轨并加入音轨：

```sh
ffmpeg -v error -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=132.18' -af 'volume=0.02' -c:a aac -b:a 96k /tmp/media-kit-p5-avsync-tone.m4a
MP4Box -add '/tmp/media-kit-DV-P5.mp4#video' -add '/tmp/media-kit-p5-avsync-tone.m4a#audio' -new /tmp/media-kit-p5-avsync-diagnostic.mp4
```

输出 `/tmp/media-kit-p5-avsync-diagnostic.mp4` SHA-256 `3d0dd5b00fe8f01add6bfc2eb69feb972748b12f19f2f9d24dd608c919a5daec`，约233MiB。ffprobe 回读 HEVC Main10 3840×2160/50fps、`dvh1`、Dolby Vision profile=5/level=9、RPU=1/EL=0/BL=1/compatibility_id=0，共6609视频帧、132.18秒；另有 AAC LC 48kHz 音轨，时长同为132.18秒。分别对原文件与诊断包全部视频 packet 导出 PTS、DTS、size、SHA-256，两个6609行清单**逐字节相同**，清单 SHA-256 `3d6cad74fc46bf1ebcb9160d7c740974f98eaf23850347d3570ba9c42ecc4aa0`。FFmpeg 同时解码前5秒音视频无错误。

首次用 FFmpeg 直接重封装的试件虽仍标 `dvh1`，却丢失 DOVI configuration record；尝试 `dovi_rpu` bsf 也未恢复。这些无效临时包已删除，不作样本。MP4Box 输出同时满足 DV 配置与逐包视频等价性，才用于真机**音频时钟/`avsync` 属性**测试。连续正弦音没有与画面事件对应的听觉标记，不能证明人工可感知声画同步或精确音视频硬件输出延迟；仍须以实际含同步事件的合法 P5 片或另立定量方法完成最终 ≤100ms 门槛。真机11015在960×540布局纹理目标下运行120秒、VO/解码累计掉帧0、内部`avsync`约0.02ms；对照与限制见[布局尺寸A/B](android-p5-avsync-layout-ab-20260925.md)。

诊断包曾推送到设备独立路径，设备端 `sha256sum` 与主机 SHA-256 完全一致；运行结束已删除设备副本并恢复10369基线。原 `/sdcard/Download/DV-P5.mp4` 未被替换。后续若需复播，从主机保留的 `/tmp/media-kit-p5-avsync-diagnostic.mp4` 按上述SHA重新推送。
