# P5→PQ 公开 GPU 输出路线复核（2026-09-28）

目标限定 Huawei LYA-AL00、Android 10/API29、固件 `10.1.0.163C00`、普通应用 UID。此轮只读复核已有设备实验和 Android 10 AOSP/公开 API，没有构建或操作手机。

- 目标固件的 `ANativeWindow_setBuffersDataSpace(PQ)` 在真正设置前调用 HDR support 查询；11008 同一窗口 `pqQuery=-1/support=0`，SurfaceFlinger 拒绝应用 UID，公开 setter 返回 `-22`。晚设、10-bit EGL buffer 与窗口 HDR mode 的旧实验均未越过此门禁。见 `android-hdr-nativewindow-support-query-20260925.md`、`android-hdr-late-pq-after-gpu-buffer-20260925.md`、`android-window-hdr-mode-gpu-pq-20260925.md`。
- EGL 10-bit config 不等于 PQ colorspace 扩展；既有 8322 实测未声明 PQ window 扩展。Vulkan 同 Surface 枚举的10-bit/FP16格式均配 sRGB colorspace，没有 PQ/HLG swapchain 组合。见 `android-hdr-surface-dataspace-gate-20260924.md`、`android-hdr-vulkan-surface-probe-20260925.md`。
- 公开 NDK SurfaceControl 的 PQ buffer/dataspace 事务在 HDR 能力查询权限失败处触发 `invalid dataspace` SIGABRT，不能在本固件普通应用里作安全回退。见 `android-hdr-surface-control-transaction-20260925.md`。
- 目标硬件编码能力枚举没有可用的 HEVC Main10 硬编桥；软件编码再硬解的4K59.94实时性和首帧没有证据，不能用缩小画面或预转码替代目标。见 `android-p5-hevc-encoder-bridge-feasibility-20260925.md`。
- 新评估 ImageWriter：Android 10 [AOSP实现](https://android.googlesource.com/platform/frameworks/base/+/android-10.0.0_r47/media/jni/android_media_ImageWriter.cpp) 的 `attachAndQueueImage` 转交 GraphicBuffer、时间戳、crop、transform、scaling，未复制 BufferItem dataspace/HDR metadata；公开 [`Image.setDataSpace`](https://developer.android.com/reference/android/media/Image#setDataSpace(int)) 是 API33。API29 不能据此假设转交后保留 PQ 信令，更不能公开标注新生成的 GPU PQ 帧。

边界结论：本固件上已验证的公开 GPU PQ 出口均不可用，目前没有可实施的新公开候选；不推广为所有 Android 设备或面板不支持 HDR。下一步采用用户已允许的精确固件受限兼容路径：普通公开接口先尝试，仅对已核指纹和 ABI 的设备启用回退，失败即停止；独立审核调用边界和 Surface 代次，设备复核同代10-bit/PQ buffer、HDR元数据、SF/HWC、真实画面、首帧及退出 SDR 复位。已有私有探针阳性记录 `android-p5-private-pq-firstframe-12541-12543-20260927.md` 不等于产品验收。
