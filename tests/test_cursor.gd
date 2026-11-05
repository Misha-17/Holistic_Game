extends SceneTree

# Andrei (30.10): over a button the cursor flickered between the hand and the
# arrow. _update_visibility() runs every frame and reset the cursor to ARROW on
# every menu screen. Only the end of a map drag may reset it.
# Needs a display (headless Godot does not track the cursor shape):
# Run: godot --path . -s tests/test_cursor.gd
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	for menu: String in ["title", "campaign", "settings", "results"]:
		game.screen = menu
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		game._update_visibility()
		check(Input.get_current_cursor_shape() == Input.CURSOR_POINTING_HAND, "The per-frame refresh keeps the hand cursor on " + menu)
	game.screen = "game"
	game.map_dragging = true
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	game._reset_map_gesture()
	check(Input.get_current_cursor_shape() == Input.CURSOR_ARROW, "Ending a map drag restores the arrow")
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: menu refresh no longer resets the button cursor; drags still restore the arrow")
	quit(0 if failures.is_empty() else 1)
