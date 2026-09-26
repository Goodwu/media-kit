# Android HDR/DV 三层数值验证方案（2026-09-25）

本方案是 `archives/conversations/android-hdr-dv-display-plan-20260922.md` 的颜色/解码验证子计划。它不改变原计划 T1/T2/T4、S1–S3 的真机播放、HDR 信令、可见画面和生命周期验收。2026-09-25 已从 `~/Downloads/test_files/` 接收启动包和额外的 `DV_TestKit_v1.zip`，本机核验结果见 `archives/experiments/android-hdr-dv-testkit-intake-20260925.md`。两包只建立了部分工程参考，尚无 Dolby 官方逐帧 golden 或本项目 GPU/DV 产品路径的颜色通过结论。

## 结果词汇和参考等级

每个结果同时记录 `checkpoint`、`reference_class`、`policy_id`、`status`。参考等级：`official_conformance`（适用范围内的官方/授权一致性输出）、`formula`（公开标准公式的数值向量）、`independent_crosscheck`（不同实现交叉核对）、`approved_regression`（冻结版本的工程回归输出）、`production_master`（制作母版/画质参考）。`independent_crosscheck` 和 `approved_regression` 均属工程参考，不能写成 Dolby 标准输出；`production_master` 另作画质参考。没有适用的权威参考时写 `REFERENCE_MISSING`，不能把通过回归测试升级为 Dolby 认证。

Dolby 官方 P5/P8 输入码流仅证明输入来源；Git LFS SHA 只证明输入身份。Netflix VDM/EXR 与 XML 是制作资产，不能在未经同版/同帧证明时充当消费级有损码流的逐像素 golden。`libplacebo→libplacebo` 比较只验证接线或版本回归。Dolby CM Offline 输出必须注明工具/CM 版本、母版与 metadata 身份、target、trims 和输出域；只有经证实同一重构输入时才可用于消费码流的第三层权威比较。当前没有 Dolby 官方逐帧 P5 reshape golden 或 CM Offline 输出。

## 检查点合同

| ID | 隔离输入 | 输出格式 | 判定与当前证据 |
| --- | --- | --- | --- |
| L1：HEVC 原生重构 | 固定压缩 BL；人工无损样本则同时用编码前 YUV | 显示顺序 `yuv420p10le`，Y/Cb/Cr 独立整数码值，左上原点；逐帧/逐平面 SHA，加抽选完整帧 | 无损样本对编码前 YUV 或规范样本的重构输出逐样本差 0；真实有损片先由独立解码器交叉核对后冻结工程参考。当前 P5 PTS10 的 27/27 九点只覆盖位置，不能算整帧通过。硬件只暴露 RGB/OES 时该硬件路径标 `NOT_DIRECTLY_OBSERVED`。 |
| L2A：RPU/SEI 解析和关联 | 固定 BL 帧身份及原始 RPU/SEI | 原始字节 SHA、显示帧号/PTS、profile、复用关系、整数/有理数参数、规范化语义字段 | 原始字段和帧关联精确核对；比较字段语义，不比 JSON 文本或结构体内存。P5 长片输入6314/匹配输出6307/尾flush7是片尾关联未闭环，不能标全片通过。P8.4 兼容底层模式要证明 **忽略 RPU**，不要求消费 RPU。 |
| L2B：reshape | 已通过 L1 的原始 YUV + 已通过 L2A 的同帧 RPU；组件向量可直接给规范化系数 | reshaped 三分量 float32/float64，显式注明此中间域、范围和矩阵阶段 | identity、pivot±ε、piecewise quadratic、MMR 1/2/3阶及彩色交叉项先用公式向量；真实 DV 用独立 CPU 实现交叉参考或已批准版本回归，不能自称 Dolby golden。 |
| L2C：颜色重构 | 固定 L2B 输出；非 DV 的 PQ/HLG/BT.2020 NCL 使用公式向量 | 主输出 BT.2020/D65 显示线性 RGB，单位 `1.0 = 1 nit-equivalent`；辅助 BT.2020/PQ RGB，PQ 的 1.0 对应 10000 nit；HLG另存 inverse OETF 后 scene-linear RGB | 固定 range、chroma location、上采样、矩阵、EOTF、亮度单位及超范围处理。先灰阶后彩色；不能把 normalized RGB 当 linear RGB，不能重复 reshape/PQ。L2B/L2C 的真实 DV 标准输出目前缺失。 |
| L3：目标显示映射 | **固定且已验证的 L2C RGB** + 固定动态元数据/状态；另跑端到端输入 | 指定 target 的 float RGB 与编码值，独立保存 target/policy 状态 | 先用 hard-clip 公式向量检查单位/编码（它不是产品画质或 Dolby CM），再锁定产品 libplacebo policy 做回归；获权威 CM 输出后单列 Dolby 对照。8370 真机 `pl_render_image_mix` 后的 BT.2020/PQ/1000nit RGBA16F 是 L3 实测输出，不是 L2 reshape 检查点，也未有同域 golden。 |

L2/L3 的隔离组必须能喂入**已验证的上一层标准输入**；端到端组同时导出 L1、L2A/B/C、L3，不能只在最终图像上找原因。每层失败只归因于其输入已确认正确的隔离组；端到端前一层失败时后层标 `UPSTREAM_INVALID`，不判后层算法通过或失败。L3 后另设 **D：设备呈现门禁**，核真实 buffer 位深、dataspace、SurfaceFlinger/HWC、HDR 激活、实际 present 与真人/仪器观察；数值三层全过也不自动通过 D。

每条产品路径另交一份 `metadata_usage.json`，对实际出现的 RPU/SEI 字段逐项写明 `parsed`、`used_for_reshape`、`used_for_mapping`、`intentionally_ignored` 或 `unsupported`，并标明代码入口/运行证据。P5 reshape 必需字段不得默默丢失；P8.4 兼容 HLG 路径的 DV 字段应明确忽略。针对宣称使用的映射字段，固定 L2C RGB 后做字段 A/B；字段不影响当前目标时须注明条件，不能要求任意字段改变都必然改画面。

## 固定目标、映射策略和时序

先定义 `SDR100_BT709_BT1886`、`PQ600_BT2020`、`PQ1000_BT2020` 三个虚拟目标：D65、黑位0、明示峰值，区分输出编码容器和物理显示覆盖色域。产品实际 203 nit SDR、P3-D65/非零黑位另设 policy，不与以上 golden 混用。每个 `policy_id` 冻结 libplacebo/FFmpeg/mpv commit、tone/gamut 算法及参数、参考白/目标峰值、源峰值来源、RPU字段的解析/消费/忽略清单、自动峰值检测与时间平滑/重置策略、ICC/dither/缩放/OSD 状态。改变算法或 target 必须生成新 ID，不能覆盖旧输出。

确定性单帧组关闭自动显示器识别、ICC、dither、OSD、缩放及时间相关峰值策略；GPU 读回优先 float32，真机仅能 RGBA16F 时保留 half bits 与独立 FP16 容差。生产时序组使用真实 policy，固定从片头/seek/切源的历史和状态重置，再测场景切换、高亮单帧、淡入淡出及 RPU 帧关联。顺播帧与直接 seek 帧不能无条件逐像素比较。P8.4 分别命名 `HLG_NATIVE_TARGET` 与 `HLG_R1000_TO_PQ_TARGET`；其兼容底层产品路径忽略 RPU。P5 缺必要 RPU 必须显式失败，不输出看似正常的错误颜色。

## 样本与覆盖表

1. 启动包入库：实际检查 ZIP CRC/目录、`README_zh.md`、三个 128×64/24fps/48帧 Main10 无损文件、编码前 YUV、逐帧 manifest、PQ/HLG/reshape 向量和比较器。核其原始文件 SHA、帧数/像素格式/色彩标签，复跑包宣称的 144 帧 CPU 逐样本验证及“改坏一值必失败”自检。任何实体或结果缺失只记 `NOT_RUN`。不将该小包的通过外推到 4K、DV RPU 或 GPU。
2. `DV_TestKit_v1` 另有 256×144 合成无损 DV P5/P8.1/P8.4、P5 参数切换和 P8.1 B 帧共 120 帧，以及两个 pivot 诊断用例共 6 帧。它适合先跑 L1 整数、L2A 帧配对、L2 数学向量与 L3 固定 ETM-v1 策略，再接离屏 GPU/产品路径。`*_math` 与 CPU runner 共享实现血缘，只计内部一致性；`*_libplacebo349` 是冻结版本回归，不是 Dolby 权威参考。诊断 pivot 不自动纳入主准入。接入状态见入库记录。
3. 真实 DV：先核 Dolby 官方 P5、P8.1、P8.4 三个 1080p MP4 的 LFS SHA/大小/轨道，之后增加 UHD。扫描全部 RPU 建立功能覆盖表，再选约32个静态帧（黑/近黑/高亮/饱和/不同 reshape 参数）与连续片段（scene cut、RPU变化、B帧、seek/preroll）。若样本没有某种 polynomial/MMR 模式，用人工向量补齐，不虚报覆盖。项目现有 `/tmp/media-kit-DV-P5.mp4` 是另一个 4K/50fps 文件，不能与 Dolby 官方 Sol Levante 24fps 的 DoViBaker/母版帧互比。
4. HEVC H.265.1 一致性码流另列 L1 规范组；HDR10+ JSON/码流只列元数据解析和关联组，不当校准图。Netflix 母版和 Sparks 列画质/极端 HDR 组，先核版本、帧坐标、色域/PQ，再做非位精确比较。

每个真实样本在 `coverage.csv` 记录 profile、compatibility ID、BL/EL/RPU、帧率/范围/色度位置、RPU polynomial/MMR/trim/复用模式、测试帧与缺口。P7/FEL 只有进入产品承诺时再加 BL/EL/NLQ 合成门禁，不能以 BL 通过替代 FEL。

## 数值判定与防误判

- L1 原生整数、L2A 整数/有理数语义及显示帧关联要求精确一致；有损编码相对制作母版的差异**不**适用 L1 零误差规则。
- L2 公式 float32 单元向量可从归一化域 `abs≤1e-5` 起步，整帧 PQ 先观察 `P99≤2e-5, max≤2e-4`，只在采集 CPU/GPU 与 FP32/FP16 误差分布后冻结阈值；这不是 Dolby 官方容差。线性 nit 域同时设绝对/相对误差，FP16 单列。不能把探索阈值当已通过标准。
- 每次报告 MAE、RMSE、P99、最大差及坐标、超阈值分量数、NaN/Inf、首个失配帧/平面；PSNR/SSIM 仅辅助。禁止未声明的配准、曝光拟合、裁切或色域变换。若需上下翻转/裁剪，先在 manifest 固定坐标合同并用定位图验证。
- 故障注入门禁：L1 改 YUV 1 code、交换 Cb/Cr、错 P010 位移；L2A 错配 RPU 一帧；L2B 去 quadratic/MMR 交叉项；L2C 重复 reshape/PQ；L3 将 600 nit 当 PQ1、忽略宣称支持的映射字段、seek 后沿用旧状态。必须证明预期检查点先失败；仅比较器自检通过不等于 GPU/DV 故障注入已做。

## 运行清单和最近执行次序

2026-09-25补充：已知`left`无损P5小图案的8377手机映射前packed10整帧读回完成，关/开相位探针对编码前YUV的确定性取样模型均三分量0差；AImage crop与buffer尺寸明确记录，证明前轮L3边缘变化来自输入色度相位。另有满码Y1023→1020的独立限制，不能混作HEVC L1误差；详见`android-p5-leftfixture-rawfull-20260925.md`。后续仍需L2B及L2C剩余残差定位，不因raw整帧通过而视作第二层通过。

2026-09-25补充：8378已用`PL_HOOK_RGB`取得手机/主机同帧L2C **编码PQ RGB** 整帧，left相位关/开使P99显著下降，但剩余局部最大差仍达.094/.177/.316；显示映射不是这些残差的唯一来源。TEX hook会强制FP16中间FBO，已对L3量化扰动，参考仍是同实现工程交叉验证而非独立/官方标准。完整边界、A/B、比较与ROI见`android-p5-l2c-sameframe-20260925.md`；尚需转换为合同规定的线性RGB并进一步分离L2B/色度重采样。

每次输出 `manifest.json`：输入 MP4/BL/EL/RPU SHA、帧索引/PTS/time_base/POC（可得时）、mpv/FFmpeg/libplacebo/RPU工具版本及补丁 SHA、解码/渲染后端与 GPU/驱动、raw 像素格式/range/stride/crop/chroma location、输出数组 dtype/字节序/通道/原点/单位、参考等级、target/policy、时间状态初始化、每个检查点的文件 SHA、比较器版本/阈值/结果。原始 float `.bin`/`.npz` 是判定数据；PNG 只供预览，不作颜色真值。所有判定关联同一输入和同一显示帧，不以播放器 `time-pos` 或截图文件名独自证明帧身份。

执行顺序：① 两包完整性、L1/CPU 数学、五项数组和三项真实 GPU 禁用 DV 故障注入已核；临时 FFmpeg/libplacebo/MoltenVK 的五个小 DV 主用例已完成 L2/L3 浮点读回，P5 系 SDR100 端到端门槛失败，须先按 FP16 输入域及近零色域裁剪重新设计分层判定，不覆盖原 FAIL（见 `android-hdr-dv-testkit-gpu-moltenvk-20260925.md`）；② P5 4K50 第500帧 FFmpeg 软件 YUV 整帧 SHA 已复核，RPU payload 同帧身份有既有独立核对；主机同压缩帧 L3 浮点工程对照已建。8371 raw packed10 网格与软件BL几乎逐码值一致；8372原片相位探针显著缩小大尾差。进一步用已知left色度边缘的无损P5诊断片完成8375手机开关A/B：奇数列邻右色度样本使RGB最大差由.407/.287/.483降至.0141/.0137/.0138，证明当前prepass在这些边缘的相位与left工程参考不一致；仍是工程交叉参考，且有残差。详见 `android-p5-float-host-sameframe-20260925.md`、`android-p5-error-raw-chroma-20260925.md`、`android-p5-chroma-left-phase-20260925.md`、`android-p5-left-pattern-fixture-20260925.md`。L2C已落地且发现剩余尾差；下一步补L2B和源crop/采样坐标观察点，界定边缘及近零残差，再确定产品修正并检查4K50额外采样成本；③ 扩展P5/P8.1/P8.4官方1080p及UHD、连续时序/真实渲染故障注入；④ 仅在拿到同输入域Dolby授权/CM参考后增设`official_conformance`，同时继续原计划的真机HDR呈现与播放门禁。
