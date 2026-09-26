# P8.4 原生 HLG 后台返回位置与自动恢复（2026-09-24）

固定 P8.4 源 SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`，Huawei LYA-AL00/API29，真实能力 `{2,3}`，自然 HLG PlatformView/`mediacodec_embed`、同原生 JAR SHA `e7b4cfefed60052277519a39d4834eb33d35f08342c59610279232878d1036bd`。`MEDIA_KIT_ANDROID_PERF_PROBE` 与新增生命周期位置日志均为测试开关。

## 未自动恢复的对照 8324

8323 初版诊断漏注册生命周期 observer，只能证明播放中的 PERF 到90秒实时推进，不能计后台对照；8324 补全注册与注销后重建。8324 APK `/tmp/media-kit-p84-native-lifecycle-6324-arm64.apk` SHA-256 `eda6af6a6b5e5fdb402f4cda4372ff451ec321e214dee721979e2d46926cf83e`。打开后 `t60 time-pos=8.808800`、VO/decoder掉帧0。按 Home 前 inactive 捕获位置32.198833、playing=true；后台时停在33.309370；返回 resumed 缓存位置33.309秒、playing=false。`t90` 与 `t120` 均为 `time-pos=33.333300 pause=yes`，没有自动继续，也没有跳回0。日志仅一次 `ANDROID_HDR_OPEN`。返回前/后的截图 SHA-256 `b4a45a1220c15be0a751e5a665b3469eb754317f041bdf2007ff376c5a0516d9` / `c7a06fed613faf929ec2a776feb549d4148862d0b37b1db21dd0cc1f9f09b1b`；静止画面可见不代表播放。完整日志 `/tmp/media-kit-p84-native-8324-home-logcat.txt` SHA-256 `2a72bb6494dff517d5c4b3ebbf969610a545c04c3c63164d38011903d53cbed4`。

## 按原会话等待新 Surface 后恢复的 8325

新增默认关闭 `MEDIA_KIT_ANDROID_HDR_AUTO_RESUME_PROBE`：从 resumed→inactive 捕获原先的 `playing` 和 HDR session；回到 resumed 时仅在同一 session 仍有效的情况下等待当前 PlatformView 输出绑定，再通过 coordinator 的 session 队列调用 `player.play()`。用户原先暂停的会话不触发。8325 APK `/tmp/media-kit-p84-native-resume-6325-arm64.apk` SHA-256 `8edac91edfc7cae9f86378a39c73eb19c4627951e3127927def8c989ecd2f452`，设备versionCode8325。后台前 `t150 time-pos=98.731967 pause=no`；Home 时捕获 `position=103770ms`、playing=true，返回 `resumed` 时缓存104940ms/playing=false，输出绑定后日志 `ANDROID_HDR_AUTO_RESUME played position=104939`。后续 `t180 time-pos=124.724600 pause=no`、decoder掉帧0、VO累计29；一次后台切换期间掉帧明显，不能宣称无可见停顿或连续帧率达标。没有第二次 `ANDROID_HDR_OPEN`，但单轮不能证明所有重建路径都不重开。两张相隔6秒的截图视频区域从车内摄影师变成狐狸，SHA-256 `afb8165db17a2427ea62c49f3f3012cebf61f256fe528bcd175f0a2efddc5f25` / `ef4cb9e45a6d118e58e254c783a0bdecabe1ac079f696581f773909f0b1a82cc`；SF/HWC 为 `BT2020_ITU_HLG`，SF SHA-256 `25806856b56e392d23c22143ba6ac3e09c67407b2a2e5fcd1cfcf5de9daeab76`。完整日志 `/tmp/media-kit-p84-native-8325-home-logcat.txt` SHA-256 `398cfdc90ef4436bb953cda955675f1d5ef35a33c692a99e9281db442886a71e`。已强停应用、8325包保留，EGL探针属性0。

截至8325的结论：P8.4 原生 HLG 的默认后台返回当前会保持位置却暂停；默认关闭的会话限定自动恢复候选在这次真机操作中恢复推进、保住HLG层。尚需重复Home、多次Surface重建、用户原先暂停不自动播放、seek/切源、长时与真人可见停顿验收；本轮没有证明光学HDR激活或DV RPU处理。下节补原先暂停的阴性对照。

## 8326 原先暂停的阴性对照

先尝试在8325视频控件上点暂停，但Home前生命周期日志仍为`playing=true`，该轮不能作为原先暂停证据。另构建8326，在固定源事务打开5秒后由默认关闭的`MEDIA_KIT_ANDROID_HDR_AUTO_PAUSE_PROBE_SECONDS=5`明确执行`player.pause()`；保留相同会话限定自动恢复候选。APK `/tmp/media-kit-p84-paused-intent-6326-arm64.apk` SHA-256 `8cf06a8ffcb44feabdaa39113dd69e4d39c93652a50d63338adbd273fc92d3f7`，设备versionCode8326，原生JAR与前轮相同。

干净轮日志：`ANDROID_HDR_AUTO_PAUSE position=4871 pause=yes`，t60 `time-pos=4.871533 pause=yes`；Home触发时捕获`capturedPlaying=false position=4871`，返回resumed缓存约5.000秒、playing=false，t90 `time-pos=5.005000 pause=yes`。未出现`ANDROID_HDR_AUTO_RESUME played`，证明此轮原先暂停状态没有被候选逻辑擅自播放；4.871→5.005秒属于mpv缓存/帧时刻差异，不是连续推进。完整日志 `/tmp/media-kit-p84-8326-paused-home-logcat.txt` SHA-256 `e5292041eefd110a3eb794b35c8e1ef7631a30cafe7035e60a9056aed17ddae5`。Dart目标analyze仅既有`use_super_parameters` info；应用已强停，8326包保留。仍缺重复Home和切源/销毁竞态回归。

## 8325 同会话连续两次 Home→返回

以 `adb install -r -d` 保留数据从8326降装回相同8325 APK，设备versionCode确认8325；第一次不带`-d`的安装被系统以版本降级拒绝，没有运行，不计实验。干净轮再次打开固定 P8.4 源，`t60 time-pos=10.443767`，仅一次 `ANDROID_HDR_OPEN`。第一次 Home 时捕获playing=true/31.297秒，返回约32.480秒时执行 `played`，t90进至36.770067秒、`pause=no`、VO累计掉11帧。第二次 Home 时捕获playing=true/49.449秒，返回约50.640秒时执行`played`，t120进至63.530133秒、`pause=no`、VO累计掉38帧。两次均未重开媒体或跳回0；这是同一设备/同一会话的两次重复，不等于所有切源、销毁或长时场景通过。第二次返回后 SF/HWC 层仍为 `BT2020_ITU_HLG`；完整日志 `/tmp/media-kit-p84-8325-repeat-two-logcat.txt` SHA-256 `cd59d96cb0076ef7126f88edf2b2605853b1088cae619a79a50ba06762129a01`，SF `/tmp/media-kit-p84-8325-repeat-sf.txt` SHA-256 `120dd731fbd5b542175ef28f852c830cbecad4a4cfb0561fc6726dad95c83ac6`。已强停应用、8325包保留。累计掉帧增加说明仍需视觉停顿和恢复时延验收。

## 8327 固定 HDR10 原生路线交叉验证

保持8325相同的默认关闭自动恢复/生命周期位置/低频PERF开关及原生JAR，只将固定输入换成HDR10 SHA-256 `e4f869b140e3ef322b7fc63fefe015593708f6443fc79060fa3e7f2234816937`。APK `/tmp/media-kit-hdr10-native-resume-6327-arm64.apk` SHA-256 `c2d902c2d47379b1ddeaf6b529be500c01aaa9dab0f1c971cfd26cef164f78ab`，设备versionCode8327。事务打开后t60位置36.970秒/`pause=no`/VO掉0；Home时捕获58.558秒/playing=true，返回后于59.740秒执行`played`，t90进至63.763秒/`pause=no`，VO累计掉32帧。日志只有一次`ANDROID_HDR_OPEN sample=hdr10`。返回后 SF/HWC 层 `BT2020_ITU_PQ`、HDR metadata types=3；相隔约5秒两张截图视频场景从林中帐篷内视角变为海边帐篷，证明画面继续变化。日志 `/tmp/media-kit-hdr10-8327-home-logcat.txt` SHA-256 `b7bef6e2c83b1c54803dea8ca1c591ee720faab18266b406de6c9f43a4d02471`，SF `/tmp/media-kit-hdr10-8327-home-sf.txt` SHA-256 `e33ce9ed03d20657882435d03a05604b93c016454a08188dd6d3ac0ecef5366d`，截图 SHA-256 `b64655dd3b67122ad1ba57f56be1b6ab97599e9fdedb5f8c1efdf8f04676c8af` / `3a29a84b3fb0fab22b060780f022ed4ca22023c560743645909aa1ba0b1e5731`。应用强停、8327包保留。单轮验证不覆盖HDR10重复后台、原先暂停、严格元数据或光学HDR；掉帧仍需真人可见停顿判断。
