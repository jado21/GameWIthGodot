extends Node3D
## Construye una arena gray-box con colisiones para probar la locomoción.

func _ready() -> void:
	_add_light()
	_box(Vector3(0, -0.5, 0), Vector3(50, 1, 50), Color("78838f"), "Suelo")
	_box(Vector3(0, 3, -25), Vector3(50, 6, 1), Color("56606e"), "ParedSur")
	_box(Vector3(0, 3, 25), Vector3(50, 6, 1), Color("56606e"), "ParedNorte")
	_box(Vector3(-25, 3, 0), Vector3(1, 6, 50), Color("56606e"), "ParedOeste")
	_box(Vector3(25, 3, 0), Vector3(1, 6, 50), Color("56606e"), "ParedEste")
	_box(Vector3(7, 0.5, 5), Vector3(8, 1, 7), Color("d8994d"), "PlataformaBaja")
	_box(Vector3(-9, 4, 7), Vector3(2, 8, 8), Color("9a5d5d"), "ParedAlta")
	# Pilares de 8 m con sus centros a 4 m para encadenar saltos de pared.
	_box(Vector3(-2, 4, -15), Vector3(1, 8, 3), Color("6f8fa8"), "PilarMuroOeste")
	_box(Vector3(2, 4, -15), Vector3(1, 8, 3), Color("6f8fa8"), "PilarMuroEste")
	_box(Vector3(14, 8, -10), Vector3(5, 16, 5), Color("7d6ab0"), "TorreGancho")
	_ramp(Vector3(-8, 0, -8), 8.0, 12.0, 4.0)

func _add_light() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("bcd3e6")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)

func _box(center: Vector3, size: Vector3, color: Color, label: String) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = center
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _ramp(origin: Vector3, width: float, length: float, height: float) -> void:
	var vertices := PackedVector3Array([
		Vector3(-width / 2.0, 0, -length / 2.0), Vector3(width / 2.0, 0, -length / 2.0),
		Vector3(width / 2.0, 0, length / 2.0), Vector3(-width / 2.0, 0, length / 2.0),
		Vector3(-width / 2.0, height, length / 2.0), Vector3(width / 2.0, height, length / 2.0)
	])
	var indices := PackedInt32Array([0, 1, 5, 0, 5, 4, 3, 2, 5, 3, 5, 4, 0, 3, 4, 0, 4, 5, 0, 5, 1, 1, 5, 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var ramp_mesh := ArrayMesh.new()
	ramp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var body := StaticBody3D.new()
	body.name = "Rampa"
	body.position = origin
	var mesh := MeshInstance3D.new()
	mesh.mesh = ramp_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("58b09c")
	mesh.material_override = material
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
