#!/usr/bin/env python3
"""Build opt-in shared mpv macOS slices from pinned source and reviewed inputs.

No input source, dependency prefix or existing product is modified. A dependency
inspection report must be reviewed and supplied as the immutable build lock.
This builds candidate slices; backend/video/display acceptance is separate.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ARCHES = ("arm64", "x86_64")
MIN_OS = "12.0"
FFMPEG = {"libavcodec": "63.1.101", "libavfilter": "12.1.101",
          "libavformat": "63.1.101", "libavutil": "61.1.101",
          "libswresample": "7.1.101", "libswscale": "10.1.101"}
OPTIONS = {"buildtype": "release", "auto_features": "disabled", "cplayer": False,
           "libmpv": True, "tests": False, "b_lundef": True, "gpl": False,
           "cplugins": "disabled", "javascript": "disabled", "lua": "disabled",
           **{x: "enabled" for x in ("cocoa", "coreaudio", "avfoundation", "gl",
              "gl-cocoa", "plain-gl", "videotoolbox-gl", "swift-build", "iconv",
              "uchardet", "zlib", "vulkan", "videotoolbox-pl")}}


def fail(message):
    raise ValueError(message)


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def write_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + ".writing")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def output(command):
    return subprocess.check_output([str(x) for x in command], text=True).strip()


def tree(path):
    path = Path(path)
    if not path.is_dir():
        fail(f"missing input directory: {path}")
    result = {}
    for p in sorted(path.rglob("*")):
        if p.is_symlink():
            # Header symlinks may name installed SDK headers. Record the link
            # and resolved bytes; a later target edit also changes identity.
            if not p.is_file():
                fail(f"unsupported directory or broken header symlink: {p}")
            result[str(p.relative_to(path))] = {"link": os.readlink(p), "sha256": sha(p)}
        elif p.is_file():
            result[str(p.relative_to(path))] = sha(p)
    if not result:
        fail(f"empty header input: {path}")
    return {"path": str(path), "files": result, "tree_sha256": canonical(result)}


def path_field(config, name, directory=False):
    p = Path(config[name]).expanduser().resolve(strict=True)
    if directory != p.is_dir():
        fail(f"{name} has incorrect type: {p}")
    if "/opt/homebrew/" in str(p) or "/usr/local/Cellar/" in str(p):
        fail(f"Homebrew dependency input is forbidden: {p}")
    if any(c in str(p) for c in ("\n", "\r", ":", "'", '"')):
        fail(f"unsupported build input path characters: {p}")
    return p


def macro(path, name):
    match = re.search(r"^\s*#\s*define\s+" + re.escape(name) + r"\s+(\d+|0x[0-9a-fA-F]+)\b", Path(path).read_text(), re.M)
    if not match:
        fail(f"missing header version {name}: {path}")
    return int(match.group(1), 0)


def minos(path, arch):
    text = output(["otool", "-arch", arch, "-l", path])
    values = re.findall(r"\bminos\s+(\d+(?:\.\d+)*)", text)
    values += re.findall(r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version (\d+(?:\.\d+)*)", text)
    if not values:
        fail(f"no macOS deployment target for {arch}: {path}")
    return max(values, key=lambda v: tuple(map(int, v.split("."))))


def version_tuple(value):
    return tuple(int(v) for v in value.split(".")) + (0,) * (3 - len(value.split(".")))


def install_dependencies(path, arch):
    lines = output(["otool", "-arch", arch, "-L", path]).splitlines()[1:]
    return [line.strip().split(" (compatibility", 1)[0] for line in lines if " (compatibility" in line]


def library_identity(path, arch):
    arches = output(["lipo", "-archs", path]).split()
    if arch not in arches:
        fail(f"missing {arch} ABI: {path} ({arches})")
    minimum = minos(path, arch)
    if version_tuple(minimum) > version_tuple(MIN_OS):
        fail(f"dependency requires macOS {minimum}, requested {MIN_OS}: {path} [{arch}]")
    return {"sha256": sha(path), "architectures": arches, "minos": minimum,
            "install_dependencies": install_dependencies(path, arch)}


def inspect_dependencies(config, selected):
    if config.get("schema_version") != 1:
        fail("dependency configuration schema_version must be 1")
    report = {"schema_version": 1, "architectures": {}}
    for arch in selected:
        c = config["architectures"][arch]
        dirs = {n: path_field(c, n, True) for n in
                ("prefix", "vulkan_include", "ffmpeg_include", "ffmpeg_lib_dir", "libass_include", "uchardet_include")}
        primary = {n: path_field(c, n) for n in
                   ("libplacebo_library", "vulkan_library", "libass_library", "uchardet_library")}
        include = dirs["ffmpeg_include"]
        if '#define FFMPEG_VERSION "9.0.1"' not in (include / "libavutil/ffversion.h").read_text():
            fail("only reviewed FFmpeg 9.0.1 headers are supported")
        versions = {}
        for name, expected in FFMPEG.items():
            upper = name.upper()
            version = ".".join(str(macro(include / name / ("version_major.h" if field == "MAJOR" and name != "libavutil" else "version.h"),
                                        upper + "_VERSION_" + field)) for field in ("MAJOR", "MINOR", "MICRO"))
            if version != expected:
                fail(f"FFmpeg header ABI mismatch: {name} {version}, expected {expected}")
            versions[name] = version
            primary[name] = (dirs["ffmpeg_lib_dir"] / (name + ".dylib")).resolve(strict=True)
        if macro(dirs["prefix"] / "include/libplacebo/config.h", "PL_API_VER") != 349:
            fail("libplacebo headers must be API349")
        if macro(dirs["libass_include"] / "ass/ass.h", "LIBASS_VERSION") != 0x01701000:
            fail("libass headers must match reviewed 0.17.1")
        versions.update({"ffmpeg": "9.0.1", "libplacebo": "7.349.0", "libass": "0.17.1", "uchardet": "0.0.8"})
        vk = dirs["vulkan_include"] / "vulkan/vulkan_core.h"
        versions["vulkan"] = "1.4." + str(macro(vk, "VK_HEADER_VERSION"))
        search = list(dict.fromkeys([*(p.parent for p in primary.values()), dirs["prefix"] / "lib"]))
        roots = [*search, dirs["prefix"]]
        libraries = {}
        pending = list(primary.values())
        while pending:
            p = pending.pop().resolve(strict=True)
            if str(p) in libraries:
                continue
            if not any(p.is_relative_to(root) for root in roots):
                fail(f"dependency escapes explicitly supplied library roots: {p}")
            entry = library_identity(p, arch)
            libraries[str(p)] = entry
            # A dylib's first LC_LOAD_DYLIB-looking line is its own ID.
            for dep in entry["install_dependencies"][1:]:
                if dep.startswith(("/usr/lib/", "/System/Library/")):
                    continue
                if "/opt/homebrew/" in dep or "/usr/local/Cellar/" in dep:
                    fail(f"Homebrew link in reviewed input: {p} -> {dep}")
                if dep.startswith("@rpath/"):
                    candidates = [root / dep[7:] for root in search]
                    q = next((q for q in candidates if q.is_file()), None)
                elif dep.startswith("@loader_path/"):
                    q = p.parent / dep[13:]
                else:
                    q = Path(dep)
                if q is None or not q.is_file():
                    fail(f"unresolved dependency: {p} -> {dep}")
                pending.append(q)
        # Confirm actual dylib compatibility metadata agrees with header ABI.
        for name in FFMPEG:
            text = output(["otool", "-arch", arch, "-L", primary[name]])
            match = re.search(r"current version ([0-9.]+)", text)
            if not match or match.group(1) != versions[name]:
                fail(f"FFmpeg runtime/header version mismatch: {primary[name]}")
        report["architectures"][arch] = {"paths": {n: str(p) for n, p in dirs.items()},
            "primary_libraries": {n: str(p) for n, p in primary.items()}, "versions": versions,
            "headers": {n: tree(p) for n, p in {"runtime": dirs["prefix"] / "include",
                 "vulkan": dirs["vulkan_include"], "ffmpeg": include, "libass": dirs["libass_include"], "uchardet": dirs["uchardet_include"]}.items()},
            "libraries": libraries, "library_search": [str(p) for p in search]}
    return report


def toolchain():
    tools = {name: str(Path(shutil.which(name) or fail(f"missing tool: {name}")).resolve())
             for name in ("meson", "ninja", "pkg-config")}
    for name in ("clang", "clang++", "ar", "strip", "swiftc"):
        tools[name] = output(["xcrun", "--find", name])
    tools["python"] = str(Path(sys.executable).resolve())
    return {"paths": tools, "sha256": {n: sha(p) for n, p in tools.items()},
            "clang_version": output([tools["clang"], "--version"]),
            "swift_version": output([tools["swiftc"], "--version"]),
            "meson_version": output([tools["meson"], "--version"]),
            "ninja_version": output([tools["ninja"], "--version"]),
            "sdk_path": output(["xcrun", "--show-sdk-path"]),
            "sdk_version": output(["xcrun", "--show-sdk-version"])}


def verify_source(archive, source):
    return json.loads(output([sys.executable, HERE / "verify_source.py", archive, source]))


def clean_environment():
    env = os.environ.copy()
    for name in list(env):
        if name.startswith(("DYLD_", "MESON_")):
            env.pop(name, None)
    for name in ("CFLAGS", "CXXFLAGS", "OBJCFLAGS", "CPPFLAGS", "LDFLAGS", "CPATH",
                 "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "LIBRARY_PATH", "SDKROOT",
                 "PKG_CONFIG_SYSROOT_DIR", "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH",
                 "MACOSX_DEPLOYMENT_TARGET", "CC", "CXX", "OBJC", "AR", "PYTHONPATH", "PYTHONHOME"):
        env.pop(name, None)
    env["PKG_CONFIG_PATH"] = ""
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


def validate_output_paths(work, dest, archive, dependencies):
    if work == dest or work.is_relative_to(dest) or dest.is_relative_to(work):
        fail("work-dir and output-dir must be separate non-nested paths")
    protected = [HERE.parent.parent, archive.resolve().parent]
    for dep in dependencies["architectures"].values():
        protected.extend(Path(p) for p in dep["paths"].values())
        protected.extend(Path(p).parent for p in dep["primary_libraries"].values())
    for candidate in (work, dest):
        if any(part.endswith(".app") for part in candidate.parts):
            fail(f"build/output may not be inside an application: {candidate}")
        if any(candidate == p or candidate.is_relative_to(p) or p.is_relative_to(candidate) for p in protected):
            fail(f"build/output intersects repository or dependency/archive input: {candidate}")


def rpaths(path, arch):
    text = output(["otool", "-arch", arch, "-l", path])
    return re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset", text)


def run(command, log, env):
    print("Running " + json.dumps([str(x) for x in command]), flush=True)
    with Path(log).open("w") as stream:
        stream.write("COMMAND " + json.dumps([str(x) for x in command]) + "\n")
        stream.flush()
        completed = subprocess.run([str(x) for x in command], env=env, stdout=stream, stderr=subprocess.STDOUT)
    if completed.returncode:
        fail(f"command exit {completed.returncode}; log: {log}")


def machine_files(work, arch, dependency, tools):
    directory = work / arch
    directory.mkdir(exist_ok=True)
    pc = directory / "pkgconfig"
    pc.mkdir(exist_ok=True)
    primary = dependency["primary_libraries"]
    headers = dependency["paths"]
    versions = dependency["versions"]
    for name, library in primary.items():
        if name.startswith("libav") or name.startswith("libsw"):
            include = headers["ffmpeg_include"]
        elif name == "libass_library":
            include = headers["libass_include"]
        elif name == "uchardet_library":
            include = headers["uchardet_include"]
        elif name == "vulkan_library":
            include = headers["vulkan_include"]
        else:
            include = str(Path(headers["prefix"]) / "include")
        package = {"libplacebo_library": "libplacebo", "vulkan_library": "vulkan",
                   "libass_library": "libass", "uchardet_library": "uchardet"}.get(name, name)
        extras = "pl_has_vulkan=1\npl_has_dovi=1\npl_has_opengl=1\n" if package == "libplacebo" else ""
        # pkg-config consumes shell-style quoted paths; never execute their text.
        (pc / (package + ".pc")).write_text(f"includedir={include}\n" + extras + f"Name: {package}\nDescription: Locked reviewed dependency\n"
            + f"Version: {versions[package]}\nLibs: \"{library}\"\nCflags: -I\"{include}\"\n")
    t = tools["paths"]
    flags = ["-isysroot", tools["sdk_path"], "-mmacosx-version-min=" + MIN_OS]
    link = ["-arch", arch, *flags, *("-Wl,-rpath," + p for p in dependency["library_search"])]
    cross = directory / "cross.ini"
    cross.write_text("[binaries]\n" + "\n".join(f"{n} = {machine_value(v)}" for n, v in {
        "c": [t["clang"], "-arch", arch], "cpp": [t["clang++"], "-arch", arch],
        "objc": [t["clang"], "-arch", arch], "ar": t["ar"], "strip": t["strip"],
        "pkg-config": t["pkg-config"], "python": t["python"], "swift": t["swiftc"]}.items())
        + f"\n[host_machine]\nsystem = 'darwin'\ncpu_family = '{'aarch64' if arch == 'arm64' else 'x86_64'}'\ncpu = '{arch}'\nendian = 'little'\n"
        + "[properties]\nneeds_exe_wrapper = true\n[built-in options]\n"
        + "\n".join(f"{lang}_args = {machine_value(flags)}\n{lang}_link_args = {machine_value(link)}" for lang in ("c", "cpp", "objc")) + "\n")
    native = directory / "native.ini"
    native.write_text("[binaries]\npython = " + machine_value(t["python"]) + "\n")
    return directory, pc, cross, native


def machine_value(value):
    if isinstance(value, list):
        return "[" + ", ".join(machine_value(x) for x in value) + "]"
    if any(c in str(value) for c in ("'", "\\", "\n", "\r")):
        fail(f"unsupported machinefile value: {value}")
    return "'" + str(value) + "'"


def publish_slice(work, destination, staging, manifest, state, arch):
    """Recoverable publication: preserve completed output until staged validation.

    The pending manifest binds the staged/current bytes to the build identity.
    An interruption after either atomic replace can resume publication; package
    consumers must always check the manifest SHA against the actual library.
    """
    pending = work / arch / "pending-publication.json"
    write_json(pending, manifest)
    library = destination / "libmpv.2.dylib"
    if staging.exists():
        if sha(staging) != manifest["sha256"]:
            fail("staged publication bytes changed")
        staging.replace(library)
    elif not library.is_file() or sha(library) != manifest["sha256"]:
        fail("interrupted publication has neither staged nor matching published library")
    subprocess.run(["codesign", "--verify", "--strict", library], check=True)
    write_json(destination / "slice-manifest.json", manifest)
    state["slices"].setdefault(arch, {}).update({"library_sha256": manifest["sha256"], "completed": True})
    write_json(work / "build-state.json", state)
    pending.unlink()


def build_slice(work, dest, source, arch, dependency, tools, state, identity, args):
    directory, pc, cross, native = machine_files(work, arch, dependency, tools)
    build = directory / "build"
    env = clean_environment()
    env["PKG_CONFIG_LIBDIR"] = str(pc)  # No host/Homebrew pkg-config fallback.
    meson = tools["paths"]["meson"]
    options = dict(OPTIONS)
    options["swift-flags"] = f"-target {arch}-apple-macosx{MIN_OS} -sdk {tools['sdk_path']} -Xcc -fmodules-cache-path={build}/swift-cache"
    flags = [f"-D{k}={str(v).lower() if isinstance(v, bool) else v}" for k, v in options.items()]
    core = build / "meson-private/coredata.dat"
    saved = state["slices"].get(arch, {})
    destination = dest / arch
    destination.mkdir(exist_ok=True)
    staging = directory / "libmpv.2.dylib.staging"
    pending = directory / "pending-publication.json"
    if pending.exists():
        recovering = json.loads(pending.read_text())
        if (recovering["build_identity_sha256"] != canonical(identity) or
                recovering["source"] != state["verified_source"] or
                recovering["dependency_identity_sha256"] != canonical(dependency) or
                recovering["library"] != str(destination / "libmpv.2.dylib")):
            fail("interrupted publication identity changed")
        publish_slice(work, destination, staging, recovering, state, arch)
        saved = state["slices"][arch]
    if core.exists():
        if saved.get("coredata_sha256") != sha(core):
            fail(f"configured build identity changed for {arch}; choose fresh work/output")
    else:
        run([meson, "setup", build, source, "--cross-file", cross, "--native-file", native, *flags],
            directory / "setup.log", env)
        saved["coredata_sha256"] = sha(core)
        state["slices"][arch] = saved
        write_json(work / "build-state.json", state)
    start = time.monotonic()
    run([meson, "compile", "-C", build, "-j", str(args.jobs)], directory / "compile.log", env)
    if verify_source(args.archive, source) != state["verified_source"]:
        fail("source changed during compilation")
    raw = build / "libmpv.2.dylib"
    if output(["lipo", "-archs", raw]).split() != [arch] or minos(raw, arch) != MIN_OS:
        fail(f"output ABI/deployment target mismatch for {arch}")
    if b"opengl-next\0" not in raw.read_bytes():
        fail("output does not contain opt-in shared backend")
    library = destination / "libmpv.2.dylib"
    if library.exists() and not args.resume:
        fail(f"existing output would be overwritten: {library}")
    if library.exists() and saved.get("library_sha256") != sha(library):
        fail(f"existing output identity changed: {library}")
    shutil.copy2(raw, staging)
    # Normalize scratch absolute direct install names only on derived slice.
    for name in install_dependencies(staging, arch)[1:]:
        if name.startswith(("/System/Library/", "/usr/lib/", "@rpath/")):
            continue
        p = Path(name).resolve()
        if str(p) not in dependency["libraries"]:
            fail(f"unreviewed output link: {name}")
        normalized = "libplacebo.dylib" if "libplacebo" in p.name else p.name
        subprocess.run(["install_name_tool", "-change", name, "@rpath/" + normalized, staging], check=True)
    for name in install_dependencies(staging, arch)[1:]:
        if not name.startswith(("@rpath/", "/System/Library/", "/usr/lib/")):
            fail(f"nonportable or Homebrew link remains: {name}")
    subprocess.run(["codesign", "--force", "--sign", "-", staging], check=True)
    subprocess.run(["codesign", "--verify", "--strict", staging], check=True)
    manifest = {"schema_version": 1, "candidate": True, "architecture": arch,
        "mpv_version": "0.41.0", "minimum_macos": MIN_OS, "api_type": "opengl-next",
        "library": str(library), "sha256": sha(staging), "raw_sha256": sha(raw),
        "source": state["verified_source"], "build_identity_sha256": canonical(identity),
        "dependency_identity_sha256": canonical(dependency), "dependencies": dependency,
        "toolchain": tools, "options": options, "elapsed_seconds": time.monotonic() - start,
        "linked_libraries": install_dependencies(staging, arch), "rpaths": rpaths(staging, arch),
        "external_runtime": True, "portable_bundle": False, "runtime_acceptance": False}
    saved.update({"coredata_sha256": sha(core)})
    state["slices"][arch] = saved
    publish_slice(work, destination, staging, manifest, state, arch)
    return manifest


def publish_package(work, dest, slices, state, identity):
    """Only a complete, revalidated candidate directory becomes consumable."""
    package = {"schema_version": 1, "candidate": True, "source": state["verified_source"],
        "build_identity_sha256": canonical(identity), "architectures": identity["architectures"],
        "external_runtime": True, "portable_bundle": False, "runtime_acceptance": False,
        "slices": [{"architecture": m["architecture"], "library": str(dest / m["architecture"] / "libmpv.2.dylib"),
                    "sha256": m["sha256"], "manifest": str(dest / m["architecture"] / "slice-manifest.json")} for m in slices]}
    if dest.exists():
        if not (dest / "slice-manifest.json").is_file():
            fail("published output is missing its manifest")
        existing = json.loads((dest / "slice-manifest.json").read_text())
        if existing != state.get("publication") or {k: v for k, v in existing.items() if k != "files"} != package:
            fail("published output is immutable or differs; select fresh work/output")
        if publication_files(dest) != existing["files"]:
            fail("published output file set or bytes differ; refusing to overwrite")
        return existing
    dest.parent.mkdir(parents=True, exist_ok=True)
    staging = dest.with_name("." + dest.name + ".staging")
    if staging.exists():
        marker = staging / "publication-identity.json"
        if not marker.is_file() or json.loads(marker.read_text()) != {"build_identity_sha256": canonical(identity)}:
            fail("unknown sibling staging directory; refusing to modify")
        # Only our unpublished copy is discarded; completed work slices remain.
        shutil.rmtree(staging)
    staging.mkdir()
    write_json(staging / "publication-identity.json", {"build_identity_sha256": canonical(identity)})
    for m in slices:
        directory = staging / m["architecture"]
        directory.mkdir()
        library = directory / "libmpv.2.dylib"
        shutil.copy2(m["library"], library)
        if sha(library) != m["sha256"]:
            fail("staged slice copy differs")
        derived = dict(m)
        derived["library"] = str(dest / m["architecture"] / "libmpv.2.dylib")
        write_json(directory / "slice-manifest.json", derived)
    write_json(staging / "approved-slices.json", {m["architecture"]: m["sha256"] for m in slices})
    package["files"] = publication_files(staging)
    write_json(staging / "slice-manifest.json", package)
    state["publication"] = package
    write_json(work / "build-state.json", state)
    staging.rename(dest)  # same parent/filesystem: atomic complete-directory publication
    return package


def publication_files(directory):
    files = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            fail(f"symlink in published output: {path}")
        if path.is_file() and path != directory / "slice-manifest.json":
            files[str(path.relative_to(directory))] = sha(path)
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--dependency-config", type=Path, required=True)
    parser.add_argument("--dependency-lock", type=Path)
    parser.add_argument("--inspect-dependencies", type=Path, metavar="REPORT")
    parser.add_argument("--architectures", nargs="+", choices=ARCHES, default=list(ARCHES))
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("this builder requires macOS/Xcode")
    if not 1 <= args.jobs <= 64 or len(set(args.architectures)) != len(args.architectures):
        parser.error("jobs must be 1..64 and architectures must be unique")
    config = json.loads(args.dependency_config.read_text())
    dependencies = inspect_dependencies(config, args.architectures)
    if args.inspect_dependencies:
        if args.inspect_dependencies.exists():
            parser.error("inspection report already exists; keep reviewed locks immutable")
        write_json(args.inspect_dependencies, dependencies)
        print("Dependency inspection only; review before using as --dependency-lock", flush=True)
        return
    if not all((args.archive, args.work_dir, args.output_dir, args.dependency_lock)):
        parser.error("build requires explicit archive, work-dir, output-dir and reviewed dependency-lock")
    if json.loads(args.dependency_lock.read_text()) != dependencies:
        parser.error("dependency identity differs from reviewed lock")
    work, dest = args.work_dir.resolve(), args.output_dir.resolve()
    validate_output_paths(work, dest, args.archive, dependencies)
    ancestor = work.parent
    while not ancestor.exists():
        ancestor = ancestor.parent
    if shutil.disk_usage(ancestor).free < 2 * 1024**3:
        parser.error("at least 2GiB free space is required before building")
    source = work / "source"
    tools = toolchain()
    identity = {"schema_version": 1, "builder_sha256": sha(__file__),
        "archive": str(args.archive.resolve()), "archive_sha256": sha(args.archive),
        "preparer_sha256": sha(HERE / "prepare.py"), "verifier_sha256": sha(HERE / "verify_source.py"),
        "manifest_sha256": sha(HERE / "manifest.json"), "patch_sha256": sha(HERE / "mpv-0.41-shared-core.patch"),
        "work_dir": str(work), "output_dir": str(dest), "architectures": args.architectures,
        "jobs": args.jobs, "options": OPTIONS, "dependencies": dependencies, "toolchain": tools}
    if not args.resume and (work.exists() or dest.exists()):
        parser.error("fresh build requires absent work-dir and output-dir; no original build is reused")
    if args.resume and not (work / "build-state.json").is_file():
        parser.error("resume requires builder-owned state")
    work.mkdir(parents=True, exist_ok=args.resume)
    with (work / ".build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.resume:
            state = json.loads((work / "build-state.json").read_text())
            if state["identity"] != identity:
                parser.error("resume source/parameters/toolchain/dependency identity differs")
            if verify_source(args.archive, source) != state["verified_source"]:
                parser.error("resume full source tree differs")
        else:
            env = clean_environment()
            run([sys.executable, HERE / "prepare.py", args.archive, source], work / "prepare.log", env)
            state = {"identity": identity, "verified_source": verify_source(args.archive, source), "slices": {}}
            write_json(work / "build-state.json", state)
        private_staging = work / "slice-staging"
        private_staging.mkdir(exist_ok=args.resume)
        slices = []
        for arch in args.architectures:
            slices.append(build_slice(work, private_staging, source, arch, dependencies["architectures"][arch], tools, state, identity, args))
        if inspect_dependencies(config, args.architectures) != dependencies:
            fail("dependency inputs changed during build")
        if verify_source(args.archive, source) != state["verified_source"]:
            fail("full source tree changed before publication")
        package = publish_package(work, dest, slices, state, identity)
        print(json.dumps(package, indent=2), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"build_macos: {error}", file=sys.stderr)
        sys.exit(2)
