@tool
extends EditorExportPlugin

## Android export hooks (Godot 4 v2 plugin). Mirrors the Noctua Unity SDK build step:
## - injects the GodotNoctua AAR and the native SDK Maven dependency
## - adds res://noctuagg.json to the APK assets, even when the preset's include
##   filter does not list it
## - Firebase: when res://google-services.json exists, copies it into the Android
##   build template and applies the google-services and Crashlytics Gradle plugins;
##   removes those plugins again when it does not
## - Facebook: adds facebook.android.appId / clientToken from noctuagg.json to the
##   manifest meta-data the Facebook SDK reads
##
## Every line this plugin writes into the build template ends with MARKER, so each
## export first removes the previous lines and the result never duplicates.

const AAR_PATH := "res://addons/GodotNoctua/native/android/GodotNoctua.godot4Release.aar"
const NATIVE_SDK := "com.noctuagames.sdk:noctua-android-sdk:0.35.1"
const CONFIG_FILE := "res://noctuagg.json"
const GOOGLE_SERVICES := "res://google-services.json"
const BUILD_DIR := "res://android/build"
const MARKER := "GodotNoctua"
# Same plugin versions as the Noctua Unity SDK build step.
const GOOGLE_SERVICES_VERSION := "4.5.0"
const CRASHLYTICS_VERSION := "3.0.7"


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


func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	var android := _facebook_android()
	var app_id := str(android.get("appId", ""))
	var client_token := str(android.get("clientToken", ""))
	if app_id == "" or client_token == "":
		return ""
	# "fb" prefix: same as the Unity SDK; the Facebook SDK strips it and keeps the id a string.
	return "<meta-data android:name=\"com.facebook.sdk.ApplicationId\" android:value=\"fb%s\" />\n" % app_id.xml_escape() \
			+ "<meta-data android:name=\"com.facebook.sdk.ClientToken\" android:value=\"%s\" />\n" % client_token.xml_escape()


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not FileAccess.file_exists(CONFIG_FILE):
		push_error("Noctua: %s not found. This build will run without the Noctua SDK." % CONFIG_FILE)
		return
	add_file(CONFIG_FILE, FileAccess.get_file_as_bytes(CONFIG_FILE), false)
	if not DirAccess.dir_exists_absolute(BUILD_DIR):
		push_warning("Noctua: %s not found. Install the Android build template; Firebase is not configured." % BUILD_DIR)
		return
	_configure_firebase()
	if _facebook_android().get("appId", "") != "":
		print("Noctua: Facebook on - app id and client token from noctuagg.json added to the manifest")
	else:
		print("Noctua: Facebook off - facebook.android.appId / clientToken not set in noctuagg.json")


# ── Firebase ──────────────────────────────────────────────────────────────────

func _configure_firebase() -> void:
	var enabled := FileAccess.file_exists(GOOGLE_SERVICES)
	if enabled:
		var err := DirAccess.copy_absolute(GOOGLE_SERVICES, BUILD_DIR.path_join("google-services.json"))
		if err != OK:
			push_error("Noctua: cannot copy %s into %s (%s). Firebase is not configured." % [GOOGLE_SERVICES, BUILD_DIR, error_string(err)])
			return
	var settings_block := ""
	var build_block := ""
	if enabled:
		settings_block = "\n        id 'com.google.gms.google-services' version '%s' // %s" % [GOOGLE_SERVICES_VERSION, MARKER] \
				+ "\n        id 'com.google.firebase.crashlytics' version '%s' // %s" % [CRASHLYTICS_VERSION, MARKER]
		build_block = "\n    id 'com.google.gms.google-services' // %s" % MARKER \
				+ "\n    id 'com.google.firebase.crashlytics' // %s" % MARKER
	var ok := _patch_file(BUILD_DIR.path_join("settings.gradle"), "pluginManagement {", "plugins {", settings_block)
	ok = _patch_file(BUILD_DIR.path_join("build.gradle"), "", "plugins {", build_block) and ok
	if not ok:
		return
	if enabled:
		print("Noctua: Firebase on - google-services.json copied; google-services %s and Crashlytics %s Gradle plugins applied" % [GOOGLE_SERVICES_VERSION, CRASHLYTICS_VERSION])
	else:
		print("Noctua: Firebase off - %s not found" % GOOGLE_SERVICES)


# ── Facebook ──────────────────────────────────────────────────────────────────

func _facebook_android() -> Dictionary:
	var config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_FILE))
	if typeof(config) != TYPE_DICTIONARY:
		return {}
	var facebook = config.get("facebook", {})
	if typeof(facebook) != TYPE_DICTIONARY or typeof(facebook.get("android", {})) != TYPE_DICTIONARY:
		return {}
	return facebook.get("android", {})


# ── Template patching ─────────────────────────────────────────────────────────

## Removes this plugin's previous lines, then inserts block right after the first
## anchor that follows section ("" = from the start). Writes only when changed.
func _patch_file(path: String, section: String, anchor: String, block: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("Noctua: cannot read %s. Firebase is not configured." % path)
		return false
	var patched := _strip_marked(text)
	if block != "":
		var start := patched.find(section) if section != "" else 0
		var at := patched.find(anchor, start) if start >= 0 else -1
		if at < 0:
			push_error("Noctua: '%s' not found in %s. Reinstall the Android build template." % [anchor, path])
			return false
		at += anchor.length()
		patched = patched.substr(0, at) + block + patched.substr(at)
	if patched == text:
		return true
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Noctua: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(patched)
	return true


func _strip_marked(text: String) -> String:
	var kept := PackedStringArray()
	for line in text.split("\n"):
		if line.find(MARKER) < 0:
			kept.append(line)
	return "\n".join(kept)
