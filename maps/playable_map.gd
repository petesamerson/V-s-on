extends Node2D
class_name PlayableMap

@export var display_name: String = "Classic"

@onready var ground: TileMapLayer = $Ground
@onready var walls: TileMapLayer = $Walls
@onready var center_marker: Marker2D = $Center
@onready var spawns: Node2D = $Spawns


func marker_cell(marker: Marker2D) -> Vector2i:
	return ground.local_to_map(
		ground.to_local(marker.global_position)
	)


func get_center_cell() -> Vector2i:
	return marker_cell(center_marker)



func get_spawn_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var count := spawns.get_child_count()

	if count != 2 and count != 6:
		push_error("Maps must have two or six spawn markers.")
		return cells

	for index in range(count):
		var marker := spawns.get_node_or_null(
			"Spawn%d" % index
		) as Marker2D

		if marker == null:
			push_error("Missing Spawn%d." % index)
			return []

		cells.append(marker_cell(marker))

	return cells