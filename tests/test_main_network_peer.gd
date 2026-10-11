extends SceneTree
var finish_path := ""
var done_path := ""
var game: Node
var failures: Array[String] = []
func _initialize() -> void:
	var directory := "user://main-network-qa"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-dir="): directory = argument.trim_prefix("--qa-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	finish_path = directory.path_join("finish.signal")
	done_path = directory.path_join("done.signal")
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func wait_for(predicate: Callable, label: String, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(.05).timeout
	failures.append("Timed out: " + label)
	return false
func signal_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("ready")
	file.close()
func run() -> void:
	game = load("res://scripts/main.gd").new()
	game.name = "BeaconGame"
	game.test_mode = true
	root.add_child(game)
	if game.dedicated_server:
		var deadline := Time.get_ticks_msec() + 40000
		var finished := false
		while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(done_path):
			if not finished and FileAccess.file_exists(finish_path) and game.sim.running:
				finished = true
				game.sim.tick(330)
			await create_timer(.05).timeout
		check(FileAccess.file_exists(done_path), "Client completed full session lifecycle")
		game.network.close()
		await create_timer(.2).timeout
		if failures.is_empty(): print("PASS: dedicated main server completed replay harness")
		else:
			for failure in failures: printerr("FAIL: ", failure)
		quit(0 if failures.is_empty() else 1)
		return
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.screen = "lobby"
	game.research_enabled = true
	game.voice.set_recording_enabled(true)
	game.network.join("127.0.0.1:%d" % game.network.port)
	if not await wait_for(func(): return game.network.roster.size() == 1, "server lobby handshake"):
		finish()
		return
	check(game.network.can_start_session(), "First dedicated player can start")
	game._action("host_start")
	if not await wait_for(func(): return game.screen == "game" and game.capture_run_id != "", "first shared shift and local capture"):
		finish()
		return
	var first_run: String = game.capture_run_id
	var first_audio: String = game.voice.recording_path
	for menu in ["pause", "help", "settings"]:
		game.screen = menu
		game.previous_screen = "game"
		var before: float = game.sim.elapsed
		await create_timer(.65).timeout
		check(game.screen == menu, "Network snapshot preserves actual guest " + menu)
		check(game.sim.elapsed > before + .3, "Shared timeline advances during guest " + menu)
		check(game.capture_run_id == first_run, "Guest menu keeps current capture")
	game.screen = "game"
	signal_file(finish_path)
	if not await wait_for(func(): return game.screen == "results" and game.capture_run_id == "", "results and finalized capture"):
		finish()
		return
	check(FileAccess.file_exists(first_audio), "First session local WAV exists")
	game._action("host_start")
	if not await wait_for(func(): return game.screen == "game" and game.capture_run_id != "", "same-shift replay"):
		finish()
		return
	check(game.capture_run_id != first_run, "Replay uses new recording run")
	check(game.voice.recording_path != first_audio, "Replay uses new WAV path")
	var second_events: String = game.research.log_path
	signal_file(done_path)
	await wait_for(func(): return game.screen == "lobby" and not game.network.active, "server disconnect", 10.0)
	check(not game.research.enabled and not game.voice.recording_active, "Disconnect closes player capture")
	check(FileAccess.get_file_as_string(second_events).contains("capture_stopped"), "Disconnected mouse log flushes")
	finish()
func finish() -> void:
	game._stop_capture()
	game.voice.shutdown()
	if failures.is_empty(): print("PASS: real main client/server lobby, start, menus, results, replay, recording lifecycle and disconnect")
	else:
		for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
