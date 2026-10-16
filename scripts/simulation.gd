class_name RescueSimulation
extends RefCounted

const Campaign = preload("res://scripts/campaign.gd")
const UNIT_KINDS: Array[String] = ["fire", "medic", "engineer", "police"]
const INCIDENT_KINDS: Array[String] = ["fire", "medical", "flood", "power", "police"]
# Countdowns tick in real seconds, so each call's deadline includes the time the crews need to work on scene.
const WORK_TIME_ALLOWANCE := 1.35
const CREWS_PER_DEPARTMENT := 3
# Every department has the same number of crews, so every player carries the
# same load (playtest 15.10): 3 each in levels 1-3, 4 each in levels 4-6.
# See Campaign.crews_per_department().
const CREWS_BY_DEPARTMENT := {"fire": 3, "medic": 3, "engineer": 3, "police": 3}
const ROAD_X: Array[float] = [96.0 / 2752, 352.0 / 2752, 608.0 / 2752, 864.0 / 2752, 1120.0 / 2752, 1376.0 / 2752, 1632.0 / 2752, 1888.0 / 2752, 2144.0 / 2752, 2400.0 / 2752, 2656.0 / 2752]
const ROAD_Y: Array[float] = [192.0 / 1536, 448.0 / 1536, 704.0 / 1536, 928.0 / 1536, 1184.0 / 1536, 1440.0 / 1536]
# The new navigable world has larger buildings and streets. Use one uniform
# physical speed in both axes, calibrated to cross the full width in 19.2s.
# More pixels add navigable detail, not a proportional penalty to every rescue.
const WORLD_DISTANCE_SCALE := Campaign.MAP_SIZE / Vector2(1024, 1024)

var shift_index: int = 0
var elapsed: float = 0.0
var duration: float = 330.0
var running: bool = false
var finished: bool = false
var won: bool = false
var score: int = 0
var reputation: float = 100.0
var rescued: int = 0
var combo: int = 0
var best_combo: int = 0
var credits: int = 0
var incidents: Array[Dictionary] = []
var units: Array[Dictionary] = []
var events: Array[Dictionary] = []
var upgrades: Dictionary = {}
var weather: String = "clear"
var notice: String = "Welcome to Beacon Bay"
var supplies: int = 3
var max_supplies: int = 3
var supply_regen: float = 0.0
var special_cooldown: float = 0.0
var special_duration: float = 0.0
var disruption: String = ""
var disruption_remaining: float = 0.0
var resolved_count: int = 0
var failed_count: int = 0
var total_spawned: int = 0
var stars: int = 0
var target: int = 30
var minimum_confidence: float = 50.0
var shift_reward: int = 0
var rush_remaining: float = 0.0
var successful_dispatches: int = 0
var scout_count: int = 0
var supply_count: int = 0
var breather_remaining: float = 0.0
var surge_warning_remaining: float = 0.0
var surge_count: int = 0
var escalation_count: int = 0
var rapid_response_count: int = 0
var peak_active: int = 0
var scout_cooldown: float = 0.0
var dispatch_cooldown: float = 0.0
var department_cooldowns: Dictionary = {}
var wrong_dispatches: int = 0
var last_action_effect: Dictionary = {}
var chaos_phase: String = "normal"
var chaos_phase_index: int = -1
var arrival_index: int = 0
# Road events (traffic rework): the active and finished blockages of this shift.
var road_events: Array[Dictionary] = []
var _road_event_index: int = 0
var roads_cleared: int = 0
var _ignore_road_events := false
# Level layout (see Campaign.layout): empty = the normal full road grid.
var _layout: Dictionary = {}
var _edge_cache: Dictionary = {}
var _blocked_edges: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _shift: Dictionary = {}
var _next_spawn: float = 2.8
var _next_id: int = 1
var _disruption_index: int = 0
var _reported_final_minute: bool = false
var _reported_target: bool = false
var _previous_spawn_location: int = -1
var _surge_index: int = 0
var _surge_warned_index: int = -1
var _surge_pending: int = 0
var _surge_spawn_timer: float = 0.0
var _surge_breather_length: float = 0.0

func start_shift(index: int) -> void:
	shift_index = clampi(index, 0, 5)
	_shift = Campaign.shift_data(shift_index)
	_rng.seed = 738291 + shift_index * 1097
	elapsed = 0.0
	duration = 330.0
	running = true
	finished = false
	won = false
	score = 0
	reputation = 100.0
	rescued = 0
	combo = 0
	best_combo = 0
	incidents.clear()
	units.clear()
	events.clear()
	weather = str(_shift.weather)
	notice = str(_shift.introduction)
	max_supplies = 3 + upgrade_level("supplies")
	supplies = max_supplies
	supply_regen = 0.0
	special_cooldown = 0.0
	special_duration = 0.0
	disruption = ""
	disruption_remaining = 0.0
	resolved_count = 0
	failed_count = 0
	total_spawned = 0
	stars = 0
	target = int(_shift.target)
	minimum_confidence = 50.0
	shift_reward = 0
	rush_remaining = 0.0
	successful_dispatches = 0
	scout_count = 0
	supply_count = 0
	breather_remaining = 0.0
	surge_warning_remaining = 0.0
	surge_count = 0
	escalation_count = 0
	rapid_response_count = 0
	peak_active = 0
	scout_cooldown = 0.0
	dispatch_cooldown = 0.0
	department_cooldowns = {}
	wrong_dispatches = 0
	last_action_effect = {}
	chaos_phase = "normal"
	chaos_phase_index = -1
	arrival_index = 0
	road_events = []
	_road_event_index = 0
	roads_cleared = 0
	_set_layout()
	_next_spawn = 2.8
	_next_id = 1
	_disruption_index = 0
	_reported_final_minute = false
	_reported_target = false
	_previous_spawn_location = -1
	_surge_index = 0
	_surge_warned_index = -1
	_surge_pending = 0
	_surge_spawn_timer = 0.0
	_surge_breather_length = 0.0
	_build_fleet()
	_emit("shift_started", notice, {"shift": shift_index})
	_tick_chaos_schedule()

func tick(delta: float) -> void:
	if not running or finished:
		return
	
	var left: float = maxf(0.0, delta)
	while left > 0.0 and running:
		var step: float = minf(left, 0.1)
		_tick_step(step)
		left -= step

func _tick_step(delta: float) -> void:
	elapsed += delta
	special_cooldown = maxf(0.0, special_cooldown - delta)
	special_duration = maxf(0.0, special_duration - delta)
	scout_cooldown = maxf(0.0, scout_cooldown - delta)
	dispatch_cooldown = maxf(0.0, dispatch_cooldown - delta)
	for department: String in department_cooldowns.keys():
		department_cooldowns[department] = maxf(0.0, float(department_cooldowns[department]) - delta)
	_tick_chaos_schedule()
	if disruption_remaining > 0.0:
		disruption_remaining = maxf(0.0, disruption_remaining - delta)
		if disruption_remaining <= 0.0:
			disruption = ""
			_emit("disruption_end", "Conditions improving • keep going")
	var schedule: Array = _shift.get("disruptions", [])
	if _disruption_index < schedule.size() and elapsed >= float(schedule[_disruption_index].at):
		_start_disruption(schedule[_disruption_index])
		_disruption_index += 1
	if supplies < max_supplies and disruption != "shortage":
		supply_regen += delta
		if supply_regen >= supply_interval():
			supply_regen = 0.0
			supplies += 1
			_emit("supply_ready", "Fresh supplies have arrived")
	elif supplies >= max_supplies:
		supply_regen = 0.0
	_tick_arrivals()
	_tick_hazard_warnings(delta)
	_tick_road_events()
	_tick_floods(delta)
	for unit: Dictionary in units:
		_tick_unit(unit, delta)
	for incident: Dictionary in incidents:
		_tick_incident(incident, delta)
	peak_active = maxi(peak_active, active_count())
	if not _reported_target and rescued >= target:
		_reported_target = true
		_emit("target_reached", "Rescue goal reached • keep the bay safe", {"rescued": rescued})
	if not _reported_final_minute and elapsed >= duration - 60.0:
		_reported_final_minute = true
		_emit("final_minute", "One minute until relief • finish strong")
	if reputation <= 0.0 or elapsed >= duration:
		_finish_shift()
	elif _all_work_done():
		# Every scheduled call and road event has happened and nothing is left
		# open: end now instead of waiting out the clock.
		_emit("all_clear", "Every call handled • shift complete")
		_emit_research("shift_ended_early", {"shift": shift_index, "at": elapsed, "seconds_saved": duration - elapsed})
		_finish_shift()

func _tick_chaos_schedule() -> void:
	var schedule: Array = _shift.get("chaos_phases", [])
	while chaos_phase_index + 1 < schedule.size() and elapsed + 0.000001 >= float(schedule[chaos_phase_index + 1].at):
		chaos_phase_index += 1
		chaos_phase = str(schedule[chaos_phase_index].phase)
		var record: Dictionary = chaos_context()
		record["observed_elapsed"] = elapsed
		_emit_research("chaos_phase_changed", record)

# This information is for the research logger only. No player-facing component
# should render it or use it to anticipate incoming calls.
func chaos_context() -> Dictionary:
	var schedule: Array = _shift.get("chaos_phases", [])
	if chaos_phase_index < 0 or chaos_phase_index >= schedule.size():
		return {}
	var phase: Dictionary = schedule[chaos_phase_index]
	return {"schedule_version": Campaign.CHAOS_SCHEDULE_VERSION,
		"shift": shift_index, "phase": chaos_phase, "phase_index": chaos_phase_index,
		"at": float(phase.at), "until": float(phase.until),
		"duration": float(phase.until) - float(phase.at),
		"campaign_at": shift_index * Campaign.SHIFT_SECONDS + float(phase.at)}

func _tick_arrivals() -> void:
	var schedule: Array = _shift.get("arrival_schedule", [])
	while arrival_index < schedule.size() and elapsed + 0.000001 >= float(schedule[arrival_index].at):
		var scheduled: Dictionary = schedule[arrival_index]
		var capacity: int = int(_shift.max_active) + (1 if chaos_phase == "high" else 0)
		if active_count() < capacity:
			_spawn_incident()
		else:
			# Never move the next phase or arrival because a group is busy. The
			# skipped opportunity is retained in research data for comparison.
			_emit_research("arrival_capacity_skipped", {"schedule_version": Campaign.CHAOS_SCHEDULE_VERSION,
				"shift": shift_index, "at": float(scheduled.at), "arrival_index": arrival_index,
				"phase_index": int(scheduled.phase_index), "active_calls": active_count()})
		arrival_index += 1

func _emit_research(type: String, payload: Dictionary) -> void:
	var record: Dictionary = {"type": type, "text": "", "research_only": true}
	record.merge(payload)
	events.append(record)

func dispatch(incident_id: int, unit_kind: String, unit_id: int = -1) -> bool:
	if not running:
		return false
	var incident: Dictionary = get_incident(incident_id)
	if incident.is_empty() or not _is_active(incident):
		return false
	if unit_kind == "medical":
		unit_kind = "medic"
	if unit_kind not in UNIT_KINDS:
		return false
	if float(department_cooldowns.get(unit_kind, 0.0)) > 0.0:
		_emit("action_denied", "%s radio is transmitting • one order at a time" % kind_name(unit_kind))
		return false
	
	
	var duplicate_limit: int = maxi(1, int(incident.needs.get(unit_kind, 0))) if bool(incident.discovered) else 1
	if assigned_kind_count(incident, unit_kind) >= duplicate_limit:
		_emit("action_denied", "%s crew already committed to this call" % kind_name(unit_kind))
		return false
	var selected: Dictionary = {}
	var best_eta: float = INF
	var selected_path: Array[Vector2] = []
	for unit: Dictionary in units:
		if unit.kind == unit_kind and _unit_available(unit) and (unit_id < 0 or int(unit.id) == unit_id):
			var route: Dictionary = _best_route(unit, unit.pos, incident.pos)
			if float(route.eta) < best_eta:
				best_eta = float(route.eta)
				selected = unit
				selected_path.assign(route.path)
	if selected.is_empty():
		_emit("action_denied", "All %s crews are busy • supplies can buy time" % kind_name(unit_kind).to_lower())
		return false
	var diverting: bool = selected.state == "return"
	selected.target = incident_id
	selected.state = "travel"
	selected.arrival_at = -1.0
	selected.work_elapsed = 0.0
	selected.work_phase = "travel"
	selected.assignment_suitable = int(incident.needs.get(unit_kind, 0)) > 0
	if not bool(selected.assignment_suitable):
		wrong_dispatches += 1
	selected.inspection_remaining = 0.0
	selected.dispatch_guard_until = elapsed + 1.0
	selected.path = selected_path
	selected.path_index = 0
	selected.remaining = best_eta
	department_cooldowns[unit_kind] = 0.65
	incident.assigned.append(int(selected.id))
	incident.status = "working"
	incident.last_action = elapsed
	successful_dispatches += 1
	_emit("dispatch", "%s %s to %s • %ds arrival" % [selected.get("crew_name", selected.name), "diverting" if diverting else "en route", incident.name, ceili(best_eta)], {"incident_id": incident_id, "unit_id": selected.id, "kind": unit_kind, "pos": incident.pos, "diverted": diverting, "eta": best_eta})
	if bool(incident.discovered) and elapsed - float(incident.created_at) <= 8.0 and not bool(incident.get("rapid_response", false)):
		var all_assigned: bool = true
		for kind: String in UNIT_KINDS:
			if assigned_kind_count(incident, kind) < int(incident.needs.get(kind, 0)):
				all_assigned = false
		if all_assigned:
			incident.rapid_response = true
			incident.work_bonus = float(incident.work_bonus) + 0.1
			rapid_response_count += 1
			_emit("rapid_response", "Rapid response • crews can work faster", {"incident_id": incident_id, "pos": incident.pos})
	return true

func can_withdraw(unit_id: int) -> bool:
	if not running or finished:
		return false
	var unit: Dictionary = get_unit(unit_id)
	if unit.is_empty() or str(unit.state) not in ["travel", "working", "clearing"]:
		return false
	var road_id: int = int(unit.get("clear_target", -1))
	if road_id >= 0:
		var road: Dictionary = get_road_event(road_id)
		return str(unit.state) in ["travel", "clearing"] and not road.is_empty() and str(road.status) in ["active", "clearing"] and int(road.assigned_unit) == unit_id
	var incident: Dictionary = get_incident(int(unit.target))
	return str(unit.state) in ["travel", "working"] and not incident.is_empty() and _is_active(incident) and incident.assigned.has(unit_id)

# Cancel the assignment without completing it. Returning crews remain available
# for a new order under the same radio/dispatch guards as any returning crew.
func withdraw(unit_id: int) -> bool:
	if not can_withdraw(unit_id):
		return false
	var unit: Dictionary = get_unit(unit_id)
	var incident_id: int = int(unit.target)
	var road_id: int = int(unit.get("clear_target", -1))
	var destination_name: String = ""
	if road_id >= 0:
		var road: Dictionary = get_road_event(road_id)
		destination_name = str(road.street)
		road.assigned_unit = -1
		road.status = "active"
		road.clear_dispatched_at = -1.0
		road.clear_started_at = -1.0
		road.clear_progress = 0.0
	else:
		var incident: Dictionary = get_incident(incident_id)
		destination_name = str(incident.name)
		incident.assigned.erase(unit_id)
		incident.last_action = elapsed
		if incident.assigned.is_empty():
			incident.status = "active"
			incident.phase = "waiting"
	_send_home(unit, false)
	unit.arrival_at = -1.0
	unit.work_elapsed = 0.0
	unit.inspection_remaining = 0.0
	unit.assignment_suitable = true
	_emit("unit_withdrawn", "%s withdrawn from %s • returning to standby" % [unit.get("crew_name", unit.name), destination_name],
		{"unit_id": unit_id, "kind": unit.kind, "incident_id": incident_id, "road_event_id": road_id, "pos": unit.pos})
	return true

func scout(incident_id: int) -> bool:
	# Scouting only reveals what an unconfirmed report needs. It gives no extra time.
	if not running:
		return false
	var incident: Dictionary = get_incident(incident_id)
	if incident.is_empty() or not _is_active(incident):
		return false
	if bool(incident.get("discovered", true)):
		_emit("action_denied", "This call is already confirmed • nothing to scout")
		return false
	if scout_cooldown > 0.0:
		_emit("action_denied", "Field team ready in %ds" % ceili(scout_cooldown))
		return false
	incident.discovered = true
	incident.scouted = true
	incident.last_action = elapsed
	scout_count += 1
	scout_cooldown = maxf(3.0, 8.0 - 2.5 * upgrade_level("scouting"))
	last_action_effect = {"action": "scout", "incident_id": incident_id, "time_added": 0.0}
	var needed: Array[String] = []
	for kind: String in UNIT_KINDS:
		if int(incident.needs.get(kind, 0)) > 0: needed.append(kind_name(kind).to_lower())
	_emit("scout", "Field report • %s needs %s" % [incident.name, " + ".join(needed)], {"incident_id": incident_id, "pos": incident.pos, "time_added": 0.0})
	return true

func supply(incident_id: int) -> bool:
	if not running:
		return false
	var incident: Dictionary = get_incident(incident_id)
	if incident.is_empty() or not _is_active(incident):
		return false
	var crew_on_scene: bool = false
	for id: int in incident.assigned:
		var crew: Dictionary = get_unit(id)
		if not crew.is_empty() and crew.state == "working" and bool(crew.get("assignment_suitable", true)):
			crew_on_scene = true
	if not crew_on_scene:
		_emit("action_denied", "Supplies go to a crew on scene • send a crew first")
		return false
	if supplies <= 0:
		_emit("action_denied", "Supplies are replenishing")
		return false
	if int(incident.get("supply_count", 0)) >= 2:
		_emit("action_denied", "This call already has all the supplies it can use")
		return false
	var before_deadline: float = float(incident.deadline)
	var before_hazard: float = float(incident.get("hazard", 0.0))
	var before_work: float = _current_work_seconds(incident)
	supplies -= 1
	incident.supply_count = int(incident.supply_count) + 1
	incident.deadline = maxf(float(incident.deadline), minf(float(incident.max_deadline) + 32.0, float(incident.deadline) + 18.0))
	incident.work_bonus = float(incident.work_bonus) + 0.3
	incident.last_action = elapsed
	incident.hazard = maxf(0.0, float(incident.get("hazard", 0.0)) - 0.3)
	incident.stabilized_until = elapsed + 12.0
	supply_count += 1
	last_action_effect = {"action": "supply", "incident_id": incident_id, "time_added": float(incident.deadline) - before_deadline, "hazard_reduced": before_hazard - float(incident.hazard), "work_bonus_added": 0.3, "work_seconds_saved": maxf(0.0, before_work - _current_work_seconds(incident)), "estimated": true}
	var supply_effect: Dictionary = last_action_effect.duplicate(true)
	supply_effect.pos = incident.pos
	_emit("supply", "Supply drop • +%ds, danger reduced, rescue faster" % int(last_action_effect.time_added), supply_effect)
	return true

func use_special() -> bool:
	if not running or special_cooldown > 0.0:
		return false
	special_duration = 20.0
	special_cooldown = 95.0 - 15.0 * upgrade_level("rally")
	for incident: Dictionary in incidents:
		if _is_active(incident):
			incident.deadline = maxf(float(incident.deadline), minf(float(incident.max_deadline) + 16.0, float(incident.deadline) + 8.0))
	reputation = minf(100.0, reputation + 3.0)
	_emit("rally", "Coffee boost! • every crew moves and works faster for 20 seconds")
	return true

func buy_upgrade(_id: String) -> bool:
	return false # the workshop was removed

# The workshop was removed (Oct 2026): crews are never upgraded, so every
# session plays with the same crews. Old saves may still hold upgrades; they
# are ignored.
func upgrade_level(_id: String) -> int:
	return 0

func supply_interval() -> float:
	return 45.0 - 5.0 * upgrade_level("supplies")

func get_incident(id: int) -> Dictionary:
	for incident: Dictionary in incidents:
		if int(incident.id) == id:
			return incident
	return {}

func get_unit(id: int) -> Dictionary:
	for unit: Dictionary in units:
		if int(unit.id) == id:
			return unit
	return {}

func active_count() -> int:
	var count: int = 0
	for incident: Dictionary in incidents:
		if _is_active(incident):
			count += 1
	return count

func available_count(kind: String) -> int:
	var count: int = 0
	for unit: Dictionary in units:
		if unit.kind == kind and _unit_available(unit):
			count += 1
	return count

func pressure_level() -> float:
	var urgent: int = 0
	var hazard_total: float = 0.0
	for incident: Dictionary in incidents:
		if _is_active(incident):
			hazard_total += float(incident.get("hazard", 0.0))
			if float(incident.deadline) < 20.0:
				urgent += 1
	return clampf(float(active_count()) * 0.11 + hazard_total * 0.075 + urgent * 0.1 , 0.0, 1.0)

func next_surge_in() -> float:
	var surges: Array = _shift.get("surges", [])
	if _surge_index >= surges.size():
		return -1.0
	return maxf(0.0, float(surges[_surge_index].at) - elapsed)

func assigned_kind_count(incident: Dictionary, kind: String) -> int:
	var count: int = 0
	for id: int in incident.assigned:
		var unit: Dictionary = get_unit(id)
		if not unit.is_empty() and unit.kind == kind and int(unit.target) == int(incident.id) and unit.state in ["travel", "working"]:
			count += 1
	return count

func dispatch_options(incident_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var incident: Dictionary = get_incident(incident_id)
	if incident.is_empty() or not _is_active(incident):
		return result
	for unit: Dictionary in units:
		if not _unit_available(unit):
			continue
		var route: Dictionary = _best_route(unit, unit.pos, incident.pos)
		var estimate: Dictionary = _completion_estimate(incident, unit, float(route.eta))
		result.append({"unit_id": int(unit.id), "kind": str(unit.kind), "name": str(unit.get("crew_name", unit.name)), "pos": unit.pos, "path": route.path, "eta": float(route.eta), "work_eta": estimate.work_eta, "finish_eta": estimate.finish_eta, "margin": estimate.margin, "suitable": int(incident.needs.get(unit.kind, 0)) > 0, "known": bool(incident.discovered), "team_incomplete": estimate.team_incomplete, "fatigue": float(unit.fatigue)})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.eta) < float(b.eta))
	return result

func incident_estimate(incident_id: int) -> Dictionary:
	var incident: Dictionary = get_incident(incident_id)
	if incident.is_empty():
		return {"eta": -1.0, "work_eta": -1.0, "finish_eta": -1.0, "margin": -1.0, "known": false, "team_incomplete": true}
	return _completion_estimate(incident)

func unit_eta(unit: Dictionary) -> float:
	if unit.is_empty():
		return -1.0
	if unit.state in ["travel", "return"]:
		var pending: Array[Vector2] = []
		var path: Array = unit.get("path", [])
		for index: int in range(int(unit.get("path_index", 0)), path.size()):
			pending.append(path[index])
		return _route_eta(unit, unit.pos, pending)
	if unit.state == "rest":
		return float(unit.remaining)
	if unit.state == "working":
		if not bool(unit.get("assignment_suitable", true)):
			return maxf(0.0, 5.6 - float(unit.get("work_elapsed", 0.0)))
		return maxf(0.0, 1.6 - float(unit.get("work_elapsed", 0.0)))
	return 0.0

func road_conditions() -> Array[Dictionary]:
	# Only road events slow traffic now. The old passive zones (school crossing,
	# harbor deliveries, market queues, bridge works, flooded road) are gone:
	# they cost time without asking anyone to decide anything.
	var result: Array[Dictionary] = []
	for event: Dictionary in road_events:
		if str(event.status) not in ["active", "clearing"]: continue
		# Deadlines ignore closures the team can clear, but weather nobody can
		# clear (sandstorms, squalls) is part of every countdown it touches.
		if _ignore_road_events and not str(event.clear_kind).is_empty(): continue
		result.append({"name": event.name, "position": event.position, "size": event.size,
			"speed_factor": float(event.speed_factor), "remaining": float(event.expires_at) - elapsed,
			"pass_kind": str(event.clear_kind), "road_event_id": int(event.id), "type": str(event.type)})
	return result

func _all_work_done() -> bool:
	# Only shifts that run on the arrival schedule can end early (not the tutorial
	# or tests that clear the schedule).
	var schedule: Array = _shift.get("arrival_schedule", [])
	if schedule.is_empty() or elapsed < 60.0: return false
	if arrival_index < schedule.size(): return false
	if _road_event_index < (_shift.get("traffic", []) as Array).size(): return false
	if active_count() > 0: return false
	for unit: Dictionary in units:
		if str(unit.state) in ["travel", "working", "clearing"]: return false
	return true

func get_road_event(event_id: int) -> Dictionary:
	for event: Dictionary in road_events:
		if int(event.id) == event_id: return event
	return {}

func active_road_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in road_events:
		if str(event.status) in ["active", "clearing"]: result.append(event)
	return result

func road_event_center(event: Dictionary) -> Vector2:
	# Blackouts are fixed at their substation, not the middle of the district.
	if event.has("target"): return Vector2(event.target)
	return Vector2(event.position) + Vector2(event.size) * 0.5

func _hazard_text(event: Dictionary) -> String:
	match str(event.type):
		"blackout": return "%s • calls there can't be seen and crews crawl. An engineer at the substation brings the lights back" % event.name
		"sandstorm": return "%s • everyone drives slowly there and new calls are hard to see" % event.name
		"squall": return "%s • everyone drives slowly there and new calls are hard to see" % event.name
	return str(event.name)

func _tick_road_events() -> void:
	var schedule: Array = _shift.get("traffic", [])
	while _road_event_index < schedule.size() and elapsed + 0.000001 >= float(schedule[_road_event_index].at):
		var plan: Dictionary = schedule[_road_event_index]
		_road_event_index += 1
		if not plan.has("clear_kind"): continue # an old-style slow zone from a saved game
		var event: Dictionary = {"id": int(plan.id), "type": str(plan.type), "clear_kind": str(plan.clear_kind),
			"name": str(plan.name), "street": str(plan.get("street", "")), "position": plan.position, "size": plan.size,
			"speed_factor": float(plan.speed_factor), "clear_time": float(plan.clear_time),
			"started_at": elapsed, "expires_at": elapsed + float(plan.duration), "status": "active",
			"assigned_unit": -1, "clear_dispatched_at": -1.0, "clear_started_at": -1.0, "clear_progress": 0.0,
			"ended_at": -1.0, "chaos_phase": chaos_phase, "linked_incident": -1}
		if plan.has("target"): event["target"] = plan.target
		if bool(plan.get("hazard", false)): event["hazard"] = true
		road_events.append(event)
		# The road event comes with a call on the closed street: the team either
		# clears the road first or crawls through it.
		var site: int = Campaign.location_index(str(plan.get("call_site", "")))
		if site >= 0 and str(plan.get("call_kind", "")) != "":
			# Same capacity rule as every other arrival: a saturated group doesn't
			# get an extra call, and the skip is kept for research.
			var capacity: int = int(_shift.max_active) + (1 if chaos_phase == "high" else 0)
			var site_busy: bool = false
			for open_call: Dictionary in incidents:
				if _is_active(open_call) and int(open_call.location_index) == site: site_busy = true
			if active_count() < capacity and not site_busy:
				_spawn_incident(site, str(plan.call_kind))
				event.linked_incident = int(incidents.back().id)
			else:
				_emit_research("road_call_capacity_skipped", {"road_event_id": int(event.id), "shift": shift_index, "at": elapsed, "active_calls": active_count(), "site_busy": site_busy})
		var who: String = _department_title(str(event.clear_kind))
		if bool(event.get("hazard", false)):
			_emit("hazard_started", _hazard_text(event), {"road_event_id": event.id, "pos": road_event_center(event), "clear_kind": event.clear_kind, "hazard_type": event.type})
		else:
			_emit("road_event", "%s • only %s gets through. Clear it to open the road" % [event.name, who],
				{"road_event_id": event.id, "pos": road_event_center(event), "clear_kind": event.clear_kind})
		_emit_research("road_event_started", _road_event_record(event))
	for event: Dictionary in road_events:
		if str(event.status) in ["active", "clearing"] and elapsed >= float(event.expires_at):
			event.status = "expired"
			event.ended_at = elapsed
			var crew: Dictionary = get_unit(int(event.assigned_unit))
			if not crew.is_empty() and int(crew.get("clear_target", -1)) == int(event.id):
				crew.clear_target = -1
				_send_home(crew)
			var ended: String = "%s has cleared on its own" % event.street
			if str(event.type) == "blackout": ended = "Power is back in %s" % event.street
			elif bool(event.get("hazard", false)): ended = "The %s has passed %s" % [str(event.type), event.street]
			_emit("hazard_ended" if bool(event.get("hazard", false)) else "road_event_end", ended, {"road_event_id": event.id, "pos": road_event_center(event), "hazard_type": event.type})
			_emit_research("road_event_expired", _road_event_record(event))

func _road_event_record(event: Dictionary) -> Dictionary:
	return {"road_event_id": int(event.id), "type": str(event.type), "clear_kind": str(event.clear_kind),
		"name": str(event.name), "shift": shift_index, "started_at": float(event.started_at),
		"chaos_phase_at_start": str(event.get("chaos_phase", "")), "status": str(event.status),
		"assigned_unit": int(event.assigned_unit), "linked_incident": int(event.get("linked_incident", -1)), "clear_dispatched_at": float(event.clear_dispatched_at),
		"clear_started_at": float(event.clear_started_at), "ended_at": float(event.ended_at),
		"seconds_open": (float(event.ended_at) if float(event.ended_at) >= 0.0 else elapsed) - float(event.started_at)}

func _department_title(kind: String) -> String:
	return str({"police": "Police", "engineer": "Engineering", "fire": "Fire", "medic": "Medical"}.get(kind, kind.capitalize()))

# Send the department that can deal with it: Police to a jam, Engineering to
# debris, Fire to a road fire, Medical to an accident.
func clear_road(event_id: int, unit_id: int) -> bool:
	if not running:
		return false
	var event: Dictionary = get_road_event(event_id)
	if event.is_empty() or str(event.status) not in ["active", "clearing"]:
		return false
	if int(event.assigned_unit) >= 0:
		_emit("action_denied", "A crew is already on its way to %s" % event.street)
		return false
	if str(event.clear_kind).is_empty():
		_emit("action_denied", "Nobody can clear a %s • work around it or wait until it passes" % str(event.type))
		return false
	var crew: Dictionary = get_unit(unit_id)
	if crew.is_empty() or str(crew.kind) != str(event.clear_kind):
		_emit("action_denied", "Only %s can clear %s" % [_department_title(str(event.clear_kind)), event.street])
		return false
	if not _unit_available(crew):
		_emit("action_denied", "%s is busy" % crew.get("crew_name", crew.name))
		return false
	if float(department_cooldowns.get(str(crew.kind), 0.0)) > 0.0:
		_emit("action_denied", "%s radio is transmitting • one order at a time" % kind_name(str(crew.kind)))
		return false
	var route: Dictionary = _best_route(crew, crew.pos, road_event_center(event))
	crew.target = -1
	crew.clear_target = int(event.id)
	crew.state = "travel"
	crew.arrival_at = -1.0
	crew.work_elapsed = 0.0
	crew.work_phase = "travel"
	crew.assignment_suitable = true
	crew.inspection_remaining = 0.0
	crew.dispatch_guard_until = elapsed + 1.0
	crew.path = route.path
	crew.path_index = 0
	crew.remaining = float(route.eta)
	department_cooldowns[str(crew.kind)] = 0.65
	event.assigned_unit = int(crew.id)
	event.clear_dispatched_at = elapsed
	_emit("road_clear_dispatched", "%s heading to %s • %ds" % [crew.get("crew_name", crew.name), event.street, ceili(float(route.eta))],
		{"road_event_id": event.id, "unit_id": crew.id, "kind": crew.kind, "pos": road_event_center(event), "eta": float(route.eta)})
	_emit_research("road_event_clear_dispatched", _road_event_record(event))
	return true

func _finish_clearing(crew: Dictionary) -> void:
	var event: Dictionary = get_road_event(int(crew.get("clear_target", -1)))
	crew.clear_target = -1
	if not event.is_empty() and str(event.status) in ["active", "clearing"]:
		event.status = "cleared"
		event.ended_at = elapsed
		event.clear_progress = 1.0
		roads_cleared += 1
		var done_text: String = "%s is open again • thanks, %s" % [event.street, crew.get("crew_name", crew.name)]
		if str(event.type) == "blackout": done_text = "Lights are back on in %s • thanks, %s" % [event.street, crew.get("crew_name", crew.name)]
		_emit("road_cleared", done_text,
			{"road_event_id": event.id, "unit_id": crew.id, "kind": crew.kind, "pos": road_event_center(event)})
		_emit_research("road_event_cleared", _road_event_record(event))
		_reroute_around_roads()
	_send_home(crew)

# When a road opens, crews already on the move take the faster way.
func _reroute_around_roads() -> void:
	for unit: Dictionary in units:
		if str(unit.state) not in ["travel", "return"]: continue
		var path: Array = unit.path
		if path.is_empty(): continue
		var destination: Vector2 = path.back()
		var route: Dictionary = _best_route(unit, unit.pos, destination)
		if float(route.eta) + 0.5 < float(unit.remaining):
			unit.path = route.path
			unit.path_index = 0
			unit.remaining = float(route.eta)

func _unit_available(unit: Dictionary) -> bool:
	return unit.state in ["idle", "return"] and elapsed >= float(unit.get("divert_after", 0.0)) and elapsed >= float(unit.get("dispatch_guard_until", 0.0))

func _completion_estimate(incident: Dictionary, candidate: Dictionary = {}, candidate_eta: float = 0.0) -> Dictionary:
	var estimate: Dictionary = {"eta": -1.0, "work_eta": -1.0, "finish_eta": -1.0, "margin": -1.0, "known": bool(incident.discovered), "team_incomplete": true}
	if not bool(incident.discovered):
		return estimate
	var arrivals: Array[float] = []
	for kind: String in UNIT_KINDS:
		var kind_arrivals: Array[float] = []
		for id: int in incident.assigned:
			var unit: Dictionary = get_unit(id)
			if unit.is_empty() or unit.kind != kind or not bool(unit.get("assignment_suitable", true)):
				continue
			if unit.state == "working":
				kind_arrivals.append(maxf(0.0, 1.6 - float(unit.get("work_elapsed", 0.0))))
			elif unit.state == "travel":
				kind_arrivals.append(unit_eta(unit) + 1.6)
		if not candidate.is_empty() and candidate.kind == kind and int(incident.needs.get(kind, 0)) > kind_arrivals.size():
			kind_arrivals.append(candidate_eta + 1.6)
		kind_arrivals.sort()
		var needed: int = int(incident.needs.get(kind, 0))
		if kind_arrivals.size() < needed:
			return estimate
		for index: int in range(needed):
			arrivals.append(kind_arrivals[index])
	if arrivals.is_empty():
		return estimate
	arrivals.sort()
	var ready: float = arrivals.back()
	var first: float = arrivals.front()
	var time: float = 0.0
	var hazard: float = float(incident.get("hazard", 0.0))
	var progress: float = float(incident.progress)
	var budget: float = float(incident.deadline)
	while progress < 1.0 and time < 240.0:
		var step: float = 0.1
		var complete: bool = time >= ready
		var any_arrived: bool = time >= first
		if complete:
			hazard = maxf(0.0, hazard - step * 0.04)
		elif any_arrived:
			hazard = maxf(0.0, hazard - step * 0.015)
		elif elapsed + time >= float(incident.get("stabilized_until", 0.0)):
			var growth: float = (0.012 + shift_index * 0.0014) * 0.68
			if special_duration > time: growth *= 0.65
			hazard = minf(1.0, hazard + step * growth)
		var burn: float = 1.0
		budget -= step * burn
		if complete:
			progress += step * _work_rate(incident, hazard, time) / float(incident.work_duration)
		time += step
	estimate.eta = maxf(0.0, ready - 1.6)
	estimate.work_eta = maxf(0.0, time - ready)
	estimate.finish_eta = time
	estimate.margin = budget
	estimate.team_incomplete = false
	return estimate

func _work_rate(incident: Dictionary, hazard: float, offset: float = 0.0) -> float:
	var speed: float = 1.0 + upgrade_level("training") * 0.12 + float(incident.work_bonus)
	if special_duration > offset: speed *= 1.65
	if disruption == "clear" and disruption_remaining > offset: speed *= 1.2
	return speed * (1.0 - hazard * 0.1)

func _current_work_seconds(incident: Dictionary) -> float:
	return float(incident.work_duration) * (1.0 - float(incident.progress)) / maxf(0.1, _work_rate(incident, float(incident.get("hazard", 0.0))))

func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = events.duplicate(true)
	events.clear()
	return result

func snapshot() -> Dictionary:
	return _snapshot_encode(_raw_state())

# Network copy of the state: plain Godot values, no save-file encoding.
# var_to_bytes already handles floats, ints and vectors exactly, and this is
# ~10x smaller and much faster for the guest to apply than snapshot().
func net_snapshot() -> Dictionary:
	var state: Dictionary = _raw_state()
	state["_net"] = true
	# Settled calls only matter for a few seconds (verdict cards); older ones are history.
	var recent: Array = []
	for incident: Dictionary in incidents:
		if str(incident.get("status", "")) in ["resolved", "failed"] and elapsed - float(incident.get("resolved_at", elapsed)) > 8.0:
			continue
		recent.append(incident)
	state["incidents"] = recent
	# The shift plan never changes mid-shift; the guest rebuilds it from shift_index.
	state.erase("_shift")
	# Effects reach guests through their own event messages, not the snapshot.
	state.erase("events")
	return state

func _raw_state() -> Dictionary:
	var state: Dictionary = {
		"snapshot_version": 5, "map_version": Campaign.MAP_VERSION,
		"chaos_schedule_version": Campaign.CHAOS_SCHEDULE_VERSION,
		"chaos_phase": chaos_phase, "chaos_phase_index": chaos_phase_index, "arrival_index": arrival_index,
		"road_events": road_events.duplicate(true), "_road_event_index": _road_event_index, "roads_cleared": roads_cleared,
		"shift_index": shift_index, "elapsed": elapsed, "duration": duration,
		"running": running, "finished": finished, "won": won, "score": score,
		"reputation": reputation, "rescued": rescued, "combo": combo, "best_combo": best_combo,
		"credits": credits, "incidents": incidents.duplicate(true), "units": units.duplicate(true),
		"upgrades": upgrades.duplicate(true), "weather": weather, "notice": notice,
		"supplies": supplies, "max_supplies": max_supplies, "supply_regen": supply_regen,
		"special_cooldown": special_cooldown, "special_duration": special_duration,
		"disruption": disruption, "disruption_remaining": disruption_remaining,
		"resolved_count": resolved_count, "failed_count": failed_count, "total_spawned": total_spawned,
		"stars": stars, "target": target, "shift_reward": shift_reward,
		"minimum_confidence": minimum_confidence,
		"successful_dispatches": successful_dispatches, "scout_count": scout_count, "supply_count": supply_count,
		"rush_remaining": rush_remaining, "events": events.duplicate(true),
		"breather_remaining": breather_remaining, "surge_warning_remaining": surge_warning_remaining,
		"surge_count": surge_count, "escalation_count": escalation_count, "rapid_response_count": rapid_response_count, "peak_active": peak_active,
		"scout_cooldown": scout_cooldown, "dispatch_cooldown": dispatch_cooldown, "department_cooldowns": department_cooldowns.duplicate(true),
		"wrong_dispatches": wrong_dispatches, "last_action_effect": last_action_effect.duplicate(true),
		"_surge_index": _surge_index, "_surge_warned_index": _surge_warned_index,
		"_surge_pending": _surge_pending, "_surge_spawn_timer": _surge_spawn_timer, "_surge_breather_length": _surge_breather_length,
		"_next_spawn": _next_spawn, "_next_id": _next_id,
		"_disruption_index": _disruption_index, "_reported_final_minute": _reported_final_minute,
		"_reported_target": _reported_target, "_previous_spawn_location": _previous_spawn_location,
		
		"_rng_seed": str(_rng.seed), "_rng_state": str(_rng.state), "_shift": _shift.duplicate(true)
	}
	return state

func apply_snapshot(data: Dictionary) -> void:
	if data.is_empty():
		return
	var restored: Dictionary = data if bool(data.get("_net", false)) else _snapshot_decode(data)
	for key: String in restored:
		if key in ["incidents", "units", "events", "road_events"]:
			var typed: Array[Dictionary] = []
			for entry: Dictionary in restored[key]:
				typed.append(entry.duplicate(true))
			set(key, typed)
		elif key in ["breather_remaining", "surge_warning_remaining", "surge_count", "escalation_count", "rapid_response_count", "peak_active", "_surge_index", "_surge_warned_index", "_surge_pending", "_surge_spawn_timer", "_surge_breather_length"]:
			set(key, restored[key])
		elif key in ["chaos_phase", "chaos_phase_index", "arrival_index", "_road_event_index", "roads_cleared"]:
			set(key, restored[key])
		elif key in ["scout_cooldown", "dispatch_cooldown", "department_cooldowns", "wrong_dispatches", "last_action_effect", "minimum_confidence"]:
			set(key, restored[key])
		elif key in ["shift_index", "elapsed", "duration", "running", "finished", "won", "score", "reputation", "rescued", "combo", "best_combo", "credits", "upgrades", "weather", "notice", "supplies", "max_supplies", "supply_regen", "special_cooldown", "special_duration", "disruption", "disruption_remaining", "resolved_count", "failed_count", "total_spawned", "stars", "target", "shift_reward", "successful_dispatches", "scout_count", "supply_count", "rush_remaining", "_next_spawn", "_next_id", "_disruption_index", "_reported_final_minute", "_reported_target", "_previous_spawn_location"]:
			set(key, restored[key])
	_shift = restored.get("_shift", Campaign.shift_data(shift_index)).duplicate(true)
	_set_layout()
	_edge_cache.clear()
	_rng.seed = int(str(restored.get("_rng_seed", 738291 + shift_index * 1097)))
	if restored.has("_rng_state"):
		_rng.state = int(str(restored._rng_state))
	if not restored.has("_next_id"):
		
		_next_id = 1
		for incident: Dictionary in incidents:
			_next_id = maxi(_next_id, int(incident.id) + 1)
		_disruption_index = 0
		for scheduled: Dictionary in _shift.get("disruptions", []):
			if float(scheduled.at) <= elapsed:
				_disruption_index += 1
		_next_spawn = float(_shift.get("interval", 20.0))
		_reported_final_minute = elapsed >= duration - 60.0
		_reported_target = rescued >= target
		_previous_spawn_location = int(incidents.back().get("location_index", -1)) if not incidents.is_empty() else -1
	_restore_legacy_vectors()
	_migrate_revision_state(restored)
	_migrate_world_and_schedule(restored)

func _migrate_revision_state(restored: Dictionary) -> void:
	if not restored.has("road_events"):
		# Saved before the traffic rework: skip road events that would already have started.
		road_events = []
		roads_cleared = 0
		_road_event_index = 0
		for plan: Dictionary in _shift.get("traffic", []):
			if float(plan.get("at", 0.0)) <= elapsed: _road_event_index += 1
	for key: String in ["scout_cooldown", "dispatch_cooldown", "wrong_dispatches"]:
		if not restored.has(key): set(key, 0)
	if not restored.has("last_action_effect"): last_action_effect = {}
	if not restored.has("department_cooldowns"): department_cooldowns = {}
	if not restored.has("minimum_confidence"): minimum_confidence = 25.0
	if not restored.has("_surge_index"):
		_surge_index = 0
		for wave: Dictionary in _shift.get("surges", []):
			if float(wave.at) <= elapsed:
				_surge_index += 1
		_surge_warned_index = _surge_index - 1
		_surge_pending = 0
		surge_count = _surge_index
		breather_remaining = 0.0
		surge_warning_remaining = 0.0
	for incident: Dictionary in incidents:
		var defaults: Dictionary = {"hazard": 0.08 + int(incident.severity) * 0.08, "hazard_stage": 0, "highest_hazard_stage": 0, "escalated": false, "critical_sent": false, "stabilized_until": 0.0, "rapid_response": false, "phase": "waiting", "confirmed_on_scene": bool(incident.get("arrival_sent", false))}
		for key: String in defaults:
			if not incident.has(key):
				incident[key] = defaults[key]
	var counts: Dictionary = {"fire": 0, "medic": 0, "engineer": 0, "police": 0}
	for unit: Dictionary in units:
		var profile: Dictionary = Campaign.responder_profile(str(unit.kind), int(counts.get(unit.kind, 0)))
		counts[unit.kind] = int(counts.get(unit.kind, 0)) + 1
		for key: String in profile:
			if not unit.has(key):
				unit[key] = profile[key]
		if not unit.has("arrival_at"):
			unit.arrival_at = elapsed - 1.6 if unit.state == "working" else -1.0
		if not unit.has("work_elapsed"):
			unit.work_elapsed = 1.6 if unit.state == "working" else 0.0
		if not unit.has("work_phase"):
			unit.work_phase = "act" if unit.state == "working" else str(unit.state)
		for key: String in ["inspection_remaining", "dispatch_guard_until", "divert_after"]:
			if not unit.has(key): unit[key] = 0.0
		if not unit.has("assignment_suitable"):
			var call: Dictionary = get_incident(int(unit.target))
			unit.assignment_suitable = call.is_empty() or int(call.needs.get(unit.kind, 0)) > 0

func _migrate_world_and_schedule(restored: Dictionary) -> void:
	var previous_map_version: int = int(restored.get("map_version", 1))
	if previous_map_version == 3:
		_expand_version_3_map(restored.has("_shift"))
		_widen_version_4_map(restored.has("_shift"))
	elif previous_map_version == 4:
		_widen_version_4_map(restored.has("_shift"))
	elif previous_map_version < Campaign.MAP_VERSION:
		_migrate_map_layout(previous_map_version)
	if not restored.has("chaos_schedule_version"):
		_shift["surges"] = []
		_shift["chaos_phases"] = Campaign.chaos_schedule(shift_index)
		_shift["arrival_schedule"] = Campaign.arrival_schedule(shift_index, float(_shift.interval))
		chaos_phase_index = -1
		for phase: Dictionary in _shift.chaos_phases:
			if float(phase.at) <= elapsed + 0.000001:
				chaos_phase_index = int(phase.index)
		chaos_phase = str(_shift.chaos_phases[maxi(0, chaos_phase_index)].phase)
		arrival_index = 0
		while arrival_index < _shift.arrival_schedule.size() and float(_shift.arrival_schedule[arrival_index].at) <= elapsed + 0.000001:
			arrival_index += 1
	# Kept as inert compatibility fields for older UI/tutorial resources.
	rush_remaining = 0.0
	breather_remaining = 0.0
	surge_warning_remaining = 0.0
	_surge_pending = 0

func _expand_version_3_map(has_saved_shift: bool) -> void:
	# v4 adds new land east/south of v3. Preserve exact physical positions and
	# every waypoint; multiplying normalized values by this ratio does not
	# teleport, stretch or relocate any existing part of the city.
	var factor: Vector2 = Campaign.MAP_V3_SIZE / Campaign.MAP_V4_SIZE
	for incident: Dictionary in incidents:
		incident.pos *= factor
	for unit: Dictionary in units:
		unit.pos *= factor
		unit.home *= factor
		for index: int in range(unit.path.size()): unit.path[index] *= factor
	# A lean network snapshot rebuilds the plan in current coordinates.
	if has_saved_shift:
		for traffic: Dictionary in _shift.get("traffic", []):
			traffic.position *= factor
			traffic.size *= factor
	for event: Dictionary in events:
		if event.get("pos") is Vector2: event.pos *= factor
	if last_action_effect.get("pos") is Vector2: last_action_effect.pos *= factor
	_emit_research("map_migrated", {"at": elapsed, "from_map_version": 3,
		"map_version": Campaign.MAP_VERSION, "physical_positions_preserved": true})

# v5 (Oct 2026) adds a road column on each side: the v4 town keeps its exact
# physical layout, shifted 224 px east inside the wider map.
func _v5_point(v4_normalized: Vector2) -> Vector2:
	return (v4_normalized * Campaign.MAP_V4_SIZE + Vector2(Campaign.TOWN_SHIFT_X, 0.0)) / Campaign.MAP_SIZE

func _v5_size(v4_normalized: Vector2) -> Vector2:
	return v4_normalized * Campaign.MAP_V4_SIZE / Campaign.MAP_SIZE

func _widen_version_4_map(has_saved_shift: bool) -> void:
	for incident: Dictionary in incidents:
		incident.pos = _v5_point(incident.pos)
	for unit: Dictionary in units:
		unit.pos = _v5_point(unit.pos)
		unit.home = _v5_point(unit.home)
		for index: int in range(unit.path.size()): unit.path[index] = _v5_point(unit.path[index])
	var areas: Array = road_events.duplicate()
	if has_saved_shift: areas.append_array(_shift.get("traffic", []))
	for area: Dictionary in areas:
		if area.has("position"): area.position = _v5_point(area.position)
		if area.has("size"): area.size = _v5_size(area.size)
		if area.has("target"): area.target = _v5_point(area.target)
	for event: Dictionary in events:
		if event.get("pos") is Vector2: event.pos = _v5_point(event.pos)
	if last_action_effect.get("pos") is Vector2: last_action_effect.pos = _v5_point(last_action_effect.pos)
	_edge_cache.clear()
	_emit_research("map_migrated", {"at": elapsed, "from_map_version": 4,
		"map_version": Campaign.MAP_VERSION, "physical_positions_preserved": true})

func _migrate_map_layout(previous_version: int) -> void:
	# v1 (532x316) and v2 (664x396) both stored normalized coordinates,
	# but v3 rearranges the city. Remap call identities and station homes;
	# merely multiplying old coordinates would leave calls in the wrong lot.
	var places: Array[Dictionary] = Campaign.locations()
	for incident: Dictionary in incidents:
		var index: int = int(incident.get("location_index", -1))
		if index >= 0 and index < places.size():
			incident.pos = places[index].pos
		else:
			for place: Dictionary in places:
				if str(place.name) == str(incident.get("name", "")):
					incident.pos = place.pos
					break
	_shift["traffic"] = Campaign.shift_data(shift_index).traffic
	var counts: Dictionary = {}
	var extra_travel: Dictionary = {}
	for unit: Dictionary in units:
		var crew_index: int = int(counts.get(unit.kind, 0))
		counts[unit.kind] = crew_index + 1
		unit.home = _fleet_home(str(unit.kind), crew_index)
		var call: Dictionary = get_incident(int(unit.target))
		if unit.state == "working" and not call.is_empty():
			unit.pos = call.pos
		elif unit.state in ["idle", "rest"]:
			unit.pos = unit.home
		elif unit.state in ["travel", "return"]:
			# Older layouts were relocated into v3; keep that relative placement
			# inside the original district rather than stretching into new land.
			unit.pos = _v5_point(Vector2(unit.pos).clamp(Vector2.ZERO, Vector2.ONE) * Campaign.MAP_V3_SIZE / Campaign.MAP_V4_SIZE)
			var destination: Vector2 = call.pos if unit.state == "travel" and not call.is_empty() else unit.home
			var old_eta: float = float(unit.remaining)
			var route: Dictionary = _best_route(unit, unit.pos, destination)
			unit.path = route.path
			unit.path_index = 0
			unit.remaining = float(route.eta)
			if not route.path.is_empty(): unit.heading = (Vector2(route.path[0]) - Vector2(unit.pos)).normalized()
			if unit.state == "travel" and not call.is_empty():
				extra_travel[call.id] = maxf(float(extra_travel.get(call.id, 0.0)), maxf(0.0, float(route.eta) - old_eta))
	for id: int in extra_travel:
		var call: Dictionary = get_incident(id)
		call.deadline += float(extra_travel[id])
		call.max_deadline += float(extra_travel[id])
	# Repair any pending spatial effect before an old save's events are shown.
	for event: Dictionary in events:
		if event.has("pos"):
			var call: Dictionary = get_incident(int(event.get("incident_id", -1)))
			if not call.is_empty(): event.pos = call.pos
	_emit_research("map_migrated", {"at": elapsed, "from_map_version": previous_version,
		"map_version": Campaign.MAP_VERSION, "travel_allowance_added": extra_travel})

func _snapshot_encode(value: Variant) -> Variant:
	if value is Vector2:
		return {"_beacon_type": "Vector2", "x": float(value.x), "y": float(value.y)}
	if value is int:
		
		return {"_beacon_type": "Int64", "value": str(value)}
	if value is float:
		
		var bits := PackedByteArray()
		bits.resize(8)
		bits.encode_double(0, value)
		return {"_beacon_type": "Float64", "bits": Marshalls.raw_to_base64(bits)}
	if value is Dictionary:
		var encoded: Dictionary = {}
		for key: Variant in value:
			encoded[key] = _snapshot_encode(value[key])
		return encoded
	if value is Array:
		var encoded: Array = []
		for item: Variant in value:
			encoded.append(_snapshot_encode(item))
		return encoded
	return value

func _snapshot_decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.get("_beacon_type", "") == "Vector2":
			return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
		if value.get("_beacon_type", "") == "Int64":
			return int(str(value.get("value", "0")))
		if value.get("_beacon_type", "") == "Float64":
			var bits: PackedByteArray = Marshalls.base64_to_raw(str(value.get("bits", "")))
			return bits.decode_double(0) if bits.size() == 8 else 0.0
		var decoded: Dictionary = {}
		for key: Variant in value:
			decoded[key] = _snapshot_decode(value[key])
		return decoded
	if value is Array:
		var decoded: Array = []
		for item: Variant in value:
			decoded.append(_snapshot_decode(item))
		return decoded
	return value

func _restore_legacy_vectors() -> void:
	for incident: Dictionary in incidents:
		incident.pos = _read_legacy_vector(incident.get("pos", Vector2.ZERO))
	for unit: Dictionary in units:
		for key: String in ["pos", "home", "heading"]:
			unit[key] = _read_legacy_vector(unit.get(key, Vector2.ZERO))
		var path: Array = unit.get("path", [])
		for index: int in range(path.size()):
			path[index] = _read_legacy_vector(path[index])
		unit.path = path

func _read_legacy_vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is String:
		var coordinates: PackedStringArray = value.trim_prefix("(").trim_suffix(")").split(",")
		if coordinates.size() == 2:
			return Vector2(float(coordinates[0]), float(coordinates[1]))
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

func shift_summary() -> Dictionary:
	return {"shift": shift_index, "title": _shift.get("title", ""), "won": won, "stars": stars, "score": score, "rescued": rescued, "target": target, "resolved": resolved_count, "missed": failed_count, "reputation": snappedf(reputation, 0.1), "best_combo": best_combo, "credits_earned": shift_reward, "duration": elapsed, "dispatches": successful_dispatches, "scouts": scout_count, "supplies_used": supply_count, "escalations": escalation_count, "rapid_responses": rapid_response_count, "peak_calls": peak_active, "roads_cleared": roads_cleared, "wrong_dispatches": wrong_dispatches, "minimum_confidence": minimum_confidence}

func kind_name(kind: String) -> String:
	return str({"fire": "Fire", "medic": "Medical", "medical": "Medical", "engineer": "Engineer", "flood": "Flood", "power": "Power", "police": "Police"}.get(kind, kind.capitalize()))

func _fleet_home(kind: String, crew_index: int) -> Vector2:
	# Stations are spread over the whole town (Oct 2026): every department has a
	# main station and a second station in a different district, so which crew is
	# closest changes from call to call. Even crew numbers use the main station,
	# odd ones the second station. Stations sit on junctions that no road event closes.
	var homes: Dictionary = {"fire": Vector2(864, 448), "medic": Vector2(1632, 448), "engineer": Vector2(1888, 704), "police": Vector2(1376, 928)}
	var standby: Dictionary = {"fire": Vector2(1888, 1184), "medic": Vector2(864, 1184), "engineer": Vector2(608, 928), "police": Vector2(2144, 192)}
	var base: Vector2 = standby[kind] if crew_index % 2 == 1 else homes[kind]
	return (base + Vector2(8.0 * (crew_index / 2), 0.0)) / Campaign.MAP_SIZE

func _build_fleet() -> void:
	var crew_names: Dictionary = {"fire": ["Ember", "Cinder", "Spark", "Blaze"], "medic": ["Clover", "Willow", "Fern", "Sage"], "engineer": ["Bolt", "Copper", "Wren", "Rivet"], "police": ["Badge", "Patrol", "Siren", "Beacon"]}
	var id: int = 0
	for kind: String in UNIT_KINDS:
		var count: int = Campaign.crews_per_department(shift_index)
		for crew_index: int in range(count):
			var home: Vector2 = _fleet_home(kind, crew_index)
			var unit: Dictionary = {"id": id, "name": crew_names[kind][crew_index], "kind": kind, "pos": home, "home": home, "target": -1, "state": "idle", "remaining": 0.0, "fatigue": 0.0, "path": [], "path_index": 0, "heading": Vector2.RIGHT, "jobs": 0, "arrival_at": -1.0, "work_elapsed": 0.0, "work_phase": "idle", "assignment_suitable": true, "inspection_remaining": 0.0, "dispatch_guard_until": 0.0, "divert_after": 0.0, "clear_target": -1}
			unit.merge(Campaign.responder_profile(kind, crew_index))
			units.append(unit)
			id += 1

# forced_location / forced_kind: used by road events, whose call is part of the script.
func _spawn_incident(forced_location: int = -1, forced_kind: String = "") -> void:
	var places: Array[Dictionary] = Campaign.locations()
	var used: Array[int] = []
	for active: Dictionary in incidents:
		if _is_active(active):
			used.append(int(active.location_index))
	var location_index: int = forced_location
	if location_index < 0:
		# Spread calls over the whole town: first pick one of nine districts
		# (a 3 x 3 grid) evenly, then a free site inside it. Picking sites directly
		# put most calls in the dense north-west.
		var districts: Dictionary = {}
		for index: int in range(places.size()):
			if index in used or index == _previous_spawn_location: continue
			if not Campaign.site_open(shift_index, places[index].pos): continue
			var cell: Vector2i = Vector2i(clampi(int(places[index].pos.x * 3.0), 0, 2), clampi(int(places[index].pos.y * 3.0), 0, 2))
			var key: int = cell.y * 3 + cell.x
			if not districts.has(key): districts[key] = []
			districts[key].append(index)
		var keys: Array = districts.keys()
		keys.sort()
		if keys.is_empty():
			location_index = _rng.randi_range(0, places.size() - 1)
		else:
			var sites: Array = districts[keys[_rng.randi_range(0, keys.size() - 1)]]
			location_index = int(sites[_rng.randi_range(0, sites.size() - 1)])
	_previous_spawn_location = location_index
	var place: Dictionary = places[location_index]
	var kind: String = _choose_kind() if forced_kind.is_empty() else forced_kind
	var severity: int = 1
	if shift_index > 0 and _rng.randf() < 0.28 + 0.04 * shift_index:
		severity = 2
	if shift_index == 0:
		if kind == "flood" or (elapsed > 95.0 and _rng.randf() < 0.28):
			severity = 2
	var report_clear: bool = _rng.randf() < (0.66 if shift_index < 2 else 0.57)
	if disruption in ["blackout", "comms"]: report_clear = false
	# Calls inside a blackout or a storm come in unconfirmed: scout them or send a crew to see.
	for zone: Dictionary in active_road_events():
		if bool(zone.get("hazard", false)) and Rect2(zone.position, zone.size).has_point(place.pos): report_clear = false
	if shift_index == 0 and total_spawned == 0: report_clear = true
	if shift_index == 0 and total_spawned == 1:
		report_clear = false
		severity = 2
	if forced_location >= 0: report_clear = true
	# All-four-department calls in every shift, from shift 1, after the opening minute.
	# Each shift is guaranteed at least one by its 8th call and two by its 16th.
	if elapsed > 60.0 and total_spawned >= 4:
		var four_team_calls: int = 0
		for earlier: Dictionary in incidents:
			if int(earlier.severity) >= 3: four_team_calls += 1
		var chance: float = [0.10, 0.12, 0.14, 0.16, 0.16, 0.20][clampi(shift_index, 0, 5)]
		if _rng.randf() < chance or (four_team_calls == 0 and total_spawned >= 7) or (four_team_calls < 2 and total_spawned >= 15):
			severity = 3
	# Every call needs a team: severity 1 = two departments, 2 = three, 3 = all four.
	var needs: Dictionary = {"fire": 0, "medic": 0, "engineer": 0, "police": 0}
	var order: Array = _team_order(kind)
	var team_size: int = clampi(severity + 1, 2, 4)
	for index: int in range(team_size):
		needs[order[index]] = 1
	var work_duration: float = 10.0 + severity * 4.2
	var arrival_budget: float = 0.0
	# Deadlines assume open roads: a closed street is a problem for the team to
	# solve (clear it or crawl), not something the countdown quietly absorbs.
	_ignore_road_events = true
	for needed_kind: String in UNIT_KINDS:
		if int(needs[needed_kind]) == 0: continue
		var fastest: float = INF
		for crew: Dictionary in units:
			if crew.kind != needed_kind: continue
			var route: Dictionary = _best_route(crew, crew.pos, place.pos)
			
			
			var handover: float = 0.0 if _unit_available(crew) else 8.0
			fastest = minf(fastest, float(route.eta) + handover)
		arrival_budget = maxf(arrival_budget, fastest)
	_ignore_road_events = false
	# +2 s since the town got wider (Oct 2026): more calls sit far from a station.
	var decision_slack: float = 20.0 - shift_index * 1.2
	if total_spawned > 2 and _rng.randf() < 0.25: decision_slack *= 0.58
	var deadline: float = arrival_budget * 1.12 + work_duration * WORK_TIME_ALLOWANCE + decision_slack + _rng.randf_range(-2.0, 4.0) + 7.0 * upgrade_level("radio")
	if not report_clear: deadline += 4.0
	if shift_index == 0 and total_spawned == 0: deadline += 10.0
	var bonuses: Array[String] = ["Neighbors cleared the way.", "A safe route is marked. Crews can work faster.", "Everyone is accounted for. Rescue plan confirmed.", "Local volunteers are helping. You've got this."]
	var incident: Dictionary = {
		"id": _next_id, "pos": place.pos, "kind": kind, "name": place.name,
		"title": Campaign.incident_title(kind, severity, _rng.randi_range(0, 4)),
		"severity": severity, "deadline": deadline, "max_deadline": deadline,
		"needs": needs, "assigned": [], "progress": 0.0, "status": "active",
		"discovered": report_clear, "scouted": false,
		"bonus": bonuses[_rng.randi_range(0, bonuses.size() - 1)],
		"supply_count": 0, "work_bonus": 0.0, "work_duration": work_duration,
		"people": 2 + severity + _rng.randi_range(0, 2),
		"created_at": elapsed, "resolved_at": -1.0, "location_index": location_index,
		"last_action": elapsed, "warning_sent": false, "arrival_sent": false,
		"hazard": 0.08 + severity * 0.08, "hazard_stage": 0, "highest_hazard_stage": 0,
		"escalated": false, "critical_sent": false, "stabilized_until": 0.0,
		"rapid_response": false, "phase": "waiting", "confirmed_on_scene": false
	}
	incidents.append(incident)
	_next_id += 1
	total_spawned += 1
	_emit("incident", "%s • %s" % [incident.title if report_clear else "Unverified report", incident.name], {"incident_id": incident.id, "kind": kind, "pos": incident.pos, "severity": severity})

const LEAD_KIND := {"fire": "fire", "medic": "medical", "police": "police"}

# Every department is needed equally often (Oct 2026). The department that leads
# a call comes from a fixed per-shift order in which each department leads once
# in every block of four calls; the level's theme only decides whether an
# Engineering call is a flood or a power problem.
func _choose_kind() -> String:
	var leads: Array = Campaign.lead_order(shift_index)
	var lead: String = str(leads[total_spawned % leads.size()])
	if lead != "engineer":
		return str(LEAD_KIND[lead])
	var weights: Array = _shift.get("weights", [4, 4, 2, 2, 3]).duplicate()
	var flood: float = float(weights[2]) + (4.0 if disruption in ["rain", "storm"] else 0.0)
	var power: float = float(weights[3]) + (5.0 if disruption == "blackout" else 0.0)
	return "flood" if _rng.randf() * (flood + power) < flood else "power"

# The lead department first, then partners in an order that rotates with every
# call, so each department is a partner equally often as well.
func _team_order(kind: String) -> Array:
	var lead: String = {"fire": "fire", "medical": "medic", "flood": "engineer", "power": "engineer", "police": "police"}.get(kind, "fire")
	var others: Array = []
	for department: String in UNIT_KINDS:
		if department != lead: others.append(department)
	var turn: int = (total_spawned + total_spawned / 4) % others.size()
	var result: Array = [lead]
	for index: int in range(others.size()):
		result.append(others[(index + turn) % others.size()])
	return result

func _tick_unit(unit: Dictionary, delta: float) -> void:
	if unit.state == "idle":
		unit.fatigue = maxf(0.0, float(unit.fatigue) - delta * 0.018)
		return
	if unit.state == "travel" or unit.state == "return":
		var path: Array = unit.path
		var path_index: int = int(unit.path_index)
		var time_left: float = delta
		var zones: Array[Dictionary] = road_conditions()
		while path_index < path.size() and time_left > 0.00001:
			var destination: Vector2 = path[path_index]
			var position: Vector2 = unit.pos
			var difference: Vector2 = destination - position
			if difference.length() > 0.00001:
				unit.heading = difference.normalized()
			var moved: Dictionary = _travel_segment(unit, position, destination, -time_left, time_left, zones)
			unit.pos = moved.pos
			time_left = maxf(0.0, time_left - float(moved.time))
			if bool(moved.done):
				path_index += 1
			else:
				break
		unit.path_index = path_index
		unit.remaining = unit_eta(unit)
		if path_index >= path.size():
			if unit.state == "return":
				unit.state = "rest"
				unit.remaining = maxf(1.0, 3.5 - upgrade_level("rest"))
			elif int(unit.get("clear_target", -1)) >= 0:
				var road: Dictionary = get_road_event(int(unit.clear_target))
				if road.is_empty() or str(road.status) not in ["active", "clearing"]:
					unit.clear_target = -1
					_send_home(unit)
				else:
					unit.state = "clearing"
					unit.work_phase = "clearing"
					unit.arrival_at = elapsed
					unit.work_elapsed = 0.0
					unit.remaining = float(road.clear_time)
					road.status = "clearing"
					road.clear_started_at = elapsed
					_emit("road_crew_arrived", "%s is clearing %s" % [unit.get("crew_name", unit.name), road.street], {"road_event_id": road.id, "unit_id": unit.id, "kind": unit.kind, "pos": unit.pos})
			else:
				unit.state = "working"
				unit.remaining = 0.0
				unit.arrival_at = elapsed
				unit.work_elapsed = 0.0
				unit.work_phase = "deploy"
				_emit("crew_arrived", "%s & %s are on scene" % [unit.crew_name, unit.partner_name], {"incident_id": unit.target, "unit_id": unit.id, "pos": unit.pos, "kind": unit.kind})
	elif unit.state == "working":
		unit.work_elapsed = float(unit.get("work_elapsed", 0.0)) + delta
		if float(unit.work_elapsed) < 1.6:
			unit.work_phase = "deploy"
		elif not bool(unit.get("assignment_suitable", true)):
			unit.work_phase = "assess"
			unit.inspection_remaining = maxf(0.0, 5.6 - float(unit.work_elapsed))
			if float(unit.inspection_remaining) <= 0.0:
				var call: Dictionary = get_incident(int(unit.target))
				var call_id: int = int(unit.target)
				if not call.is_empty():
					call.assigned.erase(int(unit.id))
					call.discovered = true
					call.confirmed_on_scene = true
				_emit("dispatch_mismatch", "%s cannot resolve this call — returning to standby" % unit.crew_name, {"incident_id": call_id, "unit_id": unit.id, "kind": unit.kind, "pos": unit.pos})
				_send_home(unit)
				unit.divert_after = elapsed + 6.0
		elif unit.work_phase == "deploy":
			unit.work_phase = "hold"
			var call: Dictionary = get_incident(int(unit.target))
			if not call.is_empty():
				call.confirmed_on_scene = true
				if not bool(call.discovered):
					call.discovered = true
					_emit("field_report", "%s confirms the response teams needed at %s" % [unit.crew_name, call.name], {"incident_id": call.id, "pos": call.pos})
	elif unit.state == "clearing":
		# The coffee boost speeds clearing like any other work.
		var rate: float = 1.5 if special_duration > 0.0 else 1.0
		unit.remaining = maxf(0.0, float(unit.remaining) - delta * rate)
		unit.work_elapsed = float(unit.get("work_elapsed", 0.0)) + delta
		var road: Dictionary = get_road_event(int(unit.get("clear_target", -1)))
		if not road.is_empty():
			road.clear_progress = clampf(1.0 - float(unit.remaining) / maxf(0.1, float(road.clear_time)), 0.0, 1.0)
		if road.is_empty() or str(road.status) not in ["active", "clearing"]:
			unit.clear_target = -1
			_send_home(unit)
		elif float(unit.remaining) <= 0.0:
			_finish_clearing(unit)
	elif unit.state == "rest":
		unit.remaining = maxf(0.0, float(unit.remaining) - delta)
		unit.fatigue = maxf(0.0, float(unit.fatigue) - delta * 0.08)
		if float(unit.remaining) <= 0.0:
			unit.state = "idle"
			unit.work_phase = "idle"
			_emit("crew_ready", "%s is ready for another call" % unit.name, {"unit_id": unit.id, "kind": unit.kind})

func _tick_incident(incident: Dictionary, delta: float) -> void:
	if not _is_active(incident):
		return
	var complete_team: bool = true
	var arrived_total: int = 0
	var deploying: bool = false
	for kind: String in UNIT_KINDS:
		var arrived: int = 0
		for id: int in incident.assigned:
			var unit: Dictionary = get_unit(id)
			if not unit.is_empty() and unit.kind == kind and unit.state == "working" and bool(unit.get("assignment_suitable", true)):
				if float(unit.get("work_elapsed", 0.0)) >= 1.6:
					arrived += 1
					arrived_total += 1
				else:
					deploying = true
		if arrived < int(incident.needs.get(kind, 0)):
			complete_team = false
	_update_hazard(incident, delta, arrived_total, complete_team)
	# The countdown is real time: one second per second, always.
	incident.deadline = maxf(0.0, float(incident.deadline) - delta)
	incident.phase = "deploy" if deploying else ("contain" if arrived_total > 0 else ("enroute" if not incident.assigned.is_empty() else "waiting"))
	if complete_team:
		if not bool(incident.arrival_sent):
			incident.arrival_sent = true
			_emit("arrival", "All crews on scene • %s" % incident.name, {"incident_id": incident.id, "pos": incident.pos})
		var speed: float = _work_rate(incident, float(incident.hazard))
		incident.progress = minf(1.0, float(incident.progress) + delta * speed / float(incident.work_duration))
		incident.phase = "contain" if float(incident.progress) < 0.15 else ("rescue" if float(incident.progress) < 0.8 else "secure")
		for id: int in incident.assigned:
			var unit: Dictionary = get_unit(id)
			if not unit.is_empty() and unit.state == "working" and bool(unit.get("assignment_suitable", true)):
				unit.work_phase = "assess" if float(incident.progress) < 0.15 else ("act" if float(incident.progress) < 0.8 else "secure")
		if float(incident.progress) >= 1.0:
			_resolve(incident)
			return
	if float(incident.deadline) < 15.0 and not bool(incident.warning_sent):
		incident.warning_sent = true
		_emit("urgent", "Time is running short • %s" % incident.name, {"incident_id": incident.id, "pos": incident.pos})
	if float(incident.deadline) <= 0.0:
		_fail(incident)

func _update_hazard(incident: Dictionary, delta: float, arrived: int, complete_team: bool) -> void:
	var hazard: float = float(incident.get("hazard", 0.0))
	if complete_team:
		hazard -= delta * 0.04
	elif arrived > 0:
		hazard -= delta * 0.015
	elif elapsed >= float(incident.get("stabilized_until", 0.0)):
		var growth: float = 0.012 + shift_index * 0.0014
		var qualified_enroute: bool = false
		for id: int in incident.assigned:
			var crew: Dictionary = get_unit(id)
			if not crew.is_empty() and bool(crew.get("assignment_suitable", true)):
				qualified_enroute = true
		if qualified_enroute:
			growth *= 0.68
		if special_duration > 0.0:
			growth *= 0.65
		hazard += delta * growth
	incident.hazard = clampf(hazard, 0.0, 1.0)
	var stage: int = 3 if hazard >= 0.86 else (2 if hazard >= 0.60 else (1 if hazard >= 0.34 else 0))
	incident.hazard_stage = stage
	if stage > int(incident.get("highest_hazard_stage", 0)):
		incident.highest_hazard_stage = stage
		incident.escalated = true
		escalation_count += 1
		var descriptions: Dictionary = {"fire": "Fire spreading", "medical": "Condition worsening", "flood": "Water rising", "power": "Grid destabilizing", "police": "Situation getting tense"}
		_emit("escalated", "%s • %s" % [descriptions.get(incident.kind, "Hazard rising") if bool(incident.discovered) else "Unverified report escalating", incident.name], {"incident_id": incident.id, "pos": incident.pos, "hazard_stage": stage, "hazard": incident.hazard})
	if (stage >= 3 or float(incident.deadline) < 12.0) and not bool(incident.get("critical_sent", false)):
		incident.critical_sent = true
		_emit("critical", "Critical call • stabilize %s now" % incident.name, {"incident_id": incident.id, "pos": incident.pos, "hazard_stage": stage})

func _resolve(incident: Dictionary) -> void:
	incident.status = "resolved"
	incident.resolved_at = elapsed
	resolved_count += 1
	rescued += int(incident.people)
	combo += 1
	best_combo = maxi(best_combo, combo)
	var time_bonus: int = int(30.0 * clampf(float(incident.deadline) / float(incident.max_deadline), 0.0, 1.0))
	var earned: int = 75 + int(incident.severity) * 25 + time_bonus + mini(combo, 10) * 10
	if bool(incident.scouted):
		earned += 15
	if bool(incident.get("rapid_response", false)):
		earned += 25
	score += earned
	reputation = minf(100.0, reputation + 2.0)
	for id: int in incident.assigned:
		_send_home(get_unit(id))
	_emit("resolved", "%d neighbors safe • crews returning to standby" % incident.people, {"incident_id": incident.id, "pos": incident.pos, "people": incident.people, "points": earned, "combo": combo, "time_left": float(incident.deadline)})
	if combo in [3, 5, 8, 12, 16, 20]:
		_emit("combo", "%d calls. One unbroken chain of care." % combo, {"combo": combo})
	if combo > 0 and combo % 5 == 0:
		supplies = mini(max_supplies, supplies + 1)
		_emit("combo_supply", "Neighbors sent a supply crate • thank you for looking out for us", {"combo": combo})

func _fail(incident: Dictionary) -> void:
	incident.status = "failed"
	incident.resolved_at = elapsed
	failed_count += 1
	combo = 0
	reputation = maxf(0.0, reputation - 8.0 - int(incident.severity) * 2.0)
	for id: int in incident.assigned:
		_send_home(get_unit(id))
	_emit("failed", "Backup took over at %s • regroup and keep going" % incident.name, {"incident_id": incident.id, "pos": incident.pos})

func _send_home(unit: Dictionary, count_job: bool = true) -> void:
	if unit.is_empty():
		return
	if count_job:
		unit.jobs = int(unit.jobs) + 1
		unit.fatigue = minf(1.0, float(unit.fatigue) + 0.14 * maxf(0.2, 1.0 - upgrade_level("rest") * 0.35))
	unit.target = -1
	unit.clear_target = -1
	unit.state = "return"
	unit.work_phase = "return"
	var route: Dictionary = _best_route(unit, unit.pos, unit.home)
	unit.path = route.path
	unit.path_index = 0
	unit.remaining = float(route.eta)

func _travel_speed(unit: Dictionary, offset: float = 0.0) -> float:
	# 130 world pixels/second (was 120): the town got wider on both sides (Oct 2026)
	# and the average drive to a call should stay about as long as before.
	var speed: float = 0.126953125 * (1.0 + upgrade_level("engines") * 0.14)
	speed *= 1.0 - float(unit.fatigue) * 0.12
	if special_duration > offset and special_duration > 0.0:
		speed *= 1.5
	return speed

func _best_route(unit: Dictionary, start: Vector2, destination: Vector2) -> Dictionary:
	if not _layout.is_empty():
		return _graph_route(unit, start, destination)
	var start_y: float = _nearest(start.y, ROAD_Y)
	var end_y: float = _nearest(destination.y, ROAD_Y)
	var candidates: Array = []
	if is_equal_approx(start_y, end_y):
		candidates.append([Vector2(start.x, start_y), Vector2(destination.x, end_y), destination])
		
		var start_x: float = _nearest(start.x, ROAD_X)
		var end_x: float = _nearest(destination.x, ROAD_X)
		for lane_y: float in ROAD_Y:
			if not is_equal_approx(lane_y, start_y):
				candidates.append([Vector2(start.x, start_y), Vector2(start_x, start_y), Vector2(start_x, lane_y), Vector2(end_x, lane_y), Vector2(end_x, end_y), Vector2(destination.x, end_y), destination])
	else:
		for lane_x: float in ROAD_X:
			candidates.append([Vector2(start.x, start_y), Vector2(lane_x, start_y), Vector2(lane_x, end_y), Vector2(destination.x, end_y), destination])
	var best: Dictionary = {"path": [], "eta": INF}
	var zones: Array[Dictionary] = road_conditions()
	for candidate: Array in candidates:
		var clean: Array[Vector2] = []
		var previous: Vector2 = start
		for point: Vector2 in candidate:
			if previous.distance_to(point) > 0.00001:
				clean.append(point)
				previous = point
		var eta: float = _route_eta(unit, start, clean, zones)
		if eta < float(best.eta): best = {"path": clean, "eta": eta}
	return best

func _route_eta(unit: Dictionary, start: Vector2, points: Array, zones: Array[Dictionary] = []) -> float:
	if zones.is_empty(): zones = road_conditions()
	var total: float = 0.0
	var previous: Vector2 = start
	for point: Vector2 in points:
		var segment: Dictionary = _travel_segment(unit, previous, point, total, INF, zones)
		total += float(segment.time)
		previous = point
	return total

func _travel_segment(unit: Dictionary, start: Vector2, destination: Vector2, offset: float, budget: float, zones: Array[Dictionary]) -> Dictionary:
	
	
	var difference: Vector2 = destination - start
	var length: float = (difference * WORLD_DISTANCE_SCALE).length()
	if length < 0.000001:
		return {"pos": destination, "time": 0.0, "done": true}
	var cuts: Array[float] = [0.0, 1.0]
	for zone: Dictionary in zones:
		var rect := Rect2(zone.position, zone.size)
		for axis: int in range(2):
			if absf(difference[axis]) < 0.000001: continue
			for edge: float in [rect.position[axis], rect.end[axis]]:
				var portion: float = (edge - start[axis]) / difference[axis]
				if portion > 0.000001 and portion < 0.999999:
					var crossing: Vector2 = start + difference * portion
					var other: int = 1 - axis
					if crossing[other] >= rect.position[other] - 0.00001 and crossing[other] <= rect.end[other] + 0.00001:
						cuts.append(portion)
	cuts.sort()
	var spent: float = 0.0
	for index: int in range(cuts.size() - 1):
		var piece_length: float = (cuts[index + 1] - cuts[index]) * length
		if piece_length <= 0.000001: continue
		var midpoint: Vector2 = start + difference * ((cuts[index + 1] + cuts[index]) * 0.5)
		var done_length: float = 0.0
		while done_length < piece_length - 0.000001:
			var at: float = offset + spent
			var factor: float = 1.0
			var next_change: float = INF
			if special_duration > at and special_duration > 0.0: next_change = special_duration - at
			for zone: Dictionary in zones:
				if str(zone.get("pass_kind", "")) == str(unit.get("kind", "")): continue
				if float(zone.remaining) > at and Rect2(zone.position, zone.size).has_point(midpoint):
					factor = minf(factor, float(zone.speed_factor))
					next_change = minf(next_change, float(zone.remaining) - at)
			var speed: float = _travel_speed(unit, at) * factor
			var seconds: float = minf((piece_length - done_length) / speed, minf(next_change, budget - spent))
			if seconds <= 0.0000001:
				return {"pos": start + difference * (cuts[index] + done_length / length), "time": spent, "done": false}
			done_length += seconds * speed
			spent += seconds
			if spent >= budget - 0.0000001:
				var portion: float = cuts[index] + done_length / length
				return {"pos": destination if portion >= 0.999999 else start + difference * portion, "time": spent, "done": portion >= 0.999999}
	return {"pos": destination, "time": spent, "done": true}

func _make_route(start: Vector2, destination: Vector2) -> Array[Vector2]:
	
	var start_y: float = _nearest(start.y, ROAD_Y)
	var end_y: float = _nearest(destination.y, ROAD_Y)
	var lane_x: float = _nearest((start.x + destination.x) * 0.5, ROAD_X)
	var points: Array[Vector2] = [Vector2(start.x, start_y)]
	if not is_equal_approx(start_y, end_y):
		points.append(Vector2(lane_x, start_y))
		points.append(Vector2(lane_x, end_y))
	points.append(Vector2(destination.x, end_y))
	points.append(destination)
	return points

func _nearest(value: float, options: Array[float]) -> float:
	var best: float = options[0]
	for option: float in options:
		if absf(option - value) < absf(best - value):
			best = option
	return best

func _route_length(start: Vector2, points: Array) -> float:
	var length: float = 0.0
	var previous: Vector2 = start
	for point: Vector2 in points:
		length += ((point - previous) * WORLD_DISTANCE_SCALE).length()
		previous = point
	return length

func _start_disruption(data: Dictionary) -> void:
	disruption = str(data.type)
	disruption_remaining = float(data.duration)
	if disruption in ["comms", "blackout"]:
		for incident: Dictionary in incidents:
			if _is_active(incident) and not bool(incident.scouted) and not bool(incident.get("confirmed_on_scene", false)):
				incident.discovered = false
	_emit("disruption", str(data.text), {"disruption": disruption, "duration": disruption_remaining})
	

func _finish_shift() -> void:
	running = false
	finished = true
	for incident: Dictionary in incidents:
		if _is_active(incident):
			
			incident.status = "failed"
			incident.resolved_at = elapsed
			failed_count += 1
			reputation = maxf(0.0, reputation - 4.0)
	won = rescued >= target and reputation >= minimum_confidence
	stars = 0
	if won:
		stars = 1
		if reputation >= 75.0 and failed_count <= 3:
			stars = 2
		if reputation >= 92.0 and failed_count == 0 and rescued >= target + 8:
			stars = 3
	shift_reward = 35 + resolved_count * 4 + stars * 22 + (30 if won else 0)
	credits += shift_reward
	score += int(reputation * 3.0) + stars * 100
	_emit("shift_complete", "The bay is brighter because of you" if won else "Every rescue mattered • regroup for another watch", shift_summary())

func _is_active(incident: Dictionary) -> bool:
	return incident.status in ["active", "working"]

func _emit(type: String, message: String, payload: Dictionary = {}) -> void:
	notice = message
	var event: Dictionary = {"type": type, "text": message, "at": elapsed}
	for key: String in payload:
		event[key] = payload[key]
	events.append(event)
	
	if events.size() > 160:
		events.pop_front()


# ---------------------------------------------------------------- level layouts
# Bridges and floods (level 3, "Two Banks"). Which bridge is flooded depends
# only on the clock, so the script is identical every session.

func flooded_bridges() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _layout.has("floods"): return result
	for flood: Array in _layout.floods:
		var begins: float = float(flood[1])
		var ends: float = begins + float(flood[2])
		if elapsed >= begins and elapsed < ends:
			var column: int = int(flood[0])
			var x: float = ROAD_X[column] * Campaign.MAP_SIZE.x
			var area := Rect2(x - 30.0, Campaign.RIVER_TOP - 6.0, 60.0, Campaign.RIVER_BOTTOM - Campaign.RIVER_TOP + 12.0)
			result.append({"column": column, "name": str(_layout.bridges.get(column, "Bridge")), "remaining": ends - elapsed,
				"position": area.position / Campaign.MAP_SIZE, "size": area.size / Campaign.MAP_SIZE})
	return result

func _bridge_open(column: int) -> bool:
	if not _layout.has("bridges"): return true
	if not _layout.bridges.has(column): return false
	if _ignore_road_events: return true
	for flood: Array in _layout.floods:
		if int(flood[0]) == column and elapsed >= float(flood[1]) and elapsed < float(flood[1]) + float(flood[2]):
			return false
	return true

func _tick_floods(delta: float) -> void:
	if not _layout.has("floods"): return
	var before: float = elapsed - delta
	for flood: Array in _layout.floods:
		var begins: float = float(flood[1])
		var ends: float = begins + float(flood[2])
		var name: String = str(_layout.bridges.get(int(flood[0]), "Bridge"))
		var x: float = ROAD_X[int(flood[0])]
		var pos := Vector2(x, (Campaign.RIVER_TOP + Campaign.RIVER_BOTTOM) * 0.5 / Campaign.MAP_SIZE.y)
		if before < begins and elapsed >= begins:
			_edge_cache.clear()
			_emit("bridge_flooded", "%s is flooded • cross the river somewhere else" % name, {"pos": pos, "bridge": name, "seconds": ends - begins})
			_emit_research("bridge_flood_started", {"shift": shift_index, "bridge": name, "at": elapsed, "until": ends, "chaos_phase": chaos_phase})
			_reroute_all()
		elif before < ends and elapsed >= ends:
			_edge_cache.clear()
			_emit("bridge_open", "%s is open again" % name, {"pos": pos, "bridge": name})
			_emit_research("bridge_flood_ended", {"shift": shift_index, "bridge": name, "at": elapsed})
			_reroute_all()

# Every moving crew takes the best route again (e.g. its bridge just flooded).
func _reroute_all() -> void:
	for unit: Dictionary in units:
		if str(unit.state) not in ["travel", "return"]: continue
		var path: Array = unit.path
		if path.is_empty(): continue
		var route: Dictionary = _best_route(unit, unit.pos, path.back())
		if not route.path.is_empty() and is_finite(float(route.eta)):
			unit.path = route.path
			unit.path_index = 0
			unit.remaining = float(route.eta)

func _edge_open(horizontal: bool, ix: int, iy: int) -> bool:
	if _layout.is_empty(): return true
	# Bridges exist but flood at scripted times.
	if not horizontal and _layout.has("bridges") and iy == int(_layout.get("river_row", -1)) and _layout.bridges.has(ix):
		return _bridge_open(ix)
	return not _blocked_edges.has("%s%d_%d" % ["h" if horizontal else "v", ix, iy])

func _set_layout() -> void:
	_layout = Campaign.layout(shift_index)
	_edge_cache.clear()
	_blocked_edges.clear()
	if _layout.is_empty(): return
	for iy: int in range(ROAD_Y.size()):
		for ix: int in range(ROAD_X.size()):
			if ix + 1 < ROAD_X.size() and Campaign.edge_blocked(_layout, true, ix, iy): _blocked_edges["h%d_%d" % [ix, iy]] = true
			if iy + 1 < ROAD_Y.size() and Campaign.edge_blocked(_layout, false, ix, iy): _blocked_edges["v%d_%d" % [ix, iy]] = true

# ---------------------------------------------------------------- hazard forecast
# Every bridge flood, blackout and storm step is announced ahead of time, both
# as an event (banner + sound) and through upcoming_hazards() for the HUD and map.
# Stateless (depends only on the clock), so guests and saved games agree.
func _tick_hazard_warnings(delta: float) -> void:
	var before: float = elapsed - delta
	for item: Dictionary in _hazard_plan():
		var warn_at: float = float(item.at) - Campaign.HAZARD_WARNING_SECONDS
		if before < warn_at and elapsed >= warn_at:
			_emit("hazard_warning", "%s in %ds" % [str(item.title), int(Campaign.HAZARD_WARNING_SECONDS)],
				{"pos": Vector2(item.position) + Vector2(item.size) * 0.5, "hazard_type": item.type, "title": item.title, "at": item.at})
			_emit_research("hazard_forecast", {"shift": shift_index, "type": item.type, "title": item.title, "starts_at": item.at, "at": elapsed})

# All scripted level hazards of this shift: {type, title, at, until, position, size}.
func _hazard_plan() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for flood: Array in _layout.get("floods", []):
		var x: float = ROAD_X[int(flood[0])] * Campaign.MAP_SIZE.x
		var area := Rect2(x - 30.0, Campaign.RIVER_TOP - 6.0, 60.0, Campaign.RIVER_BOTTOM - Campaign.RIVER_TOP + 12.0)
		var name: String = str(_layout.bridges.get(int(flood[0]), "Bridge"))
		result.append({"type": "flood", "title": "%s floods" % name, "name": name, "at": float(flood[1]), "until": float(flood[1]) + float(flood[2]),
			"position": area.position / Campaign.MAP_SIZE, "size": area.size / Campaign.MAP_SIZE})
	for plan: Dictionary in _shift.get("traffic", []):
		if not bool(plan.get("hazard", false)): continue
		var title: String = str(plan.name)
		if str(plan.type) == "blackout": title = "Blackout in %s" % plan.street
		elif str(plan.type) in ["sandstorm", "squall"]: title = "%s reaches %s" % ["Sandstorm" if plan.type == "sandstorm" else "Squall", plan.street]
		result.append({"type": str(plan.type), "title": title, "name": str(plan.name), "at": float(plan.at), "until": float(plan.at) + float(plan.duration),
			"position": plan.position, "size": plan.size, "eastward": bool(plan.get("eastward", true))})
	return result

# Hazards that start within the next `window` seconds, soonest first.
func upcoming_hazards(window: float = Campaign.HAZARD_WARNING_SECONDS) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in _hazard_plan():
		var wait: float = float(item.at) - elapsed
		if wait > 0.0 and wait <= window:
			var entry: Dictionary = item.duplicate()
			entry["in"] = wait
			result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["in"]) < float(b["in"]))
	return result

# Hazards in effect right now (floods and uncleared blackouts / storms), for the HUD.
func current_hazards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for flood: Dictionary in flooded_bridges():
		result.append({"type": "flood", "title": "%s flooded" % flood.name, "remaining": float(flood.remaining), "position": flood.position, "size": flood.size})
	for event: Dictionary in active_road_events():
		if not bool(event.get("hazard", false)): continue
		var title: String = str(event.name)
		if str(event.type) == "blackout" and str(event.status) == "clearing": title = "Restoring power in %s" % event.street
		result.append({"type": str(event.type), "title": title, "remaining": float(event.expires_at) - elapsed, "position": event.position, "size": event.size, "road_event_id": int(event.id)})
	return result

# Road-graph routing for levels with a layout. Nodes are the junctions of the
# road grid; a start or destination off a junction is attached to the
# junctions at both ends of the road it is on (or, for a building, of the
# road in front of it).
func _graph_route(unit: Dictionary, start: Vector2, destination: Vector2) -> Dictionary:
	var nx: int = ROAD_X.size()
	var ny: int = ROAD_Y.size()
	var zones: Array[Dictionary] = road_conditions()
	var probe: Dictionary = {"kind": str(unit.get("kind", "")), "fatigue": 0.0}
	var key: String = "%s|%s|%s" % [probe.kind, str(_ignore_road_events), _zone_signature(zones)]
	if not _edge_cache.has(key):
		_edge_cache[key] = {}
	var cache: Dictionary = _edge_cache[key]
	var starts: Array = _attach(start, false)
	var ends: Array = _attach(destination, true)
	var dist: Array = []
	var prev: Array = []
	var done: Array = []
	var entry: Array = []
	for i in range(nx * ny):
		dist.append(INF)
		prev.append(-1)
		done.append(false)
		entry.append([])
	for option: Dictionary in starts:
		var cost: float = _points_time(probe, start, option.points, zones)
		if cost < dist[option.node]:
			dist[option.node] = cost
			entry[option.node] = option.points
	while true:
		var current: int = -1
		var best: float = INF
		for i in range(nx * ny):
			if not done[i] and dist[i] < best:
				best = dist[i]
				current = i
		if current < 0: break
		done[current] = true
		var cx: int = current % nx
		var cy: int = current / nx
		for step: Vector3i in [Vector3i(1, 0, 1), Vector3i(-1, 0, 1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
			var ox: int = cx + step.x
			var oy: int = cy + step.y
			if ox < 0 or oy < 0 or ox >= nx or oy >= ny: continue
			var horizontal: bool = step.z == 1
			if not _edge_open(horizontal, mini(cx, ox), mini(cy, oy)): continue
			var other: int = ox + oy * nx
			var edge_key: int = mini(current, other) * 1000 + maxi(current, other)
			if not cache.has(edge_key):
				cache[edge_key] = float(_travel_segment(probe, _node_point(current), _node_point(other), 0.0, INF, zones).time)
			var through: float = best + float(cache[edge_key])
			if through < dist[other]:
				dist[other] = through
				prev[other] = current
	var best_points: Array[Vector2] = []
	var best_eta: float = INF
	for option: Dictionary in ends:
		if not is_finite(float(dist[option.node])): continue
		var chain: Array[Vector2] = []
		var node: int = option.node
		while node >= 0:
			chain.push_front(_node_point(node))
			if prev[node] < 0:
				for i in range(entry[node].size() - 1, -1, -1):
					chain.push_front(entry[node][i])
			node = prev[node]
		for point: Vector2 in option.points:
			chain.append(point)
		chain.append(destination)
		var eta: float = _route_eta(unit, start, _clean_path(start, chain), zones)
		if eta < best_eta:
			best_eta = eta
			best_points = _clean_path(start, chain)
	# Start and destination on the same stretch of road: drive straight there.
	var direct: Array[Vector2] = _direct_path(start, destination)
	if not direct.is_empty():
		var eta: float = _route_eta(unit, start, direct, zones)
		if eta < best_eta:
			best_eta = eta
			best_points = direct
	return {"path": best_points, "eta": best_eta}

func _zone_signature(zones: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for zone: Dictionary in zones:
		parts.append("%d:%s" % [int(zone.get("road_event_id", -1)), str(zone.get("pass_kind", ""))])
	for flood: Dictionary in flooded_bridges():
		parts.append("f%d" % int(flood.column))
	return ",".join(parts)

func _node_point(node: int) -> Vector2:
	return Vector2(ROAD_X[node % ROAD_X.size()], ROAD_Y[node / ROAD_X.size()])

func _index_of(value: float, options: Array[float]) -> int:
	var best: int = 0
	for i in range(options.size()):
		if absf(options[i] - value) < absf(options[best] - value): best = i
	return best

# Junctions a point connects to, with the points driven in between.
# reverse = true for a destination (points run from the junction to it).
func _attach(point: Vector2, reverse: bool) -> Array:
	var nx: int = ROAD_X.size()
	var eps: float = 0.0005
	var ix: int = _index_of(point.x, ROAD_X)
	var iy: int = _index_of(point.y, ROAD_Y)
	var on_column: bool = absf(point.x - ROAD_X[ix]) < eps
	var on_row: bool = absf(point.y - ROAD_Y[iy]) < eps
	var result: Array = []
	if on_column and on_row:
		result.append({"node": ix + iy * nx, "points": []})
		return result
	if on_column:
		var upper: int = iy if ROAD_Y[iy] <= point.y else iy - 1
		for row: int in [upper, upper + 1]:
			if row >= 0 and row < ROAD_Y.size():
				result.append({"node": ix + row * nx, "points": []})
		return result
	# On a horizontal road, or a building reached from the road in front of it.
	var entry := Vector2(point.x, ROAD_Y[iy])
	var left: int = ix if ROAD_X[ix] <= point.x else ix - 1
	for column: int in [left, left + 1]:
		if column >= 0 and column < nx:
			var pts: Array = [] if on_row else [entry]
			if reverse:
				pts.reverse()
			result.append({"node": column + iy * nx, "points": pts})
	return result

func _direct_path(start: Vector2, destination: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var sy: int = _index_of(start.y, ROAD_Y)
	var dy: int = _index_of(destination.y, ROAD_Y)
	if sy != dy: return result
	var sx: float = start.x
	var dx: float = destination.x
	# Must not pass a junction in between (then the graph route covers it).
	for x: float in ROAD_X:
		if x > minf(sx, dx) + 0.0005 and x < maxf(sx, dx) - 0.0005: return result
	var points: Array = [Vector2(sx, ROAD_Y[sy]), Vector2(dx, ROAD_Y[sy]), destination]
	return _clean_path(start, points)

func _clean_path(start: Vector2, points: Array) -> Array[Vector2]:
	var clean: Array[Vector2] = []
	var previous: Vector2 = start
	for point: Vector2 in points:
		if previous.distance_to(point) > 0.00001:
			clean.append(point)
			previous = point
	return clean

func _points_time(probe: Dictionary, start: Vector2, points: Array, zones: Array[Dictionary]) -> float:
	var total: float = 0.0
	var previous: Vector2 = start
	for point: Vector2 in points:
		total += float(_travel_segment(probe, previous, point, 0.0, INF, zones).time)
		previous = point
	return total
