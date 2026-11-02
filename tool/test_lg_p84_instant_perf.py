import importlib.util
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).parent))
import lg_p84_instant_perf as m
import lg_p84_thermal_round as thermal


class InstantPerfTests(unittest.TestCase):
    def test_fbo_experiment_controls_real_path_window_and_restoration(self):
        import argparse
        import copy
        import json
        import tempfile
        from unittest.mock import MagicMock, patch
        from test_lg_p84_thermal_round import ThermalRoundTests
        for scenario in ('baseline', 'candidate', 'fallback', 'wrong-path', 'stale', 'no-progress',
                         'mapper-rebuilt', 'missing', 'readback', 'PID-reused', 'final-stale'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as d:
                expected = '0' if scenario == 'baseline' else '1'
                state = ThermalRoundTests().fbo_state(expected)
                for row in state['inputFbo']['rows']:row['hostMonotonic'] += 100
                state.update(hostMonotonic=131, playbackStartAt=100, lab={'properties':{'time-pos':'31'}},
                             labAgeSeconds=1, logcatAlive=True)
                if scenario == 'fallback':state['inputFbo']['error'] = 'input-fbo-fallback-or-copy-failure'
                if scenario == 'wrong-path':state['inputFbo']['rows'][-1]['shared_attempts'] = '1'
                if scenario == 'stale':state['hostMonotonic'] = 141
                if scenario == 'no-progress':state['inputFbo']['rows'] = state['inputFbo']['rows'][:1]
                if scenario == 'mapper-rebuilt':state['nativeImportChanged'] = True
                if scenario == 'missing':state.pop('inputFbo')
                adb=MagicMock();adb.settings.return_value={};adb.properties.return_value={thermal.INPUT_FBO_PROPERTY:'old'}
                adb.screen_state.return_value={'on':True,'keyguard':False};adb.restore.return_value=[]
                adb.wake_unprotected.return_value={'on':True,'keyguard':False}
                adb.lab_pid.side_effect = ['111',None,'111' if scenario=='PID-reused' else '123']
                adb.snapshot.return_value={'batteryC':30,'vtsC':35,'pid':'123','screen':{'on':True,'keyguard':False},
                    'raw':{'gpu_thermal_pwrlevel':'0','panel_thermal_status':'0','hdr_mode':'1','backlight':'64'}}
                def call(argv):return ('' if scenario=='readback' else expected) if argv==['shell','getprop',thermal.INPUT_FBO_PROPERTY] else ''
                adb.call.side_effect=call
                capture=MagicMock()
                final=copy.deepcopy(state)
                if scenario=='final-stale':final['hostMonotonic']=151
                capture.state.side_effect=[state,final]
                receipt=Path(d)/'source.json';receipt.write_text(json.dumps({'verified':True,'serial':'S','deviceSource':'source'}))
                args=argparse.Namespace(output=str(Path(d)/'round'),serial='S',experiment='input-fbo',
                    mode='baseline' if expected=='0' else 'candidate',duration=30,interval=2,st_fbo=expected,
                    source_receipt=str(receipt),source_hash=None,source='source',reference_start=None,
                    instant_enabled=True,expected_panel_thermal_status='0',expected_backlight=64,brightness=64,
                    allow_unprotected_menu=False,tap=None)
                with patch.object(thermal,'Adb',return_value=adb),patch.object(thermal,'LogCapture',return_value=capture), \
                        patch.object(thermal.time,'monotonic',return_value=131),patch.object(thermal,'runtime_error',return_value=None):
                    result=thermal.run(args)
                self.assertTrue(result['restorationVerified']);adb.restore.assert_called_once()
                self.assertEqual(result['requestedVideoSync'],'display-resample')
                self.assertEqual(result['requestedDeferPublishFlush'],'0')
                self.assertIn(['shell','setprop',thermal.INPUT_FBO_PROPERTY,expected],[c.args[0] for c in adb.call.call_args_list])
                if scenario in ('baseline','candidate'):
                    self.assertEqual(result['status'],'completed-observation',result)
                    self.assertTrue(result['inputFboVerified']);self.assertTrue(result['completeWindow'])
                else:
                    self.assertNotEqual(result['status'],'completed-observation',result)
                    self.assertIn('fbo',result['reason'].lower())

    def test_fbo_profile_summary_never_accepts_controller_without_effective_gate(self):
        import json
        import tempfile
        from unittest.mock import patch
        controller={'requestedVideoSync':'display-resample','expectedPanelThermalStatus':'0',
                    'status':'completed-observation','completeWindow':True,'restorationVerified':True,
                    'initial':{'raw':{'gpu_thermal_pwrlevel':'0'}},'inputFboValidationRequired':True,'requestedInputFbo':'1'}
        row={'elapsedSeconds':31,'runtime':{'playbackStartAt':100},'raw':{
            'gpu_thermal_pwrlevel':'0','hdr_mode':'1','backlight':'255','panel_thermal_status':'0'}}
        for verified in (False, True):
            with tempfile.TemporaryDirectory() as d,patch.object(thermal,'runtime_error',return_value=None), \
                    patch.object(thermal,'native_failure_reason',return_value=None),patch.object(thermal,'input_fbo_error',return_value=None):
                output=Path(d);(output/'samples.ndjson').write_text(json.dumps(row)+'\n')
                controller['inputFboVerified']=verified
                summary=m.summarize(output,controller,'source')
                self.assertEqual(summary['validCompletedProfile'],verified)
                self.assertEqual(summary['metricsAreDiagnosticOnly'],not verified)

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

    def test_gpu_thermal_gate_distinguishes_normal_cap_and_unknown(self):
        self.assertIsNone(thermal.gpu_thermal_cap_reason({'raw':{'gpu_thermal_pwrlevel':'0'}}))
        self.assertEqual(thermal.gpu_thermal_cap_reason({'raw':{'gpu_thermal_pwrlevel':'4'}}),'fresh-gpu-thermal-cap-detected')
        for raw in [None, '', 'Permission denied', 'NaN', '0.0', '-1']:
            sample={} if raw is None else {'raw':{'gpu_thermal_pwrlevel':raw}}
            self.assertEqual(thermal.gpu_thermal_cap_reason(sample),'gpu-thermal-pwrlevel-unavailable')

    def test_gpu_gate_filters_rows_and_prevents_completed_validity(self):
        import json
        import tempfile
        from unittest.mock import patch
        controller={'requestedVideoSync':'display-resample','expectedPanelThermalStatus':'0',
                    'status':'completed-observation','completeWindow':True,'restorationVerified':True,
                    'initial':{'raw':{'gpu_thermal_pwrlevel':'0'}}}
        normal={'elapsedSeconds':20,'runtime':{},'raw':{'gpu_thermal_pwrlevel':'0','hdr_mode':'1','backlight':'255','panel_thermal_status':'0'}}
        for level in ['4','']:
            bad={**normal,'raw':{**normal['raw'],'gpu_thermal_pwrlevel':level}}
            with tempfile.TemporaryDirectory() as d, patch.object(thermal,'runtime_error',return_value=None), patch.object(thermal,'native_failure_reason',return_value=None):
                output=Path(d);(output/'samples.ndjson').write_text('\n'.join(json.dumps(r) for r in [normal,bad]))
                summary=m.summarize(output,controller,'source')
                self.assertEqual(summary['stableSamples'],1)
                self.assertFalse(summary['gpuThermalGateVerified'])
                self.assertFalse(summary['validCompletedProfile'])
                self.assertTrue(summary['metricsAreDiagnosticOnly'])

    def test_gpu_cap_stops_before_any_additional_diagnostics(self):
        import argparse
        import json
        import tempfile
        from unittest.mock import MagicMock, patch
        events=[]
        normal={'batteryC':32,'vtsC':35,'raw':{'gpu_thermal_pwrlevel':'0','panel_thermal_status':'0'}}
        capped={'batteryC':33,'vtsC':36,'raw':{'gpu_thermal_pwrlevel':'4','panel_thermal_status':'0'}}
        adb=MagicMock()
        adb.lab_pid.return_value='123'
        adb.settings.return_value={};adb.properties.return_value={}
        adb.screen_state.return_value={'on':True,'keyguard':False}
        adb.wake_unprotected.return_value={'on':True,'keyguard':False}
        snapshots=iter([normal,normal,normal,capped])
        def snapshot():
            row=next(snapshots);events.append('cap' if row is capped else 'snapshot');return row
        def call(command):
            events.append('stop' if command[:3]==['shell','am','force-stop'] else 'diagnostic-or-command')
            return '0' if command == ['shell','getprop',thermal.INPUT_FBO_PROPERTY] else ''
        adb.snapshot.side_effect=snapshot;adb.call.side_effect=call;adb.restore.return_value=[]
        capture=MagicMock();capture.state.return_value={'playbackStartAt':None}
        with tempfile.TemporaryDirectory() as d:
            receipt=Path(d)/'receipt.json';receipt.write_text(json.dumps({'verified':True,'serial':'S','deviceSource':'source'}))
            args=argparse.Namespace(output=str(Path(d)/'round'),serial='S',experiment='publish-flush',mode='candidate',duration=60,interval=2,
                source_receipt=str(receipt),source_hash=None,source='source',reference_start=None,
                instant_enabled=True,expected_panel_thermal_status='0',allow_unprotected_menu=False,tap=None)
            with patch.object(thermal,'Adb',return_value=adb),patch.object(thermal,'LogCapture',return_value=capture):
                result=thermal.run(args)
        self.assertEqual(events[events.index('cap')+1],'stop')
        self.assertEqual(result['status'],'aborted')
        self.assertEqual(result['reason'],'fresh-gpu-thermal-cap-detected')
        self.assertEqual(result['finalEvidenceSource'],'last-running-sample-before-stop')
        self.assertTrue(result['restorationVerified'])
        self.assertTrue(result['hdrLabStopped'])
        self.assertNotIn('surfaceFlingerFinal',result)

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
            for script in scripts:
                for path in ['/thermal_pwrlevel','/max_gpuclk','/cpu2/cpufreq/scaling_max_freq']:
                    self.assertIn(path,script)




if __name__=='__main__':unittest.main()
