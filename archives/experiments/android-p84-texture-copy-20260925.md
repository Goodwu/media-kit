# P8.4 Texture SDR 短时对照（2026-09-25）

后续位深复核确认本轮 `mediacodec-copy` 为8-bit NV12；当前工作树已将其限于显式 `MEDIA_KIT_ANDROID_TEXTURE_COPY_DIAGNOSTIC=true`。本轮APK构建于收紧前；该结果仅供吞吐诊断，见 `android-texture-copy-bitdepth-gate-20260925.md`。

目标机 LYA-AL00，已登记 SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443` 的完整 P8.4 3840×1920/29.97fps 样本。当前工作树 debug APK 11060 SHA-256 `4ead8e2d8dd43b51441bb4c75b29138ce4623559f0821301b69340dcf8855810`。配置为 `gpu-next`→Flutter Texture、非 P5 `mediacodec-copy`、P8.4 基层滤镜 `format=dolbyvision=no`、BT.709/BT.1886 与 `bt.2390`，纹理最大宽1440。事务在配置时会检查滤镜属性包含指定标签，故打开成功说明该配置未被拒绝；本轮未独立读回逐帧 RPU 消费状态。

真机日志显示会话识别为 P8.4，视频输入 `nv12`、BT.2020/limited/HLG、3840×1920，目标纹理请求1440×720；没有11057/11058直MediaCodec的输出端口分配失败。完整文件复制/核SHA使首段应用计时处于 idle，t60 开始有视频time-pos=4.170833秒，t90=34.167467、t120=64.197467，两个30秒窗口连续推进约30秒，三点播放器与解码器掉帧计数均0、pause=no、idle=no。两张相隔约5秒的系统截图，视频ROI `(0,370,1440,1090)` RGB SHA分别为 `75f88f8f598c022fd49f0b12f67b5b15da405fd7a5b375d7aa2fe4cd8e613e81` 与 `d8e480988b51297245a964f5e83d0a31140fd4f47edf4493118b5ef122bef3b8`，差异覆盖视频区域。原日志、截图、SF dump 见 `artifacts/android-p84-texture-copy-20260925/`。

此为 S2 的机器侧短时播放证据，不是颜色、10-bit精度、物理present、真人流畅或长稳验收。`nv12` 需要进一步确认实际位深；P8.4 RPU 是否在所有阶段均未影响输出，还可用已验证同基层的有/无 RPU 成对样本做GPU路径 A/B。S1/S3及平台HDR路线保留各自独立门禁。试验后停止应用并清掉可重建暂存，恢复官方10369基线包。
