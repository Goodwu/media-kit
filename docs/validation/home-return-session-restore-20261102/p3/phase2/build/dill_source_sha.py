import sys, hashlib
dill = open(sys.argv[1], 'rb').read()
def read_uint(b, i):
    x = b[i]
    if x & 0x80 == 0: return x, 1
    if x & 0xC0 == 0x80: return ((x & 0x3F) << 8) | b[i+1], 2
    return ((x & 0x3F) << 24) | (b[i+1] << 16) | (b[i+2] << 8) | b[i+3], 4
# usage: dill path, then name=anchor pairs; finds each source blob whose prefix is the shared header
header = b'/// This file is a part of media_kit'
for spec in sys.argv[2:]:
    name, anchor = spec.split('=', 1)
    hits = []
    pos = 0
    while True:
        a = dill.find(anchor.encode(), pos)
        if a < 0: break
        pos = a + 1
        h = dill.rfind(header, 0, a)
        found = None
        for w in (1, 2, 4):
            s = h - w
            n, ww = read_uint(dill, s)
            if ww == w and s + w + n >= a and n > 0:
                blob = dill[h:h+n]
                found = (n, hashlib.sha256(blob).hexdigest())
                break
        hits.append((a, h, found))
    for a, h, f in hits:
        print(name, 'anchor@', a, 'start@', h, 'len/sha', f)
