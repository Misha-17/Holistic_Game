extends RefCounted
class_name DeviceSettings

# Settings → Devices (22.11): which microphone, which headset/speakers and
# which monitor the game uses. Kept in its own small file on this computer
# (not in the campaign save), so guests keep their choice too.
# Each choice is remembered by the device's id: if that device is unplugged
# next time, the game quietly falls back to the computer's default.
#
# Readable names (22.11, Andrei: "I don't know what that id represents"):
# - Windows and macOS already give Godot readable sound device names.
# - Linux (PulseAudio/PipeWire) gives ids such as
#   "alsa_output.pci-0000_00_1f.3.analog-stereo". The readable name
#   ("Built-in Audio Analog Stereo") is looked up with `pactl list`.
# - Godot has no monitor names at all. On Linux (X11) the model name is read
#   from the monitor's EDID with `xrandr --verbose`; everywhere the label also
#   gives the size, left/right position and "main".

const PATH := "user://beacon_bay_device_settings.cfg"
const DEFAULT := "Default"
const KINDS := ["input", "output", "monitor"]

# id → readable name, filled by refresh_names().
static var _sink_names: Dictionary = {}
static var _source_names: Dictionary = {}
static var _default_sink := ""
static var _default_source := ""
static var _monitor_names: Dictionary = {} # screen index → model name

static func inputs() -> PackedStringArray:
	return AudioServer.get_input_device_list()

static func outputs() -> PackedStringArray:
	return AudioServer.get_output_device_list()

static func input_device() -> String:
	return AudioServer.input_device

static func output_device() -> String:
	return AudioServer.output_device

static func monitor_count() -> int:
	return maxi(1, DisplayServer.get_screen_count())

static func monitor() -> int:
	return clampi(DisplayServer.window_get_current_screen(), 0, monitor_count() - 1)

static func _linux() -> bool:
	return OS.get_name() in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]

# Asks the system for readable names. Called when the Devices tab opens (a
# few milliseconds; never during a level).
static func refresh_names() -> void:
	_sink_names.clear()
	_source_names.clear()
	_default_sink = ""
	_default_source = ""
	_monitor_names.clear()
	if not _linux() or DisplayServer.get_name() == "headless": return
	_sink_names = parse_pactl_list(_run(["pactl", "list", "sinks"]))
	_source_names = parse_pactl_list(_run(["pactl", "list", "sources"]))
	var info := _run(["pactl", "info"])
	for line in info.split("\n"):
		if line.begins_with("Default Sink:"): _default_sink = line.trim_prefix("Default Sink:").strip_edges()
		elif line.begins_with("Default Source:"): _default_source = line.trim_prefix("Default Source:").strip_edges()
	if DisplayServer.get_name() == "X11":
		var outputs := parse_xrandr(_run(["xrandr", "--verbose"]))
		for i in range(monitor_count()):
			var at := DisplayServer.screen_get_position(i)
			for out: Dictionary in outputs:
				if out.position == at and not str(out.name).is_empty():
					_monitor_names[i] = out.name

static func _run(command: Array) -> String:
	var output: Array = []
	# LC_ALL=C keeps "Name:"/"Description:" in English whatever the PC's language.
	if OS.execute("env", ["LC_ALL=C"] + command, output, true) != 0 or output.is_empty(): return ""
	return str(output[0])

# `pactl list sinks|sources` (LC_ALL=C) → {id: description}.
static func parse_pactl_list(text: String) -> Dictionary:
	var names := {}
	var current := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("Name:"):
			current = line.trim_prefix("Name:").strip_edges()
		elif line.begins_with("Description:") and not current.is_empty():
			names[current] = line.trim_prefix("Description:").strip_edges()
			current = ""
	return names

# `xrandr --verbose` → [{connector, position: Vector2i, name}] for connected
# outputs; name is the model name from the EDID (empty if none).
static func parse_xrandr(text: String) -> Array:
	var outputs: Array = []
	var current: Dictionary = {}
	var reading_edid := false
	var edid := ""
	var geometry := RegEx.create_from_string("(\\d+)x(\\d+)\\+(-?\\d+)\\+(-?\\d+)")
	for raw in text.split("\n"):
		if not raw.begins_with("\t") and not raw.begins_with(" "):
			reading_edid = false
			if raw.contains(" connected"):
				if not current.is_empty(): current.name = edid_name(edid); outputs.append(current)
				current = {}
				edid = ""
				var found := geometry.search(raw)
				if found != null:
					current = {"connector": raw.get_slice(" ", 0), "position": Vector2i(int(found.get_string(3)), int(found.get_string(4))), "name": ""}
			elif raw.contains(" disconnected") and not current.is_empty():
				current.name = edid_name(edid); outputs.append(current); current = {}; edid = ""
			continue
		var line := raw.strip_edges()
		if line.begins_with("EDID:"):
			reading_edid = true
			continue
		if reading_edid:
			if line.is_valid_hex_number() and line.length() % 2 == 0: edid += line
			else: reading_edid = false
	if not current.is_empty(): current.name = edid_name(edid); outputs.append(current)
	return outputs

# Monitor model name from an EDID (hex text): display descriptor 0xFC.
static func edid_name(hex: String) -> String:
	if hex.length() < 256: return ""
	var bytes := hex.hex_decode()
	for start in [54, 72, 90, 108]:
		if bytes[start] == 0 and bytes[start + 1] == 0 and bytes[start + 3] == 0xFC:
			var name := ""
			for i in range(start + 5, start + 18):
				if bytes[i] == 0x0A or bytes[i] == 0: break
				name += char(bytes[i])
			return name.strip_edges()
	return ""

# Readable name of a sound device id.
static func sound_label(kind: String, device_id: String) -> String:
	var names: Dictionary = _source_names if kind == "input" else _sink_names
	if device_id == DEFAULT or device_id.is_empty():
		var system_default: String = _default_source if kind == "input" else _default_sink
		if names.has(system_default): return "Default: %s" % names[system_default]
		return "Default (the one chosen in your computer's sound settings)"
	if names.has(device_id): return str(names[device_id])
	return pretty_id(device_id)

# Fallback when the system gives no description: "alsa_output.usb-Logitech_
# G435_Wireless-00.analog-stereo" → "Logitech G435 Wireless (analog stereo)".
static func pretty_id(device_id: String) -> String:
	if device_id.begins_with("bluez_"): return "Bluetooth device"
	if not device_id.begins_with("alsa_"): return device_id
	var parts := device_id.split(".")
	if parts.size() < 2: return device_id
	var body := parts[1]
	if body.begins_with("pci-") or body.begins_with("platform-"):
		body = "Built-in audio"
	else:
		body = body.trim_prefix("usb-")
		var tail := body.rsplit("-", true, 1)
		if tail.size() == 2 and tail[1].is_valid_int(): body = tail[0]
		body = body.replace("_", " ").strip_edges()
	if parts.size() > 2: body += " (%s)" % parts[parts.size() - 1].replace("-", " ")
	return body

static func monitor_label(index: int) -> String:
	var text := str(_monitor_names.get(index, "Monitor %d" % (index + 1)))
	var size := DisplayServer.screen_get_size(index)
	if size.x > 0: text += "  ·  %d × %d" % [size.x, size.y]
	var place := _monitor_place(index)
	if not place.is_empty(): text += "  ·  " + place
	if monitor_count() > 1 and index == DisplayServer.get_primary_screen(): text += "  ·  main screen"
	return text

static func _monitor_place(index: int) -> String:
	var count := monitor_count()
	if count < 2: return ""
	var order: Array = range(count)
	order.sort_custom(func(a, b): return DisplayServer.screen_get_position(a).x < DisplayServer.screen_get_position(b).x)
	var rank := order.find(index)
	if rank == 0: return "left"
	if rank == count - 1: return "right"
	return "middle"

# The entries of one dropdown: [{id, label}]. Microphone list leaves out
# Linux "Monitor of …" sources (they record the speakers, not a microphone)
# unless one is in use.
static func choices(kind: String) -> Array:
	var result: Array = []
	match kind:
		"input":
			for id in inputs():
				if id.ends_with(".monitor") and id != input_device(): continue
				result.append({"id": id, "label": sound_label("input", id)})
		"output":
			for id in outputs():
				result.append({"id": id, "label": sound_label("output", id)})
		"monitor":
			for i in range(monitor_count()):
				result.append({"id": str(i), "label": monitor_label(i)})
	return result

static func current(kind: String) -> String:
	match kind:
		"input": return input_device()
		"output": return output_device()
		_: return str(monitor())

static func current_label(kind: String) -> String:
	return monitor_label(monitor()) if kind == "monitor" else sound_label(kind, current(kind))

# Picks a device from a dropdown and saves the choice.
static func choose(kind: String, device_id: String) -> void:
	match kind:
		"input":
			if device_id in inputs(): AudioServer.input_device = device_id
		"output":
			if device_id in outputs(): AudioServer.output_device = device_id
		"monitor":
			set_monitor(int(device_id))
	save()

# Moves the game window to another monitor. A fullscreen window is taken out
# of fullscreen first, moved and centred, then made fullscreen again, so it
# fills the new monitor instead of keeping the old monitor's size.
static func set_monitor(index: int) -> void:
	if index < 0 or index >= monitor_count() or Engine.is_embedded_in_editor(): return
	if index == monitor(): return
	var mode := DisplayServer.window_get_mode()
	var full := mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, DisplayServer.WINDOW_MODE_MAXIMIZED]
	if full: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(index)
	var area := DisplayServer.screen_get_usable_rect(index)
	var size := DisplayServer.window_get_size()
	DisplayServer.window_set_position(area.position + (area.size - size) / 2)
	if full: DisplayServer.window_set_mode(mode)

static func save() -> void:
	var config := ConfigFile.new()
	config.set_value("devices", "input", input_device())
	config.set_value("devices", "output", output_device())
	config.set_value("devices", "monitor", monitor())
	if config.save(PATH) != OK:
		push_error("Could not save device settings: " + PATH)

# Called once at start-up. Saved devices that are no longer plugged in are
# ignored (the computer's default stays in use).
static func load_and_apply() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK: return
	var wanted_in := str(config.get_value("devices", "input", DEFAULT))
	if wanted_in in inputs(): AudioServer.input_device = wanted_in
	var wanted_out := str(config.get_value("devices", "output", DEFAULT))
	if wanted_out in outputs(): AudioServer.output_device = wanted_out
	var wanted_monitor := int(config.get_value("devices", "monitor", -1))
	if wanted_monitor >= 0 and wanted_monitor < monitor_count(): set_monitor(wanted_monitor)
