extends Button


const MAP_PREVIEW_SCRIPT = preload("res://menus/map_preview.gd")

var preview_drawing

@onready var viewport: SubViewport = (
	$MarginContainer/VBoxContainer/Preview/SubViewport
)
@onready var name_label: Label = (
	$MarginContainer/VBoxContainer/MapName
)

@export var preview_background: Color = Color("#00456d")

@onready var preview: SubViewportContainer = (
	$MarginContainer/VBoxContainer/Preview
)

var layout: PlayableMap
var map_title: String = ""


func _ready() -> void:
	viewport.world_2d = World2D.new()
	viewport.size_changed.connect(_fit_preview)
	toggled.connect(_update_label)

	add_theme_stylebox_override(
		"normal",
		_make_style(Color("#111b24"), Color("#344957"), 1)
	)
	add_theme_stylebox_override(
		"hover",
		_make_style(Color("#192b35"), Color("#65b8bd"), 2)
	)
	add_theme_stylebox_override(
		"pressed",
		_make_style(Color("#15363b"), Color("#00ead4"), 3)
	)
	add_theme_stylebox_override(
		"hover_pressed",
		_make_style(Color("#1b4146"), Color("#00ead4"), 3)
	)

	viewport.transparent_bg = true

	var background := ColorRect.new()
	background.name = "PreviewBackground"
	background.color = preview_background
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	preview.add_child(background)
	preview.move_child(background, 0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Draw the background behind the viewport image.
	background.show_behind_parent = true
	resized.connect(_resize_card)
	call_deferred("_resize_card")


func configure(title: String, scene: PackedScene) -> void:
	map_title = title
	tooltip_text = "Choose " + title
	_update_label(button_pressed)

	if is_instance_valid(preview_drawing):
		viewport.remove_child(preview_drawing)
		preview_drawing.queue_free()

	if is_instance_valid(layout):
		viewport.remove_child(layout)
		layout.queue_free()

	layout = scene.instantiate() as PlayableMap

	if layout == null:
		push_error("Map preview needs a PlayableMap root.")
		return

	# Hide the gameplay artwork before adding the map.
	layout.hide()
	viewport.add_child(layout)

	preview_drawing = MAP_PREVIEW_SCRIPT.new()
	viewport.add_child(preview_drawing)
	preview_drawing.configure(layout)

	call_deferred("_fit_preview")

func _update_label(selected: bool) -> void:
	name_label.text = map_title
	name_label.modulate = (
		Color("#00ead4") if selected else Color.WHITE
	)
	_resize_card()

func _resize_card() -> void:
	# Keep previews compact even when the grid has wide columns.
	var preview_width := maxf(size.x - 20.0, 1.0)
	var preview_height := clampf(preview_width * 0.5625, 100.0, 160.0)

	preview.custom_minimum_size = Vector2(0, preview_height)

	var title_height := maxf(
		0.0,
		name_label.get_combined_minimum_size().y
	)
	custom_minimum_size.y = (
		20.0 + preview_height + 8.0 + title_height
	)

func _fit_preview() -> void:
	if not is_instance_valid(preview_drawing):
		return

	var bounds: Rect2 = preview_drawing.bounds

	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return

	var viewport_size := Vector2(viewport.size)
	var available := viewport_size - Vector2(20, 20)

	if available.x <= 0 or available.y <= 0:
		return

	var zoom := minf(
		available.x / bounds.size.x,
		available.y / bounds.size.y
	)

	viewport.canvas_transform = Transform2D(
		Vector2(zoom, 0),
		Vector2(0, zoom),
		viewport_size * 0.5 - bounds.get_center() * zoom
	)

func _make_style(
	background: Color,
	border: Color,
	width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(8)
	return style
