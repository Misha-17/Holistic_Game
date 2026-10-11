extends SceneTree

const Mixer = preload("res://scripts/team_voice_mixer.gd")
const Wav = preload("res://scripts/team_voice_wav.gd")
const Voice = preload("res://scripts/team_voice.gd")
const Net = preload("res://scripts/network_session.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)


func packet(sample: int) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(640)
	for index in range(320): pcm.encode_s16(index * 2, sample)
	return pcm


func _run() -> void:
	var mixer = Mixer.new()
	mixer.reset(0)
	check(mixer.push(1, 0, packet(4000), 0), "local packet accepted")
	check(mixer.push(2, 0, packet(6000), 0), "remote packet accepted")
	check(mixer.push(3, 0, packet(8000), 0), "unconsenting speaker accepted for playback")
	check(not mixer.push(2, 0, packet(2000), 0), "duplicate is dropped")
	check(not mixer.push(2, -1, packet(2000), 0), "negative sequence is dropped")
	var early: Dictionary = mixer.render(0, 1, {1: true, 2: true})
	check(early.recording.decode_s16(0) == 0, "jitter starts with silence")
	var result: Dictionary = mixer.render(960, 1, {1: true, 2: true, 3: false})
	check(result.recording.decode_s16(0) == 10000, "recording combines own and consented remote voice once")
	check(is_equal_approx(result.playback[0].x, 14000.0 / 32768.0), "playback excludes own microphone, includes all teammates")
	result = mixer.render(1280, 1, {1: true, 2: true, 3: true})
	check(result.recording.decode_s16(0) == 0, "missing packets and silence are not repeated speech")
	mixer.reset(0)
	mixer.push(2, 0, packet(24000), 0)
	mixer.push(3, 0, packet(24000), 0)
	result = mixer.render(960, 1, {2: true, 3: true})
	check(result.recording.decode_s16(0) == 32767, "simultaneous loud voices saturate safely")
	mixer.reset(0)
	for sequence in range(10000): mixer.push(2, sequence, packet(1), 0)
	check(mixer.streams[2].packets.size() <= Mixer.MAX_PACKETS, "packet buffer remains bounded under a flood")
	var folder := "res://.tools/voice-tests"
	DirAccess.make_dir_recursive_absolute(folder)
	var unique := str(Time.get_ticks_usec())
	var path := folder.path_join("mixer_" + unique + ".wav")
	var writer = Wav.new()
	check(writer.open_file(path, {"test": true}), "open local WAV")
	check(writer.append(packet(1234)), "append 20 ms audio")
	check(writer.append_silence(15680), "append silence up to one real second")
	writer.checkpoint()
	var data := FileAccess.get_file_as_bytes(path)
	check(data.size() == 32044, "WAV lasts precisely one second")
	check(data.decode_u32(4) == 32036 and data.decode_u32(40) == 32000, "live WAV header matches PCM data")
	check(data.decode_u32(24) == 16000 and data.decode_u16(22) == 1 and data.decode_u16(34) == 16, "mono PCM16 format")
	check(data.decode_s16(44) == 1234 and data.decode_s16(684) == 0, "PCM content and silence survive streaming")
	check(Wav.recover_pending(folder) == 0, "recovery leaves live recordings alone")
	writer.close_file()
	check(not FileAccess.file_exists(path + ".open"), "clean stop removes recovery marker")
	var recovery_path := folder.path_join("recovery_" + unique + ".wav")
	var broken := FileAccess.open(recovery_path, FileAccess.WRITE)
	data.encode_u32(4, 36)
	data.encode_u32(40, 0)
	broken.store_buffer(data)
	broken.close()
	var marker := FileAccess.open(recovery_path + ".open", FileAccess.WRITE)
	marker.store_string(JSON.stringify({"format": "beacon-bay-pcm16-v1", "pid": -1}))
	marker.close()
	check(Wav.recover_pending(folder) == 1, "orphaned recording is repaired")
	data = FileAccess.get_file_as_bytes(recovery_path)
	check(data.decode_u32(40) == 32000, "crash repair recovers actual retained PCM length")
	var network = Net.new()
	root.add_child(network)
	var voice = Voice.new()
	root.add_child(voice)
	voice.configure(network, false)
	check(voice.start("synthetic_" + unique), "session starts with recording off")
	check(voice.recording_path == "", "recording off creates no audio file")
	voice.set_session_time(15.0)
	voice.set_recording_enabled(true)
	check(voice.recording_active, "saving can start mid-session")
	var saved_path: String = voice.recording_path
	var began := Time.get_ticks_msec()
	await create_timer(0.08).timeout
	voice.set_recording_enabled(false)
	await create_timer(0.08).timeout
	voice.set_recording_enabled(true)
	check(voice.recording_path == saved_path, "resume retains one WAV without overwrite")
	await create_timer(0.08).timeout
	voice.stop()
	data = FileAccess.get_file_as_bytes(saved_path)
	var duration := float(data.size() - 44) / 32000.0
	var wall_seconds := (Time.get_ticks_msec() - began) / 1000.0
	check(duration >= 0.1 and absf(duration - wall_seconds) < 0.04 and data.decode_u32(40) == data.size() - 44, "session WAV includes silent interval and final header on the wall clock")
	voice.start("tail_" + unique)
	voice._mixer.push(1, 0, packet(2345), voice._clock_frame())
	voice.stop()
	data = FileAccess.get_file_as_bytes(voice.recording_path)
	var found_tail := false
	for offset in range(44, data.size(), 2):
		if data.decode_s16(offset) == 2345: found_tail = true
	check(found_tail, "session stop retains speech still in the jitter buffer")
	voice.shutdown()
	voice.queue_free()
	network.queue_free()
	await process_frame
	print("VOICE AUDIO TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
