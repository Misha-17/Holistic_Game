extends SceneTree

class FakeNetwork extends NetworkSession:
	var sent := 0
	func send_voice(_sequence: int, _pcm: PackedByteArray) -> void:
		sent += 1

class FakeVoice extends TeamVoice:
	func _create_microphone() -> bool:
		if _microphone == null:
			_microphone = AudioStreamPlayer.new()
			_microphone.stream = AudioStreamGenerator.new()
			add_child(_microphone)
			_capture = AudioEffectCapture.new()
		return true
	func _publish_state() -> void:
		pass

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr(message)

func run() -> void:
	var net := FakeNetwork.new()
	var voice := FakeVoice.new()
	root.add_child(voice)
	voice.set_process(false)
	voice._network = net
	var pcm := PackedByteArray()
	pcm.resize(640)
	for i in 320: pcm.encode_s16(i * 2, 4096)
	voice._send_microphone_packet(pcm)
	check(net.sent == 0, "voice starts off")
	voice.set_mic_enabled(true)
	for i in 3:
		voice._sequence += 1
		voice._send_microphone_packet(pcm)
	check(net.sent == 3 and voice.status == "Voice chat enabled", "enabled mic sends successive packets without a key")
	voice.stop() # Recording lifecycle / menus must not disable microphone.
	voice._sequence += 1
	voice._send_microphone_packet(pcm)
	check(net.sent == 4 and voice.mic_enabled, "recording session end leaves enabled voice open")
	voice.set_mic_enabled(false)
	voice._send_microphone_packet(pcm)
	check(net.sent == 4 and voice.status == "Voice chat disabled", "turning off stops transmission")
	check(voice._source.is_empty() and not voice._mixer.streams.has(voice._local_peer), "turning off clears pending local audio")
	var mixer = TeamVoice.Mixer.new()
	mixer.push(2, 0, pcm, 0)
	mixer.push(3, 0, pcm, 0)
	var result: Dictionary = mixer.render(TeamVoice.Mixer.JITTER, 1, {2: true, 3: true}, {2: AudioDirector.slider_gain(50), 3: AudioDirector.slider_gain(0)}, TeamVoice.RECEIVED_VOICE_GAIN)
	check(is_equal_approx(result.playback[0].x, 0.25), "default 50 doubles playback; teammate mute remains effective")
	check(result.recording.decode_s16(0) == 8192, "recording levels stay unchanged")
	voice.shutdown()
	voice._network = null
	voice.queue_free()
	net.free()
	voice = null
	mixer = null
	await create_timer(0.1).timeout
	print("OPEN VOICE TEST: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
