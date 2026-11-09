extends SceneTree

# Playtest 07.11: "Some levels seem to finish sooner than they should. On
# level 6, 2 disasters needed solving and 30 seconds remained when one of them
# got resolved and then the level ended."
# Cause: once the last scheduled call had arrived and no call was open, the
# level ended at once ("Every call handled • shift complete"), up to ~40 s
# early. Now every level runs its full time; the team is only told that nothing
# is left to do.
# Run: godot --headless --path . -s tests/test_level_full_time.gd

const Sim = preload("res://scripts/simulation.gd")
const SimTests = preload("res://tests/test_simulation.gd")

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	var bot = SimTests.new()
	for shift in range(1, 6):
		var sim := Sim.new()
		sim.start_shift(shift)
		var next := 2.0
		var all_clear_at := -1.0
		var all_clear_count := 0
		var research_rows := 0
		while sim.running:
			if sim.elapsed >= next:
				bot._bot_action(sim)
				next += 0.5
			sim.tick(0.1)
			for event in sim.drain_events():
				if event.type == "all_clear":
					all_clear_count += 1
					all_clear_at = float(event.at)
				if event.type == "all_calls_handled": research_rows += 1
				check(event.type != "shift_ended_early", "level %d: no early end event" % (shift + 1))
		check(sim.elapsed >= sim.duration - 0.001, "level %d ran its full %d s (ended at %.1f)" % [shift + 1, int(sim.duration), sim.elapsed])
		if all_clear_at >= 0.0:
			check(all_clear_count == 1 and research_rows == 1, "level %d: 'every call handled' is said once and logged once" % (shift + 1))
			check(all_clear_at < sim.duration, "level %d: the team is told when nothing is left (%.1f s)" % [shift + 1, all_clear_at])
		check(sim.won, "level %d is still winnable by the bot" % (shift + 1))
	if failures.is_empty(): print("PASS: every level runs its full time; 'every call handled' only informs the team")
	quit(0 if failures.is_empty() else 1)
