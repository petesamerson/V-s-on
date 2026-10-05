extends Control
class_name MainMenu

@onready var start_panel_container = $MainScreen/CenterContainer/StartPanelContainer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


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
		start_panel_container.scale = Vector2(4,4)
		# selection_panel.pivot_offset = selection_panel.size
	else:
		pass

func _on_new_game_pressed() -> void:
	get_tree().root.set_meta("play_vs_cpu", true)
	get_tree().change_scene_to_file("res://base_scene.tscn")

func _on_quit_button_pressed() -> void:
	get_tree().quit()

func _on_settings_button_pressed() -> void:
	pass # Replace with function body.


func _on_pass_and_play_pressed() -> void:
	get_tree().root.set_meta("play_vs_cpu", false)
	get_tree().change_scene_to_file("res://base_scene.tscn")
