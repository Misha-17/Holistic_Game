extends SceneTree

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scripts/main.gd").new()
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game._begin_shift(BeaconCampaign.PRACTICE_INDEX)
	check(game.entry_popup == "consent", "First level asks for collection choice")
	check(not game.research.enabled and not game.voice.recording_active, "No capture before opt-in")
	check(not game._simulation_active(), "Choice pauses the solo level clock")
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	game._input(key)
	check(game.entry_popup == "consent", "Enter cannot silently accept collection")
	game._choose_collection(false)
	check(game.entry_popup == "briefing" and not game.research.enabled, "Decline still opens role briefing")
	for role: String in game.ROLE_BRIEFINGS:
		check(game.ROLE_BRIEFINGS[role].size() == 4, role + " gets four instructions")
	game._complete_briefing()
	check(game._simulation_active(), "Decline still allows play")
	game._begin_shift(0)
	check(game.entry_popup == "briefing", "Choice remembered for following levels this launch")
	game._choose_collection(true)
	game._complete_briefing()
	check(game.research.enabled and game.voice.recording_enabled and game.voice.recording_consent, "Opt-in enables collection switches")
	check(not game.voice.mic_enabled, "Collection never enables microphone implicitly")
	var session: String = game.capture_session_id
	var first_run: String = game.capture_run_id
	var voice_path: String = game.voice.recording_path
	game.sim.elapsed = 10.0
	game._begin_shift(1)
	game._complete_briefing()
	check(game.capture_session_id == session and game.capture_run_id != first_run, "Levels have distinct run IDs in one session")
	check(game.voice.recording_path == voice_path, "Speaker session stays whole across levels")
	game._stop_capture()
	# The ready barrier must work independently of capture permission.
	game.network.active = true
	game.network.hosting = true
	game.network.roster = {1: 0, 44: 1}
	game._begin_shift(BeaconCampaign.PRACTICE_INDEX)
	check(game._waiting_for_briefings and not game._simulation_active(), "Host waits for all players")
	game._execute_command("level_ready", {"level_run_id": "stale-run"}, 44)
	check(not game._level_ready_peers.has(44), "Stale ready command cannot start a new level")
	game._execute_command("level_ready", {"level_run_id": game.shared_level_run_id}, 1)
	check(game._waiting_for_briefings, "One ready player cannot start the team clock")
	game._execute_command("level_ready", {"level_run_id": game.shared_level_run_id}, 44)
	check(not game._waiting_for_briefings, "All players release the team clock")
	check(game.network._valid_payload("start_shift", {"shift": 6}), "Network accepts Level 0")
	check(not game.network._valid_payload("start_shift", {"shift": 7}), "Network rejects nonexistent level")
	game.network.active = false
	game._stop_capture()
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: optional consent, role briefings, shared sessions and multiplayer ready barrier")
	else:
		for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
