"""Run the real acquisition block on Gradle without requiring Android's SDK."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


REPOSITORY = Path(__file__).resolve().parents[3]
PACKAGE = REPOSITORY / "tool/native_package/package.py"
SPEC = importlib.util.spec_from_file_location("gradle_native_package", PACKAGE)
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)
GRADLE = os.environ.get("MEDIA_KIT_TEST_GRADLE") or shutil.which("gradle")


@unittest.skipUnless(GRADLE, "Set MEDIA_KIT_TEST_GRADLE to run the actual Gradle configuration gate")
class GradleConfiguration(unittest.TestCase):
    def test_verified_package_and_failure_stderr_on_gradle(self):
        with tempfile.TemporaryDirectory(prefix="media kit Gradle ") as temporary:
            base = Path(temporary)
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
            command = [GRADLE, "--offline", "--no-daemon", "--max-workers=1", "--console=plain",
                       "--gradle-user-home", str(base / "gradle cache"), "help"]
            valid = subprocess.run(command, cwd=project, env=environment, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            self.assertEqual(valid.returncode, 0, valid.stdout)
            output = project / "build/output"
            self.assertEqual({path.name for path in output.iterdir()}, {f"native-{abi}.jar" for abi in abis})
            for abi in abis:
                self.assertEqual(hashlib.sha256((output / f"native-{abi}.jar").read_bytes()).digest(),
                                 hashlib.sha256((root / jars[abi]).read_bytes()).digest())
            environment["MEDIA_KIT_NATIVE_PACKAGE_MANIFEST_SHA256"] = "0" * 64
            invalid = subprocess.run(command, cwd=project, env=environment, text=True,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            self.assertNotEqual(invalid.returncode, 0, invalid.stdout)
            self.assertIn("Explicit Android native package verification failed (exit 1)", invalid.stdout)
            self.assertIn("Native package manifest SHA256 mismatch", invalid.stdout)
            self.assertEqual(list(output.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
