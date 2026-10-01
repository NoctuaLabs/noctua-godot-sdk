#!/usr/bin/env bash
# Downloads the Godot engine AARs the Android plugin compiles against into
# android-plugin/libs/godot3/ and libs/godot4/.
#
# Usage: scripts/fetch_godot_libs.sh [godot3-tag] [godot4-tag]
#   defaults: 3.6.2-stable 4.6.1-stable
#
# Set GODOT_LIBS_CACHE to keep downloads outside the checkout (used by CI).
set -euo pipefail

GODOT3_TAG="${1:-3.6.2-stable}"
GODOT4_TAG="${2:-4.6.1-stable}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${GODOT_LIBS_CACHE:-$ROOT/android-plugin/.godot-libs}"

# $1 libs subdir (godot3|godot4)  $2 release tag  $3 asset file name
fetch() {
  local dir="$ROOT/android-plugin/libs/$1" tag="$2" name="$3"
  local cached="$CACHE/$name"
  if [ ! -s "$cached" ]; then
    echo "Downloading $name"
    mkdir -p "$CACHE"
    curl -fsSL --retry 3 -o "$cached.part" \
      "https://github.com/godotengine/godot/releases/download/$tag/$name"
    mv "$cached.part" "$cached"
  fi
  mkdir -p "$dir"
  rm -f "$dir"/godot-lib*.aar
  cp "$cached" "$dir/"
}

# Godot 3 names release templates "release"; Godot 4 uses "template_release".
fetch godot3 "$GODOT3_TAG" "godot-lib.${GODOT3_TAG/-/.}.release.aar"
fetch godot4 "$GODOT4_TAG" "godot-lib.${GODOT4_TAG/-/.}.template_release.aar"
