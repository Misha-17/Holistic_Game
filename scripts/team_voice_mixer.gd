extends RefCounted

# A bounded, sample-clocked jitter buffer shared by playback and recording.
# Missing packets remain silence; packets are never replayed to fill a gap.
const RATE := 16000
const FRAMES := 320
const JITTER := 960 # 60 ms
const MAX_AHEAD := 6400 # 400 ms
const MAX_PACKETS := 24

var streams: Dictionary = {}
var cursor := 0


func reset(at_frame: int) -> void:
	streams.clear()
	cursor = at_frame


func remove_peer(peer_id: int) -> void:
	streams.erase(peer_id)


func push(peer_id: int, sequence: int, pcm: PackedByteArray, now_frame: int) -> bool:
	if pcm.size() != FRAMES * 2 or sequence < 0 or peer_id <= 0: return false
	var state: Dictionary = streams.get(peer_id, {})
	if not state.is_empty() and sequence <= int(state.last): return false
	if state.is_empty():
		state = {"first": sequence, "last": -1, "anchor": now_frame + JITTER, "packets": []}
	var begins := int(state.anchor) + (sequence - int(state.first)) * FRAMES
	if begins < cursor or begins > now_frame + MAX_AHEAD:
		# Long mute, dropped packets or a suspended client: restart a short buffer.
		state = {"first": sequence, "last": -1, "anchor": now_frame + JITTER, "packets": []}
		begins = now_frame + JITTER
	state.last = sequence
	var packets: Array = state.packets
	while not packets.is_empty() and int(packets[0].at) + FRAMES <= cursor:
		packets.pop_front()
	if packets.size() >= MAX_PACKETS: return false
	packets.append({"at": begins, "pcm": pcm})
	state.packets = packets
	streams[peer_id] = state
	return true


func render(at_frame: int, local_peer: int, recording_permissions: Dictionary) -> Dictionary:
	var audible := PackedFloat32Array()
	var recorded := PackedFloat32Array()
	audible.resize(FRAMES)
	recorded.resize(FRAMES)
	for peer_id in streams:
		var state: Dictionary = streams[peer_id]
		var packets: Array = state.packets
		while not packets.is_empty() and int(packets[0].at) + FRAMES <= at_frame:
			packets.pop_front()
		var save_voice := bool(recording_permissions.get(peer_id, false))
		for packet: Dictionary in packets:
			var begins: int = int(packet.at)
			if begins >= at_frame + FRAMES: break
			var pcm: PackedByteArray = packet.pcm
			for index in range(maxi(0, begins - at_frame), mini(FRAMES, begins + FRAMES - at_frame)):
				var sample := float(pcm.decode_s16((at_frame + index - begins) * 2)) / 32768.0
				if int(peer_id) != local_peer: audible[index] += sample
				if save_voice: recorded[index] += sample
	var stereo := PackedVector2Array()
	var output := PackedByteArray()
	stereo.resize(FRAMES)
	output.resize(FRAMES * 2)
	for index in range(FRAMES):
		var level := clampf(audible[index], -1.0, 1.0)
		stereo[index] = Vector2(level, level)
		output.encode_s16(index * 2, clampi(roundi(recorded[index] * 32768.0), -32768, 32767))
	cursor = at_frame + FRAMES
	return {"playback": stereo, "recording": output}
