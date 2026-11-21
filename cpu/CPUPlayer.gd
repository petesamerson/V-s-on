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

var cpu_cover_counts: Dictionary = {}
var cpu_cover_by_piece: Dictionary = {}

var capture_danger: Dictionary = {}
var recent_moves: Array[Dictionary] = []

@export var player_number: int = 2
@export_range(1,6) var difficulty: int = 5

const SpawnKnowledge = preload("res://cpu/cpu_spawn_knowledge.gd")
var spawn_knowledge = SpawnKnowledge.new()

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

var cpu_slice_started_us: int = 0

func setup(game_board: Board) -> void:
	print("cpu created with difficulty " + str(difficulty))
	rng.randomize()
	board = game_board


const WorkerJob = preload("res://cpu/cpu_worker_job.gd")
var _cpu_thread: Thread

const Cancellation = preload("res://cpu/cpu_cancellation.gd")

var _cancellation: Cancellation
var _search_cancelled: bool = false
var _ponder_thread: Thread
var _ponder_job: WorkerJob
var _ponder_cancellation: Cancellation
var _ponder_key: Array = []
var _ponder_active := false
var _ponder_tried_moves: Dictionary = {}
var _ponder_results: Array[Dictionary] = []
var _ponder_preparing := false
var _ponder_geometry: Dictionary = {}
var _ponder_predictions_started := 0

func cancel_search() -> void:
	_search_cancelled = true
	if _cancellation != null:
		_cancellation.cancel()
	if _ponder_cancellation != null:
		_ponder_cancellation.cancel()


func is_search_cancelled() -> bool:
	return _search_cancelled

func start_pondering() -> void:
	if (
		difficulty < 4
		or _search_cancelled
		or _ponder_active
		or _ponder_thread != null
		or _cpu_thread != null
		or not is_inside_tree()
		or not is_instance_valid(board)
		or not board.game_setup_complete
		or board.match_winner != 0
		or board.current_player == player_number
	):
		return

	_ponder_tried_moves.clear()
	_ponder_results.clear()
	_ponder_geometry = {}
	_ponder_predictions_started = 0
	_ponder_active = true
	_start_ponder_preparation()


func stop_pondering() -> void:
	_ponder_active = false
	if _ponder_thread != null and _ponder_thread.is_alive():
		_ponder_cancellation.cancel()


func _process(_delta: float) -> void:
	if not _ponder_active:
		return

	if (
		_search_cancelled
		or not is_instance_valid(board)
		or board.match_winner != 0
		or board.current_player == player_number
	):
		stop_pondering()
		return

	if _ponder_thread != null:
		if _ponder_thread.is_alive():
			return
		_finish_ponder_job()

	_start_next_ponder_job()


func _start_ponder_preparation() -> void:
	var job := WorkerJob.new()
	job.prepare(self)

	_ponder_job = job
	_ponder_preparing = true
	_ponder_cancellation = Cancellation.new()
	job.cancellation = _ponder_cancellation

	var thread := Thread.new()
	if thread.start(job.prepare_cpu_geometry, Thread.PRIORITY_LOW) != OK:
		job.engine.board.dispose()
		_ponder_job = null
		_ponder_cancellation = null
		_ponder_preparing = false
		_ponder_active = false
		return

	_ponder_thread = thread


func _start_next_ponder_job() -> void:
	if _ponder_predictions_started >= 2:
		_ponder_active = false
		return
	var job := WorkerJob.new()
	job.prepare(self)

	if not job.predict_player_move(_ponder_tried_moves):
		job.engine.board.dispose()
		_ponder_active = false
		return

	var tried_destinations: Array = _ponder_tried_moves.get(job.predicted_piece_id, [])
	tried_destinations.append(job.predicted_to)
	_ponder_tried_moves[job.predicted_piece_id] = tried_destinations

	# var mobile := OS.has_feature("android") or OS.has_feature("ios")
	# job.budget_override_ms = 1500 if mobile else 2500

	_ponder_key = job.position_key()
	_ponder_cancellation = Cancellation.new()
	_ponder_cancellation.record_ponder_depth = true
	job.cancellation = _ponder_cancellation

	var thread := Thread.new()
	_ponder_job = job

	if thread.start(job.compute, Thread.PRIORITY_LOW) != OK:
		job.engine.board.dispose()
		_ponder_job = null
		_ponder_cancellation = null
		_ponder_key = []
		_ponder_active = false
		return

	_ponder_thread = thread
	_ponder_predictions_started += 1


func _finish_ponder_job() -> void:
	var result: Dictionary = _ponder_thread.wait_to_finish()

	if _ponder_preparing:
		_ponder_geometry = result
	else:
		var reply := _ponder_cancellation.read_ponder_checkpoint()
		if (
			not bool(result.get("cancelled", false))
			and int(result.get("completed_search_depth", 0)) > 0
			and int(result.get("piece_id", -1)) >= 0
		):
			reply = result

		if not reply.is_empty():
			_ponder_results.append({
				"position": _ponder_key,
				"reply": reply,
			})

	_ponder_preparing = false
	_ponder_thread = null
	_ponder_job = null
	_ponder_cancellation = null
	_ponder_key = []

func _collect_pondered_turn(actual_key: Array) -> Dictionary:
	stop_pondering()

	var thread := _ponder_thread
	if thread != null:
		while thread.is_alive():
			await get_tree().process_frame
			if _ponder_thread != thread:
				return {}

		_finish_ponder_job()

	var reply: Dictionary = {}
	for entry: Dictionary in _ponder_results:
		if entry["position"] == actual_key:
			reply = entry["reply"]
			break

	if not reply.is_empty():
		print("CPU ponder matched the played move at depth ", reply["completed_search_depth"])
	elif not _ponder_tried_moves.is_empty():
		print("CPU ponder had no reusable reply for the played position")

	_ponder_results.clear()
	_ponder_tried_moves.clear()
	return reply

func take_turn() -> void:
	if _search_cancelled or not is_inside_tree():
		return
	if not is_instance_valid(board) or board.current_player != player_number:
		return
	if _cpu_thread != null:
		return
	var job := WorkerJob.new()
	job.prepare(self)

	var pondered := await _collect_pondered_turn(job.position_key())
	if _search_cancelled or not is_inside_tree():
		job.engine.board.dispose()
		return

	var prepared_geometry := _ponder_geometry
	_ponder_geometry = {}

	var result: Dictionary
	if bool(pondered.get("reached_depth_limit", false)):
		print("CPU ponder hit")
		result = pondered
		job.engine.board.dispose()
	else:
		var prepared_entries: int = job.engine.board.import_geometry_cache(prepared_geometry)
		if prepared_entries > 0:
			print("CPU preparation reused ", prepared_entries, " geometry entries")
		job.engine.ponder_hint = pondered
		result = await _run_turn_worker(job)
		if result.is_empty():
			return

	if (
		_search_cancelled
		or not is_inside_tree()
		or bool(result.get("cancelled", false))
	):
		return

	if not is_instance_valid(board) or board.current_player != player_number:
		return

	var chosen: Piece = _find_live_cpu_piece(int(result.get("piece_id", -1)))
	if not is_instance_valid(chosen):
		push_warning("CPU worker returned no move.")
		return
	if chosen.get_cur_pos() != Vector2i(result["from"]):
		push_warning("CPU result discarded because the board changed.")
		return

	# All scene changes and animation calls stay on the main thread.
	for rotation: Dictionary in result["rotations"]:
		var tower := _find_live_cpu_piece(int(rotation["id"])) as TowerRotatePiece
		if not is_instance_valid(tower) or tower.get_cur_pos() != Vector2i(rotation["from"]):
			push_warning("CPU result discarded because a tower changed.")
			return
	for rotation: Dictionary in result["rotations"]:
		var tower := _find_live_cpu_piece(int(rotation["id"])) as TowerRotatePiece
		tower.cur_direction = int(rotation["direction"])
		tower.cur_vision = tower.get_potential_vision(tower.get_cur_pos(), tower.cur_direction)
		tower.update_sprite_rotation()
	board.update_all_core_power_counts()
	board.update_all_piece_vision()

	var destination: Vector2i = result["destination"]
	var legal_moves: Array[Vector2i] = chosen.generate_possible_moves(chosen.get_cur_pos()).duplicate()
	if not legal_moves.has(destination):
		push_error("CPU worker move rejected as illegal: %s -> %s" % [chosen.get_cur_pos(), destination])
		return

	var memory: Dictionary = result["memory"]
	for field in memory:
		set(field, memory[field])
	var knowledge: Dictionary = result["knowledge"]
	spawn_knowledge.models.assign(knowledge["models"])
	spawn_knowledge.sightings = knowledge["sightings"]
	spawn_knowledge.forecast = knowledge["forecast"]
	spawn_knowledge.confidence = float(knowledge["confidence"])
	rng.state = int(result["rng_state"])
	last_enemy_capturer_id = -1
	last_moved_piece = chosen
	print("CPU worker finished in ", result["elapsed_ms"], " ms")

	recent_moves.push_front({
		"id": chosen.get_instance_id(),
		"from": chosen.get_cur_pos(),
		"to": destination,
	})

	if recent_moves.size() > 2:
		recent_moves.pop_back()

	chosen.make_cpu_move(destination)

func _run_turn_worker(job: WorkerJob) -> Dictionary:
	_cancellation = Cancellation.new()
	job.cancellation = _cancellation

	var thread := Thread.new()
	_cpu_thread = thread

	var start_error := thread.start(job.compute)
	if start_error != OK:
		job.engine.board.dispose()
		_cpu_thread = null
		_cancellation = null
		push_error("Could not start CPU worker: %s" % error_string(start_error))
		return {}

	while thread.is_alive():
		await get_tree().process_frame
		if _cpu_thread != thread:
			return {}

	var result: Dictionary = thread.wait_to_finish()
	_cpu_thread = null
	_cancellation = null
	return result

func _find_live_cpu_piece(id: int) -> Piece:
	for node in board.player_pieces[player_number - 1]:
		var piece := node as Piece
		if is_instance_valid(piece) and piece.get_instance_id() == id:
			return piece
	return null

func _exit_tree() -> void:
	cancel_search()
	if _ponder_thread != null and _ponder_thread.is_started():
		_ponder_thread.wait_to_finish()
	_ponder_thread = null
	_ponder_job = null
	_ponder_cancellation = null
	_ponder_key.clear()

	if _cpu_thread != null and _cpu_thread.is_started():
		_cpu_thread.wait_to_finish()

	_cpu_thread = null
	_cancellation = null

func recover_turn() -> bool:
	if not is_instance_valid(board):
		return false
	if board.current_player != player_number:
		return false
	if _cpu_thread != null:
		return false

	board.update_all_core_power_counts()
	board.update_all_piece_vision()
	last_moved_piece = null

	# Emergency recovery: use a move validated by the live rules.
	for node in board.player_pieces[player_number - 1]:
		var piece := node as Piece
		if not is_instance_valid(piece):
			continue
		if piece.is_queued_for_deletion():
			continue

		var moves: Array[Vector2i] = (
			piece.generate_possible_moves(
				piece.get_cur_pos()
			).duplicate()
		)
		if moves.is_empty():
			continue

		last_moved_piece = piece
		push_warning("CPU recovery: executing a live legal move.")
		piece.make_cpu_move(moves[0])
		return true

	push_error("CPU recovery found no legal moves.")
	return false


const SAVE_MEMORY_FIELDS: Array[String] = [
	"early_hop_move_count",
	"early_tower_move_count",
	"next_scout_piece_type",
	"seen_by_player",
	"cpu_turn_count",
	"observed_enemy_capture_count",
	"capture_danger",
]

const SAVE_ID_DICTIONARIES: Array[String] = [
	"moved_piece_ids",
	"enemy_last_seen",
	"enemy_last_seen_turn",
]


func export_save_state() -> Dictionary:
	var data: Dictionary = {}

	for field in SAVE_MEMORY_FIELDS:
		data[field] = get(field)

	for field in SAVE_ID_DICTIONARIES:
		data[field] = get(field)

	data["difficulty"] = difficulty
	data["recent_moves"] = recent_moves
	data["recent_piece_ids"] = recent_piece_ids
	data["last_enemy_capturer_id"] = last_enemy_capturer_id
	data["last_moved_piece_id"] = (
		last_moved_piece.get_instance_id()
		if is_instance_valid(last_moved_piece)
		else -1
	)
	data["rng_seed"] = rng.seed
	data["rng_state"] = rng.state
	data["knowledge"] = {
		"models": spawn_knowledge.models,
		"sightings": spawn_knowledge.sightings,
		"forecast": spawn_knowledge.forecast,
		"confidence": spawn_knowledge.confidence,
	}

	return data.duplicate(true)


func import_save_state(
	data: Dictionary,
	id_map: Dictionary,
	piece_map: Dictionary
) -> void:
	for field in SAVE_MEMORY_FIELDS:
		if data.has(field):
			set(field, data[field])

	for field in SAVE_ID_DICTIONARIES:
		set(field, _remap_saved_dictionary(data.get(field, {}), id_map))

	recent_moves.clear()
	for saved_move in data.get("recent_moves", []):
		var record: Dictionary = saved_move.duplicate(true)
		record["id"] = _remap_saved_id(int(record["id"]), id_map)
		recent_moves.append(record)

	recent_piece_ids.clear()
	for saved_id in data.get("recent_piece_ids", []):
		recent_piece_ids.append(_remap_saved_id(int(saved_id), id_map))

	last_enemy_capturer_id = _remap_saved_id(
		int(data.get("last_enemy_capturer_id", -1)),
		id_map
	)
	last_moved_piece = piece_map.get(
		int(data.get("last_moved_piece_id", -1))
	) as Piece

	difficulty = clampi(int(data.get("difficulty", 3)), 1, 6)
	rng.seed = int(data.get("rng_seed", rng.seed))
	rng.state = int(data.get("rng_state", rng.state))

	var knowledge: Dictionary = data.get("knowledge", {})
	spawn_knowledge.models.assign(knowledge.get("models", []))
	spawn_knowledge.sightings = _remap_saved_dictionary(
		knowledge.get("sightings", {}),
		id_map
	)
	spawn_knowledge.forecast = knowledge.get("forecast", {})
	spawn_knowledge.confidence = float(knowledge.get("confidence", 1.0))


func _remap_saved_id(saved_id: int, id_map: Dictionary) -> int:
	# Captured pieces retain distinct, non-live IDs in memory.
	return int(id_map.get(saved_id, -absi(saved_id)))


func _remap_saved_dictionary(
	values: Dictionary,
	id_map: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	for saved_id in values:
		result[_remap_saved_id(int(saved_id), id_map)] = values[saved_id]
	return result

func is_thinking() -> bool:
	return _cpu_thread != null
