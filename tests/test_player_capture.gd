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
	game.research_enabled = true
	game._begin_shift(0)
	game._process_events()
	var log_path: String = game.research.log_path
	check(game.research.enabled, "Local logging starts in a real shift")
	check(not game.voice.mic_enabled and not game.voice.recording_enabled, "Audio defaults remain explicit opt-ins")
	var before_ticker: String = game.ticker
	var before_toast: String = game.toast_text
	game._handle_game_event({"type": "chaos_phase_changed", "research_only": true, "phase": "high", "at": 45.0, "text": ""})
	check(game.ticker == before_ticker and game.toast_text == before_toast, "Hidden phases cannot become UI messages")
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP]:
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			event.position = Vector2(1550, 600)
			event.pressed = pressed
			game._input(event)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(900, 500)
	move.relative = Vector2(11, -7)
	game._input(move)
	# Game events from peers must not create local mouse records.
	game._handle_game_event({"type": "dispatch", "actor_peer": 44, "incident_id": 1})
	game._stop_capture()
	var counts := {}
	var buttons: Array[int] = []
	var seq := 0
	for line in FileAccess.get_file_as_string(log_path).split("\n", false):
		var record: Dictionary = JSON.parse_string(line)
		check(int(record.sequence) == seq + 1, "Monotonic event sequence")
		seq += 1
		counts[record.event] = int(counts.get(record.event, 0)) + 1
		check(record.has("shift_elapsed_s") and record.has("local_elapsed_us"), "Capture has game and monotonic timestamps")
		if record.event == "mouse_button": buttons.append(int(record.data.button))
	check(int(counts.get("mouse_button", 0)) == 8, "All mouse buttons down/up are logged exactly once")
	check(int(counts.get("mouse_motion", 0)) == 1, "Motion is logged once before input is consumed")
	check(buttons.count(MOUSE_BUTTON_RIGHT) == 2, "Right-click is not lost to selection clearing")
	check(int(counts.get("chaos_phase_changed", 0)) >= 1, "Phases are in local research logs")
	game._begin_tutorial(false)
	game._sync_capture()
	check(not game.research.enabled, "Tutorial input never starts capture")
	game._end_tutorial(false, false)
	game._begin_shift(0)
	game.network.active = true
	game.network.hosting = true
	game._action("pause")
	check(game._simulation_active(), "Opening a multiplayer menu does not pause the shared timeline")
	game.network.active = false
	check(not game._simulation_active(), "Solo pause freezes active elapsed time")
	game._action("unpause")
	game.map_zoom = 3.0
	game.map_pan = Vector2(99999, -99999)
	game._apply_map_layout()
	check(game._map_rect().has_point(Vector2(720, 400)), "Panning cannot lose the town outside the viewport")
	game._stop_capture()
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: player input, local capture lifecycle, hidden phases, menus and camera")
	else:
		for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
