extends Camera2D


@export var board: TileMapLayer

var is_mobile_browser: bool

func _ready() -> void:
	is_mobile_browser = (
		OS.has_feature("android") \
		or OS.has_feature("ios") \
		or OS.has_feature("web_android") \
		or OS.has_feature("web_ios")
	)
	global_position = board.to_global(
		board.map_to_local(board.board_center)
	)
	position_smoothing_enabled = false
	call_deferred("rebuild_map_bounds")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	_clamp_to_map()
	pass

# Camera Movement
var dragging = false
var drag_start_mouse = Vector2(0,0)
var drag_start_position = Vector2(0,0)
var wasPinched := false

#Touch
var touches: Dictionary = {}
var previous_pinch_distance := 0.0
const MIN_ZOOM := 0.4
const MAX_ZOOM := 3.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture and not is_mobile_browser:
		_zoom_to_point(event.factor, event.position)
		get_viewport().set_input_as_handled()

	elif event is InputEventPanGesture and not is_mobile_browser:
		_pan_camera(-event.delta * 20.0)
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and not is_mobile_browser:
		if event.button_index in [
			MOUSE_BUTTON_RIGHT,
			MOUSE_BUTTON_MIDDLE,
		]:
			dragging = event.pressed

			if dragging:
				interrupt_auto_camera()

			get_viewport().set_input_as_handled()

		elif event.pressed:
			var wheel_steps = event.factor
			if wheel_steps <= 0.0:
				wheel_steps = 1.0

			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_to_point(
					pow(1.1, wheel_steps),
					event.position
				)
				get_viewport().set_input_as_handled()

			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_to_point(
					pow(1.1, -wheel_steps),
					event.position
				)
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and not is_mobile_browser:
		if dragging:
			_pan_camera(event.relative)
			get_viewport().set_input_as_handled()

	# # Single Touch
	# elif event is InputEventScreenTouch:
	# 	if event.pressed:
	# 		touches[event.index] = event.position
	# 		# Start pinch tracking
	# 		if touches.size() == 2:
	# 			wasPinched = true
	# 			var positions = touches.values()
	# 			previous_pinch_distance = positions[0].distance_to(positions[1])
	# 	else:
	# 		touches.erase(event.index)
	# 		if touches.is_empty():
	# 			wasPinched = false
	# 			previous_pinch_distance = 0.0
	# # Touch Drag/Pinch
	# elif event is InputEventScreenDrag:
	# 	if not touches.has(event.index):
	# 		return

	# 	touches[event.index] = event.position
		
	# 	# Two fingers = pinch zoom
	# 	if touches.size() == 2:
	# 		wasPinched = true
	# 		var positions = touches.values()
	# 		var current_distance = positions[0].distance_to(
	# 			positions[1]
	# 		)
	# 		if previous_pinch_distance > 0:
	# 			var factor = current_distance / previous_pinch_distance

	# 			_zoom_to_point(
	# 				factor,
	# 				(positions[0] + positions[1]) / 2.0
	# 			)

	# 		previous_pinch_distance = current_distance

	# 	elif touches.size() == 1 and not wasPinched:
	# 		_pan_camera(event.relative)


func _pan_camera(screen_delta: Vector2) -> void:
	interrupt_auto_camera()
	global_position -= screen_delta / zoom
	_clamp_to_map()
	force_update_scroll()

func _input(event: InputEvent) -> void:
	# Observe releases even when a UI control consumes them.
	# Do not mark these events handled here.
	if event is InputEventMouseButton:
		if not event.pressed and event.button_index in [
			MOUSE_BUTTON_RIGHT,
			MOUSE_BUTTON_MIDDLE,
		]:
			dragging = false

	elif event is InputEventScreenTouch:
		if not event.pressed:
			touches.erase(event.index)
			previous_pinch_distance = 0.0

			if touches.is_empty():
				wasPinched = false


func _notification(what: int) -> void:
	if what in [
		NOTIFICATION_APPLICATION_FOCUS_OUT,
		NOTIFICATION_APPLICATION_PAUSED,
	]:
		dragging = false
		touches.clear()
		previous_pinch_distance = 0.0
		wasPinched = false
		interrupt_auto_camera()
# =====================================
# Zoom around mouse
# =====================================


func _zoom_to_mouse(factor: float) -> void:
	_zoom_to_point(factor, get_viewport().get_mouse_position())

# =====================================
# Zoom around screen point
# =====================================

func _zoom_to_point(
	factor: float,
	screen_point: Vector2
) -> void:
	if factor <= 0.0:
		return

	interrupt_auto_camera()

	var new_zoom := clampf(
		zoom.x * factor,
		MIN_ZOOM,
		MAX_ZOOM
	)

	if is_equal_approx(new_zoom, zoom.x):
		return

	var viewport := get_viewport()

	force_update_scroll()
	var world_before := (
		viewport.get_canvas_transform().affine_inverse()
		* screen_point
	)

	zoom = Vector2.ONE * new_zoom
	force_update_scroll()

	var world_after := (
		viewport.get_canvas_transform().affine_inverse()
		* screen_point
	)

	global_position += world_before - world_after
	_clamp_to_map()
	force_update_scroll()

var _auto_camera_sequence: int = 0
var _auto_camera_interrupted: bool = false
var _auto_camera_tween: Tween


func begin_auto_camera_sequence() -> int:
	_stop_auto_camera_tween()
	_auto_camera_sequence += 1
	_auto_camera_interrupted = false
	return _auto_camera_sequence


func interrupt_auto_camera() -> void:
	_auto_camera_interrupted = true
	_auto_camera_sequence += 1
	_stop_auto_camera_tween()


func _stop_auto_camera_tween() -> void:
	if _auto_camera_tween != null and _auto_camera_tween.is_valid():
		_auto_camera_tween.kill()

	_auto_camera_tween = null


func zoom_to_global_position(
	target_position: Vector2,
	target_zoom: float,
	sequence_id: int = -1
) -> void:
	if not is_inside_tree():
		return
	if sequence_id < 0:
		sequence_id = _auto_camera_sequence

	if _auto_camera_interrupted or sequence_id != _auto_camera_sequence:
		return

	_stop_auto_camera_tween()

	var tween := create_tween()
	_auto_camera_tween = tween
	tween.set_parallel(true)

	tween.tween_property(
		self,
		"global_position",
		target_position,
		1.5
	)

	tween.tween_property(
		self,
		"zoom",
		Vector2(target_zoom, target_zoom),
		1.5
	)

	# Cancellation also releases any Board function awaiting this move.
	while (
		is_inside_tree()
		and sequence_id == _auto_camera_sequence
		and _auto_camera_tween == tween
		and tween.is_valid()
		and tween.is_running()
	):
		var tree := get_tree()
		if tree == null:
			break

		await tree.process_frame

	if _auto_camera_tween == tween:
		_auto_camera_tween = null

func _exit_tree() -> void:
	interrupt_auto_camera()

@export var map_camera_padding: float = 800.0

var map_bounds := Rect2()
var map_bounds_ready: bool = false


func rebuild_map_bounds() -> void:
	map_bounds_ready = false

	for cell in board.board_tiles:
		var center: Vector2 = board.map_to_local(cell)
		var half_tile: Vector2 = Vector2(board.tile_set.tile_size) * 0.5

		for corner in [
			Vector2(-1, -1),
			Vector2(1, -1),
			Vector2(1, 1),
			Vector2(-1, 1),
		]:
			var point: Vector2 = board.to_global(center + corner * half_tile)
			if not map_bounds_ready:
				map_bounds = Rect2(point, Vector2.ZERO)
				map_bounds_ready = true
			else:
				map_bounds = map_bounds.expand(point)

	_clamp_to_map()


func _clamp_to_map() -> void:
	if not map_bounds_ready:
		return

	var bounds := map_bounds.grow(map_camera_padding)
	var half_view := get_viewport_rect().size * 0.5 / zoom
	var midpoint := bounds.get_center()

	# When the map fits on an axis, keep that axis centered.
	var travel := Vector2(
		maxf(bounds.size.x * 0.5 - half_view.x, 0.0),
		maxf(bounds.size.y * 0.5 - half_view.y, 0.0)
	)

	global_position = Vector2(
		clampf(global_position.x, midpoint.x - travel.x, midpoint.x + travel.x),
		clampf(global_position.y, midpoint.y - travel.y, midpoint.y + travel.y)
	)
