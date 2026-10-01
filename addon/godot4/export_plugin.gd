@tool
extends EditorExportPlugin

## Android export hooks: injects the GodotNoctua AAR and the native SDK Maven
## dependency (Godot 4 v2 plugin), and adds res://noctuagg.json to the APK assets
## even when the preset's include filter does not list it.

const AAR_PATH := "res://addons/GodotNoctua/native/android/GodotNoctua.godot4Release.aar"
const NATIVE_SDK := "com.noctuagames.sdk:noctua-android-sdk:0.35.1"
const CONFIG_FILE := "res://noctuagg.json"


func _get_name() -> String:
	return "GodotNoctua"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	# Only the release AAR is built; it is used for debug exports as well.
	return PackedStringArray([AAR_PATH])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return PackedStringArray([NATIVE_SDK])


func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return PackedStringArray([
		"https://dl.google.com/dl/android/maven2",
		"https://repo1.maven.org/maven2",
	])


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not FileAccess.file_exists(CONFIG_FILE):
		push_error("Noctua: %s not found. This build will run without the Noctua SDK." % CONFIG_FILE)
		return
	add_file(CONFIG_FILE, FileAccess.get_file_as_bytes(CONFIG_FILE), false)
