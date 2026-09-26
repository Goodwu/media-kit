# HDR10 先停轨解绑交叉验证：10451

- LYA-AL00/API29，固定完整 HDR10 MP4 SHA-256 `e4f869b140e3ef322b7fc63fefe015593708f6443fc79060fa3e7f2234816937`，设备原有可读副本 `/data/local/tmp/media-kit-hdr10-full.mp4`，默认发布 libmpv。10451 APK SHA-256 `353e00fde3c6f89fd49c1c84032604f61c4cbd176f1671c9920b0d0a9817b2f5`。自动亮度1/设置37。
- 使用 HDR 事务、PlatformView 和默认关闭的提前停轨诊断开关。一次 `ANDROID_HDR_OPEN sample=hdr10`；视频参数 `mediacodec`、BT.2020/PQ、3840×1920。两次 Home→前台均在首次`vo=null`前严格完成`vid=no`，bind后恢复同样的视频参数。日志未见 HEVC POC 错误或后台软件格式切换。两次自动恢复记录媒体位置17.317→18.499秒、30.664→32.000秒；t90媒体61.228秒、pause=no、VO23、decoder掉帧0。
- 同轮 SurfaceFlinger 回读视频层 `BT2020 SMPTE 2084 Limited range`，HWC `BT2020_ITU_PQ`、HDR metadata types=3；证实此轮仍走系统PQ合成。未测切换瞬间真人可见顿挫，也未做关闭开关的HDR10对照。
- 过滤日志 `android-hdr10-detach-10451-20260927.log.gz` SHA-256 `c77d1afa4444ee4435be3246d3b7d778648cb916b472799da466f554eaedca0b`。结束强停并恢复原10420、自动亮度1/设置37；未删除设备上原有 HDR10 源。
