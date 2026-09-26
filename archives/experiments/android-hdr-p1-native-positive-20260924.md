# P1 系统播放器 HDR/SDR 对照（2026-09-24）

目标机：Huawei LYA-AL00，Android 10，序列号 `3EP7N18C28016072`。以系统播放器 `com.huawei.himovie.local/com.huawei.hwvplayer.service.player.FullscreenActivity` 打开本地文件，核对解码输出、SurfaceFlinger 视频层与 HWC 接收的 dataspace。测试后已强停系统播放器。以下是原生显示链的对照证据，不代表面板实际亮度或 mpv 应用路径验收。

| 输入 | 解码器输出 | SF / HWC 视频层 | 截图观察 |
| --- | --- | --- | --- |
| 自制 PQ 灰阶，1920×1080/30，60 秒 | HEVC Main10；BT.2020/ST2084，dataspace `0x11c60000` | `BT2020 SMPTE 2084 Limited`；DEVICE，`BT2020_ITU_PQ`，HDR metadata types=3 | 七级灰阶单调；截图像素 0/37/76/129/148/166/191 |
| DV P8.4 源，3840×1920 | HEVC；BT.2020/HLG，dataspace `0x12060000` | `BT2020 STD-B67 Limited`；DEVICE，`BT2020_ITU_HLG`，metadata types=0 | 可辨识夕阳场景；RPU 是否由系统播放器处理未知 |
| 自制 SDR 对应灰阶，1920×1080/30，60 秒 | HEVC；BT.709/SMPTE170M，dataspace `0x104` | `BT709 SMPTE_170M Limited`；DEVICE，`V0_BT709`，metadata types=0 | 高亮四级剪切；截图像素 0/37/98/255/255/255/255 |

三个输入均由 `OMX.hisi.video.decoder.hevc` 解码，活动 buffer 均为厂商格式 `0x325`。因此 `0x325` 本身不等于 HDR，须与 dataspace/metadata 联合判断。从 PQ、HLG 切回 SDR 后，系统播放器的视频层恢复 BT.709/非 HDR metadata。设备 `dumpsys display` 中 `mActiveColorMode=0`、`mBrightness=1647` 在 PQ/SDR 对照中未变，不能据此判断面板 HDR 模式或光学亮度。

PQ 原始 6 秒样本 SHA-256 `748719e5d3c1336411d33963ca1b147cb7b1e97363773bfd5a32be1304d1342d`；SDR 样本 `d6e5e8c5979cd31e91cc1abdbc0c406c87b69e7fe0e4a8944b0a42bb2c3b8df5`。通过 `ffmpeg -stream_loop 9 -i <6s-input> -map 0:v:0 -c copy -t 60 -movflags +faststart <60s-output>` 无重编码扩展，二者均 1800 帧。PQ 60 秒 SHA `313dd93a7db0884dd897872de82caa1222037571f6182ed02a8d348f3d813d7c`，SDR 60 秒 SHA `a21af56148659a5a5acbb0bc11893bc9873ae9f4a28f35877e2c7b1a759c931c`；设备传输后 SHA 匹配。样本生成清单见 `android-hdr-gray-controls-20260924.json`。P8.4 设备文件 SHA `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`。

原始复播日志和层快照在 `/tmp/media-kit-p1-{pq,p84,sdr}-himovie-{logcat,sf-live}.txt`，SHA-256 顺序为：PQ `e4cc81fca716a032d4836e973cf05c5fdda9b4933e90cbfe6538b5ee948b2423` / `6c35e589cc4848a1a4495ba38a19acd8b28fc649372d184a9f3d4dfcd96305ce`；P8.4 `1059074f0bc02215f13b9240b5dbfd9deebc4e1d09efb454c1c3a1984cbe24c6` / `02df56975b1fb3585e34e8a6f8a81f1fddae15e224f9e23238490ef27a2b741f`；SDR `8302a2e981eff7157665aa26f01540067ca21c401c68b6346e6c9be6b14861a3` / `fe25d2cd9d3e6f012448f6bd2d4d4f520ea74e28d9a13e6f52ddd3df8d2929b6`。截图分别为 `/tmp/media-kit-p1-{pq,p84,sdr}-himovie-screen.png`；截图只是 8-bit 系统捕获，不能作实际亮度或独立色彩测量。静态灰阶与单帧截图也不能证明连续播放稳定性。

结论：目标机的系统播放器可让 PQ/HLG 视频以对应 dataspace 和 HWC DEVICE 层提交，切回 SDR 标签也正确。P1 的 mpv 原生视图、面板实际 HDR 激活/峰值亮度、色彩数值及长时间可见稳定性仍需分别验收；该对照不解决 P5 性能。

同轮补测真实 `/sdcard/Download/HDR10.mp4`：显式系统播放器组件前台、屏幕解锁；`OMX.hisi.video.decoder.hevc` 输出 `(Limited, BT2020, BT2020, ST2084)` 和 `0x11c60000`，对应 SurfaceView 层 `BT2020 SMPTE 2084 Limited`、HWC `BT2020_ITU_PQ`、HDR metadata types=3。强停播放器并再次采集后该视频层已消失，当前焦点回到 Launcher。这证明真实 HDR10 源与合成 PQ 控制在同一播放器中走相同的 PQ 视频层；仍未测实际面板亮度或持续帧稳定性。日志 `/tmp/media-kit-p1-hdr10-himovie-logcat.txt` SHA `3c50cd514a7599cbeb7103014b0d9c5037b0db2f2f6637ea779de6c8953b3323`，播放层快照 `/tmp/media-kit-p1-hdr10-himovie-sf.txt` SHA `1d03029979aeac3a0df17056844cd2e7576ed04a873e6e6d8ec0a4853e14ac6f`，截图 `/tmp/media-kit-p1-hdr10-himovie-screen.png` SHA `b4a545032c37fb8c2df2fd1abb37dc649f2c09edc0469f301be0ad6bf7a10a0d`。
