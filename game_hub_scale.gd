extends Control

# (0, 0) = top-left; (1, 1) = bottom-right.
@export var scale_pivot: Vector2 = Vector2.ZERO


func _ready() -> void:
	resized.connect(_update_scale_pivot)
	AppSettings.game_ui_scale_changed.connect(_apply_ui_scale)
	_apply_ui_scale()


func _apply_ui_scale() -> void:
	_update_scale_pivot()
	scale = Vector2.ONE * AppSettings.get_game_ui_scale()


func _update_scale_pivot() -> void:
	pivot_offset = size * scale_pivot