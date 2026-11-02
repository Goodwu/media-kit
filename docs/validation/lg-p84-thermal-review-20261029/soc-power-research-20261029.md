# SOC 功耗资料判读（2026-10-29 晚）

只读公开资料调研 + 本仓现场数据外推；服务于 LG-DV-P84-THERMAL-REVIEW-20261029 的功耗大头判别。所有条目标注数据形态：实测 / OEM模型 / 厂商宣称 / 学术 / 估算。本文件是 conversation Findings「SOC 功耗资料判读」节的结构化数据底稿。

## 1. 设备与平台事实

- LGH870DS = LG G6，Snapdragon 821（MSM8996PRO-AC，14nm），Kryo 2×2.35 GHz + 2×1.6 GHz，Adreno 530。实测：大核簇最高 2342.4 MHz、小核簇 1593.6 MHz；调压器名 `kryo0/kryo1`。〔GSMArena LG G6；实机取证〕
- KGSL GPU pwrlevel（AOSP msm8996pro.dtsi，speedbin0）：652.8 / 624 / 560 / 510 / **401.8 / 315 / 214** / 133 / 27 MHz（bus level 12/12/11/9/8/6/4/3/0）。实机热 cap 401.8 MHz 与表一致。公开表中无 596 MHz 级；若实机出现属 LG 定制。〔厂商内核源码〕
- CPU cpufreq 表（LG 内核 msm8996pro lineage-22.1）：小核 20 corners 至 1593.6 MHz；大核 27 corners 至 2342.4 MHz；CPR 电压上限四档 670/745/905/1140 mV。〔厂商内核源码〕

## 2. GPU CPR corner 电压表（msm8996pro.dtsi，上限/下限，非每颗芯片实际值）

| GPU 频率 | corner | 电压上限 V | 电压下限 V |
|---|---|---|---|
| 133 MHz | 2 | 0.670 | 0.52 |
| 214 MHz | 3 | 0.670 | 0.52 |
| 315 MHz | 4 | 0.745 | 0.52 |
| 401.8 MHz | 5 | 0.825 | 0.52 |
| 510 MHz | 6 | 0.905 | 0.52 |
| 560 MHz | 7 | 0.960 | 0.52 |
| 624 MHz | 8 | 1.015 | 0.52 |
| 652.8 MHz | 9 | 1.065 | 0.52 |

实机（本仓取证）GPU 上游轨压 595–645 mV @ 214–315 MHz 档，落在界内。

## 3. CPU 频率-功耗（核心数据：Pixel XL marlin power_profile.xml，OEM模型，mA@电池，×3.85V→mW 为本方换算）

小核簇（cluster0，每核 active，18 频点 MHz / mA）：

| 频率 | 307.2 | 384 | 460.8 | 537.6 | 614.4 | 691.2 | 768 | 844.8 | 902.6 | 979.2 | 1056 | 1132.8 | 1209.6 | 1286.4 | 1363.2 | 1440 | 1516.8 | 1593.6 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mA | 11.27 | 14.84 | 18.50 | 22.52 | 25.97 | 31.69 | 37.67 | 42.86 | 46.87 | 57.92 | 67.56 | 76.30 | 87.61 | 97.05 | 109.54 | 122.05 | 136.35 | 154.44 |

大核簇（cluster1，每核 active，25 频点 MHz / mA）：

| 频率 | 307.2 | 384 | 460.8 | 537.6 | 614.4 | 691.2 | 748.8 | 825.6 | 902.4 | 979.2 | 1056 | 1132.8 | 1209.6 | 1286.4 | 1363.2 | 1440 | 1516.8 | 1593.6 | 1670.4 | 1747.2 | 1824 | 1900.8 | 1977.6 | 2054.4 | 2150.4 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mA | 7.06 | 11.48 | 14.98 | 19.64 | 23.17 | 27.48 | 31.63 | 39.19 | 47.82 | 55.66 | 64.91 | 73.82 | 85.30 | 96.04 | 109.23 | 118.56 | 132.96 | 143.69 | 161.38 | 180.62 | 193.90 | 214.36 | 238.34 | 265.76 | 297.92 |

其他键值（marlin）：`cpu.cluster_power.cluster0`=14.748 mA、`cluster1`=21.155 mA（簇公共开销，不含核）、`cpu.active`=18.760、`cpu.idle`=1.389、`cpu.suspend`=5.734、`screen.on`=178.708、`screen.full`=240.790、`video`=50.93、`audio`=75.60 mA。

常用换算点：小核 @768 MHz≈145 mW、@1593.6≈595 mW；大核 @1209.6≈328 mW、@1248（内插）≈350 mW、@2150.4≈1147 mW。

LG G6 自家模型（LineageOS g6-common overlay，口径偏高）：`screen.full.display0`=185.31 mA≈713 mW、`screen.on`=95.24 mA、`cpu.idle`=22.42 mA、小核满频 159.27 mA、大核满频 503.66 mA≈1.94 W。

曲线形态：超线性。大核 1.2→2.15 GHz 功率约 ×3.3；本机 governor 让大核停在 ~1.25 GHz 与能效拐点相符。

## 4. GPU 功耗（无公开逐频实测；CV²f 外推 + 整机锚点，全部为估算）

- 公开渠道确认**不存在** Adreno 530 逐频 mW 实测（AnandTech/TechInsights/Chipworks/Notebookcheck/学术/社区均无；Chips and Cheese 的 G6 实机文章为纯架构分析，无功耗数字）。
- 整机锚点（Notebookcheck，实测，含屏）：LG G6 idle 均值 1.43 W / 重载均值 5.52 W / 峰值 10.47 W；OnePlus 3（SD820）5.92 / 10.53 W。
- 由锚点反推满频（653 MHz、~1.03 V）GPU ≈1.5–2.5 W；折到实测工作点（315 MHz、~0.645 V、busy 60%）GPU 核心 ≈0.25–0.45 W；B 候选工作点（~233 MHz、~0.595 V、busy 68%）≈0.2–0.35 W。
- 带宽参照：Adreno 530 实测 VRAM 带宽 14–15 GB/s（Chips and Cheese，G6 实机，OpenCL 微基准）。

## 5. DDR / Venus / 显示 / 整机播放锚点

- DDR：LPDDR3 ≈67、**LPDDR4 ≈50 mW/(GB/s)**（≈6.3 pJ/bit；Cadence 白皮书 Table 1，源自 JEDEC/Micron）。管线结构性流量 4–8 GB/s → ≈0.2–0.4 W。
- Venus 硬解块：无官方 mW。MIT 40nm HEVC 核 0.35–0.77 nJ/pixel、1080p24–50 仅 24.9–30.6 mW；外推 4K30（2.21 亿像素/s）≈0.08–0.17 W；marlin 模型 `video`≈196 mW；Khernache 2021：硬解 < 整机 30%。取 **0.1–0.2 W**。
- 显示：G6 峰值亮度 564 nits（GSMArena）；LG 模型 screen.full≈713 mW；最高亮度+HDR 估 0.7–1.2 W（外推，无 G6 面板 NDA 规格）；扬声器 audio 模型≈291 mW。
- 整机播放：GSMArena G6 本地视频循环 10.5 h → ≈1.2 W（SDR、中低亮度）；Turkkan 2024（LCD/Exynos）1080p 播放整机 ≈2.25–2.28 W、360p→1080p 增量仅 ~150–180 mW。

## 6. 本仓实测工作点（repeat2-A1 基线，24 稳定样本）

- GPU：中位 315 MHz（min 214）、busy 中位 60%（56–70）；上游轨压 595–645 mV。
- CPU：小核簇中位 768 kHz、大核簇中位 1248 kHz；进程整体 62% 单核（Thread-8 26% / Thread-5 11% / JNISurfaceTexture 8% / MediaCodec_loop 3.7% / AudioTrack 2.4% / demux 1.5%）；kryo0 轨压 584–825 mV（中位 776）、kryo1 固定 727 mV。

## 7. 场景功率分解（估算/模型口径，非本机实测）

| 块 | 估算 | 形态 |
|---|---|---|
| 显示+背光（亮度 255） | 0.7–1.2 W | OEM模型+外推 |
| GPU 核心 | 0.25–0.45 W | CV²f 估算 |
| DDR 带宽（GPU 管线 4–8 GB/s） | 0.2–0.4 W | 公开系数×结构流量 |
| CPU | 0.3–0.6 W | OEM模型 |
| Venus 硬解 | 0.1–0.2 W | 学术外推+OEM模型 |
| 其他（audio/modem 等） | ~0.3 W | OEM模型 |

合计 ≈2–3 W。判读：**硬解块小头；管线内大头是 GPU 渲染路径（核心+DDR 合计 0.5–0.9 W）；CPU 同量级略小且无结构性杠杆（CPU 热点线程即渲染编排）；整机最大单项是最高亮度背光。ab4 工作点降幅 21.9%（频率×busy）折算仅 ~0.1 W，与 240 s 热态 A/B 难分辨一致。**

## 8. 负结论与未找到清单

- **AC 供电下 `battery_current_now` 不能当功率计**：repeat2-A1 全部读数 0、repeat2-B1 中位 -156096 µA（充电旁路）。测整机功率须拔电（fuel-gauge 分桶 + KGSL `min/max_clock_mhz` 锁频）或 Monsoon 外置功率计。
- 未找到：Adreno 530 逐频功耗实测；SD821 出厂实际 corner 电压（仅 CPR 上下限）；Venus 官方 mW；G6 面板 5.7" 2880×1440 峰值亮度 W 级规格（NDA）；SD821 4K HDR 本地播放整机实测；XDA LG V20 power_profile 具体数值（Google Sheet 无法核验）。
- 厂商宣称（仅相对值，无绝对瓦数）：Adreno 530 vs 430 功耗 -40%；SD821 vs 820 整体 -5%；SD835 vs 820/821 整机 -25%（Qualcomm）/ -40%（Wired 口径，互相矛盾并列）。

## 9. 来源

- Pixel XL power_profile.xml：https://android.googlesource.com/device/google/marlin/+/master/marlin/overlay/frameworks/base/core/res/res/xml/power_profile.xml （OEM模型）
- LG G6 power_profile.xml：https://raw.githubusercontent.com/LineageOS/android_device_lge_g6-common/lineage-22.1/overlay/frameworks/base/core/res/res/xml/power_profile.xml （OEM模型）
- msm8996pro GPU/CPR 表：https://android.googlesource.com/kernel/msm/+/android-7.1.0_r0.2/arch/arm/boot/dts/qcom/msm8996pro.dtsi ；LG 内核：https://github.com/LineageOS/android_kernel_lge_msm8996 （厂商源码）
- 整机功耗：https://www.notebookcheck.net/LG-G6-Smartphone-Review.199364.0.html ；OnePlus 3：https://www.notebookcheck.net/Test-OnePlus-3-Smartphone.167713.0.html （实测）
- Adreno 530 架构/带宽：https://chipsandcheese.com/p/inside-qualcomms-adreno-530-a-small-mobile-igpu （实测，非功耗）
- DDR：http://www.multimediadocs.com/assets/cadence/documents/DRAM_wp.pdf （厂商/EDA）
- HEVC 核能耗：https://eems.mit.edu/wp-content/uploads/2017/06/2017_vlsi_hevc.pdf （学术实测）
- 硬解占比：https://ensta.hal.science/hal-03127340 ；RK3588 对照 https://arxiv.org/html/2402.09001v1 （学术）
- 播放建模：https://par.nsf.gov/servlets/purl/10563541 ；Carroll & Heiser https://www.usenix.org/legacy/event/atc10/tech/full_papers/Carroll.pdf （学术）
- G6 规格/亮度/续航：https://www.gsmarena.com/lg_g6-8466.php ；https://www.gsmarena.com/lg_g6-review-1590p3.php
- 本仓现场数据：`repeat2-A1/`、`repeat2-B1/`、`instant-ab4-*`（本目录内）
