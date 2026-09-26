# P5/普通 Main10 私有 AHB 的 Vulkan 1.1 属性查询（2026-09-25）

目的：验证独立 Vulkan 1.1 能否查询华为硬解实际 `0x325` AHardwareBuffer 的 external format 与 YCbCr 属性，不修改 libplacebo/播放器后端。JNI 探针位于 `artifacts/android-p5-vulkan-ahb-probe/vulkan_ahb_probe.cpp`；复用独立 MediaCodec→ImageReader.PRIVATE/GPU-sampled Java 驱动。三个输入分别为普通 Main10 无损图案、P5 无损图案、原始 4K P5 前 512 帧 hvc1 诊断副本。原始输出在同目录 `*-run.txt`，已记录 SHA-256。

三种输入、首帧及 P5 图案 PTS10 均得到 `AHB format=805 (0x325)`、`VK_ANDROID_external_memory_android_hardware_buffer` 扩展存在，`vkGetAndroidHardwareBufferPropertiesANDROID` 返回 `VK_SUCCESS`。Mali-G76/Vulkan 1.1 报告 `format=VK_FORMAT_UNDEFINED`、`externalFormat=253`、`formatFeatures=0x861001`、component swizzle 全 identity。该 feature mask 含 sampled image、linear sampling、midpoint chroma、cosited chroma、YCbCr linear filter；**不含** explicit reconstruction/forceable。建议值为 YCbCr 601、ITU narrow、X/Y cosited_even，三个输入相同。原始 4K P5 AHB 尺寸 3840×2160；两个小图案为 256×144。该查询不导入 VkImage，也未执行 Vulkan 采样/读回。

判定：私有 `0x325` 在该驱动上可经 Vulkan external format 路线接入采样，且允许分别试 midpoint/cosited；建议值不能作为 P5 的真实颜色标准。尤其同一驱动对 P5 也建议 601，说明不可据此替代码流元数据。没有 explicit reconstruction feature，用户建议的“强制 explicit reconstruction”在此 external format 上不可用。尚不能判定 GL raw sampler、MediaCodec/Surface 谁造成原 P5 的 24,348 个 Y 差异或满码合并；需要实际 Vulkan identity sampler 同帧数值读回。identity sampler 自身还执行 YCbCr range expansion，比较时须按规范逆算码值，不能直接把 shader 浮点当 GL raw 值。

已有独立门禁：同应用 SurfaceView 已枚举 Vulkan 10-bit/FP16 格式但无 PQ/HLG colorspace（`android-hdr-vulkan-surface-probe-20260925.md`）；`ANativeWindow_setBuffersDataSpace(BT2020_PQ)` 直接返回 `-22`（`android-hdr-nativewindow-support-query-20260925.md`）。因此本次 AHB 输入能力不改变 GPU HDR 输出门禁。下一步优先 Vulkan identity 同 AHB/同帧 Y hotspot 与满码测试；直采 libplacebo external YUV 的融合 patch 应在数值和 4K50 对照后评估。

设备试验后移除本轮 `/data/local/tmp` 探针和样本；测试应用仍为 10369、无应用进程、`debug.media_kit.vk_hdr_probe=0`。未安装 APK、未改播放器后端。

## 后续导入门禁

同一探针扩展为实际 `vkCreateSamplerYcbcrConversion(YCBCR_IDENTITY)`、以 `VkExternalFormatANDROID` 创建 VkImage、通过 `VkImportAndroidHardwareBufferInfoANDROID` 导入 AHB 内存并 `vkBindImageMemory`。普通 Main10 首帧、P5 图案首帧和 PTS10、原始 4K P5 首帧全部得到 `samplerYcbcrConversion=1`，`createIdentityConversion=0`、`createImage=0`、`importMemory=0`、`bindImage=0`。三份原始输出为 `artifacts/android-p5-vulkan-ahb-probe/{main10,p5-pattern,p5-original}-import-run.txt`，SHA-256 分别为 `1676407a63bd4f242e182c437a3f712d00f136312b944e611c5cad1e94714ac8`、`1517e6971e483cad74c4ee0124cb432dfbbfa3474de648350743688ef39e528a`、`0bd9682c49881810a60b471a1e76db068d52c70a6e35d57678f3f465fbc2091c`。这只证明 Vulkan 导入和 identity conversion 对象创建可行；实际像素结果见下节。

## Vulkan identity 实际同帧取样

后续加入独立 compute shader `artifacts/android-p5-vulkan-ahb-probe/sample.comp`，构建 `sample.spv`，将导入的 external VkImage 通过 immutable YCbCr identity sampler 取样至 host-visible SSBO。Java 入口扩展到550帧以取得原始4K P5的 `timestamp=10,000,000,000ns` / 输出序号500；前一次312帧运行只取到首帧，不用于热点判断。固定10坐标与已有GLES诊断一致。Vulkan range先按驱动建议 narrow 查询，再用 `-DVK_PROBE_FULL_RANGE=1` 单独构建 full-range identity；后者不额外做 YCbCr→RGB 矩阵，shader输出按 `(Cr,Y,Cb,A)` 解释。下列结果均为同输入/同PTS，**GLES 与 Vulkan 属于两次独立解码运行，不是同一 AHB 同时导入**。

原始4K P5 PTS10 的 full-range 输出乘1023并四舍五入，两轮逐点完全相同，且10/10坐标与先前GLES raw Y逐码相同：

| 坐标 | 独立软件 Y | GLES raw Y | Vulkan full Y×1023取整 |
| --- | ---: | ---: | ---: |
| 2577,1221 | 182 | 276 | 276 |
| 2576,1221 | 193 | 280 | 280 |
| 203,1105 | 726 | 668 | 668 |
| 1762,939 | 706 | 650 | 650 |
| 2215,1113 | 728 | 673 | 673 |
| 1785,963 | 708 | 656 | 656 |
| 2577,1220 | 334 | 339 | 339 |
| 三个对照点 | 120/421/415 | 120/422/416 | 120/422/416 |

full-range 原始输出、第二次运行、`compare-full.json` SHA-256 分别为 `c2a29e54fd2eee0d59181d7ddcf1de0c7b83d16026c13e541ac1bee9754afd45`、`28b1150357197731f113a73ebf99208a96de4bd915980644ae7814d5fa28d1b0`、`49af4fdfe8ee231ac9a6e72806f0afe1190f719a8c811349b7e9c19c74536018`。解析/对照脚本为 `tools/p5_vulkan_identity_compare.py`。narrow-range 两轮也逐值相同；按 `(Y-64)/876` 逆算后相对GLES最多差1码，主要是range展开/浮点取整差异，故采用full-range结果作直接对照。

无损P5图案 PTS10 在 y10 的 x233/234/236 对应输入Y=1011/1020/1023；Vulkan full-range 的 Y 分别为 `.991176486/1.0/1.0`。因此1020和1023在Vulkan采样输出仍合并，复现先前GLES的满码现象。图案原始输出 `p5-pattern-full-run.txt` SHA-256 `7f46476a6735cefb56206564b3b78380c2f0c94f626c574d40f34975dbbe3f28`。

判定：七个原P5 Y异常热点跨独立Vulkan/GLES路径复现，且十个固定点码值一致；满码合并也跨API复现。故它们**不是GLES专有shader/FBO量化错误**。仍不能把责任唯一归到MediaCodec、Surface/HFBC→LINEAR或两种API共同使用的Mali外部图像采样硬件；也不能以十点外推全帧。下一步若要拆分，优先在**同一AHB**双API采样并寻求原生整数YUV检查点；直连libplacebo的性能实验可并行，但不会自行修复这些输入侧异常。实际4K50素材最大码≤902，满码图案问题不解释其卡顿。

再次清除本轮设备 `/data/local/tmp` 探针及输入；应用10369、无进程、HDR探针属性0。没有安装APK或改变播放器后端。
