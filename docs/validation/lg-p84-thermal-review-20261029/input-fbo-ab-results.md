# LG 输入 slot FBO 复用：四轮独立结果核验（2026-10-30）

本轮**没有证明稳定、明显的 GPU 负载改善**。复用路径实际命中、四轮播放与恢复均通过；候选 GPU 频率和频率×忙碌率代理没有一致下降。CPU 均值略低，幅度小且只有两轮候选，起播热状态明显不同，尚不足以作为生产启用依据，也不能据此断言该方案必然无效或更耗电。

## 范围与环境

本次验证仅离线读取已有证据并独立计算，未操作设备、未构建、未修改实现。唯一新增文件是本文。开始时 media-kit HEAD 为 `3bdf2c6cd21860c1c258d0b75f807b743d373e4a`，工作区已有 TASKS、HDR SDK/Lab/测试工具及整套验证目录的 dirty/untracked 修改；其他 agents 同时实施 schema6。Python 为 3.15.2。

- 设备记录：LG `LGH870DS42e27764`，`LG-H870DS`，Android 7.0 / API24，USB 在线、Charging。
- A1→B1→B2→A2，各请求 60 秒、2 秒采样；A=`debug.mks.st_fbo=0`，B=`1`。两边均 display-resample、defer-publish-flush=0、GPU timing=0、YUV fusion=0。
- 实际视频：SurfaceTexture 硬解，DV8/compat4 HLG→PQ，target-peak1000、gamma0、BT.2020，surface2672×1336，背光64、HDR1。
- 本地 APK SHA256 独立重算为 `d0257632f2723a965f37caff75b19e70add7f436e43ff972531e67f8c6268786`，与 `media_kit_hdr_lab/build/app/outputs/flutter-apk/lg-p84-fbo-thermal-20261030-release.native-verification.json` 的 `verified` 收据相符。JAR SHA256 为 `f5cee8f874c2b1578af94c6f92369d74b1871f3aeea0d4672d86fe7fb85bdc1d`。Lead 已记录装机包完整回读相同；本验证未重新访问设备。
- 包中还包含默认关闭的开发中 schema6 诊断。四轮日志无 compare armed、fusion committed、GPU timer、fatal/ANR 事件；工具原状态与恢复记录内 GPU timing/fusion/fault 属性均为空。compare/oracle/probe 属性未由本轮 thermal host 完整快照，不能从四个 round 文件独立证明这些属性的值；Lead 的轮前核查与日志共同提供补充证据。
- 媒体路径四轮一致：`/sdcard/Android/data/com.example.media_kit_hdr_lab/files/hokkaido-p84.mp4`。本轮传入的历史全字节 receipt SHA256 是 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`（2026-10-29核验、1,232,790,317字节）。`--source-receipt` 分支只校验 receipt 的 verified/serial/path，本轮未重新计算源哈希或大小。Lead 正另做轮后完整回读；轮后相符可增强身份依据，但不能严格证明四轮期间从未更改。

## 原始证据与有效性

每轮目录 `input-fbo-ab-{A1,B1,B2,A2}/` 含 `summary.json`、`samples.ndjson`、`instant-summary.json`、`flutter-logcat.txt`、`thermal-logcat.txt`、`commands.ndjson` 和 `original-state.json`。控制器四轮均 `completed-observation`、`completeWindow=true`、`restorationVerified=true`；instant profile 四轮均有效。

| 轮次 | PID | 观测秒数 | 最后已报告 slot/shared 次数 | fallback / copy failure | 恢复 |
|---|---:|---:|---:|---:|---|
| A1 | 16096 | 60.430 | 0 / 1800 | 0 / 0 | 通过 |
| B1 | 16769 | 60.379 | 1800 / 0 | 0 / 0 | 通过 |
| B2 | 17454 | 60.335 | 1800 / 0 | 0 / 0 | 通过 |
| A2 | 18125 | 60.359 | 0 / 1800 | 0 / 0 | 通过 |

每轮仅一个当前 PID 的 config、一套不变的 native importer identity，7条路径报告单调推进。周期报告最后 `final=0`；这些是停止前已报告计数，并非宣称捕获了 teardown 的最终总数。原 settings/properties 均逐项恢复，screen 状态也与初始记录一致，`restoreErrors=[]`、自动亮度 scalar 未变化。

全部采样中 GPU `thermal_pwrlevel=0`，`max_gpuclk=652800000`；CPU2 scaling 最大值始终2342400kHz，panel thermal0。它们是可见限制节点的证据，不是整机全部热管理机制都未介入的证明。

所有已记录 start/sample 的硬解均为 `surfacetexture`，estimated-vf-fps29.970030，decoder/frame/VO-delayed drop计数始终0；四类 native failure（fence_create_failed、reap_stuck、latch_timeout、stale_drop）均0。最后两条 YUV 周期报告间 swap-success 速率 A1/B1/B2/A2 分别为29.9666/29.9706/29.9694/29.9689次每秒；这证明提交持续推进，不等于面板逐帧光学测量。

## 20–55秒指标

窗口按控制器 `elapsedSeconds` 的20≤t≤55秒取样，非精确媒体PTS对齐；Lab属性约10秒刷新一次。每轮16条样本均通过硬解、路由、HDR/背光、native错误和GPU cap检查。全轮累计 FBO 报告证实单一路径持续工作且无 fallback/failure，因此下表可描述该轮窗口指标；不能声称窗口内每条样本在当时都已经收到足够 FBO 报告。

算术均值从原始逐行数据重算：GPU MHz=`gpu_hz/1e6`；忙碌率使用驱动百分比；代理=`mean(MHz_i×busy_i/100)`，绝非两个均值的乘积；CPU100%表示占满一个核心。

| 顺序 | GPU MHz | GPU busy % | 逐样本 MHz×busy 代理 | CPU %（单核100%） |
|---|---:|---:|---:|---:|
| A1 | 251.875 | 64.875 | 160.484 | 61.769 |
| B1 | 296.063 | 60.688 | 177.531 | 60.539 |
| B2 | 307.800 | 60.188 | 183.828 | 61.436 |
| A2 | 315.000 | 58.313 | 183.684 | 61.889 |
| A 两轮等权平均 | 283.438 | 61.594 | 172.084 | 61.829 |
| B 两轮等权平均 | 301.931 | 60.438 | 180.679 | 60.987 |

本组 B 相对 A 的频率均值+6.52%、busy−1.88%、逐样本乘积代理+4.99%、CPU−1.36%。这些是此组观测值，不能归因成候选导致的功耗变化：A1相对其余轮有明显更低工作点，B2与A2代理基本相同，且热状态/顺序未匹配。

新工具的逐样本 FBO 门要求在 playbackStart+10秒后至少两次新报告，实际每300帧约10秒才有一条，故上述20–55秒的早期样本尚不能实时通过该门。严格保留此门后的敏感性结果如下（未改工具门）：

| 轮次 | 样本数 | 实际控制器窗口秒 | GPU MHz | busy % | 代理 | CPU % |
|---|---:|---|---:|---:|---:|---:|
| A1 | 12 | 30.47–54.97 | 264.500 | 62.917 | 163.511 | 61.768 |
| B1 | 11 | 31.37–53.53 | 315.000 | 58.091 | 182.986 | 59.910 |
| B2 | 11 | 31.20–53.40 | 313.709 | 59.273 | 184.846 | 61.186 |
| A2 | 11 | 31.09–53.02 | 315.000 | 58.091 | 182.986 | 62.084 |

此更严格子集同样未显示稳定的 GPU 优势。样本相关、仅每组两次独立播放，不能将每条采样当独立实验来给出很高的统计置信度。

## 起始条件与判定边界

| 轮次 | prelaunch battery/VTS °C | 第一个已播放样本 battery/VTS °C | 首个播放样本 t秒 | 末采样 battery/VTS °C |
|---|---|---|---:|---|
| A1 | 24.3 / 30.7 | 24.2 / 31.2 | 1.707 | 26.1 / 32.7 |
| B1 | 26.1 / 32.7 | 26.1 / 32.7 | 0.471 | 27.1 / 33.6 |
| B2 | 27.1 / 33.6 | 27.1 / 33.4 | 0.326 | 28.1 / 34.3 |
| A2 | 28.1 / 34.0 | 28.1 / 34.0 | 0.459 | 29.1 / 34.7 |

四轮未等待同一起播热状态，USB充电、亮度64，不能用终温或温升差宣称降热；A1更冷也可能影响调频与驱动状态。当前证据证明 PoC 在真实播放中命中且没有观测到计数异常，但没有完成相同PTS逐像素、生命周期全覆盖或用户画面验收。

判定：不满足“保留有明显效果的优化”的生产采用门槛。可保留默认关闭的实验供后续更受控测量；本结果既不证明明显节能，也不足以严格否定很小的驱动开销收益。频率×busy只反映粗略工作点代理，无法测量DDR、硬解块、背光、SoC或整机瓦数。

## 复核方法与输入哈希

执行方式：用 Python 标准库逐行读取四轮 `samples.ndjson`；按上述控制器窗口筛选，重算四列算术均值，并独立检查原始日志/summary的路径计数、PID、路由、cap、错误与恢复。严格子集复用了当前 `tool/lg_p84_thermal_round.py` 的 `input_fbo_error(state, requested, since=playbackStartAt+10)`；未修改该函数或任何实现。没有重新运行播放。

复现主表的最小计算：

```python
import json, statistics
from pathlib import Path
root = Path('docs/validation/lg-p84-thermal-review-20261029')
for name in ['A1', 'B1', 'B2', 'A2']:
    rows = [json.loads(s) for s in (root / f'input-fbo-ab-{name}' / 'samples.ndjson').read_text().splitlines()]
    rows = [r for r in rows if 20 <= r['elapsedSeconds'] <= 55]
    f = [float(r['raw']['gpu_hz']) / 1e6 for r in rows]
    b = [r['gpuDriverReportedBusyPercent'] for r in rows]
    c = [r['cpuDelta']['processOneCorePercent'] for r in rows]
    print(name, len(rows), statistics.mean(f), statistics.mean(b),
          statistics.mean(x*y/100 for x,y in zip(f,b)), statistics.mean(c))
```

原始文件 SHA256（独立重算）：

### A1

- `summary.json`：`2850e5be408e70f74e877b95604d53bc5a200a9de55c7d51a1b279923aa2e684`
- `samples.ndjson`：`e4eebc8c15e17fb7d93ca4ff9461388b34dd2e07e8e50c735a5ae4b3cf83ff10`
- `flutter-logcat.txt`：`92f8444b3b91b15c43b7e5880fcd7a3da31c8509349bfe0a444c345c79c63494`

### B1

- `summary.json`：`c907572ab18b214fee4e677040f468e360bf34b9a5584c939a63437ea78ddc2c`
- `samples.ndjson`：`97e516a32bac5479578817bb33089eb1dc0a9adbb434da75877dd7edbcbe4ae0`
- `flutter-logcat.txt`：`31418150164f372dff00bbf5e2d662c9611ae8f2fdfacbc57d38492ec240817e`

### B2

- `summary.json`：`eaf3fd136678249462ba83a6b2c826df23380b5980de0754b0f7f8120e2a2024`
- `samples.ndjson`：`38f27b09191e3d10959970f3056d09f84c3014e7b5e58450c203018526fa1897`
- `flutter-logcat.txt`：`2372bd26803be33f9c2b50a679d58fb045de04e96aff5fd028ed04499aac45e3`

### A2

- `summary.json`：`bf06af5eefbf13792c76247f8178358d47cc3077b63ecf2263449ca936a6a054`
- `samples.ndjson`：`32bc1d10c1a2048e15122fe8fce804e2621da86669bdb9eb2647cd31ef868532`
- `flutter-logcat.txt`：`93cc37a89d99396b8b15e43b310abc1a6b753c5a90e9898c8b76c36ca4788860`


结束时重新检查 `git status --short`，顶层 dirty/untracked 路径列表与开始时一致（验证目录原已整体 untracked，新文档位于其中）；本任务未修改任何实现或原始证据。其他 agent 并发写入的内容不由本任务清理或覆盖。

轮后补充：LG 上该路径的 1,232,790,317 字节片源于四轮之后完整经 ADB 回读并计算 SHA-256，结果为 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`，与历史 receipt 一致；这不能单独证明各轮之间文件没有变化。
