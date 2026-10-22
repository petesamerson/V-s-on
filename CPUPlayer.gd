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

const SpawnKnowledge = preload("res://cpu_spawn_knowledge.gd")
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


const WorkerJob = preload("res://cpu_worker_job.gd")
var _cpu_thread: Thread

func take_turn() -> void:
	if not is_instance_valid(board) or board.current_player != player_number:
		return
	if _cpu_thread != null:
		return

	var job = WorkerJob.new()
	job.prepare(self)
	_cpu_thread = Thread.new()
	var start_error: Error = _cpu_thread.start(job.compute)
	if start_error != OK:
		_cpu_thread = null
		push_error("Could not start CPU worker: %s" % error_string(start_error))
		return

	while _cpu_thread.is_alive():
		await get_tree().process_frame

	var result: Dictionary = _cpu_thread.wait_to_finish()
	_cpu_thread = null
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

func _find_live_cpu_piece(id: int) -> Piece:
	for node in board.player_pieces[player_number - 1]:
		var piece := node as Piece
		if is_instance_valid(piece) and piece.get_instance_id() == id:
			return piece
	return null

func _exit_tree() -> void:
	# Join before releasing the Thread if the game closes mid-search.
	if _cpu_thread != null and _cpu_thread.is_started():
		_cpu_thread.wait_to_finish()
	_cpu_thread = null


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
