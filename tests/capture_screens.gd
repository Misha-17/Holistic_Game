extends SceneTree

var game: Node

func _initialize() -> void:
	call_deferred("run")

func snap(filename: String) -> void:
	game._process(0)
	game.tactical_map.refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_output/" + filename + ".png")

func button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.get_final_transform() * (at + game.global_position)
	event.global_position = event.position
	Input.parse_input_event(event)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://test_output")
	game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game._begin_shift(0)
	game.toast_left = 0
	await snap("game-v8")
	button(Vector2(700, 450), true)
	var drag := InputEventMouseMotion.new()
	drag.position = root.get_final_transform() * (Vector2(900, 570) + game.global_position)
	drag.global_position = drag.position
	drag.relative = root.get_final_transform().basis_xform(Vector2(200, 120))
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(drag)
	button(Vector2(900, 570), false)
	await snap("dragged-v8")
	game._toggle_overview()
	await snap("overview-v8")
	var at: Vector2 = game.MINIMAP_RECT.position + game.MINIMAP_RECT.size * Vector2(.82, .8)
	for pressed in [true, false]:
		button(at, pressed)
	await snap("minimap-v8")
	game.sim.tick(48)
	game.sim.drain_events()
	var active: Array = game._active_incidents()
	if not active.is_empty():
		game._select_incident(int(active[0].id))
		game._center_map(active[0].pos)
	await snap("calls-v8")
	game._zoom_map(1.0, game.MAP_VIEW.get_center())
	await snap("zoom-v8")
	game.previous_screen = "game"
	game.screen = "settings"
	await snap("settings-v8")
	game.screen = "lobby"
	await snap("lobby-v8")
	game.screen = "title"
	await snap("title-v8")
	game._begin_tutorial(false)
	await snap("tutorial-v8")
	game._end_tutorial(false, false)
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	quit()
