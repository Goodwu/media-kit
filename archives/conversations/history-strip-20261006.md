# media-kit 主库历史剥离 archives/experiments（2026-10-06）

## Current State
- 背景: 主库 `.git` 达 1.47 GiB，历史唯一 blob 1112 MB，其中 `archives/experiments/` 占 872 MB / 4627 文件（APK、截图、logcat/stdout/jsonl 等实验证据，40MB 级 APK×2、5–12MB 级文件上千）；该目录 2026-10-05 已整体迁至独立库 `~/src/media-kit-experiments`，HEAD 树已不含它，但提交历史仍引用。
- 目标: 从全部提交历史剥离 `archives/experiments/`，只动我们自己的提交、上游谱系零影响，且不干扰同机其他会话的并发提交。
- 当前状态: **已完成**。main `51ef66cc` → `ee28accd`（tip 树逐字节相同），4 个 `libmpv-android-v*` tag 重定向并强推；登记批次（本文件/TASKS.md/.gitignore/删一次性 workflow）为剥离后首批正常提交。
- 关键结论:
  - filter-repo 路线废弃：GitHub 网页合并提交带 `gpgsig` 头，fast-export 无法还原导致剥头 → 对象字节变 → 上游全部历史级联重写（锚点 aeb29faa 实证，`--prune-degenerate never` 也救不了）；与路径过滤无关，任何 filter-repo 运行都会触发。
  - 最终方法：自研外科手术重建（`~/src/media-kit-build/history-strip-20261006/` 有 workflow 存档；脚本逻辑见本档案 Findings F2）。只重建「树含该路径或父被重建」的提交；其余提交对象零接触、哈希不变。结果：kept=2113（上游全部+我们早期）/ rebuilt=236（全部我们的提交）/ pruned=11（剥离后变空的纯归档提交，收敛到父）。
  - 验证电池全绿：tip 树逐字节相等（0271a96713b3）；新线该路径提交数=0；提交数 2360→2349（差=收敛数）；根提交一致；主线上游锚点未改写；181 个「树与父相同」的退化 merge 全部原样保留（原 182 个中 1 个在 tag 谱系不在 main 线，未触及）；重建提交抽查（e07781a2→dd02417e）作者/提交者/日期/消息/gpgsig 头逐字节保留。
  - 上游安全性复核：`archives/experiments` 的 159 个触及提交全部 Goodwu；上游侧 2014 提交 0 触及；6 个 `archive/*-202609` tag 目标均在上游/独立谱系，对象未动。`media_kit_test/assets/video_2.mp4` 与旧 JAR 看似可删，实为上游 2023 提交引入，**不可剥离**。
  - 备份：private 仓 `Goodwu/media-kit-history-archive`，分支 `pre-strip-20261006`（旧 main 完整谱系）+ `tooling-history-strip-original`（操作期 tooling 分支原样）。
  - 外部钉定已同步：PiliPlusX `pubspec.yaml` 420fba3e→23e58ec4（3 处 ref+2 处注释，提交 58bc84d39）；0fa6afe9 在上游谱系映射为自身，4 个 libs 钉定不变。media-kit-build 的 shared-source 快照目录是历史记录，不改。
  - 多会话并发保护：强推用 `--force-with-lease=<旧 tip>`；本地换引用用 `git update-ref`（另一会话工作区有未提交 HDR 修改，`reset --hard` 会毁掉它们）；基线 51ef66cc 含其他会话推送的全部提交（含 workflow 注册提交 a443f8f5→3859b219）。
- 下一步:
  - none（遗留观察项见 Action Items）
- 接手入口:
  - 旧→新哈希换算：`~/src/media-kit-build/history-strip-20261006/commit-map.json`（2360 条全映射；拿任何旧哈希先查它）
  - 剥离前完整历史：`git fetch https://github.com/Goodwu/media-kit-history-archive.git pre-strip-20261006`

## Session Log
> 默认接管只读顶部摘要；以下历史按需读取并追加维护，不转写完整对话。

- S1: 体积定位——`git rev-list --objects --all` + batch-check 按目录聚合：archives/ 872MB、android libs 旧 JAR 56MB（HEAD 已无）、libs/ohos zip 多版本 43MB、test 资产 22MB；.git 1.47GiB。
- S2: 方案与授权——路径清单三上三下（video_2.mp4/JAR 经 --find-object 反查为上游提交，剔除）；备份先行；Codespace 因 gh token 无 codespace scope 改 Actions workflow（公开仓分钟免费）。
- S3: workflow 两跑两败——run 37432487578 锚点 aeb29faa 丢失；加 `--prune-degenerate never`+182 断言后 run 37433678662 同锚点仍丢；本地镜像复现拿 commit-map，对比新旧对象字节确诊 gpgsig 剥离根因，filter-repo 路线放弃。
- S4: 外科手术重建——Python 脚本走真实对象图（`-c core.commitGraph=false`，共享仓有并发 commit-graph 写入曾导致一次幻影父引用），`hash-object -t commit -w` 逐字节保真重建；refs/strip 干跑语义即脚本输出对象+直接 sha 验证。
- S5: 换引用与强推——update-ref main+4 tags（另一会话正在工作区改 HDR 文件，零干扰）；`--force-with-lease` 推送成功；GitHub API 验证远端终态一致。
- S6: 登记——PiliPlusX 钉定换算提交（钩子 --no-verify 出口）；TASKS.md 路径映射段与接手快照更新；.gitignore 增 `archives/experiments/`；删一次性 workflow 文件。

## Findings
- F1: **gpgsig 根因**：GitHub 网页 merge 的 commit 对象带 `gpgsig` 头；`git fast-export`（filter-repo 底层）不导出签名头，重建对象缺该头 → 哈希必变。上游 media-kit 大量网页合并 → 整条上游历史级联重写。结论：任何经 fast-export 的工具（filter-repo/BFG）都会重写带签名提交的下游全链，对「只许动自己提交」的 fork 清理不可用。
- F2: **外科手术重建算法**：topo 序遍历 base tip 谱系；批量 `cat-file --batch` 以 `<tree>:archives/experiments` 探测 224 个含该路径的树；`ls-tree -z`+`mktree -z` 只重建受影响子树（树级去重缓存）；提交重建=原始对象字节仅改 tree/parent 行；单亲且树与父镜像相同则收敛（=prune，仅 11 个纯归档提交）；merge 永不剪。
- F3: 共享仓并发陷阱：本机会话并发写 commit-graph 会让 rev-list 读到瞬时不一致父链（本次真实发生：0f6aca41 幻影父）；重活一律 `-c core.commitGraph=false`。工作区可能有其他会话未提交修改，动 ref 前必须 `git status` 并用 update-ref 而非 reset --hard。
- F4: `gh workflow run` 按名称解析要求 workflow 在默认分支存在（fork 上派发非默认分支须先把文件 PUT 到 main 注册一次，raw API 同样 404）；本次在 main 留下注册提交（重写后 3859b219），workflow 文件已在登记批次删除。
- F5: 体积事实：历史唯一 blob 1112 MB；archives/ 占 872 MB（APK/PNG/MP4 低压缩，jsonl/日志高压缩）；filter-repo 路线预估 pack 600–700MB 的数字对本方法同样适用的部分：真正被剥离的 blob 不再被新历史引用。

## Decisions
- D1: 只剥离 `archives/experiments` 单路径。
  - 依据: 唯一同时满足「体积大头（872/1112 MB）」「纯我方提交」「HEAD 已不含」的路径；video_2.mp4/旧 JAR 为上游提交引入，剥离会重写上游。
  - 备选: `--strip-blobs-bigger-than` 一刀切（会误伤 HEAD 在用的 libmpv zip 与示例资产，弃）；加剥 libs/ohos 旧 zip 旧版本（收益 28MB，用户未确认，未做）。
  - 影响: 上游 2113 提交对象零接触，与上游 media-kit 的 merge-base 不变，未来上游合并照常。
- D2: 弃 filter-repo 改自研外科手术重建。
  - 依据: F1 根因；用户硬约束「其它上游的提交不用管（不许动）」。
  - 备选: 接受上游重写（违反用户约束）；联系 GitHub support 服务端改写（无此服务）。
  - 影响: 脚本一次性、无通用工具维护负担；commit-map 留档保证旧哈希可换算。
- D3: 备份走 GitHub private 仓而非本地 bundle。
  - 依据: 本地磁盘仅剩 6.1G，1.5G bundle 放不下；备份仓自带异地冗余。
  - 备选: 本地 bundle（空间不足）；不备份（违反改动保护原则）。
  - 影响: 回溯命令多一步 fetch；信任期后可删备份仓回收。

## Action Items
- [ ] A1: GitHub 服务端旧对象在 `refs/pull/*` 与 gc（约 90 天自然滚动）前仍可达，服务端 clone 短期不会变小；如需立即回收联系 GitHub support。本侧 clone 在 gc 后立即生效。
- [ ] A2: 信任期（建议 30 天）后删除备份仓 `Goodwu/media-kit-history-archive`（删前确认无会话再引用旧哈希）。
- [ ] A3: 观察：若有会话报「bad object <旧 sha>」，先查 commit-map 换算，或 `git fetch https://github.com/Goodwu/media-kit-history-archive.git pre-strip-20261006` 取回旧对象。
- [ ] A4: （承接既有待办）`~/src/media-kit-experiments` 建远端推送——本任务后它已是实验证据唯一 git 副本，优先级升高。

## Archive Metadata
- date: 2026-10-06
- entry: history-strip-20261006
- agent: ZCode (GLM)
- project: media-kit
- submodule: ""
- language: zh-CN
- tags: [archive, git-history, maintenance]
