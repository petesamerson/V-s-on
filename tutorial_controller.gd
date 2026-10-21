extends Node

enum Step {
	SELECT_PIECE,
	MOVE_PIECE,
	FIND_ENEMY,
	CAPTURE_PIECE,
	WIN_GAME,
	COMPLETE
}

@onready var board: Board = $"../Board"
@onready var instructions: Label = \
	$"../TurnLayer/TutorialPanel/Instructions"

var current_step: Step = Step.SELECT_PIECE
var lesson_finished := false


func _ready() -> void:
	board.tutorial_piece_selected.connect(_on_piece_selected)
	board.tutorial_turn_completed.connect(_on_turn_completed)
	show_step()


func show_step() -> void:
	match current_step:
		Step.SELECT_PIECE:
			instructions.text = \
				"Select one of your blue pieces."

		Step.MOVE_PIECE:
			instructions.text = \
				"Move a piece to one of its highlighted tiles."

		Step.FIND_ENEMY:
			instructions.text = \
				"Find the enemy!\n" + \
				"Move your pieces to bring a red piece into vision."

		Step.CAPTURE_PIECE:
			instructions.text = \
				"Capture an enemy piece.\n" + \
				"Select a piece that can move onto an enemy's tile."

		Step.WIN_GAME:
			instructions.text = \
				"Win the game!\n" + \
				"Capture the enemy core or remove all its power.\n" + \
				"Keep your own core powered."

		Step.COMPLETE:
			instructions.text = \
				"Tutorial complete! You found the enemy, " + \
				"captured a piece, and won."


func _on_piece_selected(_piece: Piece) -> void:
	if current_step == Step.SELECT_PIECE:
		current_step = Step.MOVE_PIECE
		show_step()


func _on_turn_completed() -> void:
	if lesson_finished:
		return

	var winner := board.determine_winner()

	if winner == 1:
		lesson_finished = true
		current_step = Step.COMPLETE
		show_step()
		board.display_winner(winner)
		return

	if winner == 2:
		lesson_finished = true
		instructions.text = \
			"Your core lost its power. Restart the tutorial to try again."
		board.display_winner(winner)
		return

	if current_step == Step.MOVE_PIECE:
		current_step = Step.FIND_ENEMY

	# Separate checks allow one move to satisfy several objectives.
	if current_step == Step.FIND_ENEMY:
		if enemy_is_visible() or player_has_captured():
			current_step = Step.CAPTURE_PIECE

	if current_step == Step.CAPTURE_PIECE:
		if player_has_captured():
			current_step = Step.WIN_GAME

	show_step()


func enemy_is_visible() -> bool:
	for piece in board.player_pieces[1]:
		if board.hasCellInVision(1, piece.get_cur_pos()):
			return true

	return false


func player_has_captured() -> bool:
	return not board.player_captures[0].is_empty()