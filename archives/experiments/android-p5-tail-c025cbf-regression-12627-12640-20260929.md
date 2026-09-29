# 12627 收敛版片尾回退实机回归与 P3 生命周期补验（12627–12640，2026-09-29）

## 当前结论

- **收敛版相邻帧回退（mpv `c025cbf`）已在实机验证**：正式重建 12632 短轮 3/3 在 Glass 片尾 PTS174.958 出现 10 次 `AImageReader` 取图 `-30001` 后命中 `P5_TAIL_FALLBACK requested_pts=174.958116667 previous_pts=174.941433333 delta=0.016683333`，收敛版新条件（10 次失败 + 相邻 PTS 0–50ms，不要求 callback 计数不变）触发且 t13/t25 截图全部为正常 DV 标版（图像识别确认，无紫屏/黑屏），Back 退出 AImage 282/283/281 全对等、retired=0、无渲染错误。
- **12627 重签包全片 2 轮**：EOS 到达（`eof-reached=yes`、`AUTO_COMPLETED completed=true`）、Back 资源闭合（acquired=deleted=10461/10476、retired=0、empty_acquires=0）、无渲染错误；两轮片尾取图故障均未发生，t175/t195 为正常 DV 标版。收敛版下全片轮连续 2 轮不复现（收敛前全片轮 12576/12585/12618/12626 均 4/4 复现）。
- **seek 边界渲染错误被同一回退消除**：12639（非 transaction 默认入口 + `gpu-next`/`mediacodec`）在 seek 触发的 PTS8.008 处出现 10 次 `-30001`（12580 旧 JAR 同位置曾报 `Failed rendering frame!` 并遗留为 P3 边界问题），本轮回退触发 `requested=8.008 previous=7.991 delta=16.683ms`，**零渲染错误**；seek 8→47 正常出画、同播放器重开 2.0 秒出画、VO 停止后资源闭合（acquired=deleted=1687、retired=0、held_after=0）。t25/t43 图像识别为正常玻璃吹制画面；t13 截图为纯黑，时间线核对落在 `reopen_begin`→`reopen_playing` 之间的源重开间隙，属预期转换而非黑屏故障。
- **Mystery Box EOF（12633）**：EOS 到达（~99 秒与片长 98.944 一致）、零取图失败、零渲染错误、Back 资源闭合（5926/5926、retired=0）；t13/t60 为实际画面（威尼斯场景/舞者场景）、t110 为片尾落版 `WWW.MYSTERYBOX.US`，均图像识别确认。
- **暂停重绘（12640）**：媒体第 8 秒 `ANDROID_HDR_MEDIA_PAUSE target=8000 timePos=8.000000 pause=yes`，暂停帧 t13/t25/t50 三张截图**字节级完全一致**（同一 SHA-256），暂停保持 37 秒以上无重绘、无紫屏/残影；暂停帧内容经图像识别确认为正常玻璃吹制炉火画面（非黑/紫帧）；退出资源闭合（474/474、retired=0、empty_acquires=0）。

## 构建与路径事实

- 正式重建在 `/private/tmp/media-kit-p5-pq-product`（e0102cf 干净工作树）进行，`ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar=/private/tmp/media-kit-p5-tail-clean-12627-arm64.jar`（即 `c025cbf` 构建，JAR 内 libmpv SHA-256 `b1bcdaf2...` 与 12627 重签包内一致）、JDK17（`/opt/homebrew/opt/openjdk@17`）。
- 12628–12631 为逐项试错复原 12626 define 集的过程（缺 `AUTO_SINGLE_PLAYER`/`OPEN_ON_TAP`/`PREOPEN_FULLSCREEN`/`NAMED_LOCAL_SOURCE`/`P5_RPU_PIPELINE_BUILT` 时分别表现为不进测试页、竖屏 tap 落空、走 346MB staging 超时、P5 门禁拒绝）。12632 最终 define 集：`MEDIA_KIT_AUTO_SINGLE_PLAYER=true`、`MEDIA_KIT_ANDROID_OPEN_ON_TAP=true`、`MEDIA_KIT_ANDROID_PREOPEN_FULLSCREEN=true`、`MEDIA_KIT_ANDROID_LOCAL_SOURCE=/data/local/tmp/media-kit-p5-glassblowing2-4k5994.mp4`、`MEDIA_KIT_ANDROID_NAMED_LOCAL_SOURCE=true`、`MEDIA_KIT_ANDROID_P5_RPU_PIPELINE_BUILT=true`、`MEDIA_KIT_ANDROID_HDR_TRANSACTION=true`、`MEDIA_KIT_ANDROID_SURFACE_PRODUCER=false`、`MEDIA_KIT_ANDROID_TEXTURE_LAYOUT_SIZE=true`、`MEDIA_KIT_ANDROID_PERF_PROBE=true`、`MEDIA_KIT_ANDROID_P5_COUNTER_PROBE=true`、`MEDIA_KIT_ANDROID_DIRECT_OPEN_TRACE=true`、`MEDIA_KIT_ANDROID_PLAYING_START_SECONDS=170`。
- 12633（Mystery EOF）＝上述集合去掉起播 define、LOCAL_SOURCE 改 mystery；12639（seek/重开）为非 transaction 版本（去 `HDR_TRANSACTION`/`NAMED_LOCAL_SOURCE`，加 `MEDIA_KIT_AUTO_TEXTURE=true`、`MEDIA_KIT_ANDROID_VO=gpu-next`、`MEDIA_KIT_ANDROID_HWDEC=mediacodec`、`AUTO_SEEK_AT=8`、`AUTO_SEEK_TARGET=45`、`AUTO_REOPEN_AFTER_SEEK=true`、`VO_SUMMARY_STOP_SECONDS=32`）；12640（暂停）＝12632 集合去起播、加 `HDR_PAUSE_AT_MEDIA_SECONDS=8`。
- 各 APK SHA-256：12632 `60cdb743416ccb9e8389ef65bb22264dd85ba58c4a8f48db0c72277b47d2242f`；12633 `f2b6ac3664de8fa2b91a9e229c4010572a82eb6518594ddee2c136867736c7d1`；12639 `8ad4a2ba018c2b01ab31d8481460d652527848317900013d1c1025bb78dbad8a`；12640 `f78ee766c40f03dd8637f3cc0f566904aebc20385271ae2cd9e33bf77789f6ba`。12628–12631、12634–12638 为试错中间包（12636/12637/12638 因 vo/hwdec 未走 P5 直通路径，证据无效），APK 已清理，日志保留。
- 环境教训：一次 Gradle 冷启动构建耗时 18 分钟且期间 USB 断开；实机轮以每轮独立日志为准。磁盘在多轮构建后耗尽（最低 120Mi），清理本会话中间 APK 后恢复。

## 证据文件

- 短轮：`/private/tmp/media-kit-p5-glass-tail-12627-clean-full{,2}-*`（全片×2）、`media-kit-p5-glass-tail-12632-short{1,2,3}-*`（片尾短轮×3）
- Mystery EOF：`/private/tmp/media-kit-p5-mystery-eof-12633-*`
- seek/重开：`/private/tmp/media-kit-p5-glass-seek-reopen-12639-*`（12636/12636b/12637/12638 为路径试错轮，仅日志）
- 暂停：`/private/tmp/media-kit-p5-glass-pause-12640-*`
- 截图均由 `proxy/eo/glm-5.3-flash-free` 图像识别模型逐张判定（正常帧/紫屏/黑屏），识别结论已记录在各轮分析中。

## 尚未覆盖

- 双视图同时显示、热切源（当前目录 real.dart 候选）、直接 Engine 销毁、退出重入（跨 Activity）未在本批轮次内完成，仍归 P3 后续。
- 片尾故障根因（华为 HEVC flush 与末帧入 ImageReader 竞态）仍为事件顺序推断；收敛版回退是缓解而非根因修复，`c025cbf` 下全片轮 2 轮未复现不等于永不复现。
