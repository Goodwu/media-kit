# P5 主机截图色彩目标纠正（2026-09-24）

**纠正先前原尺寸比较的证据口径**：mpv `vo_gpu_next.c::video_screenshot` 的`video`模式（`args->scaled=false,args->native_csp=false`）将截图目标设为`pl_color_space_srgb`，即便同一进程`video-target-params`报告窗口为BT.709/BT.1886。故早先主机3840×2160 `screenshot-to-file ... video` PNG与手机BT.709/BT.1886离屏RGBA8**并非同色彩目标**，其MAE7.52/最大35不能称为匹配目标的最终色彩差。`window`模式（`args->scaled=true`）调用`apply_target_options`，会使用显式BT.709/BT.1886设置；它仍是一次额外的8-bit截图渲染，不是直接导出Mac的bgr10a2交换链或光学测量。

以主机隔离mpv/libplacebo7.365.0，同原片从0顺序解码到PTS10，原尺寸3840×2160，保持`target-prim=bt.709,target-trc=bt.1886,tone-mapping=bt.2390,scale=dscale=bilinear,dither=no,hdr-compute-peak=no`等设置，IPC确认窗口目标3840×2160/BT.709/BT.1886/203 nits。`screenshot-to-file ... window`取得8-bit RGB PNG`/tmp/media-kit-p5-mac-7365-window-pts10.png` SHA-256 `f997b44582208aa3f7a47f7c17e30a03bee49746143b427beaea0454dfe38dc0`，脚本`/tmp/media-kit-p5-match-host-7365-window.py`。按`y_png=2159-y_gl`对手机8364的同PTS/3840×2160九点，RGB27项MAE**7.41**、最大**35**级；旧sRGB `video` PNG为7.52/35。差异仍大，但应把7.41/35当当前较合理的**同目标候选诊断**，不是手机色彩错误证明；手机硬件采样、Mac Vulkan/手机GLES与截图额外渲染仍未完全等价。

同BT.1886 `window`模式另测主机Homebrew libplacebo7.360.1：PNG`/tmp/media-kit-p5-mac-7360-window-pts10.png` SHA `276edf4f6c73122d37b79b3b29a9c4ff587af92a416657727d853a3579e6f656`，九点对手机MAE7.44/最大35；与7.365轮只有右中像素绿通道相差1。色度位置居中轮`/tmp/media-kit-p5-mac-chroma-center-window-pts10.png` SHA `e19241093772bd8bd6ab0091e2fd5a5935e88f9f869595ad53804c0dd466c510`，同7.360窗口基线九点仅少数组件变1，对手机MAE7.37/最大35。故此前“版本/简单色度位置不是九点主要差异来源”的方向在正确色彩目标下仍成立，但原有具体MAE需以本轮数值替代。

下一步若要定根因，应比较进入Dolby Vision reshape前的等坐标/邻域采样与中间阶段，或建立两端同输入纹理和同精度离屏目标。当前PNG均非独立色彩真值；P5最终可见颜色、PQ HDR与长稳仍未验收。
