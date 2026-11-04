# LG DV P8.4 性能优化第二轮方案（2026-11-02，执行于 2026-11-04 起）

## 背景与已证前提

- 无表 YUV 输出融合已是生产默认（prod3 `32b3fd20…34f0`）。clean11 期等价代码实测：CPU -15%、GPU busy -23%、触热 cap 时间 82s→148s（+80%）。
- 旧 GPU 计时证据（`docs/validation/lg-p84-thermal-review-20261029/gpu-playback-timing-20261030/results.md`）为融合默认翻转前所测：input 5.540/5.298ms、yuv 5.677/5.874ms、render 单 pass ≈8.1–8.3ms@~309MHz。旧 input 计时不能直接用于当前收益预测。
- 同步模式对照、输入 slot FBO 复用、延迟 publish flush 均无稳定收益证据，本轮不再优先投入。

## 探查确认的关键代码事实

1. **融合开启时旧 `yuv` 计时点失效**：mpv `video/out/opengl/context_android.c:1761-1762` `if (!fused) yuv_diag_final_pass(ctx)`，计时点 `:955-958` 只包旧独立 YUV pass；融合 pass 由 libplacebo `pl_render_image_mix` 执行（`vo_gpu_next.c:2486`、`fusion_render:2275`）。
2. **融合 pass GPU 时间走 `render` 模式**：`draw_frame:2631` 的 `params.info_callback` 随 `&params` 传入 `fusion_render`（`:3163/3166`）；`gpu_timing_report:921-952` 每 10s 输出 `MKS-GPU-PASS stage=frame index=N avg_ns/last_ns/peak_ns desc=…`（rolling 256 样本历史，非逐帧归因）。
3. **输入复制计时仍有效**：`hwdec_surfacetexture.c:656-661` 包住 `draw_copy` 唯一 `glDrawArrays`（仅 fresh map，`:1489-1490`），与融合状态无关；`MKS-GPU-SAMPLES kind=input-copy data=seq:PTS:issue_ns:elapsed_ns` 逐样本上报。
4. **PQ 编码在融合 pass 体内**：libplacebo `src/shaders/colorspace.c:2046-2048` 无条件 `pl_shader_delinearize(dst=PQ)` → `:817-824` 精确 ST.2084（快路径每像素 2 次 vec3 `pow` + 1 次 vec3 div；全路径 6 次 vec3 pow）。融合 tail（`src/dispatch.c:757-766`）只有 half 量化 + BT.2020 NCL 矩阵。libplacebo 有现成 `sh_lut` 机制（`src/shaders/lut.c:326`）与 1D LUT 先例（tone-map LUT `colorspace.c:1879-1900`，PQ 域索引），但无任何 transfer 走 LUT。

## 执行顺序（用户给定）

1. 重测当前无表融合基线：分别测输入复制与融合色转输出的 GPU 时间。
2. 输入复制占比明显 → 推进输入融合；色转算术占比明显 → 先做 PQ 小查表。
3. 同包交错至少三对有效 A/B，匹配起始温度并核对 GPU 工作点。验收目标（非预测）：**稳定减少至少 10% 的 GPU 每帧处理时间**。
4. 数值、观感、生命周期验证通过后，再做持续热态对照。

## 隔离纪律（2026-11-04 用户要求）

- 另一 agent 正在主工作树做 HOME 返回会话恢复（media-kit 19 文件 + mpv `player/loadfile.c` 未提交改动）。本任务全程使用独立 worktree + `perf2/lg-p84` 分支，不触碰主树未提交改动：
  - media-kit：`/Users/wuweiwei1/src/worktrees/perf2-mk`（761e29a8）
  - mpv：`/Users/wuweiwei1/src/worktrees/perf2-mpv`（c7bffdd1b0，独立 meson 树 `_build-arm64-mks`，配置命令与既有验证树逐参数一致）
  - libplacebo：`/Users/wuweiwei1/src/worktrees/perf2-lp`（3a13e0ca；构建真源仍是 deps 树，阶段 1 无 libplacebo 改动）
- 实施不派 subagent；收尾前由 critical reviewer 复审。

## 阶段 0：工具准备

- `tool/analyze_lg_p84_gpu_timing.py` + 单测：解析轮次 `flutter-logcat.txt`（`MKS-GPU-SAMPLES`/`MKS-GPU-PASS`）与 `samples.ndjson`，输出 PTS 20–55s 窗统计（均值/中位 ms、GPU MHz 中位、频率归一化 Mcycles/frame）、disjoint/drop 计数、多轮聚合占比与配对 A/B。
- `tool/lg_p84_instant_perf.py` 放开 `--reference-start/--cooldown-timeout/--battery-tolerance/--vts-tolerance` 透传（复用 thermal_round 既有机制），删除 `:186-187` 死代码；单测同步。
- 构建：`tool/build-android-test.sh`（JDK17 env），perf2-mk worktree + `build_android_native.py --mpv-source perf2-mpv`；define 集照 `source-code-manifest.json`（THERMAL_PROBE/HDR_PREFER_CONVERT/HDR_DIAGNOSTICS=true）。

## 阶段 1：无表融合基线重测

条件：LG 在线、HDR1、backlight 64、USB、local source SHA `7626cac2…`、60s/2s、`--experiment sync --mode baseline`、GPU cap 门、轮前温度匹配（battery ±0.5°C / VTS ±1.0°C）。

轮次矩阵（交错）：C×2（无计时对照）→ I×3（`--gpu-timing input --yuv-fusion`）→ R×3（`--gpu-timing render --yuv-fusion`，取 `stage=frame index=0`）；可选旧路径分解（`yuv_fusion=0`：render×2、yuv×2、input×1）。invalid/aborted 轮如实保留不计入。

产出：占比表 `share_input = cycles_input / (cycles_input + cycles_fused)`（原始 ms 与归一化 Mcycles/frame 双口径）；边界：三类分会话、render 为 rolling 历史、DVFS 不可锁频、不可拼单帧总耗时精确值。

## 阶段 2：决策门

- `share_input ≥ 30%` → 轨道 A 输入融合；`share_input < 30%` 且 PQ 段 ≥ 15% 融合 pass → 轨道 B PQ 小查表；都不达 → 如实报告交用户裁决。
- 轨道 A（设计要点）：fresh 帧由 renderer 直采 OES，lease 按需复制；保留帧身份/acquire-release/重绘/seek/EOF/销毁语义；数值门（identity copy 为 mediump，直采改变舍入点）；`debug.mks.input_direct` 默认 0、失败同帧回退、故障注入。
- 轨道 B（设计要点）：独立 NDK 探针先证成本余量与精度预算（1024/4096 项 1D LUT vs 解析 ST.2084，half 量化后差异）；libplacebo `colorspace.c` PQ case 增 `sh_lut` 路径（默认关，参数门控）；mpv `debug.mks.pq_lut`；两树同步；LYA 回归在默认翻转前。

## 阶段 3：候选 A/B 验收

同包属性门控，A=候选关、B=候选开（均 `yuv_fusion=1`），交错 ≥3 对有效，匹配起温、cap=0、HDR1/backlight64、零新增丢帧。主指标 `T = cycles_input + cycles_fused`（各自 I/R 会话、频率归一化）；验收：每对 B<A 且配对降幅中位 ≥10%。副指标：无计时轮 MHz/busy 方向一致。

## 阶段 4：验收后序

1. 数值：固定 PTS（35.035/600.03/720.05）SSBO 采集 A/B，与无表融合已接受差异量级（0.12% 末位分量）对照。
2. 观感：用户最高亮度 + 暗部渐变/锐边/运动片段。
3. 生命周期：hdr_lab 探针四动作 + HOME 往返 + 故障注入回退。
4. 持续热态：240s A/B 匹配起温，比较触 cap 时间与温升。
5. LYA 回归后讨论默认翻转；翻转需独立 critical 复审。

## 边界（不宣称）

不锁频（无特权）；DVFS 只能归一化+工作点匹配；render 计时为 rolling 历史非逐帧归因；计时开启本身有扰动（用 C 轮量化）；设备热饱和轮次如实中止。

## 附录 A：轨道 A（输入融合）设计约束清单（探查自源码，2026-11-04）

实施前提：阶段 1 测得 `share_input ≥ 30%`。以下为硬约束与已知结构事实：

1. **复制触发面**：`mpv video/out/hwdec/hwdec_surfacetexture.c` fresh map 每帧一次 identity draw（`draw_copy`，计时点 `:656-661`，调用点 `:1489-1490`）；cur lease 命中（`:1305-1313`）、retired 采纳（`:1317-1329`、`:1354-1361`）、重绘均为零拷贝复用。RGBA16 降级探测 `probe_2d_format :784-844`（禁 RGBA8 回退）。
2. **lease 存在原因**：OES 是可变单缓冲，下一次 updateTexImage 即失效；多逻辑帧/重绘/seek/pause/still 需要稳定帧身份（记录于 `lg-dv-p84-thermal-review-20261029.md` Findings §源码处理链 3）。直接采样不能破坏 acquire/release、retire 与帧身份。
3. **候选形态**（供 specialist 评估）：(a) 首渲染 pass 直采 OES（消除独立 copy draw 与源尺寸 RGBA16F 写+读），lease 仅在需保留时按需复制——保留语义最完整；(b) 保留 lease 但把 copy 融进首个必要渲染 pass——不消除中间物化，收益存疑。倾向 (a)。
4. **数值门**：identity copy shader 为 mediump；直采改变舍入点（历史 UV 实验已证插值/编译差异可传播）。须走与融合同级的数值门（fixed-PTS SSBO 采集 A/B）。
5. **接口**：libplacebo deps HEAD 已含 `PL_SAMPLER_EXTERNAL_YUV`（`980742df`）；评估 renderer 输入侧直挂外部采样器的接线成本。
6. **门控与回退**：`debug.mks.input_direct`（默认 0）；同帧失败回退复制路径；失败预算+故障注入；沿用融合 begin/commit/abort 收据链模板。
7. **生命周期回归面**：seek/暂停/still/EOF/切源/销毁/HOME/旋转（identity 门重建路径），同输出融合生产化验证清单。

## 附录 B：轨道 B（PQ 小查表）探针与实现要点（2026-11-04 准备）

- 探针 `tool/native/lg_pq_lut_probe.c`（builder `tool/build_lg_pq_lut_probe.py`，host 自测+NDK 构建）：2672×1336 RGBA16F 全屏，六变体共享生产 tail（mks_half_store + BT.2020 NCL，逐字复刻 dispatch.c:736-748）：identity 下界 / analytic 生产式（2 pow+1 div，输入域 [0,49.26] SDR 相对）/ 1024 与 4096 项 R16F LINEAR LUT（线性与 sqrt 索引域）。disjoint timer ring + 每 timed 帧 glFlush（pbuffer 无 swap，驱动不退役查询——**偏离生产"无 flush"计时契约的独立诊断环境**，绝对时长≠生产时长，仅用于变体间对比）；三组交错累计；全屏逐像素精度比对 + 256 点全 tail CPU double 参照（GPU pow vs double 差异单独报告）。
- 已知行为与边界：ST.2084 公式在 x=0 给出 C1^M2≈7.3e-7 的 lift（与 libplacebo 相同，非 bug）；LUT 端点取 texel center，x=0 clamp 后取首项而非精确黑点（1024-linear 黑端偏差最大，sqrt 索引显著缓解）——候选 LUT 须单独过精度门，探针 verdict 只含计时/GL 状态不含精度阈值。libplacebo PQ 常量源 `src/colorspace.h:23-27`、OETF `src/shaders/colorspace.c:817-824`。
- 实机状态（2026-11-04，复审校准）：四跑——run1/2 失败（timer 饿死→楔死，根因 OPEN），run4（批末 flush `529aea6b…`）走完循环正常退出至失败判定，取得部分不利计时（每变体一组 120 样本；1024 两变体中位高于 analytic 39.15%/80.19%，仅描述本次日志）。精度相对与绝对全部 OPEN（全屏差异=0 与构造矛盾，读回/渲染执行某环节未真实发生）。**B 轨=测量未闭合，不能判定实测证伪**；探针作为测量工具不可靠，修复与重跑交用户裁决并触发复审。
- 实现落点（门过之后）：libplacebo `src/shaders/colorspace.c:817-824` PQ case 增 `sh_lut`（`SH_LUT_TEXTURE`+`SH_LUT_LINEAR`，参数门控默认关）；mpv `vo_gpu_next.c` 读 `debug.mks.pq_lut`（形态同 `:4239-4247`）；`lg_p84_instant_perf.py` 增 `--pq-lut`，`thermal_round.py:752-760` 增 setprop；两树同步；LYA 回归在默认翻转前必做（PQ 编码同在 RGB10 直出路径执行）。
