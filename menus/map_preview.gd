extends Node2D

var outline_color := Color.WHITE
var outline_width := 30.0
var ground_color := Color("#000000")
var wall_color := Color("#FFFFFF")
var spawn_color := Color("#00ffff")

var tile_size := Vector2(100, 100)
var ground_positions: Array[Vector2] = []
var wall_positions: Array[Vector2] = []
var spawn_positions: Array[Vector2] = []

var bounds := Rect2()


func configure(map: PlayableMap) -> void:
	ground_positions.clear()
	wall_positions.clear()
	spawn_positions.clear()

	var ground := map.ground
	var walls := map.walls
	tile_size = Vector2(ground.tile_set.tile_size)

	# Convert everything into the map root's coordinate space.
	for cell in ground.get_used_cells():
		ground_positions.append(
			ground.transform * ground.map_to_local(cell)
		)

	for cell in walls.get_used_cells():
		wall_positions.append(
			walls.transform * walls.map_to_local(cell)
		)

	for child in map.spawns.get_children():
		if child is Marker2D:
			spawn_positions.append(
				map.spawns.transform * child.position
			)

	var positions: Array[Vector2] = []
	positions.append_array(ground_positions)
	positions.append_array(wall_positions)
	positions.append_array(spawn_positions)

	bounds = Rect2()

	if not positions.is_empty():
		bounds = Rect2(positions[0], Vector2.ZERO)

		for point in positions:
			bounds = bounds.expand(point)

		bounds.position -= tile_size * 0.5
		bounds.size += tile_size

	queue_redraw()


func _draw() -> void:
	for point in ground_positions:
		draw_colored_polygon(_hexagon(point), ground_color)

	for point in wall_positions:
		draw_colored_polygon(_hexagon(point), wall_color)

	var dot_radius := minf(tile_size.x, tile_size.y) * 0.3

	for point in spawn_positions:
		draw_circle(
			point,
			dot_radius * 1.5,
			wall_color,
			true,
			-1.0,
			true
		)
		draw_circle(
			point,
			dot_radius,
			spawn_color,
			true,
			-1.0,
			true
		)

	_draw_map_outline()


func _hexagon(center: Vector2) -> PackedVector2Array:
	var half := tile_size * 0.5 

	return PackedVector2Array([
		center + Vector2(0, -half.y),
		center + Vector2(half.x, -half.y * 0.5),
		center + Vector2(half.x, half.y * 0.5),
		center + Vector2(0, half.y),
		center + Vector2(-half.x, half.y * 0.5),
		center + Vector2(-half.x, -half.y * 0.5),
	])


func _draw_map_outline() -> void:
	var edges: Dictionary = {}
	var positions: Dictionary = {}

	# A wall may overlap ground, so count each position only once.
	for point in ground_positions + wall_positions:
		positions[Vector2i(
			roundi(point.x * 100),
			roundi(point.y * 100)
		)] = point

	for point in positions.values():
		var corners := _outline_hexagon(point)

		for i in range(6):
			var a := corners[i]
			var b := corners[(i + 1) % 6]

			var first := Vector2i(
				roundi(a.x * 100),
				roundi(a.y * 100)
			)
			var second := Vector2i(
				roundi(b.x * 100),
				roundi(b.y * 100)
			)

			# Give a shared edge the same key in either direction.
			if (
				first.x > second.x
				or (first.x == second.x and first.y > second.y)
			):
				var temporary := first
				first = second
				second = temporary

			var key := Vector4i(
				first.x, first.y, second.x, second.y
			)

			if edges.has(key):
				edges[key]["count"] += 1
			else:
				edges[key] = {"a": a, "b": b, "count": 1}

	for edge in edges.values():
		if edge["count"] == 1:
			draw_line(
				edge["a"],
				edge["b"],
				outline_color,
				outline_width,
				true
			)


func _outline_hexagon(center: Vector2) -> PackedVector2Array:
	# Full-size corners so neighboring tiles share edges.
	var half := tile_size * 0.5

	return PackedVector2Array([
		center + Vector2(0, -half.y),
		center + Vector2(half.x, -half.y * 0.5),
		center + Vector2(half.x, half.y * 0.5),
		center + Vector2(0, half.y),
		center + Vector2(-half.x, half.y * 0.5),
		center + Vector2(-half.x, -half.y * 0.5),
	])