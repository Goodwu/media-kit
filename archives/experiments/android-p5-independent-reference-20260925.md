# P5 独立参考资产核实（2026-09-25）

## 结论与比较边界

### 两个镜头的低梯度残差复核

另用 `python3 archives/experiments/tools/p5_gradient_residual.py <VDM-TIFF> <P5-P3PQ-PNG>` 对已有第240、500帧做同尺寸 RGB16 对照；每8像素采样1点，按母版该点左右/上下相邻像素的最大通道差分分为梯度分位。第240帧129600个采样点整体 MAE `(1389,646,616)`，最低25%梯度点 `(1085,435,447)`、最高10% `(1884,934,873)`；第500帧整体 `(2754,2209,1413)`，最低25% `(2314,1879,1085)`、最高10% `(3723,2771,1957)`，均以65535为满量程。边缘越强误差越大，但低梯度区域也保留明显残差；连同前述双图低通对照，**单纯边缘配准/色度采样不能解释全部差值**。低梯度分位不是严格平坦色块，采样统计也不是全帧 MAE 或感知色差；母版图像同版身份、编码损失和两端色彩域仍未独立证明，故仍不能把该残差判为 P5 解码错误。该分析只用主机既有资产，不涉及手机颜色输出。

用户提供的“Dolby 编码样本 + Netflix 开放母版 + Dolby CM Offline”方向成立，但有两个不同的参考域：Netflix VDM TIFF 是 **mastering-domain** 图像，可在完成帧对齐、色域/PQ/精度归一后检查编码 P5 的解码与 RPU reshape；Dolby CM Offline 在固定 Target Display/CM 版本下生成的是 **Dolby content mapping** 输出，可检查 Dolby 意图的目标显示效果。后者不是现有 mpv/libplacebo 映射的逐像素真值：当前 libplacebo `pl_map_dovi_metadata` 消费 RPU reshape/颜色矩阵，`pl_map_avdovi_metadata` 只额外读取 Level 1 `max_pq/avg_pq`，没有读取 Level 2 目标 trim；Netflix XML 则明确含 Target ID 1 的逐 shot Level 2 trim。故两边即便输入帧完全一致，也可能因映射算法/trim 使用而系统性不同。若产品要求与 Dolby CM 输出数值接近，需另行实现并验证相应映射，不能仅调 clip/saturation 宣称已复现 Dolby CM。

Dolby 官方[Target Display 表](https://professionalsupport.dolby.com/s/article/Mastering-and-Target-Displays)确认 ID 1 为 100 nit BT.709/BT.1886/full，ID 24/27/48 分别为 300/600/1000 nit P3-D65/PQ，ID 49 为 1000 nit BT.2020/PQ；[CM Offline 说明](https://professionalsupport.dolby.com/s/dolby-vision-professional-tools)确认其输入 HDR master + DV metadata、输出指定 target 的图像序列或视频。当前设备没有找到 `cm_offline` 可执行程序；本轮未生成 Dolby golden output，不得用 Netflix TIFF 或主机 mpv 截图冒充最终 SDR/PQ 真值。

## 已核实的公开资产

### 官方 P5 RPU 与 Netflix XML 全片关联

用 `dovi_tool export -i /tmp/media-kit-dolby-official-p5-2160p-rpu.bin -d all=/tmp/media-kit-official-p5-rpu-all.json` 导出逐帧 RPU，再运行 `python3 archives/experiments/tools/p5_xml_rpu_lineage.py --xml /tmp/media-kit-sollevante-dv29.xml --rpu-json /tmp/media-kit-official-p5-rpu-all.json`。脚本展开 XML 的 72 个 shot 和 338 个逐帧覆盖，比较全部 6314 帧：RPU 的 72 个 `scene_refresh_flag` 位置与 XML `Record/In` 列表完全相同；Level 1 `avg_pq`、`max_pq` 均为 6314/6314 精确匹配；Level 2 trim 的启用状态亦为 6314/6314 匹配，其中启用 4702 帧、默认 1612 帧，RPU Level 2 `target_max_pq=2081` 覆盖全部帧，脚本报告零不匹配。

Level 1 比较使用本素材上观察到的量化关系 `avg=max(819,round(XML_avg*4095))`、`max=max(2081,round(XML_max*4095))`；这些下限是**此资产的经验对应**，并未证明通用 Dolby 规范。Level 2 则依照本地 `dovi_tool/dolby_vision/src/xml/parser.rs` 的 `parse_level2_trim` 公式，把 XML 的 lift/gain/gamma/chroma/saturation/mid-contrast 转为 RPU 的六个代码值，**六项合计逐帧 6314/6314 完全匹配**。公式取自另一套开源解析器，且输出与码流吻合，但不把解析器自身当作 Dolby 官方规范。全片结果强烈支持两份文件的 DV 元数据来自同一制作链，比仅比较两帧或镜头起点更有力；它仍不证明 MP4 的压缩图像与 Netflix VDM TIFF 属同一版母版，也不能证明 mpv/libplacebo 或手机最终显示颜色正确。下一步仍应追查图像版本/编码来源，并在固定目标显示条件下取得独立渲染参考。

### 同仓库 P5 与 P8.1 RPU 的边界对照

对已核 SHA 的官方 4K P8.1 MP4 用 `ffmpeg -c copy -bsf:v hevc_mp4toannexb` 管道送入 `dovi_tool extract-rpu`，得到 `/tmp/media-kit-dolby-official-p81-2160p-rpu.bin`，SHA-256 `cbb65d47f25ae957eb7a810cd89b9bb9380266b7bd039d5158c56da1ff86b992`；导出逐帧 JSON 后与 P5 的 6314 帧对齐比较。两者每帧 `scene_refresh_flag`、整个 `cmv29_metadata`（包括 Level 1/2）均完全相同；但 `rpu_data_mapping`、YCC→RGB 与 RGB→LMS 矩阵每帧均不同，profile 分别为 5/8。P8.1 和 P5 的调色统计/trim 共用同一套元数据，但各自的底层信号与重塑定义不同；因此 P8.1 即使同片名、同镜头、同 trim，也不是 P5 的逐像素真值，P8.1 关闭 DV 的截图不能直接定量界定 P5 的 HEVC 压缩误差。此结果进一步缩小“元数据是否同源”的疑问，**没有解决 MP4 图像与 Netflix TIFF 是否同版**。

- [Netflix Open Content](https://opencontent.netflix.com/) 的 Sol Levante 目录同时列出 Dolby Vision PQ/P3 IMF、16-bit P3/PQ VDM + DV 2.9 XML、HDR10 1000 nit 和 SDR 资产。S3 原始清单显示 `SolLevante/vdm/sollevante_lp_vdm_16b_p3d65_pq_20200218_3840x2160.zip` 为 **155,127,367,741 字节**，`SolLevante/sdr/SolLevante_SDR_UHD_24fps.mov` 为 **16,136,968,701 字节**；当前本机空余约 13 GiB，未下载完整图像序列或 SDR 视频。S3 支持 HTTP Range，可直接提取指定 ZIP 成员。
- 已下载 XML `/tmp/media-kit-sollevante-dv29.xml`，203,263 字节，SHA-256 `ed782c213d158dad8204d3a4bde8d72e5956649696bb39ae6d9a0162d58c4ceb`。XML 为 `DolbyLabsMDF version=2.0.5`、24/1 fps，`AlgorithmVersions=2,1`，母版显示 ID 20（1000 nit P3-D65/PQ），唯一 Target Display 为 ID 1（100 nit BT.709/BT.1886），72 个连续 shot 的 Record 覆盖 `[0,6314)` 共 6314 帧；各 shot 的 Level 2 trim 目标亦均为 ID 1。
- 已核验的 Dolby Laboratories [Sol Levante P5 MP4](https://github.com/DolbyLaboratories/dolby-vision-contents) 为 1080p/24fps、`dv_profile=5`、`rpu_present_flag=1`、`nb_frames=6314`、duration 263.083333 秒。帧数和时间轴与 XML 相符，**但不能仅凭此证明它与该 XML/VDM 为完全同版本母版或 RPU**；后续须核帧内容/起点/metadata。
- 用 HTTP Range 读取 VDM ZIP 中央目录，显示 2 个目录项 + TIFF `0000000` 到 `0006312`，合计 **6313 张图像**，比 XML/编码 MP4 少最后一帧。图像为 3840×2160、RGB 16-bit、每帧解压大小 49,766,656 字节。已单独提取 `0000240.tiff` 到 `/tmp/media-kit-sollevante-vdm-frame-0240.tiff`，ZIP CRC 校验通过，SHA-256 `0c2c5524252776df43ebc8e7da101ea9260e4a9c0d631b7992b3270fcd58eacd`；Pillow 读得 RGB、16/16/16 bit、3840×2160。它是可用的**独立母版帧**，尚未与编码 P5 输出做同域像素比较。
- Dolby [Browser Test Kit](https://ott.dolby.com/browser_test_kit/help_files/topics/r_test_signals_all.html) 官方文档确认有 P5/P8.1/P8.4 的 MP4、24/25/30/50/120 fps、多个分辨率；它增加码流覆盖，不附逐帧 golden 输出。

## 可执行的下一步

1. 先用帧 240 VDM TIFF 与官方 P5 MP4 的相同内容帧核对起点、画面几何、源 P3/PQ 解释；另抽少量跨 shot 帧确认是否恒定对齐，解释末帧缺失。编码有损、1080p 对 4K，须先统一分辨率、采样和比较域，再以误差分布/结构指标比较，不能要求 bit-exact。
2. 若可取得 Dolby CM Offline，记录工具版本、实际 CM 模式与输出格式，以 XML + 对应 VDM 帧生成 Target ID 1 输出；PQ 分支需在 XML 未含对应 trim 的条件下说明插值/默认处理，不能凭 target ID 选项就假设有专属创作 trim。
3. 把“mastering-domain 恢复”和“目标显示映射”分成两道门禁。前者可用当前公开单帧 VDM 继续推进；后者需 Dolby 工具输出或同等独立结果。现有 mpv/libplacebo P5 路径未应用 XML Level 2 trim，若仅求通用 tone mapping，应明确其与 Dolby CM 的差异，避免用错误的逐像素容差判定。

另对隔离 mpv 候选的作用域做了编译级收敛：在 `/tmp/media-kit-mpv-clean-2194` 中将 demux 声明的 `dv_profile` 从 `vd_lavc` 附到 `mp_image_params`，经 AVFrame opaque 参数保留，并将 Android SDR clip 条件从“有 RPU”收紧为“`dv_profile == 5` 且有 RPU”。arm64 `libmpv.so` 使用 NDK 27 编译链接成功；尚未打包/运行验证 profile 字段及非 P5 路径，因此仍是隔离候选，不能视为产品代码或已通过回归。

## 第 240 帧首次母版域对照（2026-09-25）

用主机 mpv 0.41/libplacebo 7.360.1 对 Dolby 官方 1080p P5 MP4 **从 0 顺序解码**，避免直接 seek 时的 HEVC/RPU 警告。`--vo=gpu-next --gpu-context=macvk --video-sync=desync --untimed --target-prim=display-p3 --target-trc=pq --target-peak=1000 --tone-mapping=clip --gamut-mapping-mode=clip --hdr-compute-peak=no --dither=no`；Lua 观察 `time-pos` 到 10.000000 时暂停并执行 `screenshot-to-file ... window`。IPC 回读 `time-pos=10.000000`、源为 Dolby Vision/BT.2020/PQ、目标为 1920×1080 RGB/display-P3/PQ/1000 nit `bgr10a2`，累计播放器掉帧0。截图 `/tmp/media-kit-sollevante-p5-p3pq-window-pts1000.png` 为 1920×1080、16-bit RGBA PNG，P3-D65 色度块，SHA-256 `0a940a60a3ff87d9df9d87413dfb0f4148c900d1a4ca9528d011203c3f4e0219`。mpv 已正常退出。该 `window` 截图仍是一次额外的 libplacebo 渲染，不等同交换链/光学显示结果。

将 Netflix VDM TIFF `0000240` 以 FFmpeg bilinear 在 **PQ 编码值域** 从 3840×2160 缩到 1920×1080，分别读 RGB48 与 PNG RGBA64 原始代码值后比较：RGB 平均绝对误差 `(1454.8,678.3,661.2)` /65535，平均有符号差 `(62.3,72.7,68.4)`；P95 `(4020,1934,1917)`，最大 `(24665,8391,8092)`。隔4像素抽样的逐通道 Pearson 相关为 `(0.9565,0.9939,0.9924)`；绿色通道在 ±4 像素平移搜索中零位移最佳。邻近、bicubic、Lanczos 缩放均未使误差消失。该结果支持两图为**同一时间附近的同一画面且大体同域**，并首次给出独立母版的定量对照；红色仍有约 2.2% 满量程 MAE，不能称像素或颜色正确性已通过。待排查 1080p 编码前缩放/色度采样、16-bit TIFF 与截图量化、master 版本/帧偏移、libplacebo reshape/颜色转换及截图路径；也需跨 shot 多帧复核。不能把此差值直接归因于手机硬解或 Android GLES，因为本轮两张图都来自主机/公开母版。

### 相邻帧与缩放域排除

同一张母版第240帧直接 2×2 平均：PQ 代码值域 MAE `(1473,750,677)`，先用 ST 2084 EOTF 转线性光、2×2 平均再逆变换得到 `(1468,751,677)` /65535；两者对红色偏差影响不足 1%，简单“应在线性光缩放”不是主因。为检验一帧时间偏移，另通过 S3 HTTP Range 分块获取 VDM TIFF `0000239`、`0000241`，均经 ZIP 解压长度 49,766,656 字节和 CRC 校验；SHA-256 分别 `9dadfce577365fccbb8b1ca1be5aeab533df7edbc83ce7d0d0bd4eaff88879e3`、`af6b8086ab2ac23d9061859193490ef44d0ca2e6ed0c68bc26bf0b6a7933a289`。先前一次直接并行提取因 TLS EOF 留下**不完整文件**，已由分块重取覆盖并校验；失败文件不作证据，下载过程生成的重复压缩临时文件已清理。

同一 P5 PTS10.000 截图与三张母版分别作相同 PQ 代码域 bilinear 缩放比较，RGB MAE 为：帧239 `(2405,2030,1680)`、帧240 `(1455,678,661)`、帧241 `(2389,1965,1661)` /65535；240 三通道均明显最佳。因此在这个时间点，**简单 ±1 帧偏移不能解释剩余红色差异**。后续优先核编码前 4K→1080p 处理与色度采样、两个发布版本的母版/编码参数、Dolby RPU reshape 输出和主机截图的额外渲染量化；跨场景多帧仍需验证，不能从一帧推断全片。

### Dolby 官方 4K P5 去缩放对照

Dolby Laboratories 同仓库 3840×2160/24fps P5 MP4 已从 LFS 下载到 `/tmp/media-kit-dolby-official-p5-2160p.mp4`，289,758,635 字节，SHA-256 `dacfd04518accd6367530b650dfeea429227df2be171bd99b4bdad36d31bbf9f` 与 LFS 指针一致；ffprobe 显示 HEVC Main10/yuv420p10、`dvhe`、DV profile 5/level 6、RPU 存在、6314帧、263.083333秒，视频平均约8.81 Mbit/s。它和 Netflix VDM 母版同为 3840×2160，消除了本次**比较时**的 4K→1080p 缩放；仍不能排除该 MP4 编码前本身的处理或有损压缩。

沿用顺序解码和 Lua `time-pos=10.000000` 暂停，主机 mpv 输出目标经 IPC 核实为 3840×2160 RGB/display-P3/PQ/1000 nit、`bgr10a2`，播放器掉帧0；`window` 截图 `/tmp/media-kit-sollevante-p5-4k-p3pq-window-pts1000.png` 为3840×2160/16-bit RGBA PNG，SHA-256 `11267d3b050b763f33458d7936f334dce0228c9fb911f662712f365d7dda5738`。与 Netflix 第240帧 VDM TIFF 直接逐像素比较（**不缩放**），RGB MAE `(1378.1,632.9,623.1)` /65535、平均有符号差 `(122.5,77.7,45.1)`、P95 `(3745,1776,1716)`；隔8像素相关 `(0.9622,0.9948,0.9934)`，绿色±2像素平移仍零位移最佳。比1080p轮 `(1455,678,661)` 略好，但红色仍约2.1%满量程MAE，**4K→1080p比较缩放不是红色残差主因**。主机 mpv 已正常退出。下一步可用同内容 P8.1/HDR10 兼容底层或独立解码链与母版比较，以估计HEVC压缩/色度贡献，再检查 P5 RPU reshape 和后续 P3/PQ 渲染；这些对照亦需先核各版本是否共用母版，不以“同片名”替代身份检查。

### 同一 P8.1 文件的 DV 开关对照

从 Dolby Laboratories 同仓库取得 3840×2160/24fps P8.1 MP4 `/tmp/media-kit-dolby-official-p81-2160p.mp4`，285,352,109 字节，SHA-256 `d054a818de665bc3737a4c5b1662262929ed777b102ea3539afb050fcb4d2cae` 与 Git LFS 指针一致；ffprobe 为 HEVC Main10、BT.2020nc/PQ、DV profile 8/RPU、6314 帧。主机 mpv 从 0 顺序解码到 PTS10.000，保持 3840×2160/P3-D65/PQ/1000nit/clip、窗口截图条件不变，仅用 `--vf=format:dolbyvision=no` 切换 DV 处理。IPC 核实关闭轮输出 `colormatrix=bt.2020-ncl`，开启轮为 `dolbyvision`，两轮播放器掉帧均为 0。关闭/开启截图 SHA-256 分别为 `35ebdca71d16e3917ac98383e34d8335a9a9664bea7af9dc950688aeaeba4f27`、`0fd6fe558aee9a78c45c932bfc5a666bb8d39878545ff48596fbe6568eab650e`。

与同尺寸 Netflix VDM 第240帧 RGB16 代码值直接比较：P8.1 关闭 DV 的 MAE `(1316.8,534.3,631.8)` /65535、偏差 `(-293.4,-10.6,-42.1)`；开启 DV 的 MAE `(1296.9,534.1,633.8)`、偏差 `(-156.5,-15.0,57.1)`。同一 P8.1 文件开启减关闭的 MAE `(138.3,7.8,99.2)`、偏差 `(136.9,-4.4,99.2)`，明显小于两轮对 TIFF 的残差。P5 对同 TIFF 的 MAE `(1378.1,632.9,623.1)`，但 P5 与 P8.1 开启轮彼此的 MAE `(1497.4,544.2,624.7)`，因此 P8.1 不能充当 P5 的逐像素参考或纯粹 HEVC 压缩基线；文件名中的 `mapDynamic1000`、可能不同的调色/编码链和母版身份都须核实。当前只说明单帧上切换 P8.1 的 DV 处理无法消除大部分母版残差，**不能据此判定 P5 RPU 或最终颜色正确**。下一步优先核 P5 与 VDM 是否同一制作版本及截图颜色路径，跨 shot 抽帧复核。

### 色彩标记与低频残差复核

`ffprobe` 对 Netflix VDM TIFF 只报告 `rgb48le`，未读到色域/传递标记；其 P3-D65/PQ 含义来自 Netflix 发布的资产名与说明。mpv PNG 报告 `rgba64be`、`smpte432` (P3-D65)、`smpte2084` (PQ)。两者文件内的标记证据不对等，后续需继续核实发布说明和截图读回路径，不能只凭扩展名认为完全同域。

再以 `exiftool`/TIFF IFD 复核第240帧：文件仅标注 3840×2160、RGB 三通道各16位、无压缩和通常的条带布局，没有 ICC profile、色度坐标或 PQ 传递标签。Pillow 11 在本机 `np.asarray(Image.open(...))` 对这张 TIFF 返回 `uint8`，会静默损失精度；既有比较使用 FFmpeg `rgb48le` 原始读出，另与 TIFF 条带的 little-endian 16位原始采样核对首像素一致。第240/500帧的 FFmpeg 读出均为 3840×2160×3 `uint16`。因此独立参考的文件内色彩标记仍是证据缺口，但当前千级 MAE 并非 Pillow 8位降精度造成。公开的 [Netflix Open Content](https://opencontent.netflix.com/) 直接将该资产列为“4K HDR 16bit P3/PQ D65 Dolby Vision 2.9 XML + VDM”；[Dolby 样片仓库](https://github.com/DolbyLaboratories/dolby-vision-contents)只列出六个 MP4 文件名，未声明其编码图像来自同一版 VDM TIFF。两处公开说明支持各自资产的用途，尚不足以建立跨仓库逐帧图像血缘。

把 4K P5 截图与 VDM 帧240 **两者都**以 FFmpeg `scale=...:flags=area` 缩小后再比较 RGB16：原尺寸 MAE `(1378,633,623)`，1920×1080 `(1332,576,560)`，960×540 `(1261,479,481)`，480×270 `(1146,361,374)`，240×135 `(997,257,264)` /65535。低通使边缘/色度采样差异下降，但红色在缩小至 1/16 宽高后仍接近 1.5% 满量程；单纯高频边缘误差不足以解释全部红色残差。各尺度平均有符号偏差维持约 `(123,78,45)`。这仍不能区分版本/调色差异、RPU/色域处理及截图量化，应继续用不同 shot 和明确母版身份验证。

### 跨 shot 第 500 帧复核

VDM ZIP 第500帧位于 XML Record `[454,519)`，与前述第240帧不同 shot。按中央目录与本地 ZIP 头定位压缩成员，HTTP Range 分块读取，解压后 49,766,656 字节、CRC32 `19879138` 与目录一致，TIFF SHA-256 `160ae481be961f1a432954840b7eb3870b21723b2c487e4fa256b1fc177d15df`。同一官方 4K P5 文件由主机 mpv 顺序解码，Lua 在 `time-pos=20.833333333` 暂停，IPC 核实 `colormatrix=dolbyvision`、3840×2160、掉帧0；P3-D65/PQ/1000nit `window` 截图 SHA-256 `2106fbd7ed2834bab4dee06466b3dd5176e3198cbbd197d328ebf4b81b226822`，主机进程已退出。

第500帧 P5/VDM 原尺寸 RGB16 MAE `(2774.7,2238.4,1419.9)` /65535、偏差 `(442.5,484.4,-110.3)`、P95 `(7171,5741,3807)`；同时 area 降到 960×540 后 MAE `(2468,1875,1241)`，240×135 后 `(1774,1041,695)`。为防时间偏移，把 P5 帧499/500/501 各自与同一 VDM500 比较，MAE 分别 `(4363,4445,2477)`、`(2775,2238,1420)`、`(4331,4366,2412)`；500 三通道均最佳。因而两处不同 shot 的同索引帧在 ±1 范围内均对齐，但第500帧残差更大且低频仍存在。不能据此判定 P5 算法错误：Netflix VDM 与 Dolby 发布编码可能非同版母版/调色，截图渲染路径也未被独立验证。后续应优先找可证明编码来源的母版或独立 CM/解码输出，而非把这两帧的 MAE 直接设为质量阈值。

### 两处 shot 的元数据来源关联

Dolby 仓库 README 仅列出六个 profile/分辨率文件，未声明它们与 Netflix 2020 VDM ZIP 的逐帧图像或 XML 完全相同。MP4 封装 `creation_time=2022-06-28`，Netflix XML Revision 为 `2020-02-19`；这反映导出时间差，不能单独证明或否定母版身份。不过同一官方 4K P5 在 mpv 顺序解码后，两处 RPU Level 1 读数与 XML 对应 Record 显著接近：帧240/shot `[144,454)` 的 XML `ImageCharacter(min,avg,max)=(0.000488,0.370847,0.733398)`，mpv `avg-pq-y=0.370940,max-pq-y=0.733333`；帧500/shot `[454,519)` 的 XML `(0.000488,0.513258,0.749512)`，mpv `avg-pq-y=0.513309,max-pq-y=0.749451`。两帧 mpv `min-luma=0.000104,max-luma=1000.606506`、`colormatrix=dolbyvision`；帧240二次截图 SHA 与上次完全相同。数值差约 0.00005–0.00009，符合编码量化/表示转换量级，强烈支持 P5 RPU 与此 XML 的 shot 统计来源相关，**但不能证明编码图像是该 TIFF 序列的同版图像**，也不能把母版与消费端截图残差归为单一算法错误。下一步优先找 Dolby 样片编码来源声明，或取得相同压缩码流的独立解码/目标映射结果。

### 两 shot 通用颜色矩阵假设检验

将 P5 与 VDM 两帧均以 `area` 缩至480×270，在 PQ 编码值域对单帧最小二乘拟合 `RGB_out = RGB_in × 3×3 + 偏置`，再应用到另一帧。原始 MAE：帧240 `(1146,361,374)`，帧500 `(2133,1446,1005)` /65535；帧240自拟合 `(849,331,363)`，但应用到帧500恶化为 `(3285,1587,1131)`；帧500自拟合 `(1882,1290,919)`，应用到帧240恶化为 `(1509,1638,962)`。另在 PQ EOTF 后线性光域拟合无偏置 3×3 矩阵，连训练帧自身 MAE 也未改善。两帧内容分布不同，最小二乘可能受权重/剪裁/空间错位影响；本检验只排除“用这两帧求一组简单全局矩阵即可消除残差”的捷径，不能证明不存在更复杂的固定变换，也不能反证 DV 解码正确。下一步应找有可证明同版母版的码流或独立解码输出。

### 独立 RPU 解析与候选软件渲染器

本机 Homebrew FFmpeg 9.0.2 未编入 `libplacebo`/`zscale` 滤镜，单用其 HEVC 解码输出不能完成 P5 RPU reshape 或提供独立 PQ RGB 真值。[DoViBaker](https://github.com/erazortt/DoViBaker) 是另一套 BL/RPU→PQ RGB 的开源实现，文档说明默认不执行 DM 显示映射，适合先对照母版域，但输出语义仍须实测核对。已把上游及子模块检出到隔离目录 `/tmp/media-kit-dovibaker-reference`，Homebrew 安装 AviSynth+ 3.7.5、FFMS2 5.0；因本机 arm64 而上游 CMake 包含 x86-only timecube 源码，临时只编 DoViBaker P5 核心及 libdovi C API，得到可加载的 arm64 `libDoViBakerP5.dylib`（SHA-256 `dbd3d800aa8e3c7c2d51d627a50017c735e86ad456c9ed7b9f1a78a0f1d4f138`）。此临时构建未接入可读帧源/AVS 帧导出，**仅证明编译和动态加载，不是独立图像输出**；未修改项目或上游正式代码。

用自编译 `dovi_tool 2.1.2` 从官方 P5 MP4 的 Annex B HEVC 流抽出 `/tmp/media-kit-dolby-official-p5-2160p-rpu.bin`，SHA-256 `cde508e9e958f96897053988a159b57e64035ddd37bd27de7092b70f0b215b10`；工具 summary 报告 6314 帧、Profile 5、CM v2.9、72 个 shot、1000nit mastering 与 100nit L2 trim。导出的 72 个 `scene_refresh_flag` 帧序号与 Netflix XML 的全部 72 个 `Record/In` **逐项完全相同**（从 `0,24,120,144,454,519,...` 至 `...,4560,4908,6240`）。结合前述两 shot L1 数值匹配，P5 RPU 与 XML 使用同一镜头切分/元数据制作链的证据很强；这仍未证明 Dolby MP4 视频样本取自 Netflix VDM TIFF 的完全同版图像。FFMS2 Homebrew 瓶子没有 AviSynth 源插件，后续改用实验性单帧宿主接通输入/输出，见下。

### DoViBaker 与 mpv 同码流跨实现对照

隔离上游 DoViBaker commit `ffba39830b694ddca0bf5f73dcf1b462713bb7f4`、dovi_tool 子模块 `83e1fdad6dcd5995556235946e7c5c0f9010d5a1`。本机只为 ARM64 编译 P5 核心，未启用 x86 timecube/其他工具；实验宿主源码保存为 `archives/experiments/tools/p5_dovibaker_frame_host.cpp`。它把 FFmpeg 软件解出的 3840×2160 YUV420P10 单帧送入 AviSynth `DoViBaker<false>`，按同索引读取抽出的 RPU，默认关闭 L2 trim，输出 RGB48 原始帧；第240/500帧 raw YUV SHA 分别 `df7a9dd5a1abbae9c8fdf4c26306f1a51227a13f49c67c7845c0578573928c3f`、`c68aa84116094347d09264f56554a5b0b40f11bdbfb68d96ac35dbb781aadb35`，DoViBaker 原始输出 SHA 分别 `f26a086d8402ea969e21e4e4e3dc55c4bbd6ea40cabe7ade82e888cd5e8b5aef`、`4ba828eacc126f9ef90313f6d3d3754fbdb2be6a8033603e139abdaffcc11072`。宿主首轮输出后因帧对象比 AviSynth 环境晚析构而 exit 139；调整析构顺序后两帧输出均正常 exit 0，旧崩溃轮不作验证依据。

关键颜色域：直接把 DoViBaker 的三通道原始输出当 BT.2020/PQ RGB 与 mpv 第240帧比较，MAE `(3210,1178,322)` /65535，**不能据此判 DoViBaker 与 mpv 不同**。DoViBaker 这一路的源码在 RPU `ycc_to_rgb` 后即写帧；对本 P5 码流还须执行 PQ EOTF→RPU `rgb_to_lms` 矩阵→HPE LMS 到 BT.2020 RGB 固定矩阵→PQ OETF。比较脚本 `archives/experiments/tools/p5_dovibaker_compare.py` 从相同 RPU 取 9 个线性矩阵系数，固定 HPE 矩阵及 ST2084 常数依据本地 libplacebo DV shader；因此它独立核查了 DoViBaker 的逐帧重塑，**最后颜色矩阵并非独立于 libplacebo**。

主机 mpv 对同 P5 从0顺序解码到精确 PTS10.000/20.833333，目标均为3840×2160 RGB/BT.2020/PQ/1000nit、`bgr10a2`，`window` PNG 的 BT.2020/PQ 标签经 ffprobe 回读，掉帧0；两截图 SHA 分别 `18584396f018f61b325a08d971a06c7dbd98b4874eea43174184519f1d4a16fd`、`a90262a70808e9ee0dce8923fe7478dc96ddfce0d8240a1845836decd5b0090d`。补完上述转换后 DoViBaker 对 mpv 同域整帧 RGB16 MAE：帧240 `(52.41,33.26,25.22)`、偏差 `(-51.25,-27.45,-2.00)`、P95 `(88,81,101)`；帧500 `(74.00,98.82,83.56)`、偏差 `(-51.89,-31.96,-5.18)`、P95 `(202,333,314)`。这比两帧 mpv P3 输出对 Netflix VDM 的千级 MAE 小一个数量级以上，支持两套 RPU 重塑在相同压缩帧上**高度一致**；差值包含各自色度上采样/精度/截图渲染差异。两者共享 FFmpeg HEVC 解码、RPU 信息来源且最终固定矩阵借用 libplacebo，不能称完整独立 Dolby golden，亦不能从此证明 MP4 与 Netflix TIFF 是同版母版。优先继续核 MP4 图像来源及目标显示映射；手机 PQ/HDR 显示门禁仍独立开放。

再用标准 BT.2020 与 P3-D65 原色色度/共同 D65 白点推导线性 RGB→XYZ→RGB 矩阵，把 DoViBaker 完成上述 PQ/LMS 转换后的 BT.2020 线性 RGB 转到 P3-D65，再编码 PQ，与 Netflix VDM TIFF **原尺寸整帧**比较。实验脚本支持 `--vdm-tiff` 并报告：帧240 RGB16 MAE `(1385.46,629.73,621.81)`、偏差 `(-36.60,50.00,43.23)`；帧500 MAE `(2760.03,2228.42,1417.43)`、偏差 `(318.80,451.34,-115.33)`。这与先前主机 mpv P3/PQ 窗口对同 VDM 的 `(1378.1,632.9,623.1)`、`(2774.7,2238.4,1419.9)` 几乎同量级且各通道差最多约 15/65535。**千级 VDM 残差在第二条渲染/读回路径中复现，不能主要归因于 mpv `window` 截图独有路径。** 仍不能从两个相关实现推断哪张图“正确”：共同 HEVC 解码、RPU、末级 HPE 常数与未证实同版母版是明确边界；目标显示 Dolby CM 结果仍缺失。

### 10-bit/4:2:0 损失的窄范围代理实验

为给残差量级一个参照，对 Netflix VDM 第240/500帧原始 P3/PQ RGB **仅在代码值域** 做 BT.2020-NCL 系数形式的 RGB↔Y′CbCr 往返，显式10-bit全范围量化；4:2:0 分支对色度 2×2 box 平均、按中心位置双线性重建，亮度保留全分辨率。脚本 `archives/experiments/tools/p5_vdm_subsampling_proxy.py` 的逐通道 RGB16 MAE：4:4:4/10-bit 两帧均约 `(27,18,33)`；4:2:0/10-bit 帧240 `(225,93,231)`、帧500 `(326,137,363)`。它们小于真实 P5 输出对 VDM 的 `(1378,633,623)`、`(2775,2238,1420)`；故**这个简化的位深+色度采样模型本身不足以复现残差**。它没有模拟 P5 的 IPTPQc2 色度、Dolby reshape、HEVC 有损压缩、编码前制作处理或母版版本差，不能当真实 P5 编码误差上下界，更不能据此断定 P5/VDM 哪方错误。后续若要定量归因，需要可证明同源的编码输入/输出或实际编码流程。
