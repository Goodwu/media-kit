# P5→PQ 产品链路候选 12582（2026-09-28）

P0 Texture→SDR 的真人动态画质确认仍待进行；本轮只准备 P1 的隔离候选，没有安装或播放 12582。手机检查时连接正常，仍为原版 12492、自动亮度、熄屏。

## 实现与边界

- 代码仅在隔离工作树 `/private/tmp/media-kit-p5-pq-product`，分支 `feature/android-p5-pq-product`，基线主库 `721cc9c`；主工作树原有 Java/C++ 诊断修改未覆盖、未暂存。
- `ANativeWindow_setBuffersDataSpace` 仍先调用公开接口；仅当其明确返回 `-EINVAL`，且为 arm64、API29、精确固件指纹、RGBA1010102 与 BT.2020/PQ 时，才走此前实机反汇编核过的 window `perform` 操作码 19。成功必须精确回读 PQ dataspace。
- 对该固件的 PQ Surface，初始 10 秒每 200 ms、此后每秒持续检查 dataspace，覆盖同 Surface producer 重建。失效且不能重设时发送带当前 WID/代次的 `SurfaceRuntimeFailed`，Dart 记录明确错误并沿既有 stop→release→ACK 路径回收；尚未做故障注入或实机证实。
- 测试页移除旧的 `p5_rpu_probe=2`/`p5_raw_yuv=1` 调试属性门禁；`P5_RPU_PIPELINE_BUILT` 仍只是编译配置，不是独立的打包 JAR 来源证明。

## 静态与打包证据

- NDK arm64 C++ 语法、Java 目标编译及 `git diff --check` 通过；隔离 Dart 控制器分析只有原有 5 条 info，测试页四个相关 Dart 文件分析无问题。独立 V2 初审指出监测 10 秒结束和运行中失败只发 destroy 两个阻断项；已修改，修订后的协议仍待最终复审与设备故障注入。
- 使用自建 arm64 JAR SHA-256 `eac6514fd1b3409574f0b77014c9b29989e0d0868d40048cc199a822d94c660f`、隔离代码拷贝和 `MEDIA_KIT_ANDROID_PLATFORM_VIEW=true`、HDR transaction、P5 RPU build flag、预建横屏全屏、命名本地 Mystery Box 源，离线 Gradle release 构建成功。12582 APK SHA-256 `3f9c180fa55df10d0df5b80e9d2a7b8de8e2dec1ab5a34d964834e0bdb700a64`；APK 只含 arm64 native 库，HDR bridge 二进制有新 fallback 日志符号。APK 内 strip 后 libmpv SHA-256 `3350c910d9de2d38838bb3874f23a84ea5ecf764b8d18162b065bbe2b209fa75`。
- `flutter test --no-pub` 首轮在主机剩余约 117 MiB 时因 Objective-C native asset 链接 `No space left on device` 未运行测试体；清理生成中间文件后补轮，起初隔离构建目录仍使用旧测试文件而编译失败，复制同候选的策略测试文件后 `flutter test --no-pub test/android_hdr_playback_policy_test.dart` 通过 10 项。构建、策略测试与静态检查均不证明 PQ 出画、真实首帧或资源释放。

## 下一步

按既定顺序先完成 P0 Glass 真人动态观察。之后先复审修订协议，再用 12582 Mystery Box 做同代 Surface/PQ/10-bit/HDR 元数据与 SF/HWC、真实内容、首帧和退出 SDR 复位验证；若发现问题，在隔离分支修正并重建，不把旧私有探针结果算作产品验收。
