#!/usr/bin/env bash
# Builds the GodotNoctua iOS plugin as GodotNoctua.{debug,release}.xcframework.
#
# Usage:
#   ios-plugin/scripts/build.sh 3.x   [godot-tag]   # default tag 3.6.3-stable
#   ios-plugin/scripts/build.sh 4.x   [godot-tag]   # default tag 4.6.1-stable
#
# Output: ios-plugin/bin/<3.x|4.x>/GodotNoctua/  (gdip + both xcframeworks),
# ready to copy into the game project as res://ios/plugins/GodotNoctua/.
#
# Requirements: Xcode command line tools, git, python3 with scons
# (python3 -m pip install --user scons).
#
# An iOS plugin is compiled against the engine's own headers, so the matching
# Godot source is cloned into ios-plugin/.godot/<3.x|4.x> and a short engine
# build is run once to produce its generated headers (*.gen.h / *.gen.inc).
# Compiler flags follow godotengine/godot-ios-plugins; debug builds must define
# DEBUG_ENABLED exactly like the engine's debug export template.

set -euo pipefail

readonly MIN_IOS_VERSION="15.0" # NoctuaSDK's minimum deployment target
readonly PLUGIN_NAME="GodotNoctua"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
	echo "Usage: $0 <3.x|4.x> [godot-tag]" >&2
	exit 1
}

[[ $# -ge 1 ]] || usage
readonly GODOT_MAJOR="$1"
case "$GODOT_MAJOR" in
	3.x) readonly GODOT_TAG="${2:-3.6.3-stable}" ;;
	4.x) readonly GODOT_TAG="${2:-4.6.1-stable}" ;;
	*) usage ;;
esac

readonly GODOT_SRC="$PLUGIN_DIR/.godot/$GODOT_MAJOR"
readonly OBJ_DIR="$PLUGIN_DIR/.build/$GODOT_MAJOR"
readonly OUT_DIR="$PLUGIN_DIR/bin/$GODOT_MAJOR/$PLUGIN_NAME"

find_scons() {
	if command -v scons >/dev/null 2>&1; then
		command -v scons
	elif command -v python3 >/dev/null 2>&1 && [[ -x "$(python3 -m site --user-base)/bin/scons" ]]; then
		echo "$(python3 -m site --user-base)/bin/scons"
	else
		echo "error: scons not found — run: python3 -m pip install --user scons" >&2
		exit 1
	fi
}

fetch_godot_source() {
	if [[ -d "$GODOT_SRC/.git" ]]; then
		local current_tag
		current_tag="$(git -C "$GODOT_SRC" describe --tags --exact-match 2>/dev/null || true)"
		if [[ "$current_tag" == "$GODOT_TAG" ]]; then
			return
		fi
		echo "Godot source is at '${current_tag:-unknown}', replacing with $GODOT_TAG"
		rm -rf "$GODOT_SRC"
	fi
	echo "Cloning Godot $GODOT_TAG"
	git clone --quiet --depth 1 --branch "$GODOT_TAG" https://github.com/godotengine/godot.git "$GODOT_SRC"
}

# Runs the engine build just long enough to emit its generated headers.
generate_engine_headers() {
	local marker="$GODOT_SRC/core/version_generated.gen.h"
	local required=("$marker")
	if [[ "$GODOT_MAJOR" == "4.x" ]]; then
		required+=("$GODOT_SRC/core/object/gdvirtual.gen.inc" "$GODOT_SRC/core/disabled_classes.gen.h")
	else
		required+=("$GODOT_SRC/core/method_bind.gen.inc" "$GODOT_SRC/core/method_bind_ext.gen.inc")
	fi

	local missing=0
	for header in "${required[@]}"; do [[ -f "$header" ]] || missing=1; done
	[[ $missing -eq 0 ]] && return

	local scons platform target
	scons="$(find_scons)"
	if [[ "$GODOT_MAJOR" == "4.x" ]]; then platform="ios" target="template_debug"; else platform="iphone" target="release_debug"; fi

	echo "Generating Godot $GODOT_TAG headers (partial engine build)"
	(
		cd "$GODOT_SRC"
		"$scons" platform="$platform" target="$target" -j"$(sysctl -n hw.ncpu)" >"$PLUGIN_DIR/.godot/scons-$GODOT_MAJOR.log" 2>&1 &
		local pid=$!
		for _ in $(seq 1 600); do
			local done_all=1
			for header in "${required[@]}"; do [[ -f "$header" ]] || done_all=0; done
			if [[ $done_all -eq 1 ]]; then
				kill "$pid" 2>/dev/null || true
				wait "$pid" 2>/dev/null || true
				exit 0
			fi
			kill -0 "$pid" 2>/dev/null || break
			sleep 1
		done
		kill "$pid" 2>/dev/null || true
		echo "error: engine headers were not generated — see .godot/scons-$GODOT_MAJOR.log" >&2
		exit 1
	)
}

# Compiles every source for one variant/sdk/arch into a static library.
# $1 variant (debug|release)  $2 sdk (iphoneos|iphonesimulator)  $3 arch
build_slice() {
	local variant="$1" sdk="$2" arch="$3"
	local slice_dir="$OBJ_DIR/$variant/$sdk-$arch"
	local sdk_path
	sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
	mkdir -p "$slice_dir"

	local target_triple="$arch-apple-ios$MIN_IOS_VERSION"
	[[ "$sdk" == "iphonesimulator" ]] && target_triple+="-simulator"

	local flags=(
		-target "$target_triple" -isysroot "$sdk_path"
		-fobjc-arc -fmodules -fcxx-modules -fblocks -fno-exceptions -fvisibility=hidden
		-fno-strict-aliasing -fmessage-length=0 -Wall -Werror=return-type -Wno-ambiguous-macro
		-DPTRCALL_ENABLED -DUNIX_ENABLED -DCOREAUDIO_ENABLED -DNEED_LONG_INT -DLIBYUV_DISABLE_NEON
		-I"$PLUGIN_DIR/src" -I"$GODOT_SRC"
	)
	if [[ "$GODOT_MAJOR" == "4.x" ]]; then
		flags+=(-std=gnu++17 -DGODOT_NOCTUA_GODOT4 -DIOS_ENABLED -DAPPLE_EMBEDDED_ENABLED -I"$GODOT_SRC/platform/ios")
	else
		flags+=(-std=gnu++14 -DIPHONE_ENABLED -DGLES_ENABLED -I"$GODOT_SRC/platform/iphone")
	fi
	if [[ "$variant" == "debug" ]]; then
		flags+=(-O2 -DNDEBUG -DNS_BLOCK_ASSERTIONS=1 -DDEBUG_ENABLED -g)
	else
		flags+=(-O2 -DNDEBUG -DNS_BLOCK_ASSERTIONS=1)
	fi

	local objects=()
	for source in "$PLUGIN_DIR"/src/*.mm "$PLUGIN_DIR"/src/*.cpp; do
		local object="$slice_dir/$(basename "$source").o"
		local language_flags=(-x objective-c++)
		[[ "$source" == *.cpp ]] && language_flags=(-x c++)
		xcrun --sdk "$sdk" clang++ "${language_flags[@]}" "${flags[@]}" -c "$source" -o "$object"
		objects+=("$object")
	done

	xcrun libtool -static -o "$slice_dir/lib$PLUGIN_NAME.a" "${objects[@]}"
}

# $1 variant (debug|release)
build_xcframework() {
	local variant="$1"
	echo "Building $PLUGIN_NAME.$variant.xcframework (Godot $GODOT_TAG)"

	build_slice "$variant" iphoneos arm64
	build_slice "$variant" iphonesimulator arm64
	build_slice "$variant" iphonesimulator x86_64

	local simulator_dir="$OBJ_DIR/$variant/iphonesimulator-universal"
	mkdir -p "$simulator_dir"
	xcrun lipo -create \
		"$OBJ_DIR/$variant/iphonesimulator-arm64/lib$PLUGIN_NAME.a" \
		"$OBJ_DIR/$variant/iphonesimulator-x86_64/lib$PLUGIN_NAME.a" \
		-output "$simulator_dir/lib$PLUGIN_NAME.a"

	local xcframework="$OUT_DIR/$PLUGIN_NAME.$variant.xcframework"
	rm -rf "$xcframework"
	xcodebuild -create-xcframework \
		-library "$OBJ_DIR/$variant/iphoneos-arm64/lib$PLUGIN_NAME.a" \
		-library "$simulator_dir/lib$PLUGIN_NAME.a" \
		-output "$xcframework" >/dev/null
}

main() {
	fetch_godot_source
	generate_engine_headers

	rm -rf "$OBJ_DIR"
	mkdir -p "$OUT_DIR"
	build_xcframework debug
	build_xcframework release
	cp "$PLUGIN_DIR/$PLUGIN_NAME.gdip" "$OUT_DIR/"

	echo "Done: $OUT_DIR"
	echo "Copy that folder into your game as res://ios/plugins/$PLUGIN_NAME/"
}

main
