extends SceneTree

# Runs the real game command and UI handlers without opening network ports.
# The role network suite separately covers ENet delivery and roster replication.
# Run: godot --headless --path . -s tests/test_crew_controls.gd
var failures: Array[String] = []
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func configure_room(server_only: bool = false) -> void:
	game.network.active = true
	game.network.hosting = true
	game.network.dedicated = server_only
	game.network.roster = {44: 0, 55: 1} if server_only else {1: 0, 44: 1}
	game.network.role_assignments = {}
	game.network.player_names = {44: "Robin", 55: "Elio"} if server_only else {1: "Robin", 44: "Elio"}
	game.dedicated_server = server_only
	game.screen = "lobby"
	game.sim.running = false

func unit_of_kind(kind: String) -> Dictionary:
	for unit: Dictionary in game.sim.units:
		if str(unit.kind) == kind: return unit
	return {}

func make_call() -> Dictionary:
	game.sim._spawn_incident()
	var call: Dictionary = game.sim.incidents.back()
	call.needs = {"fire": 1, "medic": 1, "engineer": 0, "police": 0}
	call.discovered = true
	return call

func arrive(crew: Dictionary) -> void:
	game.sim._tick_unit(crew, float(crew.remaining) + 1.0)
	game.sim.elapsed = maxf(game.sim.elapsed, float(crew.get("dispatch_guard_until", 0.0)) + 1.0)
	check(str(crew.state) == "working", "Fixture crew reaches the incident before withdrawal")

func test_withdraw_commands() -> void:
	configure_room()
	game._begin_shift(0)
	var call := make_call()
	var fire := unit_of_kind("fire")
	var medic := unit_of_kind("medic")
	game._execute_command("dispatch", {"incident_id": call.id, "kind": "fire", "unit_id": fire.id}, 1)
	game._execute_command("dispatch", {"incident_id": call.id, "kind": "medic", "unit_id": medic.id}, 44)
	arrive(fire)
	arrive(medic)
	game._execute_command("withdraw", {"unit_id": fire.id, "kind": "medic"}, 44)
	check(int(fire.target) == int(call.id) and call.assigned.has(fire.id), "Spoofing an owned department cannot withdraw another player's unit")
	game._execute_command("withdraw", {"unit_id": fire.id, "kind": "fire"}, 44)
	check(str(fire.state) == "working", "A guest cannot withdraw a correctly named department they do not own")
	game._execute_command("withdraw", {"unit_id": medic.id, "kind": "medic"}, 999)
	check(str(medic.state) == "working", "A peer outside the room cannot withdraw a crew")
	game._execute_command("withdraw", {"unit_id": 999, "kind": "medic"}, 44)
	check(str(medic.state) == "working", "An invalid unit ID leaves assignments unchanged")
	game._action("withdraw:%d" % int(medic.id))
	check(str(medic.state) == "working", "The local withdrawal action respects another player's department ownership")
	game._execute_command("withdraw", {"unit_id": medic.id, "kind": "medic"}, 44)
	check(str(medic.state) == "return" and int(medic.target) == -1, "The owning guest can withdraw a crew already on scene")
	check(not call.assigned.has(medic.id) and call.assigned.has(fire.id), "Withdrawal removes only the selected crew from the incident")
	# The selected working crew must survive the normal UI refresh and its
	# withdrawal button must reach the authoritative command handler.
	game._action("unit:%d" % int(fire.id))
	check(game.selected_unit == int(fire.id), "A working crew can be selected for withdrawal")
	game._process(0.0)
	check(game.selected_unit == int(fire.id), "Refreshing the game preserves selection of a working crew")
	check(game._withdraw_control_visible(), "Selecting an on-scene crew exposes the withdrawal control")
	check(not game.tactical_map.dispatch_enabled, "An on-scene crew is not advertised as available for dispatch")
	var other_call := make_call()
	var dispatch_count: int = game.sim.successful_dispatches
	game.tactical_map.activate_target({"type": "call", "id": other_call.id})
	check(game.selected == int(other_call.id) and game.selected_unit == int(fire.id), "Clicking a different incident with an on-scene crew selected only inspects it")
	game._action("dispatch_selected")
	check(game.sim.successful_dispatches == dispatch_count and int(fire.target) == int(call.id), "A busy selected crew cannot be reassigned until withdrawn")
	var control_point: Vector2 = game.UNIT_CONTROL_RECT.get_center()
	check(game._map_input_blocked(control_point), "The withdrawal panel blocks map gestures beneath it")
	check(game.tactical_map.pointer_target(control_point + game.global_position).is_empty(), "The withdrawal panel blocks tactical map targets beneath it")
	game._action("withdraw:%d" % int(fire.id))
	check(str(fire.state) == "return" and not call.assigned.has(fire.id), "The withdrawal UI action releases the local on-scene crew")
	# Shared gameplay continues while the host has a personal menu open.
	for menu: String in ["pause", "help", "settings"]:
		game._begin_shift(0)
		call = make_call()
		medic = unit_of_kind("medic")
		game._execute_command("dispatch", {"incident_id": call.id, "kind": "medic", "unit_id": medic.id}, 44)
		arrive(medic)
		game.screen = menu
		game.previous_screen = "game"
		game._execute_command("withdraw", {"unit_id": medic.id, "kind": "medic"}, 44)
		check(str(medic.state) == "return", "Guest withdrawal works while host opens " + menu)
		check(game.screen == menu, "Guest withdrawal preserves the host's " + menu + " menu")

func test_solo_withdraw() -> void:
	game.network.active = false
	game.network.hosting = false
	game._begin_shift(0)
	var call := make_call()
	var fire := unit_of_kind("fire")
	game._command("dispatch", {"incident_id": call.id, "kind": "fire", "unit_id": fire.id})
	arrive(fire)
	game._action("unit:%d" % int(fire.id))
	game._action("withdraw:%d" % int(fire.id))
	check(str(fire.state) == "return" and not call.assigned.has(fire.id), "Solo players can withdraw their on-scene crew through the UI")

func test_between_level_roles(server_only: bool) -> void:
	configure_room(server_only)
	var mode := "Dedicated" if server_only else "LAN"
	var first := 44 if server_only else 1
	var second := 55 if server_only else 44
	var original_seats: Dictionary = game.network.roster.duplicate()
	var original_names: Dictionary = game.network.player_names.duplicate()
	var first_bundle: Array = game.network.departments_for(first)
	var second_bundle: Array = game.network.departments_for(second)
	game._execute_command("change_role", {"target_peer_id": first}, second)
	check(game.network.departments_for(first) == second_bundle and game.network.departments_for(second) == first_bundle, mode + " guests can swap roles in the lobby")
	check(game.network.roster == original_seats and game.network.player_names == original_names, mode + " role changes preserve seats and player names")
	if server_only:
		check(game.network.can_start_session(first) and not game.network.can_start_session(second), "Swapping roles preserves the dedicated session's start authority")
	game._execute_command("change_role", {"target_peer_id": second}, 999)
	game._execute_command("change_role", {"target_peer_id": 999}, first)
	game._execute_command("change_role", {"target_peer_id": first}, first)
	check(game.network.departments_for(first) == second_bundle, mode + " invalid targets, unknown senders, and self-swaps are rejected")
	game._begin_shift(0)
	check(game.network.departments_for(first) == second_bundle, mode + " chosen roles persist into the next level")
	for during: String in ["game", "pause", "help", "settings", "lobby", "results"]:
		game.screen = during
		game.previous_screen = "game"
		game._execute_command("change_role", {"target_peer_id": second}, first)
		check(game.network.departments_for(first) == second_bundle, mode + " rejects role changes while a level runs, including " + during)
	game.screen = "game"
	var call := make_call()
	var fire := unit_of_kind("fire")
	game._execute_command("dispatch", {"incident_id": call.id, "kind": "fire", "unit_id": fire.id}, second)
	check(int(fire.target) == int(call.id), mode + " the new role owner can dispatch its crew")
	arrive(fire)
	game._execute_command("withdraw", {"unit_id": fire.id, "kind": "fire"}, first)
	check(str(fire.state) == "working", mode + " the old role owner cannot withdraw the transferred crew")
	game._execute_command("withdraw", {"unit_id": fire.id, "kind": "fire"}, second)
	check(str(fire.state) == "return", mode + " the new role owner can withdraw its on-scene crew")
	game.sim.running = false
	game.sim.finished = true
	game.screen = "results"
	if server_only:
		game._execute_command("change_role", {"target_peer_id": second}, first)
	else:
		game._action("change_role:%d" % second)
	check(game.network.departments_for(first) == first_bundle and game.network.departments_for(second) == second_bundle, mode + " roles can change again between completed levels")
	check(game.screen == "results", mode + " role changes preserve the results screen")
	game.network.hosting = false
	game._execute_command("change_role", {"target_peer_id": second}, first)
	check(game.network.departments_for(first) == first_bundle, mode + " a client cannot apply an authoritative role change locally")

func test_lobby_snapshots() -> void:
	configure_room()
	game._begin_shift(0)
	game.sim.running = false
	game.sim.finished = true
	game.screen = "results"
	game._action("results_levels")
	game._process(0.2)
	var payload: Dictionary = game.network._last_snapshot.duplicate(true)
	check(str(payload.get("screen", "")) == "lobby", "Choosing another level publishes the host's shared lobby")
	game.network.hosting = false
	game.screen = "results"
	game._receive_snapshot(payload)
	check(game.screen == "lobby", "The host's lobby snapshot brings guests back from results for role selection")
	game.screen = "settings"
	game.previous_screen = "lobby"
	game._receive_snapshot(payload)
	check(game.screen == "settings", "Lobby snapshots preserve a guest's open lobby settings")

func run() -> void:
	game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	test_withdraw_commands()
	test_solo_withdraw()
	test_between_level_roles(false)
	test_between_level_roles(true)
	test_lobby_snapshots()
	game.dedicated_server = false
	game._stop_capture()
	game.voice.shutdown()
	game.network.close()
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: on-scene withdrawal UI, authoritative crew ownership, host menus, and LAN/dedicated role changes between levels")
	quit(0 if failures.is_empty() else 1)
