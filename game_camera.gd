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


var dragging = false
var drag_start_mouse = Vector2(0,0)
var drag_start_position = Vector2(0,0)
func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom *= 1.1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom *= 0.9
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				print("At dragging")
				dragging = true
				drag_start_mouse = get_global_mouse_position()  # current tile cell
				drag_start_position = position
			else:
				dragging = false
	elif event is InputEventMouseMotion and dragging:
		var current_mouse = get_global_mouse_position()
		print(["move",current_mouse,drag_start_mouse, drag_start_position])
		position = drag_start_position + (current_mouse - drag_start_mouse)
				