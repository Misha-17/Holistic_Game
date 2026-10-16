extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func run() -> void:
	var game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_process(false)
	game.audio.set_sfx_enabled(false)
	game.audio.set_music_enabled(true)
	game._begin_shift(0)
	check(not game.audio._busy, "new shift starts calm")
	# Real first-shift arrivals, no fabricated pressure or hidden-phase input.
	var first_busy := -1.0
	for i in 600:
		game._process(0.1)
		game.audio._process(0.1)
		if game.audio._busy and first_busy < 0.0:
			first_busy = game.sim.elapsed
	check(first_busy > 0.0, "actual busy city reaches the intense state")
	check(game.audio._intense_music.playing and not game.audio._music.playing, "gameplay routing plays intense alone after crossfade")
	check(is_equal_approx(game.audio._intense_music.volume_db, 34.67110038), "intense amplitude includes the additional 50 percent boost")
	# Check all samples, not just the quiet opening, for gain headroom.
	var stream: AudioStream = game.audio._intense_music.stream
	var playback := stream.instantiate_playback()
	playback.start()
	var frames := int(stream.get_length() * AudioServer.get_mix_rate())
	var remaining := frames
	var peak := 0.0
	var energy := 0.0
	while remaining > 0:
		var count := mini(4096, remaining)
		var pcm: PackedVector2Array = playback.mix_audio(1.0, count)
		for frame in pcm:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
			energy += frame.x * frame.x + frame.y * frame.y
		remaining -= count
	playback.stop()
	var gain := db_to_linear(game.audio.INTENSE_GAIN_DB)
	var output_rms: float = linear_to_db(sqrt(energy / (frames * 2)) * gain) + float(game.audio.music_volume_db)
	check(peak * gain * AudioDirector.slider_gain(50) * db_to_linear(game.audio.music_volume_db) < 1.0, "full intense recording retains output headroom at default volume")
	check(output_rms > -31.0 and output_rms < -29.0, "full-track intense level reflects the requested boost")
	print("Gameplay first busy at %.1fs; intense full-track output peak %.2f dBFS, RMS %.2f dBFS" % [first_busy, linear_to_db(peak * gain) + game.audio.music_volume_db, output_rms])
	print("MUSIC GAMEPLAY TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	playback = null
	stream = null
	game.queue_free()
	game = null
	await create_timer(0.1).timeout
	quit(0 if failures.is_empty() else 1)
