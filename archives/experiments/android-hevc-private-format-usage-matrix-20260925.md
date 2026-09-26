# Main10 PRIVATE Surface usage 对照（2026-09-25）

目的：在上一轮 Main8/Main10 格式对照后，固定同一 Main10 HEVC 文件，改变 `ImageReader.PRIVATE` 请求的 CPU/GPU usage，观察 AHB 格式是否改变。设备 LYA-AL00 / Android 10，固定 `OMX.hisi.video.decoder.hevc`；同 640×360、24fps、24帧测试片 SHA-256 `2a2b73e87a41f9e70404531c109217509c5d48912b7a84342f59db3d0ef4bf7f`。探针源码 `artifacts/android-hevc-private-usage-matrix/FormatProbe.java`，SHA-256 `6a17ab65660410231d1f9945950695a64d61fe0eda88e8b052999244c20bda87`；以API29 dex/app_process运行。

| 请求 usage | AHB 报告 usage | codec color-format | 8 帧 AHB format |
| --- | ---: | ---: | ---: |
| GPU_SAMPLED_IMAGE = 256 | 10496 | 805 | 均为 `0x325` |
| GPU_SAMPLED_IMAGE + CPU_READ_RARELY = 258 | 10498 | 805 | 均为 `0x325` |
| CPU_READ_RARELY = 2 | 10498 | 805 | 均为 `0x325` |

所有轮次 Image 为 PRIVATE(34)，PTS与Image纳秒时间戳逐帧一致，输出格式及crop相同。输出原文分别为 `artifacts/android-hevc-private-usage-matrix/usage-{256,258,2}.txt`，SHA-256依次 `cb65b57257837c4db884b115a29c0f3b1a522aa366eaad4ceccd505cc98f3b35`、`218e3b9fecb0fef0942d88caadf881081ec456669eca3e2b8dd99c77a506f52a`、`0e70b088f7b6b08a8712758d64847da9f3dcc64d3faa516fbbef1c79f950b099`。

结果表明**这些公开 ImageReader usage 请求不会改变该 Main10 输出的可见格式号 `0x325`**。API返回 usage 不完全等于请求值，但不能仅由返回 usage 判定 HFBC/linear，亦不能证明三轮物理布局相同。本轮没有取得私有 handle、有效 plane stride 或原生10-bit整数；因此没有建立安全的 `0x325` CPU 解析合同。探针只读，设备及主机临时文件已清理。
