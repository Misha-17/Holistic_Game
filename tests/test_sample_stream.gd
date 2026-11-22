extends SceneTree

## Fixed-rate sample stream and task-load variables (client feedback 01.11).
## Run: godot --headless --path . --script tests/test_sample_stream.gd

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_test_task_load()
	await _test_stream()
	if failures.is_empty(): print("PASS: 60 Hz sample stream on a fixed grid, task load per player, crew selection events")
	else:
		for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func _test_task_load() -> void:
	var sim := RescueSimulation.new()
	sim.start_shift(4)
	sim.incidents.clear()
	sim.road_events.clear()
	var medic_ids: Array[int] = []
	for unit: Dictionary in sim.units:
		if str(unit.kind) == "medic": medic_ids.append(int(unit.id))
	# 1: needs medic, nobody sent -> pending (urgent). 2: needs medic, one sent -> dispatched.
	# 3: fire only -> not needed. 4: needs medic but unconfirmed -> pending, not known.
	sim.incidents.append({"id": 1, "kind": "medical", "status": "active", "discovered": true, "deadline": 12.0, "needs": {"medic": 1, "fire": 1}, "assigned": [], "created_at": 0.0})
	sim.incidents.append({"id": 2, "kind": "medical", "status": "working", "discovered": true, "deadline": 40.0, "needs": {"medic": 1}, "assigned": [medic_ids[0]], "created_at": 0.0})
	sim.incidents.append({"id": 3, "kind": "fire", "status": "active", "discovered": true, "deadline": 30.0, "needs": {"fire": 1}, "assigned": [], "created_at": 0.0, "critical_sent": true})
	sim.incidents.append({"id": 4, "kind": "medical", "status": "active", "discovered": false, "deadline": 35.0, "needs": {"medic": 1}, "assigned": [], "created_at": 0.0})
	sim.incidents.append({"id": 5, "kind": "fire", "status": "resolved", "discovered": true, "deadline": 0.0, "needs": {"medic": 1}, "assigned": [], "created_at": 0.0})
	var load := BeaconTaskLoad.compute(sim, ["medic"])
	check(int(load.active_incidents) == 4, "Only active and working calls count")
	check(int(load.own_needed) == 3 and int(load.own_not_needed) == 1, "Own unit needed vs not needed")
	check(int(load.own_dispatched) == 1 and int(load.own_pending) == 2, "Own unit dispatched vs decision pending")
	check(int(load.own_pending_known) == 1 and int(load.own_needed_known) == 2, "Unconfirmed calls do not count as known needs")
	check(int(load.own_pending_urgent) == 1 and is_equal_approx(float(load.own_min_deadline_s), 12.0), "Urgent pending own call and its deadline")
	check(int(load.critical) == 1 and int(load.unconfirmed) == 1, "Critical and unconfirmed counts")
	check(int(load.other_pending) == 2, "Calls still waiting for other departments")
	var calls := BeaconTaskLoad.incidents(sim, ["medic"])
	check(calls.size() == 4 and str(calls[0].own_state) == "pending" and str(calls[1].own_state) == "dispatched" and str(calls[2].own_state) == "not_needed", "Per-call own state")
	var fire_load := BeaconTaskLoad.compute(sim, ["fire", "medic"])
	check(int(fire_load.own_not_needed) == 0 and int(fire_load.own_needed) == 4, "A player with several departments owns all of them")

func _test_stream() -> void:
	var game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.research_enabled = true
	game._begin_shift(4)
	game._process_events()
	check(game.research.sampler != null and game.research.sampler.is_running(), "The sampler starts with the level")
	var samples_path: String = game.research.get_level_context().get("samples_path", "")
	check(samples_path.ends_with("_mouse-and-taskload-60hz.csv"), "The manifest names the level's sample file")
	game.research.sampler.set_test_cursor(Vector2(300, 200))
	var started := Time.get_ticks_msec()
	var first_unit := -1
	for unit: Dictionary in game.sim.units:
		if game.network.owns(str(unit.kind)) and str(unit.state) == "idle":
			first_unit = int(unit.id)
			break
	while Time.get_ticks_msec() - started < 700:
		game.sim.tick(1.0 / 60.0)
		await process_frame
	game._select_unit(first_unit)
	game._select_unit(first_unit)
	while Time.get_ticks_msec() - started < 1000:
		await process_frame
	var log_path: String = game.research.log_path
	game._stop_capture()
	var rows := FileAccess.get_file_as_string(samples_path).split("\n", false)
	var header := rows[0].split(",")
	check(Array(header) == ResearchSampler.columns(), "CSV header lists every column")
	var data_rows := rows.size() - 1
	check(data_rows >= 50 and data_rows <= 66, "About 60 rows per second (got %d in ~1 s)" % data_rows)
	var col := {}
	for i in header.size(): col[header[i]] = i
	var previous_us := -1
	var spacing_ok := true
	var index_ok := true
	var load_ok := true
	var cursor_ok := true
	for i in range(1, rows.size()):
		var v := rows[i].split(",")
		if v.size() != header.size():
			check(false, "Row %d has every column" % i)
			continue
		if int(v[col.sample]) != i - 1: index_ok = false
		var t := int(v[col.local_elapsed_us])
		if previous_us >= 0 and absi(t - previous_us - 16667) > 1: spacing_ok = false
		previous_us = t
		if int(v[col.own_needed]) + int(v[col.own_not_needed]) != int(v[col.active_incidents]): load_ok = false
		if int(v[col.own_dispatched]) + int(v[col.own_pending]) != int(v[col.own_needed]): load_ok = false
		if int(v[col.held]) == 0 and float(v[col.x]) < 0.0: cursor_ok = false
	check(index_ok, "Sample index has no gaps")
	check(spacing_ok, "Scheduled times sit on a fixed 16.667 ms grid")
	check(load_ok, "Needed + not needed = active; dispatched + pending = needed")
	check(cursor_ok, "Every read slot has a cursor position")
	var events := {}
	for line in FileAccess.get_file_as_string(log_path).split("\n", false):
		var record: Dictionary = JSON.parse_string(line)
		check(int(record.schema) == 4, "Rows use schema 4")
		events[record.event] = int(events.get(record.event, 0)) + 1
	check(int(events.get("sampler_started", 0)) == 1 and int(events.get("sampler_stopped", 0)) == 1, "Sampler start and stop are logged")
	check(int(events.get("crew_selected", 0)) == 1 and int(events.get("crew_deselected", 0)) == 1, "Crew selection and deselection are logged")
	game.voice.shutdown()
	game.queue_free()
	await process_frame
