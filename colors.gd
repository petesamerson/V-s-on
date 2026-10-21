
const PLAYER_BLUE = Color("#007Bff")
const PLAYER_BLUE_POWER =  Color("#66E5FF")
const PLAYER_RED = Color("#FF1744")
const PLAYER_RED_POWER = Color("#ff7070")

const COLOR_NAMES = [
	"Blue", "Red", "Green", "Yellow", "Purple", "Orange"
]

const PLAYER_PALETTE = [
	Color("#007BFF"),
	Color("#FF1744"),
	Color("#31DB91"),
	Color("#FFCB47"),
	Color("#B780FF"),
	Color("#FF913D")
]

const POWERED_PALETTE = [
	Color("#66E5FF"),
	Color("#FF7070"),
	Color("#80F5BC"),
	Color("#FFE596"),
	Color("#D8B5FF"),
	Color("#FFC18A")
]

# Each entry stores the selected palette index for that player.
static var selected_color_indices: Array[int] = [0, 1]


static func player_color(player_id: int) -> Color:
	return PLAYER_PALETTE[_color_index(player_id)]


static func powered_color(player_id: int) -> Color:
	return POWERED_PALETTE[_color_index(player_id)]


static func set_player_color(player_id: int, color_index: int) -> void:
	if player_id < 1:
		return
	if color_index < 0 or color_index >= PLAYER_PALETTE.size():
		return

	while selected_color_indices.size() < player_id:
		selected_color_indices.append(
			selected_color_indices.size() % PLAYER_PALETTE.size()
		)

	selected_color_indices[player_id - 1] = color_index


static func _color_index(player_id: int) -> int:
	if player_id >= 1 and player_id <= selected_color_indices.size():
		return selected_color_indices[player_id - 1]

	return posmod(player_id - 1, PLAYER_PALETTE.size())
