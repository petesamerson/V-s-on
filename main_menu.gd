extends Control
class_name MainMenu

@onready var start_panel_container = $MainScreen/CenterContainer/StartPanelContainer
@onready var cpu_settings_screen: Control = $CpuSettingsScreen
@onready var multiplayer_settings: Control = $MutiplayerSettings
@onready var difficulty_label: Label = $CpuSettingsScreen/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer/CurrentDiff

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	update_mobile_scale()
	cpu_settings_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	cpu_settings_screen.hide()

	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.opponent_joined.connect(_on_opponent_joined)
	NetworkManager.network_error.connect(_on_network_error)
	NetworkManager.game_message_received.connect(_on_lobby_game_message)


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
	get_tree().root.set_meta("online_game", false)
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
	get_tree().root.set_meta("online_game", false)
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


func _on_online_play_pressed() -> void:
	multiplayer_settings.visible = true


@onready var join_code_input: LineEdit = $"MutiplayerSettings/MarginContainer/Panel/JoinCode/VBoxContainer/MarginContainer/JoinCodeEdit"
@onready var join_host_container: MarginContainer = $"MutiplayerSettings/MarginContainer/Panel/JoinHost"
@onready var join_code_container: MarginContainer = $"MutiplayerSettings/MarginContainer/Panel/JoinCode"
@onready var host_code_container: MarginContainer = $"MutiplayerSettings/MarginContainer/Panel/HostCode"

@onready var host_code_input: LineEdit = $"MutiplayerSettings/MarginContainer/Panel/HostCode/VBoxContainer/MarginContainer/HostCodeEdit"
@onready var host_status_label: Label = $"MutiplayerSettings/MarginContainer/Panel/HostCode/VBoxContainer/Label2"
@onready var join_status_label: Label = $"MutiplayerSettings/MarginContainer/Panel/JoinCode/VBoxContainer/Label2"


func _on_join_game_pressed() -> void:
	join_host_container.visible = false
	join_code_container.visible = true
	pass # Replace with function body.


func _on_host_game_pressed() -> void:
	join_host_container.visible = false
	host_code_container.visible = true
	pass # Replace with function body.


func _on_join_room_pressed() -> void:
	join_status_label.text = "Connecting..."
	NetworkManager.join_room(join_code_input.text)


func _on_start_host_pressed() -> void:
	host_status_label.text = "Creating room..."
	NetworkManager.create_room(host_code_input.text)


func _on_room_created(code: String) -> void:
	host_code_input.text = code
	host_code_input.editable = false
	host_status_label.text = "Room created. Share this code and wait for your opponent."


func _on_room_joined(_code: String) -> void:
	join_status_label.text = "Joined room. Waiting for host to start..."


func _on_opponent_joined() -> void:
	var spawn1 := randi_range(0, 5)
	var spawn2 := randi_range(0, 5)

	while spawn2 == spawn1 or abs(spawn2 - spawn1) == 1 or abs(spawn2 - spawn1) == 5:
		spawn2 = randi_range(0, 5)

	NetworkManager.send_game_message({
		"action": "start_game",
		"spawn1": spawn1,
		"spawn2": spawn2
	})

	_start_online_game(1, spawn1, spawn2)

func _on_network_error(message: String) -> void:
	if host_code_container.visible:
		host_status_label.text = message
	elif join_code_container.visible:
		join_status_label.text = message


func _start_online_game(local_player: int, spawn1: int, spawn2: int) -> void:
	get_tree().root.set_meta("play_vs_cpu", false)
	get_tree().root.set_meta("online_game", true)
	get_tree().root.set_meta("local_player", local_player)
	get_tree().root.set_meta("online_spawn1", spawn1)
	get_tree().root.set_meta("online_spawn2", spawn2)
	get_tree().change_scene_to_file("res://base_scene.tscn")


func _on_lobby_game_message(payload: Variant, from_player: int) -> void:
	if from_player != 1 or typeof(payload) != TYPE_DICTIONARY:
		return
	if payload.get("action") != "start_game":
		return

	_start_online_game(
		2,
		int(payload.get("spawn1", 0)),
		int(payload.get("spawn2", 3))
	)