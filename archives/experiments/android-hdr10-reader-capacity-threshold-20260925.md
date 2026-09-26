# HDR10 Texture Reader 容量阈值（2026-09-25）

**上游来源补核：**固定依赖JAR的仓库SHA已核为`13e882d96b8cd235425172b022e4a94dfcae5f07985dff85c8d648e7369fa2d1`。其[v1.2.7构建脚本](https://github.com/Predidit/libmpv-android-video-build/blob/v1.2.7/buildscripts/include/depinfo.sh)固定mpv提交`32a164cc017acab50389f2194f720ccfd0b01a28`；该[提交源码](https://github.com/mpv-player/mpv/blob/32a164cc017acab50389f2194f720ccfd0b01a28/video/out/hwdec/hwdec_aimagereader.c)的`AImageReader_newWithUsage`参数确为5，和固定包22→19缓冲失败相符。未对发布二进制做反汇编直接读取该常量；源码和运行模式已形成强关联。最小上游源码补丁保留在`android-hdr-reader-max3-upstream.patch`，并通过该提交索引上的`git apply --cached --check`；尚未单独用只有此补丁的干净依赖重建/验机。

固定目标机 LYA-AL00、完整HDR10 3840×1920/29.97源、当前测试树`gpu-next`→Texture/直`mediacodec`/输出最大宽1440。使用同一隔离mpv/FFmpeg Android构建，只修改 `AImageReader_newWithUsage(..., maxImages=N)` 中的N。2、3轮已记录在 `android-aimagereader-maximages-ab-20260925.md`；本轮新增4和5，均由同一构建目录单文件重编+重链，APK仅因build number/原生库身份变化。

| maxImages | APK / libmpv SHA-256 | 厂商重配置请求及结果 |
| ---: | --- | --- |
| 2 | 11064 `6408fa79…` / `23bd9a3c…` | 19、18槽被`-1010`拒；17槽成功，直解播放到视频约93秒 |
| 3 | 11066 `11654e25…` / `dfd5a97d…` | 20、19、18槽被拒；17槽成功，播放到约63秒 |
| 4 | 11069 `21f328b5b9dba2530fee22e63a9af0cbaaf791d5d814d07a8fae4650f7a383cf` / `ef7af40c7600f4e9ed3058c2a3463924cd7f1ad42a3cca5f265f6d2b9665f23f` | 21、20、19、18槽全被拒；`Failed to allocate output port buffers`、回退软件、事务失败 |
| 5 | 11068 `636e16f9f4800070fad18b979bac71d61d85f5a1568d5cb4942074949ba9049d` / `8611c54ad01fe8a4d4455d3c736daf374a1b80f9e27b11fbead466e86211ec61` | 22、21、20、19槽全被拒；同样失败 |

同隔离库下每增1个Reader可持图，ACodec最低请求也增1；本机该素材/配置的可分配上限在17，故**maxImages≤3才在所测轮次中通过端口门槛**。2/3仍各有一次首帧`acquireLatestImage=-30001`，尚不能以降低容量判生命周期可靠。11067仓库固定依赖同样请求22→19并失败，模式与本隔离库5相同，**提示**其Reader持图上限或等效缓冲开销可能为5；尚未直接证明固定二进制里具体`maxImages`常量，不能写成既定事实。隔离库还包含前期其他修改；要给固定依赖做最小修复，需取得/核实该包对应源码或在创建Reader处加入运行时参数日志，再在同一源版本下改到3并重测。不能直接用这个含大量实验差异的隔离库替换产品依赖。

此阈值只解决解码器能否启动，不证明Opaque Surface→GPU的10-bit采样、SDR/HDR颜色、可见首帧/长稳。原始日志分别在 `artifacts/android-hdr10-reader-max2-20260925/`、`artifacts/android-hdr10-reader-max3-20260925/`、`artifacts/android-hdr10-reader-max4-20260925/`、`artifacts/android-hdr10-reader-max5-20260925/`。实验后隔离源码和libmpv重建回maxImages=3，设备恢复官方10369。
