extends CanvasLayer

@onready var controls: VBoxContainer = (
	$Overlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer
)

@onready var music_slider: HSlider = controls.get_node("MusicSlider")
@onready var effects_slider: HSlider = controls.get_node("EffectsSlider")
@onready var reduce_animation: CheckButton = controls.get_node("ReduceAnimation")
@onready var close_button: Button = (
	$Overlay/CenterContainer/PanelContainer/PanelContent/CloseButton
)
@onready var low_graphics: CheckButton = controls.get_node("LowGraphics")
@onready var display_mode_label: Label = controls.get_node("DisplayModeLabel")
@onready var display_mode_button: OptionButton = controls.get_node("DisplayMode")
@onready var game_ui_size_label: Label = controls.get_node("GameUISizeLabel")
@onready var game_ui_size_slider: HSlider = controls.get_node("GameUISizeSlider")

func _ready() -> void:
	# Populate controls without triggering their change signals.
	music_slider.set_value_no_signal(AppSettings.music_volume)
	effects_slider.set_value_no_signal(AppSettings.effects_volume)
	reduce_animation.set_pressed_no_signal(AppSettings.reduce_animation)

	music_slider.value_changed.connect(AppSettings.set_music_volume)
	effects_slider.value_changed.connect(AppSettings.set_effects_volume)
	reduce_animation.toggled.connect(AppSettings.set_reduce_animation)
	close_button.pressed.connect(_close)
	low_graphics.set_pressed_no_signal(AppSettings.low_graphics)
	low_graphics.toggled.connect(AppSettings.set_low_graphics)

	var show_display_settings := AppSettings.supports_display_settings()
	display_mode_label.visible = show_display_settings
	display_mode_button.visible = show_display_settings

	display_mode_button.clear()
	display_mode_button.add_item("Windowed")
	display_mode_button.add_item("Fullscreen")
	display_mode_button.add_item("Borderless Fullscreen")

	display_mode_button.select(AppSettings.display_mode)
	display_mode_button.item_selected.connect(AppSettings.set_display_mode)

	music_slider.grab_focus()

	get_viewport().size_changed.connect(_update_text_scale)

	game_ui_size_slider.min_value = (
		AppSettings.get_game_ui_scale_min() * 100.0
	)
	game_ui_size_slider.max_value = (
		AppSettings.get_game_ui_scale_max() * 100.0
	)
	game_ui_size_slider.step = 5.0

	var percentage = AppSettings.get_game_ui_scale() * 100.0
	game_ui_size_slider.set_value_no_signal(percentage)
	_update_game_ui_size_label(percentage)

	game_ui_size_slider.value_changed.connect(_on_game_ui_size_changed)
	_update_text_scale()

func _on_game_ui_size_changed(percentage: float) -> void:
	_update_game_ui_size_label(percentage)
	AppSettings.set_game_ui_scale(percentage / 100.0)


func _update_game_ui_size_label(percentage: float) -> void:
	game_ui_size_label.text = "In-Game UI Size: %d%%" % roundi(percentage)

func _close() -> void:
	AppSettings.save_settings()
	queue_free()

func _update_text_scale() -> void:
	UITextScale.apply(
		$Overlay,
		UITextScale.current_factor(get_viewport())
	)
