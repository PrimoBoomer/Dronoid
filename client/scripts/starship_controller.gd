extends Node3D
class_name StarshipController

# Reads pilot input each physics tick and forwards it to the server.
# Server is authoritative; this controller does NOT move the ship locally.
# State updates from the server will drive the visual transform later.

@export var send_to_server: bool = true
@export var send_hz: float = 30.0

var _seq: int = 0
var _accum: float = 0.0

func _physics_process(delta: float) -> void:
	var input := _sample_input()
	_accum += delta
	var period : float = 1.0 / max(send_hz, 1.0)
	if _accum < period:
		return
	_accum = 0.0
	if send_to_server and Net.is_session_open():
		_seq += 1
		Net.send_msg({
			"type": "input",
			"seq": _seq,
			"dt": delta,
			"thrust": input.thrust,
			"strafe": input.strafe,
			"lift": input.lift,
			"yaw": input.yaw,
			"pitch": input.pitch,
			"roll": input.roll,
		})

func _sample_input() -> Dictionary:
	var thrust := 0.0
	if Input.is_physical_key_pressed(KEY_W): thrust += 1.0
	if Input.is_physical_key_pressed(KEY_S): thrust -= 1.0

	var strafe := 0.0
	if Input.is_physical_key_pressed(KEY_D): strafe += 1.0
	if Input.is_physical_key_pressed(KEY_A): strafe -= 1.0

	var lift := 0.0
	if Input.is_physical_key_pressed(KEY_SPACE): lift += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL): lift -= 1.0

	var yaw := 0.0
	if Input.is_physical_key_pressed(KEY_E): yaw += 1.0
	if Input.is_physical_key_pressed(KEY_Q): yaw -= 1.0

	var pitch := 0.0
	if Input.is_physical_key_pressed(KEY_DOWN): pitch += 1.0
	if Input.is_physical_key_pressed(KEY_UP): pitch -= 1.0

	var roll := 0.0
	if Input.is_physical_key_pressed(KEY_C): roll += 1.0
	if Input.is_physical_key_pressed(KEY_Z): roll -= 1.0

	return {
		"thrust": thrust,
		"strafe": strafe,
		"lift": lift,
		"yaw": yaw,
		"pitch": pitch,
		"roll": roll,
	}
