extends Node
## Pool reutilizable de partículas cúbicas para no superar el presupuesto visual.
const MAX_PARTICLES := 200
var pool: Array[GPUParticles3D] = []
var cursor := 0
var slow_border: Panel

func _ready() -> void:
	add_to_group("vfx")
	for index in range(10):
		var emitter := GPUParticles3D.new()
		emitter.amount = 20
		emitter.lifetime = 0.55
		emitter.one_shot = true
		emitter.emitting = false
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * 0.18
		emitter.draw_pass_1 = mesh
		add_child(emitter)
		pool.append(emitter)
	_create_screen_fx()

func _process(_delta: float) -> void:
	if slow_border: slow_border.modulate.a = 0.75 if Engine.time_scale < 0.99 else 0.0

func _create_screen_fx() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var vignette := Panel.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dark := StyleBoxFlat.new()
	dark.bg_color = Color(0, 0, 0, 0)
	dark.border_color = Color(0,0,0,0.32)
	dark.set_border_width_all(55)
	vignette.add_theme_stylebox_override("panel", dark)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vignette)
	slow_border = Panel.new()
	slow_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var blue := StyleBoxFlat.new()
	blue.bg_color = Color(0, 0, 0, 0)
	blue.border_color = Color(0.3,0.7,1.0,0.8)
	blue.set_border_width_all(35)
	slow_border.add_theme_stylebox_override("panel", blue)
	slow_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slow_border.modulate.a = 0.0
	layer.add_child(slow_border)

func burst(position: Vector3, color: Color, amount := 12, speed := 5.0) -> void:
	var emitter := pool[cursor]
	cursor = (cursor + 1) % pool.size()
	emitter.position = position
	emitter.amount = mini(amount, 20)
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 180.0
	material.initial_velocity_min = speed * 0.4
	material.initial_velocity_max = speed
	material.color = color
	emitter.process_material = material
	emitter.restart()
