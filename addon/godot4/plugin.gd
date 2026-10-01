@tool
extends EditorPlugin

## Noctua SDK editor plugin (Godot 4.2+).
##
## While enabled it:
## - registers the [code]noctua[/code] autoload (removed again when disabled)
## - injects the Android library and its Maven dependency at export, and adds
##   res://noctuagg.json to every Android export (see export_plugin.gd)
## - installs the iOS plugin into res://ios/plugins, refreshing it whenever the
##   addon is updated
## - prints a warning for each export preset setting the SDK needs

const AUTOLOAD_NAME := "noctua"
const ADDON_DIR := "res://addons/GodotNoctua"
const AUTOLOAD_PATH := ADDON_DIR + "/noctua.gd"
const BUILD_FILE := ADDON_DIR + "/BUILD"
const NATIVE_IOS := ADDON_DIR + "/native/ios/GodotNoctua"
const IOS_PLUGIN := "res://ios/plugins/GodotNoctua"
const MARKER := ".noctua_build"
const CONFIG_FILE := "res://noctuagg.json"
const PRESETS_FILE := "res://export_presets.cfg"

var _export_plugin: EditorExportPlugin = null


func _enter_tree() -> void:
	_export_plugin = preload("res://addons/GodotNoctua/export_plugin.gd").new()
	add_export_plugin(_export_plugin)
	_ensure_autoload()
	_sync_ios_plugin()
	_check_setup()


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


func _enable_plugin() -> void:
	_ensure_autoload()


func _disable_plugin() -> void:
	if _autoload_target() == AUTOLOAD_PATH:
		remove_autoload_singleton(AUTOLOAD_NAME)
		_save_project_settings()


# ── Autoload ──────────────────────────────────────────────────────────────────

func _autoload_target() -> String:
	var key := "autoload/" + AUTOLOAD_NAME
	if not ProjectSettings.has_setting(key):
		return ""
	var target := str(ProjectSettings.get_setting(key)).trim_prefix("*")
	# Godot 4.4+ stores autoloads as uid://; resolve back to a path to compare.
	if target.begins_with("uid://"):
		var id := ResourceUID.text_to_id(target)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return target


func _ensure_autoload() -> void:
	var target := _autoload_target()
	if target == "":
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
		_save_project_settings()
		print("Noctua: registered autoload '%s' -> %s" % [AUTOLOAD_NAME, AUTOLOAD_PATH])
	elif target != AUTOLOAD_PATH:
		push_warning("Noctua: autoload '%s' already points to %s. Remove it in Project Settings > Globals > Autoload to use the addon's copy." % [AUTOLOAD_NAME, target])


# Write project.godot now, so the change survives however the editor exits.
func _save_project_settings() -> void:
	var err := ProjectSettings.save()
	if err != OK:
		push_error("Noctua: cannot save project.godot (error %d)" % err)


# ── Native plugin ─────────────────────────────────────────────────────────────

func _sync_ios_plugin() -> void:
	var build := _read_text(BUILD_FILE)
	if build == "":
		push_warning("Noctua: %s is missing, so the iOS plugin was not installed. Install the addon from the release zip." % BUILD_FILE)
		return
	if _read_text(IOS_PLUGIN.path_join(MARKER)) == build:
		return
	var err := _copy_dir(NATIVE_IOS, IOS_PLUGIN)
	if err != OK:
		push_error("Noctua: cannot copy the iOS plugin to %s (%s)" % [IOS_PLUGIN, error_string(err)])
		return
	_write_text(IOS_PLUGIN.path_join(MARKER), build)
	print("Noctua: installed iOS plugin (%s) into %s" % [build, IOS_PLUGIN])


# ── Setup checks ──────────────────────────────────────────────────────────────

func _check_setup() -> void:
	if not FileAccess.file_exists(CONFIG_FILE):
		push_warning("Noctua: %s not found. Get it from the Noctua team; the SDK cannot start without it." % CONFIG_FILE)
	var presets := ConfigFile.new()
	if presets.load(PRESETS_FILE) != OK:
		return
	for section: String in presets.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var preset_name := str(presets.get_value(section, "name", section))
		var platform := str(presets.get_value(section, "platform", ""))
		var options := section + ".options"
		if platform == "Android" and not presets.get_value(options, "gradle_build/use_gradle_build", false):
			push_warning("Noctua: export preset '%s': enable Gradle Build > Use Gradle Build." % preset_name)
		elif platform == "iOS" and not presets.get_value(options, "plugins/GodotNoctua", false):
			push_warning("Noctua: export preset '%s': tick Plugins > GodotNoctua." % preset_name)


# ── File helpers ──────────────────────────────────────────────────────────────

func _copy_dir(src: String, dst: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dst)
	if err != OK:
		return err
	var dir := DirAccess.open(src)
	if dir == null:
		return DirAccess.get_open_error()
	dir.include_hidden = false
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "" and err == OK:
		var from := src.path_join(file_name)
		var to := dst.path_join(file_name)
		err = _copy_dir(from, to) if dir.current_is_dir() else DirAccess.copy_absolute(from, to)
		file_name = dir.get_next()
	dir.list_dir_end()
	return err


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Noctua: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(text)
