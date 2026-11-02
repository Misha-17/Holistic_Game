extends SceneTree

# Helper for run_leader_storage_tests.py: one real game process per role.
#   --server  dedicated server
#   --leader  first player in the room: the only computer that stores files
#   --guest   second player: drops out and rejoins mid-level, writes nothing locally
# Playtest 2.11: departments must not move when someone reconnects, and the
# guest's own input must end up on the leader's computer.
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

func run_leader() -> void:
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.screen = "lobby"
	game.research_enabled = true
	game.network.join("127.0.0.1:%d" % game.network.port)
	if not await wait_for(func(): return game.network.roster.size() == 1, "leader joins"): return
	mark("leader_joined")
	if not await wait_for(func(): return game.network.roster.size() == 2, "guest joins"): return
	check(game.network.is_leader(), "the first player is the session leader")
	game._action("host_start")
	if not await wait_for(func(): return game.screen == "game" and game.capture_run_id != "", "level starts"): return
	var mine: Array = game.network.departments_for()
	mark("level_started")
	# The guest drops out and comes back; meanwhile the leader keeps playing.
	if not await wait_for(func(): return marked("guest_back"), "guest reconnects", 20.0): return
	check(game.network.departments_for() == mine, "the leader's departments never changed")
	await move_mouse(10)
	if not await wait_for(func(): return marked("guest_done"), "guest finished input"): return
	await create_timer(.6).timeout # let the last relayed rows arrive
	var session: String = game.capture_session_id
	mark("finish")
	if not await wait_for(func(): return game.screen == "results" and game.capture_run_id == "", "results"): return
	await create_timer(.4).timeout
	var guest_key := FileAccess.get_file_as_string(qa.path_join("guest_key.txt")).strip_edges()
	var folder := "user://research/%s/players/%s" % [session, guest_key]
	check(not guest_key.is_empty() and DirAccess.dir_exists_absolute(folder), "the guest's folder exists on the leader's computer: " + folder)
	var levels := DirAccess.get_files_at(folder + "/levels")
	var events := ""
	var has_samples := false
	for name in levels:
		if name.ends_with("_events.jsonl"): events += FileAccess.get_file_as_string(folder + "/levels/" + name)
		if name.ends_with("_samples_60hz.csv"): has_samples = true
	check(events.count('"event":"mouse_motion"') >= 20, "the guest's mouse rows from before and after the reconnect are stored (%d)" % events.count('"event":"mouse_motion"'))
	check(not '"event":"incident_spawned"' in events and not '"event":"dispatch"' in events, "the guest's files hold only their own input")
	check(has_samples, "the guest's 60 Hz samples are stored")
	check(FileAccess.file_exists(folder + "/player.json"), "player.json identifies the guest")
	var own := FileAccess.get_file_as_string(game.research.log_path)
	check(own.contains('"event":"shift_started"') or own.contains('"event":"level_started"'), "the leader's own log has the shared game events")
	mark("done")
	await wait_for(func(): return not game.network.active, "server closes", 10.0)

func run_guest() -> void:
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.screen = "lobby"
	game.research_enabled = true
	if not await wait_for(func(): return marked("leader_joined"), "leader first"): return
	game.network.join("127.0.0.1:%d" % game.network.port)
	if not await wait_for(func(): return game.network.roster.size() == 2, "guest joins"): return
	var key: String = game.network.player_key(game.multiplayer.get_unique_id())
	var file := FileAccess.open(qa.path_join("guest_key.txt"), FileAccess.WRITE)
	file.store_string(key)
	file.close()
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
	await wait_for(func(): return marked("done"), "leader checked files", 20.0)
	var sessions := 0
	if DirAccess.dir_exists_absolute("user://research"):
		for name in DirAccess.get_directories_at("user://research"):
			if name.begins_with("session_"): sessions += 1
	check(sessions == 0, "the guest wrote no research session folder on its own computer")
	check(game.relay.sent_bytes > 0, "the guest sent its data to the leader")
	await wait_for(func(): return not game.network.active, "server closes", 10.0)

func finish() -> void:
	if role != "server":
		game._stop_capture()
		game.voice.shutdown()
	if failures.is_empty(): print("PASS: %s - leader stores the team's files, guest reconnects without department changes" % role)
	else:
		for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
