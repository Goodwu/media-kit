# 关键帧起播恢复优化（HOME 返回 / 手动 seek 首帧黑屏）方案（2026-11-03）

状态：**已退回（2026-11-04 收尾 critical review：B1 陈旧时间戳/B2 反向坐标/B3 证据误判/B4 兼容矩阵不足）**。B1 已随守卫撤除消解、B2 已修（`play_dir>0` 门，`phase4-mpv/mpv-recovery-final.patch`）；B3 的更正（KF3/KF1 实为 478/557 present、黑截图系 LG 采集盲区、回退数字系分析器伪值、115.181 非供流失败定论）与后续工作包见 `archives/conversations/home-return-session-restore-20261102.md` 头部；重开前须按后续工作包完成。上游任务 `HOME-RETURN-SESSION-RESTORE-20261102`。

## V2 裁决摘要（2026-11-03）

- **方向成立**：完整 A/V keyframes seek 清 AO/重置 A/V/清 `playback_pts` 与 HR 状态（`playloop.c:419-438,240-275`），比单独放宽视频显示门正确。
- **阻断（正式合入前）**：**B1** 恢复非原子——`queue_seek` 只覆盖未执行 pending，后到 relative EXACT 可经 MAX 升精度，属性逐个 await 非队列事务；须定义恢复请求独立身份与用户意图优先级（用户 seek/open 提交时即使旧恢复失效）。**B2** 音频粗索引关键帧 ~10 s（Round 5 实例 target85→75.096）与"≤1 视频 GOP"冲突——须分别记录视频/音频实际落点，超限则修对齐或重裁验收。**B3** source/owner epoch 保护不了同源新用户 seek；`_command` 默认非 strict、demux seek 可失败；普通 seek 会清 `completed`（EOF 复活风险）——内部入口需定位意图序号+提交前后身份复核+明确跳过/失败语义。**B4** 全 SDK 默认 `hr-seek=no` 影响所有 native 消费者/平台/音频定位，无证据支持——先窄域 PoC，全局默认另行裁决（本轮撤回，见下）。
- **PoC 条件**：位置=提交时实时重采样并校验 entry/seeking/无用户 pending；后台音频基准=提交时位置并报告可听回退；暂停返回保持暂停（与 VERY_EXACT 刷新优先级明确）；锁沿用 Player 粒度勿扩大（防与 open 循环等待）；失败仅诊断不重试不清 completed。
- **建议**：framedrop/back-buffer 不动；勿借用 startup_positioning"VO 无帧"判据（新 VO 也无帧，需显式 runtime 原因）；首帧后采样 ≥15 s。
- **验收协议修正**：主起点=用户输入时刻（AMS 替代须另名报告）；每轮公布首帧 PTS、视频回退、音频回退、child seek 次数、最大冻结/静音、A/V 偏差；快速/普通 HOME 各 ≥5、暂停与后台两态；失败轮不得丢弃。
- **PoC 范围修正（2026-11-03）**：SDK 默认 `hr-seek=no` **本轮不改**（B4），手动 seek 关键帧化另行窄域处理；PoC 仅验证 HOME 返回恢复 seek 收益。

## 用户产品裁决（2026-11-03）

- 跳到离目标最近的关键帧**直接开始播放**即可，接受重复一小段画面；**重复画面优于长时间黑屏**。
- 适用范围：HOME 返回恢复与**手动 seek 同样处理**（用户确认手动 seek 存在同样问题；实测数据 `p3/phase2/piliplus/ff-seek/`）。

## 历史先例（2026-11-03 用户确认）

PiliPlus `archives/conversations/video-startup-latency-20261022.md` Round 5（keyframe-start resume，用户批准、无开关）已在 mpv fork 落地三处：① `mp_seek` 启动关键帧规则——**当前条目渲染首帧之前**的 DEFAULT absolute seek 不升级 HR；**显式 EXACT 与播放后交互 seek 当时明确不动**；② `switch_segment` 不再强制 SEEK_HR；③ `refresh_skip_timeline`。实测续播起播 ~10 s → 4.5–6.7 s。**本次改动 = 把同一原则从"启动定位"扩展到"runtime 恢复 + 手动 seek 默认"（用户 2026-11-03 裁决），应扩展现有 startup_positioning 判定（`playloop.c:333-353`、`loadfile.c:1937`）而非另起机制**；Round 5 的既有测试与 eager/pending proof 不得回归。归档中另有"unified startup positioning"下一轮规格（音频 HR 追赶、≤3 次 seek、目标 ~2 s）为相关未实施方向。

## 根因（Specialist 源码定位，mpv `player/*`、`demux/*`）

1. **恢复机制有三层精确性来源**：
   - `vo/wid` 属性更新（UPDATE_VO）在已有视频轨时排队 `MPSEEK_RELATIVE,0,MPSEEK_EXACT`（`command.c:8137-8145`；同类 `:8170-8180` VD、`:8197-8202` HWDEC）；
   - `vid` 重选经 `reset_video_state()` 置 `STATUS_SYNCING` 但不清 `playback_pts` → `video.c:482-490` 隐式精确门：`img->pts < playback_pts - 5ms` 的帧解码后丢弃不显示；
   - 暂停刷新 `MPSEEK_VERY_EXACT`（`video.c:298-313`）。
2. **`vid=no` 清空视频缓存**：轨道取消选择对**全部 cached ranges** 执行该流 `clear_queue()`（`demux.c:918-933`），EDL 传播到 child demux（`demux_timeline.c:243-269`）→ 增大 back-buffer **不能**保住 GOP，饥饿期是真空等网络重定位。
3. **media-kit 默认配置放大问题**：`hr-seek=yes` + `hr-seek-framedrop=no`（`media_kit/.../native/player/real.dart:2855-2891`）→ 手动 seek（PiliPlus absolute，无 keyframes flag）全部精确恢复。
4. 首帧后的卡顿另含 cache-pause 恢复（`playloop.c:745-797`，默认等待量 1 s）。
5. 实测：HOME 返回 DV 源首帧 8.3–10.0 s，其中网络 GOP 追赶 6.5–8.1 s（`ff-attr/`）；应用内 pause→resume 131 ms；A2 授权链仅 0.2–0.4 s。

## 修改路线（三层，PoC 先行）

**PoC（media-kit Dart，先行验证收益）**：
- `_bindPlatformViewSurface` 真实 runtime 重建（非首次 open、非尺寸变化、非重复 listener）最后属性 ACK 后、发布 bound 前，经**受源/owner epoch 保护的内部恢复入口**发一次 `seek <pos> absolute+keyframes`（全 A/V；不能只动视频门——完整 seek 会 flush AO、清 `playback_pts`，同时消除显式 HR 与隐式门，A/V 落点一致，`playloop.c:419-438`）。
- 落点 `android_video_controller/real.dart:1618-1635` 附近；注意 `:915-919` 既有警告：重建中额外 seek 会丢 HEVC references，PoC 须验证无重复 flush/网络定位。
- `Player.seek` 无 seekFlags → 需要内部通道传 flag（保留序列化、错误与 completed 语义，勿用裸 `command()`）。

**正式路线**：
1. **media-kit**：默认 `hr-seek=no`（`real.dart:2868`）→ 手动 seek 关键帧起播；显式 exact 场景保留（A–B 循环、逐帧等）。
2. **mpv（须用户单独授权实施）**：`command.c` 三处内部恢复 EXACT → DEFAULT（遵循 `hr-seek` 选项）；`loadfile.c:764-770` runtime 视频重选时安排一次**有界、去重**的完整 A/V 非精确恢复 seek（guard：真实 runtime 重启而非 eager startup、有效位置、无待执行显式精确 seek、源一致；合并已有恢复请求）。**不改**：`video.c:482-490` 精确门本体（只屏蔽它不正确：不重选关键帧、不清 AO）、`demux_timeline.c` eager/pending proof 与段裁剪、EDL 段切换语义。
3. **PiliPlus**：零功能改动（UI 已是 absolute；`storage_pref.dart` 缓存配置暂不动）。
4. back-buffer 加大仅作后续对照实验。**GOP 已实测（2026-11-03）**：本地副本（设备拉回，SHA `7626cac2…` 一致）234 个关键帧、间隔**恒定 5.005 s**（max=min=avg，固定 GOP 编码），按均码率 8.1567 Mb/s 约 **4.98 MiB/GOP**——视频侧回退预算 ≤5.005 s；音频侧关键帧间隔约 10 s（Round 5 实测），EDL 联合落点可能由音频主导（V2 复核中）。原始数据 `/tmp/p84-gop/{kf.txt,intervals.txt}`（临时，重启丢失，结论已记录于此）。

## 明确保留精确性的场景

显式 `+exact`/逐帧/末帧、A–B 循环边界、EDL 段裁剪、暂停刷新（VERY_EXACT）、启动定位与 eager startup Variant A（`demux_timeline.c:480-496,821-835`，pending-generation/flags 与既有测试不动）。

## 验收（目标，非性能保证）

- 相同源、GOP 中段、网络分组：快速/普通 HOME 各 ≥5 轮；**用户恢复→真实视频首帧 ≤1.5 s**（统计 AMS 恢复→首帧、surfaceCreated→首帧、Executing→首帧）。
- 首帧视频 PTS 回退 ≤1 个**实测** GOP；记录音频实际落点（EDL 音频粗索引可能额外回退，不能只看 time-pos）。
- 首帧后 10 s 连续推进，无二次多秒冻结/长静音/持续 A/V 偏差；硬解、HDR、授权屏障仍通过。
- 必测回归：手动 seek、显式 exact、暂停返回、后台继续音频、EOF 重播/循环、A–B、EDL 段边界、首播/eager startup、快速连 seek/open/dispose。
- 诊断关联：`refresh track`、`execute seek`、`in-cache seek`、`hr-seek skipping`、首包/首解码输出/首 VO 呈现、缓存范围；ACK/time-pos 变化不算首帧。
- **过 V2**：跨 A/V 时钟、全局 seek 语义、startup 定位证明、surface 所有权边界；迟到恢复不得覆盖用户新 seek/open。

## 授权状态

- **2026-11-03 用户裁决"授权开工"**：覆盖本方案全部实施（media-kit PoC + `hr-seek=no` 默认 + **mpv 三处改动**）与 GOP 实测（含从设备拉回同 SHA 副本绕开 Downloads 权限）。mpv 实施前仍须重新核对并保护其工作树（当前干净，HEAD c7bffdd1）。
