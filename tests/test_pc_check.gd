extends SceneTree

# Study PC check (Settings > Research, Andrei 30.10): measures frame rate,
# window and scaling, and the microphone, shows pass/check/fix lines and saves
# a JSON file the researcher can collect.
# Run: godot --headless --path . -s tests/test_pc_check.gd
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.screen = "settings"
	game.settings_tab = "research"
	game._action("pc_check_run")
	check(game.settings_tab == "pc_check" and game._pc_check_running(), "The button starts the check on its own page")
	game._pc_check_started_ms -= int(game.PC_CHECK_SECONDS * 1000.0) + 10
	game._tick_pc_check(1.0 / 60.0)
	var result: Dictionary = game.pc_check
	check(not result.is_empty() and not game._pc_check_running(), "The check finishes after the measuring time")
	var ids: Array = []
	for line: Dictionary in result.get("lines", []):
		ids.append(line.id)
		check(str(line.status) in ["pass", "warn", "fail"], "Line %s has a status" % line.id)
	check(ids == ["window", "scaling", "frame_rate", "microphone", "recording"], "All five checks are reported: %s" % [ids])
	check(str(result.get("overall", "")) in ["pass", "warn", "fail"] and result.has("fps_measured") and result.display.has("window_size"), "Overall verdict, fps and display info are stored")
	check(str(result.lines[3].value) == "Voice chat is off" and str(result.lines[3].status) == "warn", "Microphone line explains when voice chat is off")
	var path: String = game._save_pc_check()
	check(path.begins_with("user://research/pc_checks/") and FileAccess.file_exists(path), "The result is saved for the researcher")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved is Dictionary and saved.schema == "beacon-bay-pc-check-v1" and saved.display.window_size is Array, "Saved file is valid JSON")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.settings_tab = "research"
	game._tick_pc_check(0.016)
	check(not game._pc_check_running(), "Leaving the page stops the check")
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: study PC check reports window, scaling, frame rate, microphone and recording, and saves a file")
	quit(0 if failures.is_empty() else 1)
