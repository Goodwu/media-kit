#!/usr/bin/env python3
"""Publish pre-reviewed exact SDK edits. Not an application build-time patcher."""
from pathlib import Path, PurePosixPath
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
ALLOWED = ('media_kit/', 'media_kit_video/', 'tool/piliplus_compat/')


def blob(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def apply(root, manifest):
    receipt = root / 'docs/plans' / (manifest['id'] + '.json')
    if receipt.exists():
        if json.loads(receipt.read_text())['request'] != manifest:
            raise RuntimeError('Applied request id reused with different edits')
        print('Already applied; no replay')
        return
    staged = []
    for entry in manifest['files']:
        name = entry['path']
        if (not name.startswith(ALLOWED) or '..' in PurePosixPath(name).parts
                or '\\' in name or '.git' in PurePosixPath(name).parts):
            raise RuntimeError('Not an approved SDK path: ' + name)
        path = root / name
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise RuntimeError('Escaping or linked SDK target: ' + name)
        original = path.read_bytes()
        if blob(original) != entry['blob']:
            raise RuntimeError('Source blob changed: ' + name)
        text = original.decode('utf-8')
        for edit in entry['edits']:
            if text.count(edit['old']) != edit.get('count', 1):
                raise RuntimeError('Exact edit count differs: ' + name)
            text = text.replace(edit['old'], edit['new'])
        staged.append((path, text.encode('utf-8')))
    # Every guard succeeds before any source file is modified.
    for path, data in staged:
        path.write_bytes(data)
    receipt.write_text(json.dumps({'request': manifest, 'result': {
        str(path.relative_to(root)): blob(data) for path, data in staged},
        'status': 'source-published-not-build-certified'}, indent=2) + '\n')


if __name__ == '__main__':
    apply(ROOT, json.loads((ROOT / 'tool/piliplus_compat/reviewed_edits.json').read_text()))
