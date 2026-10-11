extends RefCounted

const RATE := 16000
const MAX_DATA_BYTES := 0x7ffff000
var path := ""
var bytes_written := 0
var error := ""
var _file: FileAccess
var _metadata: FileAccess
var _checkpoint_bytes := 0


func open_file(destination: String, metadata: Dictionary) -> bool:
	path = destination
	bytes_written = 0
	_checkpoint_bytes = 0
	error = ""
	if FileAccess.file_exists(path):
		error = "A voice file with this name already exists."
		return false
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK and err != ERR_ALREADY_EXISTS:
		error = "Could not create the local voice folder."
		return false
	_file = FileAccess.open(path, FileAccess.WRITE_READ)
	if _file == null:
		error = "Could not open a local voice recording."
		return false
	_write_header(_file, 0)
	_file.flush()
	var marker := FileAccess.open(path + ".open", FileAccess.WRITE)
	if marker == null:
		error = "Could not create the voice recovery marker."
		close_file()
		return false
	marker.store_string(JSON.stringify({"format": "beacon-bay-pcm16-v1", "pid": OS.get_process_id()}))
	marker.close()
	_metadata = FileAccess.open(path.get_basename() + ".jsonl", FileAccess.WRITE)
	if _metadata == null:
		error = "Could not open voice timing metadata."
		close_file()
		return false
	log_metadata("recording_open", metadata)
	return true


func append(pcm: PackedByteArray) -> bool:
	if _file == null: return false
	if pcm.size() % 2 != 0 or bytes_written + pcm.size() > MAX_DATA_BYTES:
		error = "Voice recording reached its file limit."
		return false
	_file.store_buffer(pcm)
	if _file.get_error() != OK:
		error = "Could not write voice audio to disk."
		return false
	bytes_written += pcm.size()
	if bytes_written - _checkpoint_bytes >= RATE * 2:
		checkpoint()
	return true


func append_silence(frames: int) -> bool:
	var silence := PackedByteArray()
	silence.resize(mini(RATE, frames) * 2)
	while frames > 0:
		var count := mini(frames, RATE)
		if not append(silence if count == silence.size() / 2 else silence.slice(0, count * 2)): return false
		frames -= count
	return true


func checkpoint() -> void:
	if _file == null: return
	_file.flush()
	_write_header(_file, bytes_written)
	_file.seek(44 + bytes_written)
	_file.flush()
	_checkpoint_bytes = bytes_written
	if _metadata != null: _metadata.flush()


func log_metadata(event: String, data: Dictionary) -> void:
	if _metadata == null: return
	_metadata.store_line(JSON.stringify({"event": event, "audio_frame": bytes_written / 2, "data": data}))
	_metadata.flush()


func close_file() -> void:
	if _file != null:
		log_metadata("recording_closed", {"frames": bytes_written / 2, "sample_rate": RATE})
		checkpoint()
		_file.close()
		_file = null
		DirAccess.remove_absolute(path + ".open")
	if _metadata != null:
		_metadata.close()
		_metadata = null


static func _write_header(file: FileAccess, size: int) -> void:
	file.seek(0)
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + size)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(RATE)
	file.store_32(RATE * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(size)


static func recover_pending(folder: String) -> int:
	var directory := DirAccess.open(folder)
	if directory == null: return 0
	var recovered := 0
	for marker: String in directory.get_files():
		if not marker.ends_with(".wav.open"): continue
		var marker_path := folder.path_join(marker)
		var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker_path))
		if not info is Dictionary or info.get("format") != "beacon-bay-pcm16-v1": continue
		var owner_pid := int(info.get("pid", -1))
		if owner_pid > 0 and OS.is_process_running(owner_pid): continue
		var wav_path := marker_path.trim_suffix(".open")
		var file := FileAccess.open(wav_path, FileAccess.READ_WRITE)
		if file == null or file.get_length() < 44: continue
		var header := file.get_buffer(44)
		if header.slice(0, 4).get_string_from_ascii() != "RIFF" or header.slice(8, 16).get_string_from_ascii() != "WAVEfmt " or header.slice(36, 40).get_string_from_ascii() != "data":
			file.close()
			continue
		var size := mini(int(file.get_length()) - 44, MAX_DATA_BYTES)
		size -= size % 2
		_write_header(file, size)
		file.flush()
		file.close()
		DirAccess.remove_absolute(marker_path)
		recovered += 1
	return recovered
