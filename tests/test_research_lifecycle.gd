extends SceneTree

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func records(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for line: String in FileAccess.get_file_as_string(path).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary: result.append(parsed)
		else: check(false, "All flushed records are valid JSON")
	return result

func run() -> void:
	var logger := ResearchLogger.new()
	root.add_child(logger)
	logger.log_click(Vector2.ONE)
	logger.log_event("incident_started", {"incident_id": 1})
	check(logger.log_path.is_empty(), "No files or session are created before consent")
	var identity := "test_research_%d" % Time.get_ticks_usec()
	logger.begin_session(identity, {"peer_id": 22, "departments": ["engineer"], "role": "engineer", "player_name": "PRIVATE"})
	var path := logger.log_path
	logger.begin_level(6, {"level_number": 0, "level_name": "Practice"}, "practice_attempt")
	var practice_path := str(logger.get_level_context().log_path)
	logger.set_clock(12.0, 6)
	logger.log_event("road_event_started", {"road_event_id": 3, "event_type": "blackout", "clear_kind": "engineer", "started_at": 10.0})
	logger.log_pointer(Vector2(100, 200), Vector2(3, 4))
	logger.log_click(Vector2(100, 200))
	logger.set_clock(16.0, 6)
	logger.log_event("road_cleared", {"road_event_id": 3})
	logger.log_event("road_event_cleared", {"road_event_id": 3, "event_type": "blackout", "ended_at": 15.0, "solved": true, "outcome": "resolved", "actor_peer": 44})
	logger.log_event("road_event_ended", {"road_event_id": 3, "ended_at": 15.0, "solved": true, "outcome": "resolved"})
	logger.log_event("road_event_started", {"road_event_id": 4, "event_type": "blackout", "clear_kind": "engineer", "started_at": 16.0})
	logger.set_clock(18.0, 6)
	logger.log_event("road_event_expired", {"road_event_id": 4, "ended_at": 18.0, "solved": false, "outcome": "expired_unsolved"})
	logger.log_event("road_event_started", {"road_event_id": 5, "event_type": "sandstorm", "clear_kind": "", "started_at": 18.0})
	logger.log_event("road_event_expired", {"road_event_id": 5, "ended_at": 20.0, "solved": null, "outcome": "elapsed"})
	logger.set_clock(20.0, 6)
	logger.log_event("disruption", {"event_id": "disruption_0", "disruption": "market", "started_at": 19.0, "solvable": false})
	logger.log_event("disruption_end", {"event_id": "disruption_0", "ended_at": 20.0, "solved": null, "outcome": "elapsed"})
	logger.log_event("disruption", {"event_id": "disruption_1", "disruption": "market", "started_at": 20.0, "solvable": false})
	logger.log_event("disruption_end", {"event_id": "disruption_1", "ended_at": 20.0, "solved": null, "outcome": "elapsed"})
	logger.set_enabled(false)
	var disabled_length := FileAccess.get_file_as_string(path).length()
	logger.log_click(Vector2(333, 333))
	logger.log_event("must_not_be_captured", {})
	check(FileAccess.get_file_as_string(path).length() == disabled_length, "Disabled input and events never reach disk")
	logger.set_clock(30.0, 6)
	logger.begin_session(identity, {})
	logger.begin_level(6, {"level_number": 0}, "practice_attempt")
	check(logger.session_id == identity and logger.log_path == path, "Consent resumes the same whole-session timeline")
	check(int(logger.get_level_context().level_attempt) == 1, "Re-enabling capture does not invent a retry")
	logger.observe_state({"elapsed": 30.0, "road_events": [{"id": 6, "type": "blackout", "clear_kind": "engineer", "started_at": 25.0, "status": "active"}],
		"incidents": [{"id": 1, "created_at": 22.0, "resolved_at": -1.0, "status": "active", "needs": {"medic": 1}}]})
	logger.log_click(Vector2(444, 444))
	logger.set_clock(150.0, 6)
	logger.end_level("completed", {"won": true})
	logger.begin_level(0, {"level_number": 1, "level_name": "First Light"}, "first_attempt")
	var first_path := str(logger.get_level_context().log_path)
	logger.set_clock(5.0, 0)
	logger.log_click(Vector2(555, 555))
	logger.end_level("restart")
	logger.begin_level(0, {"level_number": 1}, "retry_attempt")
	check(int(logger.get_level_context().level_attempt) == 2, "Retry receives its own attempt number")
	logger.set_clock(2.0, 0)
	logger.log_click(Vector2(666, 666))
	logger.end_level("abandoned")
	logger.set_enabled(false)
	var all := records(path)
	var ends: Dictionary = {}
	var mouse_count := 0
	var previous_seq := 0
	var started_count := 0
	var resumed_count := 0
	var seen_retry := false
	for record: Dictionary in all:
		check(int(record.sequence) == previous_seq + 1, "Session sequence is continuous through consent gaps and level changes")
		previous_seq = int(record.sequence)
		check(str(record.capture_session_id) == identity, "All records share one session identifier")
		check(not JSON.stringify(record).contains("PRIVATE"), "Personal player metadata is excluded")
		if record.event == "level_started": started_count += 1
		if record.event == "capture_resumed":
			resumed_count += 1
			check(float(record.data.gap_level_start_s) == 20.0 and float(record.data.gap_level_end_s) == 30.0, "Consent gap is explicit")
		if record.event == "event_ended":
			var key := str(record.data.event_instance_id)
			check(not ends.has(key), "Each tracked event has exactly one normalized end")
			ends[key] = record.data
		if record.event == "mouse_button":
			mouse_count += 1
			check(record.peer_id == 22 and record.departments == ["engineer"], "Input carries local participant and role")
			if record.data.x == 100:
				check(record.level_number == 0 and record.level_index == 6, "Practice level display and simulation indices stay distinct")
				check(record.active_event_ids.has("practice_attempt/road:3"), "Input is correlated with active blackout")
				check(float(record.session_elapsed_s) == 12.0, "Practice does not inherit the old index-times-330 clock")
			if record.data.x == 444: check(record.data.inter_click_ms == null, "Inter-click timing resets across disabled capture")
			if record.data.x == 555: check(float(record.session_elapsed_s) == 155.0, "Session time adds the actual short practice duration")
			if record.data.x == 666:
				seen_retry = true
				check(record.level_run_id == "retry_attempt" and float(record.session_elapsed_s) == 157.0, "Retries have separate identity and continuous game time")
	check(mouse_count == 4 and started_count == 3 and resumed_count == 1 and seen_retry, "No duplicated or missing captured levels or clicks")
	check(ends.get("practice_attempt/road:3", {}).get("solved") == true, "Blackout resolution is explicit")
	check(float(ends.get("practice_attempt/road:3", {}).get("duration_s", -1)) == 5.0, "Event duration uses authoritative source timestamps")
	check(ends.get("practice_attempt/road:4", {}).get("outcome") == "expired_unsolved", "Expired solvable events are distinguished from successful repairs")
	check(ends.get("practice_attempt/road:5", {}).get("solved") == null, "Passive weather is not falsely treated as a failed task")
	check(ends.get("practice_attempt/road:6", {}).get("outcome") == "level_ended_unsolved", "Unfinished blackout receives a level-end outcome")
	check(ends.get("practice_attempt/incident:1", {}).get("solved") == false, "Unfinished observed incident receives an outcome")
	check(ends.has("practice_attempt/disruption:disruption_0") and ends.has("practice_attempt/disruption:disruption_1"), "Repeated disruptions retain distinct correlation IDs")
	for record: Dictionary in records(practice_path): check(record.level_run_id == "practice_attempt", "Practice file contains only that attempt")
	for record: Dictionary in records(first_path): check(record.level_run_id == "first_attempt", "Level file cannot mix retries or practice input")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.get_base_dir().path_join("manifest.json")))
	check(manifest.level_files.size() == 3 and bool(manifest.level_files_mirror_session_events), "Manifest indexes level artifacts and declares mirrored rows")
	# Exercise the actual encoded save format, not just plain synthetic dictionaries.
	var simulation := RescueSimulation.new()
	simulation.start_shift(0)
	logger.begin_session("test_snapshot_%d" % Time.get_ticks_usec())
	logger.begin_level(0, {}, "saved_state")
	logger.observe_state(simulation.snapshot())
	check(logger.enabled, "Encoded simulation snapshots can be observed without corrupting capture")
	logger.end_level("test_complete", {}, simulation.snapshot())
	logger.begin_level(6, {"level_number": 0}, "midlevel_flood")
	logger.observe_state({"shift_index": 6, "elapsed": 120.0, "incidents": [{"id": 99, "created_at": 119.0, "status": "active"}]})
	logger.log_click(Vector2(777, 777))
	logger.observe_state({"shift_index": 6, "elapsed": 140.0, "incidents": [], "road_events": [{"id": 88, "started_at": 145.0, "type": "blackout", "clear_kind": "engineer", "status": "active"}]})
	logger.end_level("completed")
	logger.set_enabled(false)
	var saw_flood := false
	var ended_flood := false
	var censored_incident := false
	for record: Dictionary in records(logger.log_path):
		if record.event == "mouse_button" and record.data.x == 777:
			saw_flood = record.active_event_ids.has("midlevel_flood/bridge:bridge_4_114.000")
		if record.event == "event_ended" and str(record.data.event_instance_id).contains("bridge_4_114.000"):
			ended_flood = record.data.outcome == "elapsed" and record.data.solved == null
		if record.event == "event_ended" and str(record.data.event_instance_id) == "midlevel_flood/incident:99":
			censored_incident = bool(record.data.get("censored", false)) and record.data.solved == null
		check(not str(record.data.get("event_instance_id", "")).ends_with("road:88"), "Future scheduled events are not observed prematurely")
	check(saw_flood and ended_flood, "Joining mid-flood observes its active interval and passive ending")
	check(censored_incident, "Disappeared incidents have unknown outcomes rather than invented failures")
	logger.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: research consent gaps, level attempts, contextual input, event outcomes, snapshots and session clocks")
	else:
		for failure: String in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
