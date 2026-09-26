# Android 10 HDR Surface dataspace 门禁源码定位（2026-09-24）

目标机实测：应用自建 SurfaceView 的 `ANativeWindow_setBuffersDataSpace` 对 PQ full、PQ limited、HLG 均返回 `-22`，sRGB 成功；系统播放器与本应用 MediaCodec 直出视频层却能呈现 PQ/HLG。见 P2/P3 各真机实验记录。

在 Android 开源实现的 [`ANativeWindow.cpp`](https://android.googlesource.com/platform/frameworks/native/+/85b74b7e07/libs/nativewindow/ANativeWindow.cpp) 中，NDK setter 在调用底层 `native_window_set_buffers_data_space` **之前**先运行 `isDataSpaceValid(window, dataSpace)`，不通过即返回 `-EINVAL`。该实现的 PQ 分支查询 window 的 HDR support；sRGB 直接允许；switch 默认拒绝其他值。旧实现的 [`system/window.h`](https://android.googlesource.com/platform/frameworks/native/+/a9d88cd6082463a3d06ff55ee57ff0fdb3649530/libs/nativewindow/include/system/window.h) 把该支持查询定义为内部 `NATIVE_WINDOW_GET_HDR_SUPPORT=29`。因此，当前 `-22` **可能**来自 NDK 前置校验而非 gralloc、像素格式或底层 consumer 拒绝；但目标机是厂商 Android 10，尚未从其 `libnativewindow.so` 或同一 Surface 的支持查询证实具体分支，不能把此推断当已定位根因。

尝试在现有 JNI 桥以 `window->perform(...,29,...)` 只读查询，NDK 28 把 `ANativeWindow` 声明为不透明类型，编译报 `member access into incomplete type 'ANativeWindow'`。该尝试已撤销，未构建或安装候选包；没有调用私有 ABI。不能为了探针跳过支持检查或强贴 HDR 标签。

下一项可验证的替代接口是 EGL window colorspace。AOSP [`eglApi.cpp`](https://android.googlesource.com/platform/frameworks/native/+/d3138a4e341c22690e9b34546504ff17d4e94151/opengl/libs/EGL/eglApi.cpp) 的 `eglCreateWindowSurface` 路径将 colorspace 转为 dataspace，直接调用内部 `native_window_set_buffers_data_space`，与 NDK 包装器的前置校验不同。应先隔离做同 Surface 的 `EGL_GL_COLORSPACE_BT2020_PQ_EXT` 创建/销毁探针，记录 EGL extension、config、错误码和实际 dataspace；即便创建成功，也须后续有真实 10-bit GPU buffer、SF/HWC PQ 层及参考色彩证据才算 HDR 输出。此处仅提出有源码依据的下一个实验，未声明 EGL 路径在目标机可用。

## 8322 同 Surface EGL PQ 探针

JNI 桥增加默认关闭的 `debug.media_kit.egl_hdr_probe=1` 诊断分支，仅在 NDK dataspace 设置失败后执行：读取 EGL 扩展、选 10:10:10:2 window config；只有声明 `EGL_EXT_gl_colorspace_bt2020_pq` 才创建带 PQ 属性的 EGL window surface。属性关闭时不调用 EGL 探针。第一次编译直接调用 API28 `ANativeWindow_getBuffersDataSpace` 被项目较低 minSdk 拒绝，改成与原桥相同的运行时符号解析后构建通过；未安装编译失败的包。

真机 APK `/tmp/media-kit-p84-egl-pq-probe-6322-arm64.apk` SHA-256 `4b97fe076ebf90eaf6c5cef743598b849720057d8e4662f639ae166a3e260336`，设备 versionCode8322；同本地 JAR、固定 P8.4 输入和模拟无 HLG→PQ。能力仍 `{2,3}`，NDK PQ 设置仍 `-22`、实际0。EGL 探针报告 `extension=0 choose=1 configs=1 created=0 error=0x3000 dataspace=0`：有10-bit window config，但缺 PQ window colorspace 扩展，所以按探针门禁没有调用 `eglCreateWindowSurface`；`EGL_SUCCESS` 只是未尝试创建的默认错误状态，不能解读为 PQ 创建成功。应用自身 EGL 能力报告也列 `bt2020PqWindowSurface=false`。约10秒后 `AUTO_SOURCE` 超时，无首帧/`ANDROID_HDR_OPEN`，无额外未处理异常。日志 `/tmp/media-kit-p84-egl-pq-6322-logcat.txt` SHA-256 `13f481f89fb4807403fcbba69f912e0e5465bf9532fd575d34ed2242a2610b79`。探针属性已恢复0，应用强停，8322包保留。

结论限于公开 EGL 扩展协商：只将 GPU window surface 改为 EGL BT.2020/PQ colorspace 不能在本机直接使用；未验证驱动私有 EGL 属性、其他受支持 HDR buffer 路线或目标机 NDK `-22` 的具体内部返回分支。继续寻求能真实生产 HDR buffer 并被 HWC 识别的出口，保持 Surface 失败门禁。
