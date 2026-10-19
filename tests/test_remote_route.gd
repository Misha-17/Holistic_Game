extends SceneTree

# Playtest 19.10: on a guest, a teammate's dispatch drew its "route draws itself"
# animation through the crew's previous trip (a triangle back to the station),
# because the guest's copy of that crew had not received the new path yet.
# Run: godot --headless --path . -s tests/test_remote_route.gd
var failures: Array[String] = []
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func unit_of_kind(sim, kind: String) -> Dictionary:
	for unit: Dictionary in sim.units:
		if str(unit.kind) == kind: return unit
	return {}

func new_call(sim, kind: String) -> Dictionary:
	sim._spawn_incident()
	var call: Dictionary = sim.incidents.back()
	call.needs = {"fire": 0, "medic": 0, "engineer": 0, "police": 0}
	call.needs[kind] = 1
	call.needs["police" if kind != "police" else "fire"] = 1
	call.discovered = true
	return call

func last_route_effect() -> Dictionary:
	for i in range(game.fx.effects.size() - 1, -1, -1):
		if str(game.fx.effects[i].type) == "route": return game.fx.effects[i]
	return {}

func run() -> void:
	game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game._begin_shift(1)

	# The host runs its own simulation; the game node plays the guest.
	var host = load("res://scripts/simulation.gd").new()
	host.start_shift(1)
	var crew: Dictionary = unit_of_kind(host, "fire")
	var first: Dictionary = new_call(host, "fire")
	check(host.dispatch(int(first.id), "fire", int(crew.id)), "Host dispatches the first trip")
	for i in range(30): host.tick(0.1)
	check(host.withdraw(int(crew.id)), "Host withdraws the crew mid-trip")
	var guard := 0
	while str(crew.state) != "idle" and guard < 600:
		host.tick(0.1)
		guard += 1
	check(str(crew.state) == "idle", "Crew is home again")
	host.drain_events()

	# The guest is in sync with the host: the crew is home with its old return path.
	game.sim.apply_snapshot(host.net_snapshot())
	check(not game.sim.get_unit(int(crew.id)).get("path", []).is_empty(), "Guest copy keeps the old trip's path")

	# A teammate (peer 44) dispatches the crew to a new call. The event reaches
	# the guest before the next snapshot does.
	var second: Dictionary = new_call(host, "fire")
	check(host.dispatch(int(second.id), "fire", int(crew.id)), "Host dispatches the second trip")
	var dispatch_event: Dictionary = {}
	for event: Dictionary in host.drain_events():
		if str(event.type) == "dispatch": dispatch_event = event
	check(not dispatch_event.is_empty(), "Host emits a dispatch event")
	dispatch_event["actor_peer"] = 44
	game.fx.effects.clear()
	game._handle_game_event(dispatch_event)

	var effect: Dictionary = last_route_effect()
	check(not effect.is_empty(), "Guest draws the teammate's route")
	if not effect.is_empty():
		var points: Array = effect.points
		var expected: Array = [crew.pos]
		expected.append_array(crew.path)
		check(points.size() == expected.size(), "Route has the new trip's %d points, not %d" % [expected.size(), points.size()])
		var same := points.size() == expected.size()
		if same:
			for i in range(points.size()):
				if Vector2(points[i]).distance_to(Vector2(expected[i])) > 0.0001: same = false
		check(same, "Route follows the new trip from the crew to the call")
		check(Vector2(points.back()).distance_to(Vector2(crew.path.back())) < 0.0001, "Route ends at the new call")

	# A route animation must never start from the beginning of a half-driven path.
	game.fx.effects.clear()
	var moving: Dictionary = {"id": 99, "kind": "police", "pos": Vector2(0.5, 0.5), "path": [Vector2(0.1, 0.1), Vector2(0.5, 0.5), Vector2(0.9, 0.5)], "path_index": 2}
	game.fx.dispatched(moving)
	effect = last_route_effect()
	check(not effect.is_empty() and effect.points.size() == 2, "Draw-in skips points the crew already passed")

	host = null
	game._stop_capture()
	game.voice.shutdown()
	game.network.close()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: teammates' dispatch routes on guests follow the new trip, not the previous one")
	quit(0 if failures.is_empty() else 1)
