extends CharacterBody3D
## Controlador de primera persona: correr, salto, deslizamiento y esquiva.

@onready var camera: Camera3D = $Camera3D
@onready var status: Label = $HUD/Estado
@onready var zone_label: Label = $HUD/Zona

var coyote_time := 0.0
var jump_buffer := 0.0
var dash_time := 0.0
var dash_cooldown := 0.0
var dash_direction := Vector3.ZERO
var dash_side := 0.0
var sliding := false
var last_tap := {}
var bob_time := 0.0
var camera_roll := 0.0
var extra_jumps := 1
var wall_jump_cooldown := 0.0
var fov_kick := 0.0
var hooked := false
var hook_cooldown := 0.0
var hook_time := 0.0
var hook_best_distance := INF
var hook_stuck_time := 0.0
var hook_target := Vector3.ZERO
var hook_anchor := Vector3.ZERO
var hook_message := ""
var hook_message_time := 0.0
var rope_mesh: ImmediateMesh
var rope: MeshInstance3D
var hook_piece: MeshInstance3D

func _ready() -> void:
	_configure_input_map()
	_create_hook_visual()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = Config.FOV

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * Config.SENS)
		camera.rotation.x = clamp(camera.rotation.x - event.relative.y * Config.SENS, -1.5, 1.5)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_toggle_hook()
			return
	if event.is_action_pressed("jump"):
		if hooked:
			_release_hook(true)
		else:
			jump_buffer = Config.BUFFER
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		if event.is_action_pressed(action):
			_check_double_tap(action)
	if event.is_action_pressed("dash"):
		_start_dash(_movement_direction())
	if event.is_action_pressed("hook"):
		_toggle_hook()

func _physics_process(delta: float) -> void:
	jump_buffer = maxf(jump_buffer - delta, 0.0)
	dash_cooldown = maxf(dash_cooldown - delta, 0.0)
	wall_jump_cooldown = maxf(wall_jump_cooldown - delta, 0.0)
	hook_cooldown = maxf(hook_cooldown - delta, 0.0)
	hook_message_time = maxf(hook_message_time - delta, 0.0)
	if hooked:
		_pull_hook(delta)
		move_and_slide()
		_update_hook_visual()
		_update_camera(delta, Vector3(velocity.x, 0.0, velocity.z))
		_update_hud()
		return
	var was_on_floor := is_on_floor()
	coyote_time = Config.COYOTE if was_on_floor else maxf(coyote_time - delta, 0.0)
	var direction := _movement_direction()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	var wants_slide := Input.is_action_pressed("slide")

	if not sliding and wants_slide and was_on_floor and dash_time <= 0.0 and speed >= Config.SLIDE_MIN:
		sliding = true
		horizontal = horizontal.normalized() * maxf(speed, minf(Config.SLIDE_BOOST, speed * 1.3))
	if sliding and (not wants_slide or not was_on_floor or speed < Config.SLIDE_END):
		sliding = false

	if dash_time > 0.0:
		dash_time -= delta
		horizontal = dash_direction * (Config.DASH_SPEED if dash_time > 0.0 else Config.DASH_END)
	elif sliding:
		horizontal = horizontal.move_toward(Vector3.ZERO, Config.SLIDE_FRIC * delta)
		horizontal += direction * Config.SLIDE_STEER * delta
		# La componente de la gravedad paralela a la pendiente da impulso cuesta abajo.
		if was_on_floor:
			var downhill := Vector3.DOWN.slide(get_floor_normal()).normalized()
			horizontal += downhill * Config.SLIDE_SLOPE * delta
	elif was_on_floor:
		var target_speed := Config.SPRINT if Input.is_action_pressed("sprint") else Config.WALK
		var target := direction * target_speed
		var rate := Config.GROUND_ACC if direction.length_squared() > 0.0 else Config.GROUND_FRIC
		if horizontal.length() > Config.SPRINT + 0.5:
			rate = Config.OVER_DECEL
		horizontal = horizontal.move_toward(target, rate * delta)
	elif direction.length_squared() > 0.0:
		var projected := horizontal.dot(direction)
		var gain := clampf(Config.AIR_CAP - projected, 0.0, Config.AIR_ACC * delta)
		horizontal += direction * gain

	if was_on_floor:
		extra_jumps = 1
	if jump_buffer > 0.0:
		if coyote_time > 0.0:
			velocity.y = Config.JUMP
			jump_buffer = 0.0
			coyote_time = 0.0
			sliding = false
		elif not was_on_floor:
			var wall_normal := _high_wall_normal()
			if wall_jump_cooldown <= 0.0 and wall_normal != Vector3.ZERO:
				_wall_jump(wall_normal, horizontal.length())
				# Conserva el impulso recién calculado; no lo sustituyas por el previo.
				horizontal = Vector3(velocity.x, 0.0, velocity.z)
				jump_buffer = 0.0
			elif extra_jumps > 0:
				_double_jump(direction, horizontal)
				# El doble salto también puede cambiar la velocidad horizontal.
				horizontal = Vector3(velocity.x, 0.0, velocity.z)
				jump_buffer = 0.0
	if not was_on_floor:
		velocity.y -= Config.GRAV * delta
	elif velocity.y <= 0.0:
		velocity.y = minf(velocity.y, 0.0)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_move_with_step(delta, was_on_floor)
	_update_hook_visual()
	_update_camera(delta, Vector3(velocity.x, 0.0, velocity.z))
	_update_hud()

func _movement_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return (global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

func _move_with_step(delta: float, was_on_floor: bool) -> void:
	move_and_slide()
	if not was_on_floor or not is_on_wall() or Vector2(velocity.x, velocity.z).length_squared() == 0.0:
		return
	var forward := Vector3(velocity.x, 0.0, velocity.z) * delta
	forward = forward.limit_length(Config.SNAP)
	var raised := global_transform.translated(Vector3.UP * Config.STEP)
	# Sube solo si el desplazamiento sobre el escalón está libre.
	if not test_move(global_transform, Vector3.UP * Config.STEP) and not test_move(raised, forward):
		global_transform = raised.translated(forward)
		apply_floor_snap()

func _check_double_tap(action: StringName) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if last_tap.has(action) and now - last_tap[action] <= Config.DOUBLE_TAP:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		_start_dash((global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized())
	last_tap[action] = now

func _start_dash(direction: Vector3) -> void:
	if dash_cooldown > 0.0 or dash_time > 0.0:
		return
	if direction.length_squared() == 0.0:
		direction = -global_transform.basis.z
	dash_direction = direction.normalized()
	dash_side = dash_direction.dot(global_transform.basis.x)
	dash_time = Config.DASH_TIME
	dash_cooldown = Config.DASH_CD
	sliding = false

func _double_jump(direction: Vector3, horizontal: Vector3) -> void:
	velocity.y = Config.JUMP * 0.85
	extra_jumps -= 1
	fov_kick += 5.0
	# Conserva parte del impulso y orienta el resto al movimiento solicitado.
	if direction.length_squared() > 0.0:
		var speed := maxf(horizontal.length(), 8.0)
		var pushed := horizontal * 0.4 + direction * speed * 0.6
		velocity.x = pushed.x
		velocity.z = pushed.z

func _wall_jump(normal: Vector3, speed: float) -> void:
	var away := (normal + -global_transform.basis.z * 0.5).normalized()
	var jump_speed := maxf(speed, 12.0)
	velocity.x = away.x * jump_speed
	velocity.z = away.z * jump_speed
	velocity.y = Config.JUMP * 0.95
	wall_jump_cooldown = Config.WALL_JUMP_CD
	extra_jumps = 1
	fov_kick += 8.0

func _high_wall_normal() -> Vector3:
	# El rayo por encima de la altura mínima descarta obstáculos bajos.
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * (Config.WALL_MIN_HEIGHT + 0.01)
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * Config.WALL_CHECK_DISTANCE, 0xffffffff, [get_rid()])
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and absf(hit.normal.y) < 0.2:
			return hit.normal.normalized()
	return Vector3.ZERO

func _toggle_hook() -> void:
	if hooked:
		_release_hook()
		return
	if hook_cooldown > 0.0:
		return
	var viewport_center := camera.get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(viewport_center)
	var ray_end := ray_origin + camera.project_ray_normal(viewport_center) * Config.HOOK_RANGE
	var exclude := [get_rid()]
	var space := get_world_3d().direct_space_state
	for _attempt in range(4):
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 0xffffffff, exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: CollisionObject3D = hit["collider"] as CollisionObject3D
		# El suelo no es un punto de agarre; se excluye y se sigue buscando.
		if collider != null and collider.name == "Suelo":
			exclude.append(collider.get_rid())
			continue
		_start_hook(hit["position"], hit["normal"])
		return
	hook_cooldown = Config.HOOK_MISS_CD
	hook_message = "Sin punto de agarre"
	hook_message_time = 1.0

func _start_hook(point: Vector3, normal: Vector3) -> void:
	hook_anchor = point
	hook_target = point + normal * 1.1
	hooked = true
	hook_time = 0.0
	hook_best_distance = INF
	hook_stuck_time = 0.0
	dash_time = 0.0
	sliding = false
	velocity.y = maxf(velocity.y, 3.0)
	fov_kick += 6.0
	hook_piece.global_position = hook_anchor
	hook_piece.visible = true

func _pull_hook(delta: float) -> void:
	var body_center := global_position + Vector3.UP * 0.9
	var to_target := hook_target - body_center
	var distance := to_target.length()
	hook_time += delta
	if distance > hook_best_distance - 0.04:
		hook_stuck_time += delta
	else:
		hook_best_distance = distance
		hook_stuck_time = 0.0
	if distance < Config.HOOK_STOP:
		_release_hook(false, true)
	elif hook_time > Config.HOOK_MAX_TIME or hook_stuck_time > 0.4:
		_release_hook()
	else:
		var desired_velocity := to_target.normalized() * Config.HOOK_SPEED
		velocity = velocity.lerp(desired_velocity, minf(1.0, delta * Config.HOOK_ACC))

func _release_hook(hook_jump := false, reached_stop := false) -> void:
	if not hooked:
		return
	if hook_jump:
		velocity.y = maxf(velocity.y, 0.0) + 6.0
		extra_jumps = 1
	elif reached_stop:
		velocity.y *= 0.55
		velocity.x *= 0.6
		velocity.z *= 0.6
	hooked = false
	hook_cooldown = Config.HOOK_CD
	hook_piece.visible = false
	rope.visible = false

func _create_hook_visual() -> void:
	rope_mesh = ImmediateMesh.new()
	rope = MeshInstance3D.new()
	rope.name = "CuerdaGancho"
	rope.mesh = rope_mesh
	rope.top_level = true
	rope.visible = false
	var rope_material := StandardMaterial3D.new()
	rope_material.albedo_color = Color.WHITE
	rope_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rope.material_override = rope_material
	add_child(rope)
	hook_piece = MeshInstance3D.new()
	hook_piece.name = "PiezaGancho"
	hook_piece.mesh = SphereMesh.new()
	hook_piece.top_level = true
	hook_piece.scale = Vector3.ONE * 0.16
	hook_piece.visible = false
	var piece_material := StandardMaterial3D.new()
	piece_material.albedo_color = Color.WHITE
	piece_material.emission_enabled = true
	piece_material.emission = Color.WHITE
	hook_piece.material_override = piece_material
	add_child(hook_piece)

func _update_hook_visual() -> void:
	if not hooked:
		rope.visible = false
		return
	var hand := camera.global_position + camera.global_transform.basis.x * 0.28 - camera.global_transform.basis.y * 0.22 - camera.global_transform.basis.z * 0.6
	rope_mesh.clear_surfaces()
	rope_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	rope_mesh.surface_add_vertex(hand)
	rope_mesh.surface_add_vertex(hook_anchor)
	rope_mesh.surface_end()
	rope.visible = true

func _update_camera(delta: float, horizontal: Vector3) -> void:
	var keyboard_look := Config.KEY_LOOK_SPEED * delta
	rotate_y((Input.get_action_strength("look_left") - Input.get_action_strength("look_right")) * keyboard_look)
	camera.rotation.x = clamp(camera.rotation.x + (Input.get_action_strength("look_up") - Input.get_action_strength("look_down")) * keyboard_look, -1.5, 1.5)
	var speed := horizontal.length()
	var target_fov := Config.FOV + clampf((speed - Config.WALK) / 12.0, 0.0, 1.0) * (Config.FOV_MAX - Config.FOV)
	if dash_time > 0.0:
		target_fov += Config.FOV_DASH
	fov_kick = move_toward(fov_kick, 0.0, delta * Config.FOV_KICK_RECOVER)
	target_fov += fov_kick
	camera.fov = lerpf(camera.fov, target_fov, minf(delta * 8.0, 1.0))
	var lateral := horizontal.dot(global_transform.basis.x) / Config.SPRINT
	var target_roll := -clampf(lateral, -1.3, 1.3) * Config.TILT * 3.0
	if dash_time > 0.0:
		target_roll -= dash_side * Config.DASH_TILT
	camera_roll = lerpf(camera_roll, target_roll, minf(delta * 10.0, 1.0))
	camera.rotation.z = camera_roll
	var target_eye := Config.EYE_SLIDE if sliding else Config.EYE
	var bob := 0.0
	if is_on_floor() and not sliding and speed > 1.0:
		bob_time += speed * delta * 0.9
		bob = sin(bob_time * 2.0) * Config.BOB * minf(speed / Config.SPRINT, 1.0)
	camera.position.y = lerpf(camera.position.y, target_eye + bob, minf(delta * 10.0, 1.0))

func _update_hud() -> void:
	var state := "DODGE" if dash_time > 0.0 else "SLIDE" if sliding else "AIR" if not is_on_floor() else "RUN"
	var hook_state := "ENGANCHADO" if hooked else "LISTO" if hook_cooldown <= 0.0 else "%.1f s" % hook_cooldown
	if hook_message_time > 0.0:
		hook_state = hook_message
	status.text = "%d km/h\n%s\nSALTOS EXTRA: %d\nGANCHO: %s" % [round(Vector2(velocity.x, velocity.z).length() * 3.6), state, extra_jumps, hook_state]
	zone_label.text = _zone_name(global_position.x, global_position.z)

func _zone_name(x: float, z: float) -> String:
	if absf(x) < 16.0 and absf(z) < 16.0:
		return "EL COLISEO"
	if z < -26.0:
		return "PLAZA DE INICIO"
	if z > 26.0:
		return "LAS RUINAS"
	if x < -22.0:
		return "LA FUNDICIÓN"
	if x > 22.0:
		return "DISTRITO DE TORRES"
	return "PASILLO CENTRAL"

func _configure_input_map() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("sprint", KEY_SHIFT)
	_add_key("jump", KEY_SPACE)
	_add_key("slide", KEY_C)
	_add_key("slide", KEY_CTRL)
	_add_key("dash", KEY_Q)
	_add_key("hook", KEY_R)
	_add_key("look_up", KEY_I)
	_add_key("look_down", KEY_K)
	_add_key("look_left", KEY_J)
	_add_key("look_right", KEY_L)

func _add_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.keycode = keycode
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)
