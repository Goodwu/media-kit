# P5 Glass 预建 Texture Surface 首帧对照，12500–12501

## Current State

2026-09-27，LYA-AL00/API29，指定Glass P5本地源 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`。在隔离测试页、SurfaceProducer Texture SDR路径，以固定3840×2160先调用`VideoOutputManager.SetSurfaceSize`，等待mpv回读非零`wid`且`vo=gpu-next`，然后才进入媒体open。这仅是已知源尺寸的诊断，不在产品默认路径。12500单轮APK SHA-256 `1697ea21b32a360fe95517f8d3afa8efbfd15e22b91af64688f4949142035cd8`；12501同APK属性关→开→关，APK SHA-256 `a4a022f2af7638034a78e7694586d49278042761225bedf4c1abcc083736256e`。每轮新进程，从片头点击`Video 0`，P5 raw/direct/RPU/retire属性1/1/2/1，自动亮度，竖屏测试页。

| 12501同包轮次 | 预建 | 点击回调→`media_opened` | 打开返回→OMX创建 | 点击回调→首个AImage | 固定区域首次非零像素 | 旧明显内容阈值 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| off1 | 关 | 0.760s | 0.996s | 2.485s | 4.718s | 4.950s |
| on1 | 开 | 0.844s | 0.031s | 1.177s | 3.476s | 3.727s |
| off2 | 关 | 0.744s | 1.269s | 2.550s | 5.137s | 5.472s |

单独12500开启轮的`media_opened→OMX创建`约0.033秒、首个AImage约0.735秒、首次非零像素3.003秒、旧阈值3.216秒。12501关/开/关回摆与12500方向一致：开时OMX创建前的等待缩短约0.97–1.24秒，首个AImage提前约1.31–1.37秒，首次非零提前约1.24–1.66秒。单轮波动、PixelCopy间隔、测试页预验证固定源仍存在，不能把这些差值当成产品收益或统计保证。

12500的`P5_TEXTURE_PRESIZE ready wid=11222 vo=gpu-next`在`media_opened`前约41毫秒；12501开启轮也在open前得到非零wid/`gpu-next`。这与12499中先`VO null`/软件HEVC、后绑定wid/硬解的顺序相对，支持“SurfaceProducer未预建导致首开硬解设备不可用”作为当前测试链的主要延迟原因。仍需确认正常产品入口和所有Surface重建条件。12501关闭两轮有17/18条Dart转发的缺参考POC，开启轮未见该报错；Dart日志送达时戳不等于原生发生时戳，不能由此断言POC本身耗时或已彻底消失。

尚未完成：预建后RPU逐帧匹配/色彩、全片性能、退出/重入、物理屏幕可见、HDR10/P8.4/SDR、冷/热多轮，以及通用初始尺寸策略。固定4K预建可能在未知视频尺寸下浪费内存或触发二次Surface重建，不应直接合入产品。Glass源自身约2.05秒片头黑场，正常从0按1倍速播放时，非黑画面3秒多仍不满足2秒目标；应分别报告首个真实视频帧和首个非黑内容。

原始日志：`artifacts/android-firstframe-presize-12500/run1.log.gz` SHA-256 `15e5d9e9bb902b3b1feb3f8cf3f5711205b3ba791a9681807273601911053ef8`；12501 `off1.log.gz` SHA-256 `2dc4a6455947008932f6bb17fe4b59f44574bbb684fd5e4663c868e67615ed0e`、`on1.log.gz` SHA-256 `46cea95d9af85ad2af5c8f928ac465168b284706443ce4ad05d2cddc5a5f85b4`、`off2.log.gz` SHA-256 `839f918c6ba96ef8f5e044cc308a1cee14b08b521d60278960b59996382f3ea5`。相对隔离基线的完整诊断补丁 `artifacts/android-firstframe-presize-12501/diagnostic.patch.gz` SHA-256 `aad3ca193ee7786743a2b8ac9f63dcb1b3cce6bc000f4bb9d58213af96800cd5`，解压原文SHA-256 `38d0ac978796907d33fa7d7ff571340bbd631fe7e01c64690972686fb95dd0a7`。

结束后强停应用、六个诊断属性复位0、恢复原12492 APK，自动亮度模式1，屏幕OFF。
