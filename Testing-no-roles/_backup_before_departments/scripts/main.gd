extends Node2D

const INK := Color("102832")
const PANEL := Color("193944")
const PANEL_LIGHT := Color("214956")
const CREAM := Color("f4e9d2")
const MUTED := Color("90afb2")
const TEAL := Color("70d2ba")
const CORAL := Color("f28b71")
const GOLD := Color("efc66e")
const BLUE := Color("83c4e6")
const SAVE_PATH := "user://beacon_bay_save.json"
const KIND_COLOR := {"fire": CORAL, "medic": TEAL, "engineer": GOLD, "medical": TEAL, "flood": BLUE, "power": GOLD}
const KIND_NAME := {"fire": "FIRE CREW", "medic": "MEDIC CREW", "engineer": "ENGINEERS"}

var sim: RescueSimulation
var town: TownView
var map_clip: Control
var audio: AudioDirector
var research: ResearchLogger
var network: NetworkSession
var font: Font
var hero: Texture2D
var screen := "title"
var previous_screen := "game"
var selected := -1
var selected_unit := -1
var role_filter := ""
var focused_unit := -1
var focused_unit_left := 0.0
var tactical_map: Node2D
var action_feedback := ""
var action_feedback_left := 0.0
var buttons: Array[Dictionary] = []
var elapsed_ui := 0.0
var refresh := 0.0
var net_timer := 0.0
var save_timer := 0.0
var unlocked := 0
var best_scores: Dictionary = {}
var total_rescued := 0
var toast_text := ""
var toast_left := 0.0
var ticker := "All stations ready. Let's look after each other."
var music_enabled := true
var sfx_enabled := true
var reduced_motion := false
var research_enabled := false
var comfortable := false
var show_help := false
var result_saved := false
var hovered_button := ""
var ip_input: LineEdit
var rating := 5
var stress_rating := 3
var orders: Dictionary = {}
var particles: Array[Dictionary] = []
var test_mode := false
var result_rating_sent := false
var event_actor := 1
var has_resume := false
var guest_progress: Dictionary = {}
var field_focus: Node2D
var map_overlay: Node2D
var focus_open := false
var focus_hold_id := -1
var focus_hold_left := 0.0
var urgency_cooldown := 0.0
var pressure_display := 0.0
var tutorial_active := false
var tutorial_completed := false
var tutorial_seen := false
var tutorial: TutorialDirector
var tutorial_overlay: TutorialOverlay
var _tutorial_campaign_sim: RescueSimulation
var _tutorial_saved_ui: Dictionary = {}
var _tutorial_auto_start := false
var _tutorial_last_stage := -1
const FOCUS_RECT := Rect2(40, 548, 464, 210)
const SURGE_RECT := Rect2(598, 158, 478, 51)

class MapOverlay extends Node2D:
	var game: Node2D
	func _draw() -> void:
		game._draw_map_overlay(self)

func _ready() -> void:
	get_tree().auto_accept_quit = false
	font = ThemeDB.fallback_font
	hero = load("res://assets/art/title_coast.png")
	sim = RescueSimulation.new()
	town = TownView.new()
	map_clip = Control.new()
	map_clip.position = Vector2(24,146)
	map_clip.size = Vector2(1064,632)
	map_clip.clip_contents = true
	map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_clip)
	town.position = Vector2.ZERO
	town.scale = Vector2(2, 2)
	town.sim = sim
	map_clip.add_child(town)
	town.incident_clicked.connect(_select_incident)
	tactical_map = preload("res://scripts/tactical_map_overlay.gd").new()
	tactical_map.sim = sim
	tactical_map.z_index = 2
	add_child(tactical_map)
	tactical_map.incident_selected.connect(_select_incident)
	tactical_map.unit_selected.connect(_select_unit)
	tactical_map.dispatch_requested.connect(_dispatch_selected)
	field_focus = preload("res://scripts/incident_focus.gd").new()
	field_focus.position = FOCUS_RECT.position
	field_focus.sim = sim
	field_focus.z_index = 3
	add_child(field_focus)
	map_overlay = MapOverlay.new()
	map_overlay.game = self
	map_overlay.z_index = 4
	add_child(map_overlay)
	tutorial_overlay = TutorialOverlay.new()
	add_child(tutorial_overlay)
	tutorial_overlay.advance_requested.connect(_tutorial_next)
	tutorial_overlay.skip_requested.connect(func(): _end_tutorial(false))
	audio = AudioDirector.new()
	add_child(audio)
	research = ResearchLogger.new()
	add_child(research)
	network = NetworkSession.new()
	add_child(network)
	network.command_received.connect(_execute_command)
	if network.has_signal("event_received"):
		network.connect("event_received",Callable(self,"_on_remote_event"))
	network.snapshot_received.connect(_receive_snapshot)
	network.message_received.connect(func(message: String): _toast(message))
	network.disconnected.connect(_network_ended)
	research.log_error.connect(func(message: String): research_enabled=false; _toast(message))
	ip_input = LineEdit.new()
	ip_input.position = Vector2(452, 379)
	ip_input.size = Vector2(536, 52)
	ip_input.placeholder_text = "Host's local IP address, e.g. 192.168.1.10"
	ip_input.text = "127.0.0.1"
	ip_input.add_theme_font_size_override("font_size", 20)
	add_child(ip_input)
	_load_save()
	audio.set_music_enabled(music_enabled)
	audio.set_sfx_enabled(sfx_enabled)
	audio.start_music()
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo":
			test_mode = true
			_begin_shift(0)
		if arg == "--tutorial-demo":
			test_mode = true
			_begin_tutorial(false)
		if arg.begins_with("--capture="):
			_capture_later(arg.trim_prefix("--capture="))
	_update_visibility()

func _process(delta: float) -> void:
	elapsed_ui += delta
	toast_left = maxf(0, toast_left - delta)
	action_feedback_left = maxf(0, action_feedback_left - delta)
	focused_unit_left = maxf(0, focused_unit_left - delta)
	if focused_unit_left<=0: focused_unit=-1
	focus_hold_left = maxf(0, focus_hold_left - delta)
	urgency_cooldown = maxf(0, urgency_cooldown - delta)
	if screen == "game" and (not network.active or network.hosting):
		if tutorial_active:
			tutorial.tick(delta)
			_sync_tutorial()
		else:
			sim.tick(delta * (0.8 if comfortable else 1.0))
		_process_events()
		if sim.finished and not tutorial_active:
			_finish_shift()
	if network.active and network.hosting:
		net_timer += delta
		if net_timer > 0.12:
			net_timer = 0
			network.broadcast({"simulation": sim.snapshot(), "screen": "pause" if screen=="settings" else screen, "orders": orders})
	if screen == "game":
		pressure_display = lerpf(pressure_display, _pressure(), 1.0-exp(-delta*3.0))
		audio.set_intensity(pressure_display)
		refresh += delta
		if refresh >= 1.0 and not tutorial_active:
			refresh = 0.0
			var active_calls := _active_incidents()
			var urgent_count := 0
			for call in active_calls:
				if call.deadline < 20: urgent_count += 1
			research.update_context({"shift":sim.shift_index,"role":network.role,"active_incidents":active_calls.size(),"urgent_incidents":urgent_count,"reputation":sim.reputation})
		if not tutorial_active: save_timer += delta
		if save_timer > 15 and not network.active and not tutorial_active:
			save_timer = 0
			_save_progress(true)
		if selected >= 0 and not tutorial_active:
			var incident := _incident(selected)
			if incident.is_empty() or incident.get("status", "") in ["resolved", "failed"]:
				selected = -1
				selected_unit = -1
				role_filter = ""
	else:
		audio.set_intensity(0.0)
	for p in particles:
		p.life -= delta
		p.pos += p.velocity * delta
	particles = particles.filter(func(p): return p.life > 0)
	town.selected_id = selected
	town.tactical_mode = true
	if selected_unit >= 0:
		var chosen: Dictionary = sim.get_unit(selected_unit)
		if chosen.is_empty() or chosen.state not in ["idle","return"]:
			selected_unit = -1
			role_filter = ""
	tactical_map.sim = sim
	tactical_map.selected_id = selected
	tactical_map.selected_unit_id = selected_unit
	tactical_map.role_filter = role_filter
	tactical_map.focused_unit_id = focused_unit
	tactical_map.dispatch_enabled = network.can_do("dispatch") and not (network.active and network.roster.size()>1 and network.role==1 and not orders.has(selected))
	if tutorial_active:
		var planned_crew: Dictionary=sim.get_unit(selected_unit)
		tactical_map.dispatch_enabled = not planned_crew.is_empty() and tutorial.can_action("dispatch",{"incident_id":selected,"kind":planned_crew.get("kind",""),"unit_id":selected_unit})
	tactical_map.tutorial_active = tutorial_active
	tactical_map.reduced_motion = reduced_motion
	var blocked: Array[Rect2] = []
	if field_focus.visible: blocked.append(Rect2(field_focus.position, FOCUS_RECT.size))
	if tutorial_overlay.visible: blocked.append(Rect2(tutorial_overlay.position,tutorial_overlay.panel_size))
	tactical_map.occlusions = blocked
	town.reduced_motion = reduced_motion
	town.interpolate_units = network.active and not network.hosting
	field_focus.selected_id = focus_hold_id if focus_hold_left>0 else selected
	field_focus.reduced_motion = reduced_motion
	tutorial_overlay.reduced_motion = reduced_motion
	_update_visibility()
	map_overlay.queue_redraw()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if tutorial_active: _end_tutorial(false,false)
		if sim != null:
			_save_progress(screen in ["game","pause","help"] or (screen=="settings" and previous_screen=="pause"))
		if research != null: research.set_enabled(false)
		get_tree().quit()

func _update_visibility() -> void:
	map_clip.visible = screen == "game"
	town.process_mode = Node.PROCESS_MODE_ALWAYS if screen == "game" else Node.PROCESS_MODE_DISABLED
	field_focus.visible = screen=="game" and focus_open and (selected>=0 or focus_hold_left>0)
	if tutorial_active:
		field_focus.visible = screen=="game" and bool(tutorial.current().get("show_focus",false))
	field_focus.process_mode = Node.PROCESS_MODE_ALWAYS if field_focus.visible else Node.PROCESS_MODE_DISABLED
	map_overlay.visible = screen=="game"
	if tactical_map.visible and screen!="game": tactical_map.clear_hover()
	tactical_map.visible = screen=="game"
	tutorial_overlay.visible = tutorial_active and screen=="game"
	ip_input.visible = screen == "lobby" and not network.active

func _draw() -> void:
	buttons.clear()
	draw_rect(Rect2(0, 0, 1440, 900), INK)
	match screen:
		"title": _draw_title()
		"campaign": _draw_campaign()
		"lobby": _draw_lobby()
		"settings": _draw_settings()
		"upgrades": _draw_upgrades()
		"game", "pause", "results", "help":
			_draw_game()
			if screen != "game": buttons.clear()
			if screen == "pause": _draw_pause()
			if screen == "results": _draw_results()
			if screen == "help": _draw_help()
	if toast_left > 0 and screen != "title":
		var width: float = minf(1040, font.get_string_size(toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 56)
		_panel(Rect2((1440-width)/2, 89, width, 43), PANEL_LIGHT, TEAL)
		_text(toast_text, Vector2((1440-width)/2 + 28, 117), 17, CREAM)
	for p in particles:
		draw_rect(Rect2(p.pos, Vector2(5,5)), Color(p.color, clampf(p.life, 0, 1)))

func _draw_title() -> void:
	if hero:
		draw_texture_rect(hero, Rect2(0, -30, 1440, 960), false)
	
	for i in range(72):
		var opacity := 0.84 * pow(1.0 - float(i)/72.0, 1.1)
		draw_rect(Rect2(i * 15, 0, 15, 900), Color(0.035,0.13,0.17,opacity))
	_text("A LITTLE TOWN. A BIG RESPONSIBILITY.", Vector2(74, 178), 16, GOLD)
	_text("BEACON", Vector2(65, 277), 88, CREAM)
	_text("BAY", Vector2(65, 361), 88, CREAM)
	draw_rect(Rect2(74, 395, 72, 4), CORAL)
	_text("Keep the light on.", Vector2(74, 441), 28, CREAM)
	_button("play", "CONTINUE" if unlocked > 0 or has_resume else "PLAY SOLO", Rect2(74, 497, 280, 64), TEAL, INK)
	_button("co_op", "PLAY WITH FRIENDS", Rect2(74, 575, 280, 54), Color(0.08,0.20,0.25,0.94), CREAM)
	_button("tutorial", "MEET THE CREW · TUTORIAL", Rect2(74, 643, 280, 48), Color(0.08,0.20,0.25,0.94), GOLD, 14)
	_button("settings", "SETTINGS", Rect2(74, 705, 133, 44), Color(0.08,0.20,0.25,0.86), CREAM, 15)
	_button("quit", "QUIT", Rect2(221, 705, 133, 44), Color(0.08,0.20,0.25,0.86), CREAM, 15)
	_text("SOLO / 2–4 PLAYER LAN CO-OP", Vector2(74, 835), 13, CREAM)
	_text("33-minute campaign  ·  Meet your crew", Vector2(1055, 864), 13, CREAM)
	
	if not reduced_motion:
		for i in range(22):
			var px := fmod(i * 97.0 + elapsed_ui * 5.0, 1400.0)
			var py := 690 + sin(i * 17.0 + elapsed_ui * 0.2) * 150
			draw_rect(Rect2(px, py, 3, 2), Color(1,0.91,0.64,0.2 + sin(elapsed_ui+i)*0.12))

func _draw_game() -> void:
	_text("BEACON BAY", Vector2(27, 45), 26, CREAM)
	_text("EMERGENCY SERVICES", Vector2(29, 67), 11, MUTED)
	var shift: Dictionary = BeaconCampaign.shift_data(sim.shift_index)
	_text("MEET THE CREW" if tutorial_active else shift.get("title", "First light"), Vector2(279, 45), 24, CREAM)
	_text("GUIDED PRACTICE · TAKE YOUR TIME" if tutorial_active else "SHIFT %02d / 06   ·   %s" % [sim.shift_index+1, sim.weather.to_upper()], Vector2(281, 68), 12, MUTED)
	_text("COMMUNITY / MIN %d%%" % int(sim.minimum_confidence), Vector2(684,31),10,MUTED)
	_bar(Rect2(684, 43, 156, 10), sim.reputation / 100.0, TEAL if sim.reputation > 40 else CORAL)
	_text("%d%%" % sim.reputation, Vector2(852, 55), 18, CREAM)
	_text("RESCUED", Vector2(950, 31), 11, MUTED)
	_text(str(sim.rescued), Vector2(950, 59), 26, CREAM)
	_text("TRAINING" if tutorial_active else "SHIFT ENDS", Vector2(1065, 31), 11, MUTED)
	_text("NO RUSH" if tutorial_active else _time(sim.duration - sim.elapsed), Vector2(1065, 59), 26, GOLD)
	_button("help", "?", Rect2(1258, 24, 48, 44), PANEL_LIGHT, CREAM, 22)
	_button("pause", "II", Rect2(1318, 24, 96, 44), PANEL_LIGHT, CREAM, 20)
	draw_line(Vector2(24, 88), Vector2(1416, 88), Color("2b4a54"), 1)
	_text("OPERATIONS MAP", Vector2(25, 119), 13, MUTED)
	var obj := "Read the route. Match the crew. Protect the rescue." if tutorial_active else "Save %d neighbors · keep community above %d%%" % [sim.target,int(sim.minimum_confidence)]
	_text(obj, Vector2(215,119), 14, CREAM)
	_draw_pressure_meter()
	_text("INCOMING REPORTS",Vector2(1112,119),13,MUTED)
	var active := _active_incidents()
	_text("%02d" % active.size(), Vector2(1381, 119), 15, TEAL)
	
	_panel(Rect2(21, 143, 1070, 638), PANEL_LIGHT)
	_draw_incident_queue(active)
	_draw_dispatch_panel()
	_draw_crew_cards()
	
	if screen=="game" and not tutorial_active and (field_focus.visible or selected>=0):
		buttons.append({"id":"focus","rect":_focus_button_rect()})
	_text("MAP: click call, then crew   1 / 2 / 3 filter   ENTER send   Q scout   E supply   SPACE rally   F scene", Vector2(27,892),12,MUTED)
	_text("%d WORKSHOP CREDITS" % sim.credits,Vector2(1213,891),11,GOLD)

func _draw_incident_queue(active: Array) -> void:
	for i in range(mini(active.size(),6)):
		var call: Dictionary = active[i]
		var area := Rect2(1112,146+i*48,304,43)
		var known: bool = bool(call.get("discovered",true))
		var color: Color = KIND_COLOR.get(call.kind,CORAL) if known else GOLD
		_button("select:%d" % call.id,"",area,PANEL_LIGHT if int(call.id)==selected else PANEL)
		_text("#%02d" % call.id,area.position+Vector2(10,27),16,color)
		_text(_short(str(call.name),23),area.position+Vector2(55,18),14,CREAM)
		_text(_call_status(call) if known else "UNCERTAIN REPORT · SCOUT TO CONFIRM",area.position+Vector2(55,34),9,MUTED if known else GOLD)
	if active.is_empty():
		_panel(Rect2(1112,146,304,132),PANEL)
		_symbol("safe",Vector2(1264,184),TEAL,1.1)
		_text("The bay is quiet",Vector2(1180,222),19,CREAM)
		_text("Watch the map for the next call.",Vector2(1140,251),13,MUTED)

func _pressure() -> float:
	if sim.has_method("pressure_level"):
		return float(sim.call("pressure_level"))
	return clampf(float(_active_incidents().size())/6.0,0,1)

func _draw_pressure_meter() -> void:
	var level: String = "STEADY" if pressure_display<.34 else ("BUSY" if pressure_display<.65 else "CRITICAL")
	var color: Color = TEAL if pressure_display<.34 else (GOLD if pressure_display<.65 else CORAL)
	_text("TOWN PRESSURE",Vector2(805,109),10,MUTED)
	_text(level,Vector2(994,109),10,color)
	for i in range(20):
		draw_rect(Rect2(805+i*13,117,10,7),color if float(i)/20.0<pressure_display else PANEL_LIGHT)

func _draw_map_overlay(canvas: Node2D) -> void:
	if screen!="game": return
	if tutorial_active:
		_draw_tutorial_highlight(canvas)
		return
	if field_focus.visible:
		_overlay_button(canvas,"F HIDE",_focus_button_rect())
	elif selected>=0:
		_overlay_button(canvas,"F WATCH CREW",_focus_button_rect())

func _focus_button_rect() -> Rect2:
	return Rect2(field_focus.position+Vector2(FOCUS_RECT.size.x-65,7),Vector2(57,24)) if field_focus.visible else Rect2(40,724,185,34)

func _map_occluded(point: Vector2) -> bool:
	if tutorial_overlay.visible and tutorial_overlay.blocks_point(point): return true
	if field_focus.visible and Rect2(field_focus.position,FOCUS_RECT.size).has_point(point): return true
	return false

func _overlay_button(canvas: Node2D, caption: String, rect: Rect2) -> void:
	var hover: bool = rect.has_point(get_global_mouse_position())
	canvas.draw_style_box(_style(PANEL_LIGHT.lightened(.15) if hover else PANEL_LIGHT),rect)
	canvas.draw_string(font,rect.position+Vector2(8,rect.size.y*.5+4),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11,CREAM)

func _draw_dispatch_panel() -> void:
	_panel(Rect2(1112,449,304,329),PANEL)
	var call := _incident(selected)
	if call.is_empty() or call.get("status","") not in ["active","working"]:
		_text("CALL DESK",Vector2(1130,479),15,TEAL)
		_wrap("Choose a call. Its location will light up on the map.",Vector2(1130,518),263,21,CREAM,29)
		_text("Hover a station to see its crews.",Vector2(1130,616),13,MUTED)
		_text("1 / 2 / 3 highlight a crew type.",Vector2(1130,640),13,MUTED)
		_text("Choose your responder on the map.",Vector2(1130,664),13,CREAM)
		_button("special",_boost_text(),Rect2(1130,740,268,32),PANEL_LIGHT,GOLD,12)
		return
	var known: bool = bool(call.get("discovered",true))
	var color: Color = KIND_COLOR.get(call.kind,CORAL) if known else GOLD
	_text("REPORT #%02d  ·  %d PEOPLE" % [call.id,int(call.get("people",1))],Vector2(1130,475),12,color)
	_text(_short(str(call.name),23),Vector2(1130,504),21,CREAM)
	var need_text: String = ""
	for kind: String in ["fire","medic","engineer"]:
		if int(call.needs.get(kind,0))>0:
			need_text += "%s %d  " % [{"fire":"FIRE","medic":"MED","engineer":"ENG"}[kind],call.needs[kind]]
	_text("NEEDS " + need_text if known else "? UNCONFIRMED REPORT",Vector2(1130,528),11,MUTED if known else GOLD)
	draw_line(Vector2(1130,544),Vector2(1398,544),PANEL_LIGHT,1)
	var waiting: bool = network.active and network.roster.size()>1 and network.role==1 and not orders.has(call.id)
	var covered: bool = known
	for kind: String in ["fire","medic","engineer"]:
		if _assigned_count(call,kind)<int(call.needs.get(kind,0)): covered=false
	if waiting:
		_wrap("Waiting for your dispatcher's order.",Vector2(1130,572),263,15,GOLD,23)
	elif covered:
		_text("CREWS RESPONDING",Vector2(1130,573),12,TEAL)
		_text("Follow their progress on the map.",Vector2(1130,599),13,CREAM)
		_text("Use support if the rescue is at risk.",Vector2(1130,621),12,MUTED)
	elif selected_unit>=0:
		_text("RESPONSE PLANNED ON MAP",Vector2(1130,573),12,TEAL)
		_text("Check its route. Enter confirms it.",Vector2(1130,599),13,CREAM)
	else:
		_text("CHOOSE A CREW ON THE MAP",Vector2(1130,573),12,TEAL)
		_text("Hover a crew to compare its route.",Vector2(1130,599),13,CREAM)
		_text("Click that crew to prepare a response.",Vector2(1130,621),12,MUTED)
	if network.active and network.roster.size()>1 and network.role==0 and not network.can_do("dispatch"):
		_button("order","ISSUE DISPATCH ORDER",Rect2(1130,628,268,32),TEAL,INK,12)
	var scout_label: String = "Q SCOUT +9s"
	if bool(call.get("scouted",false)): scout_label="REPORT CHECKED"
	elif float(sim.scout_cooldown)>0: scout_label="Q READY IN %ds" % ceili(float(sim.scout_cooldown))
	_button("scout",scout_label,Rect2(1130,675,129,37),PANEL_LIGHT,TEAL,10)
	_button("supply","E +18s · %d LEFT" % sim.supplies,Rect2(1269,675,129,37),PANEL_LIGHT,GOLD,10)
	var benefit: String = action_feedback if action_feedback_left>0 else ("Scout reveals needs before you commit." if not known else "Supplies: +18s, lower danger, faster work.")
	_text(_short(benefit,46),Vector2(1130,730),10,TEAL if action_feedback_left>0 else MUTED)
	_button("special",_boost_text(),Rect2(1130,740,268,32),PANEL_LIGHT,GOLD,12)

func _selected_plan() -> Dictionary:
	if selected<0 or selected_unit<0: return {}
	for option: Dictionary in sim.dispatch_options(selected):
		if int(option.unit_id)==selected_unit: return option
	return {}

func _select_unit(id: int) -> void:
	if screen!="game": return
	var call: Dictionary = _incident(selected)
	if call.is_empty() or call.get("status","") not in ["active","working"]:
		_locate_unit(id)
		_toast("Choose a call first, then pick a responder here on the map.")
		return
	var unit: Dictionary = sim.get_unit(id)
	if unit.is_empty(): return
	if unit.state not in ["idle","return"]:
		_toast("%s is committed. Follow their progress on the map." % unit.get("crew_name",unit.name))
		return
	var wait_left: float = maxf(float(unit.get("divert_after",0.0)),float(unit.get("dispatch_guard_until",0.0))) - sim.elapsed
	if wait_left>0:
		_toast("%s can take another call in %ds." % [unit.get("crew_name",unit.name),ceili(wait_left)])
		return
	if tutorial_active and not tutorial.can_action("select_unit",{"unit_id":id,"incident_id":selected,"kind":unit.kind}): return
	selected_unit=id
	focused_unit=-1
	focused_unit_left=0
	if tutorial_active:
		tutorial.on_action("select_unit",{"unit_id":id,"incident_id":selected,"kind":unit.kind})
		_sync_tutorial()
	audio.play_cue("click")

func _plan_kind(kind: String) -> void:
	
	if screen!="game" or kind not in ["fire","medic","engineer"]: return
	if tutorial_active and not tutorial.can_action("plan:"+kind,{"incident_id":selected,"kind":kind}):
		_toast(str(tutorial.current().objective))
		return
	role_filter = kind
	selected_unit=-1
	focused_unit=-1
	focused_unit_left=0
	if tutorial_active:
		tutorial.on_action("plan:"+kind,{"incident_id":selected,"kind":kind})
		_sync_tutorial()
	tactical_map.role_filter=role_filter
	tactical_map.selected_unit_id=-1
	tactical_map.refresh()

func _locate_unit(id: int) -> void:
	if screen!="game": return
	var unit: Dictionary=sim.get_unit(id)
	if unit.is_empty(): return
	if tutorial_active and not tutorial.can_action("plan:"+str(unit.kind),{"incident_id":selected,"kind":unit.kind}): return
	role_filter=str(unit.kind)
	focused_unit=id
	focused_unit_left=5.0
	selected_unit=-1
	tactical_map.role_filter=role_filter
	tactical_map.focused_unit_id=id
	tactical_map.selected_unit_id=-1
	tactical_map.refresh()

func _dispatch_selected() -> void:
	var unit: Dictionary = sim.get_unit(selected_unit)
	if selected<0 or unit.is_empty():
		_toast("Click a call, then choose its responder on the map.")
		return
	_command("dispatch",{"incident_id":selected,"kind":unit.kind,"unit_id":selected_unit})

func _draw_crew_cards() -> void:
	for i in range(3):
		var kind: String = ["fire","medic","engineer"][i]
		var rect := Rect2(24+i*360, 796, 344, 78)
		_panel(rect, PANEL)
		_symbol(kind, rect.position + Vector2(19, 15), KIND_COLOR[kind], 0.46)
		_text(KIND_NAME[kind], rect.position + Vector2(35,19), 11, MUTED)
		var available := _available_units(kind)
		var total := 0
		for unit in sim.units:
			if unit.kind == kind: total += 1
		_text("%d/%d READY" % [available,total], rect.position + Vector2(247,19), 11, TEAL if available>0 else GOLD)
		var idx := 0
		for unit in sim.units:
			if unit.kind != kind: continue
			var x: float = 13+idx*(320.0/maxi(2,total))
			var card_area := Rect2(rect.position+Vector2(x-3,26),Vector2(320.0/maxi(2,total)-3,46))
			buttons.append({"id":"unit:%d" % unit.id,"rect":card_area})
			if int(unit.id)==selected_unit: draw_rect(card_area,GOLD,false,2)
			ResponderArt.draw_portrait(self,rect.position+Vector2(x,31),kind,int(unit.get("appearance",unit.id)),1.5)
			_text(_short(str(unit.get("crew_name",unit.name)),11),rect.position+Vector2(x+30,45),12,CREAM)
			var status: String = {"idle":"READY","travel":"EN ROUTE","working":"ON SCENE","return":"CAN DIVERT","rest":"RECOVERING"}.get(unit.state,str(unit.state).to_upper())
			if unit.state=="travel": status="ARRIVE %ds" % ceili(sim.unit_eta(unit))
			var ready_in: float = maxf(float(unit.get("divert_after",0.0)),float(unit.get("dispatch_guard_until",0.0))) - sim.elapsed
			if unit.state in ["idle","return"] and ready_in>0: status="READY IN %ds" % ceili(ready_in)
			_text(status,rect.position+Vector2(x+30,62),9,KIND_COLOR[kind] if unit.state in ["travel","working"] else MUTED)
			idx += 1
	_panel(Rect2(1112,796,304,78),PANEL)
	var heading: String = "CREW UPDATES"
	if sim.surge_warning_remaining>0: heading="NEW WAVE IN %ds" % ceili(sim.surge_warning_remaining)
	elif sim.rush_remaining>0: heading="BUSY WAVE · %ds" % ceili(sim.rush_remaining)
	elif sim.breather_remaining>0: heading="RECOVERY WINDOW · %ds" % ceili(sim.breather_remaining)
	_text(heading,Vector2(1130,819),11,TEAL)
	_wrap(_short(ticker,82),Vector2(1130,842),267,12,CREAM,17)

func _draw_campaign() -> void:
	_draw_page_header("Your town is counting on you.", "SIX SHIFTS. ONE BEACON BAY.")
	for i in range(6):
		var data: Dictionary = BeaconCampaign.shift_data(i)
		var rect := Rect2(80+(i%3)*430, 222+(i/3)*221, 402, 192)
		var is_open := i <= unlocked
		_panel(rect, PANEL if is_open else Color("122e39"))
		draw_rect(Rect2(rect.position, Vector2(402,4)), [TEAL,GOLD,BLUE,CORAL,Color("b5a5e9"),GOLD][i])
		_text("%02d" % (i+1), rect.position+Vector2(23,45), 27, GOLD if is_open else MUTED)
		_text(str(data.get("title","Shift")),rect.position+Vector2(23,83),24,CREAM if is_open else MUTED)
		_text(_short(str(data.get("subtitle","")),42),rect.position+Vector2(23,112),14,MUTED)
		_text("05:30   ·   %d neighbors" % int(data.get("target",12)),rect.position+Vector2(23,141),12,MUTED)
		_button("shift:%d"%i if is_open else "locked", "START SHIFT  >" if is_open else "COMPLETE PREVIOUS SHIFT", Rect2(rect.position+Vector2(20,153),Vector2(362,29)),PANEL_LIGHT if is_open else PANEL,TEAL if is_open else MUTED,12)
	_button("upgrades","EQUIPMENT WORKSHOP   ·   %d credits" % sim.credits,Rect2(80,705,610,60),PANEL_LIGHT,GOLD,18)
	if has_resume:
		_button("resume","RESUME SAVED SHIFT",Rect2(720,705,632,60),TEAL,INK,18)
	else:
		_text("Select an unlocked shift to go on duty.",Vector2(743,743),18,MUTED)
	_text("Progress is saved automatically. A complete campaign contains 33 minutes of active shifts.",Vector2(80,818),15,MUTED)
	_button("title","<  BACK",Rect2(80,91,125,38),PANEL,CREAM,14)

func _draw_upgrades() -> void:
	_draw_page_header("Better tools. Brighter outcomes.", "THE WORKSHOP    /    %d CREDITS" % sim.credits)
	var catalog: Array = BeaconCampaign.upgrades()
	for i in range(catalog.size()):
		var item: Dictionary = catalog[i]
		var rect := Rect2(80+(i%3)*430,217+(i/3)*159,402,146)
		_panel(rect,PANEL)
		var level := int(sim.upgrades.get(item.id,0))
		_text(str(item.get("name",item.id)),rect.position+Vector2(22,35),21,CREAM)
		_wrap(str(item.get("description","")),rect.position+Vector2(22,66),355,14,MUTED,20)
		var max_level := int(item.get("max_level",3))
		var cost := BeaconCampaign.upgrade_cost(str(item.id),level)
		_text("LEVEL %d / %d"%[level,max_level],rect.position+Vector2(22,125),12,TEAL)
		_button("buy:"+str(item.id),"%d CREDITS"%cost if level<max_level else "COMPLETE",Rect2(rect.position+Vector2(222,99),Vector2(158,36)),PANEL_LIGHT,GOLD,12)
	_button("campaign","<  YOUR SHIFTS",Rect2(80,91,190,38),PANEL,CREAM,14)

func _draw_lobby() -> void:
	_draw_page_header("Good neighbors. Great teammates.", "LOCAL NETWORK CO-OP    /    UP TO FOUR PLAYERS")
	_panel(Rect2(400,240,640,452),PANEL)
	if not network.active:
		_text("Meet at the station",Vector2(451,293),28,CREAM)
		_text("Use the same local network. The host starts the shift.",Vector2(452,331),16,MUTED)
		_button("host","HOST A ROOM",Rect2(452,456,536,54),TEAL,INK)
		_button("join","JOIN THIS ADDRESS",Rect2(452,524,536,54),PANEL_LIGHT,CREAM)
		_wrap("Roles are assigned on arrival: dispatch, resources, field coordination, and support. Use your own voice call or the in-game radio pings.",Vector2(452,620),526,14,MUTED,21)
	else:
		_text("%d / 4 CREW CONNECTED" % network.roster.size(),Vector2(452,291),21,TEAL)
		_text(network.status,Vector2(452,326),15,MUTED)
		var row := 0
		for peer_id in network.roster:
			var r: int = int(network.roster[peer_id])
			_text("%02d   %s" %[row+1,NetworkSession.ROLES[r]],Vector2(452,373+row*42),19,CREAM)
			row += 1
		if network.hosting:
			_button("host_start","START SHIFT TOGETHER",Rect2(452,558,536,54),TEAL,INK)
			_text("Host IP: " + _local_address(),Vector2(452,643),16,MUTED)
		else:
			_text("Waiting for the dispatcher to begin…",Vector2(452,600),19,GOLD)
	_button("leave_lobby","<  BACK",Rect2(80,91,125,38),PANEL,CREAM,14)
	_wrap("Dispatcher marks priorities. Resource manager sends crews. Field coordinator scouts and stabilizes. Support lead triggers team boosts. Empty roles are available to the host.",Vector2(400,741),640,16,MUTED,25)

func _draw_settings() -> void:
	_draw_page_header("Make yourself comfortable.", "SETTINGS & OPTIONAL RESEARCH")
	var rows := [
		["music", "Music", "Original coastal chiptune soundtrack", music_enabled],
		["sfx", "Sound effects", "Radio, dispatch, rescue and upgrade cues", sfx_enabled],
		["motion", "Reduced motion", "Calmer water, weather and celebration effects", reduced_motion],
		["comfort", "Comfort pace", "20% slower emergencies; more time to think", comfortable],
		["research", "Local research logging", "Opt in: clicks, pointer distance, response times and surveys", research_enabled]
	]
	for i in range(rows.size()):
		var row: Array = rows[i]
		var rect := Rect2(250,218+i*94,940,80)
		_panel(rect,PANEL)
		_text(row[1],rect.position+Vector2(25,31),21,CREAM)
		_text(row[2],rect.position+Vector2(25,58),14,MUTED)
		_button("toggle:"+str(row[0]),"ON" if row[3] else "OFF",Rect2(rect.position+Vector2(800,19),Vector2(112,43)),TEAL if row[3] else PANEL_LIGHT,INK if row[3] else MUTED,16)
	_wrap("Research is off by default. If enabled, anonymized interaction events stay on this computer in the game’s user-data folder. No audio is recorded by this game. Support cues are gameplay heuristics, not a validated measure of stress.",Vector2(250,740),925,15,MUTED,23)
	_button("settings_back","<  BACK",Rect2(80,91,125,38),PANEL,CREAM,14)
	_button("open_data","OPEN DATA FOLDER",Rect2(965,829,225,38),PANEL_LIGHT,TEAL,13)

func _draw_pause() -> void:
	_overlay()
	_panel(Rect2(490,225,460,510),INK,Color("355966"))
	_text("Take a breath.",Vector2(550,286),36,CREAM)
	_text("Your crews will be here.",Vector2(550,322),17,MUTED)
	_button("unpause","BACK ON DUTY",Rect2(550,359,340,54),TEAL,INK)
	_button("pause_settings","SETTINGS",Rect2(550,429,340,48),PANEL_LIGHT,CREAM)
	_button("help","HOW TO PLAY",Rect2(550,491,340,48),PANEL_LIGHT,CREAM)
	_button("tutorial_skip" if tutorial_active else "tutorial","LEAVE PRACTICE" if tutorial_active else "MEET THE CREW · TUTORIAL",Rect2(550,553,340,48),PANEL_LIGHT,GOLD,14)
	_button("save_exit","SAVE & RETURN TO TOWN",Rect2(550,615,340,48),PANEL_LIGHT,CREAM,14)
	_text("ESC  resume    ·    F11  fullscreen",Vector2(561,705),13,MUTED)

func _draw_help() -> void:
	_overlay()
	_panel(Rect2(320,142,800,627),INK,Color("355966"))
	_text("A good call changes everything.",Vector2(365,202),30,CREAM)
	var tips := [
		["01", "Choose a call", "Choose a numbered map marker. A crew needs time to travel AND finish its work. Compare the route and projected safety margin."],
		["02", "Send the right team", "1 / 2 / 3 highlights a crew type. Hover a station or vehicle, then click a specific map crew. Check its route and press ENTER to send."],
		["03", "Contain the pressure", "Q reveals an uncertain report and buys time; scouting then recharges. E spends a limited supply for +18 seconds and faster, safer work."],
		["04", "Watch your people", "Names appear when you hover or select. Crew cards locate people on the map. SPACE rallies the team; F opens a rescue close-up."]
	]
	for i in range(tips.size()):
		var y := 257+i*105
		_text(tips[i][0],Vector2(365,y),25,TEAL)
		_text(tips[i][1],Vector2(425,y),22,CREAM)
		_wrap(tips[i][2],Vector2(425,y+29),635,15,MUTED,23)
	_button("unpause","LET'S DO SOME GOOD",Rect2(425,691,590,48),TEAL,INK,16)

func _draw_results() -> void:
	_overlay()
	_panel(Rect2(337,160,766,590),INK,Color("355966"))
	_text("SHIFT COMPLETE" if sim.won else "A DIFFICULT SHIFT",Vector2(388,211),13,TEAL if sim.won else CORAL)
	_text(("A town worth saving." if sim.shift_index==5 else "The light stays on.") if sim.won else "Regroup. You can do this.",Vector2(386,267),38,CREAM)
	for i in range(3):
		_star(Vector2(947+i*35,205),12,GOLD if i<sim.stars else PANEL_LIGHT)
	var stats := [[str(sim.rescued),"NEIGHBORS RESCUED"],["+%d" % sim.shift_reward,"WORKSHOP CREDITS"],["%d%%"%sim.reputation,"COMMUNITY CONFIDENCE"]]
	for i in range(3):
		_text(stats[i][0],Vector2(390+i*226,344),37,GOLD)
		_text(stats[i][1],Vector2(390+i*226,371),10,MUTED)
	_text("+%d WORKSHOP CREDITS    ·    BEST CHAIN %d    ·    %d CALLS RESOLVED" % [sim.shift_reward,sim.best_combo,sim.resolved_count],Vector2(390,397),12,TEAL)
	if research_enabled:
		_text("Optional check-in: how demanding was that shift?",Vector2(390,423),16,CREAM)
		for i in range(10):
			_button("rating:%d"%(i+1),str(i+1),Rect2(390+i*64,445,54,36),TEAL if rating==i+1 else PANEL_LIGHT,INK if rating==i+1 else CREAM,14)
		_text("LOW WORKLOAD",Vector2(390,503),11,MUTED)
		_text("HIGH WORKLOAD",Vector2(907,503),11,MUTED)
	else:
		_wrap("Every rescue is a little more hope. Invest your credits in the workshop, then take on the next shift.",Vector2(390,429),635,20,MUTED,30)
	if network.active and not network.hosting:
		_text("Your dispatcher will begin the next watch.",Vector2(390,585),19,GOLD)
		_button("leave_lobby","LEAVE THE ROOM",Rect2(390,631,656,46),PANEL_LIGHT,CREAM,15)
	else:
		_button("results_continue","NEXT SHIFT  >" if sim.won and sim.shift_index<5 else ("BACK TO YOUR TOWN" if sim.won else "TRY THIS SHIFT AGAIN"),Rect2(390,558,656,56),TEAL,INK,17)
		_button("results_workshop","VISIT THE WORKSHOP",Rect2(390,631,656,46),PANEL_LIGHT,GOLD,15)
	_text("Progress saved locally",Vector2(628,716),13,MUTED)

func _draw_page_header(title: String, eyebrow: String) -> void:
	_text(eyebrow,Vector2(80,52),13,TEAL)
	_text(title,Vector2(80,182),39,CREAM)
	_text("BEACON BAY",Vector2(1172,52),22,CREAM)

func _panel(rect: Rect2, color: Color = PANEL, border: Color = Color.TRANSPARENT) -> void:
	draw_style_box(_style(color,border),rect)

func _style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color=color
	box.set_corner_radius_all(8)
	if border.a>0:
		box.border_color=border
		box.set_border_width_all(1)
	return box

func _button(id: String, text: String, rect: Rect2, bg: Color = PANEL_LIGHT, fg: Color = CREAM, font_size: int = 17) -> void:
	var hovered := rect.has_point(get_global_mouse_position())
	_panel(rect,bg.lightened(0.10) if hovered else bg,fg*Color(1,1,1,0.34) if hovered else Color.TRANSPARENT)
	if text != "":
		var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		_text(text,rect.position+Vector2((rect.size.x-width)/2,(rect.size.y+font_size*0.72)/2),font_size,fg)
	buttons.append({"id":id,"rect":rect})

func _text(text: String, pos: Vector2, size: int = 18, color: Color = CREAM) -> void:
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _wrap(text: String, pos: Vector2, width: float, size: int = 18, color: Color = CREAM, line_height: float = 27) -> void:
	var line := ""
	var y := pos.y
	for word in text.split(" "):
		if font.get_string_size(line+word,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x > width and line != "":
			_text(line,Vector2(pos.x,y),size,color)
			line=""
			y+=line_height
		line+=word+" "
	_text(line,Vector2(pos.x,y),size,color)

func _bar(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect,Color("0b242e"))
	draw_rect(Rect2(rect.position,Vector2(rect.size.x*clampf(ratio,0,1),rect.size.y)),color)

func _symbol(kind: String, center: Vector2, color: Color, s: float = 1.0) -> void:
	match kind:
		"medic","medical":
			draw_rect(Rect2(center+Vector2(-4,-12)*s,Vector2(8,24)*s),color)
			draw_rect(Rect2(center+Vector2(-12,-4)*s,Vector2(24,8)*s),color)
		"fire":
			var pts := PackedVector2Array([Vector2(-10,10),Vector2(-12,0),Vector2(-5,-8),Vector2(-3,-2),Vector2(3,-16),Vector2(6,-7),Vector2(12,2),Vector2(9,11)])
			for i in range(pts.size()): pts[i]=pts[i]*s+center
			draw_colored_polygon(pts,color)
			draw_rect(Rect2(center+Vector2(-3,2)*s,Vector2(6,9)*s),GOLD)
		"engineer","power":
			draw_line(center+Vector2(-9,11)*s,center+Vector2(8,-8)*s,color,6*s)
			draw_line(center+Vector2(1,-12)*s,center+Vector2(7,-5)*s,color,5*s)
			draw_line(center+Vector2(12,-1)*s,center+Vector2(7,-5)*s,color,5*s)
		"flood":
			for i in range(3):
				draw_line(center+Vector2(-12,-7+i*7)*s,center+Vector2(-4,-10+i*7)*s,color,3*s)
				draw_line(center+Vector2(-4,-10+i*7)*s,center+Vector2(5,-6+i*7)*s,color,3*s)
				draw_line(center+Vector2(5,-6+i*7)*s,center+Vector2(12,-9+i*7)*s,color,3*s)
		_:
			draw_line(center+Vector2(-10,0)*s,center+Vector2(-3,8)*s,color,4*s)
			draw_line(center+Vector2(-3,8)*s,center+Vector2(12,-9)*s,color,4*s)

func _overlay() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0.025,0.08,0.11,0.92))

func _star(center: Vector2, radius: float, color: Color) -> void:
	var points:=PackedVector2Array()
	for i in range(10):
		points.append(center+Vector2.from_angle(-PI/2.0+i*PI/5.0)*radius*(1.0 if i%2==0 else 0.45))
	draw_colored_polygon(points,color)

func _input(event: InputEvent) -> void:
	if tutorial_overlay.visible and tutorial_overlay.handle_input(event):
		if event is InputEventMouseMotion:
			town.hover_id=-1
			tactical_map.clear_hover()
		get_viewport().set_input_as_handled()
		return
	if screen=="game" and tactical_map.visible and tactical_map.handle_input(event):
		if not tutorial_active:
			if event is InputEventMouseMotion: research.log_pointer(event.position,event.relative)
			elif event is InputEventMouseButton and event.pressed: research.log_click(event.position)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if screen == "game" and not tutorial_active: research.log_pointer(event.position,event.relative)
		var over := false
		for b in buttons:
			if b.rect.has_point(event.position): over = true
		if screen=="game" and not _map_occluded(event.position) and town.hover_id>=0: over=true
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over else Input.CURSOR_ARROW)
		if screen=="game" and _map_occluded(event.position):
			town.hover_id=-1
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if screen == "game" and not tutorial_active: research.log_click(event.position)
		for i in range(buttons.size()-1,-1,-1):
			var b: Dictionary=buttons[i]
			if b.rect.has_point(event.position):
				_action(b.id)
				get_viewport().set_input_as_handled()
				return
		if screen=="game" and _map_occluded(event.position):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if ip_input.has_focus():
			if event.keycode == KEY_ENTER: _action("join")
			return
		match event.keycode:
			KEY_F11:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
			KEY_ESCAPE:
				if screen=="game": _action("pause")
				elif screen in ["pause","help"]: _action("unpause")
				elif screen=="settings": _action("settings_back")
				elif screen in ["campaign","upgrades","lobby"]: _action("title")
			KEY_ENTER:
				if screen=="title": _action("play")
				elif screen=="game": _action("dispatch_selected")
			KEY_1:
				if screen=="game": _action("plan:fire")
			KEY_2:
				if screen=="game": _action("plan:medic")
			KEY_3:
				if screen=="game": _action("plan:engineer")
			KEY_Q:
				if screen=="game": _action("scout")
			KEY_E:
				if screen=="game": _action("supply")
			KEY_R:
				if screen=="game": _action("ping")
			KEY_F:
				if screen=="game": _action("focus")
			KEY_SPACE:
				if screen=="game": _action("special")
			KEY_TAB:
				if screen=="game": _cycle_incident()
			KEY_M:
				music_enabled = not music_enabled
				audio.set_music_enabled(music_enabled)

func _action(id: String) -> void:
	audio.play_cue("click")
	if id=="tutorial_skip":
		_end_tutorial(false)
		return
	if id=="tutorial_next":
		_tutorial_next()
		return
	if tutorial_active and not (id.begins_with("select:") or id.begins_with("dispatch:") or id.begins_with("plan:") or id.begins_with("unit:") or id in ["dispatch_selected","scout","supply","special","focus","pause","unpause","help","pause_settings","settings_back","save_exit","title","quit"] or id in ["toggle:music","toggle:sfx","toggle:motion","toggle:comfort"]):
		_toast("Finish practice or use Skip to return to your town.")
		return
	if id.begins_with("select:"):
		_select_incident(id.trim_prefix("select:").to_int())
		return
	if id.begins_with("unit:"):
		_locate_unit(id.trim_prefix("unit:").to_int())
		return
	if id.begins_with("plan:"):
		_plan_kind(id.trim_prefix("plan:"))
		return
	if id=="dispatch_selected":
		_dispatch_selected()
		return
	if id.begins_with("dispatch:"):
		_plan_kind(id.trim_prefix("dispatch:"))
		return
	if id.begins_with("shift:"):
		_begin_shift(id.trim_prefix("shift:").to_int())
		return
	if id.begins_with("buy:"):
		if has_resume:
			_toast("Finish your suspended shift before changing its equipment.")
			return
		if sim.buy_upgrade(id.trim_prefix("buy:")):
			audio.play_cue("upgrade")
			_save_progress()
			_toast("Equipment upgraded. Your crews thank you.")
		else: _toast("More credits needed, or this upgrade is complete.")
		return
	if id.begins_with("toggle:"):
		_toggle(id.trim_prefix("toggle:"))
		return
	if id.begins_with("rating:"):
		rating=id.trim_prefix("rating:").to_int()
		return
	match id:
		"tutorial": _begin_tutorial(false)
		"focus": focus_open=not focus_open
		"play":
			if unlocked==0 and best_scores.is_empty() and not has_resume:
				if not tutorial_seen: _begin_tutorial(true)
				else: _begin_shift(0)
			else: screen="campaign"
		"title":
			if tutorial_active: _end_tutorial(false,false)
			screen="title"; _leave_network()
		"campaign": screen="campaign"
		"settings": previous_screen=screen; screen="settings"
		"settings_back": screen=previous_screen; _save_progress(screen=="pause")
		"pause_settings": previous_screen="pause"; screen="settings"
		"upgrades":
			if has_resume: _toast("Resume and finish your saved shift before visiting the workshop.")
			else: screen="upgrades"
		"quit":
			if tutorial_active: _end_tutorial(false,false)
			_save_progress(screen in ["game","pause"]); get_tree().quit()
		"co_op": screen="lobby"
		"host": network.host(); _toast(network.status)
		"join":
			guest_progress=sim.snapshot()
			network.join(ip_input.text)
			ip_input.release_focus()
			_toast(network.status)
		"host_start": _begin_shift(unlocked)
		"leave_lobby":
			if screen=="results": _submit_rating()
			_leave_network()
			screen="title"
		"pause":
			if network.active and not network.hosting: _toast("The host controls the shared pause.")
			else: screen="pause"
		"unpause":
			if network.active and not network.hosting: _toast("The dispatcher controls the shared pause.")
			else: screen="game"
		"help":
			if network.active and not network.hosting: _toast("1/2/3 plan · Enter send · Q scout · E +18s · SPACE rally")
			else: screen="help"
		"scout","supply","special","order": _command(id,{"incident_id":selected})
		"ping":
			var call:=_incident(selected)
			_command("ping",{"text":"Support requested at %s"%call.get("name","the station")})
		"save_exit":
			if tutorial_active: _end_tutorial(false,false)
			_save_progress(true)
			_leave_network()
			screen="title"
		"resume": _resume_shift()
		"results_continue":
			_submit_rating()
			if sim.won and sim.shift_index<5: _begin_shift(sim.shift_index+1)
			elif sim.won: screen="campaign"
			else: _begin_shift(sim.shift_index)
		"results_workshop": _submit_rating(); screen="upgrades"; _leave_network()
		"open_data": OS.shell_open(ProjectSettings.globalize_path("user://"))
		"locked": _toast("Finish the previous shift to unlock this part of the story.")

func _begin_tutorial(auto_start: bool = false) -> void:
	if tutorial_active: return
	if network.active:
		_toast("Meet the crew from the solo title screen, outside your shared room.")
		return
	_tutorial_campaign_sim=sim
	_tutorial_saved_ui={"screen":screen,"selected":selected,"selected_unit":selected_unit,"role_filter":role_filter,"focused_unit":focused_unit,"focused_unit_left":focused_unit_left,"action_feedback":action_feedback,"action_feedback_left":action_feedback_left,"focus_open":focus_open,"focus_hold_id":focus_hold_id,"focus_hold_left":focus_hold_left,"save_timer":save_timer,"refresh":refresh,"pressure":pressure_display,"ticker":ticker,"result_saved":result_saved,"result_rating_sent":result_rating_sent,"orders":orders.duplicate(true),"has_resume":has_resume,"toast_text":toast_text,"toast_left":toast_left}
	_tutorial_auto_start=auto_start
	tutorial_active=true
	sim=RescueSimulation.new()
	tutorial=TutorialDirector.new()
	tutorial.begin(sim)
	town.sim=sim
	field_focus.sim=sim
	field_focus.position=Vector2(40,168)
	town.set_theme(0)
	screen="game"
	selected=-1
	selected_unit=-1
	role_filter=""
	focused_unit=-1
	focused_unit_left=0
	action_feedback_left=0
	focus_open=true
	focus_hold_left=0
	toast_left=0
	pressure_display=0
	orders={}
	particles.clear()
	_tutorial_last_stage=-1
	_sync_tutorial()
	_update_visibility()

func _sync_tutorial() -> void:
	if not tutorial_active: return
	var card: Dictionary=tutorial.current()
	card["step"]=int(card.stage)+1
	card["total"]=int(card.stage_count)
	if bool(card.get("is_final",false)):
		card.next_label="START MY FIRST WATCH" if _tutorial_auto_start else "BACK TO MY TOWN"
	tutorial_overlay.data=card
	if tutorial.stage!=_tutorial_last_stage:
		_tutorial_last_stage=tutorial.stage
		if not bool(card.get("independent_choice",false)): selected=int(card.focus_id)
		if bool(card.get("clear_selection",false)): selected=-1
		selected_unit=-1
		role_filter=str(card.get("crew_kind",""))
		focused_unit=-1
		focused_unit_left=0
		focus_hold_left=0
		toast_left=0
		ticker="%s: %s"%[card.speaker,card.objective]
		if tutorial.stage>0: audio.play_cue("click")

func _tutorial_next() -> void:
	if not tutorial_active: return
	if tutorial.advance():
		if tutorial.finished: _end_tutorial(true)
		else: _sync_tutorial()

func _end_tutorial(completed: bool = false, launch_after: bool = true) -> void:
	if not tutorial_active: return
	tutorial.cancel()
	tutorial_active=false
	tutorial_completed=tutorial_completed or completed
	tutorial_seen=true
	sim=_tutorial_campaign_sim
	_tutorial_campaign_sim=null
	town.sim=sim
	field_focus.sim=sim
	field_focus.position=FOCUS_RECT.position
	town.set_theme(sim.shift_index)
	screen=str(_tutorial_saved_ui.screen)
	selected=int(_tutorial_saved_ui.selected)
	selected_unit=int(_tutorial_saved_ui.get("selected_unit",-1))
	role_filter=str(_tutorial_saved_ui.get("role_filter",""))
	focused_unit=int(_tutorial_saved_ui.get("focused_unit",-1))
	focused_unit_left=float(_tutorial_saved_ui.get("focused_unit_left",0.0))
	action_feedback=str(_tutorial_saved_ui.get("action_feedback",""))
	action_feedback_left=float(_tutorial_saved_ui.get("action_feedback_left",0))
	focus_open=bool(_tutorial_saved_ui.focus_open)
	focus_hold_id=int(_tutorial_saved_ui.focus_hold_id)
	focus_hold_left=float(_tutorial_saved_ui.focus_hold_left)
	save_timer=float(_tutorial_saved_ui.save_timer)
	refresh=float(_tutorial_saved_ui.refresh)
	pressure_display=float(_tutorial_saved_ui.pressure)
	ticker=str(_tutorial_saved_ui.ticker)
	result_saved=bool(_tutorial_saved_ui.result_saved)
	result_rating_sent=bool(_tutorial_saved_ui.result_rating_sent)
	orders=_tutorial_saved_ui.orders
	has_resume=bool(_tutorial_saved_ui.has_resume)
	toast_text=str(_tutorial_saved_ui.toast_text)
	toast_left=float(_tutorial_saved_ui.toast_left)
	particles.clear()
	_persist_tutorial_status()
	if _tutorial_auto_start and launch_after: _begin_shift(0)
	tutorial=null
	_tutorial_saved_ui.clear()
	_update_visibility()

func _persist_tutorial_status() -> void:
	if test_mode: return
	var data: Dictionary={"version":2}
	if FileAccess.file_exists(SAVE_PATH):
		var existing=JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if existing is Dictionary: data=existing
	
	data["tutorial_completed"]=tutorial_completed
	data["tutorial_seen"]=tutorial_seen
	var file:=FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(data))

func _draw_tutorial_highlight(canvas: Node2D) -> void:
	var key: String=str(tutorial.current().highlight)
	if key.begins_with("dispatch:") or key.begins_with("plan:"):
		key="dispatch_selected" if selected_unit>=0 else key.replace("dispatch:","plan:")
	var accent:=Color(GOLD,.8 if reduced_motion else .72+.25*sin(elapsed_ui*3))
	if key.begins_with("map_unit:"):
		var kind: String=key.trim_prefix("map_unit:")
		if selected_unit>=0 and bool(tactical_map.dispatch_enabled) and tactical_map.has_method("send_hit_rect"):
			var send_rect: Rect2=tactical_map.send_hit_rect()
			if send_rect.has_area(): canvas.draw_rect(send_rect.grow(4),accent,false,3)
		elif tactical_map.has_method("hit_regions"):
			var any_crew: bool=false
			for hit: Dictionary in tactical_map.hit_regions():
				if hit.get("type","")=="unit":
					var unit: Dictionary=sim.get_unit(int(hit.get("id",-1)))
					if not unit.is_empty() and unit.kind==kind:
						canvas.draw_rect((hit.rect as Rect2).grow(3),accent,false,2)
						any_crew=true
			if not any_crew and tactical_map.has_method("base_hit_rect"):
				canvas.draw_rect((tactical_map.base_hit_rect(kind) as Rect2).grow(4),accent,false,3)
	elif key.begins_with("call:"):
		var ident: int=key.trim_prefix("call:").to_int()
		var calls: Array=_active_incidents()
		for i in range(calls.size()):
			if int(calls[i].id)==ident:
				canvas.draw_rect(Rect2(1108,142+i*48,312,51),accent,false,3)
		var call:=_incident(ident)
		if not call.is_empty():
			var point: Vector2=map_clip.position+call.pos*TownView.MAP_SIZE*2
			canvas.draw_rect(Rect2(point-Vector2(23,67),Vector2(46,47)),accent,false,3)
	else:
		for button in buttons:
			if str(button.id)==key:
				canvas.draw_rect((button.rect as Rect2).grow(4),accent,false,3)

func _begin_shift(index: int) -> void:
	sim.start_shift(clampi(index,0,5))
	town.set_theme(index)
	selected=-1
	selected_unit=-1
	role_filter=""
	focused_unit=-1
	focused_unit_left=0
	action_feedback_left=0
	focus_open=false
	orders.clear()
	result_saved=false
	result_rating_sent=false
	save_timer=0
	focus_hold_left=0
	pressure_display=0
	urgency_cooldown=0
	screen="game"
	ticker=str(BeaconCampaign.shift_data(index).get("introduction","All crews ready."))
	research.set_enabled(research_enabled)
	research.update_context({"shift":index,"mode":"co_op" if network.active else "solo","role":network.role,"comfort_pace":comfortable})
	audio.play_cue("shift")
	_toast("Choose a call, then click a crew on the map. 1 / 2 / 3 highlight crew types." if index==0 else ticker)

func _finish_shift() -> void:
	if result_saved: return
	result_saved=true
	screen="results"
	if sim.won:
		unlocked=maxi(unlocked,mini(5,sim.shift_index+1))
		best_scores[str(sim.shift_index)]=maxi(int(best_scores.get(str(sim.shift_index),0)),sim.score)
		total_rescued+=sim.rescued
		audio.play_cue("shift")
	else: audio.play_cue("fail")
	_save_progress()

func _select_incident(id: int) -> void:
	focus_hold_left=0
	if screen != "game": return
	if tutorial_active and not tutorial.can_action("select",{"incident_id":id}): return
	if selected!=id:
		selected_unit=-1
		focused_unit=-1
		focused_unit_left=0
	selected=id
	if tutorial_active:
		tutorial.on_action("select",{"incident_id":id})
		_sync_tutorial()
	else: research.log_inspection(id)
	audio.play_cue("click")

func _cycle_incident() -> void:
	var calls:=_active_incidents()
	if calls.is_empty(): return
	var idx:=0
	for i in range(calls.size()):
		if int(calls[i].id)==selected: idx=(i+1)%calls.size(); break
	_select_incident(int(calls[idx].id))

func _command(action: String, payload: Dictionary) -> void:
	if screen != "game": return
	if not network.can_do(action):
		_toast("Your role: %s. Coordinate with the team." % NetworkSession.ROLES[network.role])
		return
	network.send_command(action,payload)

func _execute_command(action: String,payload: Dictionary,_peer_id: int) -> void:
	if screen!="game": return
	if tutorial_active and not tutorial.can_action(action,payload):
		_toast(str(tutorial.current().objective))
		return
	if not network.can_do(action,_peer_id): return
	event_actor = _peer_id
	var id:=int(payload.get("incident_id",-1))
	var success:=false
	match action:
		"dispatch":
			if network.active and network.roster.size()>1 and int(network.roster.get(_peer_id,0))==1 and not orders.has(id):
				var denied:={"type":"action_denied","text":"Wait for a dispatch order. Press R to request support.","actor_peer":_peer_id}
				_handle_game_event(denied)
				if network.has_method("broadcast_event"): network.call("broadcast_event",denied)
				event_actor=1
				return
			success=sim.dispatch(id,str(payload.get("kind","")),int(payload.get("unit_id",-1)))
		"scout": success=sim.scout(id)
		"supply": success=sim.supply(id)
		"special": success=sim.use_special()
		"order":
			var call:=_incident(id)
			if not call.is_empty():
				orders[id]=true
				network.announce("DISPATCH ORDER: %s — send matching crews."%call.name)
				success=true
		"ping": network.announce(str(payload.get("text","Help needed"))); success=true
	if success:
		if action=="dispatch":
			selected_unit=-1
			role_filter=""
			focused_unit=-1
			focused_unit_left=0
		if tutorial_active:
			tutorial.on_action(action,payload,true)
			_sync_tutorial()
		elif action in ["order","ping"]: research.log_event(action,payload)
	else:
		_toast("Crew unavailable or already assigned. Check the call's remaining needs." if action=="dispatch" else "Not available yet. Select an active call or let supplies recharge.")
	_process_events()
	event_actor = 1

func _process_events() -> void:
	for event in sim.drain_events():
		event["actor_peer"] = event_actor
		_handle_game_event(event)
		if network.has_method("broadcast_event"):
			network.call("broadcast_event",event)

func _on_remote_event(event: Dictionary) -> void:
	_handle_game_event(event)

func _handle_game_event(event: Dictionary) -> void:
	var type:=str(event.get("type",""))
	var message:=str(event.get("text",""))
	if message!="":
		var event_call: Dictionary = _incident(int(event.get("incident_id",-1)))
		if not event_call.is_empty() and not bool(event_call.get("discovered",true)) and type in ["incident","spawn","incident_spawned","escalated"]:
			message="Unconfirmed report at %s. Scout before committing." % event_call.name
		ticker=("#%02d · " % int(event_call.id) if not event_call.is_empty() else "")+message
	var local_actor := not network.active or int(event.get("actor_peer",1))==multiplayer.get_unique_id()
	if not tutorial_active and (local_actor or type not in ["dispatch","scout","supply","rally"]):
		research.log_event("incident_spawned" if type=="incident" else type,event)
	if type in ["resolved","rescue","incident_resolved"]:
		audio.play_cue("rescue")
		_celebrate(Vector2(760,120))
		if town.has_method("celebrate") and event.get("pos") is Vector2:
			town.call("celebrate",event.pos,int(event.get("points",0)),int(event.get("people",1)))
		if int(event.get("incident_id",-1))==selected:
			focus_hold_id=selected
			focus_hold_left=2.2
	elif type in ["incident","spawn","incident_spawned","new_incident"]:
		audio.play_cue("alarm")
	elif type in ["disruption","warning"]:
		_toast(message)
		audio.play_cue("alarm")
	elif type in ["surge_warning","surge_started"]:
		town.alert()
		audio.play_cue("surge")
	elif type in ["escalated","critical","urgent"]:
		if urgency_cooldown<=0:
			audio.play_cue("urgent")
			town.alert()
			urgency_cooldown=5.0
	elif type in ["arrival","arrived"]:
		audio.play_cue("arrival")
	elif type=="rapid_response":
		audio.play_cue("combo")
		_celebrate(Vector2(1040,120))
	elif type in ["failed","incident_failed"]: audio.play_cue("fail")
	elif type=="combo": audio.play_cue("combo")
	elif type=="dispatch": audio.play_cue("dispatch")
	elif type in ["scout","supply"]:
		audio.play_cue("upgrade")
		var effect: Dictionary = sim.last_action_effect
		action_feedback="%s: +%ds · safer, faster rescue" % ["Scouted" if type=="scout" else "Supply",roundi(float(effect.get("time_added",0)))]
		action_feedback_left=9.0
	elif type=="rally": audio.play_cue("upgrade")
	elif type=="dispatch_mismatch":
		_toast(message)
		audio.play_cue("fail")
	elif type=="action_denied" and local_actor: _toast(message)

func _receive_snapshot(data: Dictionary) -> void:
	if network.hosting: return
	var next_screen:=str(data.get("screen","game"))
	if screen=="results" and next_screen=="game":
		_submit_rating()
		result_rating_sent=false
	sim.apply_snapshot(data.get("simulation",{}))
	if next_screen in ["game","pause","results","help"]:
		screen=next_screen
	orders=data.get("orders",{})
	town.set_theme(sim.shift_index)

func _leave_network() -> void:
	network.close()
	_restore_guest_progress()

func _network_ended() -> void:
	if screen=="results": _submit_rating()
	_restore_guest_progress()
	screen="lobby"
	_toast(network.status)

func _restore_guest_progress() -> void:
	if not guest_progress.is_empty():
		sim.apply_snapshot(guest_progress)
		guest_progress.clear()

func _toggle(id: String) -> void:
	match id:
		"music": music_enabled=not music_enabled; audio.set_music_enabled(music_enabled)
		"sfx": sfx_enabled=not sfx_enabled; audio.set_sfx_enabled(sfx_enabled)
		"motion": reduced_motion=not reduced_motion
		"comfort": comfortable=not comfortable
		"research": research_enabled=not research_enabled; research.set_enabled(research_enabled)
	_save_progress(screen=="settings" and previous_screen=="pause")

func _submit_rating() -> void:
	if research_enabled and not result_rating_sent:
		research.end_shift({"workload_single_item_1_10":rating,"note":"Single item workload check; not NASA-TLX."})
		result_rating_sent=true

func _save_progress(include_session: bool = false) -> void:
	if tutorial_active or test_mode or (network.active and not network.hosting): return
	var data:={"version":2,"tutorial_completed":tutorial_completed,"tutorial_seen":tutorial_seen,"unlocked":unlocked,"best_scores":best_scores,"total_rescued":total_rescued,"credits":sim.credits,"upgrades":sim.upgrades,"settings":{"music":music_enabled,"sfx":sfx_enabled,"reduced_motion":reduced_motion,"comfort":comfortable,"research":research_enabled}}
	if include_session and sim.running and not sim.finished: data["session"]=sim.snapshot()
	elif FileAccess.file_exists(SAVE_PATH) and not sim.finished:
		var old=JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if old is Dictionary and old.has("session"): data["session"]=old.session
	var file:=FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		has_resume=data.has("session")

func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var data=JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary: return
	tutorial_completed=bool(data.get("tutorial_completed",false))
	tutorial_seen=bool(data.get("tutorial_seen",tutorial_completed))
	has_resume=data.has("session")
	unlocked=clampi(int(data.get("unlocked",0)),0,5)
	best_scores=data.get("best_scores",{})
	total_rescued=int(data.get("total_rescued",0))
	sim.credits=int(data.get("credits",0))
	sim.upgrades=data.get("upgrades",{})
	var settings: Dictionary=data.get("settings",{})
	music_enabled=settings.get("music",true)
	sfx_enabled=settings.get("sfx",true)
	reduced_motion=settings.get("reduced_motion",false)
	comfortable=settings.get("comfort",false)
	
	research_enabled=false

func _resume_shift() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var data=JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if data is Dictionary and data.has("session"):
			sim.apply_snapshot(data.session)
			screen="game"
			result_saved=false
			selected=-1
			focus_hold_left=0
			pressure_display=sim.pressure_level()
			result_rating_sent=false
			save_timer=0
			town.set_theme(sim.shift_index)
			return
	_toast("No suspended shift yet. Choose a shift to get started.")

func _incident(id: int) -> Dictionary:
	for item in sim.incidents:
		if int(item.id)==id: return item
	return {}

func _active_incidents() -> Array:
	var result: Array=[]
	for call in sim.incidents:
		if call.status in ["active","working"]: result.append(call)
	result.sort_custom(func(a,b): return a.deadline<b.deadline)
	return result

func _available_units(kind: String) -> int:
	return sim.available_count(kind)

func _assigned_count(call: Dictionary,kind: String) -> int:
	var n:=0
	for unit in sim.units:
		if int(unit.target)==int(call.id) and unit.kind==kind and unit.state in ["travel","working"]: n+=1
	return n

func _call_status(call: Dictionary) -> String:
	if float(call.progress)>0:
		return str({"contain":"CONTAINING THE DANGER","rescue":"BRINGING PEOPLE TO SAFETY","secure":"SECURING THE SCENE"}.get(call.get("phase",""),"RESCUE IN PROGRESS"))
	if str(call.get("phase",""))=="deploy": return "CREWS GETTING INTO POSITION"
	if float(call.get("hazard",0))>.7: return "CRITICAL · SEND HELP"
	var sent:=0
	var needed:=0
	for kind in ["fire","medic","engineer"]:
		sent+=_assigned_count(call,kind)
		needed+=int(call.needs.get(kind,0))
	if sent>0:
		return "CREWS EN ROUTE" if sent>=needed else "MORE CREWS NEEDED"
	if not call.discovered: return "UNCONFIRMED REPORT"
	return "ORDER RECEIVED" if orders.has(call.id) else "AWAITING RESPONSE"

func _boost_text() -> String:
	return "SPACE  TEAM BOOST" if sim.special_cooldown<=0 else "TEAM BOOST  ·  %ds"%ceili(sim.special_cooldown)

func _toast(message: String) -> void:
	toast_text=message
	toast_left=5.0

func _time(seconds: float) -> String:
	var secs:=maxi(0,ceili(seconds))
	return "%02d:%02d"%[secs/60,secs%60]

func _short(text: String,count: int) -> String:
	return text if text.length()<=count else text.left(count-1)+"…"

func _local_address() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."): return address
	return "127.0.0.1 (same computer)"

func _celebrate(center: Vector2) -> void:
	if reduced_motion: return
	for i in range(22):
		particles.append({"pos":center,"velocity":Vector2.from_angle(randf()*TAU)*randf_range(30,100),"life":randf_range(0.5,1.3),"color":[TEAL,GOLD,CORAL][i%3]})

func _capture_later(path: String) -> void:
	await get_tree().create_timer(4).timeout
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	image.save_png(path)
