# 存活 Surface 回退候选正常路径：10455

- LYA-AL00/API29，完整 P8.4 MP4 SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`。10455 APK SHA-256 `4fdca68fc92cc71c9f2487aceb9e02d4a678eb126b459681a4b5ee61e1e252c5`，默认发布libmpv、HDR事务/PlatformView、提前停轨诊断开关。稳定外层key的测试页按A→A+B→B→A+B→B轮换，最后移除当前A、留下存活B。
- 候选控制器保留仍存活的备用Surface引用。phase4当前A `wid=10778` 在02:26:22.932停止producer、.934释放引用后，B `wid=11282`于.935请求重绑、.995完成，随后视频参数恢复MediaCodec/BT.2020/HLG。重复Destroy使B bind请求记录两次，但仅完成一次。媒体位置在phase1/2/3/4约4.871/11.378/15.115/21.454秒；系统HWC回读`BT2020_ITU_HLG`。两张间隔约5秒的系统截图分别为远景羚羊与近景野生动物，证明最终B持续出图。此轮只验证正常路径，不能据此证明失败重试安全。
- 独立V1审查未通过：若当前A的ReleaseSurface/ACK失败，异常会阻止B fallback bind且没有后续自动重试；B属性bind失败亦缺少受控恢复。这是代码阻断项，修复并复审前不能升为默认路径或宣称双视图已完成。
- 过滤日志`android-p84-dual-10455-20260927.log.gz` SHA-256 `9b56539d53d353545ab17cf57a0fa4ee7ef6ed9b5540982633acd47d32cc2e32`；截图`android-p84-dual-10455-a.png`/`-b.png` SHA-256 `fd35a055ba99b2949922d9e10b0b3147c2759265d6865e1dadfaa969d861b137` / `719bc09f4e3ae148cf448a896e16bf351423ec92c58bd9665d739308fa0dc49b`。
- 实验结束恢复原10420、自动亮度1/设置37，删除手机测试源副本与截图。
