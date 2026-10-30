extends SceneTree

# Andrei (30.10): "the disaster detail cards do not always close when pressing
# Esc", and settings opened during a level had no way back to the main menu.
# Run: godot --headless --path . -s tests/test_call_card_close.gd
var failures: Array[String] = []
var game

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func esc() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	game._input(key)

func card_expanded(id: int) -> bool:
	game.tactical_map.refresh()
	for item in game.tactical_map._calls:
		if int(item.incident.id) == id: return bool(item.expanded)
	return false

func make_call() -> Dictionary:
	game.sim._spawn_incident()
	var call: Dictionary = game.sim.incidents.back()
	call.discovered = true
	return call

func busy_crew() -> Dictionary:
	for unit: Dictionary in game.sim.units:
		if str(unit.kind) == "fire": return unit
	return {}

func button_ids() -> Array:
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	return game.buttons.map(func(b): return str(b.id))

func run() -> void:
	game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game._begin_shift(1)
	game.screen = "game"
	var call := make_call()
	var id := int(call.id)

	# 1. A crew is selected as well: one Esc closes the card (and the crew).
	game.selected_unit = int(busy_crew().id)
	game.selected = id
	game._process(0.0)
	esc()
	check(game.selected == -1 and game.selected_unit == -1, "One Esc closes the card even with a crew selected")
	check(game.screen == "game", "That Esc does not open the pause menu")

	# 2. Mouse still over the call: its hover preview stays closed after Esc.
	game.selected = id
	game._process(0.0)
	game.tactical_map.hovered_incident_id = id
	esc()
	game._process(0.0)
	check(not card_expanded(id), "The card under the mouse stays closed after Esc")
	esc()
	check(game.screen == "pause", "The next Esc opens the pause menu")
	game._action("unpause")
	game.tactical_map.hovered_incident_id = -1
	game.tactical_map._update_hover(Vector2(-9999, -9999))
	check(game.tactical_map.dismissed_incident_id == -1, "Moving off the call re-enables its hover preview")

	# 3. A just-resolved call's close-up is cancelled by Esc.
	game.selected = id
	game.focus_hold_id = id
	game.focus_hold_left = 2.2
	esc()
	check(game.focus_hold_left == 0.0 and game.selected == -1, "Esc also ends the resolved-call close-up")

	# 4. The card's CLOSE button closes the card but keeps a selected crew.
	game.selected_unit = int(busy_crew().id)
	game.selected = id
	game.tactical_map.close_requested.emit()
	check(game.selected == -1 and game.selected_unit == int(busy_crew().id), "CLOSE closes the card and keeps the crew")
	game.selected_unit = -1

	# 5. Settings opened from the pause menu has a way to the main menu.
	game._action("pause")
	game._action("pause_settings")
	check(game.screen == "settings" and game.previous_screen == "pause", "Settings opens from the pause menu")
	check((await button_ids()).has("save_exit"), "Settings during a level has a MAIN MENU button")
	game._action("save_exit")
	check(game.screen == "title", "It returns to the main menu")
	# 6. After a level: MAIN MENU on the results screen and in its settings.
	game._begin_shift(1)
	game.sim.running = false
	game.screen = "results"
	check((await button_ids()).has("results_title"), "The results screen has a MAIN MENU button")
	game._action("results_settings")
	check((await button_ids()).has("results_title"), "Settings opened from results also has MAIN MENU")
	game._action("settings_back")
	game._action("results_title")
	check(game.screen == "title", "MAIN MENU on the results screen returns to the title")
	game.previous_screen = "title"
	game._action("settings")
	game.screen = "settings"
	check(not (await button_ids()).has("save_exit"), "Settings from the title has no MAIN MENU button")

	game._stop_capture()
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: Esc closes call cards in one press (crew selected, mouse over it, close-up); settings during a level and the results screen can leave to the main menu")
	quit(0 if failures.is_empty() else 1)
