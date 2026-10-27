extends Node2D

var board: Board
var effects: Node2D


var fog_material: ShaderMaterial

func _ready() -> void:
	fog_material = ShaderMaterial.new()
	fog_material.shader = preload("res://unseen_board.gdshader")

	AppSettings.settings_changed.connect(_apply_graphics_settings)
	_apply_graphics_settings()


func _apply_graphics_settings() -> void:
	if AppSettings.low_graphics:
		material = null
		self_modulate = Color(0.12, 0.15, 0.22, 0.65)
	else:
		material = fog_material
		self_modulate = Color.WHITE

	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(board):
		return

	if not is_instance_valid(effects):
		return

	if not effects.started or effects.assembling:
		return

	if not board.game_setup_complete:
		return

	var viewer: int = effects._viewer()

	for cell in board.board_tiles:
		if board.hasCellInVision(viewer, cell):
			continue

		var polygon: PackedVector2Array = effects._tile_polygon(cell)

		# Fill the complete hexagon without changing other effects.
		var center: Vector2 = board.map_to_local(cell)

		for i in range(polygon.size()):
			polygon[i] = center + (polygon[i] - center) / 0.94

		draw_colored_polygon(polygon, Color.WHITE)