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
	var cell = board.local_to_map(position)
	cur_moves = []
	old_selected_tile_ids = []
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
				if(board.cell_in_board(potential_new_move)):
					cur_moves.append(potential_new_move)
				
		for potential_move in cur_moves: 
			old_selected_tile_ids.append(board.get_cell_source_id(potential_move))
			board.set_cell(potential_move, Tiles.LIGHT_BLUE, Vector2i(0,0))
	

		selected = true
		board.deselect_all_pieces([self])
	
