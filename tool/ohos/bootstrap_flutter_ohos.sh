#!/usr/bin/env bash
# Bootstrap a reproducible Flutter OHOS SDK checkout from the pinned mirror.
#
# Consumes tool/ohos/flutter-ohos.pin (single source of truth, shared with CI).
# Machine prerequisites (documented, tool-exempt per binary policy):
#   - git, python3, unzip/xz
#   - HarmonyOS command-line-tools 26.0.0.621 on PATH or DEVECO_SDK_HOME
#     (CI installs via ErBWs/setup-ohos@5c8e74d0; locally install DevEco Studio
#     or command-line-tools and export DEVECO_SDK_HOME)
#   - Java 17 for hvigor
#
# Usage:
#   tool/ohos/bootstrap_flutter_ohos.sh <dest-dir> [--precache] [--doctor]
#     <dest-dir>   SDK checkout location (created if absent)
#     --precache   run `flutter precache` after checkout (engine artifacts are
#                  otherwise downloaded lazily on first build)
#     --doctor     run `flutter doctor -v` as a smoke check
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
pin_file="$repo_root/tool/ohos/flutter-ohos.pin"

[[ -f "$pin_file" ]] || { echo "missing pin: $pin_file" >&2; exit 2; }
dest=${1:?usage: bootstrap_flutter_ohos.sh <dest-dir> [--precache] [--doctor]}
shift || true
want_precache=0; want_doctor=0
for a in "$@"; do
  case "$a" in
    --precache) want_precache=1 ;;
    --doctor) want_doctor=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

read_pin() {
  python3 -c "import json,sys;print(json.load(open('$pin_file'))['$1'])"
}
mirror=$(read_pin mirror)
fallback=$(read_pin fallback)
patch_commit=$(read_pin patch_commit)
version_tag=$(read_pin version_tag)

mkdir -p "$dest"
dest=$(cd "$dest" && pwd)

if [[ ! -d "$dest/.git" ]]; then
  echo ">> cloning mirror $mirror"
  if ! git clone "$mirror" "$dest"; then
    echo ">> mirror clone failed, falling back to $fallback" >&2
    git clone "$fallback" "$dest"
  fi
fi

echo ">> fetching pinned patch commit $patch_commit"
git -C "$dest" fetch --no-tags origin "$patch_commit" 2>/dev/null \
  || git -C "$dest" fetch --no-tags "$fallback" "$patch_commit"
git -C "$dest" checkout --detach "$patch_commit"
git -C "$dest" tag -f "$version_tag" "$patch_commit"

flutter_bin="$dest/bin/flutter"
[[ -x "$flutter_bin" ]] || { echo "flutter binary missing after checkout" >&2; exit 1; }

echo ">> flutter --version (warms basic cache)"
"$flutter_bin" --version

if [[ "$want_precache" = 1 ]]; then
  echo ">> flutter precache"
  "$flutter_bin" precache
fi
if [[ "$want_doctor" = 1 ]]; then
  "$flutter_bin" doctor -v
fi

cat <<SUMMARY

Bootstrap complete:
  sdk          : $dest
  patch_commit : $patch_commit
  version tag  : $version_tag
  engine       : $(read_pin engine_version)
Next:
  export PATH="$dest/bin:\$PATH"
  cd media_kit_test && cp pubspec.ohos.lock pubspec.lock && flutter pub get --enforce-lockfile
  flutter build hap --release --no-codesign
SUMMARY
