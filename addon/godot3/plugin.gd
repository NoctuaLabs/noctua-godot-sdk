tool
extends EditorPlugin

## Noctua SDK editor plugin (Godot 3.6).
##
## While enabled it:
## - registers the [code]noctua[/code] autoload (removed again when disabled)
## - installs the native plugins into res://android/plugins and res://ios/plugins,
##   refreshing them whenever the addon is updated
## - adds res://noctuagg.json to every Android export (see export_plugin.gd)
## - prints a warning for each export preset setting the SDK needs

const AUTOLOAD_NAME := "noctua"
const ADDON_DIR := "res://addons/GodotNoctua"
const AUTOLOAD_PATH := ADDON_DIR + "/noctua.gd"
const BUILD_FILE := ADDON_DIR + "/BUILD"
const NATIVE_ANDROID := ADDON_DIR + "/native/android"
const NATIVE_IOS := ADDON_DIR + "/native/ios/GodotNoctua"
const ANDROID_PLUGINS := "res://android/plugins"
const ANDROID_FILES := ["GodotNoctua.gdap", "GodotNoctua.godot3Release.aar"]
const IOS_PLUGIN := "res://ios/plugins/GodotNoctua"
const MARKER := ".noctua_build"
const CONFIG_FILE := "res://noctuagg.json"
const PRESETS_FILE := "res://export_presets.cfg"
const MIN_ANDROID_SDK := 23

var _export_plugin: EditorExportPlugin = null


func _enter_tree() -> void:
	_export_plugin = preload("res://addons/GodotNoctua/export_plugin.gd").new()
	add_export_plugin(_export_plugin)
	_ensure_autoload()
	_sync_native_plugins()
	_check_setup()


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


func enable_plugin() -> void:
	_ensure_autoload()


func disable_plugin() -> void:
	if _autoload_target() == AUTOLOAD_PATH:
		remove_autoload_singleton(AUTOLOAD_NAME)
		_save_project_settings()


# ── Autoload ──────────────────────────────────────────────────────────────────

func _autoload_target() -> String:
	var key := "autoload/" + AUTOLOAD_NAME
	if not ProjectSettings.has_setting(key):
		return ""
	return str(ProjectSettings.get_setting(key)).trim_prefix("*")


func _ensure_autoload() -> void:
	var target := _autoload_target()
	if target == "":
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
		_save_project_settings()
		print("Noctua: registered autoload '%s' -> %s" % [AUTOLOAD_NAME, AUTOLOAD_PATH])
	elif target != AUTOLOAD_PATH:
		push_warning("Noctua: autoload '%s' already points to %s. Remove it in Project Settings > AutoLoad to use the addon's copy." % [AUTOLOAD_NAME, target])


# Write project.godot now, so the change survives however the editor exits.
func _save_project_settings() -> void:
	var err := ProjectSettings.save()
	if err != OK:
		push_error("Noctua: cannot save project.godot (error %d)" % err)


# ── Native plugins ────────────────────────────────────────────────────────────

func _sync_native_plugins() -> void:
	var build := _read_text(BUILD_FILE)
	if build == "":
		push_warning("Noctua: %s is missing, so the native plugins were not installed. Install the addon from the release zip." % BUILD_FILE)
		return
	# Godot reads both folders directly at export time; no resource rescan needed.
	if _read_text(ANDROID_PLUGINS.plus_file(MARKER)) != build:
		_install_android(build)
	if _read_text(IOS_PLUGIN.plus_file(MARKER)) != build:
		_install_ios(build)
	_warn_duplicate_gdap()


func _install_android(build: String) -> void:
	var dir := Directory.new()
	if dir.make_dir_recursive(ANDROID_PLUGINS) != OK:
		push_error("Noctua: cannot create %s" % ANDROID_PLUGINS)
		return
	for file_name in ANDROID_FILES:
		var err := dir.copy(NATIVE_ANDROID.plus_file(file_name), ANDROID_PLUGINS.plus_file(file_name))
		if err != OK:
			push_error("Noctua: cannot copy %s to %s (error %d)" % [file_name, ANDROID_PLUGINS, err])
			return
	_write_text(ANDROID_PLUGINS.plus_file(MARKER), build)
	print("Noctua: installed Android plugin (%s) into %s" % [build, ANDROID_PLUGINS])


func _install_ios(build: String) -> void:
	var err := _copy_dir(NATIVE_IOS, IOS_PLUGIN)
	if err != OK:
		push_error("Noctua: cannot copy the iOS plugin to %s (error %d)" % [IOS_PLUGIN, err])
		return
	_write_text(IOS_PLUGIN.plus_file(MARKER), build)
	print("Noctua: installed iOS plugin (%s) into %s" % [build, IOS_PLUGIN])


# Two .gdap files with the same plugin name make Godot load the plugin twice.
func _warn_duplicate_gdap() -> void:
	var dir := Directory.new()
	if dir.open(ANDROID_PLUGINS) != OK:
		return
	dir.list_dir_begin(true, true)
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".gdap") and file_name != "GodotNoctua.gdap":
			var gdap := ConfigFile.new()
			if gdap.load(ANDROID_PLUGINS.plus_file(file_name)) == OK and gdap.get_value("config", "name", "") == "GodotNoctua":
				push_warning("Noctua: delete %s. It duplicates GodotNoctua.gdap installed by the addon." % ANDROID_PLUGINS.plus_file(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


# ── Setup checks ──────────────────────────────────────────────────────────────

func _check_setup() -> void:
	if not File.new().file_exists(CONFIG_FILE):
		push_warning("Noctua: %s not found. Get it from the Noctua team; the SDK cannot start without it." % CONFIG_FILE)
	var presets := ConfigFile.new()
	if presets.load(PRESETS_FILE) != OK:
		return
	for section in presets.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var preset_name := str(presets.get_value(section, "name", section))
		var platform := str(presets.get_value(section, "platform", ""))
		var options: String = section + ".options"
		if platform == "Android":
			_check_android_preset(presets, options, preset_name)
		elif platform == "iOS" and not presets.get_value(options, "plugins/GodotNoctua", false):
			push_warning("Noctua: export preset '%s': tick Plugins > GodotNoctua." % preset_name)


func _check_android_preset(presets: ConfigFile, options: String, preset_name: String) -> void:
	if not presets.get_value(options, "custom_build/use_custom_build", false):
		push_warning("Noctua: export preset '%s': enable Custom Build > Use Custom Build." % preset_name)
	if not presets.get_value(options, "plugins/GodotNoctua", false):
		push_warning("Noctua: export preset '%s': tick Plugins > GodotNoctua." % preset_name)
	var min_sdk := str(presets.get_value(options, "custom_build/min_sdk", ""))
	if min_sdk == "" or int(min_sdk) < MIN_ANDROID_SDK:
		push_warning("Noctua: export preset '%s': set Custom Build > Min Sdk to %d or higher." % [preset_name, MIN_ANDROID_SDK])


# ── File helpers ──────────────────────────────────────────────────────────────

func _copy_dir(src: String, dst: String) -> int:
	var dir := Directory.new()
	var err := dir.make_dir_recursive(dst)
	if err != OK:
		return err
	err = dir.open(src)
	if err != OK:
		return err
	dir.list_dir_begin(true, true)
	var file_name := dir.get_next()
	while file_name != "" and err == OK:
		var from := src.plus_file(file_name)
		var to := dst.plus_file(file_name)
		err = _copy_dir(from, to) if dir.current_is_dir() else dir.copy(from, to)
		file_name = dir.get_next()
	dir.list_dir_end()
	return err


func _read_text(path: String) -> String:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return ""
	var text := file.get_as_text().strip_edges()
	file.close()
	return text


func _write_text(path: String, text: String) -> void:
	var file := File.new()
	if file.open(path, File.WRITE) != OK:
		push_error("Noctua: cannot write %s" % path)
		return
	file.store_string(text)
	file.close()
