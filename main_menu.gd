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
		scale_text_tree(get_tree().current_scene, 2.0 if is_mobile_browser else 1.0)

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


func scale_text_tree(node: Node, factor: float) -> void:
	if node is Control:
		var control := node as Control
		if control is Label or control is RichTextLabel or control is Button \
		or control is LineEdit or control is TextEdit:
			if not control.has_meta("base_font_size"):
				control.set_meta("base_font_size", control.get_theme_font_size("font_size"))

			var base_size: int = control.get_meta("base_font_size")
			control.add_theme_font_size_override(
				"font_size",
				roundi(base_size * factor)
			)

	for child in node.get_children():
		scale_text_tree(child, factor)