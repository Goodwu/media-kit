# Debug 编译源码约束（2026-10-12）

## Current State

用户要求在 PiliPlusX 与 media-kit 的 `AGENTS.local.md` 加入 Debug 编译与测试硬约束，适用于所有平台，禁止使用钉定版本及预编译二进制，要求使用仓库最新源码或本地修改文件（含项目依赖及原生库），违者任何情况下判定测试失败。

已在本项目 `AGENTS.local.md` 追加该规则。仅完成文档核验，未构建、未提交。原生 Mechanical Worker 任务；Lead 已完成 V0 规则一致性和原意核验，git diff --check 通过。
