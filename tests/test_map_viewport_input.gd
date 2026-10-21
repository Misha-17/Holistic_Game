extends SceneTree

var game: Node
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
var label := "fixed"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func button(at: Vector2, pressed: bool, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	# Inject in window coordinates, as the desktop driver does. The viewport
	# must undo its stretch transform before the game's _input receives it.
	event.position = root.get_final_transform() * (at + game.global_position)
	event.global_position = event.position
	event.button_index = index
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	Input.parse_input_event(event)

func motion(at: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_final_transform() * (at + game.global_position)
	event.global_position = event.position
	event.relative = root.get_final_transform().basis_xform(relative)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)

func frame() -> void:
	game._process(0)
	game.tactical_map.refresh()
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func snapshot(name: String) -> void:
	await frame()
	evidence.append({"name": name, "window_size": str(root.size), "viewport_size": str(root.get_visible_rect().size), "stretch": str(root.get_final_transform()), "zoom": game.map_zoom, "pan": str(game.map_pan), "center": str(game._map_center())})
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("res://test_output/navigation-%s-%s.png" % [label, name])

func run() -> void:
	if "--baseline" in OS.get_cmdline_user_args(): label = "baseline"
	DirAccess.make_dir_recursive_absolute("res://test_output")
	game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game._begin_shift(0)
	game.toast_left = 0
	await snapshot("default")
	# Playtest 15.10: every level starts on the whole town.
	check(game._is_map_overview(), "New shifts start on the whole town")
	var kinds: Dictionary = {}
	for unit: Dictionary in game.sim.units:
		if kinds.has(unit.kind): continue
		kinds[unit.kind] = true
		var station_point: Vector2 = game._map_rect().position + Vector2(unit.home) * game._map_rect().size
		check(game.MAP_VIEW.has_point(station_point), "Initial exploration includes the main " + str(unit.kind) + " station")
	var point := Vector2(700, 450)
	game._toggle_overview()
	var before: Vector2 = game.map_pan
	button(point, true)
	check(game._map_press_pending, "Real viewport routes map press to gesture handler")
	check(game._map_press_position.distance_to(point) < .1, "Viewport maps desktop position to game coordinates")
	motion(point + Vector2(180, 95), Vector2(180, 95))
	button(point + Vector2(180, 95), false)
	check(game.map_pan.distance_to(before) > 100, "Real viewport drag visibly pans exploration")
	await snapshot("dragged")
	game._toggle_overview()
	await snapshot("overview")
	before = game.map_pan
	button(point, true)
	motion(point + Vector2(140, 70), Vector2(140, 70))
	button(point + Vector2(140, 70), false)
	check(game._is_map_overview(), "Dragging overview keeps the chosen zoom")
	check(game.map_pan == before, "Overview drag keeps the whole town in frame")
	await snapshot("overview-drag")
	# The minimap (drag view only) jumps to a distant district.
	game._toggle_overview()
	game._center_map(Vector2(.3, .3))
	var destination: Vector2 = game.MINIMAP_RECT.position + game.MINIMAP_RECT.size * Vector2(.82, .8)
	button(destination, true)
	button(destination, false)
	check(not game._is_map_overview(), "Minimap click keeps the drag view")
	check(game._map_center().x > .6 and game._map_center().y > .6, "Minimap reaches the southeast districts")
	await snapshot("minimap-southeast")
	# Two views: wheel down = whole town, wheel up = drag view; nothing in between.
	button(point, true, MOUSE_BUTTON_WHEEL_DOWN)
	check(game._is_map_overview(), "Scrolling down shows the whole town")
	for i in range(4): button(point, true, MOUSE_BUTTON_WHEEL_DOWN)
	check(game._is_map_overview(), "More scrolling down stays on the whole town")
	button(point, true, MOUSE_BUTTON_WHEEL_UP)
	for i in range(4): button(point, true, MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(game.map_zoom, game._drag_zoom()), "Scrolling up opens the drag view and never zooms further")
	await snapshot("zoom-floor")
	var floor_zoom: float = game.map_zoom
	var floor_center: Vector2 = game._map_center()
	game._toggle_overview()
	game._toggle_overview()
	check(is_equal_approx(game.map_zoom, floor_zoom) and game._map_center().distance_to(floor_center) < .002, "Explore restores the previous zoom even at the wheel floor")
	game._toggle_overview()
	button(point, true)
	button(point, false)
	check(game._is_map_overview(), "A district click keeps the chosen overview")
	var key := InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	Input.parse_input_event(key)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	check(game._is_map_overview(), "Arrow keys pan without changing zoom")
	button(point, true, MOUSE_BUTTON_MIDDLE)
	motion(point + Vector2(80, 40), Vector2(80, 40))
	button(point + Vector2(80, 40), false, MOUSE_BUTTON_MIDDLE)
	check(game._is_map_overview(), "Middle-button pan keeps the chosen zoom")
	# Exercise the actual window stretch rather than passing preconverted events
	# straight to _input. An odd aspect ratio also covers letterbox conversion.
	root.size = Vector2i(1100, 700)
	await frame()
	game.map_zoom = 1.5
	game._center_map(Vector2(.5, .5))
	await frame()
	before = game.map_pan
	button(point, true)
	check(game._map_press_position.distance_to(point) < .1, "Resized desktop pointer keeps correct game coordinates")
	motion(point + Vector2(-170, -85), Vector2(-170, -85))
	button(point + Vector2(-170, -85), false)
	check(game.map_pan.distance_to(before) > 100, "Drag works after desktop resize")
	await snapshot("resized-drag")
	# Buttons also travel through the viewport, including their drawn hit rects.
	button(Vector2(-35, 34), true)
	button(Vector2(-35, 34), false)
	check(is_equal_approx(game.map_zoom, game._fit_map_zoom()), "Overview button receives resized-window input")
	await frame()
	button(Vector2(-35, 34), true)
	button(Vector2(-35, 34), false)
	check(game.map_zoom > game._fit_map_zoom() + .2, "Explore button returns from overview after resize")
	# Panning out over the tutorial's controls must never leave a held gesture.
	game._begin_tutorial(false)
	await frame()
	button(point, true)
	motion(Vector2(710, 610), Vector2(10, 160))
	button(Vector2(710, 610), false)
	check(not game._map_press_pending and not game.map_dragging, "Tutorial panel cannot swallow the camera's mouse release")
	before = game.map_pan
	motion(point, Vector2(-10, -160))
	check(game.map_pan == before, "Mouse movement after tutorial release never drags by itself")
	game._end_tutorial(false, false)
	var log := FileAccess.open("res://test_output/navigation-%s.json" % label, FileAccess.WRITE)
	log.store_string(JSON.stringify({"evidence": evidence, "failures": failures}, "\t"))
	log.close()
	game._stop_capture()
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: real viewport drag, stable overview, minimap, explicit zoom and resized-window input")
	else:
		for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
