extends Node2D


@export var board: TileMapLayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	position = board.map_to_local(Vector2i(5, 5))
	$Area2D.input_event.connect(_on_area_2d_input_event)
	self.z_index = 1


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_area_2d_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed:
		var cell = board.local_to_map(position)  # current tile cell
		print("Current cell:", cell)
		var new_cell = cell + Vector2i(1, 0)
		position = board.map_to_local(new_cell)
		
		board.set_cell(cell, 0, Vector2i(0, 0))

		board.draw_vision_range(
			new_cell,
			3
		)