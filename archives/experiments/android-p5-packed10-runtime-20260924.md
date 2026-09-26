# P5 packed10 单纹理真机 A/B/A（2026-09-24）

目标机 Huawei LYA-AL00（`3EP7N18C28016072`），同一个 8335 arm64 Release APK、P5 原片、Texture SDR、MediaCodec、gpu-next/OpenGL、逐帧 RPU 附着（`p5_rpu_probe=2`）与 raw YUV（`p5_raw_yuv=1`）。无 VO/GPU 热路径计时探针。切换仅为 `p5_raw_packed10=1,p5_raw_mrt=0` 与 `p5_raw_packed10=0,p5_raw_mrt=1`；两者 `p5_raw_half=0`、`p5_raw_early_fence=0`。设备仍留有旧属性 `p5_raw_retire=1`，但实现要求 early fence 才启用 retire，因此两路均未启用延迟释放。三次都进入单视频页、`ANDROID_HDR_OPEN` 成功，decoder 掉帧为 0，播放到 132 秒片尾。

| 8335 顺序 | 中间纹理 | t60 VO 累计掉帧 | t90 | t120 | 片尾 | Texture 累计回调片尾 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| A1 | 单张 RGB10_A2 packed YUV | 12 | 15 | 21 | 27 | 6359 |
| B | 三张 R32F Y/U/V MRT | 926 | 1487 | 1994 | 2409 | 4190 |
| A2 | 单张 RGB10_A2 packed YUV | 21 | 31 | 44 | 47 | 6361 |

packed10 首轮截屏显示正常视频内容而非纯色/紫屏；截屏不是独立色彩参考、也不证明真人可见流畅或 HDR 激活。A/B/A 强烈支持原三张 R32F 中间纹理及其相关资源/同步成本是 P5 掉帧的主要因素之一；尚未分离纹理字节量、attachment 数、FBO 路径与驱动格式实现。该实验没有对每个原始 10-bit YUV 分量、libplacebo 通道映射、RPU reshape 输出做独立数值比较，因此不能宣布颜色或 DV/HDR 验收。首帧前的 8334 候选因本地 libplacebo 未登记 `GL_RGB10_A2`，报 `Failed mapping iformat 32857`，无有效播放；8335 补了该格式登记后才进入有效 A/B/A。

实现位于隔离 mpv 源 `/tmp/media-kit-mpv-clean-2194` 和外部构建仓的 `buildscripts/deps/libplacebo/src/opengl/formats.c`，默认关闭、属性控制。前者增加独立 `IMGFMT_YUV444_PACK10`（单平面 Y/U/V 各10位），单张 `GL_RGB10_A2` FBO、单次 draw 输出原始 YUV、单张 wrapped texture，保留 `repr.bits=10/10` 与逐帧 DOVI metadata；后者在 GLES3 格式表登记 RGB10_A2 及 10/10/10/2 packed host layout。归档的两个 integrated patch **包含此前 P5 raw/R32F 实验基础**，分别针对 mpv `32a164cc017acab50389f2194f720ccfd0b01a28` 与 libplacebo `d4624cbfb37fdef337a7da5794b66202671a89cd`，不是仅本轮增量。补丁 SHA-256：mpv `08073f0ce4c05f66304a20f281c0fbd420a1da250102d77ca9d585c3018d32ac`，libplacebo `2d30184fbd6145455dd6118eeb94f54f74900bacdd7a601b13eddaf6cbb927ea`。arm64 native/Flutter Release 构建通过，ZIP 内 `libmpv.so` 校验通过；mpv diff-check 和 libplacebo 目标文件 diff-check 通过（libplacebo 其他既有 `spirv.c` 空白错误不在本轮范围）。

APK `/tmp/media-kit-p5-packed10-8335-arm64.apk` SHA-256 `544e574b5e8310a20e3e123b3e92241bc2e923a0037247c8f9bd87cae73c9ea7`；JAR `c87374c412ab5eacdef8afe038e6fada5da6ca3b7352fdbb866215e6baad0331`；libmpv `8f5330b9767a5417d76312b9912575e38e84674bbeb4f27617024a0349668814`。原始日志依次 `/tmp/media-kit-p5-packed10-8335-run1-logcat.txt` SHA-256 `8e9b87a52873f1e3602d90742df36ea5632d15a94b8a120196939cf30dc63337`、`/tmp/media-kit-p5-packed10-8335-r32f-run-logcat.txt` SHA-256 `99ef3b96a5e387736da8309426ac11f08e4b55ff041586513415f096d073c459`、`/tmp/media-kit-p5-packed10-8335-run2-logcat.txt` SHA-256 `cb26e0bd92f8bd31443c1d0da4ad44159442cebcc516172cad9d7f03d551b580`。首轮截屏 `/tmp/media-kit-p5-packed10-8335-screen.png`。后续先做同 PTS 原始分量/reshape 数值对照与可见颜色、流畅验收，再验证 PQ/HDR 显示出口；不能由 Texture SDR 的优良掉帧数推断 HDR 已激活。
