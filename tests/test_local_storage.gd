extends SceneTree

# Playtest 07.11 (Andrei): every player stores their own study data locally
# (the 2.11 relay to the session leader was too slow and a survey never
# arrived), and the files must be easy to identify: one folder per session named
# by date, time and player name, file names that say what is inside.
# Also kept from 2.11: a reconnecting player stays one voice track.
# Run: godot --headless --path . -s tests/test_local_storage.gd

const Session = preload("res://scripts/team_voice_session.gd")

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

func files_in(folder: String) -> Array:
	var names: Array = Array(DirAccess.get_files_at(folder))
	names.sort()
	return names

func test_names() -> void:
	check(StudyFiles.label("Andrei Toma") == "Andrei-Toma", "spaces become hyphens: %s" % StudyFiles.label("Andrei Toma"))
	check(StudyFiles.label("  ") == "Player" and StudyFiles.label("O'Neil") == "ONeil", "blank names and apostrophes")
	check(StudyFiles.level_base("Mia", 3, 1) == "Mia_level-3" and StudyFiles.level_base("Mia", 3, 2) == "Mia_level-3_try-2", "level names and retries")
	var first := StudyFiles.new_session_name("Mia")
	var parts := first.split("_")
	check(parts.size() == 3 and parts[0].length() == 10 and parts[1].length() == 5 and parts[2] == "Mia", "session folder is date_time_name: %s" % first)
	DirAccess.make_dir_recursive_absolute("user://research/" + first)
	check(StudyFiles.new_session_name("Mia") == first + "_2", "a second session in the same minute gets _2")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://research/" + first))

func test_logger_writes_readable_files_locally() -> void:
	var logger := ResearchLogger.new()
	root.add_child(logger)
	logger.file_label = "Mia Lee"
	var session := StudyFiles.new_session_name("Mia Lee")
	var folder := "user://research/" + session
	logger.begin_session(session, {"peer_id": 7})
	logger.begin_level(2, {"level_number": 3}, "level3_run_a")
	logger.log_pointer(Vector2(100, 200), Vector2(3, 4))
	logger.log_event("crew_selected", {"unit_id": 4})
	logger.log_event("incident_spawned", {"incident_id": 1})
	logger.end_level("completed")
	logger.begin_level(2, {"level_number": 3}, "level3_run_b") # the same level again
	logger.log_pointer(Vector2(110, 210), Vector2(1, 1))
	logger.begin_level(3, {"level_number": 4}, "level4_run")
	logger.begin_level(2, {"level_number": 3}, "level3_run_b") # back in run b (a reconnect)
	logger.log_pointer(Vector2(120, 220), Vector2(1, 1))
	logger.end_level("completed")
	logger.set_enabled(false)
	var names := files_in(folder)
	for expected in ["Mia-Lee_all-levels_events.jsonl", "Mia-Lee_session-info.json", "Mia-Lee_level-3_events.jsonl",
			"Mia-Lee_level-3_try-2_events.jsonl", "Mia-Lee_level-4_events.jsonl", "Mia-Lee_level-3_mouse-and-taskload-60hz.csv", StudyFiles.README_NAME]:
		check(names.has(expected), "%s is in the session folder: %s" % [expected, names])
	check(not DirAccess.dir_exists_absolute(folder + "/levels") and not DirAccess.dir_exists_absolute(folder + "/players"), "no levels/ or players/ subfolders")
	var level := FileAccess.get_file_as_string(folder + "/Mia-Lee_level-3_events.jsonl")
	check('"event":"mouse_motion"' in level and '"event":"crew_selected"' in level and '"event":"incident_spawned"' in level, "own input and the game events are both stored here")
	var retry := FileAccess.get_file_as_string(folder + "/Mia-Lee_level-3_try-2_events.jsonl")
	check(retry.count('"event":"mouse_motion"') == 2, "a rejoined run continues its own file (%d mouse rows)" % retry.count('"event":"mouse_motion"'))
	check(not names.has("Mia-Lee_level-3_try-3_events.jsonl"), "rejoining is not counted as another try")
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/Mia-Lee_session-info.json"))
	check(str(info.get("player_name", "")) == "Mia Lee" and (info.get("level_files", []) as Array).size() == 3, "session info names the player and lists three level files")
	check(FileAccess.get_file_as_string(folder + "/" + StudyFiles.README_NAME).contains("Mia-Lee_nasa-tlx.json"), "the READ ME explains the files with this player's names")
	logger.queue_free()

func test_survey_and_withdrawal_in_coop() -> void:
	var game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.network.local_player_name = "Mia"
	game.capture_session_id = StudyFiles.new_session_name("Mia")
	var folder: String = "user://research/" + game.capture_session_id
	for id in ["mental_demand", "physical_demand", "temporal_demand", "performance", "effort", "frustration"]: game.tlx_form.set_answer(id, 40)
	game._submit_tlx()
	game.tlx_form.reset()
	for id in ["mental_demand", "physical_demand", "temporal_demand", "performance", "effort", "frustration"]: game.tlx_form.set_answer(id, 60)
	game._submit_tlx()
	var names := files_in(folder)
	check(names.has("Mia_nasa-tlx.json") and names.has("Mia_nasa-tlx_2.json"), "survey answers are saved next to the session files: %s" % [names])
	var answers: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/Mia_nasa-tlx.json"))
	check(str(answers.get("player_name", "")) == "Mia", "the survey file names the player")
	check(game._study_footer() == "Progress saved locally", "solo footer")
	game.network.active = true
	check(game._study_footer() == "Your study files are saved on this computer", "co-op footer: no session-leader message")
	# Withdrawal deletes the folder on this computer, in co-op too.
	game._session_had_collection = true
	game._withdraw_my_data()
	check(not DirAccess.dir_exists_absolute(folder), "withdrawing deletes this computer's session folder")
	game.network.active = false
	game.voice.shutdown()
	game.queue_free()

func run() -> void:
	test_voice_one_track_per_person()
	test_names()
	test_logger_writes_readable_files_locally()
	test_survey_and_withdrawal_in_coop()
	await process_frame
	if failures.is_empty(): print("PASS: each player's study files are stored locally in a date_time_name folder with descriptive names; one voice track per person across reconnects")
	quit(0 if failures.is_empty() else 1)
