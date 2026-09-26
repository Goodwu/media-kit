"""Generate deterministic HDR10 PQ and SDR grayscale input controls.

These clips are encoded-input controls, not a reference for measured display
brightness or a substitute for independent color/display acceptance.
"""

import hashlib
import json
import math
import subprocess
from pathlib import Path

import numpy as np


WIDTH = 1920
HEIGHT = 1080
FPS = 30
SECONDS = 6
NITS = (0, 1, 10, 100, 203, 400, 1000)
OUTPUT = Path('/tmp/media-kit-hdr-gray-controls-20260924')


def pq_encode(nits: float) -> float:
    # SMPTE ST 2084 inverse EOTF, with absolute luminance normalized to 10000 nit.
    m1 = 2610 / 16384
    m2 = 2523 / 32
    c1 = 3424 / 4096
    c2 = 2413 / 128
    c3 = 2392 / 128
    p = (nits / 10000) ** m1
    return ((c1 + c2 * p) / (1 + c3 * p)) ** m2


def limited_y(signal: float) -> int:
    return round(64 + 876 * min(1, max(0, signal)))


def pq_decode(signal: float) -> float:
    m1 = 2610 / 16384
    m2 = 2523 / 32
    c1 = 3424 / 4096
    c2 = 2413 / 128
    c3 = 2392 / 128
    p = signal ** (1 / m2)
    return 10000 * (max(p - c1, 0) / (c2 - c3 * p)) ** (1 / m1)


def make_frame(codes: list[int], path: Path) -> None:
    y = np.empty((HEIGHT, WIDTH), dtype='<u2')
    for index, code in enumerate(codes):
        left = WIDTH * index // len(codes)
        right = WIDTH * (index + 1) // len(codes)
        y[:, left:right] = code
    uv = np.full((HEIGHT // 2, WIDTH // 2), 512, dtype='<u2')
    with path.open('wb') as target:
        target.write(y.tobytes())
        target.write(uv.tobytes())
        target.write(uv.tobytes())


def encode(raw: Path, output: Path, hdr: bool,
           max_cll: int = 0, max_fall: int = 0) -> None:
    color = (
        ['-color_primaries', 'bt2020', '-color_trc', 'smpte2084',
         '-colorspace', 'bt2020nc']
        if hdr else
        ['-color_primaries', 'bt709', '-color_trc', 'bt709',
         '-colorspace', 'bt709']
    )
    x265 = 'lossless=1:repeat-headers=1:pools=4:frame-threads=2:log-level=error'
    if hdr:
        x265 += ':colorprim=9:transfer=16:colormatrix=9:range=limited'
        x265 += ':master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,50)'
        x265 += f':max-cll={max_cll},{max_fall}'
    else:
        x265 += ':colorprim=1:transfer=1:colormatrix=1:range=limited'
    subprocess.run([
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
        '-stream_loop', '-1', '-f', 'rawvideo', '-pixel_format', 'yuv420p10le',
        '-video_size', f'{WIDTH}x{HEIGHT}', '-framerate', str(FPS), '-i', str(raw),
        '-t', str(SECONDS), '-an', '-c:v', 'libx265', '-preset', 'ultrafast',
        '-x265-params', x265, *color, '-pix_fmt', 'yuv420p10le', str(output),
    ], check=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    OUTPUT.mkdir(exist_ok=True)
    pq = [limited_y(pq_encode(value)) for value in NITS]
    actual_pq_nits = [pq_decode((code - 64) / 876) for code in pq]
    widths = [WIDTH * (i + 1) // len(NITS) - WIDTH * i // len(NITS)
              for i in range(len(NITS))]
    max_cll = math.ceil(max(actual_pq_nits))
    max_fall = math.ceil(sum(width * value for width, value
                             in zip(widths, actual_pq_nits)) / WIDTH)
    # Clip the same absolute luminance bands at SDR reference white (100 nit).
    # This is display-referred gamma 2.4, not the BT.709 camera OETF or a
    # perceptual tone mapping. The stream carries BT.709 SDR video signaling.
    sdr = [limited_y((min(value, 100) / 100) ** (1 / 2.4)) for value in NITS]
    clips = {}
    for mode, codes in [('pq', pq), ('sdr', sdr)]:
        raw = OUTPUT / f'{mode}-frame-yuv420p10le.raw'
        clip = OUTPUT / f'{mode}-gray-1920x1080-6s.mp4'
        make_frame(codes, raw)
        encode(raw, clip, mode == 'pq', max_cll, max_fall)
        clips[mode] = {'path': str(clip), 'sha256': sha256(clip), 'y10_codes': codes}
    manifest = {
        'purpose': 'deterministic encoded-input PQ positive and SDR negative controls',
        'limit': 'does not prove display HDR activation, output color, or optical luminance',
        'geometry': f'{WIDTH}x{HEIGHT}', 'fps': FPS, 'duration_seconds': SECONDS,
        'grayscale_bands_left_to_right_nits': NITS,
        'quantized_pq_band_nits': [round(value, 3) for value in actual_pq_nits],
        'max_cll_nits_rounded_up': max_cll,
        'max_frame_average_nits_rounded_up': max_fall,
        'sdr_mapping': 'display-referred ideal gamma 2.4, 100 nit clip; not BT.709 camera OETF',
        'luma_range': '10-bit limited 64..940', 'chroma_code': 512,
        'clips': clips,
    }
    (OUTPUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
