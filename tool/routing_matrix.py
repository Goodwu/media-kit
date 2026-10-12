#!/usr/bin/env python3
"""Build the eight accepted-input Android HDR lab matrix rows serially.

This is a consumer/evidence runner. It never produces or weakens libmpv and it
never attests that the declared fixture has been copied to, or played on, a
device. Native authorization comes only from the fixed App acceptance ledger.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import stat
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / "media_kit_hdr_lab"
APP_GATE = "scripts/verify_routing_native_inputs.py"
APP_ACQUIRE = "scripts/acquire_routing_native_inputs.py"
APP_LEDGER = "docs/plans/routing-native-accepted-inputs.json"
IDENTITY_SOURCE = "media_kit_hdr_lab/lib/common/sources/android_hdr_sample_identity.dart"
HEX40 = re.compile(r"[0-9a-f]{40}\Z")
HEX64 = re.compile(r"[0-9a-f]{64}\Z")
KINDS = ("p5", "p84", "hdr10", "hlg")
APPROVED_JAR_MEMBERS = {
    "lib/arm64-v8a/libmpv.so", "lib/arm64-v8a/libmediakitandroidhelper.so",
    "lib/arm64-v8a/libc++_shared.so",
}
FLUTTER_APK_MEMBERS = {
    "lib/arm64-v8a/libflutter.so", "lib/arm64-v8a/libapp.so",
}
SAMPLES = {"p5": "dolbyVisionP5", "p84": "dolbyVisionP84",
           "hdr10": "hdr10", "hlg": "hlgBaseControl"}


class MatrixError(RuntimeError):
    pass


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run(argv: list[str], *, cwd: Path, env: dict[str, str], log: Path | None = None,
        receipt: list[dict] | None = None) -> subprocess.CompletedProcess:
    if shutil.disk_usage(cwd).free < 512 * 1024 * 1024:
        raise MatrixError("less than 512 MiB free; refusing new command/output")
    step: dict = {"argv": argv, "cwd": str(cwd), "exitCode": None}
    if receipt is not None:
        receipt.append(step)
    result = subprocess.run(argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    step["exitCode"] = result.returncode
    step["stdoutSha256"] = sha_bytes(result.stdout)
    step["stderrSha256"] = sha_bytes(result.stderr)
    if log is not None:
        log.write_bytes(result.stdout + (b"\n--- stderr ---\n" if result.stderr else b"") + result.stderr)
        step["log"] = str(log)
        step["logSha256"] = sha_file(log)
    if result.returncode:
        raise MatrixError(f"command failed ({result.returncode}): {argv[0]}")
    return result


def git(root: Path, *args: str) -> str:
    result = subprocess.run(["git", *args], cwd=root, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise MatrixError(f"git {' '.join(args)} failed in {root}: " +
                          result.stderr.decode("utf-8", "replace").strip())
    return result.stdout.decode("utf-8", "strict").strip()


def source_identity(root: Path, label: str) -> dict:
    root = root.resolve(strict=True)
    top = Path(git(root, "rev-parse", "--show-toplevel")).resolve(strict=True)
    if top != root:
        raise MatrixError(f"{label} root is not the Git top-level: {top}")
    status = git(root, "status", "--porcelain=v1", "--untracked-files=all")
    if status:
        raise MatrixError(f"{label} checkout is dirty; refusing matrix build")
    head = git(root, "rev-parse", "HEAD")
    tree = git(root, "rev-parse", "HEAD^{tree}")
    if not HEX40.fullmatch(head) or not HEX40.fullmatch(tree):
        raise MatrixError(f"{label} Git identity is malformed")
    branch = git(root, "branch", "--show-current")
    tracking = git(root, "config", f"branch.{branch}.remote")
    if not tracking or tracking == ".":
        raise MatrixError(f"{label} branch has no named remote tracking source")
    remote_url = git(root, "remote", "get-url", tracking)
    if "github.com/Goodwu/" not in remote_url:
        raise MatrixError(f"{label} tracking remote is not the registered Goodwu source")
    remote = git(root, "ls-remote", "--exit-code", tracking,
                 "refs/heads/routing/MK-ROUTING-20261011").split()
    if len(remote) != 2 or remote[0] != head:
        raise MatrixError(f"{label} source is not the current origin routing branch HEAD")
    return {"root": str(root), "branch": branch, "trackingRemote": tracking,
            "remoteUrl": remote_url, "head": head, "tree": tree, "status": "clean",
            "remoteRef": "refs/heads/routing/MK-ROUTING-20261011", "remoteHead": remote[0]}


def sdk_identity(flutter: Path) -> dict:
    executable = flutter.resolve(strict=True)
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise MatrixError("--flutter must name an executable Flutter binary")
    # Flutter's checked-in executable is <sdk>/bin/flutter; symlink wrappers
    # are resolved first so the receipt identifies the actual SDK checkout.
    sdk_root = executable.parent.parent
    head = git(sdk_root, "rev-parse", "HEAD")
    tree = git(sdk_root, "rev-parse", "HEAD^{tree}")
    patch = subprocess.run(["git", "diff", "HEAD", "--binary"], cwd=sdk_root,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if patch.returncode:
        raise MatrixError("cannot capture Flutter SDK patch")
    untracked = git(sdk_root, "ls-files", "--others", "--exclude-standard")
    if untracked:
        raise MatrixError("private Flutter SDK has untracked non-ignored files outside the reviewed patch capture")
    return {"root": str(sdk_root), "head": head, "tree": tree,
            "trackedPatchSha256": sha_bytes(patch.stdout),
            "trackedPatchBytes": len(patch.stdout), "untrackedPaths": untracked.splitlines(),
            "flutterExecutable": str(executable),
            "engineInputs": sdk_engine_inputs(sdk_root)}


def bound_input_snapshot(root: Path, paths, *, allow_missing=False) -> dict:
    """Freeze dereferenced bytes and link identity within one exact input root."""
    root = root.resolve(strict=True)
    found = {}
    visited_count = 0

    def link_parents(path):
        for parent in reversed(path.parents):
            if parent == root or not parent.is_relative_to(root):
                continue
            if parent.is_symlink():
                target = parent.resolve(strict=True)
                if not target.is_relative_to(root):
                    raise MatrixError("input symlink escapes exact source root")
                found[parent.relative_to(root).as_posix()] = {
                    "link": os.readlink(parent), "canonicalTarget": str(target.relative_to(root))}

    def visit(path, ancestors, depth):
        nonlocal visited_count
        visited_count += 1
        if visited_count > 200000 or depth > 128:
            raise MatrixError("input traversal exceeds bounded directory contract")
        canonical = path.resolve(strict=True)
        if not canonical.is_relative_to(root):
            raise MatrixError("input symlink escapes exact source root")
        relative = path.relative_to(root).as_posix()
        info = path.lstat()
        target_info = canonical.stat()
        record = {"canonicalTarget": str(canonical.relative_to(root)),
                  "mode": stat.S_IMODE(target_info.st_mode)}
        if stat.S_ISLNK(info.st_mode):
            record["link"] = os.readlink(path)
        if stat.S_ISDIR(target_info.st_mode):
            identity = (target_info.st_dev, target_info.st_ino)
            if identity in ancestors:
                raise MatrixError("input directory symlink cycle")
            record["kind"] = "directory"
            found[relative] = record
            for child in sorted(path.iterdir()):
                visit(child, ancestors | {identity}, depth + 1)
        elif stat.S_ISREG(target_info.st_mode):
            record.update(kind="file", sha256=sha_file(canonical), bytes=target_info.st_size)
            found[relative] = record
        else:
            raise MatrixError("input target is not a regular file/directory")

    try:
        for relative in paths:
            if not relative or Path(relative).is_absolute() or ".." in Path(relative).parts:
                raise MatrixError("input path escapes exact source root")
            path = root / relative
            if allow_missing and not path.exists() and not path.is_symlink():
                continue
            link_parents(path)
            visit(path, set(), 0)
    except (OSError, RuntimeError) as error:
        if isinstance(error, MatrixError):
            raise
        raise MatrixError("cannot read/resolve exact input closure: " + str(error)) from error
    return found


def sdk_engine_inputs(sdk_root: Path) -> dict:
    """Ignored artifacts and legal SDK-internal link targets are actual inputs."""
    roots = ("bin/cache/artifacts/engine", "bin/cache/dart-sdk",
             "bin/cache/flutter_tools.snapshot", "bin/cache/engine.stamp",
             "bin/internal/engine.version", "bin/internal/engine.realm",
             "packages/flutter_tools/.dart_tool/package_config.json",
             "packages/flutter_tools/pubspec.lock")
    return bound_input_snapshot(sdk_root, roots, allow_missing=True)


def flutter_variant_contract(sdk_root: Path) -> dict:
    source = sdk_root / "packages/flutter_tools/lib/src/asset.dart"
    if source.is_symlink() or not source.is_file():
        raise MatrixError("SDK asset variant implementation must be a regular source input")
    text = source.read_text(encoding="utf-8")
    expected = "final _assetVariantDirectoryRegExp = RegExp(r'/?(\\d+(\\.\\d*)?)x$');"
    if expected not in text or not all(marker in text for marker in (
        ".where((Directory dir) => _assetVariantDirectoryRegExp.hasMatch(dir.basename))",
        ".where((File file) => file.basename == basename)",
        "if (assetFile.existsSync()) assetPath,")):
        raise MatrixError("SDK implicit asset variant contract requires review")
    return {"sourcePath": str(source.resolve()), "sourceSha256": sha_file(source),
            "directoryPattern": r"/?([0-9]+(\.[0-9]*)?)x$", "recursiveVariants": False}


def resource_input_snapshot(root: Path, relative: str, *, directory: bool, kind: str,
                            contract: dict | None = None) -> dict:
    """Follow Flutter's immediate-file and one-level resolution-variant rules."""
    root = root.resolve(strict=True)
    pattern = (contract or {}).get("directoryPattern", r"/?([0-9]+(\.[0-9]*)?)x$")
    if pattern != r"/?([0-9]+(\.[0-9]*)?)x$":
        raise MatrixError("unsupported implicit asset variant directory rule")
    variant_pattern = re.compile(pattern)
    if not relative or Path(relative).is_absolute() or ".." in Path(relative).parts:
        raise MatrixError("declared package resource escapes exact package root")
    path = root / relative
    selected = set()
    directory_identity = None

    def confined(candidate):
        canonical = candidate.resolve(strict=True)
        if not canonical.is_relative_to(root):
            raise MatrixError("declared package resource escapes exact package root")
        return canonical

    def entries(parent):
        canonical = confined(parent)
        if not canonical.is_dir():
            raise MatrixError("resource parent is not a directory")
        children = sorted(parent.iterdir())
        if len(children) > 10000:
            raise MatrixError("resource directory scan exceeds bounded variant contract")
        return children

    def file_and_variants(base):
        if base.exists() or base.is_symlink():
            canonical = confined(base)
            if not canonical.is_file():
                raise MatrixError("declared resource base is not a regular file")
            selected.add(base.relative_to(root).as_posix())
        if kind == "font":
            if not base.exists():
                raise MatrixError("declared font file is missing")
            return
        # asset.dart variantsFor scans directories immediately under the
        # declared file's parent. Its regex uses hasMatch, not fullMatch.
        for candidate in entries(base.parent):
            if not variant_pattern.search(candidate.name):
                continue
            canonical = confined(candidate)
            if not canonical.is_dir():
                continue
            for variant in entries(candidate):
                if variant.name != base.name:
                    continue
                canonical_file = confined(variant)
                if canonical_file.is_file():
                    selected.add(variant.relative_to(root).as_posix())
        if not selected:
            raise MatrixError("declared resource has no base file or implicit variant")

    try:
        if directory:
            if kind != "asset":
                raise MatrixError("only asset declarations may name a directory")
            canonical = confined(path)
            if not canonical.is_dir():
                raise MatrixError("declared package resource file/directory type mismatch")
            info = canonical.stat()
            directory_identity = {"canonicalTarget": str(canonical.relative_to(root)),
                                  "mode": stat.S_IMODE(info.st_mode)}
            if path.is_symlink():
                directory_identity["link"] = os.readlink(path)
            for child in entries(path):
                if child.is_file():
                    file_and_variants(child)
                elif child.is_symlink():
                    # Broken/escaping directory entries cannot become silently
                    # accepted missing inputs; normal nested directories are not
                    # recursive Flutter asset wildcards.
                    confined(child)
        else:
            file_and_variants(path)
        return {"directoryIdentity": directory_identity,
                "memberPaths": sorted(selected), "inputs": bound_input_snapshot(root, sorted(selected))}
    except (OSError, RuntimeError) as error:
        if isinstance(error, MatrixError):
            raise
        raise MatrixError("cannot read/resolve declared resource variants: " + str(error)) from error


def android_precache(flutter: Path, output: Path, env: dict, commands: list) -> dict:
    run([str(flutter), "precache", "--android"], cwd=output, env=env,
        log=output / "android-precache.log", receipt=commands)
    frozen = sdk_identity(flutter)
    engine = Path(frozen["root"]) / "bin/cache/artifacts/engine/android-arm64-release"
    if not engine.is_dir() or not any(path.name == "libflutter.so" for path in engine.rglob("*")):
        raise MatrixError("Android precache did not provide arm64 release engine")
    if "bin/internal/engine.version" not in frozen["engineInputs"]:
        raise MatrixError("SDK engine version is absent from frozen Android input closure")
    revision = (Path(frozen["root"]) / "bin/internal/engine.version").read_text().strip()
    stamp = Path(frozen["root"]) / "bin/cache/engine.stamp"
    if not HEX40.fullmatch(revision) or not stamp.is_file() or stamp.read_text().strip() != revision:
        raise MatrixError("cached engine stamp differs from the tracked SDK engine revision")
    return frozen


def read_json(path: Path, label: str) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 16 * 1024 * 1024:
        raise MatrixError(f"{label} must be a bounded regular file")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise MatrixError(f"{label} is invalid JSON: {error}") from error
    if not isinstance(value, dict):
        raise MatrixError(f"{label} must be a JSON object")
    return value


def known_fixture_kinds(identity_file: Path) -> dict[str, str]:
    text = identity_file.read_text(encoding="utf-8")
    matches = re.findall(r"'([0-9a-f]{64})'\s*:\s*AndroidHdrSample\.(\w+)", text)
    found: dict[str, str] = {}
    for digest, sample in matches:
        kind = next((key for key, value in SAMPLES.items() if value == sample), None)
        if kind is None:
            continue
        if digest in found and found[digest] != kind:
            raise MatrixError("source fixture digest is mapped to conflicting samples")
        found[digest] = kind
    for kind in KINDS:
        if kind not in found.values():
            raise MatrixError(f"current lab source has no byte-identity digest for {kind}")
    return found


def _video_stream(probe: dict) -> dict:
    streams = probe.get("streams")
    if not isinstance(streams, list):
        raise MatrixError("ffprobe has no streams array")
    videos = [item for item in streams if isinstance(item, dict) and item.get("codec_type") == "video"]
    if len(videos) != 1:
        raise MatrixError("fixture must contain exactly one video stream")
    stream = videos[0]
    if stream.get("codec_name") != "hevc":
        raise MatrixError("fixture video codec must be HEVC")
    return stream


def dovi_record(stream: dict) -> dict | None:
    side = stream.get("side_data_list", [])
    if not isinstance(side, list):
        raise MatrixError("ffprobe side_data_list is malformed")
    records = [item for item in side if isinstance(item, dict) and
               item.get("side_data_type") == "DOVI configuration record"]
    if len(records) > 1:
        raise MatrixError("fixture has ambiguous Dolby Vision configuration")
    return records[0] if records else None


def probe_projection(probe: dict, kind: str) -> dict:
    stream = _video_stream(probe)
    dovi = dovi_record(stream)
    fields = ("codec_name", "profile", "width", "height", "pix_fmt",
              "color_range", "color_space", "color_transfer", "color_primaries")
    projection = {key: stream.get(key) for key in fields}
    projection["dovi"] = dovi
    if kind == "p5":
        # DV Profile 5 may omit VUI color tags. If present, reject contradictory
        # tags while preserving the actual DOVI configuration as the authority.
        if stream.get("color_primaries") not in (None, "bt2020"):
            raise MatrixError("p5 fixture has contradictory color primaries")
        if stream.get("color_space") not in (None, "bt2020nc", "bt2020c"):
            raise MatrixError("p5 fixture has a contradictory color matrix")
        if stream.get("color_transfer") not in (None, "smpte2084"):
            raise MatrixError("p5 fixture has a contradictory transfer")
    else:
        if stream.get("color_primaries") != "bt2020":
            raise MatrixError(f"{kind} fixture must signal BT.2020 primaries")
        if stream.get("color_space") not in ("bt2020nc", "bt2020c"):
            raise MatrixError(f"{kind} fixture must signal a BT.2020 matrix")
    if kind in ("p5", "p84"):
        if dovi is None:
            raise MatrixError(f"{kind} fixture lacks actual DOVI configuration record")
        expected_profile, expected_compat = (5, 0) if kind == "p5" else (8, 4)
        for key in ("dv_profile", "dv_bl_signal_compatibility_id", "el_present_flag",
                    "rpu_present_flag", "bl_present_flag"):
            if type(dovi.get(key)) is not int:
                raise MatrixError(f"{kind} DOVI field {key} is missing or non-integer")
        if (dovi["dv_profile"] != expected_profile or
                dovi["dv_bl_signal_compatibility_id"] != expected_compat or
                dovi["el_present_flag"] != 0 or dovi["rpu_present_flag"] != 1 or
                dovi["bl_present_flag"] != 1):
            raise MatrixError(f"{kind} Dolby Vision profile/compatibility/EL facts conflict")
    else:
        if dovi is not None:
            raise MatrixError(f"{kind} control fixture unexpectedly contains Dolby Vision metadata")
        transfer = "smpte2084" if kind == "hdr10" else "arib-std-b67"
        if stream.get("color_transfer") != transfer:
            raise MatrixError(f"{kind} fixture transfer is not {transfer}")
    if kind == "p84" and stream.get("color_transfer") != "arib-std-b67":
        raise MatrixError("p84 fixture must signal HLG-compatible base-layer transfer")
    return projection


def validate_fixtures(path: Path, ffprobe: Path, receipt: dict, env: dict[str, str]) -> dict:
    spec = read_json(path, "fixture evidence")
    if set(spec) != {"schemaVersion", "fixtures"} or spec["schemaVersion"] != 1 or not isinstance(spec["fixtures"], dict):
        raise MatrixError("fixture evidence schema mismatch")
    if set(spec["fixtures"]) != set(KINDS):
        raise MatrixError("fixtures must contain exactly p5, p84, hdr10, and hlg")
    known = known_fixture_kinds(ROOT / IDENTITY_SOURCE)
    results = {}
    for kind in KINDS:
        item = spec["fixtures"][kind]
        if not isinstance(item, dict) or set(item) != {"path", "sha256", "devicePath", "probeEvidence"}:
            raise MatrixError(f"{kind} fixture record fields mismatch")
        if not isinstance(item["path"], str) or not item["path"]:
            raise MatrixError(f"{kind} fixture path is invalid")
        source_input = Path(item["path"])
        if source_input.is_symlink():
            raise MatrixError(f"{kind} local fixture may not be a symbolic link")
        source = source_input.resolve(strict=True)
        if not source.is_file() or source.is_symlink():
            raise MatrixError(f"{kind} local fixture must be a regular file")
        claimed = item["sha256"]
        if not isinstance(claimed, str) or not HEX64.fullmatch(claimed):
            raise MatrixError(f"{kind} fixture SHA-256 malformed")
        actual = sha_file(source)
        if actual != claimed or known.get(actual) != kind:
            raise MatrixError(f"{kind} bytes do not match the current lab identity map")
        device_path = item["devicePath"]
        if (not isinstance(device_path, str) or
                not re.fullmatch(rf"/data/local/tmp/media-kit-{kind}-[a-z0-9][a-z0-9._-]*\.mp4", device_path)):
            raise MatrixError(f"{kind} device path does not match the lab's controlled fixture pattern")
        if not isinstance(item["probeEvidence"], str) or not item["probeEvidence"]:
            raise MatrixError(f"{kind} prior ffprobe evidence path is invalid")
        evidence_input = Path(item["probeEvidence"])
        if evidence_input.is_symlink():
            raise MatrixError(f"{kind} prior ffprobe evidence may not be a symbolic link")
        evidence = evidence_input.resolve(strict=True)
        sidecar = read_json(evidence, f"{kind} prior ffprobe evidence")
        if set(sidecar) != {"schemaVersion", "fixtureSha256", "probe"} or sidecar["schemaVersion"] != 1 or sidecar["fixtureSha256"] != actual or not isinstance(sidecar["probe"], dict):
            raise MatrixError(f"{kind} prior ffprobe evidence is not bound to these bytes")
        command = [str(ffprobe), "-v", "error", "-show_streams", "-show_format", "-of", "json", str(source)]
        result = run(command, cwd=ROOT, env=env, receipt=receipt.setdefault("commands", []))
        if sha_file(source) != actual:
            raise MatrixError(f"{kind} fixture bytes changed while ffprobe was reading them")
        try:
            actual_probe = json.loads(result.stdout)
        except (UnicodeError, json.JSONDecodeError) as error:
            raise MatrixError(f"{kind} ffprobe output is invalid JSON") from error
        current_projection = probe_projection(actual_probe, kind)
        sidecar_projection = probe_projection(sidecar["probe"], kind)
        if current_projection != sidecar_projection:
            raise MatrixError(f"{kind} ffprobe output differs from hash-bound prior evidence")
        results[kind] = {"path": str(source), "sha256": actual,
            "probeEvidencePath": str(evidence), "probeEvidenceSha256": sha_file(evidence),
            "probeCommand": command, "probeStdoutSha256": sha_bytes(result.stdout),
            "probe": current_projection, "localContentVerified": True,
            "devicePath": device_path, "deviceFixtureVerified": False}
    return results


def define_vector(kind: str, gate_open: bool, fixture: dict) -> list[str]:
    defines = [
        "--dart-define=MEDIA_KIT_ANDROID_NAMED_LOCAL_SOURCE=true",
        f"--dart-define=MEDIA_KIT_ANDROID_LOCAL_SOURCE={fixture['devicePath']}",
        f"--dart-define=MEDIA_KIT_ANDROID_HDR_GATE_OPEN={'true' if gate_open else 'false'}",
        "--dart-define=MEDIA_KIT_ANDROID_HDR_POLICY_EXPERIMENTAL=false",
    ]
    # The sample name is diagnostic input routing, while its bytes have already
    # been independently matched against the current content identity map.
    if kind not in KINDS:
        raise MatrixError("unknown matrix kind")
    return defines


def expected_native_member_sources(jar_members: set[str], lab: Path,
                                   package_roots: dict[str, str]) -> dict[str, dict]:
    if jar_members != APPROVED_JAR_MEMBERS:
        raise MatrixError("accepted JAR manifest does not declare its exact three-member closure")
    expected = {name: {"kind": "accepted-native-jar"} for name in jar_members}
    for name in FLUTTER_APK_MEMBERS:
        expected[name] = {"kind": "flutter-runtime"}
    roots = {Path(path).resolve() for path in package_roots.values()}
    roots.add(lab.resolve())
    for root in sorted(roots):
        android_root = root / "android"
        if not android_root.is_dir():
            continue
        modules = [android_root / "app"] if root == lab.resolve() else [android_root]
        for module in modules:
            scripts = [file for file in (module / "build.gradle", module / "build.gradle.kts") if file.is_file()]
            if len(scripts) > 1:
                raise MatrixError("ambiguous native Gradle module script")
            if not scripts:
                continue
            gradle = scripts[0]
            gradle_text = gradle.read_text(encoding="utf-8")
            if "externalNativeBuild" not in gradle_text:
                continue
            paths = re.findall(r"path\s*(?:=\s*)?file\(\s*['\"]([^'\"]+CMakeLists\.txt)['\"]\s*\)", gradle_text)
            if len(paths) != 1:
                raise MatrixError("native Gradle CMake path is not the reviewed literal input contract")
            cmake = (module / paths[0]).resolve(strict=True)
            if not cmake.is_relative_to(module.resolve()) or cmake.is_symlink():
                raise MatrixError("native CMake source escapes module")
            source = cmake.read_text(encoding="utf-8")
            source = re.sub(r"(?s)#\[\[.*?\]\]", "", source)
            source = re.sub(r"(?m)#.*$", "", source)
            for target in re.findall(r"(?is)add_library\s*\(\s*([A-Za-z0-9_.+-]+)\s+SHARED\b", source):
                name = f"lib/arm64-v8a/lib{target}.so"
                if name in expected:
                    raise MatrixError(f"multiple source producers claim native library {name}")
                expected[name] = {"kind": "cmake-shared-target", "target": target,
                    "cmakeLists": str(cmake), "moduleRoot": str(module.resolve()),
                    "gradleScript": str(gradle.resolve()), "gradleScriptSha256": sha_file(gradle)}
        for subtree in (android_root / "src/main/jniLibs", android_root / "libs"):
            if not subtree.is_dir():
                continue
            for path in sorted(subtree.rglob("*.so")):
                if path.is_symlink() or "arm64-v8a" not in path.parts:
                    continue
                name = f"lib/arm64-v8a/{path.name}"
                if name in expected:
                    raise MatrixError(f"multiple source producers claim native library {name}")
                expected[name] = {"kind": "source-jni-library", "source": str(path.resolve()),
                                  "sourceSha256": sha_file(path),
                                  "moduleRoot": str(_android_module_root(path))}
    return expected


def _android_module_root(path: Path) -> Path:
    parts = path.resolve().parts
    indexes = [index for index, part in enumerate(parts) if part == "android"]
    if not indexes:
        raise MatrixError(f"native source is not under an Android module: {path}")
    index = indexes[-1]
    if index + 1 >= len(parts):
        raise MatrixError(f"native Android module path is incomplete: {path}")
    android = Path(*parts[:index + 1])
    if path.resolve().is_relative_to(android / "app"):
        return android / "app"
    return android


def native_build_output_roots(lab: Path, module: Path, package_roots: dict) -> list[Path]:
    """Bind the checked-in Gradle relocation, not a guessed android/src module."""
    gradle = lab / "android/build.gradle.kts"
    if not gradle.is_file() or gradle.is_symlink():
        raise MatrixError("Lab Gradle output graph is missing")
    text = gradle.read_text(encoding="utf-8")
    required = ('rootProject.layout.buildDirectory.dir("../../build")',
                'newBuildDir.dir(project.name)', 'project.layout.buildDirectory.value(newSubprojectBuildDir)')
    if not all(part in text for part in required):
        raise MatrixError("unreviewed Lab Gradle output relocation")
    module = module.resolve(strict=True)
    if module == (lab / "android/app").resolve():
        name = "app"
    else:
        names = [name for name, root in package_roots.items()
                 if module == (Path(root) / "android").resolve()]
        if len(names) != 1:
            raise MatrixError("native module lacks unique package/Gradle project identity")
        name = names[0]
    return [lab / "build" / name, module / ".cxx", module / ".externalNativeBuild"]


def exact_native_members(apk: Path, expected_members: set[str]) -> dict:
    with zipfile.ZipFile(apk) as archive:
        names = [item.filename for item in archive.infolist()]
        actual = {name for name in names if name.startswith("lib/")}
        if actual != expected_members or len(actual) != sum(1 for name in names if name.startswith("lib/")):
            raise MatrixError("APK native ABI/member set differs from the source-derived producer closure")
        return {name: sha_bytes(archive.read(name)) for name in sorted(expected_members)}


def require_fresh_apk_path(apk: Path) -> None:
    if apk.exists() or apk.is_symlink():
        raise MatrixError("isolated row copy unexpectedly contains an old APK before build")


def _matching_build_outputs(root: Path, names: set[str], expected_sha: str) -> list[Path]:
    if not root.is_dir():
        return []
    result = []
    for candidate in root.rglob("*"):
        if candidate.is_symlink() or not candidate.is_file() or candidate.name not in names:
            continue
        if sha_file(candidate) == expected_sha:
            result.append(candidate.resolve())
    return sorted(set(result))


def verify_native_provenance(apk: Path, jar: Path, flutter_root: Path, lab: Path,
                             output: Path, readelf: Path, env: dict[str, str],
                             commands: list[dict], package_roots: dict[str, str]) -> dict:
    with zipfile.ZipFile(jar) as archive:
        jar_payload = {name: archive.read(name) for name in APPROVED_JAR_MEMBERS}
    producers = expected_native_member_sources(set(jar_payload), lab, package_roots)
    expected_members = set(producers)
    members = exact_native_members(apk, expected_members)
    with zipfile.ZipFile(apk) as archive:
        apk_payload = {name: archive.read(name) for name in expected_members}
    native_dir = output / "native-members"
    native_dir.mkdir(mode=0o700)
    member_receipts = {}
    for name in sorted(expected_members):
        payload = apk_payload[name]
        if name in APPROVED_JAR_MEMBERS and payload != jar_payload[name]:
            raise MatrixError(f"APK JAR member differs from the selected accepted JAR: {name}")
        path = native_dir / Path(name).name
        path.write_bytes(payload)
        result = run([str(readelf), "-hW", str(path)], cwd=lab, env=env,
                     receipt=commands)
        header = result.stdout.decode("utf-8", "replace")
        if (result.stderr or not re.search(r"(?m)^\s*Class:\s+ELF64\s*$", header) or
                not re.search(r"(?m)^\s*Machine:\s+AArch64\s*$", header) or
                not re.search(r"(?m)^\s*Type:\s+DYN\s+\(Shared object file\)", header)):
            raise MatrixError(f"APK native member is not a readable ELF64 AArch64 shared object: {name}")
        member_receipts[name] = {"sha256": members[name],
            "elf": {"class": "ELF64", "machine": "AArch64", "type": "DYN",
                    "readelfCommand": commands[-1]["argv"],
                    "stdoutSha256": sha_bytes(result.stdout),
                    "stderrSha256": sha_bytes(result.stderr)}}

    for name in sorted(APPROVED_JAR_MEMBERS):
        member_receipts[name]["producer"] = {"kind": "accepted-native-jar",
            "jar": str(jar.resolve()), "jarSha256": sha_file(jar),
            "memberSha256": sha_bytes(jar_payload[name])}

    engine_candidates = [
        flutter_root / "bin/cache/artifacts/engine/android-arm64-release/linux-x64/libflutter.so",
        flutter_root / "bin/cache/artifacts/engine/android-arm64-release/libflutter.so",
    ]
    engine_hash = members["lib/arm64-v8a/libflutter.so"]
    engine_sources = [path.resolve() for path in engine_candidates
                      if path.is_file() and not path.is_symlink() and sha_file(path) == engine_hash]
    if not engine_sources:
        raise MatrixError("libflutter.so does not resolve to this private Flutter SDK engine artifact")
    member_receipts["lib/arm64-v8a/libflutter.so"]["producer"] = {
        "kind": "private-flutter-sdk-engine", "sdkRoot": str(flutter_root.resolve()),
        "sources": [{"path": str(path), "sha256": sha_file(path)} for path in engine_sources]}

    app_hash = members["lib/arm64-v8a/libapp.so"]
    app_output_roots = [lab / "build", lab / "android/app/build"]
    app_sources = sorted({path for root in app_output_roots
        for path in _matching_build_outputs(root, {"libapp.so", "app.so"}, app_hash)})
    if not app_sources:
        raise MatrixError("libapp.so has no byte-matching current isolated Flutter AOT build output")
    member_receipts["lib/arm64-v8a/libapp.so"]["producer"] = {
        "kind": "current-isolated-flutter-aot-output",
        "sources": [{"path": str(path), "sha256": sha_file(path)} for path in app_sources]}

    for name, producer in producers.items():
        if name in APPROVED_JAR_MEMBERS or name in FLUTTER_APK_MEMBERS:
            continue
        base_name = Path(name).name
        module_root = Path(producer["moduleRoot"])
        build_roots = native_build_output_roots(lab, module_root, package_roots)
        outputs = sorted({path for root in build_roots
            for path in _matching_build_outputs(root, {base_name}, members[name])})
        if not outputs:
            raise MatrixError(f"native library has no byte-matching current build output: {name}")
        producer_record = dict(producer)
        producer_record["buildSourceKind"] = "current-isolated-cmake-ndk-build-output" if producer["kind"] == "cmake-shared-target" else "current-isolated-android-native-build-output"
        module_root = Path(producer["moduleRoot"])
        module_inputs = source_tree_snapshot(module_root, output_roots=("build", ".cxx", ".externalNativeBuild"))
        producer_record["moduleSourceTree"] = {
            "root": str(module_root), "fileCount": len(module_inputs),
            "sha256": sha_bytes(json.dumps(module_inputs, sort_keys=True).encode())}
        producer_record["currentBuildOutputs"] = [
            {"path": str(path), "sha256": sha_file(path)} for path in outputs]
        if producer["kind"] == "cmake-shared-target":
            cmake_file = Path(producer["cmakeLists"])
            producer_record["cmakeListsSha256"] = sha_file(cmake_file)
            if cmake_file.is_relative_to(lab.resolve()):
                producer_record["gradleBuildFile"] = {
                    "path": str(lab / "android/app/build.gradle.kts"),
                    "sha256": sha_file(lab / "android/app/build.gradle.kts")}
        member_receipts[name]["producer"] = producer_record
    return {"apkSha256": sha_file(apk), "nativeMembers": member_receipts,
            "nativeMemberPolicy": "exact App-accepted JAR closure + Flutter runtime + source-derived native consumers"}


def native_fingerprints(jar: Path, manifest: Path, ledger: Path) -> dict:
    return {"jarSha256": sha_file(jar), "manifestSha256": sha_file(manifest),
            "ledgerSha256": sha_file(ledger)}


def assert_native_fingerprints(jar: Path, manifest: Path, ledger: Path,
                               expected: dict) -> None:
    if native_fingerprints(jar, manifest, ledger) != expected:
        raise MatrixError("accepted JAR/manifest/ledger changed during matrix")


def signer_certificate(apksigner: Path, apk: Path, env: dict[str, str], commands: list[dict]) -> dict:
    result = run([str(apksigner), "verify", "--verbose", "--print-certs", str(apk)],
                 cwd=ROOT, env=env, receipt=commands)
    text = result.stdout.decode("utf-8", "replace") + "\n" + result.stderr.decode("utf-8", "replace")
    matches = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})", text)
    if not matches:
        raise MatrixError("apksigner verified no signer certificate digest")
    return {"certificateSha256": [value.lower() for value in matches],
            "stdoutSha256": sha_bytes(result.stdout), "stderrSha256": sha_bytes(result.stderr)}


def toolchain_identity(args: argparse.Namespace, env: dict[str, str],
                       commands: list[dict], output: Path) -> dict:
    sdk = args.android_sdk.resolve()
    for path, label in ((args.readelf.resolve(), "readelf"), (args.nm.resolve(), "nm")):
        if not path.is_relative_to(sdk / "ndk"):
            raise MatrixError(f"{label} must come from the explicitly selected Android SDK NDK")
    if not args.apksigner.resolve().is_relative_to(sdk / "build-tools"):
        raise MatrixError("apksigner must come from the explicitly selected Android SDK build-tools")
    java = args.java_home / "bin/java"
    if not java.is_file() or not os.access(java, os.X_OK):
        raise MatrixError("--java-home has no executable bin/java")
    java_result = run([str(java), "-version"], cwd=ROOT, env=env,
                      log=output / "java-version.log", receipt=commands)
    signer_result = run([str(args.apksigner), "--version"], cwd=ROOT, env=env,
                        log=output / "apksigner-version.log", receipt=commands)
    sdk_properties = []
    for pattern in ("build-tools/*/source.properties", "platforms/android-*/source.properties",
                    "ndk/*/source.properties"):
        for path in sorted(sdk.glob(pattern)):
            if path.is_file() and not path.is_symlink():
                sdk_properties.append({"path": str(path), "sha256": sha_file(path),
                                       "text": path.read_text(encoding="utf-8", errors="replace")})
    if not any(item["path"].startswith(str(sdk / "build-tools") + "/") for item in sdk_properties):
        raise MatrixError("selected Android SDK has no build-tools source.properties")
    if not any(item["path"].startswith(str(sdk / "ndk") + "/") for item in sdk_properties):
        raise MatrixError("selected Android SDK has no NDK source.properties")
    return {"java": {"path": str(java.resolve()), "sha256": sha_file(java),
                      "versionLogSha256": sha_file(output / "java-version.log"),
                      "stdoutSha256": sha_bytes(java_result.stdout),
                      "stderrSha256": sha_bytes(java_result.stderr)},
            "readelf": {"path": str(args.readelf.resolve()), "sha256": sha_file(args.readelf)},
            "nm": {"path": str(args.nm.resolve()), "sha256": sha_file(args.nm)},
            "apksigner": {"path": str(args.apksigner.resolve()), "sha256": sha_file(args.apksigner),
                          "versionSha256": sha_file(output / "apksigner-version.log"),
                          "versionOutputSha256": sha_bytes(signer_result.stdout)},
            "ffprobe": {"path": str(args.ffprobe.resolve()), "sha256": sha_file(args.ffprobe)},
            "androidSdkPackages": sdk_properties}


def matrix_rows(fixtures: dict) -> list[dict]:
    return [{"kind": kind, "gateOpen": gate_open,
             "allowExperimental": gate_open, "hdrPolicyExperimental": False,
             "tag": f"{kind}-gate-{'open' if gate_open else 'closed'}",
             "defines": define_vector(kind, gate_open, fixtures[kind])}
            for kind in KINDS for gate_open in (False, True)]


def safe_git_archive(media_root: Path, destination: Path, expected_head: str) -> dict:
    if destination.exists() or destination.is_symlink():
        raise MatrixError("isolated media-kit source destination must be new")
    destination.mkdir(parents=True, mode=0o700)
    result = subprocess.run(["git", "archive", "--format=tar", expected_head], cwd=media_root,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise MatrixError("cannot archive the exact media-kit source tree")
    tracked = tracked_source_manifest(media_root, expected_head)
    with tarfile.open(fileobj=__import__("io").BytesIO(result.stdout), mode="r:") as archive:
        members = archive.getmembers()
        for item in members:
            rel = Path(item.name)
            if rel.is_absolute() or ".." in rel.parts or not rel.parts:
                raise MatrixError("source archive contains an unsafe path")
            target = destination / rel
            if item.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif item.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                source = archive.extractfile(item)
                if source is None:
                    raise MatrixError("source archive regular file has no content")
                with target.open("xb") as sink:
                    shutil.copyfileobj(source, sink)
                target.chmod(item.mode & 0o777)
            elif item.issym():
                if Path(item.linkname).is_absolute() or "\\" in item.linkname:
                    raise MatrixError("source archive contains an unsafe symlink")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(item.linkname)
            else:
                raise MatrixError("source archive contains a non-file entry")
    for candidate in destination.rglob("*"):
        if candidate.is_symlink() and not candidate.resolve(strict=False).is_relative_to(destination.resolve()):
            raise MatrixError("source archive symlink escapes isolated source copy")
    verify_tracked_source_copy(destination, tracked, "archived source")
    return {"root": str(destination), "head": expected_head,
            "tree": git(media_root, "rev-parse", f"{expected_head}^{{tree}}"),
            "archiveSha256": sha_bytes(result.stdout), "archiveBytes": len(result.stdout),
            "trackedFiles": tracked, "trackedFileCount": len(tracked)}


def tracked_source_manifest(media_root: Path, expected_head: str) -> dict[str, dict]:
    result = subprocess.run(["git", "ls-tree", "-rz", "--full-tree", expected_head],
        cwd=media_root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise MatrixError("cannot enumerate exact tracked source archive inputs")
    manifest = {}
    for record in result.stdout.split(b"\0"):
        if not record:
            continue
        metadata, raw_path = record.split(b"\t", 1)
        mode, kind, blob = metadata.decode("ascii").split()
        relative = raw_path.decode("utf-8", "strict")
        if kind != "blob" or mode not in ("100644", "100755", "120000"):
            raise MatrixError(f"unsupported tracked source entry: {relative}")
        manifest[relative] = {"mode": mode, "blob": blob}
    if not manifest:
        raise MatrixError("exact tracked source archive input set is empty")
    return manifest


def verify_tracked_source_copy(root: Path, manifest: dict[str, dict], label: str) -> None:
    root = root.resolve(strict=True)
    for relative, expected in manifest.items():
        path = root / relative
        if not path.exists() and not path.is_symlink():
            raise MatrixError(f"{label} lost tracked source: {relative}")
        mode = expected["mode"]
        if mode == "120000":
            if not path.is_symlink():
                raise MatrixError(f"{label} changed tracked symlink type: {relative}")
            payload = os.readlink(path).encode("utf-8")
        else:
            if path.is_symlink() or not path.is_file():
                raise MatrixError(f"{label} changed tracked regular file type: {relative}")
            executable = bool(path.stat().st_mode & 0o111)
            if executable != (mode == "100755"):
                raise MatrixError(f"{label} changed tracked file mode: {relative}")
            payload = path.read_bytes()
        digest = hashlib.sha1(b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload).hexdigest()
        if digest != expected["blob"]:
            raise MatrixError(f"{label} modified exact tracked source: {relative}")


def verify_lab_package_roots(config: Path, source_copy: Path, pub_cache: Path,
                             flutter_root: Path) -> dict:
    packages = json.loads(config.read_text(encoding="utf-8")).get("packages")
    if not isinstance(packages, list) or not packages:
        raise MatrixError("isolated lab package_config is empty or malformed")
    package_names: set[str] = set()
    roots: dict[str, str] = {}
    media_names = {
        "media_kit": "media_kit", "media_kit_video": "media_kit_video",
        "media_kit_android_dataspace_vendor": "libs/android/media_kit_android_dataspace_vendor",
        "media_kit_libs_android_video": "libs/android/media_kit_libs_android_video",
        "media_kit_libs_ios_video": "libs/ios/media_kit_libs_ios_video",
        "media_kit_libs_macos_video": "libs/macos/media_kit_libs_macos_video",
        "media_kit_libs_linux": "libs/linux/media_kit_libs_linux",
        "media_kit_libs_ohos": "libs/ohos/media_kit_libs_ohos",
        "media_kit_libs_video": "libs/universal/media_kit_libs_video",
        "media_kit_libs_windows_video": "libs/windows/media_kit_libs_windows_video",
    }
    lab_root = (source_copy / "media_kit_hdr_lab").resolve(strict=True)
    lab_pubspec = lab_root / "pubspec.yaml"
    if not lab_pubspec.is_file() or lab_pubspec.is_symlink():
        raise MatrixError("isolated lab source lacks a regular pubspec.yaml")
    pubspec_text = lab_pubspec.read_text(encoding="utf-8")
    if not re.search(r"(?m)^name:\s*media_kit_hdr_lab\s*$", pubspec_text):
        raise MatrixError("isolated source pubspec does not declare media_kit_hdr_lab")
    lab_seen = False
    for item in packages:
        if not isinstance(item, dict):
            raise MatrixError("isolated lab package_config entry is malformed")
        name = item.get("name")
        if not isinstance(name, str) or name in package_names:
            raise MatrixError("isolated lab package_config has invalid or duplicate package name")
        package_names.add(name)
        root_uri = urlparse(urljoin(config.resolve().as_uri(), item.get("rootUri", "")))
        if root_uri.scheme != "file" or root_uri.netloc not in ("", "localhost") or root_uri.query or root_uri.fragment:
            raise MatrixError(f"lab package {name} is not resolved from a local path")
        root = Path(url2pathname(root_uri.path)).resolve(strict=True)
        if not root.is_dir():
            raise MatrixError(f"lab package root is not a directory: {name}")
        if name == "media_kit_hdr_lab":
            if root != lab_root:
                raise MatrixError("lab package_config self package does not resolve to isolated lab source")
            lab_seen = True
        elif name.startswith("media_kit"):
            if name not in media_names or root != (source_copy / media_names[name]).resolve(strict=True):
                raise MatrixError(f"lab package {name} escaped the isolated media-kit source")
        elif not any(root.is_relative_to(base.resolve()) for base in
                     (source_copy, pub_cache, flutter_root)):
            raise MatrixError(f"lab package {name} escaped isolated sources/private cache")
        roots[name] = str(root)
    missing = set(media_names) - package_names
    if missing:
        raise MatrixError("lab package_config lacks media-kit packages: " + ", ".join(sorted(missing)))
    if not lab_seen:
        raise MatrixError("lab package_config lacks its own media_kit_hdr_lab package")
    return roots


def source_tree_snapshot(root: Path, *, output_roots=(), allowed_links=None,
                         generated_files=()) -> dict:
    """Only exact root-relative build outputs are excluded; assets/build is input."""
    root = root.resolve(strict=True)
    allowed_links = allowed_links or {}
    result = {}
    for directory, dirs, files in os.walk(root, followlinks=False):
        base = Path(directory)
        for name in list(dirs):
            path = base / name
            relative = path.relative_to(root).as_posix()
            if any(relative == output or relative.startswith(output + "/") for output in output_roots):
                dirs.remove(name)
                continue
            if path.is_symlink():
                dirs.remove(name)
                target = path.resolve(strict=True)
                if allowed_links.get(relative) != str(target):
                    raise MatrixError(f"source/package tree contains an unapproved symlink: {path}")
                result[relative] = {"symlink": os.readlink(path), "target": str(target.relative_to(root)) if target.is_relative_to(root) else str(target)}
        for name in files:
            path = base / name
            relative = path.relative_to(root).as_posix()
            if relative in generated_files:
                continue
            if path.is_symlink():
                target = path.resolve(strict=True)
                if not target.is_relative_to(root) and allowed_links.get(relative) != str(target):
                    raise MatrixError(f"source/package tree contains an escaping symlink: {path}")
                result[relative] = {"symlink": os.readlink(path), "target": str(target.relative_to(root)) if target.is_relative_to(root) else str(target)}
            elif path.is_file():
                result[relative] = {"sha256": sha_file(path), "bytes": path.stat().st_size,
                                   "mode": stat.S_IMODE(path.stat().st_mode)}
            else:
                raise MatrixError("nonregular source input: " + relative)
    return result


def load_app_variant_helper(app_root: Path):
    scripts = str(app_root / "scripts")
    sys.path.insert(0, scripts)
    try:
        spec = importlib.util.spec_from_file_location("matrix_app_variant", app_root / "scripts/prepare_android_variant.py")
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        return helper
    finally:
        sys.path.remove(scripts)


def lab_input_context(config: Path, roots: dict, sdk: Path, app_root: Path,
                      commands: list) -> dict:
    helper = load_app_variant_helper(app_root)
    parser = app_root / "android/tool/parse_routing_manifest.dart"
    wrapped = {"commands": commands}
    names = sorted(roots)
    manifests = helper.parse_manifests([Path(roots[name]) / "pubspec.yaml" for name in names],
                                      sdk, parser, wrapped)
    packages = dict(zip(names, manifests))
    for name, manifest in packages.items():
        if manifest["name"] != name:
            raise MatrixError("parsed package manifest identity differs from package_config")
    lab = Path(roots["media_kit_hdr_lab"])
    allowed = {}
    metadata = lab / ".flutter-plugins-dependencies"
    if metadata.exists():
        plugins = read_json(metadata, "generated plugin metadata").get("plugins")
        if not isinstance(plugins, dict):
            raise MatrixError("plugin metadata platform mapping is malformed")
        for platform, entries in plugins.items():
            if platform not in ("android", "ios", "macos", "linux", "windows", "web") or not isinstance(entries, list):
                raise MatrixError("plugin metadata platform is unsupported")
            seen = set()
            for entry in entries:
                name = entry.get("name")
                if name in seen or name not in packages or platform not in packages[name]["pluginPlatforms"] or Path(entry.get("path", "")).resolve(strict=True) != Path(roots[name]):
                    raise MatrixError("plugin metadata differs from parsed package manifest/root")
                seen.add(name)
                shared = packages[name]["pluginPlatforms"][platform]["sharedDarwinSource"]
                if entry.get("shared_darwin_source", False) is not shared:
                    raise MatrixError("plugin shared Darwin source differs from manifest")
                if platform in ("linux", "windows"):
                    allowed[f"{platform}/flutter/ephemeral/.plugin_symlinks/{name}"] = roots[name]
                elif platform in ("ios", "macos"):
                    package = Path(roots[name])
                    target = package / ("darwin" if shared else platform) / name
                    if (target / "Package.swift").is_file():
                        target = target.resolve(strict=True)
                        if not target.is_relative_to(package):
                            raise MatrixError("plugin Swift source escapes package")
                        allowed[f"{platform}/Flutter/ephemeral/Packages/.packages/{package.name}"] = str(target)
    return {"resources": packages["media_kit_hdr_lab"]["inputs"],
            "packageResources": {name: manifest["inputs"] for name, manifest in packages.items()},
            "links": allowed,
            "manifestHashes": {name: item["manifestSha256"] for name, item in packages.items()},
            "pubGenerated": sorted(helper.PUB_GENERATED | helper.BUILD_GENERATED | {"pubspec.lock"}),
            "outputRoots": list(helper.BUILD_OUTPUTS),
            "variantContract": flutter_variant_contract(sdk)}


def lab_source_snapshot(source_copy: Path, roots: dict, context: dict) -> dict:
    lab = source_copy / "media_kit_hdr_lab"
    prefix = "media_kit_hdr_lab/"
    outputs = [prefix + item for item in context["outputRoots"]]
    # Native .cxx trees are actual module outputs; nested asset .cxx is not.
    for root in roots.values():
        package = Path(root)
        if package.is_relative_to(source_copy) and (package / "android").is_dir():
            module = package / "android/app" if package == lab else package / "android"
            relative = module.relative_to(source_copy).as_posix()
            outputs.extend(relative + "/" + name for name in (".cxx", ".externalNativeBuild", "build"))
    links = {prefix + name: target for name, target in context["links"].items()}
    generated = [prefix + name for name in context["pubGenerated"]]
    # Reject declared assets/font/shader inputs overlapping any generated root.
    reserved = outputs + [prefix + root for root in (".dart_tool", "ios/Flutter/ephemeral",
        "macos/Flutter/ephemeral", "linux/flutter/ephemeral", "windows/flutter/ephemeral")]
    for resource in context["resources"]:
        relative = prefix + resource["path"].rstrip("/")
        if relative.startswith("/") or ".." in Path(relative).parts:
            raise MatrixError("declared resource escapes isolated Lab")
        if any(relative == output or relative.startswith(output + "/") or
               (resource["directory"] and output.startswith(relative + "/")) for output in reserved) or relative in generated:
            raise MatrixError("declared resource overlaps generated output")
        path = source_copy / relative
        if path.is_symlink() or not path.exists():
            raise MatrixError("declared resource missing/symlink")
    return source_tree_snapshot(source_copy, output_roots=outputs,
                               allowed_links=links, generated_files=generated)


def lab_build_input_state(config: Path, source_copy: Path, pub_cache: Path,
                          flutter_root: Path, *, context: dict | None = None) -> dict:
    roots = verify_lab_package_roots(config, source_copy, pub_cache, flutter_root)
    lab = source_copy / "media_kit_hdr_lab"
    pubspec = lab / "pubspec.yaml"
    lockfile = lab / "pubspec.lock"
    if not lockfile.is_file() or lockfile.is_symlink():
        raise MatrixError("isolated lab flutter pub get did not produce a regular pubspec.lock")
    package_data = json.loads(config.read_text(encoding="utf-8"))
    package_hashes = {}
    declared_inputs = {}
    for item in package_data["packages"]:
        name = item["name"]
        root_uri = urlparse(urljoin(config.resolve().as_uri(), item["rootUri"]))
        package_root = Path(url2pathname(root_uri.path)).resolve(strict=True)
        if context and package_root == lab:
            files = lab_source_snapshot(source_copy, roots, context)
        else:
            files = source_tree_snapshot(package_root, output_roots=("build", "android/.cxx", "android/.externalNativeBuild", "android/.gradle", ".dart_tool"))
        package_hashes[name] = {"root": str(package_root), "fileCount": len(files),
                "treeSha256": sha_bytes(json.dumps(files, sort_keys=True).encode())}
        if context:
            resources = context.get("packageResources", {}).get(name, [])
            resolved_resources = []
            for resource in resources:
                relative = url2pathname(resource["path"]).rstrip("/")
                if not relative or Path(relative).is_absolute() or ".." in Path(relative).parts:
                    raise MatrixError("declared package resource escapes exact package root")
                target_root = package_root
                target_package = name
                path = package_root / relative
                # Follow existing Flutter asset.dart _resolvePackageAsset:
                # only absent literal packages/<name>/... paths use the exact
                # referenced package_config packageUri root, usually lib/.
                parts = Path(relative).parts
                if len(parts) >= 3 and parts[0] == "packages" and not path.is_file():
                    target_package = parts[1]
                    if target_package not in roots:
                        raise MatrixError("declared package resource has unresolved package reference")
                    target_root = Path(roots[target_package]).resolve(strict=True)
                    target_entry = next(entry for entry in package_data["packages"] if entry["name"] == target_package)
                    package_uri = target_entry.get("packageUri", "lib/")
                    parsed_uri = urlparse(urljoin(target_root.as_uri() + "/", package_uri))
                    if parsed_uri.scheme != "file" or parsed_uri.netloc not in ("", "localhost") or parsed_uri.query or parsed_uri.fragment:
                        raise MatrixError("resource packageUri is not a local input root")
                    uri_root = Path(url2pathname(parsed_uri.path)).resolve(strict=True)
                    if not uri_root.is_relative_to(target_root):
                        raise MatrixError("resource packageUri escapes exact package root")
                    path = uri_root.joinpath(*parts[2:])
                    relative = path.relative_to(target_root).as_posix()
                snapshot = resource_input_snapshot(target_root, relative,
                    directory=resource["directory"], kind=resource["kind"],
                    contract=context.get("variantContract"))
                resolved_resources.append({"declared": resource["declared"] if "declared" in resource else resource["path"],
                    "kind": resource["kind"], "targetPackage": target_package,
                    "inputRoot": str(target_root), **snapshot})
            # Resources take precedence over source snapshot generated exclusions,
            # including a legal dependency asset under its root build/ directory.
            declared_inputs[name] = resolved_resources
    source_files = lab_source_snapshot(source_copy, roots, context) if context else source_tree_snapshot(source_copy)
    generated_inputs = {}
    generated_names = set(context["pubGenerated"]) if context else {
        ".flutter-plugins", ".flutter-plugins-dependencies", ".packages",
        ".dart_tool/package_graph.json",
        "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"}
    for path in (lab / name for name in sorted(generated_names)):
        if path.exists() or path.is_symlink():
            if path.is_symlink() or not path.is_file():
                raise MatrixError(f"isolated lab generated build input is not a regular file: {path}")
            generated_inputs[str(path.relative_to(source_copy))] = sha_file(path)
    return {"packageConfigSha256": sha_file(config), "packageRoots": roots,
        "pubspecSha256": sha_file(pubspec), "pubspecLockSha256": sha_file(lockfile),
        "generatedBuildInputs": generated_inputs,
        "sourceFileCount": len(source_files),
        "sourceTreeSha256": sha_bytes(json.dumps(source_files, sort_keys=True).encode()),
        "resolvedPackageSources": package_hashes, "declaredPackageInputs": declared_inputs}


def finalize_bootstrap(app_root: Path, media_root: Path, bootstrap_dir: Path,
                       expected: dict, output: Path, env: dict[str, str]) -> dict:
    bootstrap_path = bootstrap_dir / "bootstrap.json"
    prepared = read_json(bootstrap_path, "routing bootstrap receipt")
    vector = prepared.get("finalVector")
    if (prepared.get("scope") != "routing-source-bootstrap" or
            prepared.get("status") != "fresh-source-only" or
            prepared.get("platform") != "android" or
            not isinstance(vector, dict) or
            vector.get("app") != expected["app"]["head"] or
            vector.get("appTree") != expected["app"]["tree"] or
            vector.get("media-kit") != expected["mediaKit"]["head"] or
            vector.get("media-kitTree") != expected["mediaKit"]["tree"]):
        raise MatrixError("bootstrap receipt does not cover the exact current App/media-kit source vector")
    steps = prepared.get("steps")
    if not isinstance(steps, list) or not all(any(step.get("name") == name and step.get("exitCode") == 0 for step in steps)
            for name in ("patch-SdkOnly", "patch-PackagesOnly", "patched-sdk-diff", "toolchain-machine")):
        raise MatrixError("bootstrap receipt lacks successful reviewed SDK/package patch steps")
    sdk_root = Path(prepared.get("flutterRoot", "")).resolve(strict=True)
    pub_cache = Path(prepared.get("pubCache", "")).resolve(strict=True)
    private_root = sdk_root.parent.parent
    if not sdk_root.is_relative_to(private_root) or not pub_cache.is_relative_to(private_root):
        raise MatrixError("bootstrap Flutter SDK and pub cache do not share a private root")
    if ".runtime" in private_root.parts:
        raise MatrixError("shared .runtime SDK/cache cannot be used for matrix validation")
    if Path(env["RUNNER_TEMP"]).resolve() != private_root.parent:
        raise MatrixError("bootstrap private root must be under the active RUNNER_TEMP")
    if Path(env["FLUTTER_ROOT"]).resolve() != sdk_root:
        raise MatrixError("--flutter does not resolve to the bootstrap's patched private SDK")
    if (git(sdk_root, "rev-parse", "HEAD") != prepared.get("sdkCommit") or
            git(sdk_root, "rev-parse", "HEAD^{tree}") != prepared.get("sdkTree")):
        raise MatrixError("private patched SDK HEAD/tree differs from the bootstrap receipt")
    patch_log = bootstrap_dir / "patched-sdk-diff.log"
    if not patch_log.is_file() or patch_log.is_symlink():
        raise MatrixError("bootstrap directory lacks the SDK patch capture")
    current_patch = subprocess.run(["git", "diff", "--binary"], cwd=sdk_root,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if current_patch.returncode or current_patch.stdout != patch_log.read_bytes():
        raise MatrixError("private SDK patch bytes differ from the accepted bootstrap capture")
    finalize_dir = private_root / "routing-matrix-finalize"
    if finalize_dir.exists():
        raise MatrixError("bootstrap finalization output already exists")
    finalize_dir.mkdir(mode=0o700)
    prepared_for_finalize = dict(prepared)
    # The existing helper accepts its prepared-stage state and independently
    # rechecks all current inputs. The caller's finalized receipt remains
    # untouched; only this private copy is moved back to that helper's input
    # state before it performs the final freshness check again.
    prepared_for_finalize["status"] = "prepared-source-only"
    write_json(finalize_dir / "bootstrap.json", prepared_for_finalize)
    before = bootstrap_dir / "source-resolution-before.json"
    if not before.is_file() or before.is_symlink():
        raise MatrixError("bootstrap receipt directory lacks source-resolution-before.json")
    shutil.copyfile(before, finalize_dir / "source-resolution-before.json")
    command = [sys.executable, str(app_root / "scripts/prepare_routing_ci.py"),
        "--app-root", str(app_root), "--media-kit-root", str(media_root),
        "--flutter-root", str(sdk_root), "--private-root", str(private_root),
        "--output", str(finalize_dir), "--expected-app-sha", expected["app"]["head"],
        "--expected-media-kit-sha", expected["mediaKit"]["head"],
        "--platform", "android", "--finalize"]
    finalize_env = env.copy()
    finalize_env["RUNNER_TEMP"] = str(private_root.parent)
    step = []
    run(command, cwd=app_root, env=finalize_env, log=finalize_dir / "finalize.log", receipt=step)
    finalized = read_json(finalize_dir / "bootstrap.json", "finalized bootstrap receipt")
    if finalized.get("status") != "fresh-source-only" or finalized.get("finalVector") != vector:
        raise MatrixError("existing bootstrap finalizer did not confirm the source vector")
    source_hashes = finalized.get("sourceHashes", {})
    patch_inputs = {name: value for name, value in source_hashes.items()
                    if name.startswith("app/lib/scripts/") and
                    (name.endswith(".patch") or name == "app/lib/scripts/patch.ps1")}
    return {"receipt": str(finalize_dir / "bootstrap.json"),
            "receiptSha256": sha_file(finalize_dir / "bootstrap.json"),
            "originalReceipt": str(bootstrap_path), "originalReceiptSha256": sha_file(bootstrap_path),
            "finalizerCommand": step, "sdkRoot": str(sdk_root), "pubCache": str(pub_cache),
            "sdkCommit": finalized.get("sdkCommit"), "sdkTree": finalized.get("sdkTree"),
            "patchedSdkDiffSha256": sha_file(patch_log),
            "patchInputs": patch_inputs,
            "sourceVector": vector, "sourceHashesSha256": sha_bytes(
                json.dumps(source_hashes, sort_keys=True).encode())}


def check_parser_identity(app_root: Path, bootstrap: dict, expected: dict, receipt: dict) -> None:
    helper = load_app_variant_helper(app_root)
    parser = app_root / "android/tool/parse_routing_manifest.dart"
    actual = helper.manifest_identity(app_root,
        {"android/tool/parse_routing_manifest.dart": parser.read_bytes()},
        Path(bootstrap["flutterRoot"]), Path(bootstrap["pubCache"]), parser, receipt, bootstrap)
    if actual != expected:
        raise MatrixError("locked manifest parser/SDK tools/YAML inputs changed during matrix")


def _check_fresh_sources(app_root: Path, media_identity: dict, sdk_snapshot: dict) -> None:
    current_app = source_identity(app_root, "App")
    current_media = source_identity(ROOT, "media-kit")
    if current_app["head"] != media_identity["app"]["head"] or current_media["head"] != media_identity["mediaKit"]["head"]:
        raise MatrixError("source HEAD advanced during matrix; this result is stale")
    if current_media["tree"] != media_identity["mediaKit"]["tree"]:
        raise MatrixError("media-kit source tree changed during matrix")
    current_sdk = sdk_identity(Path(sdk_snapshot["flutterExecutable"]))
    if current_sdk != sdk_snapshot:
        raise MatrixError("patched private Flutter SDK changed during matrix")


def verify_source_packages(app_root: Path, media_root: Path, output: Path,
                           expected: dict, env: dict[str, str]) -> dict:
    receipt_path = output / "app-source-resolution.json"
    command = [sys.executable, str(app_root / "scripts/verify_routing_sources.py"),
        "--app-root", str(app_root), "--media-kit-root", str(media_root),
        "--output", str(receipt_path)]
    steps: list[dict] = []
    run(command, cwd=app_root, env=env, log=output / "app-source-resolution.log", receipt=steps)
    value = read_json(receipt_path, "App package source receipt")
    if (value.get("appCommit") != expected["app"]["head"] or
            value.get("mediaKitCommit") != expected["mediaKit"]["head"] or
            value.get("appSourceTree") != expected["app"]["tree"] or
            value.get("mediaKitSourceTree") != expected["mediaKit"]["tree"] or
            value.get("nativeBinaryProvenanceVerified") is not False or
            value.get("deviceTest") is not False):
        raise MatrixError("existing source verifier receipt is outside this source vector")
    return {"receipt": str(receipt_path), "receiptSha256": sha_file(receipt_path),
            "command": steps, "packages": value["packages"]}


def prepare_isolated_source(media_root: Path, output: Path, media_identity: dict,
                            env: dict[str, str], receipt: dict) -> tuple[Path, dict]:
    copy_root = output / "source-copy"
    copy_identity = safe_git_archive(media_root, copy_root, media_identity["head"])
    lab = copy_root / "media_kit_hdr_lab"
    if not lab.is_dir():
        raise MatrixError("isolated source archive lacks media_kit_hdr_lab")
    pub_cache = output / "pub-cache"
    pub_cache.mkdir(mode=0o700)
    env["PUB_CACHE"] = str(pub_cache.resolve())
    source_files = source_tree_snapshot(copy_root)
    tracked = tracked_source_manifest(media_root, media_identity["head"])
    verify_tracked_source_copy(copy_root, tracked, "source archive")
    record = {"sourceArchive": copy_identity, "sourceRoot": str(copy_root),
        "sourceFileCount": len(source_files),
        "sourceTreeSha256": sha_bytes(json.dumps(source_files, sort_keys=True).encode()),
        "pubCache": str(pub_cache.resolve()), "trackedInputs": tracked, "localCheckoutModified": False}
    receipt["labSource"] = record
    return copy_root, record


def verify_pubget_source_set(source_copy: Path, roots: dict, context: dict, tracked: dict) -> None:
    snapshot = lab_source_snapshot(source_copy, roots, context)
    links = {"media_kit_hdr_lab/" + item for item in context["links"]}
    generated = {"media_kit_hdr_lab/" + item for item in context["pubGenerated"]}
    if set(snapshot) - links != set(tracked) - generated:
        raise MatrixError("pubget introduced unknown source inputs outside precise generated contract")
    # No stale output may be imported as the current row's newly produced bytes.
    lab = source_copy / "media_kit_hdr_lab"
    output_roots = [lab / root for root in context["outputRoots"]]
    for package in roots.values():
        module = Path(package) / "android/app" if Path(package) == lab else Path(package) / "android"
        output_roots.extend(module / item for item in (".cxx", ".externalNativeBuild", "build"))
    for root in output_roots:
        if root.exists() and (root.is_symlink() or any(path.is_file() or path.is_symlink() for path in root.rglob("*"))):
            raise MatrixError("native/build output present before current row build")


def prepare_isolated_lab_row(source_copy: Path, row_dir: Path, row_tag: str,
                             flutter: Path, env: dict[str, str], receipt: dict) -> tuple[Path, dict]:
    row_source = row_dir / "source-copy"
    shutil.copytree(source_copy, row_source, symlinks=True)
    row_source_files = source_tree_snapshot(row_source)
    source_record = receipt.get("labSource", {})
    if sha_bytes(json.dumps(row_source_files, sort_keys=True).encode()) != source_record.get("sourceTreeSha256"):
        raise MatrixError("per-row isolated media-kit copy differs from the captured source archive")
    lab = row_source / "media_kit_hdr_lab"
    row_cache = row_dir / "pub-cache"
    row_cache.mkdir(mode=0o700)
    env["PUB_CACHE"] = str(row_cache.resolve())
    tracked = source_record["trackedInputs"]
    verify_tracked_source_copy(row_source, tracked, "pre-pubget row")
    pub_log = row_dir / "pub-get.log"
    pub_steps: list[dict] = []
    run([str(flutter), "pub", "get"], cwd=lab, env=env,
        log=pub_log, receipt=pub_steps)
    verify_tracked_source_copy(row_source, tracked, "post-pubget row")
    config = lab / ".dart_tool/package_config.json"
    roots = verify_lab_package_roots(config, row_source, Path(env["PUB_CACHE"]),
                                     flutter.resolve().parent.parent)
    context = lab_input_context(config, roots, flutter.resolve().parent.parent,
                                Path(receipt["source"]["app"]["root"]), pub_steps)
    verify_pubget_source_set(row_source, roots, context, tracked)
    build_input_state = lab_build_input_state(config, row_source, Path(env["PUB_CACHE"]),
                                               flutter.resolve().parent.parent, context=context)
    gradle_file = lab / "android/app/build.gradle.kts"
    gradle_text = gradle_file.read_text(encoding="utf-8")
    if not re.search(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', gradle_text):
        raise MatrixError("isolated lab release APK is not configured with the reviewed debug signer")
    lab_record = {"rowTag": row_tag, "sourceCopy": str(row_source),
        "labRoot": str(lab), "pubCache": env["PUB_CACHE"], "pubGet": pub_steps,
        "pubGetLogSha256": sha_file(pub_log), "packageConfig": str(config),
        "packageConfigSha256": sha_file(config), "packageRoots": roots,
        "buildInputState": build_input_state, "inputContext": context, "trackedInputs": tracked,
        "releaseSigningConfig": "debug",
        "releaseGradleFile": str(gradle_file),
        "releaseGradleFileSha256": sha_file(gradle_file),
        "localCheckoutModified": False}
    receipt["labRows"] = receipt.setdefault("labRows", []) + [lab_record]
    return lab, lab_record


def run_matrix(args: argparse.Namespace) -> dict:
    output = args.output.absolute()
    if output.is_symlink() or not output.is_dir() or any(output.iterdir()):
        raise MatrixError("--output must be an existing empty, regular directory")
    receipt_path = output / "matrix-receipt.json"
    receipt = {"schemaVersion": 1, "task": "MK-ROUTING-20261011",
        "scope": "media_kit_hdr_lab-native-consumer-matrix", "status": "failed",
        "nativeVerified": False, "deviceVerified": False,
        "deviceFixtureVerified": False, "consumerKind": "media_kit_hdr_lab",
        "commands": [], "rows": []}
    write_json(receipt_path, receipt)
    for name in ("app_root", "flutter", "java_home", "android_sdk", "readelf", "nm",
                 "apksigner", "ffprobe", "fixtures", "bootstrap_dir"):
        setattr(args, name, getattr(args, name).resolve(strict=True))
    app_root = args.app_root.resolve(strict=True)
    app = source_identity(app_root, "App")
    media = source_identity(ROOT, "media-kit")
    if output.resolve().is_relative_to(app_root) or output.resolve().is_relative_to(ROOT):
        raise MatrixError("--output must be outside both source checkouts")
    for path, label in ((args.readelf, "readelf"), (args.nm, "nm"),
                        (args.apksigner, "apksigner"), (args.ffprobe, "ffprobe")):
        if not path.is_file() or not os.access(path, os.X_OK):
            raise MatrixError(f"--{label} must be an executable file")
    if not args.java_home.is_dir() or not args.android_sdk.is_dir():
        raise MatrixError("--java-home and --android-sdk must be existing directories")
    if not (app_root / APP_GATE).is_file() or not (app_root / APP_ACQUIRE).is_file():
        raise MatrixError("exact App checkout is missing the native gate/acquirer")
    ledger_path = app_root / APP_LEDGER
    ledger_before = sha_file(ledger_path)
    props = (LAB / "android/gradle.properties").read_text(encoding="utf-8")
    if not re.search(r"(?m)^\s*mediaKitArm64Only\s*=\s*true\s*$", props):
        raise MatrixError("lab Android Gradle config must set mediaKitArm64Only=true")
    env = os.environ.copy()
    env.pop("GITHUB_OUTPUT", None)
    env.pop("ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar", None)
    env.update(JAVA_HOME=str(args.java_home.resolve()), ANDROID_HOME=str(args.android_sdk.resolve()),
               ANDROID_SDK_ROOT=str(args.android_sdk.resolve()),
               ORG_GRADLE_PROJECT_mediaKitArm64Only="true")
    receipt.update({
        "source": {"app": app, "mediaKit": media}, "sdk": sdk_identity(args.flutter),
        "javaHome": str(args.java_home.resolve()), "androidSdk": str(args.android_sdk.resolve()),
        "androidGradlePropertiesSha256": sha_bytes(props.encode()),
        "appNativeGateSha256": sha_file(app_root / APP_GATE),
        "appNativeAcquirerSha256": sha_file(app_root / APP_ACQUIRE),
        "acceptanceLedgerPath": str(ledger_path), "acceptanceLedgerSha256": ledger_before})
    write_json(receipt_path, receipt)
    receipt["nativeTools"] = toolchain_identity(args, env, receipt["commands"], output)
    write_json(receipt_path, receipt)
    try:
        bootstrap_source = read_json(args.bootstrap_dir / "bootstrap.json", "routing bootstrap receipt")
        bootstrap_sdk = Path(bootstrap_source.get("flutterRoot", "")).resolve(strict=True)
        private_root = bootstrap_sdk.parent.parent
        env["FLUTTER_ROOT"] = str(bootstrap_sdk)
        env["RUNNER_TEMP"] = str(private_root.parent)
        receipt["sourceResolution"] = verify_source_packages(app_root, ROOT, output,
            {"app": app, "mediaKit": media}, env)
        receipt["bootstrap"] = finalize_bootstrap(app_root, ROOT, args.bootstrap_dir,
            {"app": app, "mediaKit": media}, output, env)
        if bootstrap_sdk != args.flutter.parent.parent.resolve(strict=True):
            raise MatrixError("--flutter is not the private patched SDK bound by bootstrap")
        write_json(receipt_path, receipt)
        fixtures = validate_fixtures(args.fixtures, args.ffprobe, receipt, env)
        receipt["fixtures"] = fixtures
        receipt["status"] = "fixtures-verified"
        write_json(receipt_path, receipt)
        native_output = output / "native-input"
        native_receipt = output / "native-acquire.json"
        acquire_cmd = [sys.executable, str(app_root / APP_ACQUIRE),
            "--output", str(native_output), "--receipt", str(native_receipt),
            "--app-commit", app["head"], "--media-kit-commit", media["head"],
            "--readelf", str(args.readelf), "--nm", str(args.nm)]
        env["RUNNER_TEMP"] = str(output.resolve())
        try:
            run(acquire_cmd, cwd=app_root, env=env, log=output / "native-acquire.log",
                receipt=receipt["commands"])
        except MatrixError:
            if native_receipt.is_file():
                receipt["nativeAcquisition"] = read_json(native_receipt, "native acquisition receipt")
            raise
        acquisition = read_json(native_receipt, "native acquisition receipt")
        receipt["nativeAcquisition"] = acquisition
        if acquisition.get("status") != "passed" or acquisition.get("nativeVerified") is not True or acquisition.get("deviceVerified") is not False:
            raise MatrixError("App fixed-ledger native acquirer did not verify an accepted JAR")
        jar = Path(acquisition["jar"]).resolve(strict=True)
        manifest = Path(acquisition["manifest"]).resolve(strict=True)
        evidence = Path(acquisition["evidenceRoot"]).resolve(strict=True)
        manifest_value = read_json(manifest, "accepted native manifest")
        accepted_jar_members = set(manifest_value.get("members", {}))
        native_snapshot = native_fingerprints(jar, manifest, ledger_path)
        initial_jar_sha = native_snapshot["jarSha256"]
        initial_manifest_sha = native_snapshot["manifestSha256"]
        if native_snapshot["ledgerSha256"] != ledger_before:
            raise MatrixError("fixed acceptance ledger changed during acquisition")
        receipt.update(nativeInput={"jar": str(jar), "jarSha256": initial_jar_sha,
            "manifest": str(manifest), "manifestSha256": initial_manifest_sha,
            "evidenceRoot": str(evidence), "ledgerSha256": ledger_before})
        receipt["status"] = "native-input-verified"
        write_json(receipt_path, receipt)
        version = run([str(args.flutter), "--version", "--machine"], cwd=output, env=env,
                      receipt=receipt["commands"])
        try:
            receipt["flutterVersion"] = json.loads(version.stdout)
        except (UnicodeError, json.JSONDecodeError) as error:
            raise MatrixError("flutter --version --machine did not return JSON") from error
        receipt["sdk"] = android_precache(args.flutter, output, env, receipt["commands"])
        helper = load_app_variant_helper(app_root)
        receipt["manifestParser"] = helper.manifest_identity(app_root,
            {"android/tool/parse_routing_manifest.dart": (app_root / "android/tool/parse_routing_manifest.dart").read_bytes()},
            bootstrap_sdk, Path(bootstrap_source["pubCache"]),
            app_root / "android/tool/parse_routing_manifest.dart", receipt, bootstrap_source)
        source_copy, source_record = prepare_isolated_source(ROOT, output, media, env, receipt)
        write_json(receipt_path, receipt)
        receipt["rows"] = []
        for row in matrix_rows(fixtures):
            try:
                _check_fresh_sources(app_root, {"app": app, "mediaKit": media}, receipt["sdk"])
            except MatrixError as error:
                receipt.update(status="stale-source-vector", staleReason=str(error))
                for previous in receipt["rows"]:
                    previous["stale"] = True
                    previous["freshnessStatus"] = "stale"
                write_json(receipt_path, receipt)
                raise
            assert_native_fingerprints(jar, manifest, ledger_path, native_snapshot)
            check_parser_identity(app_root, bootstrap_source, receipt["manifestParser"], receipt)
            row_dir = output / row["tag"]
            row_dir.mkdir(mode=0o700)
            lab, lab_record = prepare_isolated_lab_row(source_copy, row_dir, row["tag"],
                                                       args.flutter, env, receipt)
            row_record = {**row, "status": "building", "fixture": fixtures[row["kind"]],
                          "source": receipt["source"],
                          "sourceResolution": receipt["sourceResolution"],
                          "bootstrap": receipt["bootstrap"],
                          "nativeInput": receipt["nativeInput"], "labSource": source_record,
                          "lab": lab_record,
                          "buildInputBefore": lab_record["buildInputState"],
                          "nativeTools": receipt["nativeTools"],
                          "flutterVersion": receipt.get("flutterVersion"),
                          "fullDefines": list(row["defines"]),
                          "consumerKind": "media_kit_hdr_lab", "localContentVerified": True,
                          "deviceFixtureVerified": False, "nativeVerified": False,
                          "deviceVerified": False, "commands": []}
            receipt["rows"].append(row_record)
            write_json(receipt_path, receipt)
            apk = lab / "build/app/outputs/flutter-apk/app-release.apk"
            require_fresh_apk_path(apk)
            argv = [str(args.flutter), "build", "apk", "--release",
                    "--target-platform", "android-arm64", "--no-pub",
                    *row["defines"]]
            env["ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar"] = str(jar)
            env["ORG_GRADLE_PROJECT_mediaKitArm64Only"] = "true"
            try:
                run(argv, cwd=lab, env=env, log=row_dir / "build.log", receipt=row_record["commands"])
                build_input_after = lab_build_input_state(lab / ".dart_tool/package_config.json",
                    lab.parent, Path(env["PUB_CACHE"]), Path(receipt["sdk"]["root"]), context=lab_record["inputContext"])
                verify_tracked_source_copy(lab.parent, lab_record["trackedInputs"], "post-build row")
                _check_fresh_sources(app_root, {"app": app, "mediaKit": media}, receipt["sdk"])
                check_parser_identity(app_root, bootstrap_source, receipt["manifestParser"], receipt)
                row_record["buildInputAfter"] = build_input_after
                if build_input_after != row_record["buildInputBefore"]:
                    raise MatrixError("isolated lab/package/resource/generator inputs changed during Flutter build")
                if not apk.is_file() or apk.is_symlink():
                    raise MatrixError("Flutter reported success without a regular APK")
                apk_copy = row_dir / f"{row['tag']}.apk"
                shutil.copyfile(apk, apk_copy)
                apk_sha = sha_file(apk_copy)
                expected_producers = expected_native_member_sources(
                    accepted_jar_members, lab, lab_record["packageRoots"])
                members = exact_native_members(apk_copy, set(expected_producers))
                row_record.update(status="apk-built", apk=str(apk_copy),
                                  apkSha256=apk_sha, nativeMembers=members)
                write_json(receipt_path, receipt)
                gate_receipt = row_dir / "native-after.json"
                verify_cmd = [sys.executable, str(app_root / APP_GATE),
                    "--jar", str(jar), "--manifest", str(manifest),
                    "--evidence-root", str(evidence), "--apk", str(apk_copy),
                    "--app-commit", app["head"], "--media-kit-commit", media["head"],
                    "--receipt", str(gate_receipt), "--readelf", str(args.readelf), "--nm", str(args.nm)]
                run(verify_cmd, cwd=app_root, env=env,
                    log=row_dir / "native-after.log", receipt=row_record["commands"])
                verified_native = read_json(gate_receipt, "post-build native verification")
                if verified_native.get("status") != "passed" or verified_native.get("nativeVerified") is not True or verified_native.get("deviceVerified") is not False:
                    raise MatrixError("post-build App native verifier did not pass")
                native_provenance = verify_native_provenance(apk_copy, jar,
                    Path(receipt["sdk"]["root"]), lab, row_dir, args.readelf, env,
                    row_record["commands"], lab_record["packageRoots"])
                signer = signer_certificate(args.apksigner, apk_copy, env, row_record["commands"])
                prior_signers = [previous["signer"]["certificateSha256"]
                    for previous in receipt["rows"][:-1] if previous.get("signer")]
                if any(value != signer["certificateSha256"] for value in prior_signers):
                    raise MatrixError("release APK signer certificate changed between matrix rows")
                row_record.update(status="native-verified", apk=str(apk_copy), apkSha256=apk_sha,
                    nativeMembers=members, nativeGateReceipt=str(gate_receipt),
                    nativeGateReceiptSha256=sha_file(gate_receipt), signer=signer,
                    nativeProvenance=native_provenance,
                    aotInputBinding={"sdkInputSha256": sha_bytes(json.dumps(receipt["sdk"], sort_keys=True).encode()),
                        "rowDefines": row["defines"], "buildInputBefore": lab_record["buildInputState"],
                        "buildCommand": argv, "sourceArchive": source_record["sourceArchive"]},
                    localContentVerified=True, deviceFixtureVerified=False,
                    nativeVerified=True, deviceVerified=False)
            except Exception as error:
                row_record.update(status="failed", reason=str(error))
                try:
                    row_record["buildInputAfterFailure"] = lab_build_input_state(
                        lab / ".dart_tool/package_config.json", lab.parent,
                        Path(env["PUB_CACHE"]), Path(receipt["sdk"]["root"]), context=lab_record["inputContext"])
                except Exception as capture_error:
                    row_record["buildInputCaptureError"] = str(capture_error)
                write_json(receipt_path, receipt)
                raise
            if native_fingerprints(jar, manifest, ledger_path) != native_snapshot:
                row_record.update(status="failed", reason="native source/ledger changed after build")
                write_json(receipt_path, receipt)
                raise MatrixError("accepted JAR, manifest, or ledger changed after row build")
            try:
                _check_fresh_sources(app_root, {"app": app, "mediaKit": media}, receipt["sdk"])
            except MatrixError as error:
                row_record.update(status="stale", reason=str(error), stale=True)
                receipt.update(status="stale-source-vector", staleReason=str(error))
                for previous in receipt["rows"]:
                    previous["stale"] = True
                    previous["freshnessStatus"] = "stale"
                write_json(receipt_path, receipt)
                raise
            row_record["status"] = "passed"
            write_json(receipt_path, receipt)
        receipt["status"] = "passed"
        receipt["nativeVerified"] = True
        receipt["deviceVerified"] = False
        receipt["deviceFixtureVerified"] = False
        write_json(receipt_path, receipt)
        return receipt
    except Exception as error:
        if receipt.get("status") != "stale-source-vector":
            receipt["status"] = "failed"
        receipt["reason"] = str(error)
        write_json(receipt_path, receipt)
        raise


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    for name in ("app-root", "output", "flutter", "java-home", "android-sdk",
                 "readelf", "nm", "apksigner", "ffprobe", "fixtures", "bootstrap-dir"):
        result.add_argument("--" + name, type=Path, required=True)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    output_was_empty = (args.output.is_dir() and not args.output.is_symlink() and
                        not any(args.output.iterdir()))
    try:
        receipt = run_matrix(args)
        print(f"matrix status={receipt['status']} rows={len(receipt['rows'])} deviceVerified=false")
        return 0
    except Exception as error:
        if output_was_empty and args.output.is_dir() and not args.output.is_symlink():
            receipt_path = args.output / "matrix-receipt.json"
            if receipt_path.is_file() and not receipt_path.is_symlink():
                try:
                    receipt = read_json(receipt_path, "partial matrix receipt")
                except Exception:
                    receipt = {"schemaVersion": 1, "status": "failed"}
            else:
                receipt = {"schemaVersion": 1, "status": "failed"}
            receipt.update(status=("stale-source-vector" if receipt.get("status") == "stale-source-vector" else "failed"),
                           reason=str(error),
                           nativeVerified=False, deviceVerified=False,
                           deviceFixtureVerified=False)
            write_json(receipt_path, receipt)
        print(f"matrix status=failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
