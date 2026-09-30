import sys
# usage: resolve_conflicts.py <file> <hunk_indices_1based_comma_separated> <HEAD|main>
path, idxs, side = sys.argv[1], sys.argv[2], sys.argv[3]
idxs = {int(x) for x in idxs.split(',')}
lines = open(path).readlines()
out, i, hunk = [], 0, 0
while i < len(lines):
    l = lines[i]
    if l.startswith('<<<<<<<'):
        hunk += 1
        # collect head/main
        j = i + 1
        head = []
        while not lines[j].startswith('======='):
            head.append(lines[j]); j += 1
        j += 1
        mains = []
        while not lines[j].startswith('>>>>>>>'):
            mains.append(lines[j]); j += 1
        j += 1
        if hunk in idxs:
            out.extend(head if side == 'HEAD' else mains)
        else:
            # keep as unresolved, re-emit with renumbered marker
            out.append(l); out.extend(head); out.append('=======\n'); out.extend(mains); out.append('>>>>>>>\n')
        i = j
    else:
        out.append(l); i += 1
open(path, 'w').writelines(out)
print(f"applied {side} to hunks {sorted(idxs)}; remaining markers: {sum(1 for x in out if x.startswith('<<<<<<<'))}")
