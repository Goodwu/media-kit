# P8.4 双视图轮换暴露残留视图黑屏：10452

后续校正：本轮把 `ValueKey` 放在未加 key 的 `Expanded` 内，A/B 换位会额外重建 PlatformView，因此不能仅凭本轮黑屏给控制器定因。10453/10454 将 key 移至外层后，分别验证移除备用仍可见、移除当前后剩余视图冻结；以`android-p84-dual-view-10453-10454-20260927.md`为最终对照依据。

- LYA-AL00/API29，固定完整 P8.4 MP4 SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`。10452 APK SHA-256 `7a5aa0e9d9823583bdeed09140fc5ba00ce528e0a26e7b1f7f62207c280e344a`，默认发布 libmpv、HDR 事务/PlatformView/提前停轨开关与 Surface 时间线。新增仅诊断包启用的同一 VideoController 双 Video 轮换：A→A+B→B→A+B→A，各阶段间隔5秒。
- 一次 `ANDROID_HDR_OPEN` 后媒体位置在 phase1/2/3/4 分别约4.871/11.378/16.449/21.454秒，均 `playing=true`。绑定先后为A、B，轮换中多次重建 Surface；`vid=no`先于`vo=null`，没有 POC 错误，视频参数重回 MediaCodec/HLG。
- phase4 移除当前 B 时，日志显示 `wid=11186` 的 producer 停止与引用释放，但之后没有为仍在页面的 A 发起新的 bind；t90 `time-pos=40.175878` 且 `pause=no`，VO/decoder 计数为空。随后系统截图几乎全黑，仅状态栏图标可见，故“媒体时间前进”不能证明持续可见帧。需要先核实测试页在 Flutter 轮换时是否保留了 A 的 PlatformView identity，再决定修控制器的存活 Surface 选择或测试页布局。
- 过滤日志 `android-p84-dual-10452-20260927.log.gz` SHA-256 `053ab2eb5dadac25a58730e3e9af6e17d96d2fc677a7ed5a90fa6745f761ab3a`；截图 `android-p84-dual-10452-final-black.png` SHA-256 `901867a17b60f8b685fc024b97918e2485ae2781f2085efa1e73b56bd4870668`。本轮尚未达到双视图验收，不将提前停轨开关升为默认路径。
- 测试后已强停，安装回原10420，删除临时1.1GB副本与手机截图，恢复自动亮度1/设置37。
