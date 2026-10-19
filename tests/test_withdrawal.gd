extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Campaign = preload("res://scripts/campaign.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_test_on_scene_withdrawal()
	_test_travelling_withdrawal()
	_test_road_withdrawal(false)
	_test_road_withdrawal(true)
	_test_invalid_requests()
	if failures.is_empty():
		print("PASS: on-scene and travelling withdrawal, reassignment, road cancellation, snapshots and invalid requests")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _quiet_shift() -> RescueSimulation:
	var sim := Sim.new()
	sim.start_shift(0)
	for key: String in ["arrival_schedule", "chaos_phases", "disruptions", "traffic"]: sim._shift[key] = []
	return sim

func _incident(sim: RescueSimulation, location: int, needs: Dictionary) -> Dictionary:
	sim._spawn_incident(location, "fire")
	var incident: Dictionary = sim.incidents.back()
	incident.needs = needs
	incident.discovered = true
	incident.deadline = 500.0
	incident.max_deadline = 500.0
	incident.work_duration = 100.0
	return incident

func _crew(sim: RescueSimulation, kind: String) -> Dictionary:
	for unit: Dictionary in sim.units:
		if unit.kind == kind and unit.state == "idle": return unit
	return {}

func _test_on_scene_withdrawal() -> void:
	var sim := _quiet_shift()
	var incident: Dictionary = _incident(sim, 0, {"fire": 1, "medic": 1})
	var fire: Dictionary = _crew(sim, "fire")
	var medic: Dictionary = _crew(sim, "medic")
	_check(sim.dispatch(int(incident.id), "fire", int(fire.id)), "Fire dispatch must succeed")
	_check(sim.dispatch(int(incident.id), "medic", int(medic.id)), "Medic dispatch must succeed")
	while float(incident.progress) < 0.05 and sim.elapsed < 60.0: sim.tick(0.1)
	_check(fire.state == "working" and float(incident.progress) > 0.0, "Withdrawal test must begin with crews working on scene")
	var progress: float = float(incident.progress)
	var deadline: float = float(incident.deadline)
	var position: Vector2 = fire.pos
	sim.drain_events()
	_check(sim.can_withdraw(int(fire.id)) and sim.withdraw(int(fire.id)), "An on-scene crew can be withdrawn")
	_check(fire.state == "return" and int(fire.target) == -1, "Withdrawn crew must head home without an incident target")
	_check(fire.pos == position, "Withdrawal must not teleport the crew")
	_check(not incident.assigned.has(int(fire.id)) and incident.assigned.has(int(medic.id)), "Withdrawal removes only the selected crew from the scene")
	_check(sim.assigned_kind_count(incident, "fire") == 0 and bool(sim.incident_estimate(int(incident.id)).team_incomplete), "Call estimates immediately reflect the missing crew")
	_check(int(fire.jobs) == 0 and sim.resolved_count == 0 and sim.score == 0, "Withdrawal must not count as completed work or grant rewards")
	var events: Array[Dictionary] = sim.drain_events()
	_check(events.size() == 1 and str(events[0].type) == "unit_withdrawn", "Withdrawal emits one dedicated event")
	if events.size() == 1:
		_check(int(events[0].unit_id) == int(fire.id) and str(events[0].kind) == "fire" and int(events[0].incident_id) == int(incident.id) and int(events[0].road_event_id) == -1, "Withdrawal event identifies the previous assignment")
		_check(events[0].pos == position and not str(events[0].text).is_empty(), "Withdrawal event includes its location and a player-facing message")
	sim.tick(1.0)
	_check(is_equal_approx(float(incident.progress), progress), "Withdrawn crew must stop contributing to incident progress")
	_check(float(incident.deadline) < deadline, "An incomplete call's deadline must keep counting down")
	var next_call: Dictionary = _incident(sim, 1, {"fire": 1})
	_check(sim.dispatch(int(next_call.id), "fire", int(fire.id)), "Withdrawn crew can be redirected to a new scene")
	sim.tick(0.8)
	var replacement: Dictionary = _crew(sim, "fire")
	_check(sim.dispatch(int(incident.id), "fire", int(replacement.id)), "The former scene can receive a replacement crew")
	incident.work_duration = 1.0
	var until: float = sim.elapsed + 60.0
	while sim._is_active(incident) and sim.elapsed < until: sim.tick(0.1)
	_check(incident.status == "resolved", "A replacement crew must be able to finish the abandoned work")
	_check(int(fire.target) == int(next_call.id) and str(fire.state) in ["travel", "working"], "Resolving the former scene must not recall a withdrawn crew from its new call")
	_check(int(fire.jobs) == 0 and int(replacement.jobs) == 1, "Only the replacement receives the completed-job count")

func _test_travelling_withdrawal() -> void:
	var sim := _quiet_shift()
	var incident: Dictionary = _incident(sim, 0, {"fire": 1})
	var crew: Dictionary = _crew(sim, "fire")
	sim.dispatch(int(incident.id), "fire", int(crew.id))
	sim.tick(1.1)
	_check(crew.state == "travel" and sim.withdraw(int(crew.id)), "A travelling crew can also be withdrawn")
	_check(incident.assigned.is_empty() and incident.status == "active" and incident.phase == "waiting", "A scene with no remaining crews returns to waiting")
	_check(sim._unit_available(crew), "Withdrawal adds no delay beyond the existing dispatch guard")
	for state: Dictionary in [sim.snapshot(), sim.net_snapshot()]:
		var restored := Sim.new()
		restored.apply_snapshot(state)
		var copy: Dictionary = restored.get_unit(int(crew.id))
		_check(copy.state == "return" and int(copy.target) == -1 and restored.get_incident(int(incident.id)).assigned.is_empty(), "Save and network snapshots preserve withdrawn assignments")
	_check(sim.dispatch(int(incident.id), "fire", int(crew.id)), "A withdrawn crew can be dispatched again while returning")
	_check(incident.assigned.count(int(crew.id)) == 1, "Redispatch must not leave duplicate incident assignments")

func _test_road_withdrawal(on_scene: bool) -> void:
	var sim := _quiet_shift()
	var plan: Dictionary = {}
	for scheduled: Dictionary in Campaign.shift_data(1).traffic:
		if str(scheduled.clear_kind) == "police":
			plan = scheduled.duplicate(true)
			break
	plan.at = 0.0
	plan.call_kind = ""
	plan.duration = 500.0
	plan.clear_time = 20.0
	sim._shift.traffic = [plan]
	sim._tick_road_events()
	var road: Dictionary = sim.road_events[0]
	var crew: Dictionary = _crew(sim, "police")
	_check(sim.clear_road(int(road.id), int(crew.id)), "Road assignment must succeed")
	if on_scene:
		while crew.state == "travel" and sim.elapsed < 60.0: sim.tick(0.1)
		sim.tick(2.0)
		_check(crew.state == "clearing" and float(road.clear_progress) > 0.0, "Road test must begin after clearing work has started")
	else:
		sim.tick(1.1)
		_check(crew.state == "travel", "Road test must also cover withdrawal before arrival")
	_check(sim.withdraw(int(crew.id)), "A road crew can be withdrawn before or after arriving")
	_check(road.status == "active" and int(road.assigned_unit) == -1 and float(road.clear_progress) == 0.0, "Road withdrawal releases ownership and resets clearing progress")
	_check(float(road.clear_dispatched_at) == -1.0 and float(road.clear_started_at) == -1.0, "Cancelled road assignment timestamps are reset")
	_check(crew.state == "return" and int(crew.clear_target) == -1 and int(crew.jobs) == 0 and sim.roads_cleared == 0, "Cancellation must not complete or credit the road job")
	var restored := Sim.new()
	restored.apply_snapshot(sim.net_snapshot())
	_check(int(restored.get_road_event(int(road.id)).assigned_unit) == -1 and int(restored.get_unit(int(crew.id)).clear_target) == -1, "Network snapshots preserve the released road assignment")
	var replacement: Dictionary = _crew(sim, "police")
	_check(sim.clear_road(int(road.id), int(replacement.id)), "Another crew can immediately take over the road")
	var until: float = sim.elapsed + 80.0
	while str(road.status) in ["active", "clearing"] and sim.elapsed < until: sim.tick(0.1)
	_check(road.status == "cleared" and sim.roads_cleared == 1, "Only the replacement's completed road work is credited")
	_check(int(crew.jobs) == 0 and int(replacement.jobs) == 1, "Cancelled road work must not increment the withdrawn crew's jobs")

func _test_invalid_requests() -> void:
	var sim := _quiet_shift()
	var crew: Dictionary = sim.units[0]
	var before: Dictionary = sim._raw_state()
	_check(not sim.withdraw(-1) and not sim.withdraw(9999) and not sim.withdraw(int(crew.id)), "Missing and idle crews cannot withdraw")
	_check(before == sim._raw_state(), "Invalid withdrawals must not change simulation state or emit events")
	var incident: Dictionary = _incident(sim, 0, {"fire": 1})
	sim.dispatch(int(incident.id), "fire", int(crew.id))
	sim.running = false
	_check(not sim.withdraw(int(crew.id)), "Stopped shifts cannot withdraw crews")
	sim.running = true
	sim.finished = true
	_check(not sim.withdraw(int(crew.id)), "Completed shifts cannot withdraw crews")
	sim.finished = false
	incident.status = "resolved"
	_check(not sim.withdraw(int(crew.id)), "Completed incident assignments cannot be withdrawn")
	incident.status = "working"
	_check(sim.withdraw(int(crew.id)), "An immediate accidental dispatch can be cancelled")
	_check(not sim._unit_available(crew), "Cancellation must preserve the existing one-second dispatch guard")
	_check(not sim.withdraw(int(crew.id)), "Already returning crews cannot withdraw twice")
	crew.state = "rest"
	_check(not sim.can_withdraw(int(crew.id)) and not sim.withdraw(int(crew.id)), "Resting crews cannot withdraw")
