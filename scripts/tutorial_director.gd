class_name TutorialDirector
extends RefCounted



const Campaign = preload("res://scripts/campaign.gd")
enum Step { WELCOME, SELECT_MEDICAL, DISPATCH_MEDIC, WATCH_MEDIC, SCOUT_FIRE, READ_MARGIN, DISPATCH_FIRE, SUPPLY_FIRE, DISPATCH_ENGINEER, RALLY, WATCH_TEAM, COMPARE_CALLS, CHALLENGE, OUTCOME, COMPLETE }
const STAGE_COUNT: int = 15
const CAST: Dictionary = {"fire": "Bram", "medic": "Elio", "engineer": "Tess"}
var sim: RescueSimulation
var stage: int = Step.WELCOME
var stage_elapsed: float = 0.0
var active: bool = false
var finished: bool = false
var total_elapsed: float = 0.0
var challenge_attempts: int = 0
var _medical_id: int = -1
var _fire_id: int = -1
var _engineer_id: int = -1
var _selected_id: int = -1
var _selected_unit_id: int = -1
var _selected_unit_call: int = -1
var _rally_used: bool = false
var _scout_before: float = 0.0
var _scout_added: float = 0.0
var _supply_before: float = 0.0
var _supply_margin_before: float = 0.0
var _supply_added: float = 0.0
var _challenge_ids: Array[int] = []
var _challenge_snapshot: Dictionary = {}
var _challenge_started: bool = false
var _challenge_won: bool = false
var _challenge_first: int = -1

func begin(practice_sim: RescueSimulation) -> void:
	if practice_sim == null: return
	sim = practice_sim
	sim.upgrades = {}
	sim.credits = 0
	sim.start_shift(0)
	sim._rng.seed = 44004
	sim._shift = sim._shift.duplicate(true)
	for key: String in ["surges", "disruptions", "traffic"]: sim._shift[key] = []
	sim._shift["interval"] = 1000000.0
	sim._shift["max_active"] = 3
	sim._next_spawn = 1000000.0
	sim.target = 999
	sim._reported_target = true
	sim._reported_final_minute = true
	sim.weather = "clear"
	sim.disruption = ""
	sim.notice = "Practice: read the route, protect the rescue"
	sim.events.clear()
	_prepare_cast()
	stage = Step.WELCOME
	stage_elapsed = 0.0
	total_elapsed = 0.0
	active = true
	finished = false
	_medical_id = -1
	_fire_id = -1
	_engineer_id = -1
	_selected_id = -1
	_selected_unit_id = -1
	_selected_unit_call = -1
	_rally_used = false
	_challenge_ids.clear()
	_challenge_snapshot.clear()
	_challenge_started = false
	_challenge_won = false
	_challenge_first = -1
	challenge_attempts = 0

func tick(delta: float) -> void:
	if not active or finished or sim == null: return
	var step: float = maxf(0.0, delta)
	stage_elapsed += step
	total_elapsed += step
	
	if _watch_is_running(): sim.tick(minf(step, 0.25))
	else:
		
		
		sim.dispatch_cooldown = maxf(0.0, sim.dispatch_cooldown - step)
	_evaluate_action_stage()
	if stage == Step.CHALLENGE and _challenge_started:
		if _challenge_has_failed() or _challenge_is_resolved():
			_challenge_won = _challenge_is_resolved()
			_enter_stage(Step.OUTCOME)

func can_action(action: String, payload: Dictionary = {}) -> bool:
	if not active or finished: return false
	var normalized: String = _normalize_action(action, payload)
	if normalized not in current().allowed: return false
	if normalized == "filter": return true
	if normalized == "select_unit":
		var unit: Dictionary = _unit(int(payload.get("unit_id",-1)))
		var expected: String = _stage_crew_kind()
		return not unit.is_empty() and (expected.is_empty() or str(unit.kind)==expected)
	if normalized.begins_with("dispatch:"):
		
		
		if int(payload.get("unit_id",-1))!=_selected_unit_id or _selected_unit_id<0: return false
		var unit: Dictionary = _unit(_selected_unit_id)
		if unit.is_empty() or normalized!="dispatch:"+str(unit.kind): return false
	if stage == Step.CHALLENGE:
		return normalized == "special" or _action_incident(action, payload) in _challenge_ids
	if normalized == "select": return true
	if normalized in ["scout", "supply", "dispatch:fire"]: return _action_incident(action, payload) == _fire_id
	if normalized == "dispatch:medic": return _action_incident(action, payload) == _medical_id
	if normalized == "dispatch:engineer": return _action_incident(action, payload) == _engineer_id
	return true

func on_action(action: String, payload: Dictionary = {}, success: bool = true) -> bool:
	if not success or not can_action(action, payload): return false
	var previous_stage: int = stage
	var normalized: String = _normalize_action(action, payload)
	if normalized == "select":
		var call_id: int = _action_incident(action, payload)
		if call_id!=_selected_id:
			_selected_unit_id=-1
			_selected_unit_call=-1
		_selected_id = call_id
	if normalized == "select_unit":
		_selected_unit_id=int(payload.get("unit_id",-1))
		_selected_unit_call=_action_incident(action,payload)
	if stage == Step.SCOUT_FIRE and normalized == "scout": _scout_added = float(sim.get_incident(_fire_id).deadline) - _scout_before
	if stage == Step.SUPPLY_FIRE and normalized == "supply": _supply_added = float(sim.get_incident(_fire_id).deadline) - _supply_before
	if stage == Step.RALLY and normalized == "special": _rally_used = sim.special_duration > 0.0 and _is_open(_fire_id) and _is_open(_engineer_id)
	if stage == Step.CHALLENGE and normalized.begins_with("dispatch:"):
		var call: Dictionary = sim.get_incident(_action_incident(action, payload))
		if not call.is_empty() and not call.assigned.is_empty():
			_challenge_started = true
			if _challenge_first < 0: _challenge_first = int(call.id)
	if normalized.begins_with("dispatch:"):
		_selected_unit_id=-1
		_selected_unit_call=-1
	_evaluate_action_stage()
	return stage != previous_stage

func advance() -> bool:
	if not active or finished or not bool(current().can_advance): return false
	if stage == Step.OUTCOME and not _challenge_won: return retry_challenge()
	if stage == Step.COMPLETE:
		finished = true
		active = false
		sim.running = false
		return true
	_enter_stage(stage + 1)
	return true

func retry_challenge() -> bool:
	if not active or stage != Step.OUTCOME or _challenge_won or _challenge_snapshot.is_empty(): return false
	sim.apply_snapshot(_challenge_snapshot.duplicate(true))
	sim.events.clear()
	_challenge_started = false
	_challenge_first = -1
	_challenge_won = false
	challenge_attempts += 1
	_enter_stage(Step.COMPARE_CALLS)
	return true

func cancel() -> void:
	active = false
	if sim != null: sim.running = false

func current() -> Dictionary:
	var card: Dictionary = {"speaker":"Nova", "title":"Your decision reaches the street", "text":"", "objective":"", "allowed":[], "highlight":"next", "next_label":"LET'S BEGIN", "can_advance":false, "focus_id":-1, "stage":stage, "stage_count":STAGE_COUNT, "progress":float(stage)/float(STAGE_COUNT-1), "simulation_paused":not _watch_is_running(), "show_focus":stage in [Step.WATCH_MEDIC,Step.WATCH_TEAM], "show_routes":true, "independent_choice":stage in [Step.COMPARE_CALLS,Step.CHALLENGE,Step.OUTCOME], "retry_available":stage==Step.OUTCOME and not _challenge_won, "is_final":stage==Step.COMPLETE, "clear_selection":stage==Step.COMPARE_CALLS, "metrics":{}, "challenge_ids":_challenge_ids.duplicate()}
	match stage:
		Step.WELCOME:
			card.text = "I'm Nova. Sending a crew is only the start: they must travel, arrive and finish helping before the call runs out. We'll use the map to make that happen."
			card.objective = "Read the route. Match the crew. Leave time for the work."
			card.can_advance = active
		Step.SELECT_MEDICAL:
			_set_card(card,"Nova","Start with the place that needs help","Click Beacon Clinic. The icons under it show which crews it needs; the number is the time left.","Click Beacon Clinic.",_medical_id,"call:%d"%_medical_id,["select"])
		Step.DISPATCH_MEDIC:
			_set_card(card,"Elio","Pick the crew on the map","Click my medic station (the white cross) to pick me. You'll see my route. Then click the clinic again to send me.","Click Elio's station, then click the clinic.",_medical_id,"map_unit:medic",["select","select_unit","dispatch:medic"])
			card.metrics = _best_option(_medical_id)
		Step.WATCH_MEDIC:
			_set_card(card,"Elio","Arrival is not completion","Follow the ambulance's route, then watch us step out and work. The rescue only counts when the work bar fills before the countdown reaches zero.","Watch travel, arrival and the completed rescue.",_medical_id,"map",["select","select_unit"])
			card.can_advance = _is_resolved(_medical_id)
			card.next_label = "READ A REPORT"
			if card.can_advance:
				card.title = "Now Elio can help someone else"
				card.text = "The rescue is complete. Elio can take another call while returning. Until the work finished, he was committed here: there isn't an unlimited supply of crews."
		Step.SCOUT_FIRE:
			_set_card(card,"Bram","A question mark is missing information","The ? means nobody knows what the bakery needs. Q sends the scout team to find out. Scouting only reveals; it doesn't buy time.","Select the bakery and press Q.",_fire_id,"scout",["select","select_unit","scout"])
		Step.READ_MARGIN:
			_set_card(card,"Bram","Known needs. A risky finish.","It's a fire. Click my fire station to pick me and look at the margin: the time left over after travel and work. Negative means we'll be late without help.","Click Bram's fire station and read the margin.",_fire_id,"map_unit:fire",["select","select_unit"])
			card.can_advance = _selected_unit_id>=0
			card.next_label = "SEND BRAM"
			card.metrics = _best_option(_fire_id)
		Step.SUPPLY_FIRE:
			if _crew_on_scene(_fire_id):
				_set_card(card,"Bram","Supplies help a crew on scene","I'm at the bakery, but the margin is %s. E sends a crate to the crew on scene: +18 seconds, less danger, faster work. Supplies only work once a crew is there."%_seconds(float(sim.incident_estimate(_fire_id).get("margin",0.0))),"Press E to send a supply to the bakery.",_fire_id,"supply",["select","select_unit","supply"])
			else:
				_set_card(card,"Bram","On my way","Watch me drive to the bakery. Supplies can only go to a crew that is already on scene.","Wait for Bram to arrive.",_fire_id,"map",["select","select_unit"])
			card.metrics = {"margin_before":_supply_margin_before,"deadline_before":_supply_before}
		Step.DISPATCH_FIRE:
			var option: Dictionary = _best_option(_fire_id)
			_set_card(card,"Bram","Send me anyway","Even late, it's better to be on the way. Pick me at the fire station, then click the bakery. We'll fix the margin once I'm there.","Click Bram's station, then the bakery.",_fire_id,"map_unit:fire",["select","select_unit","dispatch:fire"])
			card.metrics = option
		Step.DISPATCH_ENGINEER:
			_set_card(card,"Tess","A different skill can work in parallel","Bram is busy at the bakery. Pick me at the engineer station, then click Harbor Workshop to send me.","Click Tess's station, then Harbor Workshop.",_engineer_id,"map_unit:engineer",["select","select_unit","dispatch:engineer"])
		Step.RALLY:
			_set_card(card,"Nova","One boost helps both crews","Bram and Tess are on the road. The coffee boost makes every crew move and work faster for twenty seconds. Save it for when several calls need help.","Press Space for a coffee boost.",_fire_id,"special",["select","select_unit","special"])
		Step.WATCH_TEAM:
			_set_card(card,"Tess","Two routes. Two jobs getting done.","Bram contains the bakery while I repair the workshop. Each route takes time and each rescue still needs work after arrival. Both calls must finish.","Watch both calls resolve.",_engineer_id,"map",["select","select_unit"])
			card.can_advance = _is_resolved(_fire_id) and _is_resolved(_engineer_id)
			card.next_label = "TRY YOUR OWN PLAN"
		Step.COMPARE_CALLS:
			_set_card(card,"Tess","The shortest countdown isn't the whole story","Two repairs, one engineer. Pick me and hover each call to compare margins: a longer countdown can hide a longer drive.","Compare both calls, then choose.",-1,"map_unit:engineer",["select","select_unit"])
			card.can_advance = true
			card.next_label = "MY TURN"
			card.metrics = _challenge_metrics()
		Step.CHALLENGE:
			_set_card(card,"Nova","Bring both calls home","Choose the order and support yourself. One engineer must finish a job before taking the other. Use the route and margin, and divert Tess when available. Wrong crews still waste a real trip.","Rescue both calls. Time starts with your first dispatch.",-1,"map",["select","select_unit","dispatch:fire","dispatch:medic","dispatch:engineer","scout","supply","special"])
			if _challenge_started: card.objective = "Rescue both calls: %d / 2 complete. Support is your choice."%_challenge_resolved_count()
			card.metrics = _challenge_metrics()
		Step.OUTCOME:
			card.title = "Your plan brought everyone home" if _challenge_won else "A missed call. A useful lesson."
			card.text = "You chose the crews, order and support, and both repairs finished. Keep comparing routes and margins as roads and crew positions change." if _challenge_won else "The countdown ran out before a rescue finished. Try a different order or stabilize the waiting call. Retry restores these two calls and your supplies; your campaign is untouched."
			card.objective = "Two rescues complete. You made the decisions." if _challenge_won else "Review the map, then retry the same two-call exercise."
			card.next_label = "READY FOR MY WATCH" if _challenge_won else "RETRY TWO CALLS"
			card.can_advance = true
			card.allowed = ["select"]
		Step.COMPLETE:
			card.title = "Ready to read the town"
			card.text = "Pick a crew (station or vehicle), then click the call. Q scouts a ? call. E helps a crew on scene. Space is the coffee boost. Shortcut: hover a call and press 1-4 to send the nearest crew of that type. Right-click clears your selection."
			card.objective = "Practice complete. Your campaign progress stays untouched."
			card.next_label = "READY FOR BEACON BAY"
			card.can_advance = active
	card["crew_kind"]=_stage_crew_kind()
	card["map_selection_required"]=not _stage_crew_kind().is_empty() and _selected_unit_id<0
	if "select_unit" in card.allowed: card.allowed.append("filter")
	return card

func _set_card(card: Dictionary, speaker: String, title: String, body: String, objective: String, focus: int, highlight: String, allowed: Array) -> void:
	card.speaker=speaker; card.title=title; card.text=body; card.objective=objective
	card.focus_id=focus; card.highlight=highlight; card.allowed=allowed

func _enter_stage(next_stage: int) -> void:
	stage = clampi(next_stage,Step.WELCOME,Step.COMPLETE)
	stage_elapsed = 0.0
	_selected_unit_id=-1
	_selected_unit_call=-1
	match stage:
		Step.SELECT_MEDICAL:
			_medical_id = _create_call("medical","Beacon Clinic","A neighbor needs first aid","medic",16.0)
		Step.SCOUT_FIRE:
			_fire_id = _create_call("fire","Moonrise Bakery","Unconfirmed trouble at the bakery","fire",65.0)
			var call: Dictionary = sim.get_incident(_fire_id)
			call.hazard=0.48; call.hazard_stage=1; call.highest_hazard_stage=1
			_set_margin(_fire_id,-9.0)
			call.discovered=false
			call.bonus="Confirmed: the bakery needs one fire crew."
			_scout_before=float(call.deadline)
		Step.SUPPLY_FIRE:
			_supply_before=float(sim.get_incident(_fire_id).deadline)
			_supply_margin_before=float(sim.incident_estimate(_fire_id).get("margin",0.0))
		Step.DISPATCH_ENGINEER:
			_engineer_id=_create_call("power","Harbor Workshop","Workshop power failure","engineer",18.0)
		Step.RALLY:
			sim.special_cooldown=0.0; sim.special_duration=0.0; _rally_used=false
		Step.COMPARE_CALLS:
			if _challenge_ids.is_empty(): _prepare_challenge()

func _evaluate_action_stage() -> void:
	match stage:
		Step.SELECT_MEDICAL:
			if _selected_id==_medical_id and _is_open(_medical_id): _enter_stage(Step.DISPATCH_MEDIC)
		Step.DISPATCH_MEDIC:
			if _has_crew(_medical_id,"medic"): _enter_stage(Step.WATCH_MEDIC)
		Step.SCOUT_FIRE:
			if bool(sim.get_incident(_fire_id).get("scouted",false)): _enter_stage(Step.READ_MARGIN)
		Step.DISPATCH_FIRE:
			if _has_crew(_fire_id,"fire"): _enter_stage(Step.SUPPLY_FIRE)
		Step.SUPPLY_FIRE:
			if int(sim.get_incident(_fire_id).get("supply_count",0))>0: _enter_stage(Step.DISPATCH_ENGINEER)
		Step.DISPATCH_ENGINEER:
			if _has_crew(_engineer_id,"engineer"): _enter_stage(Step.RALLY)
		Step.RALLY:
			if _rally_used: _enter_stage(Step.WATCH_TEAM)

func _prepare_challenge() -> void:
	for unit: Dictionary in sim.units:
		unit.pos=unit.home; unit.state="idle"; unit.target=-1; unit.path=[]; unit.path_index=0
		unit.remaining=0.0; unit.fatigue=0.0; unit.work_elapsed=0.0; unit.work_phase="idle"; unit.arrival_at=-1.0
		unit.divert_after=0.0; unit.dispatch_guard_until=0.0; unit.assignment_suitable=true; unit.inspection_remaining=0.0
	sim.special_duration=0.0; sim.special_cooldown=0.0
	if sim.get("scout_cooldown")!=null: sim.set("scout_cooldown",0.0)
	sim.supplies=1; sim.max_supplies=1; sim.supply_regen=0.0
	var near_id: int=_create_call("power","Harbor Workshop","Workshop fuse repair","engineer",6.0)
	var far_id: int=_create_call("power","Willow Cottage","Cottage generator repair","engineer",26.0)
	_challenge_ids=[near_id,far_id]
	_set_margin(near_id,12.0)
	_set_margin(far_id,4.0)
	_challenge_started=false; _challenge_won=false; _challenge_first=-1; challenge_attempts=1
	_challenge_snapshot=sim.snapshot().duplicate(true)

func _prepare_cast() -> void:
	var practice_units: Array[Dictionary]=[]
	var seen: Array[String]=[]
	for unit: Dictionary in sim.units:
		var kind: String=str(unit.kind)
		if kind in seen or not CAST.has(kind): continue
		seen.append(kind)
		unit.crew_name=CAST[kind]; unit.name=CAST[kind]
		practice_units.append(unit)
	sim.units=practice_units

func _create_call(kind: String, location_name: String, title: String, crew: String, work_time: float) -> int:
	sim._spawn_incident()
	var call: Dictionary=sim.incidents.back()
	for location: Dictionary in Campaign.locations():
		if str(location.name)==location_name:
			call.pos=location.pos; call.location_index=Campaign.locations().find(location)
			break
	call.kind=kind; call.name=location_name; call.title=title; call.severity=1
	call.needs={"fire":0,"medic":0,"engineer":0,"police":0}; call.needs[crew]=1
	call.deadline=120.0; call.max_deadline=120.0; call.work_duration=work_time; call.people=3
	call.discovered=true; call.hazard=0.16; call.hazard_stage=0; call.highest_hazard_stage=0
	call.tutorial=true; call.bonus="The scene is ready for the matching crew."
	if not sim.events.is_empty() and str(sim.events.back().get("type",""))=="incident": sim.events.pop_back()
	sim._emit("incident",title+" at "+location_name,{"incident_id":call.id,"kind":kind,"pos":call.pos,"severity":1,"tutorial":true})
	return int(call.id)

func _set_margin(id: int, wanted: float) -> void:
	var call: Dictionary=sim.get_incident(id)
	var option: Dictionary=_best_option(id)
	if option.is_empty(): return
	call.deadline=maxf(2.0,float(call.deadline)+wanted-float(option.get("margin",0.0)))
	call.max_deadline=maxf(float(call.max_deadline),float(call.deadline))

func _best_option(id: int) -> Dictionary:
	if not sim.has_method("dispatch_options"): return {}
	var options: Array=sim.call("dispatch_options",id)
	var best: Dictionary={}
	for option: Dictionary in options:
		if not bool(option.get("suitable",false)) or not bool(option.get("known",false)): continue
		if best.is_empty() or float(option.get("finish_eta",999.0))<float(best.get("finish_eta",999.0)): best=option
	return best.duplicate(true)

func _challenge_metrics() -> Dictionary:
	var calls: Array[Dictionary]=[]
	for id: int in _challenge_ids:
		var call: Dictionary=sim.get_incident(id)
		calls.append({"id":id,"name":call.get("name",""),"deadline":call.get("deadline",0.0),"option":_best_option(id)})
	return {"calls":calls,"started":_challenge_started,"first_dispatch":_challenge_first,"attempt":challenge_attempts,"won":_challenge_won}

func _watch_is_running() -> bool:
	if not active or sim==null: return false
	if stage==Step.WATCH_MEDIC: return _is_open(_medical_id)
	if stage==Step.SUPPLY_FIRE: return _is_open(_fire_id) and not _crew_on_scene(_fire_id)
	if stage==Step.WATCH_TEAM: return _is_open(_fire_id) or _is_open(_engineer_id)
	if stage==Step.CHALLENGE: return _challenge_started and not _challenge_has_failed() and not _challenge_is_resolved()
	return false

func _crew_on_scene(id: int) -> bool:
	for unit: Dictionary in sim.units:
		if int(unit.target)==id and unit.state=="working": return true
	return false

func _challenge_is_resolved() -> bool:
	return _challenge_ids.size()==2 and _challenge_resolved_count()==2

func _challenge_resolved_count() -> int:
	var count: int=0
	for id: int in _challenge_ids:
		if _is_resolved(id): count+=1
	return count

func _challenge_has_failed() -> bool:
	for id: int in _challenge_ids:
		if str(sim.get_incident(id).get("status",""))=="failed": return true
	return false

func _has_crew(id: int, kind: String) -> bool:
	var call: Dictionary=sim.get_incident(id)
	return not call.is_empty() and sim.assigned_kind_count(call,kind)>=1

func _is_open(id: int) -> bool:
	var call: Dictionary=sim.get_incident(id)
	return not call.is_empty() and str(call.status) in ["active","working"]

func _is_resolved(id: int) -> bool:
	return str(sim.get_incident(id).get("status",""))=="resolved"

func _normalize_action(action: String, payload: Dictionary) -> String:
	if action=="dispatch": return "dispatch:"+str(payload.get("kind",""))
	if action.begins_with("plan:") or action.begins_with("filter:"): return "filter"
	if action=="select_incident" or action.begins_with("select:"): return "select"
	return action

func _stage_crew_kind() -> String:
	if stage==Step.DISPATCH_MEDIC: return "medic"
	if stage in [Step.READ_MARGIN,Step.DISPATCH_FIRE]: return "fire"
	if stage in [Step.DISPATCH_ENGINEER,Step.COMPARE_CALLS]: return "engineer"
	return ""

func _unit(id: int) -> Dictionary:
	for unit: Dictionary in sim.units:
		if int(unit.id)==id: return unit
	return {}

func _action_incident(action: String, payload: Dictionary) -> int:
	if action.begins_with("select:"): return action.trim_prefix("select:").to_int()
	return int(payload.get("incident_id",payload.get("id",-1)))

func _seconds(value: float) -> String:
	return "%+ds"%roundi(value)
