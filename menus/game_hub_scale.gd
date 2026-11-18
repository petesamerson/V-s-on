extends Control

@export var respect_mobile_safe_area := false
@export var fit_to_mobile_safe_area := false
@export var mirror_landscape_side_inset := false

@export_enum(
	"None:-1",
	"Top Left:0",
	"Top Right:1",
	"Bottom Right:2",
	"Bottom Left:3"
) var rounded_corner: int = -1

@export var flush_right_on_rounded_screen := false
@export var scale_pivot: Vector2 = Vector2.ZERO

var _layout_queued := false
var _base_offsets: Vector4
var _mobile_safe_rect := Rect2()
var _uses_mobile_safe_area := false


func _ready() -> void:
	_base_offsets = Vector4(
		offset_left,
		offset_top,
		offset_right,
		offset_bottom
	)

	_uses_mobile_safe_area = respect_mobile_safe_area and (
		OS.has_feature("android")
		or OS.has_feature("ios")
	)

	resized.connect(_queue_layout)
	visibility_changed.connect(_queue_layout)
	AppSettings.game_ui_scale_changed.connect(_queue_layout)
	get_viewport().size_changed.connect(_queue_layout)
	AndroidCorners.changed.connect(_queue_layout)

	_queue_layout()


func _queue_layout() -> void:
	if _layout_queued:
		return

	_layout_queued = true
	_refresh_layout.call_deferred()


func _refresh_layout() -> void:
	if _uses_mobile_safe_area:
		_apply_mobile_safe_area()

	var layout_size := size
	_apply_ui_scale()

	# AndroidCorners.adjust(
	# 	self,
	# 	rounded_corner,
	# 	flush_right_on_rounded_screen,
	# 	fit_to_mobile_safe_area and _uses_mobile_safe_area,
	# 	_mobile_safe_rect
	# )

	_layout_queued = false
	if size != layout_size:
		_queue_layout()


func _apply_mobile_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var shift := Vector2.ZERO

	_mobile_safe_rect = Rect2()

	if safe.has_area():
		var viewport := get_viewport()
		var pixels_to_ui := viewport.get_screen_transform().affine_inverse()
		var window_origin := Vector2(DisplayServer.window_get_position())

		var safe_start := pixels_to_ui * (
			Vector2(safe.position) - window_origin
		)

		var safe_end := pixels_to_ui * (
			Vector2(safe.end) - window_origin
		)

		_mobile_safe_rect = Rect2(
			safe_start,
			safe_end - safe_start
		).intersection(viewport.get_visible_rect())

		var viewport_size := viewport.get_visible_rect().size

		if is_zero_approx(scale_pivot.x) and is_zero_approx(anchor_left):
			shift.x = maxf(
				0.0,
				safe_start.x - _base_offsets.x
			)
		elif (
			is_equal_approx(scale_pivot.x, 1.0)
			and is_equal_approx(anchor_right, 1.0)
		):
			var base_right := viewport_size.x + _base_offsets.z
			var right_limit := safe_end.x
			var screen := viewport.get_visible_rect()
			if (
				mirror_landscape_side_inset
				and screen.size.x > screen.size.y
				and _mobile_safe_rect.has_area()
			):
				var left_inset := _mobile_safe_rect.position.x - screen.position.x
				right_limit = minf(_mobile_safe_rect.end.x, screen.end.x - left_inset)

			shift.x = minf(0.0, right_limit - base_right)

		if is_zero_approx(scale_pivot.y) and is_zero_approx(anchor_top):
			shift.y = maxf(
				0.0,
				safe_start.y - _base_offsets.y
			)
		elif (
			is_equal_approx(scale_pivot.y, 1.0)
			and is_equal_approx(anchor_bottom, 1.0)
		):
			var base_bottom := viewport_size.y + _base_offsets.w
			var bottom_limit := safe_end.y
			if fit_to_mobile_safe_area and _mobile_safe_rect.has_area():
				var screen := viewport.get_visible_rect()
				var top_inset := _mobile_safe_rect.position.y - screen.position.y
				bottom_limit = minf(_mobile_safe_rect.end.y, screen.end.y - top_inset)

			shift.y = minf(0.0, bottom_limit - base_bottom)
			if fit_to_mobile_safe_area:
				print("SELECTION_INSET_TEST viewport=", get_viewport().get_visible_rect(),
					" raw_safe=", safe, " ui_safe=", _mobile_safe_rect,
					" bottom_shift=", shift.y, " offset_bottom=", offset_bottom)

	offset_left = _base_offsets.x + shift.x
	offset_right = _base_offsets.z + shift.x
	offset_top = _base_offsets.y + shift.y
	offset_bottom = _base_offsets.w + shift.y

func _apply_ui_scale() -> void:
	_update_scale_pivot()

	var factor := AppSettings.get_game_ui_scale()

	if fit_to_mobile_safe_area:
		var available := get_viewport().get_visible_rect()

		if _mobile_safe_rect.has_area():
			available = _mobile_safe_rect

		var available_size := available.size - Vector2(24, 24)

		if size.x > 0.0 and size.y > 0.0:
			var fit_factor := minf(
				maxf(available_size.x, 1.0) / size.x,
				maxf(available_size.y, 1.0) / size.y
			)
			factor = minf(factor, fit_factor)

	scale = Vector2.ONE * factor


func _update_scale_pivot() -> void:
	pivot_offset = size * scale_pivot
