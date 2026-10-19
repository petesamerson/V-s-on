
const PLAYER_BLUE = Color("#007Bff")
const PLAYER_BLUE_POWER =  Color("#66E5FF")
const PLAYER_RED = Color("#FF1744")
const PLAYER_RED_POWER = Color("#ff7070")



# Player IDs start at 1. Add more entries to expand the palette.
const PLAYER_PALETTE = [
	PLAYER_BLUE,
	PLAYER_RED,
	Color("#31DB91"),
	Color("#FFCB47"),
	Color("#B780FF"),
	Color("#FF78CA"),
	Color("#FF913D"),
	Color("#45E0DD"),
]

static func player_color(player_id: int) -> Color:
	if player_id >= 1 and player_id <= PLAYER_PALETTE.size():
		return PLAYER_PALETTE[player_id - 1]

	return Color.from_hsv(
		fposmod(float(player_id) * 0.61803398875, 1.0),
		0.7,
		1.0
	)

static func powered_color(player_id: int) -> Color:
	if player_id == 1:
		return PLAYER_BLUE_POWER
	if player_id == 2:
		return PLAYER_RED_POWER

	return player_color(player_id).lerp(Color.WHITE, 0.38)