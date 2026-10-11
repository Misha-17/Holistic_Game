extends SceneTree

const Director = preload("res://scripts/audio_director.gd")
var failures: Array[String] = []
var capture: AudioEffectCapture


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)


func measure(seconds: float) -> Dictionary:
	capture.clear_buffer()
	var peak := 0.0
	var energy := 0.0
	var samples := 0
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		await create_timer(0.05).timeout
		var available := capture.get_frames_available()
		if available == 0:
			continue
		for frame in capture.get_buffer(available):
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
			energy += frame.x * frame.x + frame.y * frame.y
			samples += 2
	return {"peak": peak, "rms": sqrt(energy / maxf(1, samples)), "samples": samples}


func _run() -> void:
	# Capture Master after Music's own bus gain: this measures rendered sound,
	# including the real stream, player envelope and AudioServer attenuation.
	capture = AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(0, capture)
	AudioServer.add_bus()
	var voice_bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(voice_bus, &"TeamVoice")
	AudioServer.set_bus_volume_db(voice_bus, -3.0)
	var director = Director.new()
	root.add_child(director)
	director.set_process(false)
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), -20.0), "music defaults to -20 dB")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX")), -6.0), "sound effect level is preserved")
	check(is_equal_approx(AudioServer.get_bus_volume_db(voice_bus), -3.0), "voice level is untouched")
	check(director._music.stream != null, "soft soundtrack loads")
	if director._music.stream == null:
		quit(1)
		return
	check(director._music.stream is AudioStreamWAV, "default score uses new generated WAV instead of old pressure MP3s")
	check(director._music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "score loops")
	check(not director.has_node("ResponseRhythm") and not director.has_node("PressurePulse"), "no tense or panic music layers run")
	director.start_music()
	director._process(0.25)
	check(director._music.volume_db < -35.0, "score begins gently")
	director._process(1.75)
	check(is_equal_approx(director._music.volume_db, linear_to_db(0.5)), "fade reaches halfway after two seconds")
	director._process(2.0)
	await create_timer(0.15).timeout
	var normal: Dictionary = await measure(4.0)
	check(normal.samples > 10000, "AudioServer produced actual audio frames")
	check(normal.rms > db_to_linear(-55.0), "music remains audible, not disabled")
	check(normal.peak <= db_to_linear(-25.5), "default music output stays below -25.5 dBFS")
	check(normal.rms < db_to_linear(-30.0), "default background level stays below -30 dBFS RMS")
	var score: AudioStream = director._music.stream
	director.set_intensity(1.0)
	director._process(10.0)
	var busy: Dictionary = await measure(4.0)
	check(director._music.stream == score, "busy calls keep the same soft score")
	check(busy.peak <= db_to_linear(-25.5), "busy periods cannot add louder music layers")
	director.set_music_enabled(false)
	director._process(1.0)
	check(director._music.playing and director._music.volume_db < -5.9, "mute fades gently instead of stopping abruptly")
	director._process(1.0)
	await create_timer(0.15).timeout
	var muted: Dictionary = await measure(0.2)
	check(not director._music.playing and muted.peak < 0.00001, "muted soundtrack stops and is silent")
	director.set_music_enabled(true)
	check(director._music.playing, "music can restart after mute")
	director.stop_music()
	director._process(2.0)
	check(not director._music.playing, "stop releases the music player")
	print("Music output: normal peak=%.2f dBFS RMS=%.2f dBFS; busy peak=%.2f dBFS RMS=%.2f dBFS" % [linear_to_db(normal.peak), linear_to_db(normal.rms), linear_to_db(busy.peak), linear_to_db(busy.rms)])
	print("MUSIC AUDIO TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	AudioServer.remove_bus_effect(0, 0)
	capture = null
	score = null
	director.queue_free()
	await create_timer(0.1).timeout
	quit(0 if failures.is_empty() else 1)
