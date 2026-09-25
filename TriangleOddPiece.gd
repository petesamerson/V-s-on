extends Piece
class_name TriangleOddPiece

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	pass


func setup(inital_pos: Vector2i, b: TileMapLayer):
	super.setup(inital_pos, b)

	sprite.texture = preload("res://sprites/triangle_piece.png")
	vision_range = 3

func on_clicked() -> void:
	if board == null or position == null:
		return
	if owned_player != board.current_player:
		return

	highlight_vision_range()

	var cell: Vector2i = board.local_to_map(position)
	print("Current cell:", cell , "selected", selected)

	if selected:
		selected = false
		board.deselect_all_pieces([self])
		update_piece_color()
		return

	cur_moves.clear()
	old_selected_tile_ids.clear()
	for direction in range(3):
		var raw_moves = board.get_line_from_center(cell, direction * 2, move_range)
		for move in raw_moves:
			if board.move_visible_and_unoccupied(move,cell,self):
				cur_moves.append(move)

	for potential_move in cur_moves:
		old_selected_tile_ids.append(board.get_cell_source_id(potential_move))
		var highlight = Tiles.RED if owned_player == 2 else Tiles.LIGHT_BLUE
		board.set_cell(potential_move, highlight, Vector2i.ZERO)

	selected = true
	update_piece_color()
	board.deselect_all_pieces([self])
	update_capture_on_board()

func getTypeString() -> String:
	return "Trihex";

func getTypedDescription() -> String:
	return "This piece can move in the 3 directions its triangle points to"