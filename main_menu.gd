extends Control
class_name MainMenu

@onready var start_panel_container = $MainScreen/CenterContainer/StartPanelContainer
@onready var cpu_settings_screen: Control = $CpuSettingsScreen
@onready var multiplayer_settings: Control = $MutiplayerSettings
@onready var difficulty_label: Label = $CpuSettingsScreen/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer/CurrentDiff

const GameColors = preload("res://colors.gd")
@onready var player_color_select: OptionButton = \
	$CpuSettingsScreen/MarginContainer/Panel/MarginContainer/VBoxContainer/Player1Row/P1ColorSelect

@onready var enemy_color_select: OptionButton = \
	$CpuSettingsScreen/MarginContainer/Panel/MarginContainer/VBoxContainer/Player2Row/P2ColorSelect

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

	for dropdown in [player_color_select, enemy_color_select]:
		dropdown.clear()
		var control_scale := 2.0 if is_mobile_browser else 1.0
		dropdown.custom_minimum_size = Vector2(100, 40) * control_scale
		var popup = dropdown.get_popup()
		popup.add_theme_font_size_override("font_size", roundi(16 * control_scale))
		popup.add_theme_constant_override("v_separation", roundi(8 * control_scale))

		for color in GameColors.PLAYER_PALETTE:
			var swatch := Image.create(
				roundi(60 * control_scale), roundi(24 * control_scale), false, Image.FORMAT_RGBA8
			)
			swatch.fill(color)

			var texture := ImageTexture.create_from_image(swatch)
			dropdown.add_icon_item(texture, "")

	player_color_select.select(GameColors.selected_color_indices[0])
	enemy_color_select.select(GameColors.selected_color_indices[1])

	player_color_select.item_selected.connect(
		_on_player_color_selected
	)
	enemy_color_select.item_selected.connect(
		_on_enemy_color_selected
	)
	get_viewport().size_changed.connect(_on_mobile_viewport_resized)

func _on_mobile_viewport_resized() -> void:
	update_mobile_scale()

func _on_player_color_selected(index: int) -> void:
	GameColors.set_player_color(1, index)
	refresh_color_options()


func _on_enemy_color_selected(index: int) -> void:
	GameColors.set_player_color(2, index)
	refresh_color_options()

func refresh_color_options() -> void:
	var dropdowns: Array[OptionButton] = [
		player_color_select,
		enemy_color_select
	]

	for dropdown in dropdowns:
		for color_index in range(dropdown.item_count):
			var taken := false

			for other in dropdowns:
				if other != dropdown and other.selected == color_index:
					taken = true
					break

			dropdown.set_item_disabled(color_index, taken)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


var is_mobile_browser = false

func update_mobile_scale():
	is_mobile_browser = (
		OS.has_feature("android")
		or OS.has_feature("ios")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)
	if is_mobile_browser:
		scale_text_tree(get_tree().current_scene, 2.0 if is_mobile_browser else 1.0)
	# Size the control itself so its icon and hit area share the same bounds.
	var control_scale := 2.0 if is_mobile_browser else 1.0
	for close_button: Button in [
		$CpuSettingsScreen/MarginContainer/Panel/CloseGameSettings,
		$MutiplayerSettings/MarginContainer/Panel/CloseMultiSettings,
	]:
		var side := 54.0 * control_scale
		close_button.scale = Vector2.ONE
		close_button.expand_icon = true
		close_button.custom_minimum_size = Vector2(side, side)
		close_button.offset_left = -side
		close_button.offset_top = 0.0
		close_button.offset_right = 0.0
		close_button.offset_bottom = side

func _on_new_game_pressed() -> void:
	# get_tree().root.set_meta("play_vs_cpu", true)
	# get_tree().change_scene_to_file("res://base_scene.tscn")
	cpu_settings_screen.show()

func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _on_settings_button_pressed() -> void:
	if get_tree().current_scene.has_node("SettingsOverlay"):
		return

	var settings := preload("res://settings_menu.tscn").instantiate()
	settings.name = "SettingsOverlay"
	get_tree().current_scene.add_child(settings)


func _on_pass_and_play_pressed() -> void:
	get_tree().root.set_meta("online_game", false)
	get_tree().root.set_meta("play_vs_cpu", false)
	get_tree().change_scene_to_file("res://base_scene.tscn")



func _on_difficulty_slider_value_changed(value: float) -> void:
	var selected_difficulty := clampi(roundi(value), 1, 6)

	var difficulty_names := [
		"Very Easy",
		"Easy",
		"Normal",
		"Hard",
		"Very Hard",
		"Expert",
	]

	difficulty_label.text = difficulty_names[
		selected_difficulty - 1
	]

	get_tree().root.set_meta(
		"cpu_difficulty",
		selected_difficulty
	)

func _on_start_cpu_game_pressed() -> void:
	var slider := get_node(
		"CpuSettingsScreen/MarginContainer/Panel/"
		+ "MarginContainer/VBoxContainer/HBoxContainer/"
		+ "Difficulty Slider"
	) as HSlider

	_on_difficulty_slider_value_changed(slider.value)

	get_tree().root.set_meta("play_vs_cpu", true)
	get_tree().root.set_meta("online_game", false)
	get_tree().change_scene_to_file("res://base_scene.tscn")


func scale_text_tree(node: Node, factor: float) -> void:
	if node is Control:
		var control := node as Control
		var size_names: Array[String] = []

		if node is RichTextLabel:
			size_names = [
				"normal_font_size",
				"bold_font_size",
				"italics_font_size",
				"bold_italics_font_size",
				"mono_font_size"
			]
		elif node is Label or node is Button \
		or node is LineEdit or node is TextEdit:
			size_names = ["font_size"]

		for size_name in size_names:
			var meta_name := "menu_base_" + size_name

			if not control.has_meta(meta_name):
				control.set_meta(
					meta_name,
					control.get_theme_font_size(size_name)
				)

			var base_size: int = control.get_meta(meta_name)
			control.add_theme_font_size_override(
				size_name,
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

func _on_close_game_settings_pressed() -> void:
	cpu_settings_screen.visible = false


func _on_close_multi_settings_pressed() -> void:
	multiplayer_settings.visible = false


func _on_how_to_play_pressed() -> void:
	get_tree().change_scene_to_file("res://tutorial.tscn")
