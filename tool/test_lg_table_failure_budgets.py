"""Table failure-budget state machine tests (review P1: rebuild storm).

Replicates the exact budget semantics of vo_gpu_next's table state machine:
- seed budget: fusion_table_note_failure counts, >=2 disables the table;
  a successful seed (READY) resets it to 0.
- consume budget (the fix): consumer/commit failures after READY count
  separately, are NOT reset by a successful seed, and only a COMMITTED
  fused frame resets them; >=2 disables table AND fusion (sticky).

Verifies the reviewer's constructed loop (seed success -> consume fail,
repeated) terminates in bounded rebuilds, and that genuine geometry
transitions (fail -> reseed -> committed recovery) survive.
"""
import unittest

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

# 与 vo_gpu_next.c 状态机一致的 Python 副本（计数语义逐行对应）
class TableStateMachine:
    def __init__(self):
        self.table_enabled = True
        self.fusion_disabled = False          # 非表路径粘性
        self.table_failures = 0               # seed 预算（ready 清零）
        self.table_consume_failures = 0       # 消费预算（仅 commit 成功清零）
        self.state = 'OFF'                    # OFF/SEEDING/READY
        self.rebuilds = 0

    def note_failure(self):
        self.table_failures += 1
        if self.table_failures >= 2:
            self.table_enabled = False

    def seed_success(self):
        # poll COMPLETE -> READY（真实代码在此清 seed 预算）
        self.state = 'READY'
        self.table_failures = 0
        self.rebuilds += 1

    def fused_commit_ok(self):
        self.table_consume_failures = 0

    def consume_failure(self):
        # fix30/fix31 非粘性表路径分支
        self.table_consume_failures += 1
        if self.table_consume_failures >= 2:
            self.table_enabled = False
            self.fusion_disabled = True
        self.note_failure()
        self.state = 'OFF'


class BudgetTests(unittest.TestCase):
    def test_rebuild_storm_terminates(self):
        # 复审构造的循环：seed 成功 -> 消费失败 -> 重建 -> 消费失败 ...
        m = TableStateMachine()
        m.seed_success()
        for _ in range(10):
            self.assertTrue(m.table_enabled, 'must still be trying early')
            m.consume_failure()          # 内部融合失败，回退普通渲染
            if not m.table_enabled:
                break
            m.seed_success()             # seed 成功不证明消费会成功
        self.assertFalse(m.table_enabled, 'consume budget must disable')
        self.assertTrue(m.fusion_disabled)
        self.assertLessEqual(m.rebuilds, 2 + 1, 'bounded rebuilds (2 fails -> disable)')

    def test_geometry_transition_survives(self):
        # 真实过渡：失败 -> 重建 -> commit 成功恢复（预算清零）
        m = TableStateMachine()
        m.seed_success()
        m.consume_failure()              # resize 后旧表被拒
        self.assertTrue(m.table_enabled)
        m.seed_success()                 # 新尺寸重建
        m.fused_commit_ok()              # 表驱动帧提交成功
        self.assertEqual(m.table_consume_failures, 0)
        self.assertTrue(m.table_enabled)
        # 第二次过渡同样存活
        m.consume_failure()
        m.seed_success()
        m.fused_commit_ok()
        self.assertTrue(m.table_enabled)
        self.assertEqual(m.rebuilds, 3)

    def test_consume_budget_not_reset_by_seed(self):
        m = TableStateMachine()
        m.seed_success()
        m.consume_failure()
        m.seed_success()                 # 仅 seed 成功
        self.assertEqual(m.table_consume_failures, 1,
                         'seed success must NOT clear the consume budget')

    def test_persistent_seed_failure_disables(self):
        # 原持续 seed 失败语义保留
        m = TableStateMachine()
        m.note_failure()
        self.assertTrue(m.table_enabled)
        m.note_failure()
        self.assertFalse(m.table_enabled)


class SourceTests(unittest.TestCase):
    """Pin the real code's budget semantics (vo_gpu_next.c)."""

    SOURCE = Path('/Users/wuweiwei1/src/mpv/video/out/vo_gpu_next.c').read_text()

    def test_consume_budget_exists_with_threshold_and_sticky(self):
        block = self.SOURCE
        self.assertIn('p->table_consume_failures >= 2', block)
        self.assertIn('reason=consume-failures', block)
        # 消费预算触发时表+融合同时禁用（风暴封顶）
        self.assertIn('p->fusion_table_enabled = false;\n            p->fusion_disabled = true;', block)

    def test_consume_budget_cleared_only_by_committed_frame(self):
        self.assertIn('p->table_consume_failures = 0;', self.SOURCE)
        # 清零位于 commit 成功路径内
        anchor = 'if (p->ra_ctx->fns->yuv_fusion_commit(p->ra_ctx, desc, confirmed)) {'
        idx = self.SOURCE.index(anchor)
        clear = self.SOURCE.index('p->table_consume_failures = 0;', idx)
        self.assertLess(clear, idx + 400, 'clear must sit inside the commit-ok branch')

    def test_ready_still_resets_seed_budget_only(self):
        anchor = self.SOURCE.index('event=ready cache_id=')
        seg = self.SOURCE[anchor-300:anchor]
        self.assertIn('p->table_failures = 0', seg)
        self.assertNotIn('table_consume_failures = 0', seg)


if __name__ == '__main__':
    unittest.main()
