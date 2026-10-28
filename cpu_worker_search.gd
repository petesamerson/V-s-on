extends RefCounted
const Model = preload("res://cpu_worker_model.gd")

const WIN_SCORE: float = 1000000.0

var simulation: Model.DataBoard
var cpu_player: int
var enemy_player: int

var deadline: int
var timed_out: bool = false
var completed_depth: int = 0
var branch_limit: int = 8

var clones: Dictionary = {}
var known_cores: Dictionary = {}
var all_enemies_known: bool = false

var memory_risk: Dictionary = {}
var early_eye_protection: float = 0.0

var initial_known_tiles: Dictionary = {}
var initial_positions: Dictionary = {}
var recent_capturer: Model.DataPiece

var turn_deadline: int = 0
var slice_started_us: int = 0

var initial_exposure_cost: float = 0.0
var aggression: float = 1.0

const SEARCH_SLICE_US: int = 4000
const EXCHANGE_EXTENSION_DEPTH: int = 1

const Cancellation = preload("res://cpu_cancellation.gd")
var cancellation: Cancellation

func choose(
	live_board: Model.DataBoard,
	player_id: int,
	difficulty: int,
	candidates: Array[Dictionary],
	recent_capturer_id: int = -1
) -> Dictionary:
	cpu_player = player_id
	slice_started_us = Time.get_ticks_usec()
	enemy_player = 2 if player_id == 1 else 1

	completed_depth = 0
	timed_out = false
	clones.clear()
	known_cores.clear()

	var budget_ms: int = 120
	var max_depth: int = 2

	if difficulty == 5:
		budget_ms = 250
		max_depth = 4
	elif difficulty >= 6:
		budget_ms = 500
		max_depth = 6

	deadline = turn_deadline if turn_deadline > 0 else Time.get_ticks_msec() + budget_ms

	var prep_started_ms: int = Time.get_ticks_msec()

	_build_simulation(live_board)
	recent_capturer = clones.get(recent_capturer_id) as Model.DataPiece

	var roots: Array[Dictionary] = []
	var root_moves: Dictionary = {}

	for candidate in candidates:

		var live_piece := candidate["piece"] as Model.DataPiece

		if not is_instance_valid(live_piece):
			continue

		# Tower root actions are generated separately with directions.
		if live_piece is Model.DataTowerRotatePiece:
			continue

		var copy := clones.get(
			live_piece.get_instance_id()
		) as Model.DataPiece

		if copy == null:
			continue

		simulation.current_player = cpu_player

		var copy_id: int = copy.get_instance_id()
		if not root_moves.has(copy_id):
			root_moves[copy_id] = _moves(copy)
		var destinations: Array[Vector2i] = root_moves[copy_id]

		if not destinations.has(candidate["destination"]):
			continue

		var action: Dictionary = {
			"piece": copy,
			"destination": candidate["destination"],
			"original": candidate,
		}

		action["recapture_bonus"] = _recapture_preference(action)
		action["priority"] = (
			_move_priority(action)
			+ _legacy_preference(action)
		)
		roots.append(action)

	for node in live_board.player_pieces[cpu_player - 1]:
		var source := node as Model.DataPiece
		if not source is Model.DataTowerRotatePiece:
			continue

		var copy := clones.get(
			source.get_instance_id()
		) as Model.DataTowerRotatePiece

		if copy == null:
			continue

		simulation.current_player = cpu_player

		for option in copy.generate_turn_actions():
			var destination: Vector2i = option["destination"]
			var direction: int = int(option["direction"])
			var priority: float = _directional_priority(option)

			var original: Dictionary = {
				"piece": source,
				"destination": destination,
				"direction": direction,
				"score": priority,
				"unprotected_danger": true,
				"scout_score": 0.0,
			}

			option["original"] = original
			option["recapture_bonus"] = 0.0
			option["priority"] = priority
			roots.append(option)

	if roots.is_empty():
		simulation.dispose()
		return {}

	roots.sort_custom(
		func(a, b):
			return float(a["priority"]) > float(b["priority"])
	)

	# Cheap shortlist before applying and undoing every candidate.
	roots = _trim_search_actions(roots, cpu_player, 48)

	var safety_started_ms: int = Time.get_ticks_msec()
	var shortlisted_roots: int = roots.size()

	roots = _prefer_core_safe_actions(roots, cpu_player, false)
	roots = _trim_search_actions(roots, cpu_player, 18)

	var best_original: Dictionary = roots[0]["original"]
	var fallback_score: float = -INF
	var best_piece_safety: int = -1

	for action in roots:

		var original: Dictionary = action["original"]

		var piece_safety: int = (
			0 if bool(original.get("unprotected_danger", true))
			else 1
		)

		var undo: Dictionary = _push(action)

		if action["piece"] is Model.DataTowerRotatePiece:
			var moved_tower := action["piece"] as Model.DataTowerRotatePiece
			var unsafe: bool = simulation.is_piece_under_attack(moved_tower)
			original["unprotected_danger"] = unsafe
			piece_safety = 0 if unsafe else 1

		if _terminal_score() == WIN_SCORE:
			piece_safety = 2

		_pop(action, undo)

		var original_score: float = (
			float(original.get("score", 0.0))
			+ float(action.get("recapture_bonus", 0.0))
		)
		if (
			piece_safety > best_piece_safety
			or (
				piece_safety == best_piece_safety
				and original_score > fallback_score
			)
		):
			best_piece_safety = piece_safety
			fallback_score = original_score
			best_original = original

	timed_out = false
	deadline = turn_deadline if turn_deadline > 0 else Time.get_ticks_msec() + budget_ms


	var search_started_ms: int = Time.get_ticks_msec()

	for depth in range(1, max_depth + 1):


		if _expired():
			break

		var iteration_best: Dictionary = {}
		var iteration_score: float = -INF
		var alpha: float = -INF

		for action in roots:

			if _expired():
				break

			var undo: Dictionary = _push(action)

			var value: float

			if depth == 1:
				# Establish a completed baseline without exchange extensions.
				value = _evaluate()
			else:
				value = _minimax(
					depth - 1,
					enemy_player,
					alpha,
					INF
				)

			_pop(action, undo)
			if absf(value) < WIN_SCORE * 0.5:
				value += _legacy_preference(action)

			if timed_out:
				break

			if value > iteration_score:
				iteration_score = value
				iteration_best = action["original"]

			alpha = maxf(alpha, iteration_score)

		if timed_out:
			break

		if not iteration_best.is_empty():
			best_original = iteration_best
			completed_depth = depth

			# Examine the previous completed depth's best move first.
			var best_piece: Model.DataPiece = iteration_best["piece"]
			var best_destination: Vector2i = iteration_best["destination"]

			for i in range(roots.size()):
				var original: Dictionary = roots[i]["original"]
				if (
					original["piece"] == best_piece
					and original["destination"] == best_destination
					and int(original.get("direction", -1))
						== int(iteration_best.get("direction", -1))
				):
					var preferred: Dictionary = roots[i]
					roots.remove_at(i)
					roots.push_front(preferred)
					break

	print(
		"CPU search completed depth ",
		completed_depth,
		" at difficulty ",
		difficulty
	)
	print(
		"CPU timing: candidates=",
		safety_started_ms - prep_started_ms,
		" ms, safety/fallback=",
		search_started_ms - safety_started_ms,
		" ms, search=",
		Time.get_ticks_msec() - search_started_ms,
		" ms, roots=",
		shortlisted_roots,
		" -> ",
		roots.size()
	)

	simulation.dispose()
	return best_original


func _build_simulation(
	live_board: Model.DataBoard,
	include_hidden_for_defense: bool = false
) -> void:
	initial_known_tiles.clear()
	initial_positions.clear()
	simulation = Model.DataBoard.new()
	simulation.board_center = live_board.board_center
	simulation.board_size = live_board.board_size
	simulation.board_tiles = live_board.board_tiles.duplicate()
	simulation.current_player = cpu_player
	simulation.player_pieces = [[], []]

	simulation.pieces_container = Model.PieceBag.new()

	var enemy_count: int = 0
	var visible_enemy_count: int = 0

	for side_index in range(live_board.player_pieces.size()):
		for node in live_board.player_pieces[side_index]:
			var source := node as Model.DataPiece

			if source == null or source.is_queued_for_deletion():
				continue

			if source.owned_player != cpu_player:
				enemy_count += 1

				if not include_hidden_for_defense and not live_board.hasCellInVision(
					cpu_player,
					source.get_cur_pos()
				):
					continue

				visible_enemy_count += 1

			var copy := source.get_script().new() as Model.DataPiece

			copy.board = simulation
			copy.owned_player = source.owned_player
			copy.position = simulation.map_to_local(
				source.get_cur_pos()
			)
			copy.vision_range = source.vision_range
			copy.move_range = source.move_range
			copy.piece_value = source.piece_value
			copy.powered = source.powered

			if source is Model.DataTowerRotatePiece:
				(copy as Model.DataTowerRotatePiece).cur_direction = (
					(source as Model.DataTowerRotatePiece).cur_direction
				)

			simulation.pieces_container.add_child(copy)
			simulation.player_pieces[
				copy.owned_player - 1
			].append(copy)

			clones[source.get_instance_id()] = copy
			initial_positions[copy.get_instance_id()] = (
				copy.get_cur_pos()
			)

			if copy is Model.DataCorePiece:
				known_cores[copy.owned_player] = true

	all_enemies_known = enemy_count == visible_enemy_count
	_refresh()

	for node in simulation.player_pieces[cpu_player - 1]:
		var piece := node as Model.DataPiece

		for cell in piece.cur_vision:
			initial_known_tiles[cell] = true
	initial_exposure_cost = _known_exposure_cost()


func _refresh() -> void:
	for group in simulation.player_pieces:
		for node in group:
			var piece := node as Model.DataPiece

			if piece is Model.DataCorePiece:
				piece.cur_vision = []
			else:
				piece.cur_vision = piece.get_potential_vision(
					piece.get_cur_pos()
				)

	_refresh_core_power()


func _refresh_core_power() -> void:
	for side in [1, 2]:
		var core: Model.DataCorePiece = _core(side)

		if core != null:
			core.power_count = _support_count(side, core)


func _core(side: int) -> Model.DataCorePiece:
	for node in simulation.player_pieces[side - 1]:
		if node is Model.DataCorePiece:
			return node as Model.DataCorePiece

	return null


func _support_count(side: int, core: Model.DataCorePiece) -> int:
	var count: int = 0

	for node in simulation.player_pieces[side - 1]:
		var piece := node as Model.DataPiece

		if piece is Model.DataCorePiece:
			continue

		if piece.cur_vision.has(core.get_cur_pos()):
			count += 1

	return count


func _moves(piece: Model.DataPiece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if piece is Model.DataCorePiece:
		result.assign(
			(piece as Model.DataCorePiece).generate_possible_moves(
				piece.get_cur_pos()
			)
		)
	else:
		result.assign(
			piece.generate_possible_moves(piece.get_cur_pos())
		)

	return result

func _actions(
	side: int,
	apply_limit: bool = true,
	captures_only: bool = false
) -> Array[Dictionary]:
	simulation.current_player = side

	simulation.regenerate_all_piece_moves(1, true)
	simulation.regenerate_all_piece_moves(2, true)

	var actions: Array[Dictionary] = []

	for node in simulation.player_pieces[side - 1]:

		if _expired():
			break

		var piece := node as Model.DataPiece

		for action in _piece_actions(piece):
			if _expired():
				break

			if captures_only and not _is_capture(action, side):
				continue

			action["priority"] = _directional_priority(action)
			actions.append(action)

	actions.sort_custom(
		func(a, b):
			return float(a["priority"]) > float(b["priority"])
	)

	if apply_limit:
		actions = _trim_search_actions(
			actions, side, branch_limit * 3
		)

	actions = _prefer_core_safe_actions(actions, side)

	if apply_limit:
		actions = _trim_search_actions(actions, side, branch_limit)

	return actions

func _move_priority(action: Dictionary) -> float:
	var piece := action["piece"] as Model.DataPiece
	var destination: Vector2i = action["destination"]
	var opponent: int = 2 if piece.owned_player == 1 else 1

	var target: Model.DataPiece = simulation.get_enemy_piece_at_cell(
		destination,
		opponent
	)

	var priority: float = 0.0

	if target is Model.DataCorePiece:
		return WIN_SCORE

	if target != null:
		priority += (
			1000.0
			+ float(target.piece_value) * 100.0
			- float(piece.piece_value) * 10.0
		)

	var vision: Array[Vector2i] = piece.get_potential_vision(
		destination
	)

	var value: float = maxf(
		1.0,
		float(piece.piece_value)
	)

	var scout_weight: float = (
		5.0 / (1.0 + value * 0.75)
	)

	for cell in vision:
		if not simulation.hasCellInVision(
			piece.owned_player,
			cell
		):
			priority += scout_weight
	return priority

func _is_capture(action: Dictionary, side: int) -> bool:
	var opponent: int = 3 - side
	var destination: Vector2i = action["destination"]

	return simulation.get_enemy_piece_at_cell(
		destination, opponent
	) != null


func _trim_search_actions(
	actions: Array[Dictionary],
	side: int,
	limit: int
) -> Array[Dictionary]:
	# Actions have already passed the existing core-safety filter.
	# Keep every available response when the core is threatened.
	if _core_threat_count(side) > 0:
		return actions

	var kept: Array[Dictionary] = []
	var quiet: Array[Dictionary] = []

	for action in actions:
		if _is_capture(action, side):
			kept.append(action)
		else:
			quiet.append(action)

	# Captures cannot be pushed out by highly scored scou/ting moves.
	for action in quiet:
		if kept.size() >= limit:
			break
		kept.append(action)

	kept.sort_custom(
		func(a, b):
			return float(a["priority"]) > float(b["priority"])
	)

	return kept

func _legacy_preference(action: Dictionary) -> float:
	var original: Dictionary = action.get("original", {})

	var original_score: float = float(
		original.get("score", 0.0)
	)

	var recapture_bonus: float = float(
		action.get("recapture_bonus", 0.0)
	)

	var activity_preference: float = 0.0
	var piece := action["piece"] as Model.DataPiece

	if piece is Model.DataCorePiece:
		if not simulation.is_piece_under_attack(piece):
			var target := simulation.get_enemy_piece_at_cell(
				action["destination"],
				3 - piece.owned_player
			)
			if target == null:
				if simulation.player_pieces[piece.owned_player - 1].size() > 5:
					activity_preference -= 60.0

	var reversal_penalty: float = float(
		original.get("reversal_penalty", 0.0)
	)

	# Remove the penalty from the discounted score, then apply it once
	# at full strength.
	return (
		clampf(original_score + reversal_penalty, -5000.0, 5000.0) * 0.05
		+ recapture_bonus
		+ activity_preference
		- reversal_penalty
)

func _push(action: Dictionary) -> Dictionary:
	var piece := action["piece"] as Model.DataPiece
	var destination: Vector2i = action["destination"]
	var opponent: int = 2 if piece.owned_player == 1 else 1

	var captured: Model.DataPiece = simulation.get_enemy_piece_at_cell(
		destination,
		opponent
	)

	var undo: Dictionary = {
		"position": piece.position,
		"vision": piece.cur_vision,
		"player": simulation.current_player,
		"captured": captured,
		"captured_index": -1,
	}

	if piece is Model.DataTowerRotatePiece:
		var tower := piece as Model.DataTowerRotatePiece
		undo["direction"] = tower.cur_direction
		tower.cur_direction = int(
			action.get("direction", tower.cur_direction)
		)

	if captured != null:
		var group: Array = simulation.player_pieces[opponent - 1]
		undo["captured_index"] = group.find(captured)

		group.erase(captured)
		simulation.pieces_container.remove_child(captured)

	piece.position = simulation.map_to_local(destination)

	# Other pieces' vision does not depend on this piece's position.
	if not piece is Model.DataCorePiece:
		piece.cur_vision = piece.get_potential_vision(piece.get_cur_pos())

	_refresh_core_power()
	return undo


func _pop(action: Dictionary, undo: Dictionary) -> void:
	var piece := action["piece"] as Model.DataPiece
	piece.position = undo["position"]
	piece.cur_vision = undo["vision"]

	if piece is Model.DataTowerRotatePiece and undo.has("direction"):
		(piece as Model.DataTowerRotatePiece).cur_direction = int(
			undo["direction"]
		)

	var captured := undo["captured"] as Model.DataPiece

	if captured != null:
		simulation.pieces_container.add_child(captured)

		var group: Array = simulation.player_pieces[
			captured.owned_player - 1
		]

		group.insert(int(undo["captured_index"]), captured)

	simulation.current_player = int(undo["player"])
	_refresh_core_power()


func _terminal_score() -> float:
	var own_core: Model.DataCorePiece = _core(cpu_player)
	var opponent_core: Model.DataCorePiece = _core(enemy_player)

	if own_core == null or own_core.power_count == 0:
		return -WIN_SCORE

	if known_cores.has(enemy_player) and opponent_core == null:
		return WIN_SCORE

	if (
		all_enemies_known
		and opponent_core != null
		and opponent_core.power_count == 0
	):
		return WIN_SCORE

	return 0.0


func _evaluate() -> float:
	var terminal: float = _terminal_score()

	if terminal != 0.0:
		return terminal

	var score: float = 0.0

	for side in [cpu_player, enemy_player]:
		var sign_value: float = 1.0 if side == cpu_player else -1.0
		var visible_cells: Dictionary = {}

		for node in simulation.player_pieces[side - 1]:

			var piece := node as Model.DataPiece


			if not piece is Model.DataCorePiece:
				var material_value: float = float(piece.piece_value) * 100.0
				if piece is Model.DataEyePiece:
					material_value += 300.0 + 600.0 * early_eye_protection

				score += sign_value * material_value

			for cell in piece.cur_vision:
				visible_cells[cell] = true

		score += sign_value * float(visible_cells.size()) * 0.5

		var core: Model.DataCorePiece = _core(side)

		if core != null:
			score += (
				sign_value
				* float(mini(core.power_count, 4))
				* 20.0
			)
	score -= (
		float(mini(_core_threat_count(cpu_player), 3))
		* 30000.0
	)

	score += (
		float(mini(_core_threat_count(enemy_player), 3))
		* 15000.0
	)

	var own_core: Model.DataCorePiece = _core(cpu_player)

	if own_core != null and own_core.power_count == 1:
		score -= 8000.0


	score += _scouting_score()
	score += _tactical_score()
	var exposure_change: float = (
		_known_exposure_cost() - initial_exposure_cost
	)
	score -= exposure_change
	score -= _memory_danger_cost()
	score -= _early_eye_danger_cost()

	return score


func _minimax(
	depth: int,
	side: int,
	alpha: float,
	beta: float
) -> float:


	if _expired():
		return _evaluate()

	var terminal: float = _terminal_score()

	if terminal != 0.0:
		return terminal

	if depth <= 0:
		return _search_exchanges(
			side,
			alpha,
			beta,
			EXCHANGE_EXTENSION_DEPTH
		)
	var actions: Array[Dictionary] = _actions(side)

	if actions.is_empty() or timed_out:
		return _evaluate()

	var maximizing: bool = side == cpu_player
	var best: float = -INF if maximizing else INF
	var next_side: int = 2 if side == 1 else 1

	for action in actions:
		if _expired():
			break

		var undo: Dictionary = _push(action)

		var value: float = _minimax(
			depth - 1,
			next_side,
			alpha,
			beta
		)

		_pop(action, undo)

		if timed_out:
			break

		if maximizing:
			best = maxf(best, value)
			alpha = maxf(alpha, best)
		else:
			best = minf(best, value)
			beta = minf(beta, best)

		if beta <= alpha:
			break

	if timed_out:
		return _evaluate()

	return best

func _search_exchanges(
	side: int,
	alpha: float,
	beta: float,
	remaining: int
) -> float:
	var terminal: float = _terminal_score()
	if terminal != 0.0:
		return terminal

	if _expired() or remaining <= 0:
		return _evaluate()

	var maximizing: bool = side == cpu_player
	var core_threatened: bool = _core_threat_count(side) > 0

	var core: Model.DataCorePiece = _core(side)
	if core != null and core.power_count == 0:
		core_threatened = true

	var standing_score: float = _evaluate()

	# In a quiet position, the static evaluation is our baseline.
	# Under a core threat, require an actual response instead.
	var best: float = standing_score
	if core_threatened:
		best = -INF if maximizing else INF
	else:
		if maximizing:
			if best >= beta:
				return best
			alpha = maxf(alpha, best)
		else:
			if best <= alpha:
				return best
			beta = minf(beta, best)

	if _expired():
		return standing_score

	# Request all actions so quiet moves cannot exclude captures.
	var actions: Array[Dictionary] = _actions(
		side,
		false,
		not core_threatened
	)

	# Limit optional capture continuations, not emergency defenses.
	if not core_threatened and actions.size() > 4:
		actions.resize(4)

	if timed_out:
		return standing_score

	var searched: bool = false

	for action in actions:
		if _expired():
			break

		# Normally extend captures only. If the core is threatened,
		# also examine quiet defensive responses.
		if not core_threatened and not _is_capture(action, side):
			continue

		var undo: Dictionary = _push(action)
		var value: float = _search_exchanges(
			3 - side,
			alpha,
			beta,
			remaining - 1
		)
		_pop(action, undo)

		if timed_out:
			break

		searched = true

		if maximizing:
			best = maxf(best, value)
			alpha = maxf(alpha, best)
		else:
			best = minf(best, value)
			beta = minf(beta, best)

		if beta <= alpha:
			break

	if timed_out or not searched:
		return standing_score

	return best

func _expired() -> bool:
	if cancellation != null and cancellation.is_cancelled():
		timed_out = true
	elif Time.get_ticks_msec() >= deadline:
		timed_out = true

	return timed_out

func _can_reach_core(attacker: Model.DataPiece, target: Vector2i) -> bool:
	var origin := attacker.get_cur_pos()

	if origin == target:
		return false

	if attacker is Model.DataTowerRotatePiece:
		for direction in range(6):
			var first_axis: Array[Vector2i] = (
				simulation.get_line_from_center(
					origin, direction, attacker.move_range
				)
			)

			var second_axis: Array[Vector2i] = (
				simulation.get_line_from_center(
					origin,
					(direction + 1) % 6,
					attacker.move_range
				)
			)

			for i in range(
				mini(first_axis.size(), second_axis.size())
			):
				if i % 2 != 0:
					continue

				var cross_line: Array[Vector2i] = (
					simulation.cached_hex_line(
						first_axis[i],
						second_axis[i]
					)
				)

				if cross_line.is_empty():
					continue

				var midpoint: Vector2i = cross_line[
					cross_line.size() / 2
				]

				if midpoint == target:
					return true

		return false

	var directions: Array[int] = [0, 1, 2, 3, 4, 5]

	if attacker is Model.DataTriangleEvenPiece:
		directions = [1, 3, 5]
	elif attacker is Model.DataTriangleOddPiece:
		directions = [0, 2, 4]

	for direction in directions:
		var cells: Array[Vector2i] = (
			simulation.get_line_from_center(
				origin,
				direction,
				attacker.move_range
			)
		)

		if attacker is Model.DataHopPiece:
			if not cells.is_empty() and cells.back() == target:
				return true
		elif cells.has(target):
			return true

	return false

func _core_threat_count(side: int) -> int:
	var core: Model.DataCorePiece = _core(side)

	if core == null:
		return 0

	var critical_cells: Array[Vector2i] = [
		core.get_cur_pos()
	]

	if core.power_count == 1:
		for node in simulation.player_pieces[side - 1]:
			var supporter := node as Model.DataPiece

			if supporter is Model.DataCorePiece:
				continue

			if supporter.cur_vision.has(core.get_cur_pos()):
				critical_cells.append(supporter.get_cur_pos())
				break

	var opponent: int = 2 if side == 1 else 1
	var count: int = 0

	for node in simulation.player_pieces[opponent - 1]:
		var attacker := node as Model.DataPiece

		for target in critical_cells:
			if _can_reach_core(attacker, target):
				count += 1
				break

	return count

func _prefer_core_safe_actions(
	actions: Array[Dictionary],
	side: int,
	stop_on_timeout: bool = true
) -> Array[Dictionary]:
	var preferred: Array[Dictionary] = []
	var best_safety: int = -2

	for action in actions:

		if stop_on_timeout and _expired():
			break
		var undo: Dictionary = _push(action)
		var core: Model.DataCorePiece = _core(side)
		var terminal: float = _terminal_score()
		var perspective: float = (
			1.0 if side == cpu_player else -1.0
		)

		var safety: int = 0

		if terminal * perspective > 0.0:
			safety = 2
		elif core == null or core.power_count == 0:
			safety = -1
		elif _core_threat_count(side) == 0:
			safety = 1

		_pop(action, undo)

		if safety > best_safety:
			best_safety = safety
			preferred.clear()

		if safety == best_safety:
			preferred.append(action)

	return preferred

func _can_recapture(
	attacker: Model.DataPiece,
	target: Model.DataPiece
) -> bool:
	var defending_side: int = target.owned_player
	var destination := target.get_cur_pos()

	var action: Dictionary = {
		"piece": attacker,
		"destination": destination,
	}

	var undo: Dictionary = _push(action)

	simulation.current_player = defending_side

	var can_recapture: bool = false
	var defending_core: Model.DataCorePiece = _core(defending_side)

	var core_captured: bool = (
		known_cores.has(defending_side)
		and defending_core == null
	)

	var power_lost: bool = (
		defending_core != null
		and defending_core.power_count == 0
		and (
			defending_side == cpu_player
			or all_enemies_known
		)
	)

	if not core_captured and not power_lost:
		for node in simulation.player_pieces[defending_side - 1]:


			var defender := node as Model.DataPiece
			var moves: Array[Vector2i] = _moves(defender)

			if moves.has(destination):
				can_recapture = true
				break

	_pop(action, undo)

	return can_recapture


func _tactical_score() -> float:
	var saved_player: int = simulation.current_player
	var total: float = 0.0

	for side in [cpu_player, enemy_player]:
		simulation.current_player = side

		var opponent: int = 2 if side == 1 else 1
		var sign_value: float = (
			1.0 if side == cpu_player else -1.0
		)

		var best_gain_by_target: Dictionary = {}
		var strongest_fork: float = 0.0

		for node in simulation.player_pieces[side - 1]:

			if _expired():
				simulation.current_player = saved_player
				return 0.0

			var attacker := node as Model.DataPiece
			var moves: Array[Vector2i] = _moves(attacker)
			var profitable_targets: Array[float] = []

			var targets: Array = (
				simulation.player_pieces[opponent - 1].duplicate()
			)

			for target_node in targets:

				if _expired():
					simulation.current_player = saved_player
					return 0.0

				var target := target_node as Model.DataPiece

				if target is Model.DataCorePiece:
					continue

				if not moves.has(target.get_cur_pos()):
					continue
				var gain: float = _exchange_value(target)
				var attacker_cost: float = _exchange_value(attacker)

				if _can_recapture(attacker, target):
					gain -= attacker_cost


				gain = maxf(gain, 0.0)

				var target_id: int = target.get_instance_id()
				var previous_gain: float = float(
					best_gain_by_target.get(target_id, 0.0)
				)

				best_gain_by_target[target_id] = maxf(
					previous_gain,
					gain
				)

				if gain > 0.0:
					profitable_targets.append(gain)

			if profitable_targets.size() >= 2:
				profitable_targets.sort()
				profitable_targets.reverse()

				strongest_fork = maxf(
					strongest_fork,
					profitable_targets[1]
				)

		var side_score: float = 0.0

		for target_id in best_gain_by_target:
			side_score += float(
				best_gain_by_target[target_id]
			)

		var fork_multiplier: float = 0.6
		if side == cpu_player:
			fork_multiplier *= aggression

		side_score += minf(
			strongest_fork * fork_multiplier,
			600.0
		)


		var threat_weight: float = 1.0
		if side == cpu_player:
			threat_weight = lerpf(
				0.45, 0.75, aggression - 1.0
			)

		total += (
			sign_value
			* minf(side_score, 4000.0)
			* threat_weight
		)
	simulation.current_player = saved_player
	return total

func _exchange_value(piece: Model.DataPiece) -> float:
	var value: float = float(piece.piece_value) * 100.0

	if piece is Model.DataCorePiece:
		return WIN_SCORE

	if piece is Model.DataEyePiece:
		value += 300.0 + 600.0 * early_eye_protection

	var core: Model.DataCorePiece = _core(piece.owned_player)

	if (
		core != null
		and piece.cur_vision.has(core.get_cur_pos())
	):
		value *= 1.35

		if core.power_count <= 2:
			value += 150.0

	return value

func _early_eye_danger_cost() -> float:
	if early_eye_protection <= 0.0:
		return 0.0

	var cost: float = 0.0

	for node in simulation.player_pieces[cpu_player - 1]:
		var piece := node as Model.DataPiece
		if not piece is Model.DataEyePiece:
			continue

		if simulation.is_piece_under_attack(piece):
			cost += 450.0 * early_eye_protection

	return cost

func _scouting_score() -> float:
	var cheapest_revealer: Dictionary = {}
	var risk_penalty: float = 0.0
	var development_reward: float = 0.0

	for node in simulation.player_pieces[cpu_player - 1]:
		var piece := node as Model.DataPiece
		if piece is Model.DataCorePiece:
			continue

		var value: float = maxf(1.0, float(piece.piece_value))
		var initial_cell: Vector2i = initial_positions.get(
			piece.get_instance_id(), piece.get_cur_pos()
		)
		var moved: bool = piece.get_cur_pos() != initial_cell
		var unknown_cells: int = 0

		# Nearby friendly vision provides support, not guaranteed safety.
		var supported: bool = false
		for ally_node in simulation.player_pieces[cpu_player - 1]:
			var ally := ally_node as Model.DataPiece
			if ally == piece or ally is Model.DataCorePiece:
				continue
			if ally.cur_vision.has(piece.get_cur_pos()):
				supported = true
				break

		var threatened: bool = simulation.is_piece_under_attack(piece)
		var reward_factor: float = 1.0
		if not supported:
			reward_factor = 0.45
		if threatened:
			reward_factor *= 0.2

		for cell in piece.cur_vision:
			if initial_known_tiles.has(cell):
				continue

			unknown_cells += 1
			var reward: float = (
				8.0 / (1.0 + value * 0.75)
			) * reward_factor

			# Count shared discoveries once, using the best scout.
			cheapest_revealer[cell] = maxf(
				float(cheapest_revealer.get(cell, 0.0)),
				reward
			)

		if moved and unknown_cells > 0:
			var uncertainty: float = minf(
				float(unknown_cells) / 12.0, 1.0
			)

			risk_penalty += (
				uncertainty * value * value
				* (1.0 if supported else 3.0)
			)

			if supported and not threatened:
				development_reward += (
					20.0 / (1.0 + value * 0.75)
				)

	var exploration_reward: float = 0.0
	for reward in cheapest_revealer.values():
		exploration_reward += float(reward)

	return (
		minf(exploration_reward, 160.0)
		+ minf(development_reward, 30.0)
		- risk_penalty
	)

func _recapture_preference(action: Dictionary) -> float:
	if not is_instance_valid(recent_capturer):
		return 0.0

	var piece := action["piece"] as Model.DataPiece
	var destination: Vector2i = action["destination"]

	var target: Model.DataPiece = simulation.get_enemy_piece_at_cell(
		destination,
		enemy_player
	)

	if target != recent_capturer:
		return 0.0

	if piece is Model.DataCorePiece or target is Model.DataCorePiece:
		return 0.0

	var target_value: float = float(target.piece_value)
	var attacker_value: float = float(piece.piece_value)

	if _can_recapture(piece, target):
		var trade_gain: float = target_value - attacker_value

		if trade_gain < 0.0:
			return 0.0

		return 150.0 + trade_gain * 40.0

	return 200.0 + target_value * 25.0

func _known_exposure_cost() -> float:
	var enemy_vision: Dictionary = {}

	# Normal search contains only enemies known at search start.
	for node in simulation.player_pieces[enemy_player - 1]:
		var enemy := node as Model.DataPiece
		for cell in enemy.cur_vision:
			enemy_vision[cell] = true

	var cost: float = 0.0

	for node in simulation.player_pieces[cpu_player - 1]:
		var piece := node as Model.DataPiece
		if not enemy_vision.has(piece.get_cur_pos()):
			continue

		var piece_cost: float = (
			5.0 + float(piece.piece_value) * 4.0
		)
		if piece is Model.DataCorePiece:
			piece_cost = 80.0
		elif piece is Model.DataEyePiece:
			piece_cost = 60.0

		cost += piece_cost

	return cost

func _memory_danger_cost() -> float:
	var total: float = 0.0

	for node in simulation.player_pieces[cpu_player - 1]:
		var piece := node as Model.DataPiece
		var risk: float = float(
			memory_risk.get(piece.get_cur_pos(), 0.0)
		)

		if risk <= 0.0:
			continue

		var value: float = _exchange_value(piece)
		var cost: float = minf(value, 1200.0) * 0.65

		if piece is Model.DataCorePiece:
			cost = 3000.0

		total += risk * cost

	return total



func _piece_actions(piece: Model.DataPiece) -> Array[Dictionary]:
	if piece is Model.DataTowerRotatePiece:
		return (
			piece as Model.DataTowerRotatePiece
		).generate_turn_actions()

	var actions: Array[Dictionary] = []

	for destination in _moves(piece):
		actions.append({
			"piece": piece,
			"destination": destination,
		})

	return actions

func _directional_priority(action: Dictionary) -> float:
	var piece := action["piece"] as Model.DataPiece

	if not piece is Model.DataTowerRotatePiece:
		return _move_priority(action)

	var tower := piece as Model.DataTowerRotatePiece
	var original_direction: int = tower.cur_direction

	tower.cur_direction = int(
		action.get("direction", original_direction)
	)

	var priority: float = _move_priority(action)

	tower.cur_direction = original_direction
	return priority
