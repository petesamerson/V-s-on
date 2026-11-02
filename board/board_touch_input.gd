extends Node

@export var drag_threshold: float = 16.0

@onready var board: Board = get_parent() as Board

const MOUSE_POINTER_ID: int = -100
var next_touch_token: int = 0

# All physical fingers, including fingers that started over UI.
var physical_touches: Dictionary = {}

# Only fingers whose presses reached the board.
var board_touches: Dictionary = {}
var touch_tokens: Dictionary = {}

var tap_finger: int = -1
var tap_origin := Vector2.ZERO
var tap_cancelled: bool = false
var multi_touch: bool = false
var panning: bool = false

func _input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return

	# Switching to right/middle drag cancels any pending left-click.
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [
			MOUSE_BUTTON_RIGHT,
			MOUSE_BUTTON_MIDDLE,
		]:
			tap_cancelled = true

	event = _as_pointer_event(event)
	# Observe gestures here without consuming UI input.
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			if physical_touches.is_empty():
				_reset_gesture()

			next_touch_token += 1
			physical_touches[event.index] = next_touch_token

			if physical_touches.size() > 1:
				multi_touch = true
				tap_cancelled = true
		else:
			var token: Variant = physical_touches.get(event.index)
			physical_touches.erase(event.index)

			if event.canceled:
				tap_cancelled = true

			# If UI consumes the release, still remove the finger.
			call_deferred("_cleanup_release", event.index, token)

	elif event is InputEventScreenDrag:
		if event.index == tap_finger:
			if event.position.distance_to(tap_origin) > drag_threshold:
				tap_cancelled = true


func _unhandled_input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return

	event = _as_pointer_event(event)

	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			board_touches[event.index] = event.position
			touch_tokens[event.index] = physical_touches.get(event.index)

			if physical_touches.size() == 1 and not multi_touch:
				tap_finger = event.index
				tap_origin = event.position

			board.camera.interrupt_auto_camera()
			get_viewport().set_input_as_handled()
			return

		if not board_touches.has(event.index):
			return

		var confirmed_tap: bool = (
			event.index == tap_finger
			and not event.canceled
			and not tap_cancelled
			and not multi_touch
			and event.position.distance_to(tap_origin) <= drag_threshold
		)

		board_touches.erase(event.index)
		touch_tokens.erase(event.index)
		get_viewport().set_input_as_handled()

		if physical_touches.is_empty():
			_reset_gesture()

		if confirmed_tap:
			board.handle_touch_tap(event.position)

	elif event is InputEventScreenDrag:
		if not board_touches.has(event.index):
			return

		var old_positions: Array = board_touches.values()
		board_touches[event.index] = event.position

		if board_touches.size() == 2 and physical_touches.size() == 2:
			multi_touch = true
			tap_cancelled = true

			var new_positions: Array = board_touches.values()
			var old_a: Vector2 = old_positions[0]
			var old_b: Vector2 = old_positions[1]
			var new_a: Vector2 = new_positions[0]
			var new_b: Vector2 = new_positions[1]

			var old_distance: float = old_a.distance_to(old_b)
			var new_distance: float = new_a.distance_to(new_b)
			var old_center: Vector2 = (old_a + old_b) * 0.5
			var new_center: Vector2 = (new_a + new_b) * 0.5

			board.camera._pan_camera(new_center - old_center)

			if old_distance > 1.0 and new_distance > 1.0:
				board.camera._zoom_to_point(
					new_distance / old_distance,
					new_center
				)

		elif (
			board_touches.size() == 1
			and not multi_touch
			and event.index == tap_finger
		):
			if event.position.distance_to(tap_origin) > drag_threshold:
				panning = true
				tap_cancelled = true

			if panning:
				board.camera._pan_camera(event.relative)

		get_viewport().set_input_as_handled()

func _as_pointer_event(event: InputEvent) -> InputEvent:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var touch := InputEventScreenTouch.new()
			touch.device = event.device
			touch.index = MOUSE_POINTER_ID
			touch.position = event.position
			touch.pressed = event.pressed
			return touch

	elif event is InputEventMouseMotion:
		# Let the camera handle right/middle dragging.
		if (
			event.button_mask
			& (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)
		) != 0:
			return event

		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var drag := InputEventScreenDrag.new()
			drag.device = event.device
			drag.index = MOUSE_POINTER_ID
			drag.position = event.position
			drag.relative = event.relative
			return drag

	return event


func _cleanup_release(index: int, token: Variant) -> void:
	# A reused finger index must not erase a newer touch.
	if touch_tokens.has(index) and touch_tokens[index] == token:
		board_touches.erase(index)
		touch_tokens.erase(index)

	if physical_touches.is_empty():
		_reset_gesture()


func _reset_gesture() -> void:
	board_touches.clear()
	touch_tokens.clear()
	tap_finger = -1
	tap_cancelled = false
	multi_touch = false
	panning = false


func _notification(what: int) -> void:
	if what in [
		NOTIFICATION_APPLICATION_FOCUS_OUT,
		NOTIFICATION_APPLICATION_PAUSED,
	]:
		physical_touches.clear()
		_reset_gesture()