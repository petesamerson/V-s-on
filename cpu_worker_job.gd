extends RefCounted

const Model = preload("res://cpu_worker_model.gd")
const Scorer = preload("res://cpu_worker_scorer.gd")

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

# Call this on the main thread, before starting compute().
func prepare(cpu: Node) -> void:
	var source_board: Variant = cpu.get("board")
	engine.board = Model.DataBoard.new()
	engine.board.board_center = source_board.board_center
	engine.board.board_size = source_board.board_size
	engine.board.board_tiles = source_board.board_tiles.duplicate()
	engine.board.current_player = source_board.current_player
	engine.player_number = cpu.get("player_number")
	engine.difficulty = cpu.get("difficulty")

	for side in range(2):
		engine.board.player_captures[side].resize(
			source_board.player_captures[side].size()
		)
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

# Runs exclusively on a worker thread. It has no live Node references.
func compute() -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var budgets: Array[int] = [750, 1000, 1250, 1500, 2250, 3000]
	engine.turn_deadline = started + budgets[clampi(engine.difficulty - 1, 0, 5)]
	engine.take_turn()

	var result: Dictionary = {"piece_id": -1, "rotations": []}
	if not engine.chosen_action.is_empty():
		var chosen: Model.DataPiece = engine.chosen_action["piece"]
		result["piece_id"] = chosen.live_id
		result["from"] = chosen.get_cur_pos()
		result["destination"] = engine.chosen_action["destination"]
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
