extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Tutorial = preload("res://scripts/tutorial_director.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_test_map_and_routes()
	_test_outer_district_dispatches()
	_test_reproducible_phases()
	_test_busy_group_protocol()
	_test_save_and_network_continuation()
	_test_legacy_coordinates()
	_test_version_3_expansion()
	_test_tutorial()
	_test_playability()
	if failures.is_empty():
		print("PASS: expanded map and district dispatches, deterministic hidden phases/capacity skips, save/network continuation, legacy saves, full tutorial, six-shift playability")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _test_map_and_routes() -> void:
	_check(Campaign.MAP_SIZE == Vector2(2304, 1536), "Navigable world must cover 2304x1536 logical pixels")
	_check(Campaign.MAP_SIZE.x * Campaign.MAP_SIZE.y > 5.0 * 664 * 396, "World must be substantially larger than the earlier expansion")
	var sites: Array[Dictionary] = Campaign.locations()
	# 48 sites from the map expansion + 11 southern/eastern sites added with the station spread (Oct 2026).
	_check(sites.size() == 59, "Expanded town needs 59 playable sites")
	var sim := Sim.new()
	sim.start_shift(0)
	var outer_sites: int = 0
	for site: Dictionary in sites:
		var pixels: Vector2 = site.pos * Campaign.MAP_SIZE
		if pixels.x >= 1536 or pixels.y >= 1024: outer_sites += 1
		_check(Rect2(Vector2.ZERO, Campaign.MAP_SIZE).has_point(pixels), "Site outside map: " + str(site.name))
		_check(pixels.y < 1460, "Call site occupies reserved southern coastline")
		for other: Dictionary in sites:
			if other.name != site.name: _check(pixels.distance_to(other.pos * Campaign.MAP_SIZE) >= 129.99, "Call sites too tightly packed")
		for road: float in Sim.ROAD_X: _check(absf(pixels.x - road * Campaign.MAP_SIZE.x) > 22, "Call entrance lies on a vertical road")
		for road: float in Sim.ROAD_Y: _check(absf(pixels.y - road * Campaign.MAP_SIZE.y) > 22, "Call entrance lies on a horizontal road")
		for crew: Dictionary in sim.units:
			var route: Dictionary = sim._best_route(crew, crew.home, site.pos)
			_check(is_finite(float(route.eta)) and float(route.eta) > 0.0, "Unreachable site: " + str(site.name))
			_check(not route.path.is_empty() and route.path.back().is_equal_approx(site.pos), "Route misses destination")
	_check(outer_sites == 27, "The 27 added sites must occupy geography outside v3")
	var original_positions: Array[Vector2] = [Vector2(256,84),Vector2(512,84),Vector2(512,540),Vector2(1024,836),Vector2(256,276),Vector2(768,84),Vector2(1024,84),Vector2(1024,276),Vector2(256,540),Vector2(512,276),Vector2(768,276),Vector2(1470,836),Vector2(1280,276),Vector2(1024,540),Vector2(256,406),Vector2(512,406),Vector2(1280,84),Vector2(1280,406),Vector2(1024,670),Vector2(1280,836),Vector2(66,836),Vector2(512,836),Vector2(768,836),Vector2(1280,670),Vector2(768,406),Vector2(1024,406),Vector2(768,540),Vector2(1280,540),Vector2(256,670),Vector2(512,670),Vector2(768,670),Vector2(256,836)]
	for index: int in range(32):
		_check((sites[index].pos * Campaign.MAP_SIZE).is_equal_approx(original_positions[index]), "Original city was stretched instead of expanded")
	# Physical speed is uniform in both axes, with practical town crossings.
	var crew: Dictionary = sim.units[0]
	var horizontal: Dictionary = sim._travel_segment(crew, Vector2.ZERO, Vector2(512, 0) / Campaign.MAP_SIZE, 0.0, INF, [])
	var vertical: Dictionary = sim._travel_segment(crew, Vector2.ZERO, Vector2(0, 512) / Campaign.MAP_SIZE, 0.0, INF, [])
	_check(absf(float(horizontal.time) - float(vertical.time)) < 0.001, "Equal physical distances must take equal travel time")
	var crossing: Dictionary = sim._travel_segment(crew, Vector2.ZERO, Vector2(2304, 0) / Campaign.MAP_SIZE, 0.0, INF, [])
	_check(float(crossing.time) > 12 and float(crossing.time) < 20, "Full-town travel must remain meaningful and practical")
	_check(absf(float(crossing.time) / float(horizontal.time) - 4.5) < 0.001, "Travel no longer scales with route distance")

func _test_outer_district_dispatches() -> void:
	for site: Dictionary in Campaign.locations():
		var sim := Sim.new()
		sim.start_shift(0)
		for key: String in ["chaos_phases", "arrival_schedule", "disruptions", "traffic"]: sim._shift[key] = []
		sim._spawn_incident()
		var call: Dictionary = sim.incidents.back()
		call.pos = site.pos
		call.needs = {"fire": 1, "medic": 1, "engineer": 1, "police": 1}
		call.discovered = true
		call.deadline = 150.0
		call.work_duration = 5.0
		for kind: String in Sim.UNIT_KINDS:
			# Exercise every department from its primary station.
			var crew: Dictionary = {}
			for candidate: Dictionary in sim.units:
				if candidate.kind == kind: crew = candidate; break
			_check(sim.dispatch(int(call.id), kind, int(crew.id)), "Dispatch into expanded district rejected")
			for point: Vector2 in crew.path:
				_check(Rect2(Vector2.ZERO, Vector2.ONE).has_point(point), "Route leaves playable map")
		var travel_elapsed := 0.0
		while sim._is_active(call) and travel_elapsed < 150.0:
			sim.tick(0.1)
			travel_elapsed += 0.1
			for crew: Dictionary in sim.units:
				_check(Rect2(Vector2.ZERO, Vector2.ONE).has_point(crew.pos), "Travelling crew left map")
		_check(call.status == "resolved", "Four-department team cannot finish in new district: " + str(site.name))
		_check(travel_elapsed > 8.0, "Expanded district did not require meaningful travel")
		# Intermediate legs must follow an actual connected road; the last leg
		# is the short driveway from that road to the incident entrance.
		var origin := Vector2(384, 448) / Campaign.MAP_SIZE
		var path: Array = sim._best_route(sim.units[0], origin, site.pos).path
		path.push_front(origin)
		for index: int in range(1, path.size() - 1):
			var previous: Vector2 = path[index - 1]
			var current: Vector2 = path[index]
			var horizontal: bool = absf(previous.y - current.y) < 0.00001
			var vertical: bool = absf(previous.x - current.x) < 0.00001
			_check(horizontal or vertical, "Route cuts diagonally through a city block")
			if horizontal: _check(absf(sim._nearest(current.y, Sim.ROAD_Y) - current.y) < 0.00001, "Horizontal route leaves the road grid")
			elif vertical: _check(absf(sim._nearest(current.x, Sim.ROAD_X) - current.x) < 0.00001, "Vertical route leaves the road grid")

func _phase_records(sim: RescueSimulation) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in sim.drain_events():
		_check(event.type not in ["surge_warning", "surge_started", "surge_end"], "Player-facing surge event leaked")
		if event.type == "chaos_phase_changed":
			_check(bool(event.get("research_only", false)) and str(event.get("text", "")) == "", "Phase event must be research-only")
			result.append({"phase": event.phase, "at": event.at, "until": event.until, "version": event.schedule_version})
	return result

func _run_protocol(shift: int, step: float, noisy: bool) -> Array[Dictionary]:
	var sim := Sim.new()
	sim.start_shift(shift)
	var records: Array[Dictionary] = _phase_records(sim)
	while sim.running:
		# Retain the full protocol even if this intentionally passive group loses.
		sim.reputation = 100.0
		if noisy:
			sim._rng.randf()
			if sim.active_count() > 0: _bot_action(sim)
		sim.tick(minf(step, 330.0 - sim.elapsed))
		records.append_array(_phase_records(sim))
	_check(sim.arrival_index == sim._shift.arrival_schedule.size(), "Every scheduled arrival opportunity must be consumed")
	_check(sim.rush_remaining == 0.0 and sim.surge_warning_remaining == 0.0, "Legacy wave indicators must remain inert")
	return records

func _test_reproducible_phases() -> void:
	for shift: int in range(6):
		var passive: Array[Dictionary] = _run_protocol(shift, 0.37, false)
		var active: Array[Dictionary] = _run_protocol(shift, 0.11, true)
		_check(passive == active, "Player actions/RNG/frame cadence changed phase timeline for shift %d" % shift)
		_check(passive.size() == 9, "Expected all nine study phases")
		_check(passive[0].phase == "normal" and float(passive[0].at) == 0.0, "Every shift must begin at normal chaos")
		_check(passive[1].phase == "high" and passive[2].phase == "low", "Opening normal/high/low protocol changed")
		for index: int in range(1, passive.size()):
			_check(passive[index - 1].until == passive[index].at, "Phase schedule has a gap or overlap")

func _test_busy_group_protocol() -> void:
	var sim := Sim.new()
	sim.start_shift(0)
	# Keep six legitimate open calls occupying all normal/high slots for the
	# whole shift; nobody dispatches a crew in this intentionally busy group.
	for index: int in range(6):
		sim._spawn_incident()
		sim.incidents.back().deadline = 10000.0
		sim.incidents.back().max_deadline = 10000.0
	var skipped := 0
	var phase_records: Array[Dictionary] = []
	while sim.running:
		sim.tick(0.1)
		for event: Dictionary in sim.drain_events():
			if event.type == "arrival_capacity_skipped":
				_check(bool(event.get("research_only", false)), "Capacity skip leaked into player events")
				_check(float(event.at) == float(sim._shift.arrival_schedule[skipped].at), "Busy group shifted an arrival opportunity")
				skipped += 1
			elif event.type == "chaos_phase_changed": phase_records.append(event)
	_check(skipped == sim._shift.arrival_schedule.size(), "Busy group silently lost arrival records")
	_check(sim.total_spawned == 6 and phase_records.size() == 9, "Saturated group changed hidden phase progression")

func _test_save_and_network_continuation() -> void:
	var original := Sim.new()
	original.start_shift(2)
	for index: int in range(137):
		original.reputation = 100.0
		original.tick(0.5)
	original.drain_events()
	var saved := Sim.new()
	saved.apply_snapshot(original.snapshot())
	var guest := Sim.new()
	guest.apply_snapshot(original.net_snapshot())
	for index: int in range(160):
		for sim: RescueSimulation in [original, saved, guest]:
			sim.reputation = 100.0
			sim.tick(0.5)
		var expected: Array[Dictionary] = _phase_records(original)
		_check(_phase_records(saved) == expected and _phase_records(guest) == expected, "Snapshot duplicated, skipped or shifted a phase")
		_check(saved.arrival_index == original.arrival_index and guest.arrival_index == original.arrival_index, "Snapshot changed arrival schedule cursor")
		_check(saved.chaos_context() == original.chaos_context() and guest.chaos_context() == original.chaos_context(), "Late join phase context differs")

func _test_legacy_coordinates() -> void:
	for old_version: int in [1, 2]:
		var old := Sim.new()
		old.start_shift(2)
		old._spawn_incident()
		old._spawn_incident()
		old.drain_events()
		var state: Dictionary = old._raw_state()
		state["map_version"] = old_version
		if old_version == 1: state.erase("chaos_schedule_version")
		state["_net"] = true
		state["elapsed"] = 84.0
		var source_size := Vector2(532, 316) if old_version == 1 else Vector2(664, 396)
		state.incidents[0].location_index = 0
		state.incidents[0].name = "Willow Cottage"
		state.incidents[0].pos = Vector2(64, 44) / source_size
		state.incidents[1].location_index = 1
		state.incidents[1].name = "Moonrise Bakery"
		state.incidents[1].pos = Vector2(171, 41) / source_size
		state.units[0].pos = Vector2(95, 100) / source_size
		state.units[0].home = Vector2(95, 139) / source_size
		state.units[0].state = "travel"
		state.units[0].target = int(state.incidents[0].id)
		state.units[0].remaining = 2.0
		state.units[0].path = [Vector2(95, 61) / source_size, state.incidents[0].pos]
		state.units[3].state = "working"
		state.units[3].target = int(state.incidents[1].id)
		state.units[3].pos = state.incidents[1].pos
		state["chaos_phase"] = "low"
		state["chaos_phase_index"] = 2
		var expected_arrival_index := 0
		for arrival: Dictionary in state._shift.arrival_schedule:
			if float(arrival.at) <= 84.0: expected_arrival_index += 1
		state["arrival_index"] = expected_arrival_index
		var migrated := Sim.new()
		migrated.apply_snapshot(state)
		_check(migrated.elapsed == 84.0, "Legacy map migration reset the study clock")
		_check(migrated.incidents[0].pos.is_equal_approx(Campaign.locations()[0].pos), "Legacy incident no longer matches its building")
		_check(migrated.units[0].home.is_equal_approx(migrated._fleet_home("fire", 0)), "Legacy crew station not relocated")
		_check(migrated.units[0].path.back().is_equal_approx(migrated.incidents[0].pos), "Legacy travelling crew route misses relocated incident")
		_check(migrated.units[3].pos.is_equal_approx(migrated.incidents[1].pos), "Legacy working crew left its incident")
		_check(migrated.chaos_phase == "low" and migrated.chaos_phase_index == 2, "Legacy map migration changed study phase")
		_check(migrated.arrival_index == expected_arrival_index, "Legacy map migration replayed previous arrival opportunities")
		_check(migrated.incidents[0].deadline >= state.incidents[0].deadline, "Longer migrated route consumed original decision allowance")
		var second_load := Sim.new()
		second_load.apply_snapshot(migrated.snapshot())
		_check(second_load.units[0].pos.is_equal_approx(migrated.units[0].pos), "Current save was migrated twice")
		_check(second_load.incidents[0].deadline == migrated.incidents[0].deadline, "Current save received migration allowance twice")

func _test_version_3_expansion() -> void:
	var source := Sim.new()
	source.start_shift(0)
	source._spawn_incident()
	source.drain_events()
	var state: Dictionary = source._raw_state()
	state["map_version"] = 3
	state["_net"] = true
	state["elapsed"] = 55.0
	state["chaos_phase"] = "high"
	state["chaos_phase_index"] = 1
	state["arrival_index"] = 4
	var old_size := Vector2(1536,1024)
	state.incidents[0].location_index = 3
	state.incidents[0].pos = Vector2(1024,836) / old_size
	state.incidents[0].name = "North Pier"
	state.units[0].home = Vector2(384,448) / old_size
	state.units[0].pos = Vector2(512,448) / old_size
	state.units[0].state = "travel"
	state.units[0].target = int(state.incidents[0].id)
	state.units[0].path_index = 0
	state.units[0].path = [Vector2(640,448)/old_size,Vector2(640,928)/old_size,Vector2(1024,928)/old_size,Vector2(1024,836)/old_size]
	state._shift.traffic[0].position = Vector2(364,178) / old_size
	state._shift.traffic[0].size = Vector2(40,240) / old_size
	state.events = [{"type":"dispatch","pos":Vector2(512,448)/old_size}]
	var migrated := Sim.new()
	migrated.apply_snapshot(state)
	_check((migrated.incidents[0].pos * Campaign.MAP_SIZE).is_equal_approx(Vector2(1024,836)), "v3 incident teleported during expansion")
	_check((migrated.units[0].pos * Campaign.MAP_SIZE).is_equal_approx(Vector2(512,448)), "v3 moving crew changed physical position")
	_check((migrated.units[0].home * Campaign.MAP_SIZE).is_equal_approx(Vector2(384,448)), "v3 crew home was relocated")
	for index: int in range(state.units[0].path.size()):
		_check((migrated.units[0].path[index] * Campaign.MAP_SIZE).is_equal_approx(state.units[0].path[index] * old_size), "v3 route waypoint was stretched")
	_check((migrated._shift.traffic[0].position * Campaign.MAP_SIZE).is_equal_approx(Vector2(364,178)), "v3 roadworks position changed")
	_check((migrated.events[0].pos * Campaign.MAP_SIZE).is_equal_approx(Vector2(512,448)), "v3 pending spatial event moved")
	_check(migrated.elapsed == 55.0 and migrated.arrival_index == 4 and migrated.chaos_phase == "high", "v3 expansion changed the experimental clock")
	var restored := Sim.new()
	restored.apply_snapshot(migrated.snapshot())
	_check(restored.units[0].pos.is_equal_approx(migrated.units[0].pos), "v4 save was expanded twice")
	var network_state: Dictionary = state.duplicate(true)
	network_state.erase("_shift")
	var guest := Sim.new()
	guest.apply_snapshot(network_state)
	# The guest rebuilds the plan from the campaign (road events since the traffic rework).
	_check(guest._shift.traffic[0].position.is_equal_approx(Campaign.shift_data(guest.shift_index).traffic[0].position), "Rebuilt network plan was scaled twice")

func _tutorial_dispatch(tutorial: TutorialDirector, kind: String, incident_id: int) -> void:
	var sim: RescueSimulation = tutorial.sim
	tutorial.on_action("select", {"incident_id": incident_id})
	for crew: Dictionary in sim.units:
		if crew.kind != kind or not sim._unit_available(crew): continue
		var payload := {"unit_id": int(crew.id), "incident_id": incident_id, "kind": kind}
		tutorial.on_action("select_unit", payload)
		if tutorial.can_action("dispatch", payload):
			var success: bool = sim.dispatch(incident_id, kind, int(crew.id))
			tutorial.on_action("dispatch", payload, success)
			return

func _test_tutorial() -> void:
	var tutorial := Tutorial.new()
	var sim := Sim.new()
	tutorial.begin(sim)
	var test_seconds := 0.0
	var next_action := 0.0
	while not tutorial.finished and test_seconds < 600.0:
		var card: Dictionary = tutorial.current()
		if test_seconds >= next_action:
			next_action += 0.8
			match tutorial.stage:
				Tutorial.Step.SELECT_MEDICAL:
					tutorial.on_action("select", {"incident_id": int(card.focus_id)})
				Tutorial.Step.DISPATCH_MEDIC: _tutorial_dispatch(tutorial, "medic", int(card.focus_id))
				Tutorial.Step.SCOUT_FIRE:
					var id: int = int(card.focus_id)
					tutorial.on_action("select", {"incident_id": id})
					tutorial.on_action("scout", {"incident_id": id}, sim.scout(id))
				Tutorial.Step.READ_MARGIN:
					for crew: Dictionary in sim.units:
						if crew.kind == "fire": tutorial.on_action("select_unit", {"incident_id": int(card.focus_id), "unit_id": int(crew.id)})
					tutorial.advance()
				Tutorial.Step.DISPATCH_FIRE: _tutorial_dispatch(tutorial, "fire", int(card.focus_id))
				Tutorial.Step.SUPPLY_FIRE:
					var id: int = tutorial._fire_id
					if tutorial._crew_on_scene(id): tutorial.on_action("supply", {"incident_id": id}, sim.supply(id))
				Tutorial.Step.DISPATCH_ENGINEER: _tutorial_dispatch(tutorial, "engineer", int(card.focus_id))
				Tutorial.Step.RALLY: tutorial.on_action("special", {}, sim.use_special())
				Tutorial.Step.CHALLENGE:
					for id: int in tutorial._challenge_ids:
						var call: Dictionary = sim.get_incident(id)
						if sim._is_active(call) and call.assigned.is_empty(): _tutorial_dispatch(tutorial, "engineer", id)
						elif sim._is_active(call) and tutorial._crew_on_scene(id) and float(call.deadline) < 30:
							tutorial.on_action("supply", {"incident_id": id}, sim.supply(id))
					if tutorial._challenge_started and sim.special_cooldown <= 0.0: tutorial.on_action("special", {}, sim.use_special())
				Tutorial.Step.OUTCOME:
					_check(tutorial._challenge_won, "Authored tutorial challenge no longer solvable after map expansion")
					if not tutorial._challenge_won: break
					tutorial.advance()
				_:
					if bool(card.can_advance): tutorial.advance()
		for event: Dictionary in sim.drain_events():
			_check(event.type != "chaos_phase_changed", "Authored practice emitted hidden study phases")
		tutorial.tick(0.1)
		test_seconds += 0.1
	_check(tutorial.finished, "Tutorial stalled at stage %d" % tutorial.stage)
	_check(sim.total_spawned == 5, "Authored practice unexpectedly generated ambient calls")
	print("Tutorial: stage %d, practice %.1fs, calls %d, resolved %d" % [tutorial.stage, sim.elapsed, sim.total_spawned, sim.resolved_count])

# One action every 0.8 seconds, no upgrades, no knowledge of hidden call needs.
# This is a regression smoke test for solvability, not a claim of human usability.
func _bot_action(sim: RescueSimulation) -> void:
	if sim.active_count() >= 3 and sim.special_cooldown <= 0.0:
		sim.use_special()
		return
	# Like a team that talks: once a road is closed or a district is dark for a
	# few seconds, the department that can fix it sends a crew.
	for event: Dictionary in sim.active_road_events():
		if int(event.assigned_unit) < 0 and str(event.clear_kind) != "" and sim.elapsed - float(event.started_at) > 4.0:
			for unit: Dictionary in sim.units:
				if unit.kind == event.clear_kind and unit.state == "idle":
					if sim.clear_road(int(event.id), int(unit.id)): return
	var calls: Array[Dictionary] = []
	for incident: Dictionary in sim.incidents:
		if incident.status in ["active", "working"]: calls.append(incident)
	calls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.deadline) < float(b.deadline))
	for incident: Dictionary in calls:
		if not bool(incident.discovered):
			if sim.scout(int(incident.id)): return
			continue
		for kind: String in Sim.UNIT_KINDS:
			if sim.assigned_kind_count(incident, kind) < int(incident.needs.get(kind, 0)) and sim.available_count(kind) > 0:
				if sim.dispatch(int(incident.id), kind): return
		if float(incident.deadline) < 25.0 and sim.supplies > 0:
			if sim.supply(int(incident.id)): return

func _test_playability() -> void:
	for shift: int in range(6):
		var sim := Sim.new()
		sim.start_shift(shift)
		var next_action: float = 2.0
		while sim.running:
			if sim.elapsed >= next_action:
				_bot_action(sim)
				next_action += 0.8
			sim.tick(0.1)
			sim.drain_events()
		print("Shift %d: rescued %d/%d, confidence %.0f, resolved %d, missed %d" % [shift + 1, sim.rescued, sim.target, sim.reputation, sim.resolved_count, sim.failed_count])
		_check(sim.won, "Representative dispatch bot cannot complete shift %d" % (shift + 1))
