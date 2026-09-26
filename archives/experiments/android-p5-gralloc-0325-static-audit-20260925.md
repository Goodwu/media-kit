# Kirin 980 gralloc `0x324/0x325` 静态核对（2026-09-25）

## 对象与方法

- 设备：LYA-AL00，Android 10；只读取得 `/vendor/lib64/hw/gralloc.kirin980.so`。
- 库 SHA-256：`c56074edfb7c388edf615eee08e7118033f613396d19272bfb36ea693d0ba35d`，ELF AArch64，导出部分 C++ 符号；使用本机 `nm -D -C`、`objdump -d` 检查。
- 未修改设备、系统库或项目播放器；分析用的 `/tmp` 副本已删除。

## 直接观察

1. `GrPlatformConstraint::InitmapFun()` 分别把 `0x325`（偏移 `0x1a284`）与 `0x324`（`0x1a364`）插入格式映射表。它们是 gralloc 实际识别的两个不同键，不是 AHardwareBuffer 临时生成的值。
2. `GrPlatformConstraint::CheckHfbcSupport()`（`0x1c5f4`）计算 `format | 1`，与 `0x325` 比较，设置一个内部字节字段（`0x1c610–0x1c61c`）。这同时覆盖 `0x324` 和 `0x325`，但还不能据此给最低位命名。
3. 同一函数仅在后续格式/usage 条件成立时，才返回 `format | 0x1000000000000` 并设置另一字段（`0x1c6b4–0x1c6c4`）。因此基础格式编号和 HFBC 相关内部标志在此路径分开处理；`AHardwareBuffer format=0x325` 本身不证明缓冲已启用 HFBC。
4. 导出符号还有 `GetYuvPx10SizeAndDimensions`、`GetYuvHfbcSizeAndDimensions`、`GetYuvHebcSizeAndDimensions`、`SetHandleHfbcInfo`。这些说明库具备多种 10-bit / 压缩布局处理函数，不说明本次 P5 buffer 调用了哪一种。
5. 续查 `GetYuvHfbcSizeAndDimensions`（`0x1d718`）先检查分配数据偏移`0x75`的条件字段，随后读取`0x77`的格式族字段来调整大小计算（`0x1d71c–0x1d754`）。`CheckHfbcSupport` 仅在额外条件满足时设置前一字段，而`format | 1 == 0x325`设置后一字段。这进一步说明“属于`0x324/0x325`族”和“走HFBC尺寸路径”是两个判断；仍不能确定实际P5缓冲的backing。
6. `GrVendorConstraint` 的动态重定位表中 `GetYuvPx10SizeAndDimensions` 确实出现两次（`0x22270`、`0x22288`），但所处表项的键分别是`0x402`、`0x403`，**不是**`0x324/0x325`。目前未找到可证明这两对编号直接对应的映射，不能仅凭该函数名宣称`0x325`的plane布局或UV顺序。

## 尚未证明

- 未发现公开的 `0x324/0x325` 名称定义、plane/stride 合同或两者最低位的正式含义。
- 不能据此断言 `0x325` 等于 P010、packed10、HFBC，也不能断言该次 P5 buffer 为 linear。
- 当前 P5 第500帧 `AHardwareBuffer_lockPlanes` 虽成功，只有一平面且 row/pixel stride 均为0，不能直接当标准 YUV 数据解释；独立 GPU 采样路径与软件参考之间的局部差异仍未归因到解码、Surface 转换或采样。

## 下一步判别

优先在同设备、同样本、同一 `ImageReader.PRIVATE` 配置下记录 8-bit HEVC 与 Main10 的 AHB `format`，并同时记录可获取的 handle/usage 元数据及实际日志中的 HFBC/LINEAR 状态。若有可控的 HFBC→LINEAR 开关，再进行同输入 A/B；不能仅用不同素材的格式号差异作强结论。任何私有 handle 字段解释须找到对应版本代码或动态证据。
