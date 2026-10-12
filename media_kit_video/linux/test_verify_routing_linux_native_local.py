import importlib.util
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("linux_preflight", HERE / "verify_routing_linux_native_local.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout.strip()


class TrustedPreflightTest(unittest.TestCase):
    def repo(self, root, files, remote="https://github.com/Goodwu/PiliPlusX.git"):
        root.mkdir()
        git(root, "init", "-b", gate.TASK_BRANCH)
        git(root, "config", "user.email", "test@example.invalid")
        git(root, "config", "user.name", "Test")
        git(root, "remote", "add", "origin", remote)
        for name, contents in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
        git(root, "add", "--all")
        git(root, "commit", "-m", "fixture")
        return git(root, "rev-parse", "HEAD")

    def test_rejects_wrong_expected_head_before_running_app_helper(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            marker = base / "executed"
            app = base / "app"
            app_sha = self.repo(app, {
                gate.APP_VERIFIER.as_posix(): f"from pathlib import Path\nPath({str(marker)!r}).touch()\n",
                gate.APP_LEDGER.as_posix(): '{"schemaVersion":1}\n',
            })
            media = base / "media"
            media_sha = self.repo(media, {"tracked.txt": "fixture\n"}, "https://github.com/Goodwu/media-kit.git")
            with self.assertRaisesRegex(gate.Reject, "expected consumer vector"):
                gate.preflight(app, media, "0" * 40, media_sha)
            self.assertFalse(marker.exists())
            self.assertEqual(git(app, "rev-parse", "HEAD"), app_sha)

    def test_rejects_untracked_or_modified_app_helper(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            app = base / "app"
            app_sha = self.repo(app, {
                gate.APP_VERIFIER.as_posix(): "# reviewed\n",
                gate.APP_LEDGER.as_posix(): "{}\n",
            })
            media = base / "media"
            media_sha = self.repo(media, {"tracked.txt": "fixture\n"}, "https://github.com/Goodwu/media-kit.git")
            (app / gate.APP_VERIFIER).write_text("# replaced\n")
            with self.assertRaisesRegex(gate.Reject, "dirty"):
                gate.preflight(app, media, app_sha, media_sha)

    def test_requires_canonical_remote_and_task_branch(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            app = base / "app"
            app_sha = self.repo(app, {
                gate.APP_VERIFIER.as_posix(): "# reviewed\n",
                gate.APP_LEDGER.as_posix(): "{}\n",
            })
            git(app, "remote", "set-url", "origin", "https://example.invalid/fake.git")
            media = base / "media"
            media_sha = self.repo(media, {"tracked.txt": "fixture\n"}, "https://github.com/Goodwu/media-kit.git")
            with self.assertRaisesRegex(gate.Reject, "canonical Goodwu remote"):
                gate.preflight(app, media, app_sha, media_sha)

    def test_modes_forward_exactly_one_app_verifier_operation(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            marker = base / "argv.json"
            app = base / "app"
            verifier = f"#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\nPath({str(marker)!r}).write_text(json.dumps(sys.argv[1:]))\n"
            app_sha = self.repo(app, {
                gate.APP_VERIFIER.as_posix(): verifier,
                gate.APP_LEDGER.as_posix(): '{"schemaVersion":1,"task":"MK-ROUTING-20261011","selectedManifestSha256":null,"entries":[]}\n',
            })
            media = base / "media"
            media_sha = self.repo(media, {"tracked.txt": "fixture\n"},
                                  "https://github.com/Goodwu/media-kit.git")
            root, receipt = base / "native", base / "receipt.json"
            readelf = base / "readelf"
            readelf.write_text("#!/bin/sh\nexit 0\n")
            readelf.chmod(0o755)
            common = ["--app-root", str(app), "--media-kit-root", str(media),
                      "--expected-app-sha", app_sha, "--expected-media-kit-sha", media_sha,
                      "--root", str(root), "--receipt", str(receipt), "--readelf", str(readelf)]
            for mode, expected in ((["--local-input", "--write-cmake", "-"], "--local-input"),
                                   (["--postbuild-plugin", str(base / "plugin.so")], "--verify-plugin"),
                                   (["--postbuild-bundle", str(base / "bundle")], "--verify-bundle")):
                marker.unlink(missing_ok=True)
                result = subprocess.run([sys.executable, str(HERE / "verify_routing_linux_native_local.py"),
                                         *common, *mode], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                forwarded = __import__("json").loads(marker.read_text())
                self.assertEqual(forwarded.count(expected), 1)
                self.assertEqual(sum(flag in forwarded for flag in
                                     ("--local-input", "--verify-plugin", "--verify-bundle")), 1)

    def test_rejects_wrong_branch_before_helper_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            marker = base / "executed"
            app = base / "app"
            app.mkdir()
            git(app, "init", "-b", "other")
            git(app, "config", "user.email", "test@example.invalid")
            git(app, "config", "user.name", "Test")
            git(app, "remote", "add", "origin", "https://github.com/Goodwu/PiliPlusX.git")
            for rel, content in ((gate.APP_VERIFIER, f"from pathlib import Path\nPath({str(marker)!r}).touch()\n"),
                                 (gate.APP_LEDGER, "{}\n")):
                path = app / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            git(app, "add", "--all")
            git(app, "commit", "-m", "fixture")
            app_sha = git(app, "rev-parse", "HEAD")
            media = base / "media"
            media_sha = self.repo(media, {"tracked.txt": "fixture\n"}, "https://github.com/Goodwu/media-kit.git")
            with self.assertRaisesRegex(gate.Reject, "branch mismatch"):
                gate.preflight(app, media, app_sha, media_sha)
            self.assertFalse(marker.exists())

    def test_routing_cmake_fails_closed_without_entering_legacy_download_lane(self):
        workspace = HERE.parents[2]
        app = workspace / "app"
        media = workspace / "media-kit"
        cmake = subprocess.run(["cmake", "--version"], capture_output=True, text=True)
        if cmake.returncode:
            self.skipTest("CMake unavailable")
        app_sha = subprocess.run(["git", "-C", str(app), "rev-parse", "HEAD"],
                                 check=True, capture_output=True, text=True).stdout.strip()
        media_sha = subprocess.run(["git", "-C", str(media), "rev-parse", "HEAD"],
                                   check=True, capture_output=True, text=True).stdout.strip()
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            native = base / "native"
            (native / "lib").mkdir(parents=True)
            (native / "include/mpv").mkdir(parents=True)
            receipt = base / "receipt.json"
            receipt.write_text("{}\n")
            result = subprocess.run([
                "cmake", "-S", str(HERE), "-B", str(base / "build"),
                "-DCMAKE_SYSTEM_NAME=Linux", "-DCMAKE_SYSTEM_PROCESSOR=x86_64",
                "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY", "-DCMAKE_CXX_COMPILER_WORKS=TRUE",
                f"-DROUTING_PYTHON3={sys.executable}", "-DROUTING_READELF=/usr/bin/true",
                "-DMEDIA_KIT_ROUTING_MODE=ON", "-DMEDIA_KIT_LIBS_AVAILABLE=ON",
                f"-DMEDIA_KIT_LINUX_NATIVE_ROOT={native}",
                f"-DMEDIA_KIT_LINUX_NATIVE_RECEIPT={receipt}",
                f"-DMEDIA_KIT_LINUX_NATIVE_APP_ROOT={app}",
                f"-DMEDIA_KIT_LINUX_NATIVE_APP_SHA={app_sha}",
                f"-DMEDIA_KIT_LINUX_NATIVE_MEDIA_KIT_SHA={media_sha}",
            ], capture_output=True, text=True, timeout=60)
            output = result.stdout + result.stderr
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("routing Linux native verification failed", output)
            self.assertNotIn("Downloading libmpv from", output)
            self.assertNotIn("https://github.com/Predidit/libmpv-linux-build", output)


if __name__ == "__main__":
    unittest.main()
