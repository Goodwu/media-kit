#!/usr/bin/env python3
"""验收截图像素统计：正常画面/紫屏/黑屏/白屏/落版判定。"""
import sys
from PIL import Image
import statistics

def stats(path):
    im = Image.open(path).convert('RGB')
    im.thumbnail((320, 180))
    px = list(im.getdata())
    n = len(px)
    r = sum(p[0] for p in px) / n
    g = sum(p[1] for p in px) / n
    b = sum(p[2] for p in px) / n
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    means = (r, g, b)
    var = statistics.pvariance([0.299*p[0]+0.587*p[1]+0.114*p[2] for p in px])
    verdict = '正常画面'
    if lum < 8 and var < 30:
        verdict = '黑屏'
    elif lum > 245 and var < 30:
        verdict = '白屏'
    elif r > g + 25 and b > g + 25 and lum > 40:
        verdict = '疑似紫屏'
    elif var < 15:
        verdict = '纯色/落版(需人工确认)'
    print(f"{path.split('/')[-1]}: mean=({r:.1f},{g:.1f},{b:.1f}) lum={lum:.1f} var={var:.0f} -> {verdict}")

for p in sys.argv[1:]:
    stats(p)
