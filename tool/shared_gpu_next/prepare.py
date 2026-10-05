#!/usr/bin/env python3
"""Prepare the pinned shared mpv source; never modify an existing checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
if __package__:
    from .verify_source import verify
else:
    from verify_source import verify


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    manifest = json.loads((here / "manifest.json").read_text())
    patch = here / "mpv-0.41-shared-core.patch"
    if digest(args.archive) != manifest["base_archive_sha256"]:
        parser.error("mpv source archive hash does not match the pinned baseline")
    if digest(patch) != manifest["patch_sha256"]:
        parser.error("shared-core patch hash does not match its manifest")
    destination = args.destination.resolve()
    if destination.exists():
        parser.error("destination already exists; choose a new source directory")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="shared-core-", dir=destination.parent) as temporary:
        temporary = Path(temporary)
        with tarfile.open(args.archive) as archive:
            for member in archive.getmembers():
                target = (temporary / member.name).resolve()
                if not target.is_relative_to(temporary) or not (member.isfile() or member.isdir()):
                    parser.error(f"unsupported archive entry: {member.name}")
            archive.extractall(temporary)
        source = temporary / manifest["base"]
        if not source.is_dir():
            parser.error("archive does not contain the expected source root")
        for name, hashes in manifest["files"].items():
            path = source / name
            before = digest(path) if path.is_file() else None
            if before != hashes["before"]:
                parser.error(f"baseline file mismatch: {name}")
        subprocess.run(["patch", "--batch", "--forward", "-p1", "-d", str(source),
                        "-i", str(patch)], check=True)
        for name, hashes in manifest["files"].items():
            path = source / name
            after = digest(path) if path.is_file() else None
            if after != hashes["after"]:
                parser.error(f"patched source mismatch: {name}")
        identity = verify(args.archive, source)
        shutil.move(str(source), destination)
    print(f"Prepared and verified {len(manifest['files'])} shared-core files: {destination}")
    print(f"Verified complete source tree: {identity['file_count']} files, SHA-256 {identity['source_tree_sha256']}")


if __name__ == "__main__":
    main()
