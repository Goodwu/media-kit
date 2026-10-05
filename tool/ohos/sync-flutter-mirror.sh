#!/usr/bin/env bash
# Local fallback for syncing the flutter_flutter mirror when the GitHub-side
# scheduled workflow (Goodwu/flutter_flutter infra branch, daily 02:17 UTC)
# cannot reach gitcode. Fast-forward only: a non-FF push is refused so a
# polluted mirror branch can never be silently overwritten.
#
# Usage: tool/ohos/sync-flutter-mirror.sh [--check]
#   --check   only report drift between gitcode tip and local mirror ref
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
pin_file="$repo_root/tool/ohos/flutter-ohos.pin"
mirror=$(python3 -c "import json;print(json.load(open('$pin_file'))['mirror'])")
fallback=$(python3 -c "import json;print(json.load(open('$pin_file'))['fallback'])")
branch=$(python3 -c "import json;print(json.load(open('$pin_file'))['upstream_branch'])")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q "$work/m" && cd "$work/m"

echo ">> fetching gitcode $branch"
ok=0
for i in 1 2 3; do
  if timeout 600 git fetch --no-tags "$fallback" "$branch"; then ok=1; break; fi
  echo "retry $i"; sleep 20
done
[[ "$ok" = 1 ]] || { echo "gitcode unreachable" >&2; exit 1; }
tip=$(git rev-parse FETCH_HEAD)
echo "upstream tip: $tip"

git remote add origin "$mirror"
if [[ "${1:-}" = "--check" ]]; then
  git fetch --no-tags origin "$branch"
  current=$(git rev-parse "FETCH_HEAD")
  if [[ "$current" = "$tip" ]]; then
    echo "mirror up to date: $tip"
  else
    git merge-base --is-ancestor "$current" "$tip" \
      && echo "mirror behind: $current -> $tip (run without --check to sync)" \
      || echo "mirror DIVERGED: $current vs upstream $tip (manual intervention)"
  fi
  exit 0
fi

echo ">> pushing to $mirror ($branch, fast-forward only)"
git push origin "$tip":refs/heads/"$branch"
echo "mirror synced to $tip"
