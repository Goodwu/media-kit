# 输出融合 + UV 查表 生产化方案（2026-11-01）

## 背景与已证前提

- 输出融合（末级 RGB→YUV CSC 并入渲染主 pass）短时实测 GPU 频率×busy 代理 -36.7%、CPU -12.2%（backlight64 ABBA 四轮）；画质阻断=融合 pass 与原 final pass 的 UV 采样坐标舍入不同（1634 像素 V 分量 1-3 ULP）。
- schema10 已证（r19+final 双复现，nonce 独立）：A0 记录的 UV 表跨帧复用后，消费侧全屏 UV 与 half RGB **逐位相等**（captured-floats-bit-equal, cross_pts_reuse_validated=true）。
- 解析 UV 公式无法逐位复现（早期证伪）；表是已验证的唯一等价路径。

## 生产形态

**每帧流程（表 READY 时）**：
1. mpv 融合门（现有 mask 0-34）全过 且 表 READY → 融合渲染到 YUV wrapper。
2. libplacebo dispatch 生成 rgb16f_to_yuv 最终 pass 时，检测 gpu 上挂接的生产表 cache → body 的 `textureLod(tex0, uv0, 0.0)` 替换为 `textureLod(tex0, mks_cache_uv(), 0.0)`（复用 `mks_atlas_b0` 变换），并追加只读 SSBO descriptor（binding 0, mks_cache_block = cache 的 storage buffer）。pass signature 合并新盐 `0x43503555564154`（"UVTABLE"）区分缓存。
3. 输出 = 查表版融合 pass（生产 B0，无任何探针代码）。

**首帧建表（SEED）**：
- 该帧不融合：原路径渲染（RGB FBO + final pass），画面与现状逐位一致。
- 同帧追加 schema9 式锚事务**轻量模式**：A0 → atlas 记录 companion → A0（3 个 GPU pass，毫秒级），**不读回 RGB 对照**（r19 的 ~10s 主要来自 171MB 读回+分析，生产全部去掉），fence 后 poll COMPLETE → promote（表常驻 GPU ~41MiB；count 高位标记保留，host 不扫）。
- promote 成功 → attach 表 → READY。

**表失效**：
- libplacebo consumer 逐 pass 校验 material/geometry signature（现有机制）；失配 → cache invalidated。
- mpv 每帧渲染后检查 cache invalidated / poll FAILED → detach → 回 OFF（该帧起回原路径）→ 下一满足门条件的帧重新 SEED。
- 融合门 reject（如 seek 后 crop 变化、interpolation 帧）期间不渲染融合，表保持；门重新通过且 signature 未变则继续 READY（跨帧复用已证）。

**失败回退**：
- SEED 任一步失败（arm/promote/fence）→ OFF + 本会话禁用融合表（普通路径），下帧可重试一次；连续 2 次失败 → 会话内永久 OFF（记日志）。
- READY 帧 pass 编译失败/GL 错误 → 现有 fusion gate 的 disabled 回退链（rgb-fresh/final pass 保障画面）。

## 未插桩等价验证（schema11，实机门）

事务（单帧、复用 compare 框架 + 表基础设施）：
1. SEED 建表 + promote（诊断工具已有）。
2. 同一帧：A0 渲染（RGB FBO）→ final pass 正常输出 → Android ROI CSC 采样（7 words/px）。
3. 生产查表 B0 渲染（真实生产 pass，无探针，attach 表）到 YUV wrapper → Android ROI 采样。
4. host 对比两侧 ROI YUV 逐位；全零 → 等价通过。
5. 对照组：无表融合（旧 B）应仍呈现既有差异（验证测试装置灵敏）。

## 性能/温升验收

- 低亮度(backlight64) 交错 ABBA×2 起（fusion+table vs 原路径），20-55s 窗 GPU 频率×busy、CPU；判据：与既有 fusion 数据一致的稳定降幅。
- 匹配起播温度的长时（≥240s）温升对照；USB 供电条件记录，不宣称整机功率。
- 用户观感（亮度/色彩/黑位/高光/流畅度）确认。

## 生产落地

- **已落地（2026-11-01，用户裁决：默认启用，先例 sdrEmbed"不加开关默认用"）**。三处默认门翻转（属性空=开，显式 "0"=退回）：
  - `mpv video/out/opengl/context_android.c`：`debug.mks.yuv_fusion`（输出融合总门）
  - `mpv video/out/vo_gpu_next.c`：`debug.mks.yuv_fusion_table`（UV 查表三态机）
  - `mpv video/out/gpu_next/context.c`：能力缓存随表默认配置
- 最终生产包 `fusion-table-prod-20261101-release.apk`（SHA256 `b2774896…5a052`）装机核验一致后三态实测：属性空→表自动建+融合查表（首试 ready）；`yuv_fusion_table=0`→融合保留表关闭；双 0→完全回 `rgb-final` 原路径。
- 生命周期回归：暂停恢复/seek/HOME 返回表保持（实机）；stop 拆除失效（实机）；EOF 重播（探针 Dart 契约失败，非表）；旋转/resize 转换链路由身份门+尺寸门代码与单测覆盖（锁横屏测试 App 无法自然触发，live resize 未上机为残留边界）。

## 边界（不宣称）

- 表构建信任 schema9/10 已验证的记录机制，生产 seed 不做 host 数值校验（count 高位标记仍写，诊断模式可查）。
- 未插桩 B0 等价以 ROI 仪器采样 + 全屏 UV/half（schema10 探针版）双证据链支撑；物理 YUV 全屏字节、面板光学、整机功率不在本轮范围。
