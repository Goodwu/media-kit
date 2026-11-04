# LG P8.4 目标尺寸 lease 方案与环境交接（perf round 3，2026-11-05）

> 新会话接手文档。前置任务：perf round 2（`TASKS.md` §LG-P84-PERF-ROUND2-20261104，
> 归档 `archives/conversations/lg-p84-perf-round2-20261104.md` 含五轮 critical 复审与
> specialist 评估全文）。本文自包含：环境→事实→设计→实验计划→验收→风险。

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
- **M2 性能 A/B**：同包交错 ≥3 对（A=关/B=开，均 `--yuv-fusion`、起温匹配 C 锚）；
  主指标=input+render 频率归一化总时长（分析器 `--pair`），副指标=无计时轮 MHz/busy。
  **验收=每对 B<A 且中位降幅 ≥10%**；达不到→如实报告并停。
- **M3 数值/观感/生命周期**：固定 PTS 35.035/600.03/720.05 SSBO capture A/B
  （`lg_p84_capture_round.py`）量化差异并对照 0.12% 先例；用户最高亮度观感+暗部/锐边/
  运动片段；生命周期四动作+HOME+**真实 resize 双向**+seek/pause/still/EOF/切源。
- **M4 热态**：240s A/B 匹配起温（`lg_p84_thermal_round.py --reference-start`），
  比较触 cap 时间与温升。
- **M5 LYA 回归**（LYA 也走 surfacetexture mapper）+ critical 复审（生产管线改动，
  收尾前必做；默认翻转另议并需独立复审）。

### 否决/中止条件

总时长 <10%；数值门差异显著超先例量级且无法解释；观感可辨退化；resize/生命周期
失败不可修；等比判定之外的内容出现几何错误（立即收窄或回退）。

## 五、并行小包（不阻塞主线）

PQ 探针执行可信性修复：GLQ 宏改单次执行+错误终止、canary（clear/draw/read 活性）、
四锚点验证、timer 超时即失败、LUT 端点建表改域映射（参照 libplacebo
`src/shaders/lut.c:282-294`）。修好并复审前，B 轨任何数据不得采用。

## 六、记录与纪律

- 本任务 topic：`archives/conversations/lg-p84-target-lease-20261105.md`（新会话
  首读 Current State）；TASKS 节已建。方案变更回写本文档。
- 实施不派 subagent（用户既有要求；specialist 咨询与 critical 复审除外）。
- 提交需用户授权；证据外置归档约定照旧；OPEN 项如实标注。
