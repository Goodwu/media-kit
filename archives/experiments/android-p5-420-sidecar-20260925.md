# P5 4:2:0 双平面诊断（2026-09-25）

目标是在同一 P5 4K50、PTS10.000 输入上保留半分辨率色度平面，让 libplacebo 按 `left` 色度位置重构，检验现有全分辨率 packed10 预采样是否造成 L2C 局部误差。手机为 LYA-AL00；对照是主机 FFmpeg 软件解码加同版 libplacebo 7.365.0 的 `PL_HOOK_RGB` RGBA16F，属于**工程参考**，不是 Dolby 权威输出。两端同帧 RPU size206/hash `907c8b42`，手机本轮 4 个 UV 取样点与软件基础层对应样本一致，GL error 0。手机导出 3840×2160×8 字节完整 L2C 缓冲。

诊断实现新增 `IMGFMT_YUV420_PACK10`：全尺寸 RGB10_A2 纹理承载 Y，半尺寸 RGB10_A2 纹理的 G/B 承载 Cb/Cr，后者由全尺寸纹理最近邻 blit 得到。第一包 8380 漏设 `vo_gpu_next` 的分量映射，libplacebo 把半尺寸纹理 R/G 当作 Cb/Cr，L2C 几乎全帧失配（>0.01 的 RGB 像素 8,291,725）；这是**诊断适配代码错误**，不代表厂商解码错误。8381 显式改为 `{-1,1,2}`，运行日志确认两平面、`chroma_location=2`、RPU 身份和完整回读。

| 手机路径 | RGB P99 绝对误差 | 任一 RGB >0.01 像素 |
| --- | --- | ---: |
| 8378 原 packed10，相位关 | .008911/.003662/.010498 | 120,342 |
| 8378 原 packed10，奇数列右邻相位探针开 | .000610/.000244/.000977 | 12,922 |
| 8380 双平面，错误映射 | .326171/.070190/.051392 | 8,291,725 |
| 8381 双平面，映射修正 | .008057/.003174/.009277 | 98,529 |
| 8384 双平面，映射修正且 `left` 位置 | .006348/.002441/.007080 | 54,335 |

8381 已恢复到可比较量级，但明显差于奇数列相位探针；RGB 最大残差分别 .12036/.22107/.36841。故“把现有 packed10 结果简单最近邻缩成 4:2:0，再交给 libplacebo”不能作为产品修正。半尺寸 blit 的取样位置、Y/UV 各自纹理坐标、libplacebo 色度滤波与码流 `left` 语义仍须分别核对。此前 7×7 原始采样在新增异常中心 `(1985,1002)`，相位关/开 CbCr 分别为 `(468,441)`/`(467,432)`，与软件 BL 左/右样本各一致；相位探针固定选右邻会修正大多数奇数列，也会在局部过补偿。除 `(2216,1047)` Y=639 对软件 650 外，四个 7×7 ROI 中 Y/Cb/Cr 全部符合对应确定性模型；单个 Y 差异尚未归因。

后续查到一项确定的元数据转接错误：原 MP4/HEVC 的 `chroma_location=left`，但上游 PRIVATE/OES 图像在 mpv 中先被视为非抽样格式，`mp_image_params_guess()`将其色度位置重置为 `PL_CHROMA_CENTER=2`。8381 新建的 420 sidecar 直接继承这个值，日志证实传入 libplacebo 的确为 2。8384 在**sidecar 边界**显式恢复 `PL_CHROMA_LEFT=1`，同一 PTS10.000 的两平面与 RGBA16F 导出成功；本轮未单独记录该帧 RPU hash，但确认正确 RPU 链接且 DV 输入门禁通过。任一 RGB >.01 像素降为 54,335，P99亦下降，证明误传 center 是部分误差来源。仍远差于8378的12,922；不能把 center→left 当完整修复。8384 的最大RGB残差 .09692/.21936/.33203，>0.01 分布偶/奇列11,982/42,353，提示仍有取样或滤波差异。

8382/8383 首次重链接误用了不附着当前逐帧 RPU 的 FFmpeg 静态库；应用虽然开始解码，但 mapper 从首帧起报 `P5 raw YUV requested without first-frame DOVI metadata`、无法形成有效L2C，因而**不纳入上表**。8384 重链接正确的 `/tmp/media-kit-ffmpeg-p5-stream-2215/_build-arm64/libavcodec/libavcodec.a` 后同帧钩子与映射恢复。前缀静态库测试后恢复原 SHA `36a68423...`。

完整比较在 `artifacts/android-p5-l2c-838{0,1}-sidecar-host-compare.json`，累积隔离源码补丁为 `android-p5-420-sidecar-8381-mpv-cumulative.patch`（SHA-256 `9a45fee2b33d9fc009de59fd404efd0cddfcd1998fb3ca6aa5db26d9b297bc42`）。8381 APK `/tmp/media-kit-p5-420-sidecar2-8381.apk` SHA-256 `8f4c315eb08373728937342f31217e82b96fa3248a0515035f99f7699d4a955b`；L2C 原始缓冲 `/tmp/media-kit-p5-l2c-sidecar2-8381.rgba16f` SHA-256 `1bd22afd8c2b47a085d6e7820a935e13eaf0fcdcb3f43c7b16818778e29d6201`；完整 logcat `/tmp/media-kit-p5-420-sidecar2-8381-logcat.txt` SHA-256 `478e13c388042a404b0fcc0df61990ead39dd6e0a77bb114bc1022327470ac01`。累积补丁 `git diff --check` 通过；这不是产品补丁，也未做性能或屏幕观感验收。

测试后手机恢复基线 10369，双平面及 L2C 等诊断属性回读为 0，应用无进程。下一步先在离线参考上核对 libplacebo 对 `left` 420 的实际坐标及滤波，再调整预采样，避免继续凭观感选择采样邻居；同时单独测试这台 Android 10 设备有无可用的公开 10-bit 解码平面，不能把通用格式可请求等同于本机 P5 10-bit 硬解可用。

8384 比较数据为 `artifacts/android-p5-l2c-8384-sidecar-left-host-compare.json`，累计隔离补丁 `android-p5-420-sidecar-8384-mpv-cumulative.patch` SHA-256 `5e4906ac715aa188bc773bfba1649b1edc134b718847bf6d80881752f6826ada`。APK `/tmp/media-kit-p5-420-left-rpu-8384.apk` SHA-256 `8c855d04550141f262b3fb15dda5517f7252ec3e9e7b6eb8aee66a96bf7cf751`；L2C 缓冲 `/tmp/media-kit-p5-l2c-sidecar-left-8384.rgba16f` SHA-256 `8750dc1ef59efc83cb6e6f196a49e7384c2e1bf71c764e06d59a8d5daf8fd49f`；日志 `/tmp/media-kit-p5-420-left-rpu-8384-logcat.txt` SHA-256 `f29ad8ed83d7eafde716ff1683eb794eb3799064b2c589652ae1dbd16d0ee94c`。此轮仍是隔离诊断，没有性能或真人显示验收。

## 8386 GPU 中间纹理 Y/Cb/Cr 整帧核对

为区别“sidecar 生成已错”和“正确的 420 平面在 libplacebo 上采样不同”，8386 在 PTS10.000、crop/buffer均3840×2160、GL error0 时分别读回全尺寸 packed Y（33,177,600字节）和半尺寸 packed UV（8,294,400字节）。与同一码流 FFmpeg 软件第500帧`yuv420p10le`逐整数样本比较。**两份 GL 读回按文件行顺序直接对软件 YUV，无垂直翻转**；翻转后Y失配8,254,593点，排除了这份GPU中间纹理的上下颠倒解释。比较脚本`tools/p5_sidecar_yuv_compare.py`、结果`artifacts/android-p5-raw-sidecar-8386-vs-sw-n500.json`；脚本2×2人工相等/单码值破坏自检通过。PRIVATE/OES缓冲本身仍不可直接读取，这不是第一层硬解原生输出检查点。

| 平面 | 不同样本/总样本 | 平均绝对码值差 | 最大绝对码值差 | 差异边界框 x0,y0,x1,y1 |
| --- | ---: | ---: | ---: | --- |
| Y | 24,348/8,294,400 | .01880 | 93 | 54,765,3839,1247 |
| Cb | 6,017/2,073,600 | .01012 | 18 | 36,391,1919,623 |
| Cr | 6,313/2,073,600 | .03126 | 54 | 27,391,1919,623 |

这些是**GPU 中间纹理中实际存在的局部码值差异**，不是整帧色彩映射才出现的误差；然而不能仅据 PRIVATE/OES→GL 读回断言是硬件 HEVC 解码错误，也可能是外部纹理取样/转换。多数中间纹理样本精确一致。UV 在 8385、8386 两次独立运行逐字节同 SHA `21fe4dc1...`，Y 在8386重复运行逐字节同 SHA `b04220ef...`，故此差异可复现。与软件498–502五帧比较，第500帧分别仅Y24,348、Cb6,017、Cr6,313点失配；相邻499帧Y5,584,910点、501帧Y7,857,695点失配，排除整帧错配一帧，见`artifacts/android-p5-raw-sidecar-8386-adjacent-frame-compare.json`。软件本轮第500帧与既有`/tmp/media-kit-p5-sw-n500.yuv`逐字节一致。常数±1/±2像素平移也不能明显降低Y差异区域的平均误差。L2C异常与中间纹理差异的边界框大量重叠，但逐像素不能一一对应，不能把全部54,335个L2C超阈像素归因于这12–24k个码值差异。

8386 APK `/tmp/media-kit-p5-420-yuvdump-8386.apk` SHA-256 `81864ba446155fbf41c8386c89949e7c69f2a3e356c5f0318d7c7a47bec8311e`；Y读回`/tmp/media-kit-p5-raw-420-y-8386.bin` SHA `b04220ef51629371d77e5d5eccd9ca773ae063e462d1c3499fcb5a37f048e81f`，UV读回`/tmp/media-kit-p5-raw-420-uv-8386.bin` SHA `21fe4dc1afe8bcfcfaf9b1193e4e8d98278d4e7dca7b6d1e81b95da3d8918bd1`，软件第500帧 SHA `8a41d06c8b14a313864d04907bf3cca667d6f732fa2b2db281d105c3b833fe44`，完整日志`/tmp/media-kit-p5-420-yuvdump-8386-logcat.txt` SHA `01d391f618b88b0041a7ba391cf62a4d58fb83a76d5f2a6710081b830058aea3`。隔离mpv累计补丁`android-p5-420-sidecar-8386-mpv-cumulative.patch` SHA `ad3587523d385f81eeec3484823bc053a621d3b51dc6c7a55309f385e3172f29`，`git diff --check`通过。恢复手机10369、相关诊断属性0、无应用进程；重复软件五帧临时文件及无效中间APK已删除。下一步先查这些局部差异是否来自 PRIVATE/OES 外部取样（例如直接对比另一种可观测输出），再调整sidecar色度滤波。单一软件实现仍属工程参考，不能标为官方HEVC一致性标准。

## 独立解码交叉检查与误差形态

在 macOS 同一 P5 压缩文件上，额外显式使用 FFmpeg `-hwaccel videotoolbox -hwaccel_output_format videotoolbox_vld`，在第500帧 `select` 后 `hwdownload,format=p010le` 并导出 `yuv420p10le`。debug 日志确认 decoder 选择 `videotoolbox_vld`，滤镜入口也确为此硬件像素格式；输出 `/tmp/media-kit-p5-videotoolbox-explicit-n500.yuv` SHA-256 `8a41d06c8b14a313864d04907bf3cca667d6f732fa2b2db281d105c3b833fe44`，与纯软件第500帧 `cmp` 逐字节一致。debug 日志 `/tmp/media-kit-p5-videotoolbox-explicit-n500-debug.log` SHA `8bd91778bf44e96e2e8fc1eb95157289ca5ac35da012eacfff4772d323b1207e`。VideoToolbox 是独立的硬件重构路径，但此实验仍经 FFmpeg 的同一码流解析和 P010→planar 转换；它是强交叉参考，不是 Dolby/HEVC 官方一致性资产。

手机 Y 的24,348个不同样本中23,813个高于软件参考，535个低于；Cb差异以低于参考为主（5,237/6,017），Cr以高于参考为主（6,022/6,313）。Y差异样本的来源码值中位137，主要集中在暗部和运动区域；约70%手机 Y 值落在软件参考同位置周围3×3的最小/最大值内，但固定±1/±2像素平移未能明显降低差异。此形态支持继续检查 PRIVATE/OES 取样或厂商输出处理，却不足以证明某一个具体操作（插值、去噪、硬解重构）是原因。尤其不能把整张 GPU 中间纹理当成直接可读的硬解L1。下一步最好在同机为同一码流寻找第二种可观测解码输出；若只能拿到8-bit YUV，须明确量化/转换合同，不能把它直接当10-bit bit-exact标准。
