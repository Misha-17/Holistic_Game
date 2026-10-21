extends SceneTree

const Session = preload("res://scripts/team_voice_session.gd")
const Player = preload("res://scripts/team_voice_player.gd")
const Voice = preload("res://scripts/team_voice.gd")
const Net = preload("res://scripts/network_session.gd")
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)


func packet(value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(640)
	for frame in 320: bytes.encode_s16(frame * 2, value)
	return bytes


func wait_ms(milliseconds: int) -> void:
	var end := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < end: await process_frame


func samples(path: String) -> Dictionary:
	var data := FileAccess.get_file_as_bytes(path)
	var unique: Dictionary = {}
	for offset in range(44, data.size(), 2): unique[data.decode_s16(offset)] = true
	return unique


func run() -> void:
	var unique := str(Time.get_ticks_usec())
	var folder := "res://.tools/voice-tests/session_" + unique
	var writer = Session.new()
	var manifest_path := folder.path_join("session.json")
	check(writer.open_file(manifest_path, {"session_id": unique}), "speaker session opens")
	writer.append_silence(320)
	writer.append_speakers({1: packet(24000)}, {1: {"display_name": "Robin"}})
	writer.append_speakers({1: packet(24000), 2: packet(24000)}, {1: {"display_name": "Robin"}, 2: {"display_name": "Elio"}})
	writer.append_silence(320)
	writer.close_file()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	check(manifest.tracks.size() == 2 and int(manifest.frames) == 1280, "manifest groups both speakers into one session")
	for track: Dictionary in manifest.tracks:
		var data := FileAccess.get_file_as_bytes(folder.path_join(track.file))
		check(int(track.frames) == 1280 and data.size() == 44 + 2560, "late speaker and original speaker share frame zero and duration")
		check(data.decode_s16(44) == 0 and data.decode_s16(44 + 640 * 2) == 24000 and data.decode_s16(44 + 960 * 2) == 0, "leading silence, overlap and pause stay sample aligned")
		check(not samples(folder.path_join(track.file)).has(32767), "overlapping loud voices are never summed in saved files")
	check(Session.recover_pending("res://.tools/voice-tests") == 0, "closed sessions need no recovery")
	var malicious := manifest.duplicate(true)
	malicious.tracks[0].display_name = "</script><script>window.injected=true</script>"
	var player_path := folder.path_join("unsafe_name_test.html")
	check(Player.write_file(player_path, malicious), "offline review player is created")
	var player_html := FileAccess.get_file_as_string(player_path)
	check(not player_html.contains(malicious.tracks[0].display_name) and player_html.contains("\\u003c/script\\u003e"), "speaker names cannot break out of embedded JSON")
	check(player_html.contains("name.textContent=") and player_html.contains("Promise.all(tracks.map"), "player labels use text and one transport starts every track")
	var recovery_folder := folder + "_interrupted"
	DirAccess.make_dir_recursive_absolute(recovery_folder)
	for track: Dictionary in manifest.tracks:
		var retained := FileAccess.get_file_as_bytes(folder.path_join(track.file))
		if int(track.peer_id) == 2: retained.resize(44 + 640 * 2)
		retained.encode_u32(4, 36)
		retained.encode_u32(40, 0)
		var file := FileAccess.open(recovery_folder.path_join(track.file), FileAccess.WRITE)
		file.store_buffer(retained)
		file.close()
		file = FileAccess.open(recovery_folder.path_join(str(track.file) + ".open"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"format": "beacon-bay-pcm16-v1", "pid": -1}))
		file.close()
		file = FileAccess.open(recovery_folder.path_join(str(track.file).get_basename() + ".jsonl"), FileAccess.WRITE)
		file.store_string(FileAccess.get_file_as_string(folder.path_join(str(track.file).get_basename() + ".jsonl")))
		file.close()
	var interrupted := manifest.duplicate(true)
	interrupted.state = "recording"
	interrupted.pid = -1
	interrupted.tracks.resize(1)
	var partial := FileAccess.open(recovery_folder.path_join("session.json"), FileAccess.WRITE)
	partial.store_string(JSON.stringify(interrupted))
	partial.close()
	check(Session.recover_pending("res://.tools/voice-tests") == 2, "interrupted speaker WAVs are recovered")
	var recovered: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(recovery_folder.path_join("session.json")))
	check(recovered.state == "recovered" and recovered.tracks.size() == 2, "recovery restores a track absent from the last manifest checkpoint")
	for track: Dictionary in recovered.tracks:
		var retained := FileAccess.get_file_as_bytes(recovery_folder.path_join(track.file))
		check(int(track.frames) == 1280 and retained.decode_u32(40) == 2560, "recovered tracks are padded to the same session duration")
	check(FileAccess.file_exists(recovery_folder.path_join("listen.html")), "recovery regenerates the offline session player")

	var network = Net.new()
	root.add_child(network)
	network.roster = {1: 0, 2: 1, 3: 2}
	network.player_names = {1: "Robin", 2: "Elio", 3: "Nova"}
	network.voice_participants = {1: {"mic": true, "consent": true, "recording": false}, 2: {"mic": true, "consent": true, "recording": false}, 3: {"mic": true, "consent": false, "recording": false}}
	var voice = Voice.new()
	root.add_child(voice)
	voice.configure(network)
	voice.mic_enabled = true # Synthetic PCM; never open the physical microphone.
	voice.set_capture_active(false)
	voice.set_recording_enabled(true)
	voice.set_research_context({"level_run_id": "practice", "level_id": 0, "level_elapsed_s": 0.0})
	voice.start(unique)
	check(voice.recording_path.is_empty(), "capture gate creates no file while consent or level start is pending")
	await wait_ms(40)
	voice.set_capture_active(true)
	var session_path: String = voice.recording_path
	voice._sequence += 1
	voice._send_microphone_packet(packet(6666), false)
	voice._sequence += 1
	voice._send_microphone_packet(packet(1111))
	voice._receive_voice(2, 1, packet(2222))
	voice._receive_voice(3, 1, packet(9999))
	await wait_ms(180)
	voice.set_capture_active(false)
	voice._receive_voice(2, 2, packet(7777))
	await wait_ms(30)
	voice.set_research_context({"level_run_id": "first", "level_id": 1, "level_elapsed_s": 0.0})
	voice.start(unique)
	voice.set_capture_active(true)
	voice.set_session_time(0.0)
	check(voice.recording_path == session_path, "level changes and elapsed-time resets retain one session")
	await wait_ms(180)
	voice._receive_voice(2, 3, packet(8888))
	network.voice_participants[2].consent = false
	voice._participants_updated()
	network.voice_participants[2].consent = true
	voice._participants_updated()
	await wait_ms(180)
	voice.stop()
	manifest = JSON.parse_string(FileAccess.get_file_as_string(session_path))
	check(manifest.tracks.size() == 2, "unconsenting participant has no audio track")
	check(manifest.level_segments.size() == 2 and manifest.level_segments[0].level_run_id == "practice" and manifest.level_segments[1].level_run_id == "first", "manifest has explicit level segments for the session player")
	check(manifest.audio_activity.size() == 2, "speaker activity spans identify only recorded speech")
	for track: Dictionary in manifest.tracks:
		var values := samples(session_path.get_base_dir().path_join(track.file))
		check(int(track.frames) == int(manifest.frames), "all session tracks stay aligned through level transition")
		check(not values.has(9999) and not values.has(7777) and not values.has(8888) and not values.has(6666), "nonconsent, pre-opt-in microphone samples, between-level speech and revoked buffered speech are excluded")
		check(values.has(1111 if int(track.peer_id) == 1 else 2222), "track contains its own speaker only")
		check(str(track.display_name).contains("Robin" if int(track.peer_id) == 1 else "Elio"), "manifest labels speaker by participant name")
	var timeline := FileAccess.get_file_as_string(session_path.get_base_dir().path_join("timeline.jsonl"))
	check(timeline.contains('"level_run_id":"practice"') and timeline.contains('"level_run_id":"first"'), "voice timing metadata retains both level segments")
	check(timeline.contains('"capture_suspended"') and timeline.contains('"capture_resumed"'), "capture gaps are explicit on the session timeline")
	voice.shutdown()
	voice.queue_free()
	network.queue_free()
	await process_frame
	print("VOICE SESSION TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
