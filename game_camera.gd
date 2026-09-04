extends Camera2D


@export var board: TileMapLayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	position = board.map_to_local(
		board.board_center
	)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


# Camera Movement
var dragging = false
var drag_start_mouse = Vector2(0,0)
var drag_start_position = Vector2(0,0)

#Touch
var touches: Dictionary = {}
var previous_pinch_distance := 0.0
const MIN_ZOOM := 0.4
const MAX_ZOOM := 2.0

#--------TEST Values Touch Pinch
# PC pinch testing
var test_pinch := false
var test_finger_offset := Vector2(200, 0)
var test_previous_distance := 0.0
#---------

func _unhandled_input(event):
	# Mouse Controls
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_to_mouse(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_to_mouse(0.9)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			#-----More Test Touch Pinch
			if event.pressed:
				test_pinch = true
				test_previous_distance = 0.0
			else:
				test_pinch = false
			#-----More Test Touch Pinch

		# 	if event.pressed:
		# 		print("At dragging")
		# 		dragging = true
		# 		drag_start_mouse = get_global_mouse_position()  # current tile cell
		# 		drag_start_position = position
		# 	else:
		# 		dragging = false

	elif event is InputEventMouseMotion and dragging:
		var current_mouse = get_global_mouse_position()
		print(["move", current_mouse, drag_start_mouse, drag_start_position])
		var drag_target = drag_start_position - (current_mouse - drag_start_mouse)
		position = position.lerp(drag_target, 0.5)

	#-----More Test Touch Pinch
	elif event is InputEventMouseMotion:
		if test_pinch:
			var finger1 = event.position
			var finger2 = event.position + Vector2(
				200.0 + event.position.y,
				0
			)

			var current_distance = finger1.distance_to(finger2)

			if test_previous_distance > 0:
				var difference = current_distance - test_previous_distance
				var factor = 1.0 + difference * 0.005

				print("Fake pinch: ", current_distance, " factor: ", factor)

				_zoom_to_point(
					factor,
					(finger1 + finger2) / 2.0
				)

			test_previous_distance = current_distance
	#-----------------

	# Single Touch
	elif event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			# Start pinch tracking
			if touches.size() == 2:
				var positions = touches.values()
				previous_pinch_distance = positions[0].distance_to(positions[1])
		else:
			touches.erase(event.index)
	# Touch Drag/Pinch
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		
		# Two fingers = pinch zoom
		if touches.size() == 2:
			print("Pinch zoom")
			var positions = touches.values()
			var current_distance = positions[0].distance_to(
				positions[1]
			)
			if previous_pinch_distance > 0:
				var difference = current_distance \
					- previous_pinch_distance

				var factor = 1.0 + difference * 0.003

				_zoom_to_point(
					factor,
					(positions[0] + positions[1]) / 2.0
				)

			previous_pinch_distance = current_distance

		# One finger = pan
		elif touches.size() == 1:
			var delta = event.relative
			position -= delta / zoom.x

# =====================================
# Zoom around mouse
# =====================================

func _zoom_to_mouse(factor: float):

	var mouse_screen = get_global_mouse_position()

	_zoom_to_point(factor, mouse_screen)


# =====================================
# Zoom around screen point
# =====================================

func _zoom_to_point(factor: float, screen_point: Vector2):
	var old_zoom = zoom.x

	var new_zoom = clamp(
		old_zoom * factor,
		MIN_ZOOM,
		MAX_ZOOM
	)

	factor = new_zoom / old_zoom

	var viewport = get_viewport()

	var world_before = viewport.get_canvas_transform().affine_inverse() * screen_point

	zoom = Vector2(new_zoom, new_zoom)

	var world_after = viewport.get_canvas_transform().affine_inverse() * screen_point

	position += world_before - world_after