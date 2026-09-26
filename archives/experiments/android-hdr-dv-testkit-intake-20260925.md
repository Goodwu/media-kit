# HDR/DV 两套测试包接收与本机复验（2026-09-25）

输入位于 `~/Downloads/test_files/`；测试时解压到 `/tmp/media-kit-hdr-dv-testfiles-20260925/`，未将约 500 个包内资产复制进仓库。`HDR_DV_Three_Layer_Test_Starter.zip` SHA-256 为 `6d0a1e129b7587666a7f12a872d7461fba6a53ec3686a37facce140831a523ab`；`DV_TestKit_v1.zip` SHA-256 为 `77ecd80263f04c09ec221d0288a9fb6f46317a9448877377f6f711446c361489`。两包 `unzip -t` 均通过。另附 `DV_TestKit_v1_validation.json` 是提供者的结果声明，不算本机复验。

## 本机结果

| 范围 | 本机检查与结果 | 证据等级及边界 |
| --- | --- | --- |
| 启动包完整性与数学自检 | `shasum -a 256 -c SHA256SUMS` 全通过；`python3 tools/selftest_math.py` 通过 | 公式/文件完整性；不含真实 DV。 |
| 启动包 L1 | `python3 tools/verify_l1.py`：3 个 128×64、48 帧的 Main10 无损片共 144 帧，FFmpeg 9.0.2 解码对编码前 YUV 逐样本 0 差；比较器的一码值突变在第 0 帧 Y(0,0) 检出 | 合成无损样本 L1，不能外推到硬解或 4K。 |
| DV 包完整性 | `python3 tools/quickcheck.py`：494 个文件 SHA、4 个 RPU fixture CRC、130 个 scalar reconstruction vectors 全通过；PQ 最大误差 2.93e-08 | 文件身份与包内自检；RPU 来源仍按包内声明，不是 Dolby 认证。 |
| DV 包 L1 | `python3 tools/run_tests.py --mode cpu --diagnostics --de265`：5 个主用例 120 帧和 2 个 pivot 诊断用例 6 帧，libde265 1.1.3 对编码前 YUV 逐样本一致；另用本机 FFmpeg 9.0.2 核主用例 120 帧，也逐样本一致 | 两种解码器交叉验证合成无损码流 L1；真机 MediaCodec 原生 YUV 仍未直接观察。 |
| DV 包 L2A | FFprobe 检查 5 个主用例：各 24 帧的 DV config、显示 PTS、RPU 语义子集与包内帧清单匹配 | 验证包内预期的配帧；尚非独立 RPU 解析器之间的完整字段核对。 |
| DV 包 L2/L3 CPU | 7 个用例每例 L2 math 和 3 个目标 L3 math，35 项通过，最大数组误差 0 | `*_math` 参考与 runner 同实现血缘，只能称内部一致性；ETM-v1 不是产品当前映射策略或 Dolby CM。 |
| 故障注入 | 单一码值、R/B 交换、显示帧错序、RPU 延迟一帧、PQ600/PQ1000 错目标共 5 项数组变异均被检出 | 只验证包内数组比较门禁；真实 shader/RPU 禁用等 GPU 故障注入未运行。 |

DV 包包含 P5、P8.1、P8.4、P5 参数切换、P8.1 B 帧五个主用例和两个 pivot 诊断用例。它提供 L2 `*_math`、固定 libplacebo 349 输出及 L3 ETM-v1 数据；前者可供公式/工程检查，libplacebo 输出只可标为冻结版本回归。诊断 pivot 用例不计主准入，须先调查其边界差异。包内 PNG/TIFF 只作可视化或按明确数值格式检查，不能仅凭图像文件名提升为 Dolby 官方 golden。

## 未完成的实测

系统 FFmpeg 9.0.2 的 `--mode all --case p5` GPU 入口在 `-init_hw_device vulkan=vk` 失败，且未列出 `libplacebo` filter；该轮状态是 `NOT_RUN_ENVIRONMENT`。随后另构建本机 FFmpeg n7.1.3 + libplacebo/Vulkan，在 MoltenVK 上已运行全部五个主用例的真实离屏 GPU 测试：L2 与 PQ600/PQ1000 全过，SDR100 的 P5/P5 参数切换按原门槛失败；进一步分层定位与 8 项完整故障注入见 `android-hdr-dv-testkit-gpu-moltenvk-20260925.md`。不能再将整套 GPU 测试称为未运行，但 Android 产品路径仍未接入。

小合成 DV 样本能先验证代码接线、RPU 帧关联和指定策略，但不能替代 Dolby 官方 1080p/4K 样本、授权一致性输出或当前 4K50 P5 手机上 8370 的同帧同域参考。P8.4 的产品兼容 HLG 路径明确忽略 RPU，不能按 DV reshape 用例的输出给它判失败。L3 ETM-v1 结果不能拿来判定产品使用其他映射算法的正确性。
