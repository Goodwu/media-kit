# P5 同一 AImage 的 OES NEAREST/LINEAR 双取样（2026-09-25）

## 目的与边界

在同一台 LYA-AL00 / Android10、同一原P5文件 SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`、PTS10.000/第500帧上，检查 `0x325`→EGL/OES 外部取样过滤是否解释既有局部 packed10 差异。诊断只在隔离 mpv 的 raw 420 sidecar 全帧 dump 目标帧启用：**同一次 mapper render、同一张已导入 AImage**，先用 `GL_NEAREST` 画入 Y/UV 中间纹理并读回，再将同一外部纹理改 `GL_LINEAR` 重画/读回，最后恢复 NEAREST 及原目标纹理内容供正常渲染。仅目标帧执行额外同步读回，不用于性能判断；开关默认关闭。

输入保留逐帧RPU，属性为 `p5_raw_yuv=1,p5_raw_packed10=1,p5_raw_code_scale=1,p5_raw_420_sidecar=1,p5_rpu_probe=2,p5_raw_full_dump=1,p5_raw_dual_filter=1`。隔离增量补丁 `android-p5-dual-filter-8390-mpv.patch` SHA-256 `abbb52f244b3d34089dec3b19b7a16f86f09a7f92763596a0d50f425988bbc6e`；只在8386诊断包中替换 `libmpv.so`，zipalign/签名/验签通过。8380/8386产品外诊断逻辑未接入正式依赖。

## 证据

8390 APK SHA-256 `b63cd31744cb056b639a1c4e528f68beab332fd611860a4d7c1ad418d356e223`。原始直播日志经筛选 `artifacts/android-p5-dual-filter-8390-filtered.txt` SHA-256 `a02bb8a303e34026c578b23d97189ceb4227b034f3c97ae140edc87b9dfb4002`：`ANDROID_HDR_OPEN sample=dolbyVisionP5`，目标PTS10 `src_dovi=1`，两次 `P5_RAW_FULL` 都是PTS10、crop/buffer全3840×2160、UV读回各8,294,400字节且GL读回错误0。Y读回文件各33,177,600字节。两次独立启动的四份输出分别同SHA，且NEAREST Y/UV均与先前8386基线逐字节一致。

| 输出 | Y SHA-256 | UV SHA-256 |
| --- | --- | --- |
| NEAREST | `b04220ef51629371d77e5d5eccd9ca773ae063e462d1c3499fcb5a37f048e81f` | `21fe4dc1afe8bcfcfaf9b1193e4e8d98278d4e7dca7b6d1e81b95da3d8918bd1` |
| LINEAR | `c7906a43ff94190958acd96eae07c1213b79c3d8d3dddce16f188327f7808446` | `5610df64aed4ec73b2322a499b036b011de367d6e4b74b2bcfa61fc2eb4fa6de` |

参考是同源 FFmpeg/VideoToolbox 一致的第500帧原生10-bit YUV，SHA-256 `8a41d06c8b14a313864d04907bf3cca667d6f732fa2b2db281d105c3b833fe44`，属独立交叉工程参考，不是官方一致性资产。比较脚本已用既有 `tools/p5_sidecar_yuv_compare.py`；完整统计在 `artifacts/android-p5-dual-filter-8390-{nearest,linear}-vs-sw.json`，状态转移在 `artifacts/android-p5-dual-filter-8390-transition.json`。

| 平面 | NEAREST失配 | LINEAR失配 | NEAREST错而LINEAR对 | NEAREST对而LINEAR错 |
| --- | ---: | ---: | ---: | ---: |
| Y / 8,294,400 | 24,348 | 163,951 | 3 | 139,606 |
| Cb / 2,073,600 | 6,017 | 233,863 | 407 | 228,253 |
| Cr / 2,073,600 | 6,313 | 282,333 | 85 | 276,105 |

**改成普通 `GL_LINEAR` 显著恶化同帧原始样本一致性，不能作为P5修复。** 该试验证明过滤状态能改变OES读回，而且NEAREST恢复原8386读回；但它不能区分 `0x325` 内部后处理与NEAREST点取样在少数局部点各自的贡献。不能把更接近工程参考的NEAREST当作DV标准认证，也不能依据本试验直接改产品路径。下一步仍需有格式合同的Surface前检查点，或对已知失配ROI做另一种真正独立的同AImage采样/供应商转换对照。
