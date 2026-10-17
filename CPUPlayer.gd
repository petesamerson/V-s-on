extends Node
class_name CPUPlayer

const CORE_CAPTURE_ENDGAME_PIECES := 3

const EYE_MOVE_ENDGAME_PIECES_LEFT := 6
const EYE_MOVE_ENDGAME_BONUS := 45.0
const EYE_RECAPTURE_BONUS := 1200.0

const CORE_MOVE_ENDGAME_PIECES_LEFT := 4
const CORE_MOVE_ENDGAME_BONUS := 60.0

const SCOUT_APPROACH_WEIGHT := 12.0
const SCOUT_REVEAL_WEIGHT := 180.0
const TOWER_SCOUT_MULTIPLIER := 2.5
const VISIBLE_ATTACK_WEIGHT := 1.5

const HOP_CATCH_UP_BONUS := 50.0
const MAX_HOP_CATCH_UP_BONUS := 3
const EARLY_GAME_CAPTURE_LIMIT := 4
const EARLY_HOP_MOVE_BONUS := 1200.0
const EARLY_HOP_SCOUT_MULTIPLIER := 7.5

var early_hop_move_count := 0
var early_tower_move_count := 0

const RECAPTURE_BONUS = 500.0
const UNGUARDED_EYE_THREAT_PENALTY := 350.0
const LOW_VALUE_EYE_CAPTURE_BONUS := 250.0

var next_scout_piece_type := "hop"

const CORE_GUARD_CAPTURE_BONUS_PER_HEX := 80.0
const MIN_EARLY_CORE_SUPPORT := 4
const CORE_SUPPORT_ENDGAME_CAPTURE_COUNT := 27

@export var player_number: int = 2
@export_range(1,5) var difficulty: int = 5

var seen_by_player = false

var board: Board
var last_moved_piece: Piece
var recent_piece_ids: Array[int] = []
var moved_piece_ids: Dictionary = {}
var rng := RandomNumberGenerator.new()

var enemy_last_seen: Dictionary = {}
var cpu_turn_count := 0
var enemy_last_seen_turn: Dictionary = {}
var observed_enemy_capture_count := 0
var last_enemy_capturer_id := -1

func setup(game_board: Board) -> void:
	print("cpu created with difficulty " + str(difficulty))
	rng.randomize()
	board = game_board


func take_turn() -> void:
	if board == null or board.current_player != player_number:
		return

	cpu_turn_count += 1
	rotate_towers_for_turn()


	var enemy_player := 1 if player_number == 2 else 2

	var enemy_capture_count := board.player_captures[enemy_player - 1].size()

	if enemy_capture_count > observed_enemy_capture_count:
		var enemy_index := enemy_player - 1
		last_enemy_capturer_id = board.last_capture_capturer_ids[enemy_index]

		for node in board.player_pieces[enemy_index]:
			var capturer := node as Piece
			if (
				capturer != null
				and capturer.get_instance_id() == last_enemy_capturer_id
			):
				enemy_last_seen[last_enemy_capturer_id] = capturer.get_cur_pos()
				enemy_last_seen_turn[last_enemy_capturer_id] = cpu_turn_count
				break

	observed_enemy_capture_count = enemy_capture_count

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy != null and board.hasCellInVision(player_number, enemy.get_cur_pos()):
			var enemy_id := enemy.get_instance_id()
			enemy_last_seen[enemy_id] = enemy.get_cur_pos()
			enemy_last_seen_turn[enemy_id] = cpu_turn_count


	board.regenerate_all_piece_moves(enemy_player, true)

	var visible_enemy_core := find_visible_core(enemy_player)

	var own_core := find_core(player_number)
	var core_under_attack := (
		own_core != null
		# and has_visible_attacker(own_core)
		and board.is_piece_under_attack(own_core)
	)
	var core_attackers: Array[Piece] = []

	if core_under_attack and own_core != null:
		for node in board.player_pieces[enemy_player - 1]:
			var attacker := node as Piece
			if attacker == null:
				continue

			var attacker_moves := attacker.cur_moves
			if attacker is TowerRotatePiece:
				attacker_moves = (attacker as TowerRotatePiece).cur_possible_rotate_moves

			if attacker_moves.has(own_core.get_cur_pos()):
				core_attackers.append(attacker)

	var non_core_pieces_left := count_non_core_pieces()

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
			# if (
			# 	piece is CorePiece
			# 	and non_core_pieces_left > CORE_MOVE_ENDGAME_PIECES_LEFT
			# 	and not is_running_away(piece, destination)
			# ):
			# 	continue

			if (
				piece is EyePiece
				and non_core_pieces_left > EYE_MOVE_ENDGAME_PIECES_LEFT
				and not is_running_away(piece, destination)
			):
				continue

			if (
				piece is EyePiece
				and visible_enemy_core != null
				and visible_enemy_core.cur_moves.has(destination)
				and moves_from_position(piece, destination).has(
					visible_enemy_core.get_cur_pos()
				)
				and not board.can_enemy_recapture_after_move(
					visible_enemy_core,
					destination,
					piece
				)
			):
				continue

			var randomness_by_difficulty := [40.0, 28.0, 18.0, 10.0, 5.0]
			var randomness: float = randomness_by_difficulty[
				clampi(difficulty - 1, 0, 4)
			]
			var move_score := score_move(piece, destination, core_under_attack)
			move_score += rng.randf_range(-randomness, randomness)

			actions.append({
				"piece": piece,
				"destination": destination,
				"score": move_score,
				"unprotected_danger": is_unprotected_move(piece, destination),
				"scout_score": score_scouting_action(
					piece,
					piece.get_cur_pos(),
					destination,
					enemy_player
				),
			})


	if core_under_attack:
		var defensive_actions: Array[Dictionary] = []

		for action in actions:
			var resolves_threat := action["piece"] is CorePiece

			if (
				not resolves_threat
				and core_attackers.size() == 1
				and board.hasCellInVision(
					player_number,
					action["destination"]
				)
			):
				var target := board.get_enemy_piece_at_cell(
					action["destination"],
					enemy_player
				)
				resolves_threat = target == core_attackers[0]

			if resolves_threat:
				defensive_actions.append(action)

		if not defensive_actions.is_empty():
			actions = defensive_actions

	if actions.is_empty():
		print("CPU has no legal moves")
		return

	var safer_actions: Array[Dictionary] = []
	for action in actions:
		if not action["unprotected_danger"]:
			safer_actions.append(action)

	if not safer_actions.is_empty():
		actions = safer_actions

		if should_keep_scouting(enemy_player):
			var preferred_scout_actions: Array[Dictionary] = []

			for action in actions:
				if float(action["scout_score"]) <= 0.0:
					continue

				var candidate := action["piece"] as Piece
				if (
					next_scout_piece_type == "hop" and candidate is HopPiece
				) or (
					next_scout_piece_type == "tower" and candidate is TowerRotatePiece
				):
					preferred_scout_actions.append(action)

			if not preferred_scout_actions.is_empty():
				actions = preferred_scout_actions

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
	if (
		float(choice["scout_score"]) > 0.0
		and (chosen_piece is HopPiece or chosen_piece is TowerRotatePiece)
	):
		next_scout_piece_type = "hop" if rng.randf() < 0.5 else "tower"

	var total_captures := (
		board.player_captures[0].size()
		+ board.player_captures[1].size()
	)

	# if total_captures < EARLY_GAME_CAPTURE_LIMIT:
	# 	next_scout_piece_type = (
	# 		"hop" if rng.randf() < 0.5 else "tower"
	# 	)

	var destination: Vector2i = choice["destination"]
	var old_position := chosen_piece.get_cur_pos()


	if score_scouting_action(
		chosen_piece,
		old_position,
		destination,
		enemy_player
	) > 0.0:
		if chosen_piece is HopPiece:
			next_scout_piece_type = "tower"
		elif chosen_piece is TowerRotatePiece:
			next_scout_piece_type = "hop"

	recent_piece_ids.push_front(chosen_piece.get_instance_id())
	if recent_piece_ids.size() > 2:
		recent_piece_ids.pop_back()

	last_moved_piece = chosen_piece
	moved_piece_ids[chosen_piece.get_instance_id()] = true
	chosen_piece.make_cpu_move(destination)
	last_enemy_capturer_id = -1

func is_move_threatened(destination: Vector2i) -> bool:
	var enemy_player := 1 if player_number == 2 else 2
	var captured: Piece = null

	if board.hasCellInVision(player_number, destination):
		captured = board.get_enemy_piece_at_cell(destination, enemy_player)

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy == null or enemy == captured:
			continue
		if not board.hasCellInVision(player_number, enemy.get_cur_pos()):
			continue
		var enemy_moves: Array[Vector2i] = enemy.cur_moves
		if enemy is TowerRotatePiece:
			enemy_moves = (enemy as TowerRotatePiece).cur_possible_rotate_moves

		if enemy_moves.has(destination):
			return true	

	return false

func is_unprotected_move(piece: Piece, destination: Vector2i) -> bool:
	if not is_move_threatened(destination):
		return false

	var enemy_player := 1 if player_number == 2 else 2
	var captured: Piece = null
	if board.hasCellInVision(player_number, destination):
		captured = board.get_enemy_piece_at_cell(destination, enemy_player)

	if (
		captured != null
		and captured.get_instance_id() == last_enemy_capturer_id
	):
		return false

	return not is_destination_guarded(piece, destination, captured)

func is_enemy_guarded_by_ally(
	attacker: Piece,
	moving_piece: Piece
) -> bool:
	for node in board.player_pieces[player_number - 1]:
		var ally := node as Piece
		if ally == null or ally == moving_piece:
			continue

		var ally_moves: Array[Vector2i] = ally.cur_moves
		if ally is TowerRotatePiece:
			ally_moves = (ally as TowerRotatePiece).cur_possible_rotate_moves

		if ally_moves.has(attacker.get_cur_pos()):
			return true

	return false

func is_destination_guarded(
	moving_piece: Piece,
	destination: Vector2i,
	captured: Piece
) -> bool:
	var visible_attackers: Array[Piece] = []

	for node in board.player_pieces[1 if player_number == 2 else 0]:
		var enemy := node as Piece
		if enemy == null or enemy == captured:
			continue
		if not board.hasCellInVision(player_number, enemy.get_cur_pos()):
			continue

		var enemy_moves: Array[Vector2i] = enemy.cur_moves
		if enemy is TowerRotatePiece:
			enemy_moves = (enemy as TowerRotatePiece).cur_possible_rotate_moves

		if enemy_moves.has(destination):
			visible_attackers.append(enemy)

	if visible_attackers.is_empty():
		return false

	for attacker in visible_attackers:
		var attacker_is_guarded := false

		for node in board.player_pieces[player_number - 1]:
			var ally := node as Piece
			if ally == null or ally == moving_piece:
				continue

			var ally_moves: Array[Vector2i] = ally.cur_moves
			if ally is TowerRotatePiece:
				ally_moves = (ally as TowerRotatePiece).cur_possible_rotate_moves

			if ally_moves.has(attacker.get_cur_pos()):
				attacker_is_guarded = true
				break

		if not attacker_is_guarded:
			return false

	return true

func get_moves_from_position(enemy: Piece, position: Vector2i) -> Array[Vector2i]:
	if enemy is TowerRotatePiece:
		var tower := enemy as TowerRotatePiece
		var saved_direction := tower.cur_direction
		var saved_moves := tower.cur_moves.duplicate()
		var saved_rotate_moves := tower.cur_possible_rotate_moves.duplicate()

		var moves := tower.generate_all_possible_moves_with_rotation(position)

		tower.cur_direction = saved_direction
		tower.cur_moves = saved_moves
		tower.cur_possible_rotate_moves = saved_rotate_moves
		return moves

	var saved_moves := enemy.cur_moves.duplicate()
	var moves := enemy.generate_possible_moves(position)
	enemy.cur_moves = saved_moves
	return moves


func is_guarded_against_attacker(
	moving_piece: Piece,
	attacker_position: Vector2i
) -> bool:
	for node in board.player_pieces[player_number - 1]:
		var ally := node as Piece
		if ally == null or ally == moving_piece:
			continue

		var ally_moves: Array[Vector2i] = ally.cur_moves
		if ally is TowerRotatePiece:
			ally_moves = (ally as TowerRotatePiece).cur_possible_rotate_moves

		if ally_moves.has(attacker_position):
			return true

	return false

func score_move(piece: Piece, destination: Vector2i, core_under_attack: bool) -> float:
	var enemy_player := 1 if player_number == 2 else 2
	var defensive_factor := get_defensive_factor()
	var own_core := find_core(player_number)

	if own_core == null:
		return 0.0


	var total_captures := (
		board.player_captures[0].size()
		+ board.player_captures[1].size()
	)
	var protect_eyes_early := total_captures < 4

	# Candidate destinations should be in the CPU's vision. Only inspect
	# an enemy occupying a destination the CPU can currently see.
	var captured: Piece = null
	if board.hasCellInVision(player_number, destination):
		captured = board.get_enemy_piece_at_cell(destination, enemy_player)

	var is_recapture := (
		captured != null
		and captured.get_instance_id() == last_enemy_capturer_id
	)

	var score: float = 0.0

	# var captured_threatens_core := (
	# 	captured != null
	# 	and captured.cur_moves.has(own_core.get_cur_pos())
	# )
	# if core_under_attack and piece is CorePiece:
	# 	if captured_threatens_core:
	# 		score += 1600.0
	# 	else:
	# 		score += 100.0

	var captured_threatens_core := (
		captured != null
		and get_capture_moves(captured).has(own_core.get_cur_pos())
	)

	var non_core_pieces_left := count_non_core_pieces()

	if core_under_attack and captured_threatens_core:
		if piece is CorePiece:
			if non_core_pieces_left <= CORE_CAPTURE_ENDGAME_PIECES:
				score += 1600.0
			else:
				score -= 5000.0
		else:
			score += 2000.0
	elif core_under_attack and piece is CorePiece:
		score += 100.0

	var own_support_after := count_core_support(
		player_number,
		own_core.get_cur_pos(),
		piece,
		destination
	)


	var old_position := piece.get_cur_pos()

	var core_position := own_core.get_cur_pos()
	var support_before := count_core_support(player_number, core_position)
	var is_last_core_supporter := (
		piece.cur_vision.has(core_position)
		and support_before == 1
	)

	if protect_eyes_early and piece is EyePiece:
		var distance_from_core := hex_distance(
			old_position,
			own_core.get_cur_pos()
		)
		var destination_from_core := hex_distance(
			destination,
			own_core.get_cur_pos()
		)

		# Keep the Eyes in a three-hex ring around their core early on.
		if destination_from_core > 3:
			score -= float(destination_from_core - 3) * 40.0

		# Discourage advancing an Eye toward the front early in the game.
		if destination_from_core > distance_from_core:
			score -= float(destination_from_core - distance_from_core) * 25.0

		var cover_before := count_possible_eye_cover(old_position)

		var cover_after := count_possible_eye_cover(
			destination,
			piece,
			destination
		)

		score += float(cover_after - cover_before) * 35.0

	var new_vision: Array[Vector2i] = piece.get_potential_vision(destination)

	score += score_scouting_action(
		piece,
		old_position,
		destination,
		enemy_player
	)

	if piece is TowerRotatePiece and not should_keep_scouting(enemy_player):
		for node in board.player_pieces[enemy_player - 1]:
			var enemy := node as Piece
			if enemy == null:
				continue

			var enemy_cell := enemy.get_cur_pos()
			if (
				new_vision.has(enemy_cell)
				and not board.hasCellInVision(player_number, enemy_cell)
			):
				score += 100.0

	if not (piece is EyePiece):
		for spawn_cell in board.get_possible_spawn_locations():
			if not board.hasCellInVision(player_number, spawn_cell):
				var distance_before := hex_distance(old_position, spawn_cell)
				var distance_after := hex_distance(destination, spawn_cell)
				score += float(distance_before - distance_after) * 2.0
	
	for last_seen_position in enemy_last_seen.values():
		if not board.hasCellInVision(player_number, last_seen_position):
			var distance_before := hex_distance(old_position, last_seen_position)
			var distance_after := hex_distance(destination, last_seen_position)
			score += float(distance_before - distance_after) * 3.0


	if (piece is TowerRotatePiece or HopPiece):
		var vision_without_piece := {}

		for node in board.player_pieces[player_number - 1]:
			var ally := node as Piece
			if ally == null or ally == piece:
				continue

			for cell in ally.cur_vision:
				vision_without_piece[cell] = true

		# Reward revealing enemies that are currently hidden from all friendly pieces.
		for node in board.player_pieces[enemy_player - 1]:
			var enemy := node as Piece
			if enemy == null:
				continue

			var enemy_cell := enemy.get_cur_pos()
			if (
				new_vision.has(enemy_cell)
				and not vision_without_piece.has(enemy_cell)
			):
				score -= float(piece.piece_value) * 5.0
				# score += 80.0

	if not (piece is CorePiece):
		var cover_before := count_possible_eye_cover(old_position)
		var cover_after := count_possible_eye_cover(
			destination,
			piece,
			destination
		)

		score += float(cover_after - cover_before) * 35.0
		score *= maxf(1.0, float(piece.piece_value))

	if core_under_attack and piece is CorePiece:
		score += 1000.0

	# if captured != null:
	# 	score += 90.0
	# if captured != null:
	# 	score += float(captured.piece_value) * 50.0

	# 	if board.can_enemy_recapture_after_move(piece, destination, captured):
	# 		var recapture_penalty := float(piece.piece_value) * 25.0
	# 		score -= recapture_penalty#float(piece.piece_value) * 50.0

	# 	# Keep your existing bonus for capturing an enemy threatening an ally.
	# 	for ally_node in board.player_pieces[player_number - 1]:
	# 		var ally := ally_node as Piece
	# 		if ally == null or ally == piece:
	# 			continue
	# 		if captured.cur_moves.has(ally.get_cur_pos()):
	# 			score += 100.0 if ally is CorePiece else 55.0
	# 			break

	if captured != null:

		if piece is CorePiece and has_non_core_capture(captured):
			score -= 1000.0

		var capture_reward := 70.0 + float(captured.piece_value) * 35.0
		var is_lower_value_capture :bool = captured.piece_value < piece.piece_value

		# if is_lower_value_capture and not is_recapture:
		# 	capture_reward *= 0.25 if total_captures < 4 else 0.5
		if is_lower_value_capture and not is_recapture:
			if piece is TowerRotatePiece and captured is HopPiece:
				capture_reward *= 0.05 if total_captures < 4 else 0.1
			else:
				capture_reward *= 0.25 if total_captures < 4 else 0.5

		score += capture_reward

		if not is_last_core_supporter:
			var distance_from_core := hex_distance(old_position, core_position)
			if distance_from_core <= 4:
				score += (
					float(5 - distance_from_core)
					* CORE_GUARD_CAPTURE_BONUS_PER_HEX
				)


		if captured is EyePiece and is_lower_value_capture:
			var value_gap := float(captured.piece_value - piece.piece_value)
			var cheaper_piece_factor := value_gap / maxf(1.0, float(captured.piece_value))
			score += LOW_VALUE_EYE_CAPTURE_BONUS * cheaper_piece_factor

		if captured.piece_value >= piece.piece_value:
			score += 200.0

		if board.can_enemy_recapture_after_move(piece, destination, captured):
			var recapture_penalty := float(piece.piece_value) * 25.0
			score -= recapture_penalty

		var has_more_valuable_capture := false

		for node in board.player_pieces[enemy_player - 1]:
			var enemy := node as Piece
			if enemy == null or enemy == captured:
				continue

			if (
				board.hasCellInVision(player_number, enemy.get_cur_pos())
				and get_capture_moves(piece).has(enemy.get_cur_pos())
				and enemy.piece_value > captured.piece_value
			):
				has_more_valuable_capture = true
				break

		if (
			not has_more_valuable_capture
			and piece.piece_value == captured.piece_value
		):
			score += 60.0

	# Strongly prioritize recapturing an enemy that just took a friendly piece.
	if captured != null and captured.piece_value <= 5:
		for ally_node in board.player_pieces[player_number - 1]:
			var ally := ally_node as Piece
			if ally == null or ally == piece or ally is CorePiece:
				continue

			# The ally can capture the enemy piece on its next move.
			if ally.cur_moves.has(captured.get_cur_pos()):
				score += 300.0
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
		# Reward scouting, with a stronger preference for low-value pieces.
	var newly_seen_cells := 0
	for cell in new_vision:
		if not board.hasCellInVision(player_number, cell):
			newly_seen_cells += 1

	var scouting_factor := 1.0 / (1.0 + float(piece.piece_value) * 0.35)
	score += float(newly_seen_cells) * 2.5 * scouting_factor

	# Strongly reward discovering an enemy that was outside our current vision.
	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy == null:
			continue

		var enemy_cell := enemy.get_cur_pos()
		if (
			not board.hasCellInVision(player_number, enemy_cell)
			and new_vision.has(enemy_cell)
		):
			score += 90.0 * scouting_factor
	
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
	if total_captures < CORE_SUPPORT_ENDGAME_CAPTURE_COUNT:
		var support_shortfall := maxi(
			0,
			MIN_EARLY_CORE_SUPPORT - own_support_after
		)
		score -= float(support_shortfall) * 1000.0
	else:
		if own_support_after == 0:
			score -= 100000.0
		elif own_support_after == 1:
			score -= 100.0

	# A threatened destination is safer if allies can answer every
	# visible attacker from their current squares.
	var threatened_before := false
	var threatened_after := false

	for node in board.player_pieces[enemy_player - 1]:
		var enemy_piece := node as Piece
		if enemy_piece == null or enemy_piece == captured:
			continue
		if not board.hasCellInVision(player_number, enemy_piece.get_cur_pos()):
			continue

		if enemy_piece.cur_moves.has(old_position):
			threatened_before = true

		var enemy_moves: Array[Vector2i] = enemy_piece.cur_moves
		if enemy_piece is TowerRotatePiece:
			enemy_moves = (enemy_piece as TowerRotatePiece).cur_possible_rotate_moves

		if enemy_moves.has(destination):
			var value := float(piece.piece_value)
			var attacker_value := float(enemy_piece.piece_value)

			var loss_penalty := 300.0 + value * value * 40.0
			loss_penalty *= defensive_factor

			if value > attacker_value:
				loss_penalty += (value - attacker_value) * 120.0

			if is_enemy_guarded_by_ally(enemy_piece, piece):
				loss_penalty *= 0.7

			score -= loss_penalty
	# Remembered threats count less than visible threats, and fade each turn.
	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy == null:
			continue

		var enemy_id := enemy.get_instance_id()
		if not enemy_last_seen.has(enemy_id):
			continue

		# Visible enemies are handled by the normal threat scoring above.
		if board.hasCellInVision(player_number, enemy.get_cur_pos()):
			continue

		var last_position: Vector2i = enemy_last_seen[enemy_id]
		var age := cpu_turn_count - int(enemy_last_seen_turn.get(enemy_id, cpu_turn_count))
		if age > 4:
			continue

		var remembered_moves := get_moves_from_position(enemy, last_position)
		if not remembered_moves.has(destination):
			continue

		var confidence := pow(0.65, float(age))
		var value := float(piece.piece_value)
		var remembered_penalty := (
			(80.0 + value * value * 10.0)
			* confidence
			* defensive_factor
		)

		# Reduce the risk when an ally can answer by attacking the
		# enemy's last known square.
		if is_guarded_against_attacker(piece, last_position):
			remembered_penalty *= 0.25

		score -= remembered_penalty

	if threatened_before and not threatened_after:
		score += 250.0 + float(piece.piece_value) * 100.0

	if not threatened_after:
		if (
			piece is CorePiece
			and non_core_pieces_left <= CORE_MOVE_ENDGAME_PIECES_LEFT
			and own_support_after >= 2
		):
			score += CORE_MOVE_ENDGAME_BONUS
		elif (
			piece is EyePiece
			and non_core_pieces_left <= EYE_MOVE_ENDGAME_PIECES_LEFT
		):
			score += EYE_MOVE_ENDGAME_BONUS

	# Encourage rotating through pieces when choices are close in value.
	if recent_piece_ids.has(piece.get_instance_id()):
		score -= 14.0

	var eye_forks_enabled := non_core_pieces_left <= EYE_MOVE_ENDGAME_PIECES_LEFT
	var can_score_fork := (
		not (piece is CorePiece)
		and not threatened_after
		and (
			not (piece is EyePiece)
			or (eye_forks_enabled and board.is_guarded(piece))
		)
	)

	if can_score_fork:
		var forks_before := count_attacked_enemies(piece, old_position)
		var forks_after := count_attacked_enemies(piece, destination)

		if forks_after >= 2 and forks_after > forks_before:
			if piece is EyePiece:
				score += 60.0
			else:
				score += minf(
					25.0,
					float(forks_after - forks_before) * 12.0
				)

	# if captured != null:
	# 	score += float(captured.piece_value) * 45.0 * VISIBLE_ATTACK_WEIGHT

	score -= float(piece.piece_value) * 5.0

	if should_keep_scouting(enemy_player):
		for node in board.player_pieces[enemy_player - 1]:
			var enemy := node as Piece
			if enemy == null or enemy.is_queued_for_deletion():
				continue

			var enemy_cell := enemy.get_cur_pos()
			if (
				new_vision.has(enemy_cell)
				and not board.hasCellInVision(player_number, enemy_cell)
			):
				score += SCOUT_REVEAL_WEIGHT * enemy_protection_weight(enemy)
	
	if is_recapture:
		if captured is EyePiece:
			score += EYE_RECAPTURE_BONUS * defensive_factor
		else:
			score += RECAPTURE_BONUS * defensive_factor	

	var is_eye_or_triangle := (
		piece is EyePiece
		or piece is TriangleOddPiece
		or piece is TriangleEvenPiece
	)

	if is_eye_or_triangle and captured == null:
		var possible_moves := moves_from_position(piece, destination)
		var threatens_enemy_eye := false

		for node in board.player_pieces[enemy_player - 1]:
			var enemy := node as Piece
			if enemy == null or not (enemy is EyePiece):
				continue

			var enemy_cell := enemy.get_cur_pos()
			if (
				board.hasCellInVision(player_number, enemy_cell)
				or new_vision.has(enemy_cell)
			) and possible_moves.has(enemy_cell):
				threatens_enemy_eye = true
				break

		if threatens_enemy_eye and is_unprotected_move(piece, destination):
			score -= UNGUARDED_EYE_THREAT_PENALTY

	if total_captures < EARLY_GAME_CAPTURE_LIMIT and piece is HopPiece:
		var tower_lead := mini(
			maxi(0, early_tower_move_count - early_hop_move_count),
			MAX_HOP_CATCH_UP_BONUS
		)
		score += EARLY_HOP_MOVE_BONUS + float(tower_lead) * HOP_CATCH_UP_BONUS

	return score


func find_core(player_id: int) -> CorePiece:
	for node in board.player_pieces[player_id - 1]:
		if node is CorePiece:
			return node as CorePiece
	return null

func should_keep_scouting(enemy_player: int) -> bool:
	var alive_count := 0
	var visible_count := 0

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy == null or enemy.is_queued_for_deletion():
			continue

		alive_count += 1
		if board.hasCellInVision(player_number, enemy.get_cur_pos()):
			visible_count += 1

	# Stop the scouting bonus once at least half of living enemies are visible.
	return alive_count > 0 and visible_count * 4 < alive_count


func enemy_protection_weight(enemy: Piece) -> float:
	var protection := 0

	for node in board.player_pieces[enemy.owned_player - 1]:
		var ally := node as Piece
		if ally == null or ally == enemy:
			continue

		if ally.cur_vision.has(enemy.get_cur_pos()):
			protection += 1

	return 1.0 + minf(float(protection) * 0.5, 2.0)


func score_scouting_action(
	piece: Piece,
	old_position: Vector2i,
	destination: Vector2i,
	enemy_player: int
) -> float:
	if not should_keep_scouting(enemy_player):
		return 0.0

	var new_vision: Array[Vector2i] = piece.get_potential_vision(destination)
	var score := 0.0

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy == null or enemy.is_queued_for_deletion():
			continue

		var enemy_cell := enemy.get_cur_pos()
		if board.hasCellInVision(player_number, enemy_cell):
			continue

		var protection := enemy_protection_weight(enemy)
		var distance_gain := (
			hex_distance(old_position, enemy_cell)
			- hex_distance(destination, enemy_cell)
		)

		score += float(distance_gain) * SCOUT_APPROACH_WEIGHT * protection

		if new_vision.has(enemy_cell):
			score += SCOUT_REVEAL_WEIGHT * protection

	if not moved_piece_ids.has(piece.get_instance_id()):
		score += 60.0
	if piece is TowerRotatePiece:
		score *= TOWER_SCOUT_MULTIPLIER
	elif piece is HopPiece:
		var captures_so_far := (
			board.player_captures[0].size()
			+ board.player_captures[1].size()
		)
		if captures_so_far < EARLY_GAME_CAPTURE_LIMIT:
			score *= EARLY_HOP_SCOUT_MULTIPLIER

	if piece is HopPiece:
		score *= 1.5 if next_scout_piece_type == "hop" else 0.1
	elif piece is TowerRotatePiece:
		score *= 1.5 if next_scout_piece_type == "tower" else 0.1

	return score

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

func count_possible_eye_cover(
	eye_position: Vector2i,
	moving_piece: Piece = null,
	moving_destination: Vector2i = Vector2i.ZERO
) -> int:
	var count := 0

	for node in board.player_pieces[player_number - 1]:
		var piece := node as Piece
		if piece == null or piece is CorePiece or piece == moving_piece:
			continue

		if piece is TowerRotatePiece:
			var tower := piece as TowerRotatePiece
			for direction in range(6):
				if tower.get_potential_vision(
					tower.get_cur_pos(),
					direction
				).has(eye_position):
					count += 1
					break
		else:
			var vision: Array[Vector2i]
			if piece == moving_piece:
				vision = piece.get_potential_vision(moving_destination)
			else:
				vision = piece.cur_vision

			if vision.has(eye_position):
				count += 1

	return count

func get_capture_moves(piece: Piece) -> Array[Vector2i]:
	if piece is TowerRotatePiece:
		var tower := piece as TowerRotatePiece
		return tower.generate_all_possible_moves_with_rotation(
			tower.get_cur_pos()
		)

	return piece.cur_moves

func has_non_core_capture(target: Piece) -> bool:
	var enemy_cell := target.get_cur_pos()

	for node in board.player_pieces[player_number - 1]:
		var ally := node as Piece
		if ally == null or ally is CorePiece:
			continue

		if (
			board.hasCellInVision(player_number, enemy_cell)
			and get_capture_moves(ally).has(enemy_cell)
		):
			return true

	return false

func count_attacked_enemies(piece: Piece, destination: Vector2i) -> int:
	var potential_moves: Array[Vector2i]

	if piece is TowerRotatePiece:
		potential_moves = (piece as TowerRotatePiece) \
			.generate_all_possible_moves_with_rotation(destination)
	else:
		potential_moves = piece.generate_possible_moves(destination)

	var attacked := 0
	for node in board.player_pieces[1 if player_number == 2 else 0]:
		var enemy := node as Piece
		if enemy == null:
			continue

		if potential_moves.has(enemy.get_cur_pos()):
			attacked += 1

	return attacked

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
			remember_enemies_in_vision(tower.cur_vision)

func remember_enemies_in_vision(visible_cells: Array[Vector2i]) -> void:
	var enemy_player := 1 if player_number == 2 else 2

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy == null:
			continue

		var enemy_position := enemy.get_cur_pos()
		if visible_cells.has(enemy_position):
			var enemy_id := enemy.get_instance_id()
			enemy_last_seen[enemy_id] = enemy_position
			enemy_last_seen_turn[enemy_id] = cpu_turn_count

func score_tower_rotation(
	tower: TowerRotatePiece,
	new_vision: Array[Vector2i],
	enemy_player: int
) -> float:
	var other_vision := {}

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

	# Before finding the enemy, strongly favor rotations that reveal
	# previously unseen enemy pieces, wherever they are.
	if should_keep_scouting(enemy_player):
		for node in board.player_pieces[enemy_player - 1]:
			var enemy := node as Piece
			if enemy == null:
				continue

			var enemy_cell := enemy.get_cur_pos()
			if (
				new_vision.has(enemy_cell)
				and not board.hasCellInVision(player_number, enemy_cell)
			):
				score += 100.0

	return score


func has_visible_enemy_piece(enemy_player: int) -> bool:
	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Piece
		if enemy != null and board.hasCellInVision(
			player_number,
			enemy.get_cur_pos()
		):
			return true

	return false

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

func count_non_core_pieces() -> int:
	var count := 0

	for node in board.player_pieces[player_number - 1]:
		var piece := node as Piece
		if piece != null and not (piece is CorePiece):
			count += 1

	return count

func get_material_value(player_id: int) -> float:
	var total := 0.0

	for node in board.player_pieces[player_id - 1]:
		var piece := node as Piece
		if piece == null or piece.is_queued_for_deletion():
			continue
		total += float(piece.piece_value)

	return total


func get_defensive_factor() -> float:
	var enemy_player := 1 if player_number == 2 else 2
	var deficit := (
		get_material_value(enemy_player)
		- get_material_value(player_number)
	)

	# 1.0 when even or ahead; rises to 3.0 as the CPU falls behind.
	return 1.0 + minf(maxf(deficit, 0.0) / 20.0, 2.0)

func is_running_away(piece: Piece, destination: Vector2i) -> bool:
	var current_position := piece.get_cur_pos()

	return (
		is_move_threatened(current_position)
		and not is_move_threatened(destination)
	)


func moves_from_position(piece: Piece, position: Vector2i) -> Array[Vector2i]:
	var original_moves := piece.cur_moves.duplicate()

	if piece is TowerRotatePiece:
		var tower := piece as TowerRotatePiece
		var original_rotate_moves := tower.cur_possible_rotate_moves.duplicate()
		var moves := tower.generate_all_possible_moves_with_rotation(position)
		tower.cur_possible_rotate_moves = original_rotate_moves
		return moves

	var moves := piece.generate_possible_moves(position)
	piece.cur_moves = original_moves
	return moves


# func should_keep_scouting(enemy_player: int) -> bool:
# 	var alive_count := 0
# 	var visible_count := 0

# 	for node in board.player_pieces[enemy_player - 1]:
# 		var enemy := node as Piece
# 		if enemy == null or enemy.is_queued_for_deletion():
# 			continue

# 		alive_count += 1
# 		if board.hasCellInVision(player_number, enemy.get_cur_pos()):
# 			visible_count += 1

# 	# Integer comparison avoids rounding issues: 2 * visible >= alive
# 	return alive_count > 0 and visible_count * 2 < alive_count