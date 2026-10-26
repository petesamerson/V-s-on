extends Node

signal settings_changed

const SAVE_PATH := "user://settings.cfg"
const MAX_GAIN_DB := 5.0

# About 71% preserves the current listening level.
var music_volume: float = 71.0
var effects_volume: float = 71.0
var reduce_animation: bool = false


func _ready() -> void:
	var config := ConfigFile.new()

	if config.load(SAVE_PATH) == OK:
		music_volume = clampf(
			float(config.get_value("audio", "music", 71.0)),
			0.0, 100.0
		)
		effects_volume = clampf(
			float(config.get_value("audio", "effects", 71.0)),
			0.0, 100.0
		)
		reduce_animation = bool(
			config.get_value("visuals", "reduce_animation", false)
		)

	apply_audio()


func apply_audio() -> void:
	_apply_bus("Music", music_volume)
	_apply_bus("Effects", effects_volume)


func _apply_bus(bus_name: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)

	if index < 0:
		push_warning("Missing audio bus: " + bus_name)
		return

	AudioServer.set_bus_mute(index, volume <= 0.0)

	if volume > 0.0:
		var gain := (volume / 100.0) * db_to_linear(MAX_GAIN_DB)
		AudioServer.set_bus_volume_db(index, linear_to_db(gain))


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 100.0)
	apply_audio()
	settings_changed.emit()


func set_effects_volume(value: float) -> void:
	effects_volume = clampf(value, 0.0, 100.0)
	apply_audio()
	settings_changed.emit()


func set_reduce_animation(value: bool) -> void:
	reduce_animation = value
	settings_changed.emit()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("visuals", "reduce_animation", reduce_animation)

	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save settings: " + error_string(error))