extends SceneTree

# 4.11 (Andrei): study consent with clear information on the first screen, and
# withdrawal after playing (placeholder wording in scripts/study_info.gd).
# Run: godot --headless --path . -s tests/test_study_consent.gd
const Session = preload("res://scripts/team_voice_session.gd")

var failures: Array[String] = []
var game

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func button_ids() -> Array:
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	return game.buttons.map(func(b): return str(b.id))

func play_level(index: int) -> void:
	game._begin_shift(index)
	game.entry_popup = ""
	game._waiting_for_briefings = false
	game._sync_capture()
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(500, 400)
	motion.relative = Vector2(3, 2)
	for i in 5: game._input(motion)
	game.sim.elapsed = 330.0
	game.sim.running = false
	game.sim.finished = true
	game.sim.won = true
	game.screen = "results"
	game._sync_capture()

func write_lines(path: String, lines: Array) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	for line in lines: file.store_line(JSON.stringify(line))
	file.close()

func tone() -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(640)
	for i in 320: pcm.encode_s16(i * 2, 3000 if i % 2 == 0 else -3000)
	return pcm

func run() -> void:
	game = load("res://scripts/main.gd").new()
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)

	# --- Launch screen
	game._open_study_info("launch")
	var ids: Array = await button_ids()
	check(game.screen == "study_info" and ids.has("study_agree") and ids.has("study_decline") and not ids.has("study_back"), "the first screen asks for consent: %s" % [ids])
	game._action("study_decline")
	check(game.screen == "title" and not game.research_enabled and game.collection_choice_made, "declining goes to the title with recording off")
	check(not game.voice.recording_consent, "declining also refuses team voice recording")
	game._open_study_info("launch")
	game._action("study_agree")
	check(game.research_enabled and game.voice.recording_consent and game.study_consent_agreed, "agreeing turns recording on")

	# --- The answer holds: no consent question at the first level
	game.test_mode = false
	game._begin_shift(1)
	check(game.entry_popup != "consent", "no second consent question at the first level (entry: %s)" % game.entry_popup)
	game._stop_capture()
	check(game.collection_choice_made, "the launch answer holds after a session ends")
	game.test_mode = true

	# --- Study information can be re-read from settings
	game.screen = "settings"
	game.previous_screen = "title"
	game.settings_tab = "research"
	game._action("study_view")
	check(game.screen == "study_info" and game.study_info_mode == "view", "Settings > Research opens the study information")
	ids = await button_ids()
	check(ids.has("study_back") and not ids.has("study_agree"), "re-reading shows BACK, not the consent buttons")
	game._action("study_back")
	check(game.screen == "settings", "BACK returns to settings")
	game._action("settings_back")
	check(game.screen == "title", "settings BACK still returns to the title")

	# --- Solo withdrawal
	play_level(1)
	var session: String = game._tlx_session()
	var folder := "user://research/" + session
	check(DirAccess.dir_exists_absolute(folder), "the solo session was recorded")
	check(FileAccess.get_file_as_string(folder + "/session_events.jsonl").contains('"event":"study_consent"'), "the consent and its text version are in the log")
	check(game._can_withdraw(), "WITHDRAW MY DATA is offered after the level")
	ids = await button_ids()
	check(ids.has("withdraw_open") and ids.has("results_title"), "the results screen shows WITHDRAW MY DATA")
	game._action("withdraw_open")
	ids = await button_ids()
	check(game.withdraw_prompt and ids.has("withdraw_confirm") and ids.has("withdraw_cancel") and not ids.has("results_title"), "on the results screen it asks to confirm first")
	game._action("withdraw_cancel")
	check(DirAccess.dir_exists_absolute(folder), "CANCEL deletes nothing")
	game.screen = "title"
	ids = await button_ids()
	check(ids.has("withdraw_open") and ids.has("settings") and ids.has("quit"), "the main menu shows WITHDRAW MY DATA: %s" % [ids])
	game._action("withdraw_open")
	ids = await button_ids()
	check(game.withdraw_prompt and ids.has("withdraw_confirm") and not ids.has("play"), "a confirmation blocks the screen")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	game._input(esc)
	check(not game.withdraw_prompt and DirAccess.dir_exists_absolute(folder), "Esc cancels and deletes nothing")
	game._action("withdraw_open")
	game._action("withdraw_confirm")
	check(not DirAccess.dir_exists_absolute(folder), "withdrawing deletes the solo session folder")
	check(not game.research_enabled and not game.voice.recording_consent, "recording stops for this player")
	check(not game._can_withdraw(), "the button disappears afterwards")
	ids = await button_ids()
	check(not ids.has("withdraw_open"), "the main menu no longer shows it")
	var notes := FileAccess.get_file_as_string("user://research/withdrawals.jsonl")
	check(notes.contains(session) and notes.contains('"role":"solo"') and not notes.contains("mouse_motion"), "a withdrawal note without data is kept")

	# --- Leader: own rows go, shared game events and teammates stay
	var lead_session := "session_leadwithdraw_%d" % Time.get_ticks_usec()
	var lead := "user://research/" + lead_session
	var rows := [{"event": "incident_spawned", "data": {}}, {"event": "mouse_motion", "data": {}}, {"event": "dispatch", "data": {}}, {"event": "crew_selected", "data": {}}]
	write_lines(lead + "/session_events.jsonl", rows)
	write_lines(lead + "/levels/run1_events.jsonl", rows)
	write_lines(lead + "/levels/run1_samples_60hz.csv", ["header"])
	write_lines(lead + "/questionnaires/nasa_tlx_1.json", [{}])
	write_lines(lead + "/players/abcd0000abcd0001/levels/run1_events.jsonl", rows)
	var removed: Array = game._remove_own_rows(lead_session)
	var kept := FileAccess.get_file_as_string(lead + "/levels/run1_events.jsonl")
	check(kept.contains("incident_spawned") and kept.contains('"dispatch"') and not kept.contains("mouse_motion") and not kept.contains("crew_selected"), "the leader's own input rows are removed, game events kept")
	check(not FileAccess.file_exists(lead + "/levels/run1_samples_60hz.csv") and not DirAccess.dir_exists_absolute(lead + "/questionnaires"), "the leader's 60 Hz samples and survey answers are deleted")
	check(FileAccess.file_exists(lead + "/players/abcd0000abcd0001/levels/run1_events.jsonl"), "teammates' data is untouched")
	check(removed.size() >= 3, "the deleted items are listed: %s" % [removed])

	# --- Leader receives a teammate's withdrawal
	game.capture_session_id = lead_session
	game._store_relayed("abcd0000abcd0001", "withdrawal.json", "{}".to_utf8_buffer(), "withdraw")
	check(not DirAccess.dir_exists_absolute(lead + "/players/abcd0000abcd0001"), "a teammate's withdrawal deletes their folder on the leader's computer")
	check(FileAccess.get_file_as_string("user://research/withdrawals.jsonl").contains("abcd0000abcd0001"), "and is noted")
	game.capture_session_id = ""
	game._delete_tree(lead)

	# --- Teammate (not leader): a request is queued for the leader
	game.network.active = true
	game.network.hosting = false
	game.network.dedicated = true
	game.network.roster = {77: 0, 1: 1}
	game.last_capture_session_id = "session_guest_1"
	game._session_had_collection = true
	game._withdrawn_session = ""
	game._session_role = "guest"
	game._session_key = "abcd1234ef567890"
	game.relay.enqueue("levels/a_events.jsonl", "x\n".to_utf8_buffer(), "append")
	check(game._sends_to_leader(), "fixture: this player is not the leader")
	game._withdraw_my_data()
	var outbox: Array = game.relay._outbox
	check(outbox.size() == 1 and outbox[0].mode == "withdraw", "queued data is dropped and a withdrawal request is queued for the leader")
	game.relay.clear()
	game.network.active = false
	game.network.roster = {}
	# A teammate who already left the room: nothing can be deleted from here,
	# so the dialog gives a code for the researcher instead.
	game._withdrawn_session = ""
	game.last_capture_session_id = "session_guest_2"
	game.screen = "title"
	game._action("withdraw_open")
	game._action("withdraw_confirm")
	ids = await button_ids()
	check(game.withdraw_prompt and ids.has("withdraw_cancel") and not ids.has("withdraw_confirm"), "an offline teammate sees a code instead of a delete button")
	check(game._participant_code() == "ABCD-1234", "the code comes from the player key (%s)" % game._participant_code())
	game._action("withdraw_cancel")
	game._session_role = "solo"

	# --- Voice: one person's track removed from a finished session
	var vfolder := "user://voice_withdraw_%d" % Time.get_ticks_usec()
	var writer = Session.new()
	writer.open_file(vfolder.path_join("session.json"), {"session_id": "s"})
	for i in 5: writer.append_speakers({2: tone(), 3: tone()}, {2: {"speaker_key": "player_a", "peer_id": 2}, 3: {"speaker_key": "player_b", "peer_id": 3}})
	writer.close_file()
	var gone: Array = Session.withdraw_from_folder(vfolder, "player_b")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(vfolder.path_join("session.json")))
	check(gone.has("player_b.wav") and not FileAccess.file_exists(vfolder.path_join("player_b.wav")), "the withdrawn person's WAV is deleted")
	check((manifest.tracks as Array).size() == 1 and manifest.tracks[0].speaker_id == "player_a" and manifest.withdrawn_speakers == ["player_b"], "session.json keeps only the other track")
	check(FileAccess.file_exists(vfolder.path_join("player_a.wav")) and FileAccess.file_exists(vfolder.path_join("listen.html")), "the other track and the player stay")
	# ...and from a session that is still recording: never recorded again.
	var live_folder := "user://voice_withdraw_live_%d" % Time.get_ticks_usec()
	var live = Session.new()
	live.open_file(live_folder.path_join("session.json"), {"session_id": "t"})
	live.append_speakers({2: tone(), 3: tone()}, {2: {"speaker_key": "player_a", "peer_id": 2}, 3: {"speaker_key": "player_b", "peer_id": 3}})
	live.withdraw_speaker("player_b")
	live.append_speakers({2: tone(), 3: tone()}, {2: {"speaker_key": "player_a", "peer_id": 2}, 3: {"speaker_key": "player_b", "peer_id": 3}})
	live.close_file()
	check(not FileAccess.file_exists(live_folder.path_join("player_b.wav")), "a live session does not recreate the withdrawn track")

	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: consent on the first screen with study information; withdrawal deletes the player's data (solo, leader, teammate) and voice track")
	quit(0 if failures.is_empty() else 1)
