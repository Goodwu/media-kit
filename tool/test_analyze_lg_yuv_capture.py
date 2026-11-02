import importlib.util
import copy
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('analyzer',Path(__file__).with_name('analyze_lg_yuv_capture.py'))
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)

def bits(f):return struct.unpack('<I',struct.pack('<f',f))[0]

class CaptureTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.path=self.root/'capture.json'
        self.lib=[1,*map(bits,(.1,.2,.3)),*map(bits,(.1,.2,.3)),*map(bits,(.2,.5,.6)),1,*map(bits,(.1,.2,.3))]
        self.android=[1,*map(bits,(.1,.2,.3)),*map(bits,(.2,.5,.6))]
        self.m={'schema':1,'status':'complete','pid':123,'capture_id':1,'generation':2,'source_pts':35.035,'current_pts':35.035,'target_pts':35.035,'roi':{'x':4,'y':6,'w':1,'h':1},'target_width':8,'target_height':8,'shader_body_hash':'123456789','lib_words':14,'android_words':7,'lib_status':'complete','android_status':'ready','byte_order':'little','lib_candidate_ok':True,'lib_baseline_ok':True,'android_swap_succeeded':True,'lib_fence_signaled':True,'android_fence_signaled':True,'files':{k:'mks-yuv-compare-123-1'+v for k,v in {'lib':'.lib.bin','android':'.android.bin','candidate':'.candidate.glsl','baseline':'.baseline.glsl','vertex':'.vertex.glsl'}.items()}}
        for k in ('candidate','baseline','vertex'):(self.root/self.m['files'][k]).write_text('#version 310 es\nvoid main() {}\n')
        self.save()
    def save(self):
        self.path.write_text(json.dumps(self.m))
        (self.root/self.m['files']['lib']).write_bytes(struct.pack('<'+str(len(self.lib))+'I',*self.lib))
        (self.root/self.m['files']['android']).write_bytes(struct.pack('<'+str(len(self.android))+'I',*self.android))
        if 'oracle_probe' in self.m['files']:
            (self.root/self.m['files']['oracle_probe']).write_bytes(struct.pack('<'+str(len(self.probe))+'I',*self.probe))
        for key in ('baseline_vertices','candidate_vertices'):
            if key in self.m['files']:(self.root/self.m['files'][key]).write_bytes(getattr(self,key))
    def make_repeat(self):
        self.m.update(schema=2,repetitions=2,draw_order=['B1','A1','B2','A2'],
                draw_ok={name:True for name in a.DRAW_ORDER},frame_id=99,frame_token=9,
                same_input_snapshot=True,assertion_scope=a.INPUT_ASSERTION_SCOPE,
                programs_reused=True,program_tokens=['11','22','11','22'],
                draw_epoch_before=['0']*4,draw_epoch_after=['0']*4,lib_words=56,android_words=14)
        self.m['roi']['w']=2
        second=self.lib.copy();second_android=self.android.copy()
        for offset in (1,4,11):second[offset:offset+3]=list(map(bits,(.4,.5,.6)))
        second[7:10]=list(map(bits,(.7,.8,.9)))
        second_android[1:4]=list(map(bits,(.4,.5,.6)));second_android[4:7]=list(map(bits,(.7,.8,.9)))
        self.lib=(self.lib+second)*2;self.android+=second_android;self.save()
    def make_sample_tap(self):
        self.make_repeat()
        self.m.update(schema=3,sample_tap=True,sample_tap_site_count=1,words_per_pixel=26,
                      sample_tap_body_hash='987654321',instrumentation_scope=a.SAMPLE_TAP_SCOPE,lib_words=104)
        self.m['files']['original_body']='mks-yuv-compare-123-1.original-body.glsl'
        (self.root/self.m['files']['original_body']).write_text('color.rgb = textureLod(tex, pos, 0.0).rgb;\n')
        expanded=[]
        for offset in range(0,len(self.lib),14):
            pixel=(offset//14)%2
            tap=list(map(bits,(.1,.2,.1,.2,.3) if pixel==0 else (.3,.4,.4,.5,.6)))+[1]
            expanded+=self.lib[offset:offset+14]+tap+tap
        self.lib=expanded;self.save()
    def make_invariant(self):
        self.make_sample_tap()
        self.m.update(schema=4,invariant_b=True,invariant_uv_identifier='_8003',
                      draw_order=a.INVARIANT_DRAW_ORDER,draw_ok={name:True for name in a.INVARIANT_DRAW_ORDER})
        self.m['files']['candidate_vertex']='mks-yuv-compare-123-1.candidate-vertex.glsl'
        anchor='#version 310 es\nout vec2 _8003;\nvoid main() {\ngl_Position = vec4(va_pos, 0.0, 1.0);\n_8003 = vec2(0.0);\n}\n'
        candidate=anchor.replace('void main','invariant gl_Position;\ninvariant _8003;\nvoid main',1)
        (self.root/self.m['files']['vertex']).write_text(anchor)
        (self.root/self.m['files']['candidate_vertex']).write_text(candidate)
        self.save()
    def make_oracle(self,use_a=False):
        self.make_sample_tap()
        self.m.update(schema=5,uv_oracle=True,uv_oracle_use_a=use_a,uv_oracle_barriers=2,
                      uv_oracle_barrier_ok=[True,True],uv_oracle_barrier_epoch_before=['0','0'],
                      uv_oracle_barrier_epoch_after=['0','0'],draw_order=a.ORACLE_DRAW_ORDER,
                      draw_ok={name:True for name in a.ORACLE_DRAW_ORDER})
        self.save()
    def make_probe(self,use_a=True):
        self.make_oracle(use_a)
        self.m.update(schema=6,uv_oracle_probe=True,uv_oracle_probe_status='complete',
                      uv_oracle_probe_words=40,uv_oracle_probe_words_per_pixel=10,oracle_preconditions_valid=True,
                      oracle_cpu_validation_mask=0,oracle_cpu_validation_reasons=[])
        self.m['files']['oracle_probe']='mks-yuv-compare-123-1.oracle-probe.bin'
        self.probe=[]
        for base in (0,26,52,78):
            self.probe += [1,1,1,1,1,*self.lib[base+20:base+22],0,1,int(use_a)]
        self.save()
    def mark_probe_invalid(self,mask):
        self.m.update(status='diagnostic-invalid',oracle_preconditions_valid=False,
                      oracle_cpu_validation_mask=mask,oracle_cpu_validation_reasons=a.cpu_validation_reasons(mask))
        for key,old in list(self.m['files'].items()):
            new=old.replace('mks-yuv-compare-123-1.','mks-yuv-compare-123-1.diagnostic-invalid.',1)
            (self.root/old).rename(self.root/new);self.m['files'][key]=new
        self.save()
    def make_single_pair(self,use_a=True):
        self.make_probe(use_a)
        self.m.update(schema=7,uv_oracle_single_pair=True,repetitions=1,draw_order=a.SINGLE_PAIR_DRAW_ORDER,
                      draw_ok={name:True for name in a.SINGLE_PAIR_DRAW_ORDER},programs_reused=False,
                      program_tokens=self.m['program_tokens'][:2],draw_epoch_before=['0']*2,draw_epoch_after=['0']*2,
                      uv_oracle_barriers=1,uv_oracle_barrier_ok=[True],uv_oracle_barrier_epoch_before=['0'],
                      uv_oracle_barrier_epoch_after=['0'],lib_words=52,uv_oracle_probe_words=20)
        self.lib=self.lib[:52];self.probe=self.probe[:20];self.save()
    def make_quad_order(self,reverse=False):
        self.make_single_pair(False)
        attr=lambda name,location,offset:{'name':name,'format_name':'rg32f','glsl_type':'vec2','fmt_type':'float32',
            'location':location,'num_components':2,'component_depth':[32,32,0,0],'host_bits':[32,32,0,0],
            'sample_order':[0,1,2,3],'opaque':False,'num_planes':0,'offset':offset,'texel_size':8}
        layout={'primitive':'triangle_strip','indexed':False,'vertex_count':4,'num_attributes':2,'position_attrib':1,
            'stride':20,'byte_size':80,'viewport':[0,0,8,8],'scissors':[0,0,8,8],
            'attributes':[attr('_15',0,0),attr('_16',1,8)]}
        self.m.update(schema=8,quad_order=True,quad_order_reverse=reverse,quad_vertex_layout=layout)
        self.m['files'].update(baseline_vertices='mks-yuv-compare-123-1.baseline-vertices.bin',
                               candidate_vertices='mks-yuv-compare-123-1.candidate-vertices.bin')
        records=[struct.pack('<4fI',u,v,x,y,0x7fc00000+i) for i,(u,v,x,y) in enumerate(
            ((0,0,-1,1),(1,0,1,1),(0,1,-1,-1),(1,1,1,-1)))]
        self.baseline_vertices=b''.join(records)
        self.candidate_vertices=b''.join(records[i] for i in ([3,2,1,0] if reverse else [0,1,2,3]))
        vertex='#version 320 es\nin vec2 _15;\nout vec2 _8003;\nin vec2 _16;\nvoid main() {\n_8003 = _15;\nvec2 va_pos = _16;\ngl_Position = vec4(va_pos, 0.0, 1.0);\n}\n'
        (self.root/self.m['files']['vertex']).write_text(vertex);self.save()
    def test_equal(self):
        r=a.analyze(self.path);self.assertEqual(r['status'],'captured-floats-bit-equal');self.assertEqual(r['pixels'],1)
    def test_each_stage_difference(self):
        for offset,stage in [(1,'pre_rgb'),(4,'half_rgb'),(7,'yuv')]:
            with self.subTest(stage=stage):
                old=self.lib[offset];self.lib[offset]=bits(.9);self.save();r=a.analyze(self.path)
                self.assertEqual(r['status'],'captured-float-differences');self.assertEqual(r['comparisons'][stage]['bit_mismatches'],1)
                self.assertEqual(r['comparisons'][stage]['first_differences'][0]['x'],4);self.lib[offset]=old
    def test_signed_zero_is_difference(self):
        self.lib[1]=bits(-0.);self.lib[11]=bits(0.);self.save();r=a.analyze(self.path)
        self.assertEqual(r['comparisons']['pre_rgb']['bit_mismatches'],1)
        self.assertEqual(r['comparisons']['pre_rgb']['max_absolute_difference'],0)
    def test_equal_nan_still_invalid(self):
        self.lib[1]=self.lib[11]=0x7fc00000;self.save();r=a.analyze(self.path)
        self.assertEqual(r['status'],'invalid-nonfinite')
    def test_counts_missing_or_duplicate(self):
        for where in ('b','a','csc'):
            for value in (0,2):
                with self.subTest(where=where,value=value):
                    self.lib[0]=self.lib[10]=self.android[0]=1
                    if where=='b':self.lib[0]=value
                    elif where=='a':self.lib[10]=value
                    else:self.android[0]=value
                    self.save()
                    with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_false_status_or_missing_fence(self):
        for key,value in [('status','pending'),('lib_candidate_ok',False),('android_swap_succeeded',False),('lib_fence_signaled',None),('android_status','failed')]:
            with self.subTest(key=key):
                old=self.m[key];self.m[key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
                self.m[key]=old
    def test_pts_mismatch(self):
        self.m['source_pts']+=.033;self.save()
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_oversized_json_integer_pts(self):
        for key in ('source_pts','target_pts','current_pts'):
            for value in (10**400,-10**400):
                with self.subTest(key=key,value=value):
                    old=self.m[key];self.m[key]=value;self.save()
                    with self.assertRaisesRegex(a.InvalidCapture,'invalid '+key):a.analyze(self.path)
                    result=subprocess.run([sys.executable,str(Path(a.__file__)),str(self.path)],capture_output=True,text=True)
                    self.assertEqual(result.returncode,2)
                    self.assertEqual(json.loads(result.stdout)['status'],'invalid-capture')
                    self.assertEqual(result.stderr,'')
                    self.m[key]=old
    def test_truncated_and_extra_data(self):
        for raw in (b'',b'\0'*52,b'\0'*60):
            (self.root/self.m['files']['lib']).write_bytes(raw)
            with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_manifest_word_counts(self):
        self.m['lib_words']=15;self.save()
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_path_escape_symlink_alias(self):
        self.m['files']['candidate']='../outside';self.path.write_text(json.dumps(self.m))
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        self.m['files']['candidate']='mks-yuv-compare-123-1.candidate.glsl';p=self.root/self.m['files']['candidate'];p.unlink();p.symlink_to(self.root/self.m['files']['baseline']);self.path.write_text(json.dumps(self.m))
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_duplicate_json(self):
        self.path.write_text('{"schema":1,"schema":1}')
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_hash_mismatch(self):
        self.m['sha256']={k:'0'*64 for k in a.FILES};self.save()
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_no_shader(self):
        (self.root/self.m['files']['candidate']).write_text('garbage')
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_invalid_roi(self):
        for value in (0,-1,True,1024*1024+1):
            self.m['roi']['w']=value;self.save()
            with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema2_equal_contiguous_chunks(self):
        self.make_repeat();r=a.analyze(self.path)
        self.assertEqual(r['schema'],2);self.assertEqual(r['status'],'captured-floats-bit-equal')
        self.assertEqual(r['pixels'],2)
        self.assertEqual(r['repeat_analysis']['repeatability'],'captured-stages-bit-stable')
        self.assertEqual(r['repeat_analysis']['not_captured']['baseline_repeat'],['half_rgb','yuv'])
    def test_schema2_b1_differences_do_not_replace_current_ab(self):
        self.make_repeat();self.lib[14+1]=bits(.91);self.save();r=a.analyze(self.path)
        self.assertEqual(r['status'],'captured-float-differences')
        self.assertTrue(all(v['bit_mismatches']==0 for v in r['comparisons'].values()))
        repeat=r['repeat_analysis']['comparisons']['candidate_repeat']['pre_rgb']
        self.assertEqual(repeat['first_differences'][0]['x'],5)
        self.assertEqual(r['repeat_analysis']['ab_localization']['first_differing_stage']['ab1'],'pre_rgb')
        result=subprocess.run([sys.executable,str(Path(a.__file__)),str(self.path)],capture_output=True,text=True)
        self.assertEqual(result.returncode,3)
        self.assertEqual(json.loads(result.stdout)['repeat_analysis']['repeatability'],'captured-stages-bit-unstable')
        self.assertEqual(result.stderr,'')
    def test_schema2_b2_is_current_ab(self):
        self.make_repeat();self.lib[28+7]=bits(.91);self.save();r=a.analyze(self.path)
        self.assertEqual(r['comparisons']['yuv']['bit_mismatches'],1)
        self.assertEqual(r['repeat_analysis']['comparisons']['ab2']['yuv']['bit_mismatches'],1)
    def test_schema2_a1_pre_is_checked(self):
        self.make_repeat();self.lib[11]=bits(.91);self.save();r=a.analyze(self.path)
        self.assertEqual(r['status'],'captured-float-differences')
        self.assertEqual(r['repeat_analysis']['comparisons']['baseline_repeat']['pre_rgb']['bit_mismatches'],1)
        self.assertEqual(r['comparisons']['pre_rgb']['bit_mismatches'],0)
    def test_schema2_all_counts_strict(self):
        self.make_repeat()
        for offset in (0,10,14,24,28,38,42,52):
            for value in (0,2):
                with self.subTest(offset=offset,value=value):
                    self.lib[offset]=value;self.save()
                    with self.assertRaisesRegex(a.InvalidCapture,'coverage not exactly one'):a.analyze(self.path)
                    self.lib[offset]=1
    def test_schema2_b1_nonfinite_cannot_hide_behind_final_ab(self):
        self.make_repeat();self.lib[7]=0x7fc00000;self.save();r=a.analyze(self.path)
        self.assertEqual(r['status'],'invalid-nonfinite')
        self.assertEqual(r['repeat_analysis']['repeatability'],'invalid-nonfinite')
        self.assertTrue(all(v['nonfinite_components']==0 for v in r['comparisons'].values()))
    def test_schema2_metadata_fail_closed(self):
        self.make_repeat();original=json.loads(json.dumps(self.m))
        changes=[('repetitions',1),('draw_order',['B1','B2','A1','A2']),
                 ('draw_ok',{'B1':True,'A1':True,'B2':False,'A2':True}),
                 ('draw_ok',dict.fromkeys(a.DRAW_ORDER,1)),('frame_id',0),('frame_token',None),
                 ('same_input_snapshot',False),('assertion_scope','same pixels'),
                 ('programs_reused',False),('program_tokens',['11','22','33','22']),
                 ('program_tokens',[11,22,11,22]),('program_tokens',['11','0','11','0'])]
        for key,value in changes+[(key,None) for key in ('repetitions','draw_order','draw_ok','same_input_snapshot','programs_reused','program_tokens')]:
            with self.subTest(key=key,value=value):
                self.m=json.loads(json.dumps(original));self.m[key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema2_bad_size_and_word_count(self):
        self.make_repeat();self.lib=self.lib[:-1];self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'invalid byte size'):a.analyze(self.path)
        self.lib.append(0);self.m['lib_words']=28;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'wrong word count'):a.analyze(self.path)
    def test_schema2_epoch_limits_and_programs_need_not_be_distinct(self):
        self.make_repeat();self.m['program_tokens']=['11']*4
        for epoch in ('0','7',str((1<<64)-1)):
            with self.subTest(epoch=epoch):
                self.m['draw_epoch_before']=[epoch]*4;self.m['draw_epoch_after']=[epoch]*4;self.save()
                r=a.analyze(self.path)
                self.assertEqual(r['status'],'captured-floats-bit-equal')
                self.assertEqual(r['repeat_metadata']['draw_epoch_before'],[epoch]*4)
    def test_schema2_epoch_metadata_fail_closed(self):
        self.make_repeat();original=json.loads(json.dumps(self.m))
        for key in ('draw_epoch_before','draw_epoch_after'):
            values=[None,[],['0']*3,['0']*5,[0]*4,['-1']*4,['1.0']*4,
                    ['0','0','1','0'],[str(1<<64)]*4,['9'*21]*4,['']*4,['١']*4]
            for value in values:
                with self.subTest(key=key,value=value):
                    self.m=json.loads(json.dumps(original));self.m[key]=value;self.save()
                    with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
            self.m=json.loads(json.dumps(original));del self.m[key];self.save()
            with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        self.m=json.loads(json.dumps(original))
        self.m['draw_epoch_before']=['0','1','1','1'];self.m['draw_epoch_after']=['0','1','1','1'];self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'discontinuous'):a.analyze(self.path)
    def test_schema2_android_coverage_is_final_a2_only(self):
        self.make_repeat();self.android[0]=0;self.save()
        with self.assertRaises(a.InvalidCapture) as result:a.analyze(self.path)
        message=str(result.exception)
        self.assertIn('"final_A2_CSC": 0',message)
        self.assertNotIn('repetition',message)
        self.assertNotIn('A1',message)
    def test_schema3_sample_tap_equal(self):
        self.make_sample_tap();r=a.analyze(self.path)
        self.assertEqual(r['schema'],3);self.assertEqual(r['status'],'captured-floats-bit-equal')
        self.assertEqual(r['sample_tap_analysis']['repeatability'],'sample-taps-bit-stable')
        self.assertEqual(r['sample_tap_analysis']['comparisons']['ab2']['uv']['components'],4)
        self.assertEqual(r['sample_tap_analysis']['comparisons']['ab2']['sample_rgb']['components'],6)
        self.assertIn('not an unmodified shader',r['limitations'][-1])
        self.assertEqual(len(r['files']),6)
        self.assertEqual(r['original_body_relation']['status'],'not-independently-verified')
    def test_schema3_tap_only_b1_uv_difference_fail_closed(self):
        self.make_sample_tap();self.lib[26+15]=bits(.91);self.save();r=a.analyze(self.path)
        self.assertEqual(r['status'],'captured-float-differences')
        self.assertTrue(all(v['bit_mismatches']==0 for v in r['comparisons'].values()))
        self.assertEqual(r['repeat_analysis']['repeatability'],'captured-stages-bit-stable')
        self.assertEqual(r['sample_tap_analysis']['repeatability'],'sample-taps-bit-unstable')
        diff=r['sample_tap_analysis']['comparisons']['candidate_repeat']['uv']['first_differences'][0]
        self.assertEqual((diff['x'],diff['y'],diff['channel']),(5,6,'V'))
        result=subprocess.run([sys.executable,str(Path(a.__file__)),str(self.path)],capture_output=True,text=True)
        self.assertEqual(result.returncode,3)
        self.assertEqual(json.loads(result.stdout)['status'],'captured-float-differences')
        self.assertEqual(result.stderr,'')
    def test_schema3_stable_tap_ab_difference(self):
        self.make_sample_tap()
        for offset in (16,52+16):self.lib[offset]=bits(.91)
        self.save();r=a.analyze(self.path)
        self.assertEqual(r['status'],'captured-float-differences')
        self.assertEqual(r['sample_tap_analysis']['repeatability'],'sample-taps-bit-stable')
        for group in ('ab1','ab2'):
            self.assertEqual(r['sample_tap_analysis']['comparisons'][group]['sample_rgb']['bit_mismatches'],1)
    def test_schema3_a1_tap_repeat_difference(self):
        self.make_sample_tap();self.lib[22]=bits(.91);self.save();r=a.analyze(self.path)
        self.assertEqual(r['sample_tap_analysis']['repeatability'],'sample-taps-bit-unstable')
        self.assertEqual(r['sample_tap_analysis']['comparisons']['baseline_repeat']['sample_rgb']['bit_mismatches'],1)
    def test_schema3_all_site_counts_strict(self):
        self.make_sample_tap()
        for offset in (19,25,26+19,26+25,52+19,52+25,78+19,78+25):
            for value in (0,2):
                with self.subTest(offset=offset,value=value):
                    self.lib[offset]=value;self.save()
                    with self.assertRaisesRegex(a.InvalidCapture,'sample_site_count'):a.analyze(self.path)
                    self.lib[offset]=1
    def test_schema3_fragment_counts_use_26_word_stride(self):
        self.make_sample_tap()
        for base in (0,26,52,78):
            for index in (0,10):
                for value in (0,2):
                    with self.subTest(base=base,index=index,value=value):
                        self.lib[base+index]=value;self.save()
                        with self.assertRaisesRegex(a.InvalidCapture,'coverage not exactly one'):a.analyze(self.path)
                        self.lib[base+index]=1
    def test_schema3_nonfinite_in_every_tap_component_invalid(self):
        self.make_sample_tap()
        for base in (0,26,52,78):
            for offset in (14,15,16,17,18,20,21,22,23,24):
                with self.subTest(base=base,offset=offset):
                    old=self.lib[base+offset];self.lib[base+offset]=0x7fc00000;self.save()
                    r=a.analyze(self.path)
                    self.assertEqual(r['status'],'invalid-nonfinite')
                    self.assertFalse(r['sample_tap_analysis']['captured_repeatability_confirmed'])
                    self.lib[base+offset]=old
    def test_schema3_tap_metadata_fail_closed(self):
        self.make_sample_tap();original=json.loads(json.dumps(self.m))
        changes=[('sample_tap',False),('sample_tap_site_count',0),('sample_tap_site_count',True),
                 ('words_per_pixel',14),('sample_tap_body_hash','0'),('sample_tap_body_hash',str(1<<64)),
                 ('instrumentation_scope','unmodified shader')]
        for key,value in changes+[(k,None) for k in ('sample_tap','sample_tap_site_count','words_per_pixel','sample_tap_body_hash','instrumentation_scope')]:
            with self.subTest(key=key,value=value):
                self.m=json.loads(json.dumps(original));self.m[key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema3_requires_full_26_word_layout(self):
        self.make_sample_tap();self.lib=self.lib[:56];self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'byte size'):a.analyze(self.path)
    def test_schema3_original_body_missing_empty_or_misnamed_invalid(self):
        self.make_sample_tap();name=self.m['files']['original_body'];p=self.root/name
        p.unlink()
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        for raw in (b'',b' \n',b'\xff'):
            p.write_bytes(raw)
            with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        p.write_text('color.rgb = vec3(0.0);')
        self.m['files']['original_body']='other.original-body.glsl';self.save()
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        del self.m['files']['original_body'];self.save()
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema3_original_body_sha256_archived_and_verified(self):
        self.make_sample_tap();r=a.analyze(self.path)
        digest=r['files']['original_body']['sha256']
        self.assertEqual(len(digest),64)
        self.m['sha256']={key:info['sha256'] for key,info in r['files'].items()};self.save()
        self.assertEqual(a.analyze(self.path)['files']['original_body']['sha256'],digest)
        (self.root/self.m['files']['original_body']).write_text('changed nonempty body')
        with self.assertRaisesRegex(a.InvalidCapture,'hash mismatch: original_body'):a.analyze(self.path)
    def test_schema4_equal_and_source_relation_scope(self):
        self.make_invariant();r=a.analyze(self.path)
        self.assertEqual(r['schema'],4);self.assertEqual(r['status'],'captured-floats-bit-equal')
        self.assertEqual(len(r['files']),7)
        self.assertEqual(r['invariant_vertex_relation']['status'],'exact-two-invariant-declarations-only')
        self.assertEqual(r['baseline_control_relation']['status'],'not-independently-verified')
        self.assertEqual(r['sample_tap_analysis']['comparisons']['ab2']['uv']['left_role'],'A02')
        self.assertEqual(r['repeat_analysis']['comparisons']['baseline_repeat']['pre_rgb']['left_role'],'A01')
        self.assertIn('A02 versus B2',r['current_ab'])
    def test_schema4_metadata_fail_closed(self):
        self.make_invariant();original=json.loads(json.dumps(self.m))
        changes=[('invariant_b',False),('invariant_b',None),('invariant_b',1),
                 ('invariant_uv_identifier',None),('invariant_uv_identifier','_0'),
                 ('invariant_uv_identifier','_deadbeef'),('invariant_uv_identifier','_8003;'),
                 ('draw_order',a.DRAW_ORDER),('draw_ok',dict.fromkeys(a.DRAW_ORDER,True))]
        for key,value in changes:
            with self.subTest(key=key,value=value):
                self.m=json.loads(json.dumps(original));self.m[key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema4_extra_vertex_change_rejected(self):
        self.make_invariant();p=self.root/self.m['files']['candidate_vertex']
        p.write_text(p.read_text().replace('vec2(0.0)','vec2(1.0)'))
        with self.assertRaisesRegex(a.InvalidCapture,'exact two invariant'):a.analyze(self.path)
    def test_schema4_missing_or_wrong_identity_candidate_vertex_rejected(self):
        self.make_invariant();p=self.root/self.m['files']['candidate_vertex'];p.unlink()
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        self.m['files']['candidate_vertex']='mks-yuv-compare-123-2.candidate-vertex.glsl';self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'capture identity'):a.analyze(self.path)
    def test_schema4_a0_tap_repeat_and_coverage_strict(self):
        self.make_invariant();self.lib[22]=bits(.91);self.save();r=a.analyze(self.path)
        self.assertEqual(r['status'],'captured-float-differences')
        self.assertEqual(r['sample_tap_analysis']['repeatability'],'sample-taps-bit-unstable')
        self.lib[25]=2;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'A0_sample_site_count'):a.analyze(self.path)
    def test_schema4_nonfinite_and_error_epochs_fail_closed(self):
        self.make_invariant();self.lib[16]=0x7f800000;self.save()
        self.assertEqual(a.analyze(self.path)['status'],'invalid-nonfinite')
        self.m['draw_epoch_before'][2]='1';self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'epochs changed'):a.analyze(self.path)
    def test_schema4_csc_coverage_role_is_final_a02(self):
        self.make_invariant();self.android[0]=0;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'final_A02_CSC'):a.analyze(self.path)
    def test_schema5_control_and_oracle_framework(self):
        for use_a in (False,True):
            with self.subTest(use_a=use_a):
                self.make_oracle(use_a);r=a.analyze(self.path)
                self.assertEqual(r['schema'],5);self.assertEqual(r['status'],'captured-floats-bit-equal')
                self.assertEqual(len(r['files']),6)
                self.assertEqual(r['oracle_metadata']['uv_oracle_use_a'],use_a)
                self.assertEqual(r['baseline_control_relation']['status'],'not-independently-verified')
                self.assertIn('Diagnostic UV oracle only',r['limitations'][-1])
                self.setUp()
    def test_schema5_control_uv_difference_is_recorded(self):
        self.make_oracle(False);self.lib[15]=bits(.91);self.save();r=a.analyze(self.path)
        self.assertEqual(r['status'],'captured-float-differences')
        self.assertEqual(r['oracle_uv_relation']['status'],'UV-match-not-required-for-control')
    def test_schema5_oracle_uv_mismatch_invalidates_experiment(self):
        self.make_oracle(True)
        for offset in (14,15,52+14,52+15):
            with self.subTest(offset=offset):
                old=self.lib[offset];self.lib[offset]=bits(.91);self.save()
                with self.assertRaisesRegex(a.InvalidCapture,'oracle B UV does not match captured A UV'):a.analyze(self.path)
                self.lib[offset]=old
    def test_schema5_equal_uv_nonfinite_invalidates_experiment(self):
        self.make_oracle(True);self.lib[14]=self.lib[20]=0x7f800000;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'oracle B UV does not match captured A UV'):a.analyze(self.path)
    def test_schema5_equal_uv_different_rgb_remains_numeric_difference(self):
        self.make_oracle(True);self.lib[16]=bits(.91);self.save();r=a.analyze(self.path)
        self.assertEqual(r['oracle_uv_relation']['status'],'captured-UV-bits-match')
        self.assertEqual(r['status'],'captured-float-differences')
        self.assertEqual(r['sample_tap_analysis']['comparisons']['ab1']['sample_rgb']['bit_mismatches'],1)
    def test_schema5_oracle_metadata_fail_closed(self):
        self.make_oracle();original=json.loads(json.dumps(self.m))
        changes=[('uv_oracle',False),('uv_oracle_use_a',1),('uv_oracle_use_a',None),
                 ('invariant_b',True),('invariant_b',0),('uv_oracle_barriers',1),('uv_oracle_barriers',True),
                 ('uv_oracle_barrier_ok',[True,False]),('uv_oracle_barrier_ok',[1,1]),('uv_oracle_barrier_ok',[True]),
                 ('draw_order',a.DRAW_ORDER),('draw_ok',{'A1':True,'B1':False,'A2':True,'B2':True})]
        changes += [(key,None) for key in ('uv_oracle','uv_oracle_use_a','uv_oracle_barriers',
                                           'uv_oracle_barrier_ok','uv_oracle_barrier_epoch_before','uv_oracle_barrier_epoch_after')]
        for key,value in changes:
            with self.subTest(key=key,value=value):
                self.m=json.loads(json.dumps(original));self.m[key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema5_barrier_epochs_strict_and_zero_allowed(self):
        self.make_oracle();original=json.loads(json.dumps(self.m))
        for epoch in ('0','7',str((1<<64)-1)):
            self.m=json.loads(json.dumps(original))
            for key in ('draw_epoch_before','draw_epoch_after'):self.m[key]=[epoch]*4
            for key in ('uv_oracle_barrier_epoch_before','uv_oracle_barrier_epoch_after'):self.m[key]=[epoch]*2
            self.save();self.assertEqual(a.analyze(self.path)['status'],'captured-floats-bit-equal')
        for key in ('uv_oracle_barrier_epoch_before','uv_oracle_barrier_epoch_after'):
            for value in ([],['0'],['0']*3,[0,0],['-1','-1'],[str(1<<64)]*2,['0','1'],['7','7']):
                with self.subTest(key=key,value=value):
                    self.m=json.loads(json.dumps(original));self.m[key]=value;self.save()
                    with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema5_missing_oracle_site_invalid(self):
        self.make_oracle(True);self.lib[19]=0;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'sample_site_count'):a.analyze(self.path)
    def test_schema6_probe_complete(self):
        for use_a in (False,True):
            with self.subTest(use_a=use_a):
                if use_a:self.setUp()
                self.make_probe(use_a);r=a.analyze(self.path)
                self.assertEqual(r['status'],'captured-floats-bit-equal')
                self.assertEqual(len(r['files']),7)
                self.assertTrue(r['oracle_probe_analysis']['preconditions_valid'])
                self.assertEqual(r['oracle_probe_analysis']['records'],4)
                self.assertFalse(r['causal_conclusion_allowed'])
    def test_schema6_gpu_rejected_counts_retained_separately_from_terminal_a(self):
        self.make_probe()
        for index,base in enumerate((0,26,52,78)):
            self.probe[index*10+3:index*10+10]=[0,0,0,0,6,0,2];self.lib[base+19]=0
        self.mark_probe_invalid(33);r=a.analyze(self.path);d=r['oracle_probe_analysis']
        self.assertEqual(r['status'],'diagnostic-invalid')
        self.assertEqual(r['numeric_status'],'captured-floats-bit-equal')
        self.assertEqual(d['invalid_records'],4);self.assertEqual(d['reason_counts'],{'6':4})
        self.assertEqual(d['GPU_observed_vs_CPU_terminal']['A_fragment_count_differences'],4)
        example=d['first_invalid_records'][0]
        self.assertEqual(example['GPU_observed_A']['fragment_count'],0)
        self.assertEqual(example['CPU_terminal_A']['fragment_count'],1)
        self.assertEqual(example['execution']['actual_sample_sites'],1)
        self.assertEqual(example['B_dependency_valid_count'],0)
        result=subprocess.run([sys.executable,str(Path(a.__file__)),str(self.path)],capture_output=True,text=True)
        self.assertEqual(result.returncode,3);self.assertEqual(json.loads(result.stdout)['status'],'diagnostic-invalid')
    def test_schema6_outside_roi_is_not_an_a_read(self):
        self.make_probe();self.probe[3:10]=[0,0,0,0,1,0,2];self.lib[19]=0;self.mark_probe_invalid(1)
        r=a.analyze(self.path);d=r['oracle_probe_analysis']
        self.assertEqual(d['A_read_records'],3)
        example=d['first_invalid_records'][0]
        self.assertFalse(example['A_read_performed'])
        self.assertIsNone(example['GPU_observed_A']['fragment_count'])
        self.assertIsNone(example['GPU_observed_A']['UV_finite'])
    def test_schema6_observed_nan_retained_without_json_nonfinite(self):
        self.make_probe();self.probe[5]=0x7fc00000;self.probe[7:10]=[8,0,2];self.lib[19]=0;self.mark_probe_invalid(33)
        r=a.analyze(self.path)
        self.assertEqual(r['status'],'diagnostic-invalid')
        example=r['oracle_probe_analysis']['first_invalid_records'][0]
        self.assertFalse(example['GPU_observed_A']['UV_finite'])
        self.assertEqual(example['GPU_observed_A']['stored_UV_bits'][0],'7fc00000')
        json.dumps(r,allow_nan=False)
    def test_schema6_observed_finite_uv_different_from_terminal_invalid(self):
        self.make_probe();self.probe[5]=bits(.91);self.lib[14]=bits(.91);self.mark_probe_invalid(32)
        r=a.analyze(self.path);d=r['oracle_probe_analysis']
        self.assertEqual(r['status'],'diagnostic-invalid')
        self.assertEqual(d['reason_counts'],{'0':4})
        self.assertEqual(d['GPU_observed_vs_CPU_terminal']['A_UV_bit_differences'],1)
    def test_schema6_selected_uv_must_match_same_observed_values(self):
        self.make_probe();self.lib[14]=bits(.91);self.mark_probe_invalid(64);r=a.analyze(self.path)
        self.assertEqual(r['oracle_probe_analysis']['issue_counts']['selected-a-uv-mismatch'],1)
    def test_schema6_control_does_not_require_original_uv_to_match_a(self):
        self.make_probe(False);self.lib[14]=bits(.91);self.save();r=a.analyze(self.path)
        self.assertEqual(r['status'],'captured-float-differences')
        self.assertTrue(r['oracle_probe_analysis']['preconditions_valid'])
    def test_schema6_probe_execution_coverage_is_hard_gate(self):
        self.make_probe()
        for index in (0,1,2,10,11,12,20,21,22,30,31,32):
            for value in (0,2):
                with self.subTest(index=index,value=value):
                    old=self.probe[index];self.probe[index]=value;self.save()
                    with self.assertRaisesRegex(a.InvalidCapture,'execution coverage'):a.analyze(self.path)
                    self.probe[index]=old
    def test_schema6_probe_reason_and_selection_consistency(self):
        self.make_probe();original=self.probe.copy()
        self.lib[19]=2;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'range'):a.analyze(self.path)
        self.lib[19]=1
        changes=[(7,16),(8,2),(9,3)]
        for index,value in changes:
            with self.subTest(index=index,value=value):
                self.probe=original.copy();self.probe[index]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        for index,value,mask in ((7,4,7),(8,0,29),(9,0,8)):
            with self.subTest(index=index,value=value,mask=mask):
                self.setUp();self.make_probe();self.probe[index]=value;self.mark_probe_invalid(mask)
                r=a.analyze(self.path)
                self.assertEqual(r['status'],'diagnostic-invalid')
                self.assertEqual(r['oracle_probe_analysis']['cpu_validation_mask'],mask)
    def test_schema6_outside_flag_contradiction_is_retained_as_ambiguous(self):
        self.make_probe();self.probe[7:10]=[1,0,2];self.lib[19]=0;self.mark_probe_invalid(3)
        r=a.analyze(self.path);d=r['oracle_probe_analysis']
        self.assertEqual(r['status'],'diagnostic-invalid')
        self.assertEqual(d['A_read_ambiguous_records'],1)
        record=d['first_invalid_records'][0]
        self.assertIsNone(record['A_read_performed'])
        self.assertIsNone(record['GPU_observed_A']['fragment_count'])
        self.assertEqual(record['GPU_observed_A']['raw_fragment_count'],1)
    def test_schema6_cpu_mask_aggregates_all_records(self):
        self.make_probe();self.probe[5]=bits(.91);self.lib[14]=bits(.91)
        self.lib[26+14]=bits(.92);self.mark_probe_invalid(96);r=a.analyze(self.path)
        d=r['oracle_probe_analysis']
        self.assertEqual(d['cpu_validation_mask'],96)
        self.assertEqual(d['invalid_records'],2)
        self.assertEqual(d['cpu_validation_reasons'],['observed-a-uv-mismatch','selected-a-uv-mismatch'])
    def test_schema6_validity_claim_contradiction_keeps_diagnostic(self):
        self.make_probe();self.probe[5]=bits(.91);self.lib[14]=bits(.91);self.save()
        with self.assertRaises(a.InvalidCapture) as result:a.analyze(self.path)
        self.assertIsNotNone(result.exception.diagnostic)
        self.assertEqual(result.exception.diagnostic['invalid_records'],1)
        cli=subprocess.run([sys.executable,str(Path(a.__file__)),str(self.path)],capture_output=True,text=True)
        self.assertEqual(cli.returncode,2)
        self.assertEqual(json.loads(cli.stdout)['diagnostic']['cpu_validation_mask'],32)
    def test_schema6_probe_metadata_status_identity_and_size(self):
        self.make_probe();original=json.loads(json.dumps(self.m))
        changes=[('uv_oracle_probe',False),('uv_oracle_probe_status','pending'),('uv_oracle_probe_words',39),
                 ('uv_oracle_probe_words_per_pixel',9),('oracle_preconditions_valid',0),('oracle_preconditions_valid',False),
                 ('oracle_cpu_validation_mask',128),('oracle_cpu_validation_mask',True),('oracle_cpu_validation_reasons',['unknown'])]
        for key,value in changes+[(key,None) for key in ('uv_oracle_probe','uv_oracle_probe_status','uv_oracle_probe_words','uv_oracle_probe_words_per_pixel','oracle_preconditions_valid','oracle_cpu_validation_mask','oracle_cpu_validation_reasons')]:
            with self.subTest(key=key,value=value):
                self.m=json.loads(json.dumps(original));self.m[key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        self.m=json.loads(json.dumps(original));self.probe=self.probe[:-1];self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'byte size: oracle_probe'):a.analyze(self.path)
    def test_schema6_diagnostic_invalid_does_not_bypass_hard_gates(self):
        self.make_probe();self.probe[3:10]=[0,0,0,0,6,0,2];self.lib[19]=0;self.mark_probe_invalid(33)
        original=json.loads(json.dumps(self.m))
        for key,value in [('lib_fence_signaled',False),('android_swap_succeeded',False),('lib_status','pending'),
                          ('uv_oracle_barrier_ok',[True,False]),('draw_epoch_before',['0','0','1','0'])]:
            with self.subTest(key=key):
                self.m=json.loads(json.dumps(original));self.m[key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        self.m=json.loads(json.dumps(original));self.lib[10]=0;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'coverage not exactly one'):a.analyze(self.path)
    def test_schema6_diagnostic_invalid_requires_dedicated_prefix(self):
        self.make_probe();self.m.update(status='diagnostic-invalid',oracle_preconditions_valid=False,
                oracle_cpu_validation_mask=1,oracle_cpu_validation_reasons=['gpu-dependency-invalid']);self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'capture identity'):a.analyze(self.path)
    def test_schema6_dependency_count_not_execution_count(self):
        self.make_probe();self.lib[19]=0;self.mark_probe_invalid(16)
        r=a.analyze(self.path)
        self.assertEqual(r['status'],'diagnostic-invalid')
        self.assertEqual(r['oracle_probe_analysis']['cpu_validation_mask'],16)
    def assert_schema6_actual_nonfinite_rejected(self, diagnostic_invalid):
        self.make_probe()
        if diagnostic_invalid:
            self.probe[3:10]=[0,0,0,0,6,0,2];self.lib[19]=0;self.mark_probe_invalid(33)
        main_offsets=list(range(1,10))+list(range(11,19))+list(range(20,25))
        fields=[('main',self.lib,base+offset) for base in (0,26,52,78) for offset in main_offsets]
        fields += [('Android',self.android,base+offset) for base in (0,7) for offset in range(1,7)]
        for name,words,index in fields:
            old=words[index]
            for value in (0x7fc00000,0x7f800000,0xff800000):
                with self.subTest(diagnostic_invalid=diagnostic_invalid,name=name,index=index,value=value):
                    words[index]=value;self.save()
                    with self.assertRaisesRegex(a.InvalidCapture,'nonfinite actual '+name+' float'):a.analyze(self.path)
            words[index]=old
    def test_schema6_complete_actual_main_and_android_nonfinite_hard_rejected(self):
        self.assert_schema6_actual_nonfinite_rejected(False)
    def test_schema6_diagnostic_actual_main_and_android_nonfinite_hard_rejected(self):
        self.assert_schema6_actual_nonfinite_rejected(True)
    def test_schema6_diagnostic_android_nan_cli_is_invalid_capture(self):
        self.make_probe();self.probe[3:10]=[0,0,0,0,6,0,2];self.lib[19]=0;self.mark_probe_invalid(33)
        self.android[1]=0x7fc00000;self.save()
        cli=subprocess.run([sys.executable,str(Path(a.__file__)),str(self.path)],capture_output=True,text=True)
        self.assertEqual(cli.returncode,2)
        report=json.loads(cli.stdout)
        self.assertEqual(report['status'],'invalid-capture')
        self.assertIn('nonfinite actual Android float',report['reason'])
    def test_schema7_single_pair_and_no_repetition_claim(self):
        self.make_single_pair();r=a.analyze(self.path)
        self.assertEqual(r['status'],'captured-floats-bit-equal')
        self.assertFalse(r['within_capture_repeatability_measured'])
        self.assertFalse(r['single_pair_metadata']['programs_reused'])
        self.assertEqual(r['repeat_analysis']['status'],'not-measured-single-pair')
        self.assertEqual(set(r['sample_tap_analysis']['comparisons']),{'ab1'})
        self.assertFalse(r['sample_tap_analysis']['captured_repeatability_confirmed'])
        self.assertEqual(r['oracle_probe_analysis']['records'],2)
        self.assertIn('A1 versus B1',r['current_ab'])
        self.assertIn('physical program instance',r['program_instance_scope'])
    def test_schema7_control_uv_difference_allowed(self):
        self.make_single_pair(False);self.lib[14]=bits(.91);self.save();r=a.analyze(self.path)
        self.assertEqual(r['status'],'captured-float-differences')
        self.assertTrue(r['oracle_probe_analysis']['preconditions_valid'])
        self.assertEqual(r['oracle_uv_relation']['status'],'UV-match-not-required-for-control')
    def test_schema7_diagnostic_invalid_retains_single_pair_record(self):
        self.make_single_pair();self.probe[3:10]=[0,0,0,0,6,0,2];self.lib[19]=0;self.mark_probe_invalid(33)
        r=a.analyze(self.path)
        self.assertEqual(r['status'],'diagnostic-invalid')
        self.assertEqual(r['oracle_probe_analysis']['records'],2)
        self.assertEqual(r['oracle_probe_analysis']['invalid_records'],1)
        self.assertEqual(r['oracle_probe_analysis']['cpu_validation_mask'],33)
        cli=subprocess.run([sys.executable,str(Path(a.__file__)),str(self.path)],capture_output=True,text=True)
        self.assertEqual(cli.returncode,3)
        self.assertEqual(json.loads(cli.stdout)['status'],'diagnostic-invalid')
    def test_schema7_metadata_rejects_repeat_shape_and_reuse_claims(self):
        self.make_single_pair();original=json.loads(json.dumps(self.m))
        changes=[('uv_oracle_single_pair',False),('uv_oracle_single_pair',None),('repetitions',2),
                 ('draw_order',['B1','A1']),('draw_order',a.ORACLE_DRAW_ORDER),
                 ('draw_ok',dict.fromkeys(a.ORACLE_DRAW_ORDER,True)),('programs_reused',True),
                 ('program_tokens',['11','22','11','22']),('program_tokens',['11','0']),
                 ('draw_epoch_before',['0']*4),('draw_epoch_after',['0','1']),
                 ('uv_oracle_barriers',2),('uv_oracle_barrier_ok',[True,True]),
                 ('uv_oracle_barrier_epoch_before',['0','0']),('uv_oracle_barrier_epoch_after',['1']),
                 ('frame_id',0),('invariant_b',True)]
        for key,value in changes:
            with self.subTest(key=key,value=value):
                self.m=json.loads(json.dumps(original));self.m[key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema7_exact_single_chunk_sizes_and_identity(self):
        self.make_single_pair();self.lib*=2;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'byte size: lib'):a.analyze(self.path)
        self.lib=self.lib[:52];self.probe*=2;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'byte size: oracle_probe'):a.analyze(self.path)
        self.probe=self.probe[:20];self.m['lib_words']=104;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'wrong word count: lib'):a.analyze(self.path)
        self.m['lib_words']=52;self.m['uv_oracle_probe_words']=40;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'wrong oracle probe word count'):a.analyze(self.path)
        self.m['uv_oracle_probe_words']=20;self.m['files']['oracle_probe']='mks-yuv-compare-123-2.oracle-probe.bin';self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'capture identity'):a.analyze(self.path)
    def test_schema7_execution_coverage_hard_and_final_csc_is_a1(self):
        self.make_single_pair()
        for index in (0,1,2,10,11,12):
            self.probe[index]=0;self.save()
            with self.assertRaisesRegex(a.InvalidCapture,'execution coverage'):a.analyze(self.path)
            self.probe[index]=1
        for base in (0,26):
            for index in (0,10,25):
                self.lib[base+index]=0;self.save()
                with self.assertRaisesRegex(a.InvalidCapture,'coverage not exactly one'):a.analyze(self.path)
                self.lib[base+index]=1
        self.android[0]=0;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'final_A1_CSC'):a.analyze(self.path)
    def test_schema7_actual_nonfinite_never_diagnostic_evidence(self):
        for diagnostic_invalid in (False,True):
            self.setUp();self.make_single_pair()
            if diagnostic_invalid:
                self.probe[3:10]=[0,0,0,0,6,0,2];self.lib[19]=0;self.mark_probe_invalid(33)
            fields=[('main',self.lib,base+index) for base in (0,26) for index in (1,4,7,11,14,16,20,22,24)]
            fields += [('Android',self.android,base+index) for base in (0,7) for index in (1,6)]
            for name,words,index in fields:
                old=words[index]
                for word in (0x7fc00000,0x7f800000,0xff800000):
                    with self.subTest(diagnostic_invalid=diagnostic_invalid,name=name,index=index,word=word):
                        words[index]=word;self.save()
                        with self.assertRaisesRegex(a.InvalidCapture,'nonfinite actual '+name):a.analyze(self.path)
                words[index]=old
    def test_schema7_oracle_selected_uv_mismatch_rejects_conclusion(self):
        self.make_single_pair();self.lib[14]=bits(.91);self.mark_probe_invalid(64);r=a.analyze(self.path)
        self.assertEqual(r['status'],'diagnostic-invalid')
        self.assertEqual(r['oracle_probe_analysis']['cpu_validation_mask'],64)
        self.assertFalse(r['causal_conclusion_allowed'])
    def test_schema6_not_relaxed_by_single_pair_option(self):
        self.make_probe();self.m.update(uv_oracle_single_pair=True,repetitions=1);self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'invalid repetitions'):a.analyze(self.path)
    def test_schema8_control_and_reverse_full_records(self):
        for reverse in (False,True):
            self.setUp();self.make_quad_order(reverse);r=a.analyze(self.path)
            self.assertEqual(r['status'],'captured-floats-bit-equal');self.assertEqual(len(r['files']),9)
            relation=r['quad_payload_relation']
            self.assertEqual(relation['permutation'],[3,2,1,0] if reverse else [0,1,2,3])
            self.assertTrue(relation['padding_bytes_preserved'])
            self.assertEqual(relation['A_twice_signed_areas'],relation['B_twice_signed_areas'])
            self.assertFalse(r['within_capture_repeatability_measured'])
            self.assertIn('not production',relation['scope'])
    def test_schema8_requires_exact_full_record_permutation_including_padding(self):
        self.make_quad_order(True)
        # Reversing active attribute bytes but retaining old padding is invalid.
        b=bytearray(self.candidate_vertices)
        for i in range(4):b[i*20+16:i*20+20]=self.baseline_vertices[i*20+16:i*20+20]
        self.candidate_vertices=bytes(b);self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'full records'):a.analyze(self.path)
    def test_schema8_declared_reverse_cannot_hide_identity_or_alternate_permutation(self):
        self.make_quad_order(True);records=[self.baseline_vertices[i*20:(i+1)*20] for i in range(4)]
        for permutation in ([0,1,2,3],[1,3,0,2]):
            self.candidate_vertices=b''.join(records[i] for i in permutation);self.save()
            with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema8_layout_hard_gates(self):
        self.make_quad_order();original=copy.deepcopy(self.m)
        changes=[('primitive','triangle_list'),('indexed',True),('vertex_count',3),('num_attributes',1),
                 ('position_attrib',2),('stride',21),('stride',1028),('byte_size',79),
                 ('viewport',[0,0,7,8]),('scissors',[False,0,8,8])]
        for key,value in changes:
            with self.subTest(key=key,value=value):
                self.m=copy.deepcopy(original);self.m['quad_vertex_layout'][key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema8_attribute_format_and_bounds_hard_gates(self):
        self.make_quad_order();original=copy.deepcopy(self.m)
        changes=[('name','_15'),('location',0),('format_name',''),('glsl_type','vec3'),('fmt_type','unorm'),
                 ('opaque',True),('num_planes',1),('component_depth',[32,16,0,0]),
                 ('host_bits',[32,16,0,0]),('sample_order',[1,0,2,3]),('host_bits',[32,32,0]),
                 ('offset',9),('offset',16),('offset',4),('texel_size',16)]
        for key,value in changes:
            with self.subTest(key=key,value=value):
                self.m=copy.deepcopy(original);self.m['quad_vertex_layout']['attributes'][1][key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema8_all_supported_float_attribute_widths(self):
        for components,format_name in ((1,'r32f'),(3,'rgb32f'),(4,'rgba32f')):
            self.setUp();self.make_quad_order();layout=self.m['quad_vertex_layout']
            extra=copy.deepcopy(layout['attributes'][0])
            extra.update(name='_17',format_name=format_name,glsl_type='float' if components==1 else 'vec'+str(components),
                location=2,num_components=components,component_depth=[32]*components+[0]*(4-components),
                host_bits=[32]*components+[0]*(4-components),offset=16,texel_size=4*components)
            layout['attributes'].append(extra);layout['num_attributes']=3;layout['stride']=20+4*components
            layout['byte_size']=4*layout['stride']
            rows=[]
            for i in range(4):
                values=struct.unpack_from('<4f',self.baseline_vertices,i*20)
                rows.append(struct.pack('<'+'f'*(4+components)+'I',*values,*([.25]*components),0x7fc00000+i))
            self.baseline_vertices=self.candidate_vertices=b''.join(rows)
            p=self.root/self.m['files']['vertex'];p.write_text(p.read_text().replace('void main() {','in '+extra['glsl_type']+' _17;\nvoid main() {'))
            self.save();self.assertEqual(a.analyze(self.path)['quad_payload_relation']['status'],'exact-full-record-permutation')
    def test_schema8_actual_vertex_attributes_must_be_finite_but_padding_may_be_any_bits(self):
        self.make_quad_order(True)
        for key in ('baseline_vertices','candidate_vertices'):
            original=getattr(self,key)
            for vertex in range(4):
                for offset in (0,4,8,12):
                    b=bytearray(original);struct.pack_into('<I',b,vertex*20+offset,0x7fc00000)
                    setattr(self,key,bytes(b));self.save()
                    with self.assertRaisesRegex(a.InvalidCapture,'nonfinite actual quad attribute'):a.analyze(self.path)
            setattr(self,key,original)
    def test_schema8_position_geometry_requires_unique_corners_and_middle_diagonal(self):
        self.make_quad_order();original=self.baseline_vertices
        for positions in (((-1,1),(1,1),(-1,-1),(-1,1)),((-1,1),(1,1),(-1,-1),(0.5,-1)),
                          ((-1,1),(1,-1),(-1,-1),(1,1))):
            b=bytearray(original)
            for i,position in enumerate(positions):struct.pack_into('<2f',b,i*20+8,*position)
            self.baseline_vertices=self.candidate_vertices=bytes(b);self.save()
            with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema8_unknown_vertex_position_transform_or_input_rejected(self):
        self.make_quad_order();p=self.root/self.m['files']['vertex'];original=p.read_text()
        for source in (original.replace('vec2 va_pos = _16;','vec2 va_pos = _16;\nva_pos += vec2(0.1);'),
                       original.replace('in vec2 _16;','in vec3 _16;'),original.replace('vec2 va_pos = _16;','vec2 va_pos = _15;')):
            p.write_text(source)
            with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
    def test_schema8_binary_size_identity_and_quad_mode_hard_gates(self):
        self.make_quad_order();original=copy.deepcopy(self.m)
        for key,value in [('quad_order',False),('quad_order_reverse',1),('uv_oracle_use_a',True)]:
            self.m=copy.deepcopy(original);self.m[key]=value;self.save()
            with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        self.m=copy.deepcopy(original);self.candidate_vertices+=b'xxxx';self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'byte size: candidate_vertices'):a.analyze(self.path)
        self.candidate_vertices=self.candidate_vertices[:-4]
        self.m['files']['baseline_vertices']='mks-yuv-compare-123-2.baseline-vertices.bin';self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'capture identity'):a.analyze(self.path)
    def test_schema8_diagnostic_invalid_never_becomes_geometric_or_numeric_acceptance(self):
        self.make_quad_order(True);self.probe[3:10]=[0,0,0,0,6,0,2];self.lib[19]=0;self.mark_probe_invalid(33)
        r=a.analyze(self.path)
        self.assertEqual(r['status'],'diagnostic-invalid');self.assertFalse(r['causal_conclusion_allowed'])
        self.assertEqual(r['quad_payload_relation']['status'],'exact-full-record-permutation')
        self.android[1]=0x7fc00000;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'nonfinite actual Android'):a.analyze(self.path)

class InvariantSourceTest(unittest.TestCase):
    def setUp(self):
        self.anchor='#version 310 es\nout vec2 _8003;\nvoid main() {\ngl_Position = vec4(va_pos, 0.0, 1.0);\n_8003 = vec2(0.0);\n}\n'
        self.candidate=self.anchor.replace('void main','invariant gl_Position;\ninvariant _8003;\nvoid main',1)
    def test_exact_two_declarations_source_relation(self):
        result=a.invariant_vertex_relation(self.anchor,self.candidate,'_8003')
        self.assertEqual(result['status'],'exact-two-invariant-declarations-only')
        self.assertFalse(result['identical'])
        self.assertIn('+invariant gl_Position;',result['unified_diff'])
        self.assertIn('does not independently prove A0',result['scope'])
    def test_extra_change_or_bad_declarations_fail_closed(self):
        for candidate in (self.candidate.replace('vec2(0.0)','vec2(1.0)'),self.anchor,
                          self.candidate.replace('invariant _8003;\n',''),
                          self.candidate.replace('invariant _8003;\n','invariant _8003;\ninvariant _8003;\n'),
                          self.candidate.replace('invariant _8003;','//invariant _8003;'),
                          self.anchor+'invariant gl_Position;\ninvariant _8003;\n'):
            with self.subTest(candidate=candidate):
                with self.assertRaises(a.InvalidCapture):a.invariant_vertex_relation(self.anchor,candidate,'_8003')
    def test_bad_uv_identifier_fail_closed(self):
        for identifier in ('gl_Position','_8003; injected',None,'1uv','','_0','_abcd1','_ABCD'):
            with self.subTest(identifier=identifier):
                with self.assertRaises(a.InvalidCapture):a.invariant_vertex_relation(self.anchor,self.candidate,identifier)
    def test_source_diff_truncation_explicit(self):
        result=a.source_difference('a\n'*10000,'b\n'*10000,'left','right')
        self.assertTrue(result['diff_truncated'])
        self.assertEqual(len(result['unified_diff']),32768)

class SampleTapComparisonTest(unittest.TestCase):
    def setUp(self):
        self.samples={name:{'uv':list(map(bits,(.1,.2,.3,.4))),
                            'sample_rgb':list(map(bits,(.1,.2,.3,.4,.5,.6)))} for name in a.DRAW_ORDER}
    def test_stable_taps_carry_instrumentation_limit(self):
        result=a.compare_sample_taps(self.samples,2,(4,6))
        self.assertEqual(result['repeatability'],'sample-taps-bit-stable')
        self.assertIn('not an unmodified shader',result['scope'])
    def test_uv_uses_two_components_and_real_pixel_coordinate(self):
        for name in ('B1','B2'):self.samples[name]['uv'][3]=bits(.9)
        result=a.compare_sample_taps(self.samples,2,(4,6))
        self.assertEqual(result['repeatability'],'sample-taps-bit-stable')
        diff=result['comparisons']['ab2']['uv']['first_differences'][0]
        self.assertEqual((diff['x'],diff['y'],diff['channel']),(5,6,'V'))
    def test_sample_rgb_same_program_repeat_is_strict(self):
        self.samples['A2']['sample_rgb'][0]=bits(.9)
        result=a.compare_sample_taps(self.samples,2,(4,6))
        self.assertEqual(result['repeatability'],'sample-taps-bit-unstable')
        self.assertFalse(result['captured_repeatability_confirmed'])
        self.assertEqual(result['comparisons']['baseline_repeat']['sample_rgb']['bit_mismatches'],1)
    def test_equal_nonfinite_uv_invalid(self):
        for name in a.DRAW_ORDER:self.samples[name]['uv'][0]=0x7f800000
        result=a.compare_sample_taps(self.samples,2,(4,6))
        self.assertEqual(result['repeatability'],'invalid-nonfinite')
        self.assertFalse(result['captured_repeatability_confirmed'])
    def test_missing_tap_draw_or_stage_invalid(self):
        del self.samples['A1']['uv']
        with self.assertRaises(a.InvalidCapture):a.compare_sample_taps(self.samples,2,(0,0))
        self.setUp();del self.samples['A2']
        with self.assertRaises(a.InvalidCapture):a.compare_sample_taps(self.samples,2,(0,0))

class RepeatComparisonTest(unittest.TestCase):
    def setUp(self):
        self.samples={name:{stage:list(map(bits,(.1,.2,.3))) for stage in ('pre_rgb','half_rgb','yuv')}
                      for name in ('B1','B2','A2')}
        self.samples['A1']={'pre_rgb':list(map(bits,(.1,.2,.3)))}
    def test_stable_captured_stages_do_not_imply_full_baseline_repeat(self):
        r=a.compare_repeats(self.samples,1,(4,6))
        self.assertEqual(r['repeatability'],'captured-stages-bit-stable')
        self.assertFalse(r['ab_localization']['full_baseline_repeatability_confirmed'])
        self.assertEqual(r['not_captured']['baseline_repeat'],['half_rgb','yuv'])
        self.assertEqual(set(r['comparisons']['baseline_repeat']),{'pre_rgb'})
    def test_each_candidate_repeat_stage_difference(self):
        for stage in ('pre_rgb','half_rgb','yuv'):
            with self.subTest(stage=stage):
                old=self.samples['B2'][stage][0];self.samples['B2'][stage][0]=bits(.9)
                r=a.compare_repeats(self.samples,1,(4,6))
                self.assertEqual(r['repeatability'],'captured-stages-bit-unstable')
                self.assertEqual(r['comparisons']['candidate_repeat'][stage]['bit_mismatches'],1)
                self.assertFalse(r['ab_localization']['captured_repeatability_confirmed'])
                self.samples['B2'][stage][0]=old
    def test_baseline_pre_repeat_difference(self):
        self.samples['A1']['pre_rgb'][1]=bits(.9)
        r=a.compare_repeats(self.samples,1,(4,6))
        self.assertEqual(r['repeatability'],'captured-stages-bit-unstable')
        self.assertEqual(r['comparisons']['baseline_repeat']['pre_rgb']['bit_mismatches'],1)
    def test_stable_ab_pre_difference(self):
        for name in ('B1','B2'):self.samples[name]['pre_rgb'][0]=bits(.9)
        r=a.compare_repeats(self.samples,1,(4,6))
        self.assertEqual(r['repeatability'],'captured-stages-bit-stable')
        self.assertEqual(r['ab_localization']['first_differing_stage'],{'ab1':'pre_rgb','ab2':'pre_rgb'})
    def test_missing_or_synthetic_stage_rejected(self):
        del self.samples['B1']['half_rgb']
        with self.assertRaises(a.InvalidCapture):a.compare_repeats(self.samples,1,(0,0))
        self.setUp();self.samples['A1']['half_rgb']=self.samples['A2']['half_rgb']
        with self.assertRaises(a.InvalidCapture):a.compare_repeats(self.samples,1,(0,0))
    def test_repeat_nonfinite_is_invalid(self):
        self.samples['B1']['yuv'][0]=self.samples['B2']['yuv'][0]=0x7fc00000
        r=a.compare_repeats(self.samples,1,(0,0))
        self.assertEqual(r['repeatability'],'invalid-nonfinite')
        self.assertFalse(r['ab_localization']['captured_repeatability_confirmed'])

class AtlasCaptureTest(unittest.TestCase):
    def setUp(self):
        fixture=CaptureTest();fixture.setUp();fixture.make_quad_order(False)
        self.addCleanup(fixture.doCleanups);self.root=fixture.root;self.path=fixture.path
        layout=copy.deepcopy(fixture.m['quad_vertex_layout'])
        layout['viewport']=layout['scissors']=[0,0,2,1]
        self.m={'schema':9,'status':'complete','scope':a.ATLAS_SCOPE,'pid':123,'capture_id':1,
            'generation':2,'frame_id':9,'frame_token':10,'source_pts':35.035,'current_pts':35.035,
            'target_pts':35.035,'width':2,'height':1,'pixels':2,'rgba_words':8,'atlas_words':6,
            'byte_order':'little','read_format':6408,'read_type':5126,'draw_order':['a0_before','atlas_a','a0_after'],
            'draw_ok':[True]*3,'readback_ok':[True]*3,'half_exact':[True]*3,'program_tokens':['11','22','11'],
            'draw_epoch_before':['0']*3,'draw_epoch_after':['0']*3,'readback_epoch_before':['0']*3,
            'readback_epoch_after':['0']*3,'finish_epoch':'0','framebuffer':[7]*3,'source_abi_ok':True,
            'fence_signaled':True,'atlas_complete':True,'anchor_equal':True,'mismatches_before_atlas':0,
            'mismatches_before_after':0,'bad_half_components':[0]*3,'bad_atlas_pixels':0,
            'anchor_validation_mask':0,'anchor_validation_reasons':[],'baseline_ok':True,'android_status':'ready',
            'android_swap_succeeded':True,'android_fence_signaled':True,'android_words':14,
            'android_roi':{'x':0,'y':0,'w':2,'h':1},'vertex_layout':layout,'comparison_pass':'unknown',
            'readback_representation':a.ATLAS_REPRESENTATION,'instrumentation_scope':a.ATLAS_INSTRUMENTATION,
            'files':{key:'mks-yuv-atlas-123-1'+a.ATLAS_SUFFIXES[key] for key in a.ATLAS_FILES}}
        self.rgba=list(map(bits,(.125,.25,.5,1.0,.75,.5,.625,1.0)))
        self.payload={key:self.rgba.copy() for key in ('a0_before','atlas_a','a0_after')}
        self.payload.update(atlas=[bits(.25),bits(.5),1,bits(.75),bits(.5),1],
                            android=[1,*map(bits,(.125,.25,.5,.25,.5,.75))]*2)
        self.vertices=fixture.baseline_vertices
        body='void main() {\n  vec4 color = textureLod(tex, uv, 0.0);\ncolor_out = color;\n}\n'
        a0='#version 310 es\n'+body
        def chunk(name):return '// MKS_ATLAS_'+name+'_BEGIN\n// inserted\n// MKS_ATLAS_'+name+'_END\n'
        atlas=a0.replace(body,chunk('GLOBALS')+body).replace('vec4 color',chunk('SITE')+'vec4 color')
        atlas=atlas[:-2]+chunk('TAIL')+atlas[-2:]
        self.sources={'a0_fragment':a0,'atlas_fragment':atlas,'original_body':body,
            'vertex':(self.root/fixture.m['files']['vertex']).read_text()}
        self.save()
    def save(self):
        self.path.write_text(json.dumps(self.m))
        for key,words in self.payload.items():
            (self.root/self.m['files'][key]).write_bytes(struct.pack('<'+'I'*len(words),*words))
        (self.root/self.m['files']['baseline_vertices']).write_bytes(self.vertices)
        for key,source in self.sources.items():(self.root/self.m['files'][key]).write_text(source)
    def mark_difference(self,mask):
        self.m.update(status='diagnostic-invalid',comparison_pass='refused',anchor_equal=False,
            anchor_validation_mask=mask,anchor_validation_reasons=[v for k,v in a.ATLAS_REASONS.items() if mask&k])
        self.m['mismatches_before_after']=int(bool(mask&1));self.m['mismatches_before_atlas']=int(bool(mask&2))
        self.m['files']={key:'mks-yuv-atlas-123-1.diagnostic-invalid'+a.ATLAS_SUFFIXES[key] for key in a.ATLAS_FILES}
        self.save()
    def test_full_capture_equal_and_scope(self):
        result=a.analyze(self.path)
        self.assertEqual(result['status'],'captured-floats-bit-equal')
        self.assertFalse(result['quality_pass']);self.assertTrue(result['diagnostic_only'])
        self.assertEqual(result['source_relation']['status'],'exact-three-insertions')
        self.assertEqual(len(result['archived_files']),10)
        self.assertEqual(result['atlas_coverage']['coverage'],'exactly-one-record-per-pixel')
    def test_a0_and_instrumented_atlas_cannot_share_program_identity(self):
        self.m['program_tokens']=['11','11','11'];self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'distinct program tokens'):a.analyze(self.path)
    def test_a0_rejects_legacy_capture_and_all_storage_buffers(self):
        original=copy.deepcopy(self.sources)
        for prefix in ('layout(std430,binding=0) buffer legacy_capture {uint mks_compare_words[];};\n',
                       'layout(std430,binding=0) readonly buffer payload {float words[];};\n',
                       'layout(std430,binding=0) coherent buffer payload {uint words[];};\n',
                       'uint mks_tap_site_count;\n','uint MKS_COMPARE_words;\n',
                       'uint mks_legacy_unknown;\n','uint MKS_OTHER_CAPTURE;\n',
                       'layout(rgba16f,binding=0) readonly uniform highp image2D values;\n',
                       'layout(rgba8ui,binding=0) writeonly uniform highp uimage2DArray values;\n'):
            with self.subTest(prefix=prefix):
                self.sources=copy.deepcopy(original)
                for key in ('a0_fragment','atlas_fragment'):
                    self.sources[key]=self.sources[key].replace('#version 310 es\n','#version 310 es\n'+prefix,1)
                self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        self.sources=copy.deepcopy(original)
        for key in ('a0_fragment','atlas_fragment'):
            self.sources[key]=self.sources[key].replace('#version 310 es\n',
                '#version 310 es\n// no buffer descriptor\n/* buffer is only a comment */\n'
                'layout(std140,binding=1) uniform Params { vec4 ordinary_value; };\n'
                'uniform sampler2D ordinary_texture;\n',1)
        self.save();self.assertEqual(a.analyze(self.path)['status'],'captured-floats-bit-equal')
    def test_sole_direct_sample_cannot_be_duplicated_or_replaced(self):
        original=copy.deepcopy(self.sources)
        for call in ('textureLod(tex, uv, 0.0)','texture(tex, uv)','texelFetch(tex, ivec2(0), 0)',
                     'textureProj(tex, vec3(uv, 1.0))'):
            with self.subTest(call=call):
                self.sources=copy.deepcopy(original)
                self.sources['atlas_fragment']=original['atlas_fragment'].replace('// inserted\n',
                    'vec4 extra_sample = '+call+';\n',1)
                self.save()
                with self.assertRaisesRegex(a.InvalidCapture,'sole direct textureLod'):a.analyze(self.path)
        self.sources=copy.deepcopy(original)
        for key in ('a0_fragment','atlas_fragment','original_body'):
            self.sources[key]=self.sources[key].replace('textureLod(tex, uv, 0.0)','texture(tex, uv)')
        self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'sole direct textureLod'):a.analyze(self.path)
    def test_mismatch_masks_are_independently_verified(self):
        for mask in (1,2,3):
            with self.subTest(mask=mask):
                self.setUp()
                if mask&1:self.payload['a0_after'][0]=bits(.875)
                if mask&2:self.payload['atlas_a'][0]=bits(.875)
                self.mark_difference(mask);result=a.analyze(self.path)
                self.assertEqual(result['status'],'diagnostic-invalid')
                self.assertEqual(result['numeric_status'],'captured-float-differences')
                self.assertFalse(result['quality_pass'])
                self.m['mismatches_before_atlas']+=1;self.save()
                with self.assertRaisesRegex(a.InvalidCapture,'disagrees'):a.analyze(self.path)
    def test_metadata_hard_gates(self):
        original=copy.deepcopy(self.m)
        bads={'scope':'quality-pass','width':True,'pixels':1,'rgba_words':7,'atlas_words':5,
            'read_format':5126,'read_type':6408,'draw_order':['atlas_a','a0_before','a0_after'],
            'program_tokens':['11','22','33'],'draw_ok':[True,False,True],'readback_ok':[True]*2,
            'half_exact':[True,True,False],'framebuffer':[7,8,7],'finish_epoch':'1',
            'readback_epoch_after':['0','1','0'],'source_abi_ok':False,'fence_signaled':False,
            'atlas_complete':False,'baseline_ok':False,'android_swap_succeeded':False,'android_status':'pending',
            'bad_half_components':[0,1,0],'bad_atlas_pixels':1,'anchor_equal':False,'comparison_pass':'passed',
            'anchor_validation_reasons':['atlas-rgb-mismatch'],'android_words':7,'generation':0}
        for key,value in bads.items():
            with self.subTest(key=key):
                self.m=copy.deepcopy(original);self.m[key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        self.m=original
        self.m['width']=4096;self.m['height']=1025;self.m['pixels']=4096*1025
        with self.assertRaisesRegex(a.InvalidCapture,'budget'):a.atlas_metadata(self.m)
    def test_atlas_uv_and_execution_are_hard_gates(self):
        for offset,word in ((0,0x7fc00000),(1,0x7f800000),(2,0),(2,2),(2,0x80000001),(5,0xffffffff)):
            with self.subTest(offset=offset,word=word):
                old=self.payload['atlas'][offset];self.payload['atlas'][offset]=word;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
                self.payload['atlas'][offset]=old
    def test_main_and_android_nonfinite_never_diagnostic_success(self):
        self.payload['atlas_a'][0]=bits(.875);self.mark_difference(2)
        for role in ('a0_before','atlas_a','a0_after','android'):
            for offset in range(len(self.payload[role])):
                if role=='android' and offset%7==0:continue
                with self.subTest(role=role,offset=offset):
                    old=self.payload[role][offset];self.payload[role][offset]=0x7fc00000;self.save()
                    with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
                    self.payload[role][offset]=old
        self.payload['android'][0]=2;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'Android CSC coverage'):a.analyze(self.path)
    def test_sources_payload_geometry_and_file_identity(self):
        original=self.sources['atlas_fragment']
        for source in (original.replace('color_out = color;','color_out = color*2.0;'),
                       original.replace('// MKS_ATLAS_SITE_END\n',''),
                       original+'// MKS_ATLAS_SITE_BEGIN\n'):
            with self.subTest(source=source[-60:]):
                self.sources['atlas_fragment']=source;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        self.sources['atlas_fragment']=original;self.save()
        old=self.vertices;self.vertices=old[:-1];self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'byte size'):a.analyze(self.path)
        self.vertices=old;self.save();self.m['files']['atlas']='mks-yuv-atlas-123-2.atlas.bin'
        self.path.write_text(json.dumps(self.m))
        with self.assertRaisesRegex(a.InvalidCapture,'identity'):a.analyze(self.path)
    def test_source_and_geometry_anchors_reject_unverified_changes(self):
        original=copy.deepcopy(self.sources)
        for key,value in (('original_body',original['original_body']+'// missing\n'),
                          ('a0_fragment',original['a0_fragment']+'// mks_atlas collision\n'),
                          ('vertex',original['vertex'].replace('vec4(va_pos, 0.0, 1.0)','vec4(va_pos*2.0, 0.0, 1.0)'))):
            with self.subTest(key=key):
                self.sources=copy.deepcopy(original);self.sources[key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path)
        self.sources=original;self.save()
        self.vertices=struct.pack('<f',float('nan'))+self.vertices[4:];self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'nonfinite actual quad attribute'):a.analyze(self.path)
    def test_files_and_manifest_hashes_are_strict(self):
        self.save();file=self.root/self.m['files']['a0_after'];file.write_bytes(file.read_bytes()[:-4])
        with self.assertRaisesRegex(a.InvalidCapture,'byte size'):a.analyze(self.path)
        self.save();self.m['sha256']={key:'0'*64 for key in a.ATLAS_FILES};self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'hash mismatch'):a.analyze(self.path)
    def test_cli_refuses_diagnostic(self):
        self.payload['atlas_a'][0]=bits(.875);self.mark_difference(2)
        run=subprocess.run([sys.executable,str(Path(a.__file__)),str(self.path)],capture_output=True,text=True)
        self.assertEqual(run.returncode,3)
        self.assertEqual(json.loads(run.stdout)['status'],'diagnostic-invalid')

class AtlasReadCaptureTest(unittest.TestCase):
    def setUp(self):
        seed=AtlasCaptureTest();seed.setUp();self.addCleanup(seed.doCleanups)
        body='vec4 body_color() {\nvec4 color = textureLod(tex, uv, 0.0);\nreturn color;\n}\n'
        a0='#version 310 es\nuniform sampler2D tex;\nout vec4 out_color;\n'+body+'void main() {\nout_color = body_color();\n}'
        def chunk(prefix,name,code='// inserted\n'):
            return '// '+prefix+name+'_BEGIN\n'+code+'// '+prefix+name+'_END\n'
        atlas=a0.replace(body,chunk('MKS_ATLAS_','GLOBALS')+body).replace('vec4 color',chunk('MKS_ATLAS_','SITE')+'vec4 color')
        atlas=atlas[:-1]+chunk('MKS_ATLAS_','TAIL')+atlas[-1:]
        seed.sources.update(a0_fragment=a0,atlas_fragment=atlas,original_body=body);seed.save()
        self.seed_root=seed.root;self.seed_path=seed.root/'mks-yuv-atlas-123-1.json'
        seed.path.rename(self.seed_path)
        self.root=seed.root/'read1';self.root.mkdir();self.path=self.root/'capture.json'
        self.m={'schema':10,'status':'complete','scope':a.ATLAS_READ_SCOPE,'comparison_pass':'unknown',
            'pid':123,'capture_id':11,'generation':2,'ordinal':1,'frame_id':9,'frame_token':11,
            'source_pts':35.035,'current_pts':35.035,'target_pts':35.035,'seed_capture_id':1,
            'seed_frame_id':9,'seed_frame_token':10,'seed_pts':35.035,'seed_input_image_token':'123',
            'input_image_token':'123','seed_input_texture_token':'456','input_texture_token':'456',
            'cache_id':55,'cache_generation':2,'cache_storage_buffer':77,'cache_storage_offset':'0',
            'cache_storage_size':'24','renderer_id':'99','renderer_generation':'1','signature':'0'*64,
            'seed_reference':{'manifest':self.seed_path.name,'sha256':a.hashlib.sha256(self.seed_path.read_bytes()).hexdigest()},
            'width':2,'height':1,'pixels':2,'rgba_words':8,'probe_words':8,'atlas_words':6,'byte_order':'little',
            'read_format':6408,'read_type':5126,'draw_order':['a0','uv','half'],'draw_ok':[True]*3,
            'readback_ok':[True]*3,'program_tokens':['11','22','22'],'b0_program_token':'33','b0_drawn':False,
            'probe_modes':[0,1],'draw_epoch_before':['0']*3,'draw_epoch_after':['0']*3,
            'readback_epoch_before':['0']*3,'readback_epoch_after':['0']*3,'finish_epoch':'0',
            'baseline_ok':True,'fence_signaled':True,'signature_match':True,'reject_reason':0,
            'uv_equal':True,'half_equal':True,'bad_uv_pixels':0,'bad_half_pixels':0,'read_validation_mask':0,
            'read_validation_reasons':[],'android_status':'ready','android_swap_succeeded':True,
            'android_fence_signaled':True,'android_words':14,'android_roi':seed.m['android_roi'],
            'vertex_layout':seed.m['vertex_layout'],'diagnostic_cache_settings':{'skip_caching_single_frame':True,'preserve_mixing_cache':False},
            'cache_policy':a.ATLAS_CACHE_POLICY,'source_scope':a.ATLAS_READ_SOURCE_SCOPE,
            'signature_algorithm':'sha256-length-prefix-v1','signature_scope':a.ATLAS_SIGNATURE_SCOPE,
            'files':{k:'mks-uv-atlas-read-123-11'+a.ATLAS_READ_SUFFIXES[k] for k in a.ATLAS_READ_FILES}}
        helper=('layout(std430,binding=0) readonly restrict buffer mks_cache_block { highp uint mks_cache_words[6]; };\n'
            'highp vec2 mks_cache_uv() {\nuvec2 mks_cache_p=uvec2(gl_FragCoord.xy);\n'
            'uint mks_cache_i=(mks_cache_p.y*2u+mks_cache_p.x)*3u;\n'
            'highp vec2 mks_cache_loaded=uintBitsToFloat(uvec2(mks_cache_words[mks_cache_i],mks_cache_words[mks_cache_i+1u]));\n'
            'return mks_cache_loaded;\n}\n')
        b0='#version 310 es\nuniform sampler2D tex;\nlayout(yuv) out highp vec3 out_color;\n'+helper+body.replace('textureLod(tex, uv, 0.0)',
            'textureLod(tex, mks_cache_uv(), 0.0)')+'void main() {\nhighp vec3 mks_rgb = body_color().rgb;\nout_color = mks_rgb;\n}'
        probe=a.atlas_read_probe_source(b0,2,1)
        self.sources={'a0_fragment':a0,'b0_fragment':b0,'probe_fragment':probe,
            'vertex':seed.sources['vertex'],'original_body':body}
        self.payload={'a0':seed.payload['a0_before'].copy(),'seed_atlas':seed.payload['atlas'].copy(),
            'android':seed.payload['android'].copy()}
        self.payload['uv']=[1,*self.payload['seed_atlas'][:2],1,1,*self.payload['seed_atlas'][3:5],1]
        self.payload['half']=[1,*self.payload['a0'][:3],1,*self.payload['a0'][4:7]]
        self.vertices=seed.vertices
        material={'input_width':2,'input_height':1,'sampler_type':0,'sample_mode':0,'address_mode':0,
            'format_type':5,'num_components':4,'component_depth':[16]*4,'host_bits':[16]*4,'sample_order':[0,1,2,3],
            'format_name':'rgba16f','num_variables':0,'uniform_bytes':0,'variables':[],'uniforms_hex':''}
        self.materials={key:json.dumps(material,separators=(',',':')).encode()+b'\n' for key in ('seed_material','current_material')}
        self.save()
    def save(self,refresh_signature=True):
        raw={key:source.encode() for key,source in self.sources.items()}
        raw.update(self.materials);raw['baseline_vertices']=self.vertices
        if refresh_signature:self.m['signature']=a.atlas_read_signature(raw,self.m['vertex_layout'],2,1,2)
        for key,data in raw.items():(self.root/self.m['files'][key]).write_bytes(data)
        for key,words in self.payload.items():(self.root/self.m['files'][key]).write_bytes(struct.pack('<'+'I'*len(words),*words))
        self.path.write_text(json.dumps(self.m))
    def test_complete_single_observation_is_not_reuse_or_b0_proof(self):
        result=a.analyze(self.path,seed_root=self.seed_root)
        self.assertEqual(result['status'],'captured-floats-bit-equal')
        self.assertTrue(result['within_frame_fullscreen_uv_half_equal'])
        for key in ('quality_pass','cross_pts_reuse_validated','b0_numerical_equivalence_established','yuv_equality_measured'):
            self.assertFalse(result[key])
        with self.assertRaisesRegex(a.InvalidCapture,'explicit complete schema9'):a.analyze(self.path)
    def test_fresh_second_pts_pair_can_change_rgb_not_mapping(self):
        first=self.path
        self.root=self.seed_root/'read2';self.root.mkdir();self.path=self.root/'capture.json'
        self.m.update(capture_id=12,ordinal=2,frame_id=10,frame_token=12,source_pts=600.032766667,
            current_pts=600.032766667,target_pts=600.032766667,input_image_token='124',input_texture_token='457')
        self.m['files']={k:'mks-uv-atlas-read-123-12'+a.ATLAS_READ_SUFFIXES[k] for k in a.ATLAS_READ_FILES}
        self.payload['a0'][0]=bits(.875);self.payload['half'][1]=bits(.875);self.save()
        result=a.validate_atlas_read_pair(first,self.path,self.seed_root)
        self.assertTrue(result['cross_pts_reuse_validated']);self.assertFalse(result['quality_pass'])
        self.m['renderer_generation']='2';self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'renderer_generation'):a.validate_atlas_read_pair(first,self.path,self.seed_root)
    def test_signature_material_source_and_seed_dependencies_are_strict(self):
        original=copy.deepcopy(self.materials)
        self.materials['current_material']=self.materials['current_material'].replace(b'"input_width":2',b'"input_width":3');self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'material differs'):a.analyze(self.path,seed_root=self.seed_root)
        self.materials=original;self.save();self.m['signature']='f'*64;self.save(False)
        with self.assertRaisesRegex(a.InvalidCapture,'signature digest'):a.analyze(self.path,seed_root=self.seed_root)
        self.save();self.m['seed_reference']['sha256']='f'*64;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'seed manifest SHA'):a.analyze(self.path,seed_root=self.seed_root)
    def test_probe_marker_and_actual_atlas_helper_reject_changes(self):
        original=copy.deepcopy(self.sources)
        self.sources['probe_fragment']=self.sources['probe_fragment'].replace('// MKS_READ_SITE_END\n','');self.save()
        with self.assertRaises(a.InvalidCapture):a.analyze(self.path,seed_root=self.seed_root)
        self.sources=original
        for key in ('b0_fragment','probe_fragment'):
            self.sources[key]=self.sources[key].replace('return mks_cache_loaded;','return vec2(0.0);')
        self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'probe insertion locations|readonly atlas helper'):a.analyze(self.path,seed_root=self.seed_root)
    def test_probe_semantics_and_uniform_abi_are_checked(self):
        self.sources['probe_fragment']=self.sources['probe_fragment'].replace('mks_read_uv=mks_cache_loaded;',
            'mks_read_uv=vec2(0.0);');self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'insertion semantics'):a.analyze(self.path,seed_root=self.seed_root)
        material=json.loads(self.materials['seed_material'])
        source='uniform sampler2D tex;\nuniform mat3 _m;\n'
        material.update(num_variables=1,uniform_bytes=36,uniforms_hex='00'*36,
            variables=[{'name':'_m','type':3,'dim_v':3,'dim_m':3,'dim_a':1,'offset':0,'size':36}])
        a.validate_atlas_read_uniforms(source,source,material)
        for bad in ('uniform Params {float _m;};\nuniform sampler2D tex;\n',
                    source.replace('mat3','vec3'),source+'uniform sampler2D other;\n'):
            with self.subTest(source=bad),self.assertRaises(a.InvalidCapture):a.validate_atlas_read_uniforms(bad,bad,material)
    def test_coverage_finite_and_half_are_hard_gates_even_for_diagnostics(self):
        self.payload['half'][1]=bits(.875)
        self.m.update(status='diagnostic-invalid',comparison_pass='refused',half_equal=False,bad_half_pixels=1,
            read_validation_mask=2,read_validation_reasons=['half-mismatch'])
        self.m['files']={k:'mks-uv-atlas-read-123-11.diagnostic-invalid'+a.ATLAS_READ_SUFFIXES[k] for k in a.ATLAS_READ_FILES}
        for role,offset,word in (('uv',0,2),('uv',3,0),('uv',1,0x7fc00000),('half',0,0),
            ('half',1,0x7f800000),('half',2,bits(.1)),('a0',3,0x7fc00000),('seed_atlas',2,2),('android',1,0x7fc00000)):
            with self.subTest(role=role,offset=offset):
                old=self.payload[role][offset];self.payload[role][offset]=word;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path,seed_root=self.seed_root)
                self.payload[role][offset]=old
        self.save()
        self.seed_path.unlink()
        with self.assertRaisesRegex(a.InvalidCapture,'missing or symlink'):a.analyze(self.path,seed_root=self.seed_root)
    def test_metadata_fallback_owner_mode_identity_fail_closed(self):
        original=copy.deepcopy(self.m)
        for key,value in {'signature_match':False,'reject_reason':1,'b0_drawn':True,'probe_modes':[1,0],
            'program_tokens':['11','22','33'],'b0_program_token':'22','frame_token':10,'frame_id':10,
            'cache_storage_size':'20','cache_generation':3,'fence_signaled':False,
            'readback_epoch_after':['0','1','0'],'signature_scope':'native key proven'}.items():
            with self.subTest(key=key):
                self.m=copy.deepcopy(original);self.m[key]=value;self.save()
                with self.assertRaises(a.InvalidCapture):a.analyze(self.path,seed_root=self.seed_root)
    def test_uv_half_diff_diagnostic_and_component_vs_pixel_count(self):
        self.payload['uv'][1]=bits(.875);self.payload['uv'][2]=bits(.75)
        self.m.update(status='diagnostic-invalid',comparison_pass='refused',uv_equal=False,bad_uv_pixels=1,
            read_validation_mask=1,read_validation_reasons=['uv-mismatch'])
        self.m['files']={k:'mks-uv-atlas-read-123-11.diagnostic-invalid'+a.ATLAS_READ_SUFFIXES[k] for k in a.ATLAS_READ_FILES};self.save()
        result=a.analyze(self.path,seed_root=self.seed_root)
        self.assertEqual(result['status'],'diagnostic-invalid')
        self.assertEqual(result['uv_analysis']['comparison']['bit_mismatches'],2)
        self.assertEqual(result['bad_uv_pixels'],1)
        self.m['bad_uv_pixels']=2;self.save()
        with self.assertRaisesRegex(a.InvalidCapture,'producer validation'):a.analyze(self.path,seed_root=self.seed_root)
    def test_material_packed_layout_and_uniform_bytes(self):
        material=json.loads(self.materials['seed_material'])
        material.update(num_variables=1,uniform_bytes=8,variables=[{'name':'_1','type':3,'dim_v':2,'dim_m':1,'dim_a':1,'offset':0,'size':8}],uniforms_hex='000000000000803f')
        a.atlas_read_material(material)
        for key,value in (('offset',4),('size',4),('type',0),('dim_v',0)):
            bad=copy.deepcopy(material);bad['variables'][0][key]=value
            with self.subTest(key=key),self.assertRaises(a.InvalidCapture):a.atlas_read_material(bad)

class AtlasConsumerNumericTest(unittest.TestCase):
    def setUp(self):
        self.atlas=[bits(.1),bits(.2),1,bits(.7),bits(.8),1]
        self.uv=[1,bits(.1),bits(.2),1,1,bits(.7),bits(.8),1]
        self.rgba=list(map(bits,(.125,.25,.5,1.,.625,.75,.875,1.)))
        self.half=[1,*self.rgba[:3],1,*self.rgba[4:7]]
    def test_fullscreen_values_equal(self):
        uv=a.compare_atlas_consumer_uv(self.uv,self.atlas,2,1)
        half=a.compare_atlas_consumer_half(self.half,self.rgba,2,1)
        self.assertEqual(uv['status'],half['status']);self.assertEqual(uv['status'],'captured-floats-bit-equal')
        self.assertEqual(uv['comparison']['components'],4);self.assertEqual(half['comparison']['components'],6)
        self.assertIn('uninstrumented B0',half['scope'])
    def test_uv_and_half_bit_differences_are_located(self):
        self.uv[6]=bits(.9)
        result=a.compare_atlas_consumer_uv(self.uv,self.atlas,2,1)
        self.assertEqual(result['status'],'captured-float-differences')
        difference=result['comparison']['first_differences'][0]
        self.assertEqual((difference['x'],difference['y'],difference['channel']),(1,0,'V'))
        self.half[5]=bits(.5)
        result=a.compare_atlas_consumer_half(self.half,self.rgba,2,1)
        self.assertEqual(result['comparison']['bit_mismatches'],1)
        self.assertEqual(result['comparison']['first_differences'][0]['channel'],'R')
    def test_incomplete_and_duplicate_execution_fail(self):
        for key in ('uv','half'):
            original=getattr(self,key).copy()
            for bad in (original[:-1],original*2):
                with self.subTest(key=key,size=len(bad)),self.assertRaises(a.InvalidCapture):
                    if key=='uv':a.compare_atlas_consumer_uv(bad,self.atlas,2,1)
                    else:a.compare_atlas_consumer_half(bad,self.rgba,2,1)
            for count in (0,2,True):
                bad=original.copy();bad[0]=count
                with self.subTest(key=key,count=count),self.assertRaises(a.InvalidCapture):
                    if key=='uv':a.compare_atlas_consumer_uv(bad,self.atlas,2,1)
                    else:a.compare_atlas_consumer_half(bad,self.rgba,2,1)
        self.uv[3]=0
        with self.assertRaises(a.InvalidCapture):a.compare_atlas_consumer_uv(self.uv,self.atlas,2,1)
    def test_nonfinite_and_nonhalf_rejected(self):
        for word in (0x7fc00000,0x7f800000,0xff800000):
            uv=self.uv.copy();uv[1]=word
            with self.assertRaises(a.InvalidCapture):a.compare_atlas_consumer_uv(uv,self.atlas,2,1)
        for word in (0x7fc00000,0x7f800000,bits(.1),bits(65536.)):
            half=self.half.copy();half[1]=word
            with self.assertRaises(a.InvalidCapture):a.compare_atlas_consumer_half(half,self.rgba,2,1)
        rgba=self.rgba.copy();rgba[3]=0x7fc00000
        with self.assertRaises(a.InvalidCapture):a.compare_atlas_consumer_half(self.half,rgba,2,1)
    def test_zero_is_compared_by_bits(self):
        self.half[1]=bits(-0.);self.rgba[0]=bits(0.)
        result=a.compare_atlas_consumer_half(self.half,self.rgba,2,1)
        self.assertEqual(result['comparison']['bit_mismatches'],1)
        self.assertEqual(result['comparison']['max_absolute_difference'],0.)

class AtlasReadbackTest(unittest.TestCase):
    def setUp(self):
        self.words = list(map(bits, (.125,.25,.5,1.0,.75,.5,.625,1.0)))
    def test_all_three_equal(self):
        result = a.compare_atlas_readbacks(self.words,self.words,self.words,2,1)
        self.assertEqual(result['status'],'captured-floats-bit-equal')
        self.assertTrue(result['baseline_readback_stable'])
        self.assertIn('not physical storage bytes',result['representation'])
    def test_each_pair_and_signed_zero(self):
        before=self.words.copy();middle=self.words.copy();after=self.words.copy()
        before[0]=middle[0]=bits(0.0);after[0]=bits(-0.0)
        result=a.compare_atlas_readbacks(before,middle,after,2,1)
        self.assertFalse(result['baseline_readback_stable'])
        self.assertEqual(result['comparisons']['A0_before_vs_after']['bit_mismatches'],1)
        middle=before.copy();middle[4]=bits(.875)
        result=a.compare_atlas_readbacks(before,middle,before,2,1)
        self.assertTrue(result['baseline_readback_stable'])
        diff=result['comparisons']['A0_before_vs_atlas_A']['first_differences'][0]
        self.assertEqual((diff['x'],diff['y'],diff['channel']),(1,0,'R'))
    def test_missing_duplicate_dimension_or_nonfinite_rejected(self):
        for role in range(3):
            for bad in (self.words[:-1],self.words*2):
                supplied=[self.words]*3;supplied[role]=bad
                with self.subTest(role=role,size=len(bad)),self.assertRaises(a.InvalidCapture):
                    a.compare_atlas_readbacks(*supplied,2,1)
            for offset in range(8):
                for word in (0x7fc00000,0x7f800000,0xff800000):
                    bad=self.words.copy();bad[offset]=word;supplied=[self.words]*3;supplied[role]=bad
                    with self.subTest(role=role,offset=offset,word=word),self.assertRaises(a.InvalidCapture):
                        a.compare_atlas_readbacks(*supplied,2,1)
        for width,height in ((True,1),(0,1),(2,2),(2,0)):
            with self.subTest(width=width,height=height),self.assertRaises(a.InvalidCapture):
                a.compare_atlas_readbacks(self.words,self.words,self.words,width,height)
    def test_exact_binary16_expansions_exhaustive(self):
        for half_bits in range(65536):
            value=struct.unpack('<e',struct.pack('<H',half_bits))[0]
            self.assertEqual(a.is_binary16_expansion(bits(value)), math.isfinite(value))
        for value in (.1,65536.0,2**-25):
            invalid=self.words.copy();invalid[0]=bits(value)
            with self.subTest(value=value),self.assertRaisesRegex(a.InvalidCapture,'binary16 expansion'):
                a.compare_atlas_readbacks(invalid,self.words,self.words,2,1)

if __name__=='__main__':unittest.main()
