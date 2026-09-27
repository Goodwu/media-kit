# P5 Glass 同进程冷开/重开阶段对照，12498

## Current State

2026-09-27，LYA-AL00/API29，指定 Glass P5 本地源，12498 arm64诊断APK SHA-256 `0e726a5a9a66d974d18477f7f23b03fa09bfb5bc2cda65b1c713652f2f839974`；和12497同代码/JAR/固定已验证本地源、80ms PixelCopy，版本号不同。同进程先点击打开，约7秒后再次点击同一源。P5 raw/direct/RPU/retire/VO trace属性1/1/2/1/1，正常自动亮度，竖屏测试页。结束恢复原12492、五属性0、自动亮度1、屏幕OFF。

| 阶段 | 首开 epoch / 相对 media_opened | 同进程重开 epoch / 相对 media_opened |
| --- | ---: | ---: |
| `media_opened` | 1790475965.528 / 0 | 1790475972.892 / 0 |
| HEVC缺参考POC | 5966.232 / +0.704s，共17行 | 本次重开窗口未见 |
| OMX HEVC组件开始创建 | 5966.502 / +0.974s | 5972.920 / +0.028s |
| 输出端口重新启用 | 5966.865 / +1.337s | 5973.122 / +0.230s |
| 首个有效mix/AImage可见日志 | mix 5967.166、AImage 5967.172 / +1.638/+1.644s | 至迟5973.830已有mix PTS0.634 / ≤+0.938s；首个AImage时刻未记录 |

同进程重开仍新建MediaCodec组件，却明显缩短了`media_opened→组件创建`阶段。该对照只有各一轮，且解码/缓存/线程/OS状态不同，不能声称已确定优化点或POC因果。重开时 PixelCopy 启动后的首样本约55ms就有上一段播放残留画面，**不能作为新播放首帧时间**；需要先识别或清空旧帧，再测重开的实际新帧。

另做一个属性对照：同12498冷进程仅将 `debug.media_kit.p5_rpu_probe` 从2改成0，测试入口在约209ms以 `P5 RPU attachment and raw YUV pipeline are not enabled` 拒绝打开。因此它不是有效的RPU性能A/B，不推断其对POC或延迟的影响。无需再以同配置重复。

原始日志 `artifacts/android-firstframe-warm-reopen-12498/two-opens.log.gz` SHA-256 `c0be8b81bb9d8888a9fa0d77f7dd309157759c9e93a3dbbab2cf889b4ec7c2d4`、`rpu0-cold.log.gz` SHA-256 `51372fe73efeb1fade307972bb99db7a908c2df470356c1ee3df8e3b7b30eb04`。下一步应对首开`media_opened→MediaCodec创建`约0.97秒增加可归因的demux/FFmpeg/视频链事件，并分别测产品正常路径与同进程重开；保留画质/RPU门槛，避免通过关闭必要处理取得虚假的首帧收益。
