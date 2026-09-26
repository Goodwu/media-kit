# P5 L2C 检查点边界复核（2026-09-25）

检查当前隔离 libplacebo 7.365.0 `src/renderer.c`：`pass_read_image()` 先组合 native 图像，再调用 `pl_shader_decode_color()`；之后才调用 `pass_hook(..., PL_HOOK_RGB)`。颜色管理、目标映射位于后续阶段。当前手机 `vo_gpu_next.c` 的 `p5_post_rpu_full_dump` 在 `pl_render_image_mix()` 返回后读目标 FBO，因此实为 L3，不能重命名为 L2C。

建议新增默认关闭的 `PL_HOOK_RGB` 只读诊断 hook，限定单一 PTS/输入身份，在 hook 收到的 `repr/color/rect/format` 原样记录，并将 RGB 阶段纹理复制到 host-readable 高精度纹理后下载。下载的是**DV 解码后、显示映射前的 RGB 编码域**；必须读取实际 `color.transfer`，只有 PQ 时才按 BT.2100 PQ EOTF 和内部亮度单位换算出测试合同的 BT.2020/D65 线性 RGB。不能直接把 RGB hook 数值标成线性 nit。

不选择 `PL_HOOK_LINEAR` 作为第一观察点：该 hook 的存在会在 `pass_scale_main()` 中强制 `use_linear=true` 与 FBO，可能改变原本跳过的缩放流水线，干扰与现有产品路径的同帧比较。L2B reshape 输出仍早于 RGB hook，需要独立的 `PL_HOOK_NATIVE` 或更细的 DV shader 观察点。

实现门禁：保持 hook 默认关闭；按 PTS10 和 RPU hash 锁同帧；固定无缩放、ICC/LUT/OSD、chroma filter、坐标和位深；下载纹理时记录复制格式和量化误差；在同一 APK 的诊断开/关轮核验 L3 不受只读 hook 改变。主机同阶段工程参考应使用独立软件 BL 输入与同版 libplacebo，不称 Dolby 官方 golden。

本轮仅完成源码边界确认和实施设计，**未取得手机 L2C 数值**。
