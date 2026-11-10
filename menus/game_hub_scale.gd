extends Control

@export var respect_mobile_safe_area := false
@export var fit_to_mobile_safe_area := false

var _base_offsets: Vector4
var _mobile_safe_rect := Rect2()

@export var scale_pivot: Vector2 = Vector2.ZERO


func _ready() -> void:
	resized.connect(_apply_ui_scale)
	AppSettings.game_ui_scale_changed.connect(_apply_ui_scale)
	get_viewport().size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()

	if respect_mobile_safe_area and (
		OS.has_feature("android") or OS.has_feature("ios")
	):
		_base_offsets = Vector4(
			offset_left, offset_top, offset_right, offset_bottom
		)
		get_viewport().size_changed.connect(_apply_mobile_safe_area)
		_apply_mobile_safe_area()

func _apply_mobile_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var shift := Vector2.ZERO


	if safe.has_area():
		var viewport := get_viewport()
		var pixels_to_ui := viewport.get_screen_transform().affine_inverse()
		var window_origin := Vector2(DisplayServer.window_get_position())
		var safe_start := pixels_to_ui * (Vector2(safe.position) - window_origin)
		var safe_end := pixels_to_ui * (Vector2(safe.end) - window_origin)
		_mobile_safe_rect = Rect2(safe_start, safe_end - safe_start).intersection(
			viewport.get_visible_rect()
		)
		var viewport_size := viewport.get_visible_rect().size

		if is_zero_approx(scale_pivot.x) and is_zero_approx(anchor_left):
			shift.x = maxf(0.0, safe_start.x - _base_offsets.x)
		elif is_equal_approx(scale_pivot.x, 1.0) and is_equal_approx(anchor_right, 1.0):
			var base_right := viewport_size.x + _base_offsets.z
			shift.x = minf(0.0, safe_end.x - base_right)

		if is_zero_approx(scale_pivot.y) and is_zero_approx(anchor_top):
			shift.y = maxf(0.0, safe_start.y - _base_offsets.y)
		elif is_equal_approx(scale_pivot.y, 1.0) and is_equal_approx(anchor_bottom, 1.0):
			var base_bottom := viewport_size.y + _base_offsets.w
			shift.y = minf(0.0, safe_end.y - base_bottom)

	offset_left = _base_offsets.x + shift.x
	offset_right = _base_offsets.z + shift.x
	offset_top = _base_offsets.y + shift.y
	offset_bottom = _base_offsets.w + shift.y
	_apply_ui_scale()

func _apply_ui_scale() -> void:
	_update_scale_pivot()

	var factor := AppSettings.get_game_ui_scale()

	if fit_to_mobile_safe_area:
		var available := get_viewport().get_visible_rect()

		if _mobile_safe_rect.has_area():
			available = _mobile_safe_rect

		# Keep the panel inside the available screen area.
		var available_size := available.size - Vector2(24, 24)

		if size.x > 0 and size.y > 0:
			var fit_factor := minf(
				maxf(available_size.x, 1.0) / size.x,
				maxf(available_size.y, 1.0) / size.y
			)
			factor = minf(factor, fit_factor)

	scale = Vector2.ONE * factor

func _update_scale_pivot() -> void:
	pivot_offset = size * scale_pivot