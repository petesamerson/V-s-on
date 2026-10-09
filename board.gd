extends TileMapLayer
class_name Board

@export var camera: Camera2D
@onready var tilemap = $TileMap
@onready var turn_label: RichTextLabel = $"../TurnLayer/StatMargin/StatContainer/TurnLabel"
@onready var core_label: RichTextLabel = $"../TurnLayer/StatMargin/StatContainer/CoreLabel"
@onready var win_label: Label = $"../TurnLayer/WinLabel"
@onready var your_turn_label: Label = $"../TurnLayer/YourTurnLabel"
@onready var turn_menu = $"../TurnLayer/PlayerSwitchOverlay"
@onready var selection_panel= $"../TurnLayer/SelectionPanel"
@onready var settings_cover= $"../TurnLayer/SettingsCover"

@export var capture_texture: Texture2D

var Tiles = preload("res://tiles.gd")
const GameColors = preload("res://colors.gd")

var board_center = Vector2i(10, 10)
var board_size = 10
var board_tiles: Array[Vector2i] = []

var turn = 1
var current_player: int = 1
var play_vs_cpu: bool = false

var game_setup_complete := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.z_index = 0
	board_tiles = get_hexagon_tiles(board_center, board_size)
	for c in board_tiles:
		set_cell(c, Tiles.BLACK, Vector2i(0,0))

	call_deferred("spawn_all_pieces")

	get_viewport().size_changed.connect(resize_text_overlay)

	instantiate_turn_menu()
	instantiate_core_menu()

	intialize_drawn_sprite_nodes()
	update_mobile_scale()

	play_vs_cpu = get_tree().root.get_meta("play_vs_cpu", false)
	if play_vs_cpu:
		intialize_cpu_player(2)

var is_mobile_browser: bool = false

func update_mobile_scale():
	is_mobile_browser = (
		OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)
	
	if is_mobile_browser:
		# selection_panel.scale = Vector2(2.5,2.5)
		scale_text_tree(get_tree().current_scene, 2.0 if is_mobile_browser else 1.0)
		selection_panel.pivot_offset = selection_panel.size
	else:
		# scale_text_tree(get_tree().current_scene, 2.0 if true else 1.0)
		# selection_panel.scale = Vector2(0.8,0.8)
		selection_panel.pivot_offset = selection_panel.size
		pass
	
		# SelectionPanel.scale = Vector2(3.0,3.0)


func resize_selection_image_to_text() -> void:
	var margin := selection_panel.get_child(0) as MarginContainer
	var root := margin.get_child(0) as VBoxContainer
	var row := root.get_child(0) as HBoxContainer
	var text_column := row.get_node("VBoxContainer") as VBoxContainer
	var image_panel := row.get_node("PanelContainer") as PanelContainer

	await get_tree().process_frame

	var side := maxf(text_column.size.y, 120.0)
	image_panel.custom_minimum_size = Vector2(side, side)

func scale_text_tree(node: Node, factor: float) -> void:
	if node is RichTextLabel:
		var label := node as RichTextLabel

		for size_name in ["normal_font_size", "bold_font_size"]:
			var meta_name = "base_" + size_name
			if not label.has_meta(meta_name):
				label.set_meta(meta_name, label.get_theme_font_size(size_name))

			var base_size: int = label.get_meta(meta_name)
			label.add_theme_font_size_override(
				size_name,
				roundi(base_size * factor)
			)
	elif node is Label or node is Button or node is LineEdit or node is TextEdit:
		var control := node as Control
		if not control.has_meta("base_font_size"):
			control.set_meta(
				"base_font_size",
				control.get_theme_font_size("font_size")
			)

		var base_size: int = control.get_meta("base_font_size")
		control.add_theme_font_size_override(
			"font_size",
			roundi(base_size * factor)
		)

	for child in node.get_children():
		scale_text_tree(child, factor)

	resize_selection_image_to_text()

func intialize_drawn_sprite_nodes():
	rotate_sprites = Node2D.new()
	rotate_sprites.z_index = 3
	add_child(rotate_sprites)

	capture_sprites = Node2D.new()
	capture_sprites.z_index = 3
	add_child(capture_sprites)



func instantiate_turn_menu():
	# Apply the styling wrapper dynamically without changing the original variable
	turn_label.bbcode_enabled = true
	turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	turn_label.fit_content = true

	var raw_message = "Player 1's Turn"
	turn_label.text = "[outline_size=10][outline_color=black][b][color=cyan]%s[/color][/b]" % raw_message

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


func update_turn_text():
	if current_player == 1:
		var raw_message = "Player 1's Turn"
		turn_label.text = "[outline_size=10][outline_color=black][b][color=cyan]%s[/color][/b]" % raw_message
		if(cpu_player != null):
			display_turn_message()
	else:
		var raw_message = "Player 2's Turn"
		turn_label.text = "[outline_size=10][outline_color=black][b][color=red]%s[/color][/b]" % raw_message

	if(cpu_player == null):
		display_turn_message()

	update_mobile_scale()


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
	var raw_message = "Player "+str(winner)+" WINS!"
	if winner == 1:
		win_label.text = raw_message
		win_label.modulate = GameColors.PLAYER_BLUE_POWER
	else:
		win_label.text = raw_message#"[outline_size=10][outline_color=black][font_size=200][b][color=red]%s[/color][/b][/font_size]" % raw_message
		win_label.modulate = GameColors.PLAYER_RED_POWER
	win_label.visible = true

func update_selection_panel(selectedPiece: Piece):
	var margin_container = selection_panel.get_child(0) as MarginContainer
	var v_box_root = margin_container.get_child(0) as VBoxContainer
	var h_box = v_box_root.get_child(0) as HBoxContainer
	for child in h_box.get_children():
		if child is PanelContainer:
			var tr = child.get_child(0) as TextureRect
			tr.texture = selectedPiece.sprite.texture
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
	print("winner " + str(winner))
	
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
var player_vision_tiles: Array[Array] = [[],[]]

func spawn_all_pieces():
	var num1 := randi_range(0, 5)
	var num2 := randi_range(0, 5)

	while (num2 == num1 || abs(num2 - num1) == 1 || abs(num2 - num1) == 5):
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

func spawn_player_location(center: Vector2i, player: int):
	print("WAHT player " + str(player))

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
		piece.z_index = 2
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


func remove_piece(piece: Piece):
	player_pieces[piece.owned_player - 1].erase(piece)
	pieces_container.remove_child(piece)

func get_enemy_piece_at_cell(cell: Vector2i, player: int) -> Piece:
	for node in pieces_container.get_children():
		var piece := node as Piece

		if piece != null and piece.owned_player == player:
			var piece_cell = local_to_map(piece.position)

			if piece_cell == cell:
				return piece

	return null

func update_all_piece_vision(excluded_pieces: Array[Piece] = []):
	clear_board()
	print(str("Current player: ") + str(current_player))
	if(current_player == 1):
		for p in player_pieces[0]:
			if(!excluded_pieces.has(p)):
				print(p.getTypeString())
				p.draw_current_vision()
				p.update_piece_color()
		for p in player_pieces[0]:
			p.visible = true
		for p in player_pieces[1]:
			p.visible = false
			print("update hide all")
	else:
		if(cpu_player == null):
			for p in player_pieces[1]:
				if(!excluded_pieces.has(p)):
					print("updating vision for player 2")
					print(p.getTypeString())
					p.draw_current_vision()
					p.update_piece_color()
			for p in player_pieces[0]:
				p.visible = false
				print("update hide all")
			for p in player_pieces[1]:
				p.visible = true

	for i in player_pieces.size():
		for j in player_pieces[i].size():
			for v in player_pieces[i][j].cur_vision:
				player_vision_tiles[i].append(v)
				if (hasEnemyPieceInVision(current_player, v)):
					setEnemyPieceVisiblity(v, true)

	if(cpu_player == null || current_player == 1):
		update_core_power()

					

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
func set_take_piece_sprite(enemy_loc: Vector2i):
	# for child in capture_sprites.get_children():
	# 	child.queue_free()
	var sprite := Sprite2D.new()
	sprite.texture = capture_texture
	var world_position := map_to_local(enemy_loc)
	sprite.position = world_position
	# add_child(sprite)
	capture_sprites.add_child(sprite)

func clear_captures():
	for child in capture_sprites.get_children():
		child.queue_free()
	

	

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
	if(moved_piece.cur_vision.has(core.get_cur_pos())):
		if(core.power_count == 1):
			if(!moved_piece.get_potential_vision(new_move).has(core.get_cur_pos())):
				return true
	return false

func does_rotate_unpower_core(piece: TowerRotatePiece, first_rotate: bool) -> bool:
	var core = get_current_core()
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
	print("piece cell: " + str(target_cell) + " owned by player " + str(piece.owned_player))
	var attacked := false

	for attacker in player_pieces[attacker_player - 1]:
		for move in attacker.cur_moves:
			print("attacker: " + str(attacker) + " move: " + str(move))
		if attacker.cur_moves.has(target_cell):
			attacked = true
			if piece is CorePiece:
				attacker.visible = true
			break

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
	for child in get_children():
		if child is Line2D:
			child.queue_free()
	var current_core: = get_current_core()

	if current_core == null:
		return

	update_all_core_power_counts()

	#Pieces that can see Core
	var see_count = 0
	for p in player_pieces[(current_player + 1)%2]:
		if(!(p is CorePiece)):
			if (p.cur_vision.has(current_core.get_cur_pos())):
				var line := Line2D.new()
				line.points = PackedVector2Array([
					Vector2(current_core.position.x, current_core.position.y),
					Vector2(p.position.x, p.position.y)
				])
				line.width = 3.0
				line.z_index = 1
				
				current_core.update_piece_color()
				if(current_core.selected):
					line.default_color = Color.WHITE
				else:
					line.default_color = get_player_color(true)
				p.powered = true
				p.update_piece_color()
				add_child(line)
				see_count += 1
			else:
				p.powered = false
	update_core_text(see_count)
	current_core.power_count = see_count

	update_visible_enemy_core_highlights()

	if(game_setup_complete):
		var winner := determine_winner()
		if winner != 0:
			display_winner(winner)
			return

	# if(see_count == 0):
	# 	display_winner(determine_winner())

	if(is_piece_under_attack(current_core) and !displayed_warning_text):
		display_core_attack()

func update_all_core_power_counts() -> void:
	for player_id in [1, 2]:
		var core: CorePiece = null

		for node in player_pieces[player_id - 1]:
			if node is CorePiece:
				core = node as CorePiece
				break

		if core == null:
			continue

		var support_count := 0
		for node in player_pieces[player_id - 1]:
			var supporter := node as Piece
			if supporter == null or supporter == core:
				continue
			if supporter.cur_vision.has(core.get_cur_pos()):
				support_count += 1

		core.power_count = support_count

func update_visible_enemy_core_highlights() -> void:
	var enemy_player := 2 if current_player == 1 else 1
	var enemy_core: CorePiece = null

	for node in player_pieces[enemy_player - 1]:
		if node is CorePiece:
			enemy_core = node as CorePiece
			break

	if enemy_core == null:
		return

	var core_cell := enemy_core.get_cur_pos()

	# Don't reveal the opponent's core or its support unless the core is visible.
	if not hasCellInVision(current_player, core_cell):
		return

	var visible_support_count := 0

	for node in player_pieces[enemy_player - 1]:
		var supporter := node as Piece
		if supporter == null or supporter is CorePiece:
			continue

		# Only show information about opposing pieces the current player can see.
		if not hasCellInVision(current_player, supporter.get_cur_pos()):
			continue

		var supports_core := supporter.cur_vision.has(core_cell)
		supporter.powered = supports_core
		supporter.update_piece_color()

		if not supports_core:
			continue

		var line := Line2D.new()
		line.points = PackedVector2Array([
			Vector2(enemy_core.position.x, enemy_core.position.y),
			Vector2(supporter.position.x, supporter.position.y)
		])
		line.width = 3.0
		line.z_index = 1
		line.default_color = (
			GameColors.PLAYER_BLUE_POWER
			if enemy_player == 1
			else GameColors.PLAYER_RED_POWER
		)
		add_child(line)
		visible_support_count += 1

	# Tint the visible enemy core based only on the support the player can see.
	enemy_core.powered = visible_support_count > 0
	enemy_core.update_piece_color()

func display_core_attack():
	print("core under attack")
	var text_timer := Timer.new()
	text_timer.wait_time = 1.5
	text_timer.one_shot = true
	text_timer.timeout.connect(_on_core_attack_timer_timeout)
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
	match current_player:
		1: 
			if(powered):
				return GameColors.PLAYER_BLUE_POWER
			return GameColors.PLAYER_BLUE
		2: 
			if(powered):
				return GameColors.PLAYER_RED_POWER
			return GameColors.PLAYER_RED
	return Color.WHITE

func setEnemyPieceVisiblity(cell: Vector2i, visible:bool) -> void:
	var enemy_player = 2 if current_player == 1 else 1
	for p in player_pieces[enemy_player - 1]:
		if(cell == p.get_cur_pos()):
			p.visible = visible
			print("set enemy piece visibility")
	return

func clear_board():
	print("clear")
	for c in board_tiles:
		set_cell(c, Tiles.BLACK, Vector2i(0,0))
	update_rotate_map_board()


func deselect_all_pieces(excluded_pieces: Array[Piece] = []):
	for p in pieces_container.get_children():
		if(!excluded_pieces.has(p)):
			# print(["excluded_log", self.local_to_map(p.position)])
			p.selected = false
		p.update_piece_color()
	update_core_power()
	clear_captures()

func end_turn(movedPiece: Piece):
	var core_found = false
	clear_captures()
	displayed_warning_text = false
	if(cpu_player == null or current_player != cpu_player.player_number):
		await update_move_camera(movedPiece)
	for i in get_enemy_player_numbers():
		for p in player_pieces[i - 1]:
			if(p is CorePiece):
				core_found = true
	if(core_found):
		var potential_winner = determine_winner()
		if(potential_winner == 0):
			if(cpu_player != null):
				end_turn_vs_cpu()
			else:
				turn_menu.show()
		else:
			display_winner(potential_winner)
	else:
		display_winner(current_player)

func end_turn_vs_cpu():
	current_player = 2 if current_player == 1 else 1
	if current_player == cpu_player.player_number:
		cpu_player.take_turn()
	else:
		update_turn_text()
		update_all_piece_vision()
		turn_menu.hide()


func update_move_camera(movedPiece: Piece):
	update_all_piece_vision()
	if(movedPiece.owned_player == current_player):
		await camera.zoom_to_global_position(
			movedPiece.global_position,
			camera.zoom.x
		)
	else:
		if(player_last_moves.size() == player_pieces.size()):
			await camera.zoom_to_global_position(
				player_last_moves[current_player - 1].global_position,
				camera.zoom.x
			)

	if(player_last_moves.size() < 2):
		player_last_moves.append(movedPiece)
	else:
		player_last_moves[current_player - 1] = movedPiece


func get_enemy_player_numbers():
	var enemy_players: Array[int] = []
	for i in range(player_pieces.size()) :
		if(i+1) != current_player:
			enemy_players.append((i + 1))
	# print(enemy_players)
	return enemy_players


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
		# print(["curAni xy", cur_ani_x, cur_ani_y, "index|offset", ani_index, ani_offset])
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
		# print(["unhandle board", cell])

		var tile_pos = map_to_local(Vector2i(3, 4))
		# print(tile_pos)



func draw_hex_around(center: Vector2i) :
	var curTile = 0
	if(current_player == 1):
		curTile = 11		
	else:
		curTile = 9
	
	if(center.y % 2 ==  0): 
		# print("even")
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
		# print("odd")
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
			# print(["offset", offset, center_even])
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
		# print(["offset", offset_pos,"i", i, center])
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
		# print(["offset", offset_pos,"i", i, center])
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
		# print(["offset", offset_pos,"i", i, center])

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
	# print(["hexline", cells])
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

func move_camera_to_core():
	var core = get_current_core()
	camera.zoom_to_global_position(core.position,0.6)
	# for p in pieces_container.get_children():
	# 	if(p is CorePiece and p.owned_player == current_player):
	update_selection_panel(core)

func _on_next_pressed() -> void:
	var enemy_eye = false
	for p in pieces_container.get_children():
		if(p is EyePiece and p.owned_player != current_player):
			enemy_eye = true
	current_player = 2 if current_player == 1 else 1
	update_turn_text()
	update_all_piece_vision()
	move_camera_to_core()
	turn_menu.hide()
	if(player_last_moves.size() == player_pieces.size()):
		await update_move_camera(
			player_last_moves[current_player - 1]
		)


func _on_stay_button_pressed() -> void:
	update_turn_text()
	update_all_piece_vision()
	turn_menu.hide()

@onready var music_player: AudioStreamPlayer2D = $"../AudioStreamPlayer2D"


func _on_pause_pressed() -> void:
	settings_cover.visible = true


func _on_continue_pressed() -> void:
	settings_cover.visible = false

func _on_check_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		music_player.play()
	else:
		music_player.stop()
