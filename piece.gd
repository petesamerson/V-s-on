extends Node2D
class_name Piece


var Tiles = preload("res://tiles.gd")
const GameColors = preload("res://colors.gd")

var board: Board
var owned_player: int = 1
var vision_range: int = 3
var move_range: = 6
var piece_value = 0
var powered: bool = false

var effects: Node2D
var movement_tween: Tween
var sprite_rest_position := Vector2.ZERO
var shimmer_material: ShaderMaterial

@onready var area: Area2D = $Area2D
@onready var sprite: Sprite2D = $Sprite2D

func _init() -> void:
	pass
	
func setup(inital_pos: Vector2i, b: TileMapLayer):
	if(inital_pos == null):
		return
	board = b
	position = board.map_to_local(inital_pos)

	area.input_event.connect(_on_area_2d_input_event)

	sprite_rest_position = sprite.position
	shimmer_material = ShaderMaterial.new()
	shimmer_material.shader = preload("res://piece_shimmer.gdshader")
	if not AppSettings.settings_changed.is_connected(_apply_graphics_settings):
		AppSettings.settings_changed.connect(_apply_graphics_settings)
	_apply_graphics_settings()
	update_piece_color()

	if not is_instance_valid(effects):
		effects = preload("res://piece_effects.gd").new()
		effects.piece = self
		board.add_child(effects)
		effects.z_index = 3
		tree_exiting.connect(effects.queue_free)

	self.z_index = 4
	draw_vision_change()
	
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	# position = board.map_to_local(Vector2i(5, 5))
	# $Area2D.input_event.connect(_on_area_2d_input_event)
	# self.z_index = 1


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# if(!vision_drawn):
	# 	draw_vision_change()
	# 	vision_drawn = true
	pass

func _apply_graphics_settings() -> void:
	if AppSettings.low_graphics:
		sprite.material = null
	else:
		sprite.material = shimmer_material

	update_piece_color()

var cur_moves : Array[Vector2i] = []
var selected = false
var moving = false
var old_selected_tile_ids: Array[int] = []

var cur_vision: Array[Vector2i] = []
var vision_drawn = false

#TODO rename for board position
func get_cur_pos() -> Vector2i:
	if(board == null or position == null):
		return Vector2i(0,0)
	return board.local_to_map(position)

func draw_vision_change():
	var cur_pos := board.local_to_map(position)
	var raw_vision = board.get_hexagon_tiles(
		cur_pos, vision_range
	)

	cur_vision.clear()

	for cell in raw_vision:
		if board.cell_in_board(cell):
			cur_vision.append(cell)

	if board.game_setup_complete:
		board.call_deferred("update_all_piece_vision")

func get_potential_vision(new_pos: Vector2i) -> Array[Vector2i]:
	var cur_pos = board.local_to_map(position)
	var raw_vision = board.get_hexagon_tiles(new_pos, vision_range)
	var new_vision: Array[Vector2i] = []
	
	for cell in raw_vision:
		if(board.cell_in_board(cell)):
			new_vision.append(cell)
	return new_vision

func end_turn():
	board.end_turn(self)

func draw_current_vision():
	for cell in cur_vision:
		board.draw_player_vision(cell, owned_player)
	

var armed := false

func _on_area_2d_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		if inspect_enemy_piece():
			armed = false
			get_viewport().set_input_as_handled()
			return

		on_clicked()
		if board.tutorial_mode and selected and can_control_piece():
			board.tutorial_piece_selected.emit(self)
		armed = true

func inspect_enemy_piece() -> bool:
	if not is_instance_valid(board):
		return false
	if not board.game_setup_complete:
		return false

	var viewer: int = board.get_viewer_player()
	if owned_player == viewer:
		return false
	if not board.hasCellInVision(viewer, get_cur_pos()):
		return false

	# Panel only: never set selected or generate highlights.
	board.update_selection_panel(self)
	return true

func can_control_piece() -> bool:
	if board == null or board.cpu_turn_in_progress:
		return false
	if board.online_game and board.online_disconnected:
		return false	
	if owned_player != board.current_player:
		return false
	if board.online_game and owned_player != board.local_player:
		return false
	if is_instance_valid(board.cpu_player):
		if owned_player == board.cpu_player.player_number:
			return false
	return true

func on_clicked() -> void:
	if not can_control_piece():
		return

	var cell = board.local_to_map(position)  # current tile cell
	print("Current cell:", cell , "selected", selected)
	old_selected_tile_ids = []
	if(selected):
		selected = false
		update_piece_color()
		board.deselect_all_pieces([self])
	else:
		highlight_vision_range()
		generate_possible_moves(cell)
		for potential_move in cur_moves: 
			old_selected_tile_ids.append(board.get_cell_source_id(potential_move))
			if(owned_player == 2):
				board.set_cell(potential_move,Tiles.RED, Vector2i(0,0))
			else:
				board.set_cell(potential_move, Tiles.LIGHT_BLUE, Vector2i(0,0))

		selected = true
		update_piece_color()
		board.deselect_all_pieces([self])
		update_capture_on_board()

func generate_possible_moves(cur_location: Vector2i) -> Array[Vector2i]:
	cur_moves = []
	for i in range(6):
		var raw_moves = board.get_line_from_center(cur_location, i, move_range)
		for move in raw_moves:
			if(board.move_visible_and_unoccupied(move, cur_location, self)):
				cur_moves.append(move)
	return cur_moves

func update_capture_on_board():
	board.clear_captures()

	for cell in cur_moves:
		if not board.hasCellInVision(owned_player, cell):
			continue

		for player_id in range(1, board.player_pieces.size() + 1):
			if player_id == owned_player:
				continue

			if board.get_enemy_piece_at_cell(
				cell,
				player_id
			) != null:
				board.set_take_piece_sprite(cell)
				break

# func highlight_vision_range():
# 	print("hightlight")
# 	for cell in cur_vision:
# 		if(owned_player == 1):
# 			board.set_cell(cell, Tiles.DARK_BLUE_OUTLINE, Vector2i(0,0))
# 		else:
# 			board.set_cell(cell, Tiles.DARK_RED_OUTLINE, Vector2i(0,0))

# 	board.update_selection_panel(self)
func highlight_vision_range():
	board.update_selection_panel(self)

# func update_piece_color():
# 	if sprite == null: return
# 	print("piece_color_update " + str(selected))
# 	if(selected):
# 		sprite.modulate = Color.WHITE
# 	else:
# 		if(owned_player == 1):
# 			if(powered):
# 				sprite.modulate = GameColors.PLAYER_BLUE_POWER
# 			else:
# 				sprite.modulate = GameColors.PLAYER_BLUE
# 		else:
# 			if(powered):
# 				sprite.modulate = GameColors.PLAYER_RED_POWER
# 			else:
# 				sprite.modulate = GameColors.PLAYER_RED

func update_piece_color():
	if sprite == null:
		return

	var color: Color = GameColors.player_color(owned_player)

	if powered:
		color = GameColors.powered_color(owned_player)

	sprite.modulate = color

	if shimmer_material != null:
		var strength: float = 0.0
		var speed: float = 0.25

		if powered:
			strength = 0.7 if selected else 0.4
		elif selected:
			strength = 0.7
			speed = 0.55

		shimmer_material.set_shader_parameter(
			"shimmer_strength", strength
		)
		shimmer_material.set_shader_parameter(
			"shimmer_speed", speed
		)
		shimmer_material.set_shader_parameter(
			"shimmer_phase",
			fposmod(float(owned_player - 1) * 0.17, 1.0)
		)

# func _input(event):
# 	if not selected or not can_control_piece():
# 		return

# 	if (
# 		event is InputEventMouseButton
# 		and event.pressed
# 		and event.button_index == MOUSE_BUTTON_LEFT
# 	):
# 		var mouse_cell: Vector2i = board.local_to_map(
# 			board.to_local(board.camera.get_global_mouse_position())
# 		)
# 		var enemy := board.get_enemy_piece_at_cell(
# 			mouse_cell, 3 - owned_player
# 		) as Piece

# 		# Legal capture clicks continue through normal move handling.
# 		if is_instance_valid(enemy) and not cur_moves.has(mouse_cell):
# 			# Restore existing highlights and deselect normally.
# 			handle_move_input_event(event)
# 			enemy.inspect_enemy_piece()
# 			get_viewport().set_input_as_handled()
# 			return
# 		handle_move_input_event(event)
# 		get_viewport().set_input_as_handled()
func _unhandled_input(event: InputEvent) -> void:
	if not selected or not can_control_piece():
		return

	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return

	var mouse_cell: Vector2i = board.local_to_map(
		board.to_local(board.camera.get_global_mouse_position())
	)
	# A selected tower's rotation markers take priority.
	if self is TowerRotatePiece:
		var tower := self as TowerRotatePiece

		for pivot in tower.rotate_map.values():
			if board.cell_in_board(pivot) and mouse_cell == pivot:
				get_viewport().set_input_as_handled()
				tower.handle_move_input_event(event)
				return

	# Switch directly to another friendly piece.
	for node in board.player_pieces[owned_player - 1]:
		var friendly := node as Piece

		if not is_instance_valid(friendly) or friendly == self:
			continue
		if friendly.get_cur_pos() != mouse_cell:
			continue
		if not friendly.can_control_piece():
			continue

		get_viewport().set_input_as_handled()

		armed = false
		board.deselect_all_pieces()
		board.update_all_piece_vision()

		friendly.on_clicked()
		friendly.armed = true
		board.update_selection_panel(friendly)

		if board.tutorial_mode and friendly.selected:
			board.tutorial_piece_selected.emit(friendly)

		return

	var enemy := board.get_enemy_piece_at_cell(
		mouse_cell,
		3 - owned_player
	) as Piece

	# Preserve inspection of enemies outside legal capture moves.
	if is_instance_valid(enemy) and not cur_moves.has(mouse_cell):
		handle_move_input_event(event)
		enemy.inspect_enemy_piece()
		get_viewport().set_input_as_handled()
		return

	handle_move_input_event(event)
	get_viewport().set_input_as_handled()

func handle_move_input_event(event):
	if not can_control_piece():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var global_mouse = board.camera.get_global_mouse_position()
		var local_mouse = board.to_local(global_mouse)
		var cell = board.local_to_map(local_mouse)
		var from_cell = board.local_to_map(position)
		var moved = false

		if cell in cur_moves:
			move_piece(cell)
			moved = true
		else:
			for i in range(cur_moves.size()):
				var old_move = cur_moves[i]
				if(old_selected_tile_ids.size() > i):
					board.set_cell(old_move, old_selected_tile_ids[i], Vector2i(0,0))

			selected = false
			board.deselect_all_pieces([self])
			
			old_selected_tile_ids = []
			cur_moves = []

		draw_vision_change()

		if(moved):
			if board.tutorial_mode:
				board.tutorial_piece_moved.emit(self)
			if board.online_game and owned_player == board.local_player:
				NetworkManager.send_game_message({
					"action": "move",
					"from": [from_cell.x, from_cell.y],
					"to": [cell.x, cell.y]
				})
			end_turn()

		# #debug
		# print("Lines Arrive")
		# for i in range(0,6):
		# 	print(["line", i, 8 + i, "center", cell])
		# 	board.draw_line_from_center(cell, i, 13, 9)

# func move_piece(move: Vector2i):
# 	moving = true
# 	position = board.map_to_local(move)

# 	var enemy_player = 1
# 	if(board.current_player == 1):
# 		enemy_player = 2
# 	var enemy_piece = board.get_enemy_piece_at_cell(move, enemy_player)
# 	if enemy_piece != null:
# 		board.last_capture_capturer_ids[board.current_player - 1] = get_instance_id()
# 		board.add_capture_feed_entry(self, enemy_piece)
# 		board.remove_piece(enemy_piece)
# 		for i in range(cur_moves.size()):
# 			var old_move = cur_moves[i]
# 			if(old_selected_tile_ids.size() > i):
# 				board.set_cell(old_move, old_selected_tile_ids[i], Vector2i(0,0))

# 	cur_moves = []
# 	old_selected_tile_ids = []
# 	selected = false
# 	moving = false
func move_piece(move: Vector2i):
	moving = true

	var previous_position := position
	var visual_position := position + sprite.position

	# Move the logical piece immediately so existing turn,
	# vision, CPU, and networking code keeps working.
	position = board.map_to_local(move)

	# Animate the sprite toward its new logical position.
	if movement_tween != null and movement_tween.is_valid():
		movement_tween.kill()

	sprite.position = visual_position - position

	movement_tween = create_tween()
	movement_tween.tween_property(
		sprite,
		"position",
		sprite_rest_position,
		0.24
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var enemy_player = 1
	if board.current_player == 1:
		enemy_player = 2

	var enemy_piece = board.get_enemy_piece_at_cell(
		move,
		enemy_player
	)

	if is_instance_valid(board.board_effects):
		board.board_effects.record_move(
			previous_position,
			position,
			owned_player
		)

	if is_instance_valid(effects):
		effects.add_move(
			previous_position,
			position,
			enemy_piece != null
		)

	if enemy_piece != null:
		board.last_capture_capturer_ids[
			board.current_player - 1
		] = get_instance_id()

		board.add_capture_feed_entry(self, enemy_piece)
		board.remove_piece(enemy_piece)

		for i in range(cur_moves.size()):
			var old_move = cur_moves[i]

			if old_selected_tile_ids.size() > i:
				board.set_cell(
					old_move,
					old_selected_tile_ids[i],
					Vector2i.ZERO
				)

	cur_moves = []
	old_selected_tile_ids = []
	selected = false
	moving = false
	update_piece_color()

func make_cpu_move(move: Vector2i):
	move_piece(move)
	draw_vision_change()
	end_turn()



func _equals(other) -> bool:
	if other is Piece:
		return self.position == other.position	
	return false
	

func getTypeString() -> String:
	return "Piece";

func getTypedDescription() -> String:
	return "This is the Piece that all Pieces are a clone of"
