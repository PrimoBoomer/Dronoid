extends Node3D

@export var thrust_accel: float = 10.0
@export var max_speed: float = 45.0
@export var brake_decel: float = 25.0
@export var mouse_sensitivity: float = 0.0012
@export var camera_lag: float = 6.0
@export var camera_offset: Vector3 = Vector3(0.0, 6.0, 28.0)

const ORBIT_SENSITIVITY: float = 0.0035
const ORBIT_PITCH_LIMIT: float = 1.35

const PLANET_VISUAL_SCALE: float = 3.5
const MOON_VISUAL_SCALE: float = 4.5
const ASTEROID_VISUAL_SCALE: float = 4.0
const STAR_VISUAL_SCALE: float = 2.2

const STAR_SEGMENTS := Vector2i(96, 48)
const PLANET_SEGMENTS := Vector2i(96, 48)
const MOON_SEGMENTS := Vector2i(64, 32)
const ASTEROID_SEGMENTS := Vector2i(12, 6)
const FAR_STAR_SEGMENTS := Vector2i(20, 10)

var _planet_textures: Array = []
var _moon_textures: Array = []
var _asteroid_texture: Texture2D = null
var _bh_sprite_texture: Texture2D = null

@onready var _ship: Node3D = $Ship
@onready var _cam: Camera3D = $ChaseCam
var _status: Label = null

var _pause_layer: CanvasLayer = null
var _pause_root: Control = null
var _paused: bool = false

var _velocity: Vector3 = Vector3.ZERO
var _captured: bool = false

var _epoch_ms: int = 0
var _orbiters: Array = []

var _belt_mm: MultiMesh = null
var _belt_phases: PackedFloat32Array = PackedFloat32Array()
var _belt_omegas: PackedFloat32Array = PackedFloat32Array()
var _belt_radii_orbit: PackedFloat32Array = PackedFloat32Array()
var _belt_ys: PackedFloat32Array = PackedFloat32Array()
var _belt_scales: PackedFloat32Array = PackedFloat32Array()
var _belt_ids: PackedInt64Array = PackedInt64Array()
var _belt_alive: PackedByteArray = PackedByteArray()
var _belt_id_to_idx: Dictionary = {}

const MAX_MINE_RANGE: float = 60.0
const HOVER_RANGE: float = 800.0
const MINE_INTERVAL_MS: int = 150
const PICK_TOLERANCE: float = 1.5
const AUTOPILOT_TURN_RATE: float = 1.6
const AUTOPILOT_BRAKE_SAFETY: float = 1.2
const AUTOPILOT_CANCEL_MOUSE: float = 80.0

var _alt_held: bool = false
var _orbit_active: bool = false
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = 0.0
var _orbit_distance: float = 28.0
var _last_mine_ms: int = 0
var _beam_mi: MeshInstance3D = null
var _beam_impact: MeshInstance3D = null

var _action_kind: String = ""
var _action_target_kind: String = ""
var _action_target_idx: int = -1
var _action_target_node: Node3D = null
var _action_stop_distance: float = 0.0
var _action_pending_mine: bool = false
var _autopilot_mouse_accum: float = 0.0
var _mining: bool = false
var _mining_target_idx: int = -1
var _current_target_idx: int = -1

var _hover_target_kind: String = ""
var _hover_target_idx: int = -1
var _hover_target_node: Node3D = null
var _hover_world_pos: Vector3 = Vector3.ZERO
var _hover_radius_visual: float = 0.0

var _ctx_layer: CanvasLayer = null
var _ctx_panel: PanelContainer = null
var _ctx_vbox: VBoxContainer = null
var _ctx_open: bool = false
var _ctx_target_kind: String = ""
var _ctx_target_idx: int = -1
var _ctx_target_node: Node3D = null
var _ctx_target_radius: float = 0.0

var _pickable_static: Array = []

var _belt_stock: PackedInt32Array = PackedInt32Array()
var _belt_kinds: PackedStringArray = PackedStringArray()
var _belt_initial_stock: PackedInt32Array = PackedInt32Array()

var _tooltip_layer: CanvasLayer = null
var _tooltip_panel: PanelContainer = null
var _tooltip_label: Label = null
var _tooltip_connector: Line2D = null
var _connector_target: Vector2 = Vector2.ZERO
var _connector_initialized: bool = false

var _inv_labels: Dictionary = {}
const INV_KINDS := ["iron", "copper", "silicon", "ice"]
const INV_DISPLAY := {
	"iron": "Fe",
	"copper": "Cu",
	"silicon": "Si",
	"ice": "H2O",
}
const ASTEROID_KIND_LABEL := {
	"iron": "Fer",
	"copper": "Cuivre",
	"silicon": "Silicium",
	"ice": "Glace",
}

const KIND_POPUP_COLOR := {
	"iron":    Color(1.00, 0.78, 0.55),
	"copper":  Color(1.00, 0.65, 0.30),
	"silicon": Color(0.75, 0.90, 1.00),
	"ice":     Color(0.85, 0.97, 1.00),
}

const UI_BORDER := Color(0.40, 0.65, 1.00, 0.85)
const UI_BORDER_SOFT := Color(0.30, 0.50, 0.85, 0.45)
const UI_TITLE := Color(0.88, 0.94, 1.00)
const UI_TEXT := Color(0.80, 0.88, 0.96)
const UI_SUBTLE := Color(0.55, 0.72, 0.92)
const UI_BTN_NORMAL := Color(0.20, 0.40, 0.85, 0.85)

const BEAM_BASE_THICKNESS: float = 0.35
const BEAM_TIP_THICKNESS: float = 0.18
const BEAM_PULSE_RATE: float = 9.0
const BEAM_BASE_EMISSION: float = 4.0

const DRONE_COST := {"iron": 20, "copper": 10, "silicon": 5}
const FACTORY_COST := {"iron": 200, "copper": 100, "silicon": 80, "ice": 50}

var _inv_state: Dictionary = {"iron": 0, "copper": 0, "silicon": 0, "ice": 0}
var _drones_state: Array = []
var _factories_state: Array = []

var _inv_panel_layer: CanvasLayer = null
var _inv_panel_root: Control = null
var _inv_panel_visible: bool = false
var _inv_drone_btn: Button = null
var _inv_factory_btn: Button = null
var _inv_drone_cost_lbl: Label = null
var _inv_factory_cost_lbl: Label = null
var _inv_drones_list: VBoxContainer = null
var _inv_drones_title: Label = null
var _inv_factories_list: VBoxContainer = null
var _inv_factories_title: Label = null
var _inv_status_lbl: Label = null
var _inv_order_all_btn: Button = null

var _drone_submenu_layer: CanvasLayer = null
var _drone_submenu_panel: PanelContainer = null
var _drone_submenu_vbox: VBoxContainer = null
var _drone_submenu_drone_id: int = -1
var _drone_submenu_open: bool = false

var _drone_view_layer: CanvasLayer = null
var _drone_view_panel: PanelContainer = null
var _drone_view_info_lbl: Label = null
var _drone_view_subviewport: SubViewport = null
var _drone_view_camera: Camera3D = null
var _drone_view_target_id: int = -1
var _drone_view_open: bool = false

var _drone_hud_layer: CanvasLayer = null
var _drone_hud_root: Control = null
var _drone_hud_widgets: Array = []

var _cheat_layer: CanvasLayer = null

var _pause_dim: ColorRect = null
var _pause_panel: PanelContainer = null

const DRONE_STATE_LABEL := {
	"idle": "Inactif",
	"to_target": "En route",
	"mining": "En minage",
	"returning": "Retour",
}

var _drone_nodes: Array = []
var _drone_beams: Array = []
var _drone_target_pos: Array = []
var _drone_target_vel: Array = []
var _drone_target_t_ms: int = 0
var _factory_nodes: Array = []
const DRONE_FORMATION_RADIUS: float = 14.0
const DRONE_FORMATION_HEIGHT: float = 2.5
const DRONE_VISUAL_SCALE: float = 2.4
const DRONE_MINE_RANGE_VISUAL: float = 8.0
const DRONE_RECONCILE_RATE: float = 6.0
const DRONE_EXTRAPOLATE_CAP_S: float = 0.30

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SkyBackground.set_active(false)
	_capture_mouse(true)
	var spawn: Dictionary = Net.current_spawn
	var sys: Dictionary = spawn.get("system", {}) as Dictionary
	var star: Dictionary = sys.get("star", {}) as Dictionary
	var planets: Array = sys.get("planets", []) as Array
	var asteroids: Array = spawn.get("asteroids", []) as Array
	var black_hole: Dictionary = spawn.get("black_hole", {}) as Dictionary
	var far_stars: Array = spawn.get("far_stars", []) as Array
	_epoch_ms = int(sys.get("epoch_ms", 0))

	var sname := String(star.get("name", "?"))
	var status_text := "%s — %d planètes • %d astéroïdes • %d étoiles distantes" % [
		sname, planets.size(), asteroids.size(), far_stars.size()
	]

	_generate_textures()
	_build_system(star, planets)
	_build_asteroid_belt(asteroids)
	_build_far_objects(star, black_hole, far_stars)
	_place_ship(spawn, star)
	_snap_camera_to_ship()
	_build_pause_menu()
	_build_inventory_hud()
	_build_inputs_hud()
	_build_mining_beam()
	_build_tooltip_ui()
	_build_context_menu()
	_build_inventory_panel()
	_build_drone_submenu()
	_build_drone_view()
	_build_drone_hud()
	if OS.is_debug_build():
		_build_cheat_panel()
	if _status != null:
		_status.text = status_text
	_apply_inventory(spawn.get("inventory", {}) as Dictionary)
	_drones_state = (spawn.get("drones", []) as Array).duplicate()
	_factories_state = (spawn.get("factories", []) as Array).duplicate()
	_refresh_drones_visuals()
	_refresh_factories_visuals()

	Net.mine_tick.connect(_on_mine_tick)
	Net.asteroid_depleted.connect(_on_asteroid_depleted)
	Net.mine_reject.connect(_on_mine_reject)
	Net.build_result.connect(_on_build_result)
	Net.drone_tick.connect(_on_drone_tick)
	Net.order_result.connect(_on_order_result)

func _build_system(star: Dictionary, planets: Array) -> void:
	var system_root := Node3D.new()
	system_root.name = "System"
	add_child(system_root)

	var star_radius := float(star.get("radius", 1.0)) * STAR_VISUAL_SCALE

	var star_mesh := MeshInstance3D.new()
	star_mesh.name = "Star"
	var star_sphere := SphereMesh.new()
	star_sphere.radius = star_radius
	star_sphere.height = star_radius * 2.0
	star_sphere.radial_segments = STAR_SEGMENTS.x
	star_sphere.rings = STAR_SEGMENTS.y
	star_mesh.mesh = star_sphere
	var star_color_arr: Array = star.get("color", [1.0, 1.0, 0.9]) as Array
	var star_color := Color(float(star_color_arr[0]), float(star_color_arr[1]), float(star_color_arr[2]), 1.0)
	var star_visual_color := star_color.lerp(Color.WHITE, 0.45)
	var star_mat := StandardMaterial3D.new()
	star_mat.albedo_color = star_visual_color
	star_mat.emission_enabled = true
	star_mat.emission = star_visual_color
	star_mat.emission_energy_multiplier = 4.0
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mesh.material_override = star_mat
	system_root.add_child(star_mesh)
	_pickable_static.append({
		"kind": "star",
		"name": String(star.get("name", "?")),
		"node": star_mesh,
		"radius_visual": star_radius,
		"description": "Étoile %s\nRayon : %.1f ku" % [String(star.get("name", "?")), star_radius],
	})

	var star_light := OmniLight3D.new()
	star_light.name = "StarLight"
	star_light.light_color = star_color
	star_light.light_energy = 6.0
	star_light.omni_range = 4096.0
	star_light.omni_attenuation = 0.5
	system_root.add_child(star_light)

	for p in planets:
		var planet: Dictionary = p as Dictionary
		var p_orbit := float(planet.get("orbit_radius", 5.0))
		var p_phase := float(planet.get("phase", 0.0))
		var p_omega := float(planet.get("omega", 0.0))
		var p_radius := float(planet.get("radius", 0.5))
		var p_color_arr: Array = planet.get("color", [0.7, 0.7, 0.7]) as Array
		var p_color := Color(float(p_color_arr[0]), float(p_color_arr[1]), float(p_color_arr[2]), 1.0)

		var pivot := Node3D.new()
		pivot.name = String(planet.get("name", "P"))
		system_root.add_child(pivot)
		_orbiters.append({"node": pivot, "phase": p_phase, "omega": p_omega})

		var planet_node := Node3D.new()
		planet_node.position = Vector3(p_orbit, 0.0, 0.0)
		pivot.add_child(planet_node)

		var planet_visual_r := p_radius * PLANET_VISUAL_SCALE
		var planet_mesh := MeshInstance3D.new()
		var planet_sphere := SphereMesh.new()
		planet_sphere.radius = planet_visual_r
		planet_sphere.height = planet_visual_r * 2.0
		planet_sphere.radial_segments = PLANET_SEGMENTS.x
		planet_sphere.rings = PLANET_SEGMENTS.y
		planet_mesh.mesh = planet_sphere
		var planet_mat := StandardMaterial3D.new()
		planet_mat.albedo_color = p_color
		planet_mat.roughness = 0.85
		if not _planet_textures.is_empty():
			var idx_p: int = abs(hash(String(planet.get("name", "P")))) % _planet_textures.size()
			planet_mat.albedo_texture = _planet_textures[idx_p]
		planet_mesh.material_override = planet_mat
		planet_node.add_child(planet_mesh)
		_pickable_static.append({
			"kind": "planet",
			"name": String(planet.get("name", "P")),
			"node": planet_mesh,
			"radius_visual": planet_visual_r,
			"description": "Planète %s\nOrbite : %.1f ku\nRayon : %.2f ku" % [
				String(planet.get("name", "P")), p_orbit, p_radius
			],
		})

		var moons: Array = planet.get("moons", []) as Array
		for m in moons:
			var moon: Dictionary = m as Dictionary
			var m_orbit := float(moon.get("orbit_radius", 1.0))
			var m_phase := float(moon.get("phase", 0.0))
			var m_omega := float(moon.get("omega", 0.0))
			var m_radius := float(moon.get("radius", 0.1))
			var m_color_arr: Array = moon.get("color", [0.8, 0.8, 0.8]) as Array
			var m_color := Color(float(m_color_arr[0]), float(m_color_arr[1]), float(m_color_arr[2]), 1.0)

			var moon_pivot := Node3D.new()
			moon_pivot.name = String(moon.get("name", "M"))
			planet_node.add_child(moon_pivot)
			_orbiters.append({"node": moon_pivot, "phase": m_phase, "omega": m_omega})

			var moon_visual_r := m_radius * MOON_VISUAL_SCALE
			var moon_mesh := MeshInstance3D.new()
			moon_mesh.position = Vector3(m_orbit, 0.0, 0.0)
			var moon_sphere := SphereMesh.new()
			moon_sphere.radius = moon_visual_r
			moon_sphere.height = moon_visual_r * 2.0
			moon_sphere.radial_segments = MOON_SEGMENTS.x
			moon_sphere.rings = MOON_SEGMENTS.y
			moon_mesh.mesh = moon_sphere
			var moon_mat := StandardMaterial3D.new()
			moon_mat.albedo_color = m_color
			moon_mat.roughness = 0.9
			if not _moon_textures.is_empty():
				var idx_m: int = abs(hash(String(moon.get("name", "M")))) % _moon_textures.size()
				moon_mat.albedo_texture = _moon_textures[idx_m]
			moon_mesh.material_override = moon_mat
			moon_pivot.add_child(moon_mesh)
			_pickable_static.append({
				"kind": "moon",
				"name": String(moon.get("name", "M")),
				"node": moon_mesh,
				"radius_visual": moon_visual_r,
				"description": "Lune %s\nOrbite locale : %.2f ku\nRayon : %.2f ku" % [
					String(moon.get("name", "M")), m_orbit, m_radius
				],
			})

func _build_asteroid_belt(asteroids: Array) -> void:
	if asteroids.is_empty():
		return

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "AsteroidBelt"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = ASTEROID_SEGMENTS.x
	sphere.rings = ASTEROID_SEGMENTS.y
	mm.mesh = sphere
	mm.instance_count = asteroids.size()
	mmi.multimesh = mm

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	if _asteroid_texture != null:
		mat.albedo_texture = _asteroid_texture
	mmi.material_override = mat
	add_child(mmi)
	_belt_mm = mm

	_belt_phases.resize(asteroids.size())
	_belt_omegas.resize(asteroids.size())
	_belt_radii_orbit.resize(asteroids.size())
	_belt_ys.resize(asteroids.size())
	_belt_scales.resize(asteroids.size())
	_belt_ids.resize(asteroids.size())
	_belt_alive.resize(asteroids.size())
	_belt_stock.resize(asteroids.size())
	_belt_kinds.resize(asteroids.size())
	_belt_initial_stock.resize(asteroids.size())
	_belt_id_to_idx.clear()

	for i in asteroids.size():
		var a: Dictionary = asteroids[i] as Dictionary
		_belt_phases[i] = float(a.get("phase", 0.0))
		_belt_omegas[i] = float(a.get("omega", 0.0))
		_belt_radii_orbit[i] = float(a.get("orbit_radius", 1.0))
		_belt_ys[i] = float(a.get("orbit_y", 0.0))
		_belt_scales[i] = float(a.get("radius", 0.1)) * ASTEROID_VISUAL_SCALE
		var aid := int(a.get("id", 0))
		_belt_ids[i] = aid
		_belt_alive[i] = 1
		_belt_id_to_idx[aid] = i
		_belt_kinds[i] = String(a.get("kind", "iron"))
		_belt_stock[i] = int(a.get("stock", 0))
		_belt_initial_stock[i] = int(a.get("stock", 0))
		var c_arr: Array = a.get("color", [0.6, 0.6, 0.6]) as Array
		mm.set_instance_color(i, Color(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]), 1.0))

	_update_belt_transforms(0.0)

func _build_far_objects(star: Dictionary, black_hole: Dictionary, far_stars: Array) -> void:
	if black_hole.is_empty() and far_stars.is_empty():
		return

	var far_root := Node3D.new()
	far_root.name = "FarObjects"
	add_child(far_root)

	var my_gpos_arr: Array = star.get("galactic_pos", [0.0, 0.0, 0.0]) as Array
	var my_gpos := Vector3(float(my_gpos_arr[0]), float(my_gpos_arr[1]), float(my_gpos_arr[2]))

	if not black_hole.is_empty():
		var bh_radius := float(black_hole.get("radius", 200.0))
		var bh_pos := -my_gpos
		var dist := bh_pos.length()
		var sprite_size: float = max(bh_radius * 4.0, dist * 0.04)
		var bh_sprite := Sprite3D.new()
		bh_sprite.name = "BlackHole"
		bh_sprite.position = bh_pos
		bh_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bh_sprite.shaded = false
		bh_sprite.transparent = true
		bh_sprite.no_depth_test = false
		bh_sprite.pixel_size = sprite_size / 256.0
		bh_sprite.texture = _bh_sprite_texture
		far_root.add_child(bh_sprite)

	for s in far_stars:
		var fs: Dictionary = s as Dictionary
		var gpos_arr: Array = fs.get("galactic_pos", [0.0, 0.0, 0.0]) as Array
		var gpos := Vector3(float(gpos_arr[0]), float(gpos_arr[1]), float(gpos_arr[2]))
		var rel := gpos - my_gpos
		var dist := rel.length()
		var real_r := float(fs.get("radius", 10.0))
		var visual_r: float = max(real_r, dist * 0.002)
		var fs_mesh := MeshInstance3D.new()
		fs_mesh.name = "FarStar_" + String(fs.get("name", "?"))
		fs_mesh.position = rel
		var fs_sphere := SphereMesh.new()
		fs_sphere.radius = visual_r
		fs_sphere.height = visual_r * 2.0
		fs_sphere.radial_segments = FAR_STAR_SEGMENTS.x
		fs_sphere.rings = FAR_STAR_SEGMENTS.y
		fs_mesh.mesh = fs_sphere
		var c_arr: Array = fs.get("color", [1.0, 1.0, 1.0]) as Array
		var c := Color(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]), 1.0)
		var fs_mat := StandardMaterial3D.new()
		fs_mat.albedo_color = c
		fs_mat.emission_enabled = true
		fs_mat.emission = c
		fs_mat.emission_energy_multiplier = 2.0
		fs_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fs_mesh.material_override = fs_mat
		far_root.add_child(fs_mesh)

func _place_ship(spawn: Dictionary, star: Dictionary) -> void:
	var pos_arr: Array = spawn.get("position", [0.0, 0.0, 0.0]) as Array
	var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	if pos == Vector3.ZERO:
		var star_radius := float(star.get("radius", 1.0))
		pos = Vector3(0.0, 0.0, star_radius * 6.0)
	_ship.position = pos
	_ship.look_at(Vector3.ZERO, Vector3.UP)

func _style_label_title(lbl: Label, size: int = 16, accent: Color = UI_BORDER_SOFT) -> void:
	lbl.theme_type_variation = &"TitleLabel"
	if size != 16:
		lbl.add_theme_font_size_override("font_size", size)
	if accent != UI_BORDER_SOFT:
		lbl.add_theme_color_override("font_outline_color", accent)

func _make_gradient_separator(h: int = 1) -> Control:
	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(0, h)
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

func _attach_button_hover_anim(btn: Button) -> void:
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

func _pulse_label(lbl: Label, color: Color = Color(1.6, 1.6, 1.6, 1.0), dur: float = 0.30) -> void:
	if not is_instance_valid(lbl):
		return
	var tw := lbl.create_tween()
	lbl.modulate = color
	tw.tween_property(lbl, "modulate", Color.WHITE, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _tint_button(btn: Button, tint: Color) -> void:
	var normal := (btn.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
	var hover := (btn.get_theme_stylebox("hover") as StyleBoxFlat).duplicate() as StyleBoxFlat
	var pressed := (btn.get_theme_stylebox("pressed") as StyleBoxFlat).duplicate() as StyleBoxFlat
	var tint_bg := Color(tint.r * 0.45, tint.g * 0.45, tint.b * 0.55, 0.85)
	var tint_hover := Color(tint.r * 0.65, tint.g * 0.65, tint.b * 0.75, 0.95)
	var tint_pressed := Color(tint.r * 0.35, tint.g * 0.35, tint.b * 0.50, 1.0)
	normal.bg_color = tint_bg
	hover.bg_color = tint_hover
	pressed.bg_color = tint_pressed
	normal.border_color = tint.lerp(Color.WHITE, 0.3)
	hover.border_color = tint.lerp(Color.WHITE, 0.5)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)

func _build_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "PauseMenu"
	_pause_layer.layer = 10
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)

	_pause_dim = ColorRect.new()
	_pause_dim.color = Color(0.02, 0.04, 0.10, 0.65)
	_pause_dim.anchor_right = 1.0
	_pause_dim.anchor_bottom = 1.0
	_pause_layer.add_child(_pause_dim)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	_pause_layer.add_child(center)

	_pause_panel = PanelContainer.new()
	_pause_panel.custom_minimum_size = Vector2(320, 0)
	_pause_panel.theme_type_variation = &"HeroPanel"
	center.add_child(_pause_panel)
	var panel := _pause_panel

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Pause"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label_title(title, 30, Color(0.55, 0.85, 1.00, 0.85))
	box.add_child(title)

	box.add_child(_make_gradient_separator())

	var resume_btn := Button.new()
	resume_btn.text = "Reprendre"
	resume_btn.custom_minimum_size = Vector2(240, 0)
	_attach_button_hover_anim(resume_btn)
	resume_btn.pressed.connect(_on_resume_pressed)
	box.add_child(resume_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quitter au menu"
	quit_btn.custom_minimum_size = Vector2(240, 0)
	_attach_button_hover_anim(quit_btn)
	quit_btn.pressed.connect(_on_quit_to_menu_pressed)
	box.add_child(quit_btn)

	if not OS.has_feature("web"):
		var quit_game_btn := Button.new()
		quit_game_btn.text = "Quitter le jeu"
		quit_game_btn.custom_minimum_size = Vector2(240, 0)
		_attach_button_hover_anim(quit_game_btn)
		quit_game_btn.pressed.connect(_on_quit_game_pressed)
		box.add_child(quit_game_btn)

	_pause_root = center
	_pause_layer.visible = false

func _toggle_pause() -> void:
	if _paused:
		_resume()
	else:
		_pause()

func _pause() -> void:
	_paused = true
	get_tree().paused = true
	_pause_layer.visible = true
	_capture_mouse(false)
	if _pause_dim != null and _pause_panel != null:
		_pause_dim.color.a = 0.0
		_pause_panel.modulate.a = 0.0
		_pause_panel.pivot_offset = _pause_panel.size * 0.5
		_pause_panel.scale = Vector2(0.95, 0.95)
		var tw := _pause_layer.create_tween().set_parallel(true)
		tw.tween_property(_pause_dim, "color:a", 0.65, 0.18).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(_pause_panel, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(_pause_panel, "scale", Vector2(1.0, 1.0), 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _resume() -> void:
	_paused = false
	get_tree().paused = false
	_pause_layer.visible = false
	_capture_mouse(true)

func _on_resume_pressed() -> void:
	_resume()

func _on_quit_game_pressed() -> void:
	get_tree().quit()

func _on_quit_to_menu_pressed() -> void:
	get_tree().paused = false
	Net.disconnect_now()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/connect.tscn")

func _snap_camera_to_ship() -> void:
	_cam.global_transform = _ideal_cam_transform()

func _ideal_cam_transform() -> Transform3D:
	var ideal_pos: Vector3 = _ship.global_transform * camera_offset
	var up: Vector3 = _ship.global_transform.basis.y
	return Transform3D(Basis.IDENTITY, ideal_pos).looking_at(_ship.global_position, up)

func _orbit_cam_transform() -> Transform3D:
	var cp := cos(_orbit_pitch)
	var dir := Vector3(sin(_orbit_yaw) * cp, sin(_orbit_pitch), cos(_orbit_yaw) * cp)
	var pos := _ship.global_position + dir * _orbit_distance
	return Transform3D(Basis.IDENTITY, pos).looking_at(_ship.global_position, Vector3.UP)

func _enter_orbit() -> void:
	var rel := _cam.global_position - _ship.global_position
	var dist: float = rel.length()
	if dist < 1.0:
		rel = -_ship.global_transform.basis.z * camera_offset.length()
		dist = rel.length()
	_orbit_distance = dist
	var horiz: float = sqrt(rel.x * rel.x + rel.z * rel.z)
	_orbit_pitch = clampf(atan2(rel.y, horiz), -ORBIT_PITCH_LIMIT, ORBIT_PITCH_LIMIT)
	_orbit_yaw = atan2(rel.x, rel.z)
	_orbit_active = true

func _exit_orbit() -> void:
	_orbit_active = false

func _capture_mouse(capture: bool) -> void:
	_captured = capture
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE)

func _refresh_mouse_capture() -> void:
	var should_capture := not _paused \
		and not _ctx_open \
		and not _alt_held \
		and not _inv_panel_visible \
		and not _drone_view_open \
		and not _drone_submenu_open
	if should_capture != _captured:
		_capture_mouse(should_capture)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE:
			if _ctx_open:
				_close_context_menu()
				return
			if _drone_submenu_open:
				_close_drone_submenu()
				return
			if _drone_view_open:
				_close_drone_view()
				return
			if _inv_panel_visible:
				_toggle_inventory_panel()
				return
			_toggle_pause()
			return
		if ke.pressed and not ke.echo and ke.keycode == KEY_E:
			if not _paused and not _ctx_open:
				_toggle_inventory_panel()
				return
	if _paused:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _ctx_open and mb.pressed:
			if not _ctx_panel.get_global_rect().has_point(mb.position):
				_close_context_menu()
				return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed and _alt_held and _is_hovering():
				_open_context_menu(mb.position)
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				if not _alt_held and not _ctx_open and not _inv_panel_visible:
					_enter_orbit()
			else:
				if _orbit_active:
					_exit_orbit()
			return
	if event is InputEventMouseMotion and _captured:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		if _orbit_active:
			_orbit_yaw -= rel.x * ORBIT_SENSITIVITY
			_orbit_pitch = clampf(_orbit_pitch + rel.y * ORBIT_SENSITIVITY, -ORBIT_PITCH_LIMIT, ORBIT_PITCH_LIMIT)
			return
		_ship.rotate_object_local(Vector3.UP, -rel.x * mouse_sensitivity)
		_ship.rotate_object_local(Vector3.RIGHT, -rel.y * mouse_sensitivity)
		if _action_kind == "navigate" or _mining:
			_autopilot_mouse_accum += rel.length()
			if _autopilot_mouse_accum >= AUTOPILOT_CANCEL_MOUSE:
				if _mining:
					_cancel_mining()
				if _action_kind == "navigate":
					_cancel_autopilot()

func _process(delta: float) -> void:
	var alt_now := Input.is_key_pressed(KEY_ALT)
	if alt_now != _alt_held:
		_alt_held = alt_now
		_refresh_mouse_capture()
	if _orbit_active and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_exit_orbit()
	if _paused:
		return
	var t: float = float(Net.server_now_ms() - _epoch_ms) / 1000.0
	for entry in _orbiters:
		var node: Node3D = entry["node"]
		node.rotation.y = entry["phase"] + entry["omega"] * t
	if _belt_mm != null:
		_update_belt_transforms(t)
	if _ctx_open:
		pass
	elif _alt_held:
		_process_hover(t)
	else:
		_hover_target_kind = ""
		_hide_tooltip()
	_update_mining(t)
	_update_camera(delta)
	if _drone_nodes.size() > 0:
		_position_drones(delta)
	if _drone_view_open:
		_update_drone_view()
	_update_drone_hud()

func _update_mining(t: float) -> void:
	if not _mining or _belt_mm == null or _mining_target_idx < 0:
		if _mining:
			_cancel_mining()
		else:
			_hide_beam()
		return
	var idx := _mining_target_idx
	if idx >= _belt_alive.size() or _belt_alive[idx] == 0:
		_cancel_mining()
		return
	var target_pos := _world_pos_of_asteroid(idx, t)
	if _ship.global_position.distance_to(target_pos) > MAX_MINE_RANGE * 1.4:
		_cancel_mining()
		return
	_current_target_idx = idx
	_show_beam(target_pos)
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_mine_ms >= MINE_INTERVAL_MS:
		_last_mine_ms = now_ms
		Net.send_mine(int(_belt_ids[idx]))

func _pick_target(t: float, max_range: float = MAX_MINE_RANGE) -> int:
	var viewport := get_viewport()
	var mouse_pos: Vector2
	if _alt_held:
		mouse_pos = viewport.get_mouse_position()
	else:
		var sz := viewport.get_visible_rect().size
		mouse_pos = sz * 0.5
	var ray_origin := _cam.project_ray_origin(mouse_pos)
	var ray_dir := _cam.project_ray_normal(mouse_pos)

	var ship_pos := _ship.global_position
	var best_exact_idx: int = -1
	var best_exact_along: float = INF
	var best_tol_idx: int = -1
	var best_tol_along: float = INF
	var n: int = _belt_mm.instance_count
	for i in n:
		if _belt_alive[i] == 0:
			continue
		var pos := _world_pos_of_asteroid(i, t)
		if pos.distance_to(ship_pos) > max_range:
			continue
		var to_pt := pos - ray_origin
		var along := to_pt.dot(ray_dir)
		if along <= 0.0:
			continue
		var perp := (to_pt - ray_dir * along).length()
		var radius: float = _belt_scales[i]
		if perp <= radius:
			if along < best_exact_along:
				best_exact_along = along
				best_exact_idx = i
		elif perp <= radius * PICK_TOLERANCE:
			if along < best_tol_along:
				best_tol_along = along
				best_tol_idx = i
	return best_exact_idx if best_exact_idx >= 0 else best_tol_idx

func _update_camera(delta: float) -> void:
	var ideal: Transform3D
	if _orbit_active:
		ideal = _orbit_cam_transform()
		_cam.global_transform = ideal
		return
	var k: float = 1.0 - exp(-camera_lag * delta)
	ideal = _ideal_cam_transform()
	var cur := _cam.global_transform
	cur.origin = cur.origin.lerp(ideal.origin, k)
	var a := cur.basis.orthonormalized()
	var b := ideal.basis.orthonormalized()
	cur.basis = a.slerp(b, k)
	_cam.global_transform = cur

func _update_belt_transforms(t: float) -> void:
	var n: int = _belt_mm.instance_count
	for i in n:
		var s: float = _belt_scales[i] if _belt_alive[i] == 1 else 0.0
		var angle: float = _belt_phases[i] + _belt_omegas[i] * t
		var r: float = _belt_radii_orbit[i]
		var y: float = _belt_ys[i]
		var pos := Vector3(cos(angle) * r, y, sin(angle) * r)
		var b := Basis().scaled(Vector3(s, s, s))
		_belt_mm.set_instance_transform(i, Transform3D(b, pos))

func _world_pos_of_asteroid(idx: int, t: float) -> Vector3:
	var angle: float = _belt_phases[idx] + _belt_omegas[idx] * t
	var r: float = _belt_radii_orbit[idx]
	var y: float = _belt_ys[idx]
	return Vector3(cos(angle) * r, y, sin(angle) * r)

func _get_action_target_pos(t: float) -> Vector3:
	if _action_target_kind == "asteroid":
		return _world_pos_of_asteroid(_action_target_idx, t)
	if _action_target_node != null:
		return _action_target_node.global_position
	return _ship.global_position

func _cancel_autopilot() -> void:
	_action_kind = ""
	_action_target_kind = ""
	_action_target_node = null
	_action_pending_mine = false
	_autopilot_mouse_accum = 0.0

func _cancel_mining() -> void:
	_mining = false
	_mining_target_idx = -1
	_current_target_idx = -1
	_autopilot_mouse_accum = 0.0
	_hide_beam()

func _autopilot_process(delta: float) -> void:
	var t := float(Net.server_now_ms() - _epoch_ms) / 1000.0
	var target_pos := _get_action_target_pos(t)
	var to_target := target_pos - _ship.global_position
	var dist := to_target.length()
	if dist < 0.001:
		_action_kind = ""
		return
	var dir := to_target / dist
	var fwd := -_ship.global_transform.basis.z
	var angle := fwd.angle_to(dir)
	if angle > 0.01:
		var axis := fwd.cross(dir)
		if axis.length_squared() > 0.0001:
			_ship.rotate(axis.normalized(), minf(angle, AUTOPILOT_TURN_RATE * delta))
	var remaining := dist - _action_stop_distance
	var speed := _velocity.length()
	var brake_dist := speed * speed / (2.0 * brake_decel) * AUTOPILOT_BRAKE_SAFETY
	if remaining <= 1.0 and speed < 1.5:
		_velocity = Vector3.ZERO
		if _action_pending_mine and _action_target_kind == "asteroid":
			_action_pending_mine = false
			_mining_target_idx = _action_target_idx
			_mining = true
			_autopilot_mouse_accum = 0.0
		else:
			_action_pending_mine = false
		_action_kind = ""
		_action_target_kind = ""
		_action_target_node = null
	elif remaining > brake_dist and angle < 0.4:
		_velocity += fwd * thrust_accel * delta
		if _velocity.length() > max_speed:
			_velocity = _velocity.normalized() * max_speed
	else:
		if speed > 0.0:
			_velocity = _velocity * (maxf(speed - brake_decel * delta, 0.0) / speed)

func _physics_process(delta: float) -> void:
	if _paused:
		return
	if _mining and _captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_cancel_mining()
	if _action_kind == "navigate":
		if _captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_cancel_autopilot()
		else:
			_autopilot_process(delta)
			_ship.position += _velocity * delta
			_ship.transform = _ship.transform.orthonormalized()
			return
	var thrusting := _captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var fwd: Vector3 = -_ship.transform.basis.z
	if thrusting:
		_velocity += fwd * thrust_accel * delta
		var sp := _velocity.length()
		if sp > max_speed:
			_velocity = _velocity * (max_speed / sp)
	else:
		var sp := _velocity.length()
		if sp > 0.0:
			var new_sp: float = max(sp - brake_decel * delta, 0.0)
			_velocity = _velocity * (new_sp / sp)
	_ship.position += _velocity * delta
	_ship.transform = _ship.transform.orthonormalized()

func _build_mining_beam() -> void:
	_beam_mi = MeshInstance3D.new()
	_beam_mi.name = "MiningBeam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = BEAM_TIP_THICKNESS
	cyl.bottom_radius = BEAM_BASE_THICKNESS
	cyl.height = 1.0
	cyl.radial_segments = 14
	cyl.rings = 1
	_beam_mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.20, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.22)
	mat.emission_energy_multiplier = BEAM_BASE_EMISSION
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mi.material_override = mat
	_beam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_mi.visible = false
	add_child(_beam_mi)

	_beam_impact = MeshInstance3D.new()
	_beam_impact.name = "MiningImpact"
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.10
	sphere.radial_segments = 16
	sphere.rings = 8
	_beam_impact.mesh = sphere
	var im_mat := StandardMaterial3D.new()
	im_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	im_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im_mat.albedo_color = Color(1.0, 0.75, 0.35, 0.55)
	im_mat.emission_enabled = true
	im_mat.emission = Color(1.0, 0.7, 0.3)
	im_mat.emission_energy_multiplier = 3.5
	_beam_impact.material_override = im_mat
	_beam_impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_impact.visible = false
	add_child(_beam_impact)

func _show_beam(target_world_pos: Vector3) -> void:
	var ship_pos := _ship.global_position
	var delta_v := target_world_pos - ship_pos
	var distance := delta_v.length()
	if distance < 0.05:
		_beam_mi.visible = false
		_beam_impact.visible = false
		return
	var dir_n := delta_v / distance
	var up_ref: Vector3 = Vector3.RIGHT if absf(dir_n.y) > 0.99 else Vector3.UP
	var x_axis := up_ref.cross(dir_n).normalized()
	var z_axis := dir_n.cross(x_axis).normalized()
	var t := float(Time.get_ticks_msec()) / 1000.0
	var pulse: float = 0.85 + 0.30 * sin(t * BEAM_PULSE_RATE)
	var thickness_pulse: float = 0.92 + 0.16 * sin(t * BEAM_PULSE_RATE * 0.7)
	var basis := Basis(x_axis * thickness_pulse, dir_n * distance, z_axis * thickness_pulse)
	var midpoint := ship_pos + delta_v * 0.5
	_beam_mi.global_transform = Transform3D(basis, midpoint)
	var mat: StandardMaterial3D = _beam_mi.material_override
	mat.emission_energy_multiplier = BEAM_BASE_EMISSION * pulse
	_beam_mi.visible = true

	var impact_scale: float = 0.85 + 0.30 * sin(t * BEAM_PULSE_RATE * 1.3)
	_beam_impact.global_position = target_world_pos
	_beam_impact.scale = Vector3.ONE * impact_scale
	var im_mat: StandardMaterial3D = _beam_impact.material_override
	im_mat.emission_energy_multiplier = 3.0 + 1.5 * sin(t * BEAM_PULSE_RATE * 1.1)
	_beam_impact.visible = true

func _hide_beam() -> void:
	if _beam_mi != null:
		_beam_mi.visible = false
	if _beam_impact != null:
		_beam_impact.visible = false

func _spawn_mine_popup(world_pos: Vector3, kind: String, amount: int) -> void:
	if amount <= 0:
		return
	var label := Label3D.new()
	var color: Color = KIND_POPUP_COLOR.get(kind, Color.WHITE)
	label.text = "+%d %s" % [amount, ASTEROID_KIND_LABEL.get(kind, kind)]
	label.font_size = 36
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.95)
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.005
	add_child(label)
	label.global_position = world_pos
	var rise_to: float = world_pos.y + 4.0
	var lateral := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	label.global_position += lateral
	label.scale = Vector3(0.6, 0.6, 0.6)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", rise_to, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3(1.15, 1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(label, "scale", Vector3(1.0, 1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD)
	var tw_fade := create_tween()
	tw_fade.tween_property(label, "modulate:a", 0.0, 0.85).set_delay(0.30).set_trans(Tween.TRANS_LINEAR)
	tw_fade.tween_callback(label.queue_free)

func _build_tooltip_ui() -> void:
	_tooltip_layer = CanvasLayer.new()
	_tooltip_layer.layer = 128
	add_child(_tooltip_layer)

	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.modulate.a = 0.0
	_tooltip_layer.add_child(_tooltip_panel)

	_tooltip_panel.theme_type_variation = &"TooltipPanel"

	_tooltip_label = Label.new()
	_tooltip_label.add_theme_color_override("font_color", UI_TITLE)
	_tooltip_label.add_theme_font_size_override("font_size", 13)
	_tooltip_panel.add_child(_tooltip_label)

	_tooltip_connector = Line2D.new()
	_tooltip_connector.width = 1.8
	_tooltip_connector.default_color = UI_BORDER
	_tooltip_connector.antialiased = true
	_tooltip_connector.visible = false
	var line_grad := Gradient.new()
	line_grad.colors = PackedColorArray([
		Color(0.55, 0.80, 1.00, 1.00),
		Color(0.40, 0.65, 1.00, 0.65),
		Color(0.30, 0.50, 0.85, 0.10),
	])
	line_grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_tooltip_connector.gradient = line_grad
	_tooltip_layer.add_child(_tooltip_connector)

func _show_tooltip(text: String) -> void:
	var was_hidden := not _tooltip_panel.visible
	_tooltip_label.text = text
	_tooltip_panel.visible = true
	var mp := get_viewport().get_mouse_position()
	var sz := _tooltip_panel.size
	var vp := get_viewport().get_visible_rect().size
	var x := mp.x + 16.0
	var y := mp.y + 16.0
	if x + sz.x > vp.x: x = mp.x - sz.x - 8.0
	if y + sz.y > vp.y: y = mp.y - sz.y - 8.0
	_tooltip_panel.position = Vector2(x, y)
	if was_hidden:
		var tw := _tooltip_panel.create_tween()
		tw.tween_property(_tooltip_panel, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_QUAD)
	else:
		_tooltip_panel.modulate.a = 1.0
	_update_connector()

func _update_connector() -> void:
	if _tooltip_connector == null or not _tooltip_panel.visible:
		return
	var to_body := _hover_world_pos - _cam.global_position
	if to_body.dot(-_cam.global_transform.basis.z) < 0.0:
		_tooltip_connector.visible = false
		return
	var body_2d := _cam.unproject_position(_hover_world_pos)
	var panel_pos := _tooltip_panel.position
	var panel_size := _tooltip_panel.size
	if panel_size.x == 0.0 or panel_size.y == 0.0:
		return

	var attach: Vector2
	if body_2d.x < panel_pos.x:
		attach = Vector2(panel_pos.x, clampf(body_2d.y, panel_pos.y, panel_pos.y + panel_size.y))
	elif body_2d.x > panel_pos.x + panel_size.x:
		attach = Vector2(panel_pos.x + panel_size.x, clampf(body_2d.y, panel_pos.y, panel_pos.y + panel_size.y))
	elif body_2d.y < panel_pos.y:
		attach = Vector2(clampf(body_2d.x, panel_pos.x, panel_pos.x + panel_size.x), panel_pos.y)
	else:
		attach = Vector2(clampf(body_2d.x, panel_pos.x, panel_pos.x + panel_size.x), panel_pos.y + panel_size.y)

	if not _connector_initialized:
		_connector_target = attach
		_connector_initialized = true
	else:
		_connector_target = _connector_target.lerp(attach, 0.2)

	var dx := _connector_target.x - body_2d.x
	var dy := _connector_target.y - body_2d.y
	var elbow: Vector2
	if abs(dx) >= abs(dy):
		elbow = Vector2(body_2d.x + signf(dx) * abs(dy), _connector_target.y)
	else:
		elbow = Vector2(_connector_target.x, body_2d.y + signf(dy) * abs(dx))

	_tooltip_connector.clear_points()
	_tooltip_connector.add_point(body_2d)
	_tooltip_connector.add_point(elbow)
	_tooltip_connector.add_point(_connector_target)
	_tooltip_connector.visible = true

func _hide_tooltip() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false
		_tooltip_panel.modulate.a = 0.0
	if _tooltip_connector != null:
		_tooltip_connector.visible = false
	_connector_initialized = false

func _pick_static_target() -> int:
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _cam.project_ray_origin(mouse_pos)
	var ray_dir    := _cam.project_ray_normal(mouse_pos)
	var best_exact_idx := -1
	var best_exact_along := INF
	var best_tol_idx := -1
	var best_tol_along := INF
	for i in _pickable_static.size():
		var entry: Dictionary = _pickable_static[i]
		var node: Node3D = entry["node"]
		var to_obj := node.global_position - ray_origin
		var along := to_obj.dot(ray_dir)
		if along <= 0.0:
			continue
		var perp := (to_obj - ray_dir * along).length()
		var radius: float = entry["radius_visual"] as float
		if perp <= radius:
			if along < best_exact_along:
				best_exact_along = along
				best_exact_idx = i
		elif perp <= radius * PICK_TOLERANCE:
			if along < best_tol_along:
				best_tol_along = along
				best_tol_idx = i
	return best_exact_idx if best_exact_idx >= 0 else best_tol_idx

func _is_hovering() -> bool:
	return _hover_target_kind != ""

func _process_hover(t: float) -> void:
	var aidx := _pick_target(t, HOVER_RANGE)
	if aidx >= 0:
		_hover_target_kind = "asteroid"
		_hover_target_idx = aidx
		_hover_target_node = null
		_hover_radius_visual = _belt_scales[aidx]
		_hover_world_pos = _world_pos_of_asteroid(aidx, t)
		var kind_key := _belt_kinds[aidx] if _belt_kinds.size() > aidx else "?"
		var kind_label: String = ASTEROID_KIND_LABEL.get(kind_key, kind_key)
		var stock := _belt_stock[aidx] if _belt_stock.size() > aidx else 0
		var initial := _belt_initial_stock[aidx] if _belt_initial_stock.size() > aidx else stock
		_show_tooltip("Astéroïde  —  %s\nStock : %d / %d\n\n→ Clic droit" % [kind_label, stock, initial])
		return
	var sidx := _pick_static_target()
	if sidx >= 0:
		var entry: Dictionary = _pickable_static[sidx]
		_hover_target_kind = entry["kind"] as String
		_hover_target_idx = sidx
		_hover_target_node = entry["node"] as Node3D
		_hover_radius_visual = entry["radius_visual"] as float
		_hover_world_pos = _hover_target_node.global_position
		_show_tooltip(entry.get("description", entry.get("name", "?")) + "\n\n→ Clic droit")
		return
	_hover_target_kind = ""
	_hover_target_idx = -1
	_hover_target_node = null
	_hide_tooltip()

func _make_ctx_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(180, 0)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", UI_TITLE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0)
	sn.corner_radius_top_left = 6
	sn.corner_radius_top_right = 6
	sn.corner_radius_bottom_left = 6
	sn.corner_radius_bottom_right = 6
	sn.content_margin_left = 12
	sn.content_margin_right = 12
	sn.content_margin_top = 6
	sn.content_margin_bottom = 6
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.30, 0.55, 1.00, 0.30)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.35, 0.60, 1.00, 0.50)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_stylebox_override("focus", sn)
	_attach_button_hover_anim(btn)
	return btn

func _build_context_menu() -> void:
	_ctx_layer = CanvasLayer.new()
	_ctx_layer.layer = 64
	add_child(_ctx_layer)

	_ctx_panel = PanelContainer.new()
	_ctx_panel.visible = false
	_ctx_layer.add_child(_ctx_panel)
	_ctx_panel.theme_type_variation = &"MenuPanel"

	_ctx_vbox = VBoxContainer.new()
	_ctx_vbox.add_theme_constant_override("separation", 2)
	_ctx_panel.add_child(_ctx_vbox)

func _open_context_menu(screen_pos: Vector2) -> void:
	_ctx_target_kind   = _hover_target_kind
	_ctx_target_idx    = _hover_target_idx
	_ctx_target_node   = _hover_target_node
	_ctx_target_radius = _hover_radius_visual

	_hide_tooltip()

	for child in _ctx_vbox.get_children():
		child.queue_free()

	var btn_nav := _make_ctx_button("Se déplacer vers")
	btn_nav.pressed.connect(_on_ctx_navigate)
	_ctx_vbox.add_child(btn_nav)

	if _ctx_target_kind == "asteroid":
		var btn_mine := _make_ctx_button("Miner")
		btn_mine.pressed.connect(_on_ctx_mine)
		_ctx_vbox.add_child(btn_mine)

	_ctx_panel.visible = true
	_ctx_panel.modulate.a = 0.0
	_ctx_panel.scale = Vector2(0.92, 0.92)
	await get_tree().process_frame
	var sz := _ctx_panel.size
	var vp := get_viewport().get_visible_rect().size
	var x := minf(screen_pos.x, vp.x - sz.x - 4.0)
	var y := minf(screen_pos.y, vp.y - sz.y - 4.0)
	_ctx_panel.position = Vector2(maxf(x, 4.0), maxf(y, 4.0))
	_ctx_panel.pivot_offset = Vector2.ZERO
	var tw := _ctx_panel.create_tween().set_parallel(true)
	tw.tween_property(_ctx_panel, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_ctx_panel, "scale", Vector2(1.0, 1.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_ctx_open = true

func _close_context_menu() -> void:
	_ctx_open = false
	_ctx_panel.visible = false
	_refresh_mouse_capture()

func _on_ctx_navigate() -> void:
	_close_context_menu()
	_autopilot_mouse_accum = 0.0
	_action_kind        = "navigate"
	_action_target_kind = _ctx_target_kind
	_action_target_idx  = _ctx_target_idx
	_action_target_node = _ctx_target_node
	_action_pending_mine = false
	_action_stop_distance = MAX_MINE_RANGE * 0.7 if _ctx_target_kind == "asteroid" \
		else _ctx_target_radius + 8.0

func _on_ctx_mine() -> void:
	_close_context_menu()
	_autopilot_mouse_accum = 0.0
	_action_kind        = "navigate"
	_action_target_kind = _ctx_target_kind
	_action_target_idx  = _ctx_target_idx
	_action_target_node = null
	_action_pending_mine = true
	_action_stop_distance = MAX_MINE_RANGE * 0.7

func _build_inventory_panel() -> void:
	_inv_panel_layer = CanvasLayer.new()
	_inv_panel_layer.name = "InventoryLayer"
	_inv_panel_layer.layer = 20
	_inv_panel_layer.visible = false
	add_child(_inv_panel_layer)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0.02, 0.04, 0.10, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_inv_panel_layer.add_child(dim)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	dim.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	panel.theme_type_variation = &"ModalPanel"
	center.add_child(panel)
	_inv_panel_root = panel

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	var title := Label.new()
	title.text = "Drones & construction"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label_title(title, 17, UI_BORDER_SOFT)
	header.add_child(title)
	var hint_pill := PanelContainer.new()
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(0.10, 0.16, 0.28, 0.85)
	hint_style.border_width_left = 1
	hint_style.border_width_right = 1
	hint_style.border_width_top = 1
	hint_style.border_width_bottom = 1
	hint_style.border_color = UI_BORDER_SOFT
	hint_style.corner_radius_top_left = 4
	hint_style.corner_radius_top_right = 4
	hint_style.corner_radius_bottom_left = 4
	hint_style.corner_radius_bottom_right = 4
	hint_style.content_margin_left = 8
	hint_style.content_margin_right = 8
	hint_style.content_margin_top = 2
	hint_style.content_margin_bottom = 2
	hint_pill.add_theme_stylebox_override("panel", hint_style)
	var hint := Label.new()
	hint.text = "E pour fermer"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", UI_SUBTLE)
	hint_pill.add_child(hint)
	header.add_child(hint_pill)
	box.add_child(_make_gradient_separator())

	# Construction drone : bouton court + coût en sous-texte.
	var drone_box := VBoxContainer.new()
	drone_box.add_theme_constant_override("separation", 1)
	box.add_child(drone_box)
	_inv_drone_btn = Button.new()
	_inv_drone_btn.text = "Construire un drone"
	_attach_button_hover_anim(_inv_drone_btn)
	_inv_drone_btn.add_theme_font_size_override("font_size", 14)
	_inv_drone_btn.pressed.connect(_on_build_pressed.bind("drone"))
	drone_box.add_child(_inv_drone_btn)
	_inv_drone_cost_lbl = Label.new()
	_inv_drone_cost_lbl.text = _format_cost_line(DRONE_COST)
	_inv_drone_cost_lbl.add_theme_font_size_override("font_size", 10)
	drone_box.add_child(_inv_drone_cost_lbl)

	# Section drones + stratégies (compactée)
	_inv_drones_title = Label.new()
	_inv_drones_title.text = "Drones (0)"
	_inv_drones_title.add_theme_font_size_override("font_size", 12)
	_inv_drones_title.add_theme_color_override("font_color", UI_SUBTLE)
	box.add_child(_inv_drones_title)

	# Ordres globaux : 2 boutons larges côte à côte + 4 boutons kind + cancel
	var strat_row1 := HBoxContainer.new()
	strat_row1.add_theme_constant_override("separation", 4)
	box.add_child(strat_row1)
	_inv_order_all_btn = Button.new()
	_inv_order_all_btn.text = "Distincts"
	_attach_button_hover_anim(_inv_order_all_btn)
	_inv_order_all_btn.add_theme_font_size_override("font_size", 11)
	_inv_order_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_order_all_btn.pressed.connect(_on_order_all_pressed.bind("mine_distinct", ""))
	strat_row1.add_child(_inv_order_all_btn)
	var spread_btn := Button.new()
	spread_btn.text = "Répartir par type"
	_attach_button_hover_anim(spread_btn)
	spread_btn.add_theme_font_size_override("font_size", 11)
	spread_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spread_btn.pressed.connect(_on_order_all_pressed.bind("spread_kinds", ""))
	strat_row1.add_child(spread_btn)

	var strat_row2 := HBoxContainer.new()
	strat_row2.add_theme_constant_override("separation", 3)
	box.add_child(strat_row2)
	for kind in INV_KINDS:
		var k_btn := Button.new()
		k_btn.text = String(INV_DISPLAY.get(kind, kind))
		_attach_button_hover_anim(k_btn)
		var k_color: Color = KIND_POPUP_COLOR.get(kind, UI_BTN_NORMAL)
		_tint_button(k_btn, k_color)
		k_btn.add_theme_font_size_override("font_size", 11)
		k_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k_btn.pressed.connect(_on_order_all_pressed.bind("mine_kind", kind))
		strat_row2.add_child(k_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "✕"
	_attach_button_hover_anim(cancel_btn)
	cancel_btn.add_theme_font_size_override("font_size", 11)
	cancel_btn.tooltip_text = "Annuler tous les ordres"
	cancel_btn.pressed.connect(_on_order_all_pressed.bind("idle", ""))
	strat_row2.add_child(cancel_btn)

	# Liste de drones scrollable
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_inv_drones_list = VBoxContainer.new()
	_inv_drones_list.add_theme_constant_override("separation", 1)
	_inv_drones_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inv_drones_list)

	# Section avancée (usines) repliée en bas
	box.add_child(_make_gradient_separator())
	var factory_row := HBoxContainer.new()
	factory_row.add_theme_constant_override("separation", 6)
	box.add_child(factory_row)
	_inv_factory_btn = Button.new()
	_inv_factory_btn.text = "Construire usine"
	_attach_button_hover_anim(_inv_factory_btn)
	_inv_factory_btn.add_theme_font_size_override("font_size", 11)
	_inv_factory_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_factory_btn.pressed.connect(_on_build_pressed.bind("factory"))
	factory_row.add_child(_inv_factory_btn)
	_inv_factories_title = Label.new()
	_inv_factories_title.text = "0"
	_inv_factories_title.add_theme_font_size_override("font_size", 11)
	_inv_factories_title.add_theme_color_override("font_color", Color(0.50, 0.58, 0.70))
	factory_row.add_child(_inv_factories_title)
	_inv_factory_cost_lbl = Label.new()
	_inv_factory_cost_lbl.text = _format_cost_line(FACTORY_COST)
	_inv_factory_cost_lbl.add_theme_font_size_override("font_size", 9)
	_inv_factory_cost_lbl.add_theme_color_override("font_color", Color(0.50, 0.58, 0.70))
	box.add_child(_inv_factory_cost_lbl)
	_inv_factories_list = VBoxContainer.new()
	_inv_factories_list.add_theme_constant_override("separation", 0)
	_inv_factories_list.visible = false
	box.add_child(_inv_factories_list)

	_inv_status_lbl = Label.new()
	_inv_status_lbl.text = ""
	_inv_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inv_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	_inv_status_lbl.add_theme_font_size_override("font_size", 11)
	box.add_child(_inv_status_lbl)

func _format_cost_line(costs: Dictionary) -> String:
	var parts: Array = []
	for k in costs.keys():
		parts.append("%d %s" % [int(costs[k]), String(INV_DISPLAY.get(k, k))])
	return "Coût : " + ", ".join(parts)

func _can_afford(costs: Dictionary) -> bool:
	for k in costs.keys():
		if int(_inv_state.get(k, 0)) < int(costs[k]):
			return false
	return true

func _toggle_inventory_panel() -> void:
	_inv_panel_visible = not _inv_panel_visible
	_inv_panel_layer.visible = _inv_panel_visible
	if _inv_panel_visible:
		_inv_status_lbl.text = ""
		_refresh_mouse_capture()
		_refresh_inventory_panel()
		if _inv_panel_root != null:
			_inv_panel_root.pivot_offset = _inv_panel_root.size * 0.5
			_inv_panel_root.modulate.a = 0.0
			_inv_panel_root.scale = Vector2(0.96, 0.96)
			var dim_node := _inv_panel_layer.get_node_or_null("Dim") as ColorRect
			if dim_node != null:
				dim_node.color.a = 0.0
			var tw := _inv_panel_layer.create_tween().set_parallel(true)
			tw.tween_property(_inv_panel_root, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(_inv_panel_root, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if dim_node != null:
				tw.tween_property(dim_node, "color:a", 0.55, 0.16).set_trans(Tween.TRANS_QUAD)
	else:
		_refresh_mouse_capture()

func _refresh_inventory_panel() -> void:
	var can_drone := _can_afford(DRONE_COST)
	_inv_drone_btn.disabled = not can_drone
	_inv_drone_cost_lbl.add_theme_color_override(
		"font_color",
		Color(0.55, 0.85, 0.55) if can_drone else Color(0.85, 0.55, 0.55)
	)

	var can_factory := _can_afford(FACTORY_COST)
	_inv_factory_btn.disabled = not can_factory
	_inv_factory_cost_lbl.add_theme_color_override(
		"font_color",
		Color(0.55, 0.85, 0.55) if can_factory else Color(0.85, 0.55, 0.55)
	)

	_inv_drones_title.text = "Drones (%d)" % _drones_state.size()
	_inv_order_all_btn.disabled = _drones_state.is_empty()
	for child in _inv_drones_list.get_children():
		child.queue_free()
	var row_idx := 0
	for d in _drones_state:
		var did := int(d.get("id", 0))
		var state_label: String = DRONE_STATE_LABEL.get(String(d.get("state", "idle")), "?")
		var row_wrap := PanelContainer.new()
		row_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if row_idx % 2 == 1:
			var zebra := StyleBoxFlat.new()
			zebra.bg_color = Color(0.30, 0.50, 0.85, 0.06)
			zebra.corner_radius_top_left = 4
			zebra.corner_radius_top_right = 4
			zebra.corner_radius_bottom_left = 4
			zebra.corner_radius_bottom_right = 4
			row_wrap.add_theme_stylebox_override("panel", zebra)
		var btn := _make_ctx_button("#%d — %s" % [did, state_label])
		btn.add_theme_font_size_override("font_size", 11)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_drone_row_pressed.bind(did))
		row_wrap.add_child(btn)
		_inv_drones_list.add_child(row_wrap)
		row_idx += 1

	_inv_factories_title.text = "× %d" % _factories_state.size()

func _on_build_pressed(item: String) -> void:
	if not Net.send_build(item):
		_inv_status_lbl.text = "Réseau indisponible"

func _on_build_result(payload: Dictionary) -> void:
	var inv: Dictionary = payload.get("inventory", {}) as Dictionary
	_apply_inventory(inv)
	_drones_state = (payload.get("drones", []) as Array).duplicate()
	_factories_state = (payload.get("factories", []) as Array).duplicate()
	_refresh_drones_visuals()
	_refresh_factories_visuals()
	if _inv_panel_visible:
		var ok := bool(payload.get("ok", false))
		var item := String(payload.get("item", "?"))
		if ok:
			_inv_status_lbl.add_theme_color_override("font_color", Color(0.6, 0.95, 0.65))
			_inv_status_lbl.text = "Construit : %s" % item
		else:
			_inv_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
			var reason := String(payload.get("reason", ""))
			_inv_status_lbl.text = "Échec (%s) : %s" % [item, reason]
		_pulse_label(_inv_status_lbl, Color(1.4, 1.4, 1.4, 1.0), 0.45)
		_refresh_inventory_panel()

func _on_drone_tick(payload: Dictionary) -> void:
	_drones_state = (payload.get("drones", []) as Array).duplicate()
	_apply_inventory(payload.get("inventory", {}) as Dictionary)
	_drone_target_t_ms = Net.server_now_ms()
	_drone_target_pos.resize(_drones_state.size())
	_drone_target_vel.resize(_drones_state.size())
	for i in _drones_state.size():
		var d: Dictionary = _drones_state[i]
		var p_arr: Array = d.get("position", [0.0, 0.0, 0.0]) as Array
		var v_arr: Array = d.get("velocity", [0.0, 0.0, 0.0]) as Array
		_drone_target_pos[i] = Vector3(float(p_arr[0]), float(p_arr[1]), float(p_arr[2]))
		_drone_target_vel[i] = Vector3(float(v_arr[0]), float(v_arr[1]), float(v_arr[2]))
	_refresh_drones_visuals()
	if _inv_panel_visible:
		_refresh_inventory_panel()

func _on_order_result(payload: Dictionary) -> void:
	if not _inv_panel_visible:
		return
	var ok := bool(payload.get("ok", false))
	if ok:
		var n := int(payload.get("affected", 0))
		_inv_status_lbl.add_theme_color_override("font_color", Color(0.6, 0.95, 0.65))
		_inv_status_lbl.text = "Ordre transmis (%d drone%s)" % [n, "s" if n > 1 else ""]
	else:
		var reason := String(payload.get("reason", ""))
		_inv_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
		_inv_status_lbl.text = "Ordre rejeté : %s" % reason
	_pulse_label(_inv_status_lbl, Color(1.4, 1.4, 1.4, 1.0), 0.45)

func _on_order_all_pressed(order: String, kind: String) -> void:
	if not Net.send_order_all_drones(order, kind, _ship.global_position):
		_inv_status_lbl.text = "Réseau indisponible"

func _build_drone_submenu() -> void:
	_drone_submenu_layer = CanvasLayer.new()
	_drone_submenu_layer.name = "DroneSubmenuLayer"
	_drone_submenu_layer.layer = 22
	_drone_submenu_layer.visible = false
	add_child(_drone_submenu_layer)
	_drone_submenu_panel = PanelContainer.new()
	_drone_submenu_panel.theme_type_variation = &"MenuPanel"
	_drone_submenu_layer.add_child(_drone_submenu_panel)
	_drone_submenu_vbox = VBoxContainer.new()
	_drone_submenu_vbox.add_theme_constant_override("separation", 2)
	_drone_submenu_panel.add_child(_drone_submenu_vbox)

func _open_drone_submenu(drone_id: int, screen_pos: Vector2) -> void:
	_drone_submenu_drone_id = drone_id
	for c in _drone_submenu_vbox.get_children():
		c.queue_free()
	var b_view := _make_ctx_button("Voir")
	b_view.pressed.connect(_on_drone_view_pressed.bind(drone_id))
	_drone_submenu_vbox.add_child(b_view)
	var b_join := _make_ctx_button("Rejoindre")
	b_join.pressed.connect(_on_drone_join_pressed.bind(drone_id))
	_drone_submenu_vbox.add_child(b_join)
	var b_order := _make_ctx_button("Miner l'astre minable le plus proche")
	b_order.pressed.connect(_on_drone_order_mine_pressed.bind(drone_id))
	_drone_submenu_vbox.add_child(b_order)
	var b_cancel := _make_ctx_button("Annuler ordre")
	b_cancel.pressed.connect(_on_drone_order_idle_pressed.bind(drone_id))
	_drone_submenu_vbox.add_child(b_cancel)
	_drone_submenu_panel.visible = true
	_drone_submenu_layer.visible = true
	_drone_submenu_open = true
	await get_tree().process_frame
	var sz := _drone_submenu_panel.size
	var vp := get_viewport().get_visible_rect().size
	var x := minf(screen_pos.x, vp.x - sz.x - 4.0)
	var y := minf(screen_pos.y, vp.y - sz.y - 4.0)
	_drone_submenu_panel.position = Vector2(maxf(x, 4.0), maxf(y, 4.0))

func _close_drone_submenu() -> void:
	_drone_submenu_open = false
	_drone_submenu_drone_id = -1
	if _drone_submenu_layer != null:
		_drone_submenu_layer.visible = false
	_refresh_mouse_capture()

func _on_drone_row_pressed(drone_id: int) -> void:
	var pos := get_viewport().get_mouse_position()
	_open_drone_submenu(drone_id, pos)

func _on_drone_view_pressed(drone_id: int) -> void:
	_close_drone_submenu()
	_open_drone_view(drone_id)

func _on_drone_join_pressed(drone_id: int) -> void:
	_close_drone_submenu()
	var node := _find_drone_node(drone_id)
	if node == null:
		_inv_status_lbl.text = "Drone introuvable"
		return
	_action_kind = "navigate"
	_action_target_kind = "drone"
	_action_target_node = node
	_action_target_idx = -1
	_action_pending_mine = false
	_action_stop_distance = 4.0
	_autopilot_mouse_accum = 0.0
	if _inv_panel_visible:
		_toggle_inventory_panel()

func _on_drone_order_mine_pressed(drone_id: int) -> void:
	_close_drone_submenu()
	if not Net.send_order_drone(drone_id, "mine_nearest", _ship.global_position):
		_inv_status_lbl.text = "Réseau indisponible"

func _on_drone_order_idle_pressed(drone_id: int) -> void:
	_close_drone_submenu()
	if not Net.send_order_drone(drone_id, "idle", _ship.global_position):
		_inv_status_lbl.text = "Réseau indisponible"

func _find_drone_node(drone_id: int) -> Node3D:
	for i in _drones_state.size():
		if int((_drones_state[i] as Dictionary).get("id", 0)) == drone_id:
			if i < _drone_nodes.size():
				return _drone_nodes[i]
	return null

func _build_drone_view() -> void:
	_drone_view_layer = CanvasLayer.new()
	_drone_view_layer.name = "DroneViewLayer"
	_drone_view_layer.layer = 24
	_drone_view_layer.visible = false
	add_child(_drone_view_layer)

	_drone_view_panel = PanelContainer.new()
	_drone_view_panel.anchor_left = 1.0
	_drone_view_panel.anchor_right = 1.0
	_drone_view_panel.offset_left = -340.0
	_drone_view_panel.offset_right = -16.0
	_drone_view_panel.offset_top = 16.0
	_drone_view_panel.theme_type_variation = &"ModalPanel"
	_drone_view_layer.add_child(_drone_view_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_drone_view_panel.add_child(box)

	var title := Label.new()
	title.text = "Drone"
	title.name = "Title"
	_style_label_title(title, 18, Color(0.55, 0.85, 1.00, 0.85))
	box.add_child(title)

	box.add_child(_make_gradient_separator())

	var feed_wrap := Control.new()
	feed_wrap.custom_minimum_size = Vector2(300, 200)
	feed_wrap.clip_contents = true
	box.add_child(feed_wrap)

	var sub_container := SubViewportContainer.new()
	sub_container.anchor_right = 1.0
	sub_container.anchor_bottom = 1.0
	sub_container.stretch = true
	feed_wrap.add_child(sub_container)

	_drone_view_subviewport = SubViewport.new()
	_drone_view_subviewport.size = Vector2i(300, 200)
	_drone_view_subviewport.transparent_bg = false
	_drone_view_subviewport.handle_input_locally = false
	_drone_view_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_container.add_child(_drone_view_subviewport)
	_drone_view_subviewport.world_3d = get_world_3d()

	_drone_view_camera = Camera3D.new()
	_drone_view_camera.fov = 55.0
	_drone_view_subviewport.add_child(_drone_view_camera)

	var frame_overlay := Panel.new()
	frame_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_overlay.anchor_right = 1.0
	frame_overlay.anchor_bottom = 1.0
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0)
	frame_style.border_width_left = 2
	frame_style.border_width_right = 2
	frame_style.border_width_top = 2
	frame_style.border_width_bottom = 2
	frame_style.border_color = UI_BORDER
	frame_overlay.add_theme_stylebox_override("panel", frame_style)
	feed_wrap.add_child(frame_overlay)

	var scan := ColorRect.new()
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scan.color = Color(0.55, 0.80, 1.00, 0.35)
	scan.size = Vector2(300, 2)
	scan.anchor_right = 1.0
	scan.offset_bottom = 2.0
	feed_wrap.add_child(scan)
	var scan_tw := scan.create_tween().set_loops()
	scan_tw.tween_property(scan, "position:y", 198.0, 2.0).set_trans(Tween.TRANS_LINEAR)
	scan_tw.tween_property(scan, "position:y", 0.0, 0.0)

	_drone_view_info_lbl = Label.new()
	_drone_view_info_lbl.text = ""
	_drone_view_info_lbl.add_theme_font_size_override("font_size", 12)
	_drone_view_info_lbl.add_theme_color_override("font_color", UI_TEXT)
	box.add_child(_drone_view_info_lbl)

	var close_btn := Button.new()
	close_btn.text = "Fermer"
	_attach_button_hover_anim(close_btn)
	close_btn.pressed.connect(_close_drone_view)
	box.add_child(close_btn)

func _open_drone_view(drone_id: int) -> void:
	_drone_view_target_id = drone_id
	_drone_view_open = true
	_drone_view_layer.visible = true
	if _drone_view_panel.has_node("VBoxContainer"):
		pass
	var title_node := _drone_view_panel.get_child(0).get_node("Title")
	if title_node is Label:
		(title_node as Label).text = "Drone #%d" % drone_id
	_update_drone_view()

func _close_drone_view() -> void:
	_drone_view_open = false
	_drone_view_target_id = -1
	if _drone_view_layer != null:
		_drone_view_layer.visible = false
	_refresh_mouse_capture()

func _update_drone_view() -> void:
	if not _drone_view_open or _drone_view_target_id < 0:
		return
	var d: Dictionary = {}
	for entry in _drones_state:
		if int((entry as Dictionary).get("id", 0)) == _drone_view_target_id:
			d = entry
			break
	if d.is_empty():
		return
	var node := _find_drone_node(_drone_view_target_id)
	if node != null and _drone_view_camera != null:
		var cam_pos := node.global_position + Vector3(0.0, 1.6, 5.5)
		_drone_view_camera.global_transform = Transform3D(Basis.IDENTITY, cam_pos).looking_at(node.global_position, Vector3.UP)
	if _drone_view_info_lbl != null:
		var state := String(d.get("state", "idle"))
		var label_state: String = DRONE_STATE_LABEL.get(state, state)
		var pos_arr: Array = d.get("position", [0.0, 0.0, 0.0]) as Array
		var ast := int(d.get("target_asteroid", 0)) if d.get("target_asteroid", null) != null else 0
		var ast_text := ("astéroïde #%d" % ast) if ast > 0 else "—"
		_drone_view_info_lbl.text = "État : %s\nCible : %s\nPosition : (%.1f, %.1f, %.1f)" % [
			label_state, ast_text,
			float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]),
		]

func _build_cheat_panel() -> void:
	_cheat_layer = CanvasLayer.new()
	_cheat_layer.name = "CheatPanel"
	_cheat_layer.layer = 8
	add_child(_cheat_layer)

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -260.0
	panel.offset_right = -16.0
	panel.offset_top = 220.0
	panel.theme_type_variation = &"CompactPanel"
	_cheat_layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var stats_title := Label.new()
	stats_title.text = "Système"
	stats_title.add_theme_font_size_override("font_size", 11)
	stats_title.add_theme_color_override("font_color", UI_SUBTLE)
	box.add_child(stats_title)

	_status = Label.new()
	_status.add_theme_color_override("font_color", UI_TEXT)
	_status.add_theme_font_size_override("font_size", 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(232, 0)
	box.add_child(_status)

	box.add_child(HSeparator.new())

	var title := Label.new()
	title.text = "Triche (debug)"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.55))
	box.add_child(title)

	var btn := Button.new()
	btn.text = "+100 chaque matériau"
	_attach_button_hover_anim(btn)
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(_on_cheat_grant_pressed)
	box.add_child(btn)

func _on_cheat_grant_pressed() -> void:
	Net.send_cheat("grant_resources")

func _build_drone_hud() -> void:
	_drone_hud_layer = CanvasLayer.new()
	_drone_hud_layer.name = "DroneHud"
	_drone_hud_layer.layer = 9
	add_child(_drone_hud_layer)
	_drone_hud_root = Control.new()
	_drone_hud_root.anchor_right = 1.0
	_drone_hud_root.anchor_bottom = 1.0
	_drone_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drone_hud_layer.add_child(_drone_hud_root)

func _make_drone_hud_widget() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2(120, 24)

	var tip := PanelContainer.new()
	tip.name = "Tip"
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.12, 0.78)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.40, 0.65, 1.00, 0.55)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	tip.add_theme_stylebox_override("panel", style)
	var tip_lbl := Label.new()
	tip_lbl.name = "TipLabel"
	tip_lbl.add_theme_font_size_override("font_size", 11)
	tip_lbl.add_theme_color_override("font_color", UI_TEXT)
	tip_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.10, 0.95))
	tip_lbl.add_theme_constant_override("outline_size", 2)
	tip.add_child(tip_lbl)
	root.add_child(tip)

	var arrow := Label.new()
	arrow.name = "Arrow"
	arrow.text = "▶"
	arrow.add_theme_font_size_override("font_size", 22)
	arrow.add_theme_color_override("font_color", UI_BORDER)
	arrow.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.10, 0.95))
	arrow.add_theme_constant_override("outline_size", 3)
	arrow.size = Vector2(24, 24)
	arrow.pivot_offset = Vector2(12, 12)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(arrow)
	var pulse_tw := arrow.create_tween().set_loops()
	pulse_tw.tween_property(arrow, "modulate:a", 0.55, 0.7).set_trans(Tween.TRANS_SINE)
	pulse_tw.tween_property(arrow, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)

	return root

func _refresh_drone_hud_widgets() -> void:
	if _drone_hud_root == null:
		return
	while _drone_hud_widgets.size() > _drones_state.size():
		var w: Control = _drone_hud_widgets.pop_back()
		if is_instance_valid(w):
			w.queue_free()
	while _drone_hud_widgets.size() < _drones_state.size():
		var w := _make_drone_hud_widget()
		_drone_hud_root.add_child(w)
		_drone_hud_widgets.append(w)

func _update_drone_hud() -> void:
	if _drone_hud_root == null:
		return
	if _drone_hud_widgets.size() != _drones_state.size():
		_refresh_drone_hud_widgets()
	if _drone_hud_widgets.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	var center := vp * 0.5
	var margin := 36.0
	for i in _drone_hud_widgets.size():
		var w: Control = _drone_hud_widgets[i]
		if not is_instance_valid(w):
			continue
		if i >= _drone_nodes.size() or i >= _drones_state.size():
			w.visible = false
			continue
		var node: Node3D = _drone_nodes[i]
		var d: Dictionary = _drones_state[i]
		if not is_instance_valid(node):
			w.visible = false
			continue
		var world_pos := node.global_position
		var to_drone := world_pos - _cam.global_position
		var fwd := -_cam.global_transform.basis.z
		var forward := to_drone.dot(fwd)
		var screen_pos := _cam.unproject_position(world_pos)
		var off_screen: bool = forward <= 0.0 \
			or screen_pos.x < margin \
			or screen_pos.x > vp.x - margin \
			or screen_pos.y < margin \
			or screen_pos.y > vp.y - margin

		var tip: PanelContainer = w.get_node("Tip") as PanelContainer
		var tip_lbl: Label = tip.get_node("TipLabel") as Label
		var arrow: Label = w.get_node("Arrow") as Label
		w.visible = true

		if off_screen:
			tip.visible = false
			arrow.visible = true
			var dir: Vector2 = (screen_pos - center) if forward > 0.0 else (center - screen_pos)
			if dir.length_squared() < 0.0001:
				dir = Vector2(0, -1)
			dir = dir.normalized()
			var halfw := center.x - margin
			var halfh := center.y - margin
			var t_lim: float = INF
			if absf(dir.x) > 0.001:
				t_lim = minf(t_lim, halfw / absf(dir.x))
			if absf(dir.y) > 0.001:
				t_lim = minf(t_lim, halfh / absf(dir.y))
			var pos := center + dir * t_lim
			arrow.position = pos - Vector2(12, 12)
			arrow.rotation = dir.angle()
		else:
			arrow.visible = false
			tip.visible = true
			var state := String(d.get("state", "idle"))
			var lbl_state: String = DRONE_STATE_LABEL.get(state, state)
			tip_lbl.text = "D#%d — %s" % [int(d.get("id", 0)), lbl_state]
			tip.position = screen_pos + Vector2(10, 10)

func _make_drone_mesh() -> Node3D:
	var root := Node3D.new()
	root.name = "Drone"
	root.scale = Vector3.ONE * DRONE_VISUAL_SCALE

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.55, 0.62, 0.72)
	body_mat.metallic = 0.7
	body_mat.roughness = 0.3

	var thruster_mat := StandardMaterial3D.new()
	thruster_mat.albedo_color = Color(0.9, 0.4, 0.15)
	thruster_mat.emission_enabled = true
	thruster_mat.emission = Color(1.0, 0.45, 0.15)
	thruster_mat.emission_energy_multiplier = 1.6

	var arm_mat := StandardMaterial3D.new()
	arm_mat.albedo_color = Color(0.35, 0.40, 0.48)
	arm_mat.metallic = 0.5
	arm_mat.roughness = 0.4

	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.32
	body_mesh.height = 0.45
	body.mesh = body_mesh
	body.material_override = body_mat
	root.add_child(body)

	var arm_dirs := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for d in arm_dirs:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.7, 0.06, 0.06)
		arm.mesh = arm_mesh
		arm.material_override = arm_mat
		var basis := Basis.IDENTITY
		if d.z != 0.0:
			basis = Basis(Vector3.UP, PI * 0.5)
		arm.transform = Transform3D(basis, d * 0.45)
		root.add_child(arm)

		var thruster := MeshInstance3D.new()
		var th_mesh := SphereMesh.new()
		th_mesh.radius = 0.10
		th_mesh.height = 0.18
		thruster.mesh = th_mesh
		thruster.material_override = thruster_mat
		thruster.position = d * 0.85
		root.add_child(thruster)

	return root

func _make_factory_mesh() -> Node3D:
	var root := Node3D.new()
	root.name = "Factory"

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.45, 0.48, 0.55)
	body_mat.metallic = 0.4
	body_mat.roughness = 0.7

	var hangar_mat := StandardMaterial3D.new()
	hangar_mat.albedo_color = Color(0.30, 0.35, 0.42)
	hangar_mat.metallic = 0.5
	hangar_mat.roughness = 0.6

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.20, 0.55, 0.95)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.30, 0.65, 1.0)
	glow_mat.emission_energy_multiplier = 1.4

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(8.0, 2.0, 8.0)
	base.mesh = base_mesh
	base.material_override = body_mat
	base.position = Vector3(0, 1.0, 0)
	root.add_child(base)

	var tower := MeshInstance3D.new()
	var tower_mesh := CylinderMesh.new()
	tower_mesh.top_radius = 1.6
	tower_mesh.bottom_radius = 2.0
	tower_mesh.height = 4.0
	tower.mesh = tower_mesh
	tower.material_override = body_mat
	tower.position = Vector3(0, 4.0, 0)
	root.add_child(tower)

	var hangar := MeshInstance3D.new()
	var hangar_mesh := BoxMesh.new()
	hangar_mesh.size = Vector3(4.0, 3.0, 6.0)
	hangar.mesh = hangar_mesh
	hangar.material_override = hangar_mat
	hangar.position = Vector3(5.0, 2.5, 0)
	root.add_child(hangar)

	var antenna := MeshInstance3D.new()
	var ant_mesh := CylinderMesh.new()
	ant_mesh.top_radius = 0.08
	ant_mesh.bottom_radius = 0.12
	ant_mesh.height = 3.0
	antenna.mesh = ant_mesh
	antenna.material_override = body_mat
	antenna.position = Vector3(0, 7.5, 0)
	root.add_child(antenna)

	var glow := MeshInstance3D.new()
	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(0.6, 1.8, 5.6)
	glow.mesh = glow_mesh
	glow.material_override = glow_mat
	glow.position = Vector3(7.05, 2.4, 0)
	root.add_child(glow)

	return root

func _refresh_drones_visuals() -> void:
	while _drone_nodes.size() > _drones_state.size():
		var node: Node3D = _drone_nodes.pop_back()
		if is_instance_valid(node):
			node.queue_free()
		var beam: MeshInstance3D = _drone_beams.pop_back() if _drone_beams.size() > 0 else null
		if beam != null and is_instance_valid(beam):
			beam.queue_free()
	while _drone_nodes.size() < _drones_state.size():
		var idx: int = _drone_nodes.size()
		var n := _make_drone_mesh()
		add_child(n)
		var initial_pos: Vector3 = _ship.global_position
		if idx < _drone_target_pos.size():
			initial_pos = _drone_target_pos[idx]
		n.global_position = initial_pos
		_drone_nodes.append(n)
		var beam := _make_drone_beam()
		add_child(beam)
		_drone_beams.append(beam)
	_position_drones(0.0)

func _position_drones(delta: float) -> void:
	var count: int = _drone_nodes.size()
	if count == 0:
		return
	var ship_pos := _ship.global_position
	var t: float = float(Net.server_now_ms() - _epoch_ms) / 1000.0
	var k: float = 1.0 - exp(-DRONE_RECONCILE_RATE * delta) if delta > 0.0 else 1.0
	var elapsed_s: float = clampf(float(Net.server_now_ms() - _drone_target_t_ms) / 1000.0, 0.0, DRONE_EXTRAPOLATE_CAP_S)
	for i in count:
		var node: Node3D = _drone_nodes[i]
		if not is_instance_valid(node):
			continue
		var d: Dictionary = _drones_state[i] if i < _drones_state.size() else {}
		var state := String(d.get("state", "idle"))
		var beam: MeshInstance3D = _drone_beams[i] if i < _drone_beams.size() else null
		if state == "idle":
			var angle: float = TAU * float(i) / float(count)
			var slot_pos := ship_pos + Vector3(
				cos(angle) * DRONE_FORMATION_RADIUS,
				DRONE_FORMATION_HEIGHT,
				sin(angle) * DRONE_FORMATION_RADIUS,
			)
			var k_idle: float = 1.0 - exp(-DRONE_RECONCILE_RATE * delta) if delta > 0.0 else 1.0
			if node.global_position.distance_to(slot_pos) > 50.0:
				node.global_position = slot_pos
			else:
				node.global_position = node.global_position.lerp(slot_pos, k_idle)
			node.rotation.y = -angle + PI * 0.5
			if beam != null:
				beam.visible = false
		else:
			var target_pos: Vector3 = _drone_target_pos[i] if i < _drone_target_pos.size() else node.global_position
			var target_vel: Vector3 = _drone_target_vel[i] if i < _drone_target_vel.size() else Vector3.ZERO
			var extrapolated := target_pos + target_vel * elapsed_s
			node.global_position = node.global_position.lerp(extrapolated, k)
			var look_pos: Vector3
			if target_vel.length_squared() > 0.5:
				look_pos = node.global_position + target_vel
			elif state == "mining" or state == "to_target":
				look_pos = _drone_target_world_pos(d, t, ship_pos)
			else:
				look_pos = ship_pos
			var to_look := look_pos - node.global_position
			if to_look.length_squared() > 0.001:
				node.look_at(look_pos, Vector3.UP)
			if beam != null:
				if state == "mining":
					var ast_pos := _drone_target_world_pos(d, t, node.global_position)
					_show_drone_beam(beam, node.global_position, ast_pos)
				else:
					beam.visible = false

func _drone_target_world_pos(d: Dictionary, t: float, fallback: Vector3) -> Vector3:
	var ast_id: int = int(d.get("target_asteroid", 0))
	if ast_id <= 0:
		return fallback
	if _belt_id_to_idx.has(ast_id):
		var idx: int = int(_belt_id_to_idx[ast_id])
		if idx >= 0 and idx < _belt_alive.size() and _belt_alive[idx] == 1:
			return _world_pos_of_asteroid(idx, t)
	return fallback

func _make_drone_beam() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.16
	cyl.height = 1.0
	cyl.radial_segments = 10
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.45, 0.85, 1.0, 0.80)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.90, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

func _show_drone_beam(beam: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var delta_v := to - from
	var distance := delta_v.length()
	if distance < 0.05:
		beam.visible = false
		return
	var dir_n := delta_v / distance
	var up_ref: Vector3 = Vector3.RIGHT if absf(dir_n.y) > 0.99 else Vector3.UP
	var x_axis := up_ref.cross(dir_n).normalized()
	var z_axis := dir_n.cross(x_axis).normalized()
	var t := float(Time.get_ticks_msec()) / 1000.0
	var pulse: float = 0.85 + 0.30 * sin(t * 8.0)
	var basis := Basis(x_axis * pulse, dir_n * distance, z_axis * pulse)
	beam.global_transform = Transform3D(basis, from + delta_v * 0.5)
	var mat: StandardMaterial3D = beam.material_override
	mat.emission_energy_multiplier = 3.0 * pulse
	beam.visible = true

func _refresh_factories_visuals() -> void:
	while _factory_nodes.size() > _factories_state.size():
		var node: Node3D = _factory_nodes.pop_back()
		if is_instance_valid(node):
			node.queue_free()
	while _factory_nodes.size() < _factories_state.size():
		var idx: int = _factory_nodes.size()
		var f: Dictionary = _factories_state[idx] as Dictionary
		var pos_arr: Array = f.get("position", [0.0, 0.0, 0.0]) as Array
		var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var n := _make_factory_mesh()
		add_child(n)
		n.global_position = pos
		_factory_nodes.append(n)

func _build_inputs_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "InputsHud"
	layer.layer = 5
	add_child(layer)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_top = -210.0
	panel.offset_bottom = -16.0
	panel.theme_type_variation = &"HudPanel"
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var title := Label.new()
	title.text = "COMMANDES"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", UI_SUBTLE)
	box.add_child(title)
	box.add_child(_make_gradient_separator())

	var lines := [
		"Souris : orienter",
		"LMB : propulsion",
		"MMB : caméra orbitale",
		"ALT + clic droit : interagir",
		"E : inventaire",
		"ESC : menu pause",
	]
	for line_v in lines:
		var line: String = String(line_v)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var sep_idx: int = line.find(" : ")
		var key_text: String = line.substr(0, sep_idx) if sep_idx >= 0 else line
		var act_text: String = line.substr(sep_idx + 3) if sep_idx >= 0 else ""

		var key_pill := PanelContainer.new()
		var pill_style := StyleBoxFlat.new()
		pill_style.bg_color = Color(0.10, 0.16, 0.28, 0.85)
		pill_style.border_width_left = 1
		pill_style.border_width_right = 1
		pill_style.border_width_top = 1
		pill_style.border_width_bottom = 1
		pill_style.border_color = UI_BORDER_SOFT
		pill_style.corner_radius_top_left = 4
		pill_style.corner_radius_top_right = 4
		pill_style.corner_radius_bottom_left = 4
		pill_style.corner_radius_bottom_right = 4
		pill_style.content_margin_left = 6
		pill_style.content_margin_right = 6
		pill_style.content_margin_top = 1
		pill_style.content_margin_bottom = 1
		key_pill.add_theme_stylebox_override("panel", pill_style)
		var key_lbl := Label.new()
		key_lbl.text = key_text
		key_lbl.add_theme_font_size_override("font_size", 11)
		key_lbl.add_theme_color_override("font_color", UI_TITLE)
		key_pill.add_child(key_lbl)
		row.add_child(key_pill)

		var act_lbl := Label.new()
		act_lbl.text = act_text
		act_lbl.add_theme_font_size_override("font_size", 12)
		act_lbl.add_theme_color_override("font_color", UI_SUBTLE)
		act_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(act_lbl)

	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.4).set_delay(0.2).set_trans(Tween.TRANS_QUAD)

func _build_inventory_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "InventoryHud"
	layer.layer = 5
	add_child(layer)

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -220.0
	panel.offset_right = -16.0
	panel.offset_top = 16.0
	panel.theme_type_variation = &"HudPanel"
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Inventaire"
	_style_label_title(title, 14, UI_BORDER_SOFT)
	box.add_child(title)

	box.add_child(_make_gradient_separator())

	for kind in INV_KINDS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = INV_DISPLAY[kind]
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", UI_SUBTLE)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.text = "0"
		val_lbl.add_theme_font_size_override("font_size", 14)
		val_lbl.add_theme_color_override("font_color", UI_TITLE)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		_inv_labels[kind] = val_lbl

func _apply_inventory(inv: Dictionary) -> void:
	for kind in INV_KINDS:
		var amount := int(inv.get(kind, 0))
		var prev := int(_inv_state.get(kind, 0))
		_inv_state[kind] = amount
		if _inv_labels.has(kind):
			var label: Label = _inv_labels[kind]
			label.text = "%d" % amount
			if amount > prev:
				var pop_color: Color = KIND_POPUP_COLOR.get(kind, Color(1.6, 1.6, 1.6, 1.0))
				_pulse_label(label, pop_color * 1.6, 0.35)
	if _inv_panel_visible:
		_refresh_inventory_panel()

func _on_mine_tick(payload: Dictionary) -> void:
	_apply_inventory(payload.get("inventory", {}) as Dictionary)
	var aid := int(payload.get("asteroid_id", -1))
	var amount := int(payload.get("gained_amount", 0))
	var kind := String(payload.get("gained_kind", "iron"))
	if _belt_id_to_idx.has(aid):
		var idx := int(_belt_id_to_idx[aid])
		if _belt_stock.size() > idx:
			_belt_stock[idx] = int(payload.get("remaining", 0))
		if _belt_alive[idx] == 1 and amount > 0:
			var t: float = float(Net.server_now_ms() - _epoch_ms) / 1000.0
			_spawn_mine_popup(_world_pos_of_asteroid(idx, t), kind, amount)

func _on_asteroid_depleted(payload: Dictionary) -> void:
	_apply_inventory(payload.get("inventory", {}) as Dictionary)
	var aid := int(payload.get("asteroid_id", -1))
	var amount := int(payload.get("gained_amount", 0))
	var kind := String(payload.get("gained_kind", "iron"))
	if _belt_id_to_idx.has(aid):
		var idx := int(_belt_id_to_idx[aid])
		if _belt_alive[idx] == 1 and amount > 0:
			var t: float = float(Net.server_now_ms() - _epoch_ms) / 1000.0
			_spawn_mine_popup(_world_pos_of_asteroid(idx, t), kind, amount)
		if _belt_stock.size() > idx:
			_belt_stock[idx] = 0
		_belt_alive[idx] = 0
		_belt_omegas[idx] = 0.0
		_belt_scales[idx] = 0.0
		if _current_target_idx == idx:
			_current_target_idx = -1
			_hide_beam()

func _on_mine_reject(payload: Dictionary) -> void:
	var reason := String(payload.get("reason", "?"))
	var aid := int(payload.get("asteroid_id", -1))
	if reason == "asteroid_not_found" and _belt_id_to_idx.has(aid):
		var idx := int(_belt_id_to_idx[aid])
		_belt_alive[idx] = 0
		_belt_omegas[idx] = 0.0
		_belt_scales[idx] = 0.0
		if _current_target_idx == idx:
			_current_target_idx = -1
			_hide_beam()

const TEX_SIZE_PLANET: int = 512
const TEX_SIZE_MOON: int = 256
const TEX_SIZE_ASTEROID: int = 128
const TEX_SIZE_BH: int = 256

func _generate_textures() -> void:
	_planet_textures.clear()
	_moon_textures.clear()
	for i in 8:
		_planet_textures.append(_make_planet_texture(i, TEX_SIZE_PLANET))
	for i in 4:
		_moon_textures.append(_make_moon_texture(i, TEX_SIZE_MOON))
	_asteroid_texture = _make_asteroid_texture(TEX_SIZE_ASTEROID)
	_bh_sprite_texture = _make_bh_sprite_texture(TEX_SIZE_BH)

func _make_noise(seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.seed = seed
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n

func _make_planet_texture(seed: int, size: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 17
	var hue := rng.randf()
	var sat := rng.randf_range(0.4, 0.8)
	var base := Color.from_hsv(hue, sat, 0.55)
	var land := Color.from_hsv(hue, sat * 0.7, 0.85)
	var noise := _make_noise(seed, 0.012, 5)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var col := base.lerp(land, clamp(n, 0.0, 1.0))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _make_moon_texture(seed: int, size: int) -> ImageTexture:
	var noise := _make_noise(seed * 31 + 5, 0.04, 4)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var v: float = 0.4 + n * 0.45
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)

func _make_asteroid_texture(size: int) -> ImageTexture:
	var noise := _make_noise(1234, 0.08, 3)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var v: float = 0.55 + n * 0.35
			img.set_pixel(x, y, Color(v, v * 0.95, v * 0.85))
	return ImageTexture.create_from_image(img)

func _make_bh_sprite_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := float(size) * 0.5
	var max_r := center
	for y in size:
		for x in size:
			var dx := float(x) - center
			var dy := float(y) - center
			var r := sqrt(dx * dx + dy * dy) / max_r
			var col: Color
			if r < 0.18:
				col = Color(0.0, 0.0, 0.0, 1.0)
			elif r < 0.32:
				var t := (r - 0.18) / 0.14
				col = Color(1.0, 0.55 + t * 0.3, 0.15 + t * 0.2, 1.0)
			elif r < 0.6:
				var t := (r - 0.32) / 0.28
				col = Color(1.0 - t * 0.5, 0.4 - t * 0.2, 0.25 + t * 0.25, 1.0 - t)
			else:
				col = Color(0.0, 0.0, 0.0, 0.0)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
