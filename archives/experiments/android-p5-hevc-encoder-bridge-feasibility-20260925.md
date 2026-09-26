# P5 GPU→HEVC编码→原生HDR Surface候选能力核查（2026-09-25）

## 结论

目标机 LYA-AL00 / Android API29 / build `HUAWEI/LYA-AL00/HWLYA:10/HUAWEILYA-AL00/10.1.0.163C00:user/release-keys` 的公开 `MediaCodecList.ALL_CODECS` 只报告一个硬件 HEVC 编码器 `OMX.hisi.video.encoder.hevc`；其全部 profile 项均为值 `1`（Android `HEVCProfileMain`），未报告值 `2`（`HEVCProfileMain10`）或 HDR10 Main10 profile。软件 `c2.android.hevc.encoder` 只报告 Main(1)/MainStill(4)，也未报告 Main10。因而通过公开 MediaCodec 能力，**没有可验证的10-bit HEVC编码路径**把GPU转换后的P5帧重新编码并送到已有原生HDR解码Surface。不能用只声明8-bit Main的转码桥替代计划要求的P5 10-bit精度与颜色正确性；它会新增一次有损编码和延迟，当前不列为正确实现候选。这是能力声明阴性，未试运行编码器，不排除未公开的厂商私有能力。

硬编的 `areSizeAndRateSupported` 对3840×2160@50返回false、@30返回true，1920×1080@50/60返回true。1440×810@50返回false而1440×812@50返回true（XML标注4×4对齐），因此仅尺寸修正可解决这一项，**不能解决Main10缺失**。4K50输入即使降最终编码尺寸也会增加完整GPU→编码→解码链成本，不符合已有原生SDR/1440无额外压缩路线的画质边界。`/vendor/etc/media_codecs.xml` 同时为该编码器标注3840×2160@30与1920×1080@60性能点，和运行时结果方向一致；XML未列profile，最终profile结论以运行时API为准。

## 可复核证据

- 隔离Java探针 `artifacts/android-p5-hevc-encoder-probe/CodecProbe.java` 直接枚举 `MediaCodecList.ALL_CODECS` 中HEVC编码器的 `isHardwareAccelerated`、`profileLevels`、`colorFormats` 和给定尺寸速率能力；用本机JDK17/android-35.jar/d8 `--min-api 29` 打包为 `codec-probe.jar`，通过设备 `app_process` 运行，无需修改或安装项目APK。
- 同目录 `result.txt` SHA-256 `1d8b9a53fc672bb48fee95ca2abc6423d772ecbc1f18e45459c043bd55ddeb1d`；`CodecProbe.java` SHA `cb89a29cb7b94e9b85ab4d983163b6e8b29d725019ce8751380534cf794dd5fa`，探针JAR SHA `8a52e639a80ca437fe0e6e5745a89ade141cff2ee1014996c4a50685f494308c`，设备vendor XML SHA `2d5c7d7939d2876e624c12ae24b3626d339095c84274550249d97616299eadb1`。
- Android SDK常量（本机android-35.jar `javap -constants`）：`HEVCProfileMain=1`、`HEVCProfileMain10=2`、`HEVCProfileMain10HDR10=4096`、`HEVCProfileMain10HDR10Plus=8192`、`HEVCProfileMainStill=4`。探针输出硬编的profile从头到尾都是1，软件只有1与4。
- 结束后设备探针JAR已删除，项目包仍为versionCode10369、应用未运行；本次未更改产品源码。
