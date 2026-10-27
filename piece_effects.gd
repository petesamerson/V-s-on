extends Node2D

const GameColors = preload("res://colors.gd")

var piece: Piece
var elapsed: float = 0.0
var trails: Array[Dictionary] = []
var bursts: Array[Dictionary] = []

var was_selected: bool = false
var connection_age: float = 2.0
const CONNECTION_DURATION: float = 1.6

func _ready() -> void:
	AppSettings.settings_changed.connect(_apply_graphics_settings)
	_apply_graphics_settings()


func _apply_graphics_settings() -> void:
	if AppSettings.low_graphics:
		trails.clear()
		bursts.clear()

	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta

	if is_instance_valid(piece):
		if piece.selected and not was_selected:
			connection_age = 0.0

		was_selected = piece.selected

	connection_age += delta

	for trail in trails:
		trail["age"] += delta

	for burst in bursts:
		burst["age"] += delta

	trails = trails.filter(
		func(trail): return trail["age"] < 0.4
	)
	bursts = bursts.filter(
		func(burst): return burst["age"] < 0.65
	)

	queue_redraw()


func add_move(
	from: Vector2,
	to: Vector2,
	capture: bool
) -> void:
	if AppSettings.low_graphics:
		return
	trails.append({
		"from": from,
		"to": to,
		"age": 0.0,
	})

	if capture:
		bursts.append({
			"position": to,
			"age": 0.0,
		})


func _draw() -> void:
	if not is_instance_valid(piece):
		return
	if not piece.is_visible_in_tree():
		return

	var color: Color = GameColors.player_color(
		piece.owned_player
	)

	if not AppSettings.low_graphics:
		if piece.selected or piece.powered:
			draw_tile_shimmer(color)
	# if piece.selected or piece.powered:
	# 	draw_tile_shimmer(color)

	draw_selected_connections(color)

	for trail in trails:
		var fade: float = 1.0 - trail["age"] / 0.4

		draw_line(
			trail["from"], trail["to"],
			Color(color, fade * 0.12),
			18.0, true
		)
		draw_line(
			trail["from"], trail["to"],
			Color(color, fade * 0.8),
			3.0, true
		)

	for burst in bursts:
		var progress: float = burst["age"] / 0.65
		var center: Vector2 = burst["position"]
		var burst_color := Color(color, 1.0 - progress)

		draw_arc(
			center,
			15.0 + progress * 100.0,
			0.0, TAU, 48,
			burst_color, 3.0, true
		)

		for i in range(12):
			var direction := Vector2.from_angle(
				TAU * float(i) / 12.0
			)

			draw_line(
				center + direction * (20.0 + progress * 80.0),
				center + direction * (28.0 + progress * 110.0),
				burst_color, 2.0, true
			)

	if piece.selected:
		var pulse: float = 0.55 + 0.25 * sin(elapsed * 4.0)

		draw_arc(
			piece.position + piece.sprite.position,
			68.0 + sin(elapsed * 4.0) * 3.0,
			0.0, TAU, 48,
			Color(color, pulse), 3.0, true
		)

		draw_move_markers(color)

func draw_move_markers(color: Color) -> void:
	var pulse: float = 0.75 + 0.25 * sin(elapsed * 3.0)

	for cell in piece.cur_moves:
		if not piece.board.hasCellInVision(
			piece.owned_player,
			cell
		):
			continue

		var capture: bool = false

		for player_id in range(
			1,
			piece.board.player_pieces.size() + 1
		):
			if player_id == piece.owned_player:
				continue

			if piece.board.get_enemy_piece_at_cell(
				cell,
				player_id
			) != null:
				capture = true
				break

		if capture:
			continue

		var center: Vector2 = piece.board.map_to_local(cell)

		draw_circle(center, 10.0, Color(color, 0.12))
		draw_circle(center, 4.0, Color(color, pulse))

func draw_tile_shimmer(color: Color) -> void:
	var center := piece.position
	var tile_size := Vector2(piece.board.tile_set.tile_size)
	var radius: float = minf(tile_size.x, tile_size.y) * 0.42

	var speed: float = 2.0 if piece.selected else 0.8
	var strength: float = 0.8 if piece.selected else 0.4
	var phase: float = elapsed * speed
	var pulse: float = 0.75 + 0.25 * sin(phase * 2.0)

	# Soft light spreading across the tile.
	for i in range(6):
		var spread: float = float(i) / 5.0
		var glow_radius: float = radius * lerpf(0.4, 1.0, spread)
		var alpha: float = strength * pulse * 0.025

		draw_circle(
			center,
			glow_radius,
			Color(color, alpha)
		)

	# Two moving glints around the tile.
	for i in range(2):
		var angle: float = phase + float(i) * PI

		# Wider, faint glow behind the shimmer.
		draw_arc(
			center,
			radius,
			angle,
			angle + PI * 0.45,
			24,
			Color(color, strength * 0.12),
			10.0,
			true
		)

		# Narrow, bright shimmer.
		draw_arc(
			center,
			radius,
			angle,
			angle + PI * 0.3,
			24,
			Color(color.lerp(Color.WHITE, 0.35), strength * pulse),
			2.0,
			true
		)


func draw_selected_connections(color: Color) -> void:
	if not piece.selected or not piece.powered:
		return

	var viewer: int = (
		piece.board.local_player
		if piece.board.online_game
		else piece.board.current_player
	)

	if piece.owned_player != viewer:
		return

	var is_core: bool = piece is CorePiece
	var pulse_age: float = connection_age

	if is_core:
		pulse_age = fposmod(
			connection_age,
			CONNECTION_DURATION + 0.6
		)
	elif connection_age >= CONNECTION_DURATION:
		return

	if pulse_age >= CONNECTION_DURATION:
		return

	var fade_in: float = smoothstep(
		0.0, 0.15, pulse_age
	)
	var fade_out: float = 1.0 - smoothstep(
		0.5, CONNECTION_DURATION, pulse_age
	)
	var alpha: float = fade_in * fade_out * 0.45
	var line_color := Color(color, alpha)

	var network: Array[Piece] = []

	for node in piece.board.player_pieces[piece.owned_player - 1]:
		var other := node as Piece

		if not is_instance_valid(other):
			continue
		if not other.powered or not other.is_visible_in_tree():
			continue

		network.append(other)

	if is_core:
		# Reveal every connection once, including the core.
		for i in range(network.size()):
			for j in range(i + 1, network.size()):
				var first := network[i]
				var second := network[j]

				draw_line(
					first.position + first.sprite.position,
					second.position + second.sprite.position,
					line_color,
					1.5,
					true
				)
	else:
		# Other selections briefly reveal only their own links.
		var start := piece.position + piece.sprite.position

		for other in network:
			if other == piece or other is CorePiece:
				continue

			draw_line(
				start,
				other.position + other.sprite.position,
				line_color,
				1.5,
				true
			)