# MK-ROUTING 文档与交接入口

## 当前分层约束

[受管 YUV 输出：分层解耦与生命周期设计约束](managed-yuv-layering-contract-20261015.md) 是 `MK-ROUTING-20261011/LAYERING-20261015-r1` 的库侧规范，包含 L01—L12 和 L-A01—L-A16。它约束后续实现，不表示普通 owner 或设备验收已经完成。

[PiliPlusX 对接契约](https://github.com/Goodwu/PiliPlusX/blob/routing/MK-ROUTING-20261011/docs/plans/media-kit-layering-integration-contract-20261015.md) 承接应用边界与 APP-L01—APP-L08；不得在 App 另建厂商协议。

## 原任务接续

- [中央执行方案](media-kit-routing-implementation-20261011.md)：继续原任务，§13 的动态 HDR 延期范围不变；本次新增规范仅补全普通受管输出的分层/生命周期要求。
- [方案 C 历史裁决](lg-p84-yuv-window-reopen-20261014-spec-c.md)：保留已实施阶段的设计与证据；与新规范的衔接见新规范 §1，不倒改历史。
- [C4 无载体修复交接](app-pq-carrier-admission-20261015.md)：既有修复不重做；普通 owner 的后续约束转到新规范。
- [中央历史台账](media-kit-routing-handoff-20261011.json) 及各增量记录：implemented/verified 不因新增设计变回 planned，历史 pending 须结合最新 PR 回执解读。

继续 media-kit PR #4 / PiliPlusX PR #1 的既有 `routing/MK-ROUTING-20261011` 分支。接手先核最新 refs、工作区改动和 PR 回执，不从旧 main 重新开发。源码通过、完整原生产物、普通安装包及设备验收分开记录；文档更新不等于代码/功能验证。
