extends Node
class_name TeamVoice

signal status_changed(text: String)
signal voice_error(message: String)
signal recording_changed(active: bool, path: String)
signal participants_changed

const Mixer = preload("res://scripts/team_voice_mixer.gd")
const Wav = preload("res://scripts/team_voice_wav.gd")
const Session = preload("res://scripts/team_voice_session.gd")
const DIRECTORY := "user://research/voice" # before 9.11; still recovered and listed
const RESEARCH_ROOT := "user://research"
const RATE := 16000
const FRAMES := 320
const RECEIVED_VOICE_GAIN := 2.0

var mic_enabled := false
var recording_enabled := false
var recording_consent := false
var recording_active := false
var recording_path := ""
var status := "Voice chat disabled"
## 9.11: the player's name for file names (StudyFiles.label). The recording goes
## into the session folder: research/<session>/<name>_voice/<name>_voice.wav.
var file_label := "Player"
var playback_level := 50
var peer_playback_gains: Dictionary = {}

func set_playback_level(value: int) -> void:
	playback_level = clampi(value, 0, 100)
	if is_instance_valid(_speaker): _speaker.volume_linear = float(playback_level) / 50.0
var session_id := ""

var _network: NetworkSession
var _server_only := false
var _configured := false
var _session_active := false
var _session_time := 0.0
var _session_sync_ms := 0
var _session_start_ms := 0
var _session_start_frame := 0
var _capture_active := true
var _research_context: Dictionary = {}
var _last_metadata_ms := 0
var _local_peer := 1
var _mixer = Mixer.new()
var _writer: RefCounted
var _cursor := 0
var _sequence := 0
var _capture: AudioEffectCapture
var _microphone: AudioStreamPlayer
var _speaker: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _capture_bus := ""
var _source := PackedVector2Array()
var _resample_position := 0.0
var _recording_source_cutoff := 0
var _last_capture_ms := 0
var _warned_no_capture := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(network: NetworkSession, server_only: bool = false) -> void:
	_network = network
	_server_only = server_only
	_configured = true
	_cursor = _clock_frame()
	_mixer.reset(_cursor)
	if server_only:
		set_process(false)
		return
	network.voice_packet_received.connect(_receive_voice)
	network.voice_participants_changed.connect(_participants_updated)
	network.roster_changed.connect(_roster_updated)
	network.disconnected.connect(_disconnected)
	var recovered: int = Session.recover_pending(DIRECTORY)
	if DirAccess.dir_exists_absolute(RESEARCH_ROOT):
		for name in DirAccess.get_directories_at(RESEARCH_ROOT):
			if name != "voice" and name != "pc_checks": recovered += Session.recover_pending(RESEARCH_ROOT.path_join(name))
	if recovered > 0: _set_status("Recovered %d local voice recording(s)" % recovered)
	_roster_updated()


# Session lifecycle is separate from microphone and saving preferences. Starting
# with saving off creates no file; enabling it later starts one with a time map.
func start(id: String) -> bool:
	if _server_only or not _configured: return false
	if _session_active and session_id == id: return true
	stop()
	_render_audio()
	session_id = id
	recording_path = ""
	_session_active = true
	_session_start_ms = Time.get_ticks_msec()
	_session_start_frame = _cursor
	_session_sync_ms = _session_start_ms
	_mixer.clear_recording_permission()
	if recording_enabled and _capture_active: return _open_recording()
	return true


func stop() -> void:
	_seal_microphone_capture()
	if _writer != null:
		_render_audio()
		_flush_recorded_tail()
		if _writer != null:
			_writer.log_metadata("session_stopped", _timing())
			_writer.close_file()
			var close_error := str(_writer.error)
			_writer = null
			if not close_error.is_empty(): voice_error.emit(close_error)
	_session_active = false
	recording_active = false
	_publish_state()
	recording_changed.emit(false, recording_path)
	_refresh_status()


func set_session_time(seconds: float) -> void:
	_session_time = maxf(0.0, seconds)
	_session_sync_ms = Time.get_ticks_msec()


func set_research_context(context: Dictionary) -> void:
	var changed_level := str(context.get("level_run_id", "")) != str(_research_context.get("level_run_id", ""))
	if changed_level: _render_audio()
	_research_context = context.duplicate(true)
	if changed_level: _log("level_context", _timing())


func set_capture_active(value: bool) -> void:
	if _server_only or _capture_active == value: return
	_seal_microphone_capture()
	_render_audio()
	# Finishing a level retains consented speech already captured into the short
	# jitter buffer. User opt-out uses set_recording_enabled, which discards it.
	if not value: _flush_recorded_tail()
	_capture_active = value
	_mixer.clear_recording_permission()
	recording_active = value and recording_enabled and _session_active and _writer != null
	if value and recording_enabled and _session_active and _writer == null: _open_recording()
	_log("capture_resumed" if value else "capture_suspended", _timing())
	if not value and _writer != null and _writer.has_method("publish_checkpoint"): _writer.publish_checkpoint()
	_publish_state()
	recording_changed.emit(recording_active, recording_path)
	_refresh_status()


func set_mic_enabled(value: bool) -> void:
	if _server_only or mic_enabled == value: return
	if value:
		if not _create_microphone(): return
		_microphone.play()
		_capture.clear_buffer()
		_last_capture_ms = Time.get_ticks_msec()
		_warned_no_capture = false
	else:
		if _microphone != null: _microphone.stop()
		if _capture != null: _capture.clear_buffer()
		_source.clear()
		_resample_position = 0.0
		_recording_source_cutoff = 0
		_mixer.remove_peer(_local_peer)
		input_level_db = -120.0
		_meter_peak_db = -120.0
	mic_enabled = value
	_publish_state()
	_log("microphone", {"enabled": value})
	_refresh_status()


func set_recording_consent(value: bool) -> void:
	if _server_only or recording_consent == value: return
	recording_consent = value
	if not value: _mixer.clear_recording_permission(_local_peer)
	_publish_state()
	_log("sharing_consent", {"allowed": value})
	_refresh_status()


func set_recording_enabled(value: bool) -> void:
	if _server_only or recording_enabled == value: return
	_seal_microphone_capture()
	_render_audio()
	recording_enabled = value
	_mixer.clear_recording_permission()
	if value and _session_active and _capture_active:
		if _writer == null:
			_open_recording()
		else:
			recording_active = true
			_log("recording_resumed", _timing())
	else:
		recording_active = false
		_log("recording_paused", _timing())
	_publish_state()
	recording_changed.emit(recording_active, recording_path)
	_refresh_status()


func get_participants() -> Dictionary:
	return _network.voice_participants.duplicate(true) if _network != null else {}


func get_recording_info() -> Dictionary:
	return {"active": recording_active, "path": ProjectSettings.globalize_path(recording_path) if recording_path != "" else "",
		"session_id": session_id, "sample_rate": RATE, "channels_per_track": 1, "format": Session.FORMAT,
		"frames": int(_writer.bytes_written) / 2 if _writer != null else 0,
		"session_seconds": _session_time, "microphone_enabled": mic_enabled}


func shutdown() -> void:
	stop()
	set_mic_enabled(false)
	_destroy_audio()


func _process(_delta: float) -> void:
	if not _configured or _server_only: return
	if mic_enabled: _capture_microphone()
	_render_audio()
	var now := Time.get_ticks_msec()
	if _writer != null and now - _last_metadata_ms >= 1000:
		_last_metadata_ms = now
		_log("clock_sync", _timing())
	if mic_enabled and not _warned_no_capture and now - _last_capture_ms > 5000:
		_warned_no_capture = true
		voice_error.emit("No microphone samples received. Check the selected input and system microphone permission.")


## Delete every voice folder of a session on this computer (study withdrawal).
func delete_session_folders(session: String) -> Array:
	if session_id == session and _writer != null: stop()
	var removed: Array = []
	for folder in session_folders(session):
		for name in DirAccess.get_files_at(folder):
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(name))) == OK: removed.append(name)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	return removed

func session_folders(session: String) -> Array[String]:
	var result: Array[String] = []
	if session.is_empty(): return result
	var folder := RESEARCH_ROOT.path_join(session.validate_filename())
	if DirAccess.dir_exists_absolute(folder):
		for name in DirAccess.get_directories_at(folder):
			if name.ends_with("_voice"): result.append(folder.path_join(name))
	if not DirAccess.dir_exists_absolute(DIRECTORY): return result
	var safe := ""
	for character in session.left(64):
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": safe += character
	for name in DirAccess.get_directories_at(DIRECTORY):
		if name.begins_with("team_%s_" % safe): result.append(DIRECTORY.path_join(name))
	return result

## The voice key of this computer's player (same as the track name).
func local_speaker_key() -> String:
	return _speaker_key(_local_peer)

func _open_recording() -> bool:
	if _server_only or not _session_active or not recording_enabled or not _capture_active: return false
	_render_audio()
	var session_folder := RESEARCH_ROOT.path_join(session_id.validate_filename() if not session_id.is_empty() else "session")
	var voice_folder := StudyFiles.free_folder(session_folder, StudyFiles.label(file_label) + "_voice")
	recording_path = session_folder.path_join(voice_folder).path_join("session.json")
	_writer = Session.new()
	var info := _timing()
	info.merge({"session_id": session_id.left(128), "sample_rate": RATE, "channels_per_track": 1,
		"format": "PCM16", "local_only": true, "capture": "in_game_team_voice",
		"jitter_buffer_ms": int(Mixer.JITTER * 1000 / RATE), "peer_id": _local_peer,
		"permissions": get_participants(), "utc": Time.get_datetime_string_from_system(true)})
	if not _writer.open_file(recording_path, info):
		_recording_failed(str(_writer.error))
		return false
	if not _writer.append_silence(maxi(0, _cursor - _session_start_frame)):
		_recording_failed(str(_writer.error))
		return false
	if not _writer.update_speaker(_local_peer, _speaker_identity(_local_peer)):
		_recording_failed(str(_writer.error))
		return false
	recording_active = true
	_log("recording_resumed", _timing())
	_last_metadata_ms = Time.get_ticks_msec()
	_publish_state()
	recording_changed.emit(true, recording_path)
	_refresh_status()
	return true


func _render_audio(until_frame: int = -1) -> void:
	if not _configured or _server_only: return
	var now := _clock_frame() if until_frame < 0 else until_frame
	if now - _cursor > RATE / 2:
		# A stalled/suspended game preserves wall-clock silence without retaining
		# minutes of audio in memory or replaying stale speech after resuming.
		var skipped := now - _cursor
		if _writer != null:
			_log("audio_gap", {"frames": skipped, "reason": "client_stall"})
			if _writer != null and not _writer.append_silence(skipped): _recording_failed(str(_writer.error))
		_cursor = now
		_mixer.reset(_cursor)
	var permissions: Dictionary = {}
	if recording_active:
		# 9.11: each computer saves only its own player's microphone. Every player
		# keeps their own files and sends them to the researcher, so teammates'
		# voices are not saved a second time here.
		permissions[_local_peer] = true
	while _cursor + FRAMES <= now:
		var mixed: Dictionary = _mixer.render(_cursor, _local_peer, permissions, peer_playback_gains, RECEIVED_VOICE_GAIN)
		_cursor += FRAMES
		if _playback != null and _playback.can_push_buffer(FRAMES):
			_playback.push_buffer(mixed.playback)
		var identities: Dictionary = {}
		for peer_id in mixed.speakers: identities[peer_id] = _speaker_identity(int(peer_id))
		if _writer != null and not _writer.append_speakers(mixed.speakers, identities):
			_recording_failed(str(_writer.error))


func _flush_recorded_tail() -> void:
	if not recording_active or _writer == null: return
	var end := _cursor
	for state: Dictionary in _mixer.streams.values():
		for packet: Dictionary in state.packets:
			end = maxi(end, int(packet.at) + FRAMES)
	end = mini(end, _clock_frame() + Mixer.MAX_AHEAD)
	if end <= _cursor: return
	var count := ceili(float(end - _cursor) / FRAMES) * FRAMES
	_log("buffered_speech_tail", {"frames": count})
	_render_audio(_cursor + count)


func _capture_microphone() -> void:
	if _capture == null: return
	var available := _capture.get_frames_available()
	if available <= 0: return
	_last_capture_ms = Time.get_ticks_msec()
	_source.append_array(_capture.get_buffer(available))
	var input_rate := AudioServer.get_mix_rate()
	var step := input_rate / float(RATE)
	if _source.size() > int(input_rate * 0.2):
		var skipped := _source.size() - int(input_rate * 0.1)
		_source = _source.slice(skipped)
		_recording_source_cutoff = maxi(0, _recording_source_cutoff - skipped)
		_resample_position = 0.0
	var packets := 0
	while _resample_position + FRAMES * step < _source.size() and packets < 8:
		var source_recordable := _resample_position >= _recording_source_cutoff
		var pcm := PackedByteArray()
		pcm.resize(FRAMES * 2)
		var energy := 0.0
		var peak := 0
		for index in range(FRAMES):
			var position := _resample_position + index * step
			var base := int(position)
			var stereo: Vector2 = _source[base].lerp(_source[base + 1], position - base)
			var sample := clampi(roundi((stereo.x + stereo.y) * 0.5 * 32768.0), -32768, 32767)
			pcm.encode_s16(index * 2, sample)
			energy += float(sample * sample)
			peak = maxi(peak, absi(sample))
		_meter_packet(sqrt(energy / FRAMES), peak)
		_resample_position += FRAMES * step
		_sequence += 1
		_send_microphone_packet(pcm, source_recordable)
		packets += 1
	var consumed := int(_resample_position)
	if consumed > 0:
		_source = _source.slice(consumed)
		_resample_position -= consumed
		_recording_source_cutoff = maxi(0, _recording_source_cutoff - consumed)


# Microphone level, in dBFS (0 = digital maximum). The meter shows the live
# level; a microphone check collects the loudest 20 ms frames while the player
# speaks (mid-term report, Table A4: one microphone was very quiet).
const MIC_GOOD_DB := -30.0 # loudest speech frames should reach this
const MIC_SILENT_DB := -55.0 # below this nothing usable was heard
const MIC_CLIP_DB := -0.5
var input_level_db := -120.0
var _meter_peak_db := -120.0
var _meter_peak_ms := 0
var _check_active := false
var _check_frames := 0
var _check_speech_frames := 0
var _check_clipped_frames := 0
var _check_loudest_db := -120.0
var _check_levels: PackedFloat32Array = PackedFloat32Array()

static func level_db(value: float) -> float:
	return 20.0 * log(maxf(value, 1.0) / 32768.0) / log(10.0)

func _meter_packet(rms: float, peak: int) -> void:
	var db := level_db(rms)
	# Fast attack, slow release, like a normal level meter.
	input_level_db = db if db > input_level_db else lerpf(input_level_db, db, 0.15)
	var peak_db := level_db(float(peak))
	if peak_db >= _meter_peak_db or Time.get_ticks_msec() - _meter_peak_ms > 1500:
		_meter_peak_db = peak_db
		_meter_peak_ms = Time.get_ticks_msec()
	if not _check_active: return
	_check_frames += 1
	_check_loudest_db = maxf(_check_loudest_db, db)
	if db > MIC_SILENT_DB + 10.0:
		_check_speech_frames += 1
		_check_levels.append(db)
	if peak_db >= MIC_CLIP_DB: _check_clipped_frames += 1

func input_peak_db() -> float:
	return _meter_peak_db if Time.get_ticks_msec() - _meter_peak_ms <= 1500 else input_level_db

func begin_mic_check() -> void:
	_check_active = true
	_check_frames = 0
	_check_speech_frames = 0
	_check_clipped_frames = 0
	_check_loudest_db = -120.0
	_check_levels = PackedFloat32Array()

# Verdict on what was heard since begin_mic_check(). The speech level is the
# 90th percentile of active 20 ms frames, so one cough cannot pass the check.
func mic_check_result() -> Dictionary:
	var levels := _check_levels.duplicate()
	levels.sort()
	var speech_db: float = levels[int(levels.size() * 0.9)] if levels.size() >= 10 else _check_loudest_db
	var verdict := "waiting"
	if not mic_enabled: verdict = "microphone_off"
	elif _check_frames == 0: verdict = "no_signal"
	elif _check_speech_frames < 10: verdict = "waiting" if _check_loudest_db > MIC_SILENT_DB else "no_signal"
	elif _check_clipped_frames > maxi(3, _check_speech_frames / 20): verdict = "too_loud"
	elif speech_db < MIC_GOOD_DB: verdict = "too_quiet"
	else: verdict = "good"
	return {"verdict": verdict, "speech_level_db": snappedf(speech_db, 0.1), "loudest_frame_db": snappedf(_check_loudest_db, 0.1),
		"speech_frames": _check_speech_frames, "frames": _check_frames, "clipped_frames": _check_clipped_frames,
		"good_threshold_db": MIC_GOOD_DB}

func end_mic_check() -> Dictionary:
	var result := mic_check_result()
	_check_active = false
	_log("microphone_check", result)
	return result

func _seal_microphone_capture() -> void:
	# Drain queued microphone samples using the old permission. A packet that
	# straddles the next opt-in boundary remains playable, but is not saved.
	if mic_enabled: _capture_microphone()
	_recording_source_cutoff = _source.size()


func _send_microphone_packet(pcm: PackedByteArray, source_recordable: bool = true) -> void:
	if not mic_enabled or _server_only: return
	_mixer.push(_local_peer, _sequence, pcm, _clock_frame(), recording_active and source_recordable)
	if _network != null: _network.send_voice(_sequence, pcm)

func _create_microphone() -> bool:
	if _microphone != null: return true
	if DisplayServer.get_name() == "headless":
		voice_error.emit("Microphone input is unavailable in headless mode.")
		return false
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		voice_error.emit("Microphone input is disabled in this game build.")
		return false
	_capture_bus = "TeamMic_%d" % get_instance_id()
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, _capture_bus)
	AudioServer.set_bus_send(bus, "Master")
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.2
	AudioServer.add_bus_effect(bus, _capture)
	AudioServer.set_bus_mute(bus, true) # Capture occurs before mute: no local mic echo.
	_microphone = AudioStreamPlayer.new()
	_microphone.stream = AudioStreamMicrophone.new()
	_microphone.bus = _capture_bus
	add_child(_microphone)
	_ensure_speaker()
	return true


func _ensure_speaker() -> void:
	if _speaker != null or _server_only or DisplayServer.get_name() == "headless": return
	_speaker = AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = RATE
	generator.buffer_length = 0.2
	_speaker.stream = generator
	_speaker.volume_linear = float(playback_level) / 50.0
	add_child(_speaker)
	_speaker.play()
	_playback = _speaker.get_stream_playback() as AudioStreamGeneratorPlayback


func _receive_voice(peer_id: int, sequence: int, pcm: PackedByteArray) -> void:
	if _server_only or peer_id == _local_peer: return
	_ensure_speaker()
	var allowed := recording_active and _network != null and bool(_network.voice_participants.get(peer_id, {}).get("consent", false))
	_mixer.push(peer_id, sequence, pcm, _clock_frame(), allowed)


func _publish_state() -> void:
	if _network != null and not _server_only:
		_network.set_voice_state(mic_enabled, recording_consent, recording_active)


func _roster_updated() -> void:
	var next_peer := multiplayer.get_unique_id() if _network.active else 1
	if next_peer != _local_peer:
		_mixer.reset(_cursor)
		_local_peer = next_peer
	_publish_state()
	_participants_updated()


func _participants_updated() -> void:
	if _network == null: return
	for peer_id in _mixer.streams.keys():
		if int(peer_id) != _local_peer and not _network.roster.has(peer_id):
			_mixer.remove_peer(int(peer_id))
		elif int(peer_id) != _local_peer and not bool(_network.voice_participants.get(peer_id, {}).get("consent", false)):
			_mixer.clear_recording_permission(int(peer_id))
	_log("participants", {"states": get_participants()})
	participants_changed.emit()
	_refresh_status()


func _disconnected() -> void:
	stop()
	_mixer.reset(_cursor)


func _recording_failed(message: String) -> void:
	if _writer != null:
		_writer.close_file()
		_writer = null
	recording_active = false
	recording_enabled = false
	_publish_state()
	recording_changed.emit(false, recording_path)
	voice_error.emit(message)
	_refresh_status()


func _timing() -> Dictionary:
	var context := _research_context.duplicate(true)
	context.merge({"local_elapsed_ms": Time.get_ticks_msec() - _session_start_ms,
		"session_seconds": _session_time, "context_age_ms": Time.get_ticks_msec() - _session_sync_ms,
		"capture_session_id": session_id}, true)
	return context


## One track per person, even when they reconnect with a new network id (2.11:
## a dropping player used to get a new full-length track for every reconnect).
func _speaker_key(peer_id: int) -> String:
	if peer_id == _local_peer: return StudyFiles.label(file_label) + "_voice" # 9.11: <name>_voice.wav
	if _network != null and _network.player_keys.has(peer_id): return "player_" + str(_network.player_keys[peer_id])
	if peer_id == _local_peer and _network != null and not _network.active and not _network.local_player_key.is_empty():
		return "player_" + _network.local_player_key
	return "peer_%d" % peer_id

func _speaker_identity(peer_id: int) -> Dictionary:
	return {"peer_id": peer_id, "speaker_id": _speaker_key(peer_id), "speaker_key": _speaker_key(peer_id),
		"display_name": _network.player_log_label(peer_id) if _network != null else "Player %d" % peer_id,
		"departments": _network.departments_for(peer_id) if _network != null else [],
		"local": peer_id == _local_peer,
		"player_key": str(_network.player_keys.get(peer_id, _network.local_player_key if peer_id == _local_peer else "")) if _network != null else ""}


func _log(event: String, data: Dictionary) -> void:
	if _writer != null:
		var context := _timing()
		context.merge(data, true)
		_writer.log_metadata(event, context)
		if not str(_writer.error).is_empty(): _recording_failed(str(_writer.error))


func _refresh_status() -> void:
	var text := "Voice chat enabled" if mic_enabled else "Voice chat disabled"
	if recording_active: text += " | Saving your voice"
	_set_status(text)


func _set_status(text: String) -> void:
	if text == status: return
	status = text
	status_changed.emit(text)


func _destroy_audio() -> void:
	if is_instance_valid(_microphone):
		_microphone.stop()
		_microphone.queue_free()
	_microphone = null
	if is_instance_valid(_speaker):
		_speaker.stop()
		_speaker.queue_free()
	_speaker = null
	_playback = null
	_capture = null
	var bus := AudioServer.get_bus_index(_capture_bus)
	if bus > 0: AudioServer.remove_bus(bus)
	_capture_bus = ""


static func _clock_frame() -> int:
	return int(Time.get_ticks_usec() * RATE / 1000000)


func _exit_tree() -> void:
	# Child audio nodes may already have left the tree; avoid network RPCs here.
	if _writer != null:
		_writer.close_file()
		_writer = null
	_destroy_audio()
