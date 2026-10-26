@tool
extends Control

const CORE = preload("res://sprites/core_piece.png")
const EYE = preload("res://sprites/eye_piece.png")

const GameColors = preload("res://colors.gd")
const BLUE = Color("#007BFF")
const RED = Color("#FF1744")

@export_range(24.0, 100.0) var hex_radius: float = 48.0:
	set(value):
		hex_radius = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()

	# Keep the editor preview independent of runtime settings.
	if Engine.is_editor_hint():
		return

	var settings := get_node("/root/AppSettings")
	settings.settings_changed.connect(_apply_animation_settings)
	_apply_animation_settings()

func _apply_animation_settings() -> void:
	var settings := get_node("/root/AppSettings")
	var reduced: bool = settings.reduce_animation

	var board_material := material as ShaderMaterial
	if board_material != null:
		board_material.set_shader_parameter("reduce_animation", reduced)

	var fog := get_node("Fog") as ColorRect
	var fog_material := fog.material as ShaderMaterial
	if fog_material != null:
		fog_material.set_shader_parameter("reduce_animation", reduced)

func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()

	for i in range(6):
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	return points


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var width := sqrt(3.0) * hex_radius
	var row_height := hex_radius * 1.5
	var columns := ceili(size.x / width) + 2
	var rows := ceili(size.y / row_height) + 2

	for row in range(-1, rows):
		for column in range(-1, columns):
			var center := Vector2(
				column * width + (width * 0.5 if row % 2 != 0 else 0.0),
				row * row_height
			)

			var uv := center / size
			var blue_distance := uv.distance_to(Vector2(0.18, 0.47))
			var red_distance := uv.distance_to(Vector2(0.82, 0.55))
			var variation := posmod(column * 7 + row * 11, 5)

			var fill := Color("#252525")
			var edge := Color("#414141")
			var team := Color.WHITE
			var territory := false

			if blue_distance < 0.22:
				team = BLUE
				territory = true
			elif red_distance < 0.22:
				team = RED
				territory = true

			if territory:
				var strength := 0.25 + float(variation) * 0.12
				fill = Color("#141414").lerp(team, strength)
				edge = team.lerp(Color.WHITE, 0.15)
			else:
				fill = fill.lightened(float(variation) * 0.015)

			# Leave a small gap between neighboring tiles.
			var points := _hex_points(center, hex_radius - 2.0)
			draw_colored_polygon(points, fill)

			var outline := points.duplicate()
			outline.append(points[0])
			draw_polyline(outline, edge, 1.0, true)

			# Decorative pieces using the gameplay palette.
			if territory and posmod(column * 3 + row * 5, 13) == 0:
				var is_core := variation % 2 == 0
				var texture: Texture2D = CORE if is_core else EYE
				var player_id := 1 if blue_distance < 0.22 else 2

				var tint: Color = GameColors.player_color(player_id)
				if is_core:
					tint = GameColors.powered_color(player_id)

				# Match the eye's smaller scale in its gameplay scene.
				var piece_scale := 1.0 if is_core else 0.8
				var piece_size := Vector2.ONE * hex_radius * 1.2 * piece_scale
				var rect := Rect2(center - piece_size * 0.5, piece_size)

				draw_texture_rect(texture, rect, false, tint)