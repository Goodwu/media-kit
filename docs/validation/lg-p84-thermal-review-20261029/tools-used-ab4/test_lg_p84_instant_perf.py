import importlib.util
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).parent))
import lg_p84_instant_perf as m
import lg_p84_thermal_round as thermal


class InstantPerfTests(unittest.TestCase):
    def test_cpu_uses_device_ticks_and_uptime_not_host_sample_delay(self):
        before={'deviceUptime':10,'pid':'1','processStartTicks':1,'appCpuTicks':100,
                'tasks':[{'tid':'2','name':'vout','ticks':50,'startTicks':2}],
                'raw':{'cpu_total':'cpu 100 0 100 800 0 0 0 0\ncpu0 25 0 25 200 0 0 0 0'}}
        after={'deviceUptime':12,'pid':'1','processStartTicks':1,'appCpuTicks':250,
               'tasks':[{'tid':'2','name':'vout','ticks':150,'startTicks':2}],
               'raw':{'cpu_total':'cpu 200 0 200 1400 0 0 0 0\ncpu0 50 0 50 350 0 0 0 0'}}
        d=m.delta(before,after,100)
        self.assertEqual(d['processOneCorePercent'],75)
        self.assertEqual(d['systemBusyPercent']['cpu'],25)
        self.assertEqual(d['threadOneCorePercent'][0]['percent'],50)
        after['processStartTicks']=9
        self.assertIsNone(m.delta(before,after,100)['processOneCorePercent'])

    def policy_state(self, expected='1'):
        zero='kind=import instance=0x1 start_ns=1 defer_publish_flush='+expected+' publish_flush=0 publish_deferred=0 retire_flush=0 fence_create_failed=0 reap_stuck=0 latch_timeout=0 stale_drop=0'
        active='publish_deferred' if expected=='1' else 'publish_flush'
        work=zero.replace(' '+active+'=0',' '+active+'=100').replace('retire_flush=0','retire_flush=4')
        return {'nativeImportIdentity':{'instance':'0x1','start_ns':'1'},'nativeImportChanged':False,'hostMonotonic':12,
                'native':[{'hostMonotonic':1,'line':zero},{'hostMonotonic':11,'line':work}]}

    def test_publish_policy_requires_effective_fresh_fixed_instance_counters(self):
        state=self.policy_state()
        self.assertIsNone(thermal.publish_policy_error(state,'1'))
        self.assertIsNone(thermal.native_failure_reason(state))
        self.assertIsNone(thermal.publish_policy_error(self.policy_state('0'),'0'))
        self.assertEqual(thermal.publish_policy_error(state,'0'),'native-import-publish-policy-mismatch')
        for key in ['fence_create_failed','reap_stuck','latch_timeout','stale_drop']:
            bad=self.policy_state();bad['native'][-1]['line']=bad['native'][-1]['line'].replace(key+'=0',key+'=1')
            self.assertEqual(thermal.native_failure_reason(bad),'native-import-failure-counter:'+key)
        state['hostMonotonic']=32
        self.assertEqual(thermal.publish_policy_error(state,'1'),'stale-native-import-policy')
        state=self.policy_state();state['nativeImportChanged']=True
        self.assertEqual(thermal.publish_policy_error(state,'1'),'native-import-instance-rebuilt')
        state=self.policy_state();state['native'][-1]['line']=state['native'][0]['line']
        self.assertEqual(thermal.publish_policy_error(state,'1'),'native-publish-policy-has-no-effective-work')

    def test_no_periodic_gpubusy_reader(self):
        from unittest.mock import patch
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            adb=m.InstantAdb('S',Path(d));scripts=[]
            raw='@@ uptime\n1.0 0\n@@ battery_type\nbattery\n@@ battery_temp\n32000\n@@ vts_type\nvts\n@@ vts_temp\n360\n'
            with patch.object(adb,'lab_pid',return_value=None),patch.object(adb,'screen_state',return_value={'on':True,'keyguard':False}),patch.object(adb,'shell',side_effect=lambda script:scripts.append(script) or raw):
                adb.snapshot();adb.snapshot()
            self.assertIn('/gpubusy',scripts[0])
            self.assertNotIn('/gpubusy',scripts[1])




if __name__=='__main__':unittest.main()
