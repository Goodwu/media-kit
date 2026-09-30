#!/usr/bin/env python3
"""截图绿色偏色/撕裂形态分析：绿色像素分布（行列/块聚集）、对角撕裂趋势、边缘能量。

来源：Mi Note 3 HDR10 观感诊断轮（jason，绿块/斜线撕裂判定），由一次性脚本参数化收编。
"""
import sys
import numpy as np
from PIL import Image

FILES = sys.argv[1:]
if not FILES:
    sys.exit("usage: analyze_shots.py <screenshot.png> [...]")

def analyze(path):
    img = Image.open(path).convert("RGB")
    W, H = img.size
    a = np.asarray(img).astype(np.float32)
    R, G, B = a[...,0], a[...,1], a[...,2]

    # ---- green cast detection ----
    greenish = (G - np.maximum(R, B) > 25) & (G > 60)
    frac = greenish.mean()
    rowfrac = greenish.mean(axis=1)   # per row
    colfrac = greenish.mean(axis=0)   # per col

    # rows/cols dominated by green (candidate bars)
    grow = np.where(rowfrac > 0.30)[0]
    gcol = np.where(colfrac > 0.30)[0]

    # green blobs on a coarse 24x24-pixel... use block grid 40x40 px
    bs = 40
    gh, gw = H//bs, W//bs
    gblk = greenish[:gh*bs, :gw*bs].reshape(gh, bs, gw, bs).mean(axis=(1,3))
    blocks = np.argwhere(gblk > 0.25)  # blocks with >25% green pixels
    nblk = len(blocks)

    print(f"===== {path}  ({W}x{H}) =====")
    print(f"green-cast pixel fraction: {frac*100:.2f}%")
    if grow.size:
        # summarize contiguous row runs
        runs = []
        s = grow[0]; p = grow[0]
        for r in grow[1:]:
            if r == p+1: p = r
            else: runs.append((s,p)); s = r; p = r
        runs.append((s,p))
        print(f"green-dominated rows (>{30}% of row): {len(grow)} rows in {len(runs)} run(s): "
              + ", ".join(f"y={a0}-{b0} (h={b0-a0+1}, meanfrac={rowfrac[a0:b0+1].mean():.2f})" for a0,b0 in runs[:8]))
    else:
        print("no green-dominated full rows")
    if gcol.size:
        runs = []
        s = gcol[0]; p = gcol[0]
        for c in gcol[1:]:
            if c == p+1: p = c
            else: runs.append((s,p)); s = c; p = c
        runs.append((s,p))
        print(f"green-dominated cols: {len(gcol)} cols in {len(runs)} run(s): "
              + ", ".join(f"x={a0}-{b0}" for a0,b0 in runs[:8]))
    if nblk:
        ys = blocks[:,0]*bs; xs = blocks[:,1]*bs
        print(f"green blocks (>25% in 40px block): {nblk}, extent y=[{ys.min()},{ys.max()+bs}) x=[{xs.min()},{xs.max()+bs})")
        # print top blocks by density
        dens = gblk[blocks[:,0], blocks[:,1]]
        order = np.argsort(-dens)[:10]
        for i in order:
            by, bx = blocks[i]
            print(f"   block y={by*bs}-{(by+1)*bs} x={bx*bs}-{(bx+1)*bs} green={dens[i]*100:.0f}%")

    # ---- tear / diagonal detection ----
    Y = 0.299*R + 0.587*G + 0.114*B
    gx = np.abs(np.diff(Y, axis=1))  # H x (W-1), gradient along x
    THR = 70
    xs_per_row = []
    for yy in range(0, H, 4):
        row = gx[yy]
        idx = np.where(row > THR)[0]
        if idx.size:
            # strongest
            best = idx[np.argmax(row[idx])]
            xs_per_row.append((yy, best, row[best], idx.size))
    n_strong = len(xs_per_row)
    print(f"rows with strong horizontal gradient(>{THR}): {n_strong} / {len(range(0,H,4))}")
    if n_strong >= 20:
        ys2 = np.array([p[0] for p in xs_per_row], float)
        xs2 = np.array([p[1] for p in xs_per_row], float)
        # correlation of x-position with y -> diagonal?
        if ys2.std() > 0 and xs2.std() > 0:
            corr = np.corrcoef(ys2, xs2)[0,1]
            slope = np.polyfit(ys2, xs2, 1)[0]
            print(f"breakpoint x-vs-y: corr={corr:.3f}, slope={slope:.2f} px/row "
                  f"({'DIAGONAL trend' if abs(corr)>0.7 and abs(slope)>0.3 else 'no clear diagonal'})")
        sample = xs_per_row[::max(1,len(xs_per_row)//8)]
        print("   sample breakpoints: " + "; ".join(f"y={y}:x={x}(g={g:.0f},n={n})" for y,x,g,n in sample))

    # diagonal edge energy: shift-and-difference
    e_diag1 = np.abs(Y[1:, 1:] - Y[:-1, :-1]).mean()   # main diagonal changes
    e_diag2 = np.abs(Y[1:, :-1] - Y[:-1, 1:]).mean()   # anti-diagonal
    e_h = np.abs(np.diff(Y, axis=0)).mean()
    e_v = np.abs(np.diff(Y, axis=1)).mean()
    print(f"edge energy: diag1={e_diag1:.2f} diag2={e_diag2:.2f} horiz={e_h:.2f} vert={e_v:.2f}")

    # local noise/ghosting proxy: block-wise high-freq residual
    # noise proxy via block-wise laplacian below
    # simpler: per-block std of laplacian
    Yc = Y[:gh*bs, :gw*bs]
    lap = np.abs(4*Yc[1:-1,1:-1] - Yc[:-2,1:-1] - Yc[2:,1:-1] - Yc[1:-1,:-2] - Yc[1:-1,2:])
    b2 = bs - 2
    lb = lap[:gh*b2, :gw*b2].reshape(gh, b2, gw, b2).mean(axis=(1,3))
    hot = np.argwhere(lb > max(60, np.quantile(lb, 0.999)))
    if hot.size:
        print(f"high-frequency hotspot blocks: {len(hot)} (top: " +
              ", ".join(f"y={y*bs},x={x*bs}(v={lb[y,x]:.0f})" for y,x in hot[:6]) + ")")
    print()

for f in FILES:
    analyze(f)
