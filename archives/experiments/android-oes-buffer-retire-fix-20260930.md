# OES 路径缓冲生命周期保护修复：Adreno 512 撕裂/绿色色块（2026-09-30）

## 背景

Mi Note 3（jason，骁龙 660/Adreno 512，LineageOS Android 15）HDR10 4K30 SDR 播放轮（前一日 77725564 记录）中用户肉眼观察到：开场数个场景画面抖动、绿色横条色块、左下→右上斜线撕裂，中后段基本正常、偶发绿色色块。定时截图与像素扫描均未捕捉（瞬态）；源码诊断定位：`mapper_unmap` 对非 P5 内容（标准 OES 导入）立即 `DestroyImageKHR`+`AImage_delete` 归还 buffer，而 direct（P5）路径的 retire+fence 持有机制不覆盖 OES——GL 异步采样可能与 codec 重写同一 buffer 竞争（Adreno 512 无 AHardwareBuffer 隐式同步），半写数据=斜线撕裂、未初始化=绿色（NV12 全零）。抖动另有解释：开场 29 帧启动收敛丢帧的节奏跳动，非缺陷。

## 修复（mpv fork `5e26cf86`，已推送 Goodwu/mpv media-kit/android）

`video/out/hwdec/hwdec_aimagereader.c` 七处改动（+28/−11）：新增 `buffer_retire` 旗标（仅依赖 GL FenceSync/ClientWaitSync/DeleteSync/Flush 能力，与内容无关），`direct_retire = direct_yuv && buffer_retire`；unmap 的 fence 创建与 retired[] 持有、map 的同帧复用/retire_reap、uninit 的收尾对 OES 路径同样生效；OES 导入分支与 keep-previous（重绘）分支补记 `sample_submitted`；retire 路径纹理重建的 `external_yuv` 与滤波参数随 direct_yuv 取值（此前硬编码 YUV/NEAREST，仅因该路径 P5 专属而未暴露）。P5 专属逻辑（dovi 元数据重标定、相邻帧尾帧回退）不变。

## 构建链（复原 dad30ae2 产品配方）

`_build-arm64` 链接的是 mkp4prefix 旧属性门控 libavcodec（cd1a08，教训见 P5 色彩修复记录）——产品重链必须替换 `/tmp/media-kit-p5-product-ffmpeg-lib/libavcodec.a`（fff3ee7 世代，fc0c525f…）并补 `-lc++_shared`（build.ninja 1229/1230 行提取链接命令）。重链脚本 `/tmp/mk-relink-product.sh`；产物 `libmpv-fixed.so`（NEEDED 含 libc++_shared、含 P5_BUFFER_RETIRE 标记）。JAR：colorfix JAR 为底换 libmpv.so → `/tmp/media-kit-oes-retire-fix-arm64.jar`（SHA `7cb87a5c…`）。APK：HDR10 SDR `06f75246…`、P5 SDR `b75e9b8e…`（均 12632 define 集）。

## 实机验证（Mi Note 3，每轮结束恢复原状态）

- **30 秒 A/B 轮**（连续抓拍 26 张/轮，问题集中 5-20s 窗口）：基线（原 12705 包）vs 修复版同流程。修复版 `P5_BUFFER_RETIRE enabled=1` 生效；同窗口丢帧 45→28；零渲染失败。像素预扫两组 52 张均无 >0.5% 绿色占比命中（瞬态花屏未入镜，与既往一致）。
- **用户真人观感（两次）**：修复版首次播放"好像没看到问题"；复放确认**"画面没有问题了"**——真人验收通过。
- **P5 回归检查**（20 秒短轮）：`P5_SECTION_INIT direct=1` 保持——fff3ee7 avcodec 重链世代正确（无误链 mkp4prefix 的 direct=0 复演）；P5 直通路径 buffer_retire 同样 enabled=1；4K60 丢帧/avsync 增长为该机解码上限已知特征，非回归。
- 图像判定（glm-5.3-flash-free 子代理逐张，70 张：基线 26、修复 26、复放 14+）：**基线组 1 张异常、修复组 0 张**。异常张为 `dense-baseline-d13.png`（画面左侧 0-18% 宽度垂直条状区域边界锐利、偏蓝青色调，判定员确认非撕裂/非绿色但属渲染异常）；修复组与复放组全部正常画面。该结果与用户真人确认（"画面没有问题了"）及基线轮用户现场看到抖动/撕裂相互印证。

## 遗留

- 修复在 mpv fork 主线（`5e26cf86`），产品 JAR 重建周期时纳入（连同 av_log 接管 `6719532`）。
- 华为机（Mali G76，隐式同步）回归未跑——该路径行为由旗标扩展覆盖，理论无差异（buffer_retire 在华为本就随 direct_retire 对 P5 生效；OES 路径新增持有为纯增益），待下轮产品验收顺带覆盖。
- 截图证据：`~/src/media-kit-build/evidence/oes-buffer-retire-20260930/dense-{baseline,fixed,fixed2}-*.png`、日志同目录 `dense-*-device.log`（/tmp 原件已删除，持久副本为权威）。
