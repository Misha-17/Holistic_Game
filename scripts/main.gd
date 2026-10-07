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
const VIOLET := Color("a3aef5")
const DEPARTMENTS: Array[String] = ["fire","medic","engineer","police"]
const SAVE_PATH := "user://beacon_bay_save.json"
# The game canvas is 1600x900 (16:9, scales exactly to 1920x1080). The layout below is
# 1440 wide, so the whole scene is shifted right to sit in the middle.
const UI_OFFSET_X := 80.0
const KIND_COLOR := {"fire": CORAL, "medic": TEAL, "engineer": GOLD, "police": VIOLET, "medical": TEAL, "flood": BLUE, "power": GOLD}
const KIND_NAME := {"fire": "FIRE CREW", "medic": "MEDIC CREW", "engineer": "ENGINEERS", "police": "POLICE"}
const KIND_SHORT := {"fire":"FIRE","medic":"MED","engineer":"ENG","police":"POL"}

var cv: CanvasItem
var hud: Node2D
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
var _route_cache: Array = []
var _route_cache_target := -1
var _route_cache_until := 0
var _route_cache_sim: RefCounted
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
var _tick_left := 0.0
# Networking smoothness (guests only): dispatches shown before the host confirms them.
var predicted_dispatches: Array[Dictionary] = []
var host_speed := 1.0
var show_perf := false
var _snapshot_gap_ms := 0.0
var _last_snapshot_ms := -1
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
# Game screen layout (main.gd local coordinates; the visible window spans x -80..1520).
const VIEW := Rect2(-80, 0, 1600, 900)
const MAP_SCALE := 3.0
const MAP_ORIGIN := Vector2(-78, 0)
const MAP_PIXELS := Vector2(1596, 948)
const CREW_BAR := Rect2(-72, 836, 1584, 58)
const FOCUS_RECT := Rect2(-64, 612, 464, 210)
const SURGE_RECT := Rect2(598, 158, 478, 51)

# Everything main.gd draws (HUD, menus, toasts) goes on this layer, above the map.
class HudLayer extends Node2D:
	var game: Node2D
	func _draw() -> void:
		game._draw_all(self)

class MapOverlay extends Node2D:
	var game: Node2D
	func _draw() -> void:
		game._draw_map_overlay(self)

func _ready() -> void:
	get_tree().auto_accept_quit = false
	position = Vector2(UI_OFFSET_X, 0)
	font = ThemeDB.fallback_font
	hero = load("res://assets/art/title_coast.png")
	sim = RescueSimulation.new()
	town = TownView.new()
	map_clip = Control.new()
	map_clip.position = MAP_ORIGIN
	map_clip.size = Vector2(MAP_PIXELS.x, VIEW.size.y)
	map_clip.clip_contents = true
	map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_clip)
	town.position = Vector2.ZERO
	town.scale = Vector2(MAP_SCALE, MAP_SCALE)
	town.sim = sim
	map_clip.add_child(town)
	town.incident_clicked.connect(_select_incident)
	tactical_map = preload("res://scripts/tactical_map_overlay.gd").new()
	tactical_map.sim = sim
	tactical_map.options_provider = _cached_dispatch_options
	tactical_map.z_index = 2
	tactical_map.map_rect = Rect2(MAP_ORIGIN, MAP_PIXELS)
	tactical_map.view_rect = Rect2(MAP_ORIGIN, Vector2(MAP_PIXELS.x, VIEW.size.y))
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
	hud = HudLayer.new()
	hud.game = self
	hud.z_index = 10
	add_child(hud)
	tutorial_overlay = TutorialOverlay.new()
	add_child(tutorial_overlay)
	tutorial_overlay.position = Vector2(-64, CREW_BAR.position.y - tutorial_overlay.panel_size.y - 10)
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
	ip_input.select_all_on_focus = true
	# Must sit above the HUD layer (z 10), which draws the lobby panel.
	ip_input.z_index = 20
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
	_apply_playtest_args()
	_update_visibility()

# Local multiplayer testing (Godot: Debug > Customize Run Instances > launch arguments per instance):
#   --host            open a room straight away
#   --join=127.0.0.1  join that address straight away
#   --tile=0..3       shrink the window to a quarter of the screen in that corner; tiles 1-3 also mute the music
func _apply_playtest_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if arg.begins_with("--tile="):
			var tile: int = clampi(arg.trim_prefix("--tile=").to_int(), 0, 3)
			var area: Rect2i = DisplayServer.screen_get_usable_rect()
			var size := Vector2i(area.size.x / 2, area.size.y / 2)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(area.position + Vector2i((tile % 2) * size.x, (tile / 2) * size.y))
			if tile > 0:
				music_enabled = false
				audio.set_music_enabled(false)
		elif arg == "--host":
			screen = "lobby"
			network.host()
			_toast(network.status)
		elif arg.begins_with("--join="):
			screen = "lobby"
			ip_input.text = arg.trim_prefix("--join=")
			# Give the host a moment to open its room first.
			get_tree().create_timer(1.5).timeout.connect(func():
				guest_progress = sim.snapshot()
				network.join(ip_input.text)
				_toast(network.status))

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
	elif screen == "game" and network.active and not network.hosting:
		# Guests run the same simulation between host updates so crews glide and
		# timers count down every frame; each snapshot from the host corrects it.
		sim.tick(delta * host_speed)
		sim.drain_events()
	if network.active and network.hosting:
		net_timer += delta
		if net_timer > 0.12:
			net_timer = 0
			network.broadcast({"simulation": sim.net_snapshot(), "screen": "pause" if screen=="settings" else screen, "orders": orders, "speed": (0.8 if comfortable else 1.0)})
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
		var about_to_fail := false
		for call in _active_incidents():
			if float(call.deadline) < 10.0 and _missing_crews(call) > 0:
				about_to_fail = true
				break
		audio.set_ticking(about_to_fail and sim.running)
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
		audio.set_ticking(false)
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
	var planned: Dictionary = sim.get_unit(selected_unit)
	tactical_map.dispatch_enabled = not planned.is_empty() and network.owns(str(planned.kind))
	tactical_map.owned_kinds = network.departments_for()
	var owners: Dictionary = {}
	if network.active:
		for kind in DEPARTMENTS:
			if not network.owns(kind):
				var owner: int = network.owner_of(kind)
				owners[kind] = "P%d" % (int(network.roster.get(owner, 0)) + 1) if owner > 0 else "?"
	tactical_map.owner_labels = owners
	if tutorial_active:
		var planned_crew: Dictionary=sim.get_unit(selected_unit)
		tactical_map.dispatch_enabled = not planned_crew.is_empty() and tutorial.can_action("dispatch",{"incident_id":selected,"kind":planned_crew.get("kind",""),"unit_id":selected_unit})
	tactical_map.tutorial_active = tutorial_active
	tactical_map.reduced_motion = reduced_motion
	var blocked: Array[Rect2] = []
	if screen=="game":
		blocked.append(_hud_rect())
		blocked.append(Rect2(VIEW.position.x, CREW_BAR.position.y - 4, VIEW.size.x, VIEW.end.y - CREW_BAR.position.y + 4))
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
	hud.queue_redraw()

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

func _draw_all(canvas: CanvasItem) -> void:
	cv = canvas
	buttons.clear()
	if screen != "game": cv.draw_rect(Rect2(-UI_OFFSET_X, 0, 1600, 900), INK)
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
		_panel(Rect2((1440-width)/2, 104, width, 40), Color(INK, 0.8), TEAL)
		_text(toast_text, Vector2((1440-width)/2 + 28, 130), 16, CREAM)
	for p in particles:
		cv.draw_rect(Rect2(p.pos, Vector2(5,5)), Color(p.color, clampf(p.life, 0, 1)))
	if show_perf:
		var line: String = "%d FPS" % Engine.get_frames_per_second()
		if network.active and not network.hosting:
			line += "   ping %d ms   host updates every %d ms" % [network.round_trip_ms(), roundi(_snapshot_gap_ms)]
		elif network.active:
			line += "   hosting"
		_panel(Rect2(-64, 70, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 24, 30), Color(INK, 0.8), TEAL)
		_text(line, Vector2(-52, 91), 15, CREAM)

func _draw_title() -> void:
	if hero:
		cv.draw_texture_rect(hero, Rect2(-UI_OFFSET_X, -60, 1600, 1067), false)
	
	for i in range(72):
		var opacity := 0.84 * pow(1.0 - float(i)/72.0, 1.1)
		cv.draw_rect(Rect2(i * 15, 0, 15, 900), Color(0.035,0.13,0.17,opacity))
	_text("A LITTLE TOWN. A BIG RESPONSIBILITY.", Vector2(74, 178), 16, GOLD)
	_text("BEACON", Vector2(65, 277), 88, CREAM)
	_text("BAY", Vector2(65, 361), 88, CREAM)
	cv.draw_rect(Rect2(74, 395, 72, 4), CORAL)
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
			cv.draw_rect(Rect2(px, py, 3, 2), Color(1,0.91,0.64,0.2 + sin(elapsed_ui+i)*0.12))

func _hud_rect() -> Rect2:
	var width: float = 860.0 if network.active else 720.0
	return Rect2(VIEW.position.x + (VIEW.size.x - width) / 2.0, 8, width, 52)

func _draw_game() -> void:
	if screen != "game":
		cv.draw_rect(VIEW, INK)
	var bar: Rect2 = _hud_rect()
	_panel(bar, Color(INK, 0.62), Color(CREAM, 0.12))
	var x: float = bar.position.x + 18
	if network.active:
		var mine: Array = network.departments_for()
		_text("YOU", Vector2(x, 24), 10, MUTED)
		var bx: float = x
		for kind in mine:
			_symbol(kind, Vector2(bx + 8, 42), KIND_COLOR[kind], 0.5)
			bx += 22
		if mine.size() >= DEPARTMENTS.size(): _text("ALL", Vector2(x, 48), 16, CREAM)
		x += 130
	_text("RESCUED", Vector2(x, 26), 10, MUTED)
	_text("%d / %d" % [sim.rescued, sim.target] if not tutorial_active else str(sim.rescued), Vector2(x, 50), 22, CREAM if sim.rescued < sim.target else TEAL)
	x += 120
	_text("COMMUNITY", Vector2(x, 26), 10, MUTED)
	_bar(Rect2(x, 36, 140, 10), sim.reputation / 100.0, TEAL if sim.reputation > sim.minimum_confidence + 10 else CORAL)
	cv.draw_rect(Rect2(x + 140 * sim.minimum_confidence / 100.0 - 1, 32, 2, 18), CREAM)
	_text("%d%%" % sim.reputation, Vector2(x + 148, 47), 16, CREAM)
	x += 210
	_text("TIME", Vector2(x, 26), 10, MUTED)
	_text("--:--" if tutorial_active else _time(sim.duration - sim.elapsed), Vector2(x, 50), 22, GOLD)
	x += 90
	var boost := Rect2(x, 14, 136, 40)
	var boost_ready: bool = sim.special_cooldown <= 0
	_button("special", "", boost, Color(PANEL_LIGHT, 0.85) if boost_ready else Color(PANEL, 0.6), GOLD)
	var label: String = "COFFEE BOOST"
	var lw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_text(label, boost.position + Vector2((boost.size.x - lw) / 2, 19), 14, GOLD if boost_ready else MUTED)
	var sub: String = "SPACE" if boost_ready else "ready in %ds" % ceili(sim.special_cooldown)
	var sw: float = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	_text(sub, boost.position + Vector2((boost.size.x - sw) / 2, 34), 10, MUTED)
	_button("help", "?", Rect2(bar.end.x - 102, 16, 40, 36), Color(PANEL_LIGHT, 0.85), CREAM, 18)
	_button("pause", "II", Rect2(bar.end.x - 54, 16, 40, 36), Color(PANEL_LIGHT, 0.85), CREAM, 16)
	if sim.surge_warning_remaining > 0:
		_pill(Rect2(bar.get_center().x - 120, bar.end.y + 6, 240, 34), "WAVE INCOMING · %ds" % ceili(sim.surge_warning_remaining), CORAL)
	elif sim.rush_remaining > 0:
		_pill(Rect2(bar.get_center().x - 120, bar.end.y + 6, 240, 34), "BUSY WAVE · %ds" % ceili(sim.rush_remaining), GOLD)
	_draw_crew_cards()

func _pill(rect: Rect2, text: String, color: Color) -> void:
	var pulse: float = 0.0 if reduced_motion else (sin(elapsed_ui * 6.0) + 1.0) * 0.5
	_panel(rect, Color(INK, 0.7), Color(color, 0.6 + 0.4 * pulse))
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	_text(text, rect.position + Vector2((rect.size.x - width) / 2, 23), 15, color)

func _need_chips(call: Dictionary, origin: Vector2, size: float = 18.0) -> void:
	var x: float = origin.x
	for kind in DEPARTMENTS:
		var needed: int = int(call.needs.get(kind,0))
		if needed<=0: continue
		var covered: bool = _assigned_count(call,kind)>=needed
		var chip := Rect2(Vector2(x, origin.y), Vector2(size, size))
		cv.draw_rect(chip, KIND_COLOR[kind] if covered else INK)
		cv.draw_rect(chip, KIND_COLOR[kind], false, 1)
		_symbol(kind, chip.get_center(), INK if covered else KIND_COLOR[kind], size / 34.0)
		x += size + 4



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
		cv.draw_rect(Rect2(805+i*13,117,10,7),color if float(i)/20.0<pressure_display else PANEL_LIGHT)

func _draw_map_overlay(canvas: Node2D) -> void:
	if screen!="game": return
	if tutorial_active:
		_draw_tutorial_highlight(canvas)

func _focus_button_rect() -> Rect2:
	return Rect2(field_focus.position+Vector2(FOCUS_RECT.size.x-65,7),Vector2(57,24)) if field_focus.visible else Rect2(40,724,185,34)

func _map_occluded(point: Vector2) -> bool:
	if tutorial_overlay.visible and tutorial_overlay.blocks_point(point + global_position): return true
	if field_focus.visible and Rect2(field_focus.position,FOCUS_RECT.size).has_point(point): return true
	return false

func _overlay_button(canvas: Node2D, caption: String, rect: Rect2) -> void:
	var hover: bool = rect.has_point(get_local_mouse_position())
	canvas.draw_style_box(_style(PANEL_LIGHT.lightened(.15) if hover else PANEL_LIGHT),rect)
	canvas.draw_string(font,rect.position+Vector2(8,rect.size.y*.5+4),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11,CREAM)



func _missing_crews(call: Dictionary) -> int:
	var count := 0
	for kind in DEPARTMENTS:
		count += maxi(0, int(call.needs.get(kind,0)) - _assigned_count(call,kind))
	return count

func _crew_on_scene(call: Dictionary) -> bool:
	for unit in sim.units:
		if int(unit.target)==int(call.id) and unit.state=="working" and bool(unit.get("assignment_suitable",true)): return true
	return false

func _clear_selection() -> void:
	if selected_unit>=0:
		selected_unit=-1
	else:
		selected=-1
	role_filter=""
	focused_unit=-1

# Number keys pick a free crew of that department (the fastest one to the selected call).
# Number keys: with the mouse over a call (or a call selected) they SEND the nearest free crew of that
# department straight there. With no call targeted they just pick that crew.
func _pick_department(kind: String) -> void:
	if not network.owns(kind):
		var owner: int = network.owner_of(kind)
		_toast("%s crews belong to %s." % [str(NetworkSession.DEPARTMENT_NAMES.get(kind,kind)), network.player_label(owner) if owner>0 else "a teammate"])
		return
	var target: int = int(tactical_map.hovered_incident_id) if int(tactical_map.hovered_incident_id)>=0 else selected
	var call: Dictionary = _incident(target)
	var best: int = -1
	var best_eta: float = INF
	if not call.is_empty() and call.get("status","") in ["active","working"]:
		for option: Dictionary in sim.dispatch_options(target):
			if str(option.kind)==kind and float(option.eta)<best_eta:
				best_eta=float(option.eta); best=int(option.unit_id)
		if best<0:
			_toast("No %s crew is free right now." % str(NetworkSession.DEPARTMENT_NAMES.get(kind,kind)).to_lower())
			return
		selected=target
		_command("dispatch",{"incident_id":target,"kind":kind,"unit_id":best})
		return
	for unit in sim.units:
		if unit.kind==kind and unit.state in ["idle","return"] and sim.elapsed>=float(unit.get("dispatch_guard_until",0.0)) and sim.elapsed>=float(unit.get("divert_after",0.0)):
			best=int(unit.id); break
	if best<0:
		_toast("No %s crew is free right now." % str(NetworkSession.DEPARTMENT_NAMES.get(kind,kind)).to_lower())
		return
	_select_unit(best)

func _cached_dispatch_options(target: int) -> Array:
	var now := Time.get_ticks_msec()
	if sim != _route_cache_sim or target != _route_cache_target or now >= _route_cache_until:
		_route_cache = sim.dispatch_options(target)
		_route_cache_sim = sim
		_route_cache_target = target
		_route_cache_until = now + 100
	return _route_cache

func _selected_plan() -> Dictionary:
	if selected<0 or selected_unit<0: return {}
	for option: Dictionary in _cached_dispatch_options(selected):
		if int(option.unit_id)==selected_unit: return option
	return {}

func _select_unit(id: int) -> void:
	if screen!="game": return
	var unit: Dictionary = sim.get_unit(id)
	if unit.is_empty(): return
	if not network.owns(str(unit.kind)):
		var owner: int = network.owner_of(str(unit.kind))
		_toast("%s is a %s crew. %s commands them — ask over voice." % [unit.get("crew_name",unit.name),str(NetworkSession.DEPARTMENT_NAMES.get(unit.kind,unit.kind)).to_lower(),network.player_label(owner) if owner>0 else "Nobody"])
		return
	if selected_unit==id:
		selected_unit=-1
		return
	if unit.state not in ["idle","return"]:
		_toast("%s is busy. Pick a free crew." % unit.get("crew_name",unit.name))
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
	audio.play_cue("select")

func _plan_kind(kind: String) -> void:
	
	if screen!="game" or kind not in DEPARTMENTS: return
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
		_toast("Pick a crew, then click a call.")
		return
	_command("dispatch",{"incident_id":selected,"kind":unit.kind,"unit_id":selected_unit})

func _draw_crew_cards() -> void:
	var gap: float = 8.0
	var width: float = (CREW_BAR.size.x - gap * (DEPARTMENTS.size() - 1)) / DEPARTMENTS.size()
	for i in range(DEPARTMENTS.size()):
		var kind: String = DEPARTMENTS[i]
		var rect := Rect2(CREW_BAR.position.x + i * (width + gap), CREW_BAR.position.y, width, CREW_BAR.size.y)
		var mine: bool = network.owns(kind)
		_panel(rect, Color(INK, 0.72), Color(KIND_COLOR[kind], 0.9) if mine and network.active else Color(CREAM, 0.1))
		_symbol(kind, rect.position + Vector2(14, 14), KIND_COLOR[kind], 0.42)
		var owner_text: String = KIND_NAME[kind]
		if network.active:
			var owner: int = network.owner_of(kind)
			owner_text = "%s · %s" % [KIND_NAME[kind], "YOU" if mine else (network.player_label(owner).to_upper() if owner>0 else "—")]
		_text(owner_text, rect.position + Vector2(28,18), 10, CREAM if mine and network.active else MUTED)
		var total := 0
		for unit in sim.units:
			if unit.kind == kind: total += 1
		var available := _available_units(kind)
		_text("%d/%d READY" % [available,total], rect.position + Vector2(rect.size.x - 78,18), 10, TEAL if available>0 else GOLD)
		var idx := 0
		var slot: float = (rect.size.x - 12) / maxi(1,total)
		for unit in sim.units:
			if unit.kind != kind: continue
			var x: float = 8 + idx * slot
			var card_area := Rect2(rect.position + Vector2(x - 2, 22), Vector2(slot - 4, 34))
			buttons.append({"id":"unit:%d" % unit.id,"rect":card_area})
			if int(unit.id)==selected_unit:
				cv.draw_rect(card_area, Color(GOLD, 0.18))
				cv.draw_rect(card_area, GOLD, false, 2)
			ResponderArt.draw_portrait(cv, rect.position + Vector2(x + 2, 26), kind, int(unit.get("appearance",unit.id)), 1.4)
			_text(_short(str(unit.get("crew_name",unit.name)),8), rect.position + Vector2(x + 30, 38), 13, CREAM)
			var status: String = {"idle":"READY","travel":"EN ROUTE","working":"ON SCENE","return":"RETURNING","rest":"RESTING"}.get(unit.state,str(unit.state).to_upper())
			if unit.state=="travel": status="ARRIVE %ds" % ceili(sim.unit_eta(unit))
			var ready_in: float = maxf(float(unit.get("divert_after",0.0)),float(unit.get("dispatch_guard_until",0.0))) - sim.elapsed
			if unit.state in ["idle","return"] and ready_in>0: status="READY IN %ds" % ceili(ready_in)
			_text(status, rect.position + Vector2(x + 30, 52), 10, KIND_COLOR[kind] if unit.state in ["travel","working"] else MUTED)
			idx += 1

func _draw_campaign() -> void:
	_draw_page_header("Your town is counting on you.", "SIX SHIFTS. ONE BEACON BAY.")
	for i in range(6):
		var data: Dictionary = BeaconCampaign.shift_data(i)
		var rect := Rect2(80+(i%3)*430, 222+(i/3)*221, 402, 192)
		var is_open := i <= unlocked
		_panel(rect, PANEL if is_open else Color("122e39"))
		cv.draw_rect(Rect2(rect.position, Vector2(402,4)), [TEAL,GOLD,BLUE,CORAL,Color("b5a5e9"),GOLD][i])
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
		_text("Same Wi-Fi / LAN, or a shared VPN such as Tailscale.",Vector2(452,331),16,MUTED)
		_text("TO JOIN: TYPE THE HOST'S IP ADDRESS (shown on the host's screen)",Vector2(452,370),12,TEAL)
		_button("host","HOST A ROOM",Rect2(452,456,536,54),TEAL,INK)
		_button("join","JOIN THIS ADDRESS",Rect2(452,524,536,54),PANEL_LIGHT,CREAM)
		_wrap("Everyone plays the same role: you each command your own emergency departments. Talk over your voice call to cover calls that need several crews.",Vector2(452,620),526,14,MUTED,21)
	else:
		_text("%d / 4 CREW CONNECTED" % network.roster.size(),Vector2(452,291),21,TEAL)
		_text(network.status,Vector2(452,326),15,MUTED)
		var row := 0
		for peer_id in network.roster:
			var r: int = int(network.roster[peer_id])
			_text("%s%s" %[network.player_label(int(peer_id)), "  (you)" if int(peer_id)==multiplayer.get_unique_id() else ""],Vector2(452,373+row*42),19,CREAM)
			var dx: float = 640
			for kind in network.departments_for(int(peer_id)):
				_symbol(kind,Vector2(dx,367+row*42),KIND_COLOR[kind],0.5)
				_text(str(KIND_SHORT[kind]),Vector2(dx+12,373+row*42),15,KIND_COLOR[kind])
				dx += 74
			row += 1
		if network.hosting:
			_button("host_start","START SHIFT TOGETHER",Rect2(452,540,536,54),TEAL,INK)
			_text("Same network: " + "   ".join(_local_addresses()),Vector2(452,624),16,CREAM)
			_text(_short(network.internet_status,78),Vector2(452,652),13,TEAL if network.internet_address!="" else MUTED)
			_text("Port %d (UDP). Allow Beacon Bay through the firewall when Windows asks." % NetworkSession.PORT,Vector2(452,676),12,MUTED)
		else:
			_text("Waiting for the host to begin…",Vector2(452,600),19,GOLD)
	_button("leave_lobby","<  BACK",Rect2(80,91,125,38),PANEL,CREAM,14)
	_wrap("Departments split automatically: 1 player commands all four, 2 players take two each, 3 players: the host also takes police, 4 players: one each. Anyone can scout, use supplies, use the coffee boost and ping.",Vector2(400,741),640,16,MUTED,25)

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
		["01", "Pick a crew", "Click a station, a vehicle on the road or a crew card. 1-4 picks a free crew of that type. In co-op you only command your own departments."],
		["02", "Click the call", "Hover a call to see whether the crew makes it IN TIME, then click it to send. Shortcut: hover a call and press 1-4 to send the nearest fire / medic / engineer / police crew."],
		["03", "Scout and supply", "Q reveals what a ? call needs. E sends supplies to a crew already on scene: +18 seconds and faster work."],
		["04", "Stay calm", "SPACE: coffee boost, every crew is faster for 20 seconds. Right-click or ESC clears your selection. F opens a close-up of the selected call."]
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
	cv.draw_style_box(_style(color,border),rect)

func _style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color=color
	box.set_corner_radius_all(8)
	if border.a>0:
		box.border_color=border
		box.set_border_width_all(1)
	return box

func _button(id: String, text: String, rect: Rect2, bg: Color = PANEL_LIGHT, fg: Color = CREAM, font_size: int = 17) -> void:
	var hovered := rect.has_point(get_local_mouse_position())
	_panel(rect,bg.lightened(0.10) if hovered else bg,fg*Color(1,1,1,0.34) if hovered else Color.TRANSPARENT)
	if text != "":
		var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		_text(text,rect.position+Vector2((rect.size.x-width)/2,(rect.size.y+font_size*0.72)/2),font_size,fg)
	buttons.append({"id":id,"rect":rect})

func _text(text: String, pos: Vector2, size: int = 18, color: Color = CREAM) -> void:
	cv.draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

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
	cv.draw_rect(rect,Color("0b242e"))
	cv.draw_rect(Rect2(rect.position,Vector2(rect.size.x*clampf(ratio,0,1),rect.size.y)),color)

func _symbol(kind: String, center: Vector2, color: Color, s: float = 1.0) -> void:
	match kind:
		"police":
			cv.draw_rect(Rect2(center+Vector2(-9,-11)*s,Vector2(18,14)*s),color)
			cv.draw_colored_polygon(PackedVector2Array([center+Vector2(-9,3)*s,center+Vector2(9,3)*s,center+Vector2(0,13)*s]),color)
			cv.draw_rect(Rect2(center+Vector2(-3,-6)*s,Vector2(6,6)*s),INK)
		"medic","medical":
			cv.draw_rect(Rect2(center+Vector2(-4,-12)*s,Vector2(8,24)*s),color)
			cv.draw_rect(Rect2(center+Vector2(-12,-4)*s,Vector2(24,8)*s),color)
		"fire":
			var pts := PackedVector2Array([Vector2(-10,10),Vector2(-12,0),Vector2(-5,-8),Vector2(-3,-2),Vector2(3,-16),Vector2(6,-7),Vector2(12,2),Vector2(9,11)])
			for i in range(pts.size()): pts[i]=pts[i]*s+center
			cv.draw_colored_polygon(pts,color)
			cv.draw_rect(Rect2(center+Vector2(-3,2)*s,Vector2(6,9)*s),GOLD)
		"engineer","power":
			cv.draw_line(center+Vector2(-9,11)*s,center+Vector2(8,-8)*s,color,6*s)
			cv.draw_line(center+Vector2(1,-12)*s,center+Vector2(7,-5)*s,color,5*s)
			cv.draw_line(center+Vector2(12,-1)*s,center+Vector2(7,-5)*s,color,5*s)
		"flood":
			for i in range(3):
				cv.draw_line(center+Vector2(-12,-7+i*7)*s,center+Vector2(-4,-10+i*7)*s,color,3*s)
				cv.draw_line(center+Vector2(-4,-10+i*7)*s,center+Vector2(5,-6+i*7)*s,color,3*s)
				cv.draw_line(center+Vector2(5,-6+i*7)*s,center+Vector2(12,-9+i*7)*s,color,3*s)
		_:
			cv.draw_line(center+Vector2(-10,0)*s,center+Vector2(-3,8)*s,color,4*s)
			cv.draw_line(center+Vector2(-3,8)*s,center+Vector2(12,-9)*s,color,4*s)

func _overlay() -> void:
	cv.draw_rect(Rect2(-UI_OFFSET_X,0,1600,900),Color(0.025,0.08,0.11,0.92))

func _star(center: Vector2, radius: float, color: Color) -> void:
	var points:=PackedVector2Array()
	for i in range(10):
		points.append(center+Vector2.from_angle(-PI/2.0+i*PI/5.0)*radius*(1.0 if i%2==0 else 0.45))
	cv.draw_colored_polygon(points,color)

func _input(event: InputEvent) -> void:
	if tutorial_overlay.visible and tutorial_overlay.handle_input(event):
		if event is InputEventMouseMotion:
			town.hover_id=-1
			tactical_map.clear_hover()
		get_viewport().set_input_as_handled()
		return
	var over_hud_button: bool = false
	if screen=="game" and event is InputEventMouse:
		var p: Vector2 = event.position - global_position
		for b in buttons:
			if b.rect.has_point(p): over_hud_button = true
	if screen=="game" and tactical_map.visible and not over_hud_button and tactical_map.handle_input(event):
		if not tutorial_active:
			if event is InputEventMouseMotion: research.log_pointer(event.position,event.relative)
			elif event is InputEventMouseButton and event.pressed: research.log_click(event.position)
		get_viewport().set_input_as_handled()
		return
	var local_pos: Vector2 = (event.position - global_position) if event is InputEventMouse else Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and screen=="game":
		_clear_selection()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if screen == "game" and not tutorial_active: research.log_pointer(event.position,event.relative)
		var over := false
		for b in buttons:
			if b.rect.has_point(local_pos): over = true
		if screen=="game" and not _map_occluded(local_pos) and town.hover_id>=0: over=true
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over else Input.CURSOR_ARROW)
		if screen=="game" and _map_occluded(local_pos):
			town.hover_id=-1
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if screen == "game" and not tutorial_active: research.log_click(event.position)
		for i in range(buttons.size()-1,-1,-1):
			var b: Dictionary=buttons[i]
			if b.rect.has_point(local_pos):
				_action(b.id)
				get_viewport().set_input_as_handled()
				return
		if screen=="game" and _map_occluded(local_pos):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if ip_input.has_focus():
			if event.keycode == KEY_ENTER: _action("join")
			return
		match event.keycode:
			KEY_F3:
				show_perf = not show_perf
			KEY_F11:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
			KEY_ESCAPE:
				if screen=="game" and (selected_unit>=0 or selected>=0): _clear_selection()
				elif screen=="game": _action("pause")
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
			KEY_4:
				if screen=="game": _action("plan:police")
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
		_select_unit(id.trim_prefix("unit:").to_int())
		return
	if id.begins_with("plan:"):
		if tutorial_active: _plan_kind(id.trim_prefix("plan:"))
		else: _pick_department(id.trim_prefix("plan:"))
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
			if network.active and not network.hosting: _toast("Hover a call + 1-4 sends a crew · Q scout · E supplies · SPACE coffee boost · R ping")
			else: screen="help"
		"scout","supply","special": _command(id,{"incident_id":selected})
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
	field_focus.position=Vector2(-64,80)
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
		if selected_unit>=0 and selected>=0:
			var call_rect: Rect2=tactical_map.call_hit_rect(selected)
			if call_rect.has_area(): canvas.draw_rect(call_rect.grow(4),accent,false,3)
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
		var call:=_incident(ident)
		if not call.is_empty():
			var point: Vector2=map_clip.position+call.pos*TownView.MAP_SIZE*MAP_SCALE
			canvas.draw_rect(Rect2(point-Vector2(23,67),Vector2(46,47)),accent,false,3)
	else:
		for button in buttons:
			if str(button.id)==key:
				canvas.draw_rect((button.rect as Rect2).grow(4),accent,false,3)

func _begin_shift(index: int) -> void:
	_route_cache_until = 0
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
	_toast(("You command %s. Choose a call, then click one of your crews." % network.departments_text()) if network.active else ("Choose a call, then click a crew on the map. 1-4 highlight crew types." if index==0 else ticker))

func _finish_shift() -> void:
	if result_saved: return
	result_saved=true
	screen="results"
	if sim.won:
		unlocked=maxi(unlocked,mini(5,sim.shift_index+1))
		best_scores[str(sim.shift_index)]=maxi(int(best_scores.get(str(sim.shift_index),0)),sim.score)
		total_rescued+=sim.rescued
		audio.play_cue("win")
	else: audio.play_cue("lose")
	_save_progress()

func _select_incident(id: int) -> void:
	focus_hold_left=0
	if screen != "game": return
	# A crew is selected: clicking a call sends that crew there.
	if selected_unit>=0:
		var crew: Dictionary = sim.get_unit(selected_unit)
		var payload := {"incident_id":id,"kind":str(crew.get("kind","")),"unit_id":selected_unit}
		if not crew.is_empty() and (not tutorial_active or tutorial.can_action("dispatch",payload)):
			selected=id
			_command("dispatch",payload)
			return
	if tutorial_active and not tutorial.can_action("select",{"incident_id":id}): return
	selected=id
	if tutorial_active:
		tutorial.on_action("select",{"incident_id":id})
		_sync_tutorial()
	else:
		research.log_inspection(id)
	audio.play_cue("click")

func _cycle_incident() -> void:
	var calls:=_active_incidents()
	if calls.is_empty(): return
	var idx:=0
	for i in range(calls.size()):
		if int(calls[i].id)==selected: idx=(i+1)%calls.size(); break
	_select_incident(int(calls[idx].id))

func _command(action: String, payload: Dictionary) -> void:
	_route_cache_until = 0
	if screen != "game": return
	if not network.can_do(action,-1,payload):
		var owner: int = network.owner_of(str(payload.get("kind","")))
		_toast("You command %s. Ask %s to send that crew." % [network.departments_text(), network.player_label(owner) if owner>0 else "a teammate"])
		return
	network.send_command(action,payload)
	if action == "dispatch" and network.active and not network.hosting and sim.running:
		var id: int = int(payload.get("incident_id", -1))
		if sim.dispatch(id, str(payload.get("kind", "")), int(payload.get("unit_id", -1))):
			sim.drain_events()
			predicted_dispatches.append({"incident_id": id, "kind": str(payload.get("kind", "")), "unit_id": int(payload.get("unit_id", -1)), "until": Time.get_ticks_msec() + 1500})
			selected_unit = -1
			selected = id
			role_filter = ""
			focused_unit = -1
			focused_unit_left = 0

func _execute_command(action: String,payload: Dictionary,_peer_id: int) -> void:
	_route_cache_until = 0
	if screen!="game": return
	if tutorial_active and not tutorial.can_action(action,payload):
		_toast(str(tutorial.current().objective))
		return
	if not network.can_do(action,_peer_id,payload): return
	event_actor = _peer_id
	var local_command: bool = not network.active or _peer_id==multiplayer.get_unique_id()
	var id:=int(payload.get("incident_id",-1))
	var success:=false
	match action:
		"dispatch":
			success=sim.dispatch(id,str(payload.get("kind","")),int(payload.get("unit_id",-1)))
		"scout": success=sim.scout(id)
		"supply": success=sim.supply(id)
		"special": success=sim.use_special()
		"ping": network.announce("%s: %s" % [network.player_label(_peer_id) if network.active else "Radio", str(payload.get("text","Help needed"))]); success=true
	if success:
		if action=="dispatch" and local_command:
			selected_unit=-1
			selected=id
			role_filter=""
			focused_unit=-1
			focused_unit_left=0
		if tutorial_active:
			tutorial.on_action(action,payload,true)
			_sync_tutorial()
		elif action=="ping": research.log_event(action,payload)
	else:
		var reason: String = "Crew unavailable or already assigned. Check the call's remaining needs." if action=="dispatch" else "Not available yet. Select an active call or let supplies recharge."
		if local_command: _toast(reason)
		elif network.has_method("broadcast_event"): network.call("broadcast_event",{"type":"action_denied","text":reason,"actor_peer":_peer_id})
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
	if message!="" and type!="action_denied":
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
		audio.play_cue("new_call")
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
	elif type=="rally": audio.play_cue("boost")
	elif type=="dispatch_mismatch":
		_toast(message)
		audio.play_cue("fail")
	elif type=="action_denied" and local_actor: _toast(message)

func _receive_snapshot(data: Dictionary) -> void:
	_route_cache_until = 0
	if network.hosting: return
	var next_screen:=str(data.get("screen","game"))
	if screen=="results" and next_screen=="game":
		_submit_rating()
		result_rating_sent=false
	var previous_shift: int = sim.shift_index
	sim.apply_snapshot(data.get("simulation",{}))
	host_speed = float(data.get("speed", 1.0))
	var now: int = Time.get_ticks_msec()
	if _last_snapshot_ms >= 0: _snapshot_gap_ms = lerpf(_snapshot_gap_ms, float(now - _last_snapshot_ms), 0.2)
	_last_snapshot_ms = now
	if next_screen == "game" and sim.running:
		# The snapshot left the host half a round trip ago; catch up to "now".
		sim.tick(clampf(network.round_trip_ms() * 0.0005, 0.0, 0.15) * host_speed)
		_reapply_predictions()
		sim.drain_events()
	if next_screen in ["game","pause","results","help"]:
		screen=next_screen
	orders=data.get("orders",{})
	# Repainting the town backdrop is expensive; only do it when the shift changes.
	if sim.shift_index != previous_shift or screen != "game": town.set_theme(sim.shift_index)

# A guest's dispatch moves the crew on their own screen straight away. Until the
# host's snapshot shows the crew assigned, it is re-applied after every snapshot
# so the crew doesn't jump back to the station.
func _reapply_predictions() -> void:
	var now: int = Time.get_ticks_msec()
	var keep: Array[Dictionary] = []
	for p in predicted_dispatches:
		if now > int(p.until): continue
		var unit: Dictionary = sim.get_unit(int(p.unit_id))
		if unit.is_empty(): continue
		if int(unit.get("target", -1)) == int(p.incident_id) and str(unit.get("state", "")) != "idle": continue
		sim.dispatch(int(p.incident_id), str(p.kind), int(p.unit_id))
		keep.append(p)
	predicted_dispatches = keep

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
	var missing: Array[String] = []
	for kind in DEPARTMENTS:
		sent+=_assigned_count(call,kind)
		needed+=int(call.needs.get(kind,0))
		if call.discovered and _assigned_count(call,kind)<int(call.needs.get(kind,0)): missing.append(KIND_SHORT[kind])
	if not call.discovered: return "UNCONFIRMED REPORT"
	if not missing.is_empty(): return ("STILL NEEDS " if sent>0 else "NEEDS ") + " + ".join(missing)
	return "CREWS EN ROUTE"

func _boost_text() -> String:
	return "COFFEE BOOST" if sim.special_cooldown<=0 else "COFFEE BOOST %ds"%ceili(sim.special_cooldown)

func _toast(message: String) -> void:
	toast_text=message
	toast_left=5.0

func _time(seconds: float) -> String:
	var secs:=maxi(0,ceili(seconds))
	return "%02d:%02d"%[secs/60,secs%60]

func _short(text: String,count: int) -> String:
	return text if text.length()<=count else text.left(count-1)+"…"

# Every IPv4 address another computer could use to reach this one (home/school LAN, Tailscale/ZeroTier VPN).
func _local_addresses() -> Array[String]:
	var found: Array[String] = []
	for address in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."): continue
		if not found.has(address): found.append(address)
	found.sort_custom(func(a,b): return (0 if a.begins_with("192.168.") else 1) < (0 if b.begins_with("192.168.") else 1))
	if found.is_empty(): found.append("127.0.0.1 (this computer only)")
	return found.slice(0,3)

func _celebrate(center: Vector2) -> void:
	if reduced_motion: return
	for i in range(22):
		particles.append({"pos":center,"velocity":Vector2.from_angle(randf()*TAU)*randf_range(30,100),"life":randf_range(0.5,1.3),"color":[TEAL,GOLD,CORAL][i%3]})

func _capture_later(path: String) -> void:
	await get_tree().create_timer(4).timeout
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	image.save_png(path)
