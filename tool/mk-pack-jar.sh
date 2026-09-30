#!/bin/bash
# 重打包 media_kit arm64 JAR：解开源 JAR、替换 lib/arm64-v8a/libmpv.so 后重新压缩
# usage: mk-pack-jar.sh <src.jar> <new_libmpv.so> <out.jar>
set -e
SRC_JAR=${1:?}; NEW_SO=${2:?}; OUT=${3:?}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
unzip -q "$SRC_JAR"
cp "$NEW_SO" lib/arm64-v8a/libmpv.so
rm -f "$OUT"
zip -q -r "$OUT" lib META-INF 2>/dev/null || zip -q -r "$OUT" lib
echo "packed $OUT"
shasum -a 256 "$OUT"
