import io
import json
import statistics
import subprocess
import time
from pathlib import Path

from PIL import Image, ImageStat

serial = '3EP7N18C28016072'
base = ['adb', '-s', serial]
out = Path('/tmp/media-kit-12484-fill')
out.mkdir(exist_ok=True)


def adb(*args):
    return subprocess.check_output(base + list(args))


def capture():
    raw = adb('exec-out', 'screencap', '-p')
    img = Image.open(io.BytesIO(raw)).convert('RGB')
    pane = img.crop((200, 450, 600, 700)).resize((100, 63))
    pixels = list(pane.getdata())
    magenta = sum(r > 235 and g < 20 and b > 235 for r, g, b in pixels) / len(pixels)
    stats = ImageStat.Stat(pane)
    spread = statistics.mean(stats.stddev)
    mean = statistics.mean(stats.mean)
    return raw, magenta, mean, spread, img.size


for trial in range(1, 4):
    adb('shell', 'am', 'force-stop', 'com.example.media_kit_test')
    adb('shell', 'am', 'start', '-n', 'com.example.media_kit_test/.MainActivity')
    for _ in range(30):
        time.sleep(0.2)
        raw, magenta, mean, spread, size = capture()
        if size == (1440, 3120) and magenta > 0.95:
            break
    else:
        print(f'trial={trial} invalid baseline magenta={magenta:.3f} size={size}', flush=True)
        continue
    baseline_magenta = magenta
    (out / f'trial-{trial}-before.png').write_bytes(raw)
    t0 = time.monotonic_ns()
    adb('shell', 'input', 'tap', '120', '1280')
    samples = []
    first_replaced = None
    first_content = None
    for index in range(1, 50):
        raw, magenta, mean, spread, size = capture()
        elapsed_ms = (time.monotonic_ns() - t0) / 1e6
        samples.append([index, elapsed_ms, magenta, mean, spread])
        if first_replaced is None and magenta < 0.05:
            first_replaced = elapsed_ms
            (out / f'trial-{trial}-first-replaced.png').write_bytes(raw)
        if first_replaced is not None and spread > 10:
            first_content = elapsed_ms
            (out / f'trial-{trial}-first-content.png').write_bytes(raw)
            break
    (out / f'trial-{trial}.json').write_text(json.dumps({
        'baseline_magenta': baseline_magenta,
        'first_replaced_upper_ms': first_replaced,
        'first_content_upper_ms': first_content,
        'samples': samples,
    }, indent=2))
    print(f'trial={trial} replaced_upper_ms={first_replaced} content_upper_ms={first_content} samples={len(samples)}', flush=True)
