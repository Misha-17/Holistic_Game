extends Node
class_name ResearchRelay

# 2.11 (Andrei): "Only the host stores files." In a co-op game only the session
# leader's computer writes study files. Every other player's game hands its own
# study data (mouse, clicks, keys, selections, 60 Hz samples, questionnaire
# answers) to this relay instead of the disk; the relay sends it over the game
# connection and the leader stores it in research/<session>/players/<key>/.
#
# The research logger and the 60 Hz sampler write through RelayFile objects
# that look like the few FileAccess calls they use. The sampler writes from its
# own thread, so the outbox is guarded by a mutex and sent from _process.
# Nothing is written on this computer. If the leader cannot be reached the data
# waits in memory (up to MAX_QUEUED_BYTES) and is sent when they are back.

const MAX_QUEUED_BYTES := 64 * 1024 * 1024
const MAX_CHUNK_BYTES := 16 * 1024
const UPLOAD_BYTES_PER_SECOND := 64 * 1024
# Replacements remain atomic; allow credit to accumulate for a large survey/file.
const MAX_UPLOAD_CREDIT := NetworkSession.RESEARCH_RAW_MAX
var _upload_credit := 0.0
var _budget_ms := -1
const ROOT := "user://research/"

var network: NetworkSession
var sent_bytes := 0
var dropped_bytes := 0
var _outbox: Array[Dictionary] = [] # {rel, data, mode}
var _queued_bytes := 0
var _started: Dictionary = {} # rel paths this game has already sent to
var _mutex := Mutex.new()


class RelayFile extends RefCounted:
	var relay: ResearchRelay
	var rel := ""
	var mode := "append"
	var _content := ""
	var _existed := false

	func store_string(text: String) -> void:
		if text.is_empty(): return
		if mode == "append": relay.enqueue(rel, text.to_utf8_buffer(), "append")
		else: _content += text

	func store_line(text: String) -> void:
		store_string(text + "\n")

	func flush() -> void:
		pass

	func get_error() -> int:
		return OK

	func get_length() -> int:
		return 1 if _existed else 0

	func seek_end(_offset: int = 0) -> void:
		pass

	func close() -> void:
		if mode == "replace" and not _content.is_empty():
			relay.enqueue(rel, _content.to_utf8_buffer(), "replace")
		_content = ""


## A file-like writer for a research path. Paths below user://research/<session>/
## keep their place inside the player's folder on the leader's computer.
func open_file(path: String, append: bool) -> RelayFile:
	var file := RelayFile.new()
	file.relay = self
	file.rel = relative_path(path)
	file.mode = "append" if append else "replace"
	_mutex.lock()
	file._existed = _started.has(file.rel)
	_started[file.rel] = true
	_mutex.unlock()
	return file

## "user://research/session_x/levels/a_events.jsonl" -> "levels/a_events.jsonl".
static func relative_path(path: String) -> String:
	var rel := path.trim_prefix(ROOT)
	var slash := rel.find("/")
	return rel.substr(slash + 1) if slash >= 0 else rel

func send_file(rel: String, text: String) -> void:
	enqueue(rel, text.to_utf8_buffer(), "replace")

func enqueue(rel: String, data: PackedByteArray, mode: String) -> void:
	if data.is_empty(): return
	if mode == "append" and data.size() > MAX_CHUNK_BYTES:
		for offset in range(0, data.size(), MAX_CHUNK_BYTES):
			enqueue(rel, data.slice(offset, mini(offset + MAX_CHUNK_BYTES, data.size())), mode)
		return
	_mutex.lock()
	if _queued_bytes + data.size() > MAX_QUEUED_BYTES:
		dropped_bytes += data.size()
	else:
		# Consecutive appends to one file travel together.
		var last: Dictionary = _outbox.back() if not _outbox.is_empty() else {}
		if mode == "append" and not last.is_empty() and last.rel == rel and last.mode == "append" and (last.data as PackedByteArray).size() + data.size() <= MAX_CHUNK_BYTES:
			var merged: PackedByteArray = last.data
			merged.append_array(data)
			last.data = merged
		else:
			_outbox.append({"rel": rel, "data": data.duplicate(), "mode": mode})
		_queued_bytes += data.size()
	_mutex.unlock()

func pending_bytes() -> int:
	_mutex.lock()
	var total := _queued_bytes
	_mutex.unlock()
	return total

func clear() -> void:
	_mutex.lock()
	_outbox.clear()
	_queued_bytes = 0
	_started.clear()
	_mutex.unlock()

func _process(_delta: float) -> void:
	flush_now()

## Send what is queued, if the leader can be reached. Returns bytes sent.
func flush_now() -> int:
	var now := Time.get_ticks_msec()
	var elapsed := maxf(0.0, (now - _budget_ms) / 1000.0) if _budget_ms >= 0 else 0.0
	_budget_ms = now
	if network == null or not network.relay_ready() or network.connection_stalled():
		_upload_credit = 0.0
		return 0
	_upload_credit = minf(MAX_UPLOAD_CREDIT, _upload_credit + elapsed * UPLOAD_BYTES_PER_SECOND)
	var sent := 0
	while true:
		_mutex.lock()
		if _outbox.is_empty():
			_upload_credit = minf(_upload_credit, MAX_CHUNK_BYTES)
			_mutex.unlock()
			break
		if (_outbox[0].data as PackedByteArray).size() > _upload_credit:
			_mutex.unlock()
			break
		var item: Dictionary = _outbox.pop_front()
		if not item.is_empty(): _queued_bytes -= (item.data as PackedByteArray).size()
		_mutex.unlock()
		if item.is_empty(): break
		if not network.send_research(str(item.rel), item.data, str(item.mode)):
			# Not sendable now (connection just dropped): put it back for later.
			_mutex.lock()
			_outbox.push_front(item)
			_queued_bytes += (item.data as PackedByteArray).size()
			_mutex.unlock()
			break
		sent += (item.data as PackedByteArray).size()
		_upload_credit -= (item.data as PackedByteArray).size()
		break # At most one research message per frame.
	sent_bytes += sent
	return sent
