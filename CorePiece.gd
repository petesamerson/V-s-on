
extends Piece
class_name CorePiece

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	pass


func setup(inital_pos: Vector2i, b: TileMapLayer):
	super.setup(inital_pos, b)

	sprite.texture = preload("res://sprites/core_piece.png")
	vision_range = 0
	z_index = 0
	powered = true


func draw_vision_change():
	pass

var power_count = 8
var move_range = 2

func on_clicked() -> void:
	if board == null or position == null:
		return
	if owned_player != board.current_player:
		return

	var cell: Vector2i = board.local_to_map(position)
	print("Current cell:", cell , "selected", selected)

	if selected:
		selected = false
		board.deselect_all_pieces([self])
		board.update_all_piece_vision([self])
		update_piece_color()
		board.update_core_power()
		return

	cur_moves.clear()
	old_selected_tile_ids.clear()
	for direction in range(6):
		var raw_moves = board.get_line_from_center(cell, direction, move_range)
		for move in raw_moves:
			if board.cell_in_board(move) and move != cell:
				if(!board.friendlyPieceExistsAtCell(owned_player,move)):
					cur_moves.append(move)

	for potential_move in cur_moves:
		old_selected_tile_ids.append(board.get_cell_source_id(potential_move))
		var highlight = Tiles.RED if owned_player == 2 else Tiles.LIGHT_BLUE
		board.set_cell(potential_move, highlight, Vector2i.ZERO)

	selected = true
	update_piece_color()
	board.update_core_power()
	board.deselect_all_pieces([self])
	update_capture_on_board()