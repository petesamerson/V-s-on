extends Node2D
class_name Piece


var board: Board
var Tiles = preload("res://tiles.gd")

@onready var area: Area2D = $Area2D

func _init() -> void:
	pass
	
func setup(inital_pos: Vector2i, b: TileMapLayer):
	if(inital_pos == null):
		return
	board = b
	position = board.map_to_local(inital_pos)

	area.input_event.connect(_on_area_2d_input_event)

	self.z_index = 1
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

func draw_vision_change():
	var cur_pos = board.local_to_map(position)
	var raw_vision = board.get_hexagon_tiles(cur_pos, 5)
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

func draw_current_vision():
	for cell in cur_vision:
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
		if(position == null or board == null):
			return
		var cell = board.local_to_map(position)  # current tile cell
		print("Current cell:", cell , "selected", selected)
		cur_moves = []
		old_selected_tile_ids = []
		if(selected):
			selected = false
			board.deselect_all_pieces([self])
		else:
			for i in range(6):
				var raw_moves = board.get_line_from_center(cell, i, 6)
				for move in raw_moves:
					if(board.cell_in_board(move) && move != cell):
						cur_moves.append(move)
			for potential_move in cur_moves: 
				old_selected_tile_ids.append(board.get_cell_source_id(potential_move))
				board.set_cell(potential_move, Tiles.LIGHT_BLUE, Vector2i(0,0))

			selected = true
			board.deselect_all_pieces([self])


func _input(event):
	if(selected):
		handle_move_input_event(event)
		get_viewport().set_input_as_handled()

func handle_move_input_event(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var global_mouse = board.camera.get_global_mouse_position()
		var local_mouse = board.to_local(global_mouse)
		var cell = board.local_to_map(local_mouse)

		if cell in cur_moves:
			moving = true
			position = board.map_to_local(cell)
			for i in range(cur_moves.size()):
				var old_move = cur_moves[i]
				board.set_cell(old_move, old_selected_tile_ids[i], Vector2i(0,0))

			cur_moves = []
			old_selected_tile_ids = []
			selected = false
			moving = false
		else:
			for i in range(cur_moves.size()):
				var old_move = cur_moves[i]
				board.set_cell(old_move, old_selected_tile_ids[i], Vector2i(0,0))

			selected = false
			board.deselect_all_pieces([self])
			
			old_selected_tile_ids = []
			cur_moves = []

		draw_vision_change()

		# #debug
		# print("Lines Arrive")
		# for i in range(0,6):
		# 	print(["line", i, 8 + i, "center", cell])
		# 	board.draw_line_from_center(cell, i, 13, 9)


func _equals(other) -> bool:
	if other is Piece:
		return self.position == other.position	
	return false
	
