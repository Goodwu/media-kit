#!/usr/bin/env python3
"""Build the MKSVUI host regression harness from the live FFmpeg fork source.

Extracts the self-contained parser block (MKSVUIGetBits ..
mcdec_probe_hevc_vui_color) from <ffmpeg-src>/libavcodec/mediacodecdec_common.c
— the same extraction D1 used in /private/tmp/mksvui/build_harness.py — and
emits a standalone harness whose main() asserts the fixture expectation table
(run_mksvui_regress.sh drives compilation and execution).

The extraction is deliberately marker-based: if the product file drifts so far
that the markers vanish, this script fails loudly instead of testing a stale
copy.
"""
import argparse
import os
import sys

PROBE_FN = 'mcdec_probe_hevc_vui_color'
BLOCK_START = 'typedef struct MKSVUIGetBits'

SHIMS = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* minimal host shims for the extracted block (mirrors D1 build_harness.py) */
#define FFMIN(a,b) ((a) < (b) ? (a) : (b))
#define FF_ARRAY_ELEMS(a) (sizeof(a)/sizeof((a)[0]))
#define AVERROR(e) (-(e))
#define AVERROR_INVALIDDATA (-0x4e444154)
#define EINVAL 22
typedef struct AVCodecContext { const unsigned char *extradata; int extradata_size; int codec_id; } AVCodecContext;
enum { AVCOL_TRC_UNSPECIFIED = 2, AVCOL_PRI_UNSPECIFIED = 2, AVCOL_SPC_UNSPECIFIED = 2 };
enum { HEVC_MAX_SUB_LAYERS = 7, HEVC_MAX_SHORT_TERM_REF_PIC_SETS = 64,
       HEVC_MAX_REFS = 16, HEVC_MAX_LONG_TERM_REF_PICS = 32 };
static const char *dummy_name(int v) { return (v >= 0 && v <= 63) ? "x" : NULL; }
#define av_color_transfer_name dummy_name
#define av_color_primaries_name dummy_name
#define av_color_space_name dummy_name
#define AV_CODEC_ID_HEVC 1

'''

MAIN = r'''
/* ---- regression driver ---- */

static unsigned long rng_state = 987654321;
static unsigned long rnd(void) {
    rng_state = rng_state*6364136223846793005UL + 1442695040888963407UL;
    return rng_state >> 17;
}

static int read_file(const char *path, unsigned char **out) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    *out = malloc(n);
    if (fread(*out, 1, n, f) != (size_t)n) { fclose(f); return -1; }
    fclose(f);
    return n;
}

struct expect {
    const char *name;
    int ok;              /* 1: probe must succeed, 0: must fail */
    int trc, prim, matrix;
};

/* Post-D1 locked expectations. b.hvcc (HLG with vui_hrd present) parsed as
 * failure before D1's HRD mirror fix; success here is the locked D1 fix #2
 * behaviour (Lead-approved HRD consumption). synA exercises the D1 fix #1
 * used_by_curr_pic read-back; synB is the nal+vcl HRD positive control
 * (bit distance 98 = 2x49); synU locks "UNSPECIFIED stays unspecified". */
static struct expect expects[] = {
    { "a.hvcc",    1, 16, 9, 9 },
    { "a.annexb",  1, 16, 9, 9 },
    { "a.265",     1, 16, 9, 9 },
    { "b.hvcc",    1, 18, 9, 9 },
    { "synA.hvcc", 1, 16, 9, 9 },
    { "synB.hvcc", 1, 16, 9, 9 },
    { "synU.hvcc", 0, -1, -1, -1 },
};

static int run_case(const char *dir, const struct expect *e) {
    char path[1024];
    unsigned char *data = NULL;
    int trc = -1, prim = -1, matrix = -1, size;

    snprintf(path, sizeof(path), "%s/%s", dir, e->name);
    size = read_file(path, &data);
    if (size < 0) {
        printf("CASE %s FAIL (cannot read %s)\n", e->name, path);
        return 1;
    }
    /* drive the product entry point (includes the UNSPECIFIED/validity gate),
     * not the raw NAL walker */
    AVCodecContext avctx = { .extradata = data, .extradata_size = size,
                             .codec_id = 1 };
    int ret = mcdec_probe_hevc_vui_color(&avctx, &trc, &prim, &matrix);
    free(data);
    int pass = e->ok ? (ret == 0 && trc == e->trc &&
                        prim == e->prim && matrix == e->matrix)
                     : (ret != 0);
    printf("CASE %s %s got=(ret=%d trc=%d prim=%d matrix=%d) "
           "want=(ret=%s trc=%d prim=%d matrix=%d)\n",
           e->name, pass ? "PASS" : "FAIL",
           ret, trc, prim, matrix, e->ok ? "0" : "<0",
           e->trc, e->prim, e->matrix);
    return pass ? 0 : 1;
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : ".";
    long fuzz_iters = argc > 2 ? atol(argv[2]) : 20000;
    int failures = 0;

    for (size_t i = 0; i < sizeof(expects)/sizeof(expects[0]); i++)
        failures += run_case(dir, &expects[i]);

    /* deterministic malformed-input smoke: truncations, bit flips, random
     * blobs — must never crash (ASan/UBSan aborts fail the run) */
    {
        enum { NSEEDS = 6 };  /* expects[0..5]; synU is a must-fail case */
        unsigned char *seeds[NSEEDS] = { 0 };
        int seed_len[NSEEDS] = { 0 };
        for (int s = 0; s < NSEEDS; s++) {
            char path[1024];
            snprintf(path, sizeof(path), "%s/%s", dir, expects[s].name);
            seed_len[s] = read_file(path, &seeds[s]);
            if (seed_len[s] < 0) {
                printf("CASE fuzz FAIL (seed %s unreadable)\n", expects[s].name);
                return 1;
            }
            if (seed_len[s] > 4096) seed_len[s] = 4096;
        }
        unsigned char buf[4096];
        long clean = 0;
        for (long iter = 0; iter < fuzz_iters; iter++) {
            int s = rnd() % NSEEDS;
            int len = seed_len[s];
            memcpy(buf, seeds[s], len);
            int mode = rnd() % 5;
            if (mode == 0 && len > 1) len = rnd() % len;
            else if (mode == 1) { int flips = rnd() % 16; for (int f = 0; f < flips; f++) buf[rnd() % len] ^= 1 << (rnd() % 8); }
            else if (mode == 2 && len < 4000) { int add = rnd() % 64; for (int a2 = 0; a2 < add; a2++) buf[len++] = rnd() & 0xff; }
            else if (mode == 3) { int start = len * 6 / 10; int flips = rnd() % 8; for (int f = 0; f < flips && start < len; f++) buf[start + rnd() % (len - start)] ^= 1 << (rnd() % 8); }
            else { len = rnd() % 512; for (int a3 = 0; a3 < len; a3++) buf[a3] = rnd() & 0xff; }
            int trc, prim, matrix;
            mkvui_probe_hevc_extradata(buf, len, &trc, &prim, &matrix);
            AVCodecContext avctx = { .extradata = buf,
                                     .extradata_size = len, .codec_id = 1 };
            mcdec_probe_hevc_vui_color(&avctx, &trc, &prim, &matrix);
            clean++;
        }
        for (int s = 0; s < NSEEDS; s++) free(seeds[s]);
        printf("CASE fuzz %s (%ld iterations, no crash)\n",
               clean == fuzz_iters ? "PASS" : "FAIL", clean);
        if (clean != fuzz_iters) failures++;
    }

    printf("SUMMARY failures=%d\n", failures);
    return failures ? 1 : 0;
}
'''


def extract_block(src_path):
    src = open(src_path, encoding='utf-8').read()
    try:
        start = src.index(BLOCK_START)
        i = src.index('{', src.index(f'static int {PROBE_FN}'))
    except ValueError as e:
        sys.exit(f'mksvui_regress: marker not found in {src_path} '
                 f'(product layout drifted?): {e}')
    depth = 0
    j = i
    while True:
        if src[j] == '{':
            depth += 1
        elif src[j] == '}':
            depth -= 1
            if depth == 0:
                break
        j += 1
    return src[start:j + 1]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--ffmpeg-src', default=os.environ.get(
        'FFMPEG_SRC', os.path.expanduser('~/src/FFmpeg')))
    ap.add_argument('--out', required=True, help='harness .c output path')
    args = ap.parse_args()

    src_file = os.path.join(args.ffmpeg_src, 'libavcodec',
                            'mediacodecdec_common.c')
    block = extract_block(src_file)
    with open(args.out, 'w', encoding='utf-8') as f:
        f.write(f'/* GENERATED by {os.path.basename(__file__)} from '
                f'{src_file} -- do not edit the extracted block. */\n')
        f.write(SHIMS)
        f.write(block)
        f.write(MAIN)
    print(f'mksvui_regress: extracted {block.count(chr(10))} parser lines '
          f'from {src_file} -> {args.out}')


if __name__ == '__main__':
    main()
