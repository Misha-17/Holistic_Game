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
var _tracks: Dictionary = {}
var _manifest: Dictionary = {}
var _timeline: FileAccess
var _checkpoint_frames := 0
var _closed := false
var _level_segments: Array[Dictionary] = []
var _segment_open := false
var _audio_activity: Array[Dictionary] = []
var _last_activity: Dictionary = {}


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


func update_speaker(peer_id: int, identity: Dictionary) -> bool:
	if _closed: return false
	if _tracks.has(peer_id):
		var entry: Dictionary = _tracks[peer_id]
		if entry.identity != identity:
			entry.identity = identity.duplicate(true)
			log_metadata("speaker_identity", identity)
		return error.is_empty()
	var filename := "peer_%d.wav" % peer_id
	var writer = Wav.new()
	var details := identity.duplicate(true)
	details.merge({"session_id": _manifest.get("session_id", ""), "speaker_id": "peer_%d" % peer_id,
		"peer_id": peer_id, "timeline_start_frame": 0}, true)
	if not writer.open_file(path.get_base_dir().path_join(filename), details):
		error = str(writer.error)
		return false
	if not writer.append_silence(bytes_written / 2):
		error = str(writer.error)
		writer.close_file()
		return false
	_tracks[peer_id] = {"writer": writer, "identity": identity.duplicate(true), "file": filename}
	log_metadata("speaker_track_opened", details)
	return _save_manifest()


func append_speakers(packets: Dictionary, identities: Dictionary, frames: int = 320) -> bool:
	if _closed or _timeline == null: return false
	if bytes_written + frames * 2 > Wav.MAX_DATA_BYTES:
		error = "Voice session reached its recording limit."
		return false
	for peer_id in packets:
		if not update_speaker(int(peer_id), identities.get(peer_id, {"peer_id": peer_id})): return false
		_note_activity(int(peer_id), packets[peer_id], frames)
	for peer_id in _tracks:
		var writer = _tracks[peer_id].writer
		var ok: bool = writer.append(packets[peer_id]) if packets.has(peer_id) else writer.append_silence(frames)
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


func _save_manifest() -> bool:
	var tracks: Array[Dictionary] = []
	for peer_id in _tracks:
		var entry: Dictionary = _tracks[peer_id]
		var track: Dictionary = entry.identity.duplicate(true)
		track.merge({"speaker_id": "peer_%d" % int(peer_id), "peer_id": peer_id,
			"file": entry.file, "start_frame": 0, "frames": int(entry.writer.bytes_written) / 2}, true)
		tracks.append(track)
	_manifest.tracks = tracks
	if _segment_open: _level_segments.back().end_frame = bytes_written / 2
	_manifest["level_segments"] = _level_segments
	_manifest["audio_activity"] = _audio_activity
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


func _note_activity(peer_id: int, pcm: PackedByteArray, frames: int) -> void:
	var audible := false
	for offset in range(0, pcm.size(), 2):
		if absi(pcm.decode_s16(offset)) >= 256:
			audible = true
			break
	if not audible: return
	var start := bytes_written / 2
	var index := int(_last_activity.get(peer_id, -1))
	if index >= 0 and start - int(_audio_activity[index].end_frame) <= RATE / 5:
		_audio_activity[index].end_frame = start + frames
	else:
		_last_activity[peer_id] = _audio_activity.size()
		_audio_activity.append({"speaker_id": "peer_%d" % peer_id, "start_frame": start, "end_frame": start + frames})


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
			if not filename.begins_with("peer_") or not filename.ends_with(".wav") or known.has(filename): continue
			var id_text := filename.trim_prefix("peer_").trim_suffix(".wav")
			if not id_text.is_valid_int(): continue
			var details: Dictionary = {"peer_id": int(id_text), "speaker_id": "peer_" + id_text}
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
			if str(track.get("file", "")) != "peer_%d.wav" % int(track.get("peer_id", -1)): continue
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
