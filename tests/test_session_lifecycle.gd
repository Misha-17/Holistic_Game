extends SceneTree

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	# Exercise the real game command handler, including ownership checks. The
	# separate ENet suite covers delivery and identity of these remote commands.
	game.network.active = true
	game.network.hosting = true
	game.network.roster = {1: 0, 44: 1}
	for menu in ["pause", "help", "settings"]:
		game._begin_shift(0)
		game.sim._spawn_incident()
		var call: Dictionary = game.sim.incidents.back()
		call.needs = {"medic": 1}
		call.discovered = true
		game.screen = menu
		game.previous_screen = "game"
		game._execute_command("dispatch", {"incident_id": call.id, "kind": "medic"}, 44)
		check(game.sim.successful_dispatches == 1, "Guest dispatch works while host opens " + menu)
		check(game.screen == menu, "Guest dispatch preserves host " + menu)
	# Capture remains one local pair of files across all menus in a shift.
	game.research_enabled = true
	game.voice.set_recording_enabled(true)
	game._begin_shift(0)
	var initial_run: String = game.capture_run_id
	var initial_events: String = game.research.log_path
	var initial_audio: String = game.voice.recording_path
	game._begin_tutorial(false)
	check(not game.tutorial_active, "A shared session cannot enter solo tutorial")
	check(game.capture_run_id == initial_run and game.voice.recording_active, "Rejected tutorial preserves active capture")
	# No transport peer in this unit harness; snapshot handling below still uses
	# the real guest handler, while the ENet suite tests packet transport.
	game.network.active = false
	game.network.hosting = false
	game.sim.elapsed = 10.0
	game.map_zoom = 2.0
	game._center_map(Vector2(.7, .6))
	var menu_pan: Vector2 = game.map_pan
	var payload: Dictionary = {"screen": "game", "simulation": game.sim.net_snapshot(), "orders": {}, "speed": 1.0}
	for menu in ["pause", "help", "settings"]:
		game.screen = menu
		game.previous_screen = "game"
		game._receive_snapshot(payload)
		game._sync_capture()
		check(game.screen == menu, "Host snapshots preserve guest " + menu)
		check(game.map_zoom == 2.0 and game.map_pan == menu_pan, "Routine snapshots preserve the player's camera")
		check(game.capture_run_id == initial_run and game.research.log_path == initial_events and game.voice.recording_path == initial_audio, "Menu does not split recording files: " + menu)
	# Replaying the same shift has the same timeline but fresh local files.
	game.sim.elapsed = 120.0
	game.map_zoom = game._fit_map_zoom()
	game._center_map(Vector2(.5, .5))
	var replay = load("res://scripts/simulation.gd").new()
	replay.start_shift(0)
	game._receive_snapshot({"screen": "game", "simulation": replay.net_snapshot()})
	game._sync_capture()
	check(game.map_zoom == game.MAP_SCALE, "A replay resets the guest to the movable exploration view")
	check(game.capture_run_id != initial_run, "Same-shift replay creates a fresh capture run")
	check(game.research.log_path != initial_events and game.voice.recording_path != initial_audio, "Replay cannot overwrite previous local files")
	check(FileAccess.get_file_as_string(initial_events).contains("capture_stopped"), "Previous input file finalized on replay")
	var second_events: String = game.research.log_path
	var second_audio: String = game.voice.recording_path
	game._network_ended()
	check(game.screen == "lobby", "Disconnect returns player to lobby")
	check(game.capture_run_id == "" and not game.research.enabled and not game.voice.recording_active, "Disconnect stops both local captures")
	check(FileAccess.get_file_as_string(second_events).contains("capture_stopped"), "Disconnect flushes the final input file")
	check(FileAccess.file_exists(second_audio), "Disconnect leaves a finalized local audio file")
	game.network.active = false
	game.network.hosting = false
	game.map_zoom = 3.0
	game.map_pan = Vector2(-200, -300)
	game._apply_map_layout()
	var saved_pan: Vector2 = game.map_pan
	game._begin_tutorial(false)
	check(is_equal_approx(game.map_zoom, game._fit_map_zoom()), "Tutorial starts with the full map in view")
	game._end_tutorial(false, false)
	check(game.map_zoom == 3.0 and game.map_pan == saved_pan, "Tutorial restores the previous map camera")
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: guest commands during host menus, snapshot menu preservation, rejected tutorial, replay and disconnect capture lifecycle")
	else:
		for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
