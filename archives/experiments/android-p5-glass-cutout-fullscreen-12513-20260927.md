# Glass P5 横屏缺口区域与物理全屏布局（12513）

2026-09-27，华为 LYA-AL00/API29，自动亮度。物理横屏 3120×1440，Glass P5 4K59.94 固定本地源 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`。诊断 APK 12513 SHA-256 `df95c6cd666de699bbddfe6b8f0e0ba06309888da8f7ef85dceb6e6f8d9d75c1`，arm64 JAR SHA-256 `f745146332b532d8baeb162b7a33ddefa03ae8dc0a7731f13a9584ef7e6fa3f9`。它与 12511 同为播放前横屏、Video 铺满应用窗口、中央 PixelCopy、固定文件预验证入口、P5 Texture SDR；隔离测试 Activity 新增 `layoutInDisplayCutoutMode=SHORT_EDGES`，不是产品库改动。

系统在横屏直接报告 `DisplayFrames w=3120 h=1440 r=1`、`DisplayCutout.insets=Rect(136,0-0,0)`。12511 不允许进入缺口时预建布局 2984×1440；12513 允许进入后，原生两轮预建均为 **3120×1440**、`bound=true`，同一输出后续随 4K 片源调整为 3840×2160。这直接确认此前少掉的 136 像素来自**屏幕缺口安全区**，不是左右栏或导航栏。截屏中测试占位洋红铺满窗口，播放后两侧洋红为 16:9 视频留边，不是片源层纹。系统输出、截屏和日志在 [artifacts/android-firstframe-cutout-12513](artifacts/android-firstframe-cutout-12513/)。

两次独立进程点击后的中央 Flutter Surface PixelCopy 结果（秒）：

| 轮次 | 首次黑画面替换洋红 | 首次非零像素样本 | `spread>10` 内容阈值 |
| --- | ---: | ---: | ---: |
| 1 | 1.654 | 3.752 | 4.025 |
| 2 | 1.280 | 3.430 | 3.703 |

同源约 2.052 秒片头黑场，且采样是 Flutter Surface 读回上界，不能当物理屏幕光学首帧。12511 安全区窗口的三轮内容阈值为 3.628–3.763 秒；两包窗口布局不同、样本少，当前不能宣称缺口模式有确定性能增减。**完整物理窗口已经验证，2 秒首个非黑画面仍未达标。**

第三轮开始前 ADB 与 macOS USB 列表均不再出现手机，等待命令已中止，避免重连后意外播放。用户重新接线后，ADB 再次识别同一设备；已强停诊断应用，恢复原 12492 APK、五项 P5 诊断属性均为 0。自动亮度模式为 1、自动旋转为 1、用户旋转为 0；再次发送休眠指令后确认 `mWakefulness=Asleep`、显示 OFF。第三轮未执行，不计入有效样本。
