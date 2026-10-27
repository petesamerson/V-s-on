extends Node

signal settings_changed

const SAVE_PATH := "user://settings.cfg"
const MAX_GAIN_DB := 5.0

# About 71% preserves the current listening level.
var music_volume: float = 71.0
var effects_volume: float = 71.0
var reduce_animation: bool = false
var low_graphics: bool = false

signal game_ui_scale_changed

var desktop_game_ui_scale: float = 1.0
var mobile_game_ui_scale: float = 1.0

enum DisplayMode {
	WINDOWED,
	FULLSCREEN,
	BORDERLESS,
}

var display_mode: int = DisplayMode.WINDOWED

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
		low_graphics = bool(
			config.get_value("visuals", "low_graphics", false)
		)
		display_mode = clampi(
			int(config.get_value("display", "mode", DisplayMode.WINDOWED)),
			DisplayMode.WINDOWED,
			DisplayMode.BORDERLESS
		)
		desktop_game_ui_scale = clampf(
			float(config.get_value("ui", "desktop_game_scale", 1.0)),
			0.75,
			1.5
		)
		mobile_game_ui_scale = clampf(
			float(config.get_value("ui", "mobile_game_scale", 1.0)),
			1.0,
			1.25
		)

	apply_audio()
	apply_display()

func is_mobile_platform() -> bool:
	return (
		OS.has_feature("android")
		or OS.has_feature("ios")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)


func get_game_ui_scale() -> float:
	if is_mobile_platform():
		return mobile_game_ui_scale
	return desktop_game_ui_scale


func get_game_ui_scale_min() -> float:
	return 1.0 if is_mobile_platform() else 0.75


func get_game_ui_scale_max() -> float:
	return 1.25 if is_mobile_platform() else 1.5


func set_game_ui_scale(value: float) -> void:
	var new_scale := clampf(
		value,
		get_game_ui_scale_min(),
		get_game_ui_scale_max()
	)

	if is_equal_approx(new_scale, get_game_ui_scale()):
		return

	if is_mobile_platform():
		mobile_game_ui_scale = new_scale
	else:
		desktop_game_ui_scale = new_scale

	game_ui_scale_changed.emit()

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

func set_low_graphics(value: bool) -> void:
	low_graphics = value
	settings_changed.emit()

func supports_display_settings() -> bool:
	return OS.has_feature("pc") and not OS.has_feature("web")


func apply_display() -> void:
	if not supports_display_settings():
		return

	match display_mode:
		DisplayMode.WINDOWED:
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED
			)
			DisplayServer.window_set_flag(
				DisplayServer.WINDOW_FLAG_BORDERLESS, false
			)

		DisplayMode.FULLSCREEN:
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			)

		DisplayMode.BORDERLESS:
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_FULLSCREEN
			)


func set_display_mode(value: int) -> void:
	display_mode = clampi(
		value,
		DisplayMode.WINDOWED,
		DisplayMode.BORDERLESS
	)
	apply_display()
	settings_changed.emit()

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("visuals", "reduce_animation", reduce_animation)
	config.set_value("visuals", "low_graphics", low_graphics)
	config.set_value("display", "mode", display_mode)
	config.set_value("ui", "desktop_game_scale", desktop_game_ui_scale)
	config.set_value("ui", "mobile_game_scale", mobile_game_ui_scale)

	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save settings: " + error_string(error))