# P5 VO 入队时序与提前取帧对照（2026-09-24）

固定设备 LYA-AL00、P5 3840×2160/50fps 输入、MediaCodec、RPU、厂商 `0x325` raw/MRT、SurfaceTexture 1440×810。测试页在约 75 秒把 VO 切到 null，诊断汇总才会输出。`debug.media_kit.p5_vo_summary` 默认关闭；Flutter Texture 消费计数为构建时诊断，逐帧仅记内存、不打印。均为解锁前台轮，视频时间轴约实时、decoder drop 0、thermal status 1；没有真人连续流畅或独立颜色验收。

隔离 mpv 新增入队前/队列中截止时间与队列等待汇总，补丁 `archives/experiments/android-p5-vo-queue-summary-20260924.patch` SHA-256 `90312cf2200df90be013813b63640a8b2d703cfec643d28ffa442617a37666cd`；`vo.c` Android 交叉编译通过。`queued` 包含最终绘制与被 VO 丢弃的帧；入队过期 10 + 排队后过期 4 = VO 丢弃 13 + 按 mpv 防冻结规则仍绘制的迟到 1，口径一致。CPU 墙钟统计不能解释 GPU、显示或不可见的队列等待；探针可能改变调度。

6303 有效 APK SHA-256 `a55890b2751870ee0dcaa75919ce9faa28e7e6b2e9f286e0261366e800c18652`，versionCode 8303，包内 strip libmpv SHA `9d034910cfe414d70dc9a8fb42fbf626dc8c511708edefdf0984b87adb243212`，完整 helper 库、验签/ZIP 通过，设备私有 P5 文件 SHA `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`。同 APK 的开关对照：

| 运行 | 汇总 | t18/28/60 VO 累计掉帧 | t28→60 Flutter 不同纹理消费 | 日志 |
| --- | --- | --- | --- | --- |
| 6303 on | 开 | 13/13/13 | 860→2457，增 1597 | `/tmp/media-kit-6303-p5-queue-logcat.txt` SHA `a36eeba2852ba873609b101b543cfd3b00834bfe9573b6123a716606bfaf3443` |
| 6303 off | 关 | 0/0/284 | 912→2215，增 1303 | `/tmp/media-kit-6303-p5-queue-summary-off-logcat.txt` SHA `626aafce3c782a1d6003a09dd9220f35c7778bb35c810c482e80df4820f044bf` |

6303 on 于 75 秒 VO 结束：`queued=3228 expired_at_queue=10 expired_queue_to_vo=4 deadline_drops=13 late_draws=1`；queue wait 平均约 15.17 ms，其中 2304 次在 16–33 ms；draw CPU 平均约 5.41 ms，flip CPU 平均约 1.25 ms。开关差异大，表明新增逐帧计时强烈扰动系统，不能以开启轮近满帧或这组时长判定根因/修复。关闭轮前 28 秒近满帧，随后 `P5_RETIRE` 每 50 帧间隔由约 1 秒变为约 1.2–1.3 秒，与 6299/6300 后期下降相符；热状态 1，但不能单独归因热限频。

测试页另加默认关闭且读回校验的 `MEDIA_KIT_ANDROID_VIDEO_TIMING_OFFSET`。6304 把设置误放在普通打开分支；P5 HDR 事务绕过该分支，日志无读回，故 6304 t18/28/60 掉 35/66/359 只是默认参数复测，不计 0.1 秒对照。日志 `/tmp/media-kit-6304-p5-timing-invalid-logcat.txt` SHA `b7f5415beaaa7c74b4cfa541ef6c53f9a15568dce647ff99335790c1578cf883`。6305 把设置移到 HDR 事务与普通入口共用方法，读回 `video-timing-offset=0.100000`；APK SHA `966c05bed2cb30fc741e117738cfa06d39d7c6b2a54dff01ed2c20e4065819ae`，versionCode8305，同 libmpv，VO 汇总关闭；t18/28/60 掉 35/74/362、decoder0，t28/60 Texture 不同时间戳 778/2067。75 秒主动切 `vo=null` 已记录。完整日志 `/tmp/media-kit-6305-p5-timing-100ms-logcat.txt` SHA `b2a3b2af9e51442ca9264afbc9de9b764168832440de2f93c5a50cfd464ff94c`。该值较 mpv 默认 50 ms 增加提前取帧量，后期仍明显掉帧；轮次热状态/起点未严格配对，不据相近数字宣称完全无性能效应。

6301 首包只含 libmpv，漏 Android helper 且未启用自动单视频页；虽然构建验签安装成功，不能做播放证据。6302 补 helper/自动页后把固定源误指向无读取权限的 `/sdcard/Download/DV-P5.mp4`，报 `PathAccessException`，不能做播放证据。6303 改用应用私有目录并核对输入 SHA，才是本节首个有效轮。构建初期磁盘不足导致一次多 ABI 打包失败；限定 arm64 后通过。已删除部分有日志/哈希的旧诊断 APK 和无签名中间文件以腾空间，未动源视频与原始日志。

下一步应在汇总关闭条件下寻找不干扰播放的时间/队列证据，或测试能够改变调度而不牺牲画质/同步正确性的真实输出策略；单纯 VO 计时、提前取帧或一次近满帧不构成 P5 性能验收。P5 原生 PQ/HDR 与独立色彩仍是单独门禁。
