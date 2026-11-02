import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent))
spec = importlib.util.spec_from_file_location('quality_round', Path(__file__).with_name('lg_p84_quality_round.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def quality(status, pid='123', ordinal=1, run='123:unique', pts=35.035, fusion='1'):
    return f'10-30 01:00:00.001 {pid} {pid} I flutter : P84_QUALITY '+json.dumps({
        'pid': int(pid), 'runId': run, 'ordinal': ordinal, 'status': status,
        'requestedPTS': pts, 'requestedFusionMode': fusion})


def swap(pid='123', route='fused', pts='35.035', confirmed='1', token='3'):
    return (f'10-30 01:00:00.002 {pid} {pid} I flutter : MKS-FUSION-FRAME '
            f'event=swap-success route={route} pid={pid} instance=0x123 token={token} '
            f'generation=2 frame_id=9 source_pts={pts} current_pts={pts} '
            f'still=1 redraw=0 repeat=0 mono_ns=123456 gpu_draw_confirmed={confirmed}')


class QualityTests(unittest.TestCase):
    def test_ready_requires_matching_seek_ordinal_and_process(self):
        lines=[quality('seek-started'),swap(),quality('ready-for-observation')]
        pair=m.observation_pair(lines,'123',35.035,'1')
        self.assertEqual(pair[:2],(0,2))
        self.assertIsNotNone(m.native_swap(lines,'123',pair[0],35.035,'1'))
        self.assertIsNone(m.observation_pair(lines,'999',35.035,'1'))
        self.assertIsNone(m.observation_pair(lines[1:],'123',35.035,'1'))

    def test_cancelled_ordinal_supersedes_ready(self):
        lines=[quality('seek-started'),swap(),quality('ready-for-observation'),quality('cancelled')]
        with self.assertRaisesRegex(RuntimeError,'cancelled'):
            m.observation_pair(lines,'123',35.035,'1')

    def test_multiple_seeks_and_wrong_mode_rejected(self):
        for lines in ([quality('seek-started'),quality('seek-started',ordinal=2)],
                      [quality('seek-started',fusion='0')]):
            with self.assertRaises(RuntimeError):m.observation_pair(lines,'123',35.035,'1')

    def test_stale_native_before_seek_cannot_prove_frame(self):
        self.assertIsNone(m.native_swap([swap(),quality('seek-started')],'123',1,35.035,'1'))
        self.assertIsNone(m.native_swap([quality('seek-started'),swap(pid='999')],'123',0,35.035,'1'))

    def test_latest_success_must_match_source_pts_and_actual_route(self):
        lines=[quality('seek-started'),swap()]
        for last in [swap(pts='36'),swap(route='rgb-final',confirmed='0'),swap(confirmed='0')]:
            self.assertIsNone(m.native_swap(lines+[last],'123',0,35.035,'1'))
        self.assertIsNotNone(m.native_swap([quality('seek-started'),swap(route='rgb-final',confirmed='0')],'123',0,35.035,'0'))

    def test_malformed_trace_and_nonfinite_pts_never_pass(self):
        for line in [swap(pts='nan'),swap(token='0'),swap().replace('frame_id=9','')]:
            with self.assertRaises(RuntimeError):m.native_swap([quality('seek-started'),line],'123',0,35.035,'1')

    def persistent(self):
        return {'runId':'123:unique','ordinal':1,'pid':123,'status':'observation-heartbeat','heartbeat':1,
                'requestedPTS':35.035,'requestedFusionMode':'1',
                'owner':{'sourcePath':'/source.mp4','generation':7},
                'faultPropertiesBefore':{'debug.mks.yuv_fail_commit':'0','debug.mks.yuv_fail_gl':''},
                'faultPropertiesAfter':{'debug.mks.yuv_fail_commit':'0','debug.mks.yuv_fail_gl':''},
                'properties':{'path':'/source.mp4','pause':'yes','seeking':'no','hwdec-current':'surfacetexture','vo':'gpu-next',
                  'target-trc':'pq','target-prim':'bt.2020','target-peak':'1000','gamma':'0',
                  'current-tracks/video/dolby-vision-profile':'8','current-tracks/video/dolby-vision-compatibility-id':'4',
                  'video-params/gamma':'hlg','video-params/primaries':'bt.2020','video-params/w':'3840','video-params/h':'1920',
                  'container-fps':'29.970030','time-pos':'35.035'},
                'report':{'verified':True,'generation':7,'error':None,
                  'source':{'kind':'dolbyVisionP84','dvProfile':8,'dvCompatibilityId':4},
                  'actual':{'strategy':'baseLayerConvert'}}}

    def test_persistent_current_fields_and_final_status_mandatory(self):
        row=self.persistent()
        self.assertIs(m.validate_persistent([row],row,'123','/source.mp4',35.035,'1'),row)
        for key in ['video-params/w','current-tracks/video/dolby-vision-profile','video-params/gamma','hwdec-current']:
            changed=json.loads(json.dumps(row));changed['properties'][key]=''
            with self.assertRaises(RuntimeError):m.validate_persistent([changed],row,'123','/source.mp4',35.035,'1')
        with self.assertRaises(RuntimeError):m.validate_persistent([row,{**row,'status':'cancelled'}],row,'123','/source.mp4',35.035,'1')
        row['faultPropertiesAfter']['debug.mks.yuv_fail_gl']='1'
        with self.assertRaises(RuntimeError):m.validate_persistent([row],row,'123','/source.mp4',35.035,'1')

    def test_thermal_unknown_or_cap_and_foreground(self):
        good={'batteryC':30,'vtsC':35,'raw':{'gpu_thermal_pwrlevel':'0','panel_thermal_status':'0','hdr_mode':'1','backlight':'64'}}
        m.thermal_gate(good,{},'0',64)
        for cap in ['', '4']:
            bad=json.loads(json.dumps(good));bad['raw']['gpu_thermal_pwrlevel']=cap
            with self.assertRaises(RuntimeError):m.thermal_gate(bad,{},'0',64)
        self.assertTrue(m.foreground_matches('mCurrentFocus=Window{a u0 com.example.media_kit_hdr_lab/.MainActivity}'))
        self.assertFalse(m.foreground_matches('mCurrentFocus=Window{a u0 other/.MainActivity}'))

    def test_control_snapshot_includes_restore_of_new_properties(self):
        with tempfile.TemporaryDirectory() as d:
            adb=m.QualityAdb('serial',Path(d))
            with patch.object(adb,'call',return_value='old'):
                values=adb.properties()
            self.assertIn('debug.mks.yuv_frame_trace',values)
            self.assertIn('debug.mks.quality_pts',values)
            with patch.object(adb,'shell') as shell:
                self.assertEqual(adb.restore({},values),[])
            restored=' '.join(str(c) for c in shell.call_args_list)
            self.assertIn('debug.mks.yuv_frame_trace',restored)
            self.assertIn('debug.mks.quality_pts',restored)

    def test_failure_after_mutation_stops_and_restores(self):
        with tempfile.TemporaryDirectory() as d:
            dest=Path(d)/'round';receipt=Path(d)/'source.json'
            receipt.write_text(json.dumps({'verified':True,'serial':'serial','deviceSource':'/source.mp4','deviceSha256':'b'*64,'hostSha256':'b'*64,'deviceBytes':123,'hostBytes':123,'returncode':0}))
            calls=[]
            class FakeAdb:
                def __init__(self,*args):pass
                def settings(self):return {'screen_brightness':'120'}
                def properties(self):return {'debug.mks.yuv_frame_trace':'old'}
                def screen_state(self):return {'on':True}
                def snapshot(self):return {'batteryC':30,'vtsC':35,'raw':{'gpu_thermal_pwrlevel':'0','panel_thermal_status':'0'}}
                def source_hash(self,path):return {'sha256':'a'*64}
                def shell(self,*args):return '123'
                def wake_unprotected(self,*args):calls.append('wake')
                def call(self,args):
                    calls.append(args)
                    if args[:3]==['shell','pm','path']:return 'package:/data/app/test/base.apk'
                    return ''
                def restore(self,settings,props):calls.append(('restore',settings,props));return []
                def lab_pid(self):return '123'
            with patch.object(m,'QualityAdb',FakeAdb),patch.object(m.thermal,'LogCapture',side_effect=RuntimeError('forced capture failure')):
                result=m.run(SimpleNamespace(output=str(dest),serial='serial',source_receipt=str(receipt),source='/source.mp4',
                   expected_panel_thermal_status='0',expected_apk_sha256='a'*64,brightness=64,timeout=30,
                   allow_unprotected_menu=True,fusion='1',pts=35.035))
            self.assertEqual(result['status'],'failed')
            self.assertEqual(result['reason'],'forced capture failure')
            self.assertTrue(result['restorationVerified'])
            self.assertTrue(any(isinstance(c,tuple) and c[0]=='restore' for c in calls))

    def test_png_failure_is_not_screenshot_evidence(self):
        with tempfile.TemporaryDirectory() as d:
            adb=m.QualityAdb('serial',Path(d))
            bad=SimpleNamespace(returncode=0,stdout=b'not an image',stderr=b'')
            with patch.object(m.subprocess,'run',return_value=bad):
                with self.assertRaisesRegex(RuntimeError,'PNG'):adb.screenshot(Path(d)/'capture.png')
            self.assertFalse((Path(d)/'capture.png').exists())

    def test_failure_after_launch_force_stops_before_restoration(self):
        with tempfile.TemporaryDirectory() as d:
            receipt=Path(d)/'source.json';receipt.write_text(json.dumps({'verified':True,'serial':'serial','deviceSource':'/source.mp4','deviceSha256':'b'*64,'hostSha256':'b'*64,'deviceBytes':123,'hostBytes':123,'returncode':0}))
            adb=MagicMock()
            adb.settings.return_value={'screen_brightness':'120'}
            adb.properties.return_value={'debug.mks.yuv_frame_trace':'old'}
            adb.screen_state.return_value={'on':True}
            adb.snapshot.return_value={'batteryC':30,'vtsC':35,'raw':{'gpu_thermal_pwrlevel':'0','panel_thermal_status':'0'}}
            adb.source_hash.return_value={'sha256':'a'*64}
            adb.shell.return_value='123'
            adb.call.side_effect=lambda args: 'package:/data/app/test/base.apk' if args[:3]==['shell','pm','path'] else ''
            adb.lab_pid.return_value=None
            adb.restore.return_value=[]
            with patch.object(m,'QualityAdb',return_value=adb),patch.object(m.thermal,'LogCapture'):
                result=m.run(SimpleNamespace(output=str(Path(d)/'round'),serial='serial',source_receipt=str(receipt),source='/source.mp4',
                   expected_panel_thermal_status='0',expected_apk_sha256='a'*64,brightness=64,timeout=30,
                   allow_unprotected_menu=True,fusion='1',pts=35.035))
            self.assertEqual(result['reason'],'quality-process-not-running')
            self.assertTrue(result['hdrLabStopped'])
            self.assertTrue(result['restorationVerified'])
            self.assertEqual(sum(call.args[0]==['shell','am','force-stop',m.thermal.PACKAGE] for call in adb.call.call_args_list),2)

    def test_heartbeat_must_advance_and_stale_guard_times_out(self):
        rows=iter([{'heartbeat':2},{'heartbeat':3}])
        with patch.object(m.time,'sleep'):
            self.assertEqual(m.fresh_heartbeat(lambda:next(rows),2)['heartbeat'],3)
        with patch.object(m.time,'monotonic',side_effect=[0,1,2,6]),patch.object(m.time,'sleep'):
            with self.assertRaisesRegex(RuntimeError,'stale'):m.fresh_heartbeat(lambda:{'heartbeat':2},2)

    def test_screenshot_full_decode_rejects_plausible_truncated_PNG(self):
        import io
        from PIL import Image
        data=io.BytesIO();Image.new('RGB',(4,4)).save(data,format='PNG');raw=data.getvalue()
        # Retain IHDR, IDAT marker, and IEND while corrupting compressed payload.
        bad=bytearray(raw);i=raw.index(b'IDAT')+4;bad[i]=0
        with tempfile.TemporaryDirectory() as d:
            adb=m.QualityAdb('serial',Path(d))
            result=SimpleNamespace(returncode=0,stdout=bytes(bad),stderr=b'')
            with patch.object(m.subprocess,'run',return_value=result):
                with self.assertRaisesRegex(RuntimeError,'full-decode'):adb.screenshot(Path(d)/'bad.png')
            self.assertFalse((Path(d)/'bad.png').exists())

    def test_source_receipt_requires_consistent_SHA_and_size(self):
        row={'verified':True,'serial':'serial','deviceSource':'/source.mp4','deviceSha256':'b'*64,
             'hostSha256':'b'*64,'deviceBytes':123,'hostBytes':123,'returncode':0}
        self.assertEqual(m.validate_source_receipt(row,'serial','/source.mp4'),123)
        for key,value in [('deviceSha256',''),('deviceBytes',0),('deviceBytes',True),('hostBytes',124),('hostSha256','c'*64),('returncode',1)]:
            with self.assertRaises(RuntimeError):m.validate_source_receipt({**row,key:value},'serial','/source.mp4')

    def test_post_screenshot_watermark_rejects_preexisting_heartbeat(self):
        # seq6 may have been written before capture completed; it cannot prove
        # a post-capture read. seq7 alone may be the pre-watermark in-flight read.
        with patch.object(m.time,'monotonic',side_effect=[0,1,2,6]),patch.object(m.time,'sleep'):
            with self.assertRaisesRegex(RuntimeError,'stale'):
                m.post_screenshot_heartbeat(lambda:{'heartbeat':6})
        rows=iter([{'heartbeat':6},{'heartbeat':7},{'heartbeat':8}])
        with patch.object(m.time,'sleep'):
            watermark,row=m.post_screenshot_heartbeat(lambda:next(rows))
        self.assertEqual(watermark,6)
        self.assertEqual(row['heartbeat'],8)

    def test_slow_heartbeat_read_cannot_return_after_deadline(self):
        with patch.object(m.time,'monotonic',side_effect=[0,1,6]):
            with self.assertRaisesRegex(RuntimeError,'exceeded-deadline'):
                m.fresh_heartbeat(lambda:{'heartbeat':9},1)

    def test_real_paused_seek_still_zero_uses_independent_pause_heartbeat(self):
        # Exact counterexample from quality-live-35-A/flutter-logcat.txt:
        # mpv player/video.c only sets frame.still for step_frames; paused seek
        # can swap a queued decoded frame with still=0. Old timed-out evidence
        # remains failed; this tests the corrected matcher only.
        line=('10-30 03:27:58.067 22729 22729 I flutter : MPVLOG [vo/gpu-next/opengl] error: '
              'MKS-FUSION-FRAME event=swap-success route=rgb-final pid=22729 '
              'instance=0x741d8bd050 token=24 generation=2 frame_id=72 '
              'source_pts=35.035000000 current_pts=35.035000000 still=0 redraw=0 '
              'repeat=0 mono_ns=7021943360 gpu_draw_confirmed=0')
        matched=m.native_swap(['seek-marker',line],'22729',0,35.035,'0')
        self.assertIsNotNone(matched)
        self.assertEqual(matched['still'],'0')
        row=self.persistent()
        self.assertIsNotNone(m.validate_persistent([row],row,'123','/source.mp4',35.035,'1'))
        row['properties']['pause']='no'
        with self.assertRaisesRegex(RuntimeError,'property-mismatch'):
            m.validate_persistent([row],row,'123','/source.mp4',35.035,'1')

    def test_still_zero_does_not_excuse_invalidated_or_stale_heartbeat(self):
        self.assertIsNotNone(m.native_swap(['seek-marker',swap().replace('still=1','still=0')],'123',0,35.035,'1'))
        row=self.persistent()
        with self.assertRaisesRegex(RuntimeError,'invalidated'):
            m.validate_persistent([row,{**row,'status':'invalidated'}],row,'123','/source.mp4',35.035,'1')
        with patch.object(m.time,'monotonic',side_effect=[0,1,2,6]),patch.object(m.time,'sleep'):
            with self.assertRaisesRegex(RuntimeError,'stale'):
                m.post_screenshot_heartbeat(lambda:row)

    def test_native_still_flag_must_still_be_well_formed(self):
        with self.assertRaisesRegex(RuntimeError,'still-flag'):
            m.native_swap(['seek-marker',swap().replace('still=1','still=unknown')],'123',0,35.035,'1')

    def test_quantized_timepos_requires_exact_same_decoded_source_frame(self):
        row=self.persistent();row['requestedPTS']=600.032766667
        row['properties']['time-pos']='600.032000'
        self.assertIsNotNone(m.validate_persistent([row],row,'123','/source.mp4',600.032766667,'1'))
        # Exact real source/current PTS at the requested decoded frame passes;
        # the millisecond command value itself is not decoded-frame evidence.
        lines=['seek-marker',swap(pts='600.032766667')]
        before=m.native_swap(lines,'123',0,600.032766667,'1')
        self.assertIsNotNone(before)
        self.assertIsNone(m.native_swap(['seek-marker',swap(pts='600.032000')],'123',0,600.032766667,'1'))
        self.assertIsNone(m.native_swap(['seek-marker',swap(pts=str(600.032766667+1001/30000))],'123',0,600.032766667,'1'))
        after={**before,'source_pts':'600.032766667','current_pts':'600.032766667','token':'99'}
        self.assertTrue(m.same_native_source(before,after))
        self.assertFalse(m.same_native_source(before,{**after,'source_pts':'600.033766667'}))
        row['properties']['seeking']='yes'
        with self.assertRaisesRegex(RuntimeError,'property-mismatch'):
            m.validate_persistent([row],row,'123','/source.mp4',600.032766667,'1')
