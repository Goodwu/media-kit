# LG P8.4 · D3 上游化决策记录（2026-10-10，followup 计划 D3 交付）

## 决策

**FFmpeg fork 长期携带 D1 修正与 MediaCodec 颜色探测特性；不向上游提交补丁。**
同时收口 D2 移交的两项裁决（见 §3）。

## 依据（事实，Scout 收集 2026-10-10）

1. **不存在可上游化的缺陷修复**。D1 修的两个缺陷（非预测 st_rps 漏读
   used_by_curr_pic_s0/s1_flag、nal_hrd+vcl_hrd 并存时 SchedSelEntry 单遍）全部位于
   fork 自写的镜像解析器内；上游基线 `libavcodec/hevc/ps.c`（7.1.3）对同样两处本来就
   正确（L217/L230 每个 delta_poc 后各读 1 位 used；L433-438 nal/vcl 各自独立调用
   decode_sublayer_hrd）。上游无同缺陷，无"修 bug"型补丁可提。
2. **镜像解析器是 fork 特有新特性，且首次入库即含修正**。整块代码
   （MKSVUIGetBits…mcdec_probe_hevc_vui_color，+605 行/-0，仅 mediacodecdec_common.c）
   由 d4bb79394b 一次性引入（`git log --all -S MKSVUIGetBits` 唯一命中）；开发期含缺陷的
   440 行工作版从未进 git，缺陷修正烘焙在首提交。上游化=提议整个"MediaCodec HEVC VUI
   颜色探测"新特性，属功能贡献而非修复，收益/接受概率与维护责任不成立。
3. **该特性是 media-kit 产品行为链的组成部分**：VUI 探测服务 D2 分类修复链
   （color keys 回写+dst_params 传播，MKSCOLORKEYS 机制 avctx trc=16），与 fork 内
   native_dv 门（P5/P8）同属 fork 携带的整条 MediaCodec 定制线；单拆一件上游化不减少
   fork 携带面。
4. **fork 携带成本有界且已有缓解**：代际升级链式影响（genbump 事故：DPS stash 与 prefix
   错代致 exit(1)）已通过方案 b 单代化（链接配方重指 prefix tip，override 退役）消除
   主要复发面；全量重建成本实证在案
   （`~/src/media-kit-build/lg-api24/genbump-provenance-20261010/bisect-INDEX.txt`）。

## D2 移交裁决

1. **MKSVUIPROBE/MKSCOLORKEYS**：实查为 av_log 文本标签（mediacodecdec_common.c:1717/
   1721/1726），**非环境变量开关**（链上无 getenv 注入，与 D2 记录的更正一致）——
   "降级"无对象，**保持现状**；其日志行为 mksvui-regress 回归 harness 的断言依据，
   移除将破坏回归锁定。
2. **configure hack**：位于 media-kit-build 构建树配方（prefix-build），非 FFmpeg 仓
   内容；是当前已验证构建配方的成分（fork tip d4bb79394b + configure hack + kazumi hls
   patch）。**短期保留**（过渡态）；其**正式化方案已另立 G 线 G1**（2026-10-10 用户裁决
   "configure hack 需正式方案"：推荐方案 B=清空动作收敛为构建仓确定性步骤+重建归档与
   现役 genbump2 代逐字节一致门，待用户批准实施，见计划文档 §14）——G1 批准后本节
   "保留"由 G1 的实施与字节门接管，上游化形态归 D3 记录的复审触发（见下）。

## 复审触发条件

- 未来 fork rebase/升级到含等价 MediaCodec 颜色探测能力的上游版本时；
- 决定向上游 FFmpeg 提交 MediaCodec 颜色特性（整特性贡献，独立立项）时；
- D1 修正若发现上游 ps.c 回归（上游自身引入同类缺陷）时，可转为上游缺陷报告。
