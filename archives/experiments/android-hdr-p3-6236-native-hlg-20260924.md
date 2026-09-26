# P3 6236 P8.4 原生 HLG 事务实机（2026-09-24）

Huawei LYA-AL00/API29，屏幕解锁、前台。固定 P8.4 私有源 `/data/local/tmp/media-kit-p84-full.mp4` SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`。保留数据安装 `/tmp/media-kit-p84-natural-hlg-platform-transaction-6236-arm64.apk` SHA `cfda587aacc61282af210949691566dd69eb4408b3a889ad8d098d131491289e`，设备 versionCode=6236。测试后强停应用、包保留。

测试页在真实 `displayHdrTypes={2,3}`、`simulateNoHlgForP84=false` 条件选择自然 HLG 原生路线。`ANDROID_HDR_OPEN sample=dolbyVisionP84` 返回，运行中 video params 为 `mediacodec`、3840×1920、BT.2020/HLG。应用 SurfaceView 视频层 `BT2020 STD-B67 Limited`，HWC `BT2020_ITU_HLG`、DEVICE 合成、HDR metadata types=0。两张相隔约7秒的截图视频区域从林中熊画面变成摄影者画面，证明多个场景曾出现在屏幕捕获中；不证明精确帧率或人工持续流畅。一次 Home→前台后仍有完整摄影者画面及 HLG HWC 层。日志出现再次 `ANDROID_HDR_OPEN`，故该操作不能被解释为完全无重开、无回退；缺精确前后 PTS。结果对象的 `presentationVerified=false` 也未升级为真值。

本轮只证明该固定源在新版事务上能以 HLG 兼容层显示并在一次后台返回后有画面；系统播放器是否应用 RPU、mpv `mediacodec_embed` 路线是否保留或消费 RPU、独立参考色彩、面板实际 HDR 亮度、完整长播/音画及多轮生命周期均未验证。它不代替 gpu-next→PlatformView 的 T2；该路线另在 [6238](android-hdr-p3-6238-hlg-surface-20260924.md) 的 HDR dataspace 门禁失败。

原始日志 `/tmp/media-kit-p3-p84-6236-logcat.txt` SHA `fedeef61ef54c8ae2ab06ae1dddcecd4bb7ee94842c5146d4c44baaf1dda2984`，SF `/tmp/media-kit-p3-p84-6236-sf.txt` SHA `af91434579c97036f42233f21818433d153c950b5a012d6b6c078f542ae37687`；Home 返回日志/SF SHA `db3b646e43a1081222969bf0f40d811c44e7b2c3ada601ee1994572b92f3e3f9` / `a85500ce1a29d9690e6448544b12ed32c03b6aabfebbfc479e97d84c5664e1b4`。截图 `/tmp/media-kit-p3-p84-6236-{t1,t2,home-return}.png` SHA 依次为 `1cd0d851c8c6a44e297afe66a61660b9f7e0102d911fda6f6721c467b41921f1`、`37919abe686b269189d5aae469701822d31f23282e0fd5b1158bd862db3dbea8`、`4ae5766670d334eed461b59edf611771e49e11aecf6fa46b94a3f65e03061b6c`。
