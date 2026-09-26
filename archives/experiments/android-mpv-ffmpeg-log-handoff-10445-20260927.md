# mpv 多实例 FFmpeg 日志接管实机复核（2026-09-27）

- 根因：mpv 原 `common/av_log.c` 仅在第一个实例初始化时安装进程级 FFmpeg 回调；第二实例与第一实例短暂重叠时未接管，第一实例随后销毁又将回调重置为默认 stderr。因此 10442 第二段虽硬解/有图像，但 Flutter 流丢失 RPU 探针记录。10444 在旧实例退出后创建临时第三实例重绑回调，直接恢复第二段 RPU 记录，支持这一判断。
- 修复：Goodwu/mpv `fix/ffmpeg-log-owner-handoff` 提交 `9acfeff`，保持最早存活实例为进程级日志接收者，退出时将回调交给下一存活实例，最后实例退出才恢复默认；切换前释放日志缓冲。FFmpeg 回调没有 mpv 归属信息，实例重叠期不能按接收 Player 判断日志来源。独立 V1 审查后无剩余阻断，Android arm64 单文件编译和链接成功。
- 诊断 JAR SHA-256 `91f5c6bb386cb87a5c77c20d65eb40a5bf0203d9efabc7aff80f92bc399f978c`，其中新 strip libmpv SHA `8005f120c3bbab97335312a001dedd3e5e41feeb62853cb367889262936a7b1f`；10445 APK SHA `6373ccd9d6ffa80ccae81f766e680094c4ecd13ff74c1e7cf5cc7cad8448040f`，包内 lib SHA 与 JAR 一致。该诊断 lib 从既有隔离 mpv 对象链接，仅替换 `common_av_log.c.o`；它不是 10444 的同版 renderer 二进制，因此本轮只验证日志接管与 P5 RPU 记录，不能用它复核画质/性能。
- LYA-AL00/API29、官方 P5 1080p24 源、HDR 事务/PlatformView/RPU=2/raw_yuv=1、自动亮度。`MEDIA_KIT_AUTO_LIFECYCLE=true` 第14秒重建；不创建 10444 的临时日志接收 Player，两个播放段各在第16秒 stop。第一段 RPU `inputs=211 outputs=201 matched=201 errors=0 discarded=10`，第二段的普通 `MPVLOG [ffmpeg/video]` 直接收到 `inputs=229 outputs=225 matched=225 errors=0 discarded=4`；AImage 分别 `200/200`、`224/224`，最终资源归零，未见 abort。证明此短轮日志接管生效且实际解码输出 RPU 对应；长期多实例与颜色仍未验收。
- 过滤日志 `android-mpv-ffmpeg-log-handoff-10445-20260927.log.gz`，SHA-256 `f4dc7117908210d9a8341b269c8b96f5e64bf7b9ebe23c58c44084c8e6279e37`。结束恢复原 10420、自动亮度1/设置37、三个诊断属性0。
