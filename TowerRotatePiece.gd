extends Piece
class_name TowerRotatePiece


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("reached tower ready")
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

@onready var sprite: Sprite2D = $Sprite2D

func setup(inital_pos: Vector2i, b: TileMapLayer):
	super.setup(inital_pos, b)

	sprite.texture = preload("res://tower1.png")
	print([
		"towersprite", sprite, 
		"board", board, 
		"area",area
	])
	print("reached tower setup")
	
var cur_direction = 5
var cur_rotate: Array[Vector2i] = []
var old_selected_rotate_tile_ids: Array[int]= []

func draw_vision_change():
	var cur_pos = board.local_to_map(position)
	var raw_vision = board.get_triangle_tiles_from_center(cur_pos, 5, cur_direction)
	var new_vision: Array[Vector2i] = []
	
	for cell in raw_vision:
		if(board.cell_in_board(cell)):
			new_vision.append(cell)

	for cell in cur_vision:
		board.set_cell(cell,Tiles.BLACK, Vector2i(0,0))

	cur_vision = new_vision
	for cell in cur_vision:
		board.set_cell(cell,Tiles.DARK_BLUE, Vector2i(0,0))
			
	board.update_all_piece_vision([self])


func on_clicked():
	print("on_tower_clicked")
	if(board == null or position == null):
		return
	var cell = board.local_to_map(position)
	cur_moves = []
	cur_rotate = []
	old_selected_tile_ids = []
	old_selected_rotate_tile_ids = []
	if(selected):
		selected = false
		board.deselect_all_pieces([self])
	else:
		var first_axis = board.get_line_from_center(cell, cur_direction, 10)
		var second_axis = board.get_line_from_center(cell, (cur_direction + 1) % 6, 10)
		
		# for hex in first_axis: 
		# 	board.set_cell(hex, Tiles.DARK_RED, Vector2i(0,0))
		
		# for hex in second_axis: 
		# 	board.set_cell(hex, Tiles.HEX_STAR, Vector2i(0,0))
		

		for i in range(first_axis.size()):
			if(i%2 == 0):
				var connect_line = board.hex_line(first_axis[i], second_axis[i])

				# if(i == 2):
				# 	for hex in connect_line: 
				# 		board.set_cell(hex, Tiles.DARK_GREY, Vector2i(0,0))
				var potential_new_move = connect_line[(connect_line.size())/2]
				if(board.cell_in_board(potential_new_move) && cell != potential_new_move):
					cur_moves.append(potential_new_move)

		first_axis = board.get_line_from_center(cell, cur_direction, 10)
		second_axis = board.get_line_from_center(cell, (cur_direction - 1) % 6, 10)
		var connect_line = board.hex_line(first_axis[2], second_axis[2])
		var potential_new_move = connect_line[(connect_line.size())/2]
		if(board.cell_in_board(potential_new_move)):
			cur_rotate.append(potential_new_move)

		first_axis = board.get_line_from_center(cell, (cur_direction + 1) % 6, 10)
		second_axis = board.get_line_from_center(cell, (cur_direction + 2) % 6, 10)
		connect_line = board.hex_line(first_axis[2], second_axis[2])
		potential_new_move = connect_line[(connect_line.size())/2]
		if(board.cell_in_board(potential_new_move)):
			cur_rotate.append(potential_new_move)
		
				
		for potential_move in cur_moves: 
			old_selected_tile_ids.append(board.get_cell_source_id(potential_move))
			board.set_cell(potential_move, Tiles.LIGHT_BLUE, Vector2i(0,0))

		for potential_rotate in cur_rotate: 
			old_selected_rotate_tile_ids.append(board.get_cell_source_id(potential_rotate))
			board.set_cell(potential_rotate, Tiles.SNOW_FLAKE, Vector2i(0,0))
	

		selected = true
		board.deselect_all_pieces([self])
	

func handle_move_input_event(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var global_mouse = board.camera.get_global_mouse_position()
		var local_mouse = board.to_local(global_mouse)
		var cell = board.local_to_map(local_mouse)
		var found = false
		for i in range(cur_rotate.size()):
			if(cell == cur_rotate[i]):
				found = true
				if(i == 0):
					if cur_direction == 0:
						cur_direction = 5
					else:
						cur_direction = cur_direction - 1
				else:
					cur_direction = (cur_direction + 1) % 6
		if found:
			for i in range(cur_moves.size()):
				var old_move = cur_moves[i]
				board.set_cell(old_move, old_selected_tile_ids[i], Vector2i(0,0))
			for i in range(cur_rotate.size()):
				var old_move = cur_rotate[i]
				board.set_cell(old_move, old_selected_rotate_tile_ids[i], Vector2i(0,0))
			old_selected_tile_ids = []
			old_selected_rotate_tile_ids = []
			cur_moves = []
			cur_rotate = []
			draw_vision_change()
		else:
			for i in range(cur_rotate.size()):
				var old_move = cur_rotate[i]
				board.set_cell(old_move, old_selected_rotate_tile_ids[i], Vector2i(0,0))
			cur_rotate = []
			old_selected_rotate_tile_ids = []
			super.handle_move_input_event(event)
