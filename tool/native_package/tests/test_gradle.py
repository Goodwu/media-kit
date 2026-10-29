"""Run the real acquisition block on Gradle without requiring Android's SDK."""
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock
import zipfile


REPOSITORY = Path(__file__).resolve().parents[3]
PACKAGE = REPOSITORY / "tool/native_package/package.py"
SPEC = importlib.util.spec_from_file_location("gradle_native_package", PACKAGE)
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)
GRADLE = os.environ.get("MEDIA_KIT_TEST_GRADLE") or shutil.which("gradle")


def cleanup_gradle_temp(temporary, *, windows=None, sleep=time.sleep, attempts=10):
    """Bounded retry for transient Windows DLL sharing violations.

    Never suppress exhausted cleanup errors: a stuck worker must remain
    visible as a CI failure rather than silently leak a test fixture.
    """
    if windows is None:
        windows = os.name == "nt"
    if attempts < 1:
        raise ValueError("cleanup needs at least one attempt")
    for retry in range(attempts):
        try:
            temporary.cleanup()
            return
        except PermissionError:
            if not windows or retry + 1 == attempts:
                raise
            sleep(min((retry + 1) * 0.3, 1.5))


def stop_fixture_gradle(gradle, user_home):
    """Stop only daemons belonging to this test's isolated Gradle home."""
    result = subprocess.run(
        [gradle, "--stop", "--gradle-user-home", str(user_home)],
        cwd=user_home.parent,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=60,
    )
    if result.returncode:
        raise AssertionError("Unable to stop isolated test Gradle processes:\n" + result.stdout)


@contextmanager
def isolated_gradle_workspace(gradle):
    temporary = tempfile.TemporaryDirectory(prefix="media kit Gradle ")
    base = Path(temporary.name)
    try:
        yield base
    finally:
        stop_error = None
        try:
            gradle_home = base / "gradle cache"
            if gradle_home.is_dir():
                stop_fixture_gradle(gradle, gradle_home)
        except (OSError, subprocess.SubprocessError, AssertionError) as error:
            stop_error = error
        # Cleanup still runs if Gradle shutdown failed. A persistent sharing
        # violation is fatal, not a skipped test or ignored cleanup error.
        cleanup_gradle_temp(temporary)
        if stop_error is not None:
            raise stop_error


class GradleWorkspaceCleanupTests(unittest.TestCase):
    def test_transient_windows_dll_lock_is_retried(self):
        temporary = Mock()
        temporary.cleanup.side_effect = [PermissionError("locked DLL"), None]
        delays = []
        cleanup_gradle_temp(temporary, windows=True, sleep=delays.append, attempts=3)
        self.assertEqual(temporary.cleanup.call_count, 2)
        self.assertEqual(delays, [0.3])

    def test_persistent_windows_dll_lock_is_a_failure(self):
        temporary = Mock()
        temporary.cleanup.side_effect = PermissionError("locked DLL")
        with self.assertRaisesRegex(PermissionError, "locked DLL"):
            cleanup_gradle_temp(temporary, windows=True, sleep=lambda _: None, attempts=3)
        self.assertEqual(temporary.cleanup.call_count, 3)

    def test_non_windows_cleanup_error_is_not_hidden(self):
        temporary = Mock()
        temporary.cleanup.side_effect = PermissionError("unexpected cleanup failure")
        with self.assertRaisesRegex(PermissionError, "unexpected cleanup failure"):
            cleanup_gradle_temp(temporary, windows=False, sleep=lambda _: None, attempts=3)
        temporary.cleanup.assert_called_once()


@unittest.skipUnless(GRADLE, "Set MEDIA_KIT_TEST_GRADLE to run the actual Gradle configuration gate")
class GradleConfiguration(unittest.TestCase):
    def test_verified_package_and_failure_stderr_on_gradle(self):
        with isolated_gradle_workspace(GRADLE) as base:
            checkout = base / "media-kit"
            project = checkout / "libs/android/media_kit_libs_android_video/android"
            project.mkdir(parents=True)
            verifier = checkout / "tool/native_package/package.py"
            verifier.parent.mkdir(parents=True)
            shutil.copy2(PACKAGE, verifier)
            original = (REPOSITORY / "libs/android/media_kit_libs_android_video/android/build.gradle").read_text()
            # The entire production acquisition block runs unchanged. Only the
            # AGP declaration is replaced by Gradle's built-in base plugin.
            imports = "\n".join(line for line in original.splitlines() if line.startswith("import "))
            acquisition = original[original.index("// Acquisition runs during configuration"):]
            (project / "build.gradle").write_text(imports + "\napply plugin: 'base'\n" + acquisition)
            (project / "settings.gradle").write_text("rootProject.name = 'native-package-consumer'\n")
            root = base / "native package"
            root.mkdir()
            abis = ["arm64-v8a", "armeabi-v7a", "x86_64", "x86"]
            jars = {}
            for abi in abis:
                name = f"{abi}.jar"
                with zipfile.ZipFile(root / name, "w") as archive:
                    archive.writestr(f"lib/{abi}/libmpv.so", b"synthetic fixture")
                jars[abi] = name
            spec = base / "spec.json"
            spec.write_text(json.dumps({
                "platform": "android", "architectures": abis, "profile": "gradle-configuration-test",
                "identity": {"origin": "source", "sources": {
                    "mpv": {"repository": "https://github.com/example/mpv", "commit": "a" * 40}}},
                "layout": {"jars": jars}, "capabilities": [],
                "validation": {"compiled": False, "runtime": False, "device": False},
            }))
            created = package.create(root, spec)
            environment = {key: value for key, value in os.environ.items()
                           if not key.startswith("MEDIA_KIT_NATIVE_PACKAGE_")}
            environment.update({
                "MEDIA_KIT_NATIVE_PACKAGE_ROOT": str(root),
                "MEDIA_KIT_NATIVE_PACKAGE_MANIFEST": created["manifest"],
                "MEDIA_KIT_NATIVE_PACKAGE_MANIFEST_SHA256": created["manifest_sha256"],
                "MEDIA_KIT_NATIVE_PACKAGE_PYTHON": sys.executable,
            })
            command = [GRADLE, "--offline", "--no-daemon", "--no-watch-fs",
                       "--max-workers=1", "--console=plain",
                       "--gradle-user-home", str(base / "gradle cache"), "help"]
            valid = subprocess.run(command, cwd=project, env=environment, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            self.assertEqual(valid.returncode, 0, valid.stdout)
            output = project / "build/output"
            self.assertEqual({path.name for path in output.iterdir()}, {f"native-{abi}.jar" for abi in abis})
            for abi in abis:
                self.assertEqual(hashlib.sha256((output / f"native-{abi}.jar").read_bytes()).digest(),
                                 hashlib.sha256((root / jars[abi]).read_bytes()).digest())
            # The dev variant may consume an explicitly authenticated package.
            # Merely setting -Pdev must not force a fallback to a release JAR.
            dev_command = command + ["-Pdev=true"]
            verified_dev = subprocess.run(dev_command, cwd=project, env=environment, text=True,
                                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            self.assertEqual(verified_dev.returncode, 0, verified_dev.stdout)
            self.assertEqual({path.name for path in output.iterdir()},
                             {f"native-{abi}.jar" for abi in abis})
            environment["MEDIA_KIT_NATIVE_PACKAGE_MANIFEST_SHA256"] = "0" * 64
            invalid = subprocess.run(command, cwd=project, env=environment, text=True,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            self.assertNotEqual(invalid.returncode, 0, invalid.stdout)
            self.assertIn("Explicit Android native package verification failed (exit 1)", invalid.stdout)
            self.assertIn("Native package manifest SHA256 mismatch", invalid.stdout)
            self.assertEqual(list(output.iterdir()), [])

            # No explicit native input must fail closed before any release download.
            unconfigured = {key: value for key, value in environment.items()
                            if key not in {"MEDIA_KIT_NATIVE_PACKAGE_ROOT",
                                           "MEDIA_KIT_NATIVE_PACKAGE_MANIFEST",
                                           "MEDIA_KIT_NATIVE_PACKAGE_MANIFEST_SHA256"}}
            missing_dev = subprocess.run(dev_command, cwd=project, env=unconfigured, text=True,
                                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            self.assertNotEqual(missing_dev.returncode, 0, missing_dev.stdout)
            self.assertIn("dev builds require a verified native package or mediaKitLocalArm64Jar",
                          missing_dev.stdout)
            self.assertEqual(list(output.iterdir()), [])

            # Preserve compat's current-source local-JAR path for arm64 test APKs.
            local_jar = root / jars["arm64-v8a"]
            local_command = dev_command + ["-PmediaKitArm64Only=true",
                                           f"-PmediaKitLocalArm64Jar={local_jar}"]
            local_dev = subprocess.run(local_command, cwd=project, env=unconfigured, text=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            self.assertEqual(local_dev.returncode, 0, local_dev.stdout)
            self.assertEqual({path.name for path in output.iterdir()}, {"local-arm64-v8a.jar"})

            # CI's strict mutual exclusion still applies in dev builds.
            conflict = subprocess.run(local_command, cwd=project, env={
                **unconfigured,
                "MEDIA_KIT_NATIVE_PACKAGE_ROOT": str(root),
                "MEDIA_KIT_NATIVE_PACKAGE_MANIFEST": created["manifest"],
                "MEDIA_KIT_NATIVE_PACKAGE_MANIFEST_SHA256": created["manifest_sha256"],
            }, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            self.assertNotEqual(conflict.returncode, 0, conflict.stdout)
            self.assertIn("Do not combine a verified native package with mediaKitLocalArm64Jar",
                          conflict.stdout)
            self.assertEqual(list(output.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
