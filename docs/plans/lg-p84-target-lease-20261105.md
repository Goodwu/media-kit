# LG P8.4 目标尺寸 lease 方案与环境交接（perf round 3，2026-11-05）

> 新会话接手文档。前置任务：perf round 2（`TASKS.md` §LG-P84-PERF-ROUND2-20261104，
> 归档 `archives/conversations/lg-p84-perf-round2-20261104.md` 含五轮 critical 复审与
> specialist 评估全文）。本文保留立项时的环境、设计和实验计划。
>
> **2026-11-05 现行更正**：以下初版叙述和环境表是历史方案，不能作为当前状态或
> 已证事实。现有 `gpu`/`gpu-next` 尚未接入目标 lease；`dst_params` 不可逐 map 改尺寸。
> 已缩小的旧 lease 不能凭坐标恢复源细节，目标 copy 失败后当前帧也不能同帧回源。
> UNORM16 慢不证明 Adreno 存在 float16 快路径。既有 `perf2-mpv` 构建树仍链接共享
> prefix；只改 mpv 路径或 APK tag 不构成安全隔离，完整构建目前 blocked。当前状态以
> `TASKS.md`、conversation 的 Current State 和证据 README 为准；下文 §七的更正亦适用。

## 当前推荐（2026-11-05，替代历史 M0 中冲突的前提）

用户明确没有要求截图或暂停放大恢复源分辨率细节，不再将每帧额外保留大图作为
硬条件，也不推断用户已接受任意画质退化。两名 specialist 的原始数据复算与独立
critical 设计审查支持优先继续 **direct OES→small，单份 lease**；full+small 只可
考虑用于受控画质诊断，不能将其双路开销混入正式性能轮。

仅 fresh、全帧严格等比且满足既有几何门时申请目标尺寸；不适用的 fresh 帧回源尺寸。
已经创建的小 lease 在重绘、截图或条件改变时按自身真实逐映射几何消费，不重新
release/latch，不伪报物理尺寸；上采样不能恢复源细节。逻辑源坐标、物理纹理坐标和
每次 render 的局部 crop 须分开，字幕 overlay 的视频坐标同样映射但 atlas 坐标不改，
共享 parts/纹理不得被原地重复缩放或污染。截图尺寸与画质分开验证，不通过隐藏字幕
或关闭用户功能取得性能结果。

接入前仍需解决实际表示与混帧缓存命中兼容性、各渲染入口的局部几何及部分 acquire
失败清理；`skip_caching_single_frame` 不是完整旁路。未适配的 hooks/table/atlas 等
路径应保持源尺寸或先证明可安全消费实际几何，不改真实混帧时序或帧身份。缓存条目
可能比底层 lease 活得更久，不能假定清除缓存后可重新获取已消费帧；每次渲染许可、
实际表示 witness、缓存兼容性、字幕/截图独立所有权须分别处理。仅对确实无混帧的
单帧用途考虑 `pl_render_image()` 的受限旁路，不得强行将多帧压成单帧；该途径的
暂停/重绘性能与用户处理选项仍须验证。以上是待审设计建议，不是已批准或已实现的
完整 M0 裁决。

先做 host 行为测试及独立 critical 复核，再建立可审查的独立依赖/prefix 和 Flutter
写入隔离，经标准源码入口构建 APK 后按设备协议开展功能与同包交错 A/B；完整逐帧
GPU 指标的覆盖和计时所有权须先建立，不能简单跨 draw→flip 计时或把跨 session
分项相加。≥10% 仍是验收目标，不是预测；现有性能和画质均未验收。

## 一、环境交代（新会话第一件事：核对）

### 1. 代码线（perf2 worktree，与主树另一任务隔离）

| 仓 | 目录 | 分支/基线 | 状态 |
|---|---|---|---|
| media-kit | `/Users/wuweiwei1/src/worktrees/perf2-mk` | `perf2/lg-p84` @ `3b7fd8ae` | 干净（round2 已提交） |
| mpv | `/Users/wuweiwei1/src/worktrees/perf2-mpv` | `perf2/lg-p84` @ `0206c931ac` | 干净（lease 格式诊断开关已提交） |
| libplacebo | `/Users/wuweiwei1/src/worktrees/perf2-lp` | `perf2/lg-p84` @ `3a13e0ca` | 干净，round2/3 预计无需改动 |

- **主树注意**：`~/src/media-kit` 历史已于 2026-11-04 重写（仓库减重整改，
  `docs/validation/ARCHIVE.md`）；perf2 分支父链是重写后的 `ff299501`，无需处理。
  主树仍有另一 agent 的 HOME 返回会话恢复任务——**开工前查主树 git status**；
  若其已落地合并，是否 rebase 到 feature/dv 由用户定，不自行合入。
- 符号链接（源码断言测试依赖）：`~/src/worktrees/mpv → perf2-mpv`、
  `~/src/worktrees/libplacebo → perf2-lp`，已就位。

### 2. 构建链

- 入口：`tool/build-android-test.sh --tag <tag> --local-source /sdcard/Android/data/com.example.media_kit_hdr_lab/files/hokkaido-p84.mp4 -- --dart-define=…`
- 环境重定向（必须，否则吃到主树另一 agent 的未提交改动）：
  `MEDIA_KIT_MPV_SOURCE=/Users/wuweiwei1/src/worktrees/perf2-mpv`
  `MEDIA_KIT_MPV_BUILD=/Users/wuweiwei1/src/worktrees/perf2-mpv/_build-arm64-mks`
  `MEDIA_KIT_BUILD_JOBS=8`；`JAVA_HOME` 脚本内已定 JDK17；NDK 27.2.12479018。
- mpv 独立 meson 树已配置（`_build-arm64-mks`，参数与验证树一致）；增量重建 ~1 分钟，全量 ~7 分钟。
- APK define 集（round 2 验证有效）：`MEDIA_KIT_ANDROID_P84_THERMAL_PROBE=true
  HDR_PREFER_CONVERT=true HDR_DIAGNOSTICS=true PERF_PROBE=false P5_COUNTER_PROBE=false
  DIRECT_OPEN_TRACE=false`（经脚本 `--` 透传，链路已证正确）。
- **装机后必须 md5 门**：每轮前 `md5sum $(pm path …)` 比对本地——round 2 中另一
  agent 覆盖装机曾造成假失败。

### 3. 设备与现场协议

- LG `LGH870DS42e27764`（SD821/Adreno530/GLES3.2/API24）。样片：
  `/sdcard/Android/data/com.example.media_kit_hdr_lab/files/hokkaido-p84.mp4`
  SHA256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`
  （3840×1920@29.97 HEVC10 DV8.4 compat4，显示面 2672×1336）。
- 轮次工具：`tool/lg_p84_instant_perf.py`（60s/2s、backlight 64、
  `--reference-start <锚>/summary.json --cooldown-timeout 1800 --battery-tolerance 0.5 --vts-tolerance 1`
  起温匹配已支持；`--yuv-fusion` 显式开、`--gpu-timing input|render` 互斥）。
- 设备坑（round 2 实测教训）：①轮前让设备自然熄屏（原态=OFF，restore 才能过）；
  ②keyguard：WAKEUP→1.5s→MENU（工具已内置重试）；③LG 流式 logcat 不可靠，取证用
  `adb exec-out logcat -d`；④ADB 偶发断连→重连重跑；⑤**设备可能与另一 agent 共用，
  冲突时等待重试不抢占**（用户指示）；⑥GPU 热 cap 门自动中止，被中止轮如实保留。
- 分析：`tool/analyze_lg_p84_gpu_timing.py`（fail-closed；share/pair 用法见其测试）。
- round 2 证据：`docs/validation/lg-p84-perf-round2-20261102/`（README 索引）；
  原始流外置 `~/Documents/media-kit-validation-archive/artifacts/lg-p84-perf-round2-20261102/`。
  新轮证据按同约定：flutter-logcat+summary 入库，samples/commands/thermal 流外置。

## 二、已确立的事实基础（勿重测）

1. **占比**：输入复制 pass（OES→RGBA16F lease，源尺寸）5.80–5.92ms≈**33.1%**；
   融合 pass 11.73–11.81ms≈66.9%（8 轮、214MHz、零 cap、起温逐轮匹配；份额模型与
   busy 52–53% 一致）。draw≈30Hz、无重复渲染。
2. **UNORM16 lease 否定**（copy +44%/融合 +42%，观察性）：同 64bpp 更慢 → Adreno530
   存在 float16 快路径；** lease 改格式方向已封**。
3. **MRT 并 pass 不可行**（默认帧缓冲不能挂第二颜色附件）；OES 直采=帧身份结构风险；
   同步模式/FBO 复用/延迟 flush=已证无益。
4. PQ LUT 探针不可靠（输出有效性 OPEN），B 轨暂挂；探针修复（GLQ 宏错误重执行缺陷
   `lg_pq_lut_probe.c:45` 必修）为独立小包，不阻塞本任务。
5. mpv mapper 现状（改动落点，行号为 round2 时点）：
   `video/out/hwdec/hwdec_surfacetexture.c`——`draw_copy` :624-682（全屏 identity、
   计时点 :656-661）、`probe_2d_format` :788+（rgba16f→rgba16，默认关翻转开关
   `debug.mks.st_lease_rgba16` 已提交）、`take_slot` :1241-1281（**lease 按 src 尺寸分配**）、
   fresh map 调用 :1489、cur/retired 复用 :1305-1361、mapper_init 属性读取 :860+。
   融合门 `vo_gpu_next.c:1166-1241`（REJECT 含源 rect/crop 检查 :1188,1221）。

## 三、方案设计：目标尺寸 RGBA16F lease

### 概念

把源→lease 的复制从"源尺寸 identity"改为"**源矩形→目标矩形的双线性降采样**"：
lease 以显示面尺寸 2672×1336 分配（面积比 0.484），融合渲染端对 lease 变成 1:1 采样
（不再承担 3840→2672 缩放）。RGBA16F 格式不变（float 快路径已证）。

**收益模型**（specialist）：copy 5.83→≈2.82ms（若随面积线性），input+fused 总时长
17.6→14.6ms，**模型总降幅 ≈-17.1%**，新 copy 份额 ≈19.3%。验收线 ≥10% 有余量，
但模型≠承诺——copy 现在要做真滤波（非 identity），实际缩放系数待测。

### 适用域收窄（安全边界，先做窄后放）

仅当 **源矩形→目标矩形是纯等比缩放（本片 2.0:2.0 全帧）** 时启用目标尺寸 lease；
出现 crop/非等比/旋转/anamorphic 时**整帧回退源尺寸 lease**（经典路径），不构造
letterbox lease。判定点：mapper 侧持 src_params 与目标尺寸（尺寸 generation），
每 reconfig 重判。

### 两个待裁决的设计点（新会话第一设计决策）

**A. 下游声明方式**（二选一，需对照融合门与 renderer 语义验证）：
- A1：dst_params 声明目标尺寸 + **PAR 补偿**（2672×1336、PAR=源宽高比补偿值），保持
  显示宽高比不变；下游（含融合 rect/crop 门）看到的是"真实的 2672 图像+非方形像素"。
- A2：dst_params 保持源尺寸声明，lease 纹理目标尺寸，mapper 增设显式
  "pre-scaled" 几何元数据，renderer 侧把 scale_main 退化为 1:1。
  **禁止**伪报尺寸绕过 crop 门（specialist 明确）。
- 倾向 A1（对下游最诚实、改动集中在 mapper）；需验证 mpv 图像参数链（SAR/PAR 传播）
  与融合身份门对 PAR 的反应。

**B. 量化次序差异**：现路径=源像素域 half 量化→渲染时插值；新路径=插值（在 copy 的
mediump shader 内）→目标像素域量化。两级舍入不可交换——**必须用固定 PTS 数值门量化**
（对齐 round2 无表融合 0.12% 先例的口径），并覆盖暗部渐变/锐边/运动。

### 约束清单（全部为硬约束）

1. 帧身份/lease 退休契约不变：cur 命中、retired 采纳、重绘零拷贝复用照旧；
   acquire/release、fence、retire flush 语义不动。
2. updateTexImage 调度、A/V 同步、display-resample 行为不动。
3. 尺寸 generation：surface 尺寸变化（resize/旋转）必须触发 lease 重建与回退判定，
   真实 resize 轮是生命周期验收必测项（可借 `debug.mks.yuv_table_transition` 同款
   VO 级 resize 注入 harness）。
4. 融合身份门（material/UV 角点/尺寸）不得被绕过；lease 尺寸变化要进身份快照。
5. RGBA8 禁令、真实 FBO draw 探测门照旧；格式仍 rgba16f 优先。
6. 属性开关：`debug.mks.st_lease_target`（默认 0=源尺寸），与 `st_lease_rgba16` 正交。
   失败回退=同帧源尺寸 lease（copy 前判定，不产生半帧混合）。

## 四、实验计划（阶段门，逐段过）

- **M0 设计定稿**（无实机）：A1/A2 裁决（对照 `vo_gpu_next.c` 融合门与
  libplacebo `renderer.c` 采样语义源码核验）；静态帧等价推演（不接播放）。
  产出：设计段补进本文档。
- **M1 受限实现+功能轮**：mapper 改动+开关+工具链（instant/thermal_round 增
  `--lease-target` 与 setprop）；F 轮验证生效（新增日志：`MKSURF: lease target-size
  chosen 2672x1336 (src 3840x1920)`，MP_ERR 级）+ 融合 committed 正常 + completed。
- **M2 性能 A/B（原预登记口径，尚未验收）**：同包交错 ≥3 对（A=关/B=开，
  均 `--yuv-fusion`、起温匹配 C 锚）；原计划以不同 session 的 input+render
  频率归一化结果之和为主指标，副指标=无计时轮 MHz/busy。原通过线为每对 B<A
  且中位降幅 ≥10%。分析器明确限制不同 session 不能组成逐帧总量；该和仅为
  代理、不是同帧实测时长，DVFS 未控制，不能由其直接推出实际帧时或功耗收益。
  首组 input/render 混锚，严格同热锚仅两组；性能验收保持 OPEN。
- **M3 数值/观感/生命周期**：固定 PTS 35.035/600.03/720.05 SSBO capture A/B
  （`lg_p84_capture_round.py`）量化差异并对照 0.12% 先例；用户最高亮度观感+暗部/锐边/
  运动片段；生命周期四动作+HOME+**真实 resize 双向**+seek/pause/still/EOF/切源。
- **M4 热态**：240s A/B 匹配起温（`lg_p84_thermal_round.py --reference-start`），
  比较触 cap 时间与温升。
- **M5 LYA 回归**（LYA 也走 surfacetexture mapper）+ critical 复审（生产管线改动，
  收尾前必做；默认翻转另议并需独立复审）。

### 否决/中止条件

原文：总时长 <10%；数值门差异显著超先例量级且无法解释；观感可辨退化；resize/
生命周期失败不可修；等比判定之外的内容出现几何错误（立即收窄或回退）。其中
“总时长”与上述跨 session 频率归一化代理的关系存在歧义，不能以代理直接声称
实际总帧时或能量收益，须先澄清测量能力与可比条件。M3a 现有的是同轮两渲染分支
差异，不是 lease 新旧路径的跨轮数值对照，验收保持 OPEN。

## 五、并行小包（不阻塞主线）

PQ 探针执行可信性修复：GLQ 宏改单次执行+错误终止、canary（clear/draw/read 活性）、
四锚点验证、timer 超时即失败、LUT 端点建表改域映射（参照 libplacebo
`src/shaders/lut.c:282-294`）。修好并复审前，B 轨任何数据不得采用。

## 六、记录与纪律

- 本任务 topic：`archives/conversations/lg-p84-target-lease-20261105.md`（新会话
  首读 Current State）；TASKS 节已建。方案变更回写本文档。
- 实施不派 subagent（用户既有要求；specialist 咨询与 critical 复审除外）。
- 提交需用户授权；证据外置归档约定照旧；OPEN 项如实标注。

## 七、M0 初版裁决（2026-11-05，保留历史；已被 review 推翻部分前提）

> **状态：待重新设计，不作为已验收方案。** critical review 确认 cur/retired
> 发布路径不能维持本节声称的尺寸声明不变量；`hwdec.h` 要求 `dst_params`
> 在 init 后不可变，旧 `--vo=gpu` 还有一次性消费点，因此下文“偏离但安全”、
> “异构帧无需重建即可正确”“融合身份自动闭环”等均未证明。`highp float` 声明
> 不能单独证明硬件纹理滤波采用 FP32、或证明只有一次量化；第 B 节只是待验证
> 假设。现有 M2/M3a PASS 和“未超先例”判断撤回，详见证据索引及 conversation
> Current State。必须保留初始化参数契约、显式传递并校验每次映射的真实几何，
> 不支持的消费者和几何回退；修复后重新评审并实测。

### 裁决 A：取 A1（诚实声明目标尺寸），A2 否决

核验前提（本树架构事实，行号为 perf2/lg-p84 `0206c931ac` 时点）：

- `vo->params` 是**解码器源参数**（`vo.c:605`），mapper `dst_params` 不回传 VO；
  hw 帧以 IMGFMT_MEDIACODEC 源尺寸到达融合门（REJECT(7) 即证）。
- pl_frame 几何来自 mapper 纹理：`map_frame`（`vo_gpu_next.c:746`）只从 dst_params
  取 color/repr/rotation，w/h 不进 pl_frame；crop 由 `apply_crop(image, p->src,
  vo->params->w/h)`（:3026，截图 :3609 同）以**源参数空间**写入。
- 融合门 REJECT(30)=源空间（p->src vs `mpi->w/h` 均源参数），REJECT(34)=图像
  crop 全帧判定（crop 是映射后空间）。
- 生产默认=无表融合（round2 终版），查表为备选；两路径 UV 均源自渲染几何
  （crop→target 映射），不依赖独立几何通道。

**A2 否决（源码证据）**：声明源尺寸 3840×1920 + 纹理 2672×1336 时，crop
(0,0,3840,1920) 超出纹理 → OOB UV（CLAMP_TO_EDGE 拉伸边缘像素）；修复需改
libplacebo renderer scale_main 语义并新增跨仓"pre-scaled"契约，且"声明源尺寸+
纹理目标尺寸"本身就是 specialist 明令禁止的伪报。否决。

**A1 落地（dst_params 诚实声明 + VO 侧几何基切换，libplacebo 零改动）**：

1. mapper（`hwdec_surfacetexture.c`）：门通过时 lease 按目标尺寸分配
   （`take_slot` :1246-1281 已有按 slot 尺寸重分配与 cur/retired 退休保护），
   copy shader 从全屏 identity 改为源矩形→lease 矩形双线性降采样；
   `dst_params.w/h = lease 实际尺寸`（诚实声明==纹理尺寸恒成立）。
2. PAR 补偿恒为 1:1：等比门用精确整数叉乘判定 `src_w*dst_h == src_h*dst_w`
   （全帧、无 crop/旋转/anamorphic 前置条件下）；等比 ⇔ 宽高比相等 ⇔ 无需
   PAR 补偿。不相等 → 整帧回退源尺寸 lease（声明同步回退，不产生半帧混合）。
3. vo_gpu_next：mapped hw 帧的图像几何基从 `vo->params`（源空间）切换为
   **该帧映射纹理实际尺寸**（frame_priv 在 map 时记录）：`apply_crop` 基
   （渲染 :3026 与截图 :3609）、REJECT(34) 全帧判定基、`table_src_w/h` 种子基
   （:2269，查表备选路径）。p->src 源矩形按基比例映射进该帧纹理空间
   （全帧门内即全帧；回退帧比例 1:1 语义不变）。
4. REJECT(30) 保持源空间语义不变（p->src 与 mpi 均源参数，仍诚实）。
5. 融合身份门自动覆盖：material `input_width/height` 取实际 tap 纹理
   （libplacebo `dispatch.c:1887`），tap↔seed 一致性校验（:1183）与角点 UV
   字节比对自动携带新尺寸——lease 尺寸进身份快照（约束 4 满足，lp 无改动）。

### 尺寸感知与 resize（约束 3 落地）

- 目标尺寸通道：`mapper->owner->ra_ctx->vo->dwidth/dheight`（核验 ==
  context_android `p->yuv.w/h` == fusion desc w/h，`context_android.c:2041-2042/:411`），
  mapper 线程与 VO 渲染线程同线程，无竞态。
- 每次 map 时重读目标尺寸并重判等比门：surface resize → lease 尺寸变化经
  take_slot 按槽重分配自然重建（cur/retired 退休保护在位，在飞帧纹理不被
  回收）；`dst_params.w/h` 在重判点同步更新（mks 驱动自有契约，`hwdec.h`
  "init 后不可变"为通用代码注释，本驱动注释声明偏离；map_frame 每次现读
  dst_params，消费点安全）。过渡期异构帧（旧尺寸纹理在飞）：几何基为每帧
  记录值 → crop 正确；查表路径由 tap↔seed 尺寸不一致 → 融合拒绝 → 分裂
  路径兜底（既有机制）；无需 pl_queue reset、无需 mapper 全量重建、不丢帧。
- resize 使 fusion_generation++（`yuv_fusion_invalidate` 既有路径）→ 表按新
  代重播。真实 resize 双向为 M3 必测项。

### 裁决 B：量化次序（数值门设计）

- 新路径 copy shader：OES 纹素读取（f16/源域）→ **highp(float32) 权重与累加**
  双线性插值 → 写 RGBA16F（目标域量化，两路径唯一共同量化点）。
  shader 显式 `precision highp float`（GLES 默认 mediump=fp16 会引入额外舍入，
  与"单次量化差异"口径不符）。
- 两路径量化点计数相同（各一次 f16 落盘+渲染端读回）；唯一差异=插值发生在
  首次量化之前（新）或之后（现）。此外新增核差异风险：copy 双线性 2×2 vs
  渲染端原 scaler 核（降采样 0.696 下混叠风险）——均由 M3 固定 PTS SSBO
  capture 数值门（对齐 0.12% 先例口径）+ 用户观感门裁决，M0 不预判。

### 静态帧等价推演（不接播放）

- 几何：copy 内 3840×1920→2672×1336 等比降采样（0.6958）+ 渲染端 lease→dst
  1:1，与现状"渲染端 3840→2672 缩放"复合等价（全帧、等比、无 letterbox）。
- 数值：量化链见裁决 B；差异仅插值次序+核形状，M3 量化。
- 生命周期：帧身份/退休契约键为帧身份（pts/buffer），与 lease 尺寸无关；
  尺寸变化经 material/角点 UV 进身份快照；updateTexImage 调度、A/V 同步、
  acquire/release/fence/retire flush 全部不动（约束 1/2 满足）。
