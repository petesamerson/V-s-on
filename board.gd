extends TileMapLayer
class_name Board

@export var camera: Camera2D
@onready var tilemap = $TileMap
@onready var capture_feed: VBoxContainer = $"../TurnLayer/CaptureFeed/MarginContainer/FeedContent/FeedEntries"
@onready var capture_feed_panel: PanelContainer = $"../TurnLayer/CaptureFeed"
@onready var turn_label: RichTextLabel = $"../TurnLayer/StatMargin/StatContainer/TurnLabel"
@onready var core_label: RichTextLabel = $"../TurnLayer/StatMargin/StatContainer/CoreLabel"
@onready var win_label: Label = $"../TurnLayer/WinLabel"
@onready var your_turn_label: Label = $"../TurnLayer/YourTurnLabel"
@onready var turn_menu = $"../TurnLayer/PlayerSwitchOverlay"
@onready var selection_panel= $"../TurnLayer/SelectionPanel"
@onready var settings_cover= $"../TurnLayer/SettingsCover"
@onready var stat_container: VBoxContainer = $"../TurnLayer/StatMargin/StatContainer"
@export var capture_texture: Texture2D

const CAPTURE_FEED_TEXTURE: Texture2D = preload("res://sprites/capturefeed.png")

var Tiles = preload("res://tiles.gd")
const GameColors = preload("res://colors.gd")

var board_center = Vector2i(10, 10)
var board_size = 10
var board_tiles: Array[Vector2i] = []

var board_effects: Node2D
var map_border: Node2D

var turn = 1
var current_player: int = 1

var play_vs_cpu: bool = false
var online_game := false
var online_disconnected: bool = false
var local_player := 1
var match_winner = 0

var game_setup_complete := false
var cpu_turn_in_progress := false
var _cpu_feedback_active: bool = false
var _cpu_feedback_timer: float = 0.0
var _cpu_feedback_dots: int = 1

var player_fills: Array[TileMapLayer] = []
var player_powered_fills: Array[TileMapLayer] = []
var player_outlines: Array[TileMapLayer] = []
var player_selected_outlines: Array[TileMapLayer] = []
var player_move_fills: Array[TileMapLayer] = []
var core_attacker_highlights: TileMapLayer

@export var white_fill_source_id: int
@export var white_outline_source_id: int

@export var tutorial_mode: bool = false

signal tutorial_piece_selected(piece: Piece)
signal tutorial_piece_moved(piece: Piece)
signal tutorial_turn_completed


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.z_index = 0
	board_tiles = get_hexagon_tiles(board_center, board_size)
	for c in board_tiles:
		set_cell(c, Tiles.BLACK, Vector2i(0,0))

	board_effects = preload("res://board_effects.gd").new()
	board_effects.board = self
	board_effects.name = "BoardEffects"
	add_child(board_effects)
	board_effects.z_index = 2

	map_border = preload("res://map_border.gd").new()
	map_border.board = self
	map_border.z_index = 3
	add_child(map_border)
	map_border.rebuild()

	call_deferred("spawn_all_pieces")

	get_viewport().size_changed.connect(_on_mobile_viewport_resized)

	create_player_highlight_layers(2)
	core_attacker_highlights = create_highlight_layer(
		"CoreAttackerHighlights",
		Color.WHITE
	)
	core_attacker_highlights.z_index = 3
	move_child(board_effects, get_child_count() - 1)
	instantiate_turn_menu()
	instantiate_core_menu()
	create_capture_hud()

	intialize_drawn_sprite_nodes()
	update_mobile_scale()


	capture_feed_panel.hide()

	play_vs_cpu = get_tree().root.get_meta("play_vs_cpu", false)

	online_game = get_tree().root.get_meta("online_game", false)
	local_player = int(get_tree().root.get_meta("local_player", 1))

	if tutorial_mode:
		play_vs_cpu = false
		online_game = false

	if online_game:
		NetworkManager.game_message_received.connect(_on_network_game_message)
		NetworkManager.opponent_disconnected.connect(_on_opponent_disconnected)
		NetworkManager.connection_closed.connect(_on_connection_closed)
		NetworkManager.network_error.connect(_on_online_network_error)
	elif play_vs_cpu:
		intialize_cpu_player(2)

func _on_mobile_viewport_resized() -> void:
	update_mobile_scale()
	

var is_mobile_browser: bool = false
var ui_scale: float = 1.0


func mobile_text_scale() -> float:
	return UITextScale.current_factor(get_viewport())

func update_mobile_scale():
	is_mobile_browser = (
		OS.has_feature("android") \
		or OS.has_feature("ios") \
		or OS.has_feature("web_android") \
		or OS.has_feature("web_ios")
	)
	var pause_button := get_node("../TurnLayer/MarginContainer/VBoxContainer/Pause") as Button
	var pause_side := 80.0 * (2.0 if is_mobile_browser else 1.0)
	pause_button.expand_icon = true
	pause_button.custom_minimum_size = Vector2(pause_side, pause_side)
	pause_button.add_theme_constant_override("icon_max_width", roundi(pause_side - 16.0))
	pause_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	if is_mobile_browser:
		# selection_panel.scale = Vector2(2.5,2.5)
		# scale_text_tree(get_tree().current_scene, 2.0 if is_mobile_browser else 1.0)
		scale_text_tree(get_tree().current_scene, mobile_text_scale())
		resize_selection_image_to_text()
		selection_panel.pivot_offset = selection_panel.size
	else:
		# scale_text_tree(get_tree().current_scene, 2.0 if true else 1.0)
		# selection_panel.scale = Vector2(0.8,0.8)
		selection_panel.pivot_offset = selection_panel.size
		resize_selection_image_to_text()

	ui_scale = 2.0 if (
		OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	) else 1.0
	
	


func resize_selection_image_to_text() -> void:
	var margin := selection_panel.get_child(0) as MarginContainer
	var root := margin.get_child(0) as VBoxContainer
	var row := root.get_child(0) as HBoxContainer
	var text_column := row.get_node("VBoxContainer") as VBoxContainer
	var image_panel := row.get_node("PanelContainer") as PanelContainer
	var image_magin := image_panel.get_child(0) as MarginContainer
	var image_rect := image_magin.get_child(0) as TextureRect

	await get_tree().process_frame

	var side := maxf(text_column.size.y, 120.0)
	image_rect.custom_minimum_size = Vector2(side*2/3, side*2/3)

func scale_text_tree(node: Node, factor: float) -> void:
	UITextScale.apply(node, factor)


func intialize_drawn_sprite_nodes():
	rotate_sprites = Node2D.new()
	rotate_sprites.z_index = 5
	add_child(rotate_sprites)

	capture_sprites = Node2D.new()
	capture_sprites.z_index = 5
	add_child(capture_sprites)

func draw_player_vision(cell: Vector2i, player_id: int) -> void:
	if not cell_in_board(cell):
		return

	var i := player_id - 1

	player_fills[i].set_cell(
		cell, white_fill_source_id, Vector2i.ZERO
	)
	player_outlines[i].set_cell(
		cell, white_outline_source_id, Vector2i.ZERO
	)


func draw_selected_vision(cell: Vector2i, player_id: int) -> void:
	if not cell_in_board(cell):
		return

	player_selected_outlines[player_id - 1].set_cell(
		cell, white_outline_source_id, Vector2i.ZERO
	)


func draw_potential_move(cell: Vector2i, player_id: int) -> void:
	if not cell_in_board(cell):
		return

	player_move_fills[player_id - 1].set_cell(
		cell, white_fill_source_id, Vector2i.ZERO
	)
	draw_selected_vision(cell, player_id)

func instantiate_turn_menu():
	# Apply the styling wrapper dynamically without changing the original variable
	turn_label.bbcode_enabled = true
	turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	turn_label.fit_content = true

	var color_hex := GameColors.powered_color(current_player).to_html(false)
	turn_label.text = (
		"[outline_size=10][outline_color=black][b]"
		+ "[color=#%s]Player %d's Turn[/color][/b]"
		% [color_hex, current_player]
	)

	turn_menu.hide()

var cpu_player: CPUPlayer

func intialize_cpu_player(player_number: int):
	if player_number == 1:
		print("CPU Player 1")
	elif player_number == 2:
		print("CPU Player 2")
	cpu_player = CPUPlayer.new()
	cpu_player.player_number = 2
	cpu_player.difficulty = int(get_tree().root.get_meta("cpu_difficulty", 3))
	add_child(cpu_player)
	cpu_player.setup(self)

func resize_text_overlay():
	update_turn_text()
	update_core_text()


func instantiate_core_menu():
	# Apply the styling wrapper dynamically without changing the original variable
	core_label.bbcode_enabled = true
	core_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	core_label.fit_content = true
	core_label.size = Vector2(400, 100)


	var raw_message = "Core Seen By 6 Pieces"
	core_label.text = "[outline_size=10][outline_color=black][b][color=white]%s[/color][/b]" % raw_message

	# core_menu.hide()

func clear_player_highlights() -> void:
	for layers in [
		player_fills,
		player_powered_fills,
		player_outlines,
		player_selected_outlines,
		player_move_fills
	]:
		for layer in layers:
			layer.clear()		

func redraw_selected_highlights() -> void:
	for layer in player_selected_outlines:
		layer.clear()

	for layer in player_move_fills:
		layer.clear()

	for piece in pieces_container.get_children():
		if piece is Piece and piece.selected:
			for cell in piece.cur_vision:
				draw_selected_vision(cell, piece.owned_player)

			for cell in piece.cur_moves:
				draw_potential_move(cell, piece.owned_player)


func create_player_highlight_layers(player_count: int) -> void:
	for layers in [
		player_fills,
		player_powered_fills,
		player_outlines,
		player_move_fills,
		player_selected_outlines
	]:
		for layer in layers:
			remove_child(layer)
			layer.queue_free()
		layers.clear()

	for i in range(player_count):
		var player_id := i + 1
		var dark := GameColors.player_color(player_id).darkened(0.5)
		var light := GameColors.powered_color(player_id)
		var powered_vision_color := dark.lerp(light, 0.18)

		player_fills.append(
			create_highlight_layer("VisionFill%d" % player_id, dark)
		)

		player_powered_fills.append(
			create_highlight_layer(
				"PoweredVisionFill%d" % player_id,
				powered_vision_color
			)
		)

		player_outlines.append(
			create_highlight_layer("VisionOutline%d" % player_id, dark)
		)

		player_move_fills.append(
			create_highlight_layer("MoveFill%d" % player_id, light)
		)

		player_selected_outlines.append(
			create_highlight_layer("SelectedOutline%d" % player_id, light)
		)



func create_highlight_layer(
	layer_name: String,
	color: Color
) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tile_set
	layer.z_index = 1
	layer.modulate = color
	add_child(layer)
	return layer

func refresh_powered_vision() -> void:
	for layer in player_powered_fills:
		layer.clear()

	var viewer := get_viewer_player()
	var layer := player_powered_fills[viewer - 1]

	for piece in player_pieces[viewer - 1]:
		if not piece.powered:
			continue

		for cell in piece.cur_vision:
			if cell_in_board(cell):
				layer.set_cell(
					cell,
					white_fill_source_id,
					Vector2i.ZERO
				)


func update_turn_text() -> void:
	_refresh_turn_label()
	update_mobile_scale()
	update_selection_panel_colors()


func _cpu_is_thinking() -> bool:
	return (
		match_winner == 0
		and not online_game
		and is_instance_valid(cpu_player)
		and current_player == cpu_player.player_number
		and cpu_player.is_thinking()
	)


func _refresh_turn_label() -> void:
	var color_hex := GameColors.powered_color(current_player).to_html(false)
	var message := "Player %d's Turn" % current_player

	if match_winner != 0:
		message = "Game Over"
	elif _cpu_is_thinking():
		message = "CPU thinking" + ".".repeat(_cpu_feedback_dots)

	turn_label.text = (
		"[outline_size=10][outline_color=black][b]"
		+ "[color=#%s]%s[/color][/b]" % [color_hex, message]
	)


func _update_cpu_feedback(delta: float) -> void:
	var thinking: bool = _cpu_is_thinking()

	if thinking != _cpu_feedback_active:
		_cpu_feedback_active = thinking
		_cpu_feedback_timer = 0.0
		_cpu_feedback_dots = 1
		_refresh_turn_label()

	if not thinking:
		return

	_cpu_feedback_timer += delta

	if _cpu_feedback_timer >= 0.4:
		_cpu_feedback_timer = fmod(_cpu_feedback_timer, 0.4)
		_cpu_feedback_dots = (_cpu_feedback_dots % 3) + 1
		_refresh_turn_label()

func display_turn_message():
	var text_timer := Timer.new()
	text_timer.wait_time = 1.0
	text_timer.one_shot = true
	text_timer.timeout.connect(_on_turn_message_timer_timeout)
	your_turn_label.text = "Your Turn"
	# your_turn_label.modulate = Color.RED
	add_child(text_timer)
	your_turn_label.visible = true
	text_timer.start()

func _on_turn_message_timer_timeout():
	your_turn_label.text = ""
	your_turn_label.visible = false

func display_winner(winner):
	if match_winner != 0:
		return

	match_winner = winner
	_refresh_turn_label()
	if not online_game and not tutorial_mode:
		OfflineSave.clear_match()
	win_label.text = "Player %d WINS!" % winner
	win_label.modulate = GameColors.powered_color(winner)
	win_label.visible = true

func update_selection_panel(selectedPiece: Piece):
	var margin_container = selection_panel.get_child(0) as MarginContainer
	var v_box_root = margin_container.get_child(0) as VBoxContainer
	var h_box = v_box_root.get_child(0) as HBoxContainer
	for child in h_box.get_children():
		if child is PanelContainer:
			var tr = child.get_child(0).get_child(0) as TextureRect
			tr.texture = selectedPiece.sprite.texture
			tr.self_modulate = selectedPiece.sprite.modulate

			# Share the material so the shimmer stays synchronized.
			tr.material = selectedPiece.sprite.material

			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if child is VBoxContainer:
			for label in child.get_children():
				if(label is Label):
					match label.name:
						"PieceName":
							label.text = selectedPiece.getTypeString()
						"Description":
							label.text = selectedPiece.getTypedDescription()
						"MoveRange":
							label.text = "MoveRange: " + str(selectedPiece.move_range)
						"VisionRange":
							label.text = "VisionRange: " + str(selectedPiece.vision_range)
	update_selection_panel_colors(selectedPiece.owned_player)
			
func update_selection_panel_colors(player_id: int = -1) -> void:
	if player_id < 1:
		player_id = get_viewer_player()

	var tint: Color = GameColors.player_color(player_id)
	var text_color: Color = tint.lerp(Color.WHITE, 0.55)

	var existing: StyleBox = selection_panel.get_theme_stylebox("panel")
	var panel_style: StyleBoxFlat

	if existing is StyleBoxFlat:
		panel_style = existing.duplicate() as StyleBoxFlat
	else:
		panel_style = StyleBoxFlat.new()
		panel_style.set_corner_radius_all(8)

	panel_style.bg_color = Color(tint.darkened(0.8), 0.95)
	panel_style.border_color = Color(tint, 0.8)
	panel_style.set_border_width_all(2)

	selection_panel.add_theme_stylebox_override(
		"panel", panel_style
	)

	for node in selection_panel.find_children("*", "Label", true, false):
		var label := node as Label
		label.add_theme_color_override("font_color", text_color)


func determine_winner() -> int:
	var winner = 0
	var cores: Array[CorePiece] = []
	for piece_list in player_pieces:
		for p in piece_list:
			if(p is CorePiece):
				cores.append(p as CorePiece)
		
	if(cores.size() == 1):
		return cores[0].owned_player
	
	var loser = 0
	for core in cores:
		if(core.power_count == 0):
			loser = core.owned_player
	if loser == 0:
		return 0

	winner = 2 if loser == 1 else 1
	
	return winner

func update_core_text(numberCanSeeCore : int = -1):
	# var viewport_size = get_viewport().get_visible_rect().size
	# core_label.position.x  5
	# core_label.position.y = 5

	if(numberCanSeeCore != -1):
		var raw_message = "Core Seen By " +  str(numberCanSeeCore) +  " Pieces"
		core_label.text = "[outline_size=10][outline_color=black][b][color=white]%s[/color][/b]" % raw_message

	update_mobile_scale()


# Called every frame. 'delta' is the elapsed time since the previous frame.
var timer := 0.0
var interval := 0.25 #seconds

func _process(delta: float) -> void:
	timer += delta
	if timer >= interval:
		timer = 0.0
	_update_cpu_feedback(delta)
		# animate_board()

@onready var pieces_container = $Pieces
@onready var tilemap_layer = $TileMapLayer
@export var piece_scene: PackedScene
@export var core_piece_scene: PackedScene
@export var eye_piece_scene: PackedScene
@export var tower_piece_scene: PackedScene
@export var hop_piece_scene: PackedScene
@export var triangle_odd_piece_scene: PackedScene
@export var triangle_even_piece_scene: PackedScene

@onready var player_pieces = [[],[]]
var player_last_moves: Array[Piece] = []
var last_capture_capturer_ids: Array[int] = [-1, -1]
var player_vision_tiles: Array[Array] = [[],[]]

var player_captures: Array[Array] = [[], []]
var capture_rows: Array[HFlowContainer] = []

func spawn_all_pieces():
	clear_all_power_lines()

	if not online_game and not tutorial_mode:
		if not OfflineSave.pending_resume.is_empty():
			var saved: Dictionary = OfflineSave.pending_resume
			OfflineSave.pending_resume = {}

			if not restore_offline_checkpoint(saved):
				push_error("The saved match could not be restored.")
				get_tree().change_scene_to_file("res://main_menu.tscn")
			return
	var num1: int
	var num2: int
	if tutorial_mode:
		num1 = 0
		num2 = 3
	elif online_game:
		num1 = int(get_tree().root.get_meta("online_spawn1", 0))
		num2 = int(get_tree().root.get_meta("online_spawn2", 3))
	else:
		num1 = randi_range(0, 5)
		num2 = randi_range(0, 5)
		while num2 == num1 or abs(num2 - num1) == 1 or abs(num2 - num1) == 5:
			num2 = randi_range(0, 5)
	# num1 = 0
	# num2 = 3
	var spawn1 = get_line_from_center(Vector2i(10,10), num1, 6)
	var spawn2 = get_line_from_center(Vector2i(10,10), num2, 6)

	
	spawn_player_location(spawn1.get(spawn1.size() - 1), 1)
	spawn_player_location(spawn2.get(spawn2.size() - 1), 2)

	update_all_piece_vision()
	move_camera_to_core()
	game_setup_complete = true
	update_core_power()
	board_effects.play_setup()
	save_offline_checkpoint()

func get_possible_spawn_locations() -> Array[Vector2i]:
	var locations: Array[Vector2i] = []

	for direction in range(6):
		var line: Array[Vector2i] = get_line_from_center(Vector2i(10, 10), direction, 6)
		if not line.is_empty():
			locations.append(line[line.size() - 1])

	return locations

func spawn_player_location(center: Vector2i, player: int):

	var core_piece := core_piece_scene.instantiate() as CorePiece
	core_piece.owned_player = player
	player_pieces[player - 1].append(core_piece)
	pieces_container.add_child(core_piece)
	core_piece.setup(center, self)
	update_selection_panel(core_piece)
	

	var positions = [
		Vector2i(center.x-1,center.y),
		Vector2i(center.x+1,center.y)
	]
	for pos in positions:
		var piece := eye_piece_scene.instantiate() as EyePiece
		piece.owned_player = player
		piece.z_index = 4
		player_pieces[player - 1].append(piece)
		pieces_container.add_child(piece)
		piece.setup(pos, self)

	

	var hop_piece_locations: Array[Vector2i] = []
	for i in range(6):
		hop_piece_locations.append(get_line_end_from_center(center, i, 3))
	for i in range(6):
		var hop_piece := hop_piece_scene.instantiate() as HopPiece
		hop_piece.owned_player = player
		player_pieces[player - 1].append(hop_piece)
		pieces_container.add_child(hop_piece)
		hop_piece.setup(
			hop_piece_locations[i],
			self
		)

	var tri_odd_piece_locations: Array[Vector2i] = []
	for i in range(3):
		# tri_odd_piece_locations.append(get_line_end_from_center(center, i*2, 2))
		var line = get_line_from_center(center, i*2, 2)
		tri_odd_piece_locations.append(line[2])
	for i in range(3):
		var tri_odd_piece := triangle_odd_piece_scene.instantiate() as TriangleOddPiece
		tri_odd_piece.owned_player = player
		player_pieces[player - 1].append(tri_odd_piece)
		pieces_container.add_child(tri_odd_piece)
		tri_odd_piece.setup(
			tri_odd_piece_locations[i],
			self
		)

	var tri_even_piece_locations: Array[Vector2i] = []
	for i in range(3):
		var line = get_line_from_center(center, 1 + i*2, 2)
		tri_even_piece_locations.append(line[2])
		# tri_even_piece_locations.append(get_line_end_from_center(center, 1 + i*2, 2))
	for i in range(3):
		var tri_even_piece := triangle_even_piece_scene.instantiate() as TriangleEvenPiece
		tri_even_piece.owned_player = player
		player_pieces[player - 1].append(tri_even_piece)
		pieces_container.add_child(tri_even_piece)
		tri_even_piece.setup(
			tri_even_piece_locations[i],
			self
		)

	var rotate_piece_locations: Array[Vector2i] = []
	for i in range(12):
		var line = get_line_from_center(center, 1 + i*2, 2)
		# rotate_piece_locations.append(line[line.size() - 1])
		var first_axis = get_line_from_center(center, i, 2)
		var second_axis = get_line_from_center(center, (i + 1) % 6, 2)
		

		if(first_axis != null and second_axis != null):
			var connect_line = hex_line(
				first_axis[first_axis.size()-1], 
				second_axis[second_axis.size()-1]
			)
			var potential_new_move = connect_line[(connect_line.size())/2]
			rotate_piece_locations.append(potential_new_move)

	for i in rotate_piece_locations.size():
		var rotate_piece := tower_piece_scene.instantiate() as TowerRotatePiece
		rotate_piece.owned_player = player
		
		player_pieces[player - 1].append(rotate_piece)
		pieces_container.add_child(rotate_piece)
		rotate_piece.setup(
			rotate_piece_locations[i],
			self
		)
		if(i!=(rotate_piece_locations.size()-1)):
			rotate_piece.cur_direction = (5 + i)%5
		rotate_piece.update_sprite_rotation()
		rotate_piece.draw_vision_change()


# func remove_piece(piece: Piece):
# 	player_pieces[piece.owned_player - 1].erase(piece)
# 	pieces_container.remove_child(piece)

var play_capture: bool = false
var enemy_captured_this_turn = false

func remove_piece(piece: Piece) -> void:
	if cpu_player == null or current_player != cpu_player.player_number:
		play_capture = true
		queue_game_sound(PLAYER_CAPTURE_SOUND, true)
	else: 
		enemy_captured_this_turn = true

	var capturer_index := current_player - 1

	player_captures[capturer_index].append({
		"texture": piece.sprite.texture,
		"name": piece.getTypeString(),
		"cell": piece.get_cur_pos()
	})
	add_captured_piece_icon(capturer_index, piece)

	player_pieces[piece.owned_player - 1].erase(piece)
	pieces_container.remove_child(piece)
	piece.queue_free()

func create_capture_hud() -> void:
	var hud := VBoxContainer.new()
	hud.name = "CapturedPiecesHUD"
	hud.add_theme_constant_override("separation", round(8 * ui_scale))
	stat_container.add_child(hud)

	for player_id in range(1, 3):

		var panel := PanelContainer.new()
		panel.name = "P%d" % player_id
		panel.custom_minimum_size = Vector2(170, 0)
		hud.add_child(panel)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", round(8 * ui_scale))
		margin.add_theme_constant_override("margin_top",  round(8 * ui_scale))
		margin.add_theme_constant_override("margin_right", round(8 * ui_scale))
		margin.add_theme_constant_override("margin_bottom", round(8 * ui_scale))
		panel.add_child(margin)

		var column := VBoxContainer.new()
		margin.add_child(column)

		var title := Label.new()
		title.text = "P%d" % player_id
		title.modulate = GameColors.powered_color(player_id)
		column.add_child(title)

		var row := HFlowContainer.new()
		row.custom_minimum_size = Vector2(150, 0)
		row.add_theme_constant_override("h_separation",  round(4 * ui_scale))
		row.add_theme_constant_override("v_separation",  round(4 * ui_scale))
		column.add_child(row)

		capture_rows.append(row)


func add_captured_piece_icon(player_index: int, captured_piece: Piece) -> void:
	var row := capture_rows[player_index]

	var icon := TextureRect.new()
	var icon_side := 32.0 * (ui_scale)

	icon.custom_minimum_size = Vector2(icon_side, icon_side)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = captured_piece.sprite.texture
	icon.modulate = captured_piece.sprite.modulate
	icon.tooltip_text = captured_piece.getTypeString()

	row.add_child(icon)

func get_enemy_piece_at_cell(cell: Vector2i, player: int) -> Piece:
	for node in pieces_container.get_children():
		var piece := node as Piece

		if piece != null and piece.owned_player == player:
			var piece_cell = local_to_map(piece.position)

			if piece_cell == cell:
				return piece

	return null

# func update_all_piece_vision(excluded_pieces: Array[Piece] = []):
# 	var viewer := local_player if online_game else current_player
# 	clear_board()
# 	if(current_player == 1):
# 		for p in player_pieces[0]:
# 			if(!excluded_pieces.has(p)):
# 				p.draw_current_vision()
# 				p.update_piece_color()
# 		for p in player_pieces[0]:
# 			p.visible = true
# 		for p in player_pieces[1]:
# 			p.visible = false
# 	else:
# 		if(cpu_player == null):
# 			for p in player_pieces[1]:
# 				if(!excluded_pieces.has(p)):
# 					p.draw_current_vision()
# 					p.update_piece_color()
# 			for p in player_pieces[0]:
# 				p.visible = false
# 			for p in player_pieces[1]:
# 				p.visible = true

# 	for i in player_pieces.size():
# 		for j in player_pieces[i].size():
# 			for v in player_pieces[i][j].cur_vision:
# 				player_vision_tiles[i].append(v)
# 				if (hasEnemyPieceInVision(current_player, v)):
# 					setEnemyPieceVisiblity(v, true)

# 	if(cpu_player == null || current_player == 1):
# 		update_core_power()

func update_all_piece_vision(excluded_pieces: Array[Piece] = []):
	var viewer := get_viewer_player()
	var own_index := viewer - 1
	var enemy_index := 1 - own_index

	clear_board()

	for piece in player_pieces[own_index]:
		if not excluded_pieces.has(piece):
			piece.draw_current_vision()
			piece.update_piece_color()
		piece.visible = true

	for piece in player_pieces[enemy_index]:
		piece.visible = false

	for i in range(player_pieces.size()):
		player_vision_tiles[i].clear()
		for piece in player_pieces[i]:
			for cell in piece.cur_vision:
				player_vision_tiles[i].append(cell)

		for enemy_piece in player_pieces[enemy_index]:
			var enemy_cell = enemy_piece.get_cur_pos()
			var can_see_enemy := hasCellInVision(viewer, enemy_cell)

			enemy_piece.visible = can_see_enemy

			if can_see_enemy:
				set_enemy_piece_visiblity(enemy_cell, true, viewer)

	# if cpu_player == null or current_player == 1:
	update_core_power()					
	redraw_selected_highlights()

func set_enemy_piece_visiblity(cell: Vector2i, visible: bool, viewer: int) -> void:
	var enemy_player := 2 if viewer == 1 else 1

	for piece in player_pieces[enemy_player - 1]:
		if cell == piece.get_cur_pos():
			piece.visible = visible

			if cpu_player != null and cpu_player.player_number == enemy_player:
				if not cpu_player.seen_by_player:
					cpu_player.seen_by_player = true
					queue_game_sound(ENEMY_SPOTTED_SOUND, true)
					played_found_sound = true

func hasEnemyPieceInVision(player: int, enemy: Vector2i) -> bool:
	var enemy_player = 2 if player == 1 else 1
	for p in player_pieces[player-1]:
		if(p.cur_vision.has(enemy)):
			return true
	return false

func hasCellInVision(player: int, cell: Vector2i) -> bool:
	for p in player_pieces[player-1]:
		if(p.cur_vision.has(cell)):
			return true
	return false

var capture_sprites: Node2D


func clear_captures():
	for child in capture_sprites.get_children():
		child.queue_free()
	
func set_take_piece_sprite(enemy_loc: Vector2i):
	var icon := Sprite2D.new()
	icon.texture = capture_texture
	icon.position = map_to_local(enemy_loc)
	icon.scale = Vector2.ONE * 0.94
	icon.modulate.a = 0.65

	capture_sprites.add_child(icon)

	# Binding the tween to the icon stops it automatically
	# when selection cleanup frees the icon.
	var pulse := icon.create_tween()
	pulse.set_loops()

	pulse.tween_property(
		icon,
		"scale",
		Vector2.ONE * 1.08,
		0.75
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	pulse.parallel().tween_property(
		icon,
		"modulate:a",
		1.0,
		0.75
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	pulse.tween_property(
		icon,
		"scale",
		Vector2.ONE * 0.94,
		0.75
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	pulse.parallel().tween_property(
		icon,
		"modulate:a",
		0.65,
		0.75
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	

func friendlyPieceExistsAtCell(player: int, cell: Vector2i) -> bool:
	for p in player_pieces[player-1]:
		if(p.get_cur_pos() == cell):
			return true
	return false

func get_current_core() -> CorePiece:
	var current_core: CorePiece = null
	for c in player_pieces[current_player-1]:
		if(c is CorePiece and c.owned_player == current_player):
			current_core = c
	return current_core

func does_move_unpower_core(moved_piece: Piece, new_move: Vector2i) -> bool:
	var core = get_current_core()
	if core == null:
		return false
	if(moved_piece.cur_vision.has(core.get_cur_pos())):
		if(core.power_count == 1):
			if(!moved_piece.get_potential_vision(new_move).has(core.get_cur_pos())):
				return true
	return false

func does_rotate_unpower_core(piece: TowerRotatePiece, first_rotate: bool) -> bool:
	var core = get_current_core()
	if(core == null):
		return false
	var new_direction = piece.cur_direction
	if(first_rotate):
		if new_direction == 0:
			new_direction = 5
		else:
			new_direction = new_direction - 1
	else:
		new_direction = (new_direction + 1) % 6

	if(piece.cur_vision.has(core.get_cur_pos())):
		if(core.power_count == 1):
			if(!piece.get_potential_vision(piece.get_cur_pos(), new_direction).has(core.get_cur_pos())):
				return true
	return false

# func is_piece_under_attack(piece: Piece) -> bool:
# 	var is_core = piece is CorePiece
# 	var enemy_player = 2 if piece.owned_player == 1 else 1
# 	for p in player_pieces[enemy_player - 1]:
# 		var moves = p.generate_possible_moves(p.get_cur_pos())
# 		if(moves.has(piece.get_cur_pos())):
# 			# p.visible = true
# 			if is_core:
# 				p.update_piece_color()
# 				p.visible = true
# 				print("is_core visible check" + str(p.visible))
# 				print(
# 					"piece=", p.name,
# 					" local_visible=", p.visible,
# 					" visible_in_tree=", p.is_visible_in_tree(),
# 					" sprite_visible=", p.sprite.visible,
# 					" sprite_modulate=", p.sprite.modulate,
# 					" global_position=", p.global_position,
# 					" z_index=", p.z_index,
# 					"cell=", p.get_cur_pos(),
# 					" sprite_texture=", p.sprite.texture,
# 					# " global_z=", p.sprite.get_canvas_item().get_index()
# 				)
# 			return true
# 	return false

func is_piece_under_attack(piece: Piece) -> bool:
	var attacker_player := 2 if piece.owned_player == 1 else 1

	# current_player = attacker_player
	regenerate_all_piece_moves(attacker_player, true)

	var target_cell := piece.get_cur_pos()
	var attacked := false
	for attacker in player_pieces[attacker_player - 1]:
		if attacker is TowerRotatePiece:
			if (attacker as TowerRotatePiece).can_attack_cell_after_any_rotation(target_cell):
				attacked = true
				if piece is CorePiece:
					attacker.visible = true
				break
		elif attacker.cur_moves.has(target_cell):
			attacked = true
			break

	# for attacker in player_pieces[attacker_player - 1]:
	# 	# if attacker.cur_moves.has(target_cell):
	# 	var attacker_moves: Array[Vector2i]
	# 	if attacker is TowerRotatePiece:
	# 		attacker_moves = (attacker as TowerRotatePiece).cur_possible_rotate_moves
	# 	else:
	# 		attacker_moves = attacker.cur_moves

	# 	if attacker_moves.has(target_cell):	
	# 			attacked = true
	# 			if piece is CorePiece:
	# 				attacker.visible = true
	# 			break

	# current_player = previous_current_player
	return attacked

# is_enemy is to stop recursion stackoverflow
func regenerate_all_piece_moves(player: int, is_enemy: bool = false):
	for p in player_pieces[player - 1]:
		if(p is CorePiece):
			p.generate_possible_moves(p.get_cur_pos(), is_enemy)
		elif(p is TowerRotatePiece):
			p.generate_all_possible_moves_with_rotation(p.get_cur_pos())
			p.generate_possible_moves(p.get_cur_pos())
		else:
			p.generate_possible_moves(p.get_cur_pos())
				
func is_move_threatened(move: Vector2i, player: int) -> bool:
	var enemy_player = 2 if player == 1 else 1
	for p in player_pieces[enemy_player - 1]:
		if(p is TowerRotatePiece):
			if p.cur_possible_rotate_moves.has(move):
				return true
		if p.cur_moves.has(move):
			return true
	return false
			
func move_visible_and_unoccupied(
	move: Vector2i,
	currentCell: Vector2i,
	piece: Piece
) -> bool:
	if(cell_in_board(move) && move != currentCell):
		if(hasCellInVision(piece.owned_player, move)):
			if(!friendlyPieceExistsAtCell(piece.owned_player,move)):
				if(!does_move_unpower_core(piece, move)):
					return true
	return false

func get_guarders(target: Piece) -> Array[Piece]:
	var guarders: Array[Piece] = []
	if target == null:
		return guarders

	var player := target.owned_player
	var enemy_player := 2 if player == 1 else 1

	for enemy_node in player_pieces[enemy_player - 1]:
		var enemy := enemy_node as Piece
		if enemy == null or not enemy.cur_moves.has(target.get_cur_pos()):
			continue

		# This enemy can legally attack the target.
		for ally_node in player_pieces[player - 1]:
			var ally := ally_node as Piece
			if ally == null or ally == target:
				continue

			# This ally can legally capture the attacker.
			if ally.cur_moves.has(enemy.get_cur_pos()) and not guarders.has(ally):
				guarders.append(ally)

	return guarders


func is_guarded(target: Piece) -> bool:
	return not get_guarders(target).is_empty()


func can_enemy_recapture_after_move(
	moving_piece: Piece,
	destination: Vector2i,
	captured_piece: Piece
) -> bool:
	if moving_piece == null or captured_piece == null:
		return false

	var moving_player := moving_piece.owned_player
	var enemy_player := 2 if moving_player == 1 else 1

	# Only use enemy locations the moving player currently knows about.
	var visible_enemies: Array[Piece] = []
	for node in player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy == null or enemy == captured_piece:
			continue
		if hasCellInVision(moving_player, enemy.get_cur_pos()):
			visible_enemies.append(enemy)

	# Save enemy move-generation state, which regeneration will overwrite.
	var saved_states: Array[Dictionary] = []
	for node in player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy == null:
			continue

		var state: Dictionary = {
			"piece": enemy,
			"moves": enemy.cur_moves.duplicate()
		}

		if enemy is TowerRotatePiece:
			var tower := enemy as TowerRotatePiece
			state["direction"] = tower.cur_direction
			state["rotate_moves"] = tower.cur_possible_rotate_moves.duplicate()
			state["cur_rotate"] = tower.cur_rotate.duplicate()
			state["rotate_map"] = tower.rotate_map.duplicate(true)

		saved_states.append(state)

	var original_position := moving_piece.position
	var original_player := current_player
	var captured_index : int = player_pieces[enemy_player - 1].find(captured_piece)

	# Simulate the capture without calling move_piece() or changing visuals.
	if captured_index >= 0:
		player_pieces[enemy_player - 1].remove_at(captured_index)

	moving_piece.position = map_to_local(destination)
	current_player = enemy_player
	regenerate_all_piece_moves(enemy_player, true)

	var can_recapture := false
	for enemy in visible_enemies:
		if enemy.cur_moves.has(destination):
			can_recapture = true
			break

	# Restore the board and move lists before returning.
	current_player = original_player
	moving_piece.position = original_position

	if captured_index >= 0:
		player_pieces[enemy_player - 1].insert(captured_index, captured_piece)

	for state in saved_states:
		var enemy := state["piece"] as Piece
		enemy.cur_moves = state["moves"]

		if enemy is TowerRotatePiece:
			var tower := enemy as TowerRotatePiece
			tower.cur_direction = state["direction"]
			tower.cur_possible_rotate_moves = state["rotate_moves"]
			tower.cur_rotate = state["cur_rotate"]
			tower.rotate_map = state["rotate_map"]

	return can_recapture

var displayed_warning_text = false

func update_core_power():

	clear_all_power_lines()
	var viewer := get_viewer_player()

	# for child in get_children():
	# 	if child is Line2D:

	# 		child.queue_free()

	var viewed_core: CorePiece = null
	for piece in player_pieces[viewer - 1]:
		if piece is CorePiece:
			viewed_core = piece as CorePiece
			break

	if viewed_core == null:
		return

	update_all_core_power_counts()
	var active_own_core_lines: Dictionary = {}

	var support_count := 0
	for piece in player_pieces[viewer - 1]:
		if piece is CorePiece:
			continue

		if piece.cur_vision.has(viewed_core.get_cur_pos()):
			var line_key := "own_core:%d:%d" % [
				viewed_core.get_instance_id(),
				piece.get_instance_id()
			]

			active_own_core_lines[line_key] = true

			set_cached_power_line(
				line_key,
				viewed_core.position,
				piece.position,
				GameColors.powered_color(viewer),
				5.0
			)

			viewed_core.update_piece_color()
			piece.powered = true
			piece.update_piece_color()
			support_count += 1
		else:
			piece.powered = false
			piece.update_piece_color()

	remove_cached_lines_except(
		"own_core:%d:" % viewed_core.get_instance_id(),
		active_own_core_lines
	)

	update_core_text(support_count)
	viewed_core.power_count = support_count

	var enemy_index := 1 - (viewer - 1)
	remove_cached_lines_with_prefix("enemy_core:")
	remove_cached_lines_with_prefix("powered_pair:%d:" % enemy_index)

	update_visible_enemy_core_highlights(viewer)
	draw_powered_piece_links()
	refresh_powered_vision()

	if game_setup_complete:
		var winner := determine_winner()
		if winner != 0:
			display_winner(winner)
			return
	
	highlight_core_attackers(viewed_core)

	if is_piece_under_attack(viewed_core) and not displayed_warning_text:
		display_core_attack()

func highlight_core_attackers(core: CorePiece) -> void:
	core_attacker_highlights.clear()

	var enemy_player := 2 if core.owned_player == 1 else 1
	var target_cell := core.get_cur_pos()

	regenerate_all_piece_moves(enemy_player, true)

	for attacker in player_pieces[enemy_player - 1]:
		var threatens_core: bool = false

		if attacker is TowerRotatePiece:
			threatens_core = (
				attacker as TowerRotatePiece
			).can_attack_cell_after_any_rotation(target_cell)
		else:
			threatens_core = attacker.cur_moves.has(target_cell)

		if threatens_core and attacker.is_visible_in_tree():
			core_attacker_highlights.set_cell(
				attacker.get_cur_pos(),
				white_outline_source_id,
				Vector2i.ZERO
			)

func draw_powered_piece_links() -> void:
	# Remove the permanent small connections.
	remove_cached_lines_with_prefix("powered_pair:")


func update_visible_enemy_core_highlights(viewer: int) -> void:
	var enemy_player := 2 if viewer == 1 else 1
	var enemy_core: CorePiece = null


	for node in player_pieces[enemy_player - 1]:
		if node is CorePiece:
			enemy_core = node as CorePiece
			if not enemy_core.visible:
				enemy_core = null
			break

	if enemy_core == null:
		remove_cached_lines_with_prefix("enemy_core:")
		return

	var core_cell := enemy_core.get_cur_pos()
	var visible_support_count := 0

	for node in player_pieces[enemy_player - 1]:
		var supporter := node as Piece
		if supporter == null or supporter is CorePiece:
			continue

		var line_key := "enemy_core:%d:%d" % [
			enemy_core.get_instance_id(),
			supporter.get_instance_id()
		]

		var supporter_visible := (
			supporter.visible
			and hasCellInVision(viewer, supporter.get_cur_pos())
		)

		if not supporter_visible:
			remove_cached_power_line(line_key)
			continue

		var supports_core := supporter.cur_vision.has(core_cell)
		supporter.powered = supports_core
		supporter.update_piece_color()

		if supports_core:
			set_cached_power_line(
				line_key,
				enemy_core.position,
				supporter.position,
				GameColors.powered_color(enemy_player),
				3.0
			)
			visible_support_count += 1
		else:
			remove_cached_power_line(line_key)

	var core_visible := (
		enemy_core.visible
		and hasCellInVision(viewer, core_cell)
	)
	enemy_core.powered = core_visible and visible_support_count > 0
	enemy_core.update_piece_color()

var cached_power_lines: Dictionary = {}

func set_cached_power_line(
	key: String,
	start: Vector2,
	finish: Vector2,
	color: Color,
	width: float,
	alpha: float = 1.0
) -> void:
	var line := cached_power_lines.get(key) as Line2D

	if line == null:
		line = Line2D.new()
		line.z_index = 3
		add_child(line)
		cached_power_lines[key] = line

	var line_color := color
	line_color.a = alpha

	line.points = PackedVector2Array([start, finish])
	line.width = width
	line.default_color = line_color


func remove_cached_power_line(key: String) -> void:
	var line := cached_power_lines.get(key) as Line2D
	if line != null:
		line.queue_free()
		cached_power_lines.erase(key)

func remove_cached_lines_except(prefix: String, keep: Dictionary) -> void:
	for key in cached_power_lines.keys():
		if str(key).begins_with(prefix) and not keep.has(key):
			remove_cached_power_line(key)

func remove_cached_lines_with_prefix(prefix: String) -> void:
	for key in cached_power_lines.keys():
		if str(key).begins_with(prefix):
			remove_cached_power_line(key)

func clear_all_power_lines() -> void:
	for child in get_children():
		if child is Line2D:
			remove_child(child)
			child.queue_free()

	cached_power_lines.clear()

# func update_all_core_power_counts() -> void:
# 	for player_id in [1, 2]:
# 		var core: CorePiece = null

# 		for node in player_pieces[player_id - 1]:
# 			if node is CorePiece:
# 				core = node as CorePiece
# 				break

# 		if core == null:
# 			continue

# 		var support_count := 0
# 		for node in player_pieces[player_id - 1]:
# 			var supporter := node as Piece
# 			if supporter == null or supporter == core:
# 				continue
# 			if supporter.cur_vision.has(core.get_cur_pos()):
# 				support_count += 1

# 		core.power_count = support_count

func update_all_core_power_counts() -> void:
	for player_id in [1, 2]:
		var core: CorePiece = null

		for node in player_pieces[player_id - 1]:
			if node is CorePiece:
				core = node as CorePiece
				break

		if core == null:
			continue

		var core_position := core.get_cur_pos()
		var support_count := 0

		for node in player_pieces[player_id - 1]:
			var supporter := node as Piece
			if supporter == null or supporter == core:
				continue

			supporter.powered = supporter.cur_vision.has(core_position)
			supporter.update_piece_color()

			if supporter.powered:
				support_count += 1

		core.power_count = support_count

func display_core_attack():
	var text_timer := Timer.new()
	text_timer.wait_time = 1.5
	text_timer.one_shot = true
	text_timer.timeout.connect(_on_core_attack_timer_timeout)
	queue_game_sound(CORE_ATTACK_SOUND)
	win_label.text = "Core Under Attack!"
	# win_label.modulate = Color.RED
	add_child(text_timer)
	win_label.visible = true
	displayed_warning_text = true
	text_timer.start()
	
func _on_core_attack_timer_timeout():
	win_label.text = ""
	win_label.visible = false

var rotate_sprites: Node2D

func update_rotate_map_board(rotate_map: Dictionary = {}):
	for child in rotate_sprites.get_children():
		child.queue_free()
	if(rotate_map.size() != 0):
		for key in rotate_map.keys():
			var rotate_cell = rotate_map[key]
			var source_id := get_cell_source_id(rotate_cell)
			var source := tile_set.get_source(source_id) as TileSetAtlasSource
			var sprite := Sprite2D.new()
			sprite.texture = source.get_texture()
			var world_position := map_to_local(rotate_cell)
			sprite.position = world_position
			# add_child(sprite)
			rotate_sprites.add_child(sprite)
		

func get_player_color(powered: bool = false) -> Color:
	if powered:
		return GameColors.powered_color(current_player)

	return GameColors.player_color(current_player)
# func get_player_color(powered: bool = false) -> Color:
# 	match current_player:
# 		1: 
# 			if(powered):
# 				return GameColors.PLAYER_BLUE_POWER
# 			return GameColors.PLAYER_BLUE
# 		2: 
# 			if(powered):
# 				return GameColors.PLAYER_RED_POWER
# 			return GameColors.PLAYER_RED
# 	return Color.WHITE

var played_found_sound = false

# func setEnemyPieceVisiblity(cell: Vector2i, visible:bool) -> void:
# 	var enemy_player = 2 if current_player == 1 else 1
# 	for p in player_pieces[enemy_player - 1]:
# 		if(cell == p.get_cur_pos()):
# 			p.visible = visible
# 			if cpu_player.player_number == enemy_player:
# 				if not cpu_player.seen_by_player:
# 					cpu_player.seen_by_player = true
# 					queue_game_sound(game_sound_files[3], true)
# 					played_found_sound = true
# 	return

func clear_board():
	clear_player_highlights()

	for c in board_tiles:
		set_cell(c, Tiles.BLACK, Vector2i.ZERO)

	update_rotate_map_board()

func deselect_all_pieces(excluded_pieces: Array[Piece] = []):
	for p in pieces_container.get_children():
		if(!excluded_pieces.has(p)):
			p.selected = false
		p.update_piece_color()
	update_core_power()
	clear_captures()
	redraw_selected_highlights()

func end_turn(movedPiece: Piece):
	if online_disconnected:
		return
	if tutorial_mode:
		clear_captures()
		deselect_all_pieces()
		update_all_piece_vision()
		update_core_power()
		tutorial_turn_completed.emit()
		return

	if not online_game:
		if is_instance_valid(cpu_player):
			save_offline_checkpoint(3 - current_player, false, movedPiece)
		else:
			save_offline_checkpoint(current_player, true, movedPiece)
	var core_found = false
	clear_captures()
	displayed_warning_text = false
	if(cpu_player == null or current_player != cpu_player.player_number):
		queue_game_sound(PLAYER_MOVE_SOUND)

		await update_move_camera(movedPiece)
		if online_disconnected:
			return
	for i in get_enemy_player_numbers():
		for p in player_pieces[i - 1]:
			if(p is CorePiece):
				core_found = true
	if(core_found):
		var potential_winner = determine_winner()
		if potential_winner == 0:
			if online_game:
				current_player = 3 - current_player
				turn_menu.hide()
				update_turn_text()
				update_all_piece_vision()
				if current_player == local_player:
					display_turn_message()
			elif cpu_player != null:
				end_turn_vs_cpu()
			else:
				turn_menu.show()
		# if(potential_winner == 0):
		# 	if(cpu_player != null):
		# 		end_turn_vs_cpu()
		# 	else:
		# 		turn_menu.show()
		else:
			display_winner(potential_winner)
	else:
		display_winner(current_player)


func get_viewer_player() -> int:
	if online_game:
		return local_player

	if cpu_player != null:
		return 3 - cpu_player.player_number

	return current_player

var enemy_turn_interrupt = false

func end_turn_vs_cpu() -> void:
	current_player = 2 if current_player == 1 else 1
	await _continue_cpu_turn()


func _continue_cpu_turn() -> void:
	if current_player == cpu_player.player_number:
		update_turn_text()
		cpu_turn_in_progress = true

		await get_tree().process_frame

		await cpu_player.take_turn()

		# Retry once using a fresh snapshot if no move was completed.
		if current_player == cpu_player.player_number:
			push_warning("CPU did not complete its turn; retrying once.")
			await get_tree().process_frame
			enemy_captured_this_turn = false
			await cpu_player.take_turn()

		# If normal selection still failed, use the live legal fallback.
		if current_player == cpu_player.player_number:
			cpu_player.recover_turn()

		cpu_turn_in_progress = (
			current_player == cpu_player.player_number
		)

		if(enemy_captured_this_turn):
			queue_game_sound(ENEMY_CAPTURE_SOUND, true)
			enemy_captured_this_turn = false
		elif(enemy_turn_interrupt):
			queue_game_sound(ENEMY_MOVE_SOUND, true)
		elif (played_found_sound):
			queue_game_sound(ENEMY_MOVE_SOUND, false)
			enemy_turn_interrupt = true

		if player_last_moves.size() < 2:
			if(cpu_player.last_moved_piece != null):
				player_last_moves.append(cpu_player.last_moved_piece)
		else:
			if(cpu_player.last_moved_piece != null):
				player_last_moves[1] = cpu_player.last_moved_piece
	else:
		update_all_piece_vision()
		turn_menu.hide()
		var camera_sequence: int = camera.begin_auto_camera_sequence()
		update_turn_text()

		# First show the CPU move, if it is visible.
		var enemy_move: Piece = cpu_player.last_moved_piece
		if (
			enemy_move != null
			and is_instance_valid(enemy_move)
			and hasCellInVision(current_player, enemy_move.get_cur_pos())
		):
			await camera.zoom_to_global_position(
				enemy_move.global_position,
				camera.zoom.x,
				camera_sequence
			)

		# Then show this player's last move, or their core.
		var own_index := current_player - 1
		if own_index < player_last_moves.size():
			var own_move: Piece = player_last_moves[own_index]
			if is_instance_valid(own_move):
				await camera.zoom_to_global_position(
					own_move.global_position,
					camera.zoom.x,
					camera_sequence
				)
			else:
				await move_camera_to_core(camera_sequence)
		else:
			await move_camera_to_core(camera_sequence)
		display_turn_message()

func update_move_camera(movedPiece: Piece):
	update_all_piece_vision()
	var camera_sequence: int = camera.begin_auto_camera_sequence()

	if online_game:
		if movedPiece.owned_player == local_player or movedPiece.visible:
			await camera.zoom_to_global_position(
				movedPiece.global_position,
				camera.zoom.x,
				camera_sequence
			)
	elif movedPiece.owned_player == current_player:
		await camera.zoom_to_global_position(
			movedPiece.global_position,
			camera.zoom.x,
			camera_sequence
		)
	elif player_last_moves.size() == player_pieces.size():
		var enemy_player = 2 if current_player == 1 else 1
		await camera.zoom_to_global_position(
			player_last_moves[enemy_player - 1].global_position,
			camera.zoom.x,
			camera_sequence
		)

	if player_last_moves.size() < 2:
		player_last_moves.append(movedPiece)
	else:
		player_last_moves[current_player - 1] = movedPiece


func get_enemy_player_numbers():
	var enemy_players: Array[int] = []
	for i in range(player_pieces.size()) :
		if(i+1) != current_player:
			enemy_players.append((i + 1))
	return enemy_players

# func add_capture_feed_entry(capturing_piece: Piece, captured_piece: Piece) -> void:
# 	var entry := HBoxContainer.new()
# 	entry.add_theme_constant_override("separation", round(8 * ui_scale))

# 	for piece in [capturing_piece, captured_piece]:
# 		var icon := TextureRect.new()
# 		var icon_side := 48.0 * ui_scale
# 		icon.custom_minimum_size = Vector2(icon_side, icon_side)
# 		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
# 		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
# 		icon.texture = piece.sprite.texture
# 		icon.modulate = piece.sprite.modulate
# 		entry.add_child(icon)

# 	capture_feed.add_child(entry)

# 	await get_tree().create_timer(2.5).timeout
# 	if is_instance_valid(entry):
# 		entry.queue_free()

func add_capture_feed_entry(capturing_piece: Piece, captured_piece: Piece) -> void:

	var entry := HBoxContainer.new()
	var player_color := GameColors.player_color(
		capturing_piece.owned_player
	)
	# var player_color := (
	# 	GameColors.PLAYER_BLUE
	# 	if capturing_piece.owned_player == 1
	# 	else GameColors.PLAYER_RED
	# )

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = player_color.darkened(0.65)
	panel_style.bg_color.a = 0.5
	panel_style.set_corner_radius_all(8)
	capture_feed_panel.add_theme_stylebox_override("panel", panel_style)
	# resize_capture_feed_panel()
	# capture_feed_panel.show()
	capture_feed.add_child(entry)
	entry.add_theme_constant_override("separation", round(8 * ui_scale))

	for i in range(2):
		var piece: Piece = capturing_piece if i == 0 else captured_piece

		var icon := TextureRect.new()
		var icon_side := 48.0 * ui_scale
		icon.custom_minimum_size = Vector2(icon_side, icon_side)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = piece.sprite.texture
		icon.modulate = piece.sprite.modulate
		entry.add_child(icon)

		if i == 0:
			var capture_icon := TextureRect.new()
			var capture_side := 36.0 * ui_scale
			capture_icon.pivot_offset = Vector2(capture_side / 2.0, capture_side / 2.0)
			# capture_icon.scale.x = -1.0
			capture_icon.flip_h = true
			capture_icon.custom_minimum_size = Vector2(capture_side, capture_side)
			capture_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			capture_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			capture_icon.texture = CAPTURE_FEED_TEXTURE
			entry.add_child(capture_icon)

	capture_feed.add_child(entry)
	resize_capture_feed_panel()
	capture_feed_panel.show()

	await get_tree().create_timer(2.5).timeout

	if is_instance_valid(entry):
		capture_feed.remove_child(entry)
		entry.queue_free()

		if capture_feed.get_child_count() == 0:
			capture_feed_panel.hide()
		else:
			resize_capture_feed_panel()

func resize_capture_feed_panel() -> void:
	var content_size := capture_feed.get_combined_minimum_size()
	var padding := Vector2(20.0, 20.0) # 10px margin on each side

	capture_feed_panel.offset_right = content_size.x + padding.x

	var panel_height := content_size.y + padding.y
	capture_feed_panel.offset_top = -panel_height / 2.0
	capture_feed_panel.offset_bottom = panel_height / 2.0

func screen_to_board_cell(screen_position: Vector2) -> Vector2i:
	var local_position := (
		get_global_transform_with_canvas().affine_inverse()
		* screen_position
	)
	return local_to_map(local_position)

func handle_touch_tap(screen_position: Vector2) -> void:
	if not game_setup_complete:
		return
	if online_disconnected or match_winner != 0:
		return
	if settings_cover.visible or turn_menu.visible:
		return
	if get_tree().current_scene.has_node("SettingsOverlay"):
		return

	# Reuse the existing click logic only after confirming a tap.
	var click := InputEventMouseButton.new()
	click.position = screen_position
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true

	for group in player_pieces:
		for piece: Piece in group:
			if piece.selected and piece.can_control_piece():
				piece.handle_board_click(click)
				return

	# Nothing selected: select a friendly piece or inspect a visible enemy.
	var cell := screen_to_board_cell(screen_position)

	for group in player_pieces:
		for piece: Piece in group:
			if piece.get_cur_pos() != cell or not piece.visible:
				continue

			if piece.inspect_enemy_piece():
				return

			if not piece.can_control_piece():
				return

			piece.on_clicked()
			piece.armed = true
			update_selection_panel(piece)

			if tutorial_mode and piece.selected:
				tutorial_piece_selected.emit(piece)

			return

var cur_ani_x = 0
var cur_ani_y = 0
var x_ani = true
var ani_index = 0
var ani_offset = 0
func animate_board():
	var cur_range = (cur_ani_x + 1)*2
	if(cur_range == 0):
		cur_range = 2
	for i in range(cur_range):
		set_cell(Vector2i(cur_ani_x - ani_offset,cur_ani_y), 12, Vector2i(0,0))
		if(cur_ani_y % 2 == 1):
			ani_offset += 1
		cur_ani_y += 1
	cur_ani_y = 0
	ani_offset = 0 
	cur_ani_x += 1

func cell_in_board(cell: Vector2i) -> bool:
	return cell in board_tiles

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:

		var local = to_local(
			camera.get_global_mouse_position() - position
		)
		var cell = local_to_map(local)

		var tile_pos = map_to_local(Vector2i(3, 4))



func draw_hex_around(center: Vector2i) :
	var curTile = 0
	if(current_player == 1):
		curTile = 11		
	else:
		curTile = 9
	
	if(center.y % 2 ==  0): 
		set_cell(
			Vector2i(center.x - 1, center.y), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x , center.y - 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x + 1 , center.y - 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x + 1 , center.y + 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x , center.y + 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x + 1 , center.y), 
			curTile,
			Vector2i(0,0)
		)
	else:
		set_cell(
			Vector2i(center.x - 1, center.y - 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x , center.y - 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x + 1 , center.y), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x - 1 , center.y ), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x , center.y + 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x - 1 , center.y + 1), 
			curTile,
			Vector2i(0,0)
		)

func get_line_end_from_center(center: Vector2i, direction, length: int):
	#clockwise
	var center_even = center.y % 2 == 0
	match direction:
		0: 
			var offset = 0
			if(center_even):
				offset = 1
			offset = offset + length / 2 
			return Vector2i(center.x + offset, center.y - length)	
		1: 
			return Vector2i(center.x + length, center.y)
		2: 
			var offset = 0
			if(center_even):
				offset = 1
			offset = offset + length / 2 
			return Vector2i(center.x + offset, center.y + length)
		3: 
			var offset = 1
			if(center_even):
				offset = 0
			offset = offset + length / 2 
			return Vector2i(center.x - offset, center.y + length)
		4:
			return Vector2i(center.x - length, center.y)
		5: 
			var offset = 1
			if(center_even):
				offset = 0
			offset = offset + length / 2 
			return Vector2i(center.x - offset, center.y - length)


func get_line_from_center(center: Vector2i, direction: int, length: int):
	#clockwise
	var center_even = center.y % 2 == 0
	match direction:
		0: 
			var offset = 0
			if(center_even):
				offset = 1
				if(length % 2 == 0):
					offset = offset - 1
			offset = offset + length / 2 
			return hex_line(center, Vector2i(center.x + offset, center.y - length))	
		1: 
			return hex_line(center, Vector2i(center.x + length, center.y))
		2: 
			var offset = 0
			if(center_even):
				offset = 1
				if(length % 2 == 0):
					offset = offset - 1
			offset = offset + length / 2 
			return hex_line(center, Vector2i(center.x + offset, center.y + length))
		3: 
			var offset = 1
			if(center_even):
				offset = 0
			else:
				if(length % 2 == 0):
					offset = offset - 1
			offset = offset + length / 2 
			return hex_line(center,Vector2i(center.x - offset, center.y + length))
		4:
			return hex_line(center,Vector2i(center.x - length, center.y))
		5: 
			var offset = 1
			if(center_even):
				offset = 0
			else:
				if(length % 2 == 0):
					offset = offset - 1
			offset = offset + length / 2 
			return hex_line(center,Vector2i(center.x - offset, center.y - length))


func draw_line_from_center(center: Vector2i,direction: int, length: int, color: int):
	var cells = get_line_from_center(center, direction, length)
	for cell in cells:
		set_cell(cell, color, Vector2i(0,0))
	#clockwise
	# var center_even = center.y % 2 == 0
	# match direction:
	# 	0: 
	# 		var offset = 0
	# 		if(center_even):
	# 			offset = 1
	# 		offset = offset + length / 2 
	# 		draw_hex_tile_line(center, Vector2i(center.x + offset, center.y - length), color)
	# 	1: 
	# 		draw_hex_tile_line(center, Vector2i(center.x + length, center.y), color)
	# 	2: 
	# 		var offset = 0
	# 		if(center_even):
	# 			offset = 1
	# 		offset = offset + length / 2 
	# 		draw_hex_tile_line(center, Vector2i(center.x + offset, center.y + length), color)
	# 	3: 
	# 		var offset = 1
	# 		if(center_even):
	# 			offset = 0
	# 		offset = offset + length / 2 
	# 		draw_hex_tile_line(center, Vector2i(center.x - offset, center.y + length), color)
	# 	4:
	# 		draw_hex_tile_line(center, Vector2i(center.x - length, center.y), color)
	# 	5: 
	# 		var offset = 1
	# 		if(center_even):
	# 			offset = 0
	# 		offset = offset + length / 2 
	# 		draw_hex_tile_line(center, Vector2i(center.x - offset, center.y - length), color)
			

		
func draw_horz_line(center: Vector2i):
	var line_color_id = 3
	for i in range(5):
		set_cell(Vector2i(center.x + i, center.y), line_color_id, Vector2i(0,0))
		set_cell(Vector2i(center.x - i, center.y), line_color_id, Vector2i(0,0))

func draw_back_dia_line(center: Vector2i):
	var line_color_id = 8
	var offset_pos = 0
	if (center.y) % 2 == 0:
		offset_pos = 1
	
	var offset_neg = 1
	if (center.y) % 2 == 0:
		offset_neg = 0

	for i in range(1,6):
		set_cell(Vector2i(center.x + offset_pos, center.y + i), line_color_id, Vector2i(0,0))
		set_cell(Vector2i(center.x - offset_neg, center.y - i), line_color_id, Vector2i(0,0))
		if (center.y + i) % 2 == 0:
			offset_pos += 1
		if (center.y + i) % 2 == 1:
			offset_neg += 1
		
func draw_forward_dia_line(center: Vector2i):
	var line_color_id = 12
	var offset_pos = 0
	if (center.y) % 2 == 0:
		offset_pos = 1
	
	var offset_neg = 1
	if (center.y) % 2 == 0:
		offset_neg = 0

	for i in range(1,6):
		set_cell(Vector2i(center.x - offset_neg, center.y + i), line_color_id, Vector2i(0,0))
		set_cell(Vector2i(center.x + offset_pos, center.y - i), line_color_id, Vector2i(0,0))
		if (center.y + i) % 2 == 0:
			offset_pos += 1
		if (center.y + i) % 2 == 1:
			offset_neg += 1

func draw_vision_range(center: Vector2i, vision_range: int, color: int):
	var hex_color_id = color
	var offset_pos = 0
	if (center.y) % 2 == 0:
		offset_pos = 1
	
	var offset_neg = 1
	if (center.y) % 2 == 0:
		offset_neg = 0

	var minXTop = 10
	var minXBottom= 10

	for i in range(1,vision_range + 1):

		# set_cell(Vector2i(center.x - offset_neg, center.y + i), 6, Vector2i(0,0))
		# set_cell(Vector2i(center.x + offset_pos, center.y + i), 6, Vector2i(0,0))

		#below
		draw_hex_tile_line(
			Vector2i(center.x - offset_neg, center.y + i), 
			Vector2i(center.x + offset_pos, center.y + i),
			hex_color_id
		)

		# above
		draw_hex_tile_line(
			Vector2i(center.x + offset_pos, center.y - i),	
			Vector2i(center.x - offset_neg, center.y - i),
			hex_color_id
		)

		var temp_color = 7
		draw_hex_tile_line(
			Vector2i(center.x - offset_neg, center.y + i), 
			Vector2i(center.x - i, center.y),
			temp_color
		)
		draw_hex_tile_line(
			Vector2i(center.x - offset_neg, center.y - i), 
			Vector2i(center.x - i, center.y),
			temp_color
		)

		draw_hex_tile_line(
			Vector2i(center.x + offset_pos, center.y + i), 
			Vector2i(center.x + i, center.y),
			temp_color
		)
		draw_hex_tile_line(
			Vector2i(center.x + offset_pos, center.y - i), 
			Vector2i(center.x + i, center.y),
			temp_color
		)

		set_cell(Vector2i(center.x + i, center.y), hex_color_id, Vector2i(0,0))
		set_cell(Vector2i(center.x - i, center.y), hex_color_id, Vector2i(0,0))

		if (center.y + i) % 2 == 0:
			offset_pos += 1
		if (center.y + i) % 2 == 1:
			offset_neg += 1

func get_triangle_tiles_from_center(center: Vector2i, hex_radius: int, direction: int):

	var triangle_tiles: Array[Vector2i] = []

	var offset_pos = 0
	if (center.y) % 2 == 0:
		offset_pos = 1
	
	var offset_neg = 1
	if (center.y) % 2 == 0:
		offset_neg = 0

	for i in range(1,hex_radius + 1):
		match direction:
			0:
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x + offset_pos, center.y - i), 
						Vector2i(center.x + i, center.y),
					)
				)
			1:
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x + offset_pos, center.y + i), 
						Vector2i(center.x + i, center.y),
					)
				)
			2:
				# below
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x - offset_neg, center.y + i), 
						Vector2i(center.x + offset_pos, center.y + i),
					)
				)
			3:
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x - offset_neg, center.y + i), 
						Vector2i(center.x - i, center.y),
					)
				)
			4:
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x - offset_neg, center.y - i), 
						Vector2i(center.x - i, center.y),
					)
				)
			5:
				# above
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x + offset_pos, center.y - i),	
						Vector2i(center.x - offset_neg, center.y - i),
					)
				)

	


		if(direction == 0 or direction == 1): 
			triangle_tiles.append(Vector2i(center.x + i, center.y))

		if(direction == 3 or direction == 4): 
			triangle_tiles.append(Vector2i(center.x - i, center.y))

		if (center.y + i) % 2 == 0:
			offset_pos += 1
		if (center.y + i) % 2 == 1:
			offset_neg += 1
		
	triangle_tiles.append(center)
	return triangle_tiles


func get_hexagon_tiles(center: Vector2i, hex_radius: int):
	var offset_pos = 0
	if (center.y) % 2 == 0:
		offset_pos = 1
	
	var offset_neg = 1
	if (center.y) % 2 == 0:
		offset_neg = 0

	var hexagon_tiles: Array[Vector2i] = []

	for i in range(1,hex_radius + 1):

		#below
		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x - offset_neg, center.y + i), 
				Vector2i(center.x + offset_pos, center.y + i),
			)
		)

		# above
		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x + offset_pos, center.y - i),	
				Vector2i(center.x - offset_neg, center.y - i),
			)
		)

		var temp_color = 7
		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x - offset_neg, center.y + i), 
				Vector2i(center.x - i, center.y),
			)
		)
	
		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x - offset_neg, center.y - i), 
				Vector2i(center.x - i, center.y),
			)
		)

		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x + offset_pos, center.y + i), 
				Vector2i(center.x + i, center.y),
			)
		)

		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x + offset_pos, center.y - i), 
				Vector2i(center.x + i, center.y),
			)
		)


		hexagon_tiles.append(Vector2i(center.x + i, center.y))
		hexagon_tiles.append(Vector2i(center.x - i, center.y))

		if (center.y + i) % 2 == 0:
			offset_pos += 1
		if (center.y + i) % 2 == 1:
			offset_neg += 1
		
	hexagon_tiles.append(center)
	return hexagon_tiles



func draw_hex_tile_line(a: Vector2i, b: Vector2i, tile_id: int) -> void:
	var cells = hex_line(a, b)
	for pos in cells:
		set_cell(pos, tile_id, Vector2i(0,0))


static func offset_to_cube(offset: Vector2i) -> Vector3i:
	var col = offset.x
	var row = offset.y

	# even-r conversion
	var x = col - ((row + (row & 1)) / 2)
	var z = row
	var y = -x - z

	return Vector3i(x, y, z)


# ------------------------------------------------
# Cube → Offset
# ------------------------------------------------
static func cube_to_offset(c: Vector3i) -> Vector2i:
	var x = c.x
	var z = c.z

	# even-r conversion
	var col = x + ((z + (z & 1)) / 2)
	var row = z

	return Vector2i(col, row)


# ------------------------------------------------
# Cube interpolation
# ------------------------------------------------
static func cube_lerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, t)


# ------------------------------------------------
# Cube rounding
# ------------------------------------------------
static func cube_round(c: Vector3) -> Vector3i:
	var rx = round(c.x)
	var ry = round(c.y)
	var rz = round(c.z)

	var dx = abs(rx - c.x)
	var dy = abs(ry - c.y)
	var dz = abs(rz - c.z)

	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry

	return Vector3i(rx, ry, rz)


# ------------------------------------------------
# Hex line generation (cube interpolation)
# ------------------------------------------------
static func hex_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	if(a.y == b.y):
		for i in range(abs(a.x - b.x) + 1):
			if(a.x > b.x):
				results.append(Vector2i(a.x - i, a.y))			
			else:
				results.append(Vector2i(a.x + i, a.y))
		return results

	var ac = offset_to_cube(a)
	var bc = offset_to_cube(b)

	var dist = max(abs(ac.x - bc.x), abs(ac.y - bc.y), abs(ac.z - bc.z))


	for i in range(dist + 1):
		var t = i / float(dist)
		var c = cube_round(cube_lerp(ac, bc, t))
		results.append(cube_to_offset(c))

	return results

func move_camera_to_core(camera_sequence: int = -1) -> void:
	var core := get_current_core()

	if not is_instance_valid(core):
		return

	update_selection_panel(core)

	await camera.zoom_to_global_position(
		core.global_position,
		0.6,
		camera_sequence
	)

func _on_next_pressed() -> void:
	var enemy_eye = false
	for p in pieces_container.get_children():
		if(p is EyePiece and p.owned_player != current_player):
			enemy_eye = true

	current_player = 2 if current_player == 1 else 1
	update_all_piece_vision()
	# move_camera_to_core()
	turn_menu.hide()
	save_offline_checkpoint()
	var camera_sequence: int = camera.begin_auto_camera_sequence()
	# if(player_last_moves.size() == player_pieces.size()):
	# 	await update_move_camera(
	# 		player_last_moves[current_player - 1]
	# 	)
		# Show the enemy's last move, if it is visible to the incoming player.
	
	

	if player_last_moves.size() > 1:
		var enemy_index := 1 if current_player == 1 else 0
		var enemy_move: Piece = player_last_moves[enemy_index]
		if (
			is_instance_valid(enemy_move)
			and hasCellInVision(current_player, enemy_move.get_cur_pos())
		):
			await camera.zoom_to_global_position(
				enemy_move.global_position,
				camera.zoom.x,
				camera_sequence
			)

	# Return to this player's last move, or their core if they have not moved yet.
	var own_index := current_player - 1
	if own_index < player_last_moves.size():
		var own_move: Piece = player_last_moves[own_index]
		if is_instance_valid(own_move):
			await camera.zoom_to_global_position(
				own_move.global_position,
				camera.zoom.x,
				camera_sequence
			)
		else:
			await move_camera_to_core(camera_sequence)
	else:
		await move_camera_to_core(camera_sequence)

	update_turn_text()
	display_turn_message()


func save_offline_checkpoint(
	saved_player: int = -1,
	handoff_pending: bool = false,
	moved_piece: Piece = null
) -> void:
	if online_game or tutorial_mode or not game_setup_complete:
		return

	update_all_core_power_counts()
	if determine_winner() != 0:
		OfflineSave.clear_match()
		return

	var pieces: Array[Dictionary] = []
	for group in player_pieces:
		for piece: Piece in group:
			pieces.append({
				"id": piece.get_instance_id(),
				"kind": piece.get_script().resource_path.get_file(),
				"player": piece.owned_player,
				"cell": piece.get_cur_pos(),
				"direction": (
					piece.cur_direction
					if piece is TowerRotatePiece
					else 0
				),
			})

	var captures: Array = [[], []]
	for side in range(2):
		for record: Dictionary in player_captures[side]:
			var texture := record.get("texture") as Texture2D
			captures[side].append({
				"name": record.get("name", ""),
				"cell": record.get("cell", Vector2i.ZERO),
				"texture_path": texture.resource_path if texture != null else "",
			})

	var last_moves: Array[int] = [-1, -1]
	for side in range(mini(player_last_moves.size(), 2)):
		if is_instance_valid(player_last_moves[side]):
			last_moves[side] = player_last_moves[side].get_instance_id()

	if is_instance_valid(moved_piece):
		last_moves[moved_piece.owned_player - 1] = moved_piece.get_instance_id()

	var data: Dictionary = {
		"pieces": pieces,
		"captures": captures,
		"current_player": current_player if saved_player < 0 else saved_player,
		"turn": turn,
		"handoff_pending": handoff_pending,
		"play_vs_cpu": play_vs_cpu,
		"colors": GameColors.selected_color_indices.duplicate(),
		"last_moves": last_moves,
		"last_capturers": last_capture_capturer_ids.duplicate(),
		"camera_position": camera.global_position,
		"camera_zoom": camera.zoom,
		"cpu": (
			cpu_player.export_save_state()
			if is_instance_valid(cpu_player)
			else {}
		),
	}

	var error = OfflineSave.write_match(data)
	if error != OK:
		push_error("Could not save offline match: " + error_string(error))
	
func _saved_piece_scenes() -> Dictionary:
	return {
		"Piece.gd": piece_scene,
		"CorePiece.gd": core_piece_scene,
		"EyePiece.gd": eye_piece_scene,
		"TowerRotatePiece.gd": tower_piece_scene,
		"HopPiece.gd": hop_piece_scene,
		"TriangleOddPiece.gd": triangle_odd_piece_scene,
		"TriangleEvenPiece.gd": triangle_even_piece_scene,
	}


func restore_offline_checkpoint(data: Dictionary) -> bool:
	var scenes := _saved_piece_scenes()
	var records: Array = data.get("pieces", [])
	var captures: Array = data.get("captures", [])

	if records.is_empty() or captures.size() != 2:
		return false
	if int(data.get("current_player", 0)) not in [1, 2]:
		return false

	# Validate before replacing any pieces.
	for record in records:
		if not record is Dictionary:
			return false
		if not scenes.has(record.get("kind", "")):
			return false
		if scenes[record["kind"]] == null:
			return false
		if int(record.get("player", 0)) not in [1, 2]:
			return false
		if not record.get("cell") is Vector2i:
			return false
		if not cell_in_board(record["cell"]):
			return false
		if not record.has("id"):
			return false
		if int(record.get("direction", -1)) not in range(6):
			return false

	for group in captures:
		if not group is Array:
			return false
		for record in group:
			if not record is Dictionary:
				return false
			var path := str(record.get("texture_path", ""))
			if not path.is_empty():
				if not path.begins_with("res://sprites/"):
					return false
				if not ResourceLoader.exists(path, "Texture2D"):
					return false

	game_setup_complete = false
	current_player = int(data["current_player"])
	turn = int(data.get("turn", 1))

	for child in pieces_container.get_children():
		pieces_container.remove_child(child)
		child.queue_free()

	player_pieces = [[], []]
	var piece_map: Dictionary = {}
	var id_map: Dictionary = {}

	for record: Dictionary in records:
		var scene: PackedScene = scenes[record["kind"]]
		var piece := scene.instantiate() as Piece
		piece.owned_player = int(record["player"])
		player_pieces[piece.owned_player - 1].append(piece)
		pieces_container.add_child(piece)
		piece.setup(record["cell"], self)

		if piece is TowerRotatePiece:
			piece.cur_direction = int(record["direction"])
			piece.update_sprite_rotation()

		if piece is CorePiece:
			piece.cur_vision.clear()
		else:
			piece.cur_vision = piece.get_potential_vision(piece.get_cur_pos())

		var saved_id := int(record["id"])
		piece_map[saved_id] = piece
		id_map[saved_id] = piece.get_instance_id()

	player_last_moves.clear()
	for saved_id in data.get("last_moves", [-1, -1]):
		player_last_moves.append(piece_map.get(int(saved_id)) as Piece)

	last_capture_capturer_ids.clear()
	for saved_id in data.get("last_capturers", [-1, -1]):
		last_capture_capturer_ids.append(
			int(id_map.get(int(saved_id), -1))
		)

	player_captures = [[], []]
	for side in range(2):
		for child in capture_rows[side].get_children():
			capture_rows[side].remove_child(child)
			child.queue_free()

		for record: Dictionary in captures[side]:
			var path := str(record.get("texture_path", ""))
			var texture: Texture2D = null
			if not path.is_empty():
				texture = load(path) as Texture2D

			player_captures[side].append({
				"name": record.get("name", ""),
				"cell": record.get("cell", Vector2i.ZERO),
				"texture": texture,
			})

			var icon := TextureRect.new()
			icon.texture = texture
			icon.custom_minimum_size = Vector2.ONE * 32.0 * ui_scale
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.modulate = GameColors.player_color(2 - side)
			icon.tooltip_text = str(record.get("name", ""))
			capture_rows[side].add_child(icon)

	if is_instance_valid(cpu_player):
		cpu_player.import_save_state(data["cpu"], id_map, piece_map)

	update_all_piece_vision()
	update_all_core_power_counts()
	game_setup_complete = true
	update_core_power()
	update_turn_text()

	var core := get_current_core()
	if is_instance_valid(core):
		update_selection_panel(core)

	turn_menu.visible = (
		not play_vs_cpu
		and bool(data.get("handoff_pending", false))
	)
	settings_cover.hide()

	camera.interrupt_auto_camera()
	camera.global_position = data.get(
		"camera_position",
		board_center
	)
	var saved_zoom: Vector2 = data.get("camera_zoom", Vector2.ONE)
	camera.zoom = Vector2.ONE * clampf(saved_zoom.x, 0.4, 3.0)
	camera.rebuild_map_bounds()
	camera.force_update_scroll()
	board_effects.start_resumed_game()

	if is_instance_valid(cpu_player):
		if current_player == cpu_player.player_number:
			cpu_turn_in_progress = true
			call_deferred("_continue_cpu_turn")

	return true

func _on_network_game_message(payload: Variant, from_player: int) -> void:
	if online_disconnected:
		return
	if not online_game or typeof(payload) != TYPE_DICTIONARY:
		return
	if from_player == local_player or from_player != current_player:
		return

	var from_data: Variant = payload.get("from", [])
	if typeof(from_data) != TYPE_ARRAY or from_data.size() != 2:
		return

	var from_cell := Vector2i(int(from_data[0]), int(from_data[1]))
	if not cell_in_board(from_cell):
		return

	var piece := get_enemy_piece_at_cell(from_cell, from_player)
	if piece == null:
		return

	match payload.get("action", ""):
		"move":
			var to_data: Variant = payload.get("to", [])
			if typeof(to_data) != TYPE_ARRAY or to_data.size() != 2:
				return

			var to_cell := Vector2i(int(to_data[0]), int(to_data[1]))
			if not cell_in_board(to_cell):
				return

			piece.make_cpu_move(to_cell)

		"rotate":
			if not piece is TowerRotatePiece:
				return

			var direction := int(payload.get("direction", -1))
			if direction < 0 or direction > 5:
				return

			var tower := piece as TowerRotatePiece
			tower.cur_direction = direction
			tower.update_sprite_rotation()
			tower.draw_vision_change()

func _on_opponent_disconnected() -> void:
	_end_disconnected_match( 
		"Your opponent left the match.\nYou win!",
		true
	)


func _on_connection_closed() -> void:
	_end_disconnected_match(
		"The connection to the server was lost.\nThis match cannot continue."
	)


func _on_online_network_error(message: String) -> void:
	_end_disconnected_match(
		"An online connection error occurred:\n" + message
	)


func _end_disconnected_match(
	message: String,
	opponent_left: bool = false
) -> void:
	if not online_game or online_disconnected:
		return

	online_disconnected = true
	camera.interrupt_auto_camera()
	deselect_all_pieces()
	clear_captures()
	NetworkManager.leave_room()

	# Preserve an existing result if the match already finished.
	if match_winner != 0:
		return

	var title := "Match Disconnected"

	if opponent_left:
		display_winner(local_player)
		title = "You Win!"
		win_label.text = "You Win!\nOpponent left the match."

	call_deferred("_show_disconnect_dialog", message, title)


func _show_disconnect_dialog(
	message: String,
	title: String = "Match Disconnected"
) -> void:
	if not is_inside_tree():
		return

	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.ok_button_text = "Return to Main Menu"
	dialog.exclusive = true
	add_child(dialog)

	dialog.confirmed.connect(_return_from_disconnected_match)
	dialog.close_requested.connect(_return_from_disconnected_match)
	dialog.popup_centered()

func _return_from_disconnected_match() -> void:
	NetworkManager.leave_room()
	get_tree().call_deferred(
		"change_scene_to_file",
		"res://main_menu.tscn"
	)

func _on_stay_button_pressed() -> void:
	update_turn_text()
	update_all_piece_vision()
	turn_menu.hide()
	save_offline_checkpoint()

@onready var music_player: AudioStreamPlayer2D = $"../AudioStreamPlayer2D"
@onready var game_sounds: AudioStreamPlayer =$"../GameSounds"

const PLAYER_MOVE_SOUND = preload("res://audio/firsttake.wav")
const PLAYER_CAPTURE_SOUND = preload("res://audio/Capture2.wav")
const CORE_ATTACK_SOUND = preload("res://audio/core_attack.wav")
const ENEMY_MOVE_SOUND = preload("res://audio/EnemyMove.wav")
const ENEMY_SPOTTED_SOUND = preload("res://audio/Capture1.wav")
const ENEMY_CAPTURE_SOUND = preload("res://audio/enemy_capture.wav")


var sound_queue: Array[AudioStream] = []


func queue_game_sound(sound: AudioStream, clearQueue: bool = false) -> void:
	if clearQueue:
		# Preserve any core warning waiting in the queue.
		sound_queue = sound_queue.filter(
			func(queued: AudioStream) -> bool:
				return queued == CORE_ATTACK_SOUND
		)

		# Let a core warning finish before playing other effects.
		if not (
			game_sounds.playing
			and game_sounds.stream == CORE_ATTACK_SOUND
		):
			game_sounds.stop()

	sound_queue.append(sound)

	if not game_sounds.finished.is_connected(_play_next_sound):
		game_sounds.finished.connect(_play_next_sound)

	if not game_sounds.playing:
		_play_next_sound()	

func _play_next_sound() -> void:
	if sound_queue.is_empty():
		return
	game_sounds.stop()
	game_sounds.stream = sound_queue.pop_front()
	game_sounds.play()

func _on_pause_pressed() -> void:
	settings_cover.visible = true


func _on_continue_pressed() -> void:
	settings_cover.visible = false

# func _on_check_button_toggled(toggled_on: bool) -> void:
# 	if toggled_on:
# 		music_player.play()
# 	else:
# 		music_player.stop()

func _on_settings_pressed() -> void:
	if get_tree().current_scene.has_node("SettingsOverlay"):
		return

	var settings := preload("res://settings_menu.tscn").instantiate()
	settings.name = "SettingsOverlay"
	get_tree().current_scene.add_child(settings)


func _on_quit_pressed() -> void:
	if online_game:
		online_disconnected = true
		NetworkManager.leave_room()

	camera.interrupt_auto_camera()
	get_tree().change_scene_to_file("res://main_menu.tscn")


const CORE_CAPTURE_ENDGAME_PIECES := 3


