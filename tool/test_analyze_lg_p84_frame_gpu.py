"""Host tests for the M2' frame GPU analyzer (analyze_lg_p84_frame_gpu.py)."""
from pathlib import Path
import json
import tempfile
import unittest
import sys
sys.path.insert(0, str(Path(__file__).parent))
from analyze_lg_p84_frame_gpu import parse_log_file, reconcile, classify_tickets, compute_s0_median_ms

# ---- fixtures ----

def make_init(session='s1', mode='frame'):
    return f"MKS-FGPU-INIT session={session} mode={mode} armed=1 reason=ok prop={mode} mono_ns=1000000"

def make_ticket(session='s1', t=1, present='swap_ok', reason='', reclaim='normal',
                foreign=0, acq=1, mix=1, hw=1, route='fused', seed='0', afail='0', copies_ok=1):
    return (f"MKS-FGPU-T session={session} t={t} pts=10.0 frame=1 measure=2 submit=2 "
            f"present={present} reason={reason} reclaim={reclaim} foreign={foreign} "
            f"acq={acq} rel=1 copies_ok={copies_ok} reuse=0 renders=1 okmask=3 "
            f"mix={mix} hw={hw} route={route} seed={seed} afail={afail} segs=2")

def make_seg(session='s1', t=1, g=0, kind='render.pre', call=1, issued=1,
             tstate='resolved', cpu=1000000, elapsed=500000):
    return (f"MKS-FGPU-G session={session} t={t} g={g} kind={kind} call={call} "
            f"issued={issued} tstate={tstate} cpu={cpu} elapsed={elapsed}")

def make_copy(session='s1', c=1, t=1, pts=10.0, src='3840x1920', lease='2672x1336',
              tc=1, timer='seg', seg=1):
    return (f"MKS-FGPU-C session={session} c={c} t={t} pts={pts} src={src} "
            f"lease={lease} tc={tc} timer={timer} seg={seg}")

def make_summary(session='s1', through_t=1, through_c=1, tickets=1, copies=1,
                 mode='frame', invariant=0):
    return (f"MKS-FGPU-S session={session} through_t={through_t} through_c={through_c} "
            f"tickets={tickets} copies={copies} mode={mode} armed=1 halted=0 "
            f"bind=2 rel_result=2 rel_dn=0 rel_late=0 rel_dq=0 rel_un=0 rel_uq=0 "
            f"rel_uc=0 leak_c=0 leak_q=0 busy_n=0 busy_q=0 busy_c=0 "
            f"gl_del=64 gl_leak=0 invariant={invariant}")

def make_final(session='s1', complete=1, incomplete='none'):
    return f"MKS-FGPU-FINAL session={session} complete={complete} incomplete={incomplete}"

def write_log(lines):
    with tempfile.NamedTemporaryFile(mode='w', suffix='.log', delete=False) as f:
        for line in lines:
            f.write(line + '\n')
        return f.name


class AnalyzerTests(unittest.TestCase):
    def test_valid_single_round(self):
        path = write_log([
            make_init(),
            make_ticket(t=1),
            make_seg(t=1, g=0, kind='render.pre'),
            make_seg(t=1, g=1, kind='copy', tstate='resolved', elapsed=800000),
            make_copy(t=1),
            make_summary(tickets=1, copies=1),
            make_final(),
        ])
        records = parse_log_file(path)
        errors = reconcile(records)
        self.assertEqual(errors, [])

    def test_missing_final_rejected(self):
        path = write_log([make_init(), make_ticket(t=1)])
        records = parse_log_file(path)
        errors = reconcile(records)
        self.assertTrue(any('missing FINAL' in e for e in errors))

    def test_duplicate_tseq_rejected(self):
        path = write_log([make_init(), make_ticket(t=1), make_ticket(t=1), make_final()])
        records = parse_log_file(path)
        errors = reconcile(records)
        self.assertTrue(any('duplicate' in e for e in errors))

    def test_invariant_violation_rejected(self):
        path = write_log([
            make_init(),
            make_ticket(t=1),
            make_summary(invariant=1),
            make_final(),
        ])
        records = parse_log_file(path)
        errors = reconcile(records)
        self.assertTrue(any('invariant' in e for e in errors))

    def test_old_timer_detection(self):
        path = write_log([make_init(), 'MKS-GPU kind=input-copy instance=1 supported=1'])
        from analyze_lg_p84_frame_gpu import detect_old_timer_lines
        records = parse_log_file(path)
        self.assertTrue(detect_old_timer_lines(path))
    def test_s0_classification(self):
        path = write_log([
            make_init(),
            make_ticket(t=1, copies_ok=1),
            make_seg(t=1, g=0, kind='render.pre', tstate='resolved'),
            make_seg(t=1, g=1, kind='copy', tstate='resolved'),
            make_copy(t=1),
            make_summary(tickets=1, copies=1),
            make_final(),
        ])
        records = parse_log_file(path)
        layers = classify_tickets(records)
        self.assertEqual(len(layers['S0']), 1)
        self.assertEqual(len(layers['X-invalid']), 0)

    def test_foreign_ticket_not_s0(self):
        path = write_log([
            make_init(),
            make_ticket(t=1, foreign=4),
            make_summary(tickets=1),
            make_final(),
        ])
        records = parse_log_file(path)
        layers = classify_tickets(records)
        self.assertEqual(len(layers['S0']), 0)
        self.assertEqual(len(layers['X-foreign']), 1)

    def test_swap_fail_ticket_not_s0(self):
        path = write_log([
            make_init(),
            make_ticket(t=1, present='swap_fail'),
            make_summary(tickets=1),
            make_final(),
        ])
        records = parse_log_file(path)
        layers = classify_tickets(records)
        self.assertEqual(len(layers['S0']), 0)
        self.assertEqual(len(layers['X-invalid']), 1)

    def test_s0_median(self):
        path = write_log([
            make_init(),
            make_ticket(t=1),
            make_seg(t=1, g=0, elapsed=1000000),
            make_seg(t=1, g=1, elapsed=2000000),
            make_copy(t=1),
            make_summary(tickets=1),
            make_final(),
            make_ticket(t=2),
            make_seg(t=2, g=0, elapsed=3000000),
            make_seg(t=2, g=1, elapsed=4000000),
            make_copy(t=2),
            make_summary(through_t=2, tickets=2, copies=2),
            make_final(),
        ])
        records = parse_log_file(path)
        layers = classify_tickets(records)
        # S0 has 2 tickets: 3ms and 7ms; median = 5ms
        self.assertEqual(len(layers['S0']), 2)
        median = compute_s0_median_ms(records, layers)
        self.assertAlmostEqual(median, 5.0, places=1)

    def test_pair_reduction(self):
        # Test G-9 reduction computation
        sys.path.insert(0, str(Path(__file__).parent))
        from analyze_lg_p84_frame_gpu import compute_reduction
        self.assertAlmostEqual(compute_reduction(10.0, 8.0), 0.2)
        self.assertAlmostEqual(compute_reduction(10.0, 10.0), 0.0)
        self.assertIsNone(compute_reduction(0, 8.0))
        self.assertIsNone(compute_reduction(None, 8.0))

    def test_prop_mismatch_rejected(self):
        path = write_log([
            make_init(mode='frame'),
            make_ticket(t=1),
            make_summary(mode='frame-span'),
            make_final(),
        ])
        records = parse_log_file(path)
        errors = reconcile(records)
        self.assertTrue(any('mismatch' in e.lower() or 'prop' in e.lower() for e in errors))


if __name__ == '__main__':
    unittest.main()
