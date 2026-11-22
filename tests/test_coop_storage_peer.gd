extends SceneTree

# Helper for run_coop_storage_tests.py: one real game process per role.
#   --server  dedicated server (stores nothing)
#   --leader  first player in the room ("Ana")
#   --guest   second player ("Mia Lee"): drops out and rejoins mid-level
# Playtest 2.11: departments must not move when someone reconnects.
# Playtest 07.11: every player stores their own files on their own computer, in
# a date_time_name folder with descriptive file names; the survey on the way out
# is saved there too.
var qa := ""
var role := ""
var game: Node
var failures: Array[String] = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-dir="): qa = argument.trim_prefix("--qa-dir=")
		if argument in ["--server", "--leader", "--guest"]: role = argument.trim_prefix("--")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func mark(name: String) -> void:
	var file := FileAccess.open(qa.path_join(name + ".signal"), FileAccess.WRITE)
	file.store_string("ready")
	file.close()

func marked(name: String) -> bool:
	return FileAccess.file_exists(qa.path_join(name + ".signal"))

func wait_for(predicate: Callable, label: String, seconds: float = 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(.05).timeout
	failures.append("Timed out: " + label)
	return false

func move_mouse(count: int) -> void:
	for i in count:
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(400 + i * 7, 300 + i * 3)
		motion.relative = Vector2(7, 3)
		game._input(motion)
		await create_timer(.02).timeout

func run() -> void:
	game = load("res://scripts/main.gd").new()
	game.name = "BeaconGame"
	game.test_mode = true
	root.add_child(game)
	if role == "server": await run_server()
	elif role == "leader": await run_leader()
	else: await run_guest()
	finish()

func run_server() -> void:
	var finished := false
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline and not marked("done"):
		if not finished and marked("finish") and game.sim.running:
			finished = true
			game.sim.tick(330)
		await create_timer(.05).timeout
	check(marked("done"), "players completed the session")
	game.network.close()
	await create_timer(.2).timeout

## This computer's session folders under research/ (not voice/ or pc_checks/).
func session_folders() -> Array:
	var result: Array = []
	if DirAccess.dir_exists_absolute("user://research"):
		for name in DirAccess.get_directories_at("user://research"):
			if name not in ["voice", "pc_checks"]: result.append(name)
	return result

func level_files(folder: String, suffix: String) -> Array:
	var result: Array = []
	for name in DirAccess.get_files_at(folder):
		if name.ends_with(suffix): result.append(name)
	return result

func run_leader() -> void:
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.screen = "lobby"
	game.research_enabled = true
	game.network.local_player_name = "Ana"
	game.network.join("127.0.0.1:%d" % game.network.port)
	if not await wait_for(func(): return game.network.roster.size() == 1, "leader joins"): return
	mark("leader_joined")
	if not await wait_for(func(): return game.network.roster.size() == 2, "guest joins"): return
	check(game.network.is_leader(), "the first player is the session leader")
	game._action("host_start")
	if not await wait_for(func(): return game.screen == "game" and game.capture_run_id != "", "level starts"): return
	var mine: Array = game.network.departments_for()
	mark("level_started")
	if not await wait_for(func(): return marked("guest_back"), "guest reconnects", 20.0): return
	check(game.network.departments_for() == mine, "the leader's departments never changed")
	await move_mouse(10)
	if not await wait_for(func(): return marked("guest_done"), "guest finished input"): return
	mark("finish")
	if not await wait_for(func(): return game.screen == "results" and game.capture_run_id == "", "results"): return
	await create_timer(.4).timeout
	var folders := session_folders()
	check(folders.size() == 1 and str(folders[0]).ends_with("_Ana"), "the leader has one session folder named after Ana: %s" % [folders])
	if folders.size() == 1:
		var folder: String = "user://research/" + str(folders[0])
		check(level_files(folder, "_events.jsonl").any(func(n): return str(n).begins_with("Ana_level-")), "Ana's level file: %s" % [level_files(folder, "")])
		check(not DirAccess.dir_exists_absolute(folder + "/players"), "no teammates' data on the leader's computer")
	mark("done")
	await wait_for(func(): return not game.network.active, "server closes", 10.0)

func run_guest() -> void:
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.screen = "lobby"
	game.research_enabled = true
	game.network.local_player_name = "Mia Lee"
	if not await wait_for(func(): return marked("leader_joined"), "leader first"): return
	game.network.join("127.0.0.1:%d" % game.network.port)
	if not await wait_for(func(): return game.network.roster.size() == 2, "guest joins"): return
	var key: String = game.network.player_key(game.multiplayer.get_unique_id())
	check(not game.network.is_leader(), "the second player is not the leader")
	if not await wait_for(func(): return game.screen == "game" and game.capture_run_id != "" and marked("level_started"), "level starts"): return
	var mine: Array = game.network.departments_for()
	var first_id: int = game.multiplayer.get_unique_id()
	await move_mouse(12)
	# Bad connection: drop out and rejoin.
	game._leave_network()
	game.screen = "lobby"
	await create_timer(.5).timeout
	game.network.join("127.0.0.1:%d" % game.network.port)
	if not await wait_for(func(): return game.network.roster.size() == 2 and game.screen == "game" and game.capture_run_id != "", "rejoin into the running level"): return
	check(game.multiplayer.get_unique_id() != first_id, "the rejoin has a new network id")
	check(game.network.player_key(game.multiplayer.get_unique_id()) == key, "the host recognises the same player")
	check(game.network.departments_for() == mine, "the guest gets the same departments back")
	mark("guest_back")
	await move_mouse(12)
	await create_timer(1.2).timeout # one logger flush
	mark("guest_done")
	if await wait_for(func(): return game.screen == "results", "results on the guest", 20.0):
		game._action("results_title")
		check(game.leave_prompt, "leaving asks about the survey")
		game._action("leave_tlx_yes")
		for id in ["mental_demand", "physical_demand", "temporal_demand", "performance", "effort", "frustration"]:
			game.tlx_form.set_answer(id, 55)
		game._action("tlx_submit")
		check(game.screen == "title", "after the survey the guest is on the main menu")
	await wait_for(func(): return marked("done"), "leader checked files", 20.0)
	var folders := session_folders()
	check(folders.size() == 1 and str(folders[0]).ends_with("_Mia-Lee"), "the guest has its own session folder named after Mia: %s" % [folders])
	if folders.size() == 1:
		var folder: String = "user://research/" + str(folders[0])
		var names: Array = Array(DirAccess.get_files_at(folder))
		check(names.has("Mia-Lee_level-0_events.jsonl") and names.has("Mia-Lee_level-0_mouse-and-taskload-60hz.csv"), "level events and 60 Hz samples, named after Mia: %s" % [names])
		var events := FileAccess.get_file_as_string(folder + "/Mia-Lee_level-0_events.jsonl")
		check(events.count('"event":"mouse_motion"') >= 20, "mouse rows from before and after the reconnect are in one file (%d)" % events.count('"event":"mouse_motion"'))
		check('"event":"incident_spawned"' in events or '"event":"dispatch"' in events or '"event":"state_observed"' in events, "the guest's file has the game events too")
		check(not names.has("Mia-Lee_level-0_try-2_events.jsonl"), "the reconnect did not start a second try")
		check(names.has("Mia-Lee_nasa-tlx.json"), "the survey from leaving is saved on the guest's computer")
		check(names.has("Mia-Lee_all-levels_events.jsonl") and names.has("Mia-Lee_session-info.json") and names.has(StudyFiles.README_NAME), "session events, info and READ ME")

func finish() -> void:
	if role != "server":
		game._stop_capture()
		game.voice.shutdown()
	if failures.is_empty(): print("PASS: %s - each player stores their own named files, guest reconnects without department changes" % role)
	else:
		for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
