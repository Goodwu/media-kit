# P5 PRIVATE/OES 像素中心取样偏移 A/B（2026-09-25）

目的：上轮同文件比较已把 P5 第500帧局部 YUV 差异收敛到**输出模式相关的链路**。本轮只改隔离 mpv 的 `GL_EXT_YUV_target` raw packed10 shader 采样坐标，检验它是否可用简单、固定的亚像素平移修正；不改变码流、硬解设置、RPU、10-bit 缩放、420 sidecar 或 libplacebo 颜色算法。

隔离源码 `/tmp/media-kit-mpv-clean-2194/video/out/hwdec/hwdec_aimagereader.c` 原先在 `GL_NEAREST` 外部纹理上按 `gl_FragCoord.xy / size` 取样。本轮默认关闭的 `debug.media_kit.p5_raw_sample_shift` 模式 1/2/3/4 分别给取样坐标加 `(+0.25,0)`、`(-0.25,0)`、`(0,+0.25)`、`(0,-0.25)` 个输出像素，先加偏移再做 crop 映射。累计诊断增量补丁 `android-p5-quarter-shift-8388-mpv.patch` SHA-256 `02391b0145336fa5a87026a4f60d042c96d01cd5cafaa0f6c193f2691b3a84b9`。为验证开关实际作用于 shader，8389 只把模式1改为 `(+0.75,0)`；其补丁 `android-p5-threequarter-shift-8389-mpv.patch` SHA-256 `0cb3c96224c7c1faf5a79c636a2359a96652bc61c11e522cafb21656b39740ad`。两包均从8386重打包，仅替换含该增量的 `libmpv.so`，zipalign/签名/验签通过；8388/8389 APK SHA 分别为 `4d210ccffda4cd9360a018c1d4c099ec3db22da1aab649d0f93ab9e56163ec0f`、`b13620048f1bcb0dff84879df314d5b7c44318a4f15e42da35e9f6a1722c0ec1`。

同机 LYA-AL00、原P5 MP4 SHA `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`、4K50/PTS10.000、第500帧。每轮启用 `p5_raw_yuv/p5_raw_packed10/p5_raw_code_scale/p5_raw_420_sidecar/p5_rpu_probe=2/p5_raw_full_dump`，只改 sample shift 属性。每轮日志均记录 `src_dovi=1`、同一PTS、Y/UV完整读回、GL error0；筛选日志 `artifacts/android-p5-hevc-decoder-probe/quarter-shift-runs-filtered.txt` SHA-256 `f6f363271ac0bc72f16207911aae0c66356b39373486226bb205d741d0c25b25`。此日志未逐轮打印实际 uniform 值；模式由设置的属性、编入APK的分支和下述阳性对照共同核验。

| 模式 | 偏移 | Y SHA-256 | UV SHA-256 |
| --- | --- | --- | --- |
| 8388 / 0 | `(0,0)` | `b04220ef...` | `21fe4dc1...` |
| 8388 / 1 | `(+0.25,0)` | 同基线 | 同基线 |
| 8388 / 2 | `(-0.25,0)` | 同基线 | 同基线 |
| 8388 / 3 | `(0,+0.25)` | 同基线 | 同基线 |
| 8388 / 4 | `(0,-0.25)` | 同基线 | 同基线 |
| 8389 / 1 | `(+0.75,0)` | `f3acefb1f842146169eaea1480a980f5a863069663690aa42ed99ae8ceaf900b` | `158e679c971125269e426e26197b181e4f48c651e183bb73993fa0d3a0034b5e` |

基线完整哈希 Y=`b04220ef51629371d77e5d5eccd9ca773ae063e462d1c3499fcb5a37f048e81f`、UV=`21fe4dc1afe8bcfcfaf9b1193e4e8d98278d4e7dca7b6d1e81b95da3d8918bd1`，与旧8386相同。对软件/VideoToolbox参考10-bit第500帧，基线GPU整数失配 Y24,348/Cb6,017/Cr6,313；+0.75x阳性轮变为 Y1,735,758/Cb340,284/Cr380,774。与同源 ByteBuffer8 比较的高8位失配，基线19,653/4,131/5,500，阳性轮1,061,653/189,751/238,945；完整JSON `artifacts/android-p5-quarter-shift-positive-compare.json` SHA-256 `cb08829d40ca4c7294346925159ba3387cdcd22bae4874cdb5ae6db24259104d`。阳性轮原始Y/UV当时保存为 `/tmp/media-kit-p5-shift075-{y,uv}.bin`，其SHA见上表，比较完成后按用户要求删除；重复的四分之一像素文件也已清理。

结论边界：`GL_NEAREST` 下四个 ±0.25 像素偏移没有改变任何中间纹理码值，+0.75x则大范围改变且显著变差。**小的全局坐标偏移不是当前局部差异的有效修正**；这不证明厂商 `0x325` 基础层本身错误，也不排除局部非线性采样、Surface模式后处理或其他大于测试范围的取样差异。下一步应在同一 PRIVATE buffer 上改变外部取样实现/滤波并比较原始Y，或寻找Surface输出前的可读检查点，避免直接改RPU/色彩映射掩盖基础层误差。

实验后隔离源码已恢复，按同一正确RPU静态库重链并strip得到原8386 `libmpv.so` SHA `73113a6ba9c4209f136df47e269cf3bb509c417094d124b7c17bcb4b7bd68942`；临时链接前缀也恢复原SHA。手机安装10369基线、原P5源SHA不变、相关属性含新开关均0、应用无进程。

8388/8389诊断APK在归档身份与补丁后已按用户要求从`/tmp`清理；保留的8386基底APK可用于重建。清理边界见`android-tmp-cleanup-20260925.md`。
