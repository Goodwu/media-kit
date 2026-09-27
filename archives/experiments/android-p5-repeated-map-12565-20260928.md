# P5 AImageReader 同帧重复映射修复短轮（12565）

在12563候选的时间线探针中，PTS0首次导入成功后两次映射的 `mp_image src=0x7c021db650`、`MediaCodecBuffer=0x7c0132cf20` 完全相同；`av_mediacodec_release_buffer` 再次返回0，但无新callback，20次AImage获取均为`-30001`。因此该问题是重复映射已释放的同一codec帧，非1×1布局或解码无帧。

mpv候选修订：退休项持有源帧引用；在回收前按codec buffer身份和PTS找到同一帧，把仍持有的AImage/EGLImage/外部纹理与wrapped texture取回复用。旧fence删除，新一次unmap按原流程创建fence并退休；不同帧继续按原规则回收。arm64重新编译链接通过。自建JAR SHA-256 `c98d05d30b799c9429c3d4a366f026822a67a3e4a077ecc987158ae99fb8252b`，Glass短轮APK SHA-256 `ca40dd03cad68986e793daafda60e4ecb341f59afafb3924d909d5438d55ac01`。

Glass预建横屏全屏2560×1440短播约9秒，截图有真实画面，VO1、decoder0。正常按返回后 `P5_RETIRE_FINAL maps=590 reaped=588 held_after=0`、`P5_IMAGE_FINAL acquired=588 deleted=588 retired=0 empty_acquires=0`，Player dispose完成；全量日志中 `acquireLatestImage failed` 和 `Failed rendering frame!` 均为0。maps比acquired多2，吻合两次复用；这只是短轮证据，仍须全片/重入/seek及非P5回退验证。测试结束恢复原12492、全部相关属性0、自动亮度和熄屏。

证据在 `artifacts/android-p5-repeated-map-12565/`：原身份证明日志、修复短轮日志、截图及修订补丁。
