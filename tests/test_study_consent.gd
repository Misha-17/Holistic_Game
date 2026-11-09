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
	check(FileAccess.get_file_as_string(folder + "/Player_all-levels_events.jsonl").contains('"event":"study_consent"'), "the consent and its text version are in the log")
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
	check(notes.contains(session) and not notes.contains("mouse_motion"), "a withdrawal note without data is kept")

	# --- Co-op (9.11): every player's files are on their own computer, so a
	# teammate withdraws the same way, also after leaving the room.
	game._stop_capture()
	game.research_enabled = true
	game.network.local_player_name = "Mia"
	play_level(2)
	var coop_session: String = game._tlx_session()
	check(coop_session.ends_with("_Mia") and FileAccess.file_exists("user://research/%s/Mia_level-3_events.jsonl" % coop_session), "files are named after the player: %s" % coop_session)
	game.network.active = false
	check(game._can_withdraw(), "offered again for a new session")
	game.screen = "title"
	game._action("withdraw_open")
	ids = await button_ids()
	check(ids.has("withdraw_confirm") and ids.has("withdraw_cancel"), "the same confirmation for everyone: %s" % [ids])
	game._action("withdraw_confirm")
	check(not DirAccess.dir_exists_absolute("user://research/" + coop_session), "the session folder is deleted from this computer")

	# --- Voice: the recording lives inside the session folder and goes with it.
	var vsession := StudyFiles.new_session_name("Mia")
	var vfolder := "user://research/%s/Mia_voice" % vsession
	var writer = Session.new()
	writer.open_file(vfolder.path_join("session.json"), {"session_id": vsession})
	for i in 5: writer.append_speakers({2: tone()}, {2: {"speaker_key": "Mia_voice", "peer_id": 2}})
	writer.close_file()
	check(FileAccess.file_exists(vfolder.path_join("Mia_voice.wav")), "the player's track is <name>_voice.wav")
	check(game.voice.session_folders(vsession) == [vfolder], "the voice folder is found in the session folder")
	game.voice.delete_session_folders(vsession)
	check(not DirAccess.dir_exists_absolute(vfolder), "withdrawal deletes the voice folder")
	game._delete_tree("user://research/" + vsession)

	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: consent on the first screen with study information; withdrawal deletes this computer's session folder and voice")
	quit(0 if failures.is_empty() else 1)
