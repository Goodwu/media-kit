# P5 高端码值在 raw sampler 与 RGB10_A2 前的边界（2026-09-25）

目的：承接`android-p5-fullscale-scale-ab-20260925.md`，判断源Y=1020与1023的合并是否仅由RGB10_A2 FBO/缩放造成。复用无损256×144 P5图案；从源`dvh1`以`ffmpeg -c:v copy -tag:v hvc1`重封装，Android 10 MediaExtractor才把轨道识别为`video/hevc`。源与重封装的**312条视频包PTS和逐包SHA-256完全一致**，无重编码；重封装文件`artifacts/android-p5-float-fullscale-probe/fixture-hvc1.mp4` SHA`b9395366a99c56784531007c5f521f2724013abf6f579964511c243f9d49c075`。

独立`app_process`探针固定华为`OMX.hisi.video.decoder.hevc`→`ImageReader.PRIVATE`→同一AHB`0x325`→EGLImage→`GL_EXT_YUV_target` raw取样。在同一次`sample_texture`中分别画至`RGB10_A2`与`RGBA16F`一像素FBO，后者用`GL_FLOAT`读取，不乘`1020/1023`。探针源码`artifacts/android-p5-float-fullscale-probe/{P5CodecProbe.java,ProbeMain.java,p5_gpu_import_probe.cpp}`；两轮完整输出为`run.txt`、`run-2.txt`，结构化值见`compare.json`。首轮误用`dvh1`时MediaExtractor把轨识别为`application/octet-stream`，没有进入解码；改为同包`hvc1`后两轮成功。这个封装错误不作GPU阴性结论。

参考图案在y10的x233/234/236，Y码值分别1011/1020/1023。两轮各自的PTS0与PTS10（后者Image timestamp与输出序号240精确匹配）中，raw浮点Y均为：

| 坐标与源Y | `RGBA16F`读回Y | 未缩放`RGB10_A2`读回Y |
| --- | ---: | ---: |
| x233，1011 | 0.991210938（约1011/1020） | 1014 |
| x234，1020 | 1.0 | 1023 |
| x236，1023 | 1.0 | 1023 |

两类FBO均complete，raw路径GL error0，四张被检查的Image有相同结果。因此在**raw外部纹理取样输出或更早阶段**，本机这条PRIVATE路径已无法从返回的Y值区分1020与1023；RGB10_A2量化及后续`1020/1023`缩放不是合并的唯一原因。`RGBA16F`本身可表示大于1，但这里raw Y仍是1；不能进一步把根因断言为厂商sampler，而排除解码器/Surface内部处理。本测试是无损图案的窄范围检查，不推及所有码值/帧/设备；本机原4K50 P5素材软件解码全片分量最大≤902，此问题不解释其已见局部热点或卡顿。

实验未安装APK，也未替换应用私有原片。设备`/data/local/tmp`的本轮jar/so/样本已删除；应用仍为10369基线且无进程。主机诊断编译/重封装文件仅归档必要源码、hvc1样本、两轮输出和JSON。
