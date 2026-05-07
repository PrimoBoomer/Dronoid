extends Node

var _layer: CanvasLayer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.name = "SkyLayer"
	_layer.layer = -100
	add_child(_layer)

	var rect := ColorRect.new()
	rect.name = "Sky"
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.BLACK

	var shader := load("res://shaders/starfield.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat

	_layer.add_child(rect)

func set_active(active: bool) -> void:
	if _layer != null:
		_layer.visible = active
