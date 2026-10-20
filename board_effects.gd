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

@export var enemy_overlap_strength: float = 0.18
@export var enemy_overlap_speed: float = 0.65

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


func _tile_copy(cell: Vector2i) -> Sprite2D:
	var source_id: int = board.get_cell_source_id(cell)

	if source_id < 0:
		return null

	var source := board.tile_set.get_source(
		source_id
	) as TileSetAtlasSource

	if source == null:
		return null

	var atlas := AtlasTexture.new()
	atlas.atlas = source.texture
	atlas.region = source.get_tile_texture_region(
		board.get_cell_atlas_coords(cell)
	)

	var visual := Sprite2D.new()
	visual.texture = atlas
	visual.position = board.map_to_local(cell)

	var data: TileData = board.get_cell_tile_data(cell)

	if data != null:
		visual.position += Vector2(data.texture_origin)

	add_child(visual)
	return visual


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

	if selected_piece != null:
		for cell in selected_piece.cur_vision:
			selected_vision[cell] = true

	for cell in effect_visible:
		# Never leave an effect on a tile that has lost vision.
		if not board.hasCellInVision(viewer, cell):
			continue

		var points: PackedVector2Array = _tile_polygon(cell)
		var center: Vector2 = board.map_to_local(cell)

		_draw_tile_glint(
			points,
			player_color,
			selected_vision.has(cell),
			center.y * 0.002
		)

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
		else:
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

func _draw_enemy_overlap(viewer: int) -> void:
	var enemy: int = 3 - viewer
	var tint: Color = GameColors.player_color(enemy)
	var visible_enemy_vision: Dictionary = {}

	for node in board.player_pieces[enemy - 1]:
		var piece := node as Piece
		if not is_instance_valid(piece):
			continue
		if piece.is_queued_for_deletion():
			continue
		if not board.hasCellInVision(viewer, piece.get_cur_pos()):
			continue

		for vision_cell in piece.cur_vision:
			visible_enemy_vision[vision_cell] = true

	for cell in board.board_tiles:
		if not board.hasCellInVision(viewer, cell):
			continue
		if not visible_enemy_vision.has(cell):
			continue
		var points: PackedVector2Array = _tile_polygon(cell)
		var center: Vector2 = board.map_to_local(cell)

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

func _draw_tile_glint(
	polygon: PackedVector2Array,
	color: Color,
	is_selected: bool,
	phase_offset: float
) -> void:
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

		if tile_snapshots.has(cell):
			continue

		var copy: Sprite2D = _tile_copy(cell)

		if copy == null:
			continue

		tile_snapshots[cell] = {
			"texture": copy.texture,
			"position": copy.position,
		}

		# Only retain its appearance, not another visible sprite.
		copy.free()


func _play_vision_loss(
	cell: Vector2i,
	snapshot: Dictionary
) -> void:
	var visual := Sprite2D.new()
	visual.texture = snapshot["texture"]
	visual.position = snapshot["position"]
	add_child(visual)

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
