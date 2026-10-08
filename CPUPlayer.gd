extends Node
class_name CPUPlayer

@export var player_number: int = 2
@export_range(1,5) var difficulty: int = 5

var board: Board
var recent_piece_ids: Array[int] = []


func setup(game_board: Board) -> void:
	print("cpu created with difficulty " + str(difficulty))
	board = game_board


func take_turn() -> void:
	if board == null or board.current_player != player_number:
		return

	rotate_towers_for_turn()

	var enemy_player := 1 if player_number == 2 else 2
	board.regenerate_all_piece_moves(enemy_player, true)

	var own_core := find_core(player_number)
	var core_under_attack := (
		own_core != null
		# and has_visible_attacker(own_core)
		and board.is_piece_under_attack(own_core)
	)

	var actions: Array[Dictionary] = []

	for node in board.player_pieces[player_number - 1]:
		var piece := node as Piece
		if piece == null:
			continue

		var destinations: Array[Vector2i] = []
		if(piece is CorePiece):
			destinations = (piece as CorePiece).generate_possible_moves(piece.get_cur_pos())
		elif(piece is TowerRotatePiece):
			destinations = (piece as TowerRotatePiece).generate_all_possible_moves_with_rotation(piece.get_cur_pos())
		else:
			destinations = piece.generate_possible_moves(piece.get_cur_pos())

		for destination in destinations:
			actions.append({
				"piece": piece,
				"destination": destination,
				"score": score_move(piece, destination, core_under_attack)
			})

	if actions.is_empty():
		print("CPU has no legal moves")
		return

	var best_score: float = -INF
	for action in actions:
		best_score = maxf(best_score, action["score"])

	# Choose randomly among strong options, so one piece doesn't dominate
	# every turn when several moves are nearly as good.
	var shortlist: Array[Dictionary] = []
	for action in actions:
		var tolerance_by_difficulty := [400.0, 220.0, 75.0, 15.0, 0.0]
		var tolerance : float = tolerance_by_difficulty[clampi(difficulty - 1, 0, 4)]

		if action["score"] >= best_score - tolerance:
			shortlist.append(action)

	var choice: Dictionary = shortlist.pick_random()
	var chosen_piece := choice["piece"] as Piece
	var destination: Vector2i = choice["destination"]

	recent_piece_ids.push_front(chosen_piece.get_instance_id())
	if recent_piece_ids.size() > 2:
		recent_piece_ids.pop_back()

	chosen_piece.make_cpu_move(destination)


func score_move(piece: Piece, destination: Vector2i, core_under_attack: bool) -> float:
	var enemy_player := 1 if player_number == 2 else 2
	var own_core := find_core(player_number)

	if own_core == null:
		return 0.0

	# Candidate destinations should be in the CPU's vision. Only inspect
	# an enemy occupying a destination the CPU can currently see.
	var captured: Piece = null
	if board.hasCellInVision(player_number, destination):
		captured = board.get_enemy_piece_at_cell(destination, enemy_player)

	if captured is CorePiece:
		return 100000.0

	var own_support_after := count_core_support(
		player_number,
		own_core.get_cur_pos(),
		piece,
		destination
	)

	var score: float = 0.0

	var old_position := piece.get_cur_pos()
	var new_vision: Array[Vector2i] = piece.get_potential_vision(destination)

	if core_under_attack and piece is CorePiece:
		score += 1000.0

	# if captured != null:
	# 	score += 90.0
	if captured != null:
		score += float(captured.piece_value) * 50.0

		if board.can_enemy_recapture_after_move(piece, destination, captured):
			score -= float(piece.piece_value) * 50.0

		# Keep your existing bonus for capturing an enemy threatening an ally.
		for ally_node in board.player_pieces[player_number - 1]:
			var ally := ally_node as Piece
			if ally == null or ally == piece:
				continue
			if captured.cur_moves.has(ally.get_cur_pos()):
				score += 45.0
				break
	

	# Only use the enemy core's location when it is visible to the CPU.
	var visible_enemy_core := find_visible_core(enemy_player)
	if visible_enemy_core != null:
		var enemy_core_position := visible_enemy_core.get_cur_pos()

		if captured != null and captured.cur_vision.has(enemy_core_position):
			score += 30.0

		var potential_vision: Array[Vector2i] = piece.get_potential_vision(destination)
		if (
			potential_vision.has(enemy_core_position)
			and not piece.cur_vision.has(enemy_core_position)
		):
			score += 18.0

		var old_distance := hex_distance(
			piece.get_cur_pos(),
			enemy_core_position
		)
		var new_distance := hex_distance(
			destination,
			enemy_core_position
		)

		score += float(old_distance - new_distance) * 2.5

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy == null or enemy == captured:
			continue

		var enemy_cell := enemy.get_cur_pos()
		if not board.hasCellInVision(player_number, enemy_cell):
			continue

		var old_distance := hex_distance(piece.get_cur_pos(), enemy_cell)
		var new_distance := hex_distance(destination, enemy_cell)
		score += float(old_distance - new_distance) * 4.0

		# Reward moves that let this piece see the enemy.
		var potential_vision := piece.get_potential_vision(destination)
		if potential_vision.has(enemy_cell) and not piece.cur_vision.has(enemy_cell):
			score += 16.0

	# Reward revealing territory that our pieces cannot currently see.
	var newly_seen_cells := 0
	for cell in new_vision:
		if not board.hasCellInVision(player_number, cell):
			newly_seen_cells += 1

	var scouting_factor := 1.0 / (1.0 + float(piece.piece_value) * 0.15)
	score += float(newly_seen_cells) * 0.75 * scouting_factor

	# Extra reward when this move reveals a previously hidden enemy.
	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy == null:
			continue

		var enemy_cell := enemy.get_cur_pos()
		if (
			not board.hasCellInVision(player_number, enemy_cell)
			and new_vision.has(enemy_cell)
		):
			score += 35.0 * scouting_factor

	for node in board.player_pieces[player_number - 1]:
		var ally := node as Piece
		if ally == null or ally == piece:
			continue

		if not board.is_guarded(ally) and new_vision.has(ally.get_cur_pos()):
			score += 12.0
	
	# Keep non-core pieces near allies and encourage shared coverage.
	if not piece is CorePiece:
		for node in board.player_pieces[player_number - 1]:
			var ally := node as Piece
			if ally == null or ally == piece or ally is CorePiece:
				continue

			var distance_before := hex_distance(old_position, ally.get_cur_pos())
			var distance_after := hex_distance(destination, ally.get_cur_pos())

			if distance_after <= 3:
				score += 2.0

			if distance_after < distance_before and distance_after <= 5:
				score += 2.0

			for cell in new_vision:
				if ally.cur_vision.has(cell) and not piece.cur_vision.has(cell):
					score += 0.1

	# Penalize abandoning an ally if this piece is currently one of its guarders.
	for ally in board.get_children():
		if ally is Piece and ally != piece:
			if board.get_guarders(ally).has(piece):
				score -= 18.0

	# The core must keep support. Avoid overvaluing extra defenders once
	# the core is already safe.
	if own_support_after == 0:
		score -= 100000.0
	elif own_support_after == 1:
		score -= 100.0

	# Account only for enemy pieces whose locations are visible.
	for node in board.player_pieces[enemy_player - 1]:
		var enemy_piece := node as Piece
		if enemy_piece == null or enemy_piece == captured:
			continue
		if not board.hasCellInVision(player_number, enemy_piece.get_cur_pos()):
			continue
		if enemy_piece.cur_moves.has(destination):
			var loss_penalty := 300.0 + float(piece.piece_value) * 60.0
			score -= loss_penalty

	# Encourage rotating through pieces when choices are close in value.
	if recent_piece_ids.has(piece.get_instance_id()):
		score -= 14.0

	score -= float(piece.piece_value) * 5.0

	return score


func find_core(player_id: int) -> CorePiece:
	for node in board.player_pieces[player_id - 1]:
		if node is CorePiece:
			return node as CorePiece
	return null


func find_visible_core(player_id: int) -> CorePiece:
	var core := find_core(player_id)
	if core == null:
		return null

	if board.hasCellInVision(player_number, core.get_cur_pos()):
		return core
	return null


func count_core_support(
	player_id: int,
	core_position: Vector2i,
	moving_piece: Piece = null,
	destination: Vector2i = Vector2i.ZERO,
	removed_piece: Piece = null
) -> int:
	var count := 0

	for node in board.player_pieces[player_id - 1]:
		var piece := node as Piece
		if piece == null or piece is CorePiece or piece == removed_piece:
			continue

		var vision: Array[Vector2i]
		if piece == moving_piece:
			vision = piece.get_potential_vision(destination)
		else:
			vision = piece.cur_vision

		if vision.has(core_position):
			count += 1

	return count


func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var cube_a := Board.offset_to_cube(a)
	var cube_b := Board.offset_to_cube(b)

	return maxi(
		maxi(abs(cube_a.x - cube_b.x), abs(cube_a.y - cube_b.y)),
		abs(cube_a.z - cube_b.z)
	)


func rotate_towers_for_turn() -> void:
	var enemy_player := 1 if player_number == 2 else 2

	for node in board.player_pieces[player_number - 1]:
		var tower := node as TowerRotatePiece
		if tower == null:
			continue

		# This fills rotate_map with the legal one-step rotations.
		tower.clear_rotate_maps()
		tower.generate_possible_moves(tower.get_cur_pos())

		var best_key := ""
		var best_score: float = 0.0

		for key in ["pivot1", "pivot2"]:
			var pivot: Vector2i = tower.rotate_map[key]
			if not board.cell_in_board(pivot):
				continue

			var new_direction := tower.cur_direction
			if key == "pivot1":
				new_direction = posmod(tower.cur_direction - 1, 6)
			else:
				new_direction = posmod(tower.cur_direction + 1, 6)

			var new_vision := tower.get_potential_vision(
				tower.get_cur_pos(),
				new_direction
			)
			var score := score_tower_rotation(tower, new_vision, enemy_player)

			if score > best_score:
				best_score = score
				best_key = key

		# A positive score means this rotation is useful.
		# A score of zero or less leaves the tower where it is.
		if best_key != "":
			if best_key == "pivot1":
				tower.cur_direction = posmod(tower.cur_direction - 1, 6)
			else:
				tower.cur_direction = posmod(tower.cur_direction + 1, 6)

			tower.update_sprite_rotation()
			tower.draw_vision_change()


func score_tower_rotation(
	tower: TowerRotatePiece,
	new_vision: Array[Vector2i],
	enemy_player: int
) -> float:
	var other_vision := {}

	# Count vision provided by the CPU's other pieces, so a tower doesn't
	# get credit for tiles those pieces already cover.
	for node in board.player_pieces[player_number - 1]:
		var piece := node as Piece
		if piece == null or piece == tower:
			continue

		for cell in piece.cur_vision:
			other_vision[cell] = true

	var old_unique_count := 0
	for cell in tower.cur_vision:
		if not other_vision.has(cell):
			old_unique_count += 1

	var new_unique_count := 0
	for cell in new_vision:
		if not other_vision.has(cell):
			new_unique_count += 1

	var score := float(new_unique_count - old_unique_count)

	# Give a small bonus for seeing an enemy core whose location is
	# already known to the CPU.
	var known_enemy_core := find_visible_core(enemy_player)
	if known_enemy_core != null:
		var core_cell := known_enemy_core.get_cur_pos()
		if new_vision.has(core_cell) and not tower.cur_vision.has(core_cell):
			score += 8.0

	return score


func has_visible_attacker(piece: Piece) -> bool:
	var enemy_player := 1 if player_number == 2 else 2
	var target_cell := piece.get_cur_pos()

	for node in board.player_pieces[enemy_player - 1]:
		var enemy_piece := node as Piece
		if enemy_piece == null:
			continue

		if not board.hasCellInVision(player_number, enemy_piece.get_cur_pos()):
			continue

		if enemy_piece.cur_vision.has(target_cell):
			return true

	return false

