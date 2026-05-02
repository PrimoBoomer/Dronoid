extends Node

const CLIENT_VERSION := "0.0.1"

signal connected(session_id: String)
signal disconnected()
signal failed(reason: String)
signal message(msg: Dictionary)
signal spawned(spawn: Dictionary)
signal mine_tick(payload: Dictionary)
signal asteroid_depleted(payload: Dictionary)
signal mine_reject(payload: Dictionary)

var current_spawn: Dictionary = {}

# Offset between server clock and local clock, in ms.
# server_time_ms ≈ local_unix_ms + _server_offset_ms
var _server_offset_ms: int = 0
var _has_server_time: bool = false

var _peer: WebSocketPeer = null
var _pending_name: String = ""
var _hello_sent: bool = false
var _last_state: int = WebSocketPeer.STATE_CLOSED

func connect_to(url: String, player_name: String) -> void:
	disconnect_now()
	_peer = WebSocketPeer.new()
	# Le spawn peut peser plusieurs centaines de Ko (ceinture d'astéroïdes),
	# au-dessus du défaut Godot (64 Ko). On dimensionne large.
	_peer.inbound_buffer_size = 8 * 1024 * 1024
	_peer.outbound_buffer_size = 1 * 1024 * 1024
	_peer.max_queued_packets = 4096
	_pending_name = player_name
	_hello_sent = false
	_last_state = WebSocketPeer.STATE_CLOSED
	current_spawn = {}
	var err := _peer.connect_to_url(url)
	if err != OK:
		_peer = null
		failed.emit("connect_to_url failed: %d" % err)
		return
	set_process(true)

func disconnect_now() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	_hello_sent = false
	set_process(false)

func is_session_open() -> bool:
	return _peer != null and _hello_sent and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN

func send_msg(msg: Dictionary) -> bool:
	if not is_session_open():
		return false
	return _peer.send_text(JSON.stringify(msg)) == OK

func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	var state := _peer.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN and not _hello_sent:
		var hello := {
			"type": "hello",
			"name": _pending_name,
			"client_version": CLIENT_VERSION,
		}
		_peer.send_text(JSON.stringify(hello))
		_hello_sent = true

	if state == WebSocketPeer.STATE_OPEN:
		while _peer.get_available_packet_count() > 0:
			var pkt := _peer.get_packet()
			var text := pkt.get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) != TYPE_DICTIONARY:
				continue
			var dict: Dictionary = parsed
			message.emit(dict)
			match dict.get("type", ""):
				"welcome":
					var srv_now := int(dict.get("server_now_ms", 0))
					if srv_now > 0:
						var local_ms := int(Time.get_unix_time_from_system() * 1000.0)
						_server_offset_ms = srv_now - local_ms
						_has_server_time = true
					connected.emit(String(dict.get("session_id", "")))
				"spawn":
					current_spawn = dict
					spawned.emit(dict)
				"mine_tick":
					mine_tick.emit(dict)
				"asteroid_depleted":
					asteroid_depleted.emit(dict)
				"mine_reject":
					mine_reject.emit(dict)
				"error":
					failed.emit(String(dict.get("message", "server error")))
					disconnect_now()
					return

	if state == WebSocketPeer.STATE_CLOSED and _last_state != WebSocketPeer.STATE_CLOSED:
		var code := _peer.get_close_code()
		var reason := _peer.get_close_reason()
		_peer = null
		set_process(false)
		if code == -1 and reason == "":
			failed.emit("connexion impossible")
		else:
			disconnected.emit()
		return

	_last_state = state

func send_mine(asteroid_id: int) -> bool:
	return send_msg({"type": "mine", "asteroid_id": asteroid_id})

func server_now_ms() -> int:
	var local_ms := int(Time.get_unix_time_from_system() * 1000.0)
	return local_ms + _server_offset_ms

func _ready() -> void:
	set_process(false)
