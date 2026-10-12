#!/usr/bin/env python3
"""Trusted media-kit preflight for the App-owned Linux input verifier."""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

TASK_BRANCH = "routing/MK-ROUTING-20261011"
APP_REMOTE = re.compile(r"(?:https://github\.com/Goodwu/PiliPlusX(?:\.git)?|git@github\.com:Goodwu/PiliPlusX\.git)")
MEDIA_REMOTE = re.compile(r"(?:https://github\.com/Goodwu/media-kit(?:\.git)?|git@github\.com:Goodwu/media-kit\.git)")
APP_VERIFIER = Path("scripts/verify_routing_linux_native.py")
APP_LEDGER = Path("docs/plans/routing-linux-native-accepted-inputs.json")


class Reject(ValueError):
    pass


def git(root: Path, *args: str) -> str:
    try:
        result = subprocess.run(["git", "-C", str(root), *args], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                check=False, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise Reject(f"Git inspection failed: {args[0]}: {error}") from error
    if result.returncode or result.stderr.strip():
        raise Reject(f"Git inspection failed: {args[0]}")
    return result.stdout.strip()


def validate_checkout(root: Path, expected_sha: str, remote_pattern: re.Pattern[str], role: str) -> None:
    if root.is_symlink():
        raise Reject(f"{role} root must not be a symlink")
    root = root.resolve(strict=True)
    if not root.is_dir() or Path(git(root, "rev-parse", "--show-toplevel")).resolve() != root:
        raise Reject(f"{role} root must be an exact Git worktree root")
    if git(root, "rev-parse", "--abbrev-ref", "HEAD") != TASK_BRANCH:
        raise Reject(f"{role} branch mismatch")
    head = git(root, "rev-parse", "HEAD")
    if not re.fullmatch(r"[0-9a-f]{40}", expected_sha) or head != expected_sha:
        raise Reject(f"{role} HEAD differs from expected consumer vector")
    remotes = git(root, "remote").splitlines()
    urls = [git(root, "remote", "get-url", remote) for remote in remotes]
    if not any(remote_pattern.fullmatch(url) for url in urls):
        raise Reject(f"{role} checkout lacks the canonical Goodwu remote")
    if git(root, "status", "--porcelain=v1", "--untracked-files=all"):
        raise Reject(f"{role} source checkout is dirty")


def exact_blob(root: Path, expected_sha: str, rel: Path) -> bytes:
    return subprocess.run(["git", "-C", str(root), "show", f"{expected_sha}:{rel.as_posix()}"],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
                          timeout=20).stdout


def preflight(app: Path, media: Path, app_sha: str, media_sha: str) -> None:
    validate_checkout(app, app_sha, APP_REMOTE, "App")
    validate_checkout(media, media_sha, MEDIA_REMOTE, "media-kit")
    for rel in (APP_VERIFIER, APP_LEDGER):
        path = app / rel
        if path.is_symlink() or not path.is_file():
            raise Reject(f"App tracked input missing or symlinked: {rel}")
        working = path.read_bytes()
        if working != exact_blob(app, app_sha, rel):
            raise Reject(f"App tracked input differs from expected Git blob: {rel}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-root", type=Path, required=True)
    parser.add_argument("--media-kit-root", type=Path, required=True)
    parser.add_argument("--expected-app-sha", required=True)
    parser.add_argument("--expected-media-kit-sha", required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--readelf", required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--local-input", action="store_true")
    mode.add_argument("--postbuild-plugin", type=Path)
    mode.add_argument("--postbuild-bundle", type=Path)
    parser.add_argument("--result", type=Path)
    parser.add_argument("--write-cmake", type=Path)
    args = parser.parse_args()
    try:
        preflight(args.app_root, args.media_kit_root, args.expected_app_sha,
                  args.expected_media_kit_sha)
        verifier = args.app_root.resolve(strict=True) / APP_VERIFIER
        command = [sys.executable, str(verifier), "--app-root", str(args.app_root),
                   "--media-kit-root", str(args.media_kit_root), "--root", str(args.root),
                   "--receipt", str(args.receipt), "--readelf", args.readelf]
        if args.local_input:
            command.append("--local-input")
        elif args.postbuild_plugin:
            command.extend(("--verify-plugin", str(args.postbuild_plugin)))
        else:
            command.extend(("--verify-bundle", str(args.postbuild_bundle)))
        if args.result:
            command.extend(("--result", str(args.result)))
        if args.write_cmake:
            if not args.local_input:
                raise Reject("--write-cmake is valid only with --local-input")
            command.extend(("--write-cmake", str(args.write_cmake)))
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, check=False, timeout=180)
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        return result.returncode
    except (OSError, Reject, subprocess.SubprocessError) as error:
        print(f"routing Linux trusted preflight rejected input: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
