extends Node
const MONSTER_SCENE = preload("res://monster.tscn")
var player: CharacterBody3D
var monster: CharacterBody3D
var player_bar: ProgressBar
var monster_bar: ProgressBar
var end_label: Label
var overhead_bar: ProgressBar
var damage_border: Panel
var paused_label: Label
var finished := false
var finish_time := 0.0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_start")
func _start() -> void:
	player = get_parent().get_node("Player")
	for node in get_tree().get_nodes_in_group("spawns"):
		if node is Marker3D and node.name.to_lower().begins_with("monstruo"):
			monster = MONSTER_SCENE.instantiate(); get_parent().add_child(monster); monster.global_position=node.global_position; monster.set_player(player); monster.died.connect(_victory); monster.message.connect(_message); break
	player.died.connect(_death); _build_ui()
func _process(delta: float) -> void:
	if player_bar: player_bar.value=player.health
	if damage_border: damage_border.modulate.a = player.damage_flash
	if monster_bar and is_instance_valid(monster): monster_bar.value=monster.hp
	if overhead_bar and is_instance_valid(monster):
		var camera := player.get_node("Camera3D") as Camera3D
		var point := monster.global_position + Vector3.UP * 6.0
		overhead_bar.visible = not camera.is_position_behind(point)
		if overhead_bar.visible:
			overhead_bar.position = camera.unproject_position(point) - Vector2(45, 12)
			overhead_bar.value = monster.hp
	if finished: finish_time+=delta
func _unhandled_input(event: InputEvent) -> void:
	if (event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_P)) and not finished:
		get_tree().paused = not get_tree().paused
		paused_label.visible = get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
		return
	if finished and finish_time>1.2 and (event is InputEventMouseButton or event.is_action_pressed("move_forward")): get_tree().reload_current_scene()
func _build_ui() -> void:
	var layer:=CanvasLayer.new(); add_child(layer)
	player_bar=ProgressBar.new(); player_bar.position=Vector2(16,16); player_bar.size=Vector2(200,14); player_bar.value=100; player_bar.show_percentage=false; layer.add_child(player_bar)
	monster_bar=ProgressBar.new(); monster_bar.position=Vector2(360,14); monster_bar.size=Vector2(500,16); monster_bar.max_value=520; monster_bar.value=520; monster_bar.show_percentage=false; layer.add_child(monster_bar)
	overhead_bar=ProgressBar.new(); overhead_bar.size=Vector2(90,8); overhead_bar.max_value=520; overhead_bar.value=520; overhead_bar.show_percentage=false; layer.add_child(overhead_bar)
	damage_border=Panel.new(); damage_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); var border:=StyleBoxFlat.new(); border.border_color=Color(1,0,0,.8); border.set_border_width_all(35); damage_border.add_theme_stylebox_override("panel",border); damage_border.mouse_filter=Control.MOUSE_FILTER_IGNORE; damage_border.modulate.a=0; layer.add_child(damage_border)
	end_label=Label.new(); end_label.set_anchors_preset(Control.PRESET_CENTER); end_label.position=Vector2(-180,-40); end_label.size=Vector2(360,80); end_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; end_label.add_theme_font_size_override("font_size",36); end_label.visible=false; layer.add_child(end_label)
	paused_label=Label.new(); paused_label.set_anchors_preset(Control.PRESET_CENTER); paused_label.position=Vector2(-80,-20); paused_label.text="PAUSA"; paused_label.add_theme_font_size_override("font_size",32); paused_label.visible=false; layer.add_child(paused_label)
func _message(text:String)->void: player.get_node("WeaponSystem").call("_say",text)
func _death()->void: _finish("Has muerto")
func _victory(_position:Vector3)->void: _finish("¡VICTORIA!")
func _finish(text:String)->void:
	if finished:return
	finished=true; finish_time=0; player.set_physics_process(false); end_label.text=text+"\nHaz clic o pulsa W para reintentar"; end_label.visible=true; Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
