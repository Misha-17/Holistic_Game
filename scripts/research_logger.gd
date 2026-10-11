class_name ResearchLogger
extends Node

## Local player observations only. No classifier or audio capture.
signal consent_changed(enabled: bool)
signal log_error(message: String)
const LOG_DIRECTORY := "user://research"
const SCHEMA_VERSION := 2
const MAX_BUFFER_LINES := 128
var enabled := false
var session_id := ""
var log_path := ""
var _file: FileAccess
var _context: Dictionary = {}
var _buffer := PackedStringArray()
var _session_start_us := 0
var _event_count := 0
var _click_count := 0
var _pointer_distance := 0.0
var _last_click_us := -1
var _last_flush_ms := 0
var _last_context_ms := 0
var _shift_elapsed := 0.0
var _shift_index := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if enabled and Time.get_ticks_msec() - _last_flush_ms >= 1000: _flush()

func begin_session(run_id: String, metadata: Dictionary = {}) -> void:
	set_enabled(false)
	session_id = run_id.validate_filename()
	_context = metadata.duplicate(true)
	_open()

func set_enabled(value: bool) -> void:
	if value == enabled: return
	if value:
		session_id = "%d_%s" % [int(Time.get_unix_time_from_system()), Crypto.new().generate_random_bytes(6).hex_encode()]
		_open()
	else:
		_write("capture_stopped", get_summary())
		_flush()
		if _file != null: _file.close()
		_file = null
		enabled = false
		consent_changed.emit(false)

func _open() -> void:
	var err := DirAccess.make_dir_recursive_absolute(LOG_DIRECTORY)
	if err != OK and err != ERR_ALREADY_EXISTS:
		log_error.emit("Could not create the local recordings folder.")
		return
	log_path = "%s/%s_%d_events.jsonl" % [LOG_DIRECTORY, session_id, Time.get_ticks_usec()]
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		log_error.emit("Could not open the local mouse log.")
		return
	_session_start_us = Time.get_ticks_usec()
	_event_count = 0
	_click_count = 0
	_pointer_distance = 0.0
	_last_click_us = -1
	_buffer.clear()
	enabled = true
	_write("capture_started", {"local_only": true, "scope": "local_player_game_window", "motion": "every_delivered_event", "coordinates": "1600x900 viewport pixels", "context": _context})
	_flush()
	consent_changed.emit(true)

func set_clock(shift_elapsed: float, shift_index: int) -> void:
	_shift_elapsed = shift_elapsed
	_shift_index = shift_index

func log_pointer(pos: Vector2, delta: Vector2) -> void:
	if not enabled: return
	_pointer_distance += delta.length()
	_write("mouse_motion", {"x": pos.x, "y": pos.y, "dx": delta.x, "dy": delta.y, "distance_px": delta.length()})

func log_mouse_button(event: InputEventMouseButton) -> void:
	if not enabled: return
	var now := Time.get_ticks_usec()
	var gap: Variant = null
	if event.pressed:
		_click_count += 1
		if _last_click_us >= 0: gap = (now - _last_click_us) / 1000.0
		_last_click_us = now
	_write("mouse_button", {"x": event.position.x, "y": event.position.y,
		"button": event.button_index, "pressed": event.pressed, "double_click": event.double_click,
		"factor": event.factor, "inter_click_ms": gap})

func log_click(pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	log_mouse_button(event)

func log_event(event_type: String, data: Dictionary = {}) -> void:
	_write(event_type, data)

func log_inspection(incident_id: int) -> void:
	_write("inspection", {"incident_id": incident_id})

func update_context(data: Dictionary) -> void:
	_context.merge(data, true)
	if enabled and Time.get_ticks_msec() - _last_context_ms >= 1000:
		_write("context", _context)
		_last_context_ms = Time.get_ticks_msec()

func end_shift(ratings: Dictionary = {}) -> void:
	_write("shift_end", {"ratings": ratings, "summary": get_summary()})
	_flush()

func get_summary() -> Dictionary:
	return {"enabled": enabled, "session_id": session_id, "log_path": log_path,
		"events": _event_count, "clicks": _click_count, "pointer_distance_px": _pointer_distance, "local_only": true}

func _write(event_type: String, data: Dictionary) -> void:
	if not enabled or _file == null: return
	_event_count += 1
	var record := {"schema": SCHEMA_VERSION, "session_id": session_id, "sequence": _event_count,
		"local_elapsed_us": Time.get_ticks_usec() - _session_start_us,
		"utc": Time.get_datetime_string_from_system(true), "shift_index": _shift_index,
		"shift_elapsed_s": _shift_elapsed, "session_elapsed_s": _shift_index * 330.0 + _shift_elapsed,
		"event": event_type, "data": _sanitize(data)}
	_buffer.append(JSON.stringify(record))
	if _buffer.size() >= MAX_BUFFER_LINES: _flush()

func _flush() -> void:
	if _file == null or _buffer.is_empty(): return
	_file.store_string("\n".join(_buffer) + "\n")
	_file.flush()
	_buffer.clear()
	_last_flush_ms = Time.get_ticks_msec()
	if _file.get_error() != OK:
		_file.close()
		_file = null
		enabled = false
		log_error.emit("Mouse logging stopped: the local disk could not be written.")

func _sanitize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if str(key).to_lower() in ["chat", "message", "name", "player_name", "email", "ip", "address", "transcript"]: continue
			result[str(key)] = _sanitize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_sanitize(item))
		return result
	if value is Vector2 or value is Vector2i: return {"x": value.x, "y": value.y}
	if value is String or value is StringName: return str(value).left(500)
	if value == null or value is bool or value is int or value is float: return value
	return str(value).left(100)

func _exit_tree() -> void:
	set_enabled(false)
