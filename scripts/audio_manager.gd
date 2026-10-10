class_name AudioManagerService
extends Node
## Reproductores reutilizables para efectos 2D/3D y bucles ambientales.
var warned := {}
var pool_2d: Array[AudioStreamPlayer] = []
var pool_3d: Array[AudioStreamPlayer3D] = []
var muted := false
var loops := {}

func _ready() -> void:
	for index in range(12):
		var player := AudioStreamPlayer.new(); add_child(player); pool_2d.append(player)
		var player_3d := AudioStreamPlayer3D.new(); add_child(player_3d); pool_3d.append(player_3d)
	for name in ["slide_loop", "wind_loop", "ambient_drone"]:
		var loop := AudioStreamPlayer.new(); loop.bus = "Ambient"; add_child(loop); loops[name] = loop

func play(name: String, volume_db := 0.0, pos = null) -> void:
	var stream := _stream(name)
	if stream == null: return
	if pos == null:
		var player := _free_2d(); player.bus="SFX"; player.stream=stream; player.volume_db=volume_db; player.pitch_scale=_pitch(name); player.play()
	else:
		var player := _free_3d(); player.stream=stream; player.global_position=pos; player.volume_db=volume_db; player.pitch_scale=_pitch(name); player.play()

func set_loop(name: String, enabled: bool, volume_db := 0.0) -> void:
	if not loops.has(name): return
	var player: AudioStreamPlayer = loops[name]
	if enabled and player.stream == null: player.stream = _stream(name)
	if player.stream == null: return
	player.volume_db = volume_db
	if enabled and not player.playing: player.play()
	if not enabled: player.stop()

func set_slowmo(enabled: bool) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0: return
	AudioServer.set_bus_effect_enabled(bus, 0, enabled)

func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)

func _stream(name: String) -> AudioStream:
	for extension in ["wav", "ogg"]:
		var path := "res://audio/%s.%s" % [name, extension]
		if ResourceLoader.exists(path): return load(path)
	if not warned.has(name): warned[name]=true; push_warning("Audio faltante: "+name)
	return null

func _pitch(name: String) -> float:
	return randf_range(.95,1.05) if name.begins_with("step") or name.begins_with("shot") or name.contains("hit") else 1.0
func _free_2d() -> AudioStreamPlayer:
	for player in pool_2d: if not player.playing: return player
	return pool_2d[0]
func _free_3d() -> AudioStreamPlayer3D:
	for player in pool_3d: if not player.playing: return player
	return pool_3d[0]
