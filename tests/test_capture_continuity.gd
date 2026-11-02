extends SceneTree

# Mid-term report, Table A4 (playtest 22.10): a guest's level 6 capture "ended
# itself at 97 s and restarted with the clock set back 1.3 s". Guests run the
# simulation between snapshots, so after a host/server stall the next snapshot
# is behind the guest's own clock. That must be a clock correction inside the
# same level capture, never a new level, and the logged clock must not go back.
# Run: godot --headless --path . -s tests/test_capture_continuity.gd
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func snapshot(run_id: String, index: int, elapsed: float) -> Dictionary:
	var simulation := RescueSimulation.new()
	simulation.start_shift(index)
	simulation.elapsed = elapsed
	return {"screen": "game", "level_run_id": run_id, "simulation": simulation.net_snapshot(),
		"waiting_for_briefings": false, "orders": {}, "speed": 1.0}

func records(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for line: String in FileAccess.get_file_as_string(path).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary: result.append(parsed)
	return result

func run() -> void:
	var game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.research_enabled = true
	game.collection_choice_made = true
	game.voice_choice_made = true
	game.network.active = true
	game.network.hosting = false
	game.network.dedicated = true # a study session on the dedicated server
	game.network.roster = {1: 0}

	game._receive_snapshot(snapshot("level6_run", 5, 95.0))
	var session_path: String = game.research.log_path
	var level_path: String = game.research.get_level_context().log_path
	check(game.capture_run_id == "level6_run", "Guest capture starts on the host's run ID")
	# The guest keeps simulating while no snapshot arrives (server stall).
	game.sim.tick(2.0)
	game.research.set_clock(game.sim.elapsed, game.sim.shift_index)
	game.research.log_event("probe", {"note": "guest ran ahead"})
	# The next snapshot is 1.3 s behind the guest's clock.
	game._receive_snapshot(snapshot("level6_run", 5, game.sim.elapsed - 1.3))
	check(game.capture_run_id == "level6_run", "A clock correction keeps the same level capture")
	check(game.entry_popup.is_empty(), "No level-entry prompt appears during play")
	check(game.research.get_level_context().log_path == level_path, "Same level file after the correction")
	game.research.log_event("probe", {"note": "after correction"})
	# A genuinely new level (new run ID) still starts a new capture.
	game._on_remote_event({"type": "level_transition", "previous_level_run_id": "level6_run", "level_run_id": "level6_retry", "level_index": 5})
	game._receive_snapshot(snapshot("level6_retry", 5, 0.0))
	check(game.capture_run_id == "level6_retry", "A new run ID starts a new level capture")
	game._stop_capture()
	check(FileAccess.file_exists(session_path), "The session leader keeps its log on this computer")
	check(game.relay.pending_bytes() == 0, "The leader sends nothing anywhere")

	var rows := records(session_path)
	var level_starts := 0
	var changed := 0
	var corrections := 0
	var last := -1.0
	var monotonic := true
	for row: Dictionary in rows:
		if str(row.get("level_run_id", "")) != "level6_run": continue
		if row.event == "level_started": level_starts += 1
		if row.event == "level_ended" and str(row.data.get("reason", "")) == "changed_level": changed += 1
		if row.event == "clock_correction": corrections += 1
		var t := float(row.get("level_elapsed_s", 0.0))
		if t + 0.0001 < last: monotonic = false
		last = maxf(last, t)
		check(row.has("unix_ms") and int(row.unix_ms) > 1700000000000, "Rows carry millisecond wall-clock time")
	check(level_starts == 1, "One capture segment for the level (found %d starts)" % level_starts)
	check(changed == 1, "The level ends once, when the retry starts (found %d)" % changed)
	check(corrections == 1, "The 1.3 s correction is logged once (found %d)" % corrections)
	check(monotonic, "Logged level clock never moves backwards")
	var display := 0
	for row: Dictionary in rows:
		if row.event == "display" and row.data.has("window_size") and row.data.has("refresh_rate_hz") and row.data.has("embedded_in_editor"): display += 1
	check(display >= 2, "Each level start logs frame rate and window size (found %d)" % display)

	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: guest clock corrections keep one monotonic capture per level; new runs still start new captures")
	quit(0 if failures.is_empty() else 1)
