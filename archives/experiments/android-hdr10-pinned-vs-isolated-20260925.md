# HDR10 Texture 直MediaCodec：固定依赖与隔离库复现（2026-09-25）

后续查得固定依赖v1.2.7构建脚本锁定mpv提交`32a164cc017acab50389f2194f720ccfd0b01a28`，该提交Reader源码上限为5，且固定JAR仓库SHA复核一致；和22→19失败模式形成强关联。未直接反汇编发布二进制，也未以仅改这一行的干净依赖完成产品回归；见`android-hdr10-reader-capacity-threshold-20260925.md`。

在maxImages=2/3同隔离库均成功后，用当前工作树重新构建官方固定arm64依赖（Gradle `default-arm64-v8a.jar`，仓库声明 SHA `13e882d96b8cd235425172b022e4a94dfcae5f07985dff85c8d648e7369fa2d1`），APK 11067 SHA `632075046e1fe65468b13575bcba417ab32c162ee73de951d163b277e2f43202`，APK内strip后libmpv SHA `77319bc63a205123b403e35088401e7da61886b78bd0a678a282876cfb9c0f66`。同机同源HDR10、`gpu-next`/Texture、默认直`hwdec=mediacodec`、最大纹理宽1440，未启用8-bit copy诊断。11067启动成功并读到软件 `yuv420p10` 预视，厂商解码器首次配置请求10/9槽被拒；重配置请求22、21、20、19槽均报`-1010`，随后`Failed to allocate output port buffers after port reconfiguration`，libmpv回退软件，测试事务报 `Expected mediacodec output, got no`。这复现11057/11058的固定依赖失败，排除仅一次偶然轮次。

同隔离库maxImages=3的11066在同源同配置下请求20/19/18槽失败，**17槽成功**，持续到视频62.762秒、VO/decoder采样掉帧0；maxImages=2的11064请求19/18失败也以17槽成功。由此可见固定依赖与隔离构建的缓冲协商要求不同；这很可能影响本机可用的17–18槽边界，但两套库有多处差异，尚不能直接判定是Reader上限、FFmpeg配置、dpb需求或其他选项造成。特别是maxImages=2并非必要：同隔离库3也成功。

后续应比对固定包和隔离库在`AImageReader_newWithUsage`、MediaCodec输出Surface/usage、FFmpeg解码器reorder/extra buffers及mpv队列设置上的**实际调用值**，而不是只按源码版本推断。可在独立探针记录Reader `maxImages`、codec `KEY_MAX_INPUT_SIZE`/output format、ACodec端口缓冲请求和当前硬件buffer格式；然后在同一库中单变量A/B。两库的opaque GPU路径仍未验证10-bit像素保真，不能因为隔离库能播放就判颜色通过。11067完整日志在 `artifacts/android-hdr10-pinned-vs-isolated-20260925/logcat-pinned-11067.txt`，11066见`artifacts/android-hdr10-reader-max3-20260925/logcat-11066.txt`。设备恢复官方10369。
