class_name IncidentFocus
extends Node2D


const Art = preload("res://scripts/responder_art.gd")
const INK := Color("142e39")
const CREAM := Color("eee1bd")
const MINT := Color("9bd5b8")

var sim = null
var selected_id: int = -1
var reduced_motion: bool = false
var panel_size := Vector2(464, 210)
var elapsed: float = 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta: float) -> void:
	if not reduced_motion:
		elapsed += minf(delta, .1)
	queue_redraw()

func _r(x: float, y: float, w: float, h: float, color: Color) -> void:
	draw_rect(Rect2(floorf(x), floorf(y), maxf(1, floorf(w)), maxf(1, floorf(h))), color)

func _text(value: String, position: Vector2, font_size: int, color: Color, width: float = -1) -> void:
	draw_string(ThemeDB.fallback_font, position.floor(), value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)

func _fit(value: String, max_width: float, font_size: int) -> String:
	var font := ThemeDB.fallback_font
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return value
	var clipped: String = value
	while clipped.length() > 1 and font.get_string_size(clipped + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		clipped = clipped.left(-1)
	return clipped + "…"

func _draw() -> void:
	var incident: Dictionary = {}
	if sim != null:
		for item in sim.incidents:
			if int(item.get("id", -1)) == selected_id:
				incident = item
				break
	_r(3, 4, panel_size.x, panel_size.y, Color("081f2d90"))
	_r(0, 0, panel_size.x, panel_size.y, INK)
	_r(1, 1, panel_size.x - 2, panel_size.y - 2, Color("284851"))
	_r(2, 31, panel_size.x - 4, panel_size.y - 58, Color("7f9479"))
	if incident.is_empty():
		_text("FIELD VIEW", Vector2(12, 21), 13, CREAM)
		_text("Select a call to see your crews at work.", Vector2(37, 115), 15, Color("d0d9bf"))
		return
	var kind: String = incident.get("kind", "medical")
	var progress: float = float(incident.get("progress", 0))
	var hazard: float = float(incident.get("hazard", .25))
	var resolved: bool = incident.get("status", "active") == "resolved"
	var failed: bool = incident.get("status", "active") == "failed"
	var discovered: bool = incident.get("discovered", true)
	var working: Array[Dictionary] = []
	var travelling: Array[Dictionary] = []
	var assigned: Array = incident.get("assigned", [])
	for unit in sim.units:
		if int(unit.get("target", -1)) != selected_id:
			continue
		if unit.get("state", "idle") == "working":
			working.append(unit)
		elif unit.get("state", "idle") == "travel":
			travelling.append(unit)
	_draw_scene(kind if discovered or resolved else "unknown", progress, hazard, resolved)
	if resolved:
		Art.draw_person(self, Vector2(194, 162), "civilian", selected_id + 3, "wave", elapsed, 1, 3)
		Art.draw_person(self, Vector2(256, 159), "civilian", selected_id + 6, "wave", elapsed + .7, -1, 3)
		for i in range(5):
			var x: float = 149 + i * 39
			var y: float = 79 + sin(elapsed * 1.4 + i * 2) * 5
			_r(x, y, 3, 3, Color("dcd495"))
			_r(x - 2, y + 1, 7, 1, Color("dcd495"))
	elif not failed:
		if kind == "medical" and discovered and not _has_medic(working):
			Art.draw_casualty(self, Vector2(222, 160), selected_id + 2, false, elapsed, 3)
		elif kind == "flood" and discovered and not _has_medic(working):
			_r(283, 141, 49, 9, Color("bba076"))
			_r(286, 137, 43, 5, Color("d8bf8d"))
			Art.draw_person(self, Vector2(305, 137), "civilian", selected_id + 2, "wave", elapsed, 1, 3)
		if not working.is_empty():
			_draw_workers(working, kind, progress)
		for i in range(mini(3, travelling.size())):
			_draw_approaching(travelling[i], i, travelling.size(), not working.is_empty())
	
	_r(2, 2, panel_size.x - 4, 29, Color("193640"))
	_r(2, 183, panel_size.x - 4, panel_size.y - 185, Color("193640"))
	_r(0, 30, panel_size.x, 1, Color("54806f"))
	_r(0, 182, panel_size.x, 1, Color("54806f"))
	var live_color: Color = MINT if resolved else Color("efad70") if not working.is_empty() else Color("e1c688")
	_r(11, 11, 6, 6, live_color)
	_text(_fit(str(incident.get("name", "Field view")), 210, 14), Vector2(25, 22), 14, CREAM)
	var short_status: String = "LIVE / %02d" % selected_id
	if resolved:
		short_status = "SAFE"
	elif failed:
		short_status = "CLOSED"
	elif working.is_empty():
		short_status = "EN ROUTE" if not travelling.is_empty() else "AWAITING CREWS"
	else:
		short_status = {"waiting": "ARRIVING", "enroute": "ARRIVING", "deploy": "DEPLOYING", "contain": "CONTAINING", "rescue": "RESCUING", "secure": "SECURING"}.get(str(incident.get("phase", "rescue")), "RESPONDING")
	_text(short_status, Vector2(257, 21), 10, live_color)
	if resolved:
		_text("%d neighbors safe · crews returning home" % int(incident.get("people", 0)), Vector2(12, 201), 12, MINT)
	elif failed:
		_text("Call closed · protect the next neighborhood", Vector2(12, 201), 12, Color("eab797"))
	elif not working.is_empty():
		_draw_roster(working, travelling)
	elif not travelling.is_empty():
		var eta: float = 999.0
		for unit in travelling:
			eta = minf(eta, float(unit.get("remaining", 0)))
		_text("%d crew%s dispatched · first arrival in %ds" % [travelling.size(), "s" if travelling.size() > 1 else "", ceili(eta)], Vector2(12, 201), 12, CREAM)
	else:
		_text("No crews assigned · dispatch from the call panel", Vector2(12, 201), 12, Color("d2c7aa"))
	
	_r(2, 207, panel_size.x - 4, 2, Color("102a35"))
	if progress > 0:
		_r(2, 207, (panel_size.x - 4) * clampf(progress, 0, 1), 2, MINT)

func _has_medic(units: Array[Dictionary]) -> bool:
	for unit in units:
		if unit.get("kind", "fire") == "medic":
			return true
	return false

func _draw_scene(kind: String, progress: float, hazard: float, resolved: bool) -> void:
	_r(2, 31, 460, 92, Color("87a382"))
	_r(2, 123, 460, 60, Color("929c84"))
	_r(2, 166, 460, 17, Color("758987"))
	_r(2, 166, 460, 2, Color("d7cba4"))
	for x in range(12, 460, 36):
		_r(x, 176, 17, 1, Color("c0c2a0"))
	
	_r(33, 122, 67, 8, Color("58795c"))
	_r(36, 104, 58, 21, Color("729561"))
	_r(44, 98, 42, 9, Color("8fb477"))
	_r(39, 117, 7, 4, Color("aebd79"))
	_r(75, 110, 6, 5, Color("aebd79"))
	_r(384, 132, 45, 6, Color("586f5d"))
	_r(390, 120, 33, 13, Color("aa8d64"))
	_r(392, 117, 29, 5, Color("719367"))
	for i in range(5):
		_r(394 + i * 5, 114 + i % 2 * 2, 3, 3, Color("e7ba7b") if i % 2 else Color("d38970"))
	if kind in ["fire", "power", "unknown"]:
		_r(151, 67, 168, 67, Color("3e535055"))
		_r(144, 61, 164, 65, Color("e0c89d"))
		_r(290, 62, 18, 64, Color("b59f7f"))
		_r(147, 120, 161, 6, Color("b7a781"))
		draw_colored_polygon(PackedVector2Array([Vector2(133, 65), Vector2(152, 35), Vector2(283, 35), Vector2(316, 65)]), Color("915447"))
		draw_colored_polygon(PackedVector2Array([Vector2(138, 60), Vector2(155, 36), Vector2(282, 36), Vector2(308, 60)]), Color("c87c57"))
		_r(156, 36, 128, 3, Color("e4a16a"))
		for row in range(43, 61, 7):
			for tile in range(155, 289, 20):
				_r(tile + row % 2 * 6, row, 14, 2, Color("b76b51"))
		_r(172, 79, 31, 29, Color("688385"))
		_r(175, 82, 25, 23, Color("bed4bb"))
		_r(186, 81, 3, 26, Color("e4d4aa"))
		_r(174, 93, 27, 3, Color("e4d4aa"))
		_r(250, 83, 25, 41, Color("556e72"))
		_r(254, 87, 17, 16, Color("8cad9f"))
		_r(268, 112, 3, 3, Color("dfca8c"))
		if kind == "fire" and not resolved:
			_r(165, 105, 52, 20, Color(.29, .30, .25, .32))
			Art.draw_flames(self, Vector2(197, 125), hazard, progress, elapsed, 3)
		elif kind == "power":
			_r(321, 64, 5, 65, Color("5e726c"))
			_r(310, 62, 26, 5, Color("4a6564"))
			_r(308, 58, 8, 6, Color("c6bf96"))
			_r(331, 58, 8, 6, Color("c6bf96"))
			if int(elapsed * 7) % 5 == 0 and not resolved:
				_r(310, 70, 5, 2, Color("efd386"))
				_r(305, 74, 2, 5, Color("efd386"))
	elif kind == "medical":
		_r(131, 71, 200, 55, Color("c3bea0"))
		_r(136, 75, 190, 46, Color("cecaac"))
		for x in range(143, 326, 26):
			_r(x, 75, 1, 46, Color("b4b797"))
		_r(136, 97, 190, 1, Color("b4b797"))
		_r(156, 77, 52, 7, Color("b99866"))
		_r(156, 88, 52, 8, Color("c7ac7d"))
		_r(161, 96, 4, 10, Color("526b64"))
		_r(199, 96, 4, 10, Color("526b64"))
		_r(299, 87, 17, 28, Color("73948b"))
		_r(297, 85, 21, 4, Color("c3c6a5"))
	elif kind == "flood":
		_r(121, 91, 216, 7, Color("c8b58b"))
		for i in range(8):
			_r(126 + i * 29, 67, 5, 56, Color("af9c73"))
			_r(126 + i * 29, 67, 5, 3, Color("dcc997"))
		_r(121, 74, 216, 4, Color("d0ba8c"))
		_r(2, 116 + progress * 21, 460, 47 - progress * 19, Color("3e879a"))
		for i in range(25):
			var x: float = fposmod(i * 73 + elapsed * 8, 440) + 8
			var y: float = 121 + i % 5 * 8 + progress * 15
			if y < 163:
				_r(x, y, 10 + i % 3 * 3, 1, Color("83b8b6"))
		_r(63, 135, 29, 7, Color("b89a68"))
		_r(70, 130, 22, 5, Color("d4b984"))
	if resolved:
		_r(205, 83, 42, 7, Color("d0dfac"))
		_r(217, 77, 7, 19, Color("d0dfac"))

func _draw_workers(units: Array[Dictionary], incident_kind: String, progress: float) -> void:
	var count: int = units.size()
	var scale: float = 3.0 if count <= 3 else 2.0
	var columns: int = mini(count, 3) if count <= 3 else 2
	var slot_width: float = 438.0 / columns
	for i in range(count):
		var unit: Dictionary = units[i]
		var kind: String = unit.get("kind", "fire")
		var x: float = 13 + slot_width * (i % columns) + slot_width * .32
		var y: float = 159 - (i / columns) * 48
		if count == 1 and kind == "fire":
			x = 107
		elif count == 1 and kind == "medic":
			x = 198
		var time_at_work: float = float(unit.get("work_elapsed", 2.0))
		var phase: String = unit.get("work_phase", "act")
		var appearance: int = int(unit.get("appearance", unit.get("id", i)))
		Art.draw_team(self, Vector2(x, y), kind, incident_kind, appearance, phase, progress, time_at_work, elapsed + i * .4, scale)
		if phase == "hold":
			_r(x - 4, y - 63, 5, 5, Color("f0c982"))
			_text("CONTAINING", Vector2(x + 5, y - 58), 9, INK)

func _draw_approaching(unit: Dictionary, index: int, count: int, has_workers: bool) -> void:
	var kind: String = unit.get("kind", "fire")
	var x: float = 26 + index * 117
	var y: float = 152 if has_workers else 159
	var remaining: float = float(unit.get("remaining", 0))
	
	_r(x - 5, y - 38, 111, 27, Color("203d4790"))
	_text(_fit(str(unit.get("crew_name", unit.get("name", kind))), 62, 10), Vector2(x, y - 21), 10, CREAM)
	_text("%ds" % ceili(remaining), Vector2(x + 78, y - 21), 10, Color("f1d18f"))
	var car_x: float = x + 29 + (0 if reduced_motion else sin(elapsed * 2 + index) * 2)
	_r(car_x - 18, y - 7, 38, 12, Color("2b444d"))
	_r(car_x - 16, y - 10, 30, 13, Art.uniform(kind))
	_r(car_x + 12, y - 6, 10, 9, Art.uniform(kind).darkened(.1))
	_r(car_x + 4, y - 8, 8, 8, Color("598994"))
	_r(car_x - 11, y + 2, 6, 4, INK)
	_r(car_x + 11, y + 2, 6, 4, INK)
	_r(car_x - 3, y - 12, 5, 3, Color("ed826c") if int(elapsed * 6) % 2 else Color("83c8d4"))
	if kind == "medic":
		_r(car_x - 10, y - 7, 3, 7, Color("ebead1"))
		_r(car_x - 12, y - 5, 7, 3, Color("ebead1"))
	for i in range(2):
		_r(car_x - 24 - i * 6, y + i * 3, 4, 1, Color("bccba980"))

func _draw_roster(working: Array[Dictionary], travelling: Array[Dictionary]) -> void:
	var count: int = mini(3, working.size())
	var width: float = 440.0 / maxi(1, count)
	for i in range(count):
		var unit: Dictionary = working[i]
		var phase: String = unit.get("work_phase", "act")
		var phase_text: String = {"deploy": "Arriving", "hold": "Containing", "assess": "Assessing", "act": "At work", "secure": "Securing"}.get(phase, "At work")
		var names: String = "%s & %s" % [unit.get("crew_name", unit.get("name", "Crew")), unit.get("partner_name", "partner")]
		var text: String = names if int(elapsed * .25) % 2 == 0 else names + " · " + phase_text
		_text(_fit(text, width - 12, 11), Vector2(12 + i * width, 201), 11, Art.uniform(str(unit.get("kind", "fire"))).lightened(.22))
	if not travelling.is_empty() and count == 1:
		_text("+%d en route" % travelling.size(), Vector2(358, 201), 10, Color("e5c88a"))
