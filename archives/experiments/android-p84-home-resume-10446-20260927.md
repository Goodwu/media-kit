# P8.4 发布库后台返回双轮基线（2026-09-27）

- LYA-AL00/API29，固定完整 P8.4 MP4 SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`（从手机 Download 复制到临时可读路径，结束已删除副本）。10446 APK SHA `848cd6b838b1cc3ccdc009636c247c23ce05453bfe1b97ccce16f1ea684c3c3f`，包内默认发布 libmpv SHA `77319bc63a205123b403e35088401e7da61886b78bd0a678a282876cfb9c0f66`。HDR 事务/PlatformView、自动恢复及位置/PERF 日志开关；手机自动亮度1/设置37。首次启动因临时文件权限被拒绝，不纳入播放轮；修正该测试副本权限后强停、清日志重启。
- 一次 `ANDROID_HDR_OPEN dolbyVisionP84`，`mediacodec_embed` 3840×1920 原生输出；播放中 SurfaceFlinger 回读图层 dataspace `BT2020_ITU_HLG`。t90 媒体40.607秒、VO/decoder掉帧0。
- 第一次 Home：inactive 捕获playing=true/51.051秒，后台停在52.230秒；返回时于52.230秒执行自动恢复，t120走到66.500秒、pause=no，VO掉帧30、decoder掉帧0。第二次 Home：捕获73.907秒，后台停在75.311秒；返回后于75.311秒自动恢复，t150走到92.392秒、pause=no，VO掉帧62、decoder掉帧0。全程只见一次 HDR_OPEN，没有从0重开。两次切后台期间共33条 HEVC `Could not find ref with POC`，集中于后台过渡；不能将持续出图误判为无顿挫。
- 第二次返回后相隔6秒的系统截图视频内容从两个人影/树影变为临水草地场景，证明画面继续变化而非持续冻结。原图：`android-p84-home-resume-10446-a.png` SHA `962eaf253c8be64243454d56b91a72402bf822e3f8892051232aa128a3f52788`，`android-p84-home-resume-10446-b.png` SHA `471ce2568b39419eed5f24e0800c73b8596b199d2bf5c19fbe737ad05d3e378e`。截图和计数不能判定切换瞬间的人眼可见停顿长度。
- 过滤日志 `android-p84-home-resume-10446-20260927.log.gz` SHA `96e4424995a79498f626194d934767381e42d61dd0576ad508fdf9b1d95d10d6`。结束强停、恢复原10420、自动亮度1/设置37；三个P5属性仍0。
