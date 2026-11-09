# repo-weight-remediation-20261104

## Current State

- **done / 历史大文件整改+本地迁移完成（2026-11-04）**：30 个 >1MiB 自有大 blob（author=Goodwu 引入，排除构建钉定 zip `f6dfff05`）经独立镜像仓有界重写剥离并重新推送远端；本地仓已重新 clone 就位原路径，旧仓 `media-kit-old-20261104` 保留至 2026-11-11。全量备份与恢复入口见 `docs/validation/ARCHIVE.md`。任务台账见 TASKS.md `REPO-WEIGHT-REMEDIATION-20261104`。
- 关键过程：V2 审核 BLOCK（3 P0：上游 369 处 gpgsig 会被全库 filter 重序列化剥签名；worktree 全脏；TASKS 未提交+--force 冲突）→ 独立镜像仓有界重写（`--refs ^d310049f` + 上游 5 分支保护集 + preserve 四件套）→ 对象级验收（643 映射 1:1、595 变更提交字节比对全过、上游 2014 提交闭包逐位一致、fsck 干净、30/30 剥离）→ Critical Reviewer 复审 PUSH-OK → atomic+冻结 OID lease 推送 11 ref → 全新 clone 106MB 验收 → 本地迁移。
- 边界如实：PR#3 合并提交 `dd02417e` 的 GitHub web-flow gpgsig 被剥（内容已变签名必失效，新版 `26a7358c`）；远端 8 个 `refs/pull/*` 旧对象服务端仍可达；历史 checkout 不保证可构建。

## 历史区：关键依据

### 推送回执（2026-11-04，atomic + 11 条冻结 OID force-with-lease）

| ref | 旧 OID | 新 OID |
|---|---|---|
| refs/heads/main | d761922721ad8da6bb186abd270bb096100944ea | 4a8f0b78c01ad091443052706c940d89891298c4 |
| refs/heads/feature/dv | 3bdf2c6cd21860c1c258d0b75f807b743d373e4a | 171741899e6f8f797744248c7e058e655397818b |
| refs/tags/archive/ci-compat-20261028 | 9c67f5305ec52fe9e12a86cdda295711161919f0 | db34cbcf57c32927ae2eceb51350e4c2488ab848 |
| refs/tags/archive/compat-20261026 | c8c5aaab3ee777bcf1f2b87166695a9814c24772 | 7876d265532b8a94f8104b81f311cbe2036b6e89 |
| refs/tags/archive/native-ci-20261023 | d76622180dc9d082c9e690dd7d355f418627fb4a | 2431319c4ac5245b00cdbac7dc95a74f88f6e0b9 |
| refs/tags/archive/routing-20261011 | 0597c8318ccf50f0824249ceeab310632efb84ab | da278e79e7dd9f7af9c0dfc346dba2b89805ba0a |
| refs/tags/libmpv-android-v2026.011 | 3c0bfe5bd244445f98888298bb1c3bcffd0a8fe4 | 3b694d607dc82696b30e4a314051a0bc9fc1bb25 |
| refs/tags/libmpv-android-v2026.012 | 573aea8d168d4c6c167a3cb1f4ca414bd9983f7b | 99232166f73cbfbb64985f5aa8044548c6735eec |
| refs/tags/libmpv-android-v2026.013 | 7ea31c55a867d772965ca89911d7b432687826f4 | 070f44509fd5e8162a1730fb5b338684ec78e4c5 |
| refs/tags/libmpv-android-v2026.09 | 595f68483d14661684378c74a3d0e06bbfd28d4c | 18bcf22e5e9e2c79e296167344289dcf88b2d480 |
| refs/tags/libmpv-android-v2026.10 | 495629bcb66348f2545aa31b9d2cb967adf195b5 | 3fb808bfa9f812aa0d05a50fbafd9eb999911b2d |

6 个 keep tag（dev-darwin/integration-piliplusx×2/source-predidit×2/version-1.3.0）远端原样未动。
**4 个轻量 archive tag 的 ref 更新系手工按 commit-map 修正**（filter-repo 部分模式 ref-map 只含 5 个 libmpv tag）；
完整依据见 `repo-weight-remediation-20261104/attachments/tag-remap-receipt.txt` 与镜像 `filter-repo/` 元数据。

### 本地迁移回执（2026-11-04）

- 分支重建（commit-map）：compat/piliplus→7876d265、DV-BUILD-01→7cca4ba8、DV004→32d2f940、routing→da278e79、perf2/lg-p84→ff299501；7 条分支 log 主题序列逆映射验证一致。
- codex/hdr-ab-diagnostics 弃分支：cherry-pick `4bc0c9d9` 两演化文件冲突，降级归档 `~/Documents/media-kit-validation-archive/local-migration-20261104/codex-tools-4bc0c9d9/`。
- worktree：luna-ohos-e3→acbe1340、mk-verify-0c57dcd9→4e61c01d、8f00ec76→efec0948、b8da287d→befa9ef5、head-4daafd9d→bd1db98a、perf2-mk→perf2/lg-p84；patch+未跟踪回迁后 status 与迁移前回执逐行一致（回执存 `~/Documents/media-kit-validation-archive/local-migration-20261104/worktree-receipts/`）。
- 退役：`media-kit-verify-20261010@08735626`（2026-10-10 隔离验证树残留；快照本体由 bundle 保全并已验证可恢复到精确 OID。所属任务线的正式归档 `archives/conversations/media-kit-routing-20261011.md` 中无本树的直接绑定记录，引用仅为任务线背景，勿据其检索本树结论。）；bundle 可恢复。
- commit-map/ref-map 副本：`repo-weight-remediation-20261104/attachments/`。
