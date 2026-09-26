# HDR10 Texture 外部 OES 8/10-bit 格式描述 A/B（2026-09-25）

## 结论

固定 HDR10 真机同一5秒暂停帧，mpv `vo_gpu_next.c` 调用`pl_opengl_wrap`前，基线从`ra_find_unorm_format(1,4)`得到8-bit RGBA格式描述；诊断组仅将外部OES的`iformat`改为`GL_RGB10_A2`。两组均直MediaCodec打开、BT.2020/PQ输入，截图视频区域`(0,370,1440,1090)`的RGB字节SHA-256同为`584e91e8b5e83a4feb22e8e42b275a8c9f900e4688f3a4f787935c706c2b6ebf`，逐字节相同。故**仅更改libplacebo包装时的位深格式描述，对该帧最终8-bit SDR截图没有可见/数值影响**。这不能证明内部保真、所有帧或真实显示颜色相等，也不能推出普通OES本身只有8-bit。

## 单变量与有效截图

- 两组同一设备完整HDR10源、Texture/gpu-next/直MediaCodec、目标宽1440、`MEDIA_KIT_ANDROID_HDR_PAUSE_AT_MEDIA_SECONDS=5`。日志均回读`ANDROID_HDR_MEDIA_PAUSE target=5000 timePos=5.005000 pause=yes`、硬解端口17槽成功。基线11078 JAR SHA-256`b8ad46c1cd359aa4d3651eeab06dc5ca6994de3dab998afc9e4722e34526d699`；11079诊断JAR SHA-256`1c5f2664a16fa47c75ed18c5c332a32a2feb7d73778160db75d121a34324c95d`，APK SHA-256`69971d5ddfac46ca380f921df3aa043c2c7c6e62f2c81d641f2177da55cc9c82`。诊断源码单行作用补丁`android-hdr10-oes-iformat10-probe-20260925.patch`。
- 11079第一次截图被系统通知遮挡，已排除；用`cmd statusbar collapse`恢复应用前台后，对仍暂停的同一帧重拍。有效两张全屏截图、压缩日志和逐字节比较结果位于`artifacts/android-hdr10-oes-iformat-ab-20260925/`。两张全屏图的系统UI时间不同，**只比较视频ROI**；该ROI的差图bbox为空、RGB平均差0。
- 原生库允许`GL_RGB10_A2`包装且未观察到新的导入/渲染失败，但无完整内部libplacebo采样值和输出前高精度FBO读回。最终截图为系统8-bit采集，细小高精度差异可能被后续SDR量化掩盖。因此结果只否定“改一个格式标签即可改变/修好最终画面”的简单假设。

诊断改动已从独立mpv源码撤回，重建库SHA恢复为基线`56e48164a70159849821ca16f45aad09c4e09386b1b8fe6f1ba4abf96fdd0d05`。手机已恢复`versionCode=10369`，测试暂存已清理。下一步需在**mpv实际普通OES采样之后、libplacebo色彩处理之前**做高精度定点读回，或建立同PTS最终SDR数值参考，才能判定输入保真和转换颜色。
