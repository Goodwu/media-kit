> Historical evidence imported from PR #5 at `86c186f000c9b9399d4f91227f740ab2669cb83c`. See [integration Current State](README.md) before interpreting source vectors or acceptance status. The original record below is preserved verbatim.

# LG HLG→PQ 转正独立审核（critical reviewer 终版，2026-10-12）

审核人：team-reviewer-critical（只读独立审核；未修改文件、未运行构建/测试）。
审核基线：media-kit cbcc6bb8（device/MK-ROUTING-20261011/DV-BUILD-01，实现与 a3cdbda2 无差异）、mpv c11426b67a、libplacebo ea700489、FFmpeg 9aba43cf。
DEVICE 实测证据：/Users/wuweiwei1/src/mk-device-20261011/evidence/LG-matrix/（p84-full-verified.log、p84-full-verified2.log、sf-during-play.txt 等）。

## 裁决与范围

**REQUEST_CHANGES。当前不得把整组 lab define 改为产品全局默认；总体风险高。可推进的是精确设备、源类别和输出契约门控下的 LG 转换后端。**

## 逐 define 判定表

| define | 当前语义/爆炸半径 | 判定与条件 |
|---|---|---|
| MEDIA_KIT_ANDROID_HDR_PREFER_CONVERT | lab 页面仅把 dvP84 的 baseLayerConvert 移到 nativeDV/direct 之前，不开放 experimental 门；产品库不直接消费此 define。全局移植排序会让真正 P8.4 在 HLG-capable/PQ-capable 设备优先转 PQ，抢占可行 nativeDV 并剥 RPU。纯 HLG/HDR10/SDR/P5 行不被直接修改。 | 有条件转正目标行为；不可全局默认现有排序。仅对直出不可行且转换后端完整的设备/源组合启用。LG 默认序本已在 nativeDV/HLG direct 不可行后到 convert，通常无需重排。 |
| MEDIA_KIT_ANDROID_HDR_CONVERT_ROUTE_LOCK | lab 通过 HdrVideoSession.forTesting 注入严格 planner，白名单 HLG/P8.4/HDR10、固定PQ/ST形态；SDR安全网/不符形态重试会被拒绝。产品 realizer 还用该值约束 pq-itu 实验。 | 不可转正。严格诊断锁不是 prefer；默认化会破坏两次HDR尝试后SDR兜底语义。保留诊断或明确 require 用途，不能作为产品自动路由默认。 |
| MEDIA_KIT_ANDROID_SURFACETEXTURE_POC | 产品 realizer 仅在 baseLayerConvert 决策点覆盖 hwdec；按非空字符串判断，因此字符串 false 也强制覆盖。本身不限定LG/P8.4/PQ；其他设备convert也受影响；direct/reshape/SDR不直接消费，P5 convert 被拒绝。 | 当前不可转正为默认强制开关。后端可有条件产品化：普通Session owner/init/YUV接线、多owner隔离及呈现验收通过；不能强置 officialBackendReady。 |
| MEDIA_KIT_ANDROID_MPV_OUTPUT_LEVELS=full | lab开播前全播放器设置。库内已部分产品化：YUV route验证后owned写 video-output-levels=full，结束恢复。全局full会影响其他gpu-next输出和后续播放；SDR/full有合法场景但无全设备/transfer安全证据。 | 有条件转正路由内owned full；不可全局默认full。仅用于真实成立的PQ YUV离屏契约，失败/结束/切SDR恢复。LG默认启用仍受呈现、授权和契约问题阻塞。 |
| MEDIA_KIT_ANDROID_LG_VISUAL278_EXPERIMENT | lab生成单次open owner token，经专用channel Enable，要求routeLocked、acceptNonConformant和精确设备门；该token还用于PlatformView桥初始化。格式278授权与config49 YUV授权独立。 | 不可把实验开关原样转正。可迁移必要owner机制为产品事务所有权，但不能继承单open、禁止重规划限制，也不能把历史RGB278路径当已验收YUV路径或放宽固件/ABI门。 |
| MEDIA_KIT_ANDROID_MKS_YUV_DIAG | 实际不只是观测：它arm vendor开关、选择config49 NV12输出；lab目前要求POC+DIAG组合并检查pq/full。首挂载前会退回legacy process-global arm。 | 当前不可原样默认化；功能本体有条件产品化。须将YUV功能选择与readback诊断解耦，绑定本次owner/输出或明确限制单活动转换会话，并验证重建、失败清理。不得全局arm。 |

消费点证据：
- media_kit_hdr_lab/lib/tests/01.single_player_single_video.dart:2901-2909,2948-2978,3074-3094,3209-3259,3273-3314,3761-3811
- media_kit_hdr_lab/lib/common/android_surface_texture_experiment.dart:5-13,59-104
- media_kit_video/lib/src/hdr/hdr_strategy_realizer.dart:214-308,510-544
- media_kit_video/lib/src/hdr/hdr_route_planner.dart:52-98
- media_kit_video/lib/src/hdr/hdr_player_backend.dart:485-504,553-565
- libs/android/media_kit_android_dataspace_vendor/android/src/main/java/com/alexmercerind/media_kit_android_dataspace_vendor/LgPqDataSpaceExt.java:34-61,107-167

LYA边界：现有p84-F/G控制片在本轮分类为纯HLG，证明HLG直出，不证明上述define对真正dvP84无影响；真P8.4默认重排会改道的结论来自代码路径，仍需真P8.4实机负向回归。

## 旧运行回传根因：不是结果丢失

evidence/LG-matrix/p84-G.log:1751-1772：首次surfaceCreated wid0/gen0、native format43，setter/applied=true；发布wid2099370后，gen1重新apply，native window地址不同、格式278，精确格式/实验授权门返回false；Dart随后正确dataSpaceApplyFailed并降级。

完整回传证据链：
1. native gate libs/android/media_kit_android_dataspace_vendor/.../lg_fw_adapter.cpp:138-168,285-303。
2. Java ext成功返回ext:<id>、失败null，report直接生成applied/path/requested/readback：media_kit_video/android/.../PlatformVideoView.java:581-595,672-681。
3. Factory任一live view失败则整体失败：PlatformVideoViewFactory.java:127-154。
4. Channel原样result.success：MediaKitVideoPlugin.java:194-197。
5. Dart按applied首要门，精确LG允许setter无readback但不宣称verified presentation：hdr_player_backend.dart:568-609,673-681。
VideoOutputManager是Texture创建/销毁管理，不是本次PlatformView report回传节点。不应安排"把native true修传给Dart"，不得缓存初始true或省略第二次apply。普通会话缺的是已验收YUV链的准入/初始化。

## officialBackendReady 不等于已注册后端能力

它是realizer调用mkstBridgeInitialized()所得布尔值；FFI调用mkst_ensure_init()==1，只读进程桥是否initialized，不查询mpv method、不验证调用方owner、GL能力或YUV arm。
- media_kit_video/lib/src/hdr/hdr_mkst_bridge_probe_io.dart:3-18
- media_kit_video/android/src/main/cpp/mediakit_surfacetexture_bridge.cpp:181-214,604-628
初始化由PlatformVideoView.setLgExperimentOwner在非空token/正generation时调用Java bridge：PlatformVideoView.java:168-188。

7163121865仅注册hwdec=surfacetexture method；并不置ready、初始化owner或arm YUV。importer仍需GL/EGL、initialized、create_decoder_window成功。证据：
- /Users/wuweiwei1/src/mpv/video/decode/vd_lavc.c:440-464
- /Users/wuweiwei1/src/mpv/video/out/hwdec/hwdec_surfacetexture.c:381-438
12030b9c39是Vulkan Properties2解析修复，不提供ST readiness。

阻塞：普通冷启动在输出创建前realize，bridge尚未init；无实验token的普通Session后续也不init。另可构造A初始化进程桥→B读全局true→B选择ST但并非该owner、也未必有可用窗口；native单窗口门防第二活动窗口，不等于选路正确。应分离"后端可用能力"与"本事务owner acquisition"，不可强置ready。

## owner/ACK/lease 审核

已验证安全结构：
- 输出替换先dispose旧输出，再publish新；失败保留清理债务：hdr_output_slot.dart:42-91。
- 按generation释放Surface与ACK：PlatformVideoView.java:439-489。
- importer仅成功acquire的实例可shutdown；四槽lease、identity、fence、redraw复用：/Users/wuweiwei1/src/mpv/video/out/hwdec/hwdec_surfacetexture.c:429-438,484-518,1117-1163,1191-1274,1386-1437。

高风险阻塞一：YUV arm process-global，native owner tuple为advisory，不绑定具体window。源码明确承认lab单Session例外：lg_fw_adapter.cpp:95-109,273-303,352-400。新日志确实legacy global arm：evidence/LG-matrix/p84-full-verified.log:361-362。
直接复用实验token会继承一次open、禁止偏好修改/自动重规划：hdr_video_session.dart:392-397,1006-1043,1100-1103。产品迁移必须保留等价或更强owner边界，不继承单次实验UX。

高风险阻塞二：realizer和HdrYuvPresentationContract用surfacetexture+PQ推断YUV，但config49实际由另一个vendor arm控制。可构造route声称pq-full而YUV arm未建立/失效、native仍走RGB/其他输出。形式字段校验无法证实实际carrier。应显式建模本事务YUV输出能力与授权，不能以输入hwdec名代替。

## FULL/limited：确定是跨层契约描述失配，非已证像素错误

Dart声称NV12 limited/单次16+219p：hdr_yuv_presentation_contract.dart:26-39。
当前默认BT2020_NCL shader实际 mksColor=vec3(y,cb+0.5,cr+0.5)，FULL-range；只有neutral fallback分支做16+219p：/Users/wuweiwei1/src/mpv/video/out/opengl/context_android.c:230-234,253-276。
metadata range=FULL(1)：同文件:898。vendor仍强制窗口dataspace0x11C60000：lg_fw_adapter.cpp:209-217。
历史批准包含FULL shader+metadata(9,1,16)+vendor标签组合，不能按旧注释改limited或range2。应对齐已批准native配方，明确像素/窗口标签/vendor metadata各自语义。Dart常量断言不是native buffer真值检测；颜色错误保持未验证。

## DV002最终定性

阻塞"呈现验收未完成"，不是已定位"窗口无投递/末级shader黑屏"。

已证：新完整defines两次owner init/bound、config49/NV12窗口、RGBA16F FBO、program创建、两次dataspace成功、HdrRouteAppliedEvent及hal_hdr/推进遥测。证据：
- evidence/LG-matrix/p84-full-verified.log:422-475,509-515,930-956
- evidence/LG-matrix/p84-full-verified2.log:4992-5026
所以本轮不是method缺失或verify-only init拒绝。
10-10原始验收已owner bound poc-r2、ACTUAL、完整lease teardown：
/Users/wuweiwei1/src/media-kit-build/lg-api24/lg-api24-realtime-gpu-mks-c2-telemetry-genbump2-run/logcat-bound-LOCAL-ONLY.txt:83,184,367。不能用提交时间推断a040233d3e owner机制必然晚于验收；需要真实输入字节差分。

重要反证：SF原件真正视频Layer :102-118 activeBuffer=[1440x720:1536,7FA30C04]，slot ACQUIRED/DEQUEUED，:332 HWC使用该NV12 buffer。零buffer的:33-46是animation LayerDim，:50-63/:85-98是SurfaceView的LayerDim。queued-frames=0不等于从未投递。
原件：evidence/LG-matrix/sf-during-play.txt。

已阅截图/录屏抽帧确为黑区：evidence/LG-matrix/p84v-final1.png、rec-frame-1.png。但NV12在位/HWC选层不证明面板光学正确，黑截图/黑录屏也不能唯一证明buffer为黑。HWC捕获限制是合理解释，非唯一已证根因。协调方已接受"无投递"撤回并安排人眼验收。

MKS_ST_DIAG_READBACK=0/MKS_YUV_P0_OBSERVE=0导致缺少lease像素及末级draw观测，Dart_DIAG=true不恢复编译掉的native观测；缺日志不等于未执行。最小动态验证顺序：光学确认→同owner/generation lease像素→PQ offscreen像素/FBO→末级GL/NV12真值→HWC/面板。若用户直接确认正常，关闭对应候选呈现验收项；不得同时自动关闭owner、全局arm、普通Session接线问题。

## 证据充分性

已有：10-10正确P8.4实验配方ACTUAL、owner/lease清理、历史用户颜色亮度流畅度验收记录；新tip完整define两次路由应用/NV12/HWC/解码侧健康遥测；当前向量LG P5 nativeDV、HDR10 direct、LYA HLG direct、MiNote3 SDR屏降级原始路由日志；既有owner/契约/probe测试源码（本审核未运行）。
不足：
1. 新tip实际面板显示颜色亮度未闭环。
2. LYA p84-F/G是HLG分类控制片，不替代真P8.4负向。
3. 纯HLG×convert默认成熟度仍experimental，lab严格planner显式开放；不能自动继承P8.4默认准入。
4. 普通无define冷启动、连续换源、多实例、重建未验。
5. vfps/decDrop/voDelayed不是面板呈现帧率。
6. genbump-provenance-20261010/bisect/restore-check.log:2328-2329是PREDICTION/CANDIDATE，不是ACTUAL；历史执行应引用genbump2真实日志。
7. target-peak计划写1000，但旧genbump2 logcat-bound-LOCAL-ONLY.txt:225、新p84-full-verified2.log:1202均auto；不能把1000视为共同实测配方，亦不能把它贸然列为新回归差异。

## 发布JAR差距（阻塞"宿主默认即有"交付结论）

libs/android/media_kit_libs_android_video/android/build.gradle:81-96 默认arm64下载仍是v2026.013、media-kit-d24c59905-ffmpeg-b4d2ea4-arm64-v8a-vkweak.jar，SHA 0e06f383…；其他ABI各自旧pin。本轮新向量通过mediaKitLocalArm64Jar注入JAR cd5fe26b…。源码tip可用不代表PiliPlusX默认依赖已收到。
输入向量档案：docs/plans/device-validation/MK-ROUTING-20261011/DV-BUILD-01/input-vector.md:19-24,47-53。
12030b9c39在新链经实例解析消除Vulkan1.1直接导入；旧pin vkweak不是ST/YUV后端转正证明。

## 转正前置条件清单

- [ ] DV002对应候选面板呈现验收，必要时分段像素定位；禁止沿已证伪的"SF无buffer"修复。
- [ ] 普通Session内完成精确型号/固件/API/ABI、源语义、后端能力与owner acquisition接线，不需要宿主lab define。
- [ ] 收束process-global YUV arm例外为owner/输出范围，或产品明确限制单活动转换会话并安全拒绝其他会话。
- [ ] 显式验证真实YUV输出，不以surfacetexture名替代。
- [ ] 契约文字/模型对齐已验收native FULL配方；核定target-peak等实际参数，不改批准像素/metadata配方，不重开YUV10bit或lease融合。
- [ ] 保留两次HDR尝试上限与SDR兜底，route lock不进入普通产品默认；实验单open限制不泄漏到产品UX。
- [ ] 澄清ST失败依赖归类：route deps仍沿原mediacodec/copy，而HdrVideoSession._hwdecDependency仅识别这两者；扩大默认前补ST失败/排除/重试测试。证据 hdr_video_session.dart:584-682,979-987 与 hdr_strategy_realizer.dart:299-307。
- [ ] full仅真实PQ YUV路由owned写入，失败/结束/切SDR恢复。
- [ ] YUV功能与DIAG/readback分离，产品不靠_DIAG=true运行。
- [ ] 更新、绑定正式JAR/各ABI/插件/宿主依赖，发布验收不得依赖local override。

## 最小可行路径

保留默认策略顺序和诊断route lock隔离；对精确LG固件、PQ-capable/HLG-incapable、合法HLG基层源，在普通convert候选里事务化取得完整YUV后端。用正式ST method但不强置ready，不删owner/ACK/lease。仅实际YUV PQ offscreen用owned full。以无define宿主验收后逐设备开放，不全局开启四/六个define。旧回传不需要"修true传递"，不缓存initial apply成功。

## 必需验证矩阵

设备/源：LG真P8.4、纯HLG、HDR10、SDR、P5；LYA真P8.4/HLG保持直出；现代DV设备不抢nativeDV；SDR屏不虚报HDR；非匹配LG固件拒绝私有路径。
生命周期：冷暖启动、重复open、换源、seek/EOS、pause redraw、后台前台、锁屏、旋转/全屏、Surface重建、engine detach。
并发/失败：双Player、旧generation回调、owner替换、init半失败、dataspace/GL/swap失败；ACK/lease/fence清理、撤权、有界fallback、属性恢复。
画质性能分轮：近黑/白阶/饱和色/渐变；去readback长播、热态、AV同步、资源增长。LG实际呈现帧率通道不可得时记录缺口，不能以源率/提交率替代。

## 非阻断问题

- officialBackendReady命名夸大initialized状态。
- Factory多live-view report代表视图+聚合path=none诊断粒度低；本次未证明其错误回传。
- 计划/注释/Current State与shader及输入向量漂移；整理不替代验收。
- YUV8为已批准范围，不要求重开10bit或lease融合。

## 复审触发条件

1. 设备/固件/ABI门、owner token、arm/disarm、ACK顺序有变。
2. shader range、metadata三元组、窗口标签或target-peak改变。
3. route lock、成熟度或失败预算放宽。
4. FFmpeg/mpv/libplacebo/JAR输入向量变化。
5. DV002声称关闭，或无define产品E2E成功证据出现。
6. 扩展第二设备型号或多活动转换会话。

风险评级：全局define默认化=高；跨owner/授权范围改变=高；颜色契约错误修复方向=高；旧回传缺陷假设=已证伪，不列修复；DV002=呈现验收不足，根因未定。
**最终裁决：不批准整组define全局默认化。继续推进受限、事务化、按设备/源类门控的产品后端接线。人眼通过只能关闭对应呈现项，不自动关闭全局arm、advisory owner、YUV契约代理及发布链缺口。**
