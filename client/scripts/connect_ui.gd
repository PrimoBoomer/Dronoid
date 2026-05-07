extends Control

const PALETTE_BG := Color(0.04, 0.06, 0.12, 0.92)
const PALETTE_BORDER := Color(0.40, 0.65, 1.00, 0.85)
const PALETTE_BORDER_SOFT := Color(0.30, 0.50, 0.85, 0.40)
const PALETTE_TITLE := Color(0.88, 0.94, 1.00)
const PALETTE_TEXT := Color(0.80, 0.88, 0.96)
const PALETTE_SUBTLE := Color(0.55, 0.72, 0.92)
const PALETTE_ACCENT := Color(0.30, 0.60, 1.00)
const PALETTE_INPUT_BG := Color(0.07, 0.10, 0.18, 0.95)

@onready var _panel: PanelContainer = $Center/Panel
@onready var _title: Label = $Center/Panel/Margin/Box/Title
@onready var _subtitle: Label = $Center/Panel/Margin/Box/Subtitle
@onready var _url_label: Label = $Center/Panel/Margin/Box/UrlLabel
@onready var _name_label: Label = $Center/Panel/Margin/Box/NameLabel
@onready var _url_edit: LineEdit = $Center/Panel/Margin/Box/UrlEdit
@onready var _name_edit: LineEdit = $Center/Panel/Margin/Box/NameEdit
@onready var _connect_btn: Button = $Center/Panel/Margin/Box/ConnectBtn
@onready var _status_label: Label = $Center/Panel/Margin/Box/StatusLabel

var _session_id: String = ""

func _ready() -> void:
	_apply_theme()
	_connect_btn.pressed.connect(_on_connect_pressed)
	Net.connected.connect(_on_connected)
	Net.spawned.connect(_on_spawned)
	Net.disconnected.connect(_on_disconnected)
	Net.failed.connect(_on_failed)
	_status_label.text = ""
	if OS.is_debug_build() and _name_edit.text.is_empty():
		_name_edit.text = "player%04d" % (randi() % 10000)

func _apply_theme() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PALETTE_BG
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = PALETTE_BORDER
	panel_style.corner_radius_top_left = 14
	panel_style.corner_radius_top_right = 14
	panel_style.corner_radius_bottom_left = 14
	panel_style.corner_radius_bottom_right = 14
	panel_style.shadow_color = Color(0.10, 0.30, 0.65, 0.45)
	panel_style.shadow_size = 18
	panel_style.shadow_offset = Vector2(0, 4)
	_panel.add_theme_stylebox_override("panel", panel_style)

	_title.add_theme_color_override("font_color", PALETTE_TITLE)
	_title.add_theme_font_size_override("font_size", 38)
	_subtitle.add_theme_color_override("font_color", PALETTE_SUBTLE)
	_subtitle.add_theme_font_size_override("font_size", 13)
	_url_label.add_theme_color_override("font_color", PALETTE_TEXT)
	_name_label.add_theme_color_override("font_color", PALETTE_TEXT)
	_status_label.add_theme_color_override("font_color", PALETTE_SUBTLE)
	_status_label.add_theme_font_size_override("font_size", 12)

	_apply_lineedit(_url_edit)
	_apply_lineedit(_name_edit)
	_apply_button(_connect_btn)

func _apply_lineedit(edit: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = PALETTE_INPUT_BG
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.border_color = PALETTE_BORDER_SOFT
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = PALETTE_BORDER
	focus.border_width_left = 2
	focus.border_width_right = 2
	focus.border_width_top = 2
	focus.border_width_bottom = 2
	edit.add_theme_stylebox_override("normal", normal)
	edit.add_theme_stylebox_override("focus", focus)
	edit.add_theme_stylebox_override("read_only", normal)
	edit.add_theme_color_override("font_color", PALETTE_TITLE)
	edit.add_theme_color_override("font_placeholder_color", Color(0.45, 0.55, 0.70))
	edit.add_theme_color_override("caret_color", PALETTE_ACCENT)
	edit.add_theme_color_override("selection_color", Color(0.30, 0.55, 1.00, 0.35))
	edit.add_theme_font_size_override("font_size", 14)

func _apply_button(btn: Button) -> void:
	var base := StyleBoxFlat.new()
	base.bg_color = Color(0.20, 0.40, 0.85, 0.85)
	base.border_width_left = 1
	base.border_width_right = 1
	base.border_width_top = 1
	base.border_width_bottom = 1
	base.border_color = PALETTE_BORDER
	base.corner_radius_top_left = 8
	base.corner_radius_top_right = 8
	base.corner_radius_bottom_left = 8
	base.corner_radius_bottom_right = 8
	base.content_margin_left = 14
	base.content_margin_right = 14
	base.content_margin_top = 8
	base.content_margin_bottom = 8
	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.30, 0.55, 1.00, 0.95)
	var pressed := base.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.18, 0.35, 0.75, 1.0)
	var disabled := base.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.15, 0.20, 0.30, 0.85)
	disabled.border_color = Color(0.30, 0.40, 0.55, 0.45)
	btn.add_theme_stylebox_override("normal", base)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", PALETTE_TITLE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.92, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.62, 0.75))
	btn.add_theme_font_size_override("font_size", 16)

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
