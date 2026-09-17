extends Piece
class_name TriangleEvenPiece

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func setup(inital_pos: Vector2i, b: TileMapLayer) -> void:
	super.setup(inital_pos, b)
	sprite.texture = preload("res://sprites/TriangleOdd.png")

func on_clicked() -> void:
	if(owned_player != board.current_player):
		return
	if(position == null or board == null):
		return
	if(board.current_player != owned_player):
		return
	var cell = board.local_to_map(position)  # current tile cell
	cur_moves = []
	old_selected_tile_ids = []
	if(selected):
		selected = false
		board.deselect_all_pieces([self])
	else:
		for i in range(3):
			var raw_moves = board.get_line_from_center(cell, 1 + i*2, 6)
			for move in raw_moves:
				if(board.cell_in_board(move) and move != cell):
					cur_moves.append(move)
		for potential_move in cur_moves: 
			old_selected_tile_ids.append(board.get_cell_source_id(potential_move))
			if(owned_player == 2):
				board.set_cell(potential_move,Tiles.RED, Vector2i(0,0))
			else:
				board.set_cell(potential_move, Tiles.LIGHT_BLUE, Vector2i(0,0))

		selected = true
		board.deselect_all_pieces([self])
