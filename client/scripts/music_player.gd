extends Node

const MUSIC_DIR := "res://assets/music/"
const VOLUME_DB := -10.0

var _player: AudioStreamPlayer = null
var _tracks: Array[String] = []
var _current_idx: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.volume_db = VOLUME_DB
	_player.finished.connect(_on_finished)
	add_child(_player)
	_scan_tracks()
	if _tracks.is_empty():
		return
	_play_next()

func _scan_tracks() -> void:
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		push_warning("MusicPlayer: directory %s not found" % MUSIC_DIR)
		return
	dir.list_dir_begin()
	while true:
		var fname := dir.get_next()
		if fname.is_empty():
			break
		if dir.current_is_dir():
			continue
		var lower := fname.to_lower()
		if lower.ends_with(".ogg") or lower.ends_with(".wav") or lower.ends_with(".mp3"):
			_tracks.append(MUSIC_DIR + fname)
	dir.list_dir_end()
	_tracks.shuffle()

func _play_next() -> void:
	if _tracks.is_empty():
		return
	_current_idx = (_current_idx + 1) % _tracks.size()
	var stream := load(_tracks[_current_idx]) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	_player.stream = stream
	_player.play()

func _on_finished() -> void:
	_play_next()

func set_volume(db: float) -> void:
	_player.volume_db = db
