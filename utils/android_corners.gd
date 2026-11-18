extends Node

signal changed

enum Corner {
	NONE = -1,
	TOP_LEFT = 0,
	TOP_RIGHT = 1,
	BOTTOM_RIGHT = 2,
	BOTTOM_LEFT = 3,
}

var _runtime: Object
var _java: Object
var _pending := false

# Corner bounds normalized to the Godot render surface.
var _corners: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	return

	if not OS.has_feature("android"):
		return

	if not Engine.has_singleton("AndroidRuntime"):
		return

	if not Engine.has_singleton("JavaClassWrapper"):
		return

	_runtime = Engine.get_singleton("AndroidRuntime")
	_java = Engine.get_singleton("JavaClassWrapper")

	var version = _java.wrap("android.os.Build$VERSION")

	# Rounded-corner information requires Android 12 / API 31.
	if int(version.SDK_INT) < 31:
		return

	get_viewport().size_changed.connect(_request_sample)

	# Also catches 180-degree rotations and corner information
	# that arrives after the screen resize event.
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.timeout.connect(_request_sample)
	add_child(timer)
	timer.start()

	_request_sample()


func _request_sample() -> void:
	if _pending:
		return

	var activity = _runtime.getActivity()
	if activity == null:
		return

	_pending = true

	activity.runOnUiThread(
		_runtime.createRunnableFromGodotCallable(_read_android)
	)


func _read_android() -> void:
	# Read Android views on Android's UI thread.
	var activity = _runtime.getActivity()
	if activity == null:
		_accept.call_deferred(null)
		return

	var godot = activity.getGodot()
	if godot == null or godot.getRenderView() == null:
		_accept.call_deferred(null)
		return

	var view = godot.getRenderView().getView()
	var root = view.getRootView()
	var insets = root.getRootWindowInsets()

	if insets == null or view.getWidth() <= 0 or view.getHeight() <= 0:
		_accept.call_deferred(null)
		return

	# Find the render surface within the Android window.
	var rect_class = _java.wrap("android.graphics.Rect")
	var bounds = rect_class.Rect()

	view.getDrawingRect(bounds)
	root.offsetDescendantRectToMyCoords(view, bounds)

	var origin := Vector2(
		float(bounds.left),
		float(bounds.top)
	)

	var surface_size := Vector2(
		float(view.getWidth()),
		float(view.getHeight())
	)

	var sample: Dictionary = {}

	for corner_id in range(4):
		var corner = insets.getRoundedCorner(corner_id)

		if corner == null or corner.getRadius() <= 0:
			continue

		var center = corner.getCenter()
		var radius := float(corner.getRadius())

		var center_in_surface := Vector2(
			float(center.x),
			float(center.y)
		) - origin

		var box := Rect2(
			center_in_surface - Vector2.ONE * radius,
			Vector2.ONE * radius * 2.0
		)

		if box.intersects(Rect2(Vector2.ZERO, surface_size)):
			sample[corner_id] = Rect2(
				box.position / surface_size,
				box.size / surface_size
			)

	# Return plain values to Godot's main thread.
	_accept.call_deferred(sample)


func _accept(sample: Variant) -> void:
	_pending = false

	if sample == null:
		return

	if sample != _corners:
		_corners = sample
		changed.emit()


func _boundary(
	corner_id: int,
	rect: Rect2,
	screen: Rect2
) -> float:
	var top := (
		corner_id == Corner.TOP_LEFT
		or corner_id == Corner.TOP_RIGHT
	)

	var fallback := screen.position.y if top else screen.end.y

	if not _corners.has(corner_id):
		return fallback

	var normalized: Rect2 = _corners[corner_id]

	var box := Rect2(
		screen.position + normalized.position * screen.size,
		normalized.size * screen.size
	)

	var center := box.get_center()
	var radii := box.size * 0.5

	var right := (
		corner_id == Corner.TOP_RIGHT
		or corner_id == Corner.BOTTOM_RIGHT
	)

	var x := rect.end.x if right else rect.position.x
	var distance := x - center.x if right else center.x - x

	# This control is already horizontally clear of the curve.
	if distance <= 0.0:
		return fallback

	var ratio := clampf(distance / radii.x, 0.0, 1.0)
	var arc := radii.y * sqrt(maxf(0.0, 1.0 - ratio * ratio))

	if top:
		return maxf(fallback, center.y - arc)

	return minf(fallback, center.y + arc)


func adjust(
	control: Control,
	corner_id: int,
	flush_right: bool = false,
	fit: bool = false,
	safe_rect: Rect2 = Rect2()
) -> void:
	if corner_id == Corner.NONE:
		return

	var right := (
		corner_id == Corner.TOP_RIGHT
		or corner_id == Corner.BOTTOM_RIGHT
	)

	var top_id := Corner.TOP_RIGHT if right else Corner.TOP_LEFT
	var bottom_id := Corner.BOTTOM_RIGHT if right else Corner.BOTTOM_LEFT

	var has_curve := _corners.has(corner_id) or (fit and _corners.has(top_id))
	if not has_curve and not fit:
		return

	var screen := control.get_viewport().get_visible_rect()
	var rect := control.get_global_rect()

	if flush_right:
		control.global_position.x += screen.end.x - rect.end.x
		rect = control.get_global_rect()

	var top := _boundary(top_id, rect, screen)
	var bottom := _boundary(bottom_id, rect, screen)

	if fit:
		if safe_rect.size.y > 0.0:
			top = maxf(top, safe_rect.position.y)
			bottom = minf(bottom, safe_rect.end.y)

		var top_inset := top - screen.position.y
		bottom = minf(bottom, screen.end.y - top_inset)

	# Keep a tall selection panel between the upper and lower curves.
	if fit and rect.size.y > 0.0:
		control.scale *= minf(
			1.0,
			maxf(1.0, bottom - top) / rect.size.y
		)

		rect = control.get_global_rect()

	var is_top := (
		corner_id == Corner.TOP_LEFT
		or corner_id == Corner.TOP_RIGHT
	)

	# Move only when the current position crosses the curve.
	if is_top:
		control.global_position.y += maxf(
			0.0,
			top - rect.position.y
		)
	else:
		var bottom_shift := bottom - rect.end.y
		control.global_position.y += bottom_shift if fit else minf(0.0, bottom_shift)
