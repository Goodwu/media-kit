## [DEVICE] DV004 诊断 critical reviewer 终审：REQUEST_CHANGES（部分准确，需补证后定案）/ MK-ROUTING-20261011

应要求，critical reviewer 对 DV004 根因结论（6125013567）完成只读终审。**总体判定：部分准确；根因定案与修复方案 i/ii 均暂不批准。** 全文归档 PR#5 分支（dv004-critical-review.md，随附）。

### 被更正的要点（我方登记错误，以此为准）

1. **比较层次**：抛出的是同次 gather **跨轮 observed map 比对**（"Observed decoder changed"），非"双读竞态"（单轮 A/B 另有 "Decoder endpoint changed"）；跨轮**空→非空本就放行**——故方案 ii（排除空→值）不成立。
2. **SDR 对照误标**：对照实际为 quality=64/**720P** avc（非 480P），且**通过了 Session 复核**（sdrDirect verified）——对照有效但混淆变量多（内容/CDN/编码 profile/初始颜色 trc2prim2range0 vs trc1prim1range1），"4K/HDR 协商慢"未定案。
3. **时序数字撤回**：455ms/200ms 未绑定属性变更；失败传播前 coordinator stop/reset 的 flush 不能反推为原因；音频间隔实为 ~21ms。
4. **引入史**：复核逻辑为 8b98c67a 引入（非 d9163940 新增），d9163940 为候选包含。

### 更具体的候选机制（reviewer 源码发现，优于我原假设）

mpv 首帧前写**逻辑 decoder 名**（f_decoder_wrapper.c:452-463），首个成功解码帧后以实际 AVCodec 名**改写** decoder/decoder-desc（vd_lavc.c:1257-1274 → av_common.c:449-457；vd_lavc.c:646-650 明确允许二者不同）——`h264 → h264_mediacodec` 这类非空→非空变化**无需任何真实解码器切换**即可触发跨轮拒绝。但实际新旧值序列未记录，不能终定唯一根因。

### 因果链现状（收紧后口径）

- 120-AVC 普通解码复核失败：已复现、已绑定（final-repro.log）。
- 126 HEVC 是否进入过播放器并同因失败：**未验证**（日志仅见 AVC 实例；菜单选中/嗅探成功不等于实际 open 绑定）。
- DV003 菜单修复独立有效；126 播放级验收未完成，是否 DV004 同因待补证。

### 修复方向终审

- 方案 i（稳定窗口）：只能作有界重采样策略，不能证明"不漏真切换"（首帧后改名、慢网络放大反例）。
- 方案 ii（排除补全）：不成立（已知路径是非空→非空）。
- **第三方向（reviewer 建议）**：区分"初始化事实建立"（等首帧 ready 后完整一致事实，区分逻辑名与实际 avctx 名）与"已建立事实失效"（以同代次稳定终值 + plan 履行校验对比）；若要求"任何真切换必捕获"，须引入 native decoder generation/生命周期证据——**此为用户决策点**。
- 既有 hdr_decoder_review 测试断言（A/B 失败、首帧等待、跨轮变化失败、超时/epoch/superseded 拒绝）不得整体翻转；新修复需按细分场景补测。

### 补证清单（实施修复前必须）

1. gather 抛出点（cleanup 前）记录每轮四项 identity A/B 值 + 缺失事实项 + 代次/时间戳（临时诊断，库文件，将申请认领）；
2. native 侧 decoder 生命周期可见日志（Selected decoder/underlying AVCodec/首帧/fallback/MediaCodec 创建释放）；
3. 产物来源绑定核验（APK/libmpv/FFmpeg vs 源码）；
4. 控制变量矩阵（冷/热、本地/网络、720P/4K SDR、实际 126 HEVC）；
5. 拿到实际属性序列后再定修法，实机验收以可见画面+持续播放为准。

### 决策点（请用户确认）

1. 是否按补证清单先行（临时诊断打点进库文件，CORE 认领申请）；
2. 验收语义选择：只验"最终 plan 履行"（实现较简）vs "任何真实切换均捕获"（需 native generation 证据，成本高）。
