extends SceneTree
const Mixer = preload("res://scripts/team_voice_mixer.gd")

func _initialize() -> void:
	var baseline := measure(false)
	var delayed := measure(true)
	print("VOICE CONTINUITY: baseline_silent_blocks=", baseline, " delayed_silent_blocks=", delayed, " block_ms=20; three remote speakers, 100ms delivery stalls, no packet loss")
	if baseline != 0 or delayed != 0:
		printerr("FAIL: lossless delivery stalls introduced silence")
		quit(1)
		return
	print("VOICE CONTINUITY TEST: PASS")
	quit(0)

func measure(delayed: bool) -> int:
	var mixer = Mixer.new()
	var pending: Array[Dictionary] = []
	var pcm := PackedByteArray()
	pcm.resize(640)
	for i in 320: pcm.encode_s16(i * 2, 1000)
	var silent := 0
	for tick in 250:
		for peer in [2, 3, 4]:
			pending.append({"peer": peer, "sequence": tick})
		# Hold packets for five 20ms blocks every second, then release in order.
		if not delayed or tick % 50 < 20 or tick % 50 >= 25:
			for packet in pending:
				mixer.push(packet.peer, packet.sequence, pcm, tick * 320)
			pending.clear()
		var mixed: Dictionary = mixer.render(tick * 320, 1, {})
		if tick >= 10 and mixed.playback[0].x == 0.0: silent += 1
	return silent
