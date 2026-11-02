# 生产 UV 表映射不变性证明（2026-11-01，对应复审 P1「material/geometry 身份」）

## 结论（2026-11-02 修订：按复审意见收窄声称范围）

已闭合：**不同尺寸/采样器/格式类的最终 tap 纹理切换**——dispatch 每次表驱动 pass 生成时将当前 tap 纹理（w/h/sampler_type/format type/num_components）与建表 material 逐项比对，失配即拒绝融合回原路径（`table-input-mismatch`）。复审构造的"peak 运行时翻转→still 帧单帧缓存→tap 换目标尺寸缓存纹理"路径被尺寸比对精确拦截（正向/负向行为测试：tool/test_lg_table_material_gate.py）。

**已闭合（fix23，2026-11-02）：UV 角点字节级身份门**——建表时归档种子 pass 四角 UV 浮点（dispatch run_atlas_anchor 经 uv_corners 回调写入锚，float[8]），消费侧每次表驱动 pass 生成时提取当前四角与归档 memcmp，任何位级漂移（含同纹理 rect 变化、端点经不同路径重舍入）拒绝融合（`table-uv-drift`）。与 material 门（尺寸/采样器/格式）+ 尺寸门 + tap 形状校验 + 逐帧 serial 共同构成映射实际数值的完整身份闭环。fix23 实机 60s 完整轮零误报（种子↔消费角点正常路径位级一致）。

## 原始枚举（2026-11-01 版）

生产表准入采用**受限准入 + 可达输入不变性**闭合：像素→源 UV 映射的每一个决定性输入都被一个指名的门条件钉死在逐帧检查中；种子帧与消费帧通过**同一组门**，因此凡到达表驱动融合的帧，其映射输入与建表帧完全一致。本证明不依赖"高层配置近似实际映射"的推断，而是穷举映射输入并逐一对应门条件。

## 映射输入穷举 → 门条件对应

输出像素 → 源 UV 的映射（schema9/10 已证仅由几何决定；scaler 权重不影响坐标）由以下输入完全决定，每个输入在 `fusion_frame_rejects`（vo_gpu_next.c:1157-1230）或其补充门中被逐帧钉死：

| # | 映射输入 | 钉死条件（逐帧检查） |
|---|---|---|
| 1 | 源裁剪矩形 image->crop | REJECT(34) `fusion_full_rect(image->crop, mpi->w, mpi->h)`——必须全幅 |
| 2 | 源内部矩形 p->src | REJECT(30) p->src == (0,0,mpi->w,mpi->h) |
| 3 | 源尺寸 mpi->w/h | mpv 身份门逐帧比对建表快照（table_src_w/h） |
| 4 | 目标裁剪 target->crop | REJECT(28) `fusion_full_target_rect`——必须全幅 |
| 5 | 目标内部矩形 p->dst | REJECT(29) p->dst == (0,0,desc->w,desc->h) |
| 6 | 目标尺寸 | dispatch 逐 pass 尺寸全等门（失配 detach + 拒绝生成） |
| 7 | 源旋转/翻转 | REJECT(6) mpi rotate/vflip |
| 8 | 目标翻转/旋转 | REJECT(11) desc->flipped、REJECT(14) target->rotation、REJECT(32) image->rotation |
| 9 | 混帧/插值（改变每帧 UV 计算） | REJECT(9) mix->num_frames==1、REJECT(10) !is_interpolated |
| 10 | 采样点结构（最终 pass 的坐标表达式形状） | dispatch 逐 pass 单 tap 校验（唯一受支持采样点 + vec2 varying；非唯一即拒绝融合） |
| 11 | hook/overlay/扭曲（可改写坐标路径） | REJECT(13/19/20/21/22/24/26/32) 全拒 |
| 12 | 目标格式/色域（影响 CSC 不影响 UV，仍钉死） | REJECT(15-18/27) |

补充说明：
- scaler kernel 与 linear/correct_down 开关（mpv 身份门快照）影响采样**权重**不 influence 坐标，但仍被逐帧比对——多余但无害的强约束。
- 种子帧建表时通过**同一组门**（seed 条件要求 rejects==0），锚记录的即该几何下的全屏 UV。
- 消费帧通过同门后，dispatch 的逐 pass tap 校验保证坐标表达式形状可重写且唯一，逐帧 table-pass serial 收据保证查表执行。

## 边界（如实）

- 本证明的可达性以 `fusion_frame_rejects` 的实现为准：新增 REJECT 之外的渲染特性（未来 libplacebo 新 hook 类型等）进入该管道时，需重新核对本表。
- 顶点字节布局（quad 顶点数据）未逐字节比较；其由上述几何输入决定且 tap 校验验证了 varying 形状，若有非几何来源的顶点漂移路径，属本证明之外（未发现可达路径）。
