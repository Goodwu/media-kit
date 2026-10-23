#!/usr/bin/env python3
"""Create, verify, and consume an explicitly selected media-kit native package.

The caller authenticates the complete archive before extraction and pins the
manifest digest. This tool then checks the complete extracted inventory. It does
not equate a successful hash check with runtime or physical-device validation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import sys
import tempfile


KIND = "media-kit-native-package"
PLATFORMS = {"android", "windows", "linux", "ios", "macos", "ohos"}
ENV_KEYS = (
    "MEDIA_KIT_NATIVE_PACKAGE_ROOT",
    "MEDIA_KIT_NATIVE_PACKAGE_MANIFEST",
    "MEDIA_KIT_NATIVE_PACKAGE_MANIFEST_SHA256",
)
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
META_FIELDS = {
    "schema", "kind", "platform", "architectures", "profile", "identity",
    "layout", "capabilities", "validation",
}


class PackageError(ValueError):
    pass


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def read_json(path: Path) -> dict:
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise PackageError(f"Duplicate JSON key: {key}")
            result[key] = value
        return result

    if not path.is_file() or path.is_symlink() or path.stat().st_size > 16 * 1024 * 1024:
        raise PackageError(f"Expected a regular, bounded JSON file: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique,
                           parse_constant=lambda value: (_ for _ in ()).throw(
                               PackageError(f"Non-finite JSON number: {value}")))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise PackageError(f"Invalid JSON: {path}: {error}") from error
    if not isinstance(value, dict):
        raise PackageError(f"Expected a JSON object: {path}")
    return value


def relative(value: object) -> str:
    if (not isinstance(value, str) or not value or "\\" in value or ":" in value
            or value.startswith("/") or any(ord(c) < 32 for c in value)
            or any(part in {"", ".", ".."} for part in value.split("/"))
            or str(PurePosixPath(value)) != value):
        raise PackageError(f"Unsafe package-relative path: {value!r}")
    return value


def inside(root: Path, value: object, *, directory: bool = False) -> Path:
    path = root / relative(value)
    try:
        actual = path.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise PackageError(f"Missing or cyclic package path: {value}") from error
    if root not in actual.parents:
        raise PackageError(f"Package path escapes its root: {value}")
    if not (actual.is_dir() if directory else actual.is_file()):
        raise PackageError(f"Unexpected package path type: {value}")
    return path


def package_root(path: Path) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise PackageError("Native package root must be an existing absolute directory, not a symlink")
    return path.resolve(strict=True)


def manifest_path(root: Path, path: Path | None) -> Path:
    path = path or root / "manifest.json"
    if not path.is_absolute():
        path = root / path
    if path.is_symlink() or path.parent.resolve() != root:
        raise PackageError("Native package manifest must be a regular file directly inside its root")
    # Root ancestors may be symlinks (for example /var on macOS). Keep the
    # manifest spelling canonical so inventory excludes precisely this file.
    return root / path.name


def link_target(value: str, *, windows: bool = False) -> str:
    # Win32 stores native relative link separators as backslashes. The manifest
    # always uses POSIX spelling; absolute, drive and UNC targets stay forbidden.
    if windows:
        value = value.replace("\\", "/")
    if (not value or "\\" in value or ":" in value or value.startswith("/")
            or any(ord(c) < 32 for c in value)):
        raise PackageError("Unsafe symbolic link target")
    return value


def inventory(root: Path, manifest: Path) -> tuple[dict[str, str], dict[str, str]]:
    files, links = {}, {}
    entry_names = []
    directory_edges: dict[Path, set[Path]] = {}
    for parent, dirs, names in os.walk(root, followlinks=False):
        directory_edges[Path(parent)] = set()
        for name in sorted(dirs + names):
            path = Path(parent) / name
            if path == manifest:
                continue
            rel = relative(path.relative_to(root).as_posix())
            entry_names.append(rel)
            if path.is_symlink():
                try:
                    target = link_target(os.readlink(path), windows=os.name == "nt")
                except PackageError as error:
                    raise PackageError(f"Unsafe symbolic link: {rel}") from error
                try:
                    resolved = path.resolve(strict=True)
                except (OSError, RuntimeError) as error:
                    raise PackageError(f"Dangling or cyclic symbolic link: {rel}") from error
                if root not in resolved.parents:
                    raise PackageError(f"Symbolic link escapes the package: {rel}")
                if resolved.is_dir() and (resolved == path.parent or resolved in path.parent.parents):
                    raise PackageError(f"Recursive directory symbolic link: {rel}")
                if resolved.is_dir():
                    directory_edges[Path(parent)].add(resolved)
                links[rel] = target
            elif path.is_file():
                files[rel] = file_digest(path)
            elif path.is_dir():
                directory_edges[Path(parent)].add(path)
            else:
                raise PackageError(f"Unsupported package entry: {rel}")
    if not files:
        raise PackageError("Native package contains no regular payload files")
    # Windows and common macOS filesystems cannot distinguish these names.
    casefolded = [name.casefold() for name in entry_names]
    if len(casefolded) != len(set(casefolded)):
        raise PackageError("Package paths collide on a case-insensitive filesystem")
    # A pair of individually valid relative links can still form a directory
    # cycle (A/to-B and B/to-A). Reject it before any consumer copies a tree.
    visited, active = set(), set()
    pending = [(root, True)]
    while pending:
        path, entering = pending.pop()
        if not entering:
            active.remove(path)
            visited.add(path)
        elif path in active:
            raise PackageError("Native package contains a recursive directory link graph")
        elif path not in visited:
            active.add(path)
            pending.append((path, False))
            pending.extend((child, True) for child in directory_edges.get(path, ()))
    return dict(sorted(files.items())), dict(sorted(links.items()))


def string_list(value: object, name: str, *, empty: bool = False) -> list[str]:
    if (not isinstance(value, list) or (not value and not empty)
            or any(not isinstance(x, str) or not x.strip() or x != x.strip() for x in value)
            or len(value) != len(set(value))):
        raise PackageError(f"{name} must contain unique, nonempty strings")
    return value


def metadata(spec: dict) -> dict:
    result = {"schema": 1, "kind": KIND, **spec}
    if set(result) != META_FIELDS:
        raise PackageError(f"Package metadata fields differ: {sorted(set(result) ^ META_FIELDS)}")
    if type(result["schema"]) is not int or result["schema"] != 1 or result["kind"] != KIND:
        raise PackageError("Unsupported native package schema/kind")
    if result["platform"] not in PLATFORMS:
        raise PackageError("Unsupported native package platform")
    string_list(result["architectures"], "architectures")
    string_list(result["capabilities"], "capabilities", empty=True)
    if not isinstance(result["profile"], str) or not result["profile"].strip():
        raise PackageError("Package profile is required")
    if not isinstance(result["identity"], dict) or not result["identity"]:
        raise PackageError("Package identity must record real build or upstream inputs")
    if not isinstance(result["layout"], dict):
        raise PackageError("Package layout must be an object")
    validation = result["validation"]
    if (not isinstance(validation, dict) or set(validation) != {"compiled", "runtime", "device"}
            or any(type(value) is not bool for value in validation.values())):
        raise PackageError("validation must contain explicit compiled/runtime/device booleans")
    return result


def validate_layout(root: Path, data: dict) -> dict:
    layout, platform = data["layout"], data["platform"]
    resolved = {}

    def item(key: str, *, directory: bool = False) -> Path:
        if key not in layout:
            raise PackageError(f"{platform} layout requires {key}")
        path = inside(root, layout[key], directory=directory)
        resolved[key] = str(path)
        return path

    def headers(*names: str) -> None:
        include = item("include", directory=True)
        for name in names:
            inside(root, (include / "mpv" / name).relative_to(root).as_posix())

    if platform == "android":
        if ("jars" not in layout or not set(layout) <= {"jars", "sdk_prefixes"}
                or not isinstance(layout["jars"], dict)):
            raise PackageError("Android layout requires a jars map and optional sdk_prefixes")
        if set(layout["jars"]) != set(data["architectures"]):
            raise PackageError("Android JAR ABIs must exactly match architectures")
        if not set(layout["jars"]) <= {"arm64-v8a", "armeabi-v7a", "x86_64", "x86"}:
            raise PackageError("Unsupported Android ABI")
        resolved["jars"] = {}
        import zipfile
        for abi, rel in sorted(layout["jars"].items()):
            path = inside(root, rel)
            try:
                with zipfile.ZipFile(path) as jar:
                    names = jar.namelist()
                    if len(names) != len(set(names)) or f"lib/{abi}/libmpv.so" not in names:
                        raise PackageError(f"Android JAR has duplicate members or no {abi}/libmpv.so")
                    for name in names:
                        relative(name.rstrip("/"))
                        if name.startswith("lib/") and len(name.split("/")) > 2 and name.split("/")[1] != abi:
                            raise PackageError(f"Android JAR mixes ABIs: {rel}")
            except zipfile.BadZipFile as error:
                raise PackageError(f"Invalid Android JAR: {rel}") from error
            resolved["jars"][abi] = {"path": str(path), "sha256": file_digest(path)}
        if "sdk_prefixes" in layout:
            prefixes = layout["sdk_prefixes"]
            if not isinstance(prefixes, dict) or not set(prefixes) <= set(layout["jars"]):
                raise PackageError("Android SDK prefixes must use packaged ABI names")
            resolved["sdk_prefixes"] = {
                abi: str(inside(root, rel, directory=True)) for abi, rel in prefixes.items()
            }
    elif platform in {"windows", "linux"}:
        required = {"include", "runtime", "bundle"} | ({"import_library"} if platform == "windows" else set())
        if set(layout) != required:
            raise PackageError(f"{platform} layout fields must be {sorted(required)}")
        headers("client.h", "render.h", "render_dxgi.h" if platform == "windows" else "render_gl.h")
        runtime = item("runtime")
        if runtime.name != ("libmpv-2.dll" if platform == "windows" else "libmpv.so.2"):
            raise PackageError(f"Unexpected {platform} runtime filename")
        if platform == "windows":
            item("import_library")
        bundle = string_list(layout["bundle"], "layout.bundle")
        if layout["runtime"] not in bundle:
            raise PackageError("Bundle must contain the selected runtime")
        paths = [inside(root, name) for name in bundle]
        if len({p.name.casefold() for p in paths}) != len(paths):
            raise PackageError("Bundled libraries collide at their flat install location")
        names = {path.name for path in paths}
        for path in paths:
            if path.is_symlink():
                target = os.readlink(path)
                if target not in names:
                    raise PackageError("A bundled library link must target another bundled filename")
        resolved["bundle"] = [str(path) for path in paths]
    elif platform in {"ios", "macos"}:
        if set(layout) != {"frameworks", "include"}:
            raise PackageError("Apple layout requires frameworks and matching include")
        headers("client.h", "render.h", "render_gl.h")
        frameworks = string_list(layout["frameworks"], "layout.frameworks")
        paths = [inside(root, name, directory=True) for name in frameworks]
        if any(not path.name.endswith(".xcframework") for path in paths):
            raise PackageError("Apple frameworks must be XCFramework directories")
        if len({path.name.casefold() for path in paths}) != len(paths):
            raise PackageError("Apple framework names must be unique")
        if sum(path.name == "Mpv.xcframework" for path in paths) != 1:
            raise PackageError("Apple package must contain exactly one Mpv.xcframework")
        for path in paths:
            info = inside(root, (path / "Info.plist").relative_to(root).as_posix())
            try:
                with info.open("rb") as stream:
                    slices = plistlib.load(stream)["AvailableLibraries"]
            except (OSError, ValueError, KeyError, TypeError) as error:
                raise PackageError(f"Invalid XCFramework Info.plist: {path.name}") from error
            if not isinstance(slices, list) or not slices:
                raise PackageError(f"XCFramework has no libraries: {path.name}")
            architectures = set()
            for entry in slices:
                if not isinstance(entry, dict) or entry.get("SupportedPlatform") != platform:
                    raise PackageError(f"Unexpected XCFramework platform in {path.name}")
                identifier = relative(entry.get("LibraryIdentifier"))
                library = relative(entry.get("LibraryPath"))
                binary = path / identifier / library
                inside(root, binary.relative_to(root).as_posix(), directory=binary.is_dir())
                architectures.update(string_list(entry.get("SupportedArchitectures"), "XCFramework architectures"))
            if not set(data["architectures"]) <= architectures:
                raise PackageError(f"XCFramework architecture coverage is incomplete: {path.name}")
        resolved["frameworks"] = [str(path) for path in paths]
    else:
        if not set(layout) <= {"archive", "runtime", "include"} or not ({"archive", "runtime"} & set(layout)):
            raise PackageError("OHOS layout requires archive/runtime and optional include")
        for key in layout:
            item(key, directory=key == "include")
    return resolved


def create(root: Path, spec_path: Path, manifest: Path | None = None) -> dict:
    root = package_root(root)
    manifest = manifest_path(root, manifest)
    data = metadata(read_json(spec_path))
    validate_layout(root, data)
    files, links = inventory(root, manifest)
    data.update(identity_sha256=digest(canonical(data["identity"])), files=files)
    if links:
        data["symlinks"] = links
    encoded = (json.dumps(data, sort_keys=True, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")
    manifest.write_bytes(encoded)
    return {"root": str(root), "manifest": str(manifest), "manifest_sha256": digest(encoded),
            "identity_sha256": data["identity_sha256"], "platform": data["platform"]}


def verify(root: Path, expected: str, platform: str, manifest: Path | None = None,
           expected_identity: str | None = None, architecture: str | None = None) -> dict:
    root = package_root(root)
    manifest = manifest_path(root, manifest)
    if not isinstance(expected, str) or not SHA256.fullmatch(expected):
        raise PackageError("An explicit lowercase manifest SHA256 is required")
    if not manifest.is_file() or file_digest(manifest) != expected:
        raise PackageError("Native package manifest SHA256 mismatch; refusing fallback")
    data = read_json(manifest)
    expected_fields = META_FIELDS | {"identity_sha256", "files"}
    if set(data) not in (expected_fields, expected_fields | {"symlinks"}):
        raise PackageError("Unexpected native package manifest fields")
    metadata({key: data[key] for key in META_FIELDS})
    if data["platform"] != platform:
        raise PackageError(f"Native package platform differs: expected {platform}")
    if architecture and architecture not in data["architectures"]:
        raise PackageError(f"Native package does not contain target architecture {architecture}")
    identity = digest(canonical(data["identity"]))
    if data["identity_sha256"] != identity or (expected_identity is not None and expected_identity != identity):
        raise PackageError("Native package identity hash mismatch")
    files, links = inventory(root, manifest)
    if data["files"] != files or data.get("symlinks", {}) != links:
        raise PackageError("Native package files or symbolic links differ from the authenticated manifest")
    layout = validate_layout(root, data)
    return {"root": str(root), "manifest": str(manifest), "manifest_sha256": expected,
            "identity_sha256": identity, "platform": platform, "architectures": data["architectures"],
            "profile": data["profile"], "capabilities": data["capabilities"],
            "validation": data["validation"], "layout": layout}


def from_environment(platform: str, architecture: str | None = None) -> dict:
    root, manifest, expected = (os.environ.get(name, "") for name in ENV_KEYS)
    if not root or not expected:
        raise PackageError("Explicit native input requires MEDIA_KIT_NATIVE_PACKAGE_ROOT and MEDIA_KIT_NATIVE_PACKAGE_MANIFEST_SHA256")
    return verify(Path(root), expected, platform, Path(manifest) if manifest else None,
                  architecture=architecture)


def cmake_data(result: dict, destination: Path) -> None:
    def quoted(value: str) -> str:
        # Bracket arguments avoid variable expansion. Semicolons would still
        # split CMake lists, so reject them instead of silently changing paths.
        value = value.replace("\\", "/")
        if any(c in value for c in (";", "\n", "\r", "]==]")):
            raise PackageError("Native package path cannot be represented safely in CMake")
        return f"[==[{value}]==]"

    lines = ["# Generated by the trusted native package verifier.\n"]
    for key in ("include", "runtime", "import_library"):
        if key in result["layout"]:
            lines.append(f"set(MEDIA_KIT_PACKAGE_{key.upper()} {quoted(result['layout'][key])})\n")
    lines.append("set(MEDIA_KIT_PACKAGE_BUNDLE)\n")
    for path in result["layout"].get("bundle", []):
        lines.append(f"list(APPEND MEDIA_KIT_PACKAGE_BUNDLE {quoted(path)})\n")
    lines.append(f"set(MEDIA_KIT_PACKAGE_MANIFEST_SHA256 {quoted(result['manifest_sha256'])})\n")
    destination.write_text("".join(lines), encoding="utf-8")


def copy_headers(result: dict, destination: Path) -> None:
    source = Path(result["layout"]["include"]) / "mpv"
    staging_destination(result, destination)
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / "mpv"
    if target.is_symlink():
        raise PackageError("Refusing to replace a symlinked generated header directory")
    if target.exists():
        shutil.rmtree(target)
    # Dereference only after verification established that all links remain
    # inside the authenticated package. Headers become a self-contained copy.
    shutil.copytree(source, target)


def stage_frameworks(result: dict, destination: Path) -> None:
    staging_destination(result, destination)
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".native-frameworks-", dir=destination.parent) as tmp:
        staged = Path(tmp)
        for framework in result["layout"]["frameworks"]:
            source = Path(framework)
            # Preserve normal versioned-framework links. Requiring them to stay
            # inside this framework prevents references to the package location
            # from surviving when the framework is copied into the pod.
            for parent, dirs, files in os.walk(source, followlinks=False):
                for name in dirs + files:
                    path = Path(parent) / name
                    if path.is_symlink() and source.resolve() not in path.resolve().parents:
                        raise PackageError(f"XCFramework link leaves its own framework: {path}")
            shutil.copytree(source, staged / source.name, symlinks=True)
        mpv = staged / "Mpv.xcframework"
        with (mpv / "Info.plist").open("rb") as stream:
            slices = plistlib.load(stream)["AvailableLibraries"]
        link_root = staged / ".symlinks" / "mpv"
        link_root.mkdir(parents=True)
        for entry in slices:
            name = entry["SupportedPlatform"]
            variant = entry.get("SupportedPlatformVariant")
            if variant:
                name += "-" + variant
            relative(name)
            link = link_root / name
            if link.exists() or link.is_symlink():
                raise PackageError("CocoaPods requires one combined XCFramework slice per platform/variant")
            link.symlink_to(Path("../..") / "Mpv.xcframework" / entry["LibraryIdentifier"], target_is_directory=True)
        for path in destination.glob("*.xcframework"):
            if path.is_symlink():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)
        old_links = destination / ".symlinks"
        if old_links.is_symlink():
            old_links.unlink()
        elif old_links.exists():
            shutil.rmtree(old_links)
        for path in staged.iterdir():
            shutil.move(str(path), destination / path.name)


def staging_destination(result: dict, destination: Path) -> None:
    root = Path(result["root"])
    resolved = destination.resolve()
    if destination.is_symlink() or resolved == root or root in resolved.parents or resolved in root.parents:
        raise PackageError("Generated output must be outside and separate from the authenticated package")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    create_parser = sub.add_parser("create", help="create a manifest from actual package files")
    create_parser.add_argument("--root", type=Path, required=True)
    create_parser.add_argument("--spec", type=Path, required=True)
    create_parser.add_argument("--manifest", type=Path)
    verify_parser = sub.add_parser("verify", help="verify a manifest and complete extracted package")
    verify_parser.add_argument("--root", type=Path, required=True)
    verify_parser.add_argument("--manifest", type=Path)
    verify_parser.add_argument("--manifest-sha256", required=True)
    verify_parser.add_argument("--platform", choices=sorted(PLATFORMS), required=True)
    verify_parser.add_argument("--architecture")
    verify_parser.add_argument("--expected-identity", "--expected-identity-sha256")
    consume = sub.add_parser("consume", help="verify explicit environment inputs for a native build")
    consume.add_argument("--platform", choices=sorted(PLATFORMS), required=True)
    consume.add_argument("--architecture")
    consume.add_argument("--cmake", type=Path)
    consume.add_argument("--stage-frameworks", type=Path)
    consume.add_argument("--stage-headers", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "create":
            result = create(args.root, args.spec, args.manifest)
        elif args.command == "verify":
            result = verify(args.root, args.manifest_sha256, args.platform, args.manifest,
                            args.expected_identity, args.architecture)
        else:
            result = from_environment(args.platform, args.architecture)
            if args.cmake:
                cmake_data(result, args.cmake)
            if args.stage_frameworks or args.stage_headers:
                if args.platform not in {"ios", "macos"}:
                    raise PackageError("Framework/header staging is an Apple package operation")
                if args.stage_frameworks:
                    stage_frameworks(result, args.stage_frameworks)
                if args.stage_headers:
                    copy_headers(result, args.stage_headers)
        print(json.dumps(result, sort_keys=True, ensure_ascii=False))
        return 0
    except (PackageError, OSError, ValueError, TypeError, KeyError) as error:
        print(f"media-kit native package: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
