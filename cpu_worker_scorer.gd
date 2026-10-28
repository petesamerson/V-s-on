extends RefCounted
const Model = preload("res://cpu_worker_model.gd")
var chosen_action: Dictionary = {}
var turn_deadline: int = 0

const CORE_CAPTURE_ENDGAME_PIECES := 3

const EYE_MOVE_ENDGAME_PIECES_LEFT := 6
const EYE_MOVE_ENDGAME_BONUS := 45.0
const EYE_RECAPTURE_BONUS := 1200.0
const EARLY_EYE_CAPTURE_LIMIT := 16

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

var cpu_cover_counts: Dictionary = {}
var cpu_cover_by_piece: Dictionary = {}

var capture_danger: Dictionary = {}
var reversal_origins: Dictionary = {}

var player_number: int = 2
var difficulty: int = 5

const TacticalSearch = preload("res://cpu_worker_search.gd")
const SpawnKnowledge = preload("res://cpu_worker_spawn.gd")

var spawn_knowledge = SpawnKnowledge.new()

var seen_by_player = false

var board: Model.DataBoard
var last_moved_piece: Model.DataPiece
var recent_piece_ids: Array[int] = []
var moved_piece_ids: Dictionary = {}
var rng := RandomNumberGenerator.new()

var enemy_last_seen: Dictionary = {}
var cpu_turn_count := 0
var enemy_last_seen_turn: Dictionary = {}
var observed_enemy_capture_count := 0
var last_enemy_capturer_id := -1

var cpu_slice_started_us: int = 0

const Cancellation = preload("res://cpu_cancellation.gd")
var cancellation: Cancellation


func _cancelled() -> bool:
	return cancellation != null and cancellation.is_cancelled()

func setup(game_board: Model.DataBoard) -> void:
	print("cpu created with difficulty " + str(difficulty))
	rng.randomize()
	board = game_board


func take_turn() -> void:
	if _cancelled():
		return
	if board == null or board.current_player != player_number:
		return

	cpu_slice_started_us = Time.get_ticks_usec()
	cpu_turn_count += 1

	if cpu_turn_count == 1:
		spawn_knowledge.initialize(board, player_number)

	spawn_knowledge.observe(
		board,
		player_number,
		difficulty,
		cpu_turn_count
	)

	if(difficulty < 4):
		rotate_towers_for_turn()

	rebuild_cpu_cover_cache()

	var enemy_player := 1 if player_number == 2 else 2

	var enemy_capture_count := board.player_captures[enemy_player - 1].size()

	if enemy_capture_count > observed_enemy_capture_count:
		var enemy_index := enemy_player - 1
		last_enemy_capturer_id = board.last_capture_capturer_ids[enemy_index]

		for node in board.player_pieces[enemy_index]:

			if _cancelled():
				return

			var capturer := node as Model.DataPiece
			if (
				capturer != null
				and capturer.get_instance_id() == last_enemy_capturer_id
			):
				enemy_last_seen[last_enemy_capturer_id] = capturer.get_cur_pos()
				enemy_last_seen_turn[last_enemy_capturer_id] = cpu_turn_count
				break

	# Copy before updating because this dictionary crosses the worker boundary.
	capture_danger = capture_danger.duplicate(true)

	for i in range(observed_enemy_capture_count, enemy_capture_count):
		var record: Dictionary = board.player_captures[enemy_player - 1][i]
		if record.has("cell"):
			capture_danger[record["cell"]] = cpu_turn_count

	for cell in capture_danger.keys():
		if cpu_turn_count - int(capture_danger[cell]) > 4:
			capture_danger.erase(cell)	

	observed_enemy_capture_count = enemy_capture_count

	for node in board.player_pieces[enemy_player - 1]:
		if _cancelled():
			return
		var enemy := node as Model.DataPiece
		if enemy != null and board.hasCellInVision(player_number, enemy.get_cur_pos()):
			var enemy_id := enemy.get_instance_id()
			enemy_last_seen[enemy_id] = enemy.get_cur_pos()
			enemy_last_seen_turn[enemy_id] = cpu_turn_count


	board.regenerate_all_piece_moves(enemy_player, true)

	var visible_enemy_core := find_visible_core(enemy_player)

	var own_core := find_core(player_number)
	var core_under_attack := (
		own_core != null
		and board.is_piece_under_attack(own_core)
	)
	var core_attackers: Array[Model.DataPiece] = []

	if core_under_attack and own_core != null:
		for node in board.player_pieces[enemy_player - 1]:
			if _cancelled():
				return
			var attacker := node as Model.DataPiece
			if attacker == null:
				continue

			var attacker_moves := attacker.cur_moves
			if attacker is Model.DataTowerRotatePiece:
				attacker_moves = (attacker as Model.DataTowerRotatePiece).cur_possible_rotate_moves

			if attacker_moves.has(own_core.get_cur_pos()):
				core_attackers.append(attacker)

	var non_core_pieces_left := count_non_core_pieces()

	var actions: Array[Dictionary] = []

	for node in board.player_pieces[player_number - 1]:
		if _cancelled():
			return

		var piece := node as Model.DataPiece
		if piece == null:
			continue

		var destinations: Array[Vector2i] = []
		if(piece is Model.DataCorePiece):
			destinations = (piece as Model.DataCorePiece).generate_possible_moves(piece.get_cur_pos())
		elif(piece is Model.DataTowerRotatePiece):
			destinations = (piece as Model.DataTowerRotatePiece).generate_possible_moves(piece.get_cur_pos())
		else:
			destinations = piece.generate_possible_moves(piece.get_cur_pos())

		destinations = destinations.duplicate()

		for destination in destinations:
			if _cancelled():
				return

			if (
				difficulty < 4
				and piece is Model.DataEyePiece
				and non_core_pieces_left > EYE_MOVE_ENDGAME_PIECES_LEFT
				and not is_running_away(piece, destination)
			):
				continue

			if (
				difficulty < 4
				and piece is Model.DataEyePiece
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

			var reversal_penalty: float = return_move_penalty(
				piece, destination, core_under_attack
			)
			move_score -= reversal_penalty

			move_score += rng.randf_range(-randomness, randomness)

			actions.append({
				"piece": piece,
				"destination": destination,
				"score": move_score,
				"reversal_penalty": reversal_penalty,
				"unprotected_danger": is_unprotected_move(piece, destination),
				"scout_score": score_scouting_action(
					piece,
					piece.get_cur_pos(),
					destination,
					enemy_player
				),
			})
	var validated_actions: Array[Dictionary] = []

	for action in actions:
		if _cancelled():
			return

		var candidate := action["piece"] as Model.DataPiece

		if not is_instance_valid(candidate):
			continue

		if candidate is Model.DataTriangleEvenPiece or candidate is Model.DataTriangleOddPiece:
			var legal_moves: Array[Vector2i] = (
				candidate.generate_possible_moves(
					candidate.get_cur_pos()
				).duplicate()
			)

			if not legal_moves.has(action["destination"]):
				push_warning(
					"CPU rejected an invalid triangle move: %s -> %s"
					% [
						candidate.get_cur_pos(),
						action["destination"]
					]
				)
				continue

		validated_actions.append(action)

	actions = validated_actions

	if core_under_attack:
		var emergency_actions: Array[Dictionary] = _core_emergency_actions(
			actions, own_core
		)
		if not emergency_actions.is_empty():
			actions = emergency_actions

	if difficulty >= 4 and not actions.is_empty():
		var search = TacticalSearch.new()
		search.cancellation = cancellation
		search.turn_deadline = turn_deadline
		var captures_so_far: int = (
			board.player_captures[0].size()
			+ board.player_captures[1].size()
		)

		search.early_eye_protection = 1.0 - clampf(
			float(captures_so_far) / float(EARLY_EYE_CAPTURE_LIMIT),
			0.0,
			1.0
		)
		search.memory_risk = build_memory_risk()

		var material_lead: float = (
			get_material_value(player_number)
			- get_material_value(enemy_player)
		)

		search.aggression = 1.0 + clampf(
			material_lead / 10.0,
			0.0,
			1.0
		)

		var searched_action: Dictionary = search.choose(
			board,
			player_number,
			difficulty,
			actions,
			last_enemy_capturer_id
		)
		if not searched_action.is_empty():
			actions.clear()
			actions.append(searched_action)

	if core_under_attack and difficulty < 4:
		var defensive_actions: Array[Dictionary] = []

		for action in actions:
			if(_cancelled()):
				return
			var resolves_threat := action["piece"] is Model.DataCorePiece

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
		if _cancelled():
			return
		if not action["unprotected_danger"]:
			safer_actions.append(action)

	if not safer_actions.is_empty():
		actions = safer_actions

		if should_keep_scouting(enemy_player):
			var preferred_scout_actions: Array[Dictionary] = []

			for action in actions:
				if _cancelled():
					return
				if float(action["scout_score"]) <= 0.0:
					continue

				var candidate := action["piece"] as Model.DataPiece
				if (
					next_scout_piece_type == "hop" and candidate is Model.DataHopPiece
				) or (
					next_scout_piece_type == "tower" and candidate is Model.DataTowerRotatePiece
				):
					preferred_scout_actions.append(action)

			if not preferred_scout_actions.is_empty():
				actions = preferred_scout_actions

	var best_score: float = -INF
	for action in actions:
		if _cancelled():
			return
		best_score = maxf(best_score, action["score"])

	var shortlist: Array[Dictionary] = []
	for action in actions:
		if _cancelled():
			return
		var tolerance_by_difficulty := [
			500.0, 250.0, 90.0, 25.0, 8.0, 0.0
		]
		var tolerance: float = tolerance_by_difficulty[
			clampi(difficulty - 1, 0, 5)
		]
		if action["score"] >= best_score - tolerance:
			shortlist.append(action)

	var choice: Dictionary = shortlist.pick_random()
	var chosen_piece := choice["piece"] as Model.DataPiece
	if (
		float(choice["scout_score"]) > 0.0
		and (chosen_piece is Model.DataHopPiece or chosen_piece is Model.DataTowerRotatePiece)
	):
		next_scout_piece_type = "hop" if rng.randf() < 0.5 else "tower"

	var total_captures := (
		board.player_captures[0].size()
		+ board.player_captures[1].size()
	)


	var destination: Vector2i = choice["destination"]
	var old_position := chosen_piece.get_cur_pos()


	if score_scouting_action(
		chosen_piece,
		old_position,
		destination,
		enemy_player
	) > 0.0:
		if chosen_piece is Model.DataHopPiece:
			next_scout_piece_type = "tower"
		elif chosen_piece is Model.DataTowerRotatePiece:
			next_scout_piece_type = "hop"

	recent_piece_ids.push_front(chosen_piece.get_instance_id())
	if recent_piece_ids.size() > 2:
		recent_piece_ids.pop_back()

	last_moved_piece = chosen_piece
	moved_piece_ids[chosen_piece.get_instance_id()] = true
	chosen_action = choice.duplicate()

	if chosen_piece is Model.DataTowerRotatePiece:
		var tower := chosen_piece as Model.DataTowerRotatePiece
		tower.cur_direction = int(
			choice.get("direction", tower.cur_direction)
		)

	last_enemy_capturer_id = -1

func is_move_threatened(destination: Vector2i) -> bool:
	var enemy_player := 1 if player_number == 2 else 2
	var captured: Model.DataPiece = null

	if board.hasCellInVision(player_number, destination):
		captured = board.get_enemy_piece_at_cell(destination, enemy_player)

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Model.DataPiece
		if enemy == null or enemy == captured:
			continue
		if not board.hasCellInVision(player_number, enemy.get_cur_pos()):
			continue
		var enemy_moves: Array[Vector2i] = enemy.cur_moves
		if enemy is Model.DataTowerRotatePiece:
			enemy_moves = (enemy as Model.DataTowerRotatePiece).cur_possible_rotate_moves

		if enemy_moves.has(destination):
			return true

	return false

func is_unprotected_move(piece: Model.DataPiece, destination: Vector2i) -> bool:
	if not is_move_threatened(destination):
		return false

	var enemy_player := 1 if player_number == 2 else 2
	var captured: Model.DataPiece = null
	if board.hasCellInVision(player_number, destination):
		captured = board.get_enemy_piece_at_cell(destination, enemy_player)

	if (
		captured != null
		and captured.get_instance_id() == last_enemy_capturer_id
	):
		return false

	return not is_destination_guarded(piece, destination, captured)

func is_enemy_guarded_by_ally(
	attacker: Model.DataPiece,
	moving_piece: Model.DataPiece
) -> bool:
	for node in board.player_pieces[player_number - 1]:
		var ally := node as Model.DataPiece
		if ally == null or ally == moving_piece:
			continue

		var ally_moves: Array[Vector2i] = ally.cur_moves
		if ally is Model.DataTowerRotatePiece:
			ally_moves = (ally as Model.DataTowerRotatePiece).cur_possible_rotate_moves

		if ally_moves.has(attacker.get_cur_pos()):
			return true

	return false

func is_destination_guarded(
	moving_piece: Model.DataPiece,
	destination: Vector2i,
	captured: Model.DataPiece
) -> bool:
	var visible_attackers: Array[Model.DataPiece] = []

	for node in board.player_pieces[1 if player_number == 2 else 0]:
		var enemy := node as Model.DataPiece
		if enemy == null or enemy == captured:
			continue
		if not board.hasCellInVision(player_number, enemy.get_cur_pos()):
			continue

		var enemy_moves: Array[Vector2i] = enemy.cur_moves
		if enemy is Model.DataTowerRotatePiece:
			enemy_moves = (enemy as Model.DataTowerRotatePiece).cur_possible_rotate_moves

		if enemy_moves.has(destination):
			visible_attackers.append(enemy)

	if visible_attackers.is_empty():
		return false

	for attacker in visible_attackers:
		var attacker_is_guarded := false

		for node in board.player_pieces[player_number - 1]:
			var ally := node as Model.DataPiece
			if ally == null or ally == moving_piece:
				continue

			var ally_moves: Array[Vector2i] = ally.cur_moves
			if ally is Model.DataTowerRotatePiece:
				ally_moves = (ally as Model.DataTowerRotatePiece).cur_possible_rotate_moves

			if ally_moves.has(attacker.get_cur_pos()):
				attacker_is_guarded = true
				break

		if not attacker_is_guarded:
			return false

	return true

func get_moves_from_position(enemy: Model.DataPiece, position: Vector2i) -> Array[Vector2i]:
	if enemy is Model.DataTowerRotatePiece:
		var tower := enemy as Model.DataTowerRotatePiece
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
	moving_piece: Model.DataPiece,
	attacker_position: Vector2i
) -> bool:
	for node in board.player_pieces[player_number - 1]:
		var ally := node as Model.DataPiece
		if ally == null or ally == moving_piece:
			continue

		var ally_moves: Array[Vector2i] = ally.cur_moves
		if ally is Model.DataTowerRotatePiece:
			ally_moves = (ally as Model.DataTowerRotatePiece).cur_possible_rotate_moves

		if ally_moves.has(attacker_position):
			return true

	return false

func score_move(piece: Model.DataPiece, destination: Vector2i, core_under_attack: bool) -> float:
	var enemy_player := 1 if player_number == 2 else 2
	var defensive_factor := get_defensive_factor()
	var own_core := find_core(player_number)

	if own_core == null:
		return 0.0


	var total_captures := (
		board.player_captures[0].size()
		+ board.player_captures[1].size()
	)
	var game_progress: float = clampf(
		float(total_captures)
		/ float(CORE_SUPPORT_ENDGAME_CAPTURE_COUNT),
		0.0,
		1.0
	)
	var protect_eyes_early := total_captures < EARLY_EYE_CAPTURE_LIMIT

	var captured: Model.DataPiece = null
	if board.hasCellInVision(player_number, destination):
		captured = board.get_enemy_piece_at_cell(destination, enemy_player)

	var is_recapture := (
		captured != null
		and captured.get_instance_id() == last_enemy_capturer_id
	)

	var score: float = 0.0


	var captured_threatens_core := (
		captured != null
		and get_capture_moves(captured).has(own_core.get_cur_pos())
	)

	var non_core_pieces_left := count_non_core_pieces()

	if core_under_attack and captured_threatens_core:
		if piece is Model.DataCorePiece:
			if non_core_pieces_left <= CORE_CAPTURE_ENDGAME_PIECES:
				score += 1600.0
			else:
				score -= 5000.0
		else:
			score += 2000.0
	elif core_under_attack and piece is Model.DataCorePiece:
		score += 100.0

	var core_position_after: Vector2i = own_core.get_cur_pos()
	if piece is Model.DataCorePiece:
		core_position_after = destination

	var own_support_after := count_core_support(
		player_number,
		core_position_after,
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

	if protect_eyes_early and piece is Model.DataEyePiece:
		var distance_from_core := hex_distance(
			old_position,
			own_core.get_cur_pos()
		)
		var destination_from_core := hex_distance(
			destination,
			own_core.get_cur_pos()
		)

		if destination_from_core > 3:
			score -= float(destination_from_core - 3) * 40.0

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

	if piece is Model.DataTowerRotatePiece and not should_keep_scouting(enemy_player):
		for node in board.player_pieces[enemy_player - 1]:
			var enemy := node as Model.DataPiece
			if enemy == null:
				continue

			var enemy_cell := enemy.get_cur_pos()
			if (
				new_vision.has(enemy_cell)
				and not board.hasCellInVision(player_number, enemy_cell)
			):
				score += 100.0

	if not (piece is Model.DataEyePiece):
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


	if (piece is Model.DataTowerRotatePiece or piece is Model.DataHopPiece):
		var vision_without_piece := {}

		for node in board.player_pieces[player_number - 1]:
			var ally := node as Model.DataPiece
			if ally == null or ally == piece:
				continue

			for cell in ally.cur_vision:
				vision_without_piece[cell] = true

		for node in board.player_pieces[enemy_player - 1]:
			var enemy := node as Model.DataPiece
			if enemy == null:
				continue

			var enemy_cell := enemy.get_cur_pos()
			if (
				new_vision.has(enemy_cell)
				and not vision_without_piece.has(enemy_cell)
			):
				score -= float(piece.piece_value) * 5.0

	if not (piece is Model.DataCorePiece):
		var cover_before := count_possible_eye_cover(old_position)
		var cover_after := count_possible_eye_cover(
			destination,
			piece,
			destination
		)

		score += float(cover_after - cover_before) * 35.0
		score *= maxf(1.0, float(piece.piece_value))

	# if core_under_attack and piece is Model.DataCorePiece:
	# 	score += 1000.0




	if captured != null:

		if piece is Model.DataCorePiece and has_non_core_capture(captured):
			score -= 1000.0

		var capture_reward := 70.0 + float(captured.piece_value) * 35.0
		var is_lower_value_capture :bool = captured.piece_value < piece.piece_value

		if is_lower_value_capture and not is_recapture:
			var value_gap: float = (
				float(piece.piece_value) - float(captured.piece_value)
			)

			# Initially discourage spending stronger units on cheaper targets.
			capture_reward *= lerpf(0.1, 0.75, game_progress)

			# Relax the extra penalty as the game progresses.
			if not captured_threatens_core:
				score -= value_gap * lerpf(70.0, 10.0, game_progress)

		score += capture_reward

		if not is_last_core_supporter:
			var distance_from_core := hex_distance(old_position, core_position)
			if distance_from_core <= 4:
				score += (
					float(5 - distance_from_core)
					* CORE_GUARD_CAPTURE_BONUS_PER_HEX
				)


		if captured is Model.DataEyePiece:
			var value_gap: float = (
				float(captured.piece_value) - float(piece.piece_value)
			)
			if value_gap > 0.0:
				var cheaper_piece_factor: float = (
					value_gap / maxf(1.0, float(captured.piece_value))
				)
				score += 500.0 * cheaper_piece_factor

		if captured.piece_value >= piece.piece_value:
			score += 200.0

		if board.can_enemy_recapture_after_move(piece, destination, captured):
			var recapture_penalty := float(piece.piece_value) * 25.0
			score -= recapture_penalty

		var has_more_valuable_capture := false

		for node in board.player_pieces[enemy_player - 1]:
			var enemy := node as Model.DataPiece
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

	if captured != null and captured.piece_value <= 5:
		for ally_node in board.player_pieces[player_number - 1]:
			var ally := ally_node as Model.DataPiece
			if ally == null or ally == piece or ally is Model.DataCorePiece:
				continue

			if ally.cur_moves.has(captured.get_cur_pos()):
				score += 300.0
				break

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
		var enemy := node as Model.DataPiece
		if enemy == null or enemy == captured:
			continue

		var enemy_cell := enemy.get_cur_pos()
		if not board.hasCellInVision(player_number, enemy_cell):
			continue

		var old_distance := hex_distance(piece.get_cur_pos(), enemy_cell)
		var new_distance := hex_distance(destination, enemy_cell)
		score += float(old_distance - new_distance) * 4.0

		var potential_vision := piece.get_potential_vision(destination)
		if potential_vision.has(enemy_cell) and not piece.cur_vision.has(enemy_cell):
			score += 16.0

	var newly_seen_cells := 0
	for cell in new_vision:
		if not board.hasCellInVision(player_number, cell):
			newly_seen_cells += 1

	var scouting_factor := 1.0 / (1.0 + float(piece.piece_value) * 0.35)
	score += float(newly_seen_cells) * 2.5 * scouting_factor

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Model.DataPiece
		if enemy == null:
			continue

		var enemy_cell := enemy.get_cur_pos()
		if (
			not board.hasCellInVision(player_number, enemy_cell)
			and new_vision.has(enemy_cell)
		):
			score += 90.0 * scouting_factor

	if not piece is Model.DataCorePiece:
		for node in board.player_pieces[player_number - 1]:
			var ally := node as Model.DataPiece
			if ally == null or ally == piece or ally is Model.DataCorePiece:
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

	for node in board.player_pieces[player_number - 1]:
		var ally := node as Model.DataPiece
		if ally == null or ally == piece:
			continue

		if board.get_guarders(ally).has(piece):
			if not new_vision.has(ally.get_cur_pos()):
				score -= 60.0
	
	# Start with four Core supporters, gradually reducing toward one.
	var desired_support: int = int(round(
		lerpf(4.0, 1.0, game_progress)
	))

	var support_shortfall: int = maxi(
		0, desired_support - own_support_after
	)

	score -= float(support_shortfall) * 1000.0

	# Never treat an unsupported Core as an acceptable tradeoff.
	if own_support_after == 0:
		score -= 100000.0

	var threatened_before := false
	var threatened_after := false

	for node in board.player_pieces[enemy_player - 1]:
		var enemy_piece := node as Model.DataPiece
		if enemy_piece == null or enemy_piece == captured:
			continue
		if not board.hasCellInVision(player_number, enemy_piece.get_cur_pos()):
			continue

		if enemy_piece.cur_moves.has(old_position):
			threatened_before = true

		var enemy_moves: Array[Vector2i] = enemy_piece.cur_moves
		if enemy_piece is Model.DataTowerRotatePiece:
			enemy_moves = (enemy_piece as Model.DataTowerRotatePiece).cur_possible_rotate_moves

		if enemy_moves.has(destination):
			threatened_after = true
			var value := float(piece.piece_value)
			var attacker_value := float(enemy_piece.piece_value)

			var loss_penalty := 300.0 + value * value * 40.0
			loss_penalty *= defensive_factor

			if value > attacker_value:
				loss_penalty += (value - attacker_value) * 120.0

			if is_enemy_guarded_by_ally(enemy_piece, piece):
				loss_penalty *= 0.7

			score -= loss_penalty
	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Model.DataPiece
		if enemy == null:
			continue

		var enemy_id := enemy.get_instance_id()
		if not enemy_last_seen.has(enemy_id):
			continue

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

		if is_guarded_against_attacker(piece, last_position):
			remembered_penalty *= 0.25

		score -= remembered_penalty

	if threatened_before and not threatened_after:
		score += 250.0 + float(piece.piece_value) * 100.0

	if not threatened_after:
		if (
			piece is Model.DataCorePiece
			and non_core_pieces_left <= CORE_MOVE_ENDGAME_PIECES_LEFT
			and own_support_after >= 2
		):
			score += CORE_MOVE_ENDGAME_BONUS
		elif (
			piece is Model.DataEyePiece
			and non_core_pieces_left <= EYE_MOVE_ENDGAME_PIECES_LEFT
		):
			score += EYE_MOVE_ENDGAME_BONUS

	if recent_piece_ids.has(piece.get_instance_id()):
		score -= 14.0

	var eye_forks_enabled := non_core_pieces_left <= EYE_MOVE_ENDGAME_PIECES_LEFT
	var can_score_fork := (
		not (piece is Model.DataCorePiece)
		and not threatened_after
		and (
			not (piece is Model.DataEyePiece)
			or (eye_forks_enabled and board.is_guarded(piece))
		)
	)

	if can_score_fork:
		var forks_before := count_attacked_enemies(piece, old_position)
		var forks_after := count_attacked_enemies(piece, destination)

		if forks_after >= 2 and forks_after > forks_before:
			if piece is Model.DataEyePiece:
				score += 60.0
			else:
				score += minf(
					25.0,
					float(forks_after - forks_before) * 12.0
				)


	score -= float(piece.piece_value) * 5.0

	if should_keep_scouting(enemy_player):
		for node in board.player_pieces[enemy_player - 1]:
			var enemy := node as Model.DataPiece
			if enemy == null or enemy.is_queued_for_deletion():
				continue

			var enemy_cell := enemy.get_cur_pos()
			if (
				new_vision.has(enemy_cell)
				and not board.hasCellInVision(player_number, enemy_cell)
			):
				score += SCOUT_REVEAL_WEIGHT * enemy_protection_weight(enemy)

	if is_recapture:
		if captured is Model.DataEyePiece:
			score += EYE_RECAPTURE_BONUS * defensive_factor
		else:
			score += RECAPTURE_BONUS * defensive_factor

	var is_eye_or_triangle := (
		piece is Model.DataEyePiece
		or piece is Model.DataTriangleOddPiece
		or piece is Model.DataTriangleEvenPiece
	)

	if is_eye_or_triangle and captured == null:
		var possible_moves := moves_from_position(piece, destination)
		var threatens_enemy_eye := false

		for node in board.player_pieces[enemy_player - 1]:
			var enemy := node as Model.DataPiece
			if enemy == null or not (enemy is Model.DataEyePiece):
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

	if (
		difficulty < 4
		and total_captures < EARLY_GAME_CAPTURE_LIMIT
		and piece is Model.DataHopPiece
	):
		var tower_lead := mini(
			maxi(0, early_tower_move_count - early_hop_move_count),
			MAX_HOP_CATCH_UP_BONUS
		)
		score += EARLY_HOP_MOVE_BONUS + float(tower_lead) * HOP_CATCH_UP_BONUS

	if difficulty >= 4 and not piece is Model.DataCorePiece:
		if not moved_piece_ids.has(piece.get_instance_id()):
			if not threatened_after and own_support_after >= MIN_EARLY_CORE_SUPPORT:
				score += 40.0
	
	if piece is Model.DataCorePiece:
		if not core_under_attack and captured == null:
			if non_core_pieces_left > CORE_MOVE_ENDGAME_PIECES_LEFT:
				score -= 600.0

				if own_support_after < support_before:
					score -= (
						float(support_before - own_support_after)
						* 200.0
					)

	var exposure_score: float = score_exposure_change(
		piece, destination
	)

	# Concealment matters less when fighting or escaping danger.
	if captured != null or core_under_attack:
		exposure_score *= 0.25

	score += exposure_score

	return score


func find_core(player_id: int) -> Model.DataCorePiece:
	for node in board.player_pieces[player_id - 1]:
		if node is Model.DataCorePiece:
			return node as Model.DataCorePiece
	return null

func should_keep_scouting(enemy_player: int) -> bool:
	var alive_count := 0
	var visible_count := 0

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Model.DataPiece
		if enemy == null or enemy.is_queued_for_deletion():
			continue

		alive_count += 1
		if board.hasCellInVision(player_number, enemy.get_cur_pos()):
			visible_count += 1

	return alive_count > 0 and visible_count * 4 < alive_count


func enemy_protection_weight(enemy: Model.DataPiece) -> float:
	var protection := 0

	for node in board.player_pieces[enemy.owned_player - 1]:
		var ally := node as Model.DataPiece
		if ally == null or ally == enemy:
			continue

		if ally.cur_vision.has(enemy.get_cur_pos()):
			protection += 1

	return 1.0 + minf(float(protection) * 0.5, 2.0)

func score_exposure_change(
	piece: Model.DataPiece,
	destination: Vector2i
) -> float:
	var enemy_player: int = 3 - player_number
	var known_enemy_vision: Dictionary = {}
	var observer_count: int = 0

	# Only use enemy pieces the CPU can currently see.
	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Model.DataPiece
		if not board.hasCellInVision(
			player_number, enemy.get_cur_pos()
		):
			continue

		observer_count += 1
		for cell in enemy.cur_vision:
			known_enemy_vision[cell] = true

	# No known observers does not prove that the move is concealed.
	if observer_count == 0:
		return 0.0

	var exposed_before: bool = known_enemy_vision.has(
		piece.get_cur_pos()
	)
	var exposed_after: bool = known_enemy_vision.has(destination)

	var captures: int = (
		board.player_captures[0].size()
		+ board.player_captures[1].size()
	)
	var opening_weight: float = lerpf(
		1.0, 0.4, clampf(float(captures) / 20.0, 0.0, 1.0)
	)

	var exposure_cost: float = (
		10.0 + float(piece.piece_value) * 8.0
	)
	if piece is Model.DataCorePiece:
		exposure_cost = 160.0
	elif piece is Model.DataEyePiece:
		exposure_cost = 120.0

	exposure_cost *= opening_weight

	if exposed_after and not exposed_before:
		return -exposure_cost

	if exposed_before and not exposed_after:
		return exposure_cost * 0.25

	# Reward useful concealed exploration, rather than hiding alone.
	if not exposed_after and not piece is Model.DataCorePiece:
		var new_cells: int = 0
		for cell in piece.get_potential_vision(destination):
			if not board.hasCellInVision(player_number, cell):
				new_cells += 1

		return minf(
			float(new_cells) * 2.0
			/ maxf(1.0, float(piece.piece_value)),
			20.0
		)

	return 0.0

func score_scouting_action(
	piece: Model.DataPiece,
	old_position: Vector2i,
	destination: Vector2i,
	_enemy_player: int
) -> float:
	if piece is Model.DataCorePiece:
		return 0.0

	var vision: Array[Vector2i] = piece.get_potential_vision(
		destination
	)

	var newly_seen: int = 0

	for cell in vision:
		if not board.hasCellInVision(player_number, cell):
			newly_seen += 1

	var value: float = maxf(1.0, float(piece.piece_value))
	var cheap_scout: float = 1.0 / (1.0 + value * 0.75)

	var score: float = (
		float(newly_seen) * 2.5 * cheap_scout
	)

	if difficulty >= 4:
		score += spawn_knowledge.score_move(
			piece,
			old_position,
			destination,
			board
		)

	return score











func find_visible_core(player_id: int) -> Model.DataCorePiece:
	var core := find_core(player_id)
	if core == null:
		return null

	if board.hasCellInVision(player_number, core.get_cur_pos()):
		return core
	return null


func count_core_support(
	player_id: int,
	core_position: Vector2i,
	moving_piece: Model.DataPiece = null,
	destination: Vector2i = Vector2i.ZERO,
	removed_piece: Model.DataPiece = null
) -> int:
	var count := 0

	for node in board.player_pieces[player_id - 1]:
		var piece := node as Model.DataPiece
		if piece == null or piece is Model.DataCorePiece or piece == removed_piece:
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
	moving_piece: Model.DataPiece = null,
	_moving_destination: Vector2i = Vector2i.ZERO
) -> int:
	var count: int = int(cpu_cover_counts.get(eye_position, 0))

	if is_instance_valid(moving_piece):
		var own_coverage: Dictionary = cpu_cover_by_piece.get(
			moving_piece.get_instance_id(),
			{}
		)

		if own_coverage.has(eye_position):
			count -= 1

	return count

func get_capture_moves(piece: Model.DataPiece) -> Array[Vector2i]:
	if piece is Model.DataTowerRotatePiece:
		var tower := piece as Model.DataTowerRotatePiece
		return tower.generate_all_possible_moves_with_rotation(
			tower.get_cur_pos()
		)

	return piece.cur_moves

func has_non_core_capture(target: Model.DataPiece) -> bool:
	var enemy_cell := target.get_cur_pos()

	for node in board.player_pieces[player_number - 1]:
		var ally := node as Model.DataPiece
		if ally == null or ally is Model.DataCorePiece:
			continue

		if (
			board.hasCellInVision(player_number, enemy_cell)
			and get_capture_moves(ally).has(enemy_cell)
		):
			return true

	return false

func count_attacked_enemies(
	piece: Model.DataPiece,
	destination: Vector2i
) -> int:
	var potential_moves: Array[Vector2i] = get_moves_from_position(
		piece,
		destination
	)

	var enemy_player := 1 if player_number == 2 else 2
	var attacked := 0

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Model.DataPiece

		if enemy == null:
			continue

		if not board.hasCellInVision(
			player_number,
			enemy.get_cur_pos()
		):
			continue

		if potential_moves.has(enemy.get_cur_pos()):
			attacked += 1

	return attacked

func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var cube_a := Model.DataBoard.offset_to_cube(a)
	var cube_b := Model.DataBoard.offset_to_cube(b)

	return maxi(
		maxi(abs(cube_a.x - cube_b.x), abs(cube_a.y - cube_b.y)),
		abs(cube_a.z - cube_b.z)
	)


func rotate_towers_for_turn() -> void:
	var enemy_player := 1 if player_number == 2 else 2

	for node in board.player_pieces[player_number - 1]:
		if _cancelled():
			return
		var tower := node as Model.DataTowerRotatePiece
		if tower == null:
			continue

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
			if not _tower_rotation_preserves_support(tower, new_direction):
				continue

			var score := score_tower_rotation(
				tower, new_vision, enemy_player
			)
			score += _tower_rotation_tactical_bonus(
				tower, new_direction
			)
			if score > best_score:
				best_score = score
				best_key = key

		if best_key != "":
			if best_key == "pivot1":
				tower.cur_direction = posmod(tower.cur_direction - 1, 6)
			else:
				tower.cur_direction = posmod(tower.cur_direction + 1, 6)

			tower.cur_vision = tower.get_potential_vision(
				tower.get_cur_pos(),
				tower.cur_direction
			)
			board.refresh_vision()
			remember_enemies_in_vision(tower.cur_vision)

func remember_enemies_in_vision(visible_cells: Array[Vector2i]) -> void:
	var enemy_player := 1 if player_number == 2 else 2

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Model.DataPiece
		if enemy == null:
			continue

		var enemy_position := enemy.get_cur_pos()
		if visible_cells.has(enemy_position):
			var enemy_id := enemy.get_instance_id()
			enemy_last_seen[enemy_id] = enemy_position
			enemy_last_seen_turn[enemy_id] = cpu_turn_count



func _tower_rotation_preserves_support(
	tower: Model.DataTowerRotatePiece,
	new_direction: int
) -> bool:
	var old_direction: int = tower.cur_direction
	var core := find_core(player_number)

	var new_vision: Array[Vector2i] = tower.get_potential_vision(
		tower.get_cur_pos(), new_direction
	)

	# Allow this tower to stop supporting the core if at least
	# two other supporters remain.
	if core != null:
		var core_cell: Vector2i = core.get_cur_pos()
		var support_before: int = count_core_support(
			player_number, core_cell
		)
		var support_after: int = support_before

		if tower.cur_vision.has(core_cell):
			support_after -= 1
		if new_vision.has(core_cell):
			support_after += 1

		var required_support: int = mini(2, support_before)
		required_support = maxi(1, required_support)

		if support_after < required_support:
			return false

	# Record allies this tower currently guards.
	board.regenerate_all_piece_moves(1, true)
	board.regenerate_all_piece_moves(2, true)

	var guarded_allies: Array[Model.DataPiece] = []
	for node in board.player_pieces[player_number - 1]:
		var ally := node as Model.DataPiece
		if ally == tower:
			continue
		if board.get_guarders(ally).has(tower):
			guarded_allies.append(ally)

	# Check the candidate orientation using the same guard rules.
	tower.cur_direction = new_direction
	tower.cur_vision = new_vision
	board.refresh_vision()
	board.regenerate_all_piece_moves(1, true)
	board.regenerate_all_piece_moves(2, true)

	var preserves_guards: bool = true
	for ally in guarded_allies:
		if board.get_guarders(ally).is_empty():
			preserves_guards = false
			break

	# Restore the original orientation and calculated state.
	tower.cur_direction = old_direction
	board.refresh_vision()
	board.regenerate_all_piece_moves(1, true)
	board.regenerate_all_piece_moves(2, true)

	return preserves_guards

func _tower_rotation_tactical_bonus(
	tower: Model.DataTowerRotatePiece,
	new_direction: int
) -> float:
	if difficulty < 4:
		return 0.0

	# Use part of the existing turn budget, not extra thinking time.
	var now: int = Time.get_ticks_msec()
	if turn_deadline <= now:
		return 0.0

	var probe = TacticalSearch.new()
	probe.cancellation = cancellation
	probe.cpu_player = player_number
	probe.enemy_player = 3 - player_number
	probe.deadline = mini(turn_deadline, now + 25)

	# Normal visibility only: hidden enemies are not copied.
	probe._build_simulation(board)

	var copy := probe.clones.get(
		tower.get_instance_id()
	) as Model.DataTowerRotatePiece

	if copy == null:
		probe.simulation.dispose()
		return 0.0

	var threats_before: int = probe._core_threat_count(player_number)
	var tactics_before: float = probe._tactical_score()

	if probe.timed_out:
		probe.simulation.dispose()
		return 0.0

	copy.cur_direction = new_direction
	probe._refresh()

	var threats_after: int = probe._core_threat_count(player_number)
	var tactics_after: float = probe._tactical_score()

	var timed_out: bool = probe.timed_out
	probe.simulation.dispose()

	if timed_out:
		return 0.0

	# Do not rotate into additional known core threats.
	if threats_after > threats_before:
		return -100000.0

	return (
		float(threats_before - threats_after) * 1200.0
		+ (tactics_after - tactics_before) * 0.35
	)


func score_tower_rotation(
	tower: Model.DataTowerRotatePiece,
	new_vision: Array[Vector2i],
	_enemy_player: int
) -> float:
	var other_vision: Dictionary = {}

	for node in board.player_pieces[player_number - 1]:
		var ally := node as Model.DataPiece

		if ally == null or ally == tower:
			continue

		for cell in ally.cur_vision:
			other_vision[cell] = true

	var old_unique: int = 0
	var new_unique: int = 0

	for cell in tower.cur_vision:
		if not other_vision.has(cell):
			old_unique += 1

	for cell in new_vision:
		if not other_vision.has(cell):
			new_unique += 1

	var score: float = float(new_unique - old_unique)

	if difficulty >= 4:
		score += (
			spawn_knowledge.vision_bonus(new_vision)
			- spawn_knowledge.vision_bonus(tower.cur_vision)
		)

	return score


func has_visible_enemy_piece(enemy_player: int) -> bool:
	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Model.DataPiece
		if enemy != null and board.hasCellInVision(
			player_number,
			enemy.get_cur_pos()
		):
			return true

	return false

func has_visible_attacker(piece: Model.DataPiece) -> bool:
	var enemy_player := 1 if player_number == 2 else 2
	var target_cell := piece.get_cur_pos()

	for node in board.player_pieces[enemy_player - 1]:
		var enemy_piece := node as Model.DataPiece
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
		var piece := node as Model.DataPiece
		if piece != null and not (piece is Model.DataCorePiece):
			count += 1

	return count

func get_material_value(player_id: int) -> float:
	var total := 0.0

	for node in board.player_pieces[player_id - 1]:
		var piece := node as Model.DataPiece
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

	return 1.0 + minf(maxf(deficit, 0.0) / 20.0, 2.0)

func is_running_away(piece: Model.DataPiece, destination: Vector2i) -> bool:
	var current_position := piece.get_cur_pos()

	return (
		is_move_threatened(current_position)
		and not is_move_threatened(destination)
	)


func moves_from_position(piece: Model.DataPiece, position: Vector2i) -> Array[Vector2i]:
	var original_moves := piece.cur_moves.duplicate()

	if piece is Model.DataTowerRotatePiece:
		var tower := piece as Model.DataTowerRotatePiece
		var original_rotate_moves := tower.cur_possible_rotate_moves.duplicate()
		var moves := tower.generate_all_possible_moves_with_rotation(position)
		tower.cur_possible_rotate_moves = original_rotate_moves
		return moves

	var moves := piece.generate_possible_moves(position)
	piece.cur_moves = original_moves
	return moves

func rebuild_cpu_cover_cache() -> void:
	cpu_cover_counts.clear()
	cpu_cover_by_piece.clear()

	for node in board.player_pieces[player_number - 1]:
		if _cancelled():
			return

		var piece := node as Model.DataPiece
		if not is_instance_valid(piece) or piece is Model.DataCorePiece:
			continue

		var covered: Dictionary = {}

		if piece is Model.DataTowerRotatePiece:
			var tower := piece as Model.DataTowerRotatePiece

			for direction in range(6):
				for cell in tower.get_potential_vision(
					tower.get_cur_pos(),
					direction
				):
					covered[cell] = true
		else:
			for cell in piece.cur_vision:
				covered[cell] = true

		cpu_cover_by_piece[piece.get_instance_id()] = covered

		for cell in covered:
			cpu_cover_counts[cell] = (
				int(cpu_cover_counts.get(cell, 0)) + 1
			)

func _yield_cpu_frame() -> void:
	pass

func _core_emergency_actions(
	actions: Array[Dictionary],
	own_core: Model.DataCorePiece
) -> Array[Dictionary]:
	var opponent: int = 3 - player_number
	var winning_captures: Array[Dictionary] = []

	for action in actions:
		if _cancelled():
			return []
		var destination: Vector2i = action["destination"]
		if board.hasCellInVision(player_number, destination):
			var target := board.get_enemy_piece_at_cell(
				destination, opponent
			)
			if target is Model.DataCorePiece:
				winning_captures.append(action)

	if not winning_captures.is_empty():
		return winning_captures

	# Preserve the existing emergency simulation's information policy.
	var defense = TacticalSearch.new()
	defense.cancellation = cancellation
	defense.cpu_player = player_number
	defense.enemy_player = opponent
	defense._build_simulation(board, true)

	var safe_responses: Array[Dictionary] = []

	for action in actions:
		if _cancelled():
			break
		var original_piece := action["piece"] as Model.DataPiece
		var copied_piece := defense.clones.get(
			original_piece.get_instance_id()
		) as Model.DataPiece

		if copied_piece == null:
			continue

		var simulated: Dictionary = {
			"piece": copied_piece,
			"destination": action["destination"],
		}

		if action.has("direction"):
			simulated["direction"] = action["direction"]

		var undo: Dictionary = defense._push(simulated)

		var copied_core: Model.DataCorePiece = defense._core(
			player_number
		)

		var safe: bool = false

		if copied_core != null and copied_core.power_count > 0:
			defense.simulation.current_player = player_number
			defense.simulation.regenerate_all_piece_moves(
				player_number, true
			)
			defense.simulation.current_player = opponent

			safe = not defense.simulation.is_piece_under_attack(
				copied_core
			)

		defense._pop(simulated, undo)

		if safe:
			safe_responses.append(action)

	defense.simulation.dispose()
	return safe_responses


func build_memory_risk() -> Dictionary:
	var risk: Dictionary = {}
	var enemy_player: int = 3 - player_number

	for node in board.player_pieces[enemy_player - 1]:
		var enemy := node as Model.DataPiece
		var id: int = enemy.get_instance_id()

		if not enemy_last_seen.has(id):
			continue
		if board.hasCellInVision(player_number, enemy.get_cur_pos()):
			continue

		var age: int = cpu_turn_count - int(
			enemy_last_seen_turn.get(id, cpu_turn_count)
		)
		if age > 4:
			continue

		var origin: Vector2i = enemy_last_seen[id]

		# Seeing this cell empty invalidates the exact old position.
		if board.hasCellInVision(player_number, origin):
			continue

		var strength: float = 0.65 * pow(0.75, float(age))
		var cells: Array[Vector2i] = []
		var directions: Array[int] = [0, 1, 2, 3, 4, 5]

		if enemy is Model.DataTriangleEvenPiece:
			directions = [1, 3, 5]
		elif enemy is Model.DataTriangleOddPiece:
			directions = [0, 2, 4]

		if enemy is Model.DataTowerRotatePiece:
			# Tower rotation makes the remembered direction uncertain.
			cells.assign(
				board.get_hexagon_tiles(origin, enemy.move_range)
			)
			strength *= 0.5
		else:
			for direction in directions:
				var line: Array[Vector2i] = board.get_line_from_center(
					origin, direction, enemy.move_range
				)

				if enemy is Model.DataHopPiece:
					if not line.is_empty():
						cells.append(line.back())
				else:
					cells.append_array(line)

		cells.append(origin)

		for cell in cells:
			if board.cell_in_board(cell):
				risk[cell] = maxf(
					float(risk.get(cell, 0.0)),
					strength
				)

	# Capture evidence supplements memory without adding duplicate penalties.
	for origin in capture_danger:
		var age: int = cpu_turn_count - int(capture_danger[origin])
		var strength: float = 0.45 * pow(0.75, float(age))

		for cell in board.get_hexagon_tiles(origin, 2):
			if not board.cell_in_board(cell):
				continue

			risk[cell] = maxf(
				float(risk.get(cell, 0.0)),
				strength
			)

	return risk

func return_move_penalty(
	piece: Model.DataPiece,
	destination: Vector2i,
	core_under_attack: bool
) -> float:
	var id: int = piece.get_instance_id()

	if not reversal_origins.has(id):
		return 0.0
	if destination != reversal_origins[id]:
		return 0.0

	# Do not discourage emergency defenses or escaping an attack.
	if core_under_attack or is_running_away(piece, destination):
		return 0.0

	var opponent: int = 3 - player_number
	if board.hasCellInVision(player_number, destination):
		if board.get_enemy_piece_at_cell(destination, opponent) != null:
			return 0.0

	return 30.0
