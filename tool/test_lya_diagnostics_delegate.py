#!/usr/bin/env python3
"""Host-only executable contract test for the Lab's vendor decorator.

Compiles the real wrapper against the interface extracted from current core
source, so adding a default method cannot silently bypass this coverage.
The empty host library only permits class initialization; Android diagnostic
JNI entrypoints and device HDR behavior are explicitly outside this test.
"""
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/platformview/PlatformVideoView.java"
WRAPPER = ROOT / "media_kit_hdr_lab/android/app/src/main/java/com/example/media_kit_hdr_lab/LyaDiagnosticsDataSpaceExt.java"


def interface_source():
    source = CORE.read_text()
    start = source.index("public interface SurfaceDataSpaceExt {")
    depth = 0
    for end in range(source.index("{", start), len(source)):
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
            if depth == 0:
                return source[start:end + 1]
    raise AssertionError("unterminated SurfaceDataSpaceExt")


JAVA_TEST = r'''
import android.view.Surface;
import com.alexmercerind.media_kit_video.platformview.PlatformVideoView.SurfaceDataSpaceExt;
import com.example.media_kit_hdr_lab.LyaDiagnosticsDataSpaceExt;
import java.lang.reflect.*;
import java.util.*;

public final class DelegateContractTest {
    public static void main(String[] ignored) throws Exception {
        int checked = 0;
        for (Method method : SurfaceDataSpaceExt.class.getDeclaredMethods()) {
            // A newly added default method must get an explicit wrapper
            // override; inheriting its conservative default is the bug.
            LyaDiagnosticsDataSpaceExt.class.getDeclaredMethod(
                    method.getName(), method.getParameterTypes());
            for (int variant = 0; variant < 2; variant++) {
                final Object[] expectedArgs = new Object[method.getParameterCount()];
                for (int i = 0; i < expectedArgs.length; i++) {
                    Class<?> type = method.getParameterTypes()[i];
                    if (type == Surface.class) expectedArgs[i] = new Surface();
                    else if (type == long.class) expectedArgs[i] = 9182736454L;
                    else if (type == int.class) expectedArgs[i] = 301 + i;
                    else if (type == String.class) expectedArgs[i] = variant == 0 ? null : "owner-token";
                    else throw new AssertionError("Unhandled argument type " + type);
                }
                final Object expected;
                if (method.getReturnType() == boolean.class) expected = variant != 0;
                else if (method.getReturnType() == int.class) expected = variant == 0 ? 0 : 7;
                else if (method.getReturnType() == String.class) expected = "vendor-" + variant;
                else if (method.getReturnType() == Boolean.class) expected = variant == 0 ? null : Boolean.FALSE;
                else if (method.getReturnType() == Set.class) expected = variant == 0 ? null : Collections.singleton("pq");
                else if (method.getReturnType() == void.class) expected = null;
                else throw new AssertionError("Unhandled result " + method);
                final int[] calls = {0};
                SurfaceDataSpaceExt delegate = (SurfaceDataSpaceExt) Proxy.newProxyInstance(
                        SurfaceDataSpaceExt.class.getClassLoader(),
                        new Class<?>[] { SurfaceDataSpaceExt.class }, (proxy, invoked, args) -> {
                    if (!method.equals(invoked)) throw new AssertionError("Wrong delegated method: " + invoked);
                    if (!Arrays.deepEquals(expectedArgs, args == null ? new Object[0] : args))
                        throw new AssertionError("Arguments changed for " + method);
                    calls[0]++;
                    return expected;
                });
                LyaDiagnosticsDataSpaceExt wrapper = new LyaDiagnosticsDataSpaceExt(delegate);
                Object actual = null;
                try {
                    actual = method.invoke(wrapper, expectedArgs);
                } catch (InvocationTargetException error) {
                    // Host library deliberately has no Android probe JNI.
                    // Both hooks must delegate first, then retain the native
                    // diagnostic attempt. Device probe behavior is not tested.
                    boolean diagnostic = method.getName().equals("onSurfaceAvailable")
                            || method.getName().equals("onDataSpaceApplyFailed");
                    if (!diagnostic || !(error.getCause() instanceof UnsatisfiedLinkError)) throw error;
                }
                if (calls[0] != 1) throw new AssertionError("Delegate swallowed/duplicated: " + method);
                if (method.getReturnType().isPrimitive()) {
                    if (!Objects.equals(expected, actual)) throw new AssertionError("Return changed " + method);
                } else if (actual != expected) throw new AssertionError("Return identity changed " + method);
                checked++;
            }
        }
        System.out.println("PASS: " + checked + " capability/lifecycle delegation cases");
    }
}
'''


class LyaDiagnosticsDelegateTest(unittest.TestCase):
    def test_all_current_interface_methods_are_transparently_delegated(self):
        java_home = Path(os.environ.get(
            "JAVA_HOME", "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"))
        javac = str(java_home / "bin/javac") if (java_home / "bin/javac").exists() else shutil.which("javac")
        java = str(java_home / "bin/java") if (java_home / "bin/java").exists() else shutil.which("java")
        self.assertIsNotNone(javac)
        self.assertIsNotNone(java)
        with tempfile.TemporaryDirectory(prefix="lya-delegate-test-") as temp:
            work = Path(temp)
            sources = {
                "android/view/Surface.java": "package android.view; public final class Surface {}",
                "androidx/annotation/NonNull.java": "package androidx.annotation; public @interface NonNull {}",
                "androidx/annotation/Nullable.java": "package androidx.annotation; public @interface Nullable {}",
                "com/alexmercerind/media_kit_video/platformview/PlatformVideoView.java":
                    "package com.alexmercerind.media_kit_video.platformview;\n"
                    "import androidx.annotation.NonNull; import androidx.annotation.Nullable;\n"
                    "public final class PlatformVideoView {\n" + interface_source() + "\n}",
                "com/example/media_kit_hdr_lab/LyaDiagnosticsDataSpaceExt.java": WRAPPER.read_text(),
                "DelegateContractTest.java": JAVA_TEST,
            }
            for name, value in sources.items():
                target = work / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(value)
            shim = work / "empty.c"
            shim.write_text("void thermal_test_library_only(void) {}\n")
            suffix = "dylib" if platform.system() == "Darwin" else "so"
            command = ["cc", "-dynamiclib" if suffix == "dylib" else "-shared",
                       "-fPIC", str(shim), "-o", str(work / f"libmedia_kit_p5_probe.{suffix}")]
            subprocess.run(command, check=True, capture_output=True, text=True)
            subprocess.run([javac, "--release", "11", "-d", str(work / "classes"),
                            *map(str, work.rglob("*.java"))], check=True, capture_output=True, text=True)
            result = subprocess.run([java, f"-Djava.library.path={work}", "-cp",
                                     str(work / "classes"), "DelegateContractTest"],
                                    check=True, capture_output=True, text=True)
            self.assertIn("PASS:", result.stdout)
            print(result.stdout.strip())


if __name__ == "__main__":
    unittest.main()
