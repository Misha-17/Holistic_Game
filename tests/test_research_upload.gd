extends SceneTree

# Research files reach the study server without work from players (Andrei,
# 30.10). A real dedicated server and client talk over ENet on localhost:
# full upload, incremental append (event log and WAV), resume after a
# disconnect, and refusal of paths outside the upload folder.
# Run: godot --headless --path . -s tests/test_research_upload.gd

class TestNetwork extends NetworkSession:
	func _start_upnp() -> void:
		pass

const PORT := 27951
var failures: Array[String] = []
var branches: Array[Node] = []
var base := "user://upload_test_%d" % Time.get_ticks_usec()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func make_peer(label: String) -> TestNetwork:
	var branch := Node.new()
	branch.name = label
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var session := TestNetwork.new()
	branch.add_child(session)
	branches.append(branch)
	return session

func wait_until(condition: Callable, seconds: float = 10.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if condition.call(): return true
		await create_timer(0.02).timeout
	return false

func write_bytes(path: String, data: PackedByteArray, append: bool = false) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.READ_WRITE if append and FileAccess.file_exists(path) else FileAccess.WRITE)
	if append: file.seek_end()
	file.store_buffer(data)
	file.close()

func wav_bytes(frames: int, seed: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(44 + frames * 2)
	for i in frames: data.encode_s16(44 + i * 2, int((i * 37 + seed) % 2000) - 1000)
	_wav_header(data, frames * 2)
	return data

func _wav_header(data: PackedByteArray, data_bytes: int) -> void:
	data.encode_u32(0, 0x46464952) # RIFF
	data.encode_u32(4, 36 + data_bytes)
	data.encode_u32(8, 0x45564157) # WAVE
	data.encode_u32(36, 0x61746164) # data
	data.encode_u32(40, data_bytes)

func same(local: String, remote: String) -> bool:
	if not FileAccess.file_exists(remote): return false
	return FileAccess.get_file_as_bytes(local) == FileAccess.get_file_as_bytes(remote)

func connect_client(client: TestNetwork) -> bool:
	check(client.join("127.0.0.1:%d" % PORT) == OK, "client connects")
	return await wait_until(func(): return client.roster.has(client.multiplayer.get_unique_id()) and client.dedicated)

func run() -> void:
	var server := make_peer("Server")
	server.port = PORT
	server.research_root = ProjectSettings.globalize_path(base + "/server")
	check(server.host(true) == OK, "dedicated server starts")
	var client := make_peer("Client")
	check(await connect_client(client), "client joins the dedicated server")
	var uploader := ResearchUploader.new()
	uploader.state_path = base + "/client/upload_state.json"
	branches[1].add_child(uploader)
	uploader.configure(client)
	check(uploader.uploader_id.begins_with("pc_"), "each computer has an upload id")

	# A session as the game writes it: events, a level file, a manifest, a voice track.
	var session := base + "/client/research/session_test_1"
	var voice := base + "/client/research/voice/team_session_test_1_ab12"
	var log_line := '{"event":"mouse_motion","x":1}\n'.to_utf8_buffer()
	var events := PackedByteArray()
	for i in 3000: events.append_array(log_line)
	write_bytes(session + "/session_events.jsonl", events)
	write_bytes(session + "/levels/level6_events.jsonl", events.slice(0, 40000))
	write_bytes(session + "/manifest.json", '{"levels":1}'.to_utf8_buffer())
	write_bytes(voice + "/peer_7.wav", wav_bytes(48000, 1))
	write_bytes(voice + "/peer_9.wav", wav_bytes(48000, 2)) # a teammate's track
	write_bytes(voice + "/session.json", '{"tracks":2}'.to_utf8_buffer())
	var prefix := uploader.remote_session_prefix("session_test_1")
	uploader.sync_folder(session, prefix + "/events")
	uploader.sync_folder(voice, prefix + "/voice", PackedStringArray(["session.json", "peer_7.wav"]))
	check(uploader.pending_bytes() > 100000, "files are queued")
	check(await wait_until(func(): return uploader.is_idle()), "queue drains")
	var remote := ProjectSettings.globalize_path(base + "/server").path_join(prefix)
	check(same(session + "/session_events.jsonl", remote + "/events/session_events.jsonl"), "event log arrives byte for byte")
	check(same(session + "/levels/level6_events.jsonl", remote + "/events/levels/level6_events.jsonl"), "level file arrives")
	check(same(session + "/manifest.json", remote + "/events/manifest.json"), "manifest arrives")
	check(same(voice + "/peer_7.wav", remote + "/voice/peer_7.wav"), "own voice track arrives")
	check(not FileAccess.file_exists(remote + "/voice/peer_9.wav"), "teammates' tracks are not sent by this computer")

	# Next level: logs and audio grow; only new bytes go up, the WAV header last.
	write_bytes(session + "/session_events.jsonl", events.slice(0, 50000), true)
	var longer := wav_bytes(96000, 1)
	write_bytes(voice + "/peer_7.wav", longer)
	write_bytes(session + "/manifest.json", '{"levels":2}'.to_utf8_buffer())
	uploader.sync_folder(session, prefix + "/events")
	uploader.sync_folder(voice, prefix + "/voice", PackedStringArray(["session.json", "peer_7.wav"]))
	var pending := uploader.pending_bytes()
	check(pending < 50000 + 96000 * 2 + 4000, "only the new part is pending (%d bytes)" % pending)
	check(await wait_until(func(): return uploader.is_idle()), "second sync drains")
	check(same(session + "/session_events.jsonl", remote + "/events/session_events.jsonl"), "appended log matches")
	check(same(voice + "/peer_7.wav", remote + "/voice/peer_7.wav"), "grown WAV matches, header included")
	check(same(session + "/manifest.json", remote + "/events/manifest.json"), "changed manifest replaced")

	# Disconnect in the middle of a large file, then reconnect: it resumes.
	var big := PackedByteArray()
	big.resize(3 * 1024 * 1024)
	for i in big.size(): big[i] = i % 251
	write_bytes(session + "/levels/level7_events.jsonl", big)
	uploader.sync_folder(session, prefix + "/events")
	check(await wait_until(func(): return uploader.pending_bytes() < big.size() - 200000), "large file starts uploading")
	client.close()
	check(await wait_until(func(): return not client.active), "client disconnects mid-upload")
	check(not uploader.is_idle(), "unfinished file stays queued")
	var restarted := ResearchUploader.new()
	restarted.state_path = uploader.state_path
	uploader.queue_free()
	branches[1].add_child(restarted)
	restarted.configure(client)
	check(restarted.uploader_id == uploader.uploader_id and not restarted.is_idle(), "queue survives a restart of the game")
	check(await connect_client(client), "client reconnects")
	check(await wait_until(func(): return restarted.is_idle(), 20.0), "resumed upload drains")
	check(same(session + "/levels/level7_events.jsonl", remote + "/events/levels/level7_events.jsonl"), "resumed file matches")

	# The server refuses anything outside its upload folder.
	var refused: Array = []
	client.research_ack.connect(func(path, _end, ok, _msg): if not ok: refused.append(path))
	check(not NetworkSession.valid_research_path("../../etc/x.json") and not NetworkSession.valid_research_path("a/b/run.sh"), "path rules")
	client._research_chunk.rpc_id(1, "s/pc/../../../escape.json", 0, PackedByteArray([1]), true)
	client._research_chunk.rpc_id(1, "s/pc/evil.sh", 0, PackedByteArray([1]), true)
	check(await wait_until(func(): return refused.size() == 2), "server refuses bad paths")
	check(not FileAccess.file_exists(ProjectSettings.globalize_path(base).path_join("escape.json")), "nothing written outside")

	client.close()
	server.close()
	await create_timer(0.1).timeout
	for branch in branches:
		set_multiplayer(null, branch.get_path())
		branch.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: research files upload to the study server incrementally, resume after disconnects and stay inside the upload folder")
	quit(0 if failures.is_empty() else 1)
