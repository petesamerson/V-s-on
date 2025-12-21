extends Node2D
class_name Piece


var board: TileMapLayer

var Tiles = preload("res://tiles.gd")


func _init() -> void:
	pass
	
func setup(inital_pos: Vector2i, b: TileMapLayer):
	if(inital_pos == null):
		return
	board = b
	position = board.map_to_local(inital_pos)
	$Area2D.input_event.connect(_on_area_2d_input_event)
	self.z_index = 1

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	# position = board.map_to_local(Vector2i(5, 5))
	# $Area2D.input_event.connect(_on_area_2d_input_event)
	# self.z_index = 1


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if(!vision_drawn):
		draw_vision()
		vision_drawn = true
	pass


var cur_moves : Array[Vector2i] = []
var selected = false

var cur_vision: Array[Vector2i] = []
var vision_drawn = false

func draw_vision():
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
			

func _on_area_2d_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell = board.local_to_map(position)  # current tile cell
		print("Current cell:", cell)
		if(selected):
			cur_moves = []
			selected = false
		else:
			cur_moves = []
			for i in range(6):
				var raw_moves = board.get_line_from_center(cell, i, 10)
				for move in raw_moves:
					if(board.cell_in_board(move)):
						cur_moves.append(move)
			for potential_move in cur_moves: 
				board.set_cell(potential_move, Tiles.LIGHT_BLUE, Vector2i(0,0))
			selected = true

func _input(event):
	if(selected):
		handle_move_input_event(event)

func handle_move_input_event(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var global_mouse = board.camera.get_global_mouse_position()
		var local_mouse = board.to_local(global_mouse)
		var cell = board.local_to_map(local_mouse)
		# board.draw_line_from_center(cell, 0,10, 3)

		print(["handle move"], cell, cur_moves)
		if cell in cur_moves:
			position = board.map_to_local(cell)
			for old_move in cur_moves:
				board.set_cell(old_move, Tiles.BLACK, Vector2i(0,0))
			cur_moves = []
		else:
			for old_move in cur_moves:
				board.set_cell(old_move, Tiles.BLACK, Vector2i(0,0))
			cur_moves = []

		vision_drawn = false

		# #debug
		# print("Lines Arrive")
		# for i in range(0,6):
		# 	print(["line", i, 8 + i, "center", cell])
		# 	board.draw_line_from_center(cell, i, 13, 9)


	
	
