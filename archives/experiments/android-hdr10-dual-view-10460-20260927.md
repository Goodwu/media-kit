# HDR10 双视图存活输出回退：10460

- LYA-AL00/API29，固定完整 HDR10 MP4 SHA-256 `e4f869b140e3ef322b7fc63fefe015593708f6443fc79060fa3e7f2234816937`，默认发布 libmpv、PlatformView/HDR 事务、提前停轨诊断开关。稳定外层 key 的 A→A+B→B→A+B→B，最后移除当前 A、保留存活 B。自动亮度 1/设置值 37，未调至最高亮度。
- APK versionCode 10460，SHA-256 `b59327c9baebb1a809550508c8c21cfb1747ca2d7291f4b102ac0797159c5101`，产品控制器代码与提交 `b1c97ec` 一致。phase4 于 02:50:28.885，A `wid=11146` 于 .997 释放，B `wid=11354` 于 .998 请求回退绑定、02:50:29.073 完成。phase1/2/3/4 媒体位置约 4.871/11.678/15.248/21.655 秒。
- 间隔 5 秒的系统截图在视频区域像素不同，证明 B 持续出图。同轮 SurfaceFlinger HWC 回读 `BT2020_ITU_PQ`、HDR metadata types=3。这证明 HDR10 的双视图回退与当前 PQ 合成，不证明独立色准或人工观感。
- logcat `android-hdr10-dual-10460-20260927.log.gz` SHA-256 `f4cdcef800297f3ff6addbf0b21152bbd3cb37c7808f7420a3b4ba9d876e499a`；截图 a/b SHA-256 `2d989c4de39837b02f8361b174b8473a067e971ec599fa0a5ea2de3a3e32b5bc` / `7205d377ae4a7003c032d1a8a0e136bd7ab396cc6598182bef30d6701fc5f8d1`；原始 SF dump 压缩件 `android-hdr10-dual-10460-sf.txt.gz` SHA-256 `647f01258c7cd7cc5102e26ad087211b76f7ca876d038b185a009aab98a8a1a3`，未压缩原文 SHA-256 `7c4a42913b9f379c7fb0ff2fbab3b06c2127cb53d88079c163fae1056f02ec52`。
- 结束恢复原 APK 10420、自动亮度 1/设置值 37，删除手机测试源副本。P5/SDR、交错及 engine detach 仍需单独覆盖。
