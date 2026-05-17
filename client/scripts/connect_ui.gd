extends Control

const PALETTE_BG := Color(0.04, 0.06, 0.12, 0.92)
const PALETTE_BORDER := Color(0.40, 0.65, 1.00, 0.85)
const PALETTE_BORDER_SOFT := Color(0.30, 0.50, 0.85, 0.40)
const PALETTE_BORDER_HI := Color(0.65, 0.88, 1.00, 1.00)
const PALETTE_TITLE := Color(0.88, 0.94, 1.00)
const PALETTE_TEXT := Color(0.80, 0.88, 0.96)
const PALETTE_SUBTLE := Color(0.55, 0.72, 0.92)
const PALETTE_ACCENT := Color(0.30, 0.60, 1.00)
const PALETTE_INPUT_BG := Color(0.07, 0.10, 0.18, 0.95)
const STATUS_INFO := Color(0.55, 0.78, 0.95)
const STATUS_OK := Color(0.55, 0.92, 0.65)
const STATUS_ERR := Color(1.00, 0.55, 0.50)

const BG_SHADER_CODE := """
shader_type canvas_item;
uniform float u_time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float stars(vec2 uv, float density, float speed, float seed) {
	vec2 g = floor(uv * density + vec2(seed * 13.0, seed * 7.0));
	float h = hash(g);
	vec2 cell_uv = fract(uv * density) - 0.5;
	float d = length(cell_uv);
	float twinkle = 0.55 + 0.45 * sin(u_time * speed + h * 12.5663);
	float s = step(0.985, h) * smoothstep(0.18, 0.0, d) * twinkle;
	return s;
}

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv - 0.5;
	float r = length(centered);

	// Background gradient: deep blue centre to near-black edges.
	vec3 bg = mix(vec3(0.06, 0.10, 0.20), vec3(0.01, 0.02, 0.05), smoothstep(0.0, 0.85, r));

	// Subtle galactic band — diagonal nebula glow.
	float band = exp(-pow((centered.x * 0.6 + centered.y * 0.4) / 0.30, 2.0));
	bg += vec3(0.10, 0.18, 0.35) * band * 0.35;

	// Layered drifting stars (parallax).
	vec2 drift1 = uv + vec2(u_time * 0.005, u_time * 0.002);
	vec2 drift2 = uv + vec2(u_time * 0.012, u_time * 0.006);
	float s1 = stars(drift1, 90.0, 2.0, 1.0);
	float s2 = stars(drift2, 160.0, 3.0, 5.0);

	vec3 col = bg + vec3(0.9, 0.95, 1.0) * s1 * 0.9 + vec3(0.7, 0.85, 1.0) * s2 * 0.65;
	COLOR = vec4(col, 1.0);
}
"""

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
var _bg_mat: ShaderMaterial = null
var _bg_time: float = 0.0

func _ready() -> void:
	_install_background()
	_apply_theme()
	_replace_separators()
	_connect_btn.pressed.connect(_on_connect_pressed)
	Net.connected.connect(_on_connected)
	Net.spawned.connect(_on_spawned)
	Net.disconnected.connect(_on_disconnected)
	Net.failed.connect(_on_failed)
	_status_label.text = ""
	if OS.is_debug_build() and _name_edit.text.is_empty():
		_name_edit.text = "player%04d" % (randi() % 10000)
	_add_quit_button()
	_animate_intro()
	_install_title_pulse()
	_install_focus_pulse(_url_edit)
	_install_focus_pulse(_name_edit)

func _process(delta: float) -> void:
	if _bg_mat != null:
		_bg_time += delta
		_bg_mat.set_shader_parameter("u_time", _bg_time)

func _install_background() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)
	var sh := Shader.new()
	sh.code = BG_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	bg.material = mat
	_bg_mat = mat

func _add_quit_button() -> void:
	if OS.has_feature("web"):
		return
	var btn := Button.new()
	btn.text = "Quitter"
	_apply_button(btn)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(get_tree().quit)
	var box: VBoxContainer = $Center/Panel/Margin/Box
	box.add_child(btn)

func _apply_theme() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PALETTE_BG
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 1
	panel_style.border_color = PALETTE_BORDER
	panel_style.corner_radius_top_left = 14
	panel_style.corner_radius_top_right = 14
	panel_style.corner_radius_bottom_left = 14
	panel_style.corner_radius_bottom_right = 14
	panel_style.shadow_color = Color(0.30, 0.55, 1.00, 0.55)
	panel_style.shadow_size = 28
	panel_style.shadow_offset = Vector2(0, 6)
	_panel.add_theme_stylebox_override("panel", panel_style)

	_title.add_theme_color_override("font_color", PALETTE_TITLE)
	_title.add_theme_color_override("font_outline_color", PALETTE_BORDER)
	_title.add_theme_constant_override("outline_size", 3)
	_title.add_theme_font_size_override("font_size", 42)
	_subtitle.text = "CONNEXION AU SERVEUR"
	_subtitle.add_theme_color_override("font_color", PALETTE_SUBTLE)
	_subtitle.add_theme_font_size_override("font_size", 11)
	_url_label.add_theme_color_override("font_color", PALETTE_TEXT)
	_url_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", PALETTE_TEXT)
	_name_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", PALETTE_SUBTLE)
	_status_label.add_theme_font_size_override("font_size", 12)

	_apply_lineedit(_url_edit)
	_apply_lineedit(_name_edit)
	_apply_button(_connect_btn)
	_connect_btn.custom_minimum_size = Vector2(0, 38)
	_connect_btn.add_theme_font_size_override("font_size", 18)

func _replace_separators() -> void:
	var box: VBoxContainer = $Center/Panel/Margin/Box
	for child in box.get_children():
		if child is HSeparator:
			var idx := child.get_index()
			child.queue_free()
			var grad_sep := _make_gradient_separator()
			box.add_child(grad_sep)
			box.move_child(grad_sep, idx)

func _make_gradient_separator() -> Control:
	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(0, 1)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.30, 0.50, 0.85, 0.0),
		Color(0.55, 0.80, 1.00, 0.90),
		Color(0.30, 0.50, 0.85, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var gtex := GradientTexture1D.new()
	gtex.gradient = grad
	gtex.width = 256
	tex_rect.texture = gtex
	return tex_rect

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
	focus.shadow_color = Color(0.30, 0.55, 1.00, 0.45)
	focus.shadow_size = 8
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
	hover.border_color = PALETTE_BORDER_HI
	hover.expand_margin_left = 1
	hover.expand_margin_right = 1
	hover.expand_margin_top = 1
	hover.expand_margin_bottom = 1
	hover.shadow_color = Color(0.30, 0.55, 1.00, 0.55)
	hover.shadow_size = 10
	hover.shadow_offset = Vector2(0, 0)
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
	btn.mouse_entered.connect(_on_btn_hover_in.bind(btn))
	btn.mouse_exited.connect(_on_btn_hover_out.bind(btn))

func _on_btn_hover_in(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2(1.03, 1.03), 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_btn_hover_out(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _animate_intro() -> void:
	_panel.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.98, 0.98)
	var tw := _panel.create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _install_title_pulse() -> void:
	var tw := _title.create_tween().set_loops()
	tw.tween_property(_title, "modulate", Color(1.05, 1.05, 1.10, 1.0), 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_title, "modulate", Color(0.92, 0.92, 0.98, 1.0), 1.2).set_trans(Tween.TRANS_SINE)

func _install_focus_pulse(edit: LineEdit) -> void:
	edit.focus_entered.connect(_on_edit_focus.bind(edit, true))
	edit.focus_exited.connect(_on_edit_focus.bind(edit, false))

func _on_edit_focus(edit: LineEdit, focused: bool) -> void:
	if not is_instance_valid(edit):
		return
	var tw := edit.create_tween()
	if focused:
		edit.modulate = Color(1.0, 1.0, 1.0, 1.0)
		tw.set_loops()
		tw.tween_property(edit, "modulate", Color(1.08, 1.08, 1.15, 1.0), 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(edit, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.7).set_trans(Tween.TRANS_SINE)
	else:
		tw.tween_property(edit, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)

func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)

func _on_connect_pressed() -> void:
	var url := _url_edit.text.strip_edges()
	var player_name := _name_edit.text.strip_edges()
	if url.is_empty():
		_set_status("URL vide", STATUS_ERR)
		return
	if player_name.is_empty():
		_set_status("Pseudo vide", STATUS_ERR)
		return
	_connect_btn.disabled = true
	_set_status("Connexion…", STATUS_INFO)
	Net.connect_to(url, player_name)

func _on_connected(session_id: String) -> void:
	_session_id = session_id
	_set_status("Connecté", STATUS_OK)

func _on_spawned(_spawn: Dictionary) -> void:
	_set_status("Entrée dans le système…", STATUS_OK)
	await get_tree().create_timer(0.4).timeout
	if not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.30).set_trans(Tween.TRANS_QUAD)
	await tw.finished
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/play.tscn")

func _on_disconnected() -> void:
	_connect_btn.disabled = false
	_set_status("Déconnecté", STATUS_ERR)

func _on_failed(reason: String) -> void:
	_connect_btn.disabled = false
	_set_status("Échec : %s" % reason, STATUS_ERR)
