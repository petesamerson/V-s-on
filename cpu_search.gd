extends RefCounted

const WIN_SCORE: float = 1000000.0

var simulation: Board
var cpu_player: int
var enemy_player: int

var deadline: int
var timed_out: bool = false
var completed_depth: int = 0
var branch_limit: int = 8

var clones: Dictionary = {}
var known_cores: Dictionary = {}
var all_enemies_known: bool = false

var initial_known_tiles: Dictionary = {}
var initial_positions: Dictionary = {}
var recent_capturer: Piece

func choose(
	live_board: Board,
	player_id: int,
	difficulty: int,
	candidates: Array[Dictionary],
	recent_capturer_id: int = -1
) -> Dictionary:
	cpu_player = player_id
	enemy_player = 2 if player_id == 1 else 1

	completed_depth = 0
	timed_out = false
	clones.clear()
	known_cores.clear()

	var budget_ms: int = 120
	var max_depth: int = 2

	if difficulty == 5:
		budget_ms = 250
		max_depth = 3
	elif difficulty >= 6:
		budget_ms = 500
		max_depth = 5

	deadline = Time.get_ticks_msec() + budget_ms

	_build_simulation(live_board)
	recent_capturer = clones.get(recent_capturer_id) as Piece

	var roots: Array[Dictionary] = []

	for candidate in candidates:
		var live_piece := candidate["piece"] as Piece

		if not is_instance_valid(live_piece):
			continue

		var copy := clones.get(
			live_piece.get_instance_id()
		) as Piece

		if copy == null:
			continue

		# Conservative check using the copied piece's current
		# orientation and the visible-board model.
		simulation.current_player = cpu_player

		var destinations: Array[Vector2i] = _moves(copy)

		if not destinations.has(candidate["destination"]):
			continue

		var action: Dictionary = {
			"piece": copy,
			"destination": candidate["destination"],
			"original": candidate,
		}

		# action["priority"] = _move_priority(action)
		action["recapture_bonus"] = _recapture_preference(action)
		action["priority"] = (
			_move_priority(action)
			+ _legacy_preference(action)
		)
		roots.append(action)

	if roots.is_empty():
		simulation.free()
		return {}

	# Examine core safety before captures and scouting
	# determine which moves survive the root limit.
	roots = _prefer_core_safe_actions(roots, cpu_player)

	roots.sort_custom(
		func(a, b):
			return float(a["priority"]) > float(b["priority"])
	)

	# Search a manageable set of promising root moves.
	if roots.size() > 18:
		roots.resize(18)

	# The core-safety pass has already filtered these roots.
	# If deeper search times out, preserve the original AI's
	# piece-safety judgment and strategic scoring.
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

	# Preparation and mandatory safety checks must not consume
	# the entire allowance for looking ahead.
	timed_out = false
	deadline = Time.get_ticks_msec() + budget_ms


	# Iterative deepening: only commit a fully finished depth.
	for depth in range(2, max_depth + 1):
		if _expired():
			break

		var iteration_best: Dictionary = {}
		var iteration_score: float = -INF
		var alpha: float = -INF

		for action in roots:
			if _expired():
				break

			var undo: Dictionary = _push(action)

			var value: float = _minimax(
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

	print(
		"CPU search completed depth ",
		completed_depth,
		" at difficulty ",
		difficulty
	)

	simulation.free()
	return best_original


func _build_simulation(live_board: Board) -> void:
	# Never add this board to the scene tree.
	# Its _ready(), UI, and network logic therefore do not run.
	initial_known_tiles.clear()
	initial_positions.clear()
	simulation = Board.new()
	simulation.tile_set = live_board.tile_set
	simulation.board_center = live_board.board_center
	simulation.board_size = live_board.board_size
	simulation.board_tiles = live_board.board_tiles.duplicate()
	simulation.current_player = cpu_player
	simulation.player_pieces = [[], []]

	simulation.pieces_container = Node2D.new()
	simulation.add_child(simulation.pieces_container)

	var enemy_count: int = 0
	var visible_enemy_count: int = 0

	for side_index in range(live_board.player_pieces.size()):
		for node in live_board.player_pieces[side_index]:
			var source := node as Piece

			if source == null or source.is_queued_for_deletion():
				continue

			if source.owned_player != cpu_player:
				enemy_count += 1

				if not live_board.hasCellInVision(
					cpu_player,
					source.get_cur_pos()
				):
					continue

				visible_enemy_count += 1

			var copy := source.get_script().new() as Piece

			copy.board = simulation
			copy.owned_player = source.owned_player
			copy.position = simulation.map_to_local(
				source.get_cur_pos()
			)
			copy.vision_range = source.vision_range
			copy.move_range = source.move_range
			copy.piece_value = source.piece_value
			copy.powered = source.powered

			if source is TowerRotatePiece:
				(copy as TowerRotatePiece).cur_direction = (
					(source as TowerRotatePiece).cur_direction
				)

			simulation.pieces_container.add_child(copy)
			simulation.player_pieces[
				copy.owned_player - 1
			].append(copy)

			# clones[source.get_instance_id()] = copy
			initial_positions[copy.get_instance_id()] = (
				copy.get_cur_pos()
			)

			if copy is CorePiece:
				known_cores[copy.owned_player] = true

	all_enemies_known = enemy_count == visible_enemy_count
	_refresh()

		# Territory currently visible to the CPU.
	for node in simulation.player_pieces[cpu_player - 1]:
		var piece := node as Piece

		for cell in piece.cur_vision:
			initial_known_tiles[cell] = true

func _scouting_score() -> float:
	var cheapest_revealer: Dictionary = {}
	var exposure_penalty: float = 0.0

	for node in simulation.player_pieces[cpu_player - 1]:
		var piece := node as Piece

		if piece is CorePiece:
			continue

		var value: float = maxf(
			1.0,
			float(piece.piece_value)
		)

		var unknown_cells: int = 0

		for cell in piece.cur_vision:
			if initial_known_tiles.has(cell):
				continue

			unknown_cells += 1

			# Count each new tile once, using the cheapest
			# friendly piece that can reveal it.
			var previous_value: float = float(
				cheapest_revealer.get(cell, INF)
			)

			cheapest_revealer[cell] = minf(
				previous_value,
				value
			)

		var initial_cell: Vector2i = initial_positions.get(
			piece.get_instance_id(),
			piece.get_cur_pos()
		)

		if (
			piece.get_cur_pos() != initial_cell
			and unknown_cells > 0
		):
			var uncertainty: float = minf(
				float(unknown_cells) / 12.0,
				1.0
			)

			# Expensive pieces carry more risk when advancing
			# into territory whose occupants are unknown.
			exposure_penalty += (
				uncertainty
				* value
				* value
				* 2.0
			)

	var exploration_reward: float = 0.0

	for cell in cheapest_revealer:
		var scout_value: float = float(
			cheapest_revealer[cell]
		)

		exploration_reward += (
			5.0 / (1.0 + scout_value * 0.75)
		)

	# Exploration should not outweigh major material gains
	# or the much larger core-safety penalties.
	return minf(exploration_reward, 120.0) - exposure_penalty

func _refresh() -> void:
	# Recompute vision without drawing anything.
	for group in simulation.player_pieces:
		for node in group:
			var piece := node as Piece

			if piece is CorePiece:
				piece.cur_vision = []
			else:
				piece.cur_vision = piece.get_potential_vision(
					piece.get_cur_pos()
				)

	for side in [1, 2]:
		var core: CorePiece = _core(side)

		if core != null:
			core.power_count = _support_count(side, core)


func _core(side: int) -> CorePiece:
	for node in simulation.player_pieces[side - 1]:
		if node is CorePiece:
			return node as CorePiece

	return null


func _support_count(side: int, core: CorePiece) -> int:
	var count: int = 0

	for node in simulation.player_pieces[side - 1]:
		var piece := node as Piece

		if piece is CorePiece:
			continue

		if piece.cur_vision.has(core.get_cur_pos()):
			count += 1

	return count


func _moves(piece: Piece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if piece is CorePiece:
		result.assign(
			(piece as CorePiece).generate_possible_moves(
				piece.get_cur_pos()
			)
		)
	else:
		# Towers use their current orientation here.
		result.assign(
			piece.generate_possible_moves(piece.get_cur_pos())
		)

	return result


func _actions(side: int) -> Array[Dictionary]:
	simulation.current_player = side

	# Populate both sides' threat caches before generating
	# guarded-core moves. These are simulation pieces only.
	simulation.regenerate_all_piece_moves(1, true)
	simulation.regenerate_all_piece_moves(2, true)

	var actions: Array[Dictionary] = []

	for node in simulation.player_pieces[side - 1]:
		if _expired():
			break

		var piece := node as Piece
		var destinations: Array[Vector2i] = _moves(piece)

		for destination in destinations:
			var action: Dictionary = {
				"piece": piece,
				"destination": destination,
			}

			action["priority"] = _move_priority(action)
			actions.append(action)

	actions = _prefer_core_safe_actions(actions, side)
	actions.sort_custom(
		func(a, b):
			return float(a["priority"]) > float(b["priority"])
	)

	# A bounded search: retain the most promising replies.
	if actions.size() > branch_limit:
		actions.resize(branch_limit)

	return actions


func _move_priority(action: Dictionary) -> float:
	var piece := action["piece"] as Piece
	var destination: Vector2i = action["destination"]
	var opponent: int = 2 if piece.owned_player == 1 else 1

	var target: Piece = simulation.get_enemy_piece_at_cell(
		destination,
		opponent
	)

	var priority: float = 0.0

	if target is CorePiece:
		return WIN_SCORE

	if target != null:
		priority += (
			1000.0
			+ float(target.piece_value) * 100.0
			- float(piece.piece_value) * 10.0
		)

	# Prefer cheaper scouts when ordering exploration moves.
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

func _legacy_preference(action: Dictionary) -> float:
	var original: Dictionary = action.get("original", {})

	var original_score: float = float(
		original.get("score", 0.0)
	)

	var recapture_bonus: float = float(
		action.get("recapture_bonus", 0.0)
	)

	return (
		clampf(original_score, -5000.0, 5000.0) * 0.05
		+ recapture_bonus
	)

func _push(action: Dictionary) -> Dictionary:
	var piece := action["piece"] as Piece
	var destination: Vector2i = action["destination"]
	var opponent: int = 2 if piece.owned_player == 1 else 1

	var captured: Piece = simulation.get_enemy_piece_at_cell(
		destination,
		opponent
	)

	var undo: Dictionary = {
		"position": piece.position,
		"player": simulation.current_player,
		"captured": captured,
		"captured_index": -1,
	}

	if captured != null:
		var group: Array = simulation.player_pieces[opponent - 1]
		undo["captured_index"] = group.find(captured)

		group.erase(captured)
		simulation.pieces_container.remove_child(captured)

	piece.position = simulation.map_to_local(destination)
	_refresh()

	return undo


func _pop(action: Dictionary, undo: Dictionary) -> void:
	var piece := action["piece"] as Piece
	piece.position = undo["position"]

	var captured := undo["captured"] as Piece

	if captured != null:
		simulation.pieces_container.add_child(captured)

		var group: Array = simulation.player_pieces[
			captured.owned_player - 1
		]

		group.insert(int(undo["captured_index"]), captured)

	simulation.current_player = int(undo["player"])
	_refresh()


func _terminal_score() -> float:
	var own_core: CorePiece = _core(cpu_player)
	var opponent_core: CorePiece = _core(enemy_player)

	if own_core == null or own_core.power_count == 0:
		return -WIN_SCORE

	# An unseen enemy core is unknown, not captured.
	if known_cores.has(enemy_player) and opponent_core == null:
		return WIN_SCORE

	# Unknown supporters may still be powering the enemy core.
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
			var piece := node as Piece

			if not piece is CorePiece:
				score += (
					sign_value
					* float(piece.piece_value)
					* 100.0
				)

			for cell in piece.cur_vision:
				visible_cells[cell] = true

		score += sign_value * float(visible_cells.size()) * 0.5

		var core: CorePiece = _core(side)

		if core != null:
			score += (
				sign_value
				* float(mini(core.power_count, 4))
				* 20.0
			)
	# Core exposure matters much more than ordinary material.
	score -= (
		float(mini(_core_threat_count(cpu_player), 3))
		* 30000.0
	)

	score += (
		float(mini(_core_threat_count(enemy_player), 3))
		* 15000.0
	)

	# One remaining supporter makes the CPU core fragile.
	var own_core: CorePiece = _core(cpu_player)

	if own_core != null and own_core.power_count == 1:
		score -= 8000.0

	score += _scouting_score()
	score += _tactical_score()
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
		return _evaluate()

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


func _expired() -> bool:
	if Time.get_ticks_msec() >= deadline:
		timed_out = true

	return timed_out

func _can_reach_core(attacker: Piece, target: Vector2i) -> bool:
	var origin := attacker.get_cur_pos()

	if origin == target:
		return false

	if attacker is TowerRotatePiece:
		# Consider each possible tower orientation.
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
					simulation.hex_line(
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

	if attacker is TriangleEvenPiece:
		directions = [1, 3, 5]
	elif attacker is TriangleOddPiece:
		directions = [0, 2, 4]

	for direction in directions:
		var cells: Array[Vector2i] = (
			simulation.get_line_from_center(
				origin,
				direction,
				attacker.move_range
			)
		)

		if attacker is HopPiece:
			if not cells.is_empty() and cells.back() == target:
				return true
		elif cells.has(target):
			return true

	return false

func _core_threat_count(side: int) -> int:
	var core: CorePiece = _core(side)

	if core == null:
		return 0

	var critical_cells: Array[Vector2i] = [
		core.get_cur_pos()
	]

	# Capturing the last supporter also loses the game.
	if core.power_count == 1:
		for node in simulation.player_pieces[side - 1]:
			var supporter := node as Piece

			if supporter is CorePiece:
				continue

			if supporter.cur_vision.has(core.get_cur_pos()):
				critical_cells.append(supporter.get_cur_pos())
				break

	var opponent: int = 2 if side == 1 else 1
	var count: int = 0

	for node in simulation.player_pieces[opponent - 1]:
		var attacker := node as Piece

		for target in critical_cells:
			if _can_reach_core(attacker, target):
				count += 1
				break

	return count

func _prefer_core_safe_actions(
	actions: Array[Dictionary],
	side: int
) -> Array[Dictionary]:
	var preferred: Array[Dictionary] = []
	var best_safety: int = -2

	for action in actions:
		var undo: Dictionary = _push(action)
		var core: CorePiece = _core(side)
		var terminal: float = _terminal_score()
		var perspective: float = (
			1.0 if side == cpu_player else -1.0
		)

		var safety: int = 0

		if terminal * perspective > 0.0:
			# An immediate win takes priority.
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
	attacker: Piece,
	target: Piece
) -> bool:
	var defending_side: int = target.owned_player
	var destination := target.get_cur_pos()

	var action: Dictionary = {
		"piece": attacker,
		"destination": destination,
	}

	# Evaluate the board after the threatened capture.
	# The target no longer contributes vision or core support.
	var undo: Dictionary = _push(action)

	simulation.current_player = defending_side

	var can_recapture: bool = false
	var defending_core: CorePiece = _core(defending_side)

	# A side that has already lost cannot recapture.
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

	# An unseen core does not mean the opponent has lost.
	if not core_captured and not power_lost:
		for node in simulation.player_pieces[defending_side - 1]:
			var defender := node as Piece
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

		# Avoid counting multiple attackers against the same
		# target as several separate material gains.
		var best_gain_by_target: Dictionary = {}
		var strongest_fork: float = 0.0

		for node in simulation.player_pieces[side - 1]:
			if _expired():
				simulation.current_player = saved_player
				return 0.0
				# return total

			var attacker := node as Piece
			var moves: Array[Vector2i] = _moves(attacker)
			var profitable_targets: Array[float] = []

			# Copy because simulated captures temporarily
			# remove targets from their player's array.
			var targets: Array = (
				simulation.player_pieces[opponent - 1].duplicate()
			)

			for target_node in targets:
				if _expired():
					simulation.current_player = saved_player
					return 0.0

				var target := target_node as Piece

				if target is CorePiece:
					# Core threats have their own much
					# larger safety and terminal scores.
					continue

				if not moves.has(target.get_cur_pos()):
					continue
				var gain: float = _exchange_value(target)
				var attacker_cost: float = _exchange_value(attacker)

				if _can_recapture(attacker, target):
					gain -= attacker_cost
				# var gain: float = (
				# 	float(target.piece_value) * 100.0
				# )

				# if _can_recapture(attacker, target):
				# 	gain -= (
				# 		float(attacker.piece_value) * 100.0
				# 	)

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

				# The second-best target measures the
				# alternative threat in a potential fork.
				strongest_fork = maxf(
					strongest_fork,
					profitable_targets[1]
				)

		var side_score: float = 0.0

		for target_id in best_gain_by_target:
			side_score += float(
				best_gain_by_target[target_id]
			)

		# Multiple profitable targets are a serious fork.
		side_score += minf(
			strongest_fork * 0.6,
			400.0
		)

		# Treat enemy threats seriously. Our own threats
		# are opportunities until the capture happens.
		var threat_weight: float = (
			0.45 if side == cpu_player else 1.0
		)

		total += (
			sign_value
			* minf(side_score, 4000.0)
			* threat_weight
		)
	simulation.current_player = saved_player
	return total

func _exchange_value(piece: Piece) -> float:
	var value: float = float(piece.piece_value) * 100.0

	if piece is CorePiece:
		return WIN_SCORE

	var core: CorePiece = _core(piece.owned_player)

	if (
		core != null
		and piece.cur_vision.has(core.get_cur_pos())
	):
		# Powered pieces retain their material value,
		# with a premium for supporting the core.
		value *= 1.35

		if core.power_count <= 2:
			value += 150.0

	return value


func _recapture_preference(action: Dictionary) -> float:
	if not is_instance_valid(recent_capturer):
		return 0.0

	var piece := action["piece"] as Piece
	var destination: Vector2i = action["destination"]

	var target: Piece = simulation.get_enemy_piece_at_cell(
		destination,
		enemy_player
	)

	if target != recent_capturer:
		return 0.0

	# Keep core captures under the existing terminal checks.
	if piece is CorePiece or target is CorePiece:
		return 0.0

	var target_value: float = float(target.piece_value)
	var attacker_value: float = float(piece.piece_value)

	if _can_recapture(piece, target):
		var trade_gain: float = target_value - attacker_value

		# Do not encourage an expensive revenge trade.
		if trade_gain < 0.0:
			return 0.0

		return 150.0 + trade_gain * 40.0

	# Taking the capturer without losing the responding piece
	# also prevents it from continuing its attack.
	return 200.0 + target_value * 25.0
