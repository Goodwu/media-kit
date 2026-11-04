# 证据提交说明（2026-11-04，用户裁决：只留 summary+脚本）

本目录入库内容：**summary 类**（各轮 `summary.md`/`fast-sub1s-summary.md`/`README.md`/`timeline.md` 与本说明）、**脚本**（`tools/` 及各轮目录下 `*.py`/`*.sh`/`instrumentation.diff`）、**构建身份锚点**（`build-identity*.json`/`source-sha256.txt`/`source-identity.txt`/`identity.txt`/`install-verify*.txt`/`*.native-verification.json`/git 基线快照，均为 KB 级，是 summary 中 APK SHA 与源码身份结论的溯源依据）。

**不入库但保留在磁盘**（.gitignore 本目录白名单外）：原始全量 logcat（`logcat-*.txt`）、SurfaceFlinger 密集采样（`dense-samples.txt`）、逐帧导出（`presents.csv`/`intervals.csv`）、截图（`*.png`）、`host-events.ndjson`/`driver.log`/`sample-*.txt` 等——合计约 290 MB，可由脚本+源码复跑再生；如需离线深查原始数据，直接读本目录磁盘文件。

3 个 APK 副本一律不入库（SHA 见 identity 文件）。

最终验收基线（用户面板人眼终裁 2026-11-04，PiliPlus dev p4 `22e15c40…`）：HOME 返回出画面 = 连接热 ≈2 s / 连接冷 ≈4–5 s（修前 8–10 s+）；手动拖进度条 2–4 s；"无法继续播放"事件定性为该片播放地址过期（本地文件同栈正常，`phase4-mpv/STUCK1/`）。用户终裁：结果满足要求，不再进一步优化。
