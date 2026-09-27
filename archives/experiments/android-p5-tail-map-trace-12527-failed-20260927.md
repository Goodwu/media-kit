# P5 尾段 map 轨迹诊断包 12527：启动崩溃，作废

在隔离 mpv 源码的 AImageReader mapper 加最近16次 map 的源帧/codec buffer 身份、PTS、release 结果、AImage 时间戳与 callback 数记录，准备仅在取图失败时输出。压缩源码补丁 `failed-probe.patch.gz` 和崩溃摘要存于 `artifacts/android-p5-tail-map-trace-12527/`。使用自建 arm64 JAR 构建诊断 APK 12527，尚未进入 P5 尾段，首次播放初始化即 SIGSEGV；栈显示 `vo_gpu_next.c` 的 `info_callback` 重复递归，并非目标 `P5_MAP_FAIL` 轨迹。因此**12527 无效，不能用于推断紫屏根因**。

手机已强停并恢复日常 APK12492、自动亮度、熄屏。实验 AImageReader 源文件已与修改前备份逐字节比对后恢复，失败 JAR 已删除。构建目录仍是临时生成状态，后续如再做此探针须先重建并验证基础播放，不能沿用12527。P5尾段紫屏任务仍以12526的可复现短轮为依据。
