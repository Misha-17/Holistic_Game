extends SceneTree

# Settings → Devices (22.11): dropdown lists for microphone, sound output
# (headset/speakers) and monitor, with readable names; saved on this computer. Also checks the boost rename
# (COFFEE BOOST → SPEED BOOST; the research names "special"/"rally" stay).
# Run: godot --headless --path . -s tests/test_device_settings.gd
var failures: Array[String] = []
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func button_ids() -> Array:
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	return game.buttons.map(func(b): return str(b.id))

func test_devices_tab() -> void:
	game.screen = "settings"
	game.previous_screen = "title"
	game._action("settings_tab:devices")
	game._update_visibility()
	check(game.settings_tab == "devices", "Devices tab opens")
	check(not game.sound_settings.visible, "Volume sliders are not shown on Devices")
	check(game.device_pickers.visible, "Device dropdowns are shown on Devices")
	var ids: Array = await button_ids()
	check(ids.has("settings_tab:devices") and ids.has("device_test_sound"), "Devices tab has its tab button and PLAY TEST SOUND: %s" % [ids])
	check(not ids.any(func(id): return str(id).begins_with("device:")), "No < > arrow buttons any more")
	# Each dropdown sits inside its card, below the title, and on no drawn button.
	var rows: Dictionary = game._device_rows()
	for kind in ["input", "output", "monitor"]:
		var picker: OptionButton = game.device_pickers.pickers[kind]
		var rect := Rect2(game.device_pickers.position + picker.position, picker.size)
		var card := Rect2(Vector2(game.SETTINGS_COL[0], rows[kind]), game.SETTINGS_CARD)
		check(card.encloses(rect), "%s dropdown inside its card: %s in %s" % [kind, rect, card])
		check(picker.item_count >= 1, "%s dropdown lists at least one device" % kind)
		check(picker.selected >= 0, "%s dropdown shows the current device" % kind)
		check(not picker.get_item_text(picker.selected).is_empty(), "%s dropdown shows a name" % kind)
		for b in game.buttons:
			check(not Rect2(b.rect).intersects(rect), "%s dropdown does not cover button %s" % [kind, b.id])
	for a in game.buttons:
		for b in game.buttons:
			if a != b and Rect2(a.rect).intersects(Rect2(b.rect)):
				check(false, "Buttons overlap: %s and %s" % [a.id, b.id])
	for b in game.buttons:
		check(game.VIEW.encloses(Rect2(b.rect)), "Button %s on screen" % b.id)
	game._action("settings_tab:video")
	game._update_visibility()
	check(not game.device_pickers.visible, "Dropdowns hidden on other tabs")
	game._action("settings_tab:devices")
	game._update_visibility()

func test_choosing_and_saving() -> void:
	var inputs: PackedStringArray = DeviceSettings.inputs()
	var outputs: PackedStringArray = DeviceSettings.outputs()
	check(not inputs.is_empty() and not outputs.is_empty(), "Device lists are never empty (at least Default)")
	var picker: OptionButton = game.device_pickers.pickers["output"]
	picker.select(0)
	picker.item_selected.emit(0)
	check(DeviceSettings.output_device() in outputs, "Picking from the output list sets an existing device")
	game.device_pickers.pickers["input"].item_selected.emit(0)
	check(DeviceSettings.input_device() in inputs, "Picking from the microphone list sets an existing device")
	game.device_pickers.pickers["monitor"].item_selected.emit(0)
	check(DeviceSettings.monitor() == 0, "Monitor stays valid")
	game._action("device_test_sound")
	check(FileAccess.file_exists(DeviceSettings.PATH), "Device choices saved on this computer")
	var config := ConfigFile.new()
	check(config.load(DeviceSettings.PATH) == OK and config.has_section_key("devices", "input") and config.has_section_key("devices", "output") and config.has_section_key("devices", "monitor"), "Saved file has microphone, output and monitor")
	config.set_value("devices", "input", "Unplugged USB microphone")
	config.set_value("devices", "output", "Unplugged headset")
	config.set_value("devices", "monitor", 7)
	config.save(DeviceSettings.PATH)
	DeviceSettings.load_and_apply()
	check(DeviceSettings.input_device() in inputs and DeviceSettings.output_device() in outputs, "Missing devices fall back to an available one")

func test_readable_names() -> void:
	# Linux gives ids; the readable names come from `pactl list` (LC_ALL=C).
	var pactl := "Sink #52\n\tState: RUNNING\n\tName: alsa_output.pci-0000_00_1f.3.analog-stereo\n\tDescription: Built-in Audio Analog Stereo\n\tDriver: PipeWire\n\nSink #77\n\tName: alsa_output.usb-Logitech_G435_Wireless_Gaming_Headset-00.analog-stereo\n\tDescription: G435 Wireless Gaming Headset Analog Stereo\n"
	var names := DeviceSettings.parse_pactl_list(pactl)
	check(names.get("alsa_output.pci-0000_00_1f.3.analog-stereo") == "Built-in Audio Analog Stereo", "pactl description read: %s" % [names])
	check(names.get("alsa_output.usb-Logitech_G435_Wireless_Gaming_Headset-00.analog-stereo") == "G435 Wireless Gaming Headset Analog Stereo", "Second sink read")
	DeviceSettings._sink_names = names
	DeviceSettings._default_sink = "alsa_output.usb-Logitech_G435_Wireless_Gaming_Headset-00.analog-stereo"
	check(DeviceSettings.sound_label("output", "Default") == "Default: G435 Wireless Gaming Headset Analog Stereo", "Default names the real device: " + DeviceSettings.sound_label("output", "Default"))
	check(DeviceSettings.sound_label("output", "alsa_output.pci-0000_00_1f.3.analog-stereo") == "Built-in Audio Analog Stereo", "Ids shown by their readable name")
	check(DeviceSettings.sound_label("output", "Speakers (Realtek(R) Audio)") == "Speakers (Realtek(R) Audio)", "Windows names shown as they are")
	DeviceSettings._sink_names = {}
	DeviceSettings._default_sink = ""
	check(DeviceSettings.sound_label("output", "Default").begins_with("Default ("), "Unknown default explained: " + DeviceSettings.sound_label("output", "Default"))
	check(DeviceSettings.pretty_id("alsa_output.usb-Logitech_G435_Wireless-00.analog-stereo") == "Logitech G435 Wireless (analog stereo)", "Fallback without pactl: " + DeviceSettings.pretty_id("alsa_output.usb-Logitech_G435_Wireless-00.analog-stereo"))
	check(DeviceSettings.pretty_id("alsa_input.pci-0000_00_1f.3.analog-stereo") == "Built-in audio (analog stereo)", "Built-in fallback: " + DeviceSettings.pretty_id("alsa_input.pci-0000_00_1f.3.analog-stereo"))
	# Monitor model name from the EDID in `xrandr --verbose`.
	var edid := ""
	var bytes := PackedByteArray()
	bytes.resize(128)
	var name_block := PackedByteArray([0, 0, 0, 0xFC, 0]) + "DELL U2719D".to_ascii_buffer() + PackedByteArray([0x0A, 0x20])
	for i in name_block.size(): bytes[72 + i] = name_block[i]
	edid = bytes.hex_encode()
	check(DeviceSettings.edid_name(edid) == "DELL U2719D", "EDID model name read: " + DeviceSettings.edid_name(edid))
	var xrandr := "Screen 0: minimum 8 x 8, current 4480 x 1440\nDP-1 connected primary 2560x1440+0+0 (0x46) normal (normal left inverted right x axis y axis) 597mm x 336mm\n\tIdentifier: 0x42\n\tEDID: \n"
	for i in range(0, edid.length(), 32): xrandr += "\t\t" + edid.substr(i, 32) + "\n"
	xrandr += "\tBROADCAST_RGB: Automatic\n  2560x1440 (0x46) 241.500MHz +HSync -VSync *current +preferred\nHDMI-1 connected 1920x1080+2560+0 (0x50) normal\n\tIdentifier: 0x43\nHDMI-2 disconnected (normal left inverted right x axis y axis)\n"
	var outputs := DeviceSettings.parse_xrandr(xrandr)
	check(outputs.size() == 2, "Two connected monitors: %s" % [outputs])
	if outputs.size() == 2:
		check(outputs[0].name == "DELL U2719D" and outputs[0].position == Vector2i(0, 0), "First monitor named by its model")
		check(outputs[1].name == "" and outputs[1].position == Vector2i(2560, 0), "Second monitor without EDID has no model name")
	check(DeviceSettings.monitor_label(0).begins_with("Monitor 1") or DeviceSettings.monitor_label(0).length() > 0, "Monitor label: " + DeviceSettings.monitor_label(0))

func test_mic_check_link() -> void:
	game.screen = "game"
	game._action("entry_voice_settings")
	check(game.screen == "settings" and game.settings_tab == "devices", "CHOOSE MICROPHONE in the mic check opens Devices")
	game.screen = "title"

func test_boost_name() -> void:
	game._begin_shift(1)
	check(game._boost_text() == "SPEED BOOST", "Boost is called SPEED BOOST")
	game.sim.use_special()
	check(game._boost_text().begins_with("SPEED BOOST "), "Cooling down shows SPEED BOOST Ns")
	var src := FileAccess.get_file_as_string("res://scripts/main.gd") + FileAccess.get_file_as_string("res://scripts/simulation.gd") + FileAccess.get_file_as_string("res://scripts/tutorial_director.gd")
	check(src.to_lower().find("coffee boost") == -1, "No 'coffee boost' left in the game text")

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DeviceSettings.PATH))
	game = load("res://scripts/main.gd").new()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.audio.set_music_enabled(false)
	game.audio.set_sfx_enabled(false)
	await test_devices_tab()
	test_choosing_and_saving()
	test_readable_names()
	test_mic_check_link()
	test_boost_name()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DeviceSettings.PATH))
	game._stop_capture()
	game.voice.shutdown()
	game.network.close()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: Settings > Devices (microphone, sound output, monitor) and SPEED BOOST")
	quit(0 if failures.is_empty() else 1)
