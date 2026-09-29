extends Node
class_name AudioDirector



const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const MUSIC_PATH := "res://assets/audio/beacon_bay_90bpm.wav"
const TENSION_PATH := "res://assets/audio/beacon_bay_tension.wav"
const PRESSURE_PATH := "res://assets/audio/beacon_bay_pressure.wav"
const CUE_NAMES := ["dispatch", "rescue", "alarm", "click", "upgrade", "fail", "shift", "combo", "surge", "urgent", "arrival", "work"]
const SFX_POOL_SIZE := 10

var music_enabled := true
var sfx_enabled := true
var intensity := 0.0
var music_volume_db := -8.0
var sfx_volume_db := -6.0

var _music: AudioStreamPlayer
var _tension: AudioStreamPlayer
var _pressure: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _cues: Dictionary = {}
var _music_wanted := false
var _music_gain := 0.0
var _tension_gain := 0.0
var _pressure_gain := 0.0
var _smoothed_intensity := 0.0
var _last_cue_ms: Dictionary = {}
var _last_attention_ms := -10000
var _pool_cursor := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_music = _make_player("CoastlineScore", MUSIC_BUS)
	_tension = _make_player("ResponseRhythm", MUSIC_BUS)
	_pressure = _make_player("PressurePulse", MUSIC_BUS)
	_music.stream = _load_wav(MUSIC_PATH, true)
	_tension.stream = _load_wav(TENSION_PATH, true)
	_pressure.stream = _load_wav(PRESSURE_PATH, true)
	_music.volume_db = -80.0
	_tension.volume_db = -80.0
	_pressure.volume_db = -80.0
	for cue_name in CUE_NAMES:
		_cues[cue_name] = _load_wav("res://assets/audio/%s.wav" % cue_name, false)
	for i in SFX_POOL_SIZE:
		_pool.append(_make_player("Cue%02d" % i, SFX_BUS))
	_apply_bus_volumes()
	if _music_wanted:
		start_music()


func _process(delta: float) -> void:
	if not is_instance_valid(_music):
		return
	var target := 1.0 if music_enabled and _music_wanted else 0.0
	var intensity_speed := 0.60 if intensity > _smoothed_intensity else 0.24
	_smoothed_intensity = move_toward(_smoothed_intensity, intensity, delta * intensity_speed)
	var pressure_mix := smoothstep(0.48, 0.97, _smoothed_intensity)
	
	_music_gain = move_toward(_music_gain, target * (1.0 - 0.16 * pressure_mix), delta * 1.7)
	var tension_target := smoothstep(0.12, 0.80, _smoothed_intensity) * 0.85 * target
	_tension_gain = move_toward(_tension_gain, tension_target, delta * (2.4 if target == 0.0 else 0.42))
	_pressure_gain = move_toward(_pressure_gain, pressure_mix * 0.95 * target, delta * (2.8 if target == 0.0 else 0.62))
	_music.volume_db = linear_to_db(maxf(_music_gain, 0.0001))
	_tension.volume_db = linear_to_db(maxf(_tension_gain, 0.0001))
	_pressure.volume_db = linear_to_db(maxf(_pressure_gain, 0.0001))
	if not _music_wanted and maxf(_music_gain, maxf(_tension_gain, _pressure_gain)) <= 0.0001:
		_music.stop()
		_tension.stop()
		_pressure.stop()


func play_cue(cue_name: String) -> void:
	if not sfx_enabled or not _cues.has(cue_name) or _pool.is_empty():
		return
	var now := Time.get_ticks_msec()
	
	var minimum_interval := 65 if cue_name == "click" else 110
	if cue_name == "alarm":
		minimum_interval = 1400
	elif cue_name == "surge":
		minimum_interval = 6500
	elif cue_name == "urgent":
		minimum_interval = 3500
	elif cue_name == "dispatch":
		minimum_interval = 260
	elif cue_name == "arrival":
		minimum_interval = 550
	elif cue_name == "work":
		minimum_interval = 1600
	if now - int(_last_cue_ms.get(cue_name, -10000)) < minimum_interval:
		return
	if cue_name in ["alarm", "urgent", "surge"]:
		if now - _last_attention_ms < 1100:
			return
		_last_attention_ms = now
	_last_cue_ms[cue_name] = now
	var player: AudioStreamPlayer = _pool[_pool_cursor]
	for offset in _pool.size():
		var candidate: AudioStreamPlayer = _pool[(_pool_cursor + offset) % _pool.size()]
		if not candidate.playing:
			player = candidate
			break
	_pool_cursor = (_pool_cursor + 1) % _pool.size()
	player.stop()
	player.stream = _cues[cue_name]
	player.pitch_scale = randf_range(0.985, 1.015) if cue_name in ["click", "rescue", "combo"] else 1.0
	player.volume_db = -3.0 if cue_name in ["alarm", "arrival"] else 0.0
	if cue_name == "work":
		player.volume_db = -5.0
	player.play()


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if enabled and _music_wanted and is_instance_valid(_music) and not _music.playing:
		start_music()


func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	if not enabled:
		for player in _pool:
			player.stop()


func set_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)


func set_music_volume(value_db: float) -> void:
	music_volume_db = clampf(value_db, -60.0, 0.0)
	_apply_bus_volumes()


func set_sfx_volume(value_db: float) -> void:
	sfx_volume_db = clampf(value_db, -60.0, 0.0)
	_apply_bus_volumes()


func start_music() -> void:
	_music_wanted = true
	if not is_instance_valid(_music) or not music_enabled or _music.playing:
		return
	_music.play()
	_tension.play()
	_pressure.play()


func stop_music() -> void:
	_music_wanted = false


func _make_player(player_name: String, bus_name: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = bus_name
	add_child(player)
	return player


func _load_wav(path: String, should_loop: bool) -> AudioStreamWAV:
	var source := load(path) as AudioStreamWAV
	if source == null:
		push_warning("Beacon Bay audio is missing: " + path)
		return null
	var stream := source.duplicate() as AudioStreamWAV
	if should_loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")


func _apply_bus_volumes() -> void:
	var music_index := AudioServer.get_bus_index(MUSIC_BUS)
	var sfx_index := AudioServer.get_bus_index(SFX_BUS)
	if music_index >= 0:
		AudioServer.set_bus_volume_db(music_index, music_volume_db)
	if sfx_index >= 0:
		AudioServer.set_bus_volume_db(sfx_index, sfx_volume_db)
