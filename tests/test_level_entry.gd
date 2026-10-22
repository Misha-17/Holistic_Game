extends SceneTree

class TestVoice extends TeamVoice:
	func set_mic_enabled(value: bool) -> void:
		mic_enabled = value

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func check_paused(game: Node, label: String) -> void:
	var before: Dictionary = game.sim.net_snapshot().duplicate(true)
	game.net_timer = -10.0 # The fixture uses no live network transport.
	game._process(0.5)
	check(game.sim.net_snapshot() == before, label + ": simulation unchanged across a frame")

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
	check_paused(game, "Solo collection popup")
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	game._input(key)
	check(game.entry_popup == "consent", "Enter cannot silently accept collection")
	game._choose_collection(false)
	check(game.entry_popup == "voice" and not game.research.enabled, "Decline opens voice reminder")
	game._choose_voice(false)
	check(game.entry_popup == "briefing", "Voice choice opens role instructions")
	check_paused(game, "Role instructions")
	var real_voice: TeamVoice = game.voice
	var fake_voice := TestVoice.new()
	game.voice = fake_voice
	game._choose_voice(true)
	check(fake_voice.mic_enabled and game.screen == "settings" and game.settings_tab == "sounds", "Enable voice opens Sounds settings")
	check(game.previous_screen == "game" and game.entry_popup == "briefing" and not game._simulation_active(), "Settings retain pending briefing and paused clock")
	check_paused(game, "Preparation Sounds settings")
	game.voice = real_voice
	fake_voice.free()
	game._action("settings_back")
	check(game.screen == "game" and game.entry_popup == "briefing", "Back from Sounds returns to role instructions")
	for role: String in game.ROLE_BRIEFINGS:
		check(game.ROLE_BRIEFINGS[role].size() == 4, role + " gets four instructions")
	game._complete_briefing()
	game._request_entry_action("entry_start")
	check(game._simulation_active(), "Decline still allows play")
	game._begin_shift(0)
	check(game.entry_popup == "consent", "New run asks again without restarting the app")
	game._choose_collection(true)
	game._complete_briefing()
	game._request_entry_action("entry_start")
	check(game.research.enabled and game.voice.recording_enabled and game.voice.recording_consent, "Opt-in enables collection switches")
	check(not game.voice.mic_enabled, "Collection never enables microphone implicitly")
	var session: String = game.capture_session_id
	var first_run: String = game.capture_run_id
	var voice_path: String = game.voice.recording_path
	game.sim.elapsed = 10.0
	game._begin_shift(1)
	game._complete_briefing()
	game._request_entry_action("entry_start")
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
	check(game._waiting_for_briefings and not game._simulation_active(), "All ready still waits for owner Start")
	check_paused(game, "Multiplayer ready screen")
	game._execute_command("entry_start", {"level_run_id": game.shared_level_run_id}, 44)
	check(game._waiting_for_briefings, "Guest cannot start")
	game._execute_command("entry_start", {"level_run_id": "stale-run"}, 1)
	check(game._waiting_for_briefings, "Stale Start cannot release clock")
	game._execute_command("entry_start", {"level_run_id": game.shared_level_run_id}, 1)
	check(not game._waiting_for_briefings, "Owner starts after everyone is ready")
	game._begin_shift(BeaconCampaign.PRACTICE_INDEX)
	check(game.entry_popup == "consent", "Restart on running host repeats reminder")
	game._execute_command("entry_start", {"level_run_id": game.shared_level_run_id}, 1)
	check(game._waiting_for_briefings, "Owner cannot skip unread reminders")
	game._execute_command("entry_cancel", {"level_run_id": game.shared_level_run_id}, 44)
	check(game.screen == "game", "Guest cannot cancel preparation")
	game._execute_command("entry_cancel", {"level_run_id": game.shared_level_run_id}, 1)
	check(game.screen == "lobby" and not game.sim.running and game.entry_popup.is_empty() and game.network.active and game.network.roster.size() == 2, "Owner X returns to joined waiting room without disconnecting")
	check(game._entry_owner(1) and not game._entry_owner(44), "Only multiplayer owner has the X button")
	game.network.dedicated = true
	game.network.roster = {44: 0, 55: 1}
	check(game._entry_owner(44) and not game._entry_owner(55), "First dedicated-server player owns preparation")
	game.network.dedicated = false
	check(game.network._valid_payload("start_shift", {"shift": 6}), "Network accepts Level 0")
	check(not game.network._valid_payload("start_shift", {"shift": 7}), "Network rejects nonexistent level")
	# Apply the same authoritative fields used by remote guests.
	game.network.hosting = false
	game.network.active = false
	game._stop_capture()
	game.sim.start_shift(0)
	var snapshot: Dictionary = {"screen": "game", "simulation": game.sim.net_snapshot(), "level_run_id": "guest-preparation", "waiting_for_briefings": true, "level_ready_peers": {1: true}}
	game._receive_snapshot(snapshot)
	check(game.entry_popup == "consent" and not game._simulation_active(), "Guest opens reminders with clock paused")
	check(game._level_ready_peers.get(1, false), "Ready roster arrives in snapshots")
	game.sim.running = false
	snapshot.screen = "lobby"
	snapshot.simulation = game.sim.net_snapshot()
	snapshot.waiting_for_briefings = false
	game._receive_snapshot(snapshot)
	check(game.screen == "lobby" and game.entry_popup.is_empty(), "Cancellation snapshot closes guest popup")
	game.network.active = false
	game._begin_shift(BeaconCampaign.PRACTICE_INDEX)
	game._request_entry_action("entry_cancel")
	check(game.screen == "title" and not game.sim.running, "Solo practice X returns to main menu")
	game._stop_capture()
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: optional consent, role briefings, shared sessions and multiplayer ready barrier")
	else:
		for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
