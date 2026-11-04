# 验证产物归档约定（2026-11-04 起）

## 背景

仓库历史曾随验证轮累积 >1MiB 二进制产物（uv-probe/atlas 探针、未 strip 的 .so、
全屏截图、native-candidate.json 构建转储等），导致 pack 膨胀至 633 MiB。
2026-11-04 已将 30 个历史大 blob 从全部公开分支剥离并重新发布
（见 `archives/conversations/repo-weight-remediation-20261104.md`）。

## 规则

1. **入库**：验证报告（.md）、summary/json 小证据、脚本、构建身份文件——照常提交。
2. **外置**：单文件 >1 MiB 的二进制（`*.uv-probe.bin`、`*.half-probe.bin`、`*.f32`、
   `*atlas*.bin`、`*libmpv-unstripped.so`、`*screencap_*.png`、`*native-candidate.json`，
   见 `.gitignore`）不提交，放外部归档目录，**并在本轮验证报告正文中写明归档绝对路径**。
3. `.gitignore` 挡掉的模式若确需入库（如某探针恰好是验收关键且必须可复现），显式
   `git add -f` 并在提交消息说明理由，评审时按特例审查。

## 归档位置与检索

- **整改前全量备份**：`~/Documents/media-kit-validation-archive/`
  - `media-kit-pre-rewrite-20261104.bundle`（265 MB，重写前全部 refs 的完整 git 历史，
    `git clone <bundle>` 后 `git show <旧提交>:<路径>` 可取任意被剥文件）；
  - `blobs-20261104/`（30 个剥离 blob 的原样导出 + `MANIFEST.sha256`，逐文件 sha256 可验）；
  - `local-migration-20261104/`（本地迁移回执、worktree patch、codex 工具归档）。
- **旧仓现场**：`/Users/wuweiwei1/src/media-kit-old-20261104`（保留至 2026-11-11，
  含 2026-11-04 前的完整工作区与全部旧 refs/worktree 历史）。
- **新大产物归档位置**：验证轮新建目录与 `docs/validation/<task>/` 同构，
  放 `~/Documents/media-kit-validation-archive/artifacts/<task>/`。

## 校验方法

```bash
# 验证某个归档 blob 与历史一致
shasum -a 256 ~/Documents/media-kit-validation-archive/blobs-20261104/<file>
# 与 blobs-20261104/MANIFEST.sha256 中该 blob 的第三列比对

# 从 bundle 恢复任一历史文件
git clone ~/Documents/media-kit-validation-archive/media-kit-pre-rewrite-20261104.bundle /tmp/recover
git -C /tmp/recover show <旧commit-sha>:<path>
```

## 旧 sha 引用

历史文档中引用的旧提交 sha（2026-11-04 前）不再指向当前历史。查询映射：
`~/Documents/media-kit-validation-archive/rewrite-mirror.git/filter-repo/commit-map`
（或仓内副本 `archives/conversations/repo-weight-remediation-20261104/attachments/commit-map.txt`）。
