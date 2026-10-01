tool
extends EditorExportPlugin

## Adds res://noctuagg.json to every Android export, so the native SDK finds it
## in the APK assets even when the preset's include filter does not list it.

const CONFIG_FILE := "res://noctuagg.json"


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


func _is_android(features: PoolStringArray) -> bool:
	for feature in features:
		if str(feature).to_lower() == "android":
			return true
	return false
