# P5 RPU 后图像参考路径预检（2026-09-24）

目标是为手机 packed10/raw/RPU 后最终图像建立独立参考。当前只是主机路径可行性，**没有**完成手机/主机同 PTS、同目标色域、同 RPU 身份的像素比较。

主机 Homebrew mpv 0.41.0、libplacebo 7.360.1、FFmpeg 9.0.2，用固定原片 `/tmp/media-kit-DV-P5.mp4`：

```sh
mpv --no-config --no-audio --vo=gpu-next --gpu-context=macvk --pause --start=10 --input-ipc-server=/tmp/media-kit-p5-ref-mpv.sock --keep-open=yes /tmp/media-kit-DV-P5.mp4
```

IPC回读`time-pos=10.000000`，`video-params`为3840×2160、`colormatrix=dolbyvision`、`colorlevels=full`、`primaries=bt.2020`、`gamma=pq`、`sig-peak=4.929096`；`screenshot-to-file ... video`成功。输出PNG为3840×2160、16-bit/color RGBA，SHA-256 `75c5220528ced366f064518ed2baada6671d58b2a0237443480746dd36762d1f`。预览可见正常城市场景，但不能靠单张主机截图证明手机颜色正确或面板HDR激活。mpv进程已由IPC `quit` 正常退出。

主机直接`--start=10`启动期间 FFmpeg 反复报告 `Multiple Dolby Vision RPUs found in one AU. Skipping previous.`。原片按ffprobe的packet `pos=4761846,size=263461,pts=10.000000`读取，其长度前缀HEVC NAL恰有**一个**type62 RPU（NAL总长208字节，NAL头后206字节FNV-1a哈希`907c8b42`）；同一附近其他样本各一个RPU。与Android补丁对单包RPU计数/哈希规则一致。主机`--vd-lavc-threads=1 --vo=null --start=0 --frames=520`顺序解码未报该警告，而直接`--start=10 --frames=1`仍报，说明警告与跳转启动路径有关，不能据此声称源包重复RPU。

进一步用`mpv --no-config --no-audio --vo=gpu-next --gpu-context=macvk --vd-lavc-threads=1 --frames=500 --keep-open=yes`从0顺序播放，IPC回读`time-pos=10.000000`且无上述RPU警告，再经`video`截图得到**完全相同的PNG SHA** `75c5220528ced366f064518ed2baada6671d58b2a0237443480746dd36762d1f`。保留的顺序版文件为`/tmp/media-kit-p5-mac-ref-sequential500.png`；早期直接跳转PNG及一次停在10.02秒的非同帧PNG已删除以节省空间。顺序版mpv由IPC退出，socket清理。两种播放方式在PTS10的最终图像逐字节一致，明显收窄跳转警告对**该截图**的影响；仍未从主机/手机直接记录同PTS已选RPU缓冲哈希，不能把包内单RPU和图像相同等同完整RPU身份/颜色验收。

后续8352手机与主机独立FFmpeg帧解码均读到PTS10已附着RPU缓冲`size=206,hash=907c8b42`，与原片包内唯一RPU一致，排除了该帧两端**原始RPU payload不同**的解释；详见`android-p5-post-rpu-phone-20260924.md`。主机另生成1440×810/BT.709/BT.1886/8-bit窗口参考，九点对手机仍有明显差异。此PNG仍只是**候选**RPU后参考：相同RPU payload不等于解析/颜色目标/渲染结果一致。现有`vo_gpu_next`的`video_screenshot`走`pl_render_image`并可生成高位深host-readable FBO，但手机同一PRIVATE硬解图像在正常渲染后无法再映射一次；后续改从已渲染FBO直接读回。Flutter `Player.screenshot`当前只请求`screenshot-raw video`并编码JPEG/PNG或8-bit BGRA，不能把普通屏幕截图当RPU数值参考。
