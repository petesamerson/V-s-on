extends Node

signal room_created(code: String)
signal room_joined(code: String)
signal opponent_joined
signal game_message_received(payload: Variant, from_player: int)
signal opponent_disconnected
signal connection_closed
signal network_error(message: String)

# @export var server_url := "ws://localhost:8787"
@export var server_url := "wss://online-server.v-s-on.workers.dev"

# const ROOM_CODE_CHARACTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


var socket := WebSocketPeer.new()
var room_code := ""
var _was_open := false
var _reported_closed := true

func create_room(code: String) -> void:
	var normalized_code := code.strip_edges()

	if not _is_valid_room_code(normalized_code):
		network_error.emit("Enter a 6-digit room code.")
		return

	_connect_to_room(normalized_code, "create")


func join_room(code: String) -> void:
	var normalized_code := code.strip_edges()

	if not _is_valid_room_code(normalized_code):
		network_error.emit("Enter a 6-digit room code.")
		return

	_connect_to_room(normalized_code, "join")


func _is_valid_room_code(code: String) -> bool:
	return code.length() == 6 and code.is_valid_int()

func _ready() -> void:
	pass


func send_game_message(payload: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		network_error.emit("Not connected to a room.")
		return

	socket.send_text(JSON.stringify({
		"type": "game_message",
		"payload": payload
	}))


func _process(_delta: float) -> void:
	socket.poll()

	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_was_open = true
		while (
			not _reported_closed
			and socket.get_ready_state() == WebSocketPeer.STATE_OPEN
			and socket.get_available_packet_count() > 0
		):
			var packet := socket.get_packet()
			var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())

			if typeof(parsed) != TYPE_DICTIONARY:
				network_error.emit("Received an invalid message from the server.")
				continue

			_handle_server_message(parsed)


	elif socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		set_process(false)

		if _reported_closed:
			return

		_reported_closed = true

		if socket.get_close_code() == 4001:
			opponent_disconnected.emit()
		elif _was_open:
			connection_closed.emit()
		else:
			network_error.emit(
				"Could not join that room. Check the code and try again."
			)

func _connect_to_room(code: String, action: String) -> void:
	socket = WebSocketPeer.new()
	room_code = code
	_was_open = false
	_reported_closed = false

	var url := "%s/ws/%s/%s" % [server_url.trim_suffix("/"), code, action]
	var error := socket.connect_to_url(url)

	if error != OK:
		_reported_closed = true
		network_error.emit("Could not start the connection.")
		return

	set_process(true)

func leave_room() -> void:
	# An intentional departure should not trigger an error message.
	_reported_closed = true
	room_code = ""

	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close(1000, "Player left")
		set_process(true)

func _handle_server_message(message: Dictionary) -> void:
	match message.get("type", ""):
		"room_created":
			room_code = str(message.get("code", ""))
			room_created.emit(room_code)
		"room_joined":
			room_code = str(message.get("code", ""))
			room_joined.emit(room_code)
		"opponent_joined":
			opponent_joined.emit()
		"game_message":
			game_message_received.emit(
				message.get("payload", {}),
				int(message.get("from_player", 0))
			)
		"opponent_disconnected":
			if not _reported_closed:
				_reported_closed = true
				opponent_disconnected.emit()

		"error":
			network_error.emit(str(message.get("message", "Server error.")))


# func _make_room_code() -> String:
# 	var code := ""

# 	for _index in range(6):
# 		var character_index := _random.randi_range(
# 			0,
# 			ROOM_CODE_CHARACTERS.length() - 1
# 		)
# 		code += ROOM_CODE_CHARACTERS.substr(character_index, 1)

# 	return code
