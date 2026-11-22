extends SceneTree

# Andrei (4.11): players who stop before Level 6 forget the NASA-TLX button on
# the title screen. MAIN MENU on the results screen now asks first: YES opens
# the survey, then the main menu; NO goes straight to the main menu.
# Run: godot --headless --path . -s tests/test_leave_survey.gd
var failures: Array[String] = []
var game

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func finish_level(index: int) -> void:
	game._begin_shift(index)
	game.entry_popup = ""
	game.sim.elapsed = 330.0
	game.sim.running = false
	game.sim.finished = true
	game.sim.won = true
	game.screen = "results"
	game.results_since = -1.0
	game._process(0.0)
	game.elapsed_ui += game.TLX_DELAY_S + 0.1
	game._process(0.0)

func button_ids() -> Array:
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	return game.buttons.map(func(b): return str(b.id))

func surveys(session: String) -> Array[String]:
	var found: Array[String] = []
	var folder := "user://research/%s" % session
	if DirAccess.dir_exists_absolute(folder):
		for name in DirAccess.get_files_at(folder):
			if name.contains("_nasa-tlx"): found.append(folder.path_join(name))
	return found

func esc() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	game._input(key)

func run() -> void:
	game = load("res://scripts/main.gd").new()
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.collection_choice_made = true
	game.voice_choice_made = true

	finish_level(1) # Level 2: not the last level, no automatic survey
	check(game.screen == "results", "Level 2 results do not open the survey by themselves")
	var session: String = game._tlx_session()
	check(not session.is_empty(), "the session has an id")

	# MAIN MENU asks first; Esc closes the question and stays.
	game._action("results_title")
	check(game.leave_prompt and game.screen == "results", "MAIN MENU asks about the survey first")
	var ids: Array = await button_ids()
	check(ids.has("leave_tlx_yes") and ids.has("leave_tlx_no") and not ids.has("results_continue"), "the question shows YES and NO and blocks the results buttons: %s" % [ids])
	esc()
	check(not game.leave_prompt and game.screen == "results", "Esc closes the question and stays on the results screen")

	# NO: straight to the main menu, nothing saved.
	game._action("results_title")
	game._action("leave_tlx_no")
	check(game.screen == "title" and not game.leave_prompt, "NO goes to the main menu")
	check(surveys(session).is_empty(), "NO saves no survey")

	# YES: the survey, then the main menu.
	finish_level(2)
	session = game._tlx_session()
	game._action("results_title")
	game._action("leave_tlx_yes")
	check(game.screen == "tlx" and game.tlx_source == "leaving_session", "YES opens the survey")
	ids = await button_ids()
	check(ids.has("tlx_later"), "the survey can still be skipped")
	for id in ["mental_demand", "physical_demand", "temporal_demand", "performance", "effort", "frustration"]:
		game.tlx_form.set_answer(id, 40)
	game._action("tlx_submit")
	check(game.screen == "title", "after submitting, the player is on the main menu")
	var saved := surveys(session)
	check(saved.size() == 1, "the answers are saved once")
	if saved.size() == 1:
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(saved[0]))
		check(record.source == "leaving_session" and int(record.last_level_number) == 3, "the file says the survey came from leaving after Level 3")

	# Same session again: already answered, so no question.
	finish_level(3)
	if game._tlx_session() == session:
		game._action("results_title")
		check(not game.leave_prompt and game.screen == "title", "a session with a survey is not asked again")

	# YES, then skip: still ends on the main menu.
	game._tlx_submitted_session = ""
	finish_level(3)
	game._action("results_title")
	game._action("leave_tlx_yes")
	game._action("tlx_later")
	check(game.screen == "title" and not game._leaving_after_tlx, "skipping the survey also goes to the main menu")

	# Settings opened from results: its MAIN MENU asks the same question.
	game._tlx_submitted_session = ""
	finish_level(3)
	game._action("results_settings")
	game._action("results_title")
	check(game.screen == "results" and game.leave_prompt, "settings' MAIN MENU returns to results and asks")
	game._action("leave_tlx_no")

	# A co-op player filling in the survey on the way out is not pulled into
	# the host's next level.
	game._leaving_after_tlx = true
	game.screen = "tlx"
	var next_level := RescueSimulation.new()
	next_level.start_shift(4)
	game._receive_snapshot({"screen": "game", "level_run_id": "next_level", "simulation": next_level.net_snapshot(), "waiting_for_briefings": false, "orders": {}, "speed": 1.0})
	check(game.screen == "tlx", "the next level does not interrupt the survey on the way out")
	game._leaving_after_tlx = false

	game._stop_capture()
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: leaving from the results screen asks about the NASA-TLX; YES opens it then the main menu, NO goes straight there")
	quit(0 if failures.is_empty() else 1)
