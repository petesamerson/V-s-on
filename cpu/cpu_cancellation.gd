extends RefCounted

var _mutex := Mutex.new()
var _cancelled: bool = false

var record_ponder_depth := false
var _ponder_checkpoint: Dictionary = {}


func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()


func is_cancelled() -> bool:
	_mutex.lock()
	var value: bool = _cancelled
	_mutex.unlock()
	return value

func save_ponder_checkpoint(
	piece_id: int,
	destination: Vector2i,
	direction: int,
	depth: int
) -> void:
	_mutex.lock()
	_ponder_checkpoint = {
		"piece_id": piece_id,
		"destination": destination,
		"direction": direction,
		"completed_search_depth": depth,
	}
	_mutex.unlock()


func read_ponder_checkpoint() -> Dictionary:
	_mutex.lock()
	var checkpoint := _ponder_checkpoint.duplicate()
	_mutex.unlock()
	return checkpoint