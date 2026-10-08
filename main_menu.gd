extends Control
class_name MainMenu

@onready var start_panel_container = $MainScreen/CenterContainer/StartPanelContainer
@onready var cpu_settings_screen: Control = $CpuSettingsScreen
@onready var difficulty_label: Label = $CpuSettingsScreen/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer/CurrentDiff

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	update_mobile_scale()
	cpu_settings_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	cpu_settings_screen.hide()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

var is_mobile_browser = false

func update_mobile_scale():
	is_mobile_browser = (
		OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)
	if is_mobile_browser:
		ThemeDB.fallback_base_scale = 2.0
		start_panel_container.scale = Vector2(2,2)
	else:
		ThemeDB.fallback_base_scale = 1.0

func _on_new_game_pressed() -> void:
	# get_tree().root.set_meta("play_vs_cpu", true)
	# get_tree().change_scene_to_file("res://base_scene.tscn")
	cpu_settings_screen.show()

func _on_quit_button_pressed() -> void:
	get_tree().quit()

func _on_settings_button_pressed() -> void:
	pass # Replace with function body.


func _on_pass_and_play_pressed() -> void:
	get_tree().root.set_meta("play_vs_cpu", false)
	get_tree().change_scene_to_file("res://base_scene.tscn")



func _on_difficulty_slider_value_changed(value: float) -> void:
	var difficulty := roundi(value) 
	# $DifficultyLabel.text = "Difficulty: %d" % difficulty
	var difficulty_texts := ["Very Easy", "Easy", "Normal", "Hard", "Very Hard"]
	difficulty_label.text = difficulty_texts[difficulty - 1]
	get_tree().root.set_meta("cpu_difficulty", difficulty)


func _on_start_cpu_game_pressed() -> void:
	get_tree().root.set_meta("play_vs_cpu", true)
	get_tree().change_scene_to_file("res://base_scene.tscn")
