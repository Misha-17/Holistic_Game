class_name TutorialOverlay
extends Node2D



signal advance_requested
signal skip_requested

const CREAM := Color("f2e7ce")
const PAPER := Color("fbf1dc")
const INK := Color("203b46")
const MUTED := Color("6e7c77")
const DEFAULT_PORTRAITS := "res://assets/art/tutorial_portraits.png"
const ORIGINAL_CONCEPTS := "res://assets/art/crew_concepts.png"
const PEOPLE := {
	"nova": {"name": "Nova", "role": "DISPATCHER", "quarter": Vector2i(0, 0), "accent": Color("d28b66"), "wash": Color("e7debc"), "fallback": Rect2(.294, .175, .149, .522)},
	"bram": {"name": "Bram", "role": "FIRE CAPTAIN", "quarter": Vector2i(1, 0), "accent": Color("d67d61"), "wash": Color("ebd8bf"), "fallback": Rect2(.429, .166, .212, .541)},
	"elio": {"name": "Elio", "role": "MEDIC", "quarter": Vector2i(0, 1), "accent": Color("69a89c"), "wash": Color("d9e4cd"), "fallback": Rect2(.620, .137, .187, .560)},
	"tess": {"name": "Tess", "role": "ENGINEER", "quarter": Vector2i(1, 1), "accent": Color("c9a14f"), "wash": Color("e8dfba"), "fallback": Rect2(.807, .194, .191, .505)}
}

var data: Dictionary = {}
var reduced_motion: bool = false
@export_file("*.png", "*.webp", "*.jpg") var portrait_path: String = DEFAULT_PORTRAITS
var panel_size := Vector2(1048, 264)

var _portrait_texture: Texture2D
var _using_atlas: bool = false
var _speaker: String = "nova"
var _previous_step: int = -999
var _portrait_age: float = 1.0
var _hovered: String = ""
var _elapsed: float = 0.0

func _init() -> void:
	position = Vector2(32, 514)
	z_index = 80

func _ready() -> void:
	
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_load_portraits()

func _load_portraits() -> void:
	if ResourceLoader.exists(portrait_path):
		_portrait_texture = load(portrait_path) as Texture2D
		_using_atlas = _portrait_texture != null
	elif FileAccess.file_exists(portrait_path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(portrait_path))
		if image != null and not image.is_empty():
			_portrait_texture = ImageTexture.create_from_image(image)
			_using_atlas = true
	if _portrait_texture == null and ResourceLoader.exists(ORIGINAL_CONCEPTS):
		_portrait_texture = load(ORIGINAL_CONCEPTS) as Texture2D
		_using_atlas = false

func _process(delta: float) -> void:
	if data.is_empty() or not visible:
		return
	var next_speaker: String = str(data.get("speaker", "Nova")).strip_edges().to_lower()
	if not PEOPLE.has(next_speaker):
		next_speaker = "nova"
	var step: int = int(data.get("step", 1))
	if next_speaker != _speaker or step != _previous_step:
		_speaker = next_speaker
		_previous_step = step
		_portrait_age = 0.0
	_portrait_age = minf(1.0, _portrait_age + delta)
	if not reduced_motion:
		_elapsed += minf(delta, .1)
	queue_redraw()


func blocks_point(global_position: Vector2) -> bool:
	if not is_visible_in_tree() or data.is_empty():
		return false
	var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * global_position
	return Rect2(Vector2.ZERO, panel_size).has_point(local_position)

func _local_button_rects() -> Dictionary:
	var result: Dictionary = {"skip": Rect2(panel_size.x - 94, 12, 74, 30)}
	if bool(data.get("can_advance", false)):
		result["advance"] = Rect2(panel_size.x - 192, 216, 168, 36)
	return result


func button_rects() -> Dictionary:
	var result: Dictionary = {}
	for key in _local_button_rects():
		result[key] = get_global_transform_with_canvas() * _local_button_rects()[key]
	return result



func handle_input(event: InputEvent) -> bool:
	if not is_visible_in_tree() or data.is_empty():
		return false
	if event is InputEventMouseMotion:
		var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		_hovered = ""
		for key in _local_button_rects():
			if _local_button_rects()[key].has_point(local_position):
				_hovered = key
		if Rect2(Vector2.ZERO, panel_size).has_point(local_position):
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if not _hovered.is_empty() else Input.CURSOR_ARROW)
			get_viewport().set_input_as_handled()
			queue_redraw()
			return true
		return false
	if event is InputEventMouseButton:
		var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if not Rect2(Vector2.ZERO, panel_size).has_point(local_position):
			return false
		get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var areas: Dictionary = _local_button_rects()
			if areas.skip.has_point(local_position):
				skip_requested.emit()
			elif areas.has("advance") and areas.advance.has_point(local_position):
				advance_requested.emit()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and bool(data.get("can_advance", false)):
			get_viewport().set_input_as_handled()
			advance_requested.emit()
			return true
	return false

func _rect(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color)

func _panel(rect: Rect2, color: Color, border: Color, radius: int = 10, border_width: int = 1) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)

func _text(value: String, at: Vector2, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _center_text(value: String, area: Rect2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, Vector2(area.position.x + (area.size.x - width) * .5, area.position.y + (area.size.y + font_size) * .5 - 3), font_size, color)

func _wrap(text: String, max_width: float, font_size: int) -> Array[String]:
	var result: Array[String] = []
	var font := ThemeDB.fallback_font
	for paragraph in text.split("\n"):
		var current: String = ""
		for word in paragraph.split(" ", false):
			var candidate: String = word if current.is_empty() else current + " " + word
			if not current.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
				result.append(current)
				current = word
			else:
				current = candidate
		result.append(current)
	return result

func _draw() -> void:
	if data.is_empty():
		return
	var person: Dictionary = PEOPLE.get(str(data.get("speaker", "Nova")).strip_edges().to_lower(), PEOPLE.nova)
	var accent: Color = person.accent
	var can_advance: bool = bool(data.get("can_advance", false))
	var observing: bool = not bool(data.get("simulation_paused", true)) and not can_advance
	var bounds := Rect2(Vector2.ZERO, panel_size)
	_panel(Rect2(Vector2(5, 7), panel_size), Color("071f2c95"), Color.TRANSPARENT, 13, 0)
	_panel(bounds, CREAM, INK, 12, 2)
	
	var portrait_plate := Rect2(8, 8, 232, panel_size.y - 16)
	_panel(portrait_plate, person.wash, Color("b9bba380"), 8, 1)
	_draw_portrait(portrait_plate.grow(-5), person)
	_rect(Rect2(249, 20, 1, panel_size.y - 40), Color("d5ccb4"))
	_rect(Rect2(264, 20, 3, 22), accent)
	_text(str(person.name), Vector2(276, 38), 25, INK)
	var name_width: float = ThemeDB.fallback_font.get_string_size(str(person.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x
	_text(str(person.role), Vector2(289 + name_width, 36), 12, MUTED)
	_draw_steps(accent)
	var title: String = str(data.get("title", "")).strip_edges()
	var text: String = str(data.get("text", ""))
	var body_top: float = 81 if not title.is_empty() else 65
	if not title.is_empty():
		_text(title, Vector2(264, 76), 17, INK.lightened(.12))
	var body_width: float = panel_size.x - 288
	var body_height: float = 84 if not title.is_empty() else 100
	var font_size: int = 22
	var lines: Array[String] = _wrap(text, body_width, font_size)
	while font_size > 17 and lines.size() * (font_size + 5) > body_height:
		font_size -= 1
		lines = _wrap(text, body_width, font_size)
	for i in range(lines.size()):
		_text(lines[i], Vector2(264, body_top + font_size + i * (font_size + 5)), font_size, INK)
	_draw_objective(accent, can_advance and int(data.get("step", 1)) > 1)
	var areas: Dictionary = _local_button_rects()
	var skip_rect: Rect2 = areas.skip
	if _hovered == "skip":
		_panel(skip_rect, Color("dfd7c1"), Color.TRANSPARENT, 6, 0)
	_center_text("SKIP", skip_rect, 12, MUTED if _hovered != "skip" else INK)
	if can_advance:
		var advance_rect: Rect2 = areas.advance
		_panel(advance_rect, INK.lightened(.08) if _hovered == "advance" else INK, INK, 7, 1)
		var next_label: String = str(data.get("next_label", "Continue")).to_upper()
		var label_size: int = 14
		while label_size > 10 and ThemeDB.fallback_font.get_string_size(next_label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x > advance_rect.size.x - 39:
			label_size -= 1
		_center_text(next_label, Rect2(advance_rect.position, advance_rect.size - Vector2(18, 0)), label_size, PAPER)
		var arrow: Vector2 = advance_rect.position + Vector2(advance_rect.size.x - 19, 17)
		draw_line(arrow + Vector2(-3, -4), arrow + Vector2(1, 0), PAPER, 1.5, true)
		draw_line(arrow + Vector2(1, 0), arrow + Vector2(-3, 4), PAPER, 1.5, true)
		_text("Take your time.  Enter to continue.", Vector2(264, 239), 13, MUTED)
	else:
		var turn_rect := Rect2(panel_size.x - 192, 216, 168, 36)
		_panel(turn_rect, Color("e3e2c9"), Color("bac5ad"), 7, 1)
		_center_text("CREW AT WORK" if observing else "YOUR TURN", turn_rect, 13, Color("587663"))
		var turn_hint: String = "Watch the crew work…" if observing else "Try the highlighted action above."
		if bool(data.get("map_selection_required",false)):
			turn_hint = "Number keys highlight. Click the crew on the map."
		_text(turn_hint, Vector2(264, 239), 13, MUTED)

func _draw_steps(accent: Color) -> void:
	var total: int = maxi(1, int(data.get("total", 1)))
	var step: int = clampi(int(data.get("step", 1)), 1, total)
	var displayed: int = mini(total, 16)
	var pitch: float = 10.0 if displayed > 12 else 12.0
	var width: float = displayed * pitch
	var x: float = panel_size.x - 121 - width
	for i in range(displayed):
		var represented: int = floori(float(i) * total / displayed) + 1
		var is_current: bool = step >= represented and (i == displayed - 1 or step < floori(float(i + 1) * total / displayed) + 1)
		var size := Vector2(6, 6) if not is_current else Vector2(8, 8)
		var color: Color = accent if represented <= step else Color("d4cfb7")
		_rect(Rect2(Vector2(x + i * pitch, 24 - size.y * .5), size), color)
	_text("%02d / %02d" % [step, total], Vector2(panel_size.x - 187, 47), 10, MUTED)

func _draw_objective(accent: Color, complete: bool) -> void:
	var objective: String = str(data.get("objective", ""))
	var rect := Rect2(264, 174, panel_size.x - 288, 32)
	_panel(rect, Color("e0e6cc") if complete else Color("ede2bb"), Color("d2ccb0"), 5, 1)
	_rect(Rect2(rect.position, Vector2(3, rect.size.y)), accent)
	var icon := Vector2(278, 186)
	if complete:
		draw_line(icon + Vector2(0, 3), icon + Vector2(4, 7), Color("64886e"), 2, false)
		draw_line(icon + Vector2(4, 7), icon + Vector2(11, -1), Color("64886e"), 2, false)
	else:
		_rect(Rect2(icon + Vector2(0, 2), Vector2(9, 2)), Color("947f48"))
		draw_line(icon + Vector2(6, -1), icon + Vector2(10, 3), Color("947f48"), 1.5, false)
		draw_line(icon + Vector2(10, 3), icon + Vector2(6, 7), Color("947f48"), 1.5, false)
	var objective_size: int = 14
	while objective_size > 11 and ThemeDB.fallback_font.get_string_size(objective, HORIZONTAL_ALIGNMENT_LEFT, -1, objective_size).x > rect.size.x - 51:
		objective_size -= 1
	_text(objective, Vector2(300, 195), objective_size, INK)

func _draw_portrait(area: Rect2, person: Dictionary) -> void:
	if _portrait_texture == null:
		return
	var texture_size: Vector2 = _portrait_texture.get_size()
	var source: Rect2
	if _using_atlas:
		var half_size: Vector2 = texture_size * .5
		source = Rect2(Vector2(person.quarter) * half_size, half_size)
		if str(person.name) == "Nova":
			
			
			source.size.x = maxf(1.0, source.size.x - 28.0)
	else:
		var region: Rect2 = person.fallback
		source = Rect2(region.position * texture_size, region.size * texture_size)
	var scale: float = minf(area.size.x / source.size.x, area.size.y / source.size.y)
	var size: Vector2 = source.size * scale
	var portrait_rect := Rect2(area.position + (area.size - size) * .5, size)
	var alpha: float = 1.0 if reduced_motion else clampf(_portrait_age / .18, 0, 1)
	if not reduced_motion:
		portrait_rect.position.y += (1 - alpha) * 4
	draw_texture_rect_region(_portrait_texture, portrait_rect, source, Color(1, 1, 1, alpha), false)
