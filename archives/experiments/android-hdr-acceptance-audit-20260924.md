# Android HDR10 / P8.4 / P5 计划验收核对

依据 [2026-09-22 总计划](../conversations/android-hdr-dv-display-plan-20260922.md) 的 P0–P5 和最小矩阵逐项核对。初次只读复核时，目标 `3EP7N18C28016072` 装 versionCode 4154，九个候选 APK 与两条灰阶输入存在但未在该轮设备上运行。此后已进行多轮 P5 真机诊断，2026-09-24 又完成系统播放器 PQ/HLG/SDR 对照；下表 P1 已按新证据更新，其余“当前候选”描述仍指初次核对的九包，不应理解为设备当前安装状态。源码、构建、旧版本观察不能替代当前包验收。

| 阶段 / 必要证据 | 已证实 | 未完成或证据不足 | 下一步 |
| --- | --- | --- | --- |
| P0 实验身份、素材与能力 | 当前候选版本/SHA、同一 native JAR、固定三源 SHA 与 P5 6609 包 RPU 清单已归档；测试页有固定源与私有暂存事务；旧设备报告 HDR10/HLG 能力 | 当前安装运行 PID、native 运行时版本/编译后端、完整显示/亮度/温度设置、当前 EGL/HWC 与 MediaCodec 能力未同轮冻结；新事务双视图布局与 dispose 未实机复核 | 每轮先只读采集当前设备/设置/源/APK，运行时回读后端并对未知字段记 `INCONCLUSIVE` |
| P1 设备 PQ/HLG 阳性与 SDR 阴性 | [系统播放器同机对照](android-hdr-p1-native-positive-20260924.md)已运行 PQ/真实 HDR10/HLG/SDR：codec 输出、同播放器视频层 SF dataspace/HWC DEVICE 分别为 BT.2020/PQ+metadata、BT.2020/HLG、BT.709/无 metadata；PQ/SDR 灰阶截图映射不同且切回 SDR 标签正常；真实 HDR10 强停后视频层消失 | 同 PTS 光学高光/中灰与实际面板 HDR 激活尚无独立证据；系统播放器 P8.4 RPU 处理未知；未完成首帧→稳定播放的层 generation/显示状态完整时间线 | 补齐时间线；没有仪器时光学亮度保持 `INCONCLUSIVE`，不把 HWC dataspace 直接当面板激活证据 |
| P2 HDR10 直出及 GPU PQ | [6233/6237/6310 实机对照](android-hdr-p2-6233-6237-device-20260924.md)：6233 原生直出有完整画面、跨时场景不同、Home 返回后仍有视频与 HWC PQ+metadata 层；6237/6310 GPU PQ Surface 两个 PQ 值均返回 `-22`；[6311/6313 格式/时机对照](android-hdr-p2-surface-format-timing-20260924.md)中 format4 及 10-bit WID 绑定后设置也返回 `-22` | 6233 精确 PTS/长稳、面板 HDR 激活、严格 HDR10 元数据合规仍缺；GPU T1 在 dataspace 门禁失败，软件小片段和有效像素未验；6312 旧原生库断言已在 6313 排除 | 查 `ANativeWindow` consumer/usage 合约或受支持的 HDR 生产路径；保持严格门禁；继续原生长稳与显示激活验证，不以原生直出代替 T1 |
| P3 P8.4 HLG 优先 / PQ 回退 | [6236 原生 HLG 实机](android-hdr-p3-6236-native-hlg-20260924.md)有固定源可见场景变化、HLG HWC DEVICE 层，一次 Home 返回后仍有画面；[6238 GPU HLG 实机](android-hdr-p3-6238-hlg-surface-20260924.md)在 `RGBA_1010102` Surface 设置 HLG dataspace 时返回 `-22`，无首帧；[6235 模拟无 HLG 回退](android-hdr-p3-6235-forced-pq-20260924.md)选中 PQ Surface 尝试，也返回 `-22`、无首帧；策略测试和旧 2156 Texture 可见流畅证据存在 | 6236 再次打开后前后 PTS、独立颜色/HDR亮度/RPU行为/长稳缺；6235 未到 HLG→PQ 像素转换或 RPU 剥离；6231 Texture 未在本轮运行；真实无 HLG 设备兼容缺 | 隔离应用 HDR Surface 合约；原生直出补 PTS/长稳，再测实际回退转换；不以直出代替 T2 |
| P4 P5 DV→PQ/SDR | P5 源 SHA、逐包 RPU 输入、旧探针前 250 输出 PTS 关联及 raw-YUV 候选有证据；6234 PQ 与 6232 SDR 有运行属性门禁 | 新包未运行；RPU 附到 renderer 并消费、reshape 后像素、独立 DV 参考、HDR 激活、4K50 实时均缺；输入关联不能证明正确色彩 | 按运行清单先过启动门禁与逐帧处理/像素，再分别判 Platform PQ 和 Texture SDR；颜色参考缺失时不宣称正确 |
| P5 稳定性、性能和复位 | 旧版本有部分 20秒观察、阶段性进度/掉帧、后台返回观察；当前事务有交错单测与源码审核 | 当前每格的 5 次冷启/重开、60秒/10分钟/≥30分钟、seek/暂停/旋转/后台/退出循环、整链 5 次、首个实际 present、音画差和热稳定均缺 | 先做短轮门禁，失败定位后再按原阈值做长轮；人工可见验收单列 |

最小矩阵的包入口对应关系见 [覆盖核对](android-hdr-plan-coverage-20260924.md)。硬解关闭的同源对照尚无当前候选；T1/T2 两包只覆盖硬解开。P8.1/P7 与原生 DV 是独立扩展边界，不得计入当前 P5/P8.4 成功。总体状态为 **INCOMPLETE**，没有一个新的当前包通过显示与长播验收。

用户已更正此前关于重复安装 APK 的错误记录，并明确要求继续安装。按对应运行清单执行设备预检、候选安装与实验；P5 诊断属性按测试要求设置并在结束时恢复。除设备运行外，独立 DV/HLG 颜色参考和仪器光学测量仍可能需要额外来源或设备，缺证据时保持 `INCONCLUSIVE`。
