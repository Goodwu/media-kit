"""Contract tests use tiny synthetic payloads; these are not native build tests."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import platform as host_platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile


MODULE_PATH = Path(__file__).resolve().parents[1] / "package.py"
SPEC = importlib.util.spec_from_file_location("native_package", MODULE_PATH)
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)


class PackageContract(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="media kit contract ")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.root = self.base / "payload"
        self.root.mkdir()
        self.host_architecture = "arm64" if host_platform.machine().lower() in {"arm64", "aarch64"} else "x86_64"

    def write(self, relative, value=b"test fixture\n"):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value)
        return path

    def symlink(self, path, target, directory=False):
        try:
            path.symlink_to(target, target_is_directory=directory)
        except OSError as error:
            self.skipTest(f"Host cannot create symbolic links: {error}")

    def fixture(self, platform="linux", architectures=None):
        arch = architectures or (["arm64-v8a", "armeabi-v7a", "x86_64", "x86"]
                                 if platform == "android" else ["x86_64"])
        spec = {
            "platform": platform, "architectures": arch, "profile": "contract-fixture",
            "identity": {"origin": "source", "sources": {
                "mpv": {"repository": "https://github.com/example/mpv", "commit": "a" * 40}}},
            "capabilities": [], "validation": {"compiled": False, "runtime": False, "device": False},
        }
        if platform == "android":
            jars = {}
            for abi in arch:
                path = self.root / "runtime" / f"{abi}.jar"
                path.parent.mkdir(parents=True, exist_ok=True)
                with zipfile.ZipFile(path, "w") as jar:
                    jar.writestr(f"lib/{abi}/libmpv.so", b"synthetic ELF")
                jars[abi] = path.relative_to(self.root).as_posix()
            spec["layout"] = {"jars": jars}
        else:
            for name in ("client.h", "render.h", "render_gl.h", "render_dxgi.h"):
                self.write(f"include/mpv/{name}")
            if platform in {"linux", "windows"}:
                runtime = "lib/libmpv.so.2" if platform == "linux" else "bin/libmpv-2.dll"
                self.write(runtime)
                spec["layout"] = {"include": "include", "runtime": runtime, "bundle": [runtime]}
                if platform == "windows":
                    self.write("lib/libmpv.dll.a")
                    spec["layout"]["import_library"] = "lib/libmpv.dll.a"
            elif platform in {"ios", "macos"}:
                slices = []
                variants = [None, "simulator"] if platform == "ios" else [None]
                for variant in variants:
                    identifier = platform + "-" + "_".join(arch) + ("-" + variant if variant else "")
                    slices.append({"LibraryIdentifier": identifier, "LibraryPath": "Mpv.framework",
                                   "SupportedArchitectures": arch, "SupportedPlatform": platform,
                                   **({"SupportedPlatformVariant": variant} if variant else {})})
                    self.write(f"Frameworks/Mpv.xcframework/{identifier}/Mpv.framework/Mpv")
                self.write("Frameworks/Mpv.xcframework/Info.plist", plistlib.dumps({"AvailableLibraries": slices}))
                spec["layout"] = {"include": "include", "frameworks": ["Frameworks/Mpv.xcframework"]}
            elif platform == "ohos":
                self.write("libmpv-ohos-arm64.tar.gz")
                spec["layout"] = {"archive": "libmpv-ohos-arm64.tar.gz", "include": "include"}
        spec_path = self.base / "spec.json"
        spec_path.write_text(json.dumps(spec), encoding="utf-8")
        return spec_path

    def created(self, platform="linux", architectures=None):
        result = package.create(self.root, self.fixture(platform, architectures))
        return result, package.verify(self.root, result["manifest_sha256"], platform)

    def test_all_platform_contracts_and_identity_canonicalization(self):
        for platform in sorted(package.PLATFORMS):
            with self.subTest(platform=platform):
                shutil.rmtree(self.root)
                self.root.mkdir()
                created, verified = self.created(platform)
                manifest = package.read_json(Path(created["manifest"]))
                self.assertEqual(verified["identity_sha256"], package.digest(package.canonical(manifest["identity"])))
                self.assertNotIn("manifest.json", manifest["files"])
                self.assertFalse(verified["validation"]["compiled"])

    def test_modified_runtime_and_unlisted_file_are_rejected(self):
        created, _ = self.created()
        runtime = self.root / "lib/libmpv.so.2"
        original = runtime.read_bytes()
        runtime.write_bytes(b"changed")
        with self.assertRaisesRegex(package.PackageError, "files or symbolic links differ"):
            package.verify(self.root, created["manifest_sha256"], "linux")
        runtime.write_bytes(original)
        self.write("extra.so")
        with self.assertRaises(package.PackageError):
            package.verify(self.root, created["manifest_sha256"], "linux")

    def test_manifest_digest_platform_architecture_identity_are_required(self):
        created, _ = self.created()
        for kwargs in ({"expected": "0" * 64}, {"platform": "windows"},
                       {"architecture": "arm64"}, {"expected_identity": "b" * 64}):
            arguments = {"root": self.root, "expected": created["manifest_sha256"], "platform": "linux", **kwargs}
            with self.subTest(kwargs=kwargs), self.assertRaises(package.PackageError):
                package.verify(**arguments)

    def test_missing_dxgi_headers_are_not_accepted(self):
        spec = self.fixture("windows")
        (self.root / "include/mpv/render_dxgi.h").unlink()
        with self.assertRaisesRegex(package.PackageError, "Missing or cyclic"):
            package.create(self.root, spec)

    def test_android_mixed_abi_jar_is_rejected(self):
        spec = self.fixture("android", ["arm64-v8a"])
        with zipfile.ZipFile(self.root / "runtime/arm64-v8a.jar", "a") as jar:
            jar.writestr("lib/x86/libmpv.so", b"wrong ABI")
        with self.assertRaisesRegex(package.PackageError, "mixes ABIs"):
            package.create(self.root, spec)

    def test_android_missing_mpv_and_unsafe_entry_are_rejected(self):
        for name in ("lib/arm64-v8a/libnotmpv.so", "../libmpv.so"):
            spec = self.fixture("android", ["arm64-v8a"])
            with zipfile.ZipFile(self.root / "runtime/arm64-v8a.jar", "w") as jar:
                jar.writestr(name, b"fixture")
            with self.subTest(name=name), self.assertRaises(package.PackageError):
                package.create(self.root, spec)

    def test_android_development_sdk_prefix_is_optional_and_recorded(self):
        spec_path = self.fixture("android", ["arm64-v8a"])
        self.write("sdk/arm64-v8a/include/mpv/client.h")
        spec = package.read_json(spec_path)
        spec["layout"]["sdk_prefixes"] = {"arm64-v8a": "sdk/arm64-v8a"}
        spec_path.write_text(json.dumps(spec), encoding="utf-8")
        created = package.create(self.root, spec_path)
        verified = package.verify(self.root, created["manifest_sha256"], "android")
        self.assertIn("arm64-v8a", verified["layout"]["sdk_prefixes"])

    def test_partial_environment_never_falls_back(self):
        created, _ = self.created()
        for env in ({}, {package.ENV_KEYS[0]: str(self.root)},
                    {package.ENV_KEYS[2]: created["manifest_sha256"]},
                    {package.ENV_KEYS[0]: str(self.root), package.ENV_KEYS[2]: "0" * 64}):
            with self.subTest(env=env), patch.dict(os.environ, env, clear=True):
                with self.assertRaises(package.PackageError):
                    package.from_environment("linux")

    def test_escaping_link_and_directory_cycles_are_rejected(self):
        spec = self.fixture()
        outside = self.base / "outside.h"
        outside.write_bytes(b"outside")
        link = self.root / "escape"
        self.symlink(link, "../outside.h")
        with self.assertRaisesRegex(package.PackageError, "escapes"):
            package.create(self.root, spec)
        link.unlink()
        for name in ("A", "B"):
            (self.root / name).mkdir()
        self.symlink(self.root / "A/to-B", "../B", True)
        self.symlink(self.root / "B/to-A", "../A", True)
        with self.assertRaisesRegex(package.PackageError, "recursive directory"):
            package.create(self.root, spec)

    def test_safe_library_link_requires_flat_bundle_target(self):
        spec_path = self.fixture()
        runtime = self.root / "lib/libmpv.so.2"
        runtime.rename(self.root / "lib/libmpv.so.2.5")
        self.symlink(runtime, "libmpv.so.2.5")
        with self.assertRaisesRegex(package.PackageError, "bundled filename"):
            package.create(self.root, spec_path)
        spec = package.read_json(spec_path)
        spec["layout"]["bundle"].append("lib/libmpv.so.2.5")
        spec_path.write_text(json.dumps(spec), encoding="utf-8")
        created = package.create(self.root, spec_path)
        verified = package.verify(self.root, created["manifest_sha256"], "linux")
        self.assertEqual(len(verified["layout"]["bundle"]), 2)

    def test_apple_matching_headers_framework_staging_and_safe_links(self):
        spec = self.fixture("macos", ["arm64", "x86_64"])
        framework = self.root / "Frameworks/Mpv.xcframework/macos-arm64_x86_64/Mpv.framework"
        (framework / "Versions/A").mkdir(parents=True)
        (framework / "Mpv").rename(framework / "Versions/A/Mpv")
        self.symlink(framework / "Versions/Current", "A", True)
        self.symlink(framework / "Mpv", "Versions/Current/Mpv")
        created = package.create(self.root, spec)
        verified = package.verify(self.root, created["manifest_sha256"], "macos")
        staged = self.base / "pod/Frameworks"
        package.stage_frameworks(verified, staged)
        package.copy_headers(verified, self.base / "pod/Headers")
        self.assertTrue((staged / ".symlinks/mpv/macos/Mpv.framework/Mpv").is_file())
        self.assertTrue((self.base / "pod/Headers/mpv/client.h").is_file())
        with self.assertRaises(package.PackageError):
            package.stage_frameworks(verified, self.root / "staged")

    def test_cmake_data_with_spaces_and_injection_rejection(self):
        _, verified = self.created()
        path = self.base / "data.cmake"
        package.cmake_data(verified, path)
        self.assertIn("[==[", path.read_text(encoding="utf-8"))
        verified["layout"]["runtime"] += ";evil"
        with self.assertRaises(package.PackageError):
            package.cmake_data(verified, path)

    @unittest.skipUnless(shutil.which("cmake"), "CMake is not installed")
    def test_cmake_consumer_verifies_and_rejects_modified_payload(self):
        created, _ = self.created()
        script = self.base / "consume.cmake"
        helper = MODULE_PATH.with_name("consume.cmake").as_posix()
        script.write_text(f'set(MEDIA_KIT_PACKAGE_PLATFORM linux)\n'
                          f'set(MEDIA_KIT_PACKAGE_ARCHITECTURE x86_64)\n'
                          f'include("{helper}")\n'
                          f'if(NOT EXISTS "${{MEDIA_KIT_PACKAGE_RUNTIME}}")\n'
                          f'  message(FATAL_ERROR "runtime missing")\nendif()\n', encoding="utf-8")
        env = {**os.environ, package.ENV_KEYS[0]: str(self.root),
               package.ENV_KEYS[1]: created["manifest"], package.ENV_KEYS[2]: created["manifest_sha256"],
               "MEDIA_KIT_NATIVE_PACKAGE_PYTHON": sys.executable}
        good = subprocess.run(["cmake", "-P", str(script)], cwd=self.base, env=env, capture_output=True, text=True)
        self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
        self.write("lib/libmpv.so.2", b"changed")
        bad = subprocess.run(["cmake", "-P", str(script)], cwd=self.base, env=env, capture_output=True, text=True)
        self.assertNotEqual(bad.returncode, 0)
        self.assertIn("verification failed", bad.stderr)

    def test_duplicate_keys_and_unsafe_paths_are_rejected(self):
        path = self.base / "duplicate.json"
        path.write_text('{"schema":1,"schema":2}', encoding="utf-8")
        with self.assertRaises(package.PackageError):
            package.read_json(path)
        for value in ("../x", "/x", "a/../x", "a\\x", "a:x", "a//x", "a/./x"):
            with self.subTest(value=value), self.assertRaises(package.PackageError):
                package.relative(value)

    @unittest.skipUnless(shutil.which("make") and os.name != "nt", "Apple Make adapter needs a Unix host")
    def test_apple_make_adapters_use_package_and_stop_on_partial_input(self):
        repository = MODULE_PATH.parents[2]
        checkout = self.base / "source checkout"
        verifier = checkout / "tool/native_package/package.py"
        verifier.parent.mkdir(parents=True)
        shutil.copy2(MODULE_PATH, verifier)
        for platform in ("ios", "macos"):
            with self.subTest(platform=platform):
                shutil.rmtree(self.root)
                self.root.mkdir()
                created, _ = self.created(platform, ["arm64", "x86_64"])
                relative = f"libs/{platform}/media_kit_libs_{platform}_video/{platform}"
                pod = checkout / relative
                pod.mkdir(parents=True)
                shutil.copy2(repository / relative / "Makefile", pod / "Makefile")
                env = {name: value for name, value in os.environ.items() if name not in package.ENV_KEYS}
                default = subprocess.run(["make", "-n", "-C", str(pod)], env=env, capture_output=True, text=True)
                self.assertEqual(default.returncode, 0, default.stdout + default.stderr)
                self.assertIn("curl -L", default.stdout)
                self.assertNotIn("package.py", default.stdout)
                env.update({package.ENV_KEYS[0]: str(self.root), package.ENV_KEYS[2]: created["manifest_sha256"],
                            "MEDIA_KIT_NATIVE_PACKAGE_PYTHON": sys.executable})
                good = subprocess.run(["make", "-C", str(pod)], env=env, capture_output=True, text=True)
                self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
                self.assertTrue((pod / f"Frameworks/.symlinks/mpv/{platform}/Mpv.framework/Mpv").is_file())
                self.assertFalse((pod / ".cache").exists())
                headers_make = checkout / "media_kit_video/common/darwin"
                headers_make.mkdir(parents=True, exist_ok=True)
                shutil.copy2(repository / "media_kit_video/common/darwin/Makefile", headers_make / "Makefile")
                headers = self.base / f"{platform} generated headers"
                result = subprocess.run(["make", "-C", str(headers_make), f"HEADERS_DESTDIR={headers}",
                                         f"MEDIA_KIT_APPLE_PLATFORM={platform}"], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue((headers / "mpv/client.h").is_file())
                env.pop(package.ENV_KEYS[2])
                env[package.ENV_KEYS[0]] = ""
                bad = subprocess.run(["make", "-C", str(pod)], env=env, capture_output=True, text=True)
                self.assertNotEqual(bad.returncode, 0)
                self.assertIn("requires", bad.stderr)
                self.assertFalse((pod / ".cache").exists())

    @unittest.skipUnless(shutil.which("cmake") and shutil.which("c++"), "CMake/C++ compiler is not installed")
    def test_windows_cmake_consumes_one_sdk_without_downloading(self):
        created, verified = self.created("windows", [self.host_architecture])
        source = self.base / "cmake source"
        source.mkdir()
        repository = MODULE_PATH.parents[2].as_posix()
        expected_include = (self.root / "include/mpv").as_posix()
        (source / "CMakeLists.txt").write_text(
            'cmake_minimum_required(VERSION 3.14)\nproject(Contract LANGUAGES CXX)\n'
            'function(apply_standard_settings target)\nendfunction()\n'
            'add_library(flutter INTERFACE)\nadd_library(flutter_wrapper_plugin INTERFACE)\n'
            f'add_subdirectory("{repository}/libs/windows/media_kit_libs_windows_video/windows" libs)\n'
            f'add_subdirectory("{repository}/media_kit_video/windows" video)\n'
            'get_target_property(_includes media_kit_video_plugin INCLUDE_DIRECTORIES)\n'
            f'if(NOT "{expected_include}" IN_LIST _includes)\n'
            '  message(FATAL_ERROR "Matching SDK headers not selected")\nendif()\n'
            f'if(NOT media_kit_libs_windows_video_bundled_libraries STREQUAL "{Path(verified["layout"]["runtime"]).as_posix()}")\n'
            '  message(FATAL_ERROR "Matching runtime not selected")\nendif()\n', encoding="utf-8")
        env = {**os.environ, package.ENV_KEYS[0]: str(self.root), package.ENV_KEYS[2]: created["manifest_sha256"],
               "MEDIA_KIT_NATIVE_PACKAGE_PYTHON": sys.executable}
        env.pop(package.ENV_KEYS[1], None)
        result = subprocess.run(["cmake", "-S", str(source), "-B", str(self.base / "build")],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Downloading archive", result.stdout)

    @unittest.skipUnless(shutil.which("cmake") and shutil.which("c++") and shutil.which("pkg-config"),
                         "CMake/C++/pkg-config is not installed")
    def test_linux_cmake_sets_relative_rpath_and_bundles_package(self):
        created, verified = self.created("linux", [self.host_architecture])
        source = self.base / "cmake source"
        source.mkdir()
        repository = MODULE_PATH.parents[2].as_posix()
        (source / "CMakeLists.txt").write_text(
            'cmake_minimum_required(VERSION 3.14)\nproject(Contract LANGUAGES CXX)\n'
            'function(apply_standard_settings target)\nendfunction()\n'
            'add_library(flutter INTERFACE)\n'
            'add_library(PkgConfig::GTK INTERFACE IMPORTED)\n'
            'add_library(PkgConfig::epoxy INTERFACE IMPORTED)\n'
            'set(MEDIA_KIT_LIBS_AVAILABLE ON)\n'
            f'add_subdirectory("{repository}/media_kit_video/linux" video)\n'
            'get_target_property(_rpath media_kit_video_plugin INSTALL_RPATH)\n'
            'get_target_property(_link_path media_kit_video_plugin INSTALL_RPATH_USE_LINK_PATH)\n'
            'if(NOT _rpath STREQUAL "$ORIGIN" OR _link_path)\n'
            '  message(FATAL_ERROR "Build-machine RPATH could leak into package")\nendif()\n'
            f'if(NOT media_kit_video_bundled_libraries STREQUAL "{Path(verified["layout"]["runtime"]).as_posix()}")\n'
            '  message(FATAL_ERROR "Matching runtime not selected")\nendif()\n', encoding="utf-8")
        env = {**os.environ, package.ENV_KEYS[0]: str(self.root), package.ENV_KEYS[2]: created["manifest_sha256"],
               "MEDIA_KIT_NATIVE_PACKAGE_PYTHON": sys.executable}
        env.pop(package.ENV_KEYS[1], None)
        result = subprocess.run(["cmake", "-S", str(source), "-B", str(self.base / "build")],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("downloading libmpv", result.stdout)

    def test_cli_reports_failure_without_a_result(self):
        output, error = io.StringIO(), io.StringIO()
        with patch.dict(os.environ, {}, clear=True), contextlib.redirect_stdout(output), contextlib.redirect_stderr(error):
            status = package.main(["consume", "--platform", "android"])
        self.assertEqual(status, 1)
        self.assertEqual(output.getvalue(), "")
        self.assertIn("requires", error.getvalue())


if __name__ == "__main__":
    unittest.main()
