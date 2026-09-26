# P5 已知色度边缘：手机映射前 packed10 整帧核对（2026-09-25）

承接 `android-p5-left-pattern-fixture-20260925.md` 的 L3 A/B。输入仍是归档的256×144、13秒、312帧无损P5 `left` 码流 SHA-256 `74c2cfb6b28095c4bb3b95a57507de699bb8141d62feaedbcb20b964d51a0a98`；PTS10.000 对应原24帧图案的第0帧，包内编码前 YUV 存于用户测试包 `reference/layer1/p5.npz`，SHA-256 `8d7ab503f92a4715d1dbe1b6f3442ac8c24dc54af1aa92589e05d1f54092bd79`。该图案已在上一实验验证整个312帧的FFmpeg解码样本与原YUV循环逐字节相同。

隔离 mpv raw mapper 增加默认关闭的 `debug.media_kit.p5_raw_full_dump=1`，仅对小于等于256×144且PTS在`[10.000,10.020)`的packed10路径读一次完整 FBO `GL_RGBA/GL_UNSIGNED_INT_2_10_10_10_REV`，没有在正常播放热路径读回。8377 APK SHA-256 `73a41e8d3685acb12305147c58d9111b6cdb10a22fa80ed38255293e2f2168a4`，签名校验和arm64构建通过，含前轮的默认关闭相位探针。两轮只切换 `p5_raw_chroma_left_probe=0/1`。日志两次均确认 PTS10.000、256×144、147,456字节完整写出、GL error0、AImage crop=`0,0,256,144`、buffer=`256,144`。原始缓冲分别为 `artifacts/android-p5-leftfixture-8377-raw-off.bin` SHA-256 `05e54caa35747f0db1e99df6226b75bd49faccd159b594851c0b978cb4a7cebc` 和 `...raw-on.bin` SHA-256 `bf3d37ce50b0285a1431dc1da5d2c0db24a6a582eae23b5662d3cecbbbedfb20`；它们与8376首次读回各自逐字节相同。累计mpv诊断补丁 `android-p5-rawfull-8377-mpv-cumulative.patch` SHA-256 `18d79d9a43e5425e512c3d0a25bdc01d51fca47cfe34a0954f191566622960fe`，含原有raw/VO诊断，不是产品最小补丁。

`tools/p5_raw_full_compare.py` 解包每像素的 Y/Cb/Cr 10-bit 整数，与**编码前**参考独立比较；完整机器报告为 `artifacts/android-p5-leftfixture-8377-raw-compare.json`。手机raw FBO的行序直接与YUV上原点行序对应，不沿用L3 RGBA16F的上下翻转规则。此图上：

比较器另用临时副本故意改坏首个Y码值1位，自检报`off_mismatch_y_cb_cr=[1,0,0]`、`pass=false`且进程退出1；原始两份缓冲则`pass=true`。该故障注入只验证比较门禁，不等于GPU路径错误注入。

| 判定 | 结果 |
| --- | --- |
| 探针关闭：Y/Cb/Cr 对预期逐样本差异 | 0 / 0 / 0；Cb/Cr 取 `floor(x/2)` |
| 探针开启：Y/Cb/Cr 对预期逐样本差异 | 0 / 0 / 0；Cb/Cr 奇数列取 `ceil(x/2)`，边界 clamp |
| 两轮 Y 差异 / 偶数列 Cb、Cr 差异 | 0 / 0、0 |
| 两轮奇数列 Cb、Cr 差异 | 502 / 504 个位置，均由已知色度边缘造成 |

例如 y=100、x=31：输入左样本 `(Y,Cb,Cr)=(425,463,513)`，探针关闭的raw正是该值；开启后为`(425,589,575)`，即x=32的右邻色度。x=63、95同理。因而上一实验的L3边缘改善可以在**映射前输入**直接追溯到色度取样变化，不能再笼统归因于RPU或色彩矩阵变化。

Y 有一个独立的输入域限制：关闭探针对未缩放编码前YUV的差异有1,440个像素，全部位于x=236–255、y=0–71的码值1023区域，手机raw为1020；其他Y及全部Cb/Cr与原码值相同。当前 `1020/1023` 校正路径在该图上的合同恰为 `min(Y,1020)`，**这不是HEVC规范允许3-code误差的声明**。它可能影响满码高亮，应在产品修正前单独评估；上一轮相位探针残余L3最大差位于 `(4,138)`，该点Y=951且raw与原YUV一致，故不能用1023→1020解释该残差。

本轮证明的是手机当前厂商PRIVATE/OES→packed10预处理行为及探针开关效果。它未提供Dolby授权的L2C或L3 golden，也未验证该探针对4K50吞吐、实际显示HDR、长期流畅。后续须加映射前DV重构/颜色检查点，对齐具体libplacebo policy，再在4K50上测试额外色度采样成本。实验后原P5设备文件SHA恢复为`328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`、应用回到10369、12项诊断属性均0且进程强停。
