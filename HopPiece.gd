extends Piece 
class_name HopPiece


func _ready() -> void: 
	pass


func _process(delta: float) -> void:
	pass

@onready var sprite: Sprite2D = $Sprite2D

func setup(inital_pos: Vector2i, b: TileMapLayer):
	super.setup(inital_pos, b)

	sprite.texture = preload("res://sprites/Hop1.png")


func draw_vision_change(): 
	var cur_pos = board.local_to_map(position)
	var raw_vision = board.get_hexagon_tiles(cur_pos, 2)
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
			
	board.update_all_piece_vision([self])




func on_clicked() -> void:
	if(board == null or position == null): 
		return
	var cell = board.local_to_map(position)  # current tile cell
	# print(["Current cell:", cell , "selected", selected])
	print("CLICKED:", self, "ID:", get_instance_id(), "selected:", selected)

	cur_moves = []
	old_selected_tile_ids = []
	if(selected):
		selected = false
		print(["selected reached", selected])
		board.deselect_all_pieces([self])
	else:
		for i in range(6):
			var raw_moves = board.get_line_from_center(cell, i, 2)
			var move = raw_moves[raw_moves.size() - 1]
			if(board.cell_in_board(move)):
				cur_moves.append(raw_moves[raw_moves.size() - 1])
		for potential_move in cur_moves: 
			old_selected_tile_ids.append(board.get_cell_source_id(potential_move))
			if(owned_player == 2):
				board.set_cell(potential_move,Tiles.RED, Vector2i(0,0))
			else:
				board.set_cell(potential_move, Tiles.LIGHT_BLUE, Vector2i(0,0))
		selected = true

		board.deselect_all_pieces([self])
