extends RefCounted
# Worker-only rules. No Nodes, rendering objects, or SceneTree access.

class PieceBag extends RefCounted:
	var items: Array = []
	func add_child(piece: DataPiece) -> void:
		items.append(piece)
	func remove_child(piece: DataPiece) -> void:
		items.erase(piece)
	func get_children() -> Array:
		return items

class DataPiece extends RefCounted:
	var _board_ref: WeakRef
	var board: DataBoard:
		get:
			return _board_ref.get_ref() as DataBoard if _board_ref != null else null
		set(value):
			_board_ref = weakref(value) if value != null else null
	var live_id: int = -1
	var position: Vector2 = Vector2.ZERO
	var owned_player: int = 1
	var vision_range: int = 3
	var move_range: int = 6
	var piece_value: float = 0.0
	var powered: bool = false
	var cur_moves: Array[Vector2i] = []
	var cur_vision: Array[Vector2i] = []
	func get_cur_pos() -> Vector2i:
		return Vector2i(position)
	func get_potential_vision(new_pos: Vector2i) -> Array[Vector2i]:
		return board.potential_vision(new_pos, vision_range)

	func generate_possible_moves(cur_location: Vector2i) -> Array[Vector2i]:
		cur_moves = []
		for i in range(6):
			var raw_moves = board.get_line_from_center(cur_location, i, move_range)
			for move in raw_moves:
				if(board.move_visible_and_unoccupied(move, cur_location, self)):
					cur_moves.append(move)
		return cur_moves

class DataCorePiece extends DataPiece:
	var power_count: int = 8
	func generate_possible_moves(
		cur_location: Vector2i,
		is_enemy: bool = false
	) -> Array[Vector2i]:
		var enemy_player := 2 if owned_player == 1 else 1

		if not is_enemy:
			board.regenerate_all_piece_moves(enemy_player, true)

		cur_moves.clear()

		for direction in range(6):
			var raw_moves: Array[Vector2i] = board.get_line_from_center(
				cur_location,
				direction,
				move_range
			)

			for move in raw_moves:
				if not board.cell_in_board(move) or move == cur_location:
					continue

				if board.friendlyPieceExistsAtCell(owned_player, move):
					continue

				var target := board.get_enemy_piece_at_cell(move, enemy_player)

				if target != null \
				and not target is DataCorePiece \
				and board.is_guarded(target):
					continue

				if calculate_move_core_power(move) == 0:
					continue

				if is_enemy:
					cur_moves.append(move)
				elif not board.is_move_threatened(move, owned_player):
					cur_moves.append(move)

		return cur_moves

	func calculate_move_core_power(potential_move: Vector2i = get_cur_pos()):
		var see_count = 0
		for p in board.player_pieces[(owned_player + 1)%2]:
			if(!(p is DataCorePiece)):
				if (p.cur_vision.has(potential_move)):
					see_count += 1

		return see_count

class DataEyePiece extends DataPiece:
	func generate_possible_moves(cur_location: Vector2i) -> Array[Vector2i]:
		cur_moves.clear()
		for direction in range(6):
			var raw_moves = board.get_line_from_center(cur_location, direction, move_range)
			for move in raw_moves:
				if board.move_visible_and_unoccupied(move,cur_location,self):
					cur_moves.append(move)
		return cur_moves

class DataHopPiece extends DataPiece:
	func generate_possible_moves(cur_location: Vector2i) -> Array[Vector2i]:
		cur_moves = []
		for i in range(6):
			var raw_moves = board.get_line_from_center(cur_location, i, move_range)
			var move = raw_moves[raw_moves.size() - 1]
			if board.move_visible_and_unoccupied(move,cur_location,self):
				cur_moves.append(move)
		return cur_moves

class DataTriangleEvenPiece extends DataPiece:
	func generate_possible_moves(cur_location: Vector2i) -> Array[Vector2i]:
		cur_moves = []
		for i in range(3):
			var raw_moves = board.get_line_from_center(cur_location, 1 + i*2, move_range)
			for move in raw_moves:
				if board.move_visible_and_unoccupied(move,cur_location,self):
					cur_moves.append(move)
		return cur_moves

class DataTriangleOddPiece extends DataPiece:
	func generate_possible_moves(cur_location: Vector2i) -> Array[Vector2i]:
		cur_moves = []
		for direction in range(3):
			var raw_moves = board.get_line_from_center(cur_location, direction * 2, move_range)
			for move in raw_moves:
				if board.move_visible_and_unoccupied(move,cur_location,self):
					cur_moves.append(move)
		return cur_moves

class DataTowerRotatePiece extends DataPiece:
	var cur_direction: int = 5
	var cur_rotate: Array[Vector2i] = []
	var rotate_map: Dictionary = {"pivot1": Vector2i.ZERO, "pivot2": Vector2i.ZERO}
	var cur_possible_rotate_moves: Array[Vector2i] = []
	var old_rotate_tile_ids: Dictionary = {}
	func clear_rotate_maps():
		rotate_map= {
			"pivot1": Vector2i(-1,0),
			"pivot2": Vector2i(-1,0)
		}
		old_rotate_tile_ids= {
			"pivot1": -1,
			"pivot2": -1
		}

	func get_potential_vision(new_pos: Vector2i, direction: int = cur_direction) -> Array[Vector2i]:
		return board.potential_vision(new_pos, vision_range, direction)

	func generate_possible_moves(cur_location: Vector2i) -> Array[Vector2i]:
		cur_moves = []
		cur_rotate = []
		if(board == null or position == null):
			return []
		var first_axis = board.get_line_from_center(cur_location, cur_direction, 10)
		var second_axis = board.get_line_from_center(cur_location, (cur_direction + 1) % 6, 10)


		for i in range(first_axis.size()):
			if(i%2 == 0):
				var connect_line = board.hex_line(first_axis[i], second_axis[i])
				var potential_new_move = connect_line[(connect_line.size())/2]
				if(board.move_visible_and_unoccupied(potential_new_move, cur_location, self)):
					cur_moves.append(potential_new_move)

		first_axis = board.get_line_from_center(cur_location, cur_direction, 10)
		var second_direction = cur_direction
		if(second_direction == 0):
			second_direction = 5
		else:
			second_direction = (cur_direction - 1) % 6
		second_axis = board.get_line_from_center(cur_location, second_direction, 10)
		if(first_axis != null and second_axis != null):
			var connect_line = board.hex_line(first_axis[2], second_axis[2])
			var potential_new_move = connect_line[(connect_line.size())/2]
			if(board.cell_in_board(potential_new_move)):
				if !board.does_rotate_unpower_core(self, true):
					rotate_map["pivot1"] = potential_new_move

			first_axis = board.get_line_from_center(cur_location, (cur_direction + 1) % 6, 10)
			second_axis = board.get_line_from_center(cur_location, (cur_direction + 2) % 6, 10)
			if(first_axis != null and second_axis != null):
				connect_line = board.hex_line(first_axis[2], second_axis[2])
				potential_new_move = connect_line[(connect_line.size())/2]
				if(board.cell_in_board(potential_new_move)):
					if !board.does_rotate_unpower_core(self, false):
						rotate_map["pivot2"] = potential_new_move
		return cur_moves

	func generate_all_possible_moves_with_rotation(
		cur_location: Vector2i
	) -> Array[Vector2i]:
		var all_moves: Array[Vector2i] = []

		var original_direction := cur_direction
		var original_moves: Array[Vector2i] = cur_moves.duplicate()

		for direction in range(6):
			cur_direction = direction#posmod(original_direction + direction_offset, 6)

			for move in generate_possible_moves(cur_location):
				if not all_moves.has(move):
					all_moves.append(move)

		cur_direction = original_direction
		cur_possible_rotate_moves  = all_moves
		cur_moves = original_moves

		return all_moves
	
	func generate_turn_actions() -> Array[Dictionary]:
		var actions: Array[Dictionary] = []

		var original_direction: int = cur_direction
		var original_player: int = board.current_player
		var original_moves: Array[Vector2i] = cur_moves.duplicate()
		var original_rotate_moves: Array[Vector2i] = (
			cur_possible_rotate_moves.duplicate()
		)
		var original_rotate_map: Dictionary = rotate_map.duplicate(true)

		var pending: Array[int] = [original_direction]
		var visited: Dictionary = {original_direction: true}
		var index: int = 0

		board.current_player = owned_player

		while index < pending.size():
			var direction: int = pending[index]
			index += 1

			cur_direction = direction
			board.refresh_vision()

			clear_rotate_maps()
			var destinations: Array[Vector2i] = (
				generate_possible_moves(get_cur_pos()).duplicate()
			)
			var pivots: Dictionary = rotate_map.duplicate(true)

			for destination in destinations:
				actions.append({
					"piece": self,
					"destination": destination,
					"direction": direction,
				})

			for key in ["pivot1", "pivot2"]:
				var pivot: Vector2i = pivots[key]
				if not board.cell_in_board(pivot):
					continue

				var next_direction: int = posmod(
					direction + (-1 if key == "pivot1" else 1),
					6
				)

				if visited.has(next_direction):
					continue

				visited[next_direction] = true
				pending.append(next_direction)

		cur_direction = original_direction
		board.current_player = original_player
		board.refresh_vision()

		cur_moves = original_moves
		cur_possible_rotate_moves = original_rotate_moves
		rotate_map = original_rotate_map

		return actions

	func can_attack_cell_after_any_rotation(target: Vector2i) -> bool:
		var cur_location := get_cur_pos()

		for direction in range(6):
			var hypothetical_vision := get_potential_vision(
				cur_location,
				direction
			)
			var visible := (
				board.hasCellInVision(owned_player, target)
				or hypothetical_vision.has(target)
			)
			if not visible:
				continue

			var first_axis = board.get_line_from_center(cur_location, direction, 10)
			var second_axis = board.get_line_from_center(
				cur_location,
				(direction + 1) % 6,
				10
			)

			for i in range(first_axis.size()):
				if i % 2 != 0:
					continue

				var connect_line := board.hex_line(first_axis[i], second_axis[i])
				var potential_move: Vector2i = connect_line[connect_line.size() / 2]
				if potential_move == target and board.cell_in_board(target):
					if not board.friendlyPieceExistsAtCell(owned_player, target):
						return true

		return false

class DataBoard extends RefCounted:
	var board_center: Vector2i = Vector2i(10, 10)
	var board_size: int = 10
	var board_tiles: Array[Vector2i] = []
	var current_player: int = 1
	var player_pieces: Array = [[], []]
	var player_captures: Array[Array] = [[], []]
	var last_capture_capturer_ids: Array[int] = [-1, -1]
	var pieces_container: PieceBag = PieceBag.new()
	var _vision_cache: Dictionary = {}
	var _line_cache: Dictionary = {}
	var _tile_lookup: Dictionary = {}
	func potential_vision(cell: Vector2i, radius: int, direction: int = -1) -> Array[Vector2i]:
		var key := Vector4i(cell.x, cell.y, radius, direction)
		if not _vision_cache.has(key):
			var raw: Array = get_hexagon_tiles(cell, radius) if direction < 0 else get_triangle_tiles_from_center(cell, radius, direction)
			var result: Array[Vector2i] = []
			for tile: Vector2i in raw:
				if cell_in_board(tile):
					result.append(tile)
			_vision_cache[key] = result
		return _vision_cache[key]
	func cell_in_board(cell: Vector2i) -> bool:
		if _tile_lookup.is_empty():
			for tile in board_tiles:
				_tile_lookup[tile] = true
		return _tile_lookup.has(cell)
	func get_line_from_center(center: Vector2i, direction: int, length: int):
		var key := Vector4i(center.x, center.y, direction, length)
		if not _line_cache.has(key):
			_line_cache[key] = _uncached_line_from_center(center, direction, length)
		return _line_cache[key]
	func map_to_local(cell: Vector2i) -> Vector2:
		return Vector2(cell)
	func local_to_map(point: Vector2) -> Vector2i:
		return Vector2i(point)
	func get_children() -> Array:
		return []
	func dispose() -> void:
		player_pieces = [[], []]
		pieces_container.items.clear()
	func refresh_vision() -> void:
		for group in player_pieces:
			for p: DataPiece in group:
				if p is DataCorePiece:
					p.cur_vision.clear()
				else:
					p.cur_vision = p.get_potential_vision(p.get_cur_pos())
		update_all_core_power_counts()
	func get_possible_spawn_locations() -> Array[Vector2i]:
		var locations: Array[Vector2i] = []

		for direction in range(6):
			var line: Array[Vector2i] = get_line_from_center(Vector2i(10, 10), direction, 6)
			if not line.is_empty():
				locations.append(line[line.size() - 1])

		return locations

	func get_enemy_piece_at_cell(cell: Vector2i, player: int) -> DataPiece:
		for node in pieces_container.get_children():
			var piece := node as DataPiece

			if piece != null and piece.owned_player == player:
				var piece_cell = local_to_map(piece.position)

				if piece_cell == cell:
					return piece

		return null

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

	func get_current_core() -> DataCorePiece:
		var current_core: DataCorePiece = null
		for c in player_pieces[current_player-1]:
			if(c is DataCorePiece and c.owned_player == current_player):
				current_core = c
		return current_core

	func does_move_unpower_core(moved_piece: DataPiece, new_move: Vector2i) -> bool:
		var core = get_current_core()
		if core == null:
			return false
		if(moved_piece.cur_vision.has(core.get_cur_pos())):
			if(core.power_count == 1):
				if(!moved_piece.get_potential_vision(new_move).has(core.get_cur_pos())):
					return true
		return false

	func does_rotate_unpower_core(piece: DataTowerRotatePiece, first_rotate: bool) -> bool:
		var core = get_current_core()
		if(core == null):
			return false
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

	func is_piece_under_attack(piece: DataPiece) -> bool:
		var attacker_player := 2 if piece.owned_player == 1 else 1

		regenerate_all_piece_moves(attacker_player, true)

		var target_cell := piece.get_cur_pos()
		var attacked := false
		for attacker in player_pieces[attacker_player - 1]:
			if attacker is DataTowerRotatePiece:
				if (attacker as DataTowerRotatePiece).can_attack_cell_after_any_rotation(target_cell):
					attacked = true
					if piece is DataCorePiece:
						pass
					break
			elif attacker.cur_moves.has(target_cell):
				attacked = true
				break



		return attacked

	func regenerate_all_piece_moves(player: int, is_enemy: bool = false):
		for p in player_pieces[player - 1]:
			if(p is DataCorePiece):
				p.generate_possible_moves(p.get_cur_pos(), is_enemy)
			elif(p is DataTowerRotatePiece):
				p.generate_all_possible_moves_with_rotation(p.get_cur_pos())
				p.generate_possible_moves(p.get_cur_pos())
			else:
				p.generate_possible_moves(p.get_cur_pos())

	func is_move_threatened(move: Vector2i, player: int) -> bool:
		var enemy_player = 2 if player == 1 else 1
		for p in player_pieces[enemy_player - 1]:
			if(p is DataTowerRotatePiece):
				if p.cur_possible_rotate_moves.has(move):
					return true
			if p.cur_moves.has(move):
				return true
		return false

	func move_visible_and_unoccupied(
		move: Vector2i,
		currentCell: Vector2i,
		piece: DataPiece
	) -> bool:
		if(cell_in_board(move) && move != currentCell):
			if(hasCellInVision(piece.owned_player, move)):
				if(!friendlyPieceExistsAtCell(piece.owned_player,move)):
					if(!does_move_unpower_core(piece, move)):
						return true
		return false

	func get_guarders(target: DataPiece) -> Array[DataPiece]:
		var guarders: Array[DataPiece] = []
		if target == null:
			return guarders

		var player := target.owned_player
		var enemy_player := 2 if player == 1 else 1

		for enemy_node in player_pieces[enemy_player - 1]:
			var enemy := enemy_node as DataPiece
			if enemy == null or not enemy.cur_moves.has(target.get_cur_pos()):
				continue

			for ally_node in player_pieces[player - 1]:
				var ally := ally_node as DataPiece
				if ally == null or ally == target:
					continue

				if ally.cur_moves.has(enemy.get_cur_pos()) and not guarders.has(ally):
					guarders.append(ally)

		return guarders

	func is_guarded(target: DataPiece) -> bool:
		return not get_guarders(target).is_empty()

	func can_enemy_recapture_after_move(
		moving_piece: DataPiece,
		destination: Vector2i,
		captured_piece: DataPiece
	) -> bool:
		if moving_piece == null or captured_piece == null:
			return false

		var moving_player := moving_piece.owned_player
		var enemy_player := 2 if moving_player == 1 else 1

		var visible_enemies: Array[DataPiece] = []
		for node in player_pieces[enemy_player - 1]:
			var enemy := node as DataPiece
			if enemy == null or enemy == captured_piece:
				continue
			if hasCellInVision(moving_player, enemy.get_cur_pos()):
				visible_enemies.append(enemy)

		var saved_states: Array[Dictionary] = []
		for node in player_pieces[enemy_player - 1]:
			var enemy := node as DataPiece
			if enemy == null:
				continue

			var state: Dictionary = {
				"piece": enemy,
				"moves": enemy.cur_moves.duplicate()
			}

			if enemy is DataTowerRotatePiece:
				var tower := enemy as DataTowerRotatePiece
				state["direction"] = tower.cur_direction
				state["rotate_moves"] = tower.cur_possible_rotate_moves.duplicate()
				state["cur_rotate"] = tower.cur_rotate.duplicate()
				state["rotate_map"] = tower.rotate_map.duplicate(true)

			saved_states.append(state)

		var original_position := moving_piece.position
		var original_player := current_player
		var captured_index : int = player_pieces[enemy_player - 1].find(captured_piece)

		if captured_index >= 0:
			player_pieces[enemy_player - 1].remove_at(captured_index)

		moving_piece.position = map_to_local(destination)
		current_player = enemy_player
		regenerate_all_piece_moves(enemy_player, true)

		var can_recapture := false
		for enemy in visible_enemies:
			if enemy.cur_moves.has(destination):
				can_recapture = true
				break

		current_player = original_player
		moving_piece.position = original_position

		if captured_index >= 0:
			player_pieces[enemy_player - 1].insert(captured_index, captured_piece)

		for state in saved_states:
			var enemy := state["piece"] as DataPiece
			enemy.cur_moves = state["moves"]

			if enemy is DataTowerRotatePiece:
				var tower := enemy as DataTowerRotatePiece
				tower.cur_direction = state["direction"]
				tower.cur_possible_rotate_moves = state["rotate_moves"]
				tower.cur_rotate = state["cur_rotate"]
				tower.rotate_map = state["rotate_map"]

		return can_recapture

	func update_all_core_power_counts() -> void:
		for player_id in [1, 2]:
			var core: DataCorePiece = null

			for node in player_pieces[player_id - 1]:
				if node is DataCorePiece:
					core = node as DataCorePiece
					break

			if core == null:
				continue

			var core_position := core.get_cur_pos()
			var support_count := 0

			for node in player_pieces[player_id - 1]:
				var supporter := node as DataPiece
				if supporter == null or supporter == core:
					continue

				supporter.powered = supporter.cur_vision.has(core_position)


				if supporter.powered:
					support_count += 1

			core.power_count = support_count

	func _uncached_line_from_center(center: Vector2i, direction: int, length: int):
		var center_even = center.y % 2 == 0
		match direction:
			0:
				var offset = 0
				if(center_even):
					offset = 1
					if(length % 2 == 0):
						offset = offset - 1
				offset = offset + length / 2
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

			hexagon_tiles.append_array(
				hex_line(
					Vector2i(center.x - offset_neg, center.y + i),
					Vector2i(center.x + offset_pos, center.y + i),
				)
			)

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

	static func offset_to_cube(offset: Vector2i) -> Vector3i:
		var col = offset.x
		var row = offset.y

		var x = col - ((row + (row & 1)) / 2)
		var z = row
		var y = -x - z

		return Vector3i(x, y, z)

	static func cube_to_offset(c: Vector3i) -> Vector2i:
		var x = c.x
		var z = c.z

		var col = x + ((z + (z & 1)) / 2)
		var row = z

		return Vector2i(col, row)

	static func cube_lerp(a: Vector3, b: Vector3, t: float) -> Vector3:
		return a.lerp(b, t)

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

