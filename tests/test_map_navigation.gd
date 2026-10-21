extends SceneTree

var failures: Array[String] = []
var game: Node

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
	Input.parse_input_event(event)

func motion(at: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_final_transform() * (at + game.global_position)
	event.global_position = event.position
	event.relative = root.get_final_transform().basis_xform(relative)
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
	for overview: bool in [true, false]:
		game._begin_shift(0)
		if not overview: game._toggle_overview()
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
	game.map_zoom = game._drag_zoom()
	game._center_map(Vector2(.5, .5))
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
	var initial_pan: Vector2 = game.map_pan
	button(point, true)
	check(game.sim.successful_dispatches == 0, "Marker press never dispatches before release")
	motion(point + Vector2(36, 22), Vector2(36, 22))
	button(point + Vector2(36, 22), false)
	check(game.map_pan != initial_pan, "Left dragging a call pans the town")
	check(game.sim.successful_dispatches == 0, "Dragging a call does not accidentally dispatch")
	game._center_map(Vector2(.5, .5))
	game.tactical_map.refresh()
	point = game.tactical_map.call_hit_rect(int(call.id)).get_center()
	button(point, true)
	motion(point + Vector2(2, 1), Vector2(2, 1))
	check(game.sim.successful_dispatches == 0, "Small click jitter waits until release")
	button(point + Vector2(2, 1), false)
	check(game.sim.successful_dispatches == 1, "A released click dispatches exactly once")
	button(point, false)
	check(game.sim.successful_dispatches == 1, "An unmatched mouse release never dispatches")
	# Playtest 15.10: a crew is picked on press, so a press that turns into a
	# drag still selects it (and still pans the town).
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
	# A marker outside the viewport belongs on the minimap, never clamped onto
	# an unrelated street along the visible viewport edge.
	call.pos = Vector2(.01, .01)
	game.map_zoom = game._drag_zoom()
	game._center_map(Vector2(.9, .9))
	game.tactical_map.refresh()
	check(not game.tactical_map.call_hit_rect(int(call.id)).has_area(), "Offscreen calls are not clickable edge ghosts")
	button(game.MINIMAP_RECT.position + game.MINIMAP_RECT.size * .1, true)
	button(game.MINIMAP_RECT.position + game.MINIMAP_RECT.size * .1, false)
	check(game._map_center().x < .5 and game._map_center().y < .5, "Minimap click jumps toward its world position")
	var old_zoom: float = game.map_zoom
	var old_center: Vector2 = game._map_center()
	game._toggle_overview()
	check(is_equal_approx(game.map_zoom, game._fit_map_zoom()), "Overview fits the whole world")
	check(game._map_rect().size.x <= game.MAP_VIEW.size.x + 1 and game._map_rect().size.y <= game.MAP_VIEW.size.y + 1, "Overview contains every world edge")
	game._toggle_overview()
	check(is_equal_approx(game.map_zoom, old_zoom) and game._map_center().distance_to(old_center) < .002, "Overview returns to previous camera")
	# Only two views: the wheel switches between them, never zooms further.
	game._zoom_map(1, Vector2(690, 390))
	check(is_equal_approx(game.map_zoom, game._drag_zoom()), "Wheel up in the drag view does not zoom further in")
	game.selected = int(call.id)
	game._zoom_map(-1, Vector2(690, 390))
	check(game._is_map_overview(), "Wheel down shows the whole town")
	check(game.selected == -1, "Switching to the whole town closes the open call card")
	game._zoom_map(-1, Vector2(690, 390))
	check(game._is_map_overview(), "Wheel down on the whole town stays there")
	var anchor := Vector2(690, 390)
	var world_before: Vector2 = (anchor - game._map_rect().position) / game._map_rect().size
	game._zoom_map(1, anchor)
	check(is_equal_approx(game.map_zoom, game._drag_zoom()), "Wheel up on the whole town opens the drag view")
	var world_after: Vector2 = (anchor - game._map_rect().position) / game._map_rect().size
	check(world_before.distance_to(world_after) < .02, "The drag view opens where the cursor was")
	initial_pan = game.map_pan
	button(Vector2(700, 500), true, MOUSE_BUTTON_MIDDLE)
	motion(Vector2(740, 520), Vector2(40, 20))
	button(Vector2(740, 520), false, MOUSE_BUTTON_MIDDLE)
	check(game.map_pan != initial_pan, "Middle-button panning is retained")
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
	check(clicks == 12 and moves == 4, "Gesture routing records each delivered mouse event exactly once")
	test_selection_preserves_view()
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: stable camera for selection, scouting, dispatch and crew controls in both views; drag, minimap, explicit zoom, HUD input and recording")
	else:
		for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
