# HDR10 PQ / SDR 灰阶输入对照

生成脚本 [generate_hdr_gray_controls.py](generate_hdr_gray_controls.py) 产生两条 1920×1080、30fps、6秒 HEVC Main10 灰阶视频，七个竖带按同一名义绝对亮度输入 0/1/10/100/203/400/1000 nit 排列。PQ 视频按 ST 2084 逆 EOTF编码 BT.2020 非恒定亮度、10-bit limited；清单另记 10-bit 量化后各带实际对应亮度。静态 MaxCLL/MaxFALL 由量化后像素推导并向上取整，分别为 1005/247 nit。SDR 阴性视频把亮度明确裁到 100 nit，再按理想显示端 2.4 幂律生成 BT.709 limited 编码；这不是 BT.709 摄像机 OETF，若用于定量亮度对照，须另行确认实际显示 EOTF。两条都用 x265 lossless；详细路径、SHA 和每带 Y' 编码见 [清单](android-hdr-gray-controls-20260924.json)。

当前生成环境为 FFmpeg/ffprobe 9.0.2、x265 4.3+1-e9b8812。已用 ffprobe 复核两条均为 Main10/yuv420p10le、180帧、6秒且色彩元数据分别为 BT.2020/PQ 和 BT.709；PQ 首帧含 mastering display 与 MaxCLL=1005/MaxFALL=247。FFmpeg 解码首帧后抽样七带中心，Y' 编码与清单逐项相等，Cb/Cr 全为512。重复运行脚本得到完全相同的清单及文件哈希；升级编码器后应以新哈希另记产物身份。

这只是**已知编码输入**，不是经仪器验证的屏幕亮度或独立 DV 颜色参考。后续设备实验需要在同一显示设置与环境光下分别播放 PQ 阳性、SDR 阴性，并将当前视频层的 buffer/dataspace、显示 HDR 状态、可见灰阶和亮度测量对应到源身份/PTS；仅看见七带或层上有 PQ 标签都不能判 HDR 激活。若无仪器，亮度数值项保持 `INCONCLUSIVE`。当前未把文件传到设备，也未运行播放器。
