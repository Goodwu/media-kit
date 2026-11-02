import copy
import json
from pathlib import Path
import struct
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parent))
import lg_p84_capture_round as m


def line(event, pid='123', **changes):
    fields = {'event': event, 'id': '99', 'generation': '2', 'source_pts': '35.035000000'}
    fields.update({'android': '1', 'lib': '1'} if event == 'armed' else
                  {'file': m.REMOTE + f'mks-yuv-compare-{pid}-99.json', 'comparison_pass': 'unknown'})
    fields.update(changes)
    return f'10-30 01:00:00.001 {pid} {pid} I flutter : MKS-YUV-COMPARE ' + ' '.join(f'{k}={v}' for k, v in fields.items())


def fixture(repeat=False, sample_tap=False, invariant_b=False, oracle_mode=None, uv_probe=False, diagnostic=False, single_pair=False, quad_reverse=None):
    event = m.completion(['seek', line('armed'), line('capture-complete',
        **({**({'repetitions': '2'} if repeat else {}), **({'sample_tap': '1'} if sample_tap else {}),
            **({'invariant_b': '1'} if invariant_b else {})}))],
                         '123', 0, 35.035, repeat, sample_tap, invariant_b)
    if oracle_mode is not None:
        event.update(uv_oracle='1', uv_oracle_use_a=str(oracle_mode))
    if uv_probe:
        event['uv_oracle_probe'] = '1'
    if single_pair:
        event.update(uv_oracle_single_pair='1',repetitions='1')
    if quad_reverse is not None:
        event.update(quad_order='1',quad_order_reverse=str(quad_reverse))
    if diagnostic:
        event.update(event='capture-diagnostic-invalid', comparison_pass='refused',
                     file=event['file'].replace('.json', '.diagnostic-invalid.json'))
    manifest = {'schema': 1, 'status': 'complete', 'scope': 'capture-only-not-comparison-pass',
        'pid': 123, 'capture_id': 99, 'generation': 2, 'frame_id': 8, 'frame_token': 7,
        'source_pts': 35.035, 'current_pts': 35.035, 'target_pts': 35.035, 'shader_body_hash': '12345',
        'target_width': 1, 'target_height': 1, 'roi': {'x': 0, 'y': 0, 'w': 1, 'h': 1},
        'lib_candidate_ok': True, 'lib_baseline_ok': True, 'lib_status': 'complete', 'android_status': 'ready',
        'android_swap_succeeded': True, 'lib_fence_signaled': True, 'android_fence_signaled': True,
        'lib_words': 14, 'android_words': 7, 'byte_order': 'little',
        'files': {k: 'mks-yuv-compare-123-99' + suffix for k, suffix in m.SUFFIXES.items()}}
    words = lambda vals: struct.pack('<' + str(len(vals)) + 'I', *vals)
    if repeat:
        manifest.update(schema=2, repetitions=2, draw_order=['B1', 'A1', 'B2', 'A2'],
            draw_ok={k: True for k in ('B1', 'A1', 'B2', 'A2')}, same_input_snapshot=True,
            programs_reused=True, program_tokens=['11', '22', '11', '22'],
            draw_epoch_before=['0']*4, draw_epoch_after=['0']*4,
            assertion_scope=m.analyzer.INPUT_ASSERTION_SCOPE, lib_words=28)
    if sample_tap:
        manifest.update(schema=3, sample_tap=True, sample_tap_site_count=1, words_per_pixel=26,
            sample_tap_body_hash='6789', instrumentation_scope=m.analyzer.SAMPLE_TAP_SCOPE, lib_words=52)
        manifest['files']['original_body'] = 'mks-yuv-compare-123-99.original-body.glsl'
    if invariant_b:
        manifest.update(schema=4, invariant_b=True, invariant_uv_identifier='_1',
            draw_order=['B1', 'A01', 'B2', 'A02'], draw_ok={k: True for k in ('B1', 'A01', 'B2', 'A02')})
        manifest['files']['candidate_vertex'] = 'mks-yuv-compare-123-99.candidate-vertex.glsl'
    if oracle_mode is not None:
        manifest.update(schema=5, uv_oracle=True, uv_oracle_use_a=bool(oracle_mode),
            uv_oracle_barriers=2, uv_oracle_barrier_ok=[True, True],
            uv_oracle_barrier_epoch_before=['0']*2, uv_oracle_barrier_epoch_after=['0']*2,
            draw_order=['A1', 'B1', 'A2', 'B2'], draw_ok={k: True for k in ('A1', 'B1', 'A2', 'B2')})
    if uv_probe:
        manifest.update(schema=6, uv_oracle_probe=True, uv_oracle_probe_status='complete',
            uv_oracle_probe_words=20, uv_oracle_probe_words_per_pixel=10,
            oracle_preconditions_valid=not diagnostic, oracle_cpu_validation_mask=1 if diagnostic else 0,
            oracle_cpu_validation_reasons=['gpu-dependency-invalid'] if diagnostic else [])
        manifest['files']['oracle_probe'] = 'mks-yuv-compare-123-99.oracle-probe.bin'
    if single_pair:
        manifest.update(schema=7,uv_oracle_single_pair=True,repetitions=1,draw_order=['A1','B1'],
            draw_ok={'A1':True,'B1':True},programs_reused=False,program_tokens=['11','22'],
            draw_epoch_before=['0']*2,draw_epoch_after=['0']*2,uv_oracle_barriers=1,
            uv_oracle_barrier_ok=[True],uv_oracle_barrier_epoch_before=['0'],uv_oracle_barrier_epoch_after=['0'],
            lib_words=26,uv_oracle_probe_words=10)
    if quad_reverse is not None:
        attributes=[]
        for index in (0,1):
            attributes.append({'name':'_'+str(index),'format_name':'rg32f','glsl_type':'vec2','fmt_type':'float32',
                'location':index,'num_components':2,'component_depth':[32,32,0,0],'host_bits':[32,32,0,0],
                'sample_order':[0,1,2,3],'offset':index*8,'texel_size':8,'opaque':False,'num_planes':0})
        manifest.update(schema=8,quad_order=True,quad_order_reverse=bool(quad_reverse),quad_vertex_layout={
            'primitive':'triangle_strip','indexed':False,'vertex_count':4,'num_attributes':2,'position_attrib':0,
            'stride':20,'byte_size':80,'viewport':[0,0,1,1],'scissors':[0,0,1,1],'attributes':attributes})
        manifest['files'].update(baseline_vertices='mks-yuv-compare-123-99.baseline-vertices.bin',
                                 candidate_vertices='mks-yuv-compare-123-99.candidate-vertices.bin')
    if diagnostic:
        manifest['status'] = 'diagnostic-invalid'
        manifest['files'] = {key: name.replace('mks-yuv-compare-123-99.', 'mks-yuv-compare-123-99.diagnostic-invalid.',1)
                             for key, name in manifest['files'].items()}
    files = {event['file']: json.dumps(manifest).encode()}
    for key, name in manifest['files'].items():
        if key == 'lib':
            data = words([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0])
            if sample_tap:data += words([0]*5+[1]+[0]*5+[1])
            if oracle_mode == 0:
                data = data[:14*4]+struct.pack('<f', .25)+data[15*4:]
            if diagnostic:
                data = data[:19*4]+words([0])+data[20*4:]
            if repeat and not single_pair:data *= 2
        elif key == 'android':
            data = words([1, 0, 0, 0, 0, 0, 0])
        elif key == 'original_body':
            data = b'color.rgb = textureLod(tex, uv, 0.0).rgb;\n'
        elif key == 'oracle_probe':
            data = words(([1,1,1,0,0,0,0,6,0,2] if diagnostic else [1,1,1,1,1,0,0,0,1,oracle_mode])*(1 if single_pair else 2))
        elif key in ('baseline_vertices','candidate_vertices'):
            records=[struct.pack('<4fI',*values,0xaabbcc00+i) for i,values in enumerate(
                [(-1.,-1.,0.,0.),(-1.,1.,0.,1.),(1.,-1.,1.,0.),(1.,1.,1.,1.)])]
            data=b''.join(reversed(records) if key=='candidate_vertices' and quad_reverse else records)
        elif key=='vertex' and quad_reverse is not None:
            data=b'#version 310 es\nlayout(location=0) in vec2 _0;\nlayout(location=1) in vec2 _1;\nout vec2 _2;\nvoid main() {\nvec2 va_pos = _0;\ngl_Position = vec4(va_pos, 0.0, 1.0);\n_2 = _1;\n}\n'
        elif invariant_b and key in ('vertex', 'candidate_vertex'):
            source = '#version 310 es\nout vec2 _1;\nvoid main() {\ngl_Position = vec4(va_pos, 0.0, 1.0);\n_1 = vec2(0.0);\n}\n'
            if key == 'candidate_vertex':source = source.replace('void main', 'invariant gl_Position;\ninvariant _1;\nvoid main', 1)
            data = source.encode()
        else:
            data = b'#version 310 es\nvoid main() {}\n'
        files[m.REMOTE + name] = data
    return event, manifest, files


def oracle_round(directory, mode, pid=123, capture_id=99, uv_probe=False, single_pair=False,quad_reverse=None):
    event, manifest, files = fixture(True, True, False, mode, uv_probe,single_pair=single_pair,quad_reverse=quad_reverse)
    directory = Path(directory);capture = directory/'capture';capture.mkdir(parents=True)
    old_prefix = 'mks-yuv-compare-123-99'
    new_prefix = f'mks-yuv-compare-{pid}-{capture_id}'
    manifest.update(pid=pid, capture_id=capture_id)
    manifest['files'] = {k: v.replace(old_prefix, new_prefix) for k, v in manifest['files'].items()}
    event.update(id=str(capture_id), file=m.REMOTE+new_prefix+'.json')
    for remote, data in files.items():
        name = Path(remote).name.replace(old_prefix, new_prefix)
        (capture/name).write_bytes(json.dumps(manifest).encode() if remote.endswith('.json') else data)
    result = {'status': 'completed-capture', 'restorationVerified': True, 'oracleMode': mode,
        'expectedCaptureSchema': 8 if quad_reverse is not None else 7 if single_pair else 6 if uv_probe else 5, 'oracleProbeRequested': uv_probe,
        'singlePairRequested':single_pair,
        'quadOrderRequested':quad_reverse is not None,'quadReverse':quad_reverse,
        'captureEvent': event, 'pid': str(pid), 'requestedPTS': 35.035, 'serial': 's',
        'apk': {'sha256': 'a'*64, 'bytes': 1234}, 'controls': m.controls(35.035, True, True, False, mode, uv_probe=uv_probe,single_pair=single_pair,quad_reverse=quad_reverse),
        'displayControls': {'brightness': 64, 'expectedBacklight': 64, 'expectedPanelThermalStatus': '0'},
        'sourceReceipt': {'verified': True, 'serial': 's', 'deviceSource': '/source.mp4', 'deviceSha256': 'b'*64,
                          'hostSha256': 'b'*64, 'deviceBytes': 123, 'hostBytes': 123, 'returncode': 0}}
    return directory, result


def oracle_triplet(root):
    return [oracle_round(Path(root)/str(i), mode, 123+i, 99+i) for i, mode in enumerate((0, 1, 0))]


class CaptureRoundTests(unittest.TestCase):
    def test_current_process_single_arm_complete_required(self):
        lines = ['seek', line('armed'), line('capture-complete')]
        self.assertEqual(m.completion(lines, '123', 0, 35.035)['id'], '99')
        self.assertIsNone(m.completion(lines, '999', 0, 35.035))
        self.assertIsNone(m.completion(lines[:2], '123', 0, 35.035))
        for bad in [lines[2:], lines + [line('capture-complete')],
                    ['seek', line('capture-complete'), line('armed')],
                    ['seek', line('armed', android='0'), line('capture-complete')],
                    ['seek', line('arm-input'), line('armed', lib='0'), line('arm-input-gl'), line('capture-complete')],
                    ['seek', line('armed'), line('capture-complete', generation='3')]]:
            with self.subTest(bad=bad), self.assertRaises(RuntimeError):
                m.completion(bad, '123', -1, 35.035)

    def test_failed_stale_malformed_wrong_frame_or_path_refused(self):
        for change in [{'id': '0'}, {'generation': 'x'}, {'source_pts': 'nan'},
                       {'source_pts': '35.068'}, {'file': '/tmp/old.json'}, {'comparison_pass': 'true'}]:
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                m.completion(['seek', line('armed'), line('capture-complete', **change)], '123', 0, 35.035)
        for event in ('config-invalid', 'capture-failed', 'unexpected'):
            with self.assertRaises(RuntimeError):m.completion([line(event)], '123', -1, 35.035)
        with self.assertRaisesRegex(RuntimeError, 'before-current-seek'):
            m.completion([line('armed'), 'seek', line('capture-complete')], '123', 1, 35.035)

    def test_diagnostic_namespaces_are_not_transaction_markers(self):
        diagnostic = line('arm-format').replace('MKS-YUV-COMPARE ', 'MKS-YUV-COMPARE-LIB ')
        lines = ['seek', diagnostic, line('arm-input'), line('armed'),
                 line('arm-input-gl'), line('capture-complete')]
        self.assertIsNotNone(m.completion(lines, '123', 0, 35.035))
        self.assertIsNone(m.completion([diagnostic, line('arm-input')], '123', -1, 35.035))
        # LIB events can never establish a VO transaction, even with complete's
        # fields, and unrecognized diagnostic extensions remain fail-closed.
        with self.assertRaisesRegex(RuntimeError, 'unknown-lib'):
            m.completion([line('capture-complete').replace('MKS-YUV-COMPARE ', 'MKS-YUV-COMPARE-LIB ')], '123', -1, 35.035)
        with self.assertRaisesRegex(RuntimeError, 'malformed-compare-event'):
            m.completion([line('armed') + ' event=capture-complete'], '123', -1, 35.035)

    def test_lib_readback_diagnostics_do_not_mask_terminal_failure(self):
        # Exact CPU-only diagnostic formats from gpu_tex.c; buffer metadata is
        # the producer allocation, not an independently queried GL binding.
        counts = ('10-30 06:30:00.000 123 123 I flutter : MPVLOG error: '
            'MKS-YUV-COMPARE-LIB event=readback-counts chunk=0 buffer_object=17 buffer_offset=0 buffer_size=425984 '
            'b_frag_zero=1 b_frag_one=4095 b_frag_other=0 a_frag_zero=0 a_frag_one=4096 a_frag_other=0 '
            'b_site_zero=1 b_site_one=4095 b_site_other=0 a_site_zero=0 a_site_one=4096 a_site_other=0')
        invalid = ('10-30 06:30:00.001 123 123 I flutter : MPVLOG error: '
            'MKS-YUV-COMPARE-LIB event=readback-first-invalid chunk=0 pixel=12 roi_x=12 roi_y=0 absolute_word=312 '
            'b_frag=0 a_frag=1 b_site=0 a_site=1 b_u_bits=00000000 b_v_bits=00000000 a_u_bits=3f000000 a_v_bits=3f000001')
        self.assertIsNone(m.completion([counts, invalid], '123', -1, 35.035))
        self.assertIsNone(m.completion(['seek', line('armed'), counts, invalid], '123', 0, 35.035))
        for terminal in (line('capture-failed', reason='invalid-coverage'), line('config-invalid')):
            with self.assertRaises(m.NativeCaptureFailure) as failure:
                m.completion(['seek', line('armed'), counts, invalid, terminal], '123', 0, 35.035)
            self.assertEqual(failure.exception.fields['event'], 'capture-failed' if 'capture-failed' in terminal else 'config-invalid')
            diagnostics = failure.exception.diagnostics
            self.assertEqual(next(d for d in diagnostics if d['event'] == 'readback-counts')['buffer_object'], '17')
            self.assertEqual(next(d for d in diagnostics if d['event'] == 'readback-first-invalid')['a_v_bits'], '3f000001')
        for wrong in (counts.replace('MKS-YUV-COMPARE-LIB ', 'MKS-YUV-COMPARE '),
                      invalid.replace('event=readback-first-invalid', 'event=readback-other')):
            with self.assertRaisesRegex(RuntimeError, 'unknown'):
                m.completion([wrong], '123', -1, 35.035)

    def test_actual_init_namespaces_allow_diagnostics_before_seek_not_capture(self):
        # gpu_next/context.c logs owner init in VO; libplacebo/opengl/gpu.c
        # logs capability init in LIB. Neither initialization event has an id.
        owner = ('10-30 04:30:00.000 123 123 I flutter : MPVLOG error: '
                 'MKS-YUV-COMPARE event=egl-owner-configured android-current-verified=1 egl-loader-requested=1')
        caps = ('10-30 04:30:00.001 123 123 I flutter : MPVLOG error: '
                'MKS-YUV-COMPARE-LIB event=caps-ready private_ssbo=1 fragment_blocks=4')
        self.assertIsNone(m.completion([owner, caps, 'seek'], '123', 2, 35.035))
        self.assertIsNotNone(m.completion([owner, caps, 'seek', line('armed'), line('capture-complete')], '123', 2, 35.035))
        self.assertEqual(m.compare_rows([owner], '123')[0][2]['android-current-verified'], '1')
        with self.assertRaisesRegex(RuntimeError, 'without-matching-arm'):
            m.completion([owner, caps, 'seek', line('capture-complete')], '123', 2, 35.035)
        for wrong in (owner.replace('MKS-YUV-COMPARE ', 'MKS-YUV-COMPARE-LIB '),
                      caps.replace('MKS-YUV-COMPARE-LIB ', 'MKS-YUV-COMPARE ')):
            with self.assertRaisesRegex(RuntimeError, 'unknown'):
                m.completion([wrong], '123', -1, 35.035)

    def test_init_rejections_failclosed_before_seek_with_reason_preserved(self):
        for prefix, event in [('MKS-YUV-COMPARE', 'egl-owner-rejected'),
                              ('MKS-YUV-COMPARE-LIB', 'caps-rejected')]:
            init = f'10-30 04:30:00.000 123 123 I flutter : {prefix} event={event} reason=owner-check before-lib-create=1'
            with self.subTest(event=event), self.assertRaises(m.NativeCaptureFailure) as failure:
                m.completion([init, 'seek', line('armed'), line('capture-complete')], '123', 1, 35.035)
            self.assertEqual(failure.exception.fields['reason'], 'owner-check')
            self.assertEqual(failure.exception.fields['before-lib-create'], '1')

    def test_native_ssbo_binding_rejection_formats_supersede_complete(self):
        # Exact formats from gpu_pass.c: unsupported query has a reason, while
        # linked-binding/epoch rejection supplies structural diagnostic fields.
        for detail in ('reason=unsupported-query',
                       'block=mks_compare index=4294967295 expected=3 actual=-1 length=0 clean=1 epoch_before=5 epoch_after=5'):
            rejected = ('10-30 04:45:00.000 123 123 I flutter : MPVLOG error: '
                        'MKS-YUV-COMPARE-LIB event=ssbo-binding-rejected ' + detail)
            with self.subTest(detail=detail), self.assertRaisesRegex(
                    m.NativeCaptureFailure, '^native-lib-ssbo-binding-rejected$') as failure:
                m.completion(['seek', line('armed'), rejected, line('capture-complete')], '123', 0, 35.035)
            fields = failure.exception.fields
            if detail.startswith('reason='):
                self.assertEqual(fields['reason'], 'unsupported-query')
            else:
                self.assertEqual(fields['actual'], '-1')
                self.assertEqual(fields['epoch_after'], '5')
                self.assertNotIn('reason', fields)  # Preserve native fields; invent no reason.
        with self.assertRaisesRegex(RuntimeError, 'unknown'):
            m.completion([rejected.replace('MKS-YUV-COMPARE-LIB ', 'MKS-YUV-COMPARE ')], '123', -1, 35.035)

    def test_native_sample_tap_rejected_even_after_complete_preserves_reason(self):
        for reason in ('site-not-unique-or-supported', 'highp-default'):
            rejected = ('10-30 05:30:00.000 123 123 I flutter : MPVLOG error: '
                        'MKS-YUV-COMPARE-LIB event=sample-tap-rejected reason=' + reason +
                        (' precision=16 range=14,15 clean=1' if reason == 'highp-default' else ''))
            for after_complete in (False, True):
                markers = [line('armed'), line('capture-complete', repetitions='2', sample_tap='1')]
                lines = ['seek'] + (markers + [rejected] if after_complete else [rejected] + markers)
                with self.subTest(reason=reason, after_complete=after_complete), self.assertRaisesRegex(
                        m.NativeCaptureFailure, '^native-lib-sample-tap-rejected$') as failure:
                    m.completion(lines, '123', 0, 35.035, True, True)
                self.assertEqual(failure.exception.fields['reason'], reason)
                if reason == 'highp-default':
                    self.assertEqual(failure.exception.fields['precision'], '16')
                    self.assertEqual(failure.exception.fields['range'], '14,15')
                    self.assertEqual(failure.exception.fields['clean'], '1')
                self.assertEqual(failure.exception.diagnostics[-1 if after_complete else 0]['event'], 'sample-tap-rejected')
            with self.assertRaisesRegex(RuntimeError, 'unknown'):
                m.completion([rejected.replace('MKS-YUV-COMPARE-LIB ', 'MKS-YUV-COMPARE ')], '123', -1, 35.035)
            with self.assertRaisesRegex(RuntimeError, 'unknown-lib'):
                m.completion([rejected.replace('event=sample-tap-rejected', 'event=sample-tap-unrecognized')], '123', -1, 35.035)

    def test_real_armdiag_failure_reports_terminal_not_unknown_diagnostic(self):
        # 2026-10-30 capture-smoke-35-armdiag: old host stopped on arm-input
        # and masked the explicit arm failure one log line later.
        lines = [
            '10-30 04:22:47.158 32181 32181 I flutter : MPVLOG error: MKS-YUV-COMPARE-LIB event=arm-rejected reason=egl-owner id=5876524309 generation=2 gles=32 target_fbo=0 baseline_fbo=1 target=2672x1336 baseline=2672x1336x0 renderable=1 target_yuv=1 existing_capture=0 production_draws=0 roi=1304,636,64,64',
            '10-30 04:22:47.161 32181 32181 I flutter : MPVLOG error: MKS-YUV-COMPARE event=arm-input id=5876524309 target=2672x1336 baseline=2672x1336 depth=0 renderable=1 format=fbo type=5 components=4 bits=16,16,16,16 roi=1304,636,64,64',
            '10-30 04:22:47.162 32181 32181 I flutter : MPVLOG error: MKS-YUV-COMPARE event=arm-input-gl id=5876524309 target_fbo=0 baseline_fbo=0 target_iformat=0x0 baseline_iformat=0x0 epoch_valid=0',
            '10-30 04:22:47.163 32181 32181 I flutter : MPVLOG error: MKS-YUV-COMPARE event=capture-failed id=5876524309 reason=arm-failed terminal=1 owner_current=1 owner_restored=0 frame_closed=1 fatal_context=0 requires_force_stop=0']
        with self.assertRaisesRegex(m.NativeCaptureFailure, '^native-capture-failed$') as failure:
            m.completion(lines, '32181', -1, 35.035)
        self.assertEqual(failure.exception.fields['reason'], 'arm-failed')
        self.assertEqual(len(failure.exception.diagnostics), 4)
        with self.assertRaisesRegex(m.NativeCaptureFailure, 'lib-arm-rejected'):
            m.completion(lines[:1], '32181', -1, 35.035)

    def test_terminal_failure_supersedes_complete_and_requires_force_stop(self):
        for name in ('capture-failed', 'fatal-cleanup-deferred', 'cleanup-deferred'):
            with self.subTest(event=name), self.assertRaises(m.NativeCaptureFailure) as failure:
                m.completion(['seek', line('armed'), line('capture-complete'),
                              line(name, terminal='1', fatal_context='1', requires_force_stop='1')], '123', 0, 35.035)
            self.assertEqual(failure.exception.fields['requires_force_stop'], '1')

    def test_manifest_requires_exact_native_identity_target_and_ROI(self):
        event, manifest, _ = fixture()
        self.assertEqual(len(m.validate_manifest(manifest, event, '123', 35.035)), 5)
        for key, value in [('pid', 124), ('capture_id', 100), ('generation', True), ('frame_token', 0),
                           ('current_pts', 35.035003), ('source_pts', float('nan')), ('target_pts', 35.034),
                           ('scope', 'comparison-pass'), ('roi', {'x': 0, 'y': 0, 'w': 2, 'h': 1}),
                           ('files', {**manifest['files'], 'candidate': '../outside.glsl'})]:
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                m.validate_manifest({**manifest, key: value}, event, '123', 35.035)

    def test_repeat_mode_requires_matching_event_manifest_and_metadata(self):
        event, manifest, _ = fixture(True)
        m.validate_manifest(manifest, event, '123', 35.035, True)
        for repeat in (False, True):
            expected = '2' if repeat else '1'
            lines = ['seek', line('armed'), line('capture-complete', repetitions=expected)]
            self.assertIsNotNone(m.completion(lines, '123', 0, 35.035, repeat))
            with self.assertRaisesRegex(RuntimeError, 'repetitions'):
                m.completion(lines, '123', 0, 35.035, not repeat)
        with self.assertRaisesRegex(RuntimeError, 'repetitions'):
            m.completion(['seek', line('armed'), line('capture-complete')], '123', 0, 35.035, True)
        for repeat in (False, True):
            _, wrong, _ = fixture(not repeat)
            with self.assertRaisesRegex(RuntimeError, 'schema'):
                m.validate_manifest(wrong, event, '123', 35.035, repeat)
        for key, value in [('repetitions', 1), ('program_tokens', ['11', '22', '33', '22']),
                           ('draw_order', ['A1', 'B1', 'A2', 'B2']), ('lib_words', 14), ('android_words', 14)]:
            with self.subTest(key=key), self.assertRaises((RuntimeError, m.analyzer.InvalidCapture)):
                m.validate_manifest({**manifest, key: value}, event, '123', 35.035, True)

    def test_repeat_manifest_epoch_missing_changed_or_malformed_refused(self):
        event, manifest, _ = fixture(True)
        for key in ('draw_epoch_before', 'draw_epoch_after'):
            missing = {k: v for k, v in manifest.items() if k != key}
            with self.subTest(key=key, value='missing'), self.assertRaises(m.analyzer.InvalidCapture):
                m.validate_manifest(missing, event, '123', 35.035, True)
            for value in (['0', '0', '0', '1'], ['0']*3, [0]*4, ['-1']*4, [str(1 << 64)]*4):
                with self.subTest(key=key, value=value), self.assertRaises(m.analyzer.InvalidCapture):
                    m.validate_manifest({**manifest, key: value}, event, '123', 35.035, True)
        # Nonzero historical epochs are legal when every recorded draw agrees.
        m.validate_manifest({**manifest, 'draw_epoch_before': ['9']*4, 'draw_epoch_after': ['9']*4},
                            event, '123', 35.035, True)

    def test_repeat_two_chunks_and_final_android_payload_limits(self):
        event, manifest, files = fixture(True)
        adb = MagicMock();adb.read_file.side_effect = lambda path, maximum: files[path]
        with tempfile.TemporaryDirectory() as d:
            analysis = m.collect(adb, event, '123', 35.035, Path(d)/'capture', lambda: None, True)
        self.assertEqual(analysis['schema'], 2)
        self.assertEqual(analysis['status'], 'captured-floats-bit-equal')
        self.assertEqual(analysis['repeat_analysis']['not_captured']['baseline_repeat'], ['half_rgb', 'yuv'])
        pulls = {call.args[0]: call.args[1] for call in adb.read_file.call_args_list}
        self.assertEqual(pulls[m.REMOTE+manifest['files']['lib']], 28*4)
        self.assertEqual(pulls[m.REMOTE+manifest['files']['android']], 7*4)
        # A missing second complete lib block must not be silently schema1.
        lib_path = m.REMOTE+manifest['files']['lib'];files[lib_path] = files[lib_path][:14*4]
        with tempfile.TemporaryDirectory() as d, self.assertRaisesRegex(RuntimeError, 'byte-size'):
            m.collect(adb, event, '123', 35.035, Path(d)/'capture', lambda: None, True)

    def test_repeat_only_difference_is_not_equal_capture(self):
        event, manifest, files = fixture(True)
        path = m.REMOTE + manifest['files']['lib']
        data = bytearray(files[path]);data[4:8] = struct.pack('<f', .1);files[path] = bytes(data)
        adb = MagicMock();adb.read_file.side_effect = lambda path, maximum: files[path]
        with tempfile.TemporaryDirectory() as d:
            analysis = m.collect(adb, event, '123', 35.035, Path(d)/'capture', lambda: None, True)
        self.assertEqual(analysis['status'], 'captured-float-differences')
        self.assertEqual(analysis['comparisons']['pre_rgb']['bit_mismatches'], 0)
        self.assertEqual(analysis['repeat_analysis']['repeatability'], 'captured-stages-bit-unstable')

    def test_sample_tap_requires_repeat_matching_event_and_schema3_metadata(self):
        event, manifest, _ = fixture(True, True)
        self.assertEqual(len(m.validate_manifest(manifest, event, '123', 35.035, True, True)), 6)
        for repeat, tap in ((False, True), (True, False), (False, False)):
            with self.subTest(repeat=repeat, tap=tap), self.assertRaises(RuntimeError):
                m.validate_manifest(manifest, event, '123', 35.035, repeat, tap)
        for enabled in (None, '0', '2'):
            fields = {'repetitions': '2', **({'sample_tap': enabled} if enabled is not None else {})}
            with self.subTest(enabled=enabled), self.assertRaisesRegex(RuntimeError, 'sample-tap'):
                m.completion(['seek', line('armed'), line('capture-complete', **fields)], '123', 0, 35.035, True, True)
        with self.assertRaisesRegex(RuntimeError, 'sample-tap'):
            m.completion(['seek', line('armed'), line('capture-complete', repetitions='2', sample_tap='1')], '123', 0, 35.035, True)
        for key, value in [('sample_tap', False), ('sample_tap_site_count', 2), ('words_per_pixel', 14),
                           ('sample_tap_body_hash', '0'), ('instrumentation_scope', 'unmodified-shader-equivalent')]:
            with self.subTest(key=key), self.assertRaises(m.analyzer.InvalidCapture):
                m.validate_manifest({**manifest, key: value}, event, '123', 35.035, True, True)
        with self.assertRaisesRegex(RuntimeError, 'requires-repeat'):
            m.controls(35.035, False, True)

    def test_sample_tap_six_files_two_26word_chunks_and_original_body_archived(self):
        event, manifest, files = fixture(True, True)
        adb = MagicMock();adb.read_file.side_effect = lambda path, maximum: files[path]
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/'capture'
            analysis = m.collect(adb, event, '123', 35.035, root, lambda: None, True, True)
            self.assertEqual(analysis['schema'], 3)
            self.assertEqual(analysis['status'], 'captured-floats-bit-equal')
            self.assertEqual(len(analysis['files']), 6)
            self.assertEqual(analysis['original_body_relation']['status'], 'not-independently-verified')
            self.assertEqual((root/manifest['files']['original_body']).read_bytes(), files[m.REMOTE+manifest['files']['original_body']])
        pulls = {call.args[0]: call.args[1] for call in adb.read_file.call_args_list}
        # First original body pull is bounded, second is its exact known size.
        self.assertIn((m.REMOTE+manifest['files']['original_body'], 256*1024),
                      [tuple(call.args) for call in adb.read_file.call_args_list])
        self.assertEqual(pulls[m.REMOTE+manifest['files']['lib']], 52*4)
        self.assertEqual(pulls[m.REMOTE+manifest['files']['android']], 7*4)

    def test_sample_tap_missing_original_or_14word_payload_cannot_complete(self):
        event, manifest, files = fixture(True, True)
        for name in (None, '../old-body.glsl', 'mks-yuv-compare-123-98.original-body.glsl'):
            changed = copy.deepcopy(manifest)
            if name is None:del changed['files']['original_body']
            else:changed['files']['original_body'] = name
            with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, 'file-identity'):
                m.validate_manifest(changed, event, '123', 35.035, True, True)
        for fault in ('short', 'blank-body', 'nonutf8-body'):
            changed = dict(files)
            if fault == 'short':changed[m.REMOTE+manifest['files']['lib']] = changed[m.REMOTE+manifest['files']['lib']][:28*4]
            else:changed[m.REMOTE+manifest['files']['original_body']] = b'  \n' if fault == 'blank-body' else b'\xff'
            adb = MagicMock();adb.read_file.side_effect = lambda path, maximum: changed[path]
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as d, self.assertRaises((RuntimeError, m.analyzer.InvalidCapture)):
                m.collect(adb, event, '123', 35.035, Path(d)/'capture', lambda: None, True, True)

    def test_sample_tap_only_difference_never_reports_equal(self):
        event, manifest, files = fixture(True, True)
        path = m.REMOTE + manifest['files']['lib'];data = bytearray(files[path])
        data[14*4:15*4] = struct.pack('<f', .5);files[path] = bytes(data)
        adb = MagicMock();adb.read_file.side_effect = lambda path, maximum: files[path]
        with tempfile.TemporaryDirectory() as d:
            analysis = m.collect(adb, event, '123', 35.035, Path(d)/'capture', lambda: None, True, True)
        self.assertEqual(analysis['status'], 'captured-float-differences')
        self.assertTrue(all(result['bit_mismatches'] == 0 for result in analysis['comparisons'].values()))
        self.assertEqual(analysis['sample_tap_analysis']['repeatability'], 'sample-taps-bit-unstable')

    def test_invariant_b_mode_requires_all_dependencies_exact_event_and_schema4(self):
        event, manifest, _ = fixture(True, True, True)
        self.assertEqual(len(m.validate_manifest(manifest, event, '123', 35.035, True, True, True)), 7)
        for repeat, tap in ((False, False), (True, False), (False, True)):
            with self.subTest(repeat=repeat, tap=tap), self.assertRaisesRegex(RuntimeError, 'requires-repeat-and-sample-tap'):
                m.controls(35.035, repeat, tap, True)
        for enabled in (None, '0', '2'):
            args = {'repetitions': '2', 'sample_tap': '1', **({'invariant_b': enabled} if enabled is not None else {})}
            with self.subTest(enabled=enabled), self.assertRaisesRegex(RuntimeError, 'invariant-b'):
                m.completion(['seek', line('armed'), line('capture-complete', **args)], '123', 0, 35.035, True, True, True)
        with self.assertRaisesRegex(RuntimeError, 'invariant-b'):
            m.completion(['seek', line('armed'), line('capture-complete', repetitions='2', sample_tap='1', invariant_b='1')],
                         '123', 0, 35.035, True, True)
        with self.assertRaisesRegex(RuntimeError, 'schema'):
            m.validate_manifest(manifest, event, '123', 35.035, True, True)
        for key, value in [('invariant_b', False), ('invariant_uv_identifier', 'gl_Position'),
                           ('invariant_uv_identifier', 'uv; injection'), ('draw_order', ['B1', 'A1', 'B2', 'A2'])]:
            with self.subTest(key=key, value=value), self.assertRaises(m.analyzer.InvalidCapture):
                m.validate_manifest({**manifest, key: value}, event, '123', 35.035, True, True, True)

    def test_invariant_b_archives_seven_files_and_checks_actual_vertex_relation(self):
        event, manifest, files = fixture(True, True, True)
        adb = MagicMock();adb.read_file.side_effect = lambda path, maximum: files[path]
        with tempfile.TemporaryDirectory() as d:
            analysis = m.collect(adb, event, '123', 35.035, Path(d)/'capture', lambda: None, True, True, True)
        self.assertEqual(analysis['schema'], 4)
        self.assertEqual(analysis['status'], 'captured-floats-bit-equal')
        self.assertEqual(len(analysis['files']), 7)
        self.assertEqual(analysis['baseline_control_relation']['status'], 'not-independently-verified')
        self.assertEqual(analysis['invariant_vertex_relation']['status'], 'exact-two-invariant-declarations-only')
        self.assertNotEqual(analysis['files']['vertex']['sha256'], analysis['files']['candidate_vertex']['sha256'])
        # A source change beyond the two invariant declarations is invalid even
        # when every numeric payload component is equal.
        name = m.REMOTE+manifest['files']['candidate_vertex']
        files[name] = files[name].replace(b'vec2(0.0)', b'vec2(1.0)')
        with tempfile.TemporaryDirectory() as d, self.assertRaises(m.analyzer.InvalidCapture):
            m.collect(adb, event, '123', 35.035, Path(d)/'capture', lambda: None, True, True, True)

    def test_invariant_b_missing_wrong_or_aliased_vertex_cannot_collect(self):
        event, manifest, _ = fixture(True, True, True)
        for name in (None, '../candidate-vertex.glsl', manifest['files']['vertex'],
                     'mks-yuv-compare-123-98.candidate-vertex.glsl'):
            changed = copy.deepcopy(manifest)
            if name is None:del changed['files']['candidate_vertex']
            else:changed['files']['candidate_vertex'] = name
            with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, 'file-identity'):
                m.validate_manifest(changed, event, '123', 35.035, True, True, True)

    def test_invariant_b_native_rejection_also_overrides_later_or_earlier_complete(self):
        rejected = ('10-30 05:50:00.000 123 123 I flutter : MPVLOG error: '
                    'MKS-YUV-COMPARE-LIB event=invariant-b-rejected reason=unsupported-vertex')
        markers = ['seek', line('armed'), line('capture-complete', repetitions='2', sample_tap='1', invariant_b='1')]
        for lines in ([rejected]+markers, markers+[rejected]):
            with self.assertRaisesRegex(m.NativeCaptureFailure, '^native-lib-invariant-b-rejected$') as failure:
                m.completion(lines, '123', -1, 35.035, True, True, True)
            self.assertEqual(failure.exception.fields['reason'], 'unsupported-vertex')
        for bad in (rejected.replace('MKS-YUV-COMPARE-LIB ', 'MKS-YUV-COMPARE '),
                    rejected.replace('event=invariant-b-rejected', 'event=invariant-b-unknown')):
            with self.assertRaisesRegex(RuntimeError, 'unknown'):
                m.completion([bad], '123', -1, 35.035, True, True, True)

    def test_oracle_single_capture_modes_dependencies_event_and_schema(self):
        for mode in (0, 1):
            event, manifest, files = fixture(True, True, False, mode)
            m.validate_manifest(manifest, event, '123', 35.035, True, True, False, mode)
            for changed in ({'uv_oracle_use_a': not bool(mode)}, {'uv_oracle_barrier_ok': [True, False]},
                            {'uv_oracle_barrier_epoch_after': ['0', '1']}):
                with self.subTest(mode=mode, changed=changed), self.assertRaises((RuntimeError, m.analyzer.InvalidCapture)):
                    m.validate_manifest({**manifest, **changed}, event, '123', 35.035, True, True, False, mode)
            for value in (None, str(1-mode), '2'):
                fields = {'repetitions': '2', 'sample_tap': '1', 'uv_oracle': '1',
                          **({'uv_oracle_use_a': value} if value is not None else {})}
                with self.subTest(value=value), self.assertRaisesRegex(RuntimeError, 'oracle-mode'):
                    m.completion(['seek', line('armed'), line('capture-complete', **fields)], '123', 0, 35.035, True, True, False, mode)
        for repeat, tap, invariant, mode in ((False, True, False, 0), (True, False, False, 1),
                                            (True, True, True, 0), (True, True, False, 2), (True, True, False, True)):
            with self.assertRaises(RuntimeError):m.controls(35.035, repeat, tap, invariant, mode)
        with self.assertRaisesRegex(RuntimeError, 'oracle-mode'):
            m.completion(['seek', line('armed'), line('capture-complete', repetitions='2', sample_tap='1',
                         uv_oracle='1', uv_oracle_use_a='0')], '123', 0, 35.035, True, True)

    def test_oracle_native_rejection_overrides_complete_and_preserves_reason(self):
        rejected = ('10-30 05:50:00.000 123 123 I flutter : MPVLOG error: '
                    'MKS-YUV-COMPARE-LIB event=uv-oracle-rejected reason=unsupported-site')
        markers = ['seek', line('armed'), line('capture-complete', repetitions='2', sample_tap='1', uv_oracle='1', uv_oracle_use_a='1')]
        for lines in ([rejected]+markers, markers+[rejected]):
            with self.assertRaisesRegex(m.NativeCaptureFailure, '^native-lib-uv-oracle-rejected$') as failure:
                m.completion(lines, '123', -1, 35.035, True, True, False, 1)
            self.assertEqual(failure.exception.fields['reason'], 'unsupported-site')
        with self.assertRaisesRegex(RuntimeError, 'unknown'):
            m.completion([rejected.replace('MKS-YUV-COMPARE-LIB ', 'MKS-YUV-COMPARE ')], '123', -1, 35.035)

    def test_schema6_endpoint_is_independent_failure_not_complete(self):
        event, manifest, files = fixture(True, True, False, 1, True, True)
        endpoint = line('capture-diagnostic-invalid', **{k:v for k,v in event.items() if k != 'event'})
        rows = ['seek', line('armed'), endpoint]
        with self.assertRaises(m.DiagnosticCaptureEvent) as failure:
            m.completion(rows, '123', 0, 35.035, True, True, False, 1, True)
        self.assertEqual(failure.exception.event['comparison_pass'], 'refused')
        self.assertIn('.diagnostic-invalid.json', failure.exception.event['file'])
        for changed in (endpoint.replace('.diagnostic-invalid.json','.json'), endpoint.replace('comparison_pass=refused','comparison_pass=unknown'),
                        endpoint.replace('uv_oracle_probe=1','uv_oracle_probe=0'), endpoint.replace('generation=2','generation=3')):
            with self.subTest(changed=changed), self.assertRaises(RuntimeError):
                m.completion(['seek',line('armed'),changed],'123',0,35.035,True,True,False,1,True)
        with self.assertRaisesRegex(RuntimeError,'multiple-capture'):
            m.completion(rows+[line('capture-complete')],'123',0,35.035,True,True,False,1,True)
        with self.assertRaisesRegex(RuntimeError,'before-current-seek'):
            m.completion(rows,'123',2,35.035,True,True,False,1,True)
        with self.assertRaisesRegex(m.NativeCaptureFailure,'native-capture-failed'):
            m.completion(rows+[line('capture-failed')],'123',0,35.035,True,True,False,1,True)
        self.assertIsNone(m.completion(rows,'999',0,35.035,True,True,False,1,True))

    def test_schema6_seven_files_strict_counts_cpu_mask_and_dedicated_prefix(self):
        for diagnostic in (False, True):
            event, manifest, files = fixture(True,True,False,1,True,diagnostic)
            m.validate_manifest(manifest,event,'123',35.035,True,True,False,1,True)
            for key,value in [('uv_oracle_probe_words',19),('uv_oracle_probe_words_per_pixel',9),
                    ('oracle_cpu_validation_mask',128),('oracle_cpu_validation_mask',True),
                    ('oracle_cpu_validation_reasons',['unknown']),('oracle_preconditions_valid',0)]:
                with self.subTest(key=key,diagnostic=diagnostic),self.assertRaises((RuntimeError,m.analyzer.InvalidCapture)):
                    m.validate_manifest({**manifest,key:value},event,'123',35.035,True,True,False,1,True)
            for key in ('oracle_cpu_validation_mask','oracle_cpu_validation_reasons','oracle_preconditions_valid'):
                changed=copy.deepcopy(manifest);del changed[key]
                with self.assertRaises(m.analyzer.InvalidCapture):
                    m.validate_manifest(changed,event,'123',35.035,True,True,False,1,True)
            changed=copy.deepcopy(manifest);changed['files']['oracle_probe']='mks-yuv-compare-123-98.oracle-probe.bin'
            with self.assertRaisesRegex(RuntimeError,'file-identity'):
                m.validate_manifest(changed,event,'123',35.035,True,True,False,1,True)
            if diagnostic:
                changed=copy.deepcopy(manifest)
                changed['files']={k:v.replace('.diagnostic-invalid','') for k,v in changed['files'].items()}
                with self.assertRaisesRegex(RuntimeError,'file-identity'):
                    m.validate_manifest(changed,event,'123',35.035,True,True,False,1,True)

    def test_schema6_complete_and_diagnostic_numeric_equal_remain_distinct(self):
        for diagnostic in (False, True):
            event,manifest,files=fixture(True,True,False,1,True,diagnostic)
            adb=MagicMock();adb.read_file.side_effect=lambda path,maximum:files[path]
            with tempfile.TemporaryDirectory() as d:
                root=Path(d)/'capture'
                analysis=m.collect(adb,event,'123',35.035,root,lambda:None,True,True,False,1,True)
                self.assertEqual(len(analysis['files']),7)
                self.assertEqual(analysis['status'],'diagnostic-invalid' if diagnostic else 'captured-floats-bit-equal')
                self.assertEqual(analysis['causal_conclusion_allowed'],False)
                self.assertTrue((root/'collection.json').is_file())
                if diagnostic:self.assertEqual(analysis['numeric_status'],'captured-floats-bit-equal')

    def test_schema6_cpu_mask_contradiction_retains_all_files_and_parsed_diagnostic(self):
        event,manifest,files=fixture(True,True,False,1,True,True)
        # Header is internally canonical, but falsely claims mask16 instead of
        # the independently recomputed GPU dependency failure mask1.
        manifest.update(oracle_cpu_validation_mask=16,oracle_cpu_validation_reasons=['base-site-mismatch'])
        files[event['file']]=json.dumps(manifest).encode()
        adb=MagicMock();adb.read_file.side_effect=lambda path,maximum:files[path]
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/'capture'
            with self.assertRaises(m.analyzer.InvalidCapture):
                m.collect(adb,event,'123',35.035,root,lambda:None,True,True,False,1,True)
            report=json.loads((root/'analysis.json').read_text())
            self.assertEqual(report['status'],'invalid-capture')
            self.assertEqual(report['diagnostic']['cpu_validation_mask'],1)
            self.assertEqual(len(json.loads((root/'collection.json').read_text())['files']),7)
            for name in manifest['files'].values():self.assertTrue((root/name).is_file())

    def test_schema6_truncated_or_mutated_probe_and_missing_fence_still_fail(self):
        for fault in ('short','changed','fence'):
            event,manifest,files=fixture(True,True,False,1,True,True)
            if fault=='fence':
                manifest['lib_fence_signaled']=False;files[event['file']]=json.dumps(manifest).encode()
            calls={}
            def read(path,maximum):
                calls[path]=calls.get(path,0)+1;data=files[path]
                if path.endswith('.oracle-probe.bin'):
                    if fault=='short':return data[:-4]
                    if fault=='changed' and calls[path]>1:return data[:-4]+b'\x01\0\0\0'
                return data
            adb=MagicMock();adb.read_file.side_effect=read
            with self.subTest(fault=fault),tempfile.TemporaryDirectory() as d,self.assertRaises((RuntimeError,m.analyzer.InvalidCapture)):
                m.collect(adb,event,'123',35.035,Path(d)/'capture',lambda:None,True,True,False,1,True)

    def test_schema6_diagnostic_child_stops_triplet_without_further_rounds(self):
        with tempfile.TemporaryDirectory() as d:
            args=SimpleNamespace(output=str(Path(d)/'triplet'),repeat=True,sample_tap=True,invariant_b=False,oracle_probe=True)
            child={'status':'diagnostic-invalid','reason':'native-capture-diagnostic-invalid','restorationVerified':True}
            with patch.object(m,'run',return_value=child) as run:
                result=m.run_oracle_triplet(args)
            run.assert_called_once()
            self.assertEqual(result['status'],'failed')
            self.assertIn('round-1-incomplete',result['reason'])
            self.assertTrue(result['restorationVerified'])

    def test_schema6_normal_triplet_strictly_validates_sidecar_and_mode(self):
        with tempfile.TemporaryDirectory() as d:
            rounds=[oracle_round(Path(d)/str(i),mode,123+i,99+i,True) for i,mode in enumerate((0,1,0))]
            result=m.validate_oracle_triplet(rounds)
            self.assertEqual(result['status'],'validated-triplet-evidence')
            rounds[1][1]['oracleProbeRequested']=False
            with self.assertRaises(RuntimeError):m.validate_oracle_triplet(rounds)

    def test_schema6_actual_output_nan_hard_rejected_but_observed_uv_nan_retained(self):
        for where in ('actual-android','observed-A-UV'):
            event,manifest,files=fixture(True,True,False,1,True,True)
            key='android' if where=='actual-android' else 'oracle_probe'
            path=m.REMOTE+manifest['files'][key];data=bytearray(files[path])
            if where=='actual-android':data[4:8]=struct.pack('<I',0x7fc00000)
            else:
                # GPU observed zero A counts plus NaN UV => reason 2|4|8.
                data[5*4:6*4]=struct.pack('<I',0x7fc00000);data[7*4:8*4]=struct.pack('<I',14)
                manifest.update(oracle_cpu_validation_mask=33,
                    oracle_cpu_validation_reasons=['gpu-dependency-invalid','observed-a-uv-mismatch'])
                files[event['file']]=json.dumps(manifest).encode()
            files[path]=bytes(data)
            adb=MagicMock();adb.read_file.side_effect=lambda path,maximum:files[path]
            with self.subTest(where=where),tempfile.TemporaryDirectory() as d:
                root=Path(d)/'capture'
                if where=='actual-android':
                    with self.assertRaises((RuntimeError,m.analyzer.InvalidCapture)):
                        m.collect(adb,event,'123',35.035,root,lambda:None,True,True,False,1,True)
                    self.assertTrue((root/'collection.json').is_file())
                else:
                    result=m.collect(adb,event,'123',35.035,root,lambda:None,True,True,False,1,True)
                    self.assertEqual(result['status'],'diagnostic-invalid')
                    self.assertEqual(result['numeric_status'],'captured-floats-bit-equal')
                    self.assertFalse(result['oracle_probe_analysis']['first_invalid_records'][0]['GPU_observed_A']['UV_finite'])

    def test_schema7_single_pair_exact_metadata_lengths_and_old_mode_isolation(self):
        event,manifest,files=fixture(True,True,False,1,True,single_pair=True)
        m.validate_manifest(manifest,event,'123',35.035,True,True,False,1,True,True)
        self.assertEqual(manifest['lib_words'],26);self.assertEqual(manifest['uv_oracle_probe_words'],10)
        for key,value in [('uv_oracle_single_pair',False),('repetitions',2),('programs_reused',True),
                ('program_tokens',['11','22','11','22']),('draw_order',['B1','A1']),
                ('draw_epoch_before',['0']*4),('uv_oracle_barriers',2),('uv_oracle_barrier_ok',[True,True]),
                ('uv_oracle_barrier_epoch_after',['0','0']),('lib_words',52),('uv_oracle_probe_words',20)]:
            with self.subTest(key=key),self.assertRaises((RuntimeError,m.analyzer.InvalidCapture)):
                m.validate_manifest({**manifest,key:value},event,'123',35.035,True,True,False,1,True,True)
        with self.assertRaisesRegex(RuntimeError,'schema'):
            m.validate_manifest(manifest,event,'123',35.035,True,True,False,1,True)
        for repeat,tap,invariant,mode,probe in ((False,True,False,1,True),(True,False,False,1,True),
                (True,True,True,1,True),(True,True,False,None,True),(True,True,False,1,False)):
            with self.assertRaises(RuntimeError):m.controls(35.035,repeat,tap,invariant,mode,uv_probe=probe,single_pair=True)
        with self.assertRaises(m.analyzer.InvalidCapture):
            m.analyzer.repeat_metadata({**manifest,'schema':6})

    def test_schema7_endpoint_requires_explicit_single_one_pair_and_diag_separation(self):
        event,manifest,files=fixture(True,True,False,1,True,single_pair=True)
        endpoint=line(event['event'],**{k:v for k,v in event.items() if k!='event'})
        self.assertIsNotNone(m.completion(['seek',line('armed'),endpoint],'123',0,35.035,True,True,False,1,True,True))
        for changed in (endpoint.replace('uv_oracle_single_pair=1','uv_oracle_single_pair=0'),
                        endpoint.replace('repetitions=1','repetitions=2')):
            with self.assertRaises(RuntimeError):m.completion(['seek',line('armed'),changed],'123',0,35.035,True,True,False,1,True,True)
        with self.assertRaises(RuntimeError):m.completion(['seek',line('armed'),endpoint],'123',0,35.035,True,True,False,1,True)
        diag,_,_=fixture(True,True,False,1,True,True,True)
        with self.assertRaises(m.DiagnosticCaptureEvent):
            m.completion(['seek',line('armed'),line(diag['event'],**{k:v for k,v in diag.items() if k!='event'})],
                         '123',0,35.035,True,True,False,1,True,True)

    def test_schema7_single_chunk_archive_and_no_within_capture_repeat_claim(self):
        for diagnostic in (False,True):
            event,manifest,files=fixture(True,True,False,1,True,diagnostic,True)
            adb=MagicMock();adb.read_file.side_effect=lambda path,maximum:files[path]
            with self.subTest(diagnostic=diagnostic),tempfile.TemporaryDirectory() as d:
                root=Path(d)/'capture'
                result=m.collect(adb,event,'123',35.035,root,lambda:None,True,True,False,1,True,True)
                self.assertEqual(result['schema'],7)
                self.assertEqual(result['status'],'diagnostic-invalid' if diagnostic else 'captured-floats-bit-equal')
                self.assertFalse(result['within_capture_repeatability_measured'])
                self.assertIn('A1 versus B1',result['current_ab'])
                self.assertEqual(len(result['files']),7)
                pulls={call.args[0]:call.args[1] for call in adb.read_file.call_args_list}
                self.assertEqual(pulls[m.REMOTE+manifest['files']['lib']],26*4)
                self.assertEqual(pulls[m.REMOTE+manifest['files']['oracle_probe']],10*4)
                self.assertEqual(pulls[m.REMOTE+manifest['files']['android']],7*4)

    def test_schema7_fresh_process_triplet_same_source_not_program_instance(self):
        with tempfile.TemporaryDirectory() as d:
            rounds=[oracle_round(Path(d)/str(i),mode,123+i,99+i,True,True) for i,mode in enumerate((0,1,0))]
            for index,(directory,summary) in enumerate(rounds):
                path=directory/'capture'/Path(summary['captureEvent']['file']).name
                manifest=m.analyzer.load_json(path);manifest['program_tokens']=[str(11+index),str(22+index)]
                path.write_text(json.dumps(manifest))
            result=m.validate_oracle_triplet(rounds)
            self.assertTrue(result['checks']['sameActualSources'])
            self.assertIn('not mean the same GL program instance',result['programInstanceScope'])
            self.assertIn('not measured',result['withinCaptureRepeatability'])
            changed=rounds[1][0]/'capture'/Path(rounds[1][1]['captureEvent']['file']).name
            manifest=m.analyzer.load_json(changed)
            b_source=changed.parent/manifest['files']['candidate'];b_source.write_bytes(b_source.read_bytes()+b'//differentB\n')
            with self.assertRaisesRegex(RuntimeError,'actual-source-bytes'):
                m.validate_oracle_triplet(rounds)

    def test_schema7_triplet_orchestration_keeps_single_pair_and_stops_on_diag(self):
        for diagnostic in (False,True):
            with self.subTest(diagnostic=diagnostic),tempfile.TemporaryDirectory() as d:
                seen=[]
                def child(args):
                    seen.append(args)
                    self.assertTrue(args.single_pair);self.assertTrue(args.oracle_probe)
                    if diagnostic:return {'status':'diagnostic-invalid','restorationVerified':True,'reason':'native-capture-diagnostic-invalid'}
                    return oracle_round(args.output,args.oracle_mode,123+len(seen),99+len(seen),True,True)[1]
                args=SimpleNamespace(output=str(Path(d)/'triplet'),repeat=True,sample_tap=True,invariant_b=False,
                                     oracle_probe=True,single_pair=True)
                with patch.object(m,'run',side_effect=child):result=m.run_oracle_triplet(args)
                self.assertEqual([r.oracle_mode for r in seen],[0] if diagnostic else [0,1,0])
                self.assertEqual(result['status'],'failed' if diagnostic else 'completed-oracle-triplet')
                self.assertTrue(result['restorationVerified'])

    def test_schema8_dependencies_and_endpoint_original_UV_mode_are_strict(self):
        self.assertEqual(m.controls(35.035)[m.QUAD_PROPERTY],'0')
        self.assertEqual(m.controls(35.035)[m.QUAD_REVERSE_PROPERTY],'0')
        for reverse in (0,1):
            event,manifest,_=fixture(True,True,False,0,True,single_pair=True,quad_reverse=reverse)
            m.validate_manifest(manifest,event,'123',35.035,True,True,False,0,True,True,reverse)
            endpoint=line(event['event'],**{k:v for k,v in event.items() if k!='event'})
            self.assertIsNotNone(m.completion(['seek',line('armed'),endpoint],'123',0,35.035,True,True,False,0,True,True,reverse))
            for bad in (endpoint.replace('quad_order=1','quad_order=0'),
                        endpoint.replace('quad_order_reverse='+str(reverse),'quad_order_reverse='+str(1-reverse))):
                with self.assertRaises(RuntimeError):m.completion(['seek',line('armed'),bad],'123',0,35.035,True,True,False,0,True,True,reverse)
            with self.assertRaisesRegex(RuntimeError,'schema'):
                m.validate_manifest(manifest,event,'123',35.035,True,True,False,0,True,True)
        for repeat,tap,inv,mode,probe,single,reverse in (
            (True,True,False,1,True,True,0),(True,True,False,None,True,True,0),
            (True,True,False,0,False,True,0),(True,True,False,0,True,False,0),
            (True,False,False,0,True,True,0),(False,True,False,0,True,True,0),
            (True,True,True,0,True,True,0),(True,True,False,0,True,True,2)):
            with self.assertRaises(RuntimeError):m.controls(35.035,repeat,tap,inv,mode,uv_probe=probe,single_pair=single,quad_reverse=reverse)

    def test_schema8_nine_immutable_files_actual_vertex_full_record_permutation(self):
        for reverse,diagnostic in ((0,False),(1,False),(1,True)):
            event,manifest,files=fixture(True,True,False,0,True,diagnostic,True,reverse)
            adb=MagicMock();adb.read_file.side_effect=lambda path,maximum:files[path]
            with self.subTest(reverse=reverse,diagnostic=diagnostic),tempfile.TemporaryDirectory() as d:
                result=m.collect(adb,event,'123',35.035,Path(d)/'capture',lambda:None,True,True,False,0,True,True,reverse)
                self.assertEqual(result['schema'],8)
                self.assertEqual(len(result['files']),9)
                self.assertEqual(result['status'],'diagnostic-invalid' if diagnostic else 'captured-float-differences')
                self.assertEqual(adb.read_file.call_count,20)
                for key in ('baseline_vertices','candidate_vertices'):
                    self.assertEqual(result['files'][key]['bytes'],80)
                    self.assertIn((m.REMOTE+manifest['files'][key],80),[tuple(c.args) for c in adb.read_file.call_args_list])

    def test_schema8_layout_payload_identity_and_padding_changes_fail_closed(self):
        for fault in ('missing','cross-id','layout','padding','position','short','changed'):
            event,manifest,files=fixture(True,True,False,0,True,False,True,1)
            if fault in ('missing','cross-id'):
                if fault=='missing':del manifest['files']['candidate_vertices']
                else:manifest['files']['candidate_vertices']='mks-yuv-compare-123-98.candidate-vertices.bin'
            elif fault=='layout':manifest['quad_vertex_layout']['stride']=2048
            else:
                path=m.REMOTE+manifest['files']['candidate_vertices'];data=bytearray(files[path])
                if fault=='padding':data[16]^=1
                if fault=='position':data[0:4]=struct.pack('<f',.5)
                if fault=='short':data=data[:-4]
                files[path]=bytes(data)
            files[event['file']]=json.dumps(manifest).encode();reads={}
            def read(path,maximum):
                reads[path]=reads.get(path,0)+1;data=files[path]
                if fault=='changed' and path.endswith('.candidate-vertices.bin') and reads[path]>1:
                    return data[:-1]+bytes([data[-1]^1])
                return data
            adb=MagicMock();adb.read_file.side_effect=read
            with self.subTest(fault=fault),tempfile.TemporaryDirectory() as d,self.assertRaises((RuntimeError,m.analyzer.InvalidCapture)):
                m.collect(adb,event,'123',35.035,Path(d)/'capture',lambda:None,True,True,False,0,True,True,1)

    def test_schema8_triplet_fresh_processes_strict_A_vertices_raw_sources(self):
        with tempfile.TemporaryDirectory() as d:
            rounds=[oracle_round(Path(d)/str(i),0,123+i,99+i,True,True,reverse) for i,reverse in enumerate((0,1,0))]
            result=m.validate_quad_triplet(rounds)
            self.assertEqual(result['status'],'validated-quad-triplet-evidence')
            self.assertTrue(result['checks']['allCapturedABytesStable'])
            self.assertIn('record',result['quadVertexRequirement'])
            self.assertIn('use_a remains 0',result['oracleUVRequirement'])
            with self.assertRaises(RuntimeError):m.validate_oracle_triplet(rounds)
            manifest_path=rounds[1][0]/'capture'/Path(rounds[1][1]['captureEvent']['file']).name
            manifest=m.analyzer.load_json(manifest_path)
            # Per-round A/B permutation still holds, but an A padding change in
            # only round2 breaks the independent cross-round A vertex anchor.
            a_path=manifest_path.parent/manifest['files']['baseline_vertices'];a=bytearray(a_path.read_bytes());a[16]^=1
            a_path.write_bytes(a);stride=manifest['quad_vertex_layout']['stride']
            (manifest_path.parent/manifest['files']['candidate_vertices']).write_bytes(b''.join(a[i*stride:(i+1)*stride] for i in (3,2,1,0)))
            with self.assertRaisesRegex(RuntimeError,'A-vertex-payload-drift'):
                m.validate_quad_triplet(rounds)

    def test_schema8_triplet_original_reverse_original_and_diag_stop(self):
        for diagnostic in (False,True):
            with self.subTest(diagnostic=diagnostic),tempfile.TemporaryDirectory() as d:
                seen=[]
                def child(args):
                    seen.append(args);self.assertEqual(args.oracle_mode,0)
                    if diagnostic:return {'status':'diagnostic-invalid','restorationVerified':True,'reason':'native-capture-diagnostic-invalid'}
                    return oracle_round(args.output,0,123+len(seen),99+len(seen),True,True,args.quad_reverse)[1]
                args=SimpleNamespace(output=str(Path(d)/'triplet'),repeat=True,sample_tap=True,invariant_b=False,
                                     oracle_probe=True,single_pair=True,oracle_mode=0)
                with patch.object(m,'run',side_effect=child):result=m.run_quad_triplet(args)
                self.assertEqual([r.quad_reverse for r in seen],[0] if diagnostic else [0,1,0])
                self.assertEqual(result['status'],'failed' if diagnostic else 'completed-quad-triplet')
                self.assertTrue(result['restorationVerified'])

    def test_oracle_triplet_actual_source_raw_provenance_and_A_anchor(self):
        with tempfile.TemporaryDirectory() as d:
            rounds = oracle_triplet(d)
            result = m.validate_oracle_triplet(rounds)
            self.assertEqual(result['status'], 'validated-triplet-evidence')
            self.assertTrue(all(result['checks'].values()))
            self.assertEqual(result['captureStatuses'], ['captured-float-differences', 'captured-floats-bit-equal', 'captured-float-differences'])
            # An opaque native hash change is no substitute for source bytes.
            manifest_path = rounds[1][0]/'capture'/Path(rounds[1][1]['captureEvent']['file']).name
            manifest = json.loads(manifest_path.read_text());manifest['shader_body_hash'] = '87654321'
            manifest_path.write_text(json.dumps(manifest))
            m.validate_oracle_triplet(rounds)

    def test_oracle_triplet_refuses_source_original_raw_and_A_anchor_drift(self):
        for fault in ('source', 'original-raw', 'A-pre', 'A2-csc', 'oracle-UV'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as d:
                rounds = oracle_triplet(d)
                index = 2 if fault == 'original-raw' else 1
                directory, result = rounds[index]
                manifest = m.analyzer.load_json(directory/'capture'/Path(result['captureEvent']['file']).name)
                key = 'baseline' if fault == 'source' else 'android' if fault == 'A2-csc' else 'lib'
                path = directory/'capture'/manifest['files'][key]
                if fault == 'source':path.write_bytes(path.read_bytes()+b'// changed actual source\n')
                else:
                    data = bytearray(path.read_bytes());offset = 11 if fault == 'A-pre' else 14 if fault == 'oracle-UV' else 1
                    data[offset*4:(offset+1)*4] = struct.pack('<f', .125);path.write_bytes(data)
                with self.assertRaises((RuntimeError, m.analyzer.InvalidCapture)):
                    m.validate_oracle_triplet(rounds)

    def test_oracle_triplet_rejects_provenance_controls_extent_and_incomplete(self):
        for key in ('apk', 'media', 'display', 'controls', 'mode', 'restore', 'ROI', 'PID'):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as d:
                rounds = oracle_triplet(d);other = rounds[1][1]
                if key == 'apk':other['apk']['sha256'] = 'c'*64
                elif key == 'media':other['sourceReceipt']['hostSha256'] = other['sourceReceipt']['deviceSha256'] = 'c'*64
                elif key == 'display':other['displayControls']['expectedBacklight'] = 255
                elif key == 'controls':other['controls']['debug.mks.yuv_inv'] = '1'
                elif key == 'mode':other['oracleMode'] = 0
                elif key == 'restore':other['restorationVerified'] = False
                elif key == 'PID':other['pid'] = rounds[0][1]['pid']
                elif key == 'ROI':
                    path = rounds[1][0]/'capture'/Path(other['captureEvent']['file']).name
                    manifest = json.loads(path.read_text());manifest['target_width'] = 2
                    path.write_text(json.dumps(manifest))
                with self.assertRaises((RuntimeError, m.analyzer.InvalidCapture)):
                    m.validate_oracle_triplet(rounds)
        with self.assertRaisesRegex(RuntimeError, 'three-complete'):
            m.validate_oracle_triplet([])

    def test_oracle_triplet_orchestration_modes_and_stop_on_failure_or_interrupt(self):
        for scenario in ('complete', 'failed', 'restore', 'interrupt'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as d:
                calls = []
                def child(args):
                    calls.append(args)
                    if scenario == 'interrupt' and len(calls) == 2:raise KeyboardInterrupt()
                    directory, result = oracle_round(args.output, args.oracle_mode, 123+len(calls), 99+len(calls))
                    if len(calls) == 2 and scenario == 'failed':result.update(status='failed', reason='native-capture-failed')
                    if len(calls) == 2 and scenario == 'restore':result['restorationVerified'] = False
                    return result
                args = SimpleNamespace(output=str(Path(d)/'triplet'), repeat=True, sample_tap=True, invariant_b=False)
                with patch.object(m, 'run', side_effect=child):result = m.run_oracle_triplet(args)
                self.assertEqual([r.oracle_mode for r in calls], [0, 1, 0] if scenario == 'complete' else [0, 1])
                self.assertEqual(result['status'], 'completed-oracle-triplet' if scenario == 'complete' else 'failed')
                self.assertEqual(result['restorationVerified'], scenario not in ('restore', 'interrupt'))
                self.assertTrue((Path(args.output)/'summary.json').exists())

    def test_collect_full_payload_glsl_and_analyzer_with_immutable_archive(self):
        event, manifest, files = fixture()
        adb = MagicMock();adb.read_file.side_effect = lambda path, maximum: files[path]
        guard = MagicMock()
        with tempfile.TemporaryDirectory() as d:
            root = Path(d) / 'capture'
            analysis = m.collect(adb, event, '123', 35.035, root, guard)
            self.assertEqual(analysis['status'], 'captured-floats-bit-equal')
            self.assertEqual(len(json.loads((root / 'collection.json').read_text())['files']), 5)
            self.assertEqual(adb.read_file.call_count, 12)
            self.assertGreaterEqual(guard.call_count, 11)

    def test_payload_truncation_or_mutation_or_bad_shader_cannot_complete(self):
        for fault in ('short', 'changed', 'shader', 'manifest'):
            event, manifest, files = fixture()
            counts = {}
            def read(path, maximum):
                counts[path] = counts.get(path, 0) + 1
                data = files[path]
                if fault == 'short' and path.endswith('.lib.bin'):return data[:-4]
                if fault == 'changed' and path.endswith('.android.bin') and counts[path] > 1:return bytes([2]) + data[1:]
                if fault == 'shader' and path.endswith('.candidate.glsl'):return b'garbage'
                if fault == 'manifest' and path.endswith('.json') and counts[path] > 1:return data + b' '
                return data
            adb = MagicMock();adb.read_file.side_effect = read
            with tempfile.TemporaryDirectory() as d, self.subTest(fault=fault), self.assertRaises((RuntimeError, m.analyzer.InvalidCapture)):
                m.collect(adb, event, '123', 35.035, Path(d) / 'capture', lambda: None)

    def test_meaningful_difference_is_preserved_without_claiming_equal(self):
        event, manifest, files = fixture()
        path = m.REMOTE + manifest['files']['lib']
        data = bytearray(files[path]);data[4:8] = struct.pack('<f', .1);files[path] = bytes(data)
        adb = MagicMock();adb.read_file.side_effect = lambda path, maximum: files[path]
        with tempfile.TemporaryDirectory() as d:
            analysis = m.collect(adb, event, '123', 35.035, Path(d) / 'capture', lambda: None)
            self.assertEqual(analysis['status'], 'captured-float-differences')
            self.assertEqual(analysis['comparisons']['pre_rgb']['bit_mismatches'], 1)

    def test_all_mutated_properties_are_in_restore_snapshot(self):
        with tempfile.TemporaryDirectory() as d:
            adb = m.CaptureAdb('s', Path(d))
            with patch.object(adb, 'call', return_value='old'):props = adb.properties()
            self.assertTrue(set(m.controls(35.035)) <= set(props))
            self.assertEqual(m.controls(35.035)[m.REPEAT_PROPERTY], '0')
            self.assertEqual(m.controls(35.035, True)[m.REPEAT_PROPERTY], '1')
            self.assertEqual(m.controls(35.035)[m.TAP_PROPERTY], '0')
            self.assertEqual(m.controls(35.035, True, True)[m.TAP_PROPERTY], '1')
            self.assertEqual(m.controls(35.035)[m.INVARIANT_PROPERTY], '0')
            self.assertEqual(m.controls(35.035, True, True, True)[m.INVARIANT_PROPERTY], '1')
            self.assertEqual(m.controls(35.035)[m.ORACLE_PROPERTY], '0')
            self.assertEqual(m.controls(35.035)[m.ORACLE_MODE_PROPERTY], '0')
            self.assertEqual(m.controls(35.035, True, True, False, 0)[m.ORACLE_PROPERTY], '1')
            self.assertEqual(m.controls(35.035, True, True, False, 1)[m.ORACLE_MODE_PROPERTY], '1')
            self.assertEqual(m.controls(35.035)[m.PROBE_PROPERTY],'0')
            self.assertEqual(m.controls(35.035,True,True,False,1,uv_probe=True)[m.PROBE_PROPERTY],'1')
            self.assertEqual(m.controls(35.035)[m.SINGLE_PROPERTY],'0')
            self.assertEqual(m.controls(35.035,True,True,False,1,uv_probe=True,single_pair=True)[m.SINGLE_PROPERTY],'1')
            with patch.object(adb, 'shell') as shell:self.assertEqual(adb.restore({}, props), [])
            for key in m.controls(35.035):self.assertIn(key, str(shell.call_args_list))

    def test_binary_pull_requires_complete_bytes_and_bounded_size(self):
        with tempfile.TemporaryDirectory() as d:
            adb = m.CaptureAdb('s', Path(d))
            for size, data, code in [('3', b'12', 0), ('3', b'123', 1), ('99999', b'123', 0), ('', b'', 0)]:
                with patch.object(adb, 'shell', return_value=size), patch.object(m.subprocess, 'run',
                        return_value=SimpleNamespace(stdout=data, stderr=b'', returncode=code)), self.assertRaises(RuntimeError):
                    adb.read_file('/path', 10)
            with patch.object(adb, 'shell', return_value='3'), patch.object(m.subprocess, 'run',
                    return_value=SimpleNamespace(stdout=b'123', stderr=b'', returncode=0)) as command:
                self.assertEqual(adb.read_file('/path', 10), b'123')
                self.assertEqual(command.call_args.kwargs['timeout'], 15)

    def setup_run(self, d):
        receipt = Path(d) / 'source.json'
        receipt.write_text(json.dumps({'verified': True, 'serial': 's', 'deviceSource': '/source.mp4',
            'deviceSha256': 'b'*64, 'hostSha256': 'b'*64, 'deviceBytes': 123, 'hostBytes': 123, 'returncode': 0}))
        adb = MagicMock()
        adb.settings.return_value = {'screen_brightness': '120'}
        adb.properties.return_value = {k: 'old' for k in m.controls(35.035)}
        adb.screen_state.return_value = {'on': True}
        adb.snapshot.return_value = {'batteryC': 30, 'vtsC': 35, 'raw': {
            'gpu_thermal_pwrlevel': '0', 'panel_thermal_status': '0', 'hdr_mode': '1', 'backlight': '64'}}
        adb.source_hash.return_value = {'sha256': 'a'*64}
        adb.shell.return_value = '123'
        adb.call.side_effect = lambda args: ('package:/data/app/test/base.apk' if args[:3] == ['shell', 'pm', 'path']
                                          else '0' if args[:2] == ['shell', 'getprop'] and args[2] in
                                            (m.REPEAT_PROPERTY, m.TAP_PROPERTY, m.INVARIANT_PROPERTY, m.ORACLE_PROPERTY, m.ORACLE_MODE_PROPERTY, m.PROBE_PROPERTY, m.SINGLE_PROPERTY,m.QUAD_PROPERTY,m.QUAD_REVERSE_PROPERTY, m.ATLAS_PROPERTY, m.ATLAS_REUSE_PROPERTY, m.thermal.INPUT_FBO_PROPERTY) else '')
        adb.restore.return_value = []
        args = SimpleNamespace(output=str(Path(d)/'round'), serial='s', source_receipt=str(receipt), source='/source.mp4',
            expected_panel_thermal_status='0', expected_apk_sha256='a'*64, brightness=64, expected_backlight=64,
            timeout=30, allow_unprotected_menu=True, pts=35.035, tap=None, tap_delay=0)
        return adb, args

    def test_fresh_pid_surviving_old_or_reused_pid_cannot_pass_and_restores(self):
        for pids in (['111', '111'], ['111', None, '111'], [None, None, None]):
            with tempfile.TemporaryDirectory() as d:
                adb, args = self.setup_run(d);adb.lab_pid.side_effect = pids
                with patch.object(m, 'CaptureAdb', return_value=adb), patch.object(m.thermal, 'LogCapture'):
                    result = m.run(args)
                self.assertNotEqual(result['status'], 'completed-capture')
                self.assertTrue(result['restorationVerified']);adb.restore.assert_called_once()

    def test_launch_error_or_cancel_restores_all_and_stops_lab(self):
        for error in (RuntimeError('launch-error'), KeyboardInterrupt()):
            with tempfile.TemporaryDirectory() as d:
                adb, args = self.setup_run(d);adb.lab_pid.side_effect = ['111', None]
                original_call = adb.call.side_effect
                def call(argv):
                    if argv[:3] == ['shell', 'am', 'start']:raise error
                    return original_call(argv)
                adb.call.side_effect = call
                with patch.object(m, 'CaptureAdb', return_value=adb), patch.object(m.thermal, 'LogCapture'):
                    result = m.run(args)
                self.assertTrue(result['hdrLabStopped']);self.assertTrue(result['restorationVerified'])
                self.assertEqual(result['reason'], 'interrupted' if isinstance(error, KeyboardInterrupt) else 'launch-error')
                self.assertEqual(sum(c.args[0] == ['shell', 'am', 'force-stop', m.thermal.PACKAGE]
                                     for c in adb.call.call_args_list), 2)

    def test_source_or_APK_identity_rejected_before_mutation(self):
        with tempfile.TemporaryDirectory() as d:
            adb, args = self.setup_run(d);adb.source_hash.return_value = {'sha256': 'c'*64}
            with patch.object(m, 'CaptureAdb', return_value=adb):result = m.run(args)
            self.assertEqual(result['reason'], 'installed-APK-hash-mismatch')
            adb.wake_unprotected.assert_not_called();adb.restore.assert_not_called()

    def test_complete_mock_round_and_capture_thermal_failure_restore(self):
        # Exercise the orchestration, not only individual validators: a fresh
        # transaction plus advancing live heartbeat is required around transfer.
        for scenario in ('complete', 'repeat', 'tap', 'invariant', 'original', 'oracle', 'probe', 'single', 'single-diagnostic',
                         'quad-original','quad-reverse','quad-diagnostic',
                         'diagnostic', 'diagnostic-contradiction', 'diagnostic-cancel', 'diagnostic-missing', 'fbo',
                         'thermal', 'logcat', 'resume', 'stale', 'collect-error', 'native-terminal'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as d:
                adb, args = self.setup_run(d)
                is_quad=scenario.startswith('quad-')
                args.single_pair=scenario in ('single','single-diagnostic') or is_quad
                args.repeat = scenario in ('repeat', 'tap', 'invariant', 'original', 'oracle', 'probe') or scenario.startswith('diagnostic') or args.single_pair
                args.sample_tap = scenario in ('tap', 'invariant', 'original', 'oracle', 'probe') or scenario.startswith('diagnostic') or args.single_pair
                args.invariant_b = scenario == 'invariant'
                args.oracle_mode = {'original': 0, 'oracle': 1}.get(scenario)
                args.oracle_probe = scenario=='probe' or scenario.startswith('diagnostic') or args.single_pair
                if args.oracle_probe:args.oracle_mode=1
                if is_quad:args.oracle_mode=0
                args.quad_reverse=(0 if scenario=='quad-original' else 1) if is_quad else None
                args.st_fbo = '1' if scenario == 'fbo' else None
                pids = iter(['111', None]);adb.lab_pid.side_effect = lambda: next(pids, '123')
                state = {'logcatAlive': True}
                if scenario == 'fbo':
                    from test_lg_p84_thermal_round import ThermalRoundTests
                    state.update(ThermalRoundTests().fbo_state())
                capture = MagicMock();capture.state.side_effect = lambda: dict(state)
                root = Path(args.output)
                diagnostic = scenario.startswith('diagnostic') or scenario in ('single-diagnostic','quad-diagnostic')
                event, manifest, files = fixture(args.repeat, args.sample_tap, args.invariant_b, args.oracle_mode, args.oracle_probe, diagnostic,args.single_pair,args.quad_reverse)
                if scenario=='diagnostic-contradiction':
                    manifest.update(oracle_cpu_validation_mask=16,oracle_cpu_validation_reasons=['base-site-mismatch'])
                    files[event['file']]=json.dumps(manifest).encode()
                def read_file(path,maximum):
                    if path.endswith('.oracle-probe.bin'):
                        if scenario=='diagnostic-cancel':raise KeyboardInterrupt()
                        if scenario=='diagnostic-missing':raise RuntimeError('missing-probe-file')
                    return files[path]
                adb.read_file.side_effect = read_file
                # Reuse a fully formed real host heartbeat contract fixture.
                from test_lg_p84_quality_round import QualityTests, quality as quality_line
                row = QualityTests().persistent();row['owner']['sourcePath'] = args.source
                row['properties']['path'] = args.source
                sequence = 0
                original_call = adb.call.side_effect
                def call(argv):
                    nonlocal sequence
                    if argv == ['shell', 'getprop', m.REPEAT_PROPERTY]:return '1' if args.repeat else '0'
                    if argv == ['shell', 'getprop', m.TAP_PROPERTY]:return '1' if args.sample_tap else '0'
                    if argv == ['shell', 'getprop', m.INVARIANT_PROPERTY]:return '1' if args.invariant_b else '0'
                    if argv == ['shell', 'getprop', m.ORACLE_PROPERTY]:return '1' if args.oracle_mode is not None else '0'
                    if argv == ['shell', 'getprop', m.ORACLE_MODE_PROPERTY]:return str(args.oracle_mode) if args.oracle_mode is not None else '0'
                    if argv == ['shell','getprop',m.PROBE_PROPERTY]:return '1' if args.oracle_probe else '0'
                    if argv == ['shell','getprop',m.SINGLE_PROPERTY]:return '1' if args.single_pair else '0'
                    if argv == ['shell','getprop',m.QUAD_PROPERTY]:return '1' if is_quad else '0'
                    if argv == ['shell','getprop',m.QUAD_REVERSE_PROPERTY]:return str(args.quad_reverse) if is_quad else '0'
                    if argv == ['shell', 'getprop', m.thermal.INPUT_FBO_PROPERTY]:return args.st_fbo or '0'
                    if argv[:3] == ['shell', 'am', 'start']:
                        (root/'flutter-logcat.txt').write_text('\n'.join([
                            quality_line('seek-started'), line('armed'),
                            line(event['event'],**{k:v for k,v in event.items() if k!='event'})] +
                            ([quality_line('invalidated')] if diagnostic else [quality_line('ready-for-observation'),quality_line('observation-heartbeat')]) +
                            ([line('arm-input'), line('capture-failed', terminal='1', fatal_context='1',
                                                      requires_force_stop='1')] if scenario == 'native-terminal' else [])))
                    if argv[:2] == ['exec-out', 'cat']:
                        sequence += scenario != 'stale'
                        return json.dumps({**row, 'heartbeat': sequence or 1}) + '\n'
                    return original_call(argv)
                adb.call.side_effect = call
                original_collect = m.collect
                def collect(*values):
                    if scenario == 'thermal':adb.snapshot.return_value['raw']['gpu_thermal_pwrlevel'] = '4'
                    if scenario == 'logcat':state['logcatAlive'] = False
                    if scenario == 'resume':row['properties']['pause'] = 'no'
                    if scenario == 'collect-error':raise RuntimeError('forced-payload-failure')
                    return original_collect(*values)
                # stale case is bounded without a real 5-second sleep.
                original_fresh = m.quality.fresh_heartbeat
                def fresh(load, previous, timeout=5):
                    return original_fresh(load, previous, timeout=.01 if scenario == 'stale' else timeout)
                with patch.object(m, 'CaptureAdb', return_value=adb), patch.object(m.thermal, 'LogCapture', return_value=capture), \
                        patch.object(m, 'collect', side_effect=collect), patch.object(m.quality, 'fresh_heartbeat', side_effect=fresh), \
                        patch.object(m.quality.time, 'sleep'):
                    result = m.run(args)
                self.assertTrue(result['hdrLabStopped']);self.assertTrue(result['restorationVerified'])
                adb.restore.assert_called_once();capture.close.assert_called_once()
                if scenario in ('complete', 'repeat', 'tap', 'invariant', 'original', 'oracle','probe','single','quad-original','quad-reverse'):
                    self.assertEqual(result['status'], 'completed-capture', result)
                    self.assertGreater(result['qualityAfter']['heartbeat'], result['postCollectionHeartbeatWatermark'] + 1)
                    self.assertEqual(result['repeatRequested'], args.repeat)
                    self.assertEqual(result['analysis']['schema'],8 if is_quad else 7 if args.single_pair else 6 if args.oracle_probe else 5 if args.oracle_mode is not None else 4 if args.invariant_b else 3 if args.sample_tap else 2 if args.repeat else 1)
                    self.assertEqual(result['controls'][m.REPEAT_PROPERTY], '1' if args.repeat else '0')
                    self.assertEqual(result['controls'][m.TAP_PROPERTY], '1' if args.sample_tap else '0')
                    self.assertEqual(result['controls'][m.INVARIANT_PROPERTY], '1' if args.invariant_b else '0')
                elif diagnostic:
                    self.assertEqual(result['status'],'diagnostic-invalid' if scenario in ('diagnostic','single-diagnostic','quad-diagnostic') else 'failed')
                    self.assertEqual(sequence,0)  # No historical ready/heartbeat can convert failure into success.
                    if scenario in ('diagnostic-cancel','diagnostic-missing'):
                        self.assertFalse(result['diagnosticFilesCollected'])
                        self.assertTrue((Path(result['diagnosticDirectory'])/Path(event['file']).name).is_file())
                    else:
                        self.assertTrue(result['diagnosticFilesCollected'])
                        self.assertEqual(len(json.loads((Path(result['diagnosticDirectory'])/'collection.json').read_text())['files']),9 if is_quad else 7)
                    if scenario in ('diagnostic','single-diagnostic','quad-diagnostic'):
                        self.assertEqual(result['analysis']['numeric_status'],'captured-float-differences' if is_quad else 'captured-floats-bit-equal')
                        self.assertFalse(result['causal_conclusion_allowed'])
                    elif scenario=='diagnostic-contradiction':self.assertEqual(result['analyzerDiagnostic']['cpu_validation_mask'],1)
                else:
                    self.assertEqual(result['status'], 'failed', result)
                    self.assertRegex(result['reason'], scenario if scenario in ('thermal', 'logcat') else {
                        'resume': 'current-property', 'stale': 'stale|deadline', 'collect-error': 'payload',
                        'native-terminal': '^native-capture-failed$', 'fbo':'target-frame-proof-unavailable'}[scenario])
                    if scenario == 'fbo':
                        self.assertIn('analysis', result)
                        self.assertIn('inputFbo', result)
                    if scenario == 'native-terminal':
                        self.assertEqual(result['nativeFailure']['requires_force_stop'], '1')
                        adb.read_file.assert_not_called()
                        self.assertEqual(sequence, 0)
                        self.assertTrue(result['nativeDiagnostics'])

    def test_repeat_control_unknown_or_wrong_readback_restores_and_does_not_launch(self):
        for value in ('', '2', '0'):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as d:
                adb, args = self.setup_run(d);args.repeat = True
                original = adb.call.side_effect
                adb.call.side_effect = lambda argv: value if argv == ['shell', 'getprop', m.REPEAT_PROPERTY] else original(argv)
                with patch.object(m, 'CaptureAdb', return_value=adb):result = m.run(args)
                self.assertEqual(result['reason'], 'repeat-control-readback-mismatch')
                self.assertTrue(result['restorationVerified'])
                adb.restore.assert_called_once()
                self.assertFalse(any(c.args[0][:3] == ['shell', 'am', 'start'] for c in adb.call.call_args_list))

    def test_sample_tap_control_bad_readback_restores_and_never_launches(self):
        for value in ('', '2', '0'):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as d:
                adb, args = self.setup_run(d);args.repeat = args.sample_tap = True
                original = adb.call.side_effect
                def call(argv):
                    if argv == ['shell', 'getprop', m.REPEAT_PROPERTY]:return '1'
                    if argv == ['shell', 'getprop', m.TAP_PROPERTY]:return value
                    return original(argv)
                adb.call.side_effect = call
                with patch.object(m, 'CaptureAdb', return_value=adb):result = m.run(args)
                self.assertEqual(result['reason'], 'sample-tap-control-readback-mismatch')
                self.assertTrue(result['restorationVerified']);adb.restore.assert_called_once()
                self.assertFalse(any(c.args[0][:3] == ['shell', 'am', 'start'] for c in adb.call.call_args_list))

    def test_invariant_control_bad_readback_restores_and_never_launches(self):
        for value in ('', '2', '0'):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as d:
                adb, args = self.setup_run(d);args.repeat = args.sample_tap = args.invariant_b = True
                original = adb.call.side_effect
                def call(argv):
                    if argv == ['shell', 'getprop', m.REPEAT_PROPERTY] or argv == ['shell', 'getprop', m.TAP_PROPERTY]:return '1'
                    if argv == ['shell', 'getprop', m.INVARIANT_PROPERTY]:return value
                    return original(argv)
                adb.call.side_effect = call
                with patch.object(m, 'CaptureAdb', return_value=adb):result = m.run(args)
                self.assertEqual(result['reason'], 'invariant-b-control-readback-mismatch')
                self.assertTrue(result['restorationVerified']);adb.restore.assert_called_once()
                self.assertFalse(any(c.args[0][:3] == ['shell', 'am', 'start'] for c in adb.call.call_args_list))

    def test_oracle_control_bad_readback_restores_and_never_launches(self):
        for key in (m.ORACLE_PROPERTY, m.ORACLE_MODE_PROPERTY):
            for value in ('', '2', '0'):
                with self.subTest(key=key, value=value), tempfile.TemporaryDirectory() as d:
                    adb, args = self.setup_run(d);args.repeat = args.sample_tap = True;args.oracle_mode = 1
                    original = adb.call.side_effect
                    def call(argv):
                        if argv == ['shell', 'getprop', key]:return value
                        if argv[:2] == ['shell', 'getprop'] and argv[2] in (
                                m.REPEAT_PROPERTY, m.TAP_PROPERTY, m.ORACLE_PROPERTY, m.ORACLE_MODE_PROPERTY):return '1'
                        return original(argv)
                    adb.call.side_effect = call
                    with patch.object(m, 'CaptureAdb', return_value=adb):result = m.run(args)
                    self.assertIn('control-readback-mismatch', result['reason'])
                    self.assertTrue(result['restorationVerified']);adb.restore.assert_called_once()
                    self.assertFalse(any(c.args[0][:3] == ['shell', 'am', 'start'] for c in adb.call.call_args_list))

    def test_fbo_capture_control_readback_failure_restores_without_launch(self):
        with tempfile.TemporaryDirectory() as d:
            adb,args=self.setup_run(d);args.st_fbo='1'
            original=adb.call.side_effect
            adb.call.side_effect=lambda argv: '' if argv==['shell','getprop',m.thermal.INPUT_FBO_PROPERTY] else original(argv)
            with patch.object(m,'CaptureAdb',return_value=adb):result=m.run(args)
            self.assertEqual(result['reason'],'input-fbo-control-readback-mismatch')
            self.assertTrue(result['restorationVerified']);adb.restore.assert_called_once()
            self.assertFalse(any(c.args[0][:3]==['shell','am','start'] for c in adb.call.call_args_list))

    def test_probe_control_bad_readback_restores_without_launch(self):
        for value in ('','0','2'):
            with self.subTest(value=value),tempfile.TemporaryDirectory() as d:
                adb,args=self.setup_run(d);args.repeat=args.sample_tap=args.oracle_probe=True;args.oracle_mode=1
                original=adb.call.side_effect
                def call(argv):
                    if argv==['shell','getprop',m.PROBE_PROPERTY]:return value
                    if argv[:2]==['shell','getprop'] and argv[2] in (m.REPEAT_PROPERTY,m.TAP_PROPERTY,m.ORACLE_PROPERTY,m.ORACLE_MODE_PROPERTY):return '1'
                    return original(argv)
                adb.call.side_effect=call
                with patch.object(m,'CaptureAdb',return_value=adb):result=m.run(args)
                self.assertEqual(result['reason'],'oracle-probe-control-readback-mismatch')
                self.assertTrue(result['restorationVerified']);adb.restore.assert_called_once()
                self.assertFalse(any(c.args[0][:3]==['shell','am','start'] for c in adb.call.call_args_list))

    def test_single_control_bad_readback_restores_without_launch(self):
        for value in ('','0','2'):
            with self.subTest(value=value),tempfile.TemporaryDirectory() as d:
                adb,args=self.setup_run(d);args.repeat=args.sample_tap=args.oracle_probe=args.single_pair=True;args.oracle_mode=1
                original=adb.call.side_effect
                def call(argv):
                    if argv==['shell','getprop',m.SINGLE_PROPERTY]:return value
                    if argv[:2]==['shell','getprop'] and argv[2] in (m.REPEAT_PROPERTY,m.TAP_PROPERTY,m.ORACLE_PROPERTY,m.ORACLE_MODE_PROPERTY,m.PROBE_PROPERTY):return '1'
                    return original(argv)
                adb.call.side_effect=call
                with patch.object(m,'CaptureAdb',return_value=adb):result=m.run(args)
                self.assertEqual(result['reason'],'single-pair-control-readback-mismatch')
                self.assertTrue(result['restorationVerified']);adb.restore.assert_called_once()
                self.assertFalse(any(c.args[0][:3]==['shell','am','start'] for c in adb.call.call_args_list))

    def test_quad_control_bad_readback_restores_without_launch(self):
        for key in (m.QUAD_PROPERTY,m.QUAD_REVERSE_PROPERTY):
            for value in ('','0','2'):
                with self.subTest(key=key,value=value),tempfile.TemporaryDirectory() as d:
                    adb,args=self.setup_run(d);args.repeat=args.sample_tap=args.oracle_probe=args.single_pair=True
                    args.oracle_mode=0;args.quad_reverse=1;original=adb.call.side_effect
                    def call(argv):
                        if argv==['shell','getprop',key]:return value
                        if argv[:2]==['shell','getprop'] and argv[2] in (m.REPEAT_PROPERTY,m.TAP_PROPERTY,m.ORACLE_PROPERTY,
                                m.PROBE_PROPERTY,m.SINGLE_PROPERTY,m.QUAD_PROPERTY,m.QUAD_REVERSE_PROPERTY):return '1'
                        return original(argv)
                    adb.call.side_effect=call
                    with patch.object(m,'CaptureAdb',return_value=adb):result=m.run(args)
                    self.assertIn(result['reason'],('quad-order-control-readback-mismatch','quad-reverse-control-readback-mismatch'))
                    self.assertTrue(result['restorationVerified']);adb.restore.assert_called_once()
                    self.assertFalse(any(c.args[0][:3]==['shell','am','start'] for c in adb.call.call_args_list))

    def test_atlas_is_disabled_snapshotted_and_bad_readback_stops_legacy_round(self):
        self.assertEqual(m.controls(35.035)[m.ATLAS_PROPERTY], '0')
        for value in ('', '1', '2'):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                adb, args = self.setup_run(directory)
                self.assertIn(m.ATLAS_PROPERTY, adb.properties.return_value)
                original = adb.call.side_effect
                adb.call.side_effect = lambda argv: value if argv == ['shell','getprop',m.ATLAS_PROPERTY] else original(argv)
                with patch.object(m, 'CaptureAdb', return_value=adb):
                    result = m.run(args)
                self.assertEqual(result['reason'], 'atlas-disabled-control-readback-mismatch')
                self.assertTrue(result['restorationVerified']);adb.restore.assert_called_once()
                self.assertEqual(adb.restore.call_args.args[1][m.ATLAS_PROPERTY], 'old')
                self.assertFalse(any(call.args[0][:3] == ['shell','am','start'] for call in adb.call.call_args_list))

    def test_quad_cli_dependencies_and_nonzero_numeric_difference_exit(self):
        base=['capture','--serial','s','--output','/unused','--pts','35.035','--source-receipt','/unused',
              '--expected-apk-sha256','a'*64,'--expected-panel-thermal-status','0']
        flags=['--repeat','--sample-tap','--oracle-probe','--single-pair']
        for extra in (['--quad-triplet'],flags+['--oracle-mode','oracle','--quad-triplet'],
                      flags+['--oracle-mode','original','--quad-mode','original','--quad-triplet'],
                      flags+['--oracle-mode','original','--quad-triplet','--oracle-triplet']):
            with self.subTest(extra=extra),patch.object(sys,'argv',base+extra),patch.object(m,'CaptureAdb') as adb, \
                    patch('sys.stderr'),self.assertRaises(SystemExit) as error:
                m.main()
            self.assertEqual(error.exception.code,2);adb.assert_not_called()
        result={'status':'completed-quad-triplet','restorationVerified':True,
                'verification':{'captureStatuses':['captured-float-differences']*3}}
        with patch.object(sys,'argv',base+flags+['--oracle-mode','original','--quad-triplet']), \
                patch.object(m,'run_quad_triplet',return_value=result) as run,patch.object(m.signal,'signal'),patch('builtins.print'):
            self.assertEqual(m.main(),2)
        self.assertEqual(run.call_args.args[0].oracle_mode,0)
        one={'status':'completed-capture','restorationVerified':True,'analysis':{'status':'captured-float-differences'}}
        with patch.object(sys,'argv',base+flags+['--oracle-mode','original','--quad-mode','reverse']), \
                patch.object(m,'run',return_value=one) as run,patch.object(m.signal,'signal'),patch('builtins.print'):
            self.assertEqual(m.main(),2)
        self.assertEqual(run.call_args.args[0].oracle_mode,0)
        self.assertEqual(run.call_args.args[0].quad_reverse,1)

    def test_single_cli_requires_probe_and_retains_nonzero_diagnostic_exit(self):
        base=['capture','--serial','s','--output','/unused','--pts','35.035','--source-receipt','/unused',
              '--expected-apk-sha256','a'*64,'--expected-panel-thermal-status','0','--repeat','--sample-tap',
              '--oracle-mode','oracle','--single-pair']
        with patch.object(sys,'argv',base),patch.object(m,'CaptureAdb') as adb,patch('sys.stderr'),self.assertRaises(SystemExit) as error:
            m.main()
        self.assertEqual(error.exception.code,2);adb.assert_not_called()
        result={'status':'diagnostic-invalid','restorationVerified':True,'analysis':{
            'status':'diagnostic-invalid','numeric_status':'captured-floats-bit-equal','causal_conclusion_allowed':False}}
        with patch.object(sys,'argv',base+['--oracle-probe']),patch.object(m,'run',return_value=result) as run, \
                patch.object(m.signal,'signal'),patch('builtins.print'):
            self.assertNotEqual(m.main(),0)
        self.assertTrue(run.call_args.args[0].single_pair)

    def test_probe_cli_requires_oracle_and_diagnostic_numeric_equal_still_nonzero(self):
        base=['capture','--serial','s','--output','/unused','--pts','35.035','--source-receipt','/unused',
              '--expected-apk-sha256','a'*64,'--expected-panel-thermal-status','0','--repeat','--sample-tap','--oracle-probe']
        with patch.object(sys,'argv',base),patch.object(m,'CaptureAdb') as adb,patch('sys.stderr'),self.assertRaises(SystemExit) as error:
            m.main()
        self.assertEqual(error.exception.code,2);adb.assert_not_called()
        result={'status':'diagnostic-invalid','restorationVerified':True,'analysis':{
            'status':'diagnostic-invalid','numeric_status':'captured-floats-bit-equal','causal_conclusion_allowed':False}}
        with patch.object(sys,'argv',base+['--oracle-mode','oracle']),patch.object(m,'run',return_value=result) as run, \
                patch.object(m.signal,'signal'),patch('builtins.print'):
            self.assertNotEqual(m.main(),0)
        self.assertTrue(run.call_args.args[0].oracle_probe)

    def test_cli_sample_tap_requires_repeat_before_any_device_access(self):
        argv = ['capture', '--serial', 's', '--output', '/unused', '--pts', '35.035',
                '--source-receipt', '/unused', '--expected-apk-sha256', 'a'*64,
                '--expected-panel-thermal-status', '0', '--sample-tap']
        with patch.object(sys, 'argv', argv), patch.object(m, 'CaptureAdb') as adb, patch('sys.stderr'), self.assertRaises(SystemExit) as error:
            m.main()
        self.assertEqual(error.exception.code, 2);adb.assert_not_called()

    def test_cli_invariant_requires_both_dependencies_before_device_access(self):
        base = ['capture', '--serial', 's', '--output', '/unused', '--pts', '35.035',
                '--source-receipt', '/unused', '--expected-apk-sha256', 'a'*64,
                '--expected-panel-thermal-status', '0', '--invariant-b']
        for extra in ([], ['--repeat']):
            with self.subTest(extra=extra), patch.object(sys, 'argv', base+extra), patch.object(m, 'CaptureAdb') as adb, \
                    patch('sys.stderr'), self.assertRaises(SystemExit) as error:
                m.main()
            self.assertEqual(error.exception.code, 2);adb.assert_not_called()

    def test_cli_oracle_dependencies_and_triplet_numeric_differences_remain_nonzero(self):
        base = ['capture', '--serial', 's', '--output', '/unused', '--pts', '35.035',
                '--source-receipt', '/unused', '--expected-apk-sha256', 'a'*64,
                '--expected-panel-thermal-status', '0']
        for extra in (['--oracle-triplet'], ['--oracle-mode', 'oracle'],
                      ['--oracle-triplet', '--repeat', '--sample-tap', '--invariant-b'],
                      ['--oracle-triplet', '--repeat', '--sample-tap', '--oracle-mode', 'original']):
            with self.subTest(extra=extra), patch.object(sys, 'argv', base+extra), patch.object(m, 'CaptureAdb') as adb, \
                    patch('sys.stderr'), self.assertRaises(SystemExit) as error:
                m.main()
            self.assertEqual(error.exception.code, 2);adb.assert_not_called()
        for status in ('captured-float-differences', 'captured-floats-bit-equal'):
            result = {'status': 'completed-oracle-triplet', 'restorationVerified': True,
                      'verification': {'captureStatuses': [status]*3}}
            with patch.object(sys, 'argv', base+['--repeat', '--sample-tap', '--oracle-triplet']), \
                    patch.object(m, 'run_oracle_triplet', return_value=result) as triplet, \
                    patch.object(m.signal, 'signal'), patch('builtins.print'):
                code = m.main()
            self.assertEqual(code, 0 if status == 'captured-floats-bit-equal' else 2)
            triplet.assert_called_once()


if __name__ == '__main__':unittest.main()
