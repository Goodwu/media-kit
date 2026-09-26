# P5 解析后 Dolby Vision 映射数据跨端核对（2026-09-24）

**截图目标口径纠正**：下文所引原尺寸MAE7.52来自主机强制sRGB的`video`截图，非手机BT.1886同目标；后补BT.1886 `window`截图为MAE7.41/最大35。RPU及映射数据哈希相同的结论不受影响，见`android-p5-screenshot-target-correction-20260924.md`。

背景：原尺寸PTS10 RPU后九点手机/主机仍有平均7.52、最大35个8-bit级差异，缩放不是主因；两端原始RPU缓冲同为206字节/FNV-1a `907c8b42`，但尚未排除解析映射不同。

隔离mpv在`video/mp_image.c`针对帧时间戳500（本片PTS10）对`AV_FRAME_DATA_DOVI_METADATA`调用正常的`pl_map_avdovi_metadata`，将`struct pl_dovi_metadata`缓冲改为零初始化后对完整结构体2652字节做FNV-1a哈希，记录映射后色彩系统/色域/传递函数/源峰值。主机独立FFmpeg顺序解码同源PTS10，使用Homebrew libplacebo7.360.1同一API并对零初始化结构体做同样哈希；手机isolated libplacebo7.365.0。两版本该结构布局经头文件核对一致，哈希包含零初始化的未用字段/填充，故此比较仅约束该映射结构，不表示整个渲染配置相同。

主机输出：`pts=10.000000000 rpu_size=206 fnv1a=907c8b42`；`mapped_size=2652 mapped_fnv1a=56b1ba4e repr=8 prim=6 trc=12 max_luma=1000.606506`。手机8365日志：`pts=500 size=2652 fnv1a=56b1ba4e repr=8 prim=6 trc=12 max_luma=1000.606506`。这排除同帧在两端进入渲染器前的**该解析映射结构不同**作为九点色差原因；不排除其后的libplacebo渲染实现、目标203 nits与手机未显式峰值的内部处理、输出格式/GPU等差异。

主机程序`/tmp/media-kit-p5-host-dovi-mapped.c` SHA-256 `fac244e8734ea4fd280b0d4b7bc3465f13e31df74b4bab03211da55f818fdf6e`，用`pkg-config --cflags --libs libavformat libavcodec libavutil libplacebo`编译。手机8365 APK`/tmp/media-kit-p5-dovi-mapped-8365.apk` SHA-256 `7fb349832c5d70028f869104a94c1b594f1e54a4eda7092d775f0c6a3b066f11`，日志`/tmp/media-kit-p5-dovi-mapped-8365-logcat.txt` SHA-256 `d20d9fa39b249e2765337ecc4f2571f0729cacaf2c87fc177989a3ac41d9205d`，整合mpv补丁`android-p5-dovi-mapped-8365-integrated-mpv-20260924.patch` SHA-256 `caaa8f162c3a4ca9d34cd8c06d5651e8e4ffba72384640782cf4ce98bd86635f`。arm64构建、APK签名/验签、隔离mpv diff-check通过。实验后目标机强停，14项P5诊断属性全0，无进程；保留8365包。此诊断不作性能、PQ HDR或可见色彩验收。

下一步控制目标峰值/输出量化与libplacebo版本差，优先比较相同渲染库版本的同目标离屏结果，而非继续假设原始RPU或解析数据不同。
