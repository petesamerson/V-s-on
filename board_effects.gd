extends Node2D

const GameColors = preload("res://colors.gd")

var board: Board
var started: bool = false
var assembling: bool = false

var discoveries: Dictionary = {}
var discovery_nodes: Array[Sprite2D] = []
var last_viewer: int = -1
var check_timer: float = 0.0

var effect_time: float = 0.0
var effect_visible: Dictionary = {}

var last_move_by_viewer: Dictionary = {}

@export var vision_loss_duration: float = 1.4

var tile_snapshots: Dictionary = {}
var fading_tiles: Dictionary = {}

@export var visible_effect_strength: float = 0.14
@export var selected_effect_strength: float = 0.22
@export var powered_effect_strength: float = 0.22

@export var enemy_overlap_strength: float = 0.18
@export var enemy_overlap_speed: float = 0.65
@export var enemy_powered_effect_strength: float = 0.24

func _viewer() -> int:
	if board.online_game:
		return board.local_player

	if board.cpu_player != null:
		return 3 - board.cpu_player.player_number

	return board.current_player


func _visible_cells(viewer: int) -> Dictionary:
	var cells: Dictionary = {}

	for node in board.player_pieces[viewer - 1]:
		var piece := node as Piece

		for cell in piece.cur_vision:
			if board.cell_in_board(cell):
				cells[cell] = true

	return cells


func _tile_parts(cell: Vector2i) -> Array[Dictionary]:
	var layers: Array[TileMapLayer] = [board]

	for group in [
		board.player_fills,
		board.player_powered_fills,
		board.player_outlines,
		board.player_move_fills,
		board.player_selected_outlines
	]:
		for layer in group:
			layers.append(layer)

	var parts: Array[Dictionary] = []

	for layer in layers:
		var source_id := layer.get_cell_source_id(cell)
		if source_id < 0:
			continue

		var source := layer.tile_set.get_source(
			source_id
		) as TileSetAtlasSource

		if source == null:
			continue

		var atlas := AtlasTexture.new()
		atlas.atlas = source.texture
		atlas.region = source.get_tile_texture_region(
			layer.get_cell_atlas_coords(cell)
		)

		var offset := Vector2.ZERO
		var data := layer.get_cell_tile_data(cell)
		var tint := layer.modulate

		if data != null:
			offset = Vector2(data.texture_origin)
			tint *= data.modulate

		parts.append({
			"texture": atlas,
			"offset": offset,
			"color": tint
		})

	return parts


func _visual_from_parts(
	cell: Vector2i,
	parts: Array
) -> Sprite2D:
	var visual := Sprite2D.new()
	visual.position = board.map_to_local(cell)

	for part in parts:
		var sprite := Sprite2D.new()
		sprite.texture = part["texture"]
		sprite.position = part["offset"]
		sprite.modulate = part["color"]
		visual.add_child(sprite)

	add_child(visual)
	return visual


func _tile_copy(cell: Vector2i) -> Sprite2D:
	var parts := _tile_parts(cell)

	if parts.is_empty():
		return null

	return _visual_from_parts(cell, parts)


func play_setup() -> void:
	if started:
		return

	started = true
	assembling = true

	var fog = preload("res://unseen_board_effect.gd").new()
	fog.name = "UnseenBoardMist"
	fog.board = board
	fog.effects = self
	add_child(fog)

	var viewer: int = _viewer()
	last_viewer = viewer
	discoveries[viewer] = _visible_cells(viewer)

	var original_tile_color: Color = board.self_modulate
	var original_piece_color: Color = (
		board.pieces_container.modulate
	)

	# self_modulate hides only the board's own tile drawing.
	# Its child effects remain visible.
	board.self_modulate = Color(original_tile_color, 0.0)
	board.pieces_container.modulate = Color(
		original_piece_color,
		0.0
	)

	var center: Vector2 = board.map_to_local(board.board_center)
	var furthest: float = 1.0

	for cell in board.board_tiles:
		furthest = maxf(
			furthest,
			center.distance_to(board.map_to_local(cell))
		)

	var setup_tiles: Array[Sprite2D] = []

	for cell in board.board_tiles:
		var visual: Sprite2D = _tile_copy(cell)

		if visual == null:
			continue

		setup_tiles.append(visual)

		var distance: float = center.distance_to(visual.position)
		var delay: float = distance / furthest * 0.9

		visual.scale = Vector2.ONE * 0.65
		visual.modulate.a = 0.0

		var tween := create_tween()
		tween.set_parallel(true)

		tween.tween_property(
			visual,
			"scale",
			Vector2.ONE,
			0.5
		).set_delay(delay).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_OUT)

		tween.tween_property(
			visual,
			"modulate:a",
			1.0,
			0.45
		).set_delay(delay)

	var highlight_layers: Array[TileMapLayer] = []

	for group in [
		board.player_fills,
		board.player_powered_fills,
		board.player_outlines,
		board.player_move_fills,
		board.player_selected_outlines
	]:
		for layer in group:
			highlight_layers.append(layer)
			layer.self_modulate.a = 0.0

	var piece_tween := create_tween()

	piece_tween.tween_property(
		board.pieces_container,
		"modulate",
		original_piece_color,
		0.6
	).set_delay(0.65)

	var finish := create_tween()
	finish.tween_interval(1.5)

	finish.tween_callback(
		func():
			board.self_modulate = original_tile_color

			for layer in highlight_layers:
				layer.self_modulate.a = 1.0

			for visual in setup_tiles:
				if is_instance_valid(visual):
					visual.queue_free()

			assembling = false
	)


func _process(delta: float) -> void:
	effect_time += delta
	queue_redraw()

	if not started or assembling:
		return

	if not is_instance_valid(board):
		return

	if not board.game_setup_complete:
		return

	# Ignore the temporary CPU perspective during its turn.
	if (
		board.cpu_player != null
		and board.current_player == board.cpu_player.player_number
	):
		return

	check_timer += delta

	if check_timer < 0.08:
		return

	check_timer = 0.0

	var viewer: int = _viewer()
	var visible: Dictionary = _visible_cells(viewer)
	effect_visible = visible

	if viewer != last_viewer:
		_clear_vision_fades()
		# Clear the previous player's visual effects.
		for visual in discovery_nodes:
			if is_instance_valid(visual):
				visual.queue_free()

		discovery_nodes.clear()
		last_viewer = viewer

		# Switching seats should not replay the whole board.
		var previous: Dictionary = discoveries.get(viewer, {})
		previous.merge(visible, true)
		discoveries[viewer] = previous
		return

	_update_vision_fades(visible)
	var seen: Dictionary = discoveries.get(viewer, {})

	for cell in visible:
		if seen.has(cell):
			continue

		seen[cell] = true
		_play_discovery(cell, viewer)

	discoveries[viewer] = seen

	discovery_nodes = discovery_nodes.filter(
		func(visual): return is_instance_valid(visual)
	)


func _play_discovery(cell: Vector2i, viewer: int) -> void:
	if AppSettings.low_graphics:
		return
	var visual: Sprite2D = _tile_copy(cell)

	if visual == null:
		return

	discovery_nodes.append(visual)

	var resting_position: Vector2 = visual.position

	visual.position.y -= 8.0
	visual.scale = Vector2.ONE * 1.08
	visual.modulate = Color(1.5, 1.5, 1.5, 0.85)

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		visual,
		"position",
		resting_position,
		0.35
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	tween.tween_property(
		visual,
		"scale",
		Vector2.ONE,
		0.35
	)

	tween.tween_property(
		visual,
		"modulate:a",
		0.0,
		0.45
	)

	tween.chain().tween_callback(visual.queue_free)


func _tile_polygon(cell: Vector2i) -> PackedVector2Array:
	var center: Vector2 = board.map_to_local(cell)
	var size := Vector2(board.tile_set.tile_size)

	# Hexagons matching the board's tile offset axis.
	var corners := PackedVector2Array([
		Vector2(0.0, -0.5),
		Vector2(0.5, -0.25),
		Vector2(0.5, 0.25),
		Vector2(0.0, 0.5),
		Vector2(-0.5, 0.25),
		Vector2(-0.5, -0.25),
	])

	if board.tile_set.tile_offset_axis == 1:
		corners = PackedVector2Array([
			Vector2(-0.5, 0.0),
			Vector2(-0.25, -0.5),
			Vector2(0.25, -0.5),
			Vector2(0.5, 0.0),
			Vector2(0.25, 0.5),
			Vector2(-0.25, 0.5),
		])

	var points := PackedVector2Array()

	for corner in corners:
		points.append(center + corner * size * 0.94)

	return points


func _draw() -> void:
	if not is_instance_valid(board):
		return

	if not started or assembling or not board.game_setup_complete:
		return

	# # Do not draw from the temporary CPU perspective.
	# if (
	# 	board.cpu_player != null
	# 	and board.current_player == board.cpu_player.player_number
	# ):
	# 	return

	var viewer: int = _viewer()

	# Wait for the visibility cache after a player switch.
	if viewer != last_viewer:
		return
	
	_draw_last_move(viewer)

	var player_color: Color = GameColors.player_color(viewer)
	var selected_piece: Piece = null

	for node in board.player_pieces[viewer - 1]:
		var candidate := node as Piece

		if candidate.selected:
			selected_piece = candidate
			break

	var selected_vision: Dictionary = {}
	var powered_vision: Dictionary = {}
	var powered_color: Color = GameColors.powered_color(viewer)

	for node in board.player_pieces[viewer - 1]:
		var piece := node as Piece
		if piece.powered:
			for cell in piece.cur_vision:
				powered_vision[cell] = true

	if selected_piece != null:
		for cell in selected_piece.cur_vision:
			selected_vision[cell] = true

	var enemy_vision := _enemy_vision_cells(viewer)

	for cell in effect_visible:
		# Never leave an effect on a tile that has lost vision.
		if not board.hasCellInVision(viewer, cell):
			continue
		
		# Enemy-covered tiles receive only the enemy ambient animation.
		if enemy_vision.has(cell):
			continue

		var points: PackedVector2Array = _tile_polygon(cell)
		var center: Vector2 = board.map_to_local(cell)

		_draw_tile_glint(
			points,
			player_color,
			selected_vision.has(cell),
			center.y * 0.002
		)

		if powered_vision.has(cell):
			_draw_powered_vision(points, center, powered_color)

		if selected_vision.has(cell):
			# A soft wave travels outward from the selected piece.
			var distance: float = center.distance_to(
				selected_piece.position
			)

			var wave: float = (
				0.5
				+ 0.5 * sin(
					effect_time * 2.0 - distance * 0.035
				)
			)

			var alpha: float = (
				selected_effect_strength
				* lerpf(0.4, 1.0, wave)
			)

			draw_colored_polygon(
				points,
				Color(player_color, alpha)
			)

			# A restrained outline distinguishes selected vision
			# from the rest of the visible board.
			var outline := points.duplicate()
			outline.append(points[0])

			draw_polyline(
				outline,
				Color(player_color, alpha * 2.0),
				1.25,
				true
			)
		elif not powered_vision.has(cell):
			# A slower diagonal wash across ordinary visible tiles.
			var phase: float = (
				effect_time * 1.1
				- center.x * 0.006
				- center.y * 0.004
			)

			var alpha: float = (
				visible_effect_strength
				* (0.55 + 0.45 * sin(phase))
			)

			draw_colored_polygon(
				points,
				Color(player_color, alpha)
			)
	_draw_enemy_overlap(viewer)

func _draw_powered_vision(
	points: PackedVector2Array,
	center: Vector2,
	tint: Color
) -> void:
	# A shared rhythm makes the powered area read as one energized field.
	var cycle: float = fposmod(effect_time * 0.65, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(effect_time * TAU * 0.65)
	var alpha: float = powered_effect_strength * lerpf(0.45, 1.0, pulse)
	draw_colored_polygon(points, Color(tint, alpha))

	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(tint, alpha * 1.5), 2.0, true)

	# An expanding inset hex adds motion distinct from ordinary vision's wash.
	var ring := PackedVector2Array()
	for point in points:
		ring.append(center + (point - center) * lerpf(0.35, 0.96, cycle))
	ring.append(ring[0])
	var ring_alpha: float = powered_effect_strength * sin(cycle * PI)
	draw_polyline(ring, Color(tint.lerp(Color.WHITE, 0.15), ring_alpha), 1.25, true)

func _draw_enemy_overlap(viewer: int) -> void:
	var enemy: int = 3 - viewer
	var tint: Color = GameColors.player_color(enemy)
	var visible_enemy_vision: Dictionary = {}
	var powered_enemy_vision: Dictionary = {}

	for node in board.player_pieces[enemy - 1]:
		var piece := node as Piece
		if not is_instance_valid(piece):
			continue
		if piece.is_queued_for_deletion():
			continue
		if not board.hasCellInVision(viewer, piece.get_cur_pos()):
			continue

		for vision_cell in piece.cur_vision:
			if piece.powered:
				powered_enemy_vision[vision_cell] = true
			visible_enemy_vision[vision_cell] = true

	var selection_cells: Dictionary = {}

	for node in board.player_pieces[viewer - 1]:
		var piece := node as Piece
		if not piece.selected:
			continue

		for cell in piece.cur_vision:
			selection_cells[cell] = true
		for cell in piece.cur_moves:
			selection_cells[cell] = true
	
	var core_cells: Dictionary = {}

	for side in board.player_pieces:
		for node in side:
			var piece := node as Piece
			if piece is CorePiece and piece.is_visible_in_tree():
				core_cells[piece.get_cur_pos()] = true

	for cell in board.board_tiles:
		if core_cells.has(cell):
			continue
		if selection_cells.has(cell):
			continue
		if not board.hasCellInVision(viewer, cell):
			continue
		if not visible_enemy_vision.has(cell):
			continue
		var points: PackedVector2Array = _tile_polygon(cell)
		var center: Vector2 = board.map_to_local(cell)

		# A uniform base prevents underlying player fills changing the brightness.
		var base_color: Color = tint.darkened(0.75)
		base_color.a = 0.3
		draw_colored_polygon(points, base_color)

		if powered_enemy_vision.has(cell):
			_draw_enemy_powered_vision(points, center, tint)
			_draw_enemy_selection_overlay(points, cell, viewer)
			continue

		# One full pulse every three seconds, synchronized across tiles.
		var pulse: float = (
			0.5 + 0.5 * sin(effect_time * TAU / 3.0)
		)
		var alpha: float = (
			enemy_overlap_strength * lerpf(0.7, 1.0, pulse)
		)
		var phase: float = (
			effect_time * enemy_overlap_speed
			- center.x * 0.004
			- center.y * 0.003
		)

		draw_colored_polygon(points, Color(tint, alpha))

		var outline: PackedVector2Array = points.duplicate()
		outline.append(points[0])

		draw_polyline(
			outline,
			Color(tint, alpha * 1.6),
			2.0,
			true
		)

		# A short highlight travels gently around each tile.
		var edge_phase: float = (
			effect_time * enemy_overlap_speed
		)
		var edge: int = (
			int(floor(edge_phase)) % points.size()
		)
		var next_edge: int = (edge + 1) % points.size()
		var travel: float = fposmod(edge_phase, 1.0)

		var start: Vector2 = points[edge].lerp(
			points[next_edge], travel
		)
		var end: Vector2 = points[edge].lerp(
			points[next_edge], minf(travel + 0.3, 1.0)
		)

		draw_line(
			start,
			end,
			Color(tint, minf(alpha * 3.0, 1.0)),
			3.0,
			true
		)

func _enemy_vision_cells(viewer: int) -> Dictionary:
	var cells: Dictionary = {}

	for node in board.player_pieces[2 - viewer]:
		var piece := node as Piece
		if not is_instance_valid(piece) or piece.is_queued_for_deletion():
			continue
		if not board.hasCellInVision(viewer, piece.get_cur_pos()):
			continue

		for cell in piece.cur_vision:
			cells[cell] = true

	return cells

func _draw_enemy_powered_vision(
	points: PackedVector2Array,
	center: Vector2,
	tint: Color
) -> void:
	# Match the friendly powered rhythm, but pull inward.
	var cycle: float = fposmod(effect_time * 0.65, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(effect_time * TAU * 0.65)
	var strength: float = enemy_powered_effect_strength
	var alpha: float = strength * lerpf(0.55, 1.0, pulse)

	# Keep the fill restrained so overlapping player effects remain readable.
	draw_colored_polygon(points, Color(tint, alpha))

	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(tint, alpha * 1.8), 2.25, true)

	var ring := PackedVector2Array()
	for point in points:
		ring.append(
			center + (point - center) * lerpf(0.96, 0.35, cycle)
		)
	ring.append(ring[0])

	var ring_alpha: float = strength * sin(cycle * PI)
	draw_polyline(ring, Color(tint, ring_alpha), 1.75, true)

func _draw_tile_glint(
	polygon: PackedVector2Array,
	color: Color,
	is_selected: bool,
	phase_offset: float
) -> void:
	if AppSettings.low_graphics:
		return

	var count: int = polygon.size()

	if count < 3:
		return

	var speed: float = 0.3 if is_selected else 0.16
	var width: float = 3.0 if is_selected else 2.0
	var strength: float = 0.95 if is_selected else 0.7

	var highlight := Color(
		minf(color.r * 1.5, 1.0),
		minf(color.g * 1.5, 1.0),
		minf(color.b * 1.5, 1.0)
	)

	var trail := PackedVector2Array()
	var colors := PackedColorArray()

	for i in range(14):
		var progress: float = fposmod(
			effect_time * speed
			+ phase_offset
			- float(i) * 0.018,
			1.0
		)

		var perimeter_position: float = progress * float(count)
		var edge: int = int(floor(perimeter_position))
		var fraction: float = perimeter_position - float(edge)

		trail.append(
			polygon[edge].lerp(
				polygon[(edge + 1) % count],
				fraction
			)
		)

		colors.append(
			Color(
				highlight,
				strength * (1.0 - float(i) / 14.0)
			)
		)

	draw_polyline_colors(
		trail,
		colors,
		width,
		true
	)


func _update_vision_fades(visible_cells: Dictionary) -> void:
	# Remove completed fade records.
	for cell in fading_tiles.keys():
		var entry: Dictionary = fading_tiles[cell]
		var visual: Variant = entry.get("visual")

		if not is_instance_valid(visual):
			fading_tiles.erase(cell)

	# Fade tiles that were visible but are no longer visible.
	for cell in tile_snapshots.keys():
		if visible_cells.has(cell):
			continue

		var snapshot: Dictionary = tile_snapshots[cell]
		_play_vision_loss(cell, snapshot)
		tile_snapshots.erase(cell)

	# Remember the artwork while a tile is still visible.
	for cell in visible_cells:
		# Regaining vision cancels the old fading image.
		if fading_tiles.has(cell):
			var entry: Dictionary = fading_tiles[cell]
			var tween: Variant = entry.get("tween")
			var fading_visual: Variant = entry.get("visual")

			if is_instance_valid(tween) and tween.is_valid():
				tween.kill()

			if is_instance_valid(fading_visual):
				fading_visual.queue_free()

			fading_tiles.erase(cell)

		tile_snapshots[cell] = {
			"parts": _tile_parts(cell)
		}

func _play_vision_loss(
	cell: Vector2i,
	snapshot: Dictionary
) -> void:
	var visual := _visual_from_parts(
		cell,
		snapshot["parts"]
	)
	# The underlying board has already returned to darkness.
	# This old image fades away over it.
	var tween := create_tween()

	fading_tiles[cell] = {
		"visual": visual,
		"tween": tween,
	}

	tween.tween_property(
		visual,
		"modulate:a",
		0.0,
		vision_loss_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.tween_callback(visual.queue_free)


func _clear_vision_fades() -> void:
	for entry in fading_tiles.values():
		var tween: Variant = entry.get("tween")
		var visual: Variant = entry.get("visual")

		if is_instance_valid(tween) and tween.is_valid():
			tween.kill()

		if is_instance_valid(visual):
			visual.queue_free()

	fading_tiles.clear()
	tile_snapshots.clear()

func record_move(
	from_position: Vector2,
	to_position: Vector2,
	moving_player: int
) -> void:
	var from_cell: Vector2i = board.local_to_map(from_position)
	var to_cell: Vector2i = board.local_to_map(to_position)

	last_move_by_viewer.clear()

	for viewer_index in range(board.player_pieces.size()):
		var viewer: int = viewer_index + 1
		var own_move: bool = viewer == moving_player

		last_move_by_viewer[viewer] = {
			"player": moving_player,
			"from": {
				"cell": from_cell,
				"known": (
					own_move
					or board.hasCellInVision(viewer, from_cell)
				),
			},
			"to": {
				"cell": to_cell,
				"known": (
					own_move
					or board.hasCellInVision(viewer, to_cell)
				),
			},
		}

	queue_redraw()


func _draw_last_move(viewer: int) -> void:
	if not last_move_by_viewer.has(viewer):
		return

	var record: Dictionary = last_move_by_viewer[viewer]
	var color: Color = GameColors.player_color(
		int(record["player"])
	)

	for endpoint_name in ["from", "to"]:
		var endpoint: Dictionary = record[endpoint_name]

		if not bool(endpoint["known"]):
			continue

		var cell: Vector2i = endpoint["cell"]

		# Do not reveal a hidden move or leave markers in fog.
		if not board.hasCellInVision(viewer, cell):
			continue

		var outline: PackedVector2Array = _tile_polygon(cell)
		outline.append(outline[0])

		var is_destination: bool = endpoint_name == "to"
		var alpha: float = 0.55 if is_destination else 0.25
		var width: float = 2.5 if is_destination else 1.5

		draw_polyline(
			outline,
			Color(color, alpha),
			width,
			true
		)


func _draw_enemy_selection_overlay(
	points: PackedVector2Array,
	cell: Vector2i,
	viewer: int
) -> void:
	var selected_piece: Piece = null
	for node in board.player_pieces[viewer - 1]:
		var piece := node as Piece
		if piece.selected:
			selected_piece = piece
			break

	if selected_piece == null:
		return

	var in_vision: bool = selected_piece.cur_vision.has(cell)
	var can_move: bool = selected_piece.cur_moves.has(cell)
	if not in_vision and not can_move:
		return

	var tint: Color = GameColors.powered_color(viewer)
	var pulse: float = 0.5 + 0.5 * sin(effect_time * 2.0)

	# Movement takes priority over the broader vision highlight.
	var fill_alpha: float = 0.28 if can_move else 0.12
	var edge_alpha: float = 0.95 if can_move else 0.60
	var width: float = 3.5 if can_move else 2.0

	draw_colored_polygon(
		points,
		Color(tint, fill_alpha * lerpf(0.8, 1.0, pulse))
	)

	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(tint, edge_alpha), width, true)