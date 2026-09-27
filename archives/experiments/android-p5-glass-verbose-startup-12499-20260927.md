# P5 Glass 首开详细日志与阶段拆分，12499

## Current State

2026-09-27，LYA-AL00/API29，指定Glass P5本地源、竖屏测试页。12499 arm64诊断APK SHA-256 `585028c9b39fea77b834473a1dd46c089f2ff60b2e97c99350b4a2ed8016fa86`；相对12498只开启测试页 `MEDIA_KIT_ANDROID_VERBOSE_LOG=true`。P5 raw/direct/RPU/retire属性1/1/2/1，VO限量探针关闭；一次新进程冷开。结束强停并恢复原12492、五属性0、自动亮度1、屏幕OFF。

| 从点击回调内PixelCopy开始计 | 12499本轮 | 12498非详细日志首开 |
| --- | ---: | ---: |
| `media_opened` | 0.301 s | 0.341 s |
| OMX HEVC组件开始创建 | 1.280 s；距`media_opened`0.979 s | 1.315 s；距`media_opened`0.974 s |
| 首个AImage | 1.992 s；距组件创建0.712 s | 1.985 s；距组件创建0.670 s |
| 固定区域首次非零像素 | 4.215 s | 4.219 s |
| 固定区域超过旧`spread>10`阈值 | 4.445 s | 4.445 s |

两个连续冷进程在这些关键时点接近，但详细日志仍有扰动，不代表产品时延或物理屏幕。12498可加总为：点击回调→`media_opened`0.341秒；打开返回→OMX创建0.974秒；OMX创建→首个AImage0.670秒；AImage→固定区域首次非零2.234秒（包含片源黑场）。该Glass片源媒体0–约2.05秒本身为黑，不能把最后2.234秒全算作播放器等待。12498在媒体PTS2.102实际VO `queue`约4.112秒，固定区域首次非零约4.219秒；该107毫秒差包含PixelCopy采样间隔与输出缓冲，不是纯GPU耗时。

12499 mpv详细日志的**事件顺序**暴露一个可验证的优化方向：第一次视频解码器尝试 `hevc_mediacodec-mediacodec` 时报告 `Could not create device`，退回9线程软件HEVC并出现 `VO: [null]`；稍后再次打开解码器，出现 `Using underlying hw-decoder 'hevc_mediacodec'`、`Using hardware decoding (mediacodec)`及 `VO: [gpu-next]`。当前测试页已在`media_opened`之前等待输出绑定，故还需核对mpv VO/硬解设备可用性和重配触发点，不能仅据日志断定绑定代码顺序是唯一根因。若能避免启动时4K软件解码再切硬解，`media_opened→OMX创建`约0.97秒是优先候选；须保留P5 RPU、画质和退出/重入门槛。

**mpv消息经Dart `player.stream.log`异步打印，logcat时戳不是原生日志发生时戳。** 本轮17条HEVC缺参考POC到logcat时已在OMX创建及首个AImage之后；旧轮中“POC行早于OMX创建”的时间顺序不可用来证明实际发生顺序或因果。系统`ACodec`/本地AImage日志与Dart阶段日志仍可用于阶段粗分；更细归因需原生同单调时钟探针。文件顶层盒从`ftyp`偏移0、`moov`偏移28起，后续为多个`moof/mdat`，不是尾置`moov`导致的简单faststart问题。

原始日志 `artifacts/android-firstframe-verbose-12499/cold-verbose.log.gz` SHA-256 `4bc144bf1ecf03f537a10691fff290bc701faa3aa76a125a5c07e24fabfcef84`。固定文件预验证仅是诊断钩子；以上均非正常产品路径、真全屏或物理屏幕验收。2秒目标尚未通过。
