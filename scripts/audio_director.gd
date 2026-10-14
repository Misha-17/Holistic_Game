extends Node
class_name AudioDirector
signal sound_level_changed(key: String, value: int)

const SOUND_LABELS := {"game_sound": "Game sound (music and effects)"}
const LEVEL_KEYS := ["game_sound", "voice_player_1", "voice_player_2", "voice_player_3", "voice_player_4"]
var sound_levels: Dictionary = {}
# Separate from campaign saves: guest players also retain their local mix.
var sound_preferences_path := "user://beacon_bay_sound_settings.cfg"

func sound_level(key: String) -> int:
	return int(sound_levels.get(key, 50))

func load_sound_levels() -> void:
	sound_levels.clear()
	var config := ConfigFile.new()
	if config.load(sound_preferences_path) != OK: return
	# Ignore retired per-cue values: hidden old preferences must not unbalance the mix.
	for key: String in LEVEL_KEYS:
		var value: Variant = config.get_value("sounds", key, 50)
		if value is int or value is float:
			sound_levels[key] = clampi(int(value), 0, 100)

func set_sound_level(key: String, value: int) -> void:
	if key not in LEVEL_KEYS: return
	sound_levels[key] = clampi(value, 0, 100)
	for child in get_children():
		if key == "game_sound" and child is AudioStreamPlayer and child.has_meta("sound_key"):
			_apply_sound_level(child, str(child.get_meta("sound_key")), float(child.get_meta("base_db", 0.0)))
	var config := ConfigFile.new()
	for sound_key: String in LEVEL_KEYS:
		config.set_value("sounds", sound_key, sound_level(sound_key))
	if config.save(sound_preferences_path) != OK:
		push_error("Could not save local sound settings: " + sound_preferences_path)
	sound_level_changed.emit(key, sound_level(key))

func _apply_sound_level(player: AudioStreamPlayer, key: String, base_db: float) -> void:
	player.set_meta("sound_key", key)
	player.set_meta("base_db", base_db)
	player.volume_linear = db_to_linear(base_db) * float(sound_level("game_sound")) / 50.0



const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const MUSIC_PATH := "res://assets/audio/beacon_bay_soft_v080.wav"
const MUSIC_FADE_IN_SECONDS := 4.0
const MUSIC_FADE_OUT_SECONDS := 2.0
const BUSY_THRESHOLD := 0.45
const CALM_THRESHOLD := 0.30
const BUSY_HOLD_SECONDS := 2.0
const CALM_HOLD_SECONDS := 6.0
const CROSSFADE_SECONDS := 2.0
# Supplied MP3 measures -44.56 dBFS RMS / -24.44 dBFS peak, versus the
# calm WAV's -18.27 RMS. Match their measured full-track RMS levels.
# Both then pass through the same Music bus and game-sound slider.
const INTENSE_GAIN_DB := 26.28851423
const INCIDENT_CUE_DELAY := 0.15
const INCIDENT_CUE_GAP := 1.1
const CUE_NAMES := ["dispatch", "rescue", "alarm", "click", "upgrade", "fail", "shift", "combo", "surge", "urgent", "arrival", "work"]
# Drop-in sounds: put a file named <name>.ogg / .wav / .mp3 in this folder and it replaces the built-in one.
const CUSTOM_DIR := "res://assets/audio/custom/"
# Newer cues; until a custom file exists they borrow a built-in sound.
const EXTRA_CUES := {"new_call": "alarm", "tick": "click", "select": "click", "boost": "upgrade", "win": "shift", "lose": "fail"}
# Countdown tick: a short clip is played once a second; a long clip (a ticking-clock loop) loops while needed.
var _tick_player: AudioStreamPlayer
var _ticking := false
var _tick_wait := 0.0
const SFX_POOL_SIZE := 10

var music_enabled := true
var sfx_enabled := true
var intensity := 0.0
var music_volume_db := -20.0
var sfx_volume_db := -6.0

var _music: AudioStreamPlayer
var _intense_music: AudioStreamPlayer
var _busy := false
var _busy_wait := 0.0
var _calm_wait := 0.0
var _music_mix := 0.0
var _incident_player: AudioStreamPlayer
var _incident_queue: Array[Dictionary] = []
var _incident_seen: Dictionary = {}
var _incident_wait := 0.0
var _playing_incident := -1
var _playing_incident_cue := ""
var _pool: Array[AudioStreamPlayer] = []
var _cues: Dictionary = {}
var _music_wanted := false
var _music_gain := 0.0
var _last_cue_ms: Dictionary = {}
var _last_attention_ms := -10000
var _pool_cursor := 0


func _ready() -> void:
	load_sound_levels()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_music = _make_player("CoastlineScore", MUSIC_BUS)
	var soft: AudioStream = _load_custom("music_soft", true)
	_music.stream = soft if soft != null else _load_wav(MUSIC_PATH, true)
	_music.volume_db = -80.0
	_intense_music = _make_player("BusyScore", MUSIC_BUS)
	_intense_music.stream = _load_custom("music_intense", true)
	_intense_music.volume_db = -80.0
	if _intense_music.stream == null:
		push_error("Required audio missing: assets/audio/music_intense.mp3")
	for cue_name in CUE_NAMES:
		var custom: AudioStream = _load_custom(cue_name, false)
		_cues[cue_name] = custom if custom != null else _load_wav("res://assets/audio/%s.wav" % cue_name, false)
	for cue_name in EXTRA_CUES:
		var custom: AudioStream = _load_custom(cue_name, false)
		_cues[cue_name] = custom if custom != null else _cues.get(EXTRA_CUES[cue_name])
	for cue_name in ["critical_incident", "incident_failed"]:
		_cues[cue_name] = _load_custom(cue_name, false)
		if _cues[cue_name] == null:
			push_error("Required incident audio missing: " + cue_name)
	_incident_player = _make_player("IncidentWarning", SFX_BUS)
	for i in SFX_POOL_SIZE:
		_pool.append(_make_player("Cue%02d" % i, SFX_BUS))
	_tick_player = _make_player("CountdownTick", SFX_BUS)
	var tick: AudioStream = _cues.get("tick")
	if tick != null and tick.get_length() > 1.5:
		tick = tick.duplicate()
		if tick is AudioStreamOggVorbis or tick is AudioStreamMP3:
			tick.loop = true
		elif tick is AudioStreamWAV:
			tick.loop_mode = AudioStreamWAV.LOOP_FORWARD
			tick.loop_begin = 0
			tick.loop_end = int(tick.get_length() * tick.mix_rate)
	_tick_player.stream = tick
	_apply_sound_level(_tick_player, "tick", 0.0)
	_apply_bus_volumes()
	if _music_wanted:
		start_music()


# Called every frame by the game: true while any call is about to fail without its crews.
func set_ticking(active: bool) -> void:
	_ticking = active and sfx_enabled

func _update_tick(delta: float) -> void:
	if _tick_player == null or _tick_player.stream == null:
		return
	var looping: bool = _tick_player.stream.get_length() > 1.5
	if looping:
		if _ticking and not _tick_player.playing:
			_tick_player.play()
		elif not _ticking and _tick_player.playing:
			_tick_player.stop()
		return
	_tick_wait = maxf(0.0, _tick_wait - delta)
	if _ticking and _tick_wait <= 0.0:
		_tick_wait = 1.0
		_tick_player.play()

func _process(delta: float) -> void:
	_update_tick(delta)
	_update_incident_cues(delta)
	if not is_instance_valid(_music):
		return
	var target := 1.0 if music_enabled and _music_wanted else 0.0
	var fade_seconds := MUSIC_FADE_IN_SECONDS if target > _music_gain else MUSIC_FADE_OUT_SECONDS
	_music_gain = move_toward(_music_gain, target, delta / fade_seconds)
	_music_mix = move_toward(_music_mix, 1.0 if _busy else 0.0, delta / CROSSFADE_SECONDS)
	var mix := smoothstep(0.0, 1.0, _music_mix)
	var gain := smoothstep(0.0, 1.0, _music_gain)
	_apply_sound_level(_music, "music_soft", linear_to_db(maxf(gain * (1.0 - mix), 0.0001)))
	_apply_sound_level(_intense_music, "music_intense", linear_to_db(maxf(gain * mix, 0.0001)) + INTENSE_GAIN_DB)
	# Complementary gains keep the crossfade from summing two full-volume tracks.
	if target > 0.0:
		if mix < 1.0 and not _music.playing: _music.play()
		if mix > 0.0 and not _intense_music.playing: _intense_music.play()
	if mix >= 1.0: _music.stop()
	if mix <= 0.0: _intense_music.stop()
	if target == 0.0 and _music_gain <= 0.0001:
		_music.stop()
		_intense_music.stop()


# Qualification advances only when main.gd says simulation time is running.
func update_music_context(delta: float, shift_active: bool, gameplay_running: bool) -> void:
	if not shift_active:
		_busy = false
		_busy_wait = 0.0
		_calm_wait = 0.0
		return
	if not gameplay_running:
		return
	_busy_wait = _busy_wait + delta if intensity >= BUSY_THRESHOLD else 0.0
	_calm_wait = _calm_wait + delta if intensity <= CALM_THRESHOLD else 0.0
	if not _busy and _busy_wait >= BUSY_HOLD_SECONDS:
		_busy = true
		_calm_wait = 0.0
	elif _busy and _calm_wait >= CALM_HOLD_SECONDS:
		_busy = false
		_busy_wait = 0.0


# Reset only on a new shift or restored session, never on ordinary snapshots.
# Seed past events so a late join/resume cannot sound historical warnings.
func reset_session(incidents: Array = []) -> void:
	_busy = false
	_busy_wait = 0.0
	_calm_wait = 0.0
	_incident_seen.clear()
	_incident_queue.clear()
	_incident_wait = 0.0
	_playing_incident = -1
	_playing_incident_cue = ""
	if is_instance_valid(_incident_player): _incident_player.stop()
	for incident: Dictionary in incidents:
		var id := int(incident.id)
		if bool(incident.get("critical_sent", false)):
			_incident_seen["critical_incident:%d" % id] = true
		if str(incident.get("status", "")) == "failed":
			_incident_seen["incident_failed:%d" % id] = true


func queue_incident_cue(cue_name: String, incident_id: int) -> void:
	if incident_id < 0 or cue_name not in ["critical_incident", "incident_failed"]:
		return
	var key := "%s:%d" % [cue_name, incident_id]
	if _incident_seen.has(key): return
	_incident_seen[key] = true
	if cue_name == "critical_incident" and _incident_seen.has("incident_failed:%d" % incident_id):
		return
	if cue_name == "incident_failed":
		_incident_queue = _incident_queue.filter(func(item: Dictionary) -> bool:
			return int(item.id) != incident_id)
		if _playing_incident == incident_id and _playing_incident_cue == "critical_incident":
			_incident_player.stop()
			_incident_wait = INCIDENT_CUE_DELAY
	if not sfx_enabled: return
	var item := {"cue": cue_name, "id": incident_id}
	if _incident_queue.is_empty(): _incident_wait = maxf(_incident_wait, INCIDENT_CUE_DELAY)
	if cue_name == "incident_failed": _incident_queue.push_front(item)
	else: _incident_queue.append(item)


# Shift-end conversions have no per-call failure events. Coalesce them into
# one sound and mark every ID as handled; retain the separate win/lose cue.
func finish_incident_cues(failed_ids: Array[int]) -> void:
	_incident_queue = _incident_queue.filter(func(item: Dictionary) -> bool:
		return item.cue == "incident_failed")
	var first := -1
	for id: int in failed_ids:
		if not _incident_seen.has("incident_failed:%d" % id):
			if first < 0: first = id
			else: _incident_seen["incident_failed:%d" % id] = true
	if first >= 0: queue_incident_cue("incident_failed", first)


func _update_incident_cues(delta: float) -> void:
	_incident_wait = maxf(0.0, _incident_wait - delta)
	if not sfx_enabled or _incident_queue.is_empty() or _incident_wait > 0.0:
		return
	if _incident_player.playing or Time.get_ticks_msec() - _last_attention_ms < 1100:
		return
	var item: Dictionary = _incident_queue.pop_front()
	_incident_player.stream = _cues.get(item.cue)
	if _incident_player.stream == null: return
	_playing_incident = int(item.id)
	_playing_incident_cue = str(item.cue)
	_apply_sound_level(_incident_player, str(item.cue), -3.0)
	_incident_player.play()
	_last_attention_ms = Time.get_ticks_msec()
	_incident_wait = _incident_player.stream.get_length() + INCIDENT_CUE_GAP


func play_cue(cue_name: String) -> void:
	if not sfx_enabled or not _cues.has(cue_name) or _pool.is_empty():
		return
	var now := Time.get_ticks_msec()
	
	var minimum_interval := 65 if cue_name == "click" else 110
	if cue_name in ["alarm", "new_call"]:
		minimum_interval = 1400
	elif cue_name == "tick":
		minimum_interval = 800
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
	if cue_name in ["alarm", "new_call", "urgent", "surge"]:
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
	var base_db := -3.0 if cue_name in ["alarm", "arrival"] else 0.0
	if cue_name == "dispatch": base_db = -6.02059991 # Half amplitude.
	if cue_name == "work": base_db = -5.0
	_apply_sound_level(player, cue_name, base_db)
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
		_incident_queue.clear()
		if is_instance_valid(_incident_player): _incident_player.stop()
		_ticking = false
		if is_instance_valid(_tick_player): _tick_player.stop()


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
	if not is_instance_valid(_music) or not music_enabled:
		return
	if _music_mix < 1.0 and not _music.playing: _music.play()
	if _music_mix > 0.0 and not _intense_music.playing: _intense_music.play()


func stop_music() -> void:
	_music_wanted = false


func _make_player(player_name: String, bus_name: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = bus_name
	add_child(player)
	return player


func _load_custom(cue_name: String, should_loop: bool) -> AudioStream:
	# Looks in the custom folder first, then next to the built-in sounds (assets/audio/),
	# so a new .ogg / .mp3 with the cue's name wins over the old built-in .wav.
	var candidates: Array[String] = []
	for folder in [CUSTOM_DIR, "res://assets/audio/"]:
		for extension in ["ogg", "mp3", "wav"]:
			candidates.append(folder + cue_name + "." + extension)
	for path in candidates:
		if not ResourceLoader.exists(path):
			continue
		var stream: AudioStream = load(path)
		if stream == null:
			continue
		stream = stream.duplicate()
		if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
			stream.loop = should_loop
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if should_loop else AudioStreamWAV.LOOP_DISABLED
			if should_loop:
				stream.loop_begin = 0
				stream.loop_end = int(stream.get_length() * stream.mix_rate)
		return stream
	return null

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
