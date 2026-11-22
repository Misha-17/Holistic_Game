class_name ResearchSampler
extends RefCounted

## Fixed-rate sample stream (client feedback 01.11: "a static recording frequency
## even if nothing happened between two records").
##
## Mouse events reach the game once per rendered frame, so event rows inherit
## each PC's frame rate (playtest 22.10: 28-36 fps on two PCs, 67-82 fps on the
## other two, and every PC slowed down as calls piled up). This sampler runs on
## its own thread and reads the cursor from the operating system on a fixed
## 60 Hz grid, whatever the frame rate. Game state (selection, task load) is
## the latest state the main thread published; `frame_age_ms` says how old it
## was when the cursor was read.
##
## One CSV row per grid slot: row count = duration x 60. A slot the thread could
## not read in time (`held` = 1) repeats the previous cursor reading.

const RATE_HZ := 60
const FLUSH_ROWS := 30
const MAX_EXTRAPOLATE_S := 1.0

## Columns before the task-load block (BeaconTaskLoad.KEYS follow them).
const BASE_COLUMNS: Array[String] = ["segment", "sample", "local_elapsed_us", "unix_ms", "level_elapsed_s",
	"read_late_us", "held", "x", "y", "in_window", "buttons", "window_focused", "frame_age_ms",
	"frame_ms", "fps", "screen", "clock_running", "selected_incident_id", "selected_unit_id",
	"hover_type", "hover_id"]

var path := ""
var rows_written := 0
var _thread: Thread
var _mutex := Mutex.new()
var _running := false
var _file: FileAccess
var _segment := 1
var _start_us := 0
var _session_start_us := 0
var _unix_at_start_ms := 0
var _slot := 0
var _frame: Dictionary = {}
var _mapping := {"window_pos": Vector2(), "to_view": Transform2D.IDENTITY, "window_size": Vector2(1600, 900)}
var _test_cursor: Variant = null
var _last_xy := Vector2(-1, -1)
var _last_buttons := 0
var _last_inside := 0
var _last_level_s := 0.0
var _stats := {"held": 0, "late_over_4ms": 0, "late_max_us": 0, "rows": 0}
var _late_samples := PackedInt32Array()

static func columns() -> Array[String]:
	var all: Array[String] = BASE_COLUMNS.duplicate()
	all.append_array(BeaconTaskLoad.KEYS)
	return all

## Opens (or appends to) the CSV and starts the thread. session_start_us is the
## logger's monotonic origin, so `local_elapsed_us` matches the JSONL rows.
func start(csv_path: String, session_start_us: int, segment: int) -> bool:
	if _running: return true
	path = csv_path
	_session_start_us = session_start_us
	_segment = segment
	var existed := FileAccess.file_exists(path)
	_file = FileAccess.open(path, FileAccess.READ_WRITE if existed else FileAccess.WRITE)
	if _file == null: return false
	_file.seek_end()
	if not existed or _file.get_length() == 0: _file.store_line(",".join(columns()))
	_start_us = Time.get_ticks_usec()
	_unix_at_start_ms = int(Time.get_unix_time_from_system() * 1000.0)
	_slot = 0
	_last_level_s = 0.0
	_stats = {"held": 0, "late_over_4ms": 0, "late_max_us": 0, "rows": 0}
	_late_samples = PackedInt32Array()
	_running = true
	_thread = Thread.new()
	_thread.start(_run, Thread.PRIORITY_HIGH)
	return true

## Stops the thread, writes the remaining rows and returns run statistics.
func stop() -> Dictionary:
	if _thread == null: return stats()
	_mutex.lock()
	_running = false
	_mutex.unlock()
	_thread.wait_to_finish()
	_thread = null
	if _file != null:
		_file.flush()
		_file.close()
		_file = null
	return stats()

func is_running() -> bool:
	_mutex.lock()
	var value := _running
	_mutex.unlock()
	return value

## Main thread, once per frame: the newest game state for the following samples.
func publish_frame(state: Dictionary) -> void:
	state["frame_us"] = Time.get_ticks_usec()
	_mutex.lock()
	_frame = state
	_mutex.unlock()

## Main thread, once per frame: how window pixels map to the 1600x900 view.
## to_view converts a point in window client pixels to view coordinates (the
## space of the mouse_button rows).
func publish_mapping(window_pos: Vector2, to_view: Transform2D, window_size: Vector2) -> void:
	_mutex.lock()
	_mapping = {"window_pos": window_pos, "to_view": to_view, "window_size": window_size}
	_mutex.unlock()

## Tests run headless, where the operating system cursor is always (0, 0).
func set_test_cursor(screen_position: Variant) -> void:
	_mutex.lock()
	_test_cursor = screen_position
	_mutex.unlock()

func stats() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = _stats.duplicate()
	var late := _late_samples.duplicate()
	var elapsed_s := maxf(0.001, float(Time.get_ticks_usec() - _start_us) / 1e6)
	_mutex.unlock()
	result["rate_hz"] = RATE_HZ
	result["achieved_hz"] = float(result.rows) / elapsed_s if _start_us > 0 else 0.0
	result["held_share"] = float(result.held) / maxf(1.0, float(result.rows))
	if late.size() > 0:
		late.sort()
		result["late_p50_us"] = late[late.size() / 2]
		result["late_p95_us"] = late[mini(late.size() - 1, int(late.size() * 0.95))]
	result["path"] = path
	return result

func _due_us(slot: int) -> int:
	return _start_us + int(round(float(slot) * 1000000.0 / RATE_HZ))

func _run() -> void:
	var lines := PackedStringArray()
	while true:
		_mutex.lock()
		var go := _running
		_mutex.unlock()
		if not go: break
		var now := Time.get_ticks_usec()
		var due := _due_us(_slot)
		if now < due:
			OS.delay_usec(due - now)
			continue
		# Slots that passed while the thread was not scheduled are written as held.
		while _due_us(_slot + 1) <= now:
			lines.append(_row(_slot, _due_us(_slot), now, true))
			_slot += 1
		lines.append(_row(_slot, due, now, false))
		_slot += 1
		if lines.size() >= FLUSH_ROWS:
			_file.store_string("\n".join(lines) + "\n")
			lines.clear()
	if not lines.is_empty() and _file != null: _file.store_string("\n".join(lines) + "\n")

func _row(slot: int, due_us: int, read_us: int, held: bool) -> String:
	_mutex.lock()
	var frame: Dictionary = _frame
	var mapping: Dictionary = _mapping
	var test_cursor: Variant = _test_cursor
	_mutex.unlock()
	var late := read_us - due_us
	if not held:
		var screen_pos: Vector2 = Vector2(test_cursor) if test_cursor != null else Vector2(DisplayServer.mouse_get_position())
		var window_px: Vector2 = screen_pos - Vector2(mapping.window_pos)
		var size: Vector2 = mapping.window_size
		_last_inside = 1 if window_px.x >= 0 and window_px.y >= 0 and window_px.x < size.x and window_px.y < size.y else 0
		_last_xy = Transform2D(mapping.to_view) * window_px
		_last_buttons = Input.get_mouse_button_mask()
	var frame_us := int(frame.get("frame_us", 0))
	var frame_age_ms := (read_us - frame_us) / 1000.0 if frame_us > 0 else -1.0
	var level_s := float(frame.get("level_elapsed_s", 0.0))
	if bool(frame.get("clock_running", false)) and frame_us > 0:
		level_s += minf(MAX_EXTRAPOLATE_S, float(due_us - frame_us) / 1e6) * float(frame.get("clock_rate", 1.0))
	# Like the JSONL level clock, the sampled clock never moves backwards: a frame
	# that lands slightly behind the extrapolation (or a host correction) holds it.
	level_s = maxf(level_s, _last_level_s)
	_last_level_s = level_s
	var values: Array = [_segment, slot, due_us - _session_start_us,
		_unix_at_start_ms + int((due_us - _start_us) / 1000), "%.4f" % maxf(0.0, level_s),
		late if not held else -1, 1 if held else 0, "%.1f" % _last_xy.x, "%.1f" % _last_xy.y, _last_inside, _last_buttons,
		1 if bool(frame.get("window_focused", true)) else 0, "%.1f" % frame_age_ms,
		"%.1f" % float(frame.get("frame_ms", 0.0)), "%.1f" % float(frame.get("fps", 0.0)), str(frame.get("screen", "")),
		1 if bool(frame.get("clock_running", false)) else 0, int(frame.get("selected_incident_id", -1)),
		int(frame.get("selected_unit_id", -1)), str(frame.get("hover_type", "")), int(frame.get("hover_id", -1))]
	var load: Dictionary = frame.get("task_load", {})
	for key: String in BeaconTaskLoad.KEYS:
		var value: Variant = load.get(key, 0)
		values.append("%.2f" % value if value is float else str(value))
	_mutex.lock()
	_stats.rows += 1
	if held: _stats.held += 1
	else:
		if late > 4000: _stats.late_over_4ms += 1
		_stats.late_max_us = maxi(int(_stats.late_max_us), late)
		if _late_samples.size() < 200000: _late_samples.append(late)
	_mutex.unlock()
	return ",".join(values.map(func(v): return str(v)))
