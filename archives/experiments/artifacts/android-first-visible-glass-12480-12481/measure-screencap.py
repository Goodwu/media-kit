import io
import statistics
import subprocess
import time
from PIL import Image, ImageStat

serial = '3EP7N18C28016072'
base = ['adb', '-s', serial]

def adb(*args):
    return subprocess.check_output(base + list(args))

def capture():
    data = adb('exec-out', 'screencap', '-p')
    image = Image.open(io.BytesIO(data)).convert('RGB')
    # Fixed video pane on the 1440 x 3120 portrait diagnostic page.
    # The center can contain a loading spinner; use an off-center video crop.
    pane = image.crop((200, 450, 600, 1000))
    stats = ImageStat.Stat(pane.resize((100, 55)))
    mean = statistics.mean(stats.mean)
    spread = statistics.mean(stats.stddev)
    return data, mean, spread, image.size

for trial in range(1, 4):
    adb('shell', 'am', 'force-stop', 'com.example.media_kit_test')
    adb('shell', 'am', 'start', '-n', 'com.example.media_kit_test/.MainActivity')
    ready = False
    for _ in range(20):
        time.sleep(0.2)
        _, baseline, baseline_spread, size = capture()
        if baseline < 5 and size == (1440, 3120):
            ready = True
            break
    if not ready:
        print(f'trial={trial} invalid: black ready pane not observed, mean={baseline:.2f}, size={size}', flush=True)
        continue
    time.sleep(0.25)
    before, baseline, baseline_spread, _ = capture()
    if baseline >= 5:
        print(f'trial={trial} invalid: pane changed before tap, mean={baseline:.2f}', flush=True)
        continue
    t0 = time.monotonic_ns()
    adb('shell', 'input', 'tap', '120', '1280')
    for capture_number in range(1, 90):
        frame, brightness, spread, _ = capture()
        t1 = time.monotonic_ns()
        if spread > 10:
            path = f'/tmp/media-kit-12481-glass-first-visible-{trial}.png'
            with open(path, 'wb') as output:
                output.write(frame)
            print(f'trial={trial} upper_ms={(t1-t0)/1e6:.1f} captures={capture_number} baseline={baseline:.2f} first_mean={brightness:.2f} first_spread={spread:.2f} screenshot={path}', flush=True)
            break
    else:
        print(f'trial={trial} no visible frame by {(t1-t0)/1e6:.1f}ms final_mean={brightness:.2f} final_spread={spread:.2f}', flush=True)
