class_name RescueSimulation
extends RefCounted

const Campaign = preload("res://scripts/campaign.gd")
const UNIT_KINDS: Array[String] = ["fire", "medic", "engineer"]
const INCIDENT_KINDS: Array[String] = ["fire", "medical", "flood", "power"]
const ROAD_X: Array[float] = [0.18, 0.40, 0.62, 0.84]
const ROAD_Y: Array[float] = [0.20, 0.45, 0.72]

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
var wrong_dispatches: int = 0
var last_action_effect: Dictionary = {}

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
	wrong_dispatches = 0
	last_action_effect = {}
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
	_tick_surges(delta)
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
	_next_spawn -= delta
	if _next_spawn <= 0.0 and elapsed < duration - 45.0 and breather_remaining <= 0.0:
		if active_count() < int(_shift.max_active):
			_spawn_incident()
			var interval: float = float(_shift.interval)
			if elapsed < 42.0 and shift_index == 0:
				interval = 13.0
			elif elapsed > 140.0:
				interval *= 0.91
			if rush_remaining > 0.0:
				interval *= 0.7
			if disruption == "festival":
				interval *= 0.72
			_next_spawn = interval + _rng.randf_range(-2.2, 2.2)
		else:
			_next_spawn = 3.0
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

func _tick_surges(delta: float) -> void:
	breather_remaining = maxf(0.0, breather_remaining - delta)
	var previous_rush: float = rush_remaining
	rush_remaining = maxf(0.0, rush_remaining - delta)
	if previous_rush > 0.0 and rush_remaining <= 0.0:
		_surge_pending = 0
		breather_remaining = _surge_breather_length
		_emit("surge_end", "The radio eases • clear the remaining calls", {"breather": breather_remaining})
	var schedule: Array = _shift.get("surges", [])
	surge_warning_remaining = 0.0
	if _surge_index < schedule.size():
		var wave: Dictionary = schedule[_surge_index]
		var until: float = float(wave.at) - elapsed
		if until <= 7.0 and until > 0.0:
			surge_warning_remaining = until
			if _surge_warned_index != _surge_index:
				_surge_warned_index = _surge_index
				_emit("surge_warning", "%s in 7 seconds • prepare your crews" % wave.name, {"in": until, "surge_name": wave.name})
		if until <= 0.0:
			rush_remaining = float(wave.duration)
			_surge_breather_length = float(wave.breather)
			_surge_pending = int(wave.calls)
			_surge_spawn_timer = 0.0
			breather_remaining = 0.0
			surge_count += 1
			_surge_index += 1
			_next_spawn = maxf(_next_spawn, 7.0)
			_emit("surge_started", "%s • all stations, stand by" % wave.name, {"surge_name": wave.name, "duration": rush_remaining, "calls": _surge_pending})
	if _surge_pending > 0 and rush_remaining > 0.0:
		_surge_spawn_timer -= delta
		if _surge_spawn_timer <= 0.0:
			if active_count() < int(_shift.max_active):
				_spawn_incident()
				_surge_pending -= 1
			_surge_spawn_timer = 2.6

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
	if dispatch_cooldown > 0.0:
		_emit("action_denied", "Dispatch is transmitting • one order at a time")
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
	dispatch_cooldown = 0.65
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

func scout(incident_id: int) -> bool:
	if not running:
		return false
	var incident: Dictionary = get_incident(incident_id)
	if incident.is_empty() or not _is_active(incident) or bool(incident.get("scouted", false)):
		return false
	if scout_cooldown > 0.0:
		_emit("action_denied", "Field team ready in %ds" % ceili(scout_cooldown))
		return false
	var before_deadline: float = float(incident.deadline)
	var before_hazard: float = float(incident.get("hazard", 0.0))
	var before_work: float = _current_work_seconds(incident)
	incident.discovered = true
	incident.scouted = true
	var time_granted: float = 9.0 + 6.0 * upgrade_level("scouting")
	incident.deadline = maxf(float(incident.deadline), minf(float(incident.max_deadline) + 24.0, float(incident.deadline) + time_granted))
	incident.work_bonus = float(incident.work_bonus) + 0.1 + 0.1 * upgrade_level("scouting")
	incident.last_action = elapsed
	incident.hazard = maxf(0.0, float(incident.get("hazard", 0.0)) - 0.16)
	incident.stabilized_until = maxf(float(incident.get("stabilized_until", 0.0)), elapsed + 4.0)
	scout_count += 1
	scout_cooldown = 8.0
	last_action_effect = {"action": "scout", "incident_id": incident_id, "time_added": float(incident.deadline) - before_deadline, "hazard_reduced": before_hazard - float(incident.hazard), "work_bonus_added": 0.1 + 0.1 * upgrade_level("scouting"), "work_seconds_saved": maxf(0.0, before_work - _current_work_seconds(incident)), "estimated": true}
	var message: String = str(incident.bonus)
	var scout_effect: Dictionary = last_action_effect.duplicate(true)
	scout_effect.pos = incident.pos
	_emit("scout", "Field report • +%ds • %s" % [int(last_action_effect.time_added), message], scout_effect)
	return true

func supply(incident_id: int) -> bool:
	if not running:
		return false
	var incident: Dictionary = get_incident(incident_id)
	if incident.is_empty() or not _is_active(incident):
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
	_emit("rally", "Town rally! • every crew moves and works faster")
	return true

func buy_upgrade(id: String) -> bool:
	if running:
		return false
	var entry: Dictionary = Campaign.upgrade_data(id)
	if entry.is_empty():
		return false
	var level: int = upgrade_level(id)
	var cost: int = Campaign.upgrade_cost(id, level)
	if level >= int(entry.max_level) or credits < cost:
		return false
	credits -= cost
	upgrades[id] = level + 1
	_emit("upgrade", "%s • level %d" % [entry.name, level + 1], {"upgrade_id": id, "cost": cost})
	return true

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))

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
	return clampf(float(active_count()) * 0.11 + hazard_total * 0.075 + urgent * 0.1 + (0.16 if rush_remaining > 0.0 else 0.0), 0.0, 1.0)

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
	var result: Array[Dictionary] = []
	for entry: Dictionary in _shift.get("traffic", []):
		var begins: float = float(entry.at)
		var ends: float = begins + float(entry.duration)
		if elapsed >= begins and elapsed < ends:
			result.append({"name": entry.name, "position": entry.position, "size": entry.size, "speed_factor": float(entry.speed_factor), "remaining": ends - elapsed})
	if disruption_remaining > 0.0:
		if disruption in ["market", "festival"]:
			result.append({"name": "Market queues", "position": Vector2(0.28, 0.425), "size": Vector2(0.27, 0.05), "speed_factor": 0.42, "remaining": disruption_remaining})
		elif disruption == "roadworks":
			result.append({"name": "Bridge works", "position": Vector2(0.595, 0.19), "size": Vector2(0.05, 0.28), "speed_factor": 0.38, "remaining": disruption_remaining})
		elif disruption in ["rain", "storm"]:
			result.append({"name": "Flooded harbor road", "position": Vector2(0.59, 0.695), "size": Vector2(0.35, 0.05), "speed_factor": 0.48, "remaining": disruption_remaining})
	return result

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
			if bool(incident.scouted): growth *= 0.65
			if special_duration > time: growth *= 0.65
			hazard = minf(1.0, hazard + step * growth)
		var burn: float = (0.26 if complete else (0.72 if any_arrived else 1.0)) * (1.0 + hazard * 0.35)
		if bool(incident.scouted) and disruption in ["blackout", "comms"] and time < disruption_remaining:
			burn *= 0.8
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
	var state: Dictionary = {
		"snapshot_version": 4,
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
		"scout_cooldown": scout_cooldown, "dispatch_cooldown": dispatch_cooldown,
		"wrong_dispatches": wrong_dispatches, "last_action_effect": last_action_effect.duplicate(true),
		"_surge_index": _surge_index, "_surge_warned_index": _surge_warned_index,
		"_surge_pending": _surge_pending, "_surge_spawn_timer": _surge_spawn_timer, "_surge_breather_length": _surge_breather_length,
		"_next_spawn": _next_spawn, "_next_id": _next_id,
		"_disruption_index": _disruption_index, "_reported_final_minute": _reported_final_minute,
		"_reported_target": _reported_target, "_previous_spawn_location": _previous_spawn_location,
		
		"_rng_seed": str(_rng.seed), "_rng_state": str(_rng.state), "_shift": _shift.duplicate(true)
	}
	return _snapshot_encode(state)

func apply_snapshot(data: Dictionary) -> void:
	if data.is_empty():
		return
	var restored: Dictionary = _snapshot_decode(data)
	for key: String in restored:
		if key in ["incidents", "units", "events"]:
			var typed: Array[Dictionary] = []
			for entry: Dictionary in restored[key]:
				typed.append(entry.duplicate(true))
			set(key, typed)
		elif key in ["breather_remaining", "surge_warning_remaining", "surge_count", "escalation_count", "rapid_response_count", "peak_active", "_surge_index", "_surge_warned_index", "_surge_pending", "_surge_spawn_timer", "_surge_breather_length"]:
			set(key, restored[key])
		elif key in ["scout_cooldown", "dispatch_cooldown", "wrong_dispatches", "last_action_effect", "minimum_confidence"]:
			set(key, restored[key])
		elif key in ["shift_index", "elapsed", "duration", "running", "finished", "won", "score", "reputation", "rescued", "combo", "best_combo", "credits", "upgrades", "weather", "notice", "supplies", "max_supplies", "supply_regen", "special_cooldown", "special_duration", "disruption", "disruption_remaining", "resolved_count", "failed_count", "total_spawned", "stars", "target", "shift_reward", "successful_dispatches", "scout_count", "supply_count", "rush_remaining", "_next_spawn", "_next_id", "_disruption_index", "_reported_final_minute", "_reported_target", "_previous_spawn_location"]:
			set(key, restored[key])
	_shift = restored.get("_shift", Campaign.shift_data(shift_index)).duplicate(true)
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

func _migrate_revision_state(restored: Dictionary) -> void:
	for key: String in ["scout_cooldown", "dispatch_cooldown", "wrong_dispatches"]:
		if not restored.has(key): set(key, 0)
	if not restored.has("last_action_effect"): last_action_effect = {}
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
	var counts: Dictionary = {"fire": 0, "medic": 0, "engineer": 0}
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
	return {"shift": shift_index, "title": _shift.get("title", ""), "won": won, "stars": stars, "score": score, "rescued": rescued, "target": target, "resolved": resolved_count, "missed": failed_count, "reputation": snappedf(reputation, 0.1), "best_combo": best_combo, "credits_earned": shift_reward, "duration": elapsed, "dispatches": successful_dispatches, "scouts": scout_count, "supplies_used": supply_count, "surges": surge_count, "escalations": escalation_count, "rapid_responses": rapid_response_count, "peak_calls": peak_active, "wrong_dispatches": wrong_dispatches, "minimum_confidence": minimum_confidence}

func kind_name(kind: String) -> String:
	return str({"fire": "Fire", "medic": "Medical", "medical": "Medical", "engineer": "Engineer", "flood": "Flood", "power": "Power"}.get(kind, kind.capitalize()))

func _build_fleet() -> void:
	var crew_names: Dictionary = {"fire": ["Ember", "Cinder", "Spark"], "medic": ["Clover", "Willow", "Fern"], "engineer": ["Bolt", "Copper", "Wren"]}
	var homes: Dictionary = {"fire": Vector2(0.18, 0.45), "medic": Vector2(0.62, 0.45), "engineer": Vector2(0.84, 0.45)}
	var standby: Dictionary = {"fire": Vector2(0.84, 0.20), "medic": Vector2(0.40, 0.72), "engineer": Vector2(0.18, 0.20)}
	var id: int = 0
	for kind: String in UNIT_KINDS:
		var count: int = 2 + upgrade_level(kind + "_crew")
		for crew_index: int in range(count):
			var home: Vector2 = standby[kind] if crew_index == 1 else homes[kind] + Vector2(0.009 * crew_index, 0.0)
			var unit: Dictionary = {"id": id, "name": crew_names[kind][crew_index], "kind": kind, "pos": home, "home": home, "target": -1, "state": "idle", "remaining": 0.0, "fatigue": 0.0, "path": [], "path_index": 0, "heading": Vector2.RIGHT, "jobs": 0, "arrival_at": -1.0, "work_elapsed": 0.0, "work_phase": "idle", "assignment_suitable": true, "inspection_remaining": 0.0, "dispatch_guard_until": 0.0, "divert_after": 0.0}
			unit.merge(Campaign.responder_profile(kind, crew_index))
			units.append(unit)
			id += 1

func _spawn_incident() -> void:
	var places: Array[Dictionary] = Campaign.locations()
	var used: Array[int] = []
	for active: Dictionary in incidents:
		if _is_active(active):
			used.append(int(active.location_index))
	var location_index: int = _rng.randi_range(0, places.size() - 1)
	for attempt: int in range(40):
		if location_index not in used and location_index != _previous_spawn_location:
			break
		location_index = _rng.randi_range(0, places.size() - 1)
	_previous_spawn_location = location_index
	var place: Dictionary = places[location_index]
	var kind: String = _choose_kind()
	var severity: int = 1
	if shift_index > 0 and _rng.randf() < 0.30 + 0.05 * shift_index:
		severity = 2
	if shift_index >= 3 and elapsed > 80.0 and _rng.randf() < 0.18:
		severity = 3
	
	if shift_index == 0:
		kind = ["medical", "fire", "power", "medical", "fire", "medical", "power", "flood"][total_spawned % 8]
		if kind == "flood" or (elapsed > 95.0 and _rng.randf() < 0.28):
			severity = 2
	var report_clear: bool = _rng.randf() < (0.66 if shift_index < 2 else 0.57)
	if disruption in ["blackout", "comms"]: report_clear = false
	if shift_index == 0 and total_spawned == 0: report_clear = true
	if shift_index == 0 and total_spawned == 1:
		report_clear = false
		severity = 2
	var needs: Dictionary = {"fire": 0, "medic": 0, "engineer": 0}
	match kind:
		"fire":
			needs.fire = 1
			if severity >= 2:
				needs.medic = 1
			if severity >= 3:
				needs.engineer = 1
		"medical":
			needs.medic = 1
			if severity >= 3:
				needs.fire = 1
				needs.engineer = 1
		"flood":
			needs.engineer = 1
			if severity >= 2:
				needs.medic = 1
			if severity >= 3:
				needs.fire = 1
		"power":
			needs.engineer = 1
			if severity >= 2:
				needs.fire = 1
			if severity >= 3:
				needs.medic = 1
	var work_duration: float = 10.0 + severity * 4.2
	var arrival_budget: float = 0.0
	for needed_kind: String in UNIT_KINDS:
		if int(needs[needed_kind]) == 0: continue
		var fastest: float = INF
		for crew: Dictionary in units:
			if crew.kind != needed_kind: continue
			var route: Dictionary = _best_route(crew, crew.pos, place.pos)
			
			
			var handover: float = 0.0 if _unit_available(crew) else 8.0
			fastest = minf(fastest, float(route.eta) + handover)
		arrival_budget = maxf(arrival_budget, fastest)
	var decision_slack: float = 18.0 - shift_index * 1.2
	if total_spawned > 2 and _rng.randf() < 0.25: decision_slack *= 0.58
	var deadline: float = arrival_budget * 1.12 + work_duration * 0.30 + decision_slack + _rng.randf_range(-2.0, 4.0) + 7.0 * upgrade_level("radio")
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

func _choose_kind() -> String:
	var weights: Array = _shift.get("weights", [4, 4, 2, 2]).duplicate()
	if disruption == "rain" or disruption == "storm":
		weights[2] = int(weights[2]) + 4
	if disruption == "blackout":
		weights[3] = int(weights[3]) + 5
	var total: int = 0
	for weight: int in weights:
		total += weight
	var roll: int = _rng.randi_range(1, total)
	for index: int in range(weights.size()):
		roll -= int(weights[index])
		if roll <= 0:
			return INCIDENT_KINDS[index]
	return "medical"

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
	var deadline_speed: float = 0.26 if complete_team else (0.72 if arrived_total > 0 else 1.0)
	deadline_speed *= 1.0 + float(incident.hazard) * 0.35
	if bool(incident.scouted) and disruption in ["blackout", "comms"]:
		deadline_speed *= 0.8
	incident.deadline = maxf(0.0, float(incident.deadline) - delta * deadline_speed)
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
		if bool(incident.scouted):
			growth *= 0.65
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
		var descriptions: Dictionary = {"fire": "Fire spreading", "medical": "Condition worsening", "flood": "Water rising", "power": "Grid destabilizing"}
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
	_emit("resolved", "%d neighbors safe • crews returning to standby" % incident.people, {"incident_id": incident.id, "pos": incident.pos, "people": incident.people, "points": earned, "combo": combo})
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

func _send_home(unit: Dictionary) -> void:
	if unit.is_empty():
		return
	unit.jobs = int(unit.jobs) + 1
	unit.fatigue = minf(1.0, float(unit.fatigue) + 0.14 * maxf(0.2, 1.0 - upgrade_level("rest") * 0.35))
	unit.target = -1
	unit.state = "return"
	unit.work_phase = "return"
	var route: Dictionary = _best_route(unit, unit.pos, unit.home)
	unit.path = route.path
	unit.path_index = 0
	unit.remaining = float(route.eta)

func _travel_speed(unit: Dictionary, offset: float = 0.0) -> float:
	var speed: float = 0.095 * (1.0 + upgrade_level("engines") * 0.14)
	speed *= 1.0 - float(unit.fatigue) * 0.12
	if special_duration > offset and special_duration > 0.0:
		speed *= 1.5
	return speed

func _best_route(unit: Dictionary, start: Vector2, destination: Vector2) -> Dictionary:
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
	var length: float = difference.length()
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
		length += previous.distance_to(point)
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
