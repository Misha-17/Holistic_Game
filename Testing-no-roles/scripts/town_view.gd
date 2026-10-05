class_name TownView
extends Node2D



signal incident_clicked(id: int)
signal map_clicked(pos: Vector2)

const Responders = preload("res://scripts/responder_art.gd")

const MAP_SIZE := Vector2(532, 316)
const INK := Color("223a43")
const CREAM := Color("ecddba")
const WATER := Color("27778b")
const GRASS := Color("8aaa72")
const ROAD := Color("758a87")
const SHADOW := Color("263b424b")

var sim = null
var selected_id: int = -1
var hover_id: int = -1
var title_mode: bool = false
var reduced_motion: bool = false
var interpolate_units: bool = false
var tactical_mode: bool = false
var theme_index: int = 0
var shift_theme: int = 0
var elapsed: float = 0.0
var _painter: Node2D
var _backdrop: StaticTown
var _rng := RandomNumberGenerator.new()
var _sea_glints: Array[Vector3] = []
var _pedestrians: Array[Dictionary] = []
var _lamps: Array[Vector2] = []
var _last_hover: int = -1
var _celebrations: Array[Dictionary] = []
var _alert_left: float = 0.0
var _shown_unit_positions: Dictionary = {}

class StaticTown extends Node2D:
	var town: TownView
	func _draw() -> void:
		town._paint_static(self)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_backdrop = StaticTown.new()
	_backdrop.town = self
	_backdrop.show_behind_parent = true
	add_child(_backdrop)
	_rng.seed = 827314
	for i in range(90):
		_sea_glints.append(Vector3(_rng.randi_range(0, 531), _rng.randi_range(198, 315), _rng.randf() * TAU))
	for i in range(29):
		var horizontal := i % 3 != 0
		var lane: float = [61.0, 139.0, 228.0][i % 3] if horizontal else [95.0, 213.0, 330.0, 446.0][i % 4]
		_pedestrians.append({"horizontal": horizontal, "lane": lane + [-12, 13][i % 2], "phase": _rng.randf(), "speed": _rng.randf_range(0.006, 0.014), "color": [Color("e7c879"), Color("a8c6ad"), Color("dd9276"), Color("567684"), Color("d4cbb1")][i % 5]})
	for x in [83, 200, 317, 434, 489]:
		for y in [47, 125, 214]:
			_lamps.append(Vector2(x, y))

func _process(delta: float) -> void:
	if not reduced_motion:
		elapsed += minf(delta, 0.1)
	_update_unit_positions(delta)
	for effect in _celebrations:
		effect.time = float(effect.time) + delta
	_celebrations = _celebrations.filter(func(effect: Dictionary): return float(effect.time) < 1.8)
	_alert_left = maxf(0.0, _alert_left - delta)
	queue_redraw()

func _update_unit_positions(delta: float) -> void:
	if sim == null:
		_shown_unit_positions.clear()
		return
	var present: Dictionary = {}
	var weight: float = 1.0 - exp(-maxf(0.0, delta) * 14.0)
	for unit in sim.units:
		var ident: int = int(unit.get("id", -1))
		var target: Vector2 = unit.get("pos", Vector2.ZERO)
		var shown: Vector2 = _shown_unit_positions.get(ident, target)
		present[ident] = true
		if not interpolate_units or unit.get("state", "idle") == "idle" or shown.distance_to(target) > 0.3:
			shown = target
		else:
			shown = shown.lerp(target, weight)
		_shown_unit_positions[ident] = shown
	for ident in _shown_unit_positions.keys():
		if not present.has(ident):
			_shown_unit_positions.erase(ident)

func _unit_position(unit: Dictionary) -> Vector2:
	var position: Vector2 = unit.get("pos", Vector2.ZERO)
	if interpolate_units:
		position = _shown_unit_positions.get(int(unit.get("id", -1)), position)
	return position * MAP_SIZE

func set_theme(index: int) -> void:
	shift_theme = clampi(index, 0, 5)
	theme_index = [0, 2, 3, 1, 3, 2][shift_theme]
	if is_instance_valid(_backdrop):
		_backdrop.queue_redraw()
	queue_redraw()

func celebrate(normalized_position: Vector2, points: int, people: int) -> void:
	_celebrations.append({"pos": normalized_position * MAP_SIZE, "points": points, "people": people, "time": 0.0})
	queue_redraw()

func alert() -> void:
	_alert_left = 0.75
	queue_redraw()

func screen_to_normalized(screen_position: Vector2) -> Vector2:
	return (get_global_transform_with_canvas().affine_inverse() * screen_position) / MAP_SIZE

func _unhandled_input(event: InputEvent) -> void:
	if title_mode or tactical_mode or not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		hover_id = _incident_at(local_position)
		if hover_id != _last_hover:
			_last_hover = hover_id
			queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if Rect2(Vector2.ZERO, MAP_SIZE).has_point(local_position):
			var hit := _incident_at(local_position)
			if hit >= 0:
				incident_clicked.emit(hit)
			else:
				map_clicked.emit(local_position / MAP_SIZE)
			get_viewport().set_input_as_handled()

func _incident_at(point: Vector2) -> int:
	if sim == null:
		return -1
	var nearest: int = -1
	var nearest_distance: float = 17.0
	for incident in sim.incidents:
		if incident.get("status", "active") not in ["active", "working"]:
			continue
		var pos: Vector2 = incident.get("pos", Vector2.ONE * 0.5) * MAP_SIZE
		var distance: float = minf(point.distance_to(pos - Vector2(0, 23)), point.distance_to(pos + Vector2(0, 5)))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = int(incident.get("id", -1))
	return nearest

func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	_painter.draw_rect(Rect2(floorf(x), floorf(y), maxf(1, floorf(w)), maxf(1, floorf(h))), c)

func _poly(points: Array, color: Color) -> void:
	var packed := PackedVector2Array()
	for p in points:
		packed.append(Vector2(floorf(p.x), floorf(p.y)))
	_painter.draw_colored_polygon(packed, color)

func _line(a: Vector2, b: Vector2, color: Color, width: float = 1.0) -> void:
	_painter.draw_line(a.floor(), b.floor(), color, width, false)

func _paint_static(canvas: Node2D) -> void:
	_painter = canvas
	_rng.seed = 29401
	var lawn := GRASS if theme_index != 2 else Color("a8b477")
	_r(0, 0, 532, 316, WATER)
	
	for y in range(204, 316, 9):
		_r(0, y, 532, 3, Color("2d7e91") if y % 2 == 0 else Color("277488"))
	_poly([Vector2(0, 0), Vector2(532, 0), Vector2(532, 200), Vector2(513, 213), Vector2(504, 240), Vector2(466, 272), Vector2(413, 286), Vector2(349, 297), Vector2(286, 303), Vector2(197, 298), Vector2(82, 285), Vector2(0, 291)], Color("4a9597"))
	_poly([Vector2(0, 0), Vector2(532, 0), Vector2(532, 191), Vector2(503, 206), Vector2(492, 233), Vector2(458, 259), Vector2(407, 274), Vector2(347, 286), Vector2(284, 291), Vector2(196, 286), Vector2(82, 274), Vector2(0, 280)], Color("bcbf99"))
	_poly([Vector2(0, 0), Vector2(532, 0), Vector2(532, 183), Vector2(498, 201), Vector2(484, 228), Vector2(451, 251), Vector2(403, 266), Vector2(344, 278), Vector2(284, 283), Vector2(196, 278), Vector2(82, 266), Vector2(0, 272)], lawn)
	for i in range(240):
		var x: int = _rng.randi_range(0, 530)
		var y: int = _rng.randi_range(0, 277)
		if not _is_sea(Vector2(x, y + 6)):
			_r(x, y, _rng.randi_range(1, 3), 1, Color("9ab781") if i % 3 else Color("809d69"))
	_draw_roads()
	_draw_gardens()
	
	_building(8, 8, 35, 32, 0, "house")
	_building(49, 8, 30, 32, 1, "house")
	_building(111, 7, 35, 31, 2, "house")
	_building(155, 8, 36, 31, 0, "bakery")
	_building(353, 8, 33, 31, 1, "house")
	_building(394, 7, 29, 34, 0, "house")
	_building(465, 7, 46, 34, 2, "house")
	_building(8, 88, 70, 39, 0, "fire")
	_building(110, 88, 36, 39, 1, "shop")
	_building(156, 90, 39, 37, 0, "cafe")
	_building(235, 86, 67, 43, 2, "clinic")
	_building(348, 89, 75, 41, 2, "power")
	_building(466, 83, 44, 42, 1, "house")
	_building(109, 168, 37, 40, 2, "police")
	_building(157, 173, 40, 35, 2, "library")
	_building(239, 169, 59, 39, 1, "school")
	_building(350, 169, 29, 39, 0, "house")
	_building(387, 172, 36, 36, 1, "house")
	_building(466, 165, 34, 34, 0, "cafe")
	_draw_park()
	_draw_waterfront()
	
	for base in [Vector2(8, 42), Vector2(112, 42), Vector2(353, 43), Vector2(111, 212), Vector2(350, 212)]:
		_fence(base.x, base.y, 30)
		_flowerbed(base.x + 3, base.y - 4, 11, 3)
		_flowerbed(base.x + 22, base.y - 3, 6, 2)
	for p in [Vector2(44, 25), Vector2(149, 20), Vector2(307, 101), Vector2(426, 95), Vector2(148, 181), Vector2(302, 178), Vector2(512, 103)]:
		_r(p.x, p.y, 3, 18, Color("bbc1a1"))
		for k in range(3):
			_r(p.x, p.y + k * 6, 3, 1, Color("85988a"))
	
	for p in [Vector3(5, 41, 12), Vector3(81, 36, 12), Vector3(197, 31, 10), Vector3(232, 38, 12), Vector3(315, 35, 11), Vector3(429, 33, 12), Vector3(525, 25, 13), Vector3(6, 115, 9), Vector3(79, 114, 11), Vector3(200, 114, 10), Vector3(309, 120, 9), Vector3(431, 116, 11), Vector3(520, 123, 13), Vector3(104, 198, 9), Vector3(200, 194, 10), Vector3(306, 196, 12), Vector3(432, 202, 10), Vector3(507, 172, 12), Vector3(79, 256, 9), Vector3(213, 262, 12), Vector3(292, 262, 11)]:
		_tree(p.x, p.y, p.z, int(p.x) % 3)
	for p in [Vector2(17, 250), Vector2(49, 248), Vector2(240, 255), Vector2(277, 251), Vector2(341, 251), Vector2(396, 247)]:
		_tree(p.x, p.y, 10 + int(p.x) % 4, int(p.x) % 3)
	
	_car(Vector2(58, 74), Color("e3b66f"), false, false, 0)
	_car(Vector2(145, 151), Color("638f92"), false, false, 0)
	_car(Vector2(280, 73), Color("deceb0"), false, false, 0)
	_car(Vector2(368, 153), Color("8a6371"), false, false, 0)
	_car(Vector2(513, 69), Color("c38a63"), false, false, 0)
	_car(Vector2(85, 192), Color("b6c0ae"), true, false, 0)
	_car(Vector2(458, 104), Color("cf9565"), true, false, 0)
	for p in [Vector2(74, 82), Vector2(195, 158), Vector2(315, 82), Vector2(436, 158), Vector2(84, 218), Vector2(307, 218)]:
		_bin(p.x, p.y)
	for p in [Vector2(36, 49), Vector2(162, 48), Vector2(264, 48), Vector2(373, 47), Vector2(121, 158), Vector2(288, 158), Vector2(392, 159)]:
		_bench(p.x, p.y)
	for p in _lamps:
		_lamp(p.x, p.y)
	
	for x in [0, 93, 219, 335, 448, 531]:
		_tree(x, 1, 12, x % 3)
	if theme_index == 1:
		_r(0, 0, 532, 316, Color(0.035, 0.09, 0.21, 0.44))
	elif theme_index == 3:
		_r(0, 0, 532, 316, Color(0.12, 0.22, 0.29, 0.19 if shift_theme == 2 else 0.3))
	elif shift_theme == 5:
		_r(0, 0, 532, 316, Color(0.91, 0.45, 0.29, 0.09))

func _draw_roads() -> void:
	for y in [61, 139, 228]:
		var length: int = 532 if y < 200 else 480
		_r(0, y - 13, length, 28, Color("c4c8ac"))
		_r(0, y - 10, length, 22, Color("4e6268"))
		_r(0, y - 9, length, 19, ROAD)
		_r(0, y + 10, length, 1, Color("d9d4b4"))
		for x in range(0, length, 15):
			_r(x, y, 6, 1, Color("b8bb9a"))
			_r(x, y - 13, 1, 2, Color("a7b19d"))
	for x in [95, 213, 330, 446]:
		_r(x - 13, 0, 28, 242, Color("c4c8ac"))
		_r(x - 10, 0, 22, 242, Color("4e6268"))
		_r(x - 9, 0, 19, 242, ROAD)
		_r(x + 10, 0, 1, 242, Color("d9d4b4"))
		for y in range(2, 237, 15):
			_r(x, y, 1, 6, Color("b8bb9a"))
		for y in [61, 139, 228]:
			_r(x - 10, y - 10, 21, 21, ROAD)
			for k in range(4):
				_r(x - 8 + k * 5, y - 16, 3, 4, Color("d6d8ba"))
				_r(x - 8 + k * 5, y + 13, 3, 4, Color("d6d8ba"))
				_r(x - 16, y - 8 + k * 5, 4, 3, Color("d6d8ba"))
				_r(x + 13, y - 8 + k * 5, 4, 3, Color("d6d8ba"))
			_r(x - 17, y - 15, 2, 3, INK)
			_r(x - 17, y - 15, 1, 1, Color("d6be6d"))
	for p in [Vector2(42, 62), Vector2(172, 140), Vector2(368, 62), Vector2(281, 229), Vector2(94, 114), Vector2(448, 187)]:
		_r(p.x - 2, p.y - 1, 5, 3, Color("596d71"))
		_r(p.x - 1, p.y, 3, 1, Color("7f8d86"))
	for x in [22, 133, 253, 365, 485]:
		_r(x, 74, 20, 1, Color("dad6b5"))
		_r(x, 74, 1, 6, Color("dad6b5"))
		_r(x + 19, 74, 1, 6, Color("dad6b5"))

func _building(x: int, y: int, w: int, h: int, roof: int, kind: String) -> void:
	var roofs: Array[Color] = [Color("c66e51"), Color("518b80"), Color("5f879c")]
	var roof_color: Color = roofs[roof]
	var wall := Color("e9d6a6")
	if kind == "clinic":
		wall = Color("d4e1d0")
	elif kind == "fire":
		wall = Color("d5aa85")
	elif kind == "power":
		wall = Color("b4c1b1")
	elif kind == "police":
		wall = Color("c3c9df")
	_r(x + 4, y + 7, w, h, SHADOW)
	_r(x + 2, y + h - 4, w + 1, 8, Color("b9bca1"))
	_r(x + 2, y + 12, w - 2, h - 10, INK)
	_r(x + 3, y + 12, w - 4, h - 12, wall)
	_r(x + w - 7, y + 14, 5, h - 14, wall.darkened(0.19))
	_r(x + 4, y + h - 2, w - 7, 2, wall.darkened(0.23))
	var roof_height: int = 14 if h > 35 else 12
	_poly([Vector2(x - 1, y + roof_height), Vector2(x + 5, y), Vector2(x + w - 8, y), Vector2(x + w + 1, y + roof_height), Vector2(x + w - 1, y + roof_height + 3), Vector2(x - 1, y + roof_height + 3)], INK)
	_poly([Vector2(x, y + roof_height), Vector2(x + 6, y + 1), Vector2(x + w - 8, y + 1), Vector2(x + w, y + roof_height)], roof_color)
	_r(x + 7, y + 1, w - 16, 2, roof_color.lightened(0.23))
	_r(x + 1, y + roof_height, w - 2, 2, roof_color.darkened(0.22))
	for row in range(3, roof_height, 3):
		var edge: int = int(6.0 * (1.0 - float(row) / roof_height))
		for tile in range(x + edge + 2 + (row % 2) * 3, x + w - edge - 3, 6):
			_r(tile, y + row, 4, 1, roof_color.lightened(0.08) if (tile + row) % 4 else roof_color.darkened(0.10))
	_r(x + w - 12, y - 3, 5, 9, Color("a7967d"))
	_r(x + w - 13, y - 4, 7, 2, Color("d6c7a0"))
	_r(x + w - 11, y - 4, 3, 1, Color("51656a"))
	if kind == "fire":
		for i in range(3):
			var dx: int = x + 7 + i * 20
			_r(dx, y + 21, 16, 17, INK)
			_r(dx + 1, y + 22, 14, 14, Color("715d55"))
			for k in range(4):
				_r(dx + 1, y + 23 + k * 3, 14, 1, Color("977f68"))
			_r(dx + 3, y + 25, 4, 3, Color("c4d3c7"))
			_r(dx + 9, y + 25, 4, 3, Color("c4d3c7"))
		_r(x + 23, y + 15, 25, 5, Color("963f3d"))
		_cross(x + 34, y + 16, Color("efdab1"), 3)
		_r(x + 4, y + h + 1, w - 7, 2, Color("d5b95e"))
	elif kind == "power":
		for i in range(4):
			_r(x + 9 + i * 14, y + 21, 10, 15, Color("687e7c"))
			_r(x + 10 + i * 14, y + 22, 8, 2, Color("8fa39a"))
			for j in range(3):
				_r(x + 11 + i * 14, y + 27 + j * 3, 6, 1, Color("405a62"))
		_r(x + 7, y + 4, w - 24, 7, Color("304f62"))
		for i in range(7):
			_r(x + 9 + i * 6, y + 5, 4, 2, Color("64949d"))
			_r(x + 9 + i * 6, y + 8, 4, 2, Color("497986"))
		_r(x + 33, y + 18, 8, 8, Color("ddbd69"))
		_bolt(x + 35, y + 19, INK)
	else:
		for dx in range(x + 6, x + w - 10, 11):
			_window(dx, y + roof_height + 5, roof % 2 == 0)
			if h > 36:
				_r(dx - 1, y + roof_height + 12, 7, 2, Color("9caa7d"))
		var door_x: int = x + w / 2 - 3
		_r(door_x, y + h - 12, 7, 10, Color("55696b"))
		_r(door_x + 1, y + h - 11, 5, 4, Color("9db6ac"))
		_r(door_x + 5, y + h - 5, 1, 1, CREAM)
		_r(door_x - 2, y + h - 1, 11, 2, Color("e4d7b4"))
		if kind == "clinic":
			_r(x + 22, y + 3, 25, 9, Color("e7e2c7"))
			_cross(x + 31, y + 4, Color("b5524e"), 7)
			_r(x + 5, y + 31, w - 14, 2, Color("65969a"))
		elif kind in ["shop", "cafe", "bakery"]:
			_r(x + 4, y + 22, w - 10, 4, Color("f0dbaa"))
			for dx in range(x + 4, x + w - 10, 8):
				_r(dx, y + 22, 4, 5, Color("c47b61") if kind != "shop" else Color("638b83"))
			_r(x + 5, y + 26, w - 12, 1, SHADOW)
			if kind == "cafe":
				_table(x + 6, y + h + 4)
				_table(x + w - 13, y + h + 4)
		elif kind == "school":
			_r(x + 21, y + 5, 15, 7, Color("e6d9b6"))
			_r(x + 27, y + 6, 2, 4, INK)
			_r(x + 29, y + 9, 3, 1, INK)
		elif kind == "library":
			_r(x + 9, y + 17, w - 22, 4, Color("977657"))
			for i in range(5):
				_r(x + 11 + i * 3, y + 18, 1, 2, CREAM)
		elif kind == "police":
			_r(x + 6, y + 3, w - 15, 8, Color("2f3f72"))
			_r(x + 8, y + 5, w - 19, 4, Color("e8e4cf"))
			for i in range(3):
				_r(x + 10 + i * 6, y + 6, 4, 1, Color("2f3f72"))
			_r(x + w - 9, y - 2, 3, 3, Color("7ecdd4"))

func _window(x: int, y: int, warm: bool) -> void:
	_r(x - 1, y - 1, 7, 8, Color("b09e7e"))
	_r(x, y, 5, 6, Color("3c6875"))
	_r(x + 1, y + 1, 3, 4, Color("b9d3ca") if not warm else Color("e3c890"))
	_r(x + 2, y, 1, 6, Color("708781"))
	_r(x, y + 3, 5, 1, Color("708781"))
	_r(x - 1, y + 6, 7, 1, CREAM)

func _draw_gardens() -> void:
	
	_r(9, 170, 67, 39, Color("718b6a"))
	for row in range(3):
		for column in range(3):
			var x: int = 13 + column * 20
			var y: int = 173 + row * 11
			_r(x, y, 16, 8, Color("9f8960"))
			_r(x + 1, y + 1, 14, 6, Color("685e4a"))
			for k in range(4):
				_r(x + 2 + k * 3, y + 2, 2, 3, Color("a7bc79") if row != 1 else Color("7fa16e"))
				_r(x + 3 + k * 3, y + 5, 1, 1, Color("cf9761") if row == 1 else Color("516f58"))
	_fence(8, 210, 71)
	_r(14, 165, 20, 2, Color("c9c4a0"))
	_r(65, 162, 2, 10, Color("677d6a"))
	_r(64, 164, 5, 5, Color("a8bd93"))
	
	_r(235, 4, 75, 40, Color("90a27b"))
	_poly([Vector2(257, 12), Vector2(284, 9), Vector2(299, 17), Vector2(302, 29), Vector2(289, 37), Vector2(262, 34), Vector2(250, 25)], Color("b8be96"))
	_poly([Vector2(260, 14), Vector2(284, 12), Vector2(295, 19), Vector2(298, 28), Vector2(287, 33), Vector2(265, 31), Vector2(255, 24)], Color("528a8c"))
	_r(260, 20, 13, 1, Color("7ea8a0"))
	_r(284, 27, 8, 1, Color("87b1a4"))
	_r(277, 8, 7, 28, Color("a98f64"))
	for y in range(8, 36, 3):
		_r(277, y, 7, 1, Color("ccb58a"))
	_r(276, 8, 1, 28, Color("7a755a"))
	_r(284, 8, 1, 28, Color("7a755a"))
	_tree(241, 15, 10, 0)
	_tree(307, 15, 9, 1)
	_flowerbed(237, 40, 15, 3)
	_flowerbed(289, 40, 15, 3)

func _draw_park() -> void:
	
	_r(9, 82, 1, 1, GRASS)
	_r(235, 213, 64, 2, Color("b8bc9a"))
	for x in range(238, 297, 8):
		_r(x, 212, 3, 1, Color("dad4ad"))
	_r(55, 174, 19, 2, Color("ac9b76"))
	_r(56, 173, 2, 6, Color("726f54"))
	_r(71, 173, 2, 6, Color("726f54"))
	
	_r(472, 133, 46, 20, Color("b8b389"))
	_r(475, 136, 40, 14, Color("c4ba8f"))
	_r(480, 134, 2, 15, Color("827f67"))
	_r(491, 134, 2, 15, Color("827f67"))
	_r(480, 134, 13, 2, Color("b88160"))
	_line(Vector2(484, 136), Vector2(484, 143), INK)
	_line(Vector2(489, 136), Vector2(489, 143), INK)
	_r(483, 143, 7, 2, Color("6a8790"))
	_r(503, 138, 2, 9, Color("8b795c"))
	_poly([Vector2(503, 137), Vector2(507, 137), Vector2(514, 146), Vector2(510, 146)], Color("c58158"))
	_tree(518, 146, 9, 0)

func _draw_waterfront() -> void:
	
	var coast: Array[Vector2] = [Vector2(0, 267), Vector2(82, 261), Vector2(196, 273), Vector2(284, 278), Vector2(343, 273), Vector2(402, 261), Vector2(449, 247), Vector2(479, 223), Vector2(493, 197), Vector2(532, 178)]
	for i in range(coast.size() - 1):
		_line(coast[i] + Vector2(1, 7), coast[i + 1] + Vector2(1, 7), Color("566e67"), 6)
		_line(coast[i] + Vector2(0, 3), coast[i + 1] + Vector2(0, 3), Color("d4c49b"), 6)
		_line(coast[i], coast[i + 1], Color("ead7ac"), 1)
		var segment: Vector2 = coast[i + 1] - coast[i]
		for j in range(int(segment.length() / 6)):
			var p: Vector2 = coast[i] + segment.normalized() * j * 6
			_r(p.x, p.y + 2, 1, 4, Color("a39377"))
	
	_r(353, 280, 15, 35, Color("244e5c"))
	_r(347, 269, 16, 45, Color("a48f69"))
	for y in range(269, 314, 4):
		_r(348, y, 14, 1, Color("d2b689"))
		_r(349, y + 2, 8, 1, Color("97805e"))
	for y in [276, 288, 301, 311]:
		_r(346, y, 3, 4, Color("625f4e"))
		_r(361, y, 3, 4, Color("625f4e"))
		_r(346, y, 3, 1, Color("deca99"))
		_r(361, y, 3, 1, Color("deca99"))
	_r(350, 278, 5, 5, Color("ba9b67"))
	_r(350, 278, 5, 1, Color("dfc393"))
	_r(355, 293, 5, 6, Color("6d8076"))
	_r(356, 294, 3, 1, Color("a9b7a0"))
	
	_boat(Vector2(375, 294), 0, false)
	_boat(Vector2(325, 301), 1, false)
	_boat(Vector2(414, 285), 2, false)
	_poly([Vector2(502, 201), Vector2(523, 192), Vector2(532, 201), Vector2(532, 223), Vector2(513, 222), Vector2(500, 213)], Color("8c9990"))
	_r(507, 210, 13, 2, Color("aab3a0"))
	_r(522, 216, 9, 3, Color("647d7c"))
	_lighthouse(513, 194)
	
	for i in range(3):
		var x: int = 112 + i * 28
		_r(x + 3, 256, 22, 5, SHADOW)
		_r(x + 2, 246, 2, 13, Color("82785d"))
		_r(x + 21, 246, 2, 13, Color("82785d"))
		_r(x, 244, 25, 5, Color("efd7a7"))
		for k in range(3):
			_r(x + 2 + k * 8, 244, 4, 5, Color("c97b61") if i != 1 else Color("699892"))
		_r(x + 1, 253, 23, 6, Color("a98960"))
		_r(x + 2, 253, 21, 1, Color("d9bd89"))
		for k in range(6):
			_r(x + 3 + k * 3, 251, 2, 2, [Color("d9b65f"), Color("b96b55"), Color("8cab76")][i])
	_bench(47, 258)
	_bench(302, 271)
	_bench(390, 263)

func _lighthouse(x: int, y: int) -> void:
	_r(x - 7, y + 14, 24, 5, SHADOW)
	_poly([Vector2(x - 7, y + 14), Vector2(x - 4, y - 10), Vector2(x + 5, y - 10), Vector2(x + 8, y + 14)], Color("e4d6b2"))
	_poly([Vector2(x - 4, y - 1), Vector2(x + 5, y - 1), Vector2(x + 6, y + 5), Vector2(x - 5, y + 5)], Color("b86a56"))
	_r(x + 3, y - 9, 2, 21, Color("b9ad91"))
	_r(x - 8, y - 12, 17, 3, INK)
	_r(x - 5, y - 21, 11, 9, Color("c6b998"))
	_r(x - 3, y - 20, 7, 6, Color("f4d995"))
	_r(x, y - 20, 1, 7, Color("836f54"))
	_poly([Vector2(x - 7, y - 22), Vector2(x, y - 28), Vector2(x + 8, y - 22)], Color("b76b53"))
	_r(x - 7, y - 22, 15, 2, Color("8c5348"))
	_r(x - 1, y - 30, 2, 3, INK)
	_r(x - 2, y + 8, 5, 7, Color("536c70"))
	_r(x - 9, y + 15, 20, 2, Color("d7c89d"))

func _tree(x: float, y: float, size: float, variety: int) -> void:
	var dark: Color = [Color("355d50"), Color("456b50"), Color("627544")][variety]
	var mid: Color = [Color("5a8b58"), Color("77a05f"), Color("91aa5b")][variety]
	var light: Color = [Color("8cb86f"), Color("afd280"), Color("bcd279")][variety]
	if theme_index == 2:
		mid = [Color("aa895c"), Color("b99161"), Color("bfaa6f")][variety]
		light = mid.lightened(0.16)
	_r(x - size * 0.6 + 4, y + 1, size * 1.4, 4, SHADOW)
	_r(x - 1, y - 5, 3, 8, Color("716b52"))
	_r(x + 1, y - 5, 1, 8, Color("4f6050"))
	_poly([Vector2(x - size, y - size * .5), Vector2(x - size, y - size), Vector2(x - size * .6, y - size), Vector2(x - size * .6, y - size * 1.5), Vector2(x + size * .4, y - size * 1.5), Vector2(x + size * .4, y - size * 1.2), Vector2(x + size * .8, y - size * 1.2), Vector2(x + size, y - size * .4), Vector2(x + size * .5, y), Vector2(x - size * .4, y)], dark)
	_r(x - size * .7, y - size * 1.3, size, size * .75, mid)
	_r(x - size * .95, y - size, size * .6, size * .65, mid)
	_r(x, y - size, size * .7, size * .65, mid)
	_r(x - size * .5, y - size * 1.45, size * .6, 3, light)
	_r(x - size * .85, y - size * .9, 3, 3, light)
	_r(x + size * .2, y - size * .9, size * .35, 2, light)
	for i in range(7):
		var dx: float = _rng.randf_range(-size * .65, size * .6)
		var dy: float = _rng.randf_range(-size * 1.2, -size * .3)
		_r(x + dx, y + dy, 2, 1, light if i % 2 else dark)
	if variety == 2:
		_r(x - 4, y - 8, 2, 2, Color("dbaa69"))
		_r(x + 4, y - 5, 2, 2, Color("dbaa69"))

func _fence(x: float, y: float, length: int) -> void:
	_r(x, y + 2, length, 1, Color("d3caa5"))
	_r(x, y + 5, length, 1, Color("9f9f81"))
	for i in range(0, length, 5):
		_r(x + i, y, 2, 7, Color("ddd4af"))
		_r(x + i + 1, y + 1, 1, 6, Color("b9b596"))

func _flowerbed(x: float, y: float, w: int, h: int) -> void:
	_r(x, y, w, h + 2, Color("667f60"))
	for i in range(1, w, 3):
		_r(x + i, y - 1 + (i % 2), 2, 2, Color("e6c884") if i % 2 else Color("d78e78"))

func _bench(x: float, y: float) -> void:
	_r(x + 2, y + 2, 12, 3, SHADOW)
	_r(x, y, 12, 2, Color("bba475"))
	_r(x, y - 2, 12, 1, Color("cfbb8b"))
	_r(x + 1, y + 2, 1, 3, INK)
	_r(x + 10, y + 2, 1, 3, INK)

func _table(x: float, y: float) -> void:
	_r(x + 1, y, 5, 3, Color("a78a61"))
	_r(x + 1, y, 5, 1, Color("ddc49a"))
	_r(x + 3, y + 3, 1, 2, Color("716d56"))
	_r(x - 2, y + 1, 2, 3, Color("829788"))
	_r(x + 7, y + 1, 2, 3, Color("829788"))

func _bin(x: float, y: float) -> void:
	_r(x, y, 4, 6, Color("547c72"))
	_r(x - 1, y, 6, 1, Color("a4b498"))
	_r(x + 1, y + 2, 1, 3, Color("759789"))

func _lamp(x: float, y: float) -> void:
	_r(x + 2, y + 2, 7, 2, SHADOW)
	_r(x, y - 10, 1, 13, Color("5d7067"))
	_r(x - 1, y + 2, 3, 1, Color("49615f"))
	_r(x - 2, y - 11, 5, 3, Color("9b9f7d"))
	_r(x - 1, y - 10, 3, 2, Color("f1d99a"))

func _cross(x: float, y: float, color: Color, size: int = 5) -> void:
	var third: int = maxi(1, size / 3)
	_r(x + third, y, third, size, color)
	_r(x, y + third, size, third, color)

func _bolt(x: float, y: float, color: Color) -> void:
	_poly([Vector2(x + 3, y), Vector2(x, y + 4), Vector2(x + 2, y + 4), Vector2(x + 1, y + 7), Vector2(x + 5, y + 2), Vector2(x + 3, y + 2)], color)

func _boat(p: Vector2, variant: int, moving: bool) -> void:
	var x: float = p.x
	var y: float = p.y
	if moving:
		_r(x - 18, y + 2, 13, 1, Color("83b5ad"))
		_r(x - 13, y + 5, 8, 1, Color("5f9a9c"))
	_poly([Vector2(x - 10, y - 3), Vector2(x + 8, y - 3), Vector2(x + 13, y), Vector2(x + 8, y + 4), Vector2(x - 8, y + 4)], Color("214f60"))
	_poly([Vector2(x - 10, y - 5), Vector2(x + 7, y - 5), Vector2(x + 12, y - 1), Vector2(x + 7, y + 2), Vector2(x - 8, y + 2)], Color("dfcca1"))
	_r(x - 7, y - 3, 14, 3, [Color("9b6256"), Color("62848a"), Color("ba9961")][variant])
	_r(x - 2, y - 7, 7, 5, Color("e5d7b5"))
	_r(x + 3, y - 6, 2, 3, Color("587d85"))
	_r(x, y - 9, 1, 3, INK)
	_r(x - 7, y - 2, 3, 1, Color("c1a773"))

func _is_sea(p: Vector2) -> bool:
	if p.x < 82:
		return p.y > 282 - p.x * .07
	if p.x < 284:
		return p.y > 277 + (p.x - 82) * .08
	if p.x < 402:
		return p.y > 294 - (p.x - 284) * .18
	if p.x < 458:
		return p.y > 274 - (p.x - 402) * .30
	if p.x < 495:
		return p.y > 258 - (p.x - 458) * .95
	return p.y > 222 - (p.x - 495) * .67

func _draw() -> void:
	_painter = self
	_draw_sea_life()
	_draw_town_life()
	if tactical_mode:
		_r(0, 0, 532, 316, Color(0.075, 0.16, 0.19, 0.30))
	if sim != null:
		if not tactical_mode:
			_draw_routes()
		for incident in sim.incidents:
			_draw_incident(incident, 1)
		for unit in sim.units:
			_draw_unit(unit)
		if not tactical_mode:
			for incident in sim.incidents:
				_draw_incident(incident, 2)
	_draw_weather()
	_draw_celebrations()

func _draw_sea_life() -> void:
	for glint in _sea_glints:
		var p := Vector2(glint.x + sin(elapsed * .24 + glint.z) * 3.0, glint.y)
		if _is_sea(p):
			var strength: float = (sin(elapsed * .8 + glint.z) + 1) * .5
			var col: Color = Color("74a6a6") if strength > .72 else Color("438590")
			_r(p.x, p.y, 3 + int(strength * 6), 1, col)
			if strength > .94:
				_r(p.x + 2, p.y - 1, 2, 1, Color("a6c3b4"))
	var boat_x: float = 32 + fposmod(elapsed * 2.3, 228)
	_boat(Vector2(boat_x, 304 + sin(elapsed * .8) * .6), 1, true)
	
	for i in range(3):
		var gx: float = fposmod(453 + i * 49 + elapsed * (4 + i), 570) - 20
		var gy: float = 286 + sin(elapsed * .3 + i * 2) * 14
		if _is_sea(Vector2(gx, gy)):
			var flap: int = 1 if sin(elapsed * 3 + i) > 0 else -1
			_r(gx, gy, 2, 1, Color("efdfba"))
			_r(gx - 2, gy + flap, 2, 1, Color("efdfba"))
			_r(gx + 2, gy + flap, 2, 1, Color("efdfba"))
	
	if sin(elapsed * .7) > .8:
		_r(511, 175, 3, 2, Color("ffe6a4"))
		_r(508, 176, 1, 1, Color("f0d7a2"))
		_r(516, 176, 1, 1, Color("f0d7a2"))

func _draw_town_life() -> void:
	for pedestrian in _pedestrians:
		var horizontal: bool = pedestrian.horizontal
		var phase: float = fposmod(float(pedestrian.phase) + elapsed * float(pedestrian.speed), 1.0)
		var p: Vector2 = Vector2(phase * 520 + 4, pedestrian.lane) if horizontal else Vector2(pedestrian.lane, phase * 236)
		var gait: int = int(elapsed * 5 + float(pedestrian.phase) * 6) % 2
		_person(p, pedestrian.color, gait)
	
	for i in range(4):
		var cx: float = fposmod(elapsed * (7 + i * 2) + i * 151, 568) - 18
		var cy: float = [57.0, 144.0, 232.0, 66.0][i]
		if cx < 472 or cy < 200:
			_car(Vector2(cx, cy), [Color("d1b674"), Color("6d9695"), Color("d0c9af"), Color("b58578")][i], false, false, 0)
	
	_r(19, 90, 1, 15, Color("b4b798"))
	_r(20, 90, 6, 3, Color("c76557"))
	_r(25, 90 + int(sin(elapsed * 2) > 0), 3, 3, Color("c76557"))
	
	_line(Vector2(53, 45), Vector2(72, 45), Color("6d7966"))
	for i in range(3):
		var shift: int = int(sin(elapsed * 1.6 + i) > .5)
		_r(55 + i * 6, 45 + shift, 3, 4, [Color("d6ceaa"), Color("ad806d"), Color("7b9b95")][i])
	
	for p in [Vector2(68, 6), Vector2(181, 6), Vector2(419, 6)]:
		for i in range(2):
			var drift: float = fposmod(elapsed * 2 + i * 5, 11)
			_r(p.x + drift * .25, p.y - drift, 2 + i, 2, Color(0.82, 0.83, 0.73, (1.0 - drift / 11.0) * .4))
	if theme_index == 1:
		for p in _lamps:
			_r(p.x - 6, p.y - 13, 13, 9, Color(1.0, .78, .38, .06))
			_r(p.x - 4, p.y - 11, 9, 6, Color(1.0, .78, .38, .13))
			_r(p.x - 2, p.y - 10, 5, 3, Color(1.0, .85, .48, .27))
			_r(p.x - 1, p.y - 10, 3, 2, Color("efd090"))
		for p in [Vector2(15, 26), Vector2(56, 26), Vector2(118, 25), Vector2(163, 26), Vector2(362, 27), Vector2(400, 27), Vector2(479, 26), Vector2(117, 108), Vector2(163, 109), Vector2(242, 109), Vector2(265, 109), Vector2(473, 104), Vector2(117, 190), Vector2(164, 191), Vector2(248, 190), Vector2(358, 191), Vector2(394, 191), Vector2(473, 184)]:
			_r(p.x - 2, p.y - 2, 7, 8, Color(1.0, .74, .32, .08))
			_r(p.x, p.y, 3, 4, Color("debf7e"))
			_r(p.x + 1, p.y, 1, 4, Color("aa936d"))
		_r(510, 173, 6, 5, Color("f5d694"))

func _person(p: Vector2, coat: Color, gait: int) -> void:
	_r(p.x, p.y + 2, 4, 1, Color("394f4a55"))
	_r(p.x, p.y - 4, 2, 2, Color("d6b58a"))
	_r(p.x, p.y - 5, 2, 1, Color("575348"))
	_r(p.x - 1, p.y - 2, 4, 3, coat)
	_r(p.x, p.y + 1, 1, 2 - gait, INK)
	_r(p.x + 2, p.y + 1, 1, 1 + gait, INK)

func _car(p: Vector2, color: Color, vertical: bool, emergency: bool, kind: int) -> void:
	var x: float = p.x
	var y: float = p.y
	if vertical:
		_r(x - 3, y - 5, 8, 13, SHADOW)
		_r(x - 3, y - 5, 6, 11, INK)
		_r(x - 4, y - 3, 1, 2, INK)
		_r(x + 3, y - 3, 1, 2, INK)
		_r(x - 4, y + 3, 1, 2, INK)
		_r(x + 3, y + 3, 1, 2, INK)
		_r(x - 2, y - 5, 4, 11, color)
		_r(x - 2, y - 2, 4, 2, Color("304f60"))
		_r(x - 2, y + 1, 4, 2, color.lightened(.22))
		_r(x - 2, y + 4, 4, 1, Color("405f69"))
		_r(x - 2, y - 5, 1, 1, CREAM)
		_r(x + 1, y - 5, 1, 1, CREAM)
		if emergency:
			_r(x - 2, y, 2, 1, Color("ed7667") if int(elapsed * 7) % 2 else Color("f8d496"))
			_r(x, y, 2, 1, Color("7ecdd4") if int(elapsed * 7) % 2 == 0 else Color("4a889c"))
	else:
		_r(x - 5, y - 2, 14, 7, SHADOW)
		_r(x - 6, y - 3, 13, 6, INK)
		_r(x - 4, y - 4, 2, 1, INK)
		_r(x + 3, y - 4, 2, 1, INK)
		_r(x - 4, y + 3, 2, 1, INK)
		_r(x + 3, y + 3, 2, 1, INK)
		_r(x - 6, y - 2, 13, 4, color)
		_r(x + 2, y - 2, 2, 4, Color("365867"))
		_r(x - 3, y - 2, 4, 4, color.lightened(.18))
		_r(x - 5, y - 2, 2, 4, Color("4d7179"))
		_r(x + 6, y - 2, 1, 1, CREAM)
		_r(x + 6, y + 1, 1, 1, CREAM)
		if emergency:
			_r(x, y - 2, 1, 2, Color("ef8068") if int(elapsed * 7) % 2 else Color("f7d99d"))
			_r(x, y, 1, 2, Color("80d4db") if int(elapsed * 7) % 2 == 0 else Color("4e8e9e"))
			if kind == 1:
				_cross(x - 4, y - 1, Color("b65351"), 3)

func _draw_routes() -> void:
	if selected_id < 0:
		return
	for unit in sim.units:
		if int(unit.get("target", -2)) != selected_id or unit.get("state", "idle") != "travel":
			continue
		var start: Vector2 = _unit_position(unit)
		var route: Array = unit.get("path", [])
		for waypoint in range(int(unit.get("path_index", 0)), route.size()):
			var finish: Vector2 = route[waypoint] * MAP_SIZE
			var distance: float = start.distance_to(finish)
			for i in range(int(distance / 7)):
				var p: Vector2 = start.lerp(finish, minf(1, (i * 7 + fposmod(elapsed * 9, 7)) / maxf(1, distance)))
				_r(p.x, p.y, 2, 2, Color("ead69a"))
			start = finish

func _draw_unit(unit: Dictionary) -> void:
	var p: Vector2 = _unit_position(unit)
	var kind: String = unit.get("kind", "fire")
	var state: String = unit.get("state", "idle")
	var color: Color = {"fire": Color("cf725a"), "medic": Color("e4ddba"), "engineer": Color("e0b768"), "police": Color("5f72c4")}.get(kind, Color("7fab9a"))
	var vertical: bool = false
	if state == "travel" or state == "return":
		var vector: Vector2 = unit.get("heading", Vector2.RIGHT)
		vertical = absf(vector.y) > absf(vector.x)
		if not reduced_motion:
			for i in range(3):
				var trail: Vector2 = p - vector.normalized() * (9 + i * 4)
				_r(trail.x, trail.y, 2, 1, Color(0.86, 0.82, 0.64, .25 - i * .07))
	if state == "working":
		var incident: Dictionary = {}
		for item in sim.incidents:
			if int(item.get("id", -1)) == int(unit.get("target", -2)):
				incident = item
				break
		if not incident.is_empty():
			var index: int = 0
			for other in sim.units:
				if int(other.get("id", -1)) < int(unit.get("id", -1)) and other.get("state", "") == "working" and other.get("kind", "") == kind and other.get("target", -1) == unit.get("target", -2):
					index += 1
			var appearance: int = int(unit.get("appearance", unit.get("id", 0)))
			var worked: float = float(unit.get("work_elapsed", 2.0))
			var phase: String = unit.get("work_phase", "act")
			var scene: Vector2 = {"fire": Vector2(-20, 14), "medic": Vector2(3, 22), "engineer": Vector2(-7, 27), "police": Vector2(16, 10)}.get(kind, Vector2.ZERO)
			var parking: Vector2 = {"fire": Vector2(-36, 22), "medic": Vector2(34, 29), "engineer": Vector2(-28, 32), "police": Vector2(36, 6)}.get(kind, Vector2.ZERO)
			var extra := Vector2(index * -5, index * 11)
			var parked_position: Vector2 = p + (parking + extra).lerp(Vector2.ZERO, 1 - minf(1, worked * 2))
			parked_position = parked_position.clamp(Vector2(10, 8), MAP_SIZE - Vector2(10, 9))
			var scene_position: Vector2 = (p + scene + extra).clamp(Vector2(19, 22), MAP_SIZE - Vector2(45, 8))
			_car(parked_position, color, false, true, 1 if kind == "medic" else 0)
			if not bool(incident.get("discovered", true)) or not bool(unit.get("assignment_suitable", true)):
				Responders.draw_person(self, scene_position, kind, appearance, "radio", elapsed, 1, 1)
				Responders.draw_person(self, scene_position + Vector2(-12, 3), kind, appearance + 9, "walk" if worked < 1.6 else "radio", elapsed + .4, 1, 1)
			else:
				Responders.draw_team(self, scene_position, kind, str(incident.get("kind", "fire")), appearance, phase, float(incident.get("progress", 0)), worked, elapsed + appearance * .3, 1)
			return
	_car(p, color, vertical, state in ["travel", "working"], 1 if kind == "medic" else 0)

func _draw_incident(incident: Dictionary, layer: int = 0) -> void:
	var state: String = incident.get("status", "active")
	if state not in ["active", "working"]:
		return
	var p: Vector2 = incident.get("pos", Vector2.ONE * .5) * MAP_SIZE
	var kind: String = incident.get("kind", "fire")
	var discovered: bool = incident.get("discovered", true)
	var color: Color = {"fire": Color("ed936b"), "medical": Color("c7dcb1"), "flood": Color("7bbec9"), "power": Color("edd083"), "police": Color("b3bbef")}.get(kind, Color("e8c485"))
	if not discovered:
		color = Color("c9c3d1")
	var ident: int = incident.get("id", -1)
	var selected: bool = ident == selected_id
	var hovered: bool = ident == hover_id
	var deadline: float = float(incident.get("deadline", 60)) / maxf(1, float(incident.get("max_deadline", 60)))
	var progress: float = float(incident.get("progress", 0))
	var hazard: float = float(incident.get("hazard", .3))
	if kind == "fire" and discovered and layer != 2:
		Responders.draw_flames(self, p + Vector2(0, 5), hazard, progress, elapsed, 1)
	elif kind == "flood" and discovered and layer != 2:
		var spread: float = (14 + hazard * 15) * (1 - progress * .6)
		_r(p.x - spread, p.y - 2, spread * 2, 9 + hazard * 5, Color("478e9e"))
		_r(p.x - spread + 3, p.y + 7 + hazard * 5, spread * 2 - 6, 2, Color("70a9b2"))
		for i in range(3):
			_r(p.x - 9 + i * 7 + sin(elapsed * 2 + i) * 2, p.y + i % 2 * 3, 5, 1, Color("b1d1c5"))
	elif kind == "power" and discovered and layer != 2:
		if int(elapsed * 5 + ident) % 4 == 0:
			_r(p.x - 8, p.y - 3, 2, 1, Color("f4daa0"))
			_r(p.x + 8, p.y + 1, 1, 2, Color("f4daa0"))
	elif kind == "police" and discovered and layer != 2:
		# Two bumped cars behind a cone line.
		_car(p + Vector2(-9, 8), Color("b98a6d"), false, false, 0)
		_car(p + Vector2(6, 11), Color("7f98a3"), false, false, 0)
		for i in range(4):
			_r(p.x - 14 + i * 9, p.y + 18, 3, 3, Color("ee8a52"))
			_r(p.x - 14 + i * 9, p.y + 19, 3, 1, Color("f4e3c0"))
	elif kind == "medical" and discovered and layer != 2:
		var has_medic: bool = false
		for unit in sim.units:
			if unit.get("kind", "") == "medic" and unit.get("state", "") == "working" and unit.get("target", -1) == ident:
				has_medic = true
		if not has_medic:
			Responders.draw_casualty(self, p + Vector2(-3, 13), ident + 2, false, elapsed, 1)
	if layer == 1:
		return
	
	var bx: float = p.x - 8
	var by: float = p.y - 30
	if selected or hovered:
		var edge: Color = Color("f8e2ac") if selected else Color("c9d7bd")
		_corner(p + Vector2(0, -23), 13, 11, edge)
	_r(bx + 2, by + 1, 14, 16, Color("1c333c75"))
	_r(bx, by, 16, 15, Color("203842"))
	_r(bx + 1, by + 1, 14, 12, color)
	_poly([Vector2(p.x - 3, by + 14), Vector2(p.x + 4, by + 14), Vector2(p.x, by + 18)], INK)
	if not discovered:
		_r(bx + 5, by + 3, 6, 2, Color("5e586b"))
		_r(bx + 10, by + 4, 2, 3, Color("5e586b"))
		_r(bx + 7, by + 6, 4, 2, Color("5e586b"))
		_r(bx + 7, by + 7, 2, 2, Color("5e586b"))
		_r(bx + 7, by + 10, 2, 2, Color("5e586b"))
	elif kind == "medical":
		_cross(bx + 4, by + 3, Color("3d706a"), 7)
	elif kind == "fire":
		_poly([Vector2(bx + 5, by + 10), Vector2(bx + 4, by + 7), Vector2(bx + 7, by + 3), Vector2(bx + 8, by + 6), Vector2(bx + 11, by + 4), Vector2(bx + 12, by + 9), Vector2(bx + 10, by + 11)], Color("743e3b"))
		_r(bx + 7, by + 8, 2, 3, Color("f2d4a0"))
	elif kind == "power":
		_bolt(bx + 5, by + 3, Color("6f6547"))
	elif kind == "police":
		_r(bx + 4, by + 3, 8, 6, Color("36457e"))
		_poly([Vector2(bx + 4, by + 9), Vector2(bx + 12, by + 9), Vector2(bx + 8, by + 12)], Color("36457e"))
		_r(bx + 7, by + 5, 2, 2, Color("e8e4cf"))
	else:
		for i in range(3):
			_r(bx + 3, by + 4 + i * 3, 9, 1, Color("305c73"))
			_r(bx + 6 + (i % 2) * 2, by + 3 + i * 3, 3, 1, Color("305c73"))
	_r(bx + 1, by + 13, 14, 2, Color("42555a"))
	_r(bx + 1, by + 13, maxf(1, 14 * clampf(deadline, 0, 1)), 2, Color("e6c477") if deadline > .3 else Color("e77762"))
	if progress > 0:
		_r(p.x - 9, p.y - 11, 18, 3, INK)
		_r(p.x - 8, p.y - 10, 16 * clampf(progress, 0, 1), 1, Color("aad4b4"))
	if int(incident.get("hazard_stage", 0)) >= 2:
		_r(bx + 17, by + 3, 2, 5, Color("f1a178"))
		_r(bx + 17, by + 10, 2, 2, Color("f1a178"))
	if deadline < .25 and int(elapsed * 3) % 2 == 0:
		_r(bx + 13, by - 3, 3, 3, Color("ffd6a0"))

func _corner(center: Vector2, half_w: float, half_h: float, color: Color) -> void:
	for side in [-1, 1]:
		for top in [-1, 1]:
			var x: float = center.x + side * half_w
			var y: float = center.y + top * half_h
			_r(x if side < 0 else x - 4, y, 5, 1, color)
			_r(x, y if top < 0 else y - 4, 1, 5, color)

func _draw_weather() -> void:
	if theme_index == 3:
		for i in range(65):
			var x: float = fposmod(i * 83 + elapsed * 37, 532)
			var y: float = fposmod(i * 41 + elapsed * 89, 316)
			_line(Vector2(x, y), Vector2(x - 2, y + 4), Color(.72, .84, .82, .28))
	if theme_index == 1:
		
		for i in range(5):
			var intensity: float = (sin(elapsed * 1.8 + i * 2) + 1) * .5
			if intensity > .65:
				_r(20 + i * 11 + sin(elapsed + i) * 2, 194 + cos(elapsed * .7 + i) * 6, 1, 1, Color("f0d793"))
	if _alert_left > 0:
		_r(509, 173, 8, 4, Color("ffe3a0"))
		_r(506, 174, 2, 2, Color("edcc8b"))
		_r(518, 174, 2, 2, Color("edcc8b"))

func _draw_celebrations() -> void:
	for effect in _celebrations:
		var age: float = effect.time
		var origin: Vector2 = effect.pos
		var fade: float = clampf((1.8 - age) / .5, 0, 1)
		var rise: float = 0 if reduced_motion else age * 10.0
		
		var p := Vector2(clampf(origin.x, 25, 505), clampf(origin.y - 14 - rise, 15, 295))
		var label: String = "%d SAFE" % int(effect.people)
		var width: float = ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_r(p.x - width * .5 - 4, p.y - 10, width + 8, 14, Color(.10, .24, .27, .88 * fade))
		_painter.draw_string(ThemeDB.fallback_font, Vector2(p.x - width * .5, p.y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(.88, .99, .83, fade))
		var spread: float = 4 + minf(age, .8) * 13
		for i in range(5):
			var a: float = -PI + i * PI / 4.0
			var heart := origin + Vector2(cos(a) * spread, sin(a) * spread - 5 - rise * .4)
			var color := Color(.94, .63, .51, fade)
			if i % 2 == 0:
				_r(heart.x, heart.y, 2, 2, color)
				_r(heart.x + 3, heart.y, 2, 2, color)
				_r(heart.x, heart.y + 1, 5, 2, color)
				_r(heart.x + 1, heart.y + 3, 3, 1, color)
				_r(heart.x + 2, heart.y + 4, 1, 1, color)
			else:
				_cross(heart.x, heart.y, Color(.96, .84, .54, fade), 3)
