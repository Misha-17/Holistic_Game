extends SceneTree

# Road events (traffic rework): scripted closures that only Police (jams) or
# Engineering (debris) can drive through and clear.
# Run: godot --headless --path . -s tests/test_road_events.gd
const Sim = preload("res://scripts/simulation.gd")
const Campaign = preload("res://scripts/campaign.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_test_schedule()
	_test_blocking_and_clearing()
	_test_wrong_department_and_expiry()
	_test_network_snapshot()
	_test_deadlines_assume_open_roads()
	_report_effect()
	if failures.is_empty():
		print("PASS: road events are scripted, block other departments, clear, expire, survive snapshots")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _test_schedule() -> void:
	for shift: int in range(6):
		var plan: Array = Campaign.shift_data(shift).traffic
		_check(plan.size() == 4, "Shift %d should have four road events" % (shift + 1))
		var kinds := {}
		for event: Dictionary in plan:
			kinds[event.clear_kind] = true
			for phase: Dictionary in Campaign.chaos_schedule(shift):
				if float(event.at) >= float(phase.at) and float(event.at) < float(phase.until):
					_check(phase.phase != "low", "Shift %d: %s starts in a low-chaos phase" % [shift + 1, event.name])
			var area := Rect2(Vector2(event.position) * Campaign.MAP_SIZE, Vector2(event.size) * Campaign.MAP_SIZE)
			_check(Rect2(Vector2.ZERO, Campaign.MAP_SIZE).encloses(area), "%s lies outside the map" % event.name)
		_check(kinds.has("police") and kinds.has("engineer"), "Shift %d needs both Police and Engineering road events" % (shift + 1))
	# Same plan every time.
	_check(str(Campaign.shift_data(0).traffic) == str(Campaign.shift_data(0).traffic), "Road events must be deterministic")

func _first_event(sim: RescueSimulation) -> Dictionary:
	while sim.active_road_events().is_empty() and sim.elapsed < 200.0:
		sim.tick(0.1)
	return sim.active_road_events()[0] if not sim.active_road_events().is_empty() else {}

func _crew(sim: RescueSimulation, kind: String) -> Dictionary:
	for unit: Dictionary in sim.units:
		if unit.kind == kind and unit.state == "idle": return unit
	return {}

func _quiet_shift(shift: int) -> RescueSimulation:
	var sim := Sim.new()
	sim.start_shift(shift)
	for key: String in ["chaos_phases", "arrival_schedule", "disruptions"]: sim._shift[key] = []
	return sim

func _test_blocking_and_clearing() -> void:
	var sim := _quiet_shift(0)
	var event: Dictionary = _first_event(sim)
	_check(not event.is_empty(), "First road event never started")
	if event.is_empty(): return
	_check(event.clear_kind == "police", "Shift 1 opens with a police jam")
	var center: Vector2 = sim.road_event_center(event)
	var fire: Dictionary = _crew(sim, "fire")
	var police: Dictionary = _crew(sim, "police")
	var blocked: float = float(sim._best_route(fire, fire.pos, center).eta)
	var specialist: float = float(sim._best_route(police, police.pos, center).eta)
	sim._ignore_road_events = true
	var open: float = float(sim._best_route(fire, fire.pos, center).eta)
	sim._ignore_road_events = false
	_check(blocked > open + 5.0, "A jam must cost other departments real time (%.1fs vs %.1fs open)" % [blocked, open])
	_check(specialist < blocked, "Police must reach the jam faster than a fire crew stuck in it")
	_check(sim.clear_road(int(event.id), int(police.id)), "A free police crew can clear a jam")
	_check(not sim.clear_road(int(event.id), int(_crew(sim, "police").id)), "Only one crew per road event")
	_check(police.state == "travel" and int(police.clear_target) == int(event.id), "Clearing crew must drive to the road")
	var started: float = sim.elapsed
	while str(sim.get_road_event(int(event.id)).status) in ["active", "clearing"] and sim.elapsed < started + 60.0:
		sim.tick(0.1)
	_check(sim.get_road_event(int(event.id)).status == "cleared", "Jam was not cleared")
	_check(sim.roads_cleared == 1, "Cleared roads are counted")
	_check(police.state == "return" and int(police.clear_target) == -1, "Crew returns to standby after clearing")
	var after: float = float(sim._best_route(fire, fire.pos, center).eta)
	_check(absf(after - open) < 0.01, "A cleared road no longer slows anyone")

func _test_wrong_department_and_expiry() -> void:
	var sim := _quiet_shift(0)
	var event: Dictionary = _first_event(sim)
	if event.is_empty(): return
	_check(not sim.clear_road(int(event.id), int(_crew(sim, "engineer").id)), "Engineers cannot clear a traffic jam")
	_check(not sim.clear_road(int(event.id), int(_crew(sim, "fire").id)), "Fire cannot clear a traffic jam")
	var police: Dictionary = _crew(sim, "police")
	sim.clear_road(int(event.id), int(police.id))
	event.expires_at = sim.elapsed + 0.5
	sim.tick(1.0)
	_check(event.status == "expired", "Road event expires on schedule")
	_check(police.state in ["return", "rest", "idle"] and int(police.clear_target) == -1, "A crew heading to an expired road goes back (state %s)" % police.state)
	var researched := false
	for record: Dictionary in sim.drain_events():
		if str(record.type) == "road_event_expired": researched = true
	_check(researched, "Expiry is recorded for research")

func _test_network_snapshot() -> void:
	var sim := _quiet_shift(0)
	var event: Dictionary = _first_event(sim)
	if event.is_empty(): return
	var police: Dictionary = _crew(sim, "police")
	sim.clear_road(int(event.id), int(police.id))
	sim.tick(1.0)
	var packed: PackedByteArray = var_to_bytes(sim.net_snapshot())
	var guest := Sim.new()
	guest.apply_snapshot(bytes_to_var(packed))
	_check(guest.active_road_events().size() == 1, "Guests see active road events")
	_check(int(guest.get_road_event(int(event.id)).assigned_unit) == int(police.id), "Guests see who is clearing")
	_check(int(guest.get_unit(int(police.id)).clear_target) == int(event.id), "Guests know the crew's road target")
	var saved := Sim.new()
	saved.apply_snapshot(sim.snapshot())
	_check(saved.active_road_events().size() == 1, "Saved games keep road events")
	# A guest that keeps simulating between updates must also finish the clearing.
	while str(guest.get_road_event(int(event.id)).status) in ["active", "clearing"] and guest.elapsed < 120.0:
		guest.tick(0.1)
	_check(guest.get_road_event(int(event.id)).status == "cleared", "Guest-side prediction clears the road too")

func _test_deadlines_assume_open_roads() -> void:
	var a := _quiet_shift(0)
	var b := _quiet_shift(0)
	_first_event(a)
	_first_event(b)
	b.road_events.clear()
	a._spawn_incident()
	b._spawn_incident()
	_check(absf(float(a.incidents.back().deadline) - float(b.incidents.back().deadline)) < 0.001, "A closed road must not quietly lengthen new deadlines")

# Not a pass/fail check: how much road events matter for a bot that reacts like a person.
func _report_effect() -> void:
	for clears: bool in [false, true]:
		var line := "Bot that %s: " % ("clears roads" if clears else "ignores roads")
		for shift: int in [0, 4]:
			var sim := Sim.new()
			sim.start_shift(shift)
			var next_action: float = 2.0
			while sim.running:
				if sim.elapsed >= next_action:
					_human_bot(sim, clears)
					next_action += 1.5
				sim.tick(0.1)
				sim.drain_events()
			line += "shift %d rescued %d/%d missed %d confidence %.0f roads cleared %d   " % [shift + 1, sim.rescued, sim.target, sim.failed_count, sim.reputation, sim.roads_cleared]
		print(line)

func _human_bot(sim: RescueSimulation, clears: bool) -> void:
	if clears:
		for event: Dictionary in sim.active_road_events():
			if int(event.assigned_unit) < 0 and sim.elapsed - float(event.started_at) > 6.0:
				for unit: Dictionary in sim.units:
					if unit.kind == event.clear_kind and unit.state == "idle":
						if sim.clear_road(int(event.id), int(unit.id)): return
	var calls: Array[Dictionary] = []
	for incident: Dictionary in sim.incidents:
		if incident.status in ["active", "working"] and sim.elapsed - float(incident.created_at) > 6.0: calls.append(incident)
	calls.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.id) < int(y.id))
	for incident: Dictionary in calls:
		if not bool(incident.discovered):
			if sim.scout(int(incident.id)): return
			continue
		for kind: String in Sim.UNIT_KINDS:
			if sim.assigned_kind_count(incident, kind) < int(incident.needs.get(kind, 0)) and sim.available_count(kind) > 0:
				if sim.dispatch(int(incident.id), kind): return
