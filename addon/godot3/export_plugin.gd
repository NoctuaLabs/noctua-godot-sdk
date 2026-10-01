tool
extends EditorExportPlugin

## Android export hooks (Godot 3.6 custom build). Mirrors the Noctua Unity SDK build step:
## - adds res://noctuagg.json to the APK assets, even when the preset's include
##   filter does not list it
## - Firebase: when res://google-services.json exists, copies it into the Android
##   build template and applies the google-services and Crashlytics Gradle plugins;
##   removes those plugins again when it does not
## - Facebook: writes facebook.android.appId / clientToken from noctuagg.json into
##   the meta-data the Facebook SDK reads from AndroidManifest.xml
##
## Every line this plugin writes into the build template ends with MARKER, so each
## export first removes the previous lines and the result never duplicates.

const CONFIG_FILE := "res://noctuagg.json"
const GOOGLE_SERVICES := "res://google-services.json"
const BUILD_DIR := "res://android/build"
const MARKER := "GodotNoctua"
# Same plugin versions as the Noctua Unity SDK build step.
const GOOGLE_SERVICES_VERSION := "4.5.0"
const CRASHLYTICS_VERSION := "3.0.7"


func _export_begin(features: PoolStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not _is_android(features):
		return
	var file := File.new()
	if file.open(CONFIG_FILE, File.READ) != OK:
		push_error("Noctua: %s not found. This build will run without the Noctua SDK." % CONFIG_FILE)
		return
	var data := file.get_buffer(file.get_len())
	file.close()
	add_file(CONFIG_FILE, data, false)
	if not Directory.new().dir_exists(BUILD_DIR):
		push_warning("Noctua: %s not found. Install the Android build template; Firebase and Facebook are not configured." % BUILD_DIR)
		return
	_configure_firebase()
	_configure_facebook(_facebook_android(data.get_string_from_utf8()))


func _is_android(features: PoolStringArray) -> bool:
	for feature in features:
		if str(feature).to_lower() == "android":
			return true
	return false


# ── Firebase ──────────────────────────────────────────────────────────────────

func _configure_firebase() -> void:
	var enabled := File.new().file_exists(GOOGLE_SERVICES)
	if enabled and Directory.new().copy(GOOGLE_SERVICES, BUILD_DIR.plus_file("google-services.json")) != OK:
		push_error("Noctua: cannot copy %s into %s. Firebase is not configured." % [GOOGLE_SERVICES, BUILD_DIR])
		return
	var settings_block := ""
	var build_block := ""
	if enabled:
		settings_block = "\n        id 'com.google.gms.google-services' version '%s' // %s" % [GOOGLE_SERVICES_VERSION, MARKER] \
				+ "\n        id 'com.google.firebase.crashlytics' version '%s' // %s" % [CRASHLYTICS_VERSION, MARKER]
		build_block = "\n    id 'com.google.gms.google-services' // %s" % MARKER \
				+ "\n    id 'com.google.firebase.crashlytics' // %s" % MARKER
	var ok := _patch_file(BUILD_DIR.plus_file("settings.gradle"), "pluginManagement {", "plugins {", settings_block)
	ok = _patch_file(BUILD_DIR.plus_file("build.gradle"), "", "plugins {", build_block) and ok
	if not ok:
		return
	if enabled:
		print("Noctua: Firebase on - google-services.json copied; google-services %s and Crashlytics %s Gradle plugins applied" % [GOOGLE_SERVICES_VERSION, CRASHLYTICS_VERSION])
	else:
		print("Noctua: Firebase off - %s not found" % GOOGLE_SERVICES)


# ── Facebook ──────────────────────────────────────────────────────────────────

func _facebook_android(config_text: String) -> Dictionary:
	var parsed := JSON.parse(config_text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		push_warning("Noctua: %s is not valid JSON; Facebook is not configured." % CONFIG_FILE)
		return {}
	var facebook = parsed.result.get("facebook", {})
	if typeof(facebook) != TYPE_DICTIONARY or typeof(facebook.get("android", {})) != TYPE_DICTIONARY:
		return {}
	return facebook.get("android", {})


func _configure_facebook(android: Dictionary) -> void:
	var app_id := str(android.get("appId", ""))
	var client_token := str(android.get("clientToken", ""))
	var block := ""
	if app_id != "" and client_token != "":
		# "fb" prefix: same as the Unity SDK; the Facebook SDK strips it and keeps the id a string.
		block = "\n        <meta-data android:name=\"com.facebook.sdk.ApplicationId\" android:value=\"fb%s\" /> <!-- %s -->" % [app_id.xml_escape(), MARKER] \
				+ "\n        <meta-data android:name=\"com.facebook.sdk.ClientToken\" android:value=\"%s\" /> <!-- %s -->" % [client_token.xml_escape(), MARKER]
	if not _patch_manifest(BUILD_DIR.plus_file("AndroidManifest.xml"), block):
		return
	if block != "":
		print("Noctua: Facebook on - app id and client token from noctuagg.json added to AndroidManifest.xml")
	else:
		print("Noctua: Facebook off - facebook.android.appId / clientToken not set in noctuagg.json")


# ── Template patching ─────────────────────────────────────────────────────────

## Removes this plugin's previous lines, then inserts block right after the first
## anchor that follows section ("" = from the start). Writes only when changed.
func _patch_file(path: String, section: String, anchor: String, block: String) -> bool:
	var text := _read_text(path)
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
	return _write_if_changed(path, text, patched)


func _patch_manifest(path: String, block: String) -> bool:
	var text := _read_text(path)
	var at := text.find("</application>")
	if at < 0:
		push_error("Noctua: <application> not found in %s. Facebook is not configured." % path)
		return false
	var patched := _strip_marked(text)
	if block != "":
		at = patched.find("</application>")
		patched = patched.substr(0, at).strip_edges(false, true) + block + "\n    " + patched.substr(at)
	return _write_if_changed(path, text, patched)


func _strip_marked(text: String) -> String:
	var kept := PoolStringArray()
	for line in text.split("\n"):
		if line.find(MARKER) < 0:
			kept.append(line)
	return kept.join("\n")


func _read_text(path: String) -> String:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_if_changed(path: String, before: String, after: String) -> bool:
	if after == before:
		return true
	var file := File.new()
	if file.open(path, File.WRITE) != OK:
		push_error("Noctua: cannot write %s" % path)
		return false
	file.store_string(after)
	file.close()
	return true
