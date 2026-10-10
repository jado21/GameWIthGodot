extends Node3D
## Genera la arena a partir de ArenaData, con una malla y colisión por sólido.

func _ready() -> void:
	_add_environment()
	_build_floor()
	for box in ArenaData.BOXES:
		_build_box(box)
	for ramp in ArenaData.RAMPS:
		_build_ramp(ramp)
	_build_markers()

func _add_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("2f6fc4")
	sky_material.sky_horizon_color = Color("8fc2ee")
	sky_material.ground_bottom_color = Color("d8e2e8")
	sky_material.ground_horizon_color = Color("f1e4c6")
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.fog_enabled = true
	environment.fog_light_color = Color("d8e2e8")
	environment.fog_density = 0.008
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

func _build_floor() -> void:
	var floor := StaticBody3D.new()
	floor.name = "Suelo"
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ArenaData.FLOOR_SIZE, ArenaData.FLOOR_SIZE)
	plane.material = _flat_material(ArenaData.FLOOR_COLOR)
	mesh_instance.mesh = plane
	floor.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(ArenaData.FLOOR_SIZE, 0.1, ArenaData.FLOOR_SIZE)
	collision.position.y = -0.05
	collision.shape = shape
	floor.add_child(collision)
	add_child(floor)
	for patch in ArenaData.PATCHES:
		_build_patch(patch)

func _build_patch(data: Array) -> void:
	var x0: float = data[0]
	var x1: float = data[1]
	var z0: float = data[2]
	var z1: float = data[3]
	var patch := MeshInstance3D.new()
	patch.name = "ParcheSuelo"
	patch.position = Vector3((x0 + x1) * 0.5, 0.01, (z0 + z1) * 0.5)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(x1 - x0, z1 - z0)
	mesh.material = _flat_material(data[4])
	patch.mesh = mesh
	add_child(patch)

func _build_box(data: Array) -> void:
	var body := StaticBody3D.new()
	body.name = "Caja"
	var width: float = data[2]
	var depth: float = data[3]
	var height: float = data[4]
	body.position = Vector3(data[0], height * 0.5, data[1])
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, depth)
	mesh.material = _flat_material(data[5])
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, depth)
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _build_ramp(data: Array) -> void:
	var width: float = data[2]
	var length: float = data[3]
	var height: float = data[4]
	var vertices := PackedVector3Array([
		Vector3(-width * 0.5, 0.0, -length * 0.5), Vector3(width * 0.5, 0.0, -length * 0.5),
		Vector3(width * 0.5, 0.0, length * 0.5), Vector3(-width * 0.5, 0.0, length * 0.5),
		Vector3(-width * 0.5, height, length * 0.5), Vector3(width * 0.5, height, length * 0.5),
	])
	var indices := PackedInt32Array([0, 1, 5, 0, 5, 4, 3, 2, 5, 3, 5, 4, 0, 3, 4, 0, 4, 5, 0, 5, 1, 1, 5, 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var body := StaticBody3D.new()
	body.name = "Rampa"
	body.position = Vector3(data[0], 0.0, data[1])
	body.rotation.y = data[5]
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _flat_material(data[6])
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _build_markers() -> void:
	var container := Node3D.new()
	container.name = "Marcadores"
	container.add_to_group("spawns")
	add_child(container)
	for marker_type in ArenaData.MARKERS:
		for index in range(ArenaData.MARKERS[marker_type].size()):
			var marker := Marker3D.new()
			marker.name = "%s_%d" % [marker_type, index + 1]
			marker.position = ArenaData.MARKERS[marker_type][index]
			if marker_type == "Jugador":
				marker.rotation.y = PI
			marker.add_to_group("spawns")
			container.add_child(marker)

func _flat_material(hex_color: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = _color_from_hex(hex_color)
	material.roughness = 0.9
	return material

func _color_from_hex(hex_color: int) -> Color:
	return Color(float((hex_color >> 16) & 0xff) / 255.0, float((hex_color >> 8) & 0xff) / 255.0, float(hex_color & 0xff) / 255.0)
