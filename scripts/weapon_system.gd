extends Node
## Detector, objetos ocultos, inventario y disparo sin lógica de monstruo ni sonido.

const DATA = preload("res://scripts/weapons_data.gd")

@onready var player: CharacterBody3D = get_parent()
@onready var camera: Camera3D = $"../Camera3D"
@onready var weapon_label: Label = $"../HUD/Armas"
@onready var message_label: Label = $"../HUD/Mensaje"
@onready var crosshair: Label = $"../HUD/Mira"

var items: Array[Dictionary] = []
var owned := {"pistol": false, "shotgun": false, "rifle": false}
var ammo := {"pistol": 0, "shotgun": 0, "rifle": 0}
var equipped := ""
var detector_cd := 0.0
var pulse_radius := -1.0
var pulse_id := 0
var fire_cd := 0.0
var firing := false
var recoil := 0.0
var applied_recoil := 0.0
var message_time := 0.0
var hit_time := 0.0
var flash_time := 0.0
var ring_mesh: ImmediateMesh
var ring: MeshInstance3D
var weapon_view: Node3D
var weapon_models := {}
var muzzle_flash: MeshInstance3D
var flash_light: OmniLight3D
var tracers: Array[Dictionary] = []

func _ready() -> void:
	process_priority = 10
	_configure_input_map()
	_create_detector_ring()
	_create_weapon_view()
	_say("Pulsa E para detectar metal", 5.0)
	call_deferred("_spawn_items_from_markers")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("detector"):
		_start_pulse()
	if event.is_action_pressed("fire_key"):
		firing = true
		_fire()
	if event.is_action_released("fire_key"):
		firing = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		firing = event.pressed
		if event.pressed:
			_fire()
	if event.is_action_pressed("weapon_1"):
		_select_weapon("pistol")
	if event.is_action_pressed("weapon_2"):
		_select_weapon("shotgun")
	if event.is_action_pressed("weapon_3"):
		_select_weapon("rifle")

func _process(delta: float) -> void:
	detector_cd = maxf(detector_cd - delta, 0.0)
	fire_cd = maxf(fire_cd - delta, 0.0)
	message_time = maxf(message_time - delta, 0.0)
	hit_time = maxf(hit_time - delta, 0.0)
	flash_time = maxf(flash_time - delta, 0.0)
	if firing and not equipped.is_empty() and DATA.WEAPONS[equipped]["auto"]:
		_fire()
	_update_pulse(delta)
	_update_items(delta)
	_try_pickup()
	_update_recoil(delta)
	_update_weapon_view()
	_update_tracers(delta)
	_update_hud()

func _spawn_items_from_markers() -> void:
	for node in get_tree().get_nodes_in_group("spawns"):
		if not node is Marker3D:
			continue
		var marker: Marker3D = node
		var marker_name := marker.name.to_lower()
		if marker_name.begins_with("pistola"):
			_add_item("pistol", marker.global_position)
		elif marker_name.begins_with("escopeta"):
			_add_item("shotgun", marker.global_position)
		elif marker_name.begins_with("rifle"):
			_add_item("rifle", marker.global_position)
		elif marker_name.begins_with("municion"):
			_add_item("ammo", marker.global_position)

func _add_item(kind: String, position: Vector3) -> void:
	var visual := Node3D.new()
	visual.name = "Objeto_%s" % kind
	visual.top_level = true
	visual.global_position = position
	var color := Color("66ff88") if kind == "ammo" else Color("ffd24a")
	var material := _overlay_material(color)
	var octa := MeshInstance3D.new()
	octa.mesh = _octahedron_mesh(0.5)
	octa.material_override = material
	visual.add_child(octa)
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.04
	beam_mesh.bottom_radius = 0.04
	beam_mesh.height = 9.0
	beam.mesh = beam_mesh
	beam.position.y = 4.5
	beam.material_override = material
	visual.add_child(beam)
	visual.visible = false
	add_child(visual)
	items.append({"kind": kind, "node": visual, "material": material, "reveal": 0.0, "last_pulse": -1})

func _start_pulse() -> void:
	if detector_cd > 0.0 or pulse_radius >= 0.0:
		return
	detector_cd = DATA.DET["cd"]
	pulse_radius = 0.0
	pulse_id += 1

func _update_pulse(delta: float) -> void:
	if pulse_radius < 0.0:
		ring.visible = false
		return
	pulse_radius += DATA.DET["speed"] * delta
	ring.global_position = player.global_position + Vector3.UP * 0.04
	_draw_ring(pulse_radius, 0.9 * maxf(0.0, 1.0 - pulse_radius / DATA.DET["range"]))
	for item in items:
		if item["last_pulse"] != pulse_id and player.global_position.distance_to(item["node"].global_position) <= pulse_radius:
			item["reveal"] = DATA.DET["reveal"]
			item["last_pulse"] = pulse_id
	if pulse_radius > DATA.DET["range"]:
		pulse_radius = -1.0
		ring.visible = false

func _update_items(delta: float) -> void:
	var body_center := player.global_position + Vector3.UP
	for item in items:
		item["reveal"] = maxf(0.0, item["reveal"] - delta)
		var visual: Node3D = item["node"]
		visual.rotation.y += delta * 1.5
		var distance := body_center.distance_to(visual.global_position)
		var proximity: float = (1.0 - distance / DATA.DET["prox"]) * 0.9
		var alpha := clampf(maxf(item["reveal"] / DATA.DET["reveal"], proximity), 0.0, 1.0)
		visual.visible = alpha >= 0.02
		var material: StandardMaterial3D = item["material"]
		material.albedo_color.a = alpha

func _try_pickup() -> void:
	for index in range(items.size() - 1, -1, -1):
		var item := items[index]
		var item_position: Vector3 = item["node"].global_position
		var horizontal := Vector2(item_position.x - player.global_position.x, item_position.z - player.global_position.z).length()
		if horizontal >= DATA.DET["pick"] or absf(item_position.y - (player.global_position.y + 1.0)) >= 2.5:
			continue
		if item["kind"] == "ammo":
			if not _has_weapon():
				continue
			for weapon_id in owned:
				if owned[weapon_id]:
					ammo[weapon_id] = mini(ammo[weapon_id] + DATA.WEAPONS[weapon_id]["box"], DATA.WEAPONS[weapon_id]["max"])
			_say("¡Munición recogida!")
		else:
			var weapon_id: String = item["kind"]
			owned[weapon_id] = true
			ammo[weapon_id] = mini(ammo[weapon_id] + DATA.WEAPONS[weapon_id]["start"], DATA.WEAPONS[weapon_id]["max"])
			equipped = weapon_id
			_say("¡%s encontrada!" % DATA.WEAPONS[weapon_id]["name"])
		item["node"].queue_free()
		items.remove_at(index)

func _select_weapon(weapon_id: String) -> void:
	if owned[weapon_id]:
		equipped = weapon_id

func _fire() -> void:
	if equipped.is_empty():
		_say("No tienes arma: usa el detector (E)")
		return
	if fire_cd > 0.0:
		return
	if ammo[equipped] <= 0:
		_say("Sin munición: busca cajas verdes con el detector (E)")
		fire_cd = 0.4
		return
	var weapon: Dictionary = DATA.WEAPONS[equipped]
	fire_cd = weapon["cd"]
	ammo[equipped] -= 1
	recoil = minf(0.25, recoil + weapon["kick"])
	flash_time = 0.06
	for pellet in range(int(weapon["pellets"])):
		_shoot_ray(weapon["spread"], weapon["dmg"])

func _shoot_ray(spread: float, damage: float) -> void:
	var vertical_fov := deg_to_rad(camera.fov)
	var maximum_deviation := (spread * 0.5) * (vertical_fov * 0.5)
	var direction := (-camera.global_transform.basis.z + camera.global_transform.basis.x * tan(randf_range(-maximum_deviation, maximum_deviation)) + camera.global_transform.basis.y * tan(randf_range(-maximum_deviation, maximum_deviation))).normalized()
	var origin := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 120.0, 0xffffffff, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	var end := origin + direction * 80.0
	var hit_damageable := false
	if not hit.is_empty():
		end = hit["position"]
		var target: Node = hit["collider"] as Node
		if target != null and target.has_method("take_damage"):
			target.call("take_damage", damage)
			hit_damageable = true
		elif target != null and target.is_in_group("monster") and target.has_method("take_damage"):
			target.call("take_damage", damage)
			hit_damageable = true
		_spawn_impact(end, Color("c070ff") if hit_damageable else Color("ffee55"))
	if hit_damageable:
		hit_time = 0.09
	_spawn_tracer(_hand_position(), end)

func _spawn_tracer(start: Vector3, end: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(end)
	mesh.surface_end()
	var line := MeshInstance3D.new()
	line.top_level = true
	line.mesh = mesh
	line.material_override = _overlay_material(Color("ffee55"))
	add_child(line)
	tracers.append({"node": line, "life": 0.14})

func _spawn_impact(position: Vector3, color: Color) -> void:
	var spark := MeshInstance3D.new()
	spark.top_level = true
	spark.global_position = position
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	spark.mesh = mesh
	spark.material_override = _overlay_material(color)
	add_child(spark)
	tracers.append({"node": spark, "life": 0.14})

func _update_tracers(delta: float) -> void:
	for index in range(tracers.size() - 1, -1, -1):
		tracers[index]["life"] -= delta
		if tracers[index]["life"] <= 0.0:
			tracers[index]["node"].queue_free()
			tracers.remove_at(index)

func _update_recoil(delta: float) -> void:
	# Se retira el desplazamiento visual anterior antes de aplicar el nuevo.
	camera.rotation.x = clampf(camera.rotation.x - applied_recoil, -1.5, 1.5)
	recoil = maxf(0.0, recoil - recoil * delta * 8.0 - delta * 0.02)
	applied_recoil = recoil
	camera.rotation.x = clampf(camera.rotation.x + applied_recoil, -1.5, 1.5)

func _create_detector_ring() -> void:
	ring_mesh = ImmediateMesh.new()
	ring = MeshInstance3D.new()
	ring.name = "PulsoDetector"
	ring.mesh = ring_mesh
	ring.top_level = true
	ring.material_override = _overlay_material(Color("44ddff"))
	ring.visible = false
	add_child(ring)

func _draw_ring(radius: float, alpha: float) -> void:
	ring_mesh.clear_surfaces()
	ring_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(48):
		var a := TAU * float(index) / 48.0
		var b := TAU * float(index + 1) / 48.0
		ring_mesh.surface_add_vertex(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		ring_mesh.surface_add_vertex(Vector3(cos(b) * radius, 0.0, sin(b) * radius))
	ring_mesh.surface_end()
	var material: StandardMaterial3D = ring.material_override as StandardMaterial3D
	material.albedo_color.a = alpha
	ring.visible = true

func _create_weapon_view() -> void:
	weapon_view = Node3D.new()
	weapon_view.name = "ArmaPrimeraPersona"
	weapon_view.position = Vector3(0.3, -0.28, -0.55)
	camera.add_child(weapon_view)
	weapon_models["pistol"] = _make_model([[[0.07, 0.10, 0.28], [0.0, 0.0, 0.0], "3a3f47"], [[0.06, 0.14, 0.08], [0.0, -0.10, 0.08], "2a2d33"], [[0.045, 0.045, 0.10], [0.0, 0.02, -0.17], "9aa3ad"]])
	weapon_models["shotgun"] = _make_model([[[0.09, 0.10, 0.50], [0.0, 0.0, 0.05], "6b4526"], [[0.05, 0.05, 0.50], [0.0, 0.04, -0.35], "8a929c"], [[0.06, 0.06, 0.30], [0.0, -0.02, -0.28], "8a929c"]])
	weapon_models["rifle"] = _make_model([[[0.08, 0.12, 0.60], [0.0, 0.0, 0.0], "2f4a36"], [[0.04, 0.04, 0.40], [0.0, 0.03, -0.45], "20242a"], [[0.06, 0.14, 0.10], [0.0, -0.12, 0.10], "20242a"]])
	muzzle_flash = MeshInstance3D.new()
	var flash_mesh := BoxMesh.new()
	flash_mesh.size = Vector3(0.12, 0.12, 0.12)
	muzzle_flash.mesh = flash_mesh
	muzzle_flash.position = Vector3(0.0, 0.02, -0.62)
	muzzle_flash.material_override = _overlay_material(Color("ffe066"))
	weapon_view.add_child(muzzle_flash)
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color("ffcc66")
	flash_light.omni_range = 18.0
	camera.add_child(flash_light)

func _make_model(parts: Array) -> Node3D:
	var model := Node3D.new()
	for part in parts:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(part[0][0], part[0][1], part[0][2])
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = Vector3(part[1][0], part[1][1], part[1][2])
		node.material_override = _overlay_material(Color(part[2]))
		model.add_child(node)
	weapon_view.add_child(model)
	return model

func _update_weapon_view() -> void:
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var walking := player.is_on_floor() and not bool(player.get("sliding"))
	var sway := sin(Time.get_ticks_msec() / 1000.0 * 8.0) * 0.012 * minf(speed / 10.0, 1.0) if walking else 0.0
	weapon_view.visible = not equipped.is_empty()
	weapon_view.position = Vector3(0.3 + sway, -0.28 + (-0.1 if bool(player.get("sliding")) else 0.0), -0.55 + recoil * 1.4)
	weapon_view.rotation.x = recoil * 2.0
	muzzle_flash.visible = flash_time > 0.0 and not equipped.is_empty()
	flash_light.light_energy = 2.5 if flash_time > 0.0 else 0.0
	for weapon_id in weapon_models:
		weapon_models[weapon_id].visible = weapon_id == equipped

func _update_hud() -> void:
	var lines: Array[String] = []
	for weapon_id in ["pistol", "shotgun", "rifle"]:
		if owned[weapon_id]:
			lines.append("%s%s · %d" % ["▶ " if weapon_id == equipped else "", DATA.WEAPONS[weapon_id]["name"], ammo[weapon_id]])
	lines.append("DETECTOR [E]: %s" % ("LISTO" if detector_cd <= 0.0 else "%.1f s" % detector_cd))
	weapon_label.text = "\n".join(lines)
	message_label.modulate.a = minf(message_time, 1.0)
	crosshair.visible = not equipped.is_empty()
	crosshair.modulate = Color("ff3b3b") if hit_time > 0.0 else Color.WHITE

func _say(text: String, duration := 2.2) -> void:
	message_label.text = text
	message_time = duration

func _has_weapon() -> bool:
	return owned["pistol"] or owned["shotgun"] or owned["rifle"]

func _hand_position() -> Vector3:
	return camera.global_position + camera.global_transform.basis.x * 0.28 - camera.global_transform.basis.y * 0.22 - camera.global_transform.basis.z * 0.6

func _overlay_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = 127
	return material

func _octahedron_mesh(radius: float) -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3.UP * radius, Vector3.DOWN * radius, Vector3(radius, 0, 0), Vector3(0, 0, radius), Vector3(-radius, 0, 0), Vector3(0, 0, -radius)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 3, 0, 3, 4, 0, 4, 5, 0, 5, 2, 1, 3, 2, 1, 4, 3, 1, 5, 4, 1, 2, 5])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _configure_input_map() -> void:
	_add_key("detector", KEY_E)
	_add_key("fire_key", KEY_F)
	_add_key("weapon_1", KEY_1)
	_add_key("weapon_2", KEY_2)
	_add_key("weapon_3", KEY_3)

func _add_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.keycode = keycode
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)
