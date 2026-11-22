class_name IncidentFocus
extends Node2D

const Art = preload("res://scripts/responder_art.gd")
const PixelArt = preload("res://scripts/pixel_town_art.gd")
const INK := Color("223944")
const CREAM := Color("f4f0e6")
const MINT := Color("75c4aa")
const DEPARTMENTS: Array[String] = ["fire", "medic", "engineer", "police"]
const SHORT_NAMES := {"fire": "FIRE", "medic": "MED", "engineer": "ENG", "police": "POLICE"}
const BUILDING_CELLS := {"fire": 0, "medical": 9, "police": 14, "power": 11, "flood": 10, "unknown": 5}
const SITE_TILES := [0, 1, 2, 11, 4, 0, 5, 6, 7, 8, 9, 10, 11, 0, 12, 13, 0, 11, 12, 11, 15, 3, 5, 11, 13, 6, 7, 13, 6, 5, 5, 14]

var sim = null
var selected_id := -1
var reduced_motion := false
var panel_size := Vector2(464, 210)
var elapsed := 0.0
var _buildings: Texture2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	if not reduced_motion: elapsed += minf(delta, 0.1)
	queue_redraw()


func _panel(area: Rect2, fill: Color, outline: Color = Color.TRANSPARENT, radius: int = 10) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(1 if outline.a > 0 else 0)
	style.set_corner_radius_all(radius)
	draw_style_box(style, area)


func _text(value: String, at: Vector2, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _fit(value: String, width: float, size: int) -> String:
	var font := ThemeDB.fallback_font
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width: return value
	var clipped := value
	while clipped.length() > 1 and font.get_string_size(clipped + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		clipped = clipped.left(-1)
	return clipped + "…"


func _draw() -> void:
	_panel(Rect2(Vector2(0, 5), panel_size), Color("12273355"))
	_panel(Rect2(Vector2.ZERO, panel_size), INK, Color("839e9c80"))
	draw_rect(Rect2(1, 32, panel_size.x - 2, 148), Color("e7eee8"))
	var incident: Dictionary = {}
	if sim != null:
		for item in sim.incidents:
			if int(item.get("id", -1)) == selected_id:
				incident = item
				break
	if incident.is_empty():
		_text("FIELD VIEW", Vector2(14, 22), 13, CREAM)
		_text("Select a call", Vector2(183, 114), 16, INK)
		return
	var known := bool(incident.get("discovered", true))
	var resolved := str(incident.get("status", "")) == "resolved"
	var failed := str(incident.get("status", "")) == "failed"
	var kind := str(incident.get("kind", "medical")) if known or resolved else "unknown"
	var progress := clampf(float(incident.get("progress", 0.0)), 0, 1)
	var working: Array[Dictionary] = []
	var travelling: Array[Dictionary] = []
	for unit in sim.units:
		if int(unit.get("target", -1)) != selected_id: continue
		if str(unit.get("state", "")) == "working": working.append(unit)
		elif str(unit.get("state", "")) == "travel": travelling.append(unit)
	_draw_scene(kind, progress, float(incident.get("hazard", 0.25)), resolved, int(incident.get("location_index", -1)))
	var roster: Array[Dictionary] = working.duplicate()
	roster.append_array(travelling)
	if not roster.is_empty():
		_draw_crews(roster)
	elif resolved:
		draw_circle(Vector2(329, 105), 30, Color("c8e4d4"))
		draw_polyline(PackedVector2Array([Vector2(313, 104), Vector2(324, 115), Vector2(346, 91)]), Color("448d78"), 5, true)
	elif not failed:
		_draw_needed(incident, known)
	else:
		draw_circle(Vector2(329, 105), 27, Color("ead8cf"))
		draw_line(Vector2(318, 94), Vector2(340, 116), Color("a87866"), 4, true)
		draw_line(Vector2(340, 94), Vector2(318, 116), Color("a87866"), 4, true)
	var status := "ON SCENE" if not working.is_empty() else ("EN ROUTE" if not travelling.is_empty() else "AWAITING CREW")
	var accent := MINT if not working.is_empty() else Color("e8c57e")
	if resolved:
		status = "SAFE"
		accent = MINT
	elif failed:
		status = "CLOSED"
		accent = Color("d99b85")
	_text(_fit(str(incident.get("name", "Call")), 242, 14), Vector2(14, 22), 14, CREAM)
	_panel(Rect2(275, 7, 112, 19), Color(accent, 0.13), Color.TRANSPARENT, 5)
	var status_width := ThemeDB.fallback_font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_text(status, Vector2(331 - status_width * 0.5, 20), 9, accent)
	var caption := "Choose a crew to respond"
	if resolved: caption = "%d people safe" % int(incident.get("people", 0))
	elif failed: caption = "Call closed"
	elif not working.is_empty(): caption = "%d crew%s on scene" % [working.size(), "s" if working.size() > 1 else ""]
	elif not travelling.is_empty():
		var eta := 999.0
		for unit in travelling: eta = minf(eta, float(unit.get("remaining", 0)))
		caption = "First arrival in %ds" % ceili(eta)
	elif not known: caption = "Scout to identify the crews needed"
	_text(caption, Vector2(14, 195), 11, CREAM)
	draw_rect(Rect2(14, 202, panel_size.x - 28, 3), Color("172d37"))
	if progress > 0: draw_rect(Rect2(14, 202, (panel_size.x - 28) * progress, 3), MINT)


func _draw_scene(kind: String, progress: float, hazard: float, resolved: bool, location_index: int = -1) -> void:
	# Broad flat colour fields let the new building and character art read clearly.
	draw_circle(Vector2(96, 82), 48, Color("f1e8ca"))
	draw_rect(Rect2(1, 140, panel_size.x - 2, 40), Color("d7e0d4"))
	draw_line(Vector2(1, 170), Vector2(panel_size.x - 1, 170), Color("c0ccc4"), 2, true)
	draw_rect(Rect2(29,153,166,10),Color("455e5925"))
	var pixel := PixelArt.new(self)
	pixel.site(Vector2(110,164),maxi(0,location_index),2.35)

	if resolved: return
	if kind == "fire":
		Art.draw_flames(self, Vector2(112, 147), hazard, progress, elapsed, 1.7)
	elif kind == "flood":
		draw_rect(Rect2(1, 145 + progress * 15, 208, 23 - progress * 15), Color("65a7b580"))
		for index in range(5):
			var x := 12.0 + index * 40 + sin(elapsed * 1.3 + index) * 3
			draw_line(Vector2(x, 155), Vector2(x + 21, 155), Color("c7e4df"), 1.5, true)
	elif kind == "power":
		draw_polyline(PackedVector2Array([Vector2(190, 86), Vector2(181, 104), Vector2(191, 104), Vector2(182, 122)]), Color("d1a94b"), 3, true)
	elif kind == "unknown":
		draw_circle(Vector2(178, 67), 13, Color("e6d9b8"))
		_text("?", Vector2(173, 73), 18, Color("867954"))


func _draw_crews(units: Array[Dictionary]) -> void:
	var count := mini(units.size(), 4)
	var width := 230.0 / maxi(1, count)
	for index in range(count):
		var unit: Dictionary = units[index]
		var kind := str(unit.get("kind", "fire"))
		var center := 223.0 + width * (index + 0.5)
		var travelling := str(unit.get("state", "")) == "travel"
		var actor_scale := 3.95 if count <= 3 else 3.45
		Art.draw_person(self, Vector2(center, 165), kind, int(unit.get("appearance", unit.get("id", index))),
			"walk" if travelling and not reduced_motion else "radio", elapsed + index * 0.4, 1, actor_scale)
		var label := "%ds" % ceili(float(unit.get("remaining", 0))) if travelling else str(SHORT_NAMES.get(kind, "CREW"))
		var label_width := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		_panel(Rect2(center - label_width * 0.5 - 5, 163, label_width + 10, 14), Color("f8f8efa8"), Color.TRANSPARENT, 4)
		_text(label, Vector2(center - label_width * 0.5, 174), 9, INK)


func _draw_needed(incident: Dictionary, known: bool) -> void:
	if not known:
		_text("SCOUT", Vector2(304, 111), 15, Color("718784"))
		return
	var kinds: Array[String] = []
	var needs: Dictionary = incident.get("needs", {})
	for kind in DEPARTMENTS:
		if int(needs.get(kind, 0)) > 0: kinds.append(kind)
	var width := 206.0 / maxi(1, kinds.size())
	for index in range(kinds.size()):
		var kind := kinds[index]
		var x := 231 + index * width
		_panel(Rect2(x, 81, width - 5, 61), Color("f6f6ec"), Color("c9d8cc"), 6)
		Art.draw_portrait_rect(self, Rect2(x + 3, 82, width - 11, 43), kind, 0.7)
		var label := str(SHORT_NAMES.get(kind, "CREW"))
		var text_width := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		_text(label, Vector2(x + (width - 5 - text_width) * 0.5, 136), 8, INK)
