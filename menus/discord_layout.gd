extends PanelContainer

@export var corner_margin := 16.0


func _ready() -> void:
	get_viewport().size_changed.connect(_queue_layout)
	_queue_layout()


func _queue_layout() -> void:
	call_deferred("refresh_layout")


func refresh_layout() -> void:
	var button := $DiscordButton as Button
	var viewport := get_viewport()
	var screen_rect := viewport.get_visible_rect()
	var safe_rect := screen_rect

	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe := DisplayServer.get_display_safe_area()

		if safe.has_area():
			var to_ui := viewport.get_screen_transform().affine_inverse()
			var window_origin := Vector2(
				DisplayServer.window_get_position()
			)
			var start := to_ui * (
				Vector2(safe.position) - window_origin
			)
			var finish := to_ui * (
				Vector2(safe.end) - window_origin
			)
			var converted := Rect2(start, finish - start)
			var intersection := converted.intersection(screen_rect)

			if intersection.has_area():
				safe_rect = intersection

	# Reserve room for the icon even after mobile font scaling.
	var font := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	var text_size := font.get_string_size(
		button.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size
	)
	var icon_side := maxf(28.0, float(font_size))
	var separation := float(button.get_theme_constant("h_separation"))
	var button_style := button.get_theme_stylebox("normal")

	button.expand_icon = true
	button.add_theme_constant_override(
		"icon_max_width",
		roundi(icon_side)
	)
	button.custom_minimum_size = Vector2(
		text_size.x + icon_side + separation,
		maxf(text_size.y, icon_side)
	) + button_style.get_minimum_size()

	var panel_style := get_theme_stylebox("panel")
	var desired_size := (
		button.get_combined_minimum_size()
		+ panel_style.get_minimum_size()
	)

	scale = Vector2.ONE
	pivot_offset = Vector2.ZERO

	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN

	var right_inset := screen_rect.end.x - safe_rect.end.x
	var bottom_inset := screen_rect.end.y - safe_rect.end.y

	offset_right = -right_inset - corner_margin
	offset_bottom = -bottom_inset - corner_margin
	offset_left = offset_right - desired_size.x
	offset_top = offset_bottom - desired_size.y