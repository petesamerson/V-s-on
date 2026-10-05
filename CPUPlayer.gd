extends Node
class_name CPUPlayer

@export var player_number: int = 2

var board: Board
var recent_piece_ids: Array[int] = []


func setup(game_board: Board) -> void:
    board = game_board


func take_turn() -> void:
    if board == null or board.current_player != player_number:
        return

    var actions: Array[Dictionary] = []

    for node in board.player_pieces[player_number - 1]:
        var piece := node as Piece
        if piece == null:
            continue

        var destinations: Array[Vector2i] = (
            piece.generate_possible_moves(piece.get_cur_pos())
        )

        for destination in destinations:
            actions.append({
                "piece": piece,
                "destination": destination,
                "score": score_move(piece, destination)
            })

    if actions.is_empty():
        print("CPU has no legal moves")
        return

    var best_score: float = -INF
    for action in actions:
        best_score = maxf(best_score, action["score"])

    # Choose randomly among strong options, so one piece doesn't dominate
    # every turn when several moves are nearly as good.
    var shortlist: Array[Dictionary] = []
    for action in actions:
        if action["score"] >= best_score - 10.0:
            shortlist.append(action)

    var choice: Dictionary = shortlist.pick_random()
    var chosen_piece := choice["piece"] as Piece
    var destination: Vector2i = choice["destination"]

    recent_piece_ids.push_front(chosen_piece.get_instance_id())
    if recent_piece_ids.size() > 2:
        recent_piece_ids.pop_back()

    chosen_piece.make_cpu_move(destination)


func score_move(piece: Piece, destination: Vector2i) -> float:
    var enemy_player := 1 if player_number == 2 else 2
    var own_core := find_core(player_number)

    if own_core == null:
        return 0.0

    # Candidate destinations should be in the CPU's vision. Only inspect
    # an enemy occupying a destination the CPU can currently see.
    var captured: Piece = null
    if board.hasCellInVision(player_number, destination):
        captured = board.get_enemy_piece_at_cell(destination, enemy_player)

    if captured is CorePiece:
        return 100000.0

    var own_support_after := count_core_support(
        player_number,
        own_core.get_cur_pos(),
        piece,
        destination
    )

    var score: float = 0.0

    if captured != null:
        score += 55.0

    # Only use the enemy core's location when it is visible to the CPU.
    var visible_enemy_core := find_visible_core(enemy_player)
    if visible_enemy_core != null:
        var enemy_core_position := visible_enemy_core.get_cur_pos()

        if captured != null and captured.cur_vision.has(enemy_core_position):
            score += 30.0

        var new_vision: Array[Vector2i] = piece.get_potential_vision(destination)
        if (
            new_vision.has(enemy_core_position)
            and not piece.cur_vision.has(enemy_core_position)
        ):
            score += 18.0

        var old_distance := hex_distance(
            piece.get_cur_pos(),
            enemy_core_position
        )
        var new_distance := hex_distance(
            destination,
            enemy_core_position
        )
        score += float(old_distance - new_distance) * 2.5

    # The core must keep support. Avoid overvaluing extra defenders once
    # the core is already safe.
    if own_support_after == 0:
        score -= 100000.0
    elif own_support_after == 1:
        score -= 100.0

    # Account only for enemy pieces whose locations are visible.
    for node in board.player_pieces[enemy_player - 1]:
        var enemy_piece := node as Piece
        if enemy_piece == null or enemy_piece == captured:
            continue
        if not board.hasCellInVision(player_number, enemy_piece.get_cur_pos()):
            continue
        if enemy_piece.cur_vision.has(destination):
            score -= 8.0

    # Encourage rotating through pieces when choices are close in value.
    if recent_piece_ids.has(piece.get_instance_id()):
        score -= 14.0

    return score


func find_core(player_id: int) -> CorePiece:
    for node in board.player_pieces[player_id - 1]:
        if node is CorePiece:
            return node as CorePiece
    return null


func find_visible_core(player_id: int) -> CorePiece:
    var core := find_core(player_id)
    if core == null:
        return null

    if board.hasCellInVision(player_number, core.get_cur_pos()):
        return core
    return null


func count_core_support(
    player_id: int,
    core_position: Vector2i,
    moving_piece: Piece = null,
    destination: Vector2i = Vector2i.ZERO,
    removed_piece: Piece = null
) -> int:
    var count := 0

    for node in board.player_pieces[player_id - 1]:
        var piece := node as Piece
        if piece == null or piece is CorePiece or piece == removed_piece:
            continue

        var vision: Array[Vector2i]
        if piece == moving_piece:
            vision = piece.get_potential_vision(destination)
        else:
            vision = piece.cur_vision

        if vision.has(core_position):
            count += 1

    return count


func hex_distance(a: Vector2i, b: Vector2i) -> int:
    var cube_a := Board.offset_to_cube(a)
    var cube_b := Board.offset_to_cube(b)

    return maxi(
        maxi(abs(cube_a.x - cube_b.x), abs(cube_a.y - cube_b.y)),
        abs(cube_a.z - cube_b.z)
    )