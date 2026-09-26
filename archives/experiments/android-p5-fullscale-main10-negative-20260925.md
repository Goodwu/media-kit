# 满码合并的非DV Main10 对照（2026-09-25）

承接`android-p5-fullscale-float-sampler-20260925.md`：要判断raw外部纹理中源Y=1020/1023合并是否必须由P5/RPU触发，取用户无损P5测试包的**编码前第0帧YUV420P10**，原样重复24帧，以libx265 `lossless=1`编码为普通HEVC Main10/`hvc1`，不写DV配置或RPU。生成文件`artifacts/android-p5-float-fullscale-probe/main10-no-dv-lossless.mp4` SHA-256`98a8e2c63fee029c32f1ddd5473414ef47f23cab5ea2e5981cbb0d770eb01bc5`，256×144/24fps/24帧。FFmpeg软件解码得到的全24帧YUV与编码前24帧文件逐字节`cmp`相同；因此x233/234/236、y10的源Y仍为1011/1020/1023。

复用上轮独立Java/NDK探针，同一`OMX.hisi.video.decoder.hevc`、`ImageReader.PRIVATE`、GPU sampled、EGLImage、`GL_EXT_YUV_target`、`RGB10_A2`和`RGBA16F`一像素FBO；只替换输入文件，两轮`app_process`输出分别为`artifacts/android-p5-float-fullscale-probe/main10-no-dv-run.txt`、`main10-no-dv-run-2.txt`，结构化结果`main10-no-dv-compare.json`。两轮实际MediaCodec输出`color-format=805 (0x325)`、AHB`0x325`，首张Image timestamp0；float FBO complete，raw采样GL error0。

| y10位置 | 编码前/软件解码Y | 两轮raw RGBA16F Y | 两轮未缩放RGB10_A2 Y |
| --- | ---: | ---: | ---: |
| x233 | 1011 | 0.991210938 | 1014 |
| x234 | 1020 | 1.0 | 1023 |
| x236 | 1023 | 1.0 | 1023 |

与P5样本的相同坐标结果一致，故**DV配置/RPU不是本机这条10-bit PRIVATE/raw GPU路径满码合并的必要条件**；问题归属可收敛到通用Main10解码→Surface/外部YUV取样链，仍不能单独判定是解码、Surface内部处理还是sampler的归一化/钳位。该结论仅限该设备和这些码值/坐标；不证明所有Main10或P5图像会受影响。当前固定4K50 P5影片全片软件解码各分量最大≤902，因此此高端合并仍不是该片局部热点或卡顿的解释。

两轮探针分别读到20/19张硬解输出，少于输入24帧；本实验只使用首张timestamp=0且所测内容符合已知输入的Image判断满码，不以该短片的尾帧数解释既有P5 EOS问题。实验未安装APK、未改应用媒体；手机仍为10369基线且无应用进程，设备和主机本轮临时编译文件已清理。
