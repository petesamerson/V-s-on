extends TileMapLayer
class_name Board

@export var camera: Camera2D
@onready var tilemap = $TileMap
@onready var turn_label: RichTextLabel = $"../CanvasLayer/TurnLabel"

var Tiles = preload("res://tiles.gd")

var board_center = Vector2i(10, 10)
var board_size = 10
var board_tiles: Array[Vector2i] = []


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.z_index = 0
	board_tiles = get_hexagon_tiles(board_center, board_size)
	for c in board_tiles:
		set_cell(c, Tiles.BLACK, Vector2i(0,0))

	call_deferred("spawn_pieces")

	# Apply the styling wrapper dynamically without changing the original variable
	turn_label.bbcode_enabled = true
	turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	turn_label.fit_content = true
	turn_label.size = Vector2(1000, 100)
	turn_label.set_anchors_preset(Control.PRESET_CENTER)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var viewport_size = get_viewport().get_visible_rect().size
	turn_label.position.x = (viewport_size.x - turn_label.size.x) / 2
	turn_label.position.y =  5

	var raw_message = "Player 1's Turn"
	turn_label.text = "[font_size=60][b][color=blue]%s[/color][/b][/font_size]" % raw_message

	# update_turn_text()
	pass # Replace with function body.

func update_turn_text():
	if current_player == 1:
		var raw_message = "Player 1's Turn"
		turn_label.text = "[font_size=60][b][color=blue]%s[/color][/b][/font_size]" % raw_message
	else:
		var raw_message = "Player 2's Turn"
		turn_label.text = "[font_size=60][b][color=red]%s[/color][/b][/font_size]" % raw_message

# Called every frame. 'delta' is the elapsed time since the previous frame.
var timer := 0.0
var interval := 0.25 #seconds

func _process(delta: float) -> void:
	timer += delta
	if timer >= interval:
		timer = 0.0
		# animate_board()

@onready var pieces_container = $Pieces
@onready var tilemap_layer = $TileMapLayer
@export var piece_scene: PackedScene
@export var tower_piece_scene: PackedScene
@export var hop_piece_scene: PackedScene

func spawn_pieces():
	var positions = [Vector2i(10,10)]
	for pos in positions:
		var piece := piece_scene.instantiate() as Piece
		pieces_container.add_child(piece)
		piece.setup(pos, self)

	var tower_piece := tower_piece_scene.instantiate() as TowerRotatePiece
	pieces_container.add_child(tower_piece)
	print(tower_piece is TowerRotatePiece)
	tower_piece.setup(
		Vector2i(15,15), 
		self 
	)

	var hop_piece := hop_piece_scene.instantiate() as HopPiece
	pieces_container.add_child(hop_piece)
	hop_piece.setup(
		Vector2i(5,5),
		self
	)

	var hop_piece_red := hop_piece_scene.instantiate() as HopPiece
	hop_piece_red.owned_player = 2
	pieces_container.add_child(hop_piece_red)
	hop_piece_red.setup(
		Vector2i(3,6),
		self
	)

	var piece_red := piece_scene.instantiate() as Piece
	piece_red.owned_player = 2
	pieces_container.add_child(piece_red)
	piece_red.setup(
		Vector2i(3,10),
		self
	)

	
		
		# piece.set_board_position(pos, tilemap)

func update_all_piece_vision(excluded_pieces: Array[Piece] = []):
	for p in pieces_container.get_children():
		if(!excluded_pieces.has(p)):
			p.draw_current_vision()

func deselect_all_pieces(excluded_pieces: Array[Piece] = []):
	for p in pieces_container.get_children():
		if(!excluded_pieces.has(p)):
			# print(["excluded_log", self.local_to_map(p.position)])
			p.selected = false

var current_player: int = 1

func end_turn():
	current_player = 2 if current_player == 1 else 1
	update_turn_text()

var cur_ani_x = 0
var cur_ani_y = 0
var x_ani = true
var ani_index = 0
var ani_offset = 0
func animate_board():
	var cur_range = (cur_ani_x + 1)*2
	if(cur_range == 0):
		cur_range = 2
	for i in range(cur_range):
		set_cell(Vector2i(cur_ani_x - ani_offset,cur_ani_y), 12, Vector2i(0,0))
		print(["curAni xy", cur_ani_x, cur_ani_y, "index|offset", ani_index, ani_offset])
		if(cur_ani_y % 2 == 1):
			ani_offset += 1
		cur_ani_y += 1
	cur_ani_y = 0
	ani_offset = 0 
	cur_ani_x += 1

func cell_in_board(cell: Vector2i) -> bool:
	return cell in board_tiles

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:

		var local = to_local(
			camera.get_global_mouse_position() - position
		)
		var cell = local_to_map(local)
		print(["unhandle board", cell])

		# set_cell(
		# 	cell, 
		# 	5,
		# 	Vector2i(0,0)
		# )
		# draw_hex_around(cell)
		# draw_horz_line(cell)
		# draw_forward_dia_line(cell)
		# draw_back_dia_line(cell)

		
		# # draw_vision_range(cell, 2)
		# if(player == 1) :
		# 	draw_hex_tile_line(cell, Vector2i(cell.x - 5, cell.y), 5)
		# 	player = 2
		# else:
		# 	draw_hex_tile_line(cell, Vector2i(cell.x + 5, cell.y), 5)
		# 	player = 1
		# draw_vision_range(cell,4)
		# draw_hex_tile_line(cell,Vector2i(cell.x + 5, cell.y + 5), 8)

		var tile_pos = map_to_local(Vector2i(3, 4))
		print(tile_pos)



func draw_hex_around(center: Vector2i) :
	var curTile = 0
	if(current_player == 1):
		curTile = 11		
	else:
		curTile = 9
	
	if(center.y % 2 ==  0): 
		print("even")
		set_cell(
			Vector2i(center.x - 1, center.y), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x , center.y - 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x + 1 , center.y - 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x + 1 , center.y + 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x , center.y + 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x + 1 , center.y), 
			curTile,
			Vector2i(0,0)
		)
	else:
		print("odd")
		set_cell(
			Vector2i(center.x - 1, center.y - 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x , center.y - 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x + 1 , center.y), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x - 1 , center.y ), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x , center.y + 1), 
			curTile,
			Vector2i(0,0)
		)
		set_cell(
			Vector2i(center.x - 1 , center.y + 1), 
			curTile,
			Vector2i(0,0)
		)

func get_line_end_from_center(center: Vector2i, direction, length: int):
	#clockwise
	var center_even = center.y % 2 == 0
	match direction:
		0: 
			var offset = 0
			if(center_even):
				offset = 1
			offset = offset + length / 2 
			return Vector2i(center.x + offset, center.y - length)	
		1: 
			return Vector2i(center.x + length, center.y)
		2: 
			var offset = 0
			if(center_even):
				offset = 1
			offset = offset + length / 2 
			return Vector2i(center.x + offset, center.y + length)
		3: 
			var offset = 1
			if(center_even):
				offset = 0
			offset = offset + length / 2 
			return Vector2i(center.x - offset, center.y + length)
		4:
			return Vector2i(center.x - length, center.y)
		5: 
			var offset = 1
			if(center_even):
				offset = 0
			offset = offset + length / 2 
			return Vector2i(center.x - offset, center.y - length)


func get_line_from_center(center: Vector2i, direction: int, length: int):
	#clockwise
	var center_even = center.y % 2 == 0
	match direction:
		0: 
			var offset = 0
			if(center_even):
				offset = 1
				if(length % 2 == 0):
					offset = offset - 1
			offset = offset + length / 2 
			print(["offset", offset, center_even])
			return hex_line(center, Vector2i(center.x + offset, center.y - length))	
		1: 
			return hex_line(center, Vector2i(center.x + length, center.y))
		2: 
			var offset = 0
			if(center_even):
				offset = 1
				if(length % 2 == 0):
					offset = offset - 1
			offset = offset + length / 2 
			return hex_line(center, Vector2i(center.x + offset, center.y + length))
		3: 
			var offset = 1
			if(center_even):
				offset = 0
			else:
				if(length % 2 == 0):
					offset = offset - 1
			offset = offset + length / 2 
			return hex_line(center,Vector2i(center.x - offset, center.y + length))
		4:
			return hex_line(center,Vector2i(center.x - length, center.y))
		5: 
			var offset = 1
			if(center_even):
				offset = 0
			else:
				if(length % 2 == 0):
					offset = offset - 1
			offset = offset + length / 2 
			return hex_line(center,Vector2i(center.x - offset, center.y - length))


func draw_line_from_center(center: Vector2i,direction: int, length: int, color: int):
	var cells = get_line_from_center(center, direction, length)
	for cell in cells:
		set_cell(cell, color, Vector2i(0,0))
	#clockwise
	# var center_even = center.y % 2 == 0
	# match direction:
	# 	0: 
	# 		var offset = 0
	# 		if(center_even):
	# 			offset = 1
	# 		offset = offset + length / 2 
	# 		draw_hex_tile_line(center, Vector2i(center.x + offset, center.y - length), color)
	# 	1: 
	# 		draw_hex_tile_line(center, Vector2i(center.x + length, center.y), color)
	# 	2: 
	# 		var offset = 0
	# 		if(center_even):
	# 			offset = 1
	# 		offset = offset + length / 2 
	# 		draw_hex_tile_line(center, Vector2i(center.x + offset, center.y + length), color)
	# 	3: 
	# 		var offset = 1
	# 		if(center_even):
	# 			offset = 0
	# 		offset = offset + length / 2 
	# 		draw_hex_tile_line(center, Vector2i(center.x - offset, center.y + length), color)
	# 	4:
	# 		draw_hex_tile_line(center, Vector2i(center.x - length, center.y), color)
	# 	5: 
	# 		var offset = 1
	# 		if(center_even):
	# 			offset = 0
	# 		offset = offset + length / 2 
	# 		draw_hex_tile_line(center, Vector2i(center.x - offset, center.y - length), color)
			

		
func draw_horz_line(center: Vector2i):
	var line_color_id = 3
	for i in range(5):
		set_cell(Vector2i(center.x + i, center.y), line_color_id, Vector2i(0,0))
		set_cell(Vector2i(center.x - i, center.y), line_color_id, Vector2i(0,0))

func draw_back_dia_line(center: Vector2i):
	var line_color_id = 8
	var offset_pos = 0
	if (center.y) % 2 == 0:
		offset_pos = 1
	
	var offset_neg = 1
	if (center.y) % 2 == 0:
		offset_neg = 0

	for i in range(1,6):
		print(["offset", offset_pos,"i", i, center])
		set_cell(Vector2i(center.x + offset_pos, center.y + i), line_color_id, Vector2i(0,0))
		set_cell(Vector2i(center.x - offset_neg, center.y - i), line_color_id, Vector2i(0,0))
		if (center.y + i) % 2 == 0:
			offset_pos += 1
		if (center.y + i) % 2 == 1:
			offset_neg += 1
		
func draw_forward_dia_line(center: Vector2i):
	var line_color_id = 12
	var offset_pos = 0
	if (center.y) % 2 == 0:
		offset_pos = 1
	
	var offset_neg = 1
	if (center.y) % 2 == 0:
		offset_neg = 0

	for i in range(1,6):
		print(["offset", offset_pos,"i", i, center])
		set_cell(Vector2i(center.x - offset_neg, center.y + i), line_color_id, Vector2i(0,0))
		set_cell(Vector2i(center.x + offset_pos, center.y - i), line_color_id, Vector2i(0,0))
		if (center.y + i) % 2 == 0:
			offset_pos += 1
		if (center.y + i) % 2 == 1:
			offset_neg += 1

func draw_vision_range(center: Vector2i, vision_range: int, color: int):
	var hex_color_id = color
	var offset_pos = 0
	if (center.y) % 2 == 0:
		offset_pos = 1
	
	var offset_neg = 1
	if (center.y) % 2 == 0:
		offset_neg = 0

	var minXTop = 10
	var minXBottom= 10

	for i in range(1,vision_range + 1):
		print(["offset", offset_pos,"i", i, center])

		# set_cell(Vector2i(center.x - offset_neg, center.y + i), 6, Vector2i(0,0))
		# set_cell(Vector2i(center.x + offset_pos, center.y + i), 6, Vector2i(0,0))

		#below
		draw_hex_tile_line(
			Vector2i(center.x - offset_neg, center.y + i), 
			Vector2i(center.x + offset_pos, center.y + i),
			hex_color_id
		)

		# above
		draw_hex_tile_line(
			Vector2i(center.x + offset_pos, center.y - i),	
			Vector2i(center.x - offset_neg, center.y - i),
			hex_color_id
		)

		var temp_color = 7
		draw_hex_tile_line(
			Vector2i(center.x - offset_neg, center.y + i), 
			Vector2i(center.x - i, center.y),
			temp_color
		)
		draw_hex_tile_line(
			Vector2i(center.x - offset_neg, center.y - i), 
			Vector2i(center.x - i, center.y),
			temp_color
		)

		draw_hex_tile_line(
			Vector2i(center.x + offset_pos, center.y + i), 
			Vector2i(center.x + i, center.y),
			temp_color
		)
		draw_hex_tile_line(
			Vector2i(center.x + offset_pos, center.y - i), 
			Vector2i(center.x + i, center.y),
			temp_color
		)

		# draw_hex_tile_line(
		# 	Vector2i(center.x - offset_neg, center.y + i), 
		# 	Vector2i(center.x - i, center.y),
		# 	temp_color
		# )

		set_cell(Vector2i(center.x + i, center.y), hex_color_id, Vector2i(0,0))
		set_cell(Vector2i(center.x - i, center.y), hex_color_id, Vector2i(0,0))

		# if(i == vision_range):
		# 	# center.y + i 
		# 	for x in range(center.x - offset_neg, center.x + offset_pos):
		# 		set_cell(Vector2i(x, center.y + i), hex_color_id, Vector2i(0,0))

		# 	#center.y - i
		# 	for x in range(center.x - offset_neg, center.x + offset_pos):
		# 		set_cell(Vector2i(x, center.y - i), hex_color_id, Vector2i(0,0))

			# center.y
			# draw_line( Vector2i(center.x - i,  center.y),Vector2i(center.x - offset_neg),hex_color_id , 2.0)
			# draw_hex_tile_line(Vector2i(center.x - i, center.y),Vector2i(center.x - offset_neg, center.y - i), hex_color_id)

		if (center.y + i) % 2 == 0:
			offset_pos += 1
		if (center.y + i) % 2 == 1:
			offset_neg += 1

func get_triangle_tiles_from_center(center: Vector2i, hex_radius: int, direction: int):

	var triangle_tiles: Array[Vector2i] = []

	var offset_pos = 0
	if (center.y) % 2 == 0:
		offset_pos = 1
	
	var offset_neg = 1
	if (center.y) % 2 == 0:
		offset_neg = 0

	for i in range(1,hex_radius + 1):
		match direction:
			0:
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x + offset_pos, center.y - i), 
						Vector2i(center.x + i, center.y),
					)
				)
			1:
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x + offset_pos, center.y + i), 
						Vector2i(center.x + i, center.y),
					)
				)
			2:
				# below
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x - offset_neg, center.y + i), 
						Vector2i(center.x + offset_pos, center.y + i),
					)
				)
			3:
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x - offset_neg, center.y + i), 
						Vector2i(center.x - i, center.y),
					)
				)
			4:
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x - offset_neg, center.y - i), 
						Vector2i(center.x - i, center.y),
					)
				)
			5:
				# above
				triangle_tiles.append_array(
					hex_line(
						Vector2i(center.x + offset_pos, center.y - i),	
						Vector2i(center.x - offset_neg, center.y - i),
					)
				)

	


		if(direction == 0 or direction == 1): 
			triangle_tiles.append(Vector2i(center.x + i, center.y))

		if(direction == 3 or direction == 4): 
			triangle_tiles.append(Vector2i(center.x - i, center.y))

		if (center.y + i) % 2 == 0:
			offset_pos += 1
		if (center.y + i) % 2 == 1:
			offset_neg += 1
		
	triangle_tiles.append(center)
	return triangle_tiles


func get_hexagon_tiles(center: Vector2i, hex_radius: int):
	var offset_pos = 0
	if (center.y) % 2 == 0:
		offset_pos = 1
	
	var offset_neg = 1
	if (center.y) % 2 == 0:
		offset_neg = 0

	var hexagon_tiles: Array[Vector2i] = []

	for i in range(1,hex_radius + 1):

		#below
		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x - offset_neg, center.y + i), 
				Vector2i(center.x + offset_pos, center.y + i),
			)
		)

		# above
		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x + offset_pos, center.y - i),	
				Vector2i(center.x - offset_neg, center.y - i),
			)
		)

		var temp_color = 7
		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x - offset_neg, center.y + i), 
				Vector2i(center.x - i, center.y),
			)
		)
	
		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x - offset_neg, center.y - i), 
				Vector2i(center.x - i, center.y),
			)
		)

		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x + offset_pos, center.y + i), 
				Vector2i(center.x + i, center.y),
			)
		)

		hexagon_tiles.append_array(
			hex_line(
				Vector2i(center.x + offset_pos, center.y - i), 
				Vector2i(center.x + i, center.y),
			)
		)


		hexagon_tiles.append(Vector2i(center.x + i, center.y))
		hexagon_tiles.append(Vector2i(center.x - i, center.y))

		if (center.y + i) % 2 == 0:
			offset_pos += 1
		if (center.y + i) % 2 == 1:
			offset_neg += 1
		
	hexagon_tiles.append(center)
	return hexagon_tiles



func draw_hex_tile_line(a: Vector2i, b: Vector2i, tile_id: int) -> void:
	var cells = hex_line(a, b)
	print(["hexline", cells])
	for pos in cells:
		set_cell(pos, tile_id, Vector2i(0,0))


static func offset_to_cube(offset: Vector2i) -> Vector3i:
	var col = offset.x
	var row = offset.y

	# even-r conversion
	var x = col - ((row + (row & 1)) / 2)
	var z = row
	var y = -x - z

	return Vector3i(x, y, z)


# ------------------------------------------------
# Cube → Offset
# ------------------------------------------------
static func cube_to_offset(c: Vector3i) -> Vector2i:
	var x = c.x
	var z = c.z

	# even-r conversion
	var col = x + ((z + (z & 1)) / 2)
	var row = z

	return Vector2i(col, row)


# ------------------------------------------------
# Cube interpolation
# ------------------------------------------------
static func cube_lerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, t)


# ------------------------------------------------
# Cube rounding
# ------------------------------------------------
static func cube_round(c: Vector3) -> Vector3i:
	var rx = round(c.x)
	var ry = round(c.y)
	var rz = round(c.z)

	var dx = abs(rx - c.x)
	var dy = abs(ry - c.y)
	var dz = abs(rz - c.z)

	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry

	return Vector3i(rx, ry, rz)


# ------------------------------------------------
# Hex line generation (cube interpolation)
# ------------------------------------------------
static func hex_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	if(a.y == b.y):
		for i in range(abs(a.x - b.x) + 1):
			if(a.x > b.x):
				results.append(Vector2i(a.x - i, a.y))			
			else:
				results.append(Vector2i(a.x + i, a.y))
		return results

	var ac = offset_to_cube(a)
	var bc = offset_to_cube(b)

	var dist = max(abs(ac.x - bc.x), abs(ac.y - bc.y), abs(ac.z - bc.z))


	for i in range(dist + 1):
		var t = i / float(dist)
		var c = cube_round(cube_lerp(ac, bc, t))
		results.append(cube_to_offset(c))

	return results


# ------------------------------------------------
# Replace tiles along a hex line
# ------------------------------------------------
# static func draw_hex_tile_line(tilemap: TileMap, a: Vector2i, b: Vector2i, tile_id: int) -> void:
# 	var cells = hex_line(a, b)
# 	for pos in cells:
# 		tilemap.set_cell(pos, tile_id)
