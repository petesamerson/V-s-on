extends CanvasLayer

@onready var controls: VBoxContainer = (
	$Overlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer
)

@onready var music_slider: HSlider = controls.get_node("MusicSlider")
@onready var effects_slider: HSlider = controls.get_node("EffectsSlider")
@onready var reduce_animation: CheckButton = controls.get_node("ReduceAnimation")
@onready var close_button: Button = controls.get_node("CloseButton")


func _ready() -> void:
	# Populate controls without triggering their change signals.
	music_slider.set_value_no_signal(AppSettings.music_volume)
	effects_slider.set_value_no_signal(AppSettings.effects_volume)
	reduce_animation.set_pressed_no_signal(AppSettings.reduce_animation)

	music_slider.value_changed.connect(AppSettings.set_music_volume)
	effects_slider.value_changed.connect(AppSettings.set_effects_volume)
	reduce_animation.toggled.connect(AppSettings.set_reduce_animation)
	close_button.pressed.connect(_close)

	music_slider.grab_focus()


func _close() -> void:
	AppSettings.save_settings()
	queue_free()