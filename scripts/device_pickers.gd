extends Control

# Settings → Devices (22.11): the three dropdown lists (real Godot
# OptionButtons), laid over the cards that main.gd draws in the left column.
# Like the volume sliders (sound_settings.gd), they are real controls.

signal device_chosen(kind: String, label: String)

const WIDTH := 580.0
const HEIGHT := 38.0
const CREAM := Color("f4e9d2")
const TEAL := Color("70d2ba")
var pickers: Dictionary = {} # kind → OptionButton
var _ids: Dictionary = {}    # kind → [device id per item]

# rows: kind → y of that card in main.gd's canvas (SETTINGS_COL[0] = x 80).
func build(rows: Dictionary) -> void:
	position = Vector2(80, 0)
	size = Vector2(620, 900)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind: String in DeviceSettings.KINDS:
		var picker := OptionButton.new()
		picker.name = "Picker_" + kind
		picker.position = Vector2(20, float(rows[kind]) + 42.0)
		picker.size = Vector2(WIDTH, HEIGHT)
		picker.fit_to_longest_item = false
		picker.clip_text = true
		picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		picker.alignment = HORIZONTAL_ALIGNMENT_LEFT
		picker.add_theme_font_size_override("font_size", 15)
		picker.add_theme_color_override("font_color", TEAL)
		picker.add_theme_color_override("font_hover_color", CREAM)
		picker.add_theme_color_override("font_focus_color", TEAL)
		picker.add_theme_color_override("font_pressed_color", CREAM)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("0f2a33") if state != "hover" else Color("1f4652")
			style.border_color = Color("355966") if state != "focus" else TEAL
			style.set_border_width_all(1)
			style.set_corner_radius_all(6)
			style.content_margin_left = 12
			style.content_margin_right = 12
			picker.add_theme_stylebox_override(state, style)
		var popup := picker.get_popup()
		popup.add_theme_font_size_override("font_size", 15)
		popup.add_theme_color_override("font_color", CREAM)
		popup.add_theme_color_override("font_hover_color", Color("0c1a23"))
		var list_style := StyleBoxFlat.new()
		list_style.bg_color = Color("0f2a33")
		list_style.border_color = TEAL
		list_style.set_border_width_all(1)
		list_style.set_corner_radius_all(6)
		list_style.set_content_margin_all(6)
		popup.add_theme_stylebox_override("panel", list_style)
		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = TEAL
		hover_style.set_corner_radius_all(4)
		popup.add_theme_stylebox_override("hover", hover_style)
		picker.item_selected.connect(_on_selected.bind(kind))
		add_child(picker)
		pickers[kind] = picker
	refresh()

# Re-reads the device lists and their readable names (when the tab opens, so
# a headset plugged in meanwhile appears).
func refresh() -> void:
	DeviceSettings.refresh_names()
	for kind: String in pickers:
		var picker: OptionButton = pickers[kind]
		picker.clear()
		var ids: Array = []
		var selected := 0
		for choice: Dictionary in DeviceSettings.choices(kind):
			picker.add_item(str(choice.label))
			if str(choice.id) == DeviceSettings.current(kind): selected = ids.size()
			ids.append(str(choice.id))
		_ids[kind] = ids
		if not ids.is_empty(): picker.select(selected)
		picker.tooltip_text = picker.get_item_text(selected) if not ids.is_empty() else ""
	var monitor: OptionButton = pickers.get("monitor")
	if monitor != null: monitor.disabled = Engine.is_embedded_in_editor() or DeviceSettings.monitor_count() < 2

func _on_selected(index: int, kind: String) -> void:
	var ids: Array = _ids.get(kind, [])
	if index < 0 or index >= ids.size(): return
	DeviceSettings.choose(kind, str(ids[index]))
	refresh()
	device_chosen.emit(kind, DeviceSettings.current_label(kind))
