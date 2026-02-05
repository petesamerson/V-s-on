extends Piece
class_name TriangleOddPiece

func _ready() -> void:
    pass

func _process(delta: float) -> void:
    pass

@onready var sprite = $Sprite2D

func setup(inital_pos: Vector2i, b: TileMapLayer):
    super.setup(inital_pos, b)

    sprite.texture = preload("res://TriangleOdd.png")