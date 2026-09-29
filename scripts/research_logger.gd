extends Node
class_name ResearchLogger







signal consent_changed(enabled: bool)
signal log_error(message: String)
signal support_cue_changed(cue: String)

const LOG_DIRECTORY := "user://research"
const SCHEMA_VERSION := 1
const POINTER_SAMPLE_MS := 250
const RECENT_WINDOW_MS := 60000

var enabled := false
var voice_enabled := false
var session_id := ""
var log_path := ""

var _file: FileAccess
var _context: Dictionary = {}
var _session_start_ms := 0
var _event_count := 0
var _click_count := 0
var _pointer_distance := 0.0
var _pointer_batch_distance := 0.0
var _last_pointer_record_ms := 0
var _last_click_ms := -1
var _last_flush_ms := 0
var _last_context_record_ms := -1000
var _last_recorded_context: Dictionary = {}
var _inspections: Dictionary = {}
var _incident_seen_ms: Dictionary = {}
var _incident_responded: Dictionary = {}
var _latencies: Array[float] = []
var _repeat_inspections := 0
var _recent_repeats: Array[int] = []
var _recent_latencies: Array[Dictionary] = []
var _last_support_cue := "Steady"
var _shift_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_enabled(value: bool) -> void:
	if value == enabled:
		return
	if value:
		_start_session()
	else:
		if _file != null:
			_write("consent_withdrawn", {"summary": get_summary()})
			_file.flush()
			_file.close()
			_file = null
		enabled = false
		voice_enabled = false
		_context.clear()
		_last_recorded_context.clear()
		consent_changed.emit(false)


func log_event(event_type: String, data: Dictionary = {}) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_msec()
	var id: int = int(data.get("incident_id", data.get("id", -1)))
	if event_type in ["incident_spawned", "incident_created", "incident"] and id >= 0:
		_incident_seen_ms[id] = now
	if event_type in ["dispatch", "unit_dispatched", "response"] and id >= 0:
		_record_response(id, now)
	_write(event_type, data)


func log_pointer(pos: Vector2, delta: Vector2) -> void:
	if not enabled:
		return
	var distance := delta.length()
	_pointer_distance += distance
	_pointer_batch_distance += distance
	var now := Time.get_ticks_msec()
	if now - _last_pointer_record_ms < POINTER_SAMPLE_MS:
		return
	_last_pointer_record_ms = now
	_write("pointer", {"x": snappedf(pos.x, 1.0), "y": snappedf(pos.y, 1.0),
		"distance_px": snappedf(_pointer_batch_distance, 0.1)})
	_pointer_batch_distance = 0.0


func log_click(pos: Vector2) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_msec()
	_click_count += 1
	var gap: Variant = null if _last_click_ms < 0 else now - _last_click_ms
	_last_click_ms = now
	_write("click", {"x": snappedf(pos.x, 1.0), "y": snappedf(pos.y, 1.0),
		"inter_click_ms": gap})


func log_inspection(incident_id: int) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_msec()
	var count := int(_inspections.get(incident_id, 0)) + 1
	_inspections[incident_id] = count
	if count > 1:
		_repeat_inspections += 1
		_recent_repeats.append(now)
	var data: Dictionary = {"incident_id": incident_id, "lookup_count": count,
		"repeat_lookup": count > 1}
	if _incident_seen_ms.has(incident_id):
		data["since_incident_ms"] = now - int(_incident_seen_ms[incident_id])
	_write("inspection", data)


func update_context(data: Dictionary) -> void:
	if not enabled:
		return
	_context.merge(_sanitize(data), true)
	
	var now := Time.get_ticks_msec()
	if now - _last_context_record_ms >= 1000 and _context != _last_recorded_context:
		_write("context", _context)
		_last_recorded_context = _context.duplicate(true)
		_last_context_record_ms = now
	var cue := _calculate_support_cue()
	if cue != _last_support_cue:
		_last_support_cue = cue
		support_cue_changed.emit(cue)
		_write("support_cue", {"cue": cue, "validated": false,
			"description": "Workload context heuristic; not a stress or fatigue diagnosis."})


func end_shift(ratings: Dictionary = {}) -> void:
	if not enabled:
		return
	_shift_count += 1
	
	_write("shift_end", {"shift_index": _shift_count, "self_report": _sanitize(ratings),
		"summary": get_summary()})
	if _file != null:
		_file.flush()
	
	_recent_repeats.clear()
	_recent_latencies.clear()
	_inspections.clear()
	_incident_seen_ms.clear()
	_incident_responded.clear()


func get_summary() -> Dictionary:
	var total_latency := 0.0
	for latency in _latencies:
		total_latency += latency
	return {
		"enabled": enabled,
		"local_only": true,
		"session_id": session_id,
		"log_path": log_path,
		"event_count": _event_count,
		"clicks": _click_count,
		"pointer_distance_px": snappedf(_pointer_distance, 0.1),
		"mean_response_latency_ms": snappedf(total_latency / maxf(1.0, _latencies.size()), 1.0),
		"response_samples": _latencies.size(),
		"repeated_inspections": _repeat_inspections,
		"support_cue": _calculate_support_cue() if enabled else "Research off",
		"pressure_score": _pressure_score() if enabled else 0.0,
		"inference_validated": false,
		"voice_capture_available": false,
		"duration_seconds": (Time.get_ticks_msec() - _session_start_ms) / 1000.0 if enabled else 0.0,
	}


func set_voice_enabled(_value: bool) -> void:
	
	voice_enabled = false
	if _value:
		log_error.emit("Voice capture is not included in this POC. No microphone is active.")


func _start_session() -> void:
	var error := DirAccess.make_dir_recursive_absolute(LOG_DIRECTORY)
	if error != OK and error != ERR_ALREADY_EXISTS:
		log_error.emit("Could not create the local research folder.")
		return
	_session_start_ms = Time.get_ticks_msec()
	var random_id := Crypto.new().generate_random_bytes(6).hex_encode()
	session_id = "%s_%s" % [str(int(Time.get_unix_time_from_system())), random_id]
	log_path = "%s/session_%s.jsonl" % [LOG_DIRECTORY, session_id]
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		log_error.emit("Could not open the local research log.")
		return
	_event_count = 0
	_click_count = 0
	_pointer_distance = 0.0
	_pointer_batch_distance = 0.0
	_repeat_inspections = 0
	_shift_count = 0
	_last_click_ms = -1
	_last_pointer_record_ms = 0
	_last_context_record_ms = -1000
	_context.clear()
	_last_recorded_context.clear()
	_inspections.clear()
	_incident_seen_ms.clear()
	_incident_responded.clear()
	_latencies.clear()
	_recent_repeats.clear()
	_recent_latencies.clear()
	enabled = true
	_write("consent_granted", {"local_only": true, "voice": false,
		"support_cues_validated": false,
		"signals": ["pointer_distance", "click_timing", "response_latency", "repeat_inspection", "game_context", "optional_self_report"]})
	_file.flush()
	consent_changed.emit(true)


func _record_response(incident_id: int, now: int) -> void:
	if not _incident_seen_ms.has(incident_id) or _incident_responded.has(incident_id):
		return
	var latency := float(now - int(_incident_seen_ms[incident_id]))
	_latencies.append(latency)
	_recent_latencies.append({"time": now, "latency": latency})
	_incident_responded[incident_id] = true
	_write("response_latency", {"incident_id": incident_id, "latency_ms": latency})


func _pressure_score() -> float:
	var cutoff := Time.get_ticks_msec() - RECENT_WINDOW_MS
	while not _recent_repeats.is_empty() and _recent_repeats[0] < cutoff:
		_recent_repeats.pop_front()
	while not _recent_latencies.is_empty() and int(_recent_latencies[0]["time"]) < cutoff:
		_recent_latencies.pop_front()
	var active := float(_context.get("active_incidents", _context.get("pending", 0)))
	var urgent := float(_context.get("urgent_incidents", _context.get("urgent", 0)))
	var latency := 0.0
	for sample in _recent_latencies:
		latency += float(sample["latency"])
	latency /= maxf(1.0, _recent_latencies.size())
	
	return clampf(active * 0.10 + urgent * 0.11 + minf(0.12, _recent_repeats.size() * 0.018)
		+ minf(0.16, latency / 90000.0), 0.0, 1.0)


func _calculate_support_cue() -> String:
	var pressure := _pressure_score()
	if pressure >= 0.70:
		return "Focus one call"
	if pressure >= 0.38:
		return "Check priorities"
	return "Steady"


func _write(event_type: String, data: Dictionary) -> void:
	if not enabled or _file == null:
		return
	_event_count += 1
	var now := Time.get_ticks_msec()
	var record := {"schema": SCHEMA_VERSION, "session_id": session_id,
		"sequence": _event_count, "elapsed_ms": now - _session_start_ms,
		"utc": Time.get_datetime_string_from_system(true), "event": event_type,
		"data": _sanitize(data)}
	_file.store_line(JSON.stringify(record))
	if now - _last_flush_ms >= 2000:
		_file.flush()
		_last_flush_ms = now


func _sanitize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			
			if str(key).to_lower() in ["chat", "message", "name", "player_name", "email", "ip", "address", "transcript"]:
				continue
			result[str(key)] = _sanitize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_sanitize(item))
		return result
	if value is Vector2 or value is Vector2i:
		return {"x": value.x, "y": value.y}
	if value is String or value is StringName:
		return str(value).left(240)
	if value == null or value is bool or value is int or value is float:
		return value
	return str(value).left(100)


func _exit_tree() -> void:
	if enabled and _file != null:
		_write("session_end", {"summary": get_summary()})
		_file.flush()
		_file.close()
		_file = null
