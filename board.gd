extends TileMapLayer
class_name Board

@export var camera: Camera2D
@onready var tilemap = $TileMap
@onready var turn_label: RichTextLabel = $"../TurnLayer/TurnLabel"
@onready var core_label: RichTextLabel = $"../TurnLayer/CoreLabel"
@onready var turn_menu = $"../TurnLayer/PlayerSwitchOverlay"
@onready var selection_panel= $"../TurnLayer/SelectionPanel"

@export var capture_texture: Texture2D

var Tiles = preload("res://tiles.gd")
const GameColors = preload("res://colors.gd")

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

	update_mobile_scale()
	get_viewport().size_changed.connect(resize_text_overlay)

	instantiate_turn_menu()
	instantiate_core_menu()

	intialize_drawn_sprite_nodes()

var is_mobile_browser: bool = false

func update_mobile_scale():
	is_mobile_browser = (
		OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)
	
	if is_mobile_browser:
		selection_panel.scale = Vector2(2.0,2.0)
	else:
		pass
		# SelectionPanel.scale = Vector2(3.0,3.0)

	# var touch_device := DisplayServer.is_touchscreen_available()


func intialize_drawn_sprite_nodes():
	rotate_sprites = Node2D.new()
	rotate_sprites.z_index = 3
	add_child(rotate_sprites)

	capture_sprites = Node2D.new()
	capture_sprites.z_index = 3
	add_child(capture_sprites)



func instantiate_turn_menu():
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

	var raw_message = "Player 1's Turn \nCapture Core To Win! \n(You are Invisible to Player 2)"
	turn_label.text = "[outline_size=30][outline_color=black][font_size=40][b][color=cyan]%s[/color][/b][/font_size]" % raw_message

	turn_menu.hide()

func resize_text_overlay():
	update_turn_text()
	update_core_text()


func instantiate_core_menu():
	# Apply the styling wrapper dynamically without changing the original variable
	core_label.bbcode_enabled = true
	core_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	core_label.fit_content = true
	core_label.size = Vector2(1000, 100)
	core_label.set_anchors_preset(Control.PRESET_CENTER)
	core_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var viewport_size = get_viewport().get_visible_rect().size
	core_label.position.x = (viewport_size.x - core_label.size.x) / 2
	core_label.position.y = viewport_size.y - core_label.size.y

	var raw_message = "Core Seen By 6 Pieces"
	core_label.text = "[outline_size=30][outline_color=black][font_size=40][b][color=white]%s[/color][/b][/font_size]" % raw_message

	# core_menu.hide()


func update_turn_text():
	var viewport_size = get_viewport().get_visible_rect().size
	turn_label.position.x = (viewport_size.x - turn_label.size.x) / 2
	turn_label.position.y =  5
	if current_player == 1:
		var raw_message = "Player 1's Turn"
		turn_label.text = "[outline_size=30][outline_color=black][font_size=40][b][color=cyan]%s[/color][/b][/font_size]" % raw_message
	else:
		var raw_message = "Player 2's Turn"
		turn_label.text = "[outline_size=30][outline_color=black][font_size=40][b][color=red]%s[/color][/b][/font_size]" % raw_message

func display_winner(winner):
	var raw_message = "Player "+str(winner)+" WINS!"
	if winner == 1:
		turn_label.text = "[outline_size=30][outline_color=black][font_size=200][b][color=cyan]%s[/color][/b][/font_size]" % raw_message
	else:
		turn_label.text = "[outline_size=30][outline_color=black][font_size=200][b][color=red]%s[/color][/b][/font_size]" % raw_message
	var viewport_size = get_viewport().get_visible_rect().size

	turn_label.position.x = (viewport_size.x - turn_label.size.x) / 2
	turn_label.position.y = (viewport_size.y - turn_label.size.y) / 2 

func update_selection_panel(selectedPiece: Piece):
	var margin_container = selection_panel.get_child(0) as MarginContainer
	var v_box_root = margin_container.get_child(0) as VBoxContainer
	var h_box = v_box_root.get_child(0) as HBoxContainer
	for child in h_box.get_children():
		if child is PanelContainer:
			var tr = child.get_child(0) as TextureRect
			tr.texture = selectedPiece.sprite.texture
		if child is VBoxContainer:
			for label in child.get_children():
				if(label is Label):
					match label.name:
						"PieceName":
							label.text = selectedPiece.getTypeString()
						"Description":
							label.text = selectedPiece.getTypedDescription()
						"MoveRange":
							label.text = "MoveRange: " + str(selectedPiece.vision_range)
						"VisionRange":
							label.text = "VisionRange: " + str(selectedPiece.vision_range)
			



func determine_winner() -> int:
	var winner = 0
	var cores: Array[CorePiece] = []
	for piece_list in player_pieces:
		for p in piece_list:
			if(p is CorePiece):
				cores.append(p as CorePiece)
		
	if(cores.size() == 1):
		return cores[0].owned_player
	
	var loser = 0
	for core in cores:
		if(core.power_count == 0):
			loser = core.owned_player
	if loser == 0:
		return 0

	winner = 2 if loser == 1 else 1
	print("winner " + str(winner))
	
	return winner

func update_core_text(numberCanSeeCore : int = -1):
	var viewport_size = get_viewport().get_visible_rect().size
	core_label.position.x = (viewport_size.x - core_label.size.x) / 2
	core_label.position.y = viewport_size.y - (core_label.size.y) / 2 

	if(numberCanSeeCore != -1):
		var raw_message = "Core Seen By " +  str(numberCanSeeCore) +  " Pieces"
		core_label.text = "[outline_size=30][outline_color=black][font_size=40][b][color=white]%s[/color][/b][/font_size]" % raw_message


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
	update_core_power()

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
		piece.z_index = 2
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
				p.draw_current_vision()
				p.update_piece_color()
		for p in player_pieces[0]:
			p.visible = true
		for p in player_pieces[1]:
			p.visible = false
	else:
		for p in player_pieces[1]:
			if(!excluded_pieces.has(p)):
				print("updating vision for player 2")
				print(p.getTypeString())
				p.draw_current_vision()
				p.update_piece_color()
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

	update_core_power()

					

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

var capture_sprites: Node2D
func set_take_piece_sprite(enemy_loc: Vector2i):
	# for child in capture_sprites.get_children():
	# 	child.queue_free()
	var sprite := Sprite2D.new()
	sprite.texture = capture_texture
	var world_position := map_to_local(enemy_loc)
	sprite.position = world_position
	# add_child(sprite)
	capture_sprites.add_child(sprite)

func clear_captures():
	for child in capture_sprites.get_children():
		child.queue_free()
	

	

func friendlyPieceExistsAtCell(player: int, cell: Vector2i) -> bool:
	for p in player_pieces[player-1]:
		if(p.get_cur_pos() == cell):
			return true
	return false

func get_current_core() -> CorePiece:
	var current_core: CorePiece = null
	for c in player_pieces[current_player-1]:
		if(c is CorePiece and c.owned_player == current_player):
			current_core = c
	return current_core

func does_move_unpower_core(moved_piece: Piece, new_move: Vector2i) -> bool:
	var core = get_current_core()
	if(moved_piece.cur_vision.has(core.get_cur_pos())):
		if(core.power_count == 1):
			if(!moved_piece.get_potential_vision(new_move).has(core.get_cur_pos())):
				return true
	return false

func does_rotate_unpower_core(piece: TowerRotatePiece, first_rotate: bool) -> bool:
	var core = get_current_core()
	var new_direction = piece.cur_direction
	if(first_rotate):
		if new_direction == 0:
			new_direction = 5
		else:
			new_direction = new_direction - 1
	else:
		new_direction = (new_direction + 1) % 6

	if(piece.cur_vision.has(core.get_cur_pos())):
		if(core.power_count == 1):
			if(!piece.get_potential_vision(piece.get_cur_pos(), new_direction).has(core.get_cur_pos())):
				return true
	return false
				
			
func move_visible_and_unoccupied(
	move: Vector2i,
	currentCell: Vector2i,
	piece: Piece
) -> bool:
	if(cell_in_board(move) && move != currentCell):
		if(hasCellInVision(current_player, move)):
			if(!friendlyPieceExistsAtCell(current_player,move)):
				if(!does_move_unpower_core(piece, move)):
					return true
	return false


func update_core_power():
	for child in get_children():
		if child is Line2D:
			child.queue_free()
	var current_core: = get_current_core()

	if current_core == null:
		return

	#Pieces that can see Core
	var see_count = 0
	for p in player_pieces[(current_player + 1)%2]:
		if(!(p is CorePiece)):
			if (p.cur_vision.has(current_core.get_cur_pos())):
				var line := Line2D.new()
				line.points = PackedVector2Array([
					Vector2(current_core.position.x, current_core.position.y),
					Vector2(p.position.x, p.position.y)
				])
				line.width = 3.0
				line.z_index = 1
				
				current_core.update_piece_color()
				if(current_core.selected):
					line.default_color = Color.WHITE
				else:
					line.default_color = get_player_color(true)
				p.powered = true
				p.update_piece_color()
				add_child(line)
				see_count += 1
			else:
				p.powered = false
	update_core_text(see_count)
	current_core.power_count = see_count

	if(see_count == 0):
		display_winner(determine_winner())

var rotate_sprites: Node2D

func update_rotate_map_board(rotate_map: Dictionary = {}):
	for child in rotate_sprites.get_children():
		child.queue_free()
	if(rotate_map.size() != 0):
		for key in rotate_map.keys():
			var rotate_cell = rotate_map[key]
			var source_id := get_cell_source_id(rotate_cell)
			var source := tile_set.get_source(source_id) as TileSetAtlasSource
			var sprite := Sprite2D.new()
			sprite.texture = source.get_texture()
			var world_position := map_to_local(rotate_cell)
			sprite.position = world_position
			# add_child(sprite)
			rotate_sprites.add_child(sprite)
		


func get_player_color(powered: bool = false) -> Color:
	match current_player:
		1: 
			if(powered):
				return GameColors.PLAYER_BLUE_POWER
			return GameColors.PLAYER_BLUE
		2: 
			if(powered):
				return GameColors.PLAYER_RED_POWER
			return GameColors.PLAYER_RED
	return Color.WHITE

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
	update_rotate_map_board()


func deselect_all_pieces(excluded_pieces: Array[Piece] = []):
	for p in pieces_container.get_children():
		if(!excluded_pieces.has(p)):
			# print(["excluded_log", self.local_to_map(p.position)])
			p.selected = false
		p.update_piece_color()
	update_core_power()
	clear_captures()

func end_turn(movedPiece: Piece):
	var core_found = false
	clear_captures()
	await update_move_camera(movedPiece)
	for i in get_enemy_player_numbers():
		for p in player_pieces[i - 1]:
			if(p is CorePiece):
				core_found = true
	if(core_found):
		var potential_winner = determine_winner()
		if(potential_winner == 0):
			turn_menu.show()
		else:
			display_winner(potential_winner)
	else:
		display_winner(current_player)

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
