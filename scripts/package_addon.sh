#!/usr/bin/env bash
# Packages the Godot editor addon as an installable zip:
#   dist/GodotNoctua-godot<3|4>-<build>.zip  ->  addons/GodotNoctua/...
#
# Usage: scripts/package_addon.sh <3.x|4.x>
#
# Set NOCTUA_VERSION (e.g. 1.2.0) for a release: it is written into plugin.cfg
# and the zip is named GodotNoctua-godot<3|4>-v<version>.zip instead.
#
# Build the native plugins first:
#   (cd android-plugin && ./gradlew assembleGodot3Release assembleGodot4Release)
#   ios-plugin/scripts/build.sh 3.x    # and/or 4.x
set -euo pipefail

GODOT_LINE="${1:-}"
case "$GODOT_LINE" in
  3.x) MAJOR=3 ;;
  4.x) MAJOR=4 ;;
  *) echo "usage: $0 <3.x|4.x>" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AAR="$ROOT/android-plugin/build/outputs/aar/GodotNoctua.godot${MAJOR}Release.aar"
IOS_BIN="$ROOT/ios-plugin/bin/$GODOT_LINE/GodotNoctua"

require() {
  if [ ! -e "$1" ]; then
    echo "error: $1 not found. $2" >&2
    exit 1
  fi
}
require "$AAR" "Run: (cd android-plugin && ./gradlew assembleGodot${MAJOR}Release)"
require "$IOS_BIN/GodotNoctua.gdip" "Run: ios-plugin/scripts/build.sh $GODOT_LINE"

BUILD="$(git -C "$ROOT" rev-parse --short HEAD)"
if [ -n "$(git -C "$ROOT" status --porcelain -- android-plugin/src ios-plugin/src gd addon)" ]; then
  BUILD="$BUILD-dirty"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ADDON="$STAGE/addons/GodotNoctua"
mkdir -p "$ADDON/native/android" "$ADDON/native/ios"

cp "$ROOT/addon/godot$MAJOR/"*.gd "$ROOT/addon/godot$MAJOR/plugin.cfg" "$ADDON/"
cp "$ROOT/gd/noctua.gd" "$ADDON/"
cp "$ROOT/LICENSE" "$ADDON/"
if [ -n "${NOCTUA_VERSION:-}" ]; then
  sed -i '' "s/^version=.*/version=\"$NOCTUA_VERSION\"/" "$ADDON/plugin.cfg"
fi
echo "$BUILD" > "$ADDON/BUILD"
# Keep Godot from importing or exporting the native binaries as resources.
touch "$ADDON/native/.gdignore"

cp "$AAR" "$ADDON/native/android/"
if [ "$MAJOR" = 3 ]; then
  # Godot 3 v1 plugin: the editor copies this .gdap next to the AAR in res://android/plugins.
  cp "$ROOT/android-plugin/GodotNoctua.godot3.gdap" "$ADDON/native/android/GodotNoctua.gdap"
fi
cp -R "$IOS_BIN" "$ADDON/native/ios/"

mkdir -p "$ROOT/dist"
SUFFIX="$BUILD"
[ -n "${NOCTUA_VERSION:-}" ] && SUFFIX="v$NOCTUA_VERSION"
OUT="$ROOT/dist/GodotNoctua-godot$MAJOR-$SUFFIX.zip"
rm -f "$OUT"
(cd "$STAGE" && zip -qry "$OUT" addons -x '*.DS_Store')
echo "$OUT"
