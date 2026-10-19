extends SceneTree

# Playtest 19.10: four crews per department in every level, a scout cooldown
# counter, and a SETTINGS button on the results screen (between levels).
# The multiplayer route triangle has its own suite: test_remote_route.gd.
# Run: godot --headless --path . -s tests/test_playtest_19_10.gd
const Sim = preload("res://scripts/simulation.gd")
const Campaign = preload("res://scripts/campaign.gd")
var failures: Array[String] = []
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func test_four_crews() -> void:
	for shift in range(6):
		check(Campaign.crews_per_department(shift) == 4, "Level %d: four crews per department" % (shift + 1))
		var sim := Sim.new()
		sim.start_shift(shift)
		var counts := {"fire": 0, "medic": 0, "engineer": 0, "police": 0}
		for unit: Dictionary in sim.units: counts[unit.kind] += 1
		for kind in counts:
			check(int(counts[kind]) == 4, "Level %d: %s has %d crews, expected 4" % [shift + 1, kind, counts[kind]])
		# No two crews of a department share a parking spot.
		var spots: Dictionary = {}
		for unit: Dictionary in sim.units: spots[unit.home] = true
		check(spots.size() == sim.units.size(), "Level %d: every crew has its own spot" % (shift + 1))

func test_scout_counter() -> void:
	game._begin_shift(1)
	game.sim._spawn_incident()
	var call: Dictionary = game.sim.incidents.back()
	call.discovered = false
	check(game.sim.scout_cooldown == 0.0, "Field team starts ready")
	check(game.sim.scout(int(call.id)), "Scouting works")
	check(is_equal_approx(game.sim.scout_cooldown, game.sim.scout_cooldown_total()), "Cooldown starts at the full %.0f s" % game.sim.scout_cooldown_total())
	check(game.sim.scout_cooldown_total() == 8.0, "Scout cooldown is 8 s")
	# The counter is drawn while cooling down and when ready (no script errors).
	game.screen = "game"
	game._process(0)
	game.hud.queue_redraw()
	for i in 30: game.sim.tick(0.1)
	check(absf(game.sim.scout_cooldown - 5.0) < 0.05, "About 5 s left after 3 s")
	for i in 55: game.sim.tick(0.1)
	check(game.sim.scout_cooldown == 0.0, "Field team ready again")

func test_results_settings() -> void:
	# Solo: SETTINGS from the results screen, BACK returns to it.
	game.network.active = false
	game.network.hosting = false
	game.screen = "results"
	game._action("results_settings")
	check(game.screen == "settings" and game.previous_screen == "results", "SETTINGS opens from the results screen")
	game._action("settings_back")
	check(game.screen == "results", "BACK returns to the results screen")

	# Guest: host snapshots on the results screen don't close the guest's settings,
	# and the next level still pulls the guest into the game.
	game._begin_shift(0)
	game.sim.running = false
	game.sim.finished = true
	game.screen = "results"
	game._action("results_settings")
	var payload: Dictionary = {"screen": "results", "simulation": game.sim.net_snapshot(), "orders": {}, "speed": 1.0}
	game._receive_snapshot(payload)
	check(game.screen == "settings", "Host results snapshots keep a guest's settings open")
	var next := Sim.new()
	next.start_shift(1)
	game._receive_snapshot({"screen": "game", "simulation": next.net_snapshot(), "orders": {}, "speed": 1.0})
	check(game.screen == "game", "The next level takes the guest out of settings")

	# Host: roles can still be swapped while the host has settings open after a level.
	game.network.active = true
	game.network.hosting = true
	game.network.dedicated = false
	game.network.roster = {1: 0, 44: 1}
	game.network.role_assignments = {}
	game.network.player_names = {1: "Robin", 44: "Elio"}
	game.sim.running = false
	game.screen = "settings"
	game.previous_screen = "results"
	var before: Array = game.network.departments_for(1)
	game._execute_command("change_role", {"target_peer_id": 44}, 1)
	check(game.network.departments_for(1) != before, "Role swap works from settings opened between levels")
	game.network.active = false
	game.network.hosting = false
	game.network.roster = {}

func test_settings_tabs_and_layout() -> void:
	# Settings are grouped into three tabs; the volume sliders show only on Sounds.
	check(game.settings_tab == "sounds", "Settings open on the Sounds tab")
	game.screen = "settings"
	game.previous_screen = "results"
	for tab in ["sounds", "video", "research"]:
		game._action("settings_tab:" + tab)
		game._update_visibility()
		check(game.settings_tab == tab, "Tab %s opens" % tab)
		check(game.sound_settings.visible == (tab == "sounds"), "Volume sliders only on Sounds (%s)" % tab)
	var perf: bool = game.show_perf
	game._action("toggle:perf")
	check(game.show_perf != perf, "Video: FPS and ping toggles")
	game._action("toggle:perf")
	# Results screen: one centred group, three equally wide buttons.
	for co_op in [false, true]:
		game.network.active = co_op
		var panel: Rect2 = game._results_rect()
		var group_end: float = panel.end.x + ((game.RESULTS_GAP + game.ROLES_WIDTH) if co_op else 0.0)
		check(absf((panel.position.x + group_end) / 2.0 - game.VIEW.get_center().x) < 0.5, "Results group centred (co-op %s)" % co_op)
	game.network.active = false

func run() -> void:
	game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	test_four_crews()
	test_scout_counter()
	test_results_settings()
	test_settings_tabs_and_layout()
	game._stop_capture()
	game.voice.shutdown()
	game.network.close()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: four crews per department in every level, scout cooldown counter, settings between levels")
	quit(0 if failures.is_empty() else 1)
