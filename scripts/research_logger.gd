class_name ResearchLogger
extends Node

## The session stream is authoritative; per-level files mirror its sequence IDs.
signal consent_changed(enabled: bool)
signal log_error(message: String)
const LOG_DIRECTORY := "user://research"
const SCHEMA_VERSION := 3
const MAX_BUFFER_LINES := 128
var enabled := false
var session_id := ""
var log_path := ""
var _file: FileAccess
var _level_file: FileAccess
var _context: Dictionary = {}
var _level: Dictionary = {}
var _levels: Array[Dictionary] = []
var _attempts: Dictionary = {}
var _active_events: Dictionary = {}
var _closed_events: Dictionary = {}
var _buffer := PackedStringArray()
var _level_buffer := PackedStringArray()
var _session_start_us := 0
var _event_count := 0
var _click_count := 0
var _pointer_distance := 0.0
var _level_clicks := 0
var _level_pointer_distance := 0.0
var _last_click_us := -1
var _last_flush_ms := 0
var _last_context_ms := 0
var _shift_elapsed := 0.0
var _shift_index := 0
var _completed_level_elapsed := 0.0
var _capture_segment := 0
var _disabled_at_us := -1
var _disabled_level_elapsed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if enabled and Time.get_ticks_msec() - _last_flush_ms >= 1000: _flush()

func begin_session(run_id: String, metadata: Dictionary = {}) -> void:
	var requested_id := run_id.validate_filename()
	if requested_id.is_empty(): requested_id = _new_id("session")
	if requested_id != session_id:
		if enabled:
			end_level("session_ended")
			set_enabled(false)
		session_id = requested_id
		_context = metadata.duplicate(true)
		_level = {}
		_levels.clear()
		_attempts.clear()
		_active_events.clear()
		_closed_events.clear()
		_session_start_us = Time.get_ticks_usec()
		_event_count = 0
		_click_count = 0
		_pointer_distance = 0.0
		_completed_level_elapsed = 0.0
		_capture_segment = 0
		_disabled_at_us = -1
		log_path = "%s/%s/session_events.jsonl" % [LOG_DIRECTORY, session_id]
	else:
		_context.merge(metadata, true)
	if not enabled: _open()

func set_enabled(value: bool) -> void:
	if value == enabled: return
	if value:
		begin_session(session_id if not session_id.is_empty() else _new_id("session"), _context)
	else:
		_write("capture_stopped", {"reason": "collection_disabled", "summary": get_summary()})
		_flush()
		_write_manifest()
		_close_files()
		enabled = false
		_disabled_at_us = Time.get_ticks_usec()
		_disabled_level_elapsed = _shift_elapsed
		consent_changed.emit(false)

func _open() -> void:
	var directory := "%s/%s/levels" % [LOG_DIRECTORY, session_id]
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK and err != ERR_ALREADY_EXISTS:
		log_error.emit("Could not create the local research folder.")
		return
	_file = _open_append(log_path)
	if _file == null:
		log_error.emit("Could not open the local research log.")
		return
	if not _level.is_empty():
		_level_file = _open_append(str(_level.log_path))
		if _level_file == null:
			_fail_write()
			return
	_buffer.clear()
	_level_buffer.clear()
	_last_click_us = -1
	_capture_segment += 1
	enabled = true
	_write("capture_started" if _capture_segment == 1 else "capture_resumed", {
		"local_only": true, "scope": "local_player_game_window", "motion": "every_delivered_event",
		"coordinates": "1600x900 viewport pixels", "context": _context,
		"gap_wall_us": Time.get_ticks_usec() - _disabled_at_us if _disabled_at_us >= 0 else 0,
		"gap_level_start_s": _disabled_level_elapsed if _disabled_at_us >= 0 else null,
		"gap_level_end_s": _shift_elapsed if _disabled_at_us >= 0 else null})
	_flush()
	_write_manifest()
	if enabled: consent_changed.emit(true)

func begin_level(level_index: int, metadata: Dictionary = {}, level_run_id: String = "") -> void:
	if not enabled: return
	var run_id := level_run_id.validate_filename()
	if run_id.is_empty(): run_id = _new_id("level%d" % level_index)
	if not _level.is_empty() and str(_level.level_run_id) == run_id: return
	if not _level.is_empty(): end_level("level_changed")
	_shift_index = level_index
	_shift_elapsed = float(metadata.get("elapsed", metadata.get("level_elapsed_s", 0.0)))
	var level_number := int(metadata.get("level_number", metadata.get("level_id", level_index + 1)))
	var attempt := int(_attempts.get(str(level_number), 0)) + 1
	_attempts[str(level_number)] = attempt
	_level = {"level_id": level_number, "level_number": level_number, "level_index": level_index,
		"level_name": str(metadata.get("level_name", metadata.get("name", "Level %d" % level_number))),
		"level_run_id": run_id, "level_attempt": attempt,
		"log_path": "%s/%s/levels/%s_events.jsonl" % [LOG_DIRECTORY, session_id, run_id],
		"capture_started_at_s": _shift_elapsed, "practice": bool(metadata.get("practice", level_number == 0))}
	_level_file = _open_append(str(_level.log_path))
	if _level_file == null:
		_fail_write()
		return
	_levels.append(_level.duplicate(true))
	_level_clicks = 0
	_level_pointer_distance = 0.0
	_last_click_us = -1
	_active_events.clear()
	_closed_events.clear()
	_write("level_started", {"metadata": metadata, "capture_started_midlevel": _shift_elapsed > 0.0})
	_flush()
	_write_manifest()

func end_level(reason: String = "completed", summary: Dictionary = {}, final_state: Dictionary = {}) -> void:
	if _level.is_empty(): return
	if enabled:
		if not final_state.is_empty(): observe_state(final_state)
		for key: String in _active_events.keys():
			var tracked: Dictionary = _active_events[key]
			var unresolved: Variant = false if bool(tracked.get("solvable", true)) else null
			_finish_event(key, {"ended_at": _shift_elapsed, "solved": unresolved,
				"outcome": "level_ended_unsolved" if unresolved != null else "level_ended",
				"end_reason": reason, "censored": reason not in ["completed", "finished", "won", "lost"]})
		_write("level_ended", {"reason": reason, "summary": summary,
			"clicks": _level_clicks, "pointer_distance_px": _level_pointer_distance,
			"events_observed": _closed_events.size(), "capture_duration_s": maxf(0.0, _shift_elapsed - float(_level.capture_started_at_s))})
		_flush()
		for recorded: Dictionary in _levels:
			if recorded.level_run_id == _level.level_run_id:
				recorded["ended_at_s"] = _shift_elapsed
				recorded["end_reason"] = reason
		_write_manifest()
	_completed_level_elapsed += _shift_elapsed
	if _level_file != null: _level_file.close()
	_level_file = null
	_level_buffer.clear()
	_level = {}
	_active_events.clear()
	_closed_events.clear()

func get_level_context() -> Dictionary:
	var result: Dictionary = _level.duplicate(true)
	result.merge({"session_id": session_id, "capture_session_id": session_id,
		"level_elapsed_s": _shift_elapsed, "session_elapsed_s": _completed_level_elapsed + (_shift_elapsed if not _level.is_empty() else 0.0),
		"peer_id": _context.get("peer_id", 0), "departments": _context.get("departments", [])}, true)
	return result

func set_clock(shift_elapsed: float, shift_index: int) -> void:
	_shift_elapsed = shift_elapsed
	_shift_index = shift_index

func observe_state(state: Dictionary) -> void:
	if not enabled or _level.is_empty(): return
	# Saved snapshots wrap numeric values to retain exact precision. Network
	# snapshots already contain native values; this accepts either form.
	state = _decode_snapshot(state)
	_shift_elapsed = float(state.get("elapsed", _shift_elapsed))
	var snapshot_summary: Dictionary = {}
	for key: String in ["score", "reputation", "rescued", "resolved_count", "failed_count", "roads_cleared", "supplies", "chaos_phase", "running", "finished", "won"]:
		if state.has(key): snapshot_summary[key] = state[key]
	_write("state_observed", snapshot_summary)
	for source: Dictionary in state.get("road_events", []):
		if float(source.get("started_at", 0.0)) > _shift_elapsed: continue
		var data := source.duplicate(true)
		data["road_event_id"] = int(source.get("id", -1))
		data["event_type"] = str(source.get("type", "road_event"))
		data["observed_from_snapshot"] = true
		data["solvable"] = str(source.get("clear_kind", "")) != ""
		var key := _event_key("road_event_started", data)
		if _closed_events.has(key): continue
		var status := str(source.get("status", "active"))
		_start_event(key, "road_event", data, true)
		if status not in ["active", "clearing"]:
			data["solved"] = status == "cleared" if bool(data.solvable) else null
			data["outcome"] = "resolved" if status == "cleared" else ("expired_unsolved" if bool(data.solvable) else "elapsed")
			if status == "level_ended": data["outcome"] = "level_ended_unsolved" if bool(data.solvable) else "level_ended"
			if source.has("outcome"): data["outcome"] = source.outcome
			_finish_event(key, data)
	for source: Dictionary in state.get("incidents", []):
		var data := source.duplicate(true)
		data["incident_id"] = int(source.get("id", -1))
		data["started_at"] = float(source.get("created_at", _shift_elapsed))
		data["ended_at"] = float(source.get("resolved_at", -1.0))
		data["observed_from_snapshot"] = true
		var key := _event_key("incident_started", data)
		if _closed_events.has(key): continue
		_start_event(key, "incident", data, true)
		var status := str(source.get("status", "active"))
		if status not in ["active", "working"]:
			data["solved"] = status == "resolved"
			data["outcome"] = str(source.get("outcome", status))
			_finish_event(key, data)
	# Network snapshots omit old completed incidents. A completion missed during
	# disabled capture has an unknown outcome, not an inferred player failure.
	if state.has("incidents"):
		var present_incidents: Dictionary = {}
		for source: Dictionary in state.incidents: present_incidents["incident:%d" % int(source.get("id", -1))] = true
		for key: String in _active_events.keys():
			if key.begins_with("incident:") and not present_incidents.has(key):
				_finish_event(key, {"solved": null, "outcome": "no_longer_present_in_snapshot", "censored": true, "observed_from_snapshot": true})
	var level_index := int(state.get("shift_index", _shift_index))
	var layout := BeaconCampaign.layout(level_index)
	for flood: Array in layout.get("floods", []):
		var begins := float(flood[1])
		var until := begins + float(flood[2])
		var event_id := "bridge_%d_%.3f" % [int(flood[0]), begins]
		var key := "bridge:" + event_id
		if _shift_elapsed < begins or _closed_events.has(key): continue
		var data := {"event_id": event_id, "event_type": "bridge_flood", "bridge_column": int(flood[0]),
			"bridge": str(layout.get("bridges", {}).get(int(flood[0]), "Bridge")),
			"started_at": begins, "scheduled_end_at": until, "solvable": false, "solved": null,
			"observed_from_snapshot": true}
		if _shift_elapsed < until:
			_start_event(key, "bridge_flood", data, true)
		elif _active_events.has(key):
			data.merge({"ended_at": until, "outcome": "elapsed"}, true)
			_finish_event(key, data)
	var disruption := str(state.get("disruption", ""))
	var active_disruption_key := ""
	if not disruption.is_empty():
		var disruption_index := maxi(0, int(state.get("_disruption_index", 1)) - 1)
		var disruption_id := "disruption_%d" % disruption_index
		var key := "disruption:" + disruption_id
		active_disruption_key = key
		var plan: Dictionary = state.get("_shift", BeaconCampaign.shift_data(level_index))
		var schedule: Array = plan.get("disruptions", [])
		var start: Variant = schedule[disruption_index].get("at") if disruption_index < schedule.size() else null
		_start_event(key, "disruption", {"event_type": disruption, "event_id": disruption_id, "solvable": false,
			"started_at": start, "remaining_s": state.get("disruption_remaining", 0.0), "observed_from_snapshot": true}, true)
	for key: String in _active_events.keys():
		if key.begins_with("disruption:") and key != active_disruption_key:
			_finish_event(key, {"solved": null, "outcome": "ended_during_capture_gap", "observed_from_snapshot": true})

func log_pointer(pos: Vector2, delta: Vector2) -> void:
	if not enabled: return
	_pointer_distance += delta.length()
	_level_pointer_distance += delta.length()
	_write("mouse_motion", {"x": pos.x, "y": pos.y, "dx": delta.x, "dy": delta.y, "distance_px": delta.length()})

func log_mouse_button(event: InputEventMouseButton) -> void:
	if not enabled: return
	var now := Time.get_ticks_usec()
	var gap: Variant = null
	if event.pressed:
		_click_count += 1
		_level_clicks += 1
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
	if not enabled: return
	var enriched := data.duplicate(true)
	var key := _event_key(event_type, data)
	if not key.is_empty():
		enriched["event_instance_id"] = _instance_id(key)
		_track_lifecycle(event_type, key, data)
	_write(event_type, enriched)

func log_inspection(incident_id: int) -> void:
	log_event("inspection", {"incident_id": incident_id})

func update_context(data: Dictionary) -> void:
	_context.merge(data, true)
	if enabled and Time.get_ticks_msec() - _last_context_ms >= 1000:
		_write("context", _context)
		_last_context_ms = Time.get_ticks_msec()

func end_shift(ratings: Dictionary = {}) -> void:
	_write("shift_end", {"ratings": ratings, "summary": get_summary()})
	end_level("completed", ratings)
	_flush()

func get_summary() -> Dictionary:
	return {"enabled": enabled, "session_id": session_id, "log_path": log_path,
		"events": _event_count, "clicks": _click_count, "pointer_distance_px": _pointer_distance,
		"level": get_level_context(), "levels": _levels.size(), "local_only": true}

func _event_key(event_type: String, data: Dictionary) -> String:
	if data.has("road_event_id") and int(data.road_event_id) >= 0: return "road:%d" % int(data.road_event_id)
	if data.has("incident_id") and int(data.incident_id) >= 0: return "incident:%d" % int(data.incident_id)
	if event_type.begins_with("bridge_flood_"): return "bridge:%s" % str(data.get("event_id", data.get("bridge", "unknown")))
	if event_type in ["disruption", "disruption_started", "disruption_end", "disruption_ended"]:
		if data.has("event_id"): return "disruption:" + str(data.event_id)
		for key: String in _active_events:
			if key.begins_with("disruption:"): return key
		return "disruption:observed_%.3f" % float(data.get("started_at", _shift_elapsed))
	return ""

func _track_lifecycle(event_type: String, key: String, data: Dictionary) -> void:
	if _level.is_empty(): return
	if event_type in ["road_event_started", "hazard_started", "incident_started", "incident_spawned", "incident", "bridge_flood_started", "disruption", "disruption_started"]:
		var category := "road_event" if key.begins_with("road:") else ("incident" if key.begins_with("incident:") else ("bridge_flood" if key.begins_with("bridge:") else "disruption"))
		_start_event(key, category, data)
	# Detailed simulation lifecycle records carry the authoritative outcome.
	# Presentation messages (road_cleared, hazard_ended, resolved, failed) precede
	# these and remain raw observations, without prematurely closing the event.
	if event_type in ["road_event_cleared", "road_event_expired", "road_event_ended", "incident_ended", "incident_resolved", "incident_failed", "bridge_flood_ended", "disruption_end", "disruption_ended"]:
		var ending := data.duplicate(true)
		if not ending.has("outcome"):
			ending["outcome"] = "resolved" if event_type in ["road_event_cleared", "incident_resolved"] else ("failed" if event_type == "incident_failed" else "elapsed")
		if not ending.has("solved"):
			var tracked: Dictionary = _active_events.get(key, {})
			ending["solved"] = str(ending.outcome) == "resolved" if bool(tracked.get("solvable", key.begins_with("incident:"))) else null
		if str(ending.outcome) == "elapsed" and ending.get("solved") == false: ending["outcome"] = "expired_unsolved"
		_finish_event(key, ending)

func _start_event(key: String, category: String, data: Dictionary, observed: bool = false) -> void:
	if key.is_empty() or _closed_events.has(key): return
	if _active_events.has(key):
		_active_events[key].merge(data, true)
		return
	var record := data.duplicate(true)
	record["event_instance_id"] = _instance_id(key)
	record["category"] = category
	record["event_type"] = str(data.get("event_type", data.get("hazard_type", data.get("disruption", data.get("kind", category)))))
	record["started_at"] = data.get("started_at", data.get("created_at", null if observed else data.get("at", _shift_elapsed)))
	record["observed_at_s"] = _shift_elapsed
	record["solvable"] = bool(data.get("solvable", category == "incident" or (category == "road_event" and str(data.get("clear_kind", "")) != "")))
	record["start_observed"] = not observed
	_active_events[key] = record
	_write("event_observed" if observed else "event_started", record)

func _finish_event(key: String, data: Dictionary) -> void:
	if _closed_events.has(key): return
	if not _active_events.has(key):
		_start_event(key, "road_event" if key.begins_with("road:") else ("incident" if key.begins_with("incident:") else "environment"), data, true)
	if not _active_events.has(key): return
	var record: Dictionary = _active_events[key].duplicate(true)
	record.merge(data, true)
	record["event_instance_id"] = _instance_id(key)
	var ended_at := float(data.get("ended_at", data.get("at", _shift_elapsed)))
	if ended_at < 0.0: ended_at = _shift_elapsed
	record["ended_at"] = ended_at
	record["duration_s"] = maxf(0.0, ended_at - float(record.started_at)) if record.get("started_at") != null else null
	record["end_observed"] = not bool(data.get("observed_from_snapshot", false))
	_write("event_ended", record)
	_active_events.erase(key)
	_closed_events[key] = record

func _instance_id(key: String) -> String:
	return "%s/%s" % [str(_level.get("level_run_id", "unassigned")), key]

func _write(event_type: String, data: Dictionary) -> void:
	if not enabled or _file == null: return
	_event_count += 1
	var active_ids: Array[String] = []
	for key: String in _active_events: active_ids.append(_instance_id(key))
	active_ids.sort()
	var record := {"schema": SCHEMA_VERSION, "session_id": session_id, "capture_session_id": session_id,
		"sequence": _event_count, "capture_segment": _capture_segment,
		"local_elapsed_us": Time.get_ticks_usec() - _session_start_us,
		"utc": Time.get_datetime_string_from_system(true), "shift_index": _shift_index,
		"shift_elapsed_s": _shift_elapsed, "level_elapsed_s": _shift_elapsed,
		"session_elapsed_s": _completed_level_elapsed + (_shift_elapsed if not _level.is_empty() else 0.0),
		"level_id": _level.get("level_id"), "level_number": _level.get("level_number"),
		"level_index": _level.get("level_index"), "level_name": _level.get("level_name"),
		"level_run_id": _level.get("level_run_id"), "level_attempt": _level.get("level_attempt"),
		"peer_id": _context.get("peer_id", 0), "departments": _context.get("departments", []),
		"role": _context.get("role", ""), "active_event_ids": active_ids,
		"context": _sanitize(_context), "event": event_type, "data": _sanitize(data)}
	var line := JSON.stringify(record)
	_buffer.append(line)
	if _level_file != null: _level_buffer.append(line)
	if _buffer.size() >= MAX_BUFFER_LINES: _flush()

func _flush() -> void:
	if _file == null: return
	if not _buffer.is_empty():
		_file.store_string("\n".join(_buffer) + "\n")
		_file.flush()
		_buffer.clear()
	if _level_file != null and not _level_buffer.is_empty():
		_level_file.store_string("\n".join(_level_buffer) + "\n")
		_level_file.flush()
		_level_buffer.clear()
	_last_flush_ms = Time.get_ticks_msec()
	if _file.get_error() != OK or (_level_file != null and _level_file.get_error() != OK): _fail_write()

func _write_manifest() -> void:
	if not enabled: return
	var manifest := FileAccess.open("%s/%s/manifest.json" % [LOG_DIRECTORY, session_id], FileAccess.WRITE)
	if manifest == null:
		_fail_write()
		return
	manifest.store_string(JSON.stringify({"schema": SCHEMA_VERSION, "session_id": session_id,
		"session_events": log_path, "level_files": _levels, "context": _sanitize(_context),
		"level_files_mirror_session_events": true,
		"join_key": ["session_id", "sequence"], "voice_join_key": ["capture_session_id", "level_run_id"],
		"clock": {"level_elapsed_s": "active simulation seconds within this attempt", "session_elapsed_s": "sum of actual level elapsed times, including retries", "local_elapsed_us": "monotonic wall clock since session capture first started"},
		"updated_utc": Time.get_datetime_string_from_system(true)}, "\t"))
	var error := manifest.get_error()
	manifest.close()
	if error != OK: _fail_write()

func _open_append(path: String) -> FileAccess:
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null: file.seek_end()
	return file

func _close_files() -> void:
	if _file != null: _file.close()
	if _level_file != null: _level_file.close()
	_file = null
	_level_file = null

func _fail_write() -> void:
	_close_files()
	enabled = false
	_buffer.clear()
	_level_buffer.clear()
	log_error.emit("Research collection stopped: the local disk could not be written.")
	consent_changed.emit(false)

func _new_id(prefix: String) -> String:
	return "%s_%d_%s" % [prefix, int(Time.get_unix_time_from_system()), Crypto.new().generate_random_bytes(6).hex_encode()]

func _decode_snapshot(value: Variant) -> Variant:
	if value is Dictionary:
		match str(value.get("_beacon_type", "")):
			"Int64": return int(str(value.get("value", "0")))
			"Float64":
				var bits := Marshalls.base64_to_raw(str(value.get("bits", "")))
				return bits.decode_double(0) if bits.size() == 8 else 0.0
			"Vector2": return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
		var decoded: Dictionary = {}
		for key in value: decoded[key] = _decode_snapshot(value[key])
		return decoded
	if value is Array:
		var decoded: Array = []
		for item in value: decoded.append(_decode_snapshot(item))
		return decoded
	return value

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
	if enabled: end_level("application_closed")
	set_enabled(false)
