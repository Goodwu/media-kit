#!/usr/bin/env python3
"""Validate one diagnostic GPU capture; never proves raw YUV or panel equality."""
from __future__ import annotations
import argparse
import difflib
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys

MAX_PIXELS = 1024 * 1024
MAX_ATLAS_PIXELS = 4 * 1024 * 1024
FILES = ('lib', 'android', 'candidate', 'baseline', 'vertex')
SAMPLE_TAP_FILES = FILES + ('original_body',)
INVARIANT_FILES = SAMPLE_TAP_FILES + ('candidate_vertex',)
ORACLE_PROBE_FILES = SAMPLE_TAP_FILES + ('oracle_probe',)
QUAD_ORDER_FILES = ORACLE_PROBE_FILES + ('baseline_vertices','candidate_vertices')
ATLAS_FILES = ('a0_before','atlas_a','a0_after','atlas','a0_fragment','atlas_fragment',
               'vertex','original_body','baseline_vertices','android')
ATLAS_SUFFIXES = dict(zip(ATLAS_FILES, ('.a0-before.f32','.atlas-a.f32','.a0-after.f32','.atlas.bin',
    '.a0.frag.glsl','.atlas.frag.glsl','.vertex.glsl','.original-body.glsl','.baseline-vertices.bin','.android.bin')))
ATLAS_REPRESENTATION = 'RGBA/FLOAT decoded RGB16F numerical values; not physical storage bytes'
ATLAS_INSTRUMENTATION = 'A0 before and after have no capture SSBO/tap; atlas A is instrumented; final CSC is instrumented only in Android ROI'
ATLAS_SCOPE = 'rgb-anchor-capture-only-not-quality-pass'
ATLAS_REASONS = {1:'a0-replay-mismatch',2:'atlas-rgb-mismatch'}
ATLAS_READ_FILES = ('a0','uv','half','seed_atlas','android','a0_fragment','b0_fragment',
                    'probe_fragment','vertex','original_body','baseline_vertices','seed_material','current_material')
ATLAS_READ_SUFFIXES = dict(zip(ATLAS_READ_FILES,('.a0.f32','.uv-probe.bin','.half-probe.bin','.seed-atlas.bin',
    '.android.bin','.a0.frag.glsl','.b0.frag.glsl','.probe.frag.glsl','.vertex.glsl','.original-body.glsl',
    '.baseline-vertices.bin','.seed-material.json','.current-material.json')))
ATLAS_READ_SCOPE = 'uv-half-atlas-read-capture-only-not-production-or-yuv-pass'
ATLAS_READ_SOURCE_SCOPE = 'B0 is created but not drawn; probe source strip is not uninstrumented B0 numerical proof; YUV equality is unmeasured'
ATLAS_CACHE_POLICY = 'diagnostic-only immutable atlas; no rebuild or production cache'
ATLAS_SIGNATURE_SCOPE = 'archive relation only; not a replay of the native cache key'
DRAW_ORDER = ['B1','A1','B2','A2']
INVARIANT_DRAW_ORDER = ['B1','A01','B2','A02']
ORACLE_DRAW_ORDER = ['A1','B1','A2','B2']
SINGLE_PAIR_DRAW_ORDER = ['A1','B1']
INPUT_ASSERTION_SCOPE = 'same frozen renderer input state and resource handles; no texture pixel hash'
SAMPLE_TAP_SCOPE = 'actual single textureLod site UV and sampled RGB; instrumentation may change shader compilation; not an unmodified shader'
INVARIANT_SCOPE = 'B-only vertex invariant experiment. A0 is the sample-tap baseline. Instrumentation and invariant declarations may change compilation; no production or unmodified-shader equivalence is established.'
ORACLE_SCOPE = 'Diagnostic UV oracle only. Captured UV bit equality checks values, not an independent GPU memory-barrier audit. Instrumentation and ordering may affect compilation or execution; no production, raw YUV or panel equivalence is established.'
PROBE_SCOPE = 'GPU-observed A fields were recorded by B at its dependency check; CPU-terminal A fields are separate later readback facts. A consistent outside-ROI record means no A read occurred; contradictory flags are ambiguous. Diagnostic-invalid data cannot support a causal, quality or production conclusion.'
CPU_VALIDATION_REASONS = {1:'gpu-dependency-invalid',2:'reason-mismatch',4:'dependency-flag-mismatch',
                          8:'selected-source-mismatch',16:'base-site-mismatch',
                          32:'observed-a-uv-mismatch',64:'selected-a-uv-mismatch'}
SINGLE_PAIR_SCOPE = 'Single-pair diagnostic: A1 and B1 each execute once, so within-capture repeatability is not measured. Independent processes may compare archived B source bytes; they do not share or prove reuse of one physical program instance.'
QUAD_ORDER_SCOPE = 'Captured CPU vertex payload and source relation only. Full record permutation preserves padding and attribute bytes. Native bindings and GPU execution are producer assertions; this is not production, panel or physical-program equivalence proof.'
LIMITS = [
    'Captured shader floats only; not raw NV12, driver quantization, scanout or panel evidence.',
    'Shader hashes identify archived sources; they do not prove equivalence to uninstrumented baseline.',
    'Completion/fence/error evidence is asserted by the native producer manifest, not independently queried offline.',
    'Pixels in one capture are correlated; this is not a performance or statistical confidence test.',
]

class InvalidCapture(ValueError):
    def __init__(self, message, diagnostic=None):
        super().__init__(message)
        self.diagnostic = diagnostic

def require(ok, message):
    if not ok:
        raise InvalidCapture(message)

def integer(value, name, minimum=0, maximum=(1 << 64)-1):
    require(type(value) is int and minimum <= value <= maximum, 'invalid ' + name)
    return value

def finite(value, name):
    require(type(value) in (int, float), 'invalid ' + name)
    try:
        converted = float(value)
    except OverflowError as error:
        raise InvalidCapture('invalid ' + name) from error
    require(math.isfinite(converted), 'invalid ' + name)
    return converted

def decimal_token(value, name, minimum=1):
    require(isinstance(value,str) and value.isascii() and value.isdecimal() and
            len(value) <= 20, 'invalid '+name)
    require(minimum <= int(value) < 1 << 64, 'invalid '+name+' range')
    return int(value)

def repeat_metadata(m):
    if m.get('schema') in (7,8):
        return single_pair_metadata(m)
    draw_order = ORACLE_DRAW_ORDER if m.get('schema') in (5,6) else INVARIANT_DRAW_ORDER if m.get('schema') == 4 else DRAW_ORDER
    require(type(m.get('repetitions')) is int and m['repetitions'] == 2, 'invalid repetitions')
    require(m.get('draw_order') == draw_order, 'invalid draw order')
    require(isinstance(m.get('draw_ok'),dict) and set(m['draw_ok']) == set(draw_order) and
            all(m['draw_ok'][name] is True for name in draw_order), 'incomplete repeated draw')
    integer(m.get('frame_id'), 'frame_id', 1)
    integer(m.get('frame_token'), 'frame_token', 1)
    require(m.get('same_input_snapshot') is True, 'missing same input assertion')
    require(m.get('assertion_scope') == INPUT_ASSERTION_SCOPE, 'invalid input assertion scope')
    require(m.get('programs_reused') is True, 'program reuse not confirmed')
    tokens = m.get('program_tokens')
    require(isinstance(tokens,list) and len(tokens) == 4, 'invalid program tokens')
    values = [decimal_token(v,'program token') for v in tokens]
    require(values[0] == values[2] and values[1] == values[3], 'repeat program tokens differ')
    epochs = []
    for key in ('draw_epoch_before','draw_epoch_after'):
        require(isinstance(m.get(key),list) and len(m[key]) == 4, 'invalid '+key)
        epochs += [decimal_token(value,key,minimum=0) for value in m[key]]
    require(len(set(epochs)) == 1, 'draw error epochs changed or are discontinuous')
    return {key:m[key] for key in ('repetitions','draw_order','draw_ok','frame_id','frame_token',
            'same_input_snapshot','assertion_scope','programs_reused','program_tokens',
            'draw_epoch_before','draw_epoch_after')}

def single_pair_metadata(m):
    require(m.get('uv_oracle_single_pair') is True, 'single-pair oracle not enabled')
    require(all(m.get(key) is True for key in ('uv_oracle','uv_oracle_probe','sample_tap')) and
            m.get('invariant_b',False) is False, 'single-pair mode prerequisites not met')
    require(type(m.get('repetitions')) is int and m['repetitions'] == 1, 'single-pair requires exactly one repetition')
    require(m.get('draw_order') == SINGLE_PAIR_DRAW_ORDER, 'invalid single-pair draw order')
    require(isinstance(m.get('draw_ok'),dict) and set(m['draw_ok']) == set(SINGLE_PAIR_DRAW_ORDER) and
            all(m['draw_ok'][key] is True for key in SINGLE_PAIR_DRAW_ORDER), 'incomplete single-pair draw')
    require(m.get('programs_reused') is False, 'single pair cannot assert repeated program execution')
    for key in ('frame_id','frame_token'):
        integer(m.get(key),key,1)
    require(m.get('same_input_snapshot') is True and m.get('assertion_scope') == INPUT_ASSERTION_SCOPE,
            'invalid single-pair input snapshot assertion')
    tokens = m.get('program_tokens')
    require(isinstance(tokens,list) and len(tokens) == 2, 'invalid single-pair program tokens')
    for token in tokens:
        decimal_token(token,'single-pair program token')
    epochs = []
    for key in ('draw_epoch_before','draw_epoch_after'):
        require(isinstance(m.get(key),list) and len(m[key]) == 2, 'invalid single-pair '+key)
        epochs += [decimal_token(value,key,minimum=0) for value in m[key]]
    require(len(set(epochs)) == 1, 'single-pair draw error epochs differ')
    return {key:m[key] for key in ('uv_oracle_single_pair','repetitions','draw_order','draw_ok',
            'programs_reused','program_tokens','frame_id','frame_token','same_input_snapshot','assertion_scope',
            'draw_epoch_before','draw_epoch_after')}

def sample_tap_metadata(m):
    require(m.get('sample_tap') is True, 'sample tap not enabled')
    require(type(m.get('sample_tap_site_count')) is int and m['sample_tap_site_count'] == 1,
            'sample tap requires exactly one static site')
    require(type(m.get('words_per_pixel')) is int and m['words_per_pixel'] == 26,
            'invalid sample tap layout')
    decimal_token(m.get('sample_tap_body_hash'),'sample_tap_body_hash')
    require(m.get('instrumentation_scope') == SAMPLE_TAP_SCOPE, 'invalid instrumentation scope')
    return {key:m[key] for key in ('sample_tap','sample_tap_site_count','words_per_pixel',
                                  'sample_tap_body_hash','instrumentation_scope')}

def files_for_schema(schema):
    return ATLAS_READ_FILES if schema == 10 else ATLAS_FILES if schema == 9 else QUAD_ORDER_FILES if schema == 8 else ORACLE_PROBE_FILES if schema in (6,7) else INVARIANT_FILES if schema == 4 else SAMPLE_TAP_FILES if schema in (3,5) else FILES

def quad_order_metadata(m):
    require(m.get('quad_order') is True and type(m.get('quad_order_reverse')) is bool, 'invalid quad order mode')
    require(m.get('uv_oracle_use_a') is False, 'quad order requires original varying UV')
    single_pair_metadata(m)
    require(m.get('byte_order') == 'little', 'quad payload requires little endian')
    layout = m.get('quad_vertex_layout')
    validate_vertex_layout(layout, m.get('target_width'), m.get('target_height'))
    return {key:m[key] for key in ('quad_order','quad_order_reverse','quad_vertex_layout')}

def validate_vertex_layout(layout, target_width, target_height):
    keys = {'primitive','indexed','vertex_count','num_attributes','position_attrib','stride','byte_size','viewport','scissors','attributes'}
    require(isinstance(layout,dict) and set(layout) == keys, 'invalid quad layout fields')
    require(layout['primitive'] == 'triangle_strip' and layout['indexed'] is False and
            type(layout['vertex_count']) is int and layout['vertex_count'] == 4, 'quad requires four unindexed strip vertices')
    stride = integer(layout['stride'],'quad stride',4,1024)
    require(stride % 4 == 0 and type(layout['byte_size']) is int and layout['byte_size'] == stride*4,
            'invalid quad payload byte size/alignment')
    count = integer(layout['num_attributes'],'quad attribute count',1,16)
    position = integer(layout['position_attrib'],'quad position attribute',0,count-1)
    attrs = layout['attributes']
    require(isinstance(attrs,list) and len(attrs) == count, 'quad attribute count differs')
    attr_keys = {'name','format_name','glsl_type','fmt_type','location','num_components','component_depth',
                 'host_bits','sample_order','opaque','num_planes','offset','texel_size'}
    names, locations, spans = set(), set(), []
    for attr in attrs:
        require(isinstance(attr,dict) and set(attr) == attr_keys, 'invalid quad attribute fields')
        name = attr['name']
        require(isinstance(name,str) and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',name) and name not in names,
                'invalid or duplicate quad attribute name')
        names.add(name)
        format_name = attr['format_name']
        require(isinstance(format_name,str) and 0 < len(format_name) <= 64 and
                re.fullmatch(r'[A-Za-z0-9_]+',format_name), 'invalid quad format name')
        location = integer(attr['location'],'quad attribute location',0,15)
        require(location not in locations, 'duplicate quad attribute location')
        locations.add(location)
        components = integer(attr['num_components'],'quad attribute components',1,4)
        require(attr['fmt_type'] == 'float32' and attr['glsl_type'] == ('float' if components == 1 else 'vec'+str(components)),
                'unsupported quad attribute type')
        require(attr['opaque'] is False and type(attr['num_planes']) is int and attr['num_planes'] == 0,
                'opaque or planar quad format unsupported')
        for key in ('component_depth','host_bits','sample_order'):
            values = attr[key]
            require(isinstance(values,list) and len(values) == 4 and
                    all(type(value) is int and 0 <= value <= (3 if key == 'sample_order' else 64) for value in values),
                    'invalid quad '+key)
            require(values[:components] == (list(range(components)) if key == 'sample_order' else [32]*components),
                    'unsupported quad active '+key)
        offset = integer(attr['offset'],'quad attribute offset',0,stride-1)
        size = integer(attr['texel_size'],'quad attribute texel size',4,16)
        require(offset % 4 == 0 and size == components*4 and offset+size <= stride,
                'quad attribute out of bounds or misaligned')
        spans.append((offset,offset+size))
    spans.sort()
    require(all(a[1] <= b[0] for a,b in zip(spans,spans[1:])), 'overlapping quad attributes')
    require(attrs[position]['num_components'] == 2 and attrs[position]['glsl_type'] == 'vec2', 'quad position must be float32 vec2')
    target = [0,0,integer(target_width,'target_width',1,1<<20),integer(target_height,'target_height',1,1<<20)]
    for key in ('viewport','scissors'):
        require(isinstance(layout[key],list) and len(layout[key]) == 4 and
                all(type(value) is int for value in layout[key]) and layout[key] == target,
                'quad '+key+' must cover full target')
    return layout

def quad_payload_relation(baseline, candidate, layout, reverse, vertex_source):
    require(type(reverse) is bool and isinstance(baseline,bytes) and isinstance(candidate,bytes), 'invalid quad payload arguments')
    stride = layout['stride']
    require(len(baseline) == len(candidate) == layout['byte_size'] == 4*stride, 'quad payload size differs')
    attrs = layout['attributes']; position_attr = attrs[layout['position_attrib']]
    for attr in attrs:
        pattern = r'(?m)^[ \t]*(?:layout\(location[ \t]*=[ \t]*([0-9]+)\)[ \t]*)?in[ \t]+'+re.escape(attr['glsl_type'])+r'[ \t]+'+re.escape(attr['name'])+r';[ \t]*$'
        declarations = re.findall(pattern,vertex_source)
        require(len(declarations) == 1 and (not declarations[0] or int(declarations[0]) == attr['location']),
                'quad attribute does not match archived vertex shader')
    position_name = position_attr['name']
    require(len(re.findall(r'\bva_pos\b',vertex_source)) == 2 and vertex_source.count('gl_Position') == 1 and
            len(re.findall(r'(?m)^[ \t]*vec2 va_pos = '+re.escape(position_name)+r';[ \t]*$',vertex_source)) == 1 and
            len(re.findall(r'(?m)^[ \t]*gl_Position = vec4\(va_pos, 0\.0, 1\.0\);[ \t]*$',vertex_source)) == 1,
            'quad requires supported direct position vertex shader')
    positions = {}
    for label,data in (('A',baseline),('B',candidate)):
        for vertex in range(4):
            for attr in attrs:
                values = struct.unpack_from('<'+'f'*attr['num_components'],data,vertex*stride+attr['offset'])
                require(all(math.isfinite(v) for v in values), 'nonfinite actual quad attribute: '+label)
        positions[label] = [struct.unpack_from('<2f',data,vertex*stride+position_attr['offset']) for vertex in range(4)]
        require(set(positions[label]) == {(-1.,-1.),(-1.,1.),(1.,-1.),(1.,1.)}, 'quad position is not four unique NDC corners')
        require(all(positions[label][1][axis] == -positions[label][2][axis] for axis in (0,1)),
                'quad strip middle edge must be a diagonal')
    records = [baseline[i*stride:(i+1)*stride] for i in range(4)]
    require(len(set(records)) == 4, 'quad records do not define a unique permutation')
    permutation = [3,2,1,0] if reverse else [0,1,2,3]
    require(candidate == b''.join(records[index] for index in permutation), 'quad full records differ beyond requested permutation')
    def triangles(points):
        result,areas = [],[]
        for indices in ((0,1,2),(2,1,3)):
            triangle = tuple(points[index] for index in indices)
            p = [tuple(Fraction(value) for value in point) for point in triangle]
            area = (p[1][0]-p[0][0])*(p[2][1]-p[0][1])-(p[1][1]-p[0][1])*(p[2][0]-p[0][0])
            require(area != 0, 'degenerate quad triangle')
            areas.append(area)
            result.append(min(triangle[shift:]+triangle[:shift] for shift in range(3)))
        require((areas[0] > 0) == (areas[1] > 0), 'quad strip triangle winding differs')
        return sorted(result),areas
    a_triangles,a_areas = triangles(positions['A']);b_triangles,b_areas = triangles(positions['B'])
    require(a_triangles == b_triangles and (a_areas[0] > 0) == (b_areas[0] > 0), 'quad directed triangles changed')
    return {'status':'exact-full-record-permutation','permutation':permutation,'stride':stride,
            'bytes':len(baseline),'record_bytes_verified':True,'padding_bytes_preserved':True,
            'baseline_sha256':hashlib.sha256(baseline).hexdigest(),'candidate_sha256':hashlib.sha256(candidate).hexdigest(),
            'A_positions':positions['A'],'B_positions':positions['B'],
            'A_twice_signed_areas':[float(area) for area in a_areas],'B_twice_signed_areas':[float(area) for area in b_areas],
            'scope':QUAD_ORDER_SCOPE}

def invariant_metadata(m):
    require(m.get('invariant_b') is True, 'B invariant experiment not enabled')
    identifier = m.get('invariant_uv_identifier')
    require(isinstance(identifier,str) and re.fullmatch(r'_[0-9a-f]{1,4}',identifier) and
            int(identifier[1:],16) > 0,
            'invalid invariant UV identifier')
    return {key:m[key] for key in ('invariant_b','invariant_uv_identifier')}

def oracle_metadata(m):
    require(m.get('uv_oracle') is True, 'UV oracle framework not enabled')
    require(type(m.get('uv_oracle_use_a')) is bool, 'invalid UV oracle selection')
    require(m.get('invariant_b',False) is False, 'UV oracle and invariant are mutually exclusive')
    count = 1 if m.get('schema') in (7,8) else 2
    require(type(m.get('uv_oracle_barriers')) is int and m['uv_oracle_barriers'] == count,
            'invalid UV oracle barrier count')
    barriers = m.get('uv_oracle_barrier_ok')
    require(isinstance(barriers,list) and len(barriers) == count and all(v is True for v in barriers),
            'UV oracle barrier failed or missing')
    epochs = []
    for key in ('uv_oracle_barrier_epoch_before','uv_oracle_barrier_epoch_after'):
        require(isinstance(m.get(key),list) and len(m[key]) == count, 'invalid '+key)
        epochs += [decimal_token(v,key,minimum=0) for v in m[key]]
    # The native producer asserts these GPU receipts. Only their serialized
    # consistency is checked here, including the four draw receipts.
    repeat_metadata(m)
    epochs += [decimal_token(v,'draw epoch',minimum=0) for key in ('draw_epoch_before','draw_epoch_after') for v in m[key]]
    require(len(set(epochs)) == 1, 'UV oracle barrier/draw epochs differ')
    return {key:m[key] for key in ('uv_oracle','uv_oracle_use_a','uv_oracle_barriers',
            'uv_oracle_barrier_ok','uv_oracle_barrier_epoch_before','uv_oracle_barrier_epoch_after')}

def oracle_probe_metadata(m):
    oracle_metadata(m)
    require(m.get('uv_oracle_probe') is True, 'UV oracle probe not enabled')
    require(m.get('uv_oracle_probe_status') == 'complete', 'UV oracle probe readback not complete')
    require(type(m.get('uv_oracle_probe_words_per_pixel')) is int and m['uv_oracle_probe_words_per_pixel'] == 10,
            'invalid UV oracle probe layout')
    integer(m.get('uv_oracle_probe_words'),'uv_oracle_probe_words',1)
    require(type(m.get('oracle_preconditions_valid')) is bool, 'missing oracle preconditions validity')
    mask = integer(m.get('oracle_cpu_validation_mask'),'oracle_cpu_validation_mask',0,127)
    require(m.get('oracle_cpu_validation_reasons') == cpu_validation_reasons(mask), 'invalid oracle CPU validation reasons')
    require(m['oracle_preconditions_valid'] == (mask == 0), 'oracle validity disagrees with CPU validation mask')
    expected_status = 'complete' if m['oracle_preconditions_valid'] else 'diagnostic-invalid'
    require(m.get('status') == expected_status, 'oracle validity disagrees with capture status')
    return {key:m[key] for key in ('uv_oracle_probe','uv_oracle_probe_status','uv_oracle_probe_words',
                                  'uv_oracle_probe_words_per_pixel','oracle_preconditions_valid',
                                  'oracle_cpu_validation_mask','oracle_cpu_validation_reasons')}

def cpu_validation_reasons(mask):
    return [name for bit,name in CPU_VALIDATION_REASONS.items() if mask & bit]

def source_difference(left, right, left_name, right_name):
    difference = ''.join(difflib.unified_diff(left.splitlines(keepends=True),right.splitlines(keepends=True),
                                            fromfile=left_name,tofile=right_name))
    return {'identical':left == right,
            'left_sha256':hashlib.sha256(left.encode('utf-8')).hexdigest(),
            'right_sha256':hashlib.sha256(right.encode('utf-8')).hexdigest(),
            'unified_diff':difference[:32768],'diff_truncated':len(difference)>32768}

def invariant_vertex_relation(anchor, candidate, uv_identifier):
    invariant_metadata({'invariant_b':True,'invariant_uv_identifier':uv_identifier})
    declarations = ('invariant gl_Position;\n','invariant '+uv_identifier+';\n')
    require('invariant' not in anchor, 'A0 vertex already contains invariant')
    require(anchor.count('void main() {') == 1, 'A0 vertex main is missing or ambiguous')
    main = anchor.index('void main() {')
    require(main == 0 or anchor[main-1] == '\n', 'A0 vertex main is not at line start')
    declaration = 'out vec2 '+uv_identifier+';\n'
    require(anchor.splitlines(keepends=True).count(declaration) == 1 and anchor.index(declaration) < main,
            'A0 UV output declaration is missing or ambiguous')
    position = 'gl_Position = vec4(va_pos, 0.0, 1.0);'
    require(anchor.count('gl_Position') == 1 and position in anchor and anchor.index(position) > main,
            'A0 position assignment is unsupported')
    expected = anchor.replace('void main() {',''.join(declarations)+'void main() {',1)
    require(candidate == expected, 'candidate vertex differs beyond exact two invariant declarations')
    result = source_difference(anchor,candidate,'A0.vertex','B.vertex')
    result.update(status='exact-two-invariant-declarations-only',invariant_identifiers=['gl_Position',uv_identifier],
                  scope='Source byte relation only; compilation and output may differ. This does not independently prove A0 matches an earlier control capture.')
    return result

def unique_object(pairs):
    out = {}
    for k, v in pairs:
        require(k not in out, 'duplicate JSON key: ' + k)
        out[k] = v
    return out

def load_json(path):
    try:
        return json.loads(path.read_text(), object_pairs_hook=unique_object,
                          parse_constant=lambda x: (_ for _ in ()).throw(InvalidCapture('nonfinite JSON: '+x)))
    except (OSError, json.JSONDecodeError) as error:
        raise InvalidCapture(str(error)) from error

def safe_file(root, name):
    require(isinstance(name, str) and name not in ('', '.', '..') and
            Path(name).name == name and '/' not in name and '\\' not in name,
            'file must be a basename')
    path = root / name
    require(not path.is_symlink() and path.is_file(), 'missing or symlink file: ' + name)
    return path

def float32(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]

def ordered(word):
    return (~word & 0xffffffff) if word & 0x80000000 else word | 0x80000000

def compare_vectors(left, right, width, origin, channels, known_finite=False):
    components = len(channels)
    require(components > 0 and len(left) == len(right) and len(left) % components == 0,
            'invalid vector lengths')
    mismatch = nonfinite = 0
    mismatch_pixels = 0
    last_mismatch_pixel = None
    max_abs = 0.0
    max_ulp = 0
    examples = []
    max_location = None
    for i, (a, b) in enumerate(zip(left, right)):
        if known_finite and a == b:
            continue
        av, bv = float32(a), float32(b)
        good = math.isfinite(av) and math.isfinite(bv)
        if not good:
            nonfinite += 1
        if a != b:
            mismatch += 1
            pixel, channel = divmod(i, components)
            if pixel != last_mismatch_pixel:
                mismatch_pixels += 1
                last_mismatch_pixel = pixel
            detail = {'x': origin[0]+pixel % width, 'y': origin[1]+pixel // width,
                      'channel': channels[channel], 'left_bits': f'{a:08x}', 'right_bits': f'{b:08x}'}
            if good:
                detail.update(left=av, right=bv, absolute_difference=abs(av-bv))
            if len(examples) < 10:
                examples.append(detail)
        if good:
            if abs(av-bv) > max_abs:
                pixel, channel = divmod(i, components)
                max_location = {'x':origin[0]+pixel % width, 'y':origin[1]+pixel // width, 'channel':channels[channel]}
                max_abs = abs(av-bv)
            max_ulp = max(max_ulp, abs(ordered(a)-ordered(b)))
    return {'components': len(left), 'bit_mismatches': mismatch,
            'pixels_with_bit_mismatches':mismatch_pixels,
            'nonfinite_components': nonfinite, 'max_absolute_difference': max_abs,
            'max_ulp_distance': max_ulp, 'max_absolute_difference_location': max_location, 'first_differences': examples}

def is_binary16_expansion(word):
    exponent = (word >> 23) & 255
    fraction = word & 0x7fffff
    if exponent == 0:
        return fraction == 0
    if 113 <= exponent <= 142:
        return fraction & 0x1fff == 0
    if 103 <= exponent <= 112:
        return ((0x800000 | fraction) & ((1 << (126-exponent))-1)) == 0
    return False

def validate_clean_a0(a0, original_body):
    require(bool(original_body.strip()) and a0.count(original_body) == 1, 'A0 source does not contain unique original body')
    require(not re.search(r'mks_',a0,re.IGNORECASE), 'capture symbols present in A0 source')
    a0_code = re.sub(r'//[^\n]*|/\*.*?\*/',' ',a0,flags=re.DOTALL)
    require(not re.search(r'\bbuffer\b',a0_code), 'storage buffer forbidden in A0 source')
    require(not re.search(r'\b[ui]?image(?:1D|2D|3D|Cube|Buffer)[A-Za-z0-9_]*\b',a0_code),
            'storage image forbidden in A0 source')
    calls = re.findall(r'\b(texture[A-Za-z0-9_]*|texelFetch[A-Za-z0-9_]*)\s*\(',a0_code)
    require(calls == ['textureLod'], 'expected sole direct textureLod sample in A0 source')

def strip_capture_insertions(source, prefix):
    spans = []
    for name in ('GLOBALS','SITE','TAIL'):
        begin = '// '+prefix+name+'_BEGIN\n'
        end = '// '+prefix+name+'_END\n'
        require(source.count(begin) == source.count(end) == 1, 'missing or duplicate atlas source marker: '+name)
        start = source.index(begin); stop = source.index(end)
        require(not source[source.rfind('\n',0,start)+1:start].strip() and
                (stop == 0 or source[stop-1] == '\n') and stop > start+len(begin),
                'invalid atlas insertion marker boundaries: '+name)
        spans.append((start,stop+len(end)))
    spans.sort()
    require(all(a[1] <= b[0] for a,b in zip(spans,spans[1:])), 'overlapping atlas insertion spans')
    stripped = source
    for start,stop in reversed(spans):
        stripped = stripped[:start]+stripped[stop:]
    return stripped

def atlas_source_relation(a0, atlas, original_body):
    validate_clean_a0(a0,original_body)
    code = re.sub(r'//[^\n]*|/\*.*?\*/',' ',atlas,flags=re.DOTALL)
    require(re.findall(r'\b(texture[A-Za-z0-9_]*|texelFetch[A-Za-z0-9_]*)\s*\(',code) == ['textureLod'],
            'expected sole direct textureLod sample in atlas source')
    require(strip_capture_insertions(atlas,'MKS_ATLAS_') == a0, 'atlas source differs beyond the three insertion spans')
    return {'status':'exact-three-insertions', 'a0_contains_original_body':True,
            'control_relation':'not-independently-verified',
            'scope':'Archived source bytes prove three insertions relative to archived A0. The middle atlas shader is instrumented. Equivalence of A0 to an external production control and actual native bindings remain unverified offline.'}

def validate_atlas_uv(words, width, height):
    require(len(words) == width*height*3, 'incomplete full-screen atlas')
    minima = [None,None]; maxima = [None,None]
    for pixel in range(width*height):
        u,v,count = words[pixel*3:pixel*3+3]
        for word in (u,v,count):
            integer(word,'atlas word',0,0xffffffff)
        if count != 1:
            raise InvalidCapture('invalid atlas execution count: '+json.dumps({
                'x':pixel%width,'y':pixel//width,'count':count,'invalid_flag':bool(count & 0x80000000)}))
        for channel,word in enumerate((u,v)):
            value = float32(word)
            if not math.isfinite(value):
                raise InvalidCapture('nonfinite atlas UV: '+json.dumps({
                    'x':pixel%width,'y':pixel//width,'channel':'UV'[channel],'bits':f'{word:08x}'}))
            minima[channel] = value if minima[channel] is None else min(value,minima[channel])
            maxima[channel] = value if maxima[channel] is None else max(value,maxima[channel])
    return {'pixels':width*height,'coverage':'exactly-one-record-per-pixel','all_uv_finite':True,
            'uv_min':minima,'uv_max':maxima}

def atlas_dimensions(width, height):
    width = integer(width, 'atlas readback width', 1, 16384)
    height = integer(height, 'atlas readback height', 1, 16384)
    require(width * height <= MAX_ATLAS_PIXELS, 'atlas full-screen readback exceeds pixel budget')
    return width*height

def validate_atlas_rgba(words, width, height, role):
    atlas_dimensions(width,height)
    expected = width * height * 4
    require(len(words) == expected, 'incomplete full-screen readback: ' + role)
    for index, word in enumerate(words):
        integer(word, 'RGBA/FLOAT word', 0, 0xffffffff)
        if not is_binary16_expansion(word):
            reason = 'nonfinite full-screen readback: ' if (word >> 23) & 255 == 255 else 'readback is not an exact binary16 expansion: '
            raise InvalidCapture(reason+json.dumps({'role':role, 'x':(index//4)%width, 'y':(index//4)//width,
                                                   'channel':'RGBA'[index%4], 'bits':f'{word:08x}'}))

class ChannelWords:
    """A bounded view of interleaved words; avoids full-screen Python int copies."""
    def __init__(self, words, stride, channels):
        self.words,self.stride,self.channels = words,stride,channels
    def __len__(self):
        return len(self.words)//self.stride*len(self.channels)
    def __iter__(self):
        for base in range(0,len(self.words),self.stride):
            for channel in self.channels:
                yield self.words[base+channel]

def compare_atlas_consumer_uv(probe, seed_atlas, width, height):
    pixels = atlas_dimensions(width,height)
    require(len(probe) == pixels*4, 'incomplete full-screen consumer UV probe')
    validate_atlas_uv(seed_atlas,width,height)
    for pixel in range(pixels):
        count,u,v,site = probe[pixel*4:pixel*4+4]
        require(count == 1 and type(count) is int and site == 1 and type(site) is int,
                'invalid consumer UV fragment/site coverage')
        for word in (u,v):
            integer(word,'consumer UV word',0,0xffffffff)
            require(math.isfinite(float32(word)), 'nonfinite consumer UV')
    comparison = compare_vectors(ChannelWords(probe,4,(1,2)),ChannelWords(seed_atlas,3,(0,1)),
                                 width,(0,0),'UV',known_finite=True)
    return {'status':'captured-float-differences' if comparison['bit_mismatches'] else 'captured-floats-bit-equal',
            'pixels':pixels,'coverage':'exactly-one-record-and-site-per-pixel','comparison':comparison,
            'scope':'Full-screen supplied probe UV versus seed atlas UV. Source, runtime mode, binding, cache signature, fallback and frame identities require separate validation; no uninstrumented B0 equivalence is established.'}

def compare_atlas_consumer_half(probe, a0_rgba, width, height):
    pixels = atlas_dimensions(width,height)
    require(len(probe) == pixels*4, 'incomplete full-screen consumer half probe')
    validate_atlas_rgba(a0_rgba,width,height,'consumer A0 reference')
    for pixel in range(pixels):
        count = probe[pixel*4]
        require(type(count) is int and count == 1, 'invalid consumer half fragment coverage')
        for word in probe[pixel*4+1:pixel*4+4]:
            integer(word,'consumer half word',0,0xffffffff)
            require(is_binary16_expansion(word), 'consumer half is nonfinite or not an exact binary16 expansion')
    comparison = compare_vectors(ChannelWords(probe,4,(1,2,3)),ChannelWords(a0_rgba,4,(0,1,2)),
                                 width,(0,0),'RGB',known_finite=True)
    return {'status':'captured-float-differences' if comparison['bit_mismatches'] else 'captured-floats-bit-equal',
            'pixels':pixels,'coverage':'exactly-one-record-per-pixel','comparison':comparison,
            'scope':'Full-screen instrumented half RGB versus this frame A0 readback RGB only. Alpha, YUV, physical storage, uninstrumented B0, production and panel equivalence are not established.'}

def compare_atlas_readbacks(before, atlas, after, width, height):
    """Compare supplied RGBA/FLOAT readback words, not physical half storage."""
    for role, words in (('A0_before', before), ('atlas_A', atlas), ('A0_after', after)):
        validate_atlas_rgba(words,width,height,role)
    comparisons = {name:compare_vectors(left, right, width, (0,0), 'RGBA', known_finite=True) for name,left,right in (
        ('A0_before_vs_after', before, after), ('A0_before_vs_atlas_A', before, atlas),
        ('atlas_A_vs_A0_after', atlas, after))}
    stable = not comparisons['A0_before_vs_after']['bit_mismatches']
    equal = all(not value['bit_mismatches'] for value in comparisons.values())
    return {'status':'captured-floats-bit-equal' if equal else 'captured-float-differences',
            'baseline_readback_stable':stable, 'all_three_readbacks_bit_equal':equal,
            'comparisons':comparisons,
            'representation':'RGBA/FLOAT finite float32 readback values expanded from RGBA16F; not physical storage bytes',
            'scope':'Supplied full-screen readback values only. FBO identity, coverage and synchronization require separate metadata validation. The middle atlas shader is instrumented; no production, raw YUV, panel or power conclusion.'}

def compare_stages(left, right, width, origin, left_role, right_role,
                   stages=('pre_rgb', 'half_rgb', 'yuv')):
    require(set(stages) <= set(left) and set(stages) <= set(right), 'missing repeat stage')
    results = {}
    for stage in stages:
        results[stage] = compare_vectors(left[stage], right[stage], width, origin,
                                        ('Y','Cb','Cr') if stage == 'yuv' else 'RGB')
        results[stage].update(left_role=left_role, right_role=right_role)
    return results

def compare_repeats(samples, width, origin, baseline_prefix='A'):
    """Compare four real draws; never synthesize a missing repetition."""
    a1, a2 = baseline_prefix+'1', baseline_prefix+'2'
    require(set(samples) == {'B1',a1,'B2',a2}, 'missing repeat draw')
    for name, sample in samples.items():
        expected = {'pre_rgb'} if name == a1 else {'pre_rgb','half_rgb','yuv'}
        require(set(sample) == expected, 'invalid captured stages: '+name)
    comparisons = {
        name: compare_stages(samples[left], samples[right], width, origin, left, right, stages)
        for name, left, right, stages in (
            ('candidate_repeat','B1','B2',('pre_rgb','half_rgb','yuv')),
            ('baseline_repeat',a1,a2,('pre_rgb',)),
            ('ab1',a1,'B1',('pre_rgb',)),
            ('ab2',a2,'B2',('pre_rgb','half_rgb','yuv')))
    }
    def exact(stages):
        return all(not s['bit_mismatches'] and not s['nonfinite_components']
                   for s in stages.values())
    stable = all(exact(comparisons[k]) for k in ('candidate_repeat','baseline_repeat'))
    nonfinite = any(s['nonfinite_components'] for group in comparisons.values() for s in group.values())
    localization = {}
    for name in ('ab1','ab2'):
        localization[name] = next((stage for stage, value in comparisons[name].items()
                                   if value['bit_mismatches'] or value['nonfinite_components']), None)
    return {'comparisons':comparisons,
            'repeatability':'invalid-nonfinite' if nonfinite else 'captured-stages-bit-stable' if stable else 'captured-stages-bit-unstable',
            'not_captured':{'baseline_repeat':['half_rgb','yuv'],'ab1':['half_rgb','yuv']},
            'ab_localization':{'first_differing_stage':localization,
                               'captured_repeatability_confirmed':stable and not nonfinite,
                               'full_baseline_repeatability_confirmed':False,
                               'scope':a1+' stored RGB16F sample/CSC YUV were not captured. Stage order alone does not identify a GPU or compiler root cause.'}}

def compare_sample_taps(samples, width, origin, baseline_prefix='A'):
    a1, a2 = baseline_prefix+'1', baseline_prefix+'2'
    require(set(samples) == {'B1',a1,'B2',a2}, 'missing sample tap draw')
    for name, sample in samples.items():
        require(set(sample) == {'uv','sample_rgb'}, 'invalid sample tap stages: '+name)
    comparisons = {}
    for name, left, right in (('candidate_repeat','B1','B2'),('baseline_repeat',a1,a2),
                              ('ab1',a1,'B1'),('ab2',a2,'B2')):
        comparisons[name] = {}
        for stage, channels in (('uv','UV'),('sample_rgb','RGB')):
            result = compare_vectors(samples[left][stage],samples[right][stage],width,origin,channels)
            result.update(left_role=left,right_role=right)
            comparisons[name][stage] = result
    repeated = [result for name in ('candidate_repeat','baseline_repeat')
                for result in comparisons[name].values()]
    all_results = [result for stages in comparisons.values() for result in stages.values()]
    nonfinite = any(result['nonfinite_components'] for result in all_results)
    stable = all(not result['bit_mismatches'] and not result['nonfinite_components'] for result in repeated)
    return {'comparisons':comparisons,
            'repeatability':'invalid-nonfinite' if nonfinite else 'sample-taps-bit-stable' if stable else 'sample-taps-bit-unstable',
            'captured_repeatability_confirmed':stable and not nonfinite,
            'scope':'Instrumented sample site only; instrumentation may change shader compilation. This is not an unmodified shader capture.'}

def compare_single_pair_taps(samples, width, origin):
    require(set(samples) == {'A1','B1'}, 'single-pair sample draws differ')
    require(all(set(sample) == {'uv','sample_rgb'} for sample in samples.values()), 'missing single-pair sample stage')
    pairs = {}
    for stage, channels in (('uv','UV'),('sample_rgb','RGB')):
        pairs[stage] = compare_vectors(samples['A1'][stage],samples['B1'][stage],width,origin,channels)
        pairs[stage].update(left_role='A1',right_role='B1')
    return {'comparisons':{'ab1':pairs},'repeatability':'not-measured-single-pair',
            'captured_repeatability_confirmed':False,'scope':SINGLE_PAIR_SCOPE+' '+SAMPLE_TAP_SCOPE}

def oracle_uv_relation(tap_analysis, use_a, pair_names=('ab1','ab2')):
    require(type(use_a) is bool, 'invalid UV oracle selection')
    pairs = {name:tap_analysis['comparisons'][name]['uv'] for name in pair_names}
    if use_a:
        for name, result in pairs.items():
            require(not result['bit_mismatches'] and not result['nonfinite_components'],
                    'oracle B UV does not match captured A UV: '+name+' '+json.dumps(result))
    return {'selection':'captured-A-UV' if use_a else 'original-varying-UV',
            'status':'captured-UV-bits-match' if use_a else 'UV-match-not-required-for-control',
            'comparisons':pairs,'scope':ORACLE_SCOPE}

def require_schema6_render_finite(lib, android, pixels, width, origin, repetitions=2):
    # Only the sidecar's observed A UV may hold nonfinite diagnostic bits.
    # Actual rendering and sampled payloads remain a hard gate in both modes.
    offsets = tuple(range(1,10))+tuple(range(11,19))+tuple(range(20,25))
    for repetition in range(repetitions):
        for pixel in range(pixels):
            for offset in offsets:
                word = lib[(repetition*pixels+pixel)*26+offset]
                require(math.isfinite(float32(word)), 'nonfinite actual main float: '+json.dumps({
                    'repetition':repetition+1,'x':origin[0]+pixel%width,'y':origin[1]+pixel//width,
                    'word_offset':offset,'bits':f'{word:08x}'}))
    for pixel in range(pixels):
        for offset in range(1,7):
            word = android[pixel*7+offset]
            require(math.isfinite(float32(word)), 'nonfinite actual Android float: '+json.dumps({
                'x':origin[0]+pixel%width,'y':origin[1]+pixel//width,
                'word_offset':offset,'bits':f'{word:08x}'}))

def analyze_oracle_probe(lib, probe, pixels, width, origin, use_a, repetitions=2):
    require(type(use_a) is bool, 'invalid UV oracle selection')
    require(repetitions in (1,2) and len(lib) == pixels*26*repetitions and len(probe) == pixels*10*repetitions,
            'invalid oracle probe vector lengths')
    reason_counts, selected_counts, issue_counts = {}, {}, {}
    samples, invalid_examples = [], []
    invalid_pixels = read_pixels = ambiguous_reads = uv_differences = fragment_differences = site_differences = total_mask = 0
    for repetition in range(repetitions):
        for pixel in range(pixels):
            p = probe[(repetition*pixels+pixel)*10:(repetition*pixels+pixel+1)*10]
            b = lib[(repetition*pixels+pixel)*26:(repetition*pixels+pixel+1)*26]
            location = {'repetition':repetition+1,'x':origin[0]+pixel%width,'y':origin[1]+pixel//width}
            require(tuple(p[:3]) == (1,1,1), 'oracle probe execution coverage not exactly one: '+json.dumps(dict(location,counts=p[:3])))
            require(b[10] == 1 and b[25] == 1, 'terminal A execution coverage not exactly one')
            reason, valid, selected = p[7:10]
            require(reason <= 15 and valid in (0,1) and selected in (0,1,2) and b[19] in (0,1), 'invalid oracle probe reason/selection/count range')
            inside = not bool(reason & 1)
            read = True if inside else False if reason == 1 and tuple(p[3:7]) == (0,0,0,0) else None
            observed_finite = all(math.isfinite(float32(word)) for word in p[5:7])
            mask = 1 if reason or not valid else 0
            if not inside:
                if reason != 1 or tuple(p[3:7]) != (0,0,0,0):
                    mask |= 2
            else:
                expected = (2 if p[3] != 1 else 0) | (4 if p[4] != 1 else 0) | (8 if not observed_finite else 0)
                if reason != expected:
                    mask |= 2
            if valid != int(reason == 0):
                mask |= 4
            if b[19] != valid:
                mask |= 16
            if selected != (int(use_a) if valid else 2):
                mask |= 8
            if inside:
                read_pixels += 1
                fragment_differences += p[3] != b[10]
                site_differences += p[4] != b[25]
                differences = sum(a != z for a,z in zip(p[5:7],b[20:22]))
                uv_differences += differences
                if differences:
                    mask |= 32
            elif read is None:
                ambiguous_reads += 1
            if selected == 1 and tuple(b[14:16]) != tuple(p[5:7]):
                mask |= 64
            issues = cpu_validation_reasons(mask)
            total_mask |= mask
            reason_counts[str(reason)] = reason_counts.get(str(reason),0)+1
            selected_counts[str(selected)] = selected_counts.get(str(selected),0)+1
            for issue in issues:
                issue_counts[issue] = issue_counts.get(issue,0)+1
            detail = dict(location,execution={'fragment_records':p[0],'helper_calls':p[1],'actual_sample_sites':p[2]},
                A_read_performed=read,
                GPU_observed_A={'fragment_count':p[3] if read is True else None,'site_count':p[4] if read is True else None,
                    'raw_fragment_count':p[3],'raw_site_count':p[4],
                    'stored_UV_bits':[f'{word:08x}' for word in p[5:7]],'UV_finite':observed_finite if read else None},
                CPU_terminal_A={'fragment_count':b[10],'site_count':b[25],'UV_bits':[f'{word:08x}' for word in b[20:22]]},
                reason_mask=reason,dependency_valid=bool(valid),selected_source=selected,
                B_dependency_valid_count=b[19],B_actual_UV_bits=[f'{word:08x}' for word in b[14:16]],
                cpu_validation_mask=mask,issues=issues)
            if len(samples) < 10:
                samples.append(detail)
            if issues:
                invalid_pixels += 1
                if len(invalid_examples) < 10:
                    invalid_examples.append(detail)
    return {'preconditions_valid':invalid_pixels == 0,'records':pixels*repetitions,'A_read_records':read_pixels,
            'A_read_ambiguous_records':ambiguous_reads,'cpu_validation_mask':total_mask,
            'cpu_validation_reasons':cpu_validation_reasons(total_mask),
            'invalid_records':invalid_pixels,'reason_counts':reason_counts,'selected_source_counts':selected_counts,
            'reason_bit_labels':{'1':'outside_ROI_no_A_read','2':'observed_A_fragment_count_not_one',
                                 '4':'observed_A_site_count_not_one','8':'observed_A_UV_nonfinite'},
            'selected_source_labels':{'0':'original_varying_control','1':'GPU_observed_A_UV','2':'fallback_after_invalid_dependency'},
            'issue_counts':issue_counts,'GPU_observed_vs_CPU_terminal':{
                'A_fragment_count_differences':fragment_differences,'A_site_count_differences':site_differences,
                'A_UV_bit_differences':uv_differences},
            'first_records':samples,'first_invalid_records':invalid_examples,
            'B_site_field_semantics':'lib[19] counts dependency-valid sites; probe[2] independently counts actual executed sample sites.',
            'scope':PROBE_SCOPE}

def atlas_read_material(m):
    keys = {'input_width','input_height','sampler_type','sample_mode','address_mode','format_type',
        'num_components','component_depth','host_bits','sample_order','format_name','num_variables',
        'uniform_bytes','variables','uniforms_hex'}
    require(isinstance(m,dict) and set(m) == keys, 'invalid atlas read material fields')
    for key in ('input_width','input_height'):
        integer(m[key],key,1,16384)
    require(type(m['sampler_type']) is int and m['sampler_type'] == 0, 'atlas read requires normal sampler')
    integer(m['sample_mode'],'sample mode',0,1); integer(m['address_mode'],'address mode',0,2)
    integer(m['format_type'],'format type',1,5)
    components = integer(m['num_components'],'input components',1,4)
    require(isinstance(m['format_name'],str) and re.fullmatch(r'[A-Za-z0-9_]{1,31}',m['format_name']), 'invalid input format name')
    for key in ('component_depth','host_bits','sample_order'):
        values = m[key]
        require(isinstance(values,list) and len(values) == 4, 'invalid input '+key)
        for index,value in enumerate(values):
            integer(value,key,0,3 if key == 'sample_order' else 64)
            if key != 'sample_order' and index < components:
                require(value > 0,'empty active input '+key)
    count = integer(m['num_variables'],'material variables',0,16)
    total = integer(m['uniform_bytes'],'material uniform bytes',0,4096)
    variables = m['variables']
    require(isinstance(variables,list) and len(variables) == count, 'invalid material variable count')
    names = set(); offset = 0
    for var in variables:
        require(isinstance(var,dict) and set(var) == {'name','type','dim_v','dim_m','dim_a','offset','size'}, 'invalid uniform fields')
        require(isinstance(var['name'],str) and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,30}',var['name']) and
                var['name'] not in names, 'invalid uniform name')
        names.add(var['name']); integer(var['type'],'uniform type',1,3)
        v=integer(var['dim_v'],'uniform vector',1,4); matrix=integer(var['dim_m'],'uniform matrix',1,4)
        array=integer(var['dim_a'],'uniform array',1,1024)
        require(type(var['offset']) is int and var['offset'] == offset and type(var['size']) is int and
                var['size'] == 4*v*matrix*array, 'uniform packed layout differs')
        offset += var['size']
    require(offset == total and isinstance(m['uniforms_hex'],str) and
            re.fullmatch(r'[0-9a-f]*',m['uniforms_hex']) and len(m['uniforms_hex']) == total*2,
            'uniform bytes differ from layout')
    return m

def atlas_read_metadata(m):
    require(type(m.get('schema')) is int and m['schema'] == 10, 'invalid atlas read schema')
    require(m.get('scope') == ATLAS_READ_SCOPE and m.get('source_scope') == ATLAS_READ_SOURCE_SCOPE and
            m.get('cache_policy') == ATLAS_CACHE_POLICY and m.get('signature_scope') == ATLAS_SIGNATURE_SCOPE and
            m.get('signature_algorithm') == 'sha256-length-prefix-v1', 'invalid atlas read evidence scope')
    require(m.get('diagnostic_cache_settings') == {'skip_caching_single_frame':True,'preserve_mixing_cache':False} and
            m['diagnostic_cache_settings']['skip_caching_single_frame'] is True and
            m['diagnostic_cache_settings']['preserve_mixing_cache'] is False, 'invalid diagnostic renderer cache settings')
    for key in ('pid','capture_id','generation','frame_id','frame_token','seed_capture_id','seed_frame_id',
                'seed_frame_token','cache_id','cache_generation'):
        integer(m.get(key),key,1)
    require(m['cache_generation'] == m['generation'], 'atlas cache generation differs')
    ordinal=integer(m.get('ordinal'),'atlas read ordinal',1,2)
    source=finite(m.get('source_pts'),'source_pts'); seed=finite(m.get('seed_pts'),'seed_pts')
    require(source >= 0 and seed >= 0, 'negative atlas read PTS')
    for key in ('current_pts','target_pts'):
        value=finite(m.get(key),key)
        require(value >= 0 and abs(value-source) <= 2e-6,'atlas read PTS differs')
    require(m['frame_token'] > m['seed_frame_token'], 'atlas read receipt token is not fresh')
    if ordinal == 1:
        require(m['frame_id'] == m['seed_frame_id'] and abs(source-seed) <= 2e-6, 'first atlas read must use seed frame')
    else:
        require(m['frame_id'] != m['seed_frame_id'] and abs(source-seed) > 2e-6, 'second atlas read requires a new frame and PTS')
    for key in ('seed_input_image_token','input_image_token','seed_input_texture_token','input_texture_token',
                'renderer_id','renderer_generation','b0_program_token'):
        decimal_token(m.get(key),key)
    if ordinal == 1:
        # The sampled texture is renderer-internal with a single-frame
        # lifetime; pointer equality with the seed is structurally
        # unsatisfiable on-device. Both tokens stay archived decimal values;
        # same-frame admission is frame id + PTS + signature + geometry.
        require(m['seed_input_image_token'] == m['input_image_token'],
                'seed input image identity differs')
    integer(m.get('cache_storage_buffer'),'cache storage buffer',1,0xffffffff)
    offset=decimal_token(m.get('cache_storage_offset'),'cache offset',minimum=0)
    size=decimal_token(m.get('cache_storage_size'),'cache size')
    pixels=atlas_dimensions(m.get('width'),m.get('height'))
    require(type(m.get('pixels')) is int and m['pixels'] == pixels and size == pixels*12 and offset%4 == 0,
            'atlas cache storage size/alignment differs')
    for key,expected in (('rgba_words',pixels*4),('probe_words',pixels*4),('atlas_words',pixels*3)):
        require(type(m.get(key)) is int and m[key] == expected,'invalid atlas read '+key)
    require(m.get('byte_order') == 'little' and type(m.get('read_format')) is int and m['read_format'] == 6408 and
            type(m.get('read_type')) is int and m['read_type'] == 5126,'invalid atlas read format')
    require(m.get('draw_order') == ['a0','uv','half'] and m.get('probe_modes') == [0,1] and
            all(type(value) is int for value in m['probe_modes']), 'invalid atlas read mode/order')
    for key in ('draw_ok','readback_ok'):
        require(isinstance(m.get(key),list) and len(m[key]) == 3 and all(value is True for value in m[key]), 'incomplete atlas read '+key)
    for key in ('baseline_ok','fence_signaled','signature_match','android_swap_succeeded','android_fence_signaled'):
        require(m.get(key) is True,'missing true atlas read '+key)
    require(type(m.get('reject_reason')) is int and m['reject_reason'] == 0 and m.get('b0_drawn') is False,
            'atlas read rejected or claimed B0 numerical draw')
    tokens=m.get('program_tokens')
    require(isinstance(tokens,list) and len(tokens) == 3,'invalid atlas read program tokens')
    values=[decimal_token(v,'atlas read program') for v in tokens]
    b0=decimal_token(m['b0_program_token'],'B0 program')
    require(values[1] == values[2] and len({values[0],values[1],b0}) == 3,'atlas read program identities differ')
    epochs=[decimal_token(m.get('finish_epoch'),'finish epoch',minimum=0)]
    for key in ('draw_epoch_before','draw_epoch_after','readback_epoch_before','readback_epoch_after'):
        require(isinstance(m.get(key),list) and len(m[key]) == 3,'invalid atlas read '+key)
        epochs += [decimal_token(value,key,minimum=0) for value in m[key]]
    require(len(set(epochs)) == 1,'atlas read epochs differ')
    for key in ('uv_equal','half_equal'):
        require(type(m.get(key)) is bool,'invalid atlas read '+key)
    for key in ('bad_uv_pixels','bad_half_pixels'):
        integer(m.get(key),key,0,pixels)
    mask=integer(m.get('read_validation_mask'),'read validation mask',0,3)
    require(m.get('read_validation_reasons') == [v for bit,v in ((1,'uv-mismatch'),(2,'half-mismatch')) if mask&bit] and
            m['uv_equal'] == (not bool(mask&1)) and m['half_equal'] == (not bool(mask&2)), 'atlas read validation metadata differs')
    require(m.get('status') == ('diagnostic-invalid' if mask else 'complete') and
            m.get('comparison_pass') == ('refused' if mask else 'unknown'), 'invalid atlas read completion claim')
    require(m.get('android_status') == 'ready','atlas read Android not ready')
    roi=m.get('android_roi')
    require(isinstance(roi,dict) and set(roi) == {'x','y','w','h'},'invalid atlas read Android ROI')
    x,y=(integer(roi[k],k,0) for k in ('x','y')); w,h=(integer(roi[k],k,1) for k in ('w','h'))
    require(x+w <= m['width'] and y+h <= m['height'] and w*h <= MAX_PIXELS and type(m.get('android_words')) is int and
            m['android_words'] == w*h*7,'invalid atlas read Android size')
    validate_vertex_layout(m.get('vertex_layout'),m['width'],m['height'])
    reference=m.get('seed_reference')
    require(isinstance(reference,dict) and set(reference) == {'manifest','sha256'} and
            reference['manifest'] == f"mks-yuv-atlas-{m['pid']}-{m['seed_capture_id']}.json" and
            isinstance(reference['sha256'],str) and re.fullmatch('[0-9a-f]{64}',reference['sha256']), 'invalid atlas seed reference')
    require(isinstance(m.get('signature'),str) and re.fullmatch('[0-9a-f]{64}',m['signature']), 'invalid atlas read signature')
    return {'ordinal':ordinal,'pixels':pixels,'scope':ATLAS_READ_SCOPE,'read_validation_mask':mask}

def atlas_read_source_relation(a0, b0, probe, body, width, height):
    validate_clean_a0(a0,body)
    require('MKS_READ_' not in b0 and 'mks_read_' not in b0,'probe symbols present in B0 source')
    require(strip_capture_insertions(probe,'MKS_READ_') == b0,'probe differs beyond three B0 insertions')
    require(probe == atlas_read_probe_source(b0,width,height),'probe insertion semantics differ from actual UV/half recorder')
    for source in (b0,probe):
        code=re.sub(r'//[^\n]*|/\*.*?\*/',' ',source,flags=re.DOTALL)
        require(re.findall(r'\b(texture[A-Za-z0-9_]*|texelFetch[A-Za-z0-9_]*)\s*\(',code) == ['textureLod'],
                'consumer source must retain sole textureLod')
    pattern=r'\btextureLod\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*0\.0\s*\)'
    calls=list(re.finditer(pattern,body))
    require(len(calls) == 1,'unsupported original atlas consumer sample')
    call=calls[0]; replacement=f'textureLod({call[1]}, mks_cache_uv(), 0.0)'
    modified=body[:call.start()]+replacement+body[call.end():]
    require(b0.count(modified) == 1,'B0 does not contain exact coordinate-replaced original body')
    helper=(f'layout(std430,binding=0) readonly restrict buffer mks_cache_block {{ highp uint mks_cache_words[{width*height*3}]; }};\n'
        'highp vec2 mks_cache_uv() {\nuvec2 mks_cache_p=uvec2(gl_FragCoord.xy);\n'
        f'uint mks_cache_i=(mks_cache_p.y*{width}u+mks_cache_p.x)*3u;\n'
        'highp vec2 mks_cache_loaded=uintBitsToFloat(uvec2(mks_cache_words[mks_cache_i],mks_cache_words[mks_cache_i+1u]));\n'
        'return mks_cache_loaded;\n}\n')
    require(b0.count(helper) == 1 and len(re.findall(r'\bmks_cache_uv\b',b0)) == 2 and
            len(re.findall(r'\bmks_cache_loaded\b',b0)) == 2 and len(re.findall(r'\bmks_cache_words\b',b0)) == 3,
            'B0 readonly atlas helper differs or has additional uses')
    require('layout(yuv) out highp vec3 out_color;\n' in b0,'B0 is not archived YUV candidate source')
    return {'probe_to_b0':'exact-three-insertions','b0_atlas_load':'exact-unconditional-readonly-helper',
        'b0_original_body':'exact-sole-coordinate-replacement','b0_full_transform':'not-independently-replayed',
        'scope':ATLAS_READ_SOURCE_SCOPE}

def atlas_read_probe_source(b0, width, height):
    globals_=('// MKS_READ_GLOBALS_BEGIN\n'
        f'layout(std430,binding=1) coherent restrict buffer mks_read_block {{ highp uint mks_read_words[{width*height*4}]; }};\n'
        'uniform highp int mks_read_mode;\nhighp vec2 mks_read_uv;\nhighp uint mks_read_sites=0u;\n'
        '// MKS_READ_GLOBALS_END\n')
    site='// MKS_READ_SITE_BEGIN\nmks_read_uv=mks_cache_loaded;\nmks_read_sites++;\n// MKS_READ_SITE_END\n'
    tail=('// MKS_READ_TAIL_BEGIN\nuvec2 mks_read_p=uvec2(gl_FragCoord.xy);\n'
        f'uint mks_read_i=(mks_read_p.y*{width}u+mks_read_p.x)*4u;\n'
        'uint mks_read_old=atomicAdd(mks_read_words[mks_read_i],1u);\n'
        'if(mks_read_old==0u) {\n'
        'if(mks_read_mode==0) {mks_read_words[mks_read_i+1u]=floatBitsToUint(mks_read_uv.x);'
        'mks_read_words[mks_read_i+2u]=floatBitsToUint(mks_read_uv.y);mks_read_words[mks_read_i+3u]=mks_read_sites;}\n'
        'else if(mks_read_mode==1) {mks_read_words[mks_read_i+1u]=floatBitsToUint(mks_rgb.r);'
        'mks_read_words[mks_read_i+2u]=floatBitsToUint(mks_rgb.g);mks_read_words[mks_read_i+3u]=floatBitsToUint(mks_rgb.b);}\n'
        'else {atomicOr(mks_read_words[mks_read_i],0x80000000u);}\n}\n'
        'if(mks_read_sites!=1u) atomicOr(mks_read_words[mks_read_i],0x80000000u);\n'
        '// MKS_READ_TAIL_END\n')
    require(b0.count('highp vec2 mks_cache_uv() {\n') == 1 and b0.count('return mks_cache_loaded;\n') == 1 and
            b0.endswith('\n}'),'unsupported B0 probe insertion locations')
    probe=b0.replace('highp vec2 mks_cache_uv() {\n',globals_+'highp vec2 mks_cache_uv() {\n')
    probe=probe.replace('return mks_cache_loaded;\n',site+'return mks_cache_loaded;\n')
    return probe[:-1]+tail+'}'

def atlas_read_signature(raw, layout, width, height, generation):
    parts=[raw[key] for key in ('seed_material','a0_fragment','vertex')]
    parts += [json.dumps(layout,separators=(',',':')).encode(),raw['baseline_vertices'],struct.pack('<QQQ',width,height,generation)]
    digest=hashlib.sha256()
    for part in parts:
        digest.update(struct.pack('<Q',len(part)));digest.update(part)
    return digest.hexdigest()

def validate_atlas_read_uniforms(a0, b0, material):
    pattern=r'\buniform\s+(?:(?:highp|mediump|lowp)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[\s*([0-9]+)\s*\])?\s*;'
    all_declarations=[]
    for role,source in (('A0',a0),('B0',b0)):
        code=re.sub(r'//[^\n]*|/\*.*?\*/',' ',source,flags=re.DOTALL)
        declarations=re.findall(pattern,code)
        require(len(declarations) == len(re.findall(r'\buniform\b',code)), 'unsupported '+role+' uniform/UBO declaration')
        all_declarations.append(declarations)
    require(all_declarations[0] == all_declarations[1], 'B0 original uniforms differ from A0')
    sampler_type='usampler2D' if material['format_type'] == 3 else 'isampler2D' if material['format_type'] == 4 else 'sampler2D'
    samplers=[decl for decl in all_declarations[0] if 'sampler' in decl[0]]
    require(len(samplers) == 1 and samplers[0][0] == sampler_type and not samplers[0][2], 'consumer requires exactly one matching normal 2D sampler')
    declarations={name:(glsl_type,int(array or '1')) for glsl_type,name,array in all_declarations[0] if 'sampler' not in glsl_type}
    require(len(declarations) == material['num_variables'] == len(all_declarations[0])-1, 'uniform material declaration count differs')
    for var in material['variables']:
        if var['dim_m'] > 1:
            require(var['type'] == 3 and var['dim_v'] >= 2, 'unsupported nonfloat matrix material')
            glsl='mat'+str(var['dim_m'])+('x'+str(var['dim_v']) if var['dim_m'] != var['dim_v'] else '')
        else:
            glsl={1:('int','ivec'),2:('uint','uvec'),3:('float','vec')}[var['type']]
            glsl=glsl[0] if var['dim_v'] == 1 else glsl[1]+str(var['dim_v'])
        require(declarations.get(var['name']) == (glsl,var['dim_a']), 'uniform material type/name does not match source')

def analyze_atlas_read(path, m, seed_root):
    info=atlas_read_metadata(m)
    require(seed_root is not None,'schema10 requires explicit complete schema9 seed root')
    seed_root=Path(seed_root).resolve()
    seed_path=safe_file(seed_root,m['seed_reference']['manifest'])
    require(hashlib.sha256(seed_path.read_bytes()).hexdigest() == m['seed_reference']['sha256'],'schema9 seed manifest SHA differs')
    seed=analyze(seed_path)
    require(seed.get('schema') == 9 and seed.get('status') == 'captured-floats-bit-equal','schema9 seed anchor did not independently pass')
    sm=load_json(seed_path)
    for key,seed_key in (('pid','pid'),('seed_capture_id','capture_id'),('generation','generation'),
                         ('seed_frame_id','frame_id'),('seed_frame_token','frame_token')):
        require(m[key] == sm[seed_key],'atlas read seed identity differs: '+key)
    require(abs(m['seed_pts']-sm['source_pts']) <= 2e-6 and m['width'] == sm['width'] and m['height'] == sm['height'],
            'atlas read seed PTS/size differs')
    files=m.get('files')
    require(isinstance(files,dict) and set(files) == set(ATLAS_READ_FILES),'invalid atlas read file set')
    prefix=f"mks-uv-atlas-read-{m['pid']}-{m['capture_id']}"+('.diagnostic-invalid' if m['status'] == 'diagnostic-invalid' else '')
    require(all(files[k] == prefix+ATLAS_READ_SUFFIXES[k] for k in ATLAS_READ_FILES),'atlas read filenames disagree with identity')
    sizes={k:m['rgba_words']*4 for k in ('a0','uv','half')}
    sizes.update(seed_atlas=m['atlas_words']*4,android=m['android_words']*4,baseline_vertices=m['vertex_layout']['byte_size'])
    raw={};archived={};sources={}
    require(sys.byteorder == 'little','atlas reader requires little-endian host')
    for key in ATLAS_READ_FILES:
        file=safe_file(path.parent,files[key]);size=file.stat().st_size
        limit=256*1024 if key in ('original_body','seed_material','current_material') else 4*1024*1024
        require(size == sizes[key] if key in sizes else 0 < size <= limit,'invalid atlas read byte size: '+key)
        data=file.read_bytes();require(len(data) == size,'atlas read file changed: '+key)
        raw[key]=data;archived[key]={'file':files[key],'bytes':size,'sha256':hashlib.sha256(data).hexdigest()}
        if key not in sizes and key not in ('seed_material','current_material'):
            try:sources[key]=data.decode('utf-8')
            except UnicodeDecodeError as error:raise InvalidCapture('non-UTF8 atlas read source') from error
            require(bool(sources[key].strip()) if key == 'original_body' else '#version' in sources[key] and 'void main' in sources[key],
                    'invalid atlas read source: '+key)
        if 'sha256' in m:
            require(isinstance(m['sha256'],dict) and m['sha256'].get(key) == archived[key]['sha256'],'atlas read archived SHA differs: '+key)
    materials={}
    for key in ('seed_material','current_material'):
        try:
            material=json.loads(raw[key].decode('utf-8'),object_pairs_hook=unique_object,
                parse_constant=lambda value: (_ for _ in ()).throw(InvalidCapture('nonfinite material JSON: '+value)))
        except (UnicodeError,ValueError) as error:
            raise InvalidCapture('invalid material JSON: '+key+': '+str(error)) from error
        materials[key]=atlas_read_material(material)
    require(raw['seed_material'] == raw['current_material'],'current signature material differs from seed')
    computed=atlas_read_signature(raw,m['vertex_layout'],m['width'],m['height'],m['generation'])
    require(computed == m['signature'],'atlas read signature digest differs')
    for key,seed_key in (('a0_fragment','a0_fragment'),('vertex','vertex'),('original_body','original_body'),
                         ('baseline_vertices','baseline_vertices'),('seed_atlas','atlas')):
        require(archived[key]['sha256'] == seed['archived_files'][seed_key]['sha256'],'consumer source/data differs from schema9 seed: '+key)
    require(m['vertex_layout'] == sm['vertex_layout'],'consumer vertex layout differs from seed')
    relation=atlas_read_source_relation(*(sources[k] for k in ('a0_fragment','b0_fragment','probe_fragment','original_body')),m['width'],m['height'])
    validate_atlas_read_uniforms(sources['a0_fragment'],sources['b0_fragment'],materials['seed_material'])
    geometry=quad_payload_relation(raw['baseline_vertices'],raw['baseline_vertices'],m['vertex_layout'],False,sources['vertex'])
    words={key:memoryview(raw[key]).cast('I') for key in ('a0','uv','half','seed_atlas','android')}
    uv=compare_atlas_consumer_uv(words['uv'],words['seed_atlas'],m['width'],m['height'])
    half=compare_atlas_consumer_half(words['half'],words['a0'],m['width'],m['height'])
    bad_uv=uv['comparison']['pixels_with_bit_mismatches']
    bad_half=half['comparison']['pixels_with_bit_mismatches']
    mask=int(bool(bad_uv)) | (int(bool(bad_half))<<1)
    require(mask == m['read_validation_mask'] and bad_uv == m['bad_uv_pixels'] and bad_half == m['bad_half_pixels'],
            'atlas read producer validation disagrees with raw values')
    for p in range(len(words['android'])//7):
        require(words['android'][p*7] == 1 and all(math.isfinite(float32(v)) for v in words['android'][p*7+1:p*7+7]),
                'invalid final atlas reader Android CSC coverage/finite values')
    return {'schema':10,'status':'diagnostic-invalid' if mask else 'captured-floats-bit-equal',
        'numeric_status':'captured-float-differences' if mask else 'captured-floats-bit-equal','metadata':info,
        'identity':{key:m[key] for key in ('pid','capture_id','generation','ordinal','frame_id','frame_token','source_pts','seed_capture_id',
            'cache_id','cache_generation','cache_storage_buffer','cache_storage_offset','cache_storage_size','renderer_id','renderer_generation')},
        'signature':computed,'source_relation':relation,'vertex_evidence':geometry,'uv_analysis':uv,'half_analysis':half,
        'archived_files':archived,'seed_reference':m['seed_reference'],'within_frame_fullscreen_uv_half_equal':not bool(mask),
        'cross_pts_reuse_validated':False,'quality_pass':False,'diagnostic_only':True,'b0_numerical_equivalence_established':False,
        'yuv_equality_measured':False,'read_validation_mask':mask,'bad_uv_pixels':bad_uv,'bad_half_pixels':bad_half,
        'limitations':LIMITS+[ATLAS_READ_SOURCE_SCOPE,ATLAS_SIGNATURE_SCOPE,
            'GPU/EGL owner and binding validation remains native producer evidence. Full-screen UV/half RGB is instrumented; Android CSC is auxiliary ROI only.']}

def validate_atlas_read_pair(first_manifest, second_manifest, seed_root):
    first=analyze(Path(first_manifest),seed_root=seed_root);second=analyze(Path(second_manifest),seed_root=seed_root)
    require(all(r['schema'] == 10 and r['status'] == 'captured-floats-bit-equal' for r in (first,second)),
            'atlas reuse pair contains invalid or differing observation')
    a,b=first['identity'],second['identity']
    require(a['ordinal'] == 1 and b['ordinal'] == 2,'atlas reuse ordinals must be 1 then 2')
    for key in ('pid','generation','seed_capture_id','cache_id','cache_generation','cache_storage_buffer',
                'cache_storage_offset','cache_storage_size','renderer_id','renderer_generation'):
        require(a[key] == b[key],'atlas reuse identity changed: '+key)
    require(a['capture_id'] != b['capture_id'] and a['frame_id'] != b['frame_id'] and b['frame_token'] > a['frame_token'] and
            abs(a['source_pts']-b['source_pts']) > 2e-6,'second reuse observation is not a fresh frame/receipt')
    require(first['seed_reference'] == second['seed_reference'] and first['signature'] == second['signature'],'reuse seed/signature changed')
    for key in ('seed_atlas','a0_fragment','b0_fragment','probe_fragment','vertex','original_body','baseline_vertices','seed_material','current_material'):
        require(first['archived_files'][key]['sha256'] == second['archived_files'][key]['sha256'],'reuse archived state changed: '+key)
    return {'status':'captured-floats-bit-equal','schema':10,'cross_pts_reuse_validated':True,
        'scope':'Two instrumented full-screen UV/half observations at distinct PTS with archived cache/source/signature identity. Native ownership and cache binding are producer assertions; no uninstrumented B0, YUV, production or panel equality.',
        'first':first,'second':second,'quality_pass':False,'yuv_equality_measured':False}

def atlas_metadata(m):
    require(type(m.get('schema')) is int and m['schema'] == 9, 'invalid atlas schema')
    require(m.get('scope') == ATLAS_SCOPE and m.get('readback_representation') == ATLAS_REPRESENTATION and
            m.get('instrumentation_scope') == ATLAS_INSTRUMENTATION, 'invalid atlas evidence scope')
    require(m.get('status') in ('complete','diagnostic-invalid'), 'atlas capture not complete')
    for key in ('pid','capture_id','generation','frame_id','frame_token'):
        integer(m.get(key),key,1)
    source = finite(m.get('source_pts'),'source_pts')
    require(source >= 0, 'invalid atlas source PTS')
    for key in ('target_pts','current_pts'):
        value = finite(m.get(key),key)
        require(value >= 0 and abs(value-source) <= 2e-6, 'atlas frame PTS differs')
    width = integer(m.get('width'),'atlas width',1,16384)
    height = integer(m.get('height'),'atlas height',1,16384)
    pixels = width*height
    require(pixels <= MAX_ATLAS_PIXELS and type(m.get('pixels')) is int and m['pixels'] == pixels,
            'invalid atlas pixel count or budget')
    for key,count in (('rgba_words',pixels*4),('atlas_words',pixels*3)):
        require(type(m.get(key)) is int and m[key] == count, 'invalid atlas '+key)
    require(m.get('byte_order') == 'little' and type(m.get('read_format')) is int and m['read_format'] == 6408 and
            type(m.get('read_type')) is int and m['read_type'] == 5126, 'unsupported atlas readback format')
    require(m.get('draw_order') == ['a0_before','atlas_a','a0_after'], 'invalid atlas draw order')
    for key in ('draw_ok','readback_ok','half_exact'):
        require(isinstance(m.get(key),list) and len(m[key]) == 3 and all(value is True for value in m[key]),
                'atlas stage incomplete: '+key)
    for key in ('source_abi_ok','fence_signaled','atlas_complete','baseline_ok',
                'android_swap_succeeded','android_fence_signaled'):
        require(m.get(key) is True, 'atlas missing true '+key)
    require(m.get('android_status') == 'ready', 'atlas Android stage not ready')
    tokens = m.get('program_tokens')
    require(isinstance(tokens,list) and len(tokens) == 3, 'invalid atlas program tokens')
    tokens = [decimal_token(value,'atlas program token') for value in tokens]
    require(tokens[0] == tokens[2], 'A0 replay program token differs')
    require(tokens[0] != tokens[1], 'A0 and instrumented atlas require distinct program tokens')
    framebuffers = m.get('framebuffer')
    require(isinstance(framebuffers,list) and len(framebuffers) == 3, 'invalid atlas framebuffers')
    for value in framebuffers:
        integer(value,'atlas framebuffer',1,0xffffffff)
    require(len(set(framebuffers)) == 1, 'atlas stages use different framebuffers')
    epochs = [decimal_token(m.get('finish_epoch'),'atlas finish epoch',minimum=0)]
    for key in ('draw_epoch_before','draw_epoch_after','readback_epoch_before','readback_epoch_after'):
        require(isinstance(m.get(key),list) and len(m[key]) == 3, 'invalid atlas '+key)
        epochs += [decimal_token(value,key,minimum=0) for value in m[key]]
    require(len(set(epochs)) == 1, 'atlas error epochs differ')
    require(isinstance(m.get('bad_half_components'),list) and len(m['bad_half_components']) == 3 and
            all(type(v) is int and v == 0 for v in m['bad_half_components']) and
            type(m.get('bad_atlas_pixels')) is int and m['bad_atlas_pixels'] == 0, 'invalid atlas data declared')
    mask = integer(m.get('anchor_validation_mask'),'anchor validation mask',0,3)
    reasons = [reason for bit,reason in ATLAS_REASONS.items() if mask & bit]
    require(m.get('anchor_validation_reasons') == reasons and type(m.get('anchor_equal')) is bool and
            m['anchor_equal'] == (mask == 0), 'inconsistent atlas validation metadata')
    require(m['status'] == ('complete' if mask == 0 else 'diagnostic-invalid') and
            m.get('comparison_pass') == ('unknown' if mask == 0 else 'refused'), 'invalid atlas completion claim')
    for key in ('mismatches_before_atlas','mismatches_before_after'):
        integer(m.get(key),key,0,pixels*4)
    roi = m.get('android_roi')
    require(isinstance(roi,dict) and set(roi) == {'x','y','w','h'}, 'invalid atlas Android ROI')
    x,y = (integer(roi[key],'Android ROI '+key,0) for key in ('x','y'))
    w,h = (integer(roi[key],'Android ROI '+key,1) for key in ('w','h'))
    require(x+w <= width and y+h <= height and w*h <= MAX_PIXELS and
            type(m.get('android_words')) is int and m['android_words'] == w*h*7, 'invalid atlas Android size')
    validate_vertex_layout(m.get('vertex_layout'),width,height)
    return {'width':width,'height':height,'pixels':pixels,'vertex_layout':m['vertex_layout'],
            'status':m['status'],'anchor_validation_mask':mask,'android_roi':roi,
            'scope':ATLAS_SCOPE,'readback_representation':ATLAS_REPRESENTATION,
            'instrumentation_scope':ATLAS_INSTRUMENTATION}

def analyze_atlas(path, m):
    info = atlas_metadata(m)
    files = m.get('files')
    require(isinstance(files,dict) and set(files) == set(ATLAS_FILES), 'invalid atlas file set')
    prefix = f"mks-yuv-atlas-{m['pid']}-{m['capture_id']}"
    if m['status'] == 'diagnostic-invalid':
        prefix += '.diagnostic-invalid'
    require(all(files[key] == prefix+ATLAS_SUFFIXES[key] for key in ATLAS_FILES),
            'atlas file names disagree with capture identity')
    sizes = {key:m['rgba_words']*4 for key in ('a0_before','atlas_a','a0_after')}
    sizes.update(atlas=m['atlas_words']*4,android=m['android_words']*4,
                 baseline_vertices=m['vertex_layout']['byte_size'])
    archived, raw, sources = {}, {}, {}
    require(sys.byteorder == 'little', 'atlas analyzer requires a little-endian host')
    for key in ATLAS_FILES:
        file = safe_file(path.parent,files[key]); size = file.stat().st_size
        require(size == sizes[key] if key in sizes else 0 < size <= (256*1024 if key == 'original_body' else 4*1024*1024),
                'invalid atlas byte size: '+key)
        data = file.read_bytes()
        require(len(data) == size, 'atlas file changed while reading: '+key)
        archived[key] = {'file':files[key],'bytes':size,'sha256':hashlib.sha256(data).hexdigest()}
        if key in sizes:
            raw[key] = data if key == 'baseline_vertices' else memoryview(data).cast('I')
        else:
            try:
                sources[key] = data.decode('utf-8')
            except UnicodeDecodeError as error:
                raise InvalidCapture('non-UTF8 atlas source: '+key) from error
            require(bool(sources[key].strip()) if key == 'original_body' else
                    '#version' in sources[key] and 'void main' in sources[key], 'invalid atlas source: '+key)
        if 'sha256' in m:
            require(isinstance(m['sha256'],dict) and m['sha256'].get(key) == archived[key]['sha256'],
                    'atlas archived hash mismatch: '+key)
    source_relation = atlas_source_relation(sources['a0_fragment'],sources['atlas_fragment'],sources['original_body'])
    geometry = quad_payload_relation(raw['baseline_vertices'],raw['baseline_vertices'],m['vertex_layout'],False,sources['vertex'])
    coverage = validate_atlas_uv(raw['atlas'],m['width'],m['height'])
    android = raw['android']
    for pixel in range(len(android)//7):
        require(android[pixel*7] == 1, 'invalid final Android CSC coverage')
        require(all(math.isfinite(float32(word)) for word in android[pixel*7+1:pixel*7+7]),
                'nonfinite final Android CSC float')
    numeric = compare_atlas_readbacks(*(raw[key] for key in ('a0_before','atlas_a','a0_after')),m['width'],m['height'])
    counts = numeric['comparisons']
    before_after = counts['A0_before_vs_after']['bit_mismatches']
    before_atlas = counts['A0_before_vs_atlas_A']['bit_mismatches']
    mask = int(before_after != 0) | (int(before_atlas != 0) << 1)
    require(mask == m['anchor_validation_mask'] and before_after == m['mismatches_before_after'] and
            before_atlas == m['mismatches_before_atlas'], 'atlas producer validation disagrees with readbacks')
    result = {'schema':9,'status':'diagnostic-invalid' if mask else 'captured-floats-bit-equal',
        'numeric_status':numeric['status'],'identity':{key:m[key] for key in ('pid','capture_id','generation','frame_id','frame_token','source_pts','current_pts','target_pts')},
        'pixels':m['pixels'],'atlas_metadata':info,'readback_analysis':numeric,'atlas_coverage':coverage,
        'source_relation':source_relation,'vertex_evidence':geometry,'archived_files':archived,
        'anchor_validation_mask':mask,'anchor_validation_reasons':[value for bit,value in ATLAS_REASONS.items() if mask & bit],
        'diagnostic_only':True,'quality_pass':False,'production_equivalence_established':False,
        'limitations':LIMITS+['Only full-screen RGB readback is compared. Android CSC is captured only in its ROI and is auxiliary evidence.',
            'RGBA/FLOAT values are exact binary16 expansions, not physical RGBA16F storage bytes.',
            'Atlas UV/count capture instruments the middle shader and may alter compilation. Native FBO, program, fence and epoch metadata are producer assertions.']}
    return result

def analyze(path: Path, seed_root=None):
    path = path.resolve()
    m = load_json(path)
    require(isinstance(m, dict), 'manifest is not an object')
    schema = m.get('schema')
    if type(schema) is int and schema == 10:
        return analyze_atlas_read(path,m,seed_root)
    if type(schema) is int and schema == 9:
        return analyze_atlas(path,m)
    require(type(schema) is int and schema in (1,2,3,4,5,6,7,8), 'unsupported schema')
    repetitions = 1 if schema in (1,7,8) else 2
    stride = 26 if schema >= 3 else 14
    baseline_prefix = 'A0' if schema == 4 else 'A'
    repeat_info = repeat_metadata(m) if schema >= 2 else None
    sample_info = sample_tap_metadata(m) if schema >= 3 else None
    invariant_info = invariant_metadata(m) if schema == 4 else None
    oracle_info = oracle_metadata(m) if schema in (5,6,7,8) else None
    probe_info = oracle_probe_metadata(m) if schema in (6,7,8) else None
    quad_info = quad_order_metadata(m) if schema == 8 else None
    diagnostic_invalid = schema in (6,7,8) and m.get('status') == 'diagnostic-invalid'
    require(m.get('status') == 'complete' or diagnostic_invalid, 'capture not complete')
    integer(m.get('pid'), 'pid', 1)
    integer(m.get('capture_id'), 'capture_id', 1)
    integer(m.get('generation'), 'generation', 1)
    source = finite(m.get('source_pts'), 'source_pts')
    target = finite(m.get('target_pts'), 'target_pts')
    require(source >= 0 and target >= 0 and abs(source-target) <= 2e-6, 'source and target PTS differ')
    require(abs(finite(m.get('current_pts'), 'current_pts')-source) <= 2e-6, 'current PTS differs')
    require(m.get('byte_order') == 'little', 'byte order must be little')
    require(m.get('lib_status') == 'complete' and m.get('android_status') == 'ready', 'stage not complete')
    for key in ('lib_candidate_ok', 'lib_baseline_ok', 'android_swap_succeeded',
                'lib_fence_signaled', 'android_fence_signaled'):
        require(m.get(key) is True, 'missing true ' + key)
    shader_hash = m.get('shader_body_hash')
    decimal_token(shader_hash, 'shader_body_hash')
    roi = m.get('roi')
    require(isinstance(roi, dict), 'missing ROI')
    x, y = (integer(roi.get(k), k, 0, 1 << 20) for k in ('x', 'y'))
    w, h = (integer(roi.get(k), k, 1, MAX_PIXELS) for k in ('w', 'h'))
    tw = integer(m.get('target_width'), 'target_width', 1, 1 << 20)
    th = integer(m.get('target_height'), 'target_height', 1, 1 << 20)
    require(x+w <= tw and y+h <= th, 'ROI outside target')
    pixels = w*h
    require(pixels <= MAX_PIXELS, 'ROI too large')
    files = m.get('files')
    expected_files = files_for_schema(schema)
    require(isinstance(files, dict) and all(k in files for k in expected_files), 'missing files')
    require(all(isinstance(files[k], str) for k in expected_files), 'invalid file names')
    require(len(set(files[k] for k in expected_files)) == len(expected_files), 'aliased files')
    prefix = f"mks-yuv-compare-{m['pid']}-{m['capture_id']}"
    if diagnostic_invalid:
        prefix += '.diagnostic-invalid'
    suffixes = {'lib':'.lib.bin','android':'.android.bin','candidate':'.candidate.glsl','baseline':'.baseline.glsl','vertex':'.vertex.glsl',
                'original_body':'.original-body.glsl','candidate_vertex':'.candidate-vertex.glsl',
                'oracle_probe':'.oracle-probe.bin','baseline_vertices':'.baseline-vertices.bin',
                'candidate_vertices':'.candidate-vertices.bin'}
    require(all(files[k] == prefix+suffixes[k] for k in expected_files), 'file names disagree with capture identity')
    archived = {}
    payload = {}
    source_text = {}
    binary_words = {'lib':pixels*stride*repetitions,'android':pixels*7}
    if schema in (6,7,8):
        binary_words['oracle_probe'] = pixels*10*repetitions
    if schema == 8:
        for key in ('baseline_vertices','candidate_vertices'):
            binary_words[key] = quad_info['quad_vertex_layout']['byte_size']//4
    for key in expected_files:
        p = safe_file(path.parent, files[key])
        expected = binary_words[key]*4 if key in binary_words else None
        size = p.stat().st_size
        require(size > 0 and (size == expected if expected else size <= 4*1024*1024), 'invalid byte size: ' + key)
        data = p.read_bytes()
        require(len(data) == size, 'file changed while reading: ' + key)
        archived[key] = {'file': files[key], 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        if key in binary_words:
            payload[key] = data if key in ('baseline_vertices','candidate_vertices') else struct.unpack('<' + str(len(data)//4) + 'I', data)
        else:
            try:
                text = data.decode('utf-8')
            except UnicodeDecodeError as e:
                raise InvalidCapture('non-UTF8 shader: '+key) from e
            require(bool(text.strip()) if key == 'original_body' else '#version' in text and 'void main' in text,
                    'invalid shader source: ' + key)
            source_text[key] = text
        if 'sha256' in m:
            require(isinstance(m['sha256'], dict) and m['sha256'].get(key) == archived[key]['sha256'], 'shader/payload hash mismatch: ' + key)
    for key, words_per_pixel in (('lib',stride*repetitions),('android',7)):
        require(integer(m.get(key+'_words'),key+'_words',1) == pixels*words_per_pixel, 'wrong word count: '+key)
    if schema in (6,7,8):
        require(probe_info['uv_oracle_probe_words'] == pixels*10*repetitions, 'wrong oracle probe word count')
    lib, android = payload['lib'], payload['android']
    coverage = []
    for repetition in range(repetitions):
        base = repetition*pixels*stride
        for i in range(pixels):
            offset = base+i*stride
            counts = {'candidate':lib[offset],'baseline_rgb':lib[offset+10]}
            if schema >= 3:
                counts[baseline_prefix+'_sample_site_count'] = lib[offset+25]
                if schema not in (6,7,8):
                    counts['B_sample_site_count'] = lib[offset+19]
            if any(value != 1 for value in counts.values()):
                if len(coverage) < 10:
                    coverage.append({'repetition':repetition+1,'x':x+i%w,'y':y+i//w,**counts})
    for i in range(pixels):
        if android[i*7] != 1 and len(coverage) < 10:
            csc_role = 'final_A1_CSC' if schema in (7,8) else 'final_A02_CSC' if schema == 4 else 'final_A2_CSC' if schema >= 2 else 'baseline_csc'
            coverage.append({'x':x+i%w,'y':y+i//w,csc_role:android[i*7]})
    require(not coverage, 'coverage not exactly one: '+json.dumps(coverage))
    probe_result = None
    if schema in (6,7,8):
        require_schema6_render_finite(lib,android,pixels,w,(x,y),repetitions)
        probe_result = analyze_oracle_probe(lib,payload['oracle_probe'],pixels,w,(x,y),oracle_info['uv_oracle_use_a'],repetitions)
        if (probe_result['preconditions_valid'] != probe_info['oracle_preconditions_valid'] or
            probe_result['cpu_validation_mask'] != probe_info['oracle_cpu_validation_mask']):
            raise InvalidCapture('oracle probe observations contradict manifest validation',diagnostic=probe_result)
    quad_relation = None
    if schema == 8:
        quad_relation = quad_payload_relation(payload['baseline_vertices'],payload['candidate_vertices'],
            quad_info['quad_vertex_layout'],quad_info['quad_order_reverse'],source_text['vertex'])
    def vec(words, stride, offset, base=0, components=3):
        return [words[base+i*stride+offset+c] for i in range(pixels) for c in range(components)]
    last = (repetitions-1)*pixels*stride
    pairs = {
        'pre_rgb': compare_vectors(vec(lib,stride,11,last),vec(lib,stride,1,last),w,(x,y),'RGB'),
        'half_rgb': compare_vectors(vec(android,7,1),vec(lib,stride,4,last),w,(x,y),'RGB'),
        'yuv': compare_vectors(vec(android,7,4),vec(lib,stride,7,last),w,(x,y),('Y','Cb','Cr')),
    }
    roles = {'pre_rgb':('baseline_pre_store','candidate_pre_half'),
             'half_rgb':('baseline_sampled_rgb16f','candidate_emulated_half'),
             'yuv':('baseline_csc_yuv','candidate_csc_yuv')}
    if schema == 4:
        roles = {'pre_rgb':('A02_pre_store','B2_pre_half'),
                 'half_rgb':('A02_sampled_rgb16f','B2_emulated_half'),
                 'yuv':('A02_csc_yuv','B2_csc_yuv')}
    for name, result in pairs.items():
        result['left_role'], result['right_role'] = roles[name]
    repeat_result = None
    all_results = list(pairs.values())
    if schema >= 2 and schema not in (7,8):
        samples = {}
        for repetition in range(2):
            base = repetition*pixels*stride
            samples['B'+str(repetition+1)] = {stage:vec(lib,stride,offset,base)
                    for stage,offset in (('pre_rgb',1),('half_rgb',4),('yuv',7))}
            samples[baseline_prefix+str(repetition+1)] = {'pre_rgb':vec(lib,stride,11,base)}
        samples[baseline_prefix+'2'].update(half_rgb=vec(android,7,1),yuv=vec(android,7,4))
        repeat_result = compare_repeats(samples,w,(x,y),baseline_prefix)
        all_results += [s for group in repeat_result['comparisons'].values() for s in group.values()]
    elif schema in (7,8):
        repeat_result = {'status':'not-measured-single-pair','captured_repeatability_confirmed':False,'scope':SINGLE_PAIR_SCOPE}
    sample_result = None
    if schema >= 3:
        taps = {}
        for repetition in range(repetitions):
            base = repetition*pixels*stride
            for role, uv, rgb in (('B',14,16),(baseline_prefix,20,22)):
                taps[role+str(repetition+1)] = {'uv':vec(lib,stride,uv,base,components=2),
                                               'sample_rgb':vec(lib,stride,rgb,base)}
        sample_result = compare_single_pair_taps(taps,w,(x,y)) if schema in (7,8) else compare_sample_taps(taps,w,(x,y),baseline_prefix)
        all_results += [s for group in sample_result['comparisons'].values() for s in group.values()]
    invalid = any(v['nonfinite_components'] for v in all_results)
    differs = any(v['bit_mismatches'] for v in all_results)
    result = {'schema':schema,'status':'invalid-nonfinite' if invalid else 'captured-float-differences' if differs else 'captured-floats-bit-equal',
            'capture_id':m['capture_id'],'generation':m['generation'],'pid':m['pid'],
            'source_pts':source,'target_pts':target,'roi':roi,'pixels':pixels,
            'shader_body_hash':shader_hash,'files':archived,'comparisons':pairs,'limitations':LIMITS}
    if schema >= 2:
        result.update(repeat_metadata=repeat_info,repeat_analysis=repeat_result,
                      current_ab=baseline_prefix+'2 versus B2; '+baseline_prefix+'1 stored RGB16F sample and CSC YUV unavailable')
    if schema in (7,8):
        result.update(single_pair_metadata=repeat_info,current_ab='A1 versus B1; final Android CSC samples A1.',
                      program_instance_scope=SINGLE_PAIR_SCOPE,within_capture_repeatability_measured=False)
    if schema >= 3:
        result.update(sample_tap_metadata=sample_info,sample_tap_analysis=sample_result,
                      original_body_relation={'status':'not-independently-verified',
                        'scope':'Original body and actual instrumented shader sources are archived with SHA256. Native body hashes and producer linkage assertions do not independently prove the transformation or unmodified-shader equivalence.'},
                      limitations=LIMITS+[SAMPLE_TAP_SCOPE])
    if schema == 4:
        result.update(invariant_metadata=invariant_info,
            invariant_vertex_relation=invariant_vertex_relation(source_text['vertex'],source_text['candidate_vertex'],
                                                                 invariant_info['invariant_uv_identifier']),
            fragment_source_difference=source_difference(source_text['baseline'],source_text['candidate'],'A0.fragment','B.fragment'),
            baseline_control_relation={'status':'not-independently-verified',
                'baseline_fragment_sha256':archived['baseline']['sha256'],
                'baseline_vertex_sha256':archived['vertex']['sha256'],
                'scope':'A0 fragment/vertex sources are archived. Matching an earlier inv=0 control requires independent source comparison; producer assertions do not prove that anchor.'},
            limitations=LIMITS+[SAMPLE_TAP_SCOPE,INVARIANT_SCOPE])
    if schema in (5,6,7,8):
        result.update(oracle_metadata=oracle_info,
            oracle_uv_relation=oracle_uv_relation(sample_result,oracle_info['uv_oracle_use_a'],('ab1',) if schema in (7,8) else ('ab1','ab2')) if not diagnostic_invalid
                else {'status':'unavailable-diagnostic-invalid','scope':PROBE_SCOPE},
            fragment_source_difference=source_difference(source_text['baseline'],source_text['candidate'],'A.fragment','B.oracle-framework.fragment'),
            baseline_control_relation={'status':'not-independently-verified',
                'baseline_fragment_sha256':archived['baseline']['sha256'],
                'baseline_vertex_sha256':archived['vertex']['sha256'],
                'scope':'Original/oracle/original controls require independent same-APK, same-media/frame source and captured-stage comparison. This manifest alone does not verify the cross-round anchor.'},
            limitations=LIMITS+[SAMPLE_TAP_SCOPE,ORACLE_SCOPE])
    if schema in (6,7,8):
        result.update(oracle_probe_metadata=probe_info,oracle_probe_analysis=probe_result,
                      oracle_preconditions_valid=probe_result['preconditions_valid'],
                      diagnostic_only=True,causal_conclusion_allowed=False,
                      limitations=LIMITS+[SAMPLE_TAP_SCOPE,ORACLE_SCOPE,PROBE_SCOPE])
        if schema in (7,8):
            result['limitations'].append(SINGLE_PAIR_SCOPE)
        if diagnostic_invalid:
            result.update(status='diagnostic-invalid',numeric_status='invalid-nonfinite' if invalid
                          else 'captured-float-differences' if differs else 'captured-floats-bit-equal')
    if schema == 8:
        result.update(quad_order_metadata=quad_info,quad_payload_relation=quad_relation)
        result['limitations'].append(QUAD_ORDER_SCOPE)
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest',type=Path)
    p.add_argument('--output',type=Path)
    p.add_argument('--seed-root',type=Path,help='Complete independent schema9 dependency directory for schema10')
    args=p.parse_args()
    try:
        result=analyze(args.manifest,seed_root=args.seed_root)
        code=0 if result['status']=='captured-floats-bit-equal' else 3
    except (InvalidCapture,OSError) as e:
        result={'schema':1,'status':'invalid-capture','reason':str(e),'limitations':LIMITS}; code=2
        if isinstance(e,InvalidCapture) and e.diagnostic is not None:
            result['diagnostic'] = e.diagnostic
    rendered=json.dumps(result,indent=2,allow_nan=False)+'\n'
    if args.output:
        with args.output.open('x') as f: f.write(rendered)
    print(rendered,end='')
    return code

if __name__=='__main__':sys.exit(main())
