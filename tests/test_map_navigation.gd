extends SceneTree

# 4.11 (Andrei): only the whole-town view is left: no OVERVIEW/EXPLORE button,
# no wheel zoom, no panning. Clicking, selecting and dispatching work as before.
var failures: Array[String] = []
var game: Node
var sent_buttons := 0
var sent_moves := 0

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func button(at: Vector2, pressed: bool, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_final_transform() * (at + game.global_position)
	event.global_position = event.position
	event.button_index = index
	event.pressed = pressed
	sent_buttons += 1
	Input.parse_input_event(event)

func motion(at: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_final_transform() * (at + game.global_position)
	event.global_position = event.position
	event.relative = root.get_final_transform().basis_xform(relative)
	sent_moves += 1
	Input.parse_input_event(event)

func refresh_map() -> void:
	game._process(0)
	game.tactical_map.refresh()

func click_target(rect: Rect2, label: String) -> void:
	check(rect.has_area(), label + " has a clickable marker")
	if not rect.has_area(): return
	button(rect.get_center(), true)
	button(rect.get_center(), false)

func check_camera(zoom: float, pan: Vector2, label: String) -> void:
	check(is_equal_approx(game.map_zoom, zoom) and game.map_pan == pan, label + " preserves zoom and camera position")

func test_selection_preserves_view() -> void:
	game.research_enabled = false
	game.buttons.clear()
	for overview: bool in [true]:
		game._begin_shift(0)
		game._center_map(Vector2(.55, .55))
		var zoom: float = game.map_zoom
		var pan: Vector2 = game.map_pan
		var view := "Overview" if overview else "Exploration"
		game.sim._spawn_incident()
		var call: Dictionary = game.sim.incidents.back()
		call.pos = Vector2(.48, .4)
		call.kind = "medical"
		call.needs = {"medic": 1, "fire": 1}
		call.discovered = false
		var medic: Dictionary = {}
		for unit: Dictionary in game.sim.units:
			if unit.kind == "medic":
				medic = unit
				break
		medic.state = "return"
		medic.pos = Vector2(.65, .65)
		refresh_map()
		# Stations and individual crews use press-to-select in both views.
		var station: Rect2 = game.tactical_map.base_hit_rect("engineer")
		# An offscreen station is deliberately not moved into view automatically.
		if station.has_area():
			click_target(station, view + " station")
			check(game.selected_unit >= 0 and game.sim.get_unit(game.selected_unit).kind == "engineer", view + " station selects a crew")
			check_camera(zoom, pan, view + " station selection")
		game.selected_unit = -1
		refresh_map()
		click_target(game.tactical_map.unit_hit_rect(int(medic.id)), view + " crew")
		check(game.selected_unit == int(medic.id), view + " crew remains selected after release")
		check_camera(zoom, pan, view + " crew selection")
		refresh_map()
		click_target(game.tactical_map.call_hit_rect(int(call.id)), view + " unconfirmed call")
		check(game.selected == int(call.id) and game.selected_unit == int(medic.id), view + " unconfirmed call opens with the crew still selected")
		check(game.sim.successful_dispatches == 0, view + " unconfirmed call does not dispatch")
		check_camera(zoom, pan, view + " call selection")
		refresh_map()
		click_target(game.tactical_map._rect_for("scout", int(call.id)), view + " scout control")
		check(bool(call.discovered), view + " scout control reveals the selected call")
		check_camera(zoom, pan, view + " scouting")
		refresh_map()
		click_target(game.tactical_map.call_hit_rect(int(call.id)), view + " dispatch call")
		check(game.sim.successful_dispatches == 1 and int(medic.target) == int(call.id), view + " call click dispatches the selected crew")
		check_camera(zoom, pan, view + " dispatch")
		game._pick_department("fire")
		check(game.sim.successful_dispatches == 2, view + " department shortcut dispatches another crew")
		check_camera(zoom, pan, view + " quick dispatch")
		game._action("unit:%d" % int(medic.id))
		check(game.selected_unit == int(medic.id), view + " crew bar selects an assigned crew")
		game._action("withdraw:%d" % int(medic.id))
		check(str(medic.state) == "return", view + " selected crew can withdraw")
		check_camera(zoom, pan, view + " crew controls")
		game.selected_unit = -1
		game._cycle_incident()
		check_camera(zoom, pan, view + " next-call shortcut")
		game._action("focus")
		check_camera(zoom, pan, view + " call focus panel")
		# Selecting an ordinary known call also leaves the camera untouched.
		game.selected = -1
		refresh_map()
		click_target(game.tactical_map.call_hit_rect(int(call.id)), view + " known call")
		check(game.selected == int(call.id), view + " known call opens without a selected crew")
		check_camera(zoom, pan, view + " known call selection")

func run() -> void:
	game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game.research_enabled = true
	game._begin_shift(0)
	check(game._is_map_overview(), "A level starts on the whole town")
	var whole_zoom: float = game.map_zoom
	var whole_pan: Vector2 = game.map_pan
	check(is_equal_approx(whole_zoom, game._fit_map_zoom()), "The whole town fits the screen")
	check(game._map_rect().size.x <= game.MAP_VIEW.size.x + 1 and game._map_rect().size.y <= game.MAP_VIEW.size.y + 1, "Every edge of the town is visible")
	# Old ways into a closer view do nothing now.
	game.map_zoom = game._drag_zoom()
	game._center_map(Vector2(.8, .8))
	check(is_equal_approx(game.map_zoom, whole_zoom) and game.map_pan == whole_pan, "The map cannot be zoomed in or moved")
	game._toggle_overview()
	game._zoom_map(1, Vector2(690, 390))
	check(is_equal_approx(game.map_zoom, whole_zoom), "Neither the old toggle nor the wheel zooms in")
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	check(not game.buttons.any(func(b): return str(b.id) == "map_overview"), "There is no OVERVIEW/EXPLORE button")
	check(not game._minimap_shown(), "No minimap (it only belonged to the closer view)")
	game.sim._spawn_incident()
	var call: Dictionary = game.sim.incidents.back()
	call.pos = Vector2(.5, .5)
	call.kind = "medical"
	call.needs = {"medic": 1}
	call.discovered = true
	var medic: Dictionary = {}
	for unit: Dictionary in game.sim.units:
		if unit.kind == "medic":
			medic = unit
			break
	game.selected_unit = int(medic.id)
	game._process(0)
	game.tactical_map.refresh()
	var point: Vector2 = game.tactical_map.call_hit_rect(int(call.id)).get_center()
	button(point, true)
	check(game.sim.successful_dispatches == 0, "Marker press never dispatches before release")
	motion(point + Vector2(36, 22), Vector2(36, 22))
	button(point + Vector2(36, 22), false)
	check(game.map_pan == whole_pan, "Dragging does not move the map")
	check(game.sim.successful_dispatches == 0, "Dragging across a call does not accidentally dispatch")
	game.tactical_map.refresh()
	point = game.tactical_map.call_hit_rect(int(call.id)).get_center()
	button(point, true)
	motion(point + Vector2(2, 1), Vector2(2, 1))
	check(game.sim.successful_dispatches == 0, "Small click jitter waits until release")
	button(point + Vector2(2, 1), false)
	check(game.sim.successful_dispatches == 1, "A released click dispatches exactly once")
	button(point, false)
	check(game.sim.successful_dispatches == 1, "An unmatched mouse release never dispatches")
	# Playtest 15.10: a crew is picked on press, even if the press becomes a drag.
	var fire: Dictionary = game.sim.units[0]
	fire.state = "return"
	fire.pos = Vector2(.56, .62)
	game.selected_unit = -1
	game.tactical_map.refresh()
	point = game.tactical_map.unit_hit_rect(int(fire.id)).get_center()
	button(point, true)
	motion(point + Vector2(24, 12), Vector2(24, 12))
	button(point + Vector2(24, 12), false)
	check(game.selected_unit == int(fire.id), "Pressing a crew selects it even when the press becomes a drag")
	game.selected_unit = -1
	# The wheel and the middle button no longer change the view.
	button(Vector2(690, 390), true, MOUSE_BUTTON_WHEEL_UP)
	button(Vector2(690, 390), false, MOUSE_BUTTON_WHEEL_UP)
	button(Vector2(700, 500), true, MOUSE_BUTTON_MIDDLE)
	motion(Vector2(740, 520), Vector2(40, 20))
	button(Vector2(740, 520), false, MOUSE_BUTTON_MIDDLE)
	check(is_equal_approx(game.map_zoom, whole_zoom) and game.map_pan == whole_pan, "Wheel and middle-button drag leave the whole-town view as it is")
	# HUD buttons preserve their immediate click behavior.
	game.buttons.clear()
	game.buttons.append({"id": "pause", "rect": Rect2(900, 16, 40, 36)})
	button(Vector2(910, 30), true)
	check(game.screen == "pause", "HUD left-click still acts immediately")
	var log_path: String = game.research.log_path
	game._stop_capture()
	var clicks := 0
	var moves := 0
	for line in FileAccess.get_file_as_string(log_path).split("\n", false):
		var event: Dictionary = JSON.parse_string(line)
		if event.event == "mouse_button": clicks += 1
		if event.event == "mouse_motion": moves += 1
	check(clicks == sent_buttons and moves == sent_moves, "Gesture routing records each delivered mouse event exactly once (%d/%d clicks, %d/%d moves)" % [clicks, sent_buttons, moves, sent_moves])
	test_selection_preserves_view()
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: whole-town view only (no zoom, button, wheel or panning); stable selection, scouting, dispatch and crew controls; HUD input and recording")
	else:
		for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
