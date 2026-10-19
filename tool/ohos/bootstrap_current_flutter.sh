#!/usr/bin/env bash
# Resolve the maintained patch branch afresh. Never advertise a newer SDK
# version than the audited framework pin supplies.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
dest=${1:?destination required}
metadata=${2:?metadata output directory required}
test ! -e "$dest"
mkdir -p "$metadata"
read_pin() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$root/tool/ohos/flutter-ohos.pin" "$1"; }
mirror=$(read_pin mirror)
branch=$(read_pin patch_branch)
expected=$(git ls-remote --exit-code "$mirror" "refs/heads/$branch" | awk 'NR==1 {print $1}')
test "${#expected}" = 40
git clone --depth 1 --single-branch --branch "$branch" "$mirror" "$dest"
test "$(git -C "$dest" rev-parse HEAD)" = "$expected"
# The framework's version metadata is absent from this shallow fork. Only the
# already audited pinned commit may receive its matching local semver tag.
# A changed framework must supply/review its own version; never fake 3.47.x.
if [ "$expected" = "$(read_pin patch_commit)" ]; then
  git -C "$dest" tag "$(read_pin version_tag)" "$expected"
fi
printf '%s\n' "$expected" > "$metadata/flutter-ohos-commit.txt"
git -C "$dest" show HEAD:bin/internal/engine.version > "$metadata/flutter-ohos-engine.txt"
"$dest/bin/flutter" --version --machine > "$metadata/flutter-version.json"
"$dest/bin/dart" --version 2> "$metadata/dart-version.txt"
cat "$metadata/flutter-version.json" "$metadata/dart-version.txt"
