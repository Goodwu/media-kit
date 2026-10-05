# macOS 共享 HDR 核心修复

## Current State

2026-10-05 用户授权本地提交。提交源码来自已审 r4 46节点快照，基线 d24a59537faa8fde59b53d5b0c151b5c44a795bc。原工作树其他Android内容保留。

修复共享mpv/libplacebo HDR/DV色彩路径、Darwin完成帧资源归还、回调所有权及退出handler排空。DV枚举为状态报告，不宣称系统原生DV直通。

源码manifest SHA702da85d5b8b6c3ff6e27e0ae6117efc6a6e435a8b181e4c016de4e8981d19d1；源diff SHA4038e789f546a37484a4017db915a9af9758f0fa7d6afd5b4bd809778208daca。独立V1/API与V2 PASS。产品针对性35测试及分析通过；实际normal r4 App源绑定和两ABI mpv0.41/closure/load/sign/backend门禁通过。后续诊断入口N1三文件17测试及增量Critical PASS位于PiliPlusX集成，不改变本核心快照。

性能仍有失败记录：P5和HLG严重卡顿，正常4K亦卡顿；PQ开头卡顿后改善。P5颜色正常不证明HDR亮度或实际输出；P8.4 metadata应用、同帧EDR及最终操作回归未闭合。性能优化后续专题，无新增性能实施。

证据目录：/Users/wuweiwei1/src/media-kit-build/shared-source-snapshot-20261005-r4；macos-current-fix-commit-preparation-20261005-r1。运行/实屏结果记录于PiliPlusX archives/conversations/player-architecture-remediation.md。仅本地提交，不推送；hosted fresh及正式发布未验证。
