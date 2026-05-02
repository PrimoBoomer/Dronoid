extends Control

@onready var _url_edit: LineEdit = $Center/Panel/Margin/Box/UrlEdit
@onready var _name_edit: LineEdit = $Center/Panel/Margin/Box/NameEdit
@onready var _connect_btn: Button = $Center/Panel/Margin/Box/ConnectBtn
@onready var _status_label: Label = $Center/Panel/Margin/Box/StatusLabel

var _session_id: String = ""

func _ready() -> void:
	_connect_btn.pressed.connect(_on_connect_pressed)
	Net.connected.connect(_on_connected)
	Net.spawned.connect(_on_spawned)
	Net.disconnected.connect(_on_disconnected)
	Net.failed.connect(_on_failed)
	_status_label.text = ""
	if OS.is_debug_build() and _name_edit.text.is_empty():
		_name_edit.text = "player%04d" % (randi() % 10000)

func _on_connect_pressed() -> void:
	var url := _url_edit.text.strip_edges()
	var player_name := _name_edit.text.strip_edges()
	if url.is_empty():
		_status_label.text = "URL vide"
		return
	if player_name.is_empty():
		_status_label.text = "Pseudo vide"
		return
	_connect_btn.disabled = true
	_status_label.text = "Connexion…"
	Net.connect_to(url, player_name)

func _on_connected(session_id: String) -> void:
	_session_id = session_id
	_status_label.text = "Connecté (session %s)" % session_id

func _on_spawned(spawn: Dictionary) -> void:
	var system: Dictionary = spawn.get("system", {})
	var star: Dictionary = system.get("star", {})
	var planets: Array = system.get("planets", [])
	var gpos: Array = system.get("galactic_pos", [0, 0, 0])
	var first_time: bool = bool(spawn.get("first_time", false))
	_status_label.text = "Connecté (%s) — %s @ (%.1f, %.1f, %.1f) — %d planètes — first_time=%s" % [
		_session_id,
		String(star.get("name", "?")),
		float(gpos[0]), float(gpos[1]), float(gpos[2]),
		planets.size(),
		str(first_time),
	]
	await get_tree().create_timer(0.4).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/play.tscn")

func _on_disconnected() -> void:
	_connect_btn.disabled = false
	_status_label.text = "Déconnecté"

func _on_failed(reason: String) -> void:
	_connect_btn.disabled = false
	_status_label.text = "Échec : %s" % reason
