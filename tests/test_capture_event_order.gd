extends SceneTree

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func snapshot(run_id: String, index: int, elapsed: float, finished: bool = false) -> Dictionary:
	var simulation := RescueSimulation.new()
	simulation.start_shift(index)
	simulation.elapsed = elapsed
	simulation.running = not finished
	simulation.finished = finished
	simulation.won = finished
	return {"screen": "results" if finished else "game", "level_run_id": run_id,
		"simulation": simulation.net_snapshot(), "waiting_for_briefings": false, "orders": {}, "speed": 1.0}

func road_event(run_id: String, ended: bool, solved: bool = true) -> Dictionary:
	return {"type": "road_event_ended" if ended else "road_event_started", "research_only": true,
		"level_run_id": run_id, "road_event_id": 11, "event_type": "blackout", "clear_kind": "engineer",
		"started_at": 10.0, "ended_at": 329.0 if ended else -1.0,
		"at": 329.0 if ended else 10.0, "solvable": true,
		"solved": solved if ended else null, "outcome": ("resolved" if solved else "level_ended_unsolved") if ended else "open"}

func completion(run_id: String) -> Dictionary:
	return {"type": "shift_complete", "level_run_id": run_id, "at": 330.0,
		"score": 3141, "rescued": 42, "resolved": 7, "missed": 2, "won": true, "failed_incident_ids": []}

func transition(previous: String, next: String, index: int) -> Dictionary:
	return {"type": "level_transition", "previous_level_run_id": previous, "level_run_id": next, "level_index": index}

func records(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for line: String in FileAccess.get_file_as_string(path).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary: result.append(parsed)
		else: check(false, "Flushed race-test record is valid JSON")
	return result

func run() -> void:
	var game = load("res://scripts/main.gd").new()
	game.test_mode = true
	game.music_enabled = false
	game.sfx_enabled = false
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.research_enabled = true
	game.collection_choice_made = true
	game.network.active = true
	game.network.hosting = false
	game.network.roster = {1: 0}
	# Exercise the real guest handlers deterministically. The separate network
	# suite covers ENet transport; these calls force cross-channel packet order.
	game._receive_snapshot(snapshot("race_a", 3, 328.0))
	var log_path: String = game.research.log_path
	var a_path: String = game.research.get_level_context().log_path
	game._on_remote_event(road_event("race_a", false))
	var a_results := snapshot("race_a", 3, 330.0, true)
	game._receive_snapshot(a_results)
	check(game.capture_run_id == "race_a" and game.screen == "game", "Results snapshot waits for its reliable terminal events")
	check(not game._pending_results_snapshot.is_empty() and game.research.enabled, "Premature results keep the current research file open")
	# A guest can also finish its prediction before the host's ending arrives.
	game.sim.elapsed = 330.0
	game.sim.finished = true
	game.sim.running = false
	game._sync_capture()
	check(game.research.enabled and game.capture_run_id == "race_a", "Predicted completion cannot close the authoritative event stream")
	game._on_remote_event(road_event("race_a", true))
	game._on_remote_event(completion("race_a"))
	check(game.screen == "results" and game.capture_run_id.is_empty(), "Reliable completion applies the waiting results snapshot")
	check(game._pending_results_snapshot.is_empty() and not game.research.enabled, "Terminal application flushes and closes exactly once")
	# Next-level state can overtake both the previous ending and the transition
	# marker. Reused road IDs must still be attributed to the correct attempt.
	game._on_remote_event(transition("race_a", "race_b", 3))
	game._receive_snapshot(snapshot("race_b", 3, 328.0))
	var b_path: String = game.research.get_level_context().log_path
	game._on_remote_event(road_event("race_b", false))
	game._receive_snapshot(snapshot("race_c", 4, 0.0))
	check(game.capture_run_id == "race_b" and game.sim.shift_index == 3, "Next-run snapshot cannot overtake the reliable transition marker")
	check(str(game._pending_transition_snapshot.get("level_run_id", "")) == "race_c", "Next-run snapshot is retained for the transition")
	game._on_remote_event(road_event("race_b", true, false))
	game._on_remote_event(completion("race_b"))
	check(game.capture_run_id == "race_b", "Previous run remains writable until its transition marker arrives")
	game._on_remote_event(transition("race_b", "race_c", 4))
	check(game.capture_run_id == "race_c" and game.sim.shift_index == 4, "Marker releases its buffered next-run snapshot")
	check(game._pending_transition_snapshot.is_empty(), "Applied next-run snapshot is removed from the buffer")
	check(game.research.log_path == log_path, "Cross-channel transitions retain one whole-session timeline")
	var c_path: String = game.research.get_level_context().log_path
	game._on_remote_event(road_event("race_c", false))
	# Recreate an old result left in a buffer. The current run's completion must
	# never apply a result whose identity belongs to another run.
	game._pending_results_snapshot = a_results.duplicate(true)
	game._on_remote_event(road_event("race_c", true))
	game._on_remote_event(completion("race_c"))
	check(game.capture_run_id == "race_c" and game.sim.shift_index == 4 and game.screen == "game", "Stale buffered results cannot rewind a later run")
	game._on_remote_event(transition("race_c", "race_d", 5))
	# New-run events may arrive after the marker but before that run's snapshot.
	game._on_remote_event(road_event("race_d", false))
	check(not game._pending_level_events.is_empty(), "New-run event waits for the matching simulation snapshot")
	game._receive_snapshot(snapshot("race_d", 5, 12.0))
	check(game._pending_results_snapshot.is_empty(), "Changing run clears stale pending results")
	check(game.capture_run_id == "race_d" and game._pending_level_events.is_empty(), "Matching snapshot replays queued events into the new level")
	game._on_remote_event(road_event("race_d", true))
	game._on_remote_event(completion("race_d"))
	game._receive_snapshot(snapshot("race_d", 5, 330.0, true))
	game._stop_capture()
	var endings: Dictionary = {}
	var level_ends: Dictionary = {}
	var raw_ends: Dictionary = {}
	for record: Dictionary in records(log_path):
		var run_id := str(record.get("level_run_id", ""))
		if record.event == "event_ended" and int(record.data.get("road_event_id", -1)) == 11:
			check(not endings.has(run_id), "Each reused road ID has one ending within its level attempt")
			endings[run_id] = record
			check(str(record.data.event_instance_id) == run_id + "/road:11", "Lifecycle correlation matches the containing level file")
		if record.event == "road_event_ended": raw_ends[run_id] = int(record.sequence)
		if record.event == "level_ended":
			level_ends[run_id] = int(record.sequence)
			check(float(record.level_elapsed_s) == 330.0, "Level cutoff clock uses the authoritative completion time, not guest prediction")
			check(int(record.data.summary.get("score", -1)) == 3141 and int(record.data.summary.get("rescued", -1)) == 42, "Final totals survive a next-run snapshot overtaking results")
	for run_id: String in ["race_a", "race_b", "race_c", "race_d"]:
		check(endings.has(run_id), "Terminal road event survives packet ordering for " + run_id)
		check(int(raw_ends.get(run_id, -1)) > 0 and int(raw_ends.get(run_id, -1)) < int(level_ends.get(run_id, -1)), "Authoritative ending is saved before level finalization for " + run_id)
		if endings.has(run_id):
			check(float(endings[run_id].data.ended_at) == 329.0, "Source end time survives guest prediction and snapshot timing")
	check(endings.get("race_a", {}).get("data", {}).get("solved") == true, "Successful old-run repair is not lost to early results")
	check(endings.get("race_b", {}).get("data", {}).get("outcome") == "level_ended_unsolved", "Unresolved old-run cutoff is not rewritten as a new-run event")
	for artifact: Dictionary in [{"path": a_path, "run": "race_a"}, {"path": b_path, "run": "race_b"}, {"path": c_path, "run": "race_c"}]:
		for record: Dictionary in records(artifact.path): check(record.level_run_id == artifact.run, "Level artifacts remain isolated across out-of-order transport")
	game.network.active = false
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: terminal snapshots, transition markers, queued lifecycle events and stale-result isolation")
	else:
		for failure: String in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
