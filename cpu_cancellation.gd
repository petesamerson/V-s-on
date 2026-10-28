extends RefCounted

var _mutex := Mutex.new()
var _cancelled: bool = false


func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()


func is_cancelled() -> bool:
	_mutex.lock()
	var value: bool = _cancelled
	_mutex.unlock()
	return value