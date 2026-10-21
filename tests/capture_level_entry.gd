extends SceneTree

var game: Node

func _initialize() -> void:
	call_deferred("run")

func snap(filename: String) -> void:
	game._process(0)
	game.toast_left = 0
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tools/level-entry/" + filename + ".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.tools/level-entry")
	game = load("res://scripts/main.gd").new()
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	game._begin_shift(BeaconCampaign.PRACTICE_INDEX)
	await snap("collection-choice")
	game._choose_collection(false)
	for role in game.ROLE_BRIEFINGS:
		game.briefing_role = role
		await snap("briefing-" + role)
	game._complete_briefing()
	await snap("training-harbor")
	game.sim.tick(65)
	game.sim.drain_events()
	await snap("training-events")
	game.sim.tick(85)
	game.sim.drain_events()
	game._finish_shift()
	await snap("practice-results")
	game.test_mode = true
	game.screen = "campaign"
	game.unlocked = 0
	game.best_scores = {}
	game.has_resume = false
	await snap("level-picker")
	game.unlocked = 2
	game.best_scores = {"0": 1200, "1": 1600}
	game.has_resume = true
	await snap("level-picker-returning")
	game._stop_capture()
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	quit()
