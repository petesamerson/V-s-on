extends Control

var _base_offsets: Vector4


func _ready() -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return

	_base_offsets = Vector4(offset_left, offset_top, offset_right, offset_bottom)
	get_viewport().size_changed.connect(_update_safe_area)
	_update_safe_area()


func _update_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var shift := Vector2.ZERO

	if safe.has_area():
		var viewport := get_viewport()
		var screen_to_ui := viewport.get_screen_transform().affine_inverse()
		var window_origin := Vector2(DisplayServer.window_get_position())
		var safe_start := screen_to_ui * (Vector2(safe.position) - window_origin)
		var safe_end := screen_to_ui * (Vector2(safe.end) - window_origin)
		var menu_size := get_parent_area_size()

		if is_zero_approx(anchor_left) and is_zero_approx(anchor_right):
			shift.x = maxf(0.0, safe_start.x - _base_offsets.x)
		elif is_equal_approx(anchor_left, 1.0) and is_equal_approx(anchor_right, 1.0):
			shift.x = minf(0.0, safe_end.x - menu_size.x - _base_offsets.z)

		if is_zero_approx(anchor_top) and is_zero_approx(anchor_bottom):
			shift.y = maxf(0.0, safe_start.y - _base_offsets.y)
		elif is_equal_approx(anchor_top, 1.0) and is_equal_approx(anchor_bottom, 1.0):
			shift.y = minf(0.0, safe_end.y - menu_size.y - _base_offsets.w)

	offset_left = _base_offsets.x + shift.x
	offset_right = _base_offsets.z + shift.x
	offset_top = _base_offsets.y + shift.y
	offset_bottom = _base_offsets.w + shift.y