extends SceneTree

# NASA-TLX (Andrei, 30.10): once after the last level of a session (level 6,
# won or lost) and from the title screen; one file per answer set.
# Run: godot --headless --path . -s tests/test_nasa_tlx.gd
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func finish_level(game, index: int, won: bool) -> void:
	game._begin_shift(index)
	game.entry_popup = ""
	game.sim.elapsed = 330.0
	game.sim.running = false
	game.sim.finished = true
	game.sim.won = won
	game.screen = "results"
	game.results_since = -1.0
	game._process(0.0)
	game.elapsed_ui += game.TLX_DELAY_S + 0.1
	game._process(0.0)

func run() -> void:
	var game = load("res://scripts/main.gd").new()
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.collection_choice_made = true
	game.voice_choice_made = true
	var saved: Array[String] = []
	game.research_file_saved.connect(func(path: String): saved.append(path))

	finish_level(game, 4, true)
	check(game.screen == "results", "Level 5 results do not open the survey")
	finish_level(game, 5, false)
	check(game.screen == "tlx", "A lost level 6 opens the survey after the results")
	check(not game.tlx_form.all_answered(), "No answer is preset")
	game._action("tlx_submit")
	check(game.screen == "tlx" and saved.is_empty(), "Cannot submit before all six are answered")
	var values := {"mental_demand": 85, "physical_demand": 10, "temporal_demand": 90, "performance": 60, "effort": 80, "frustration": 55}
	for id in values: game.tlx_form.set_answer(id, values[id])
	check(game.tlx_form.all_answered(), "All six answered")
	game._action("tlx_submit")
	check(game.screen == "results" and saved.size() == 1, "Submit saves and returns to the results")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(saved[0]))
	check(record.answers.mental_demand == 85 and is_equal_approx(float(record.answers.raw_tlx), 63.33), "Answers and raw TLX saved (%s)" % record.answers.get("raw_tlx"))
	check(record.source == "after_last_level" and int(record.last_level_number) == 6 and record.last_level_won == false, "Context saved")
	check(not str(record.get("capture_session_id", "")).is_empty() and saved[0].contains(str(record.capture_session_id)), "Saved under the session folder")
	for _i in 3: game._process(0.0)
	check(game.screen == "results", "The same results do not reopen the survey")
	# Title button for sessions that end early.
	game._stop_capture()
	game.screen = "title"
	game._action("tlx_title")
	check(game.screen == "tlx" and game.tlx_source == "title_button", "Title button opens the survey")
	game._action("tlx_later")
	check(game.screen == "title", "Back returns to the title")
	game._action("tlx_title")
	for id in values: game.tlx_form.set_answer(id, 50)
	game._action("tlx_submit")
	check(saved.size() == 2, "Survey from the title is saved too")
	var second: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(saved[1]))
	check(second.capture_session_id == record.capture_session_id, "A later survey attaches to the last session")
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: NASA-TLX after the last level and from the title, saved per session")
	quit(0 if failures.is_empty() else 1)
