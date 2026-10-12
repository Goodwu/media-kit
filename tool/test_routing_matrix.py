from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import zipfile

MODULE_PATH = Path(__file__).with_name("routing_matrix.py")
SPEC = importlib.util.spec_from_file_location("routing_matrix", MODULE_PATH)
matrix = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(matrix)


def probe(kind: str) -> dict:
    stream = {"codec_type": "video", "codec_name": "hevc", "profile": "Main 10",
        "width": 3840, "height": 2160, "pix_fmt": "yuv420p10le",
        "color_range": "tv", "color_space": "bt2020nc",
        "color_transfer": "smpte2084" if kind == "hdr10" else
            "arib-std-b67" if kind in ("hlg", "p84") else
            None if kind == "p5" else "unknown",
        "color_primaries": "bt2020", "side_data_list": []}
    if kind in ("p5", "p84"):
        stream["side_data_list"] = [{"side_data_type": "DOVI configuration record",
            "dv_profile": 5 if kind == "p5" else 8,
            "dv_bl_signal_compatibility_id": 0 if kind == "p5" else 4,
            "el_present_flag": 0, "rpu_present_flag": 1, "bl_present_flag": 1}]
    return {"streams": [stream], "format": {"format_name": "mov,mp4,m4a,3gp,3g2,mj2"}}


class RoutingMatrixTests(unittest.TestCase):
    def test_eight_rows_have_explicit_gate_and_experimental_values(self):
        fixtures = {kind: {"devicePath": f"/data/local/tmp/media-kit-{kind}-fixture.mp4"}
                    for kind in matrix.KINDS}
        rows = matrix.matrix_rows(fixtures)
        self.assertEqual(len(rows), 8)
        self.assertEqual([row["kind"] for row in rows],
            ["p5", "p5", "p84", "p84", "hdr10", "hdr10", "hlg", "hlg"])
        for row in rows:
            self.assertEqual(row["allowExperimental"], row["gateOpen"])
            self.assertFalse(row["hdrPolicyExperimental"])
            defines = row["defines"]
            self.assertEqual(len(defines), 4)
            self.assertIn(f"MEDIA_KIT_ANDROID_HDR_GATE_OPEN={'true' if row['gateOpen'] else 'false'}",
                          defines[2])
            self.assertEqual(defines[3], "--dart-define=MEDIA_KIT_ANDROID_HDR_POLICY_EXPERIMENTAL=false")
            self.assertNotIn("SURFACETEXTURE_POC", " ".join(defines))
            self.assertNotRegex(" ".join(defines), r"hwdec|--vo=|colorspace|colorprim|range=|YUV")

    def test_fixture_stream_semantics_are_derived_from_probe_data(self):
        for kind in matrix.KINDS:
            matrix.probe_projection(probe(kind), kind)
        bad = probe("p84")
        bad["streams"][0]["side_data_list"][0]["el_present_flag"] = 1
        with self.assertRaisesRegex(matrix.MatrixError, "profile/compatibility/EL"):
            matrix.probe_projection(bad, "p84")
        bad = probe("p5")
        bad["streams"][0]["side_data_list"][0]["dv_profile"] = 8
        with self.assertRaisesRegex(matrix.MatrixError, "profile/compatibility/EL"):
            matrix.probe_projection(bad, "p5")
        bad = probe("p84")
        bad["streams"][0]["color_transfer"] = "unknown"
        with self.assertRaisesRegex(matrix.MatrixError, "HLG-compatible"):
            matrix.probe_projection(bad, "p84")
        for kind in ("hdr10", "hlg"):
            bad = probe(kind)
            bad["streams"][0]["color_transfer"] = "bt709"
            with self.assertRaisesRegex(matrix.MatrixError, "transfer"):
                matrix.probe_projection(bad, kind)

    def test_real_p5_semantics_allow_absent_vui_but_reject_conflicts(self):
        actual = probe("p5")
        stream = actual["streams"][0]
        for key in ("color_range", "color_space", "color_transfer", "color_primaries"):
            stream.pop(key, None)
        actual["streams"].append({"codec_type": "audio", "codec_name": "eac3"})
        accepted = matrix.probe_projection(actual, "p5")
        self.assertIsNone(accepted["color_primaries"])
        self.assertEqual(accepted["dovi"]["dv_profile"], 5)
        conflict = probe("p5")
        conflict["streams"][0]["color_primaries"] = "bt709"
        with self.assertRaisesRegex(matrix.MatrixError, "contradictory color primaries"):
            matrix.probe_projection(conflict, "p5")
        actual_hash_not_in_source = "3e610d3b1b11e9b802da66d69bd97f6371a2b114ee464a7e8517fe31d706cc9f"
        self.assertNotIn(actual_hash_not_in_source,
                         matrix.known_fixture_kinds(matrix.ROOT / matrix.IDENTITY_SOURCE))

    def test_actual_ffprobe_command_is_run_and_sidecar_is_only_comparison(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ffprobe = root / "ffprobe"
            ffprobe.write_text("#!/bin/sh\nprintf '%s' \"$FAKE_PROBE\"\n", encoding="utf-8")
            ffprobe.chmod(0o755)
            spec = {"schemaVersion": 1, "fixtures": {}}
            fake_map = {}
            for kind in matrix.KINDS:
                media = root / f"fixture-{kind}.mp4"
                media.write_bytes(f"verified bytes {kind}".encode())
                digest = matrix.sha_file(media)
                evidence = root / f"{kind}-probe.json"
                expected_probe = probe(kind)
                evidence.write_text(json.dumps({"schemaVersion": 1,
                    "fixtureSha256": digest, "probe": expected_probe}), encoding="utf-8")
                spec["fixtures"][kind] = {"path": str(media), "sha256": digest,
                    "devicePath": f"/data/local/tmp/media-kit-{kind}-controlled.mp4",
                    "probeEvidence": str(evidence)}
                fake_map[digest] = kind
            fixture_file = root / "fixtures.json"
            fixture_file.write_text(json.dumps(spec), encoding="utf-8")
            sidecar_reads = {}
            # The fake executable selects output from the actual fixture bytes,
            # while the production runner executes and hashes its real output.
            probe_map_file = root / "probes.json"
            by_digest = {matrix.sha_file(root / f"fixture-{kind}.mp4"): probe(kind)
                         for kind in matrix.KINDS}
            probe_map_file.write_text(json.dumps(by_digest), encoding="utf-8")
            ffprobe.write_text(
                "#!/usr/bin/env python3\nimport hashlib,json,sys\n"
                f"data=json.load(open({str(probe_map_file)!r}))\n"
                "digest=hashlib.sha256(open(sys.argv[-1],'rb').read()).hexdigest()\n"
                "print(json.dumps(data[digest]))\n", encoding="utf-8")
            ffprobe.chmod(0o755)
            receipt = {"commands": []}
            with mock.patch.object(matrix, "known_fixture_kinds", return_value=fake_map):
                result = matrix.validate_fixtures(fixture_file, ffprobe, receipt, os.environ.copy())
            self.assertEqual(set(result), set(matrix.KINDS))
            self.assertEqual(len(receipt["commands"]), 4)
            for kind, item in result.items():
                self.assertTrue(item["localContentVerified"])
                self.assertFalse(item["deviceFixtureVerified"])
                self.assertEqual(item["probeCommand"][0], str(ffprobe))
                self.assertEqual(len(item["probeStdoutSha256"]), 64)

    def test_sidecar_claim_conflict_rejects_before_build(self):
        bad = probe("p5")
        bad["streams"][0]["side_data_list"][0]["el_present_flag"] = 1
        with self.assertRaisesRegex(matrix.MatrixError, "profile/compatibility/EL"):
            matrix.probe_projection(bad, "p5")

    def test_lab_package_config_must_resolve_every_media_kit_root_locally(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "copy"
            cache = root / "cache"
            sdk = root / "sdk"
            config_dir = source / "lab/.dart_tool"
            config_dir.mkdir(parents=True)
            cache.mkdir(); sdk.mkdir()
            package_map = {
                "media_kit_hdr_lab": "media_kit_hdr_lab",
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
            packages = []
            for name, relative in package_map.items():
                path = source / relative
                path.mkdir(parents=True)
                packages.append({"name": name, "rootUri": path.as_uri(), "packageUri": "lib/"})
            (source / "media_kit_hdr_lab/pubspec.yaml").write_text(
                "name: media_kit_hdr_lab\n", encoding="utf-8")
            external = cache / "hosted/pub.dev/path-1.9.0"
            external.mkdir(parents=True)
            packages.append({"name": "path", "rootUri": external.as_uri(), "packageUri": "lib/"})
            config = config_dir / "package_config.json"
            config.write_text(json.dumps({"configVersion": 2, "packages": packages}), encoding="utf-8")
            roots = matrix.verify_lab_package_roots(config, source, cache, sdk)
            self.assertEqual(roots["media_kit_video"], str((source / "media_kit_video").resolve()))
            self.assertEqual(roots["media_kit_hdr_lab"], str((source / "media_kit_hdr_lab").resolve()))
            lab = source / "media_kit_hdr_lab"
            (lab / "pubspec.lock").write_text("packages: {}\n", encoding="utf-8")
            resource = lab / "assets/resource.json"
            resource.parent.mkdir(); resource.write_text('{"value":1}\n')
            before = matrix.lab_build_input_state(config, source, cache, sdk)
            resource.write_text('{"value":2}\n')
            after = matrix.lab_build_input_state(config, source, cache, sdk)
            self.assertNotEqual(before["sourceTreeSha256"], after["sourceTreeSha256"])
            self.assertNotEqual(before["resolvedPackageSources"], after["resolvedPackageSources"])
            next(item for item in packages if item["name"] == "media_kit_video")["rootUri"] = external.as_uri()
            config.write_text(json.dumps({"configVersion": 2, "packages": packages}), encoding="utf-8")
            with self.assertRaisesRegex(matrix.MatrixError, "escaped the isolated media-kit"):
                matrix.verify_lab_package_roots(config, source, cache, sdk)
            next(item for item in packages if item["name"] == "media_kit_video")["rootUri"] = (
                source / "media_kit_video").as_uri()
            packages[-1] = {"name": "media_kit_unreviewed", "rootUri": str(source.as_uri()),
                             "packageUri": "lib/"}
            config.write_text(json.dumps({"configVersion": 2, "packages": packages}), encoding="utf-8")
            with self.assertRaisesRegex(matrix.MatrixError, "escaped the isolated media-kit"):
                matrix.verify_lab_package_roots(config, source, cache, sdk)

    def test_native_jar_manifest_and_ledger_changes_fail_freshness(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            jar, manifest, ledger = (root / name for name in ("native.jar", "manifest.json", "ledger.json"))
            jar.write_bytes(b"accepted jar")
            manifest.write_bytes(b"accepted manifest")
            ledger.write_bytes(b"accepted ledger")
            baseline = matrix.native_fingerprints(jar, manifest, ledger)
            matrix.assert_native_fingerprints(jar, manifest, ledger, baseline)
            jar.write_bytes(b"replaced jar")
            with self.assertRaisesRegex(matrix.MatrixError, "changed during matrix"):
                matrix.assert_native_fingerprints(jar, manifest, ledger, baseline)

    def test_apk_native_members_are_exactly_the_three_arm64_members(self):
        with tempfile.TemporaryDirectory() as temporary:
            apk = Path(temporary) / "test.apk"
            lab = Path(temporary) / "lab"
            (lab / "android/app/src/main/cpp").mkdir(parents=True)
            (lab / "android/app/src/main/cpp/CMakeLists.txt").write_text(
                "add_library(media_kit_p5_probe SHARED probe.cpp)\n")
            expected = set(matrix.expected_native_member_sources(
                set(matrix.APPROVED_JAR_MEMBERS), lab, {"media_kit_hdr_lab": str(lab)}))
            with zipfile.ZipFile(apk, "w") as archive:
                for name in expected:
                    archive.writestr(name, name.encode())
            self.assertEqual(set(matrix.exact_native_members(apk, expected)), expected)
            with zipfile.ZipFile(apk, "a") as archive:
                archive.writestr("lib/arm64-v8a/libunreviewed.so", b"unknown member")
                archive.writestr("lib/x86_64/libmpv.so", b"foreign ABI")
            with self.assertRaisesRegex(matrix.MatrixError, "native ABI/member set"):
                matrix.exact_native_members(apk, expected)

    def test_full_native_member_sources_and_elf_are_verified(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            apk, jar = root / "row.apk", root / "accepted.jar"
            sdk = root / "flutter"
            flutter_engine = sdk / "bin/cache/artifacts/engine/android-arm64-release/libflutter.so"
            flutter_engine.parent.mkdir(parents=True)
            lab = root / "row-source/media_kit_hdr_lab"
            cmake = lab / "android/app/src/main/cpp"
            cmake.mkdir(parents=True)
            (cmake / "CMakeLists.txt").write_text(
                "add_library(media_kit_p5_probe SHARED p5_codec_probe.cpp)\n")
            (cmake / "p5_codec_probe.cpp").write_text("int probe() { return 1; }\n")
            (lab / "android/app/build.gradle.kts").write_text("android { externalNativeBuild { cmake { path = file(\"src/main/cpp/CMakeLists.txt\") } } }\n")
            (lab / "android/build.gradle.kts").write_text((matrix.ROOT / "media_kit_hdr_lab/android/build.gradle.kts").read_text())
            app_output = lab / "build/app/intermediates/flutter/release/arm64-v8a/app.so"
            app_output.parent.mkdir(parents=True)
            app_output.write_bytes(b"AOT bytes")
            probe_output = lab / "build/app/intermediates/cxx/Release/obj/arm64-v8a/libmedia_kit_p5_probe.so"
            probe_output.parent.mkdir(parents=True)
            probe_output.write_bytes(b"CMake bytes")
            jar_bytes = {name: f"accepted:{name}".encode()
                for name in matrix.APPROVED_JAR_MEMBERS}
            other = {
                "lib/arm64-v8a/libflutter.so": b"Flutter engine bytes",
                "lib/arm64-v8a/libapp.so": app_output.read_bytes(),
                "lib/arm64-v8a/libmedia_kit_p5_probe.so": probe_output.read_bytes(),
            }
            flutter_engine.write_bytes(other["lib/arm64-v8a/libflutter.so"])
            with zipfile.ZipFile(jar, "w") as archive:
                for name, data in jar_bytes.items(): archive.writestr(name, data)
            with zipfile.ZipFile(apk, "w") as archive:
                for name, data in {**jar_bytes, **other}.items(): archive.writestr(name, data)
            readelf = root / "llvm-readelf"
            readelf.write_text("#!/bin/sh\ncat <<'EOF'\nELF Header:\n  Class: ELF64\n  Type: DYN (Shared object file)\n  Machine: AArch64\nEOF\n")
            readelf.chmod(0o755)
            receipt_dir = root / "receipt"; receipt_dir.mkdir()
            commands = []
            vendor = root / "row-source/libs/android/media_kit_android_dataspace_vendor"
            vendor_source = matrix.ROOT / "libs/android/media_kit_android_dataspace_vendor/android"
            shutil.copytree(vendor_source, vendor / "android")
            vendor_output = lab / "build/media_kit_android_dataspace_vendor/intermediates/cxx/Release/obj/arm64-v8a/libmedia_kit_dataspace_vendor.so"
            vendor_output.parent.mkdir(parents=True)
            vendor_output.write_bytes(b"vendor native bytes")
            with zipfile.ZipFile(apk, "a") as archive:
                archive.writestr("lib/arm64-v8a/libmedia_kit_dataspace_vendor.so", vendor_output.read_bytes())
            package_roots = {"media_kit_hdr_lab": str(lab), "media_kit_android_dataspace_vendor": str(vendor)}
            self.assertEqual(matrix._android_module_root(vendor / "android/src/main/cpp/CMakeLists.txt"), (vendor / "android").resolve())
            provenance = matrix.verify_native_provenance(apk, jar, sdk, lab, receipt_dir,
                readelf, os.environ.copy(), commands, package_roots)
            producers = {name: item["producer"]["kind"]
                         for name, item in provenance["nativeMembers"].items()}
            self.assertEqual(len(provenance["nativeMembers"]), 7)
            self.assertEqual(producers["lib/arm64-v8a/libmpv.so"], "accepted-native-jar")
            self.assertEqual(producers["lib/arm64-v8a/libflutter.so"], "private-flutter-sdk-engine")
            self.assertEqual(producers["lib/arm64-v8a/libapp.so"], "current-isolated-flutter-aot-output")
            self.assertEqual(producers["lib/arm64-v8a/libmedia_kit_p5_probe.so"],
                             "cmake-shared-target")
            self.assertEqual(len(commands), 7)
            self.assertTrue(all(item["elf"]["class"] == "ELF64" for item in provenance["nativeMembers"].values()))
            flutter_engine.write_bytes(b"changed SDK engine source")
            changed_dir = root / "changed"; changed_dir.mkdir()
            with self.assertRaisesRegex(matrix.MatrixError, "private Flutter SDK engine"):
                matrix.verify_native_provenance(apk, jar, sdk, lab, changed_dir,
                    readelf, os.environ.copy(), [], package_roots)

    def test_command_failure_records_exit_code_and_prevents_following_step(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            failing = root / "fail"
            failing.write_text("#!/bin/sh\necho failed >&2\nexit 23\n", encoding="utf-8")
            failing.chmod(0o755)
            commands = []
            after = []
            with self.assertRaisesRegex(matrix.MatrixError, r"failed \(23\)"):
                matrix.run([str(failing)], cwd=root, env=os.environ.copy(),
                           log=root / "build.log", receipt=commands)
                after.append("must not run")
            self.assertEqual(commands[0]["exitCode"], 23)
            self.assertTrue((root / "build.log").is_file())
            self.assertEqual(after, [])

    def test_old_row_apk_is_rejected_before_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            apk = Path(temporary) / "app-release.apk"
            apk.write_bytes(b"old APK must not be consumed")
            with self.assertRaisesRegex(matrix.MatrixError, "old APK before build"):
                matrix.require_fresh_apk_path(apk)

    def test_apksigner_failure_or_missing_certificate_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            apk = root / "row.apk"; apk.write_bytes(b"apk")
            failed = root / "failed-apksigner"
            failed.write_text("#!/bin/sh\necho invalid >&2\nexit 1\n", encoding="utf-8")
            failed.chmod(0o755)
            commands = []
            with self.assertRaisesRegex(matrix.MatrixError, r"command failed \(1\)"):
                matrix.signer_certificate(failed, apk, os.environ.copy(), commands)
            self.assertEqual(commands[0]["exitCode"], 1)
            missing = root / "missing-certificate-apksigner"
            missing.write_text("#!/bin/sh\necho 'Verified using v2 scheme'\n", encoding="utf-8")
            missing.chmod(0o755)
            with self.assertRaisesRegex(matrix.MatrixError, "no signer certificate digest"):
                matrix.signer_certificate(missing, apk, os.environ.copy(), [])

    def test_nonempty_output_receipt_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "output"
            output.mkdir()
            old_receipt = output / "matrix-receipt.json"
            old_receipt.write_text('{"status":"passed","rows":["old"]}\n')
            args = type("Args", (), {"output": output})()
            original = old_receipt.read_bytes()
            with mock.patch.object(matrix, "parser") as parser_mock, \
                 mock.patch.object(matrix, "run_matrix", side_effect=matrix.MatrixError("must fail")):
                parser_mock.return_value.parse_args.return_value = args
                self.assertEqual(matrix.main([]), 1)
            self.assertEqual(old_receipt.read_bytes(), original)

    def test_empty_fixed_ledger_acquirer_failure_stops_before_flutter(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "app"
            media = root / "media"
            lab = media / "media_kit_hdr_lab"
            output = root / "output"
            sdk = root / "private/sdk/flutter"
            java = root / "java"
            android = root / "android-sdk"
            bootstrap = root / "bootstrap"
            for path in (app / "scripts", app / "docs/plans", lab / "android",
                         output, sdk / "bin", java, android / "build-tools/1",
                         android / "ndk/1", bootstrap):
                path.mkdir(parents=True, exist_ok=True)
            (bootstrap / "bootstrap.json").write_text(json.dumps({"flutterRoot": str(sdk)}))
            (app / "scripts/verify_routing_native_inputs.py").write_text("# verifier\n")
            ledger = app / "docs/plans/routing-native-accepted-inputs.json"
            ledger.write_text(json.dumps({"schemaVersion": 1, "task": "MK-ROUTING-20261011",
                "selectedManifestSha256": None, "entries": []}))
            flutter_calls = root / "flutter-calls"
            flutter = sdk / "bin/flutter"
            flutter.write_text(f"#!/bin/sh\necho called >> {flutter_calls}\nexit 0\n")
            flutter.chmod(0o755)
            acquire = app / "scripts/acquire_routing_native_inputs.py"
            acquire.write_text(
                "import json,sys\nfrom pathlib import Path\n"
                "args=sys.argv\nreceipt=Path(args[args.index('--receipt')+1])\n"
                "ledger=Path(__file__).parents[1]/'docs/plans/routing-native-accepted-inputs.json'\n"
                "value=json.loads(ledger.read_text())\n"
                "receipt.write_text(json.dumps({'status':'failed','stage':'selection',"
                "'nativeVerified':False,'deviceVerified':False,"
                "'reason':'missing-accepted-native-input: explicit selected manifest is empty'}))\n"
                "sys.exit(1 if not value.get('entries') or not value.get('selectedManifestSha256') else 2)\n")
            (lab / "android/gradle.properties").write_text("mediaKitArm64Only=true\n")
            fake = root / "tool"
            fake.write_text("#!/bin/sh\nexit 0\n")
            fake.chmod(0o755)
            args = type("Args", (), {})()
            args.app_root, args.output, args.flutter = app, output, flutter
            args.java_home, args.android_sdk = java, android
            args.readelf = args.nm = args.apksigner = args.ffprobe = fake
            args.fixtures = root / "fixtures.json"
            args.fixtures.write_text("{}")
            args.bootstrap_dir = bootstrap
            app_id = {"root": str(app), "head": "a" * 40, "tree": "b" * 40,
                      "status": "clean"}
            media_id = {"root": str(media), "head": "c" * 40, "tree": "d" * 40,
                        "status": "clean"}
            sdk_id = {"root": str(sdk), "head": "e" * 40, "tree": "f" * 40,
                      "trackedPatchSha256": "1" * 64, "trackedPatchBytes": 0,
                      "untrackedPaths": [], "flutterExecutable": str(flutter)}
            with mock.patch.object(matrix, "ROOT", media), \
                 mock.patch.object(matrix, "LAB", lab), \
                 mock.patch.object(matrix, "source_identity", side_effect=lambda _, label: app_id if label == "App" else media_id), \
                 mock.patch.object(matrix, "sdk_identity", return_value=sdk_id), \
                 mock.patch.object(matrix, "toolchain_identity", return_value={}), \
                 mock.patch.object(matrix, "verify_source_packages", return_value={"verified": True}), \
                 mock.patch.object(matrix, "finalize_bootstrap", return_value={"sdkRoot": str(sdk)}), \
                 mock.patch.object(matrix, "validate_fixtures", return_value={kind: {} for kind in matrix.KINDS}):
                with self.assertRaisesRegex(matrix.MatrixError, r"command failed \(1\)"):
                    matrix.run_matrix(args)
            receipt = json.loads((output / "matrix-receipt.json").read_text())
            self.assertEqual(receipt["nativeAcquisition"]["stage"], "selection")
            self.assertFalse(receipt["rows"])
            self.assertFalse(flutter_calls.exists(), "no Flutter version/build command may run after empty-ledger refusal")

    def test_successful_runner_preserves_eight_row_command_order_and_receipts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app, media, lab = root / "app", root / "media", root / "media/lab"
            output, sdk = root / "output", root / "private/sdk/flutter"
            bootstrap, java, android = root / "bootstrap", root / "java", root / "android-sdk"
            for path in (app / "scripts", app / "docs/plans", lab / "android/app",
                         output, sdk / "bin", java, android, bootstrap):
                path.mkdir(parents=True, exist_ok=True)
            ledger = app / "docs/plans/routing-native-accepted-inputs.json"
            ledger.write_text(json.dumps({"schemaVersion": 1, "task": "MK-ROUTING-20261011",
                "selectedManifestSha256": "a" * 64, "entries": [{"accepted": True}]}))
            gate = app / matrix.APP_GATE
            gate.parent.mkdir(parents=True, exist_ok=True); gate.write_text("# gate\n")
            acquirer = app / matrix.APP_ACQUIRE
            acquirer.parent.mkdir(parents=True, exist_ok=True); acquirer.write_text("# acquire\n")
            (bootstrap / "bootstrap.json").write_text(json.dumps({"flutterRoot": str(sdk)}))
            (lab / "android/gradle.properties").write_text("mediaKitArm64Only=true\n")
            (lab / "android/app/build.gradle.kts").write_text(
                'signingConfig = signingConfigs.getByName("debug")\n')
            flutter = sdk / "bin/flutter"
            flutter.write_text("#!/bin/sh\nexit 0\n"); flutter.chmod(0o755)
            tool = root / "tool"
            tool.write_text("#!/bin/sh\nexit 0\n"); tool.chmod(0o755)
            fixture_spec = root / "fixtures.json"; fixture_spec.write_text("{}")
            args = type("Args", (), {})()
            args.app_root, args.output, args.flutter = app, output, flutter
            args.java_home, args.android_sdk = java, android
            args.readelf = args.nm = args.apksigner = args.ffprobe = tool
            args.fixtures, args.bootstrap_dir = fixture_spec, bootstrap
            app_id = {"root": str(app), "head": "a" * 40, "tree": "b" * 40, "status": "clean"}
            media_id = {"root": str(media), "head": "c" * 40, "tree": "d" * 40, "status": "clean"}
            sdk_id = {"root": str(sdk), "head": "e" * 40, "tree": "f" * 40,
                      "trackedPatchSha256": "1" * 64, "trackedPatchBytes": 0,
                      "untrackedPaths": [], "flutterExecutable": str(flutter)}
            events = []

            def fake_run(argv, *, cwd, env, log=None, receipt=None):
                args_list = list(argv)
                if any(str(acquirer) in item for item in args_list):
                    events.append("acquire")
                    native = output / "native-input"; native.mkdir()
                    jar, manifest, evidence = native / "input.jar", native / "manifest.json", native / "evidence"
                    jar.write_bytes(b"accepted arm64 input")
                    manifest.write_text(json.dumps({"members": {
                        name: {} for name in matrix.APPROVED_JAR_MEMBERS}}))
                    evidence.mkdir()
                    receipt_path = Path(args_list[args_list.index("--receipt") + 1])
                    receipt_path.write_text(json.dumps({"status": "passed", "nativeVerified": True,
                        "deviceVerified": False, "jar": str(jar), "manifest": str(manifest),
                        "evidenceRoot": str(evidence)}))
                    stdout = b""
                elif args_list[1:3] == ["--version", "--machine"]:
                    events.append("version")
                    stdout = b'{"frameworkVersion":"test"}'
                elif len(args_list) > 1 and args_list[1:3] == ["build", "apk"]:
                    events.append("build")
                    self.assertNotIn("--build-dir", args_list)
                    self.assertIn("--no-pub", args_list)
                    apk = Path(cwd) / "build/app/outputs/flutter-apk/app-release.apk"
                    apk.parent.mkdir(parents=True)
                    with zipfile.ZipFile(apk, "w") as archive:
                        expected = matrix.expected_native_member_sources(
                            set(matrix.APPROVED_JAR_MEMBERS), Path(cwd),
                            {"media_kit_hdr_lab": str(cwd)})
                        for name in expected:
                            archive.writestr(name, name.encode())
                    stdout = b""
                elif any(item.endswith(matrix.APP_GATE) for item in args_list):
                    events.append("gate")
                    gate_receipt = Path(args_list[args_list.index("--receipt") + 1])
                    gate_receipt.write_text(json.dumps({"status": "passed",
                        "nativeVerified": True, "deviceVerified": False}))
                    stdout = b""
                elif Path(args_list[0]).name == tool.name and "verify" in args_list:
                    events.append("signer")
                    stdout = b"Signer #1 certificate SHA-256 digest: " + b"a" * 64
                else:
                    raise AssertionError(f"unexpected command: {args_list}")
                if log:
                    Path(log).write_bytes(stdout)
                if receipt is not None:
                    receipt.append({"argv": args_list, "cwd": str(cwd), "exitCode": 0,
                        "stdoutSha256": matrix.sha_bytes(stdout),
                        "stderrSha256": matrix.sha_bytes(b"")})
                return __import__("subprocess").CompletedProcess(args_list, 0, stdout, b"")

            fixtures = {kind: {"sha256": str(index) * 64, "devicePath": f"/data/local/tmp/media-kit-{kind}-fixture.mp4",
                "localContentVerified": True, "deviceFixtureVerified": False}
                for index, kind in enumerate(matrix.KINDS, 1)}
            build_input_state = {"packageConfigSha256": "2" * 64,
                "pubspecSha256": "3" * 64, "pubspecLockSha256": "4" * 64,
                "sourceTreeSha256": "5" * 64, "resolvedPackageSources": {}}
            lab_record = {"packageRoots": {"media_kit": str(media)},
                "buildInputState": build_input_state, "localCheckoutModified": False}

            source_copy = root / "source-copy"
            source_copy.mkdir()
            source_record = {"sourceArchive": {"head": media_id["head"]}}

            def fake_prepare_source(_media, _output, _identity, env, _receipt):
                events.append("archive")
                pub_cache = output / "pub-cache"
                pub_cache.mkdir()
                env["PUB_CACHE"] = str(pub_cache)
                return source_copy, source_record

            def fake_prepare_row(_source, row_dir, tag, *_args):
                events.append("pubget")
                row_lab = row_dir / "source-copy/media_kit_hdr_lab"
                (row_lab / "android/app/src/main/cpp").mkdir(parents=True)
                (row_lab / "android/app/build.gradle.kts").write_text("android { externalNativeBuild { cmake { path = file(\"src/main/cpp/CMakeLists.txt\") } } }\n")
                (row_lab / "android/app/src/main/cpp/CMakeLists.txt").write_text(
                    "add_library(media_kit_p5_probe SHARED probe.cpp)\n")
                return row_lab, {**lab_record, "rowTag": tag, "inputContext": {}, "trackedInputs": {}}

            def fake_native_provenance(*_args):
                return {"verified": "mocked provenance"}

            with mock.patch.object(matrix, "ROOT", media), \
                 mock.patch.object(matrix, "LAB", lab), \
                 mock.patch.object(matrix, "source_identity", side_effect=lambda _, label: app_id if label == "App" else media_id), \
                 mock.patch.object(matrix, "sdk_identity", return_value=sdk_id), \
                 mock.patch.object(matrix, "toolchain_identity", return_value={"tools": True}), \
                 mock.patch.object(matrix, "verify_source_packages", return_value={"verified": True}), \
                 mock.patch.object(matrix, "finalize_bootstrap", return_value={"sourceVector": True}), \
                 mock.patch.object(matrix, "validate_fixtures", return_value=fixtures), \
                 mock.patch.object(matrix, "android_precache", return_value=sdk_id), \
                 mock.patch.object(matrix, "load_app_variant_helper") as helper_mock, \
                 mock.patch.object(matrix, "check_parser_identity"), \
                 mock.patch.object(matrix, "verify_tracked_source_copy"), \
                 mock.patch.object(matrix, "prepare_isolated_source", side_effect=fake_prepare_source), \
                 mock.patch.object(matrix, "prepare_isolated_lab_row", side_effect=fake_prepare_row), \
                 mock.patch.object(matrix, "lab_build_input_state", return_value=build_input_state), \
                 mock.patch.object(matrix, "verify_native_provenance", side_effect=fake_native_provenance), \
                 mock.patch.object(matrix, "_check_fresh_sources"), \
                 mock.patch.object(matrix, "run", side_effect=fake_run):
                helper_mock.return_value.manifest_identity.return_value = {}
                (app / "android/tool").mkdir(parents=True)
                (app / "android/tool/parse_routing_manifest.dart").write_text("// mocked parser")
                (bootstrap / "bootstrap.json").write_text(json.dumps({"flutterRoot": str(sdk), "pubCache": str(output)}))
                receipt = matrix.run_matrix(args)

            expected = ["acquire", "version", "archive"]
            for _ in range(8):
                expected.extend(("pubget", "build", "gate", "signer"))
            self.assertEqual(events, expected)
            self.assertEqual(receipt["status"], "passed")
            disk_receipt = json.loads((output / "matrix-receipt.json").read_text())
            self.assertEqual(disk_receipt["status"], "passed")
            self.assertTrue(disk_receipt["nativeVerified"])
            self.assertEqual(len(receipt["rows"]), 8)
            for row in receipt["rows"]:
                self.assertEqual(row["status"], "passed")
                self.assertEqual(row["consumerKind"], "media_kit_hdr_lab")
                self.assertEqual(row["nativeTools"], {"tools": True})
                self.assertEqual(row["fullDefines"], row["defines"])
                self.assertEqual(row["signer"]["certificateSha256"], ["a" * 64])
                self.assertEqual(row["nativeProvenance"], {"verified": "mocked provenance"})

    def test_exact_git_archive_input_cannot_be_recaptured_after_pubget(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, row = root / "source", root / "row"
            (source / "media_kit_hdr_lab/lib").mkdir(parents=True)
            (source / "media_kit_hdr_lab/lib/main.dart").write_text("exact source")
            subprocess.run(["git", "init", "-q", str(source)], check=True)
            subprocess.run(["git", "add", "."], cwd=source, check=True)
            subprocess.run(["git", "-c", "user.name=test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture"], cwd=source, check=True)
            head = matrix.git(source, "rev-parse", "HEAD")
            tracked = matrix.tracked_source_manifest(source, head)
            matrix.verify_tracked_source_copy(source, tracked, "fixture")
            row.mkdir()
            record = {"trackedInputs": tracked, "sourceTreeSha256": matrix.sha_bytes(json.dumps(matrix.source_tree_snapshot(source / "media_kit_hdr_lab"), sort_keys=True).encode())}
            # Copy only actual archived files, never Git metadata.
            archive = root / "archive"
            matrix.safe_git_archive(source, archive, head)
            record["sourceTreeSha256"] = matrix.sha_bytes(json.dumps(matrix.source_tree_snapshot(archive), sort_keys=True).encode())
            def mutate(_argv, **kwargs):
                (kwargs["cwd"] / "lib/main.dart").write_text("mutated during pubget")
            with mock.patch.object(matrix, "run", side_effect=mutate):
                with self.assertRaisesRegex(matrix.MatrixError, "modified exact tracked source"):
                    matrix.prepare_isolated_lab_row(archive, row, "test", root / "sdk/bin/flutter", {"PUB_CACHE": str(root)}, {"labSource": record})
            changed = row / "source-copy/media_kit_hdr_lab/lib/main.dart"
            changed.write_text("exact source"); changed.chmod(0o755)
            with self.assertRaisesRegex(matrix.MatrixError, "file mode"):
                matrix.verify_tracked_source_copy(row / "source-copy", tracked, "mode mutation")
            changed.unlink()
            with self.assertRaisesRegex(matrix.MatrixError, "lost tracked source"):
                matrix.verify_tracked_source_copy(row / "source-copy", tracked, "missing source")

    def test_asset_build_nested_name_is_input_and_plugin_links_are_exact(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            lab, plugin = root / "source/media_kit_hdr_lab", root / "cache/plugin"
            (lab / "assets/build").mkdir(parents=True); plugin.mkdir(parents=True)
            asset = lab / "assets/build/font.ttf"; asset.write_bytes(b"original font")
            context = {"outputRoots": ["build", ".dart_tool/flutter_build"], "pubGenerated": [],
                "links": {"linux/flutter/ephemeral/.plugin_symlinks/plugin": str(plugin.resolve())},
                "resources": [{"path": "assets/build/", "directory": True}]}
            link = lab / "linux/flutter/ephemeral/.plugin_symlinks/plugin"
            link.parent.mkdir(parents=True); link.symlink_to(plugin, target_is_directory=True)
            roots = {"media_kit_hdr_lab": str(lab), "plugin": str(plugin)}
            before = matrix.lab_source_snapshot(lab.parent, roots, context)
            asset.write_bytes(b"changed font")
            after = matrix.lab_source_snapshot(lab.parent, roots, context)
            self.assertNotEqual(before, after)
            generated = lab / "android/app/.cxx/Release/output.o"
            generated.parent.mkdir(parents=True); generated.write_bytes(b"output")
            self.assertNotIn("media_kit_hdr_lab/android/app/.cxx/Release/output.o", matrix.lab_source_snapshot(lab.parent, roots, context))
            link.unlink(); link.symlink_to(root, target_is_directory=True)
            with self.assertRaisesRegex(matrix.MatrixError, "unapproved symlink"):
                matrix.lab_source_snapshot(lab.parent, roots, context)

    def test_pubget_unknown_addition_and_stale_output_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            lab = source / "media_kit_hdr_lab"; lab.mkdir()
            (lab / "pubspec.yaml").write_text("name: media_kit_hdr_lab")
            tracked = {"media_kit_hdr_lab/pubspec.yaml": {}}
            roots = {"media_kit_hdr_lab": str(lab)}
            context = {"outputRoots": ["build"], "pubGenerated": [], "links": {}, "resources": []}
            matrix.verify_pubget_source_set(source, roots, context, tracked)
            unknown = lab / "unexpected.dart"; unknown.write_text("injected")
            with self.assertRaisesRegex(matrix.MatrixError, "unknown source inputs"):
                matrix.verify_pubget_source_set(source, roots, context, tracked)
            unknown.unlink()
            (lab / "build").mkdir(); (lab / "build/old.so").write_bytes(b"old")
            with self.assertRaisesRegex(matrix.MatrixError, "output present before"):
                matrix.verify_pubget_source_set(source, roots, context, tracked)

    def test_ignored_sdk_engine_cache_bytes_and_modes_are_frozen(self):
        with tempfile.TemporaryDirectory() as temporary:
            sdk = Path(temporary)
            engine = sdk / "bin/cache/artifacts/engine/android-arm64-release/libflutter.so"
            engine.parent.mkdir(parents=True); engine.write_bytes(b"frozen engine")
            (sdk / "bin/internal").mkdir(); (sdk / "bin/internal/engine.version").write_text("a" * 40)
            before = matrix.sdk_engine_inputs(sdk)
            engine.write_bytes(b"different engine")
            self.assertNotEqual(matrix.sdk_engine_inputs(sdk), before)
            engine.write_bytes(b"frozen engine"); engine.chmod(0o755)
            self.assertNotEqual(matrix.sdk_engine_inputs(sdk), before)

    def test_sdk_internal_engine_directory_links_freeze_target_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            sdk = Path(temporary)
            actual = sdk / "bin/cache/private-engine"
            actual.mkdir(parents=True)
            engine = actual / "libflutter.so"; engine.write_bytes(b"original")
            aliases = sdk / "bin/cache/artifacts/engine"; aliases.mkdir(parents=True)
            alias = aliases / "android-arm64-release"
            alias.symlink_to(actual, target_is_directory=True)
            frozen = matrix.sdk_engine_inputs(sdk)
            key = "bin/cache/artifacts/engine/android-arm64-release/libflutter.so"
            self.assertEqual(frozen[key]["sha256"], matrix.sha_file(engine))
            self.assertIn("link", frozen["bin/cache/artifacts/engine/android-arm64-release"])
            engine.write_bytes(b"changed target")
            self.assertNotEqual(matrix.sdk_engine_inputs(sdk), frozen)
            # Linked parent directories also carry identity and target bytes.
            engine.write_bytes(b"original")
            parent_alias = sdk / "bin/artifact-cache"
            parent_alias.symlink_to(sdk / "bin/cache", target_is_directory=True)
            parent = matrix.bound_input_snapshot(sdk, ["bin/artifact-cache/private-engine"])
            self.assertIn("link", parent["bin/artifact-cache"])
            self.assertEqual(parent["bin/artifact-cache/private-engine/libflutter.so"]["sha256"], matrix.sha_file(engine))

    def test_sdk_link_escape_cycle_and_read_error_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); sdk = root / "sdk"; sdk.mkdir()
            actual = sdk / "bin/cache/private-engine"; actual.mkdir(parents=True)
            engine = actual / "libflutter.so"; engine.write_bytes(b"engine")
            aliases = sdk / "bin/cache/artifacts/engine"; aliases.mkdir(parents=True)
            link = aliases / "android-arm64-release"; link.symlink_to(actual, target_is_directory=True)
            cycle = actual / "cycle"; cycle.symlink_to(actual, target_is_directory=True)
            with self.assertRaisesRegex(matrix.MatrixError, "cycle"):
                matrix.sdk_engine_inputs(sdk)
            cycle.unlink(); link.unlink(); link.symlink_to(root, target_is_directory=True)
            with self.assertRaisesRegex(matrix.MatrixError, "escapes exact source root"):
                matrix.sdk_engine_inputs(sdk)
            link.unlink(); link.symlink_to(actual, target_is_directory=True)
            with mock.patch.object(matrix, "sha_file", side_effect=OSError("read denied")):
                with self.assertRaisesRegex(matrix.MatrixError, "cannot read/resolve"):
                    matrix.sdk_engine_inputs(sdk)

    def test_dependency_declared_build_assets_fonts_are_bound(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"; lab = source / "media_kit_hdr_lab"
            dependency = root / "cache/dependency"
            lab.mkdir(parents=True); (dependency / "build/fonts").mkdir(parents=True)
            (lab / "pubspec.yaml").write_text("name: media_kit_hdr_lab")
            (lab / "pubspec.lock").write_text("packages: {}")
            resource = dependency / "build/review.bin"; resource.write_bytes(b"original asset")
            font = dependency / "build/fonts/font.ttf"; font.write_bytes(b"original font")
            encoded = dependency / "build/with space.bin"; encoded.write_bytes(b"encoded URI asset")
            config = root / "package_config.json"
            roots = {"media_kit_hdr_lab": str(lab), "dependency": str(dependency)}
            config.write_text(json.dumps({"packages": [{"name": name, "rootUri": Path(path).as_uri()} for name, path in roots.items()]}))
            context = {"resources": [], "outputRoots": ["build"], "pubGenerated": [], "links": {},
                "packageResources": {"media_kit_hdr_lab": [], "dependency": [
                    {"kind": "asset", "path": "build/review.bin", "directory": False},
                    {"kind": "font", "path": "build/fonts/font.ttf", "directory": False},
                    {"kind": "asset", "path": "build/with%20space.bin", "directory": False}]}}
            with mock.patch.object(matrix, "verify_lab_package_roots", return_value=roots):
                before = matrix.lab_build_input_state(config, source, root / "cache", root / "sdk", context=context)
                resource.write_bytes(b"changed asset")
                after = matrix.lab_build_input_state(config, source, root / "cache", root / "sdk", context=context)
                self.assertNotEqual(before["declaredPackageInputs"], after["declaredPackageInputs"])
                self.assertEqual(before["resolvedPackageSources"], after["resolvedPackageSources"])
                encoded.write_bytes(b"changed encoded URI asset")
                uri_changed = matrix.lab_build_input_state(config, source, root / "cache", root / "sdk", context=context)
                self.assertNotEqual(after["declaredPackageInputs"], uri_changed["declaredPackageInputs"])
                font.write_bytes(b"changed font")
                final = matrix.lab_build_input_state(config, source, root / "cache", root / "sdk", context=context)
                self.assertNotEqual(after["declaredPackageInputs"], final["declaredPackageInputs"])
                resource.unlink()
                with self.assertRaisesRegex(matrix.MatrixError, "no base file or implicit variant"):
                    matrix.lab_build_input_state(config, source, root / "cache", root / "sdk", context=context)
                resource.symlink_to(lab / "pubspec.yaml")
                with self.assertRaisesRegex(matrix.MatrixError, "resource escapes exact package root"):
                    matrix.lab_build_input_state(config, source, root / "cache", root / "sdk", context=context)

    def test_declared_package_asset_reference_uses_bound_package_uri_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / "source"; lab = source / "media_kit_hdr_lab"
            package = root / "cache/wakelock_plus"
            lab.mkdir(parents=True); (package / "lib/assets").mkdir(parents=True)
            (lab / "pubspec.yaml").write_text("name: media_kit_hdr_lab")
            (lab / "pubspec.lock").write_text("packages: {}")
            asset = package / "lib/assets/no_sleep.js"; asset.write_bytes(b"source asset")
            (package / "lib/assets/2.0x").mkdir()
            uri_variant = package / "lib/assets/2.0x/no_sleep.js"; uri_variant.write_bytes(b"qualified URI variant")
            roots = {"media_kit_hdr_lab": str(lab), "wakelock_plus": str(package)}
            config = root / "package_config.json"
            entries = [{"name": name, "rootUri": Path(path).as_uri(), "packageUri": "lib/"} for name, path in roots.items()]
            config.write_text(json.dumps({"packages": entries}))
            context = {"resources": [], "outputRoots": ["build"], "pubGenerated": [], "links": {},
                "packageResources": {"wakelock_plus": [{"kind": "asset", "path": "packages/wakelock_plus/assets/no_sleep.js", "directory": False}]}}
            with mock.patch.object(matrix, "verify_lab_package_roots", return_value=roots):
                before = matrix.lab_build_input_state(config, source, root / "cache", root / "sdk", context=context)
                inputs = before["declaredPackageInputs"]["wakelock_plus"][0]["inputs"]
                self.assertEqual(inputs["lib/assets/no_sleep.js"]["sha256"], matrix.sha_file(asset))
                self.assertIn("lib/assets/2.0x/no_sleep.js", inputs)
                uri_variant.write_bytes(b"changed qualified URI variant")
                self.assertNotEqual(before, matrix.lab_build_input_state(config, source, root / "cache", root / "sdk", context=context))
                uri_variant.unlink()
                self.assertNotEqual(before, matrix.lab_build_input_state(config, source, root / "cache", root / "sdk", context=context))
                asset.write_bytes(b"changed source asset")
                self.assertNotEqual(before, matrix.lab_build_input_state(config, source, root / "cache", root / "sdk", context=context))
                entries[1]["packageUri"] = lab.as_uri() + "/"
                config.write_text(json.dumps({"packages": entries}))
                with self.assertRaisesRegex(matrix.MatrixError, "packageUri escapes"):
                    matrix.lab_build_input_state(config, source, root / "cache", root / "sdk", context=context)

    def test_implicit_asset_variant_members_add_delete_bytes_mode_and_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); build = root / "build"; build.mkdir()
            base = build / "review.bin"; base.write_bytes(b"base")
            def snapshot():
                return matrix.resource_input_snapshot(root, "build/review.bin", directory=False, kind="asset")
            before = snapshot()
            variant = build / "2.0x/review.bin"; variant.parent.mkdir(); variant.write_bytes(b"variant")
            added = snapshot(); self.assertNotEqual(before, added)
            self.assertIn("build/2.0x/review.bin", added["memberPaths"])
            variant.write_bytes(b"changed variant"); changed = snapshot(); self.assertNotEqual(added, changed)
            variant.chmod(0o755); mode_changed = snapshot(); self.assertNotEqual(changed, mode_changed)
            target = root / "real.bin"; target.write_bytes(variant.read_bytes()); target.chmod(0o755)
            variant.unlink(); variant.symlink_to(target)
            linked = snapshot(); self.assertNotEqual(mode_changed, linked)
            variant.unlink(); self.assertEqual(before, snapshot())
            # Literal file can be absent when real implicit variants exist.
            base.unlink(); variant.write_bytes(b"only variant")
            no_base = snapshot(); self.assertEqual(no_base["memberPaths"], ["build/2.0x/review.bin"])
            variant.unlink()
            with self.assertRaisesRegex(matrix.MatrixError, "no base file or implicit variant"):
                snapshot()

    def test_directory_assets_only_bind_direct_files_and_real_variants(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); build = root / "build"; build.mkdir()
            (build / "one.bin").write_bytes(b"one"); (build / "two.bin").write_bytes(b"two")
            (build / "3.0x").mkdir(); (build / "3.0x/one.bin").write_bytes(b"three")
            # SDK regexp uses hasMatch: the suffix alone authorizes this folder.
            (build / "prefix2x").mkdir(); (build / "prefix2x/two.bin").write_bytes(b"two variant")
            def snapshot():
                return matrix.resource_input_snapshot(root, "build", directory=True, kind="asset")
            before = snapshot()
            self.assertEqual(set(before["memberPaths"]), {"build/one.bin", "build/two.bin", "build/3.0x/one.bin", "build/prefix2x/two.bin"})
            (build / "intermediates").mkdir(); (build / "intermediates/native.o").write_bytes(b"legitimate output")
            self.assertEqual(before, snapshot())
            (build / "3.0x/unrelated.bin").write_bytes(b"not selected")
            self.assertEqual(before, snapshot())
            (build / "three.bin").write_bytes(b"new selected base")
            self.assertNotEqual(before, snapshot())

    def test_multiple_asset_variants_read_error_and_escape_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary); root = parent / "package"; root.mkdir()
            (root / "build").mkdir(); (root / "build/review.bin").write_bytes(b"base")
            for folder in ("2x", "3x"):
                (root / "build" / folder).mkdir(); (root / "build" / folder / "review.bin").write_bytes(folder.encode())
            def snapshot():
                return matrix.resource_input_snapshot(root, "build/review.bin", directory=False, kind="asset")
            self.assertEqual(len(snapshot()["memberPaths"]), 3)
            real_sha = matrix.sha_file
            def denied(path):
                if "3x" in path.parts: raise OSError("third file read denied")
                return real_sha(path)
            with mock.patch.object(matrix, "sha_file", side_effect=denied):
                with self.assertRaisesRegex(matrix.MatrixError, "cannot read/resolve"):
                    snapshot()
            variant = root / "build/3x/review.bin"; variant.unlink()
            outside = parent / "outside.bin"; outside.write_bytes(b"external")
            variant.symlink_to(outside)
            with self.assertRaisesRegex(matrix.MatrixError, "escapes exact package root"):
                snapshot()
            variant.unlink(); (root / "build/3x").rmdir(); (root / "build/3x").symlink_to(parent, target_is_directory=True)
            with self.assertRaisesRegex(matrix.MatrixError, "escapes exact package root"):
                snapshot()

    def test_private_bootstrap_rejects_old_source_vector(self):
        stale = {"scope": "routing-source-bootstrap", "status": "fresh-source-only",
            "platform": "android", "finalVector": {"app": "0" * 40,
                "appTree": "1" * 40, "media-kit": "2" * 40, "media-kitTree": "3" * 40}}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = root / "bootstrap.json"
            receipt.write_text(json.dumps(stale), encoding="utf-8")
            with mock.patch.object(matrix, "read_json", return_value=stale):
                with self.assertRaisesRegex(matrix.MatrixError, "exact current App/media-kit"):
                    matrix.finalize_bootstrap(root, root, root, {
                        "app": {"head": "a" * 40, "tree": "b" * 40},
                        "mediaKit": {"head": "c" * 40, "tree": "d" * 40}},
                        root, os.environ.copy())


if __name__ == "__main__":
    unittest.main()
