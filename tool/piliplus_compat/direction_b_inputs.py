"""Apply the explicitly approved player-integration patch in a private app clone.

The original input checkout is never modified. This is T1B, NOT zero-patch T1.
A generated commit identifies the exact reviewed derivative; it is not pushed
into the upstream application repository. Business/native paths are denied.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path

from dependency_plan import AuditError, git

ALLOWED = frozenset({
    'lib/plugin/pl_player/controller.dart',
    'lib/plugin/pl_player/view/view.dart',
    'lib/pages/video/view.dart',
    'lib/pages/live_room/view.dart',
    'lib/pages/video/introduction/local/controller.dart',
    'lib/pages/video/post_panel/view.dart',
    'lib/common/widgets/image_viewer/gallery_viewer.dart',
})


def blob(data: bytes) -> str:
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def apply_direction_b(app: Path, sdk: Path, evidence: Path) -> dict:
    recipe = 'tool/piliplus_compat/direction_b'
    # Windows checkout autocrlf may transform patch text. Consume the reviewed
    # Git objects, not transformed worktree bytes; keep all digest and source
    # checks exact. The SDK input identity is separately guarded by the builder.
    manifest = json.loads(git(sdk, 'show', 'HEAD:' + recipe + '/manifest.json'))
    patch_data = git(sdk, 'show', 'HEAD:' + recipe + '/player-integration.patch')
    patch = evidence / 'direction-b-input.patch'
    if (manifest.get('version') != 1 or manifest.get('decision') != 'B-approved-20261019'
            or not manifest.get('files') or not set(manifest['files']).issubset(ALLOWED)):
        raise AuditError('Unapproved direction B file scope')
    if hashlib.sha256(patch_data).hexdigest() != manifest['patchSha256']:
        raise AuditError('Direction B patch digest changed')
    if git(app, 'status', '--porcelain').strip():
        raise AuditError('Direction B input clone is dirty')
    original = git(app, 'rev-parse', 'HEAD').decode().strip()
    for name, expected in manifest['files'].items():
        path = app / name
        if path.is_symlink() or not path.resolve().is_relative_to(app.resolve()):
            raise AuditError('Linked direction B target: ' + name)
        if not path.is_file() or blob(path.read_bytes()) != expected['before']:
            raise AuditError('Upstream player integration changed; review required: ' + name)
    # All preimages are checked before applying any edits. Never use --reject,
    # fuzzy textual substitutions, or accept a partial application.
    patch.write_bytes(patch_data)
    git(app, 'apply', '--check', str(patch.resolve()))
    git(app, 'apply', str(patch.resolve()))
    changed = set(git(app, 'diff', '--name-only').decode().splitlines())
    if changed != set(manifest['files']):
        raise AuditError('Direction B changed-file set differs')
    for name, expected in manifest['files'].items():
        path = app / name
        if path.is_symlink() or not path.is_file() or blob(path.read_bytes()) != expected['after']:
            raise AuditError('Direction B postimage mismatch: ' + name)
    diff = git(app, 'diff', '--binary', 'HEAD')
    (evidence / 'direction-b-applied.patch').write_bytes(diff)
    git(app, 'add', '--', *sorted(changed))
    # Only this isolated clone receives a synthetic derivative commit. The
    # original upstream SHA remains the application's input identity.
    git(app, '-c', 'user.name=media-kit integration build',
        '-c', 'user.email=build@users.noreply.github.com', 'commit', '-qm',
        'Apply reviewed direction B player integration')
    return {'mode': 'direction-b', 'zeroPatch': False, 'upstreamCommit': original,
            'integratedCommit': git(app, 'rev-parse', 'HEAD').decode().strip(),
            'files': manifest['files'], 'patchSha256': manifest['patchSha256'],
            'appliedDiffSha256': hashlib.sha256(diff).hexdigest()}
