extends Node
## Presentation preferences only. Gameplay state will live in separate services.

signal reduced_motion_changed(enabled: bool)

const SETTINGS_PATH := "user://settings.cfg"
const ENGINE_BASELINE := "4.5.stable.official.876b29033"

var reduced_motion := false


func _ready() -> void:
	var version := Engine.get_version_info()
	if version.major != 4 or version.minor != 5 or version.patch != 0 or version.status != "stable" or not str(version.hash).begins_with("876b29033"):
		push_warning("Engine baseline is %s; running %s." % [ENGINE_BASELINE, version.get("string")])
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var value: Variant = config.get_value("accessibility", "reduced_motion", false)
		if value is bool:
			reduced_motion = value


func set_reduced_motion(enabled: bool, persist: bool = true) -> Error:
	if persist:
		var config := ConfigFile.new()
		config.set_value("accessibility", "reduced_motion", enabled)
		var error := config.save(SETTINGS_PATH)
		if error != OK:
			return error
	reduced_motion = enabled
	reduced_motion_changed.emit(enabled)
	return OK
