extends SceneTree

# Levels 3-6 (Oct 2026): their own maps and hazards.
#   3 Two Banks (river + bridge floods), 4 Lights Out (Moon Lake + blackouts),
#   5 Dune Springs (oasis, dunes + sandstorms), 6 Beacon Night (river + blackout + squall).
# Run: godot --headless --path . -s tests/test_levels.gd
const Sim = preload("res://scripts/simulation.gd")
const Campaign = preload("res://scripts/campaign.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_test_maps_are_connected()
	_test_road_events_fit_the_maps()
	_test_forecast()
	_test_blackout()
	_test_storm()
	_test_snapshot()
	_test_full_levels()
	if failures.is_empty():
		print("PASS: level maps connected, hazards forecast, blackouts restorable, storms slow everyone, guests in sync, bots win")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _test_maps_are_connected() -> void:
	_check(Campaign.layout(0).is_empty() and Campaign.layout(1).is_empty(), "Levels 1-2 keep the normal town")
	for shift: int in range(2, 6):
		_check(not Campaign.layout(shift).is_empty(), "Level %d has its own map" % (shift + 1))
		var sim := Sim.new()
		sim.start_shift(shift)
		var open_sites: int = 0
		for site: Dictionary in Campaign.locations():
			if not Campaign.site_open(shift, site.pos): continue
			open_sites += 1
			for unit: Dictionary in sim.units:
				var route: Dictionary = sim._best_route(unit, unit.pos, site.pos)
				_check(is_finite(float(route.eta)) and not (route.path as Array).is_empty(), "Level %d: %s can't reach %s" % [shift + 1, unit.name, site.name])
		_check(open_sites >= 45, "Level %d keeps most of the town (%d sites)" % [shift + 1, open_sites])

func _test_road_events_fit_the_maps() -> void:
	for shift: int in range(6):
		var data: Dictionary = Campaign.layout(shift)
		for event: Dictionary in Campaign.shift_data(shift).traffic:
			if bool(event.get("hazard", false)): continue
			var area := Rect2(Vector2(event.position) * Campaign.MAP_SIZE, Vector2(event.size) * Campaign.MAP_SIZE)
			for water: Rect2 in data.get("water", []):
				_check(not water.intersects(area), "Level %d: %s is in the water" % [shift + 1, event.name])
			_check(Campaign.site_open(shift, Vector2(Campaign.locations()[Campaign.location_index(str(event.call_site))].pos)), "Level %d: %s's call site is closed" % [shift + 1, event.name])

func _test_forecast() -> void:
	for shift: int in range(2, 6):
		var sim := Sim.new()
		sim.start_shift(shift)
		for key: String in ["arrival_schedule"]: sim._shift[key] = []
		var warnings: Array[float] = []
		var starts: Dictionary = {}
		while sim.elapsed < 320.0:
			sim.tick(0.1)
			for event: Dictionary in sim.drain_events():
				if event.type == "hazard_warning": warnings.append(float(event.at) - sim.elapsed)
				if event.type in ["hazard_started", "bridge_flooded"]: starts[str(event.text)] = true
		var plan: Array = sim._hazard_plan()
		_check(plan.size() >= 2, "Level %d needs its hazards" % (shift + 1))
		_check(warnings.size() == plan.size(), "Level %d: every hazard is announced (%d of %d)" % [shift + 1, warnings.size(), plan.size()])
		for ahead: float in warnings:
			_check(absf(ahead - Campaign.HAZARD_WARNING_SECONDS) < 0.15, "Level %d: hazard announced %.1fs ahead" % [shift + 1, ahead])
	var sim := Sim.new()
	sim.start_shift(3)
	sim.elapsed = 35.0
	var soon: Array[Dictionary] = sim.upcoming_hazards()
	_check(soon.size() == 1 and soon[0].type == "blackout" and absf(float(soon[0]["in"]) - 7.0) < 0.01, "Forecast lists the next blackout with its countdown")
	var plain := Sim.new()
	plain.start_shift(0)
	_check(plain._hazard_plan().is_empty(), "Level 1 has no level hazards")

func _quiet(shift: int) -> RescueSimulation:
	var sim := Sim.new()
	sim.start_shift(shift)
	for key: String in ["arrival_schedule", "chaos_phases", "disruptions"]: sim._shift[key] = []
	return sim

func _hazard(sim: RescueSimulation, type: String) -> Dictionary:
	while sim.elapsed < 320.0:
		for event: Dictionary in sim.active_road_events():
			if str(event.type) == type: return event
		sim.tick(0.1)
	return {}

func _test_blackout() -> void:
	var sim := _quiet(3)
	var blackout: Dictionary = _hazard(sim, "blackout")
	_check(not blackout.is_empty() and str(blackout.street) == "Lantern Hill", "Lights Out starts with a blackout in Lantern Hill")
	if blackout.is_empty(): return
	var area := Rect2(blackout.position, blackout.size)
	var inside: Vector2 = Vector2(480, 406) / Campaign.MAP_SIZE   # Market Square
	var outside: Vector2 = Vector2(2016, 1050) / Campaign.MAP_SIZE
	_check(area.has_point(inside) and not area.has_point(outside), "Blackout covers its district only")
	var fire: Dictionary = {}
	var engineer: Dictionary = {}
	for unit: Dictionary in sim.units:
		if unit.kind == "fire" and fire.is_empty(): fire = unit
		if unit.kind == "engineer" and engineer.is_empty(): engineer = unit
	var from: Vector2 = Vector2(1120, 448) / Campaign.MAP_SIZE
	var dark: float = float(sim._best_route(fire, from, inside).eta)
	var probe := fire.duplicate()
	probe.kind = "engineer"
	var engineer_eta: float = float(sim._best_route(probe, from, inside).eta)
	_check(dark > engineer_eta * 1.5, "Crews crawl in the dark, engineers don't (%.1f vs %.1f)" % [dark, engineer_eta])
	# New calls in the dark are unconfirmed.
	sim._spawn_incident(Campaign.location_index("The Corner Store"))
	_check(bool(sim.incidents.back().discovered), "Scripted calls stay confirmed")
	sim._previous_spawn_location = -1
	var unconfirmed := false
	for i in range(40):
		sim._spawn_incident()
		var call: Dictionary = sim.incidents.back()
		if area.has_point(call.pos) and not bool(call.discovered): unconfirmed = true
		call.status = "resolved"
	_check(unconfirmed, "Calls inside a blackout come in unconfirmed")
	_check(not sim.clear_road(int(blackout.id), int(fire.id)), "Only Engineering can restore power")
	_check(sim.clear_road(int(blackout.id), int(engineer.id)), "An engineer can be sent to the substation")
	_check(sim.road_event_center(blackout).is_equal_approx(Vector2(608, 448) / Campaign.MAP_SIZE), "The engineer drives to the substation")
	var restored := false
	var started: float = sim.elapsed
	while sim.elapsed < started + 60.0 and not restored:
		sim.tick(0.1)
		for event: Dictionary in sim.drain_events():
			if event.type == "road_cleared" and str(event.text).begins_with("Lights are back on"): restored = true
	_check(restored and str(blackout.status) == "cleared", "Power is restored")
	var after: float = float(sim._best_route(fire, from, inside).eta)
	_check(after < dark, "Crews drive normally once the lights are back")

func _test_storm() -> void:
	var sim := _quiet(4)
	var storm: Dictionary = _hazard(sim, "sandstorm")
	_check(not storm.is_empty() and str(storm.street) == "the west", "The first sandstorm hits the west first")
	if storm.is_empty(): return
	_check(str(storm.clear_kind) == "", "Nobody clears a sandstorm")
	for unit: Dictionary in sim.units:
		if unit.kind in ["police", "engineer"]:
			_check(not sim.clear_road(int(storm.id), int(unit.id)), "%s can't clear a sandstorm" % unit.kind)
			break
	var police: Dictionary = {}
	for unit: Dictionary in sim.units:
		if unit.kind == "police": police = unit
	var a: Vector2 = Vector2(352, 448) / Campaign.MAP_SIZE
	var b: Vector2 = Vector2(864, 448) / Campaign.MAP_SIZE
	var slow: float = float(sim._best_route(police, a, b).eta)
	sim._ignore_road_events = true
	var still_slow: float = float(sim._best_route(police, a, b).eta)
	sim._ignore_road_events = false
	_check(absf(slow - still_slow) < 0.01, "Call deadlines include the storm (nobody can clear it)")
	# Sweep: west, then centre, then east.
	sim.drain_events()
	var order: Array[String] = []
	while sim.elapsed < 160.0:
		sim.tick(0.1)
		for event: Dictionary in sim.drain_events():
			if event.type == "hazard_started": order.append(str(sim.get_road_event(int(event.road_event_id)).street))
	_check(order == ["the centre", "the east"], "The storm sweeps west to east (%s)" % str(order))
	var storms_left: int = 0
	for event: Dictionary in sim.active_road_events():
		if bool(event.get("hazard", false)): storms_left += 1
	_check(storms_left == 0, "The storm passes")
	var open_eta: float = float(sim._best_route(police, a, b).eta)
	_check(slow > open_eta * 1.3, "Sandstorms slow everyone down (%.1f vs %.1f)" % [slow, open_eta])

func _test_snapshot() -> void:
	var sim := _quiet(3)
	var blackout: Dictionary = _hazard(sim, "blackout")
	if blackout.is_empty(): return
	var guest := Sim.new()
	guest.apply_snapshot(bytes_to_var(var_to_bytes(sim.net_snapshot())))
	var copy: Dictionary = guest.get_road_event(int(blackout.id))
	_check(bool(copy.get("hazard", false)) and copy.has("target"), "Guests know about the blackout and its substation")
	_check(guest.current_hazards().size() == sim.current_hazards().size(), "Guests show the same hazards")
	var saved := Sim.new()
	saved.apply_snapshot(sim.snapshot())
	_check(saved.get_road_event(int(blackout.id)).has("target"), "Saved games keep the substation")
	_check(not saved._blocked_edges.is_empty(), "Saved games restore the map")

# A team that reacts like people: four players in parallel, each with one
# department, a few seconds to notice anything, one action every 1.5 s.
# A team that reacts like people: four players in parallel, each with one
# department, a few seconds to notice anything, one action every 1.5 s.
# Three teams (4, 5 and 6 s to react); at least two of three must win, so one
# unlucky run doesn't fail the test.
func _test_full_levels() -> void:
	for shift: int in range(2, 6):
		var wins: int = 0
		var lines: Array[String] = []
		for react: float in [4.0, 5.0, 6.0]:
			var sim := Sim.new()
			sim.start_shift(shift)
			var next := {"fire": 2.0, "medic": 2.4, "engineer": 2.8, "police": 3.2}
			var in_water: int = 0
			var layout: Dictionary = Campaign.layout(shift)
			while sim.running:
				for kind: String in next:
					if sim.elapsed >= float(next[kind]):
						_player(sim, kind, react)
						next[kind] = float(next[kind]) + 1.5
				sim.tick(0.1)
				sim.drain_events()
				for unit: Dictionary in sim.units:
					var p: Vector2 = unit.pos * Campaign.MAP_SIZE
					for water: Rect2 in layout.get("water", []):
						if water.grow(-8.0).has_point(p):
							var on_bridge := false
							for column: int in layout.get("bridges", {}):
								if absf(p.x - Sim.ROAD_X[column] * Campaign.MAP_SIZE.x) < 2: on_bridge = true
							if not on_bridge: in_water += 1
			_check(in_water == 0, "Level %d: crews drove through water %d times" % [shift + 1, in_water])
			for call: Dictionary in sim.incidents:
				_check(Campaign.site_open(shift, call.pos), "Level %d: call at closed site %s" % [shift + 1, call.name])
			if sim.won: wins += 1
			lines.append("%d/%d %dmiss %d%%" % [sim.rescued, sim.target, sim.failed_count, roundi(sim.reputation)])
		_check(wins >= 2, "Level %d: a four-player team should usually win (%d of 3)" % [shift + 1, wins])
		print("Level %d %s: %d/3 teams win  [%s]" % [shift + 1, Campaign.shift_data(shift).title, wins, ", ".join(lines)])

func _player(sim: RescueSimulation, kind: String, react: float = 5.0) -> void:
	for event: Dictionary in sim.active_road_events():
		if int(event.assigned_unit) < 0 and str(event.clear_kind) == kind and sim.elapsed - float(event.started_at) > react:
			for unit: Dictionary in sim.units:
				if unit.kind == kind and unit.state == "idle":
					if sim.clear_road(int(event.id), int(unit.id)): return
	var calls: Array[Dictionary] = []
	for incident: Dictionary in sim.incidents:
		if incident.status in ["active", "working"] and sim.elapsed - float(incident.created_at) > react: calls.append(incident)
	calls.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.deadline) < float(y.deadline))
	for incident: Dictionary in calls:
		if not bool(incident.discovered):
			if kind == "police" and sim.scout(int(incident.id)): return
			continue
		if sim.assigned_kind_count(incident, kind) < int(incident.needs.get(kind, 0)) and sim.available_count(kind) > 0:
			if sim.dispatch(int(incident.id), kind): return
