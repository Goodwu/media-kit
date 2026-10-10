# mksvui-regress — MKSVUI HEVC SPS VUI 色度探测 host 回归门

D2 收编（2026-10-10）：把 D1（2026-10-09，/private/tmp/mksvui）的 VUI 探测 host
断言固化为可重跑脚本。锁定对象是分类修复链第一环——FFmpeg fork
`libavcodec/mediacodecdec_common.c` 的 `mcdec_probe_hevc_vui_color`（SPS VUI
色彩描述提取，decoder-origin 分类修复链的源头）。

## 它测什么

每次运行**从活的 fork 源码现场提取**解析器块（`MKSVUIGetBits` ..
`mcdec_probe_hevc_vui_color`，marker 定位；块结构漂移会显式失败而不是测旧拷贝），
用 ASan+UBSan 编译，断言：

1. 固件 fixtures 期望表（下方）；
2. 确定性畸形输入 fuzz smoke（默认 2 万次，`--fuzz-iters` 可调；D1 验收级
   5×200k 用 `--fuzz-iters 200000` 手动跑）。

驱动的是**产品入口** `mcdec_probe_hevc_vui_color`（含 UNSPECIFIED/有效性门），
不是裸 NAL walker。

## 用法

```
./run_mksvui_regress.sh [--fuzz-iters N] [--no-san] [--keep]
# env: FFMPEG_SRC=fork 检出（默认 ~/src/FFmpeg）
# 退出码 0=PASS / 1=FAIL；日志 /tmp/mksvui-regress/run-<ts>.log
```

## fixtures 期望表（D1 后锁定）

| fixture | 期望 | 来源/语义 |
| --- | --- | --- |
| `a.hvcc` | OK trc=16 prim=9 matrix=9 | PQ 补丁素材 SPS（hvcC，3840×1920，无 HRD）；phase1-precision 实机素材的 extradata |
| `a.annexb` | OK 16/9/9 | 同流 Annex-B 布局，锁 Annex-B 扫描路径 |
| `a.265` | OK 16/9/9 | 裸 ES 变体，同上 |
| `b.hvcc` | OK trc=18 prim=9 matrix=9 | HLG 素材，VUI 带 nal_hrd。**D1 前 fail（HRD 整链放弃），D1 HRD 镜像修正后 OK——此处锁定的是 D1 修正后的行为（Lead 已批准 HRD 消费）** |
| `synA.hvcc` | OK 16/9/9 | D1 合成阳性：st_rps 非预测 RPS + used_by_curr_pic_s0_flag 读回（D1 缺陷①回归） |
| `synB.hvcc` | OK 16/9/9 | D1 合成阳性：nal+vcl HRD 并存、cpb_cnt=1（2×49 位 SchedSelEntry，位距 98=2×49；D1 缺陷②阳性对照） |
| `synU.hvcc` | 必须拒绝（ret<0） | **D2 新增**：color description 存在但三者全 UNSPECIFIED(2)——锁"UNSPECIFIED 保持未指定"不变量（结构等价的 16/9/9 对照已验证 OK，失败专门来自有效性门） |

D1 原 harness 的 `hlg`（b.hvcc 必败）断言随 D1 修正废止，不收编。

## 合成 fixture 生成器

`make_syn_sps.py`（本次归档，D1 的生成器未存档）：确定性位写器，可重建
synA/synB/synU。`--compare-d1` 出具与 D1 原件的字节比对报告（非致命）——
重构版在 VUI 色度字段前与 D1 逐位一致，尾部布局未达字节级一致；**D1 原件
（fixtures/ 内）始终是权威**，生成器只以行为方式（C harness 的
synA/synB/synU 用例）被锁定，用于未来新增合成用例。

## 不在本门内（device 层，见 D2 回归矩阵）

color keys 回写回显、avctx 分类、dst_params 传播、mpv 属性读出——均需实机
MediaCodec/解码会话，host 不可断言；既有覆盖为 diag-oes15/euv 历史证据，
device 待验格登记在 D2 结果单。
