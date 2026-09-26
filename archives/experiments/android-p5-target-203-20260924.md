# P5 SDR目标峰值203 nits受控诊断（2026-09-24）

**截图目标口径纠正**：背景中的主机原尺寸MAE7.52来自sRGB `video`截图，非BT.1886同目标；后补窗口目标截图为MAE7.41/最大35。本文手机同PTS显式203 nits九点对照不受此更正影响，见`android-p5-screenshot-target-correction-20260924.md`。

疑点：手机3840×2160 RPU后目标结构日志`target_max_luma=0`（未显式设置），主机同BT.709/BT.1886目标报告203 nits；原尺寸PTS10九点仍MAE7.52、最大35个8-bit级。隔离mpv增加默认关闭的`debug.media_kit.p5_target_203=1`，仅在`p5_offscreen_native=1`时将`apply_target_options`后的目标峰值显式设为203.0，其余P5硬解/逐帧RPU/packed10/`1020/1023`/3840×2160 RGBA8离屏诊断保持相同。

8366开轮实际命中PTS10.000：目标日志`max_luma=203.000000`，RPU映射哈希`56b1ba4e`，九点`download_ok=1,gl_error=0`，RGBA36项与先前8364默认`max_luma=0`、同PTS/同原尺寸轮**逐项相同**。8366同包关轮及关轮重跑均首次读到PTS10.020，九点彼此36/36相同，但**不可与开轮PTS10.000做直接A/B**。此路径的VO掉帧会影响首次实际呈现帧，不应把PTS10.020与PTS10.000的场景差误判为峰值影响。源码`pl_color_space_infer`在未标记BT.1886目标最大亮度时会按`pl_color_transfer_nominal_peak`推断；本轮具体像素结果与默认SDR白203 nits等价相符，但只在九点/该素材/该输出条件验证，不能扩大为所有目标或排除其他渲染差异。

8366 APK`/tmp/media-kit-p5-target-203-8366.apk` SHA-256 `1bb37f6b459d76c7805d1ab3baec605829071cb5bd16ded01479432c738d514b`；开日志`/tmp/media-kit-p5-target-203-8366-on-logcat.txt` SHA `cf6f43e9b223cf44fd146bba973e785cc40ea38330eb352e6f2d0829883c40e7`；关与重跑日志SHA分别`cf0bc867889a71eabf0ff6dce481bee9887f291d37d7a3c603042576f153342e`、`9303525d2b5801537d263ab706f5b6fdb7bc0428095fd8da72cc0d6d5fb78f58`。整合mpv补丁`android-p5-target-203-8366-integrated-mpv-20260924.patch` SHA `f0beb2137d7a3243a992b39af80c6d5b9e55177d6ef6009e825cd66d2a400799`。arm64构建、APK签名/验签、隔离mpv diff-check通过。设备实验后强停，15项P5诊断属性全0，无应用进程；保留8366包。

下一步优先核对Android GLES与Mac Vulkan上libplacebo实际渲染参数/版本及输入平面采样，而非继续假设目标峰值0代表0 nits。P5独立画质、PQ HDR、长稳和真人可见验收仍开放。
