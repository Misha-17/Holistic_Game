extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func run() -> void:
	var director := AudioDirector.new()
	director.sound_preferences_path = "user://sound_settings_test_%d.cfg" % Time.get_ticks_usec()
	root.add_child(director)
	director.set_process(false)
	var network := NetworkSession.new()
	network.active = true
	network.roster = {1: 0, 22: 1, 33: 2}
	var panel = load("res://scripts/sound_settings.gd").new()
	root.add_child(panel)
	panel.build(director, network)
	check(panel.sliders.size() == 3, "three players: one game slider and two voice sliders")
	check(not panel.sliders.has("voice_player_1"), "local player has no voice slider")
	check(panel.sliders.has("voice_player_2") and panel.sliders.has("voice_player_3"), "teammates have distinct sliders")
	check(panel.sliders.game_sound.value == 50, "game sound defaults to 50")
	director.play_cue("dispatch")
	check(is_equal_approx(director._pool[0].volume_linear, 0.5), "dispatch siren is halved")
	panel.sliders.game_sound.value = 0
	check(director._pool[0].volume_linear == 0.0, "master slider immediately mutes playing effects")
	director.start_music()
	director.set_intensity(0.5)
	director.update_music_context(2.1, true, true)
	director._process(4.0)
	check(director._intense_music.volume_linear == 0.0, "master slider also mutes music")
	panel.sliders.game_sound.value = 100
	check(is_equal_approx(director._pool[0].volume_linear, 1.0), "master applies consistently to fixed dispatch mix")
	panel.sliders.voice_player_2.value = 0
	panel.sliders.voice_player_3.value = 75
	director.load_sound_levels()
	check(director.sound_level("game_sound") == 100 and director.sound_level("voice_player_2") == 0 and director.sound_level("voice_player_3") == 75, "master and independent voice levels persist locally")
	network.roster.erase(22)
	network.roster_changed.emit()
	check(panel.sliders.size() == 2 and not panel.sliders.has("voice_player_2"), "departed player slider disappears")
	network.roster[44] = 1
	network.roster_changed.emit()
	check(panel.sliders.voice_player_2.value == 0, "new connection in saved player slot restores its level")
	var mixer = load("res://scripts/team_voice_mixer.gd").new()
	var pcm := PackedByteArray()
	pcm.resize(640)
	for i in 320: pcm.encode_s16(i * 2, 4096)
	mixer.push(22, 0, pcm, 0)
	mixer.push(33, 0, pcm, 0)
	var mixed: Dictionary = mixer.render(960, 1, {22: true, 33: true}, {22: 0.0, 33: 1.5})
	check(is_equal_approx(mixed.playback[0].x, 0.1875), "voice mixer independently mutes one peer and scales the other")
	check(mixed.recording.decode_s16(0) == 8192, "playback settings leave recordings unchanged")
	# Match full-track average levels using the selected actual recordings.
	var levels: Array[float] = []
	for path in ["res://assets/audio/beacon_bay_soft_v080.wav", "res://assets/audio/music_intense.mp3"]:
		var stream: AudioStream = load(path)
		var playback := stream.instantiate_playback()
		playback.start()
		var frames := int(stream.get_length() * AudioServer.get_mix_rate())
		var remaining := frames
		var energy := 0.0
		while remaining > 0:
			var count := mini(4096, remaining)
			for frame in playback.mix_audio(1.0, count):
				energy += frame.x * frame.x + frame.y * frame.y
			remaining -= count
		playback.stop()
		levels.append(linear_to_db(sqrt(energy / (frames * 2))))
		playback = null
		stream = null
	check(absf(levels[0] - levels[1] - AudioDirector.INTENSE_GAIN_DB) < 0.1, "intense and calm full-track RMS match within 0.1 dB")
	print("Music RMS difference after compensation: ", absf(levels[0] - levels[1] - AudioDirector.INTENSE_GAIN_DB), " dB")
	check(load("res://scripts/main.gd") != null, "main scene script loads with simplified settings")
	DirAccess.remove_absolute(director.sound_preferences_path)
	director.set_sfx_enabled(false)
	director.stop_music()
	director._process(2.0)
	panel.queue_free()
	network.free()
	await create_timer(0.1).timeout
	director.queue_free()
	panel = null
	director = null
	mixer = null
	await create_timer(0.1).timeout
	print("SOUND SETTINGS TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
