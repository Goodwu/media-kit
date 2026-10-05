#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/tool/android_hdr_probe"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
BT="${ANDROID_BUILD_TOOLS:-$SDK/build-tools/35.0.0}"
PLATFORM="${ANDROID_PLATFORM:-$SDK/platforms/android-35/android.jar}"
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
OUT="${OUT_DIR:-/tmp/android-hdr-probe}"
WORK="$OUT/work"
APP_ID="${APP_ID:-com.example.androidhdrprobe}"
if [[ ! "$APP_ID" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]]; then
  echo "Invalid APP_ID: $APP_ID" >&2
  exit 1
fi
mkdir -p "$WORK/classes" "$WORK/dex" "$OUT"
rm -rf "$WORK/classes" "$WORK/dex"
mkdir -p "$WORK/classes" "$WORK/dex"

"$JAVA_HOME/bin/javac" -source 8 -target 8 -bootclasspath "$PLATFORM" -d "$WORK/classes" "$SRC/src/com/example/androidhdrprobe/ProbeActivity.java"
"$BT/d8" --min-api 24 --lib "$PLATFORM" --output "$WORK/dex" $(find "$WORK/classes" -name '*.class' -print)
MANIFEST="$SRC/AndroidManifest.xml"
if [ "$APP_ID" != "com.example.androidhdrprobe" ]; then
  MANIFEST="$WORK/AndroidManifest.xml"
  sed -e "s/package=\"com.example.androidhdrprobe\"/package=\"$APP_ID\"/" \
      -e 's/android:name=".ProbeActivity"/android:name="com.example.androidhdrprobe.ProbeActivity"/' \
      "$SRC/AndroidManifest.xml" > "$MANIFEST"
fi
"$BT/aapt" package -f -M "$MANIFEST" -I "$PLATFORM" -F "$WORK/base.apk"
cp "$WORK/dex/classes.dex" "$WORK/classes.dex"
(cd "$WORK" && "$BT/aapt" add base.apk classes.dex >/dev/null)
"$BT/zipalign" -f 4 "$WORK/base.apk" "$OUT/android-hdr-probe-unsigned.apk"
if [ ! -f "$OUT/debug.keystore" ]; then
  "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$OUT/debug.keystore" -storepass android -keypass android -alias androiddebugkey -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
fi
"$BT/apksigner" sign --ks "$OUT/debug.keystore" --ks-pass pass:android --key-pass pass:android --out "$OUT/android-hdr-probe.apk" "$OUT/android-hdr-probe-unsigned.apk"
"$BT/apksigner" verify --verbose "$OUT/android-hdr-probe.apk"
shasum -a 256 "$OUT/android-hdr-probe.apk"
du -h "$OUT/android-hdr-probe.apk"
echo "APK: $OUT/android-hdr-probe.apk (package: $APP_ID)"
