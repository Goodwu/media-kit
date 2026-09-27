# P5 自身转 PQ：精确固件私有诊断路径（12541–12543）

## 范围与构建

- 设备：Huawei LYA-AL00，Android 10/API 29，固件指纹 `HUAWEI/LYA-AL00/HWLYA:10/HUAWEILYA-AL00/10.1.0.163C00:user/release-keys`。
- 本地 `/data/local/tmp/media-kit-p5-full.mp4`，3840×2160 DV Profile 5；横屏全屏 PlatformView，`gpu-next`/`mediacodec`，arm64 自建 JAR `f745146332b532d8baeb162b7a33ddefa03ae8dc0a7731f13a9584ef7e6fa3f9`。12543 APK SHA-256 `7060f27da83b9b7a6ac009dde78166cffe6f1c6cd202f3d4ed1b95304e0248ce`。
- `debug.media_kit.p5_direct_dataspace_probe=1` 启用精确固件限制的内部 `ANativeWindow` perform 探针；它不是 Android 公共 API，也不是通用产品出口。12539 探针关闭时公开 setter 返回拒绝，`wid=0`，见[前一轮](android-native-hdr-firstframe-12537-12539-20260927.md)。

## 结果

| 包 | 证据 | 结论 |
| --- | --- | --- |
| 12541 | 私有 perform 两次 `0`，dataspace 回读 `163971072`；随后 Dart `pq Surface dataspace was not applied` | 旧 View 的 Surface owner 仍参与 Factory 的颜色空间 ACK，应用在打开媒体前失败。不能据此判私有 PQ 设置失败。 |
| 12542 | `gpu-next`/`mediacodec`，全屏 5 秒截图有实际画面；SF 视频层 RGBA_1010102、BT.2020/PQ，HWC 为 BT2020_PQ | Factory 跳过无有效绑定 Surface 的旧 owner 后，精确固件诊断路径再次出画。 |
| 12543 | 三独立进程触摸按下→视频 Surface PixelCopy 可辨内容 4.079、3.953、4.009 秒；2 秒 SF 视频层已有 PQ activeBuffer，截图仍为黑色片头，6 秒截图有画面 | 此时间包含片源黑场，不等于首个已解码 HDR buffer 或面板发光时刻。 |

12543 的首次 PixelCopy 成功采样曾命中预全屏旧 Surface（1440×810）；后续 `first_content` 没有记录 target 身份，故以上读回时延只能作为本轮粗估。下一轮探针需只接受当前全屏视频 Surface，并分别计首个 buffer 与可辨画面。系统 PQ 合成证据由 SF/HWC 和全屏截图补足；未经真人本轮观察，不宣称面板观感验收。

`PlatformVideoViewFactory.setColorSpace()` 的通用修复仅让 `wid != 0` 且 Surface 有效的 View 参与 ACK，避免替换后的无效旧 View 否决当前有效输出。私有探针的精确固件/内部 opcode 代码仍需单独决定产品策略，不能将这个修复等同于公开 PQ 出口已可用。

原始日志、SF 和两张截图保存在 `artifacts/android-p5-private-pq-firstframe-12541-12543/`。每轮结束均恢复原 12492 APK、P5 诊断属性 0、自动亮度模式 1 并熄屏。
