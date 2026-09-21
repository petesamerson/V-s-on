extends TileMapLayer
class_name Board

@export var camera: Camera2D
@onready var tilemap = $TileMap
@onready var turn_label: RichTextLabel = $"../TurnLayer/TurnLabel"
@onready var turn_menu = $"../TurnLayer/PlayerSwitchOverlay"

var Tiles = preload("res://tiles.gd")

var board_center = Vector2i(10, 10)
var board_size = 10
var board_tiles: Array[Vector2i] = []

var turn = 1
var current_player: int = 1


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.z_index = 0
	board_tiles = get_hexagon_tiles(board_center, board_size)
	for c in board_tiles:
		set_cell(c, Tiles.BLACK, Vector2i(0,0))

	call_deferred("spawn_all_pieces")

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

	var raw_message = "Player 1's Turn \nCapture Eye To Win! \n(You are Invisible to Player 2)"
	turn_label.text = "[outline_size=30][outline_color=black][font_size=40][b][color=cyan]%s[/color][/b][/font_size]" % raw_message

	turn_menu.hide()


func update_turn_text():
	if current_player == 1:
		var raw_message = "Player 1's Turn"
		turn_label.text = "[outline_size=30][outline_color=black][font_size=40][b][color=cyan]%s[/color][/b][/font_size]" % raw_message
	else:
		var raw_message = "Player 2's Turn"
		turn_label.text = "[outline_size=30][outline_color=black][font_size=40][b][color=red]%s[/color][/b][/font_size]" % raw_message

func display_winner():
	if current_player == 1:
		var raw_message = "Player 1 WINS!"
		turn_label.text = "[outline_size=30][outline_color=black][font_size=40][b][color=cyan]%s[/color][/b][/font_size]" % raw_message
	else:
		var raw_message = "Player 2's WINS"
		turn_label.text = "[outline_size=30][outline_color=black][font_size=40][b][color=red]%s[/color][/b][/font_size]" % raw_message

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
@export var core_piece_scene: PackedScene
@export var eye_piece_scene: PackedScene
@export var tower_piece_scene: PackedScene
@export var hop_piece_scene: PackedScene
@export var triangle_odd_piece_scene: PackedScene
@export var triangle_even_piece_scene: PackedScene

@onready var player_pieces = [[],[]]
var player_last_moves: Array[Piece] = []
var player_vision_tiles: Array[Array] = [[],[]]

func spawn_all_pieces():
	var spawn1 = get_line_from_center(Vector2i(10,10), 0, 5)
	var spawn2 = get_line_from_center(Vector2i(10,10), 3, 5)

	
	spawn_player_location(spawn1.get(spawn1.size() - 1), 1)
	spawn_player_location(spawn2.get(spawn2.size() - 1), 2)

	update_all_piece_vision()
	move_camera_to_core()

func spawn_player_location(center: Vector2i, player: int):
	print("WAHT player " + str(player))
	var core_piece := core_piece_scene.instantiate() as CorePiece
	core_piece.owned_player = player
	player_pieces[player - 1].append(core_piece)
	pieces_container.add_child(core_piece)
	core_piece.setup(center, self)

	var positions = [
		Vector2i(center.x-1,center.y),
		Vector2i(center.x+1,center.y)
	]
	for pos in positions:
		var piece := eye_piece_scene.instantiate() as EyePiece
		piece.owned_player = player
		player_pieces[player - 1].append(piece)
		pieces_container.add_child(piece)
		piece.setup(pos, self)

	

	var hop_piece_locations: Array[Vector2i] = []
	for i in range(6):
		hop_piece_locations.append(get_line_end_from_center(center, i, 3))
	for i in range(6):
		var hop_piece := hop_piece_scene.instantiate() as HopPiece
		hop_piece.owned_player = player
		player_pieces[player - 1].append(hop_piece)
		pieces_container.add_child(hop_piece)
		hop_piece.setup(
			hop_piece_locations[i],
			self
		)

	var tri_odd_piece_locations: Array[Vector2i] = []
	for i in range(3):
		tri_odd_piece_locations.append(get_line_end_from_center(center, i*2, 2))
	for i in range(3):
		var tri_odd_piece := triangle_odd_piece_scene.instantiate() as TriangleOddPiece
		tri_odd_piece.owned_player = player
		player_pieces[player - 1].append(tri_odd_piece)
		pieces_container.add_child(tri_odd_piece)
		tri_odd_piece.setup(
			tri_odd_piece_locations[i],
			self
		)

	var tri_even_piece_locations: Array[Vector2i] = []
	for i in range(3):
		var line = get_line_from_center(center, 1 + i*2, 2)
		tri_even_piece_locations.append(line[line.size() - 1])
	for i in range(3):
		var tri_even_piece := triangle_even_piece_scene.instantiate() as TriangleEvenPiece
		tri_even_piece.owned_player = player
		player_pieces[player - 1].append(tri_even_piece)
		pieces_container.add_child(tri_even_piece)
		tri_even_piece.setup(
			tri_even_piece_locations[i],
			self
		)

	var rotate_piece_locations: Array[Vector2i] = []
	for i in range(12):
		var line = get_line_from_center(center, 1 + i*2, 2)
		# rotate_piece_locations.append(line[line.size() - 1])
		var first_axis = get_line_from_center(center, i, 2)
		var second_axis = get_line_from_center(center, (i + 1) % 6, 2)
		

		if(first_axis != null and second_axis != null):
			var connect_line = hex_line(
				first_axis[first_axis.size()-1], 
				second_axis[second_axis.size()-1]
			)
			var potential_new_move = connect_line[(connect_line.size())/2]
			rotate_piece_locations.append(potential_new_move)

	for i in rotate_piece_locations.size():
		var rotate_piece := tower_piece_scene.instantiate() as TowerRotatePiece
		rotate_piece.owned_player = player
		
		player_pieces[player - 1].append(rotate_piece)
		pieces_container.add_child(rotate_piece)
		rotate_piece.setup(
			rotate_piece_locations[i],
			self
		)
		if(i!=(rotate_piece_locations.size()-1)):
			rotate_piece.cur_direction = (5 + i)%5
		rotate_piece.update_sprite_rotation()
		rotate_piece.draw_vision_change()


func remove_piece(piece: Piece):
	player_pieces[piece.owned_player - 1].erase(piece)
	pieces_container.remove_child(piece)

func get_enemy_piece_at_cell(cell: Vector2i, player: int) -> Piece:
	for node in pieces_container.get_children():
		var piece := node as Piece

		if piece != null and piece.owned_player == player:
			var piece_cell = local_to_map(piece.position)

			if piece_cell == cell:
				return piece

	return null

func update_all_piece_vision(excluded_pieces: Array[Piece] = []):
	clear_board()
	print(str("Current player: ") + str(current_player))
	if(current_player == 1):
		for p in player_pieces[0]:
			if(!excluded_pieces.has(p)):
				print(p.getTypeString())
				# if(p.selected == true p.vision):
				# 	p.highlightVisionRange()
				# else:
				p.draw_current_vision()
				# p.draw_current_vision()
		for p in player_pieces[0]:
			p.visible = true
		for p in player_pieces[1]:
			p.visible = false
	else:
		for p in player_pieces[1]:
			if(!excluded_pieces.has(p)):
				print("updating vision for player 2")
				print(p.getTypeString())
				# if(p.selected == true):
				# 	p.highlightVisionRange()
				# else:
				p.draw_current_vision()
		for p in player_pieces[0]:
			p.visible = false
		for p in player_pieces[1]:
			p.visible = true

	for i in player_pieces.size():
		for j in player_pieces[i].size():
			for v in player_pieces[i][j].cur_vision:
				player_vision_tiles[i].append(v)
				if (hasEnemyPieceInVision(current_player, v)):
					setEnemyPieceVisiblity(v, true)
					

func hasEnemyPieceInVision(player: int, enemy: Vector2i) -> bool:
	var enemy_player = 2 if player == 1 else 1
	for p in player_pieces[player-1]:
		if(p.cur_vision.has(enemy)):
			return true
	return false

func hasCellInVision(player: int, cell: Vector2i) -> bool:
	for p in player_pieces[player-1]:
		if(p.cur_vision.has(cell)):
			return true
	return false

func friendlyPieceExistsAtCell(player: int, cell: Vector2i) -> bool:
	for p in player_pieces[player-1]:
		if(p.get_cur_pos() == cell):
			return true
	return false

func setEnemyPieceVisiblity(cell: Vector2i, visible:bool) -> void:
	var enemy_player = 2 if current_player == 1 else 1
	for p in player_pieces[enemy_player - 1]:
		if(cell == p.get_cur_pos()):
			p.visible = visible
	return

func clear_board():
	print("clear")
	for c in board_tiles:
		set_cell(c, Tiles.BLACK, Vector2i(0,0))


func deselect_all_pieces(excluded_pieces: Array[Piece] = []):
	for p in pieces_container.get_children():
		if(!excluded_pieces.has(p)):
			# print(["excluded_log", self.local_to_map(p.position)])
			p.selected = false

func end_turn(movedPiece: Piece):
	var eye_found = false
	await update_move_camera(movedPiece)
	for i in get_enemy_player_numbers():
		for p in player_pieces[i - 1]:
			if(p is EyePiece):
				eye_found = true
	if(eye_found):
		turn_menu.show()
	else:
		display_winner()

func update_move_camera(movedPiece: Piece):
	update_all_piece_vision()
	if(movedPiece.owned_player == current_player):
		await camera.zoom_to_global_position(
			movedPiece.global_position,
			camera.zoom.x
		)
	else:
		if(player_last_moves.size() == player_pieces.size()):
			await camera.zoom_to_global_position(
				player_last_moves[current_player - 1].global_position,
				camera.zoom.x
			)

	if(player_last_moves.size() < 2):
		print("zoomAppend")
		player_last_moves.append(movedPiece)
	else:
		print("moved")
		player_last_moves[current_player - 1] = movedPiece


func get_enemy_player_numbers():
	var enemy_players: Array[int] = []
	for i in range(player_pieces.size()) :
		if(i+1) != current_player:
			enemy_players.append((i + 1))
	print(enemy_players)
	return enemy_players


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

func move_camera_to_core():
	for p in pieces_container.get_children():
		if(p is CorePiece and p.owned_player == current_player):
			camera.zoom_to_global_position(p.position,1.5)

func _on_next_pressed() -> void:
	var enemy_eye = false
	for p in pieces_container.get_children():
		if(p is EyePiece and p.owned_player != current_player):
			enemy_eye = true
	current_player = 2 if current_player == 1 else 1
	update_turn_text()
	update_all_piece_vision()
	move_camera_to_core()
	turn_menu.hide()
	if(player_last_moves.size() == player_pieces.size()):
		await update_move_camera(
			player_last_moves[current_player - 1]
		)


func _on_stay_button_pressed() -> void:
	update_turn_text()
	update_all_piece_vision()
	turn_menu.hide()
