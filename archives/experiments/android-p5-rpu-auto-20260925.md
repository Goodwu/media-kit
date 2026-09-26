# P5 MediaCodec RPU 自动附帧隔离候选（2026-09-25）

## 结论

此前 11015–11017 的 P5 硬解播放须人工设置 `debug.media_kit.p5_rpu_probe=2`；该属性在隔离 FFmpeg `libavcodec/mediacodecdec.c` 初始化时决定是否解析码流 RPU、按 PTS 匹配 MediaCodec 输出并附着 `AV_FRAME_DATA_DOVI_METADATA` 与原始 RPU。属性 0/缺席的旧库默认不运行此逻辑，因而诊断成功不能直接成为正常应用的 P5 能力。

本轮在 `/tmp/media-kit-ffmpeg-p5-stream-2215` 做隔离候选：仅 HEVC 流的 Dolby Vision configuration 明确为 Profile 5、`rpu_present=1`、`bl_present=1`、`el_present=0` 时自动启用附帧；先检查 codec coded side data，若尚无配置则在后续 packet side data 见到配置时启用。显式属性 `0` 关闭，`1` 保留日志诊断但不附帧，`2` 保留日志诊断并附帧；自动模式抑制先前健康帧前320/250条详细日志，错误仍记录。归档补丁 [`android-p5-rpu-auto-candidate-20260925.patch`](android-p5-rpu-auto-candidate-20260925.patch) 是相对隔离 FFmpeg clean HEAD 的**完整 P5 流补丁加本次自动启用改动**，不是可直接应用于 media-kit 产品源码的提交。NDK28 的 FFmpeg ARM64 `libavcodec.a` 构建成功，重新链接隔离 mpv，随后打成测试 JAR/APK。

11018 首包无效：`vo/gpu-next/android` 在打开前报 `No Java virtual machine has been registered`，无有效视频帧。根因是 mpv 隔离构建的 `player_client.c.o` 过旧，虽然源码已有 `mpv_lavc_set_java_vm`，该对象/产物没有导出；重编该对象、重链接并以动态符号表确认导出后打 11019。11018 不作 RPU 或性能阴性结论。

11019 同一 APK、同一 P5/AAC 样本、1440×810 Texture/gpu-next/MediaCodec/packed10 条件下做属性 A/B：

| `p5_rpu_probe` | 视频回读 | 结果边界 |
| --- | --- | --- |
| 空值（`getprop` 回读空） | `hwdec-current=mediacodec`，3840×2160 `colormatrix=dolbyvision`、BT.2020/PQ，输出1440×810 | 自动候选成功进入 DV 帧路径；首轮t60内容59.5秒、VO掉7/decoder0；重复全片t120内容119.58秒、VO掉2/decoder0，t150 EOF且完成事件为true。轮次差异不可归因于算法性能。 |
| `0` | 同硬解/1440×810，但 `colormatrix=bt.2020-ncl`、`gamma=bt.1886` | 显式关闭有效，自动DV输出并非旧属性残留；这是故意关闭必需处理的诊断阴性组，不是正确P5播放。 |

两轮均固定相同输入，只有属性及重启差异。此证据仍不足以证明全 6609 帧 RPU 与输出逐帧无误：自动模式没有逐帧日志，播放器至 EOF 也未给出 decoder close summary；需要低开销累计计数/flush 证据、seek/重开及 P8.4/HDR10/普通 HEVC 阴性实机对照。当前候选还在隔离 FFmpeg/mpv/JAR，**未并入项目依赖或产品默认**；其他颜色、显示、30分钟稳定门禁不受此轮替代。

11019 APK `/tmp/media-kit-p5-rpu-auto-11019.apk` SHA-256 `4bc15babfa0dfa1fabd4dbe1d09133a4b82f6ea7cb64b4068b1cb2ba1ce31cdc`、包内 stripped libmpv SHA-256 `728aac997fa9b6bff8a10b015cbbd7b960bf2e7a3f11970ebefecc48b8264132`；JAR SHA-256 `8948fd56d62f374052d799758a7bc745e6c81e29fbb38d049ebd3301c6812781`。自动首轮日志 `/tmp/media-kit-p5-rpu-auto-11019-logcat.txt` SHA-256 `9a8b7b0faedf3301fa383a1f9bc03b5347ba83de9ca5056f1c87f75afd5adf23`；显式关闭日志 `/tmp/media-kit-p5-rpu-auto-11019-off-logcat.txt` SHA-256 `c813cce1bbe1f30de1c00ee77c2785fed2dbcef4aad9f9879cc0d29afe4ed0a0`；自动完整轮日志 `/tmp/media-kit-p5-rpu-auto-11019-full-logcat.txt` SHA-256 `b022f3c11817fb97eceb49065a33955c8e51f9fbac53bdd05bab7e5b90bead54`。

## 后续逐帧计数与非 P5 对照

同隔离候选加入一次性结束汇总，先尝试 decoder `AVERROR_EOF` 钩子：11020 在t120进度119.46秒、VO掉1/decoder0，t132完成，但钩子未触发；说明播放器的媒体完成事件不等于此处 codec receive EOF。11022 在t145用测试入口将 `vo` 改为 `null` 并 dispose，Dart回读`AUTO_PLAYER_DISPOSE completed`，mpv日志桥仍未转发 FFmpeg close 汇总。随后11023仅在 FFmpeg close 同一计数点增加 Android 原生单次日志，终于得到计数；无效 EOF 钩子已从最终归档补丁撤除。11020/11022 属计数观测失败，不可当作零错误的证据。

11023 同一 APK、同一 P5/AAC 输入、同一1440×810 Texture/硬解配置，分别为空属性自动模式与显式 `2` 模式，均播完132秒并在t145释放：

| 模式 | 输入 | 输出 | 匹配 | 错误 | 丢弃 | 未消费 | VO/decoder掉帧 t120 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 自动（属性空） | 6609 | 6603 | 6603 | 0 | 6 | 0 | 1/0 |
| 显式 `2` | 6609 | 6608 | 6608 | 0 | 1 | 0 | 1/0 |

`epoch=2`，汇总里的`discarded`是 FFmpeg 候选在 flush/淘汰时释放的未消费输入条目，不能直接等同可见丢帧。两轮都证明**实际返回的硬解帧没有观察到RPU错配**，但自动模式少5个输出且多5个丢弃；只各一轮，不能断定差异由自动启用还是解码/片尾 drain 时序波动导致。当前不满足把该候选并入产品的证据门槛；下一步复测同模式及记录首尾输入/输出PTS、flush发生点，解释这5帧。不能以 `frame-drop-count=1` 掩盖 decoder 输出计数差。

非 P5 阴性：用 MP4Box 从既有 P8.4 源无重编码抽取10秒 `/tmp/media-kit-p84-auto-rpu-negative-10s.mp4`，SHA-256 `888ec4c7689ca755350dbe7c43c153632ed35e66c7b5b56f63ad520096becdc1`；ffprobe回读 HEVC 3840×1920、`dv_profile=8`、RPU存在、compatibility ID4、300视频帧。11021使用同一候选JAR、空诊断属性，真机 `hwdec-current=mediacodec`、track profile8，视频帧保持 `bt.2020-ncl/limited/HLG`，1440×720 Texture 输出并完成10秒，未被自动模式误标成 P5/Dolby Vision。它只覆盖一条 P8.4 样本，HDR10/普通HEVC、seek/重开仍待验。

## 片尾丢弃定位

11023 自动模式在同APK重复一轮仍为`6609/6603/6603/0/6`（输入/输出/匹配/错误/丢弃），说明该构建下计数可复现。11024在相同输入和输出配置中加入显式`p5_rpu_probe=3`（附RPU但关闭逐帧诊断日志）：显式3为`6609/6608/6608/0/1`，空属性自动为`6609/6607/6607/0/2`。因此仅用详细日志开销不能解释全部差异；不同构建的自动轮丢弃数量也会变化。

11025对首尾输入/输出PTS及flush新增低频原生日志。空属性自动模式播放完成并在t145释放时记录：输入6609、输出6602、匹配6602、错误0、丢弃7、未消费0；输入PTS`0..132140000`微秒，输出PTS`0..132020000`微秒。完成事件时首次flush（epoch0）一次丢弃7条，首尾待匹配PTS为`132040000..132160000`微秒；关闭时第二次flush新增丢弃0。可确认本轮未消费条目集中在**片尾停止/flush**，不是已返回视频帧中段发生RPU错配；不能据此证明尾帧的显示效果或把所有A/B计数差归因于自动模式。下一步应统一结束策略并观测MediaCodec drain/最后输出PTS，再做seek/重开及其他非P5阴性组。

11025 APK SHA-256 `7345c623430e24c9104e3be3139eff044c53c1be493fcd99ac2daee4b1b6f80f`；日志`/tmp/media-kit-p5-rpu-pts-flush-11025-auto-logcat.txt` SHA-256 `69c01aa9e91e9aab66e676415e878c72fdb24e2cd3bef55a30a756a41333afa7`。当前完整隔离FFmpeg补丁SHA-256 `aefac844d59ded2d070346cbba30e5f813102427f039c3d63c266108c3fe55d0`，含显式3和PTS/flush诊断，未并入产品。上节记录的旧补丁SHA属于当时快照。文末设备恢复状态以最后检查为准。

为区分长片尾部偶发状态，用`MP4Box -splitx 0:10`从同一P5/AAC输入无重编码切出10秒样本，SHA-256 `46338eb7d07beec19b4e8ff081912a6ece76f4542b23d33eb52a93230689548b`；ffprobe为P5/RPU、501视频帧、10.000秒视频和10.021秒音频。11025相同自动属性/输出设置运行至完成并于t145释放，汇总输入501、输出/匹配499、错误0、丢弃2、未消费0；最后返回PTS9.96秒，首次flush丢弃PTS9.98与10.00秒。厂商日志在flush附近记录`receive eos buffer`，但该日志未区分输入/输出EOS的完整时序，不足以单独确定mpv、FFmpeg或厂商哪层提前终止。缩短样本后仍复现**仅片尾未返回**的模式；下一步应在隔离FFmpeg的MediaCodec收包/出包和EOS返回处加一次性计数，确认是否收到带EOS的输出buffer及其PTS，再评估是否需要变更drain。

短样本日志`/tmp/media-kit-p5-rpu-drain-10s-11025-logcat.txt` SHA-256 `4d2dbb75eb309a829b2540921d450e571012af4e7df8734b1593169e53c07ccf`。本轮结束后手机恢复10369、七项相关属性均0、无应用进程，设备上的短样本已移除。

11026在相同隔离FFmpeg的`mediacodecdec_common.c`只对HEVC增加三处原生日志：空EOS输入排队、带EOS标志的输出buffer、解码器返回EOF。重复上述10秒样本时，06:17:42.777排入EOS输入，06:17:42.890收到`flags=4,size=0,pts=0`的输出EOS，06:17:42.891返回EOF；随即MediaCodec flush，并在06:17:42.893丢弃最后PTS`9.86..10.00s`的8条未匹配RPU。厂商ACodec同一时刻报告codec仍拥有`10/17`个输出buffer。此轮短样本丢弃数由2变8，佐证尾部结果有时序敏感性。**这证明FFmpeg看到硬件的输出EOS后才结束，不能直接断定MediaCodec违反规范**：仍需查输入顺序、B帧重排、输出buffer释放和厂商EOS语义；10/17占用是候选原因，不是已证根因。不能通过延迟清理RPU伪造缺失的视频帧。

11026 APK SHA-256 `2f4d3a9ccaac5f4726e374246d6d5cae7933834f8177281501c50d49bce9e640`；日志`/tmp/media-kit-p5-rpu-eos-11026-10s-logcat.txt` SHA-256 `2fea5966df07d6cb240819bb8771294bc9a329d681d5f042f00e25df9ed29ebf`。隔离完整补丁现含两个FFmpeg文件，SHA-256 `2c9c08cce8bd24677f0b44fcab364a382242ce920501090116416e668b24bbaa`；旧SHA分别对应此前快照。此轮在读到片尾EOS和flush后即强停，没有等待t145 decoder close summary，因此不能给11026宣称完整输入/输出汇总；手机已恢复10369、七属性0、短样本移除。

**短片封装计数修正：** 对短片做独立软件逐帧解码，`nb_frames=501`但`nb_read_frames=500`；MP4Box切点留下PTS10.00秒的末包，`ffprobe`标记`KD_`（含discard），不能把这包当作应显示的第501帧。故11025短片499返回/2丢弃，扣除切点discard后仍至少有1个相对于软件解码的尾帧差；11026的8条待匹配记录也包含这一个预期不显示包，不能宣称8个应显示帧全丢。原132.18秒长片的末包无discard标记，软件逐帧解码`nb_frames=nb_read_frames=6609`；其11025硬件返回6602与软件6609相差7帧，仍需解释。短片只适合定位EOS/flush时序，**不能直接作为长片尾帧数的定量替身**。下一步优先记录MediaCodec输出缓冲占用和释放时序，并把`AV_PKT_FLAG_DISCARD`输入排除出RPU待匹配计数。

以下为**已失效的开关对照解释**：同11026 APK和10秒短片，做两个设备属性轮次：`early_fence=1,retire=0`时EOS输出后首次flush丢弃3条PTS`9.96..10.00s`，ACodec报占用`10/17`输出buffer；`early_fence=0,retire=0`仍丢弃3条，ACodec报`11/17`。两轮均有`size=0,flags=4`的输出EOS，并非显式延迟退休或早期fence开关单独决定能否排完片尾。基线`early_fence=1,retire=1`上一轮丢弃8条，但短片轮次差异已有2–8，单次A/B不证明开关造成变化或无影响。还需分别测FFmpeg持有的`hw_buffer_count`及AImageReader/GL持图数量；ACodec的`10/17`不能直接全归因于Flutter/VO。两轮在片尾观测后强停，未等t145 close summary。日志SHA-256依次为`79b0cabfbf23d4a6c89696791f9198dd52033ff2a8f1fcc7744ee7b5ea396afe`、`0130b95919cc01e400710f4c83efd39dd883b515acf75dbb42c406b47fbe41aa`，路径分别`/tmp/media-kit-p5-rpu-eos-11026-10s-retire0-logcat.txt`和`/tmp/media-kit-p5-rpu-eos-11026-10s-fence0-retire0-logcat.txt`。手机已恢复10369及七属性0，测试短片已移除。

**构建一致性更正（11026/11027）：** 复核隔离`libmpv.so`字符串发现，它没有当前`hwdec_aimagereader.c`源码中的`P5_RETIRE`、`p5_raw_yuv`或`code_scale_1020_to_1023_enabled`，说明之前替换FFmpeg静态库重链接时沿用了旧mpv mapper对象。故上一段属性A/B虽设置了设备属性，**不能称为raw早期fence/retire功能A/B，也不能据此否定这些功能对尾帧的影响**；能保留的只有对应二进制下MediaCodec EOS、flush和厂商占用观察。

11027在旧mapper二进制中于EOS输入时FFmpeg`hw_buffer_count=1`，收到输出EOS时为`0`，同刻ACodec报占用`10/17`；这证明该轮10个输出槽不能全解释为FFmpeg尚未释放的`AVMediaCodecBuffer`，但不能分辨codec内部和下游Surface/ImageReader持有。其短片日志中早段还有两次`acquireLatestImage failed: -30001`，因此不作可见画质验收。11027 APK SHA-256`b51ccbaa4b0f6fb760c15c230bd49906bcab95d51152f85541fe829331b1df3e`、日志`/tmp/media-kit-p5-rpu-eos-hwcount-11027-10s-logcat.txt` SHA-256`106e5c937982e295375d638865be4fe24401b148a983efb3cd765858b58e6cbe`。

尝试直接重编当前mapper对象并重链接得到11028，`strings`已能看到上述raw标记，但运行首次进入raw路径即在libplacebo `src/renderer.c:3047 frame_ref` 的`frame->num_planes`断言SIGABRT，无法用于EOS/性能判断。11028 APK SHA-256`56196a08b9d256788a54a56412b16bcf1fa1b4b7aa3709c223bcc54eecaf2115`，崩溃日志`/tmp/media-kit-p5-rpu-currentmapper-11028-crash-logcat.txt` SHA-256`0a10e0a42ebb31c6ed83a44f77d22c9e1716e5121271822b7fa93f379a38cc83`。尝试对隔离mpv做完整`ninja libmpv.so`时Meson自动重新生成配置，错误引入macOS Homebrew库及`-framework`到Android链接，ld.lld拒绝；需重新配置一致的Android依赖/重编相邻渲染对象，不能继续混用新旧对象作结论。当前隔离FFmpeg补丁（含`hw_buffer_count` EOS日志）SHA-256`287325663950d236e069573e9324503d931b9c5c7aa9ce25bb8fb1dbf69100a8`。设备已恢复10369及七属性0。

找到同源的`/tmp/media-kit-mpv-clean-2194/_build-isolated-arm64`：其crossfile指向`/tmp/media-kit-prefix-clean-2197`的Android依赖，既有libmpv二进制含raw/retire标记且导出`mpv_lavc_set_java_vm`。只在该构建的链接命令中替换隔离FFmpeg `libavcodec.a`，11029构建/安装正常，并在同10秒P5短片中实际出现`P5_RETIRE`记录：map450时held0/reaped447/waits0/fallbacks0，说明该时点没有延迟退休图像积压。EOS输入排队时FFmpeg `hw_pending=0`，49ms后输出EOS时`hw_pending=1`，ACodec同刻报占用`10/17`输出buffer；首次flush丢弃末尾PTS`9.96..10.00s`三条，其中PTS10.00为MP4Box切点discard包。此轮确认**当前raw/retire路径也出现尾部未匹配记录**，但Reader的held数仅按每50次map采样，不能推断EOS瞬间Reader完全未持图；ACodec的10槽包括内部/Surface/Reader状态，仍需队列级证据。短片的raw路径没有由真人或截图验收画质，本轮只用于EOS时序。

11029 APK SHA-256`67d783ee82bc8fc02e7ef69637df679eecc92726aa432fd7aebfaf20530c0d06`，日志`/tmp/media-kit-p5-rpu-eos-isolated-11029-10s-logcat.txt` SHA-256`2f60dd5c4a6dbc86eade4fc8a2014ce56d66c9a9efdb8b58aa9591c2cde0c17c`。片尾观测后强停，未等t145 decoder close总计；手机恢复10369、七属性0、短片移除。后续编译/链接应使用`_build-isolated-arm64`和一致Android依赖，避免旧`_build-arm64`对象及Meson主机pkg-config污染。

11029同APK/短片的**有效raw路径**`retire=0`对照，保持`raw_yuv=1,packed10=1,early_fence=1`：原生日志仍出现`P5_RAW_STAGE`的draw路径，且无`P5_RETIRE`周期记录，符合属性关掉延迟退休；EOS输入排队时`hw_pending=0`、输出EOS时`hw_pending=1`、ACodec占`11/17`输出buffer，首次flush丢弃PTS`9.98..10.00s`两条（末条为切点discard）。`retire=1`上一轮为三条、占`10/17`，单轮波动不足以认定retire造成1帧差；两组都出现输出EOS后的未匹配RPU。对照日志`/tmp/media-kit-p5-rpu-eos-isolated-11029-retire0-10s-logcat.txt` SHA-256`e85e1f9b9537697e194861cf2de7895bf072e400ed3e897027582e81c3192a93`。两轮均未等t145 close总计、未做可见画质验收；设备恢复10369/七属性0。

## 一致raw构建的原长片与EOS PTS假设

11029在原132.18秒P5/AAC、6609视频包/软件解码帧、1440×810目标、raw packed10/early fence/retire均1的条件下播至完成并t145释放。硬解RPU汇总：输入6609、输出/匹配6603、错误0、首次flush丢弃6条PTS`132.06..132.16s`、未消费0，末返回PTS`132.04s`。输出EOS前FFmpeg hw引用从0到0，ACodec在flush时占`10/17`输出buffer。VO汇总接收6603、队列过期3、绘制6600；这两类计数分别是decoder返回与VO绘制，不可合并为同一种掉帧。P5_RETIRE map6600时held0/reaped6597/waits0/fallbacks0，只有周期采样，不证明EOS瞬间Reader持图为0。此轮证明旧构建的片尾差额并非仅因旧mapper：真正raw路径仍少于软件6609，差6帧；无真人/光学画质验收。日志`/tmp/media-kit-p5-rpu-eos-isolated-11029-full-logcat.txt` SHA-256`7c96fd5b3b7cad5138dd56c1ed0f5ed697732902f0113e32d2ffb0c56151db70`，结束后设备恢复10369/七属性0。

另在隔离FFmpeg试验`debug.media_kit.p5_eos_pts=1`：仅把HEVC空EOS输入PTS从0改为此前排队输入最大PTS+20ms，普通视频包不变；11030同APK/同10秒样本做开→关→开三轮。开两轮均实际排入EOS PTS`10.02s`，各在输出EOS后flush三条PTS`9.96..10.00s`；关轮排入PTS0、只flush切点`10.00s`一条。ACodec槽占分别10/17、12/17、11/17，且短片历史轮次本就有1–8条波动，不能从这三轮确定PTS导致恶化；但**没有改善证据**，不扩展到长片或产品。试验属性/状态字段已从隔离源码撤回并重新编译；当前归档补丁SHA-256`ad4887d324891989480ed2508aa7cd6085d6add1b8d6a98e5ec2424f4ced28ea`，11030 APK与当前补丁不对应。11030 APK SHA-256`5bdbd7d9bf9d82dfe18df9c2260337d0a9e30f093828c7bb107ef111a9a6c2e6`；开/关/重复开日志SHA-256分别`3cd196cfbc198ce3861236962966622cee688eb5d285eec9e47c5c6aa7f593a3`、`7e1387764e6efe6874ee86eaa3ee07ecd4da766b1e564591df4a07b03e42d844`、`21a63ce7c371c438ae3d71ad9db502c30a1990c5e727b7ecdce6ce1bd91b94fd`，路径`/tmp/media-kit-p5-rpu-eos-pts-11030-{on,off,on-repeat}-10s-logcat.txt`。设备已恢复10369、包括新增属性在内八项均0、短片移除。

## 原片真实结尾的快速复现样本

用`MP4Box -splitx 120:132.18`从原P5/AAC无重编码抽取最后12.18秒，生成`/tmp/media-kit-p5-tail-120-13218.mp4`，SHA-256`ce4240dd82c7625353bab45cf15e9dc412df75e2b513d3818f4dbea4b0947a1d`。ffprobe确认Profile5/RPU、609视频包；软件逐帧解码`nb_read_frames=609`，末包PTS12.14秒、无discard标记。它保留原文件的实际尾部，避免前10秒MP4Box样本的切点discard干扰；PTS重新从0开始，仍需留意起点剪切/音频时间轴不同于全片。

11031复用一致raw构建的JAR，仅把测试入口关闭计时改为25秒，同一尾段样本重复两轮：第一轮输入609、硬解输出/匹配601、错误0、首次flush丢8条PTS`12.02..12.16s`，末返回PTS12.00秒；第二轮输入609、输出/匹配606、错误0、flush丢3条PTS`12.12..12.16s`，末返回PTS12.10秒。两轮均收到`size=0,flags=4`的MediaCodec输出EOS，完成事件为true，t25 decoder close第二次flush新增0。**609个软件可解码帧全部是预期输出帧**，因此差8/3不是切点discard造成；同APK同源轮次变化确认时序敏感。该短尾样本适合后续EOS/buffer释放实验，但不能用两次短测证明长片30分钟热稳、物理显示或色彩验收。11031 APK SHA-256`32666b5e1ead8541eb04412ecb8013b066f1e6fa2902bcf33714b139726507d8`；首轮/重复日志SHA-256`5db863f860e7bb02086b88cbed531285b395f44294858145e494a7f426443b79`/`1305fe4db4a6f0274174aa9839cb20e2cd2a3b5b10f32f4dc1008be15a27cf60`，路径`/tmp/media-kit-p5-tail-11031-{first,repeat}-logcat.txt`。设备已恢复10369/八属性0、尾段样本移除。

试验“输入EOF后先有界取尽已就绪输出，再排入EOS”：11032仅对自动附RPU的P5在属性`debug.media_kit.p5_pre_eos_poll=1`时最多做4次、每次至多8ms的MediaCodec输出查询，取到帧则返回，下一次再遇EOF；属性0走原分支。对同一609帧尾段样本，同APK开/关各一轮最终均为输入609、输出/匹配606、错误0、flush丢尾部3条PTS`12.12..12.16s`。开启轮确实在排入EOS前额外取到PTS12.00/12.02秒两帧，然后4次查询为空再排EOS；关闭轮直接排EOS，但最终输出数相同。故有界预取**改变了返回时序，没有提高本次完整帧数**；考虑基线本身3–8帧波动，不作正向修复，也不扩展长片。试验属性和代码已从隔离源码撤回，当前归档补丁SHA仍为`ad4887d324891989480ed2508aa7cd6085d6add1b8d6a98e5ec2424f4ced28ea`，11032 APK不是该补丁的构建产物。APK SHA-256`2b9e578fb0805dcee56edeba2bec117215fe994a8cee412cbf6585ff40e31c8d`；开/关日志SHA-256`b8bd13f6c532e55b97edfe269d346163bc07f426a32f3d16a5687998cb0b40ab`/`4e29bd80b301791273b45b24a501c3b0dbdbe0a4e968b2b7eb9b3fa338e16de0`，路径`/tmp/media-kit-p5-pre-eos-poll-11032-{on,off}-logcat.txt`。设备恢复10369/九属性0、尾段样本移除。

新增证据：11020/11021/11022/11023 APK SHA-256 依次为 `e320573bf39ac96a2515e352d87e37553c775e95d6146d51ca8307ae380f157b`、`f22564fa042ffc466033b405a679b1aa17bc85752fa41ccbad45735418e806aa`、`8a10c0efa5db21d88c681b73f14ce6fae6d5e7034eea19b0ef26167807c82e7f`、`7f22167f3da27b9b1676e65a6850ce56d93658bd905c8f7897688855b01684f5`。11023自动/显式2日志 `/tmp/media-kit-p5-rpu-auto-11023-p5-logcat.txt` 与 `/tmp/media-kit-p5-rpu-auto-11023-explicit2-logcat.txt` SHA-256 分别 `8ca53e45b19c5dd89ea44fb58d78a32e3738070532614dd9ec3724b80d66e77a`、`f268edbff6a2c1e83edcf0b0f7d3c50d144a754a8bdbe4d0048d4b1084ac3247`；P8.4 日志 `/tmp/media-kit-p5-rpu-auto-11021-p84-logcat.txt` SHA-256 `e5f7edeb8b8394b6483810fc9b1567342b5c1cf9109ad7c7f2582b34e7d025b5`。最终隔离源码补丁 SHA-256 `179d5698e81828323ee4a43c21671907c96ab2916b2acf78b7d3115f6398ea2d`，它移除了11023二进制里未触发的EOF钩子并已重新编译静态库，未再打包复测；因此11023 APK不是该最终补丁的逐字节构建产物。设备已强停、移除两份诊断媒体、恢复10369基线APK、七项P5属性回读0、无应用进程。
