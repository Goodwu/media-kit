# P5 mediacodec 路径颜色回归：根因修正与 8-bit 采样域重标定修复（2026-09-30）

## 结论

P4（`android-p5-numeric-color-20260930.md`）报告的「mediacodec 路径约 100 倍颜色回归」**大部分是读回装置缺陷，小部分是真实但小得多的产品回归，两者均已定位并以数值闭环**：

1. **P4 的 100 倍偏差是读回装置缺陷**：P4 读回 JAR（c025cbf mpv + 8370 VO 补丁）链接的 libavcodec 来自 `/tmp/media-kit-prefix-clean-2197`（cd1a08，9/25 构建的 9/24 stage-merged 补丁世代）——该世代的逐帧 RPU 挂载**只能靠 `debug.media_kit.p5_rpu_probe=2` 属性启用**，而 P4 轮脚本没设该属性，硬解帧从未挂载 DOVI 元数据（`P5_GAMUT_SOURCE src_dovi=0`、`P5_SECTION_INIT direct=0`）。补设属性后同方法读回 `src_dovi=1`、`direct=1`。**产品 JAR（fff3ee7 FFmpeg，coded_side_data 自动启用）在设备上挂载正常**：产品轮 12627/12633 日志 `P5_SECTION_INIT direct=1`（该路径强制要求 DOVI 元数据，缺失即报错降级），且 f240 挂载 RPU 与码流第 240 帧 RPU 字节一致（size 245、FNV-1a `d34ff55e`，全流逐帧索引核对）。
2. **真实回归（~0.3%）与修复**：补属性后 direct 路径对主机参照仍有系统性偏差（Sol f240 MAE (185,106,72)、4K50 f501 (160,91,83)/65535，R 均值 +180 紧致分布）。主机 lut 模拟判定其签名与 **YUV 输入被放大 1023/1020** 精确匹配（`val×1023/1020` 模拟 vs 参照 = R +176/G +86/B −3；设备对该模拟残差 R MAE 仅 33、均值 +4）。根因：华为 `OMX.hisi.video.decoder.hevc` 对 10-bit HEVC 输出 **8-bit NV12**（AHB format 0x325；copy 路径 bytebuffer NV12 码值对软解 10-bit 全帧 ≤3/1023、100% 落在一个 8-bit LSB 内），GLES 外部 YUV 采样按 code/255 归一化，而 P5 dovi 重塑域按 10-bit code/1023 解释（8-bit×4=1020 ≠ 1023）。9/25 sidecar 时代曾有 `code_scale=1020/1023` 修正（归档补丁 `android-p5-rpu-auto-candidate-20260925.patch` 前身的 packed10 shader），**产品化重写 direct YUV 路径时丢失**。
3. **修复（mpv fork `398d0c3`）**：`hwdec_aimagereader.c` 检测 8-bit YUV AHB 格式（0x325/0x23/YV12）时，对帧自身 dovi 元数据**就地精确重标定**——pivot×k、多项式系数 a_i×k^−i、MMR 权重按单项式阶数（线性项 k^−1、跨项 k^−2·(j+1)）×k^−d，k=1023/1020；数学上等价于对采样信号乘 1020/1023（精确代入 s=s'/k，非线性矩阵作用于重塑输出域不受影响）。就地修改 mp_image 自己的元数据 buffer 是必须的：pl_frame 在 `map_frame` 阶段捕获 `repr.dovi` 指针早于 `hwdec_acquire` 里的 `mapper_map`，且 `hwdec_reconfig` 每帧把 dst_params 的 dovi 覆盖回源指针。
4. **修复后验收数值（≤100/65535 达成）**：Sol f240 设备↔主机 **(47,50,70)**、4K50 f501 **(50,19,58)**/65535（修复前 attach-on 分别 (185,106,72)/(160,91,83)，P4 断链值 (2726,2603,10212)/(4716,876,8388)）。剩余残差为 8-bit 缓冲量化+解码器暗部/运动区码值差异的底噪（G/B p99 尾部）。主机↔DoViBaker 两参考一致性 P4 已证，三角形闭合。

## 排除链（同帧隔离）

软解（hwdec=no，hevcdec 自动挂载）同链路读回对主机 **(12,13,17)** ——mpv/VO/读回链路精确；mediacodec-copy（P010→实为 NV12 8-bit 普通纹理路径）(173,87,127)、direct（外部纹理）(185,106,72) 同量级 → 差异在解码输出值本身。已逐一排除：RPU 挂载内容（字节级验证）、RPU_BUFFER 转义差异（hevcdec 同挂 `nal->raw_data+2`）、P010 容器（主机 format=p010le 渲染与 yuv420p10 MAE=0）、chroma siting（主机 center-vs-left 仅 (14,28,40) 且零均值）、SEI（f240 AU 仅 picture hash，无色彩元数据）、/1024 归一化（模拟仅 (−23,−16,−23)）、8-bit 均匀量化模型（(118,70,72)，符号/量级不符）。

## 关键证据

- 读回轮 12672–12679（每轮恢复原 12492/自动亮度/熄屏）：12672（Sol+属性）、12673（4K50+属性，f501/f502）、12674/12671（软解）、12675（copy+属性 f241）、12676（探针包，发现 libc++_shared 链接与 `-lc++_shared` 手工链接事项）、12677（copy 探针包 f240：NV12 YUV dump，`P5_YUV_DUMP imgfmt=1006 name=nv12 stride=3840,3840`）、12678（修复包 Sol f240）、12679（修复包 4K50 f501）。日志/dump：`/tmp/media-kit-p5-rpuattach-verify-1267*/`、`/tmp/p5-yuv-dump-copy-f240.bin`。
- 码流 RPU 全量索引（Annex B 逐帧）确认 f240 RPU=d34ff55e、每帧 RPU 内容确实逐帧变化（此前 `-ss -c copy` 提取取到关键帧样本，教训：`-ss` 浮点舍入会跳帧，帧精确参照用全流索引或 `-ss` 略低于目标 pts）。
- 主机参照（/tmp/mkffdv ffmpeg 重生成 f500 与既有参照逐字节一致验证命令等价）；lut 模拟系列 `/tmp/sim-*.bin`（1020/1023、8-bit 量化、1023/1020）。
- 修复构建：libmpv ninja + 手工链接命令补 `-lc++_shared`（build.ninja 的链接行缺该依赖，DT_NEEDED 丢 libc++_shared 会 dlopen 失败——P4 记录的已知事项，本轮以 build.ninja 第 1229/1230 行提取链接命令复现）；APK 直改重签流程（lib store 模式 + zipalign -p 4096 + debug 签名，并同步替换 NDK 27.2 libc++_shared.so）。
- 修复后视觉核验：12678 包 Sol 播放 t12/t24 截图像素统计判定为正常内容帧（无紫/黑/白屏、色彩多样性正常；当前会话模型不支持读图，由子代理像素统计法判定，非目视确证）。

## 边界与后续

- **8-bit 缓冲之谜**：9/25 8386 实验记录 GL 采样 YUV 对软解 10-bit 仅 0.3% 失配点（近 10-bit 精度），而今日同一解码器/同一 reader 参数（PRIVATE+GPU_SAMPLED_IMAGE, maxImages=3）得到 0x325 8-bit。差异载体未定（旧 sidecar 的 GL 读回机制 vs 今日 libplacebo EXTERNAL_YUV 采样的驱动路径差异，或解码会话配置差异）。若可恢复 10-bit 通路，残差可望从 ~50 进一步降到软解量级 (12,13,17)——需对照归档 sidecar 补丁（`android-p5-420-sidecar-8386-mpv-cumulative.patch`）继续排查，本轮未做。
- mpv fork 提交 `398d0c3`（在 c025cbf 之上）**尚未推送 Goodwu/mpv**；产品 JAR/正式包重建待推送后进行。
- P0/P1/P2 视觉验收复跑：产品代码已变（新增重标定），正式包重建后应复跑关键视觉轮 + 真人确认；本轮仅做了修复包的自动化截图核验。
- 读回基础设施改进已留存：VO YUV dump 探针（`debug.media_kit.p5_yuv_dump`，归档于 `android-p5-float-yuvdump-vo-gpu-next-20260930.patch`，基于 398d0c3）、AHB 格式一次性日志（已入产品提交）。读回轮脚本应设 `p5_rpu_probe=2`（本次教训）或改用 fff3ee7 世代 FFmpeg 重建读回 JAR。
