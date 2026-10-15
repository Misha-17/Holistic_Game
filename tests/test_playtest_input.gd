extends SceneTree

# Input fixes from the 4-player playtest (15.10):
#  - with a crew selected, clicking a "?" call opens its card (with a SCOUT
#    button) but sends nobody, and the crew stays selected;
#  - a moving vehicle on top of a call does not steal the click;
#  - the drag view is the only zoomed view; levels start on the whole town.
# Run: godot --headless --path . -s tests/test_playtest_input.gd
var failures: Array[String] = []
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func run() -> void:
	game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game._begin_shift(0)
	check(game._is_map_overview(), "Levels start on the whole town")
	game.map_zoom = game._drag_zoom()
	game._center_map(Vector2(.5, .5))
	game.sim._spawn_incident()
	var call: Dictionary = game.sim.incidents.back()
	call.pos = Vector2(.5, .5)
	call.needs = {"medic": 1, "fire": 0, "engineer": 0, "police": 0}
	call.discovered = false
	var medic: Dictionary = {}
	for unit: Dictionary in game.sim.units:
		if unit.kind == "medic":
			medic = unit
			break
	game.selected_unit = int(medic.id)
	game._select_incident(int(call.id))
	check(game.sim.successful_dispatches == 0, "A crew is never sent to an unconfirmed call")
	check(game.selected_unit == int(medic.id), "The crew stays selected after clicking a '?' call")
	check(game.selected == int(call.id), "The '?' call's card opens")
	game._process(0)
	game.tactical_map.refresh()
	var scout_hit: Dictionary = {}
	for hit: Dictionary in game.tactical_map.hit_regions():
		if hit.type == "scout" and int(hit.id) == int(call.id): scout_hit = hit
	check(not scout_hit.is_empty(), "The card of a '?' call has a SCOUT button")
	if not scout_hit.is_empty():
		game.tactical_map.activate_target(scout_hit)
		check(bool(call.discovered), "The SCOUT button reveals the call")
		check(game.selected_unit == int(medic.id), "Scouting keeps the crew selected")
	# Now confirmed: a vehicle driving over the call must not steal the click.
	var fire: Dictionary = game.sim.units[0]
	fire.state = "return"
	fire.pos = call.pos + Vector2(0, -39) / (game._map_rect().size)
	game.selected = -1
	game.tactical_map.selected_id = -1
	game._process(0)
	game.tactical_map.refresh()
	var call_rect: Rect2 = game.tactical_map.call_hit_rect(int(call.id))
	var unit_rect: Rect2 = game.tactical_map.unit_hit_rect(int(fire.id))
	check(call_rect.intersects(unit_rect), "Test setup: the vehicle overlaps the call marker")
	var spot: Vector2 = call_rect.intersection(unit_rect).get_center()
	var hit: Dictionary = game.tactical_map.pointer_target(game.tactical_map.get_global_transform_with_canvas() * spot)
	check(str(hit.get("type", "")) == "call", "A click on a call under a moving vehicle goes to the call (got %s)" % str(hit.get("type", "")))
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: no sending to '?' calls, scout button, vehicles don't steal clicks, whole-town start")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
