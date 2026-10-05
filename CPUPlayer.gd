extends Node
class_name CPUPlayer

@export var player_number: int = 2

var board: Board

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

    # Keep the highest-scoring actions, then choose randomly among ties.
    var best_score: float = -INF
    var best_actions: Array[Dictionary] = []

    for action in actions:
        var score: float = action["score"]
        if score > best_score:
            best_score = score
            best_actions.clear()
            best_actions.append(action)
        elif score == best_score:
            best_actions.append(action)

    var choice: Dictionary = best_actions.pick_random()
    var chosen_piece := choice["piece"] as Piece
    var destination: Vector2i = choice["destination"]

    chosen_piece.make_cpu_move(destination)


func score_move(piece: Piece, destination: Vector2i) -> float:
    var enemy_player := 1 if player_number == 2 else 2
    var own_core := find_core(player_number)
    var enemy_core := find_core(enemy_player)

    if own_core == null or enemy_core == null:
        return 0.0

    var captured := board.get_enemy_piece_at_cell(destination, enemy_player)

    # Taking the enemy core wins immediately.
    if captured is CorePiece:
        return 100000.0

    var own_support_after := count_core_support(
        player_number,
        own_core.get_cur_pos(),
        piece,
        destination
    )
    var enemy_support_before := count_core_support(
        enemy_player,
        enemy_core.get_cur_pos()
    )
    var enemy_support_after := count_core_support(
        enemy_player,
        enemy_core.get_cur_pos(),
        null,
        Vector2i.ZERO,
        captured
    )

    var score: float = 0.0

    # Captures are useful; capturing a defender is especially valuable.
    if captured != null:
        score += 150.0
        if captured.cur_vision.has(enemy_core.get_cur_pos()):
            score += 100.0

    # Removing the enemy's last core defender should be a top priority.
    score += float(enemy_support_before - enemy_support_after) * 140.0
    if enemy_support_after == 0:
        score += 20000.0

    # Preserve safety, but only strongly penalize a move that leaves our
    # core with its last supporting piece.
    if own_support_after == 0:
        score -= 100000.0
    elif own_support_after == 1:
        score -= 250.0

    # Move pieces into positions where they can see and pursue the enemy core.
    var new_vision: Array[Vector2i] = piece.get_potential_vision(destination)
    if new_vision.has(enemy_core.get_cur_pos()):
        score += 100.0

    # Progress toward the enemy core is useful, but secondary to captures
    # and creating a direct attack.
    var old_distance := hex_distance(
        piece.get_cur_pos(),
        enemy_core.get_cur_pos()
    )
    var new_distance := hex_distance(destination, enemy_core.get_cur_pos())
    score += float(old_distance - new_distance) * 10.0

    # Keep an eye on danger without making the CPU refuse every risky move.
    for node in board.player_pieces[enemy_player - 1]:
        var enemy_piece := node as Piece
        if enemy_piece == null or enemy_piece == captured:
            continue
        if enemy_piece.cur_vision.has(destination):
            score -= 6.0

    return score

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


func find_core(player_id: int) -> CorePiece:
    for node in board.player_pieces[player_id - 1]:
        if node is CorePiece:
            return node as CorePiece
    return null


func hex_distance(a: Vector2i, b: Vector2i) -> int:
    var cube_a := Board.offset_to_cube(a)
    var cube_b := Board.offset_to_cube(b)

    return maxi(
        maxi(abs(cube_a.x - cube_b.x), abs(cube_a.y - cube_b.y)),
        abs(cube_a.z - cube_b.z)
    )