class_name UITextScale
extends RefCounted


static func current_factor(viewport: Viewport) -> float:
	var mobile := (
		OS.has_feature("android")
		or OS.has_feature("ios")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)

	var viewport_size := viewport.get_visible_rect().size

	if mobile and viewport_size.y > viewport_size.x:
		return 2.0

	return 1.0


static func apply(node: Node, factor: float) -> void:
	if node is Control:
		var control := node as Control
		var size_names: Array[String] = []

		if node is RichTextLabel:
			size_names = [
				"normal_font_size",
				"bold_font_size",
				"italics_font_size",
				"bold_italics_font_size",
				"mono_font_size"
			]
		elif node is Label or node is Button \
		or node is LineEdit or node is TextEdit:
			size_names = ["font_size"]

		for size_name in size_names:
			var key := "ui_original_" + size_name

			if not control.has_meta(key):
				control.set_meta(
					key,
					control.get_theme_font_size(size_name)
				)

			var original: int = control.get_meta(key)
			control.add_theme_font_size_override(
				size_name,
				roundi(original * factor)
			)

	if node is HSlider or node is VSlider:
		var slider := node as Slider
		var mobile := (
			OS.has_feature("android")
			or OS.has_feature("ios")
			or OS.has_feature("web_android")
			or OS.has_feature("web_ios")
		)

		if not slider.has_meta("slider_original_minimum"):
			slider.set_meta(
				"slider_original_minimum",
				slider.custom_minimum_size
			)

		var minimum: Vector2 = slider.get_meta("slider_original_minimum")

		if mobile:
			if slider is HSlider:
				minimum.y = maxf(minimum.y, 64.0)
			else:
				minimum.x = maxf(minimum.x, 64.0)

		slider.custom_minimum_size = minimum

	for child in node.get_children():
		apply(child, factor)
