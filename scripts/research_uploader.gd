extends Node
class_name ResearchUploader

# Sends finished research files to the study server (the dedicated Azure game
# server) so the researcher can collect them without any work from players
# (Andrei, 30.10). Files are uploaded in the background while the player is
# connected to a dedicated server; anything not yet sent stays queued on disk
# and resumes on the next connection to that server, even after a restart.
#
# Each file is uploaded incrementally:
#   append  - event logs (*.jsonl) and audio (*.wav) only send the new bytes;
#             for a WAV the 44-byte header is re-sent last, so the server copy
#             always has the right length.
#   replace - small JSON/HTML files are re-sent whole when they change.
# The server acknowledges every chunk; progress is stored after each file.

const STATE_PATH := "user://research/upload_state.json"
var state_path := STATE_PATH # tests use their own
const CHUNK_BYTES := 32768
const WINDOW := 4 # chunks in flight
const PLAYING_INTERVAL_S := 0.08 # at most ~400 KB/s while a level is running
const WAV_HEADER_BYTES := 44

var uploader_id := ""
var last_error := ""
var _network: NetworkSession
var _files: Dictionary = {} # local path -> {remote, mode, acked, synced_size, synced_md5}
var _dirty: Array[String] = []
var _current := ""
var _target := 0
var _header_pending := false
var _in_flight := 0
var _next_offset := 0
var _status_requested := false
var _last_chunk_ms := 0
## Set by main.gd: true while a level is being played (uploads slow down).
var playing := false
## False under test scripts (main.gd), so tests never queue fake sessions in a
## developer's real upload queue. Tests that need it set a temporary state_path.
var enabled := true

func configure(network: NetworkSession) -> void:
	_network = network
	network.research_ack.connect(_on_ack)
	network.research_status.connect(_on_status)
	network.disconnected.connect(_on_disconnected)
	_load_state()

# Queue every research file in a folder (recursively). Names are kept relative
# to the folder under `remote_prefix` on the server.
func sync_folder(local_dir: String, remote_prefix: String, only: PackedStringArray = PackedStringArray()) -> void:
	var directory := DirAccess.open(local_dir)
	if directory == null: return
	for name: String in directory.get_files():
		if not only.is_empty() and not only.has(name): continue
		if not _uploadable(name): continue
		sync_file(local_dir.path_join(name), remote_prefix.path_join(name))
	if only.is_empty():
		for child: String in directory.get_directories():
			sync_folder(local_dir.path_join(child), remote_prefix.path_join(child))

func sync_file(local_path: String, remote_path: String) -> void:
	if not enabled or not FileAccess.file_exists(local_path) or not _valid_remote(remote_path): return
	var entry: Dictionary = _files.get(local_path, {})
	if entry.is_empty():
		entry = {"remote": remote_path, "mode": "append" if local_path.get_extension() in ["jsonl", "wav"] else "replace",
			"acked": 0, "synced_size": -1, "synced_md5": ""}
		_files[local_path] = entry
	if not _dirty.has(local_path): _dirty.append(local_path)
	_save_state()

func remote_session_prefix(session_id: String) -> String:
	return "%s/%s" % [_clean(session_id if not session_id.is_empty() else "no_session"), uploader_id]

func pending_bytes() -> int:
	var total := 0
	for local_path: String in _dirty:
		var entry: Dictionary = _files.get(local_path, {})
		var length := _length(local_path)
		total += maxi(0, length - (int(entry.get("acked", 0)) if entry.get("mode") == "append" else 0))
	return total

func is_idle() -> bool:
	return _dirty.is_empty() and _current.is_empty()

func status_text() -> String:
	if not last_error.is_empty(): return "Study upload: " + last_error
	if is_idle(): return "No study files waiting to be sent." if _files.is_empty() else "All study files are on the study server."
	var mb := float(pending_bytes()) / 1048576.0
	if _network == null or not _network.research_upload_ready():
		return "%.1f MB of study files wait for the next connection to the study server." % mb
	return "Sending study files to the study server… %.1f MB left." % mb

func _process(_delta: float) -> void:
	if _network == null or not _network.research_upload_ready():
		return
	if not _status_requested:
		var remotes: Array[String] = []
		for local_path: String in _dirty: remotes.append(str(_files[local_path].remote))
		if remotes.is_empty(): return
		_status_requested = true
		_network.request_research_status(remotes)
		return
	if _current.is_empty() and not _start_next_file(): return
	while _in_flight < WINDOW:
		if playing and Time.get_ticks_msec() - _last_chunk_ms < int(PLAYING_INTERVAL_S * 1000.0): return
		if not _send_next_chunk(): return

func _start_next_file() -> bool:
	while not _dirty.is_empty():
		var local_path: String = _dirty[0]
		var entry: Dictionary = _files.get(local_path, {})
		var length := _length(local_path)
		# Small JSON/HTML files: compare content, since file times have 1 s resolution.
		var digest := FileAccess.get_md5(local_path) if entry.get("mode") == "replace" else ""
		if length < 0 or entry.is_empty():
			_dirty.remove_at(0)
			continue
		if entry.mode == "replace":
			if length == int(entry.synced_size) and digest == str(entry.get("synced_md5", "")):
				_dirty.remove_at(0)
				continue
			entry.acked = 0
		elif length <= int(entry.acked):
			_dirty.remove_at(0)
			continue
		_current = local_path
		_target = length
		_next_offset = maxi(0, int(entry.acked))
		_header_pending = local_path.get_extension() == "wav" and entry.mode == "append"
		entry["pending_md5"] = digest
		return true
	return false

func _send_next_chunk() -> bool:
	if _current.is_empty(): return false
	var entry: Dictionary = _files[_current]
	if _next_offset >= _target:
		if _header_pending and _in_flight == 0 and int(entry.acked) >= _target:
			_header_pending = false
			var header := _read(_current, 0, WAV_HEADER_BYTES)
			if header.size() == WAV_HEADER_BYTES:
				_network.send_research_chunk(str(entry.remote), 0, header, false)
				_in_flight += 1
				return true
		return false
	var amount := mini(CHUNK_BYTES, _target - _next_offset)
	var data := _read(_current, _next_offset, amount)
	if data.size() != amount:
		last_error = "could not read " + _current.get_file()
		_finish_current()
		return false
	var truncate: bool = entry.mode == "replace" and _next_offset == 0
	_network.send_research_chunk(str(entry.remote), _next_offset, data, truncate)
	_next_offset += amount
	_in_flight += 1
	_last_chunk_ms = Time.get_ticks_msec()
	return true

func _on_ack(remote_path: String, end: int, ok: bool, message: String) -> void:
	_in_flight = maxi(0, _in_flight - 1)
	if _current.is_empty() or str(_files[_current].remote) != remote_path: return
	var entry: Dictionary = _files[_current]
	if not ok:
		last_error = message
		_finish_current()
		return
	last_error = ""
	if end > WAV_HEADER_BYTES or not entry.mode == "append" or end >= _target: entry.acked = maxi(int(entry.acked), end)
	if int(entry.acked) >= _target and not _header_pending and _in_flight == 0:
		entry.synced_size = _target
		entry["synced_md5"] = str(entry.get("pending_md5", ""))
		_dirty.erase(_current)
		_finish_current()

func _on_status(sizes: Dictionary) -> void:
	# The server reports how much of each file it already has (for example
	# after a restart of either side). Never assume more than it has.
	for local_path: String in _files:
		var entry: Dictionary = _files[local_path]
		var remote := str(entry.remote)
		if not sizes.has(remote): continue
		var have := int(sizes[remote]) # -1: the server has no copy yet
		if entry.mode == "append": entry.acked = clampi(have, 0, int(entry.acked))
		elif have < 0: entry.synced_size = -1
	_save_state()

func _on_disconnected() -> void:
	_status_requested = false
	_in_flight = 0
	_finish_current()

func _finish_current() -> void:
	_current = ""
	_target = 0
	_next_offset = 0
	_header_pending = false
	_save_state()

func _length(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return -1
	var length := int(file.get_length())
	file.close()
	return length

func _read(path: String, offset: int, amount: int) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return PackedByteArray()
	file.seek(offset)
	var data := file.get_buffer(amount)
	file.close()
	return data

static func _uploadable(name: String) -> bool:
	return name.get_extension() in ["jsonl", "json", "wav", "html"] and not name.ends_with(".tmp") and name != "upload_state.json"

static func _clean(text: String) -> String:
	var result := ""
	for character in text:
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.": result += character
	return result.left(96)

static func _valid_remote(path: String) -> bool:
	return NetworkSession.valid_research_path(path)

func _load_state() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(state_path)) if FileAccess.file_exists(state_path) else null
	if data is Dictionary:
		uploader_id = str(data.get("uploader_id", ""))
		_files = data.get("files", {})
		for local_path in data.get("dirty", []): _dirty.append(str(local_path))
	if uploader_id.is_empty():
		uploader_id = "pc_" + Crypto.new().generate_random_bytes(5).hex_encode()
		_save_state()

func _save_state() -> void:
	DirAccess.make_dir_recursive_absolute(state_path.get_base_dir())
	var file := FileAccess.open(state_path, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"uploader_id": uploader_id, "files": _files, "dirty": _dirty}, "\t"))
	file.close()
