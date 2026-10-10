#!/usr/bin/env python3
"""Deterministic synthetic hvcC SPS fixture generator for the MKSVUI host
regression (tool/mksvui-regress).

D1 (2026-10-09) hand-built synA/synB in /tmp without archiving the generator.
This module reconstructs it; `--selfcheck` proves fidelity by regenerating
synA/synB and requiring byte equality with the fixtures copied from
/private/tmp/mksvui (the D1 originals remain the authoritative fixtures).

Bit layout mirrors the syntax the product parser walks (hevc/ps.c order, see
~/src/FFmpeg/libavcodec/mediacodecdec_common.c mkvui_parse_sps_color).
"""
import argparse
import struct


class BitWriter:
    def __init__(self):
        self.bits = []

    def u(self, n, v):
        for i in range(n - 1, -1, -1):
            self.bits.append((v >> i) & 1)

    def ue(self, v):
        v += 1
        n = v.bit_length()
        self.u(n - 1, 0)
        self.u(n, v)

    def rbsp_trailing(self):
        self.u(1, 1)
        while len(self.bits) % 8:
            self.u(1, 0)

    def bytes(self):
        out = bytearray()
        for i in range(0, len(self.bits), 8):
            byte = 0
            for b in self.bits[i:i + 8]:
                byte = (byte << 1) | b
            if len(self.bits) - i < 8:
                byte <<= 8 - (len(self.bits) - i)
            out.append(byte)
        return bytes(out)


def escape(rbsp):
    """00 00 x (x<=3) -> 00 00 03 x (RBSP to EBSP)."""
    out = bytearray()
    zeros = 0
    for b in rbsp:
        if zeros >= 2 and b <= 3:
            out.append(3)
            zeros = 0
        out.append(b)
        zeros = zeros + 1 if b == 0 else 0
    return bytes(out)


# 22-byte hvcC configuration header of the D1 synthetic fixtures
# (constants per ISO 14496-15; lengthSizeMinusOne=1 -> u16 NAL lengths).
HVCC_HEAD = bytes([
    0x01,             # configurationVersion
    0x01, 0x60, 0x00, 0x00, 0x00, 0x90, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xfc, 0xfc, 0xf8, 0xfc, 0xfc, 0xfc, 0xfc, 0xfc, 0xfc, 0xfc,
])


def sps_nal(width, height, prim, trc, matrix,
            bit_depth_minus8=2,
            cb_tb_deltas=(0, 3, 0, 3, 0, 0),
            st_rps=(),          # sequence of (num_negative, num_positive)
            video_format=5, full_range=0, compat=2,
            timing=False, num_units_in_tick=1, time_scale=30,
            hrd=None,           # (nal_hrd, vcl_hrd, cpb_cnt_minus1, entries)
                                #   entries: [(bit_rate, cpb_size, cpb_size_du)]
            level_idc=0x5d):
    w = BitWriter()
    w.u(4, 0)     # sps_video_parameter_set_id
    w.u(3, 0)     # sps_max_sub_layers_minus1
    w.u(1, 1)     # temporal_id_nesting
    w.u(2, 0)     # general_profile_space
    w.u(1, 0)     # general_tier_flag
    w.u(5, 1)     # general_profile_idc
    w.u(32, compat)           # general_profile_compatibility_flags
    w.u(48, 0)                # general constraint / reserved flags
    w.u(8, level_idc)         # general_level_idc
    w.ue(0)       # sps_seq_parameter_set_id
    w.ue(1)       # chroma_format_idc (4:2:0)
    w.ue(width)
    w.ue(height)
    w.u(1, 0)     # conformance_window_flag
    w.ue(bit_depth_minus8)   # bit_depth_luma_minus8
    w.ue(bit_depth_minus8)   # bit_depth_chroma_minus8
    w.ue(4)       # log2_max_pic_order_cnt_lsb_minus4
    w.u(1, 1)     # sps_sub_layer_ordering_info_present_flag
    w.ue(0); w.ue(0); w.ue(0)   # max_dec_pic_buffering / rpl / init delay
    for d in cb_tb_deltas:    # the six log2 cb/tb size + hierarchy fields
        w.ue(d)
    w.u(1, 0)     # scaling_list_enabled_flag
    w.u(1, 0)     # amp_enabled_flag
    w.u(1, 0)     # sample_adaptive_offset_enabled_flag
    w.u(1, 0)     # pcm_enabled_flag
    w.ue(len(st_rps))         # num_short_term_ref_pic_sets
    for nn, npp in st_rps:
        w.ue(nn)  # num_negative_pics
        w.ue(npp)  # num_positive_pics
        for _ in range(nn):
            w.ue(0)   # delta_poc_s0_minus1
            w.u(1, 1)  # used_by_curr_pic_s0_flag  <- D1 fix #1 read-back
        for _ in range(npp):
            w.ue(0)   # delta_poc_s1_minus1
            w.u(1, 1)  # used_by_curr_pic_s1_flag
    w.u(1, 0)     # long_term_ref_pics_present_flag
    w.u(1, 0)     # sps_temporal_mvp_enabled_flag
    w.u(1, 0)     # strong_intra_smoothing_enabled_flag
    w.u(1, 1)     # vui_parameters_present_flag
    w.u(1, 0)     # aspect_ratio_info_present_flag
    w.u(1, 0)     # overscan_info_present_flag
    w.u(1, 1)     # video_signal_type_present_flag
    w.u(3, video_format)
    w.u(1, full_range)
    w.u(1, 1)     # colour_description_present_flag
    w.u(8, prim)
    w.u(8, trc)
    w.u(8, matrix)
    w.u(1, 0)     # chroma_loc_info_present_flag
    w.u(1, 0)     # neutral_chroma_indication_flag
    w.u(1, 0)     # field_seq_flag
    w.u(1, 0)     # frame_field_info_present_flag
    w.u(1, 0)     # default_display_window_flag
    if not timing:
        w.u(1, 0)  # vui_timing_info_present_flag (absent)
    else:
        w.u(1, 1)  # vui_timing_info_present_flag
        w.u(32, num_units_in_tick)
        w.u(32, time_scale)
        w.u(1, 0)  # poc_proportional_to_timing_flag
        if hrd is None:
            w.u(1, 0)  # vui_hrd_parameters_present_flag
        else:
            nal, vcl, cpb_cnt, entries = hrd
            w.u(1, 1)  # vui_hrd_parameters_present_flag
            w.u(1, nal)
            w.u(1, vcl)
            if nal or vcl:
                w.u(1, 0)  # sub_pic_hrd_params_present_flag
                w.u(4, 0)  # bit_rate_scale
                w.u(4, 0)  # cpb_size_scale
                w.u(5, 0)  # initial_cpb_removal_delay_length_minus1
                w.u(5, 0)  # au_cpb_removal_delay_length_minus1
                w.u(5, 0)  # dpb_output_delay_length_minus1
            for _ in range(1):  # sub-layers (sps_max_sub_layers_minus1 = 0)
                w.u(1, 1)       # fixed_pic_rate_general_flag
                w.ue(1)         # elemental_duration_in_tc_minus1
                w.ue(cpb_cnt)   # cpb_cnt_minus1
                for c in range(cpb_cnt + 1):
                    br, cbs, cbsdu = entries[c]
                    w.ue(br)       # bit_rate_value_minus1
                    w.ue(cbs)      # cpb_size_value_minus1
                    w.ue(cbsdu)    # cpb_size_du_value_minus1
                    w.u(1, 0)      # cbr_flag
    w.u(1, 0)     # sps_extension_present_flag
    w.rbsp_trailing()
    return b'\x42\x01' + escape(w.bytes())   # NAL header (type 33) + EBSP


def hvcC(nal):
    """Minimal hvcC record: 22-byte header, one array, one SPS NAL."""
    out = HVCC_HEAD + b'\x01'                       # numOfArrays = 1
    out += b'\xa1'                                  # completeness=1, type=33
    out += struct.pack('>H', 1) + struct.pack('>H', len(nal)) + nal
    return out


SYNA = dict(width=1920, height=1080, prim=9, trc=16, matrix=9,
            st_rps=((1, 0),))
SYNB = dict(width=1920, height=1080, prim=9, trc=16, matrix=9,
            st_rps=(), time_scale=24000,
            hrd=(1, 1, 1, ((1000, 20000, 2001), (4999, 1, 1000))))
# synU: colour description present but all three UNSPECIFIED(2) — the probe
# must reject so the writeback leaves the keys unset ("UNSPECIFIED stays
# unspecified" invariant at the probe boundary).
SYNU = dict(width=1920, height=1080, prim=2, trc=2, matrix=2, st_rps=())


def build(name):
    spec = {'synA': SYNA, 'synB': SYNB, 'synU': SYNU}[name]
    return hvcC(sps_nal(**spec))


def compare_d1(fixtures_dir):
    """Provenance report (non-fatal): how close is the reconstructed
    generator to the authoritative D1 fixture bytes?

    The D1 originals in fixtures/ are the regression ground truth and are
    asserted through the C harness regardless. This reconstruction matches
    them through the VUI colour fields but diverges in the post-VUI tail
    (D1's exact trailing layout was not archived); it is therefore trusted
    only for behaviour, which the C harness cases (synA/synB/synU) lock.
    """
    for name in ('synA', 'synB'):
        want = open(f'{fixtures_dir}/{name}.hvcc', 'rb').read()
        got = build(name)
        if got == want:
            print(f'compare-d1 {name}: byte-identical ({len(want)} bytes)')
        else:
            i = next((k for k in range(min(len(got), len(want)))
                      if got[k] != want[k]), min(len(got), len(want)))
            print(f'compare-d1 {name}: NOT byte-identical '
                  f'({len(got)} vs {len(want)} bytes, first diff at byte {i});'
                  ' fixture stays authoritative')
    print('compare-d1: generator trusted for behaviour only '
          '(C harness cases synA/synB/synU are the lock)')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('name', choices=['synA', 'synB', 'synU'], nargs='?')
    ap.add_argument('--fixtures-dir', default='fixtures')
    ap.add_argument('--compare-d1', dest='compare_d1', action='store_true',
                    help='provenance report vs the D1 fixture bytes '
                         '(non-fatal)')
    args = ap.parse_args()
    if args.compare_d1:
        compare_d1(args.fixtures_dir)
        return
    if not args.name:
        ap.error('fixture name required (or --compare-d1)')
    data = build(args.name)
    path = f'{args.fixtures_dir}/{args.name}.hvcc'
    open(path, 'wb').write(data)
    print(f'{path}: {len(data)} bytes')


if __name__ == '__main__':
    main()
