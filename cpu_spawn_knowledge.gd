extends RefCounted

var models: Array[Dictionary] = []
var sightings: Dictionary = {}
var forecast: Dictionary = {}
var confidence: float = 1.0


func initialize(board: Board, player: int) -> void:
	models.clear()
	sightings.clear()
	forecast.clear()

	var own_core: CorePiece = null

	for node in board.player_pieces[player - 1]:
		if node is CorePiece:
			own_core = node as CorePiece
			break

	if own_core == null:
		return

	var centers: Array[Vector2i] = (
		board.get_possible_spawn_locations()
	)
	var own_index: int = centers.find(own_core.get_cur_pos())

	if own_index < 0:
		return

	# Same spawn and adjacent spawns are forbidden.
	for offset in [2, 3, 4]:
		var index: int = posmod(own_index + int(offset), 6)
		var center: Vector2i = centers[index]

		models.append({
			"center": center,
			"layout": _make_layout(board, center),
			"weight": 1.0 / 3.0,
		})


func _make_layout(
	board: Board,
	center: Vector2i
) -> Dictionary:
	var layout: Dictionary = {}

	layout[center] = "core"
	layout[center + Vector2i(-1, 0)] = "eye"
	layout[center + Vector2i(1, 0)] = "eye"

	for direction in range(6):
		var outer: Array[Vector2i] = (
			board.get_line_from_center(center, direction, 3)
		)
		layout[outer.back()] = "hop"

		var inner: Array[Vector2i] = (
			board.get_line_from_center(center, direction, 2)
		)

		layout[inner[2]] = (
			"triangle_odd"
			if direction % 2 == 0
			else "triangle_even"
		)

		var adjacent: Array[Vector2i] = (
			board.get_line_from_center(
				center, (direction + 1) % 6, 2
			)
		)

		var cross_line: Array[Vector2i] = board.hex_line(
			inner.back(),
			adjacent.back()
		)

		layout[cross_line[cross_line.size() / 2]] = "tower"

	return layout


func _kind(piece: Piece) -> String:
	if piece is CorePiece:
		return "core"
	if piece is EyePiece:
		return "eye"
	if piece is HopPiece:
		return "hop"
	if piece is TriangleOddPiece:
		return "triangle_odd"
	if piece is TriangleEvenPiece:
		return "triangle_even"
	if piece is TowerRotatePiece:
		return "tower"

	return "unknown"


func observe(
	board: Board,
	player: int,
	level: int,
	turn_number: int
) -> void:
	forecast.clear()

	if level < 4:
		return

	var opponent: int = 2 if player == 1 else 1

	# Record the first visible sighting of each enemy.
	# Never use a hidden piece's position as evidence.
	for node in board.player_pieces[opponent - 1]:
		var enemy := node as Piece

		if enemy == null:
			continue

		var cell := enemy.get_cur_pos()

		if not board.hasCellInVision(player, cell):
			continue

		var enemy_id: int = enemy.get_instance_id()

		if not sightings.has(enemy_id):
			sightings[enemy_id] = {
				"cell": cell,
				"kind": _kind(enemy),
				"turn": turn_number,
			}

	var total_weight: float = 0.0

	for model in models:
		var weight: float = 1.0
		var layout: Dictionary = model["layout"]

		# Hard retains equal starting probabilities.
		if level >= 5:
			for observation in sightings.values():
				var first_turn: int = int(observation["turn"])

				# Late sightings tell us little about the
				# original formation.
				if first_turn > 5:
					continue

				var reliability: float = pow(
					0.65,
					float(first_turn - 1)
				)

				var expected_kind: String = str(
					layout.get(observation["cell"], "")
				)

				if expected_kind == str(observation["kind"]):
					var strength: float = (
						1.4 if level >= 6 else 0.8
					)
					weight *= 1.0 + strength * reliability
				else:
					# A moved piece can fail to match its
					# true starting formation.
					weight *= 1.0 - 0.15 * reliability

		model["weight"] = weight
		total_weight += weight

	if total_weight <= 0.0:
		return

	# Starting positions become less reliable as play continues.
	confidence = pow(
		0.88,
		float(maxi(turn_number - 1, 0))
	)

	for model in models:
		model["weight"] = float(model["weight"]) / total_weight

		var layout: Dictionary = model["layout"]
		var probability: float = float(model["weight"])

		for cell in layout:
			if not board.cell_in_board(cell):
				continue
			if board.hasCellInVision(player, cell):
				continue

			forecast[cell] = (
				float(forecast.get(cell, 0.0))
				+ probability
			)


func vision_bonus(vision: Array[Vector2i]) -> float:
	var information: float = 0.0

	for cell in vision:
		information += float(forecast.get(cell, 0.0))

	return information * 10.0 * confidence


func _distance(a: Vector2i, b: Vector2i) -> int:
	var first := Board.offset_to_cube(a)
	var second := Board.offset_to_cube(b)

	return maxi(
		maxi(
			abs(first.x - second.x),
			abs(first.y - second.y)
		),
		abs(first.z - second.z)
	)


func score_move(
	piece: Piece,
	old_position: Vector2i,
	destination: Vector2i,
	board: Board
) -> float:
	if models.is_empty():
		return 0.0

	var value: float = maxf(1.0, float(piece.piece_value))
	var cheap_scout: float = 1.0 / (1.0 + value * 0.75)

	var vision: Array[Vector2i] = piece.get_potential_vision(
		destination
	)

	var approach: float = 0.0

	for model in models:
		var center: Vector2i = model["center"]

		if board.hasCellInVision(piece.owned_player, center):
			continue

		approach += (
			float(model["weight"])
			* float(
				_distance(old_position, center)
				- _distance(destination, center)
			)
		)

	var old_exposure: float = 0.0
	var new_exposure: float = 0.0

	for cell in forecast:
		var probability: float = float(forecast[cell])

		old_exposure = maxf(
			old_exposure,
			probability * maxf(
				0.0,
				1.0 - float(_distance(old_position, cell)) / 3.0
			)
		)

		new_exposure = maxf(
			new_exposure,
			probability * maxf(
				0.0,
				1.0 - float(_distance(destination, cell)) / 3.0
			)
		)

	var reward: float = (
		vision_bonus(vision)
		+ approach * 12.0 * confidence
	) * cheap_scout

	# Expert is more cautious about sending valuable pieces
	# into a likely starting formation.
	var uncertainty_cost: float = (
		maxf(new_exposure - old_exposure, 0.0)
		* value * value
		* 3.0
		* confidence
	)

	return clampf(reward - uncertainty_cost, -120.0, 120.0)