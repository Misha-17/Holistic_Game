extends SceneTree

# The microphone check grades what was heard (mid-term report, Table A4:
# one microphone was very quiet). Synthetic levels are fed straight into the
# meter; the real capture path calls the same _meter_packet() per 20 ms frame.
# Run: godot --headless --path . -s tests/test_mic_check.gd
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func feed(voice: TeamVoice, db: float, frames: int, peak_db: float = -99.0) -> void:
	var rms := 32768.0 * pow(10.0, db / 20.0)
	var peak := int(32768.0 * pow(10.0, maxf(db + 3.0, peak_db) / 20.0))
	for i in frames: voice._meter_packet(rms, mini(peak, 32767))

func run() -> void:
	var voice := TeamVoice.new()
	root.add_child(voice)
	voice.mic_enabled = true # No audio device in tests; the meter is exercised directly.
	voice.begin_mic_check()
	check(voice.mic_check_result().verdict == "no_signal", "Nothing heard yet")
	feed(voice, -75.0, 100)
	check(voice.mic_check_result().verdict == "no_signal", "Room noise only is no signal")
	feed(voice, -42.0, 150)
	var quiet := voice.mic_check_result()
	check(quiet.verdict == "too_quiet", "Speech at -42 dBFS is too quiet (got %s)" % quiet.verdict)
	voice.begin_mic_check()
	feed(voice, -20.0, 150)
	feed(voice, -70.0, 100)
	var good := voice.mic_check_result()
	check(good.verdict == "good" and absf(float(good.speech_level_db) + 20.0) < 1.0, "Speech at -20 dBFS passes (%s, %s)" % [good.verdict, good.speech_level_db])
	check(voice.input_level_db < -20.0, "Meter falls back after speech")
	voice.begin_mic_check()
	feed(voice, -20.0, 5)
	check(voice.mic_check_result().verdict == "waiting", "A single short sound is not enough")
	voice.begin_mic_check()
	feed(voice, -6.0, 150, 0.0)
	check(voice.mic_check_result().verdict == "too_loud", "Clipping is reported")
	var ended := voice.end_mic_check()
	check(ended.has("speech_level_db") and ended.has("good_threshold_db"), "Result carries the measured level and threshold")
	voice.mic_enabled = false
	check(voice.mic_check_result().verdict == "microphone_off", "Microphone off is reported")
	voice.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: microphone check grades silence, quiet, good and clipping speech levels")
	quit(0 if failures.is_empty() else 1)
