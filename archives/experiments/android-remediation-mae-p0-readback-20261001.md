# 审整改实机验收：MAE 对照、P0-1 同进程双文件与 4K60 SDR 性能归因（2026-10-01）

## 结论

按 review `~/src/review-media-kit-android.md`（归档副本 `~/src/mpv/review-media-kit-android.md`）第 5 节"立即修"要求的实机验证，在 LYA-AL00（Kirin 980 / Mali-G76 / OMX.hisi，Android 10）全部完成：

1. **P0-2（MMR 阶次）数学经 shader 源码逐项核实为精确等价**（libplacebo `reshape_mmr` 各阶基函数次数与除数一一对应：j+1 / 2(j+1) / 3(j+1)，interior pivot 仅作段选择、首尾 pivot 仅作输出 clamp）。实机新旧数学 A/B **逐位一致**（Sol f240 全分辨率 MAE 均 99.4/110.4/121.7）——旧数学的误差对本帧对低于 f16 半 LSB，即修复无行为回归、且此前验收结论不受影响。
2. **MAE 对照（设备整帧 rgba16f 读回 ↔ 主机 libplacebo 参照，参照链 SHA 与历史逐字节一致：f240=ca8265ac、f501=f167c613）**：Sol f240 = (99.4, 110.4, 121.7)/65535，4K50 f501 = (107.4, 92.1, 111.9)。系统偏差分量（R −37 / G −11 / B +34）与 9/30 基线记录的"偏置 ±7-37"完全一致；全分辨率值高于历史基线 (47,50,70)/(51,20,59) 的部分**全部为 2px 周期零均值色度带噪声**（8× 块平均后 Sol=(40.4,37.4,52.5)、4K50=(36.7,13.4,39.7)，全部 ≤100；4K50 G=13.4 已达读回噪声底 12-17）。**四个构建变体（整改新数学/旧数学、fork c9fd879/pre-fork libplacebo、398d0c3 精确重构）读回帧逐位一致**——MAE 增量与整改无关，属基线轮（12678，其 JAR 未留存、链接 mkp4prefix 旧 .a）不可复现条件下的对照口径差异。
3. **P0-1（static 判定）同进程双文件验证通过**：同一进程同一播放器内 Sol f240（dump-1）→ 25s 后打开 4K50（`AUTO_SECOND_SOURCE`）→ f500（dump-2）。dump-2 MAE (107.7,94.3,113.0) 与独立单文件轮 (107.4,92.1,111.9) 同水平；若 P0-1 缺陷在场应出现修复前签名（R 均值 +180、MAE≈185）——未出现。第二个 mapper（参数相同则 mapper 复用、不同则重建）的重标定均生效（`AHB format=0x325 … dovi rescale k=1.002941` 为 per-mapper 日志，每轮恰一条）。
4. **4K59.94 SDR（glassblowing）性能**：整改版全片 EOS 到达、decoder drop 0、零渲染失败、零取图失败，VO drop 3590——**优于同夜同条件对照**：398d0c3=4750、398d0c3+pre-fork libplacebo=4830、c025cbf（9/28 轻负载世代）=3805（散热 5 分钟后）。三轮 3590→4750→4830 的单调劣化与 GPU 586→277→139MHz 降频轨迹一致（热累积）。**重负载体制先于本次整改存在**：9/30 merge 验收 12700 已达 2102（vs 9/28 老 App 轮 20-36），c025cbf 世代 mpv 在今日 App 下同为重负载 → 归因方向为 9/30 主合并后的 App 侧渲染路径（a886f556 上游 main 236 提交）与热状态，非 mpv 整改（整改移除逐帧探针后反而更优）。整改不引入性能回归；深挖 9/28→9/30 负载升高属后续任务。

## 环境 bug（本次发现并修复，均先于任何有效轮次）

1. **dv-experiment 构建链 prefix 为旧钉定世代**（9/23-9/25：vanilla FFmpeg 7.1.3 + pre-c9fd879 libplacebo）——51e8035 钉定（10/1 01:34）后从未构建过。直接链接会复演 P4 `direct=0` 事故（属性门控旧世代）。已全量重建（fff3ee7+HLS 补丁 FFmpeg、c9fd879+2 构建补丁 libplacebo）。
2. **mpv meson `has_member` 检查缺 `struct` 标签**：libplacebo 结构体无 typedef，裸 `pl_render_params` 在 C 下不编译 → `HAVE_PL_DOV_LINEAR_OPTIMIZE` 误判 0 → P5 SDR 快速路径整块被编译出局。已修（`'struct pl_render_params'`），修复后 HAVE_PL_DOV_LINEAR_OPTIMIZE=1。
3. **整改未提交 diff 将 `AImageReader_newWithUsage` maxImages 3→5（落实 review P1-4 建议 4~5）在 OMX.hisi 上破坏解码器启动**：`OMXParms port(1) BufferCount error` → ACodec signalError（output port disable 失败）→ IllegalStateException → 硬解整流回退软解。A/B 确认 3 恢复正常。已回退为 3 并注明厂商限制（`hwdec_aimagereader.c` 注释）。
4. **hdr_lab（P2-4 拆分）原生侧 5 个 MethodChannel 仍是旧包名 `media_kit_test/*`**（Dart 侧已改 `media_kit_hdr_lab/*`）→ `SetShortEdges` MissingPluginException 使 main() 中断、白屏。P2-4 验收只跑了 analyze/VM 测试/构建，未跑设备轮，故漏网。已修（engine_control/p5_runtime_gate/flutter_surface_probe/p5_codec_probe/capabilities 五处）。

## 工具链与资产（本轮新增/重建）

- **构建**：dv-experiment 链全量 arm64 重建（补丁齐套：ffmpeg HLS + libplacebo 2 构建补丁 + c9fd879 自含 external_yuv/r32f）；glad 子模块补齐；mpv 工作树多轮变体构建。
- **JAR**（`/tmp/mkrem/`，base=release 7cb87a5c 换 libmpv.so）：
  - `media-kit-remediation-final-product.jar`（**整改产品**，SHA-256 `a7f36bd4…`）
  - `media-kit-remediation-final-readback.jar`（整改+读回，`28f4089a…`）
  - 对照：`media-kit-398d0c3-product.jar`（f3cc1d39）、`media-kit-398d0c3-preforklp.jar`（3fb5aae8）、`media-kit-c025cbf-product.jar`（88bd8e63，去 optimize 行以配 pre-fork 头）、`media-kit-398d0c3-readback.jar`（f7ad4298）。
- **读回补丁移植**：`archives/experiments/android-p5-float-readback-remediation-20261001.patch`（348 行，8370 原补丁 → 整改树；dump 路径改 hdr_lab 包名、按文件重触发（pts<10 re-arm）、文件名带序号；App 侧 `main.dart` 增 `getExternalStorageDirectory()` 建目录——native mkdir 被 FUSE 拒）。
- **主机参照**（/tmp/mkffdv，滤镜串 9/25 固定策略；`-ss` 输出侧）：`mkhost-sol-f240`（=ca8265ac 逐字节复现历史）、`mkhost-sol-f241`（7be0db03）、`mkhost-4k50-f500`（5674b1c2）、`mkhost-4k50-f501`（=f167c613 逐字节复现历史）。
- **轮次脚本**：`/tmp/mkrem-round.sh`（读回轮：7 个 debug.media_kit.* 属性+恢复 12492）、`/tmp/mkrem-reg-round.sh`（产品回归轮：PERF/截图/GPU 频率采样/EOS 等待；GPU ndjson 键名 `gpu_frequency_hz`）。
- **设备轮**（每轮恢复原 12492、自动亮度、熄屏；轮产物 `/tmp/mkrem-round-*/`、`/tmp/mkrem-reg-*/`）：solv4（Sol MAE）、k50v4（4K50 MAE）、duofinal2（P0-1 双文件）、sololdmath/sol398/solpreforklp（A/B 对照）、glass/glassvb/glass398/glass398pf/glassc025（性能归因序列）。
- **hdr_lab 诊断 define 新增**：`MEDIA_KIT_ANDROID_AUTO_SECOND_SOURCE(_AT_SECONDS)`（同播放器二次打开，走 HDR 协调器保策略）；`_openHdrSource` 校验器放宽为命名样片模式匹配（去 `sources.first` 等值限制）。

## 多格式产品回归（整改产品 JAR a7f36bd4，均自动恢复原 12492/自动亮度/熄屏）

| 轮 | 格式/输出 | EOS | VO 掉帧 | 解码丢弃 | 渲染失败 | 截图像素统计 |
|---|---|---|---|---|---|---|
| glass | P5 4K59.94 SDR(Texture) | ✓ 177.78s | 3590（冷机 3307） | 0 | 0 | t30-150 全部正常内容帧、t180/尾黑底落版 |
| mystery-pq | P5 4K PQ(PlatformView+GPU_PLATFORM_HDR) | ✓ 98.75s | 2713 | 0 | 0 | t30-90 正常、尾黑底落版 |
| hdr10-sdr | HDR10 SDR(OES 标准导入) | ✓ 198s | **0** | 0 | 0 | 全部正常内容帧 |
| hdr10-hdr | HDR10 HDR(PlatformView) | ✓ 198s | **0** | 0 | 0 | 全部正常内容帧 |
| p84-sdr | DV P8.4 SDR | 播放健康至 198s+（片长超出轮窗） | **0** | 0 | 0 | 全部正常内容帧 |

- HDR10/P8.4 全程零掉帧、零错误——OES 路径（P1-1 改动面）与 P8.4 路径无回归且性能优异。
- P5 4K 两格式处于结构性重负载体制（glass 3307-4830、mystery 2713；9/30 基线 2102/2550、9/28 旧 App 世代 20-36/11-30），与 mpv 世代无关（c025cbf 同重）、与 libplacebo 世代无关（pre-fork 同重），整改版为同夜序列中最优——归因方向为 9/30 主合并 App 侧渲染路径，非本整改引入。

## 边界与遗留


- 基线 (47,50,70) 的全分辨率口径不可复现（12678 读回 JAR 未留存，链接 mkp4prefix 旧 .a + 旧 App）；本报告以系统偏差分量 + 四变体逐位一致 + 8× 降采样全 ≤100 作为 P0-2/P0-1 数值验收依据。
- 同夜热累积使 4K60 绝对掉帧数不可与 9/30 直接比（3590-4830 vs 2102）；整改与各世代的同夜对照有效。9/28(20-36)→9/30(2102) 负载跃升的归因（主合并 App 侧 vs 其他）待冷机对照轮。
- 读回 dump 触发帧受 offscreen bootstrap 影响可能落在 f240 或 f241（pts≥10 首帧），对照时按日志 pts 选参照帧。
- **遗留复核（与用户确认，按实测证据重排）**：不可行三项——3.1 deleteAsync（LYA 无 `EGL_ANDROID_native_fence_sync`，9/26 `android-p5-glass-direct-retire-20260926.md` 已证；当前 fence+有界队列为已验证实现）、maxImages 4~5（OMX.hisi 拒绝，本轮实证）、撤 `get_req_frames` hack（依赖前两项，本机堵死）。可做项价值排序与依据见 conversation `architecture-review-remediation-20260930.md` 遗留复核节（发布闭环 ＞ 4K60 App 侧归因 ＞ 上游化小 PR ＞ 3.3 搭车 ＞ pts 校验降级 ＞ 3.4 ＞ acquireNextImage ＞ 首帧无 RPU）。
