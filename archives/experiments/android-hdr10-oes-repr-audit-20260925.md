# HDR10 Texture OES 表示参数审计（2026-09-25）

## 问题与证据

普通 OES mapper 把原输入参数复制到 `dst_params`，只改 `imgfmt=IMGFMT_RGB0`。担心原输入的 BT.2020 YUV limited 表示仍被 gpu-next 当作 OES RGB 数据处理。

11081 临时诊断包（JAR SHA-256 `48a3e5919a30dffe67f4b05f29df07802b91886dc49d0d3f47f0bea5401d44ec`）在 `vo_gpu_next.c` 的 `mp_image_params_guess_csp` 之前记录：`OES_REPR imgfmt=1017 sample=0 color=0 shift=0 sys=4 levels=1`。完整日志 `/tmp/media-kit-hdr10-oes-repr-11081-logcat.txt` SHA-256 `21fe27bbcf1fafe386dfab76f1eb9362de9ac8bb6eabcce0bb78edac0bbb8388`；临时补丁见同目录 `android-hdr10-oes-repr-probe-20260925.patch`。

固定 mpv 源码 `video/out/vo_gpu_next.c:669` 随后调用 `mp_image_params_guess_csp(&par)`，再将 `par.repr` 交给 libplacebo。`video/mp_image.c:1015-1017` 对 RGB 像素格式强制 `repr.sys=RGB`、`repr.levels=FULL`。因此上面的 `sys=4 levels=1` 是转换**之前**的中间状态，不能作为最终渲染器收到 YUV limited 的证据；这个特定的“双重 YUV 矩阵”猜想被源码路径排除。

同一日志显示输入 bit encoding 三字段全零。固定 libplacebo `src/renderer.c` 的 `fix_frame` 会在 sample depth 未指定且纹理为 UNORM 时按包装格式推断深度；`src/colorspace.c` 对 full-range 且 sample/color depth 相等时归一化系数为 1。这解释了仅把 OES 包装格式从 RGBA8 改为 RGB10_A2 时，固定暂停帧最终 8-bit SDR ROI 仍逐字节相同的可能原因；它**不能**证明真实 GPU 采样精度、所有帧的转换精度或最终颜色正确。具体 A/B 见 `android-hdr10-oes-iformat-ab-20260925.md`。

## 状态

临时 `vo_gpu_next.c` 日志已撤回，工作树该文件对固定源码无差异；设备恢复基线 `versionCode=10369`。产品 OES 路径的数值/颜色仍需与独立 raw YUV10 参考或固定目标 golden 输出比较，不能用格式标签替代。
