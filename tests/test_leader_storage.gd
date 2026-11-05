extends SceneTree

# Playtest 2.11 (Andrei):
# - Himashi kept reconnecting; every reconnect opened a new voice track as long
#   as the whole session, with about a minute of speech each. One person must
#   stay one track.
# - "Only the host stores files." A player who is not the session leader writes
#   nothing on their own computer; their own input (not the shared game events)
#   goes to the leader, who stores it under players/<player key>/.
# Run: godot --headless --path . -s tests/test_leader_storage.gd

const Session = preload("res://scripts/team_voice_session.gd")

class FakeNetwork extends NetworkSession:
	var sent: Array = []
	func relay_ready() -> bool: return true
	func send_research(rel_path: String, raw: PackedByteArray, mode: String) -> bool:
		sent.append([rel_path, raw.duplicate(), mode])
		return true

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func tone(value: int) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(640)
	for i in 320: pcm.encode_s16(i * 2, value if i % 2 == 0 else -value)
	return pcm

func test_voice_one_track_per_person() -> void:
	var folder := "user://voice_reconnect_%d" % Time.get_ticks_usec()
	var writer = Session.new()
	check(writer.open_file(folder.path_join("session.json"), {"session_id": "s1"}), "voice session opens")
	var himashi := {"speaker_key": "player_aaaa0000aaaa0001", "display_name": "Himashi"}
	var andrei := {"speaker_key": "player_bbbb0000bbbb0002", "display_name": "Andrei"}
	# Himashi speaks as network id 5, drops, rejoins as 9, then 13.
	for peer_id in [5, 9, 13]:
		var identity: Dictionary = himashi.duplicate()
		identity["peer_id"] = peer_id
		for _i in 10: writer.append_speakers({peer_id: tone(3000), 2: tone(1000)}, {peer_id: identity, 2: andrei.merged({"peer_id": 2})})
		writer.append_silence(320 * 20) # away
	writer.close_file()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("session.json")))
	var tracks: Array = manifest.get("tracks", [])
	check(tracks.size() == 2, "two people, two tracks (found %d)" % tracks.size())
	var wavs := 0
	for name in DirAccess.get_files_at(folder): if name.ends_with(".wav"): wavs += 1
	check(wavs == 2, "two WAV files on disk (found %d)" % wavs)
	for track: Dictionary in tracks:
		if track.speaker_id == "player_aaaa0000aaaa0001":
			check((track.peer_ids as Array).map(func(v): return int(v)) == [5, 9, 13], "Himashi's three connections share one track: %s" % [track.peer_ids])
			check(track.file == "player_aaaa0000aaaa0001.wav", "the file is named after the player, not the connection")
	var activity: Array = manifest.get("audio_activity", [])
	check(activity.any(func(a): return a.speaker_id == "player_aaaa0000aaaa0001" and int(a.peer_id) == 13), "speech after a reconnect is in the same speaker's activity")

func test_non_leader_writes_nothing_locally() -> void:
	var net := FakeNetwork.new()
	root.add_child(net)
	var relay := ResearchRelay.new()
	relay.network = net
	root.add_child(relay)
	var logger := ResearchLogger.new()
	root.add_child(logger)
	logger.relay = relay
	var session := "session_relaytest_%d" % Time.get_ticks_usec()
	logger.begin_session(session, {"peer_id": 7})
	logger.begin_level(2, {"level_number": 3}, "level3_run")
	logger.log_pointer(Vector2(100, 200), Vector2(3, 4))
	logger.log_event("crew_selected", {"unit_id": 4})
	logger.log_event("incident_spawned", {"incident_id": 1}) # shared game event: the leader has it
	logger.observe_state({"elapsed": 3.0, "score": 10})
	logger.end_level("completed")
	logger.set_enabled(false)
	relay.flush_now()
	check(not DirAccess.dir_exists_absolute("user://research/" + session), "a non-leader creates no local research folder")
	var text := {}
	for item in net.sent: text[item[0]] = str(text.get(item[0], "")) + (item[1] as PackedByteArray).get_string_from_utf8()
	check(text.has("session_events.jsonl") and text.has("levels/level3_run_events.jsonl") and text.has("manifest.json"), "events, level file and manifest are relayed: %s" % [text.keys()])
	var level_text := str(text.get("levels/level3_run_events.jsonl", ""))
	check('"event":"mouse_motion"' in level_text and '"event":"crew_selected"' in level_text, "own mouse and selections are relayed")
	check(not '"event":"incident_spawned"' in level_text and not '"event":"state_observed"' in level_text, "shared game events are left to the leader")
	check(text.has("levels/level3_run_samples_60hz.csv"), "the 60 Hz samples are relayed too")
	logger.queue_free()
	relay.queue_free()
	net.queue_free()

func test_leader_stores_relayed_files() -> void:
	var game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.capture_session_id = "session_leadertest_%d" % Time.get_ticks_usec()
	var key := "cccc0000cccc0003"
	game._store_relayed(key, "levels/run_events.jsonl", "a\n".to_utf8_buffer(), "append")
	game._store_relayed(key, "levels/run_events.jsonl", "b\n".to_utf8_buffer(), "append")
	game._store_relayed(key, "manifest.json", "{\"v\":1}".to_utf8_buffer(), "replace")
	game._store_relayed(key, "manifest.json", "{\"v\":2}".to_utf8_buffer(), "replace")
	game._store_relayed(key, "../../escape.jsonl", "x".to_utf8_buffer(), "append")
	var folder := "user://research/%s/players/%s" % [game.capture_session_id, key]
	check(FileAccess.get_file_as_string(folder + "/levels/run_events.jsonl") == "a\nb\n", "appended rows arrive in order")
	check(FileAccess.get_file_as_string(folder + "/manifest.json") == "{\"v\":2}", "replaced files keep the latest version")
	check(FileAccess.file_exists(folder + "/player.json"), "player.json says who the key belongs to")
	check(not FileAccess.file_exists("user://research/%s/escape.jsonl" % game.capture_session_id) and not FileAccess.file_exists("user://escape.jsonl"), "unsafe paths are ignored")
	check(game.network.is_leader() and not game._sends_to_leader(), "solo play stores its own files")
	game.voice.shutdown()
	game.queue_free()

func run() -> void:
	test_voice_one_track_per_person()
	test_non_leader_writes_nothing_locally()
	test_leader_stores_relayed_files()
	await process_frame
	if failures.is_empty(): print("PASS: one voice track per person across reconnects; non-leaders write nothing locally and relay only their own data; the leader stores it per player")
	quit(0 if failures.is_empty() else 1)
