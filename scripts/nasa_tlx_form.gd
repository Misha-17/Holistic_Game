extends Control

# NASA Task Load Index (Hart & Staveland, 1988), raw ("RTLX") version: six
# subscales rated 0-100 in steps of 5, without the pairwise weighting step.
# The page title, instructions and buttons are drawn by main.gd (screen "tlx");
# this control holds only the six real sliders so they work with mouse and keys.
# A slider counts as answered only after the player moves it, so the default
# position never becomes an answer by accident.

signal changed

const SCALES := [
	{"id": "mental_demand", "title": "Mental demand", "question": "How mentally demanding was the task?", "low": "Very low", "high": "Very high"},
	{"id": "physical_demand", "title": "Physical demand", "question": "How physically demanding was the task?", "low": "Very low", "high": "Very high"},
	{"id": "temporal_demand", "title": "Temporal demand", "question": "How hurried or rushed was the pace of the task?", "low": "Very low", "high": "Very high"},
	{"id": "performance", "title": "Performance", "question": "How successful were you in accomplishing what you were asked to do?", "low": "Perfect", "high": "Failure"},
	{"id": "effort", "title": "Effort", "question": "How hard did you have to work to accomplish your level of performance?", "low": "Very low", "high": "Very high"},
	{"id": "frustration", "title": "Frustration", "question": "How insecure, discouraged, irritated, stressed, and annoyed were you?", "low": "Very low", "high": "Very high"},
]
const COLUMN_WIDTH := 620.0
const COLUMN_GAP := 40.0
const ROW_HEIGHT := 150.0

var sliders: Dictionary = {}
var _touched: Dictionary = {}
var _values: Dictionary = {}

func build() -> void:
	position = Vector2(80, 300)
	size = Vector2(2 * COLUMN_WIDTH + COLUMN_GAP, 3 * ROW_HEIGHT)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(SCALES.size()):
		var scale: Dictionary = SCALES[i]
		var column := i / 3
		var row := i % 3
		var origin := Vector2(column * (COLUMN_WIDTH + COLUMN_GAP), row * ROW_HEIGHT)
		_label(scale.title, origin, 21, Color("f4e9d2"))
		_label(scale.question, origin + Vector2(0, 32), 15, Color("90afb2"))
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.tick_count = 21
		slider.ticks_on_borders = true
		slider.value = 50
		slider.position = origin + Vector2(0, 66)
		slider.size = Vector2(COLUMN_WIDTH - 70, 28)
		slider.focus_mode = Control.FOCUS_ALL
		slider.value_changed.connect(_moved.bind(str(scale.id)))
		slider.gui_input.connect(_pressed.bind(str(scale.id)))
		add_child(slider)
		sliders[scale.id] = slider
		var value := _label("—", origin + Vector2(COLUMN_WIDTH - 56, 64), 20, Color("70d2ba"))
		value.custom_minimum_size.x = 56
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.name = "value_" + str(scale.id)
		_label(scale.low, origin + Vector2(0, 98), 13, Color("90afb2"))
		var high := _label(scale.high, origin + Vector2(COLUMN_WIDTH - 70 - 120, 98), 13, Color("90afb2"))
		high.custom_minimum_size.x = 120
		high.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reset()

func reset() -> void:
	_touched.clear()
	_values.clear()
	for id in sliders:
		sliders[id].set_value_no_signal(50)
		sliders[id].modulate = Color(1, 1, 1, 0.45)
		var label: Label = get_node_or_null("value_" + str(id))
		if label != null: label.text = "—"
	changed.emit()

func answered_count() -> int:
	return _touched.size()

func all_answered() -> bool:
	return _touched.size() == SCALES.size()

# Answers keyed by subscale id, plus the raw TLX score (mean of the six).
func answers() -> Dictionary:
	var result: Dictionary = {}
	var total := 0.0
	for scale: Dictionary in SCALES:
		var value := int(_values.get(scale.id, -1))
		result[scale.id] = value if _touched.has(scale.id) else null
		if _touched.has(scale.id): total += value
	result["raw_tlx"] = snappedf(total / SCALES.size(), 0.01) if all_answered() else null
	return result

func set_answer(id: String, value: int) -> void:
	# Used by tests and keyboard users; same path as moving the slider.
	if sliders.has(id): sliders[id].value = value
	_moved(float(value), id)

func _moved(value: float, id: String) -> void:
	_touched[id] = true
	_values[id] = int(round(value))
	sliders[id].modulate = Color.WHITE
	var label: Label = get_node_or_null("value_" + id)
	if label != null: label.text = str(int(round(value)))
	changed.emit()

func _pressed(event: InputEvent, id: String) -> void:
	# Clicking exactly on the default position (50) is still an answer.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_moved(sliders[id].value, id)

func _label(text: String, at: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label
