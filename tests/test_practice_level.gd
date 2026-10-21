extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Town = preload("res://scripts/town_view.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_test_map()
	_test_no_pressure()
	_test_practice_actions()
	_test_resume()
	_test_research_outcomes()
	if failures.is_empty():
		print("PASS: Level 0 has a connected new map, a deterministic 150-second gentle script, clearable exercises, resumable state and truthful event outcomes")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _test_map() -> void:
	_check(Campaign.shifts().size() == 6 and Campaign.shift_data(0).title == "FIRST LIGHT", "Existing campaign indices remain stable")
	var sim := Sim.new()
	sim.start_shift(Campaign.PRACTICE_INDEX)
	var bounds: Rect2 = Campaign.PRACTICE_BOUNDS
	_check(sim.is_practice() and Campaign.level_number(sim.shift_index) == 0, "Practice uses display level 0")
	_check(Campaign.layout(sim.shift_index).name == "training_harbor", "Practice has its own named layout")
	var sites: int = 0
	for place: Dictionary in Campaign.locations():
		if not Campaign.site_open(sim.shift_index, place.pos): continue
		sites += 1
		_check(bounds.has_point(place.pos * Campaign.MAP_SIZE), "All practice sites belong to the compact island")
		for unit: Dictionary in sim.units:
			_check(bounds.has_point(unit.home * Campaign.MAP_SIZE), "Practice stations are on the island")
			var route: Dictionary = sim._best_route(unit, unit.pos, place.pos)
			_check(is_finite(float(route.eta)) and float(route.eta) < 18.0 and not route.path.is_empty(), "Every crew can reach %s quickly" % place.name)
	_check(sites >= 8 and sites <= 22, "Practice is substantially smaller than the campaign (%d sites)" % sites)
	for arrival: Dictionary in sim._shift.arrival_schedule:
		var site: Dictionary = Campaign.locations()[Campaign.location_index(arrival.site)]
		_check(Campaign.site_open(sim.shift_index, site.pos), "Every scripted practice call is on a valid site")
	for plan: Dictionary in sim._shift.traffic:
		_check(bounds.has_point(sim.road_event_center(plan) * Campaign.MAP_SIZE), "Every exercise is reachable on the island")
	# A flooded practice bridge always leaves another crossing.
	sim.elapsed = 120.0
	_check(sim.flooded_bridges().size() == 1 and sim._bridge_open(6), "The alternate harbor bridge remains open")
	for unit: Dictionary in sim.units:
		var route: Dictionary = sim._best_route(unit, unit.pos, Vector2(1504, 1050) / Campaign.MAP_SIZE)
		_check(is_finite(float(route.eta)), "Crews can reroute around the practice flood")
	var town := Town.new()
	town.set_theme(Campaign.PRACTICE_INDEX)
	_check(town.shift_theme == Campaign.PRACTICE_INDEX and town.theme_index == 0, "Renderer selects the new practice map")
	town.free()

func _run_untouched() -> Dictionary:
	var sim := Sim.new()
	sim.start_shift(Campaign.PRACTICE_INDEX)
	var trace: Array = []
	var starts: Dictionary = {}
	var road_ends: Dictionary = {}
	var incident_ends: int = 0
	while sim.running:
		sim.tick(0.25)
		_check(sim.reputation == 100.0 and sim.failed_count == 0, "Practice never penalizes a player who is still learning")
		_check(sim.active_count() <= 2, "Practice does not stack many calls")
		for event: Dictionary in sim.drain_events():
			_check(event.type not in ["urgent", "critical", "escalated", "failed", "final_minute", "target_reached"], "Practice has no pressure event: %s" % event.type)
			if bool(event.get("research_only", false)):
				_check(int(event.level_number) == 0 and bool(event.practice), "Research identifies practice independently from campaign indices")
				trace.append(event)
			if event.type == "road_event_started": starts[event.event_type] = true
			if event.type == "bridge_flood_started": starts.bridge_flood = true
			if event.type == "road_event_ended":
				road_ends[event.road_event_id] = event
				_check(float(event.ended_at) > float(event.started_at), "Every road exercise has a start and end")
				if bool(event.solvable): _check(event.solved == false and event.outcome == "expired_unsolved", "Unanswered practice exercises are never recorded as player-solved")
				else: _check(event.solved == null and event.outcome == "elapsed", "Weather passing is not recorded as a player solve")
			if event.type == "incident_ended":
				incident_ends += 1
				_check(event.outcome == "practice_handoff" and event.solved == false, "Helpers' calls have an explicit unsolved handoff outcome")
	for type: String in ["jam", "debris", "road_fire", "accident", "blackout", "bridge_flood", "sandstorm", "squall"]:
		_check(starts.has(type), "Practice includes campaign event type %s" % type)
	_check(road_ends.size() == 7 and incident_ends == 4, "Every exercise and call records its ending")
	_check(sim.won and sim.finished and sim.stars == 0 and sim.shift_reward == 0, "Practice always completes without campaign rewards or penalties")
	_check(absf(sim.elapsed - 150.0) < 0.2 and sim.total_spawned == 4, "Practice lasts two and a half minutes with four calls")
	return {"trace": trace, "summary": sim.shift_summary()}

func _test_no_pressure() -> void:
	_check(_run_untouched() == _run_untouched(), "Practice timing, calls and outcomes are deterministic")

func _test_practice_actions() -> void:
	var sim := Sim.new()
	sim.start_shift(Campaign.PRACTICE_INDEX)
	var cleared: int = 0
	var resolved: int = 0
	while sim.running:
		for road: Dictionary in sim.active_road_events():
			if str(road.clear_kind).is_empty() or int(road.assigned_unit) >= 0 or sim.elapsed - float(road.started_at) < 5.0: continue
			for unit: Dictionary in sim.units:
				if unit.kind == road.clear_kind and sim._unit_available(unit):
					sim.clear_road(int(road.id), int(unit.id))
					break
		for incident: Dictionary in sim.incidents:
			if not sim._is_active(incident): continue
			_check(float(incident.deadline) >= 300.0 and float(incident.hazard) == 0.0, "Practice calls have no ticking deadline or escalating hazard")
			if sim.elapsed - float(incident.created_at) < 8.0: continue
			var crews_needed: int = 0
			for kind: String in Sim.UNIT_KINDS:
				crews_needed += int(incident.needs[kind])
				if int(incident.needs[kind]) > sim.assigned_kind_count(incident, kind): sim.dispatch(int(incident.id), kind)
			_check(crews_needed == 1 and bool(incident.discovered), "Practice calls are confirmed and need one crew")
		sim.tick(0.25)
		for event: Dictionary in sim.drain_events():
			if event.type == "road_event_ended" and event.solved == true: cleared += 1
			if event.type == "incident_ended" and event.solved == true: resolved += 1
	_check(cleared == 5 and resolved == 4, "A relaxed player can finish all five clearable exercises and four calls (%d, %d)" % [cleared, resolved])
	for road: Dictionary in sim.road_events:
		if not str(road.clear_kind).is_empty():
			_check(str(road.status) == "cleared", "Practice exercise must be easy to clear: %s (sent %.1f, arrived %.1f, ended %.1f)" % [road.name, road.clear_dispatched_at, road.clear_started_at, road.ended_at])

func _test_resume() -> void:
	var sim := Sim.new()
	sim.start_shift(Campaign.PRACTICE_INDEX)
	sim.tick(94.0)
	sim.drain_events()
	var saved := Sim.new()
	saved.apply_snapshot(sim.snapshot())
	var guest := Sim.new()
	guest.apply_snapshot(bytes_to_var(var_to_bytes(sim.net_snapshot())))
	_check(saved.is_practice() and guest.is_practice() and guest.duration == 150.0, "Save and multiplayer snapshots retain practice identity and duration")
	_check(guest._layout.name == "training_harbor" and guest.active_road_events().size() == sim.active_road_events().size(), "Guests and resumed players share the same map and hazards")
	sim.tick(56.5)
	saved.tick(56.5)
	_check(sim.shift_summary() == saved.shift_summary(), "A resumed practice has the same outcome")

func _test_research_outcomes() -> void:
	var sim := Sim.new()
	sim.start_shift(3)
	sim._shift.arrival_schedule = []
	sim.tick(43.0)
	var road: Dictionary = sim.active_road_events()[0]
	_check(road.type == "blackout", "Lifecycle test reaches the campaign blackout")
	sim._spawn_incident(Campaign.location_index("Community Hall"), "fire")
	var unresolved_id: int = int(sim.incidents.back().id)
	sim.drain_events()
	sim._finish_shift()
	_check(sim.get_incident(unresolved_id).get("outcome") == "level_ended_unsolved", "Snapshots retain the reason an unfinished incident closed")
	var road_ended := false
	var incident_ended := false
	for event: Dictionary in sim.drain_events():
		if event.type == "road_event_ended":
			road_ended = int(event.road_event_id) == int(road.id) and event.event_type == "blackout" and event.solved == false and event.outcome == "level_ended_unsolved"
		if event.type == "incident_ended":
			incident_ended = int(event.incident_id) == unresolved_id and event.solved == false and event.outcome == "level_ended_unsolved" and event.has("needs")
	_check(road_ended and incident_ended, "Ending a level closes unresolved calls and power outages truthfully")
	var subtype := Sim.new()
	subtype.start_shift(0)
	subtype.drain_events()
	subtype._emit_research("hazard_forecast", {"type": "blackout", "at": 12.0})
	var record: Dictionary = subtype.drain_events()[0]
	_check(record.type == "hazard_forecast" and record.event_type == "blackout", "Lifecycle and hazard subtype are both retained")
