# P5 满码图案 `code_scale=0/1` 真机对照（2026-09-25）

目的：区分现有GPU prepass的`1020/1023`校正导致的高端码值截断，与关闭该校正后是否可在RGB10_A2中间纹理保留1020和1023。使用相同8377隔离APK（SHA`73a41e8d3685acb12305147c58d9111b6cdb10a22fa80ed38255293e2f2168a4`）、同一256×144无损P5图案（SHA`74c2cfb6b28095c4bb3b95a57507de699bb8141d62feaedbcb20b964d51a0a98`）、PTS10.000/原第0帧。`p5_raw_yuv=1`、`p5_raw_packed10=1`、`p5_raw_full_dump=1`、`p5_raw_chroma_left_probe=0`、`p5_rpu_probe=2`固定，仅将`p5_raw_code_scale`从既有8377的1改为0；不是生产路径默认设置。输入参考为包内编码前`reference/layer1/p5.npz`，SHA`8d7ab503f92a4715d1dbe1b6f3442ac8c24dc54af1aa92589e05d1f54092bd79`。

本轮日志`artifacts/android-p5-leftfixture-8377-scale0-keylog.txt`确认P5样本身份、PTS10、256×144、crop/buffer完整、147,456字节写入及GL error0。本轮原始读回`artifacts/android-p5-leftfixture-8377-scale0.bin` SHA`bb9c3ff7189d1a37ae9655ac096bb2f6ce47ef8a2617be4c4231eada37d1b7ae`；既有scale1对照为`artifacts/android-p5-leftfixture-8377-raw-off.bin` SHA`05e54caa35747f0db1e99df6226b75bd49faccd159b594851c0b978cb4a7cebc`。比较机器结果`artifacts/android-p5-leftfixture-8377-scale0-compare.json`。

| 原始Y码值 | 样本数 | scale0的RGB10_A2 Y码值 | scale1的RGB10_A2 Y码值 |
| ---: | ---: | ---: | ---: |
| 1020 | 144 | 1023 | 1020 |
| 1023 | 1,440 | 1023 | 1020 |

完整Y/Cb/Cr在scale0均**逐样本匹配**`round(min(source_code,1020)×1023/1020)`模型（各0差）。这证明在当前`GL_EXT_YUV_target`→RGB10_A2可观察链路中，1020与1023合并：去掉校正只把两者一同推到1023，不能恢复区分；校正则把两者一同映到1020。它**尚不能定位合并发生在厂商raw sampler、外部纹理取样的归一化，还是RGB10_A2写入/钳位**。下一步若要验证是否能保留>1020，需同一AImage直接写入可表示>1的float纹理并读回raw值，再与RGB10_A2对照；仅换缩放常数不够。

这项极端范围问题在本机固定4K50 P5原片软件解码全片各分量最大≤902，故不解释该素材第500帧的局部热点或当前卡顿，但仍影响通用P5正确性。实验后强停应用，恢复原片SHA`328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`、旧读回文件原SHA、10369基线APK，六项本轮诊断属性均为0，无应用进程。
