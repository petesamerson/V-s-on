extends Node2D
class_name Piece


var Tiles = preload("res://tiles.gd")
const GameColors = preload("res://colors.gd")

var board: Board
var owned_player: int = 1
var vision_range: int = 3
var powered: bool = false

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

	if(owned_player == 1):
		sprite.modulate = GameColors.PLAYER_BLUE
	else:
		sprite.modulate = GameColors.PLAYER_RED

	self.z_index = 2
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
	var cur_pos = board.local_to_map(position)
	var raw_vision = board.get_hexagon_tiles(cur_pos, vision_range)
	var new_vision: Array[Vector2i] = []
	
	for cell in raw_vision:
		if(board.cell_in_board(cell)):
			new_vision.append(cell)

	for cell in cur_vision:
		board.set_cell(cell,Tiles.BLACK, Vector2i(0,0))

	cur_vision = new_vision
	for cell in cur_vision:
		if(owned_player == 2):
			board.set_cell(cell,Tiles.DARK_RED, Vector2i(0,0))
		else:
			board.set_cell(cell,Tiles.DARK_BLUE, Vector2i(0,0))

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
		if(owned_player == 2):
			board.set_cell(cell,Tiles.DARK_RED, Vector2i(0,0))
		else:
			board.set_cell(cell,Tiles.DARK_BLUE, Vector2i(0,0))
	

var armed := false

func _on_area_2d_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		on_clicked()
		armed = true

# func _unhandled_input(event: InputEvent) -> void:
# 	if event is InputEventMouseButton \
# 	and not event.pressed \
# 	and event.button_index == MOUSE_BUTTON_LEFT \
# 	and armed == true:
# 		armed = false
# 		on_clicked()
# 		print("UNHANDLED")
	

func on_clicked() -> void:
	if(owned_player != board.current_player):
		return
	if(position == null or board == null):
		return
	if(board.current_player != owned_player):
		return

	var cell = board.local_to_map(position)  # current tile cell
	print("Current cell:", cell , "selected", selected)
	cur_moves = []
	old_selected_tile_ids = []
	if(selected):
		selected = false
		update_piece_color()
		board.deselect_all_pieces([self])
	else:
		highlight_vision_range()
		for i in range(6):
			var raw_moves = board.get_line_from_center(cell, i, 6)
			for move in raw_moves:
				if(board.move_visible_and_unoccupied(move, cell, self)):
					cur_moves.append(move)
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

func update_capture_on_board():
	for move in cur_moves:
		var enemy_player = 2 if owned_player == 1 else 1
		if(board.get_enemy_piece_at_cell(move, enemy_player) != null):
			board.set_take_piece_sprite(move)

func highlight_vision_range():
	print("hightlight")
	for cell in cur_vision:
		if(owned_player == 1):
			board.set_cell(cell, Tiles.DARK_BLUE_OUTLINE, Vector2i(0,0))
		else:
			board.set_cell(cell, Tiles.DARK_RED_OUTLINE, Vector2i(0,0))
	

func update_piece_color():
	if sprite == null: return
	print("piece_color_update " + str(selected))
	if(selected):
		sprite.modulate = Color.WHITE
	else:
		if(owned_player == 1):
			if(powered):
				sprite.modulate = GameColors.PLAYER_BLUE_POWER
			else:
				sprite.modulate = GameColors.PLAYER_BLUE
		else:
			if(powered):
				sprite.modulate = GameColors.PLAYER_RED_POWER
			else:
				sprite.modulate = GameColors.PLAYER_RED

	


func _input(event):
	if(selected):
		handle_move_input_event(event)
		var viewport = get_viewport()
		if(viewport != null):
			get_viewport().set_input_as_handled()

func handle_move_input_event(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var global_mouse = board.camera.get_global_mouse_position()
		var local_mouse = board.to_local(global_mouse)
		var cell = board.local_to_map(local_mouse)
		var moved = false

		if cell in cur_moves:
			moving = true
			position = board.map_to_local(cell)

			var enemy_player = 1
			if(board.current_player == 1):
				enemy_player = 2
			var enemy_piece = board.get_enemy_piece_at_cell(cell, enemy_player)
			if enemy_piece != null:
				board.remove_piece(enemy_piece)

			for i in range(cur_moves.size()):
				var old_move = cur_moves[i]
				board.set_cell(old_move, old_selected_tile_ids[i], Vector2i(0,0))


			cur_moves = []
			old_selected_tile_ids = []
			selected = false
			moving = false
			moved = true
		else:
			for i in range(cur_moves.size()):
				var old_move = cur_moves[i]
				board.set_cell(old_move, old_selected_tile_ids[i], Vector2i(0,0))

			selected = false
			board.deselect_all_pieces([self])
			
			old_selected_tile_ids = []
			cur_moves = []

		draw_vision_change()
		if(moved):
			end_turn()

		# #debug
		# print("Lines Arrive")
		# for i in range(0,6):
		# 	print(["line", i, 8 + i, "center", cell])
		# 	board.draw_line_from_center(cell, i, 13, 9)


func _equals(other) -> bool:
	if other is Piece:
		return self.position == other.position	
	return false
	

func getTypeString() -> String:
	return "Piece";
