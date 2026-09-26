# 华为 libosal codec→HAL 格式表核对（2026-09-25）

## 对象与依据

设备 LYA-AL00 / Android 10 的 `/vendor/lib64/libOMX.hisi.vdec.core.so` SHA-256 `6e1b24e1dc9514089be60cda56a682ab7df98c1d013c957ac6115babdcf25cf3` 动态引用 `Conversion::VCodecFormat2HalFormat(ColorFormat)`；提供该符号的实际库是 `/vendor/lib64/libosal.so` SHA-256 `3ae81d3d393bccf92af4c9a00c8b417abaa8755aae766a9fab587bafc86edeaa`。本轮均只读从真机取得，`nm -D -C`、`objdump -d`与原始 ELF 字节核对。

`libosal.so` 静态初始化代码`0x5f60–0x5f9c`从只读区`0x2f48`复制五个8字节项并构建映射表；`0x5fbc–0x5ff0`又从`0x2f70`构建反向表。`VCodecFormat2HalFormat` (`0x4474`)按内部 `ColorFormat` 整数查表，未找到时默认返回`0x30d`。

| 内部 `ColorFormat` 数值 | HAL/GraphicBuffer格式 | 反向表确认 |
| ---: | ---: | --- |
| 0 | `0x30d` (781) | 是 |
| 1 | `0x30c` (780) | 是 |
| 2 | `0x1` (1) | 是 |
| 3 | `0x325` (805) | 是 |
| 4 | `0x324` (804) | 是 |

这把 `0x325` 的来源从 gralloc 推进到**HiSilicon 解码器内部格式 3，经 libosal 明确映射为 HAL 格式805**；`0x324`对应内部格式4。8-bit Main→`0x30d`、Main10→`0x325` 的实机对照与该表一致。两组相邻值非常适合检验 UV/VU 次序假设，但 ELF 表只给整数，不给 enum 名称、plane/stride/打包合同。不能把内部3/4直接命名为 NV12/NV21 或 P010，也不能用表项判断 HFBC backing。

`libosal` 同时导出 `GraphicBufferWrapper::GetBufferHandle`、`Conversion::GetBufferHandleInfo` 等接口；如继续核 plane，应先找到该版本的对应结构定义/调用证据，或以受控图案和同帧GPU读回验证，不能直接把已锁定但stride为0的 AHB 指针按公开YUV解释。只读检查结束后，主机临时库副本清理。
