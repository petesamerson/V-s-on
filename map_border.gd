extends Node2D

@export var border_color := Color("#FFFFFF")
@export var border_width: float = 6.0

var board: Board
var edges: Array = []


func rebuild() -> void:
	edges.clear()

	var occupied: Dictionary = {}
	for cell in board.board_tiles:
		occupied[cell] = true

	for cell in occupied:
		var points: PackedVector2Array = board.board_effects._tile_polygon(cell)
		var center: Vector2 = board.map_to_local(cell)

		for i in range(points.size()):
			points[i] = center + (points[i] - center) / 0.94

		for i in range(points.size()):
			var a: Vector2 = points[i]
			var b: Vector2 = points[(i + 1) % points.size()]
			var midpoint: Vector2 = (a + b) * 0.5
			var outward: Vector2 = (midpoint - center).normalized()

			# Sample just beyond this edge to identify its neighboring cell.
			var neighbor: Vector2i = board.local_to_map(
				midpoint + outward * 2.0
			)

			if not occupied.has(neighbor):
				edges.append({"a": a, "b": b})

	queue_redraw()

func _draw() -> void:
	for edge in edges:
		draw_line(
			edge["a"], edge["b"],
			Color(border_color, 0.12),
			border_width * 3.0, true
		)
		draw_line(
			edge["a"], edge["b"],
			border_color, border_width, true
		)