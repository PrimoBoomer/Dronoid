extends Node

const MUSIC_DIR := "res://assets/music/"
const VOLUME_DB := -10.0
const CROSSFADE_S := 1.5

var _player_a: AudioStreamPlayer = null
var _player_b: AudioStreamPlayer = null
var _active: AudioStreamPlayer = null
var _tracks: Array[String] = []
var _current_idx: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player_a = _make_player()
	_player_b = _make_player()
	_active = _player_a
	_scan_tracks()
	if _tracks.is_empty():
		return
	_play_next()

func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	p.volume_db = VOLUME_DB
	p.finished.connect(_on_finished)
	add_child(p)
	return p

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
	_active.stream = stream
	_active.play()

func _on_finished() -> void:
	_play_next()

func set_volume(db: float) -> void:
	_player_a.volume_db = db
	_player_b.volume_db = db
