extends SceneTree

# Level 3 "Two Banks" (and the level 6 finale): a river with three bridges; scripted floods close one bridge at a time.
# Run: godot --headless --path . -s tests/test_two_banks.gd
const Sim = preload("res://scripts/simulation.gd")
const Campaign = preload("res://scripts/campaign.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_test_layout_only_on_level_3()
	_test_flood_detour()
	_test_full_shift()
	if failures.is_empty():
		print("PASS: Two Banks river, bridges, floods, detours, no calls or crews in the river")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _test_layout_only_on_level_3() -> void:
	for shift: int in range(6):
		_check(Campaign.layout(shift).has("river") == (shift in [2, 5]), "Levels 3 and 6 have the river (shift %d)" % (shift + 1))
	_check(Campaign.shift_data(2).title == "TWO BANKS", "Level 3 is Two Banks")

func _test_flood_detour() -> void:
	var sim := Sim.new()
	sim.start_shift(2)
	var north: Vector2 = Vector2(1152, 704) / Campaign.MAP_SIZE
	var south: Vector2 = Vector2(1152, 928) / Campaign.MAP_SIZE
	var crew: Dictionary = sim.units[0]
	var open_route: Dictionary = sim._best_route(crew, north, south)
	_check(float(open_route.eta) < 4.0, "Town Bridge crossing should be short when open")
	sim.elapsed = 150.0
	sim._edge_cache.clear()
	_check(sim.flooded_bridges().size() == 1 and sim.flooded_bridges()[0].name == "Town Bridge", "Town Bridge floods at 2:26")
	var flooded_route: Dictionary = sim._best_route(crew, north, south)
	_check(float(flooded_route.eta) > float(open_route.eta) + 8.0, "A flooded bridge must force a real detour")
	for point: Vector2 in flooded_route.path:
		var pixels: Vector2 = point * Campaign.MAP_SIZE
		if pixels.y > Campaign.RIVER_TOP and pixels.y < Campaign.RIVER_BOTTOM:
			_check(absf(pixels.x - 1152.0) > 1.0, "Detour must not use the flooded bridge")
	# The planned deadline ignores temporary floods (like road events).
	sim._ignore_road_events = true
	_check(absf(float(sim._best_route(crew, north, south).eta) - float(open_route.eta)) < 0.01, "Deadlines assume open bridges")
	sim._ignore_road_events = false

func _test_full_shift() -> void:
	var sim := Sim.new()
	sim.start_shift(2)
	var next_action: float = 2.0
	var in_river := 0
	var floods := 0
	while sim.running:
		if sim.elapsed >= next_action:
			next_action += 0.8
			for event: Dictionary in sim.active_road_events():
				if int(event.assigned_unit) < 0:
					for unit: Dictionary in sim.units:
						if unit.kind == event.clear_kind and unit.state == "idle" and sim.clear_road(int(event.id), int(unit.id)): break
			for call: Dictionary in sim.incidents:
				if call.status in ["active", "working"]:
					if not bool(call.discovered): sim.scout(int(call.id)); continue
					for kind: String in Sim.UNIT_KINDS:
						if sim.assigned_kind_count(call, kind) < int(call.needs.get(kind, 0)) and sim.available_count(kind) > 0: sim.dispatch(int(call.id), kind)
		sim.tick(0.1)
		for event: Dictionary in sim.drain_events():
			if event.type == "bridge_flooded": floods += 1
		for unit: Dictionary in sim.units:
			var p: Vector2 = unit.pos * Campaign.MAP_SIZE
			if p.y > Campaign.RIVER_TOP + 4 and p.y < Campaign.RIVER_BOTTOM - 4:
				var on_bridge := false
				for column: int in [1, 4, 7]:
					if absf(p.x - Sim.ROAD_X[column] * Campaign.MAP_SIZE.x) < 2: on_bridge = true
				if not on_bridge: in_river += 1
	_check(in_river == 0, "Crews drove through the river %d times" % in_river)
	_check(floods == 3, "Three scripted floods expected, got %d" % floods)
	for call: Dictionary in sim.incidents:
		_check(Campaign.site_open(2, call.pos), "Call placed in the river at " + str(call.name))
	_check(sim.won, "A capable bot should still win Two Banks")
	print("Two Banks bot: rescued %d/%d, missed %d, ended at %.0fs" % [sim.rescued, sim.target, sim.failed_count, sim.elapsed])
