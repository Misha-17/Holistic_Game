extends SceneTree

const Net = preload("res://scripts/network_session.gd")
const Voice = preload("res://scripts/team_voice.gd")
var network: NetworkSession
var voice: TeamVoice
var is_server := false
var server_only := true
var legacy := false
var index := 0
var began := 0
var joined_at := -1
var next_send := 0
var sequence := 0
var sent_invalid := false
var peak_roster := 0
var saw_departure := false
var saw_consent := false
var received: Dictionary = {}
var bad_packets := 0
var errors: Array[String] = []
var done := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--voice-server": is_server = true
		if argument == "--desktop-host": server_only = false
		if argument == "--legacy": legacy = true
		if argument.begins_with("--index="): index = int(argument.trim_prefix("--index="))
	network = Net.new()
	root.add_child(network)
	network.voice_packet_received.connect(_packet_received)
	network.voice_participants_changed.connect(func():
		for peer_id in network.voice_participants:
			var state: Dictionary = network.voice_participants[peer_id]
			if state.mic and not state.consent: saw_consent = true)
	if is_server:
		if network.host(server_only) != OK:
			printerr("VOICE NETWORK TEST: could not bind")
			quit(1)
			return
	else:
		if legacy:
			network.multiplayer.connected_to_server.disconnect(network._connected)
			network.multiplayer.connected_to_server.connect(func(): network._hello.rpc_id(1, 1))
		network.join("127.0.0.1:%d" % network.port)
	if not (is_server and server_only) and not legacy:
		voice = Voice.new()
		root.add_child(voice)
		voice.configure(network)
		voice.set_recording_consent(index != 3)
		voice.set_recording_enabled(true)
		# Synthetic fixture, no physical microphone: mark sender enabled and feed
		# known PCM through the identical mixer and actual network RPC path.
		voice.mic_enabled = true
		voice._publish_state()
		voice.start("network_%d_%d" % [network.port, index])
	began = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if network == null or done: return false
	var now := Time.get_ticks_msec()
	var elapsed := now - began
	peak_roster = maxi(peak_roster, network.roster.size())
	if peak_roster == 4 and network.roster.size() < 4: saw_departure = true
	if legacy:
		if elapsed > 1200:
			done = true
			var success := network.roster.is_empty() and not network.active
			print("VOICE LEGACY REJECTION: ", "PASS" if success else "FAIL")
			quit(0 if success else 1)
		return false
	if network.roster.has(network.multiplayer.get_unique_id()) and joined_at < 0:
		joined_at = now
		if voice != null: voice._publish_state()
	if voice != null and joined_at >= 0 and now >= next_send:
		next_send = now + 20
		sequence += 1
		var pcm := PackedByteArray()
		pcm.resize(640)
		var level := 1000 * (1 << index)
		for sample in range(320): pcm.encode_s16(sample * 2, level)
		voice._mixer.push(network.multiplayer.get_unique_id(), sequence, pcm, voice._clock_frame())
		network.send_voice(sequence, pcm)
		if not is_server and not sent_invalid and elapsed > 2000:
			sent_invalid = true
			var invalid := PackedByteArray()
			invalid.resize(10)
			network._voice_upload.rpc_id(1, sequence + 10, invalid)
			network._voice_upload.rpc_id(1, -1, pcm)
			network._voice_upload.rpc_id(1, sequence, pcm) # Already accepted: duplicate.
	if elapsed > (9000 if is_server else (3000 if index == 3 else 5000)):
		_finish()
	return false


func _packet_received(peer_id: int, packet_sequence: int, pcm: PackedByteArray) -> void:
	if peer_id == network.multiplayer.get_unique_id() or pcm.size() != 640 or packet_sequence < 0:
		bad_packets += 1
		return
	var state: Dictionary = received.get(peer_id, {"count": 0, "last": -1})
	if packet_sequence <= int(state.last): bad_packets += 1
	state.last = packet_sequence
	state.count = int(state.count) + 1
	received[peer_id] = state


func _finish() -> void:
	done = true
	if peak_roster != 4: errors.append("four-player roster was not reached")
	if bad_packets != 0: errors.append("invalid, duplicate or loopback audio delivered")
	if not saw_consent: errors.append("recording consent did not reach participant")
	if is_server and server_only:
		if not received.is_empty(): errors.append("dedicated server received playback audio")
		if DirAccess.dir_exists_absolute("user://research/voice"): errors.append("dedicated server created voice files")
	else:
		if received.size() != 3: errors.append("did not hear all three other players")
		for peer_id in received:
			if int(received[peer_id].count) < 15: errors.append("too few audio packets received")
		voice.stop()
		var data := FileAccess.get_file_as_bytes(voice.recording_path)
		if data.size() < 6400 or data.decode_u32(40) != data.size() - 44: errors.append("invalid local WAV")
		var maximum := 0
		for offset in range(44, data.size(), 2): maximum = maxi(maximum, data.decode_s16(offset))
		if maximum <= 1000 * (1 << index): errors.append("remote voice missing from local mixed file")
		if index != 3 and maximum > 7000: errors.append("unconsenting participant was included in local recording")
		voice.shutdown()
	if index != 3 and not saw_departure: errors.append("peer departure was not observed")
	network.close()
	for error in errors: printerr("FAIL: ", error)
	print("VOICE NETWORK TEST: ", "PASS" if errors.is_empty() else "FAIL", " server=", is_server, " dedicated=", server_only, " index=", index, " received=", received.size())
	quit(0 if errors.is_empty() else 1)
