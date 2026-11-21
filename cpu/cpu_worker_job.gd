extends RefCounted

const Model = preload("res://cpu/cpu_worker_model.gd")
const Scorer = preload("res://cpu/cpu_worker_scorer.gd")

const MEMORY_FIELDS: Array[String] = [
	"early_hop_move_count", "early_tower_move_count",
	"next_scout_piece_type", "seen_by_player", "cpu_turn_count",
	"observed_enemy_capture_count",
]
const ID_DICTIONARIES: Array[String] = [
	"moved_piece_ids", "enemy_last_seen", "enemy_last_seen_turn",
]

var engine = Scorer.new()
var live_to_worker: Dictionary = {}
var worker_to_live: Dictionary = {}
var initial_directions: Dictionary = {}

const Cancellation = preload("res://cpu/cpu_cancellation.gd")
var cancellation: Cancellation
var budget_override_ms := 0
var predicted_piece_id := -1
var predicted_from := Vector2i.ZERO
var predicted_to := Vector2i.ZERO

# Call this on the main thread, before starting compute().
func prepare(cpu: Node) -> void:
	var source_board: Variant = cpu.get("board")
	engine.board = Model.DataBoard.new()
	engine.board.board_center = source_board.board_center
	engine.board.board_size = source_board.board_size
	engine.board.board_tiles = source_board.board_tiles.duplicate()
	engine.board.wall_cells = source_board.wall_cells.duplicate()
	engine.board.map_spawn_cells = (
		source_board.get_possible_spawn_locations()
	)
	engine.board.current_player = source_board.current_player
	engine.player_number = cpu.get("player_number")
	engine.difficulty = cpu.get("difficulty")

	engine.promotion_cells.clear()
	engine.promotion_moves_remaining = -1

	if source_board._promotion_enabled():
		engine.promotion_moves_remaining = source_board.promotion_turns_remaining
		var center: Vector2i = source_board.board_center
		engine.promotion_cells[center] = true
		for cell: Vector2i in source_board.get_surrounding_cells(center):
			if source_board.is_walkable_cell(cell):
				engine.promotion_cells[cell] = true

	for side in range(2):
		engine.board.player_captures[side].resize(
			source_board.player_captures[side].size()
		)

		# Transfer only capture coordinates, not rendering resources.
		for i in range(source_board.player_captures[side].size()):
			var record: Dictionary = source_board.player_captures[side][i]
			var worker_record: Dictionary = {}
			if record.has("cell"):
				worker_record["cell"] = record["cell"]
			engine.board.player_captures[side][i] = worker_record

		for source: Node in source_board.player_pieces[side]:
			if not is_instance_valid(source) or source.is_queued_for_deletion():
				continue
			var kind: String = source.get_script().resource_path.get_file().get_basename()
			var copy: Model.DataPiece = _make_piece(kind)
			copy.live_id = source.get_instance_id()
			copy.board = engine.board
			copy.position = Vector2(source.call("get_cur_pos"))
			copy.owned_player = source.get("owned_player")
			copy.vision_range = source.get("vision_range")
			copy.move_range = source.get("move_range")
			copy.piece_value = float(source.get("piece_value"))
			copy.powered = source.get("powered")
			copy.cur_vision.assign(source.get("cur_vision"))
			copy.cur_moves.assign(source.get("cur_moves"))
			if copy is Model.DataCorePiece:
				copy.power_count = source.get("power_count")
			if copy is Model.DataTowerRotatePiece:
				copy.cur_direction = source.get("cur_direction")
				initial_directions[copy.live_id] = copy.cur_direction
			engine.board.player_pieces[side].append(copy)
			engine.board.pieces_container.add_child(copy)
			live_to_worker[copy.live_id] = copy.get_instance_id()
			worker_to_live[copy.get_instance_id()] = copy.live_id

	engine.reversal_origins.clear()

	for record in cpu.get("recent_moves"):
		var worker_id: int = int(
			live_to_worker.get(int(record["id"]), -1)
		)

		if worker_id < 0:
			continue

		# The history is newest first; keep the most recent origin.
		if not engine.reversal_origins.has(worker_id):
			engine.reversal_origins[worker_id] = record["from"]

	for side in range(2):
		var capturer: int = source_board.last_capture_capturer_ids[side]
		engine.board.last_capture_capturer_ids[side] = int(
			live_to_worker.get(capturer, capturer)
		)
	for field in MEMORY_FIELDS:
		engine.set(field, cpu.get(field))
	for field in ID_DICTIONARIES:
		engine.set(field, _remap(cpu.get(field), live_to_worker))
	engine.recent_piece_ids.clear()
	for id: int in cpu.get("recent_piece_ids"):
		engine.recent_piece_ids.append(int(live_to_worker.get(id, id)))
	var recent: int = cpu.get("last_enemy_capturer_id")
	engine.last_enemy_capturer_id = int(live_to_worker.get(recent, recent))

	var knowledge: Variant = cpu.get("spawn_knowledge")
	engine.spawn_knowledge.models.assign(knowledge.models.duplicate(true))
	engine.spawn_knowledge.sightings = _remap(knowledge.sightings, live_to_worker)
	engine.spawn_knowledge.forecast = knowledge.forecast.duplicate(true)
	engine.spawn_knowledge.confidence = knowledge.confidence
	var source_rng: RandomNumberGenerator = cpu.get("rng")
	engine.rng.seed = source_rng.seed
	engine.rng.state = source_rng.state

func position_key() -> Array:
	var data_board: Model.DataBoard = engine.board
	var pieces: Array = []

	for group in data_board.player_pieces:
		for piece: Model.DataPiece in group:
			var direction := -1
			if piece is Model.DataTowerRotatePiece:
				direction = (piece as Model.DataTowerRotatePiece).cur_direction

			var vision := piece.cur_vision.duplicate()
			vision.sort()
			pieces.append([piece.live_id, piece.get_cur_pos(), direction, vision])

	return [
		data_board.current_player,
		engine.promotion_moves_remaining,
		data_board.player_captures.duplicate(true),
		[
			worker_to_live.get(data_board.last_capture_capturer_ids[0], data_board.last_capture_capturer_ids[0]),
			worker_to_live.get(data_board.last_capture_capturer_ids[1], data_board.last_capture_capturer_ids[1]),
		],
		engine.seen_by_player,
		pieces,
	]

func prepare_cpu_geometry() -> Dictionary:
	var data_board: Model.DataBoard = engine.board
	var cpu_side: int = engine.player_number
	data_board.current_player = cpu_side

	for piece: Model.DataPiece in data_board.player_pieces[cpu_side - 1]:
		if cancellation.is_cancelled():
			break

		var origin := piece.get_cur_pos()
		if piece is Model.DataTowerRotatePiece:
			var sentry := piece as Model.DataTowerRotatePiece
			for action: Dictionary in sentry.generate_turn_actions():
				if cancellation.is_cancelled():
					break

				var destination: Vector2i = action["destination"]
				var direction: int = action["direction"]
				sentry.get_potential_vision(destination, direction)
				_warm_move_lines(data_board, destination, 10)
		else:
			piece.get_potential_vision(origin)
			for destination: Vector2i in piece.generate_possible_moves(origin):
				if cancellation.is_cancelled():
					break

				piece.get_potential_vision(destination)
				_warm_move_lines(data_board, destination, piece.move_range)

	var cache := data_board.export_geometry_cache()
	data_board.dispose()
	return cache


func _warm_move_lines(
	data_board: Model.DataBoard,
	origin: Vector2i,
	length: int
) -> void:
	for direction in range(6):
		data_board.get_line_from_center(origin, direction, length)
func predict_player_move(tried_moves: Dictionary) -> bool:
	var data_board: Model.DataBoard = engine.board
	var cpu_side: int = engine.player_number
	var human_side := 3 - cpu_side

	# Either side may promote automatically on this countdown tick.
	if data_board.current_player != human_side or engine.promotion_moves_remaining == 1:
		return false

	data_board.regenerate_all_piece_moves(cpu_side, true)

	var known_targets: Dictionary = {}
	var threatened_cells: Dictionary = {}

	for opponent: Model.DataPiece in data_board.player_pieces[cpu_side - 1]:
		var cell := opponent.get_cur_pos()
		if not data_board.hasCellInVision(human_side, cell):
			continue

		known_targets[cell] = opponent
		var attacks := opponent.cur_moves
		if opponent is Model.DataTowerRotatePiece:
			attacks = (opponent as Model.DataTowerRotatePiece).cur_possible_rotate_moves

		for target_cell in attacks:
			threatened_cells[target_cell] = true

	var predicted_piece: Model.DataPiece = null
	var predicted_capture: Model.DataPiece = null
	var predicted_cell := Vector2i.ZERO
	var best_score := -INF

	for piece: Model.DataPiece in data_board.player_pieces[human_side - 1]:
		if piece is Model.DataCorePiece:
			continue

		var origin := piece.get_cur_pos()
		if not data_board.hasCellInVision(cpu_side, origin):
			continue

		var moves := piece.generate_possible_moves(origin).duplicate()
		var distance_before: int = engine.hex_distance(origin, data_board.board_center)

		for destination: Vector2i in moves:
			var tried_destinations: Array = tried_moves.get(piece.live_id, [])
			if tried_destinations.has(destination):
				continue
			if not data_board.hasCellInVision(cpu_side, destination):
				continue

			if (
				piece is Model.DataHopPiece
				and engine.promotion_moves_remaining == 0
				and engine.promotion_cells.has(destination)
			):
				continue

			var captured := known_targets.get(destination) as Model.DataPiece
			if captured is Model.DataCorePiece:
				continue

			var distance_after: int = engine.hex_distance(destination, data_board.board_center)
			var score := float(distance_before - distance_after) * 12.0
			var threatened := threatened_cells.has(destination)

			if captured != null:
				score += 75.0 + maxf(1.0, captured.piece_value) * 24.0

			if threatened:
				score -= 35.0 + maxf(1.0, piece.piece_value) * 24.0
			else:
				for ally: Model.DataPiece in data_board.player_pieces[human_side - 1]:
					if ally != piece and ally.cur_vision.has(destination):
						score += 25.0
						break

				if captured == null:
					var following_moves: Array[Vector2i] = engine.get_moves_from_position(
						piece, destination
					)
					var threat_bonus := 0.0
					for target in known_targets:
						if following_moves.has(target) and not moves.has(target):
							var enemy := known_targets[target] as Model.DataPiece
							threat_bonus = maxf(
								threat_bonus, 20.0 + enemy.piece_value * 8.0
							)
					score += threat_bonus

			if score > best_score:
				best_score = score
				predicted_piece = piece
				predicted_capture = captured
				predicted_cell = destination

	if predicted_piece == null:
		return false

	predicted_piece_id = predicted_piece.live_id
	predicted_from = predicted_piece.get_cur_pos()
	predicted_to = predicted_cell

	if predicted_capture != null:
		data_board.player_captures[human_side - 1].append({"cell": predicted_cell})
		data_board.last_capture_capturer_ids[human_side - 1] = predicted_piece.get_instance_id()
		data_board.player_pieces[cpu_side - 1].erase(predicted_capture)
		data_board.pieces_container.remove_child(predicted_capture)

	predicted_piece.position = Vector2(predicted_cell)
	data_board.current_player = cpu_side
	if engine.promotion_moves_remaining > 0:
		engine.promotion_moves_remaining -= 1

	data_board.refresh_vision()
	for piece: Model.DataPiece in data_board.player_pieces[cpu_side - 1]:
		if data_board.hasCellInVision(human_side, piece.get_cur_pos()):
			engine.seen_by_player = true
			break

	return true


# Runs exclusively on a worker thread. It has no live Node references.
func compute() -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var budgets: Array[int] = [750, 1000, 1250, 2000, 5000, 10000]
	var budget_ms := budgets[clampi(engine.difficulty - 1, 0, 5)]
	if budget_override_ms > 0:
		budget_ms = mini(budget_ms, budget_override_ms)
	engine.turn_deadline = started + budget_ms
	engine.cancellation = cancellation
	engine.take_turn()
	if cancellation != null and cancellation.is_cancelled():
		engine.chosen_action.clear()
		engine.last_moved_piece = null
		engine.board.dispose()
		return {"cancelled": true}

	var result: Dictionary = {"piece_id": -1, "rotations": []}
	result["reached_depth_limit"] = engine.reached_depth_limit
	result["completed_search_depth"] = engine.completed_search_depth
	if not engine.chosen_action.is_empty():
		var chosen: Model.DataPiece = engine.chosen_action["piece"]
		result["piece_id"] = chosen.live_id
		result["from"] = chosen.get_cur_pos()
		result["destination"] = engine.chosen_action["destination"]
		result["direction"] = int(engine.chosen_action.get("direction", -1))
	for node in engine.board.player_pieces[engine.player_number - 1]:
		if node is Model.DataTowerRotatePiece:
			var tower := node as Model.DataTowerRotatePiece
			if tower.cur_direction != int(initial_directions.get(tower.live_id, tower.cur_direction)):
				result["rotations"].append({
					"id": tower.live_id,
					"from": tower.get_cur_pos(),
					"direction": tower.cur_direction,
				})

	var memory: Dictionary = {}
	for field in MEMORY_FIELDS:
		memory[field] = engine.get(field)
	for field in ID_DICTIONARIES:
		memory[field] = _remap(engine.get(field), worker_to_live)
	var recent_ids: Array[int] = []
	for id: int in engine.recent_piece_ids:
		recent_ids.append(int(worker_to_live.get(id, id)))
	memory["recent_piece_ids"] = recent_ids
	result["memory"] = memory
	result["knowledge"] = {
		"models": engine.spawn_knowledge.models.duplicate(true),
		"sightings": _remap(engine.spawn_knowledge.sightings, worker_to_live),
		"forecast": engine.spawn_knowledge.forecast.duplicate(true),
		"confidence": engine.spawn_knowledge.confidence,
	}
	result["rng_state"] = engine.rng.state
	result["elapsed_ms"] = Time.get_ticks_msec() - started
	engine.chosen_action.clear()
	engine.last_moved_piece = null
	engine.board.dispose()
	return result

func _remap(values: Dictionary, ids: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in values:
		var value: Variant = values[id]
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		result[ids.get(id, id)] = value
	return result

func _make_piece(kind: String) -> Model.DataPiece:
	match kind:
		"CorePiece": return Model.DataCorePiece.new()
		"EyePiece": return Model.DataEyePiece.new()
		"HopPiece": return Model.DataHopPiece.new()
		"TriangleEvenPiece": return Model.DataTriangleEvenPiece.new()
		"TriangleOddPiece": return Model.DataTriangleOddPiece.new()
		"TowerRotatePiece": return Model.DataTowerRotatePiece.new()
	return Model.DataPiece.new()
