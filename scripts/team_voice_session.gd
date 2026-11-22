extends RefCounted

# One session, one time axis, one mono WAV per speaker. Simultaneous speech is
# never summed on disk; loading these tracks together preserves the conversation.
const Wav = preload("res://scripts/team_voice_wav.gd")
const Player = preload("res://scripts/team_voice_player.gd")
const RATE := 16000
const FORMAT := "beacon-bay-speaker-session-v1"
var path := ""
var bytes_written := 0 # Logical timeline bytes, not the sum of all speaker files.
var error := ""
var _tracks: Dictionary = {} # speaker key -> {writer, identity, file, peer_ids}
var _manifest: Dictionary = {}
var _timeline: FileAccess
var _checkpoint_frames := 0
var _closed := false
var _level_segments: Array[Dictionary] = []
var _segment_open := false
var _audio_activity: Array[Dictionary] = []
var _last_activity: Dictionary = {}
var _withdrawn: Dictionary = {} # speaker keys removed after a study withdrawal (4.11)


func open_file(destination: String, metadata: Dictionary) -> bool:
	path = destination
	if FileAccess.file_exists(path):
		error = "A voice session with this name already exists."
		return false
	var result := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if result != OK and result != ERR_ALREADY_EXISTS:
		error = "Could not create the local voice session folder."
		return false
	_timeline = FileAccess.open(path.get_base_dir().path_join("timeline.jsonl"), FileAccess.WRITE)
	if _timeline == null:
		error = "Could not open voice session timing metadata."
		return false
	_manifest = metadata.duplicate(true)
	_manifest.merge({"format": FORMAT, "sample_rate": RATE, "channels_per_track": 1,
		"sample_format": "PCM16", "timeline": "timeline.jsonl", "tracks": [],
		"time_axis": "local monotonic session time; all tracks start at frame zero",
		"missing_audio": "silence (recording paused, permission denied, no speech, or network loss)",
		"state": "recording", "pid": OS.get_process_id()}, true)
	if not _save_manifest(): return false
	log_metadata("recording_open", metadata)
	return error.is_empty()


## Tracks are kept per person (identity.speaker_key, stable across reconnects;
## 2.11), not per network id. A player who drops out and rejoins continues in
## the same file; the time they were away is silence.
static func speaker_key(peer_id: int, identity: Dictionary) -> String:
	var key := str(identity.get("speaker_key", ""))
	return key if not key.is_empty() else "peer_%d" % peer_id


func update_speaker(peer_id: int, identity: Dictionary) -> bool:
	if _closed: return false
	var key := speaker_key(peer_id, identity)
	if _tracks.has(key):
		var entry: Dictionary = _tracks[key]
		if not (entry.peer_ids as Array).has(peer_id):
			(entry.peer_ids as Array).append(peer_id)
			log_metadata("speaker_reconnected", {"speaker_id": key, "peer_id": peer_id})
			_save_manifest()
		if entry.identity != identity:
			entry.identity = identity.duplicate(true)
			log_metadata("speaker_identity", identity)
		return error.is_empty()
	var filename := "%s.wav" % key.validate_filename()
	var writer = Wav.new()
	var details := identity.duplicate(true)
	details.merge({"session_id": _manifest.get("session_id", ""), "speaker_id": key,
		"peer_id": peer_id, "timeline_start_frame": 0}, true)
	if not writer.open_file(path.get_base_dir().path_join(filename), details):
		error = str(writer.error)
		return false
	if not writer.append_silence(bytes_written / 2):
		error = str(writer.error)
		writer.close_file()
		return false
	_tracks[key] = {"writer": writer, "identity": identity.duplicate(true), "file": filename, "peer_ids": [peer_id]}
	log_metadata("speaker_track_opened", details)
	return _save_manifest()


func append_speakers(packets: Dictionary, identities: Dictionary, frames: int = 320) -> bool:
	if _closed or _timeline == null: return false
	if bytes_written + frames * 2 > Wav.MAX_DATA_BYTES:
		error = "Voice session reached its recording limit."
		return false
	var by_key: Dictionary = {}
	for peer_id in packets:
		var identity: Dictionary = identities.get(peer_id, {"peer_id": peer_id})
		if _withdrawn.has(speaker_key(int(peer_id), identity)): continue
		if not update_speaker(int(peer_id), identity): return false
		var key := speaker_key(int(peer_id), identity)
		if _withdrawn.has(key): continue # withdrew from the study: never written again
		if by_key.has(key): continue # the same person twice in one frame (old and new connection)
		by_key[key] = packets[peer_id]
		_note_activity(key, int(peer_id), packets[peer_id], frames)
	for key in _tracks:
		var writer = _tracks[key].writer
		var ok: bool = writer.append(by_key[key]) if by_key.has(key) else writer.append_silence(frames)
		if not ok:
			error = str(writer.error)
			return false
	bytes_written += frames * 2
	if bytes_written / 2 - _checkpoint_frames >= RATE:
		return _save_manifest()
	return error.is_empty()


func append_silence(frames: int) -> bool:
	if frames <= 0: return true
	return append_speakers({}, {}, frames)


func log_metadata(event: String, data: Dictionary) -> void:
	if _timeline == null: return
	if event in ["capture_suspended", "recording_paused", "session_stopped", "recording_closed"]:
		_end_level_segment()
	elif event in ["capture_resumed", "recording_resumed"] and not _segment_open:
		_begin_level_segment(data)
	elif event == "level_context" and _segment_open:
		_end_level_segment()
		_begin_level_segment(data)
	_timeline.store_line(JSON.stringify({"event": event, "audio_frame": bytes_written / 2,
		"audio_seconds": float(bytes_written) / (RATE * 2), "data": data}))
	_timeline.flush()
	if _timeline.get_error() != OK: error = "Could not write voice session metadata."


func close_file() -> void:
	if _closed: return
	for entry: Dictionary in _tracks.values():
		entry.writer.close_file()
		if not str(entry.writer.error).is_empty(): error = str(entry.writer.error)
	log_metadata("recording_closed", {"frames": bytes_written / 2, "sample_rate": RATE, "error": error})
	_manifest.state = "closed" if error.is_empty() else "error"
	_manifest["error"] = error
	_save_manifest()
	if not Player.write_file(path.get_base_dir().path_join("listen.html"), _manifest):
		error = "Audio saved, but the local voice player could not be written."
	if _timeline != null: _timeline.close()
	_timeline = null
	_closed = true


# Complete, playable files after every level (mid-term report, Table A4: "the
# voice files were not finalised"). If the game is later killed (for example
# with the Godot editor's Stop button), only audio after this point needs the
# recovery that runs on the next launch.
func publish_checkpoint() -> bool:
	if _closed: return false
	for entry: Dictionary in _tracks.values():
		entry.writer.checkpoint()
		if not str(entry.writer.error).is_empty(): error = str(entry.writer.error)
	_manifest["last_checkpoint_utc"] = Time.get_datetime_string_from_system(true)
	var ok := _save_manifest()
	if ok and not Player.write_file(path.get_base_dir().path_join("listen.html"), _manifest):
		ok = false
	if _timeline != null: _timeline.flush()
	return ok

func _save_manifest() -> bool:
	var tracks: Array[Dictionary] = []
	for key in _tracks:
		var entry: Dictionary = _tracks[key]
		var track: Dictionary = entry.identity.duplicate(true)
		track.merge({"speaker_id": key, "peer_id": int(entry.peer_ids.back()), "peer_ids": entry.peer_ids.duplicate(),
			"file": entry.file, "start_frame": 0, "frames": int(entry.writer.bytes_written) / 2}, true)
		tracks.append(track)
	_manifest.tracks = tracks
	if _segment_open: _level_segments.back().end_frame = bytes_written / 2
	_manifest["level_segments"] = _level_segments
	_manifest["audio_activity"] = _audio_activity
	if not _withdrawn.is_empty(): _manifest["withdrawn_speakers"] = _withdrawn.keys()
	_manifest["audio_activity_threshold_pcm16"] = 256
	_manifest["player"] = "listen.html"
	_manifest["frames"] = bytes_written / 2
	_manifest["duration_s"] = float(bytes_written) / (RATE * 2)
	var temp := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if temp == null:
		error = "Could not write the voice session manifest."
		return false
	temp.store_string(JSON.stringify(_manifest, "\t"))
	temp.flush()
	var result := temp.get_error()
	temp.close()
	if result != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "Could not save the voice session manifest."
		return false
	_checkpoint_frames = bytes_written / 2
	return error.is_empty()


func _begin_level_segment(context: Dictionary) -> void:
	if str(context.get("level_run_id", "")).is_empty(): return
	var segment := context.duplicate(true)
	segment.merge({"start_frame": bytes_written / 2, "end_frame": bytes_written / 2}, true)
	_level_segments.append(segment)
	_segment_open = true


func _end_level_segment() -> void:
	if not _segment_open: return
	_level_segments.back().end_frame = bytes_written / 2
	_segment_open = false


func _note_activity(key: String, peer_id: int, pcm: PackedByteArray, frames: int) -> void:
	var audible := false
	for offset in range(0, pcm.size(), 2):
		if absi(pcm.decode_s16(offset)) >= 256:
			audible = true
			break
	if not audible: return
	var start := bytes_written / 2
	var index := int(_last_activity.get(key, -1))
	if index >= 0 and start - int(_audio_activity[index].end_frame) <= RATE / 5 and int(_audio_activity[index].peer_id) == peer_id:
		_audio_activity[index].end_frame = start + frames
	else:
		_last_activity[key] = _audio_activity.size()
		_audio_activity.append({"speaker_id": key, "peer_id": peer_id, "start_frame": start, "end_frame": start + frames})


## Study withdrawal (4.11): delete this person's track while the session is
## still recording, and never record them again in this session. Returns the
## deleted file names.
func withdraw_speaker(key: String) -> Array:
	var removed: Array = []
	_withdrawn[key] = true
	if _tracks.has(key):
		var entry: Dictionary = _tracks[key]
		entry.writer.close_file()
		_tracks.erase(key)
		removed = _delete_track_files(path.get_base_dir(), str(entry.file))
	_audio_activity = _audio_activity.filter(func(a): return str(a.speaker_id) != key)
	_last_activity.clear()
	log_metadata("speaker_withdrawn", {"speaker_id": key, "files_deleted": removed})
	_save_manifest()
	Player.write_file(path.get_base_dir().path_join("listen.html"), _manifest)
	return removed


## The same for a finished session folder: remove the track from session.json,
## its activity and its files, and rewrite listen.html.
static func withdraw_from_folder(folder: String, key: String) -> Array:
	var manifest_path := folder.path_join("session.json")
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if FileAccess.file_exists(manifest_path) else null
	if not info is Dictionary: return []
	var removed: Array = []
	var kept: Array = []
	for track: Dictionary in info.get("tracks", []):
		if str(track.get("speaker_id", "")) == key: removed.append_array(_delete_track_files(folder, str(track.get("file", ""))))
		else: kept.append(track)
	if removed.is_empty() and kept.size() == (info.get("tracks", []) as Array).size(): return []
	info["tracks"] = kept
	info["audio_activity"] = (info.get("audio_activity", []) as Array).filter(func(a): return str(a.get("speaker_id", "")) != key)
	var withdrawn: Array = info.get("withdrawn_speakers", [])
	withdrawn.append(key)
	info["withdrawn_speakers"] = withdrawn
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(info, "\t"))
		file.close()
	Player.write_file(folder.path_join("listen.html"), info)
	return removed


static func _delete_track_files(folder: String, filename: String) -> Array:
	var removed: Array = []
	if filename.is_empty() or "/" in filename or ".." in filename: return removed
	for name in [filename, filename.get_basename() + ".jsonl", filename + ".tmp"]:
		var target := folder.path_join(name)
		if FileAccess.file_exists(target) and DirAccess.remove_absolute(ProjectSettings.globalize_path(target)) == OK: removed.append(name)
	return removed


static func recover_pending(folder: String) -> int:
	var directory := DirAccess.open(folder)
	if directory == null: return 0
	var recovered := Wav.recover_pending(folder) # Legacy mono sessions.
	for child: String in directory.get_directories():
		var session_folder := folder.path_join(child)
		var manifest_path := session_folder.path_join("session.json")
		var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if FileAccess.file_exists(manifest_path) else null
		if not info is Dictionary or info.get("format") != FORMAT: continue
		if str(info.get("state", "")) == "recording" and OS.is_process_running(int(info.get("pid", -1))): continue
		var count := Wav.recover_pending(session_folder)
		recovered += count
		if str(info.get("state", "")) != "recording" and count == 0: continue
		# A crash may occur after opening a new speaker WAV but before publishing
		# its manifest entry. Its own metadata provides the missing identity.
		var tracks: Array = info.get("tracks", [])
		var known: Dictionary = {}
		for track: Dictionary in tracks: known[str(track.get("file", ""))] = true
		var session_directory := DirAccess.open(session_folder)
		for filename: String in session_directory.get_files():
			if not (filename.begins_with("peer_") or filename.begins_with("player_") or filename.ends_with("_voice.wav")) or not filename.ends_with(".wav") or known.has(filename): continue
			var id_text := filename.trim_prefix("peer_").trim_suffix(".wav")
			if filename.begins_with("peer_") and not id_text.is_valid_int(): continue
			var details: Dictionary = {"peer_id": int(id_text) if filename.begins_with("peer_") else -1, "speaker_id": filename.get_basename()}
			var metadata_path := session_folder.path_join(filename.get_basename() + ".jsonl")
			if FileAccess.file_exists(metadata_path):
				var lines := FileAccess.get_file_as_string(metadata_path).split("\n", false)
				if not lines.is_empty():
					var first: Variant = JSON.parse_string(lines[0])
					if first is Dictionary and first.get("data") is Dictionary: details.merge(first.data, true)
			details.merge({"file": filename, "start_frame": 0}, true)
			tracks.append(details)
		# Repair headers first; pad partially written final blocks with silence so
		# all recovered tracks still have exactly the same length.
		var longest := 0
		var valid_tracks: Array[Dictionary] = []
		for track: Dictionary in tracks:
			if str(track.get("file", "")) != "%s.wav" % str(track.get("speaker_id", "")).validate_filename(): continue
			var file := FileAccess.open(session_folder.path_join(str(track.file)), FileAccess.READ)
			if file == null or file.get_length() < 44: continue
			track.frames = mini(Wav.MAX_DATA_BYTES / 2, maxi(0, (int(file.get_length()) - 44) / 2))
			longest = maxi(longest, int(track.frames))
			file.close()
			valid_tracks.append(track)
		var silence := PackedByteArray()
		silence.resize(RATE * 2)
		for track: Dictionary in valid_tracks:
			if int(track.frames) == longest: continue
			var file := FileAccess.open(session_folder.path_join(str(track.file)), FileAccess.READ_WRITE)
			if file == null: continue
			file.seek(44 + int(track.frames) * 2)
			var remaining := longest - int(track.frames)
			while remaining > 0:
				var amount := mini(remaining, RATE)
				file.store_buffer(silence if amount == RATE else silence.slice(0, amount * 2))
				remaining -= amount
			Wav._write_header(file, longest * 2)
			file.flush()
			if file.get_error() == OK: track.frames = longest
			file.close()
		info.tracks = valid_tracks
		info.frames = longest
		info.duration_s = float(longest) / RATE
		info.state = "recovered"
		info["recovery_note"] = "Interrupted session recovered from retained WAV samples; any partial final blocks are silent."
		var manifest := FileAccess.open(manifest_path, FileAccess.WRITE)
		if manifest != null:
			manifest.store_string(JSON.stringify(info, "\t"))
			manifest.close()
		Player.write_file(session_folder.path_join("listen.html"), info)
	return recovered
