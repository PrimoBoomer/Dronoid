extends Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var layer := CanvasLayer.new()
	layer.name = "SkyLayer"
	layer.layer = -100
	add_child(layer)

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

	layer.add_child(rect)
