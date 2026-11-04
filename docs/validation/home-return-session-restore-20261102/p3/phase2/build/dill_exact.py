# usage: python3 -I dill_exact.py <app.dill> <source files...>
# For each file: look for its exact bytes in the kernel's embedded Source table, preceded by a kernel UInt length prefix == file length.
import sys, hashlib
d = open(sys.argv[1], 'rb').read()
def enc(n):
    if n < 0x80: return bytes([n])
    if n < 0x4000: return bytes([0x80 | (n >> 8), n & 0xFF])
    return bytes([0xC0 | (n >> 24), (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF])
ok = True
for f in sys.argv[2:]:
    b = open(f, 'rb').read()
    hit = d.find(enc(len(b)) + b)
    print(('MATCH ' if hit >= 0 else 'NOMATCH'), hashlib.sha256(b).hexdigest(), len(b), f, ('@%d' % hit) if hit >= 0 else '')
    ok &= hit >= 0
sys.exit(0 if ok else 1)
