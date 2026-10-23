extends AudioStreamPlayer2D

enum PlaybackOrder { RANDOM, IN_ORDER }

@export var tracks: Array[AudioStream] = []
@export var playback_order: PlaybackOrder = PlaybackOrder.RANDOM

var _current_index: int = -1


func _ready() -> void:
	finished.connect(_play_next)
	_play_next()


func _play_next() -> void:
	if tracks.is_empty():
		return

	var available: Array[int] = []
	for index in range(tracks.size()):
		if tracks[index] != null:
			available.append(index)
	if available.is_empty():
		return

	if playback_order == PlaybackOrder.IN_ORDER:
		var position: int = available.find(_current_index)
		_current_index = available[(position + 1) % available.size()]
	else:
		if available.size() > 1:
			available.erase(_current_index)
		_current_index = available.pick_random()

	# Disable embedded loops on a private copy so finished can advance the playlist.
	stream = tracks[_current_index].duplicate() as AudioStream
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	play()
