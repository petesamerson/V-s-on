extends Node

var _panel: PanelContainer
var _label: Label
var _elapsed := 0.0
var _pending_seconds := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_panel)

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.9)
	background.content_margin_left = 12
	background.content_margin_right = 12
	background.content_margin_top = 12
	background.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", background)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_color_override("font_color", Color.WHITE)
	_panel.add_child(_label)

	_update_display()


func _process(delta: float) -> void:
	var reader := get_node_or_null("/root/AndroidCorners")

	if reader != null and bool(reader.get("_pending")):
		_pending_seconds += delta
	else:
		_pending_seconds = 0.0

	_elapsed += delta
	if _elapsed >= 0.5:
		_elapsed = 0.0
		_update_display()


func _update_display() -> void:
	var screen := get_viewport().get_visible_rect()
	var reader := get_node_or_null("/root/AndroidCorners")

	_panel.position = screen.position + screen.size * Vector2(0.1, 0.12)
	_panel.size.x = screen.size.x * 0.8
	_label.add_theme_font_size_override(
		"font_size",
		clampi(roundi(screen.size.y / 35.0), 12, 22)
	)

	var lines := PackedStringArray()
	lines.append("ANDROID CURVE DIAGNOSTIC")
	lines.append("Viewport: %s" % str(screen))
	lines.append("Window pixels: %s" % str(DisplayServer.window_get_size()))
	lines.append("Safe area: %s" % str(DisplayServer.get_display_safe_area()))
	lines.append(
		"AndroidRuntime: %s | Java bridge: %s" % [
			str(Engine.has_singleton("AndroidRuntime")),
			str(Engine.has_singleton("JavaClassWrapper"))
		]
	)

	if reader == null:
		lines.append("ERROR: AndroidCorners Autoload is missing")
	else:
		lines.append(
			"Read pending: %s | pending for %.1f seconds" % [
				str(reader.get("_pending")),
				_pending_seconds
			]
		)

		var corners: Dictionary = reader.get("_corners")
		lines.append("Detected curves: %d" % corners.size())

		var names := [
			"Top-left",
			"Top-right",
			"Bottom-right",
			"Bottom-left"
		]

		for corner_id in range(4):
			if corners.has(corner_id):
				var normalized: Rect2 = corners[corner_id]
				var bounds := Rect2(
					screen.position + normalized.position * screen.size,
					normalized.size * screen.size
				)
				lines.append("%s bounds: %s" % [names[corner_id], str(bounds)])
			else:
				lines.append("%s: NO DATA" % names[corner_id])

	var scene := get_tree().current_scene
	if scene != null:
		var selection := scene.get_node_or_null(
			"TurnLayer/SelectionPanel"
		) as Control

		if selection != null:
			lines.append("Selection rectangle: %s" % str(selection.get_global_rect()))
			lines.append(
				"Selection scale: %s | corner: %s | flush right: %s" % [
					str(selection.scale),
					str(selection.get("rounded_corner")),
					str(selection.get("flush_right_on_rounded_screen"))
				]
			)

	_label.text = "\n".join(lines)