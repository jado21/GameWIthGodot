extends CharacterBody3D
## Fase 1: persecución directa, zarpazo y embestida.
signal died(position: Vector3)
signal message(text: String)
const DATA = preload("res://scripts/monster_data.gd")
var player: CharacterBody3D
var hp := DATA.HP
var state := "SLEEP"
var timer := DATA.WAKE
var lunge_cd := 3.0
var lunge_direction := Vector3.FORWARD
var lunge_hit := false
var flash := 0.0
var time := 0.0
var body_material: StandardMaterial3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var body: Node3D
var head: Node3D
var AudioManager: Node
var phase := 1
var rock_cd := 4.0
var slam_cd := 3.0
var rocks: Array[Dictionary] = []
var waves: Array[Dictionary] = []
var kick_cd := 0.0
var eye_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	AudioManager = get_node("/root/AudioManager")
	add_to_group("monster")
	_build_model()

func set_player(value: CharacterBody3D) -> void:
	player = value

func take_damage(amount: float) -> void:
	if hp <= 0.0: return
	hp = maxf(0.0, hp - amount)
	flash = 0.15
	if phase == 1 and hp <= DATA.HP * 0.5:
		phase = 2; state = "ROAR"; timer = 1.2; body_material.albedo_color = Color("d8452a"); _set_eyes(Color("ff2200")); emit_signal("message", "¡EL MONSTRUO SE ENFURECE!")
	elif phase == 2 and hp <= DATA.HP * 0.25:
		phase = 3; state = "ROAR"; timer = 1.0; body_material.albedo_color = Color("9a1818"); emit_signal("message", "¡FURIA FINAL!")
	if state == "SLEEP":
		timer = 0.0
	if hp <= 0.0:
		emit_signal("died", global_position + Vector3.UP * 3.0)
		queue_free()

func _physics_process(delta: float) -> void:
	if player == null: return
	time += delta; flash = maxf(0.0, flash - delta); lunge_cd = maxf(0.0, lunge_cd - delta); rock_cd=maxf(0.0,rock_cd-delta); slam_cd=maxf(0.0,slam_cd-delta); kick_cd=maxf(0.0,kick_cd-delta)
	AudioManager.set_loop("ambient_drone", true, -24.0 + phase * 5.0)
	var to_player := player.global_position - global_position
	var flat := Vector3(to_player.x, 0, to_player.z)
	var distance := flat.length()
	if bool(player.get("sliding")) and kick_cd <= 0.0 and distance < 3.4 and absf(to_player.y) < 3.0:
		take_damage(28.0)
		kick_cd = 0.9
		emit_signal("message", "¡PATADA DESLIZANTE!")
	if distance > 0.01: look_at(player.global_position, Vector3.UP)
	if state == "SLEEP":
		timer -= delta
		if timer <= 0.0:
			state = "CHASE"; emit_signal("message", "¡El monstruo sabe dónde estás!"); AudioManager.play("monster_roar",0.0,global_position)
	elif state == "ROAR":
		velocity.x=0; velocity.z=0; timer-=delta
		if timer<=0: state="CHASE"
	elif state == "CHASE":
		if distance < DATA.SWING_RANGE - 0.6 and absf(to_player.y) < 2.5:
			state = "SWING_W"; timer = DATA.SWING_WIND; AudioManager.play("monster_warn",0.0,global_position)
		elif phase >= 3 and slam_cd<=0 and distance<22.0:
			state="SLAM_W"; timer=.7; AudioManager.play("monster_warn",0.0,global_position)
		elif phase >= 2 and rock_cd<=0 and distance>7.0:
			state="THROW_W"; timer=.45 if phase==3 else .65; AudioManager.play("monster_warn",0.0,global_position)
		elif lunge_cd <= 0.0 and distance > 8.0 and distance < 24.0 and absf(to_player.y) < 3.0:
			state = "LUNGE_W"; timer = DATA.LUNGE_WIND; AudioManager.play("monster_warn",0.0,global_position)
		elif distance > 2.8 and to_player.y <= DATA.CLIMB:
			var chase_speed := DATA.SPEED2*1.12 if phase==3 else DATA.SPEED2 if phase==2 else DATA.SPEED
			velocity.x = flat.normalized().x * chase_speed; velocity.z = flat.normalized().z * chase_speed
			if is_on_wall(): velocity = velocity.rotated(Vector3.UP, 0.7)
		else: velocity.x = 0; velocity.z = 0
	elif state == "SWING_W":
		velocity.x = 0; velocity.z = 0; timer -= delta
		if timer <= 0.0:
			if distance < DATA.SWING_RANGE and absf(to_player.y) < 2.5: player.hurt(DATA.SWING_DMG)
			state = "REC"; timer = 0.6
	elif state == "LUNGE_W":
		velocity.x = 0; velocity.z = 0; timer -= delta
		if timer <= 0.0:
			lunge_direction = flat.normalized(); lunge_hit = false; state = "LUNGE"; timer = DATA.LUNGE_TIME; AudioManager.play("monster_lunge",0.0,global_position)
	elif state == "THROW_W":
		velocity.x=0; velocity.z=0; timer-=delta
		if timer<=0: _throw_rocks(); AudioManager.play("monster_throw",0.0,global_position); state="REC"; timer=.7; rock_cd=DATA.THROW_CD
	elif state == "SLAM_W":
		velocity.x=0; velocity.z=0; timer-=delta
		if timer<=0: _slam(); AudioManager.play("shockwave",0.0,global_position); state="REC"; timer=.7; slam_cd=4.5
	elif state == "LUNGE":
		velocity.x = lunge_direction.x * DATA.LUNGE_SPEED; velocity.z = lunge_direction.z * DATA.LUNGE_SPEED; timer -= delta
		if not lunge_hit and distance < 2.8: player.hurt(DATA.LUNGE_DMG); lunge_hit = true
		if timer <= 0.0: state = "REC"; timer = .7 if phase>=2 else DATA.REC; lunge_cd = 3.0 if phase>=2 else DATA.LUNGE_CD
	elif state == "REC":
		velocity.x = 0; velocity.z = 0; timer -= delta
		if timer <= 0.0: state = "CHASE"
	if not is_on_floor(): velocity.y -= Config.GRAV * delta
	else: velocity.y = minf(velocity.y, 0.0)
	move_and_slide(); _update_projectiles(delta); _animate(delta)

func _build_model() -> void:
	body_material = _material(Color("7a3fbf")); body = _box(Vector3(3,3,2.2), Vector3(0,2.6,0), body_material)
	head = _box(Vector3(1.8,1.6,1.6), Vector3(0,4.8,0.8), body_material)
	for x in [-0.9, 0.9]: legs.append(_box(Vector3(1,1.8,1), Vector3(x,0.9,0), body_material))
	for x in [-2.0, 2.0]: arms.append(_box(Vector3(.8,.8,2.4), Vector3(x,3,1), body_material))
	for x in [-0.45, 0.45]:
		var eye_mat:=_material(Color("ffe14a"), true); eye_materials.append(eye_mat); var eye := _box(Vector3(.28,.28,.12), Vector3(x,4.9,1.62), eye_mat); eye.name = "Ojo"
		var horn := MeshInstance3D.new(); var cone := CylinderMesh.new(); cone.top_radius=0.0; cone.bottom_radius=.3; cone.height=.9; horn.mesh=cone; horn.position=Vector3(x,5.9,.8); horn.material_override=_material(Color("e5d7ff")); add_child(horn)

func _box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size=size; node.mesh=mesh; node.position=pos; node.material_override=material; node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON; add_child(node); return node
func _material(color: Color, glow := false) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new(); m.albedo_color=color; m.emission_enabled=glow; m.emission=color if glow else Color.BLACK; return m
func _animate(delta: float) -> void:
	var moving := state == "CHASE" or state == "LUNGE"; var swing := sin(time*12.0) if moving else 0.0
	for i in range(legs.size()): legs[i].position.z = (1 if i==0 else -1)*swing*.55; legs[i].rotation.x=(1 if i==0 else -1)*swing*.5
	var target_arm := -1.25 if state in ["SWING_W","LUNGE_W","THROW_W","SLAM_W","ROAR"] else (sin(time*12.0+3.0)*.35 if moving else 0.0)
	for arm in arms: arm.rotation.x = lerpf(arm.rotation.x,target_arm,minf(1.0,delta*14))
	body.position.y=2.6+(absf(swing)*.3 if moving else 0.0); head.position.y=4.8+sin(time*2.0)*.05
	if state in ["SWING_W","LUNGE_W","THROW_W","SLAM_W"]: body_material.emission=Color(0.6+0.4*sin(time*35),0,0)
	elif flash>0: body_material.emission=Color.WHITE
	else: body_material.emission=Color.BLACK
	if state=="ROAR": scale=Vector3.ONE*(1.0+.1*sin(time*40.0))
	else: scale=Vector3.ONE

func _set_eyes(color: Color) -> void:
	for material in eye_materials: material.albedo_color=color; material.emission=color

func _throw_rocks() -> void:
	var angles := [-.4,-.2,0.0,.2,.4] if phase==3 else [-.2,0.0,.2]
	for angle in angles:
		var target:=player.global_position+Vector3.UP+player.velocity*(global_position.distance_to(player.global_position)/DATA.ROCK_SPEED)*.6
		var direction:Vector3=(target-(global_position+Vector3.UP*5.2)).normalized().rotated(Vector3.UP,angle)
		var node:=MeshInstance3D.new(); var mesh:=SphereMesh.new(); mesh.radius=.7; mesh.height=1.4; node.mesh=mesh; node.position=global_position+Vector3.UP*5.2; var mat:=StandardMaterial3D.new(); mat.albedo_color=Color("ff7a1a"); mat.emission_enabled=true; mat.emission=Color("ff7a1a"); node.material_override=mat; get_parent().add_child(node); rocks.append({"node":node,"velocity":direction*DATA.ROCK_SPEED,"life":4.0})

func _slam() -> void:
	var ring:=MeshInstance3D.new(); var mesh:=TorusMesh.new(); mesh.inner_radius=.9; mesh.outer_radius=1.05; ring.mesh=mesh; ring.position=global_position+Vector3.UP*.05; ring.material_override=_material(Color("ff8a1a"),true); get_parent().add_child(ring); waves.append({"node":ring,"radius":1.0,"hit":false})

func _update_projectiles(delta:float)->void:
	for i in range(rocks.size()-1,-1,-1):
		var rock: Dictionary = rocks[i]
		var rock_node: MeshInstance3D = rock["node"] as MeshInstance3D
		var rock_velocity: Vector3 = rock["velocity"]
		rock["life"] -= delta; rock_node.position += rock_velocity * delta; rock_node.rotation += Vector3(delta*6,delta*7,0)
		var rock_delta: Vector3 = rock_node.position - player.global_position
		if Vector2(rock_delta.x,rock_delta.z).length()<1.2 and absf(rock_delta.y-1.0)<1.5: player.hurt(DATA.ROCK_DMG); rock["life"]=0.0
		if rock["life"]<=0: _vfx(rock_node.position,Color("ff7a1a"),14,7.0); rock_node.queue_free(); rocks.remove_at(i)
	for i in range(waves.size()-1,-1,-1):
		var wave:=waves[i]; wave["radius"]+=24.0*delta; wave["node"].scale=Vector3.ONE*wave["radius"]
		var distance_to_wave: float = Vector2(player.global_position.x-global_position.x,player.global_position.z-global_position.z).length()
		if not wave["hit"] and absf(distance_to_wave-wave["radius"])<1.4 and player.global_position.y<.9: player.hurt(30.0); wave["hit"]=true
		if wave["radius"]>50: wave["node"].queue_free(); waves.remove_at(i)

func _vfx(position: Vector3, color: Color, amount: int, speed: float) -> void:
	var manager := get_tree().get_first_node_in_group("vfx")
	if manager != null: manager.burst(position, color, amount, speed)
