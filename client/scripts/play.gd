extends Node3D

@export var thrust_accel: float = 10.0
@export var max_speed: float = 45.0
@export var brake_decel: float = 25.0
@export var mouse_sensitivity: float = 0.0012
@export var camera_lag: float = 6.0
@export var camera_offset: Vector3 = Vector3(0.0, 6.0, 28.0)

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
@onready var _status: Label = $UI/Status

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
var _last_mine_ms: int = 0
var _beam_mi: MeshInstance3D = null
var _beam_mesh: ImmediateMesh = null

var _action_kind: String = ""
var _action_target_kind: String = ""
var _action_target_idx: int = -1
var _action_target_node: Node3D = null
var _action_stop_distance: float = 0.0
var _action_pending_mine: bool = false
var _autopilot_mouse_accum: float = 0.0
var _mining: bool = false
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_status.text = "%s — %d planètes • %d astéroïdes • %d étoiles distantes" % [
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
	_apply_inventory(spawn.get("inventory", {}) as Dictionary)

	Net.mine_tick.connect(_on_mine_tick)
	Net.asteroid_depleted.connect(_on_asteroid_depleted)
	Net.mine_reject.connect(_on_mine_reject)

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

func _build_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "PauseMenu"
	_pause_layer.layer = 10
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	_pause_layer.add_child(dim)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	_pause_layer.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "Pause"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Reprendre"
	resume_btn.custom_minimum_size = Vector2(220, 40)
	resume_btn.pressed.connect(_on_resume_pressed)
	box.add_child(resume_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quitter au menu"
	quit_btn.custom_minimum_size = Vector2(220, 40)
	quit_btn.pressed.connect(_on_quit_to_menu_pressed)
	box.add_child(quit_btn)

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

func _resume() -> void:
	_paused = false
	get_tree().paused = false
	_pause_layer.visible = false
	_capture_mouse(true)

func _on_resume_pressed() -> void:
	_resume()

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

func _capture_mouse(capture: bool) -> void:
	_captured = capture
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE:
			_toggle_pause()
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
	if event is InputEventMouseMotion and _captured:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		_ship.rotate_object_local(Vector3.UP, -rel.x * mouse_sensitivity)
		_ship.rotate_object_local(Vector3.RIGHT, -rel.y * mouse_sensitivity)
		if _action_kind == "navigate":
			_autopilot_mouse_accum += rel.length()
			if _autopilot_mouse_accum >= AUTOPILOT_CANCEL_MOUSE:
				_cancel_autopilot()

func _process(delta: float) -> void:
	var alt_now := Input.is_key_pressed(KEY_ALT)
	if alt_now != _alt_held:
		_alt_held = alt_now
		if not _paused and not _ctx_open:
			_capture_mouse(not _alt_held)
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

func _update_mining(t: float) -> void:
	if not _mining or _belt_mm == null:
		_hide_beam()
		return
	var idx := _pick_target(t)
	_current_target_idx = idx
	if idx < 0:
		_hide_beam()
		return
	var target_pos := _world_pos_of_asteroid(idx, t)
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
	var ideal := _ideal_cam_transform()
	var k: float = 1.0 - exp(-camera_lag * delta)
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
		if _action_pending_mine:
			_action_pending_mine = false
			_mining = true
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
	_beam_mesh = ImmediateMesh.new()
	_beam_mi = MeshInstance3D.new()
	_beam_mi.name = "MiningBeam"
	_beam_mi.mesh = _beam_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.4, 0.2, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.2)
	mat.emission_energy_multiplier = 3.0
	_beam_mi.material_override = mat
	_beam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_mi.visible = false
	add_child(_beam_mi)

func _show_beam(target_world_pos: Vector3) -> void:
	_beam_mesh.clear_surfaces()
	_beam_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_beam_mesh.surface_add_vertex(_ship.global_position)
	_beam_mesh.surface_add_vertex(target_world_pos)
	_beam_mesh.surface_end()
	_beam_mi.visible = true

func _hide_beam() -> void:
	if _beam_mi != null:
		_beam_mi.visible = false

func _build_tooltip_ui() -> void:
	_tooltip_layer = CanvasLayer.new()
	_tooltip_layer.layer = 128
	add_child(_tooltip_layer)

	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_layer.add_child(_tooltip_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.10, 0.88)
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.6, 1.0, 0.6)
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left   = 10
	style.content_margin_right  = 10
	style.content_margin_top    = 6
	style.content_margin_bottom = 6
	_tooltip_panel.add_theme_stylebox_override("panel", style)

	_tooltip_label = Label.new()
	_tooltip_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	_tooltip_label.add_theme_font_size_override("font_size", 13)
	_tooltip_panel.add_child(_tooltip_label)

	_tooltip_connector = Line2D.new()
	_tooltip_connector.width = 1.0
	_tooltip_connector.default_color = Color(0.4, 0.6, 1.0, 0.6)
	_tooltip_connector.antialiased = true
	_tooltip_connector.visible = false
	_tooltip_layer.add_child(_tooltip_connector)

func _show_tooltip(text: String) -> void:
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
	btn.custom_minimum_size = Vector2(160, 0)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0)
	sn.content_margin_left = 10
	sn.content_margin_right = 10
	sn.content_margin_top = 5
	sn.content_margin_bottom = 5
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.2, 0.4, 0.9, 0.25)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.3, 0.5, 1.0, 0.35)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_stylebox_override("focus", sn)
	return btn

func _build_context_menu() -> void:
	_ctx_layer = CanvasLayer.new()
	_ctx_layer.layer = 64
	add_child(_ctx_layer)

	_ctx_panel = PanelContainer.new()
	_ctx_panel.visible = false
	_ctx_layer.add_child(_ctx_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.10, 0.92)
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.6, 1.0, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_ctx_panel.add_theme_stylebox_override("panel", style)

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
	await get_tree().process_frame
	var sz := _ctx_panel.size
	var vp := get_viewport().get_visible_rect().size
	var x := minf(screen_pos.x, vp.x - sz.x - 4.0)
	var y := minf(screen_pos.y, vp.y - sz.y - 4.0)
	_ctx_panel.position = Vector2(maxf(x, 4.0), maxf(y, 4.0))

	_ctx_open = true

func _close_context_menu() -> void:
	_ctx_open = false
	_ctx_panel.visible = false

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

func _build_inputs_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "InputsHud"
	layer.layer = 5
	add_child(layer)

	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_bottom = 1.0
	box.anchor_top = 1.0
	box.offset_left = 16.0
	box.offset_bottom = -16.0
	box.offset_top = -180.0
	box.add_theme_constant_override("separation", 2)
	layer.add_child(box)

	var lines := [
		"Souris : orienter",
		"LMB : propulsion",
		"RMB : minage",
		"ALT : libérer le curseur",
		"ESC : menu pause",
	]
	for line in lines:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		box.add_child(l)

func _build_inventory_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "InventoryHud"
	layer.layer = 5
	add_child(layer)

	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -200.0
	box.offset_right = -16.0
	box.offset_top = 16.0
	box.add_theme_constant_override("separation", 4)
	layer.add_child(box)

	var title := Label.new()
	title.text = "Inventaire"
	title.add_theme_font_size_override("font_size", 14)
	box.add_child(title)

	for kind in INV_KINDS:
		var l := Label.new()
		l.text = "%s : 0" % INV_DISPLAY[kind]
		l.add_theme_font_size_override("font_size", 14)
		box.add_child(l)
		_inv_labels[kind] = l

func _apply_inventory(inv: Dictionary) -> void:
	for kind in INV_KINDS:
		var amount := int(inv.get(kind, 0))
		if _inv_labels.has(kind):
			var label: Label = _inv_labels[kind]
			label.text = "%s : %d" % [INV_DISPLAY[kind], amount]

func _on_mine_tick(payload: Dictionary) -> void:
	_apply_inventory(payload.get("inventory", {}) as Dictionary)
	var aid := int(payload.get("asteroid_id", -1))
	if _belt_id_to_idx.has(aid):
		var idx := int(_belt_id_to_idx[aid])
		if _belt_stock.size() > idx:
			_belt_stock[idx] = int(payload.get("remaining", 0))

func _on_asteroid_depleted(payload: Dictionary) -> void:
	_apply_inventory(payload.get("inventory", {}) as Dictionary)
	var aid := int(payload.get("asteroid_id", -1))
	if _belt_id_to_idx.has(aid):
		var idx := int(_belt_id_to_idx[aid])
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
