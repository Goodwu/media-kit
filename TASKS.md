# TASKS.md

## Now（当前推进，最多 3 条）
- [x] 修复跨平台 native video output 重建与释放生命周期
  - status: done
  - context: archives/conversations/native-output-rebuild-20260920.md
  - acceptance: 代码、契约测试和 staged diff 检查通过；完成一次 Git 提交

## Next（近期候选，最多 10 条）
- [ ] 在真实 macOS/OHOS 设备上继续验证 native output 生命周期
  - status: todo
  - context: archives/conversations/native-output-rebuild-20260920.md

## Blocked（等待输入或外部条件）
- （暂无）

## Recently Done（最近完成，最多 5-10 条）
- （暂无）

## 规则
- 新任务必须写入本文件
- 完成任务必须打勾
- 建议任务状态：todo / in_progress / blocked / done
- 活跃任务建议填写 `context: archives/conversations/<topic>.md`
- 按需从本文件定位任务、读取有效 context，并在需要时检索 active memory
- 旧完成项超过上限时，压缩进对应 conversation 后从本文件移除
- 每次推进使用 Git 提交信息记录变更
