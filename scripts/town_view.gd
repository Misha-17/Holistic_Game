class_name TownView
extends Node2D

signal incident_clicked(id: int)
signal map_clicked(pos: Vector2)

const Responders = preload("res://scripts/responder_art.gd")
const MAP_SIZE := BeaconCampaign.MAP_SIZE
const PixelArt = preload("res://scripts/pixel_town_art.gd")
const INK := Color("30474e")
const CREAM := Color("f1dfb4")
const ROAD_X := [96.0,352.0,608.0,864.0,1120.0,1376.0,1632.0,1888.0,2144.0,2400.0,2656.0]
const ROAD_Y := [192.0,448.0,704.0,928.0,1184.0,1440.0]
const SITE_TILES := [0,1,2,11,4,0,5,6,7,8,9,10,11,0,12,13,0,11,12,11,15,3,5,11,13,6,7,13,6,5,5,14]

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
var _backdrop: StaticTown
var _shown_unit_positions: Dictionary = {}
var _celebrations: Array[Dictionary] = []
var _alert_left: float = 0.0
var _pixel: PixelTownArt

class StaticTown extends Node2D:
	var town: TownView
	func _draw() -> void:
		town._paint_static(self)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pixel = PixelArt.new(self)
	_backdrop = StaticTown.new()
	_backdrop.town = self
	_backdrop.show_behind_parent = true
	add_child(_backdrop)

func _process(delta: float) -> void:
	if not reduced_motion:
		elapsed += minf(delta, 0.1)
	_update_unit_positions(delta)
	for effect: Dictionary in _celebrations:
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
	for unit: Dictionary in sim.units:
		var ident: int = int(unit.get("id", -1))
		var target: Vector2 = unit.get("pos", Vector2.ZERO)
		var shown: Vector2 = _shown_unit_positions.get(ident, target)
		present[ident] = true
		if not interpolate_units or unit.get("state", "idle") == "idle" or shown.distance_to(target) > 0.3:
			shown = target
		else:
			shown = shown.lerp(target, weight)
		_shown_unit_positions[ident] = shown
	for ident: int in _shown_unit_positions.keys():
		if not present.has(ident):
			_shown_unit_positions.erase(ident)

func _unit_position(unit: Dictionary) -> Vector2:
	var pos: Vector2 = unit.get("pos", Vector2.ZERO)
	if interpolate_units:
		pos = _shown_unit_positions.get(int(unit.get("id", -1)), pos)
	return pos * MAP_SIZE

func set_theme(index: int) -> void:
	shift_theme = clampi(index, 0, 5)
	# 0 day, 1 night, 2 golden, 3 rain, 4 desert
	theme_index = [0,2,3,1,4,2][shift_theme]
	if is_instance_valid(_backdrop):
		_backdrop.queue_redraw()
	queue_redraw()

func celebrate(normalized_position: Vector2, points: int, people: int) -> void:
	_celebrations.append({"pos":normalized_position * MAP_SIZE, "points":points, "people":people, "time":0.0})

func alert() -> void:
	_alert_left = 0.75

func screen_to_normalized(screen_position: Vector2) -> Vector2:
	return (get_global_transform_with_canvas().affine_inverse() * screen_position) / MAP_SIZE

func _unhandled_input(event: InputEvent) -> void:
	if title_mode or tactical_mode or not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		hover_id = _incident_at(screen_to_normalized(event.position) * MAP_SIZE)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var point: Vector2 = screen_to_normalized(event.position)
		if Rect2(Vector2.ZERO,Vector2.ONE).has_point(point):
			var hit: int = _incident_at(point * MAP_SIZE)
			if hit >= 0:
				incident_clicked.emit(hit)
			else:
				map_clicked.emit(point)
			get_viewport().set_input_as_handled()

func _incident_at(point: Vector2) -> int:
	if sim == null:
		return -1
	for incident: Dictionary in sim.incidents:
		if incident.get("status","active") in ["active","working"] and point.distance_to(incident.pos * MAP_SIZE) < 30:
			return int(incident.id)
	return -1

func _paint_static(canvas: Node2D) -> void:
	var art := PixelArt.new(canvas)
	art.theme_index = theme_index
	var layout: Dictionary = BeaconCampaign.layout(shift_theme)
	var desert: bool = str(layout.get("theme","")) == "desert"
	var grass := Color("9fbd87") if theme_index != 2 else Color("b7bc88")
	if desert: grass = Color("dcc58f")
	_paint_outskirts(canvas, art, layout, desert, grass)
	canvas.draw_rect(Rect2(Vector2.ZERO,MAP_SIZE),grass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 29401
	# Subtle patches and tiny grass clusters keep the original handmade pixel feel.
	for i: int in range(1500):
		var point := Vector2(rng.randi_range(0,int(MAP_SIZE.x)),rng.randi_range(0,1470))
		if desert: canvas.draw_rect(Rect2(point,Vector2(4,2)),Color("cdb27a") if i%3 else Color("e8d6a6"))
		else: canvas.draw_rect(Rect2(point,Vector2(3,2)),Color("91af7e") if i%3 else Color("b3ca96"))
	for district: Dictionary in [
		{"area":Rect2(1662,214,452,454),"color":Color("a4bf8b")},
		{"area":Rect2(2174,214,194,454),"color":Color("9bb895")},
		{"area":Rect2(386,980,710,164),"color":Color("a8c493")},
		{"area":Rect2(1154,1216,1220,190),"color":Color("b0bf96")}
	]:
		canvas.draw_rect(district.area,district.color if not desert else Color(district.color.lerp(Color("d5b980"),0.85)))
	if desert:
		# Wind-ripples in the sand instead of the sea.
		for i: int in range(260):
			var at := Vector2(rng.randi_range(0,int(MAP_SIZE.x)),rng.randi_range(0,1500))
			canvas.draw_line(at,at+Vector2(26,-3),Color("c9ad74"),2.0)
		_draw_dune_band(canvas)
	else:
		# Harbor basin in the original district, plus an extended southern waterfront.
		if not str(layout.get("theme","")) == "night": _draw_basin(canvas,Rect2(1172,856,428,106))
		canvas.draw_rect(Rect2(0,1473,MAP_SIZE.x,MAP_SIZE.y-1473),Color("4f8f98"))
		canvas.draw_rect(Rect2(0,1484,MAP_SIZE.x,MAP_SIZE.y-1484),Color("367f8e"))
		for x: int in range(0,int(MAP_SIZE.x),24):
			canvas.draw_rect(Rect2(x,1470+(x/24)%3*2,24,8),Color("ded2ac"))
			canvas.draw_rect(Rect2(x,1478+(x/24)%3*2,24,3),Color("809889"))
	_draw_roads(canvas, layout)
	if layout.has("river"):
		_draw_river(canvas, art, layout)
	elif layout.has("water"):
		for water: Rect2 in layout.water:
			_draw_lake(canvas, art, water, str(layout.get("lake_name","")), desert)
	if layout.has("blocked"):
		_draw_dunes(canvas, layout)
	# New outer blocks contain local streets, orchards, parks and waterfront lots.
	for x: float in ROAD_X:
		for y: float in [126.0,348.0,610.0,798.0,1118.0,1374.0]:
			for side: int in [-1,1]:
				var foot := Vector2(x+side*54,y)
				if _in_water(layout, foot, 14.0): continue
				if Rect2(Vector2(18,18),MAP_SIZE-Vector2(36,100)).has_point(foot):
					if desert: _cactus(canvas, foot, int(x+y)%3)
					else: art.tree(foot,14.0+int(x+y)%6,(int(x+y)/32)%3)
					if int(x+y)%2==0:
						art._lamp(x+side*32,y+20)
	var sites: Array[Dictionary] = BeaconCampaign.locations()
	# House groups fill empty city blocks without changing the playable sites.
	for column: int in range(ROAD_X.size() - 1):
		for row: int in range(6):
			var point := Vector2(ROAD_X[column]+122,[120,330,585,815,1075,1330][row])
			var free := true
			for site: Dictionary in sites:
				if point.distance_to(site.pos*MAP_SIZE)<112: free=false
			if not free or Rect2(1146,820,480,160).has_point(point): continue
			if _in_water(layout, point, 40.0): continue
			canvas.draw_set_transform(point-Vector2(65,55),0,Vector2.ONE*1.5)
			art._building(0,0,32,30,(column+row)%3,"house")
			art._building(43,4,30,27,(column+row+1)%3,"house")
			art._fence(0,34,70)
			canvas.draw_set_transform(Vector2.ZERO)
	for i: int in range(sites.size()):
		if not BeaconCampaign.site_open(shift_theme, sites[i].pos): continue
		var foot: Vector2 = sites[i].pos*MAP_SIZE
		var lane_y: float = ROAD_Y[0]
		for y: float in ROAD_Y:
			if absf(y-foot.y)<absf(lane_y-foot.y): lane_y=y
		# Short driveways visually connect each incident site to the street network.
		canvas.draw_line(foot,Vector2(foot.x,lane_y),Color("c7c5a3"),10.0)
		art.site(foot,i,1.75,true)
	# Distinct scenery makes exploring the east and south recognisable.
	for row: int in range(3):
		for col: int in range(5):
			if desert: _cactus(canvas, Vector2(1944+col*32,70+row*27), (row+col)%3)
			else: art.tree(Vector2(1944+col*32,70+row*27),12.0,(row+col)%3)
	for x: int in range(324,1024,54):
		if not desert: art._flowerbed(x,1230,30,8)
		art._bench(x+3,1248)
	if not desert:
		for point: Vector2 in [Vector2(1202,885),Vector2(1544,887),Vector2(1914,1508),Vector2(714,1509),Vector2(250,1510),Vector2(2500,1506)]:
			if not _in_water(layout, point, 0.0) or layout.has("river"): art._boat(point,1,false)
	if theme_index == 1:
		canvas.draw_rect(OUTSKIRTS,Color(0.05,0.08,0.22,0.5 if str(layout.get("theme","")) == "night" else 0.20))
	elif theme_index == 3:
		canvas.draw_rect(OUTSKIRTS,Color(0.12,0.22,0.28,0.06))
	elif theme_index == 4:
		canvas.draw_rect(OUTSKIRTS,Color(1.0,0.78,0.45,0.07))
	_shade_outskirts(canvas)

# The whole-town view is wider than the town (16:9 screen, 3:2 town), so the
# countryside around it is painted too: no empty bars at the sides. It is
# slightly darker so the town's edge stays clear; nothing there is playable.
const OUTSKIRTS := Rect2(-420, -80, MAP_SIZE.x + 840, MAP_SIZE.y + 160)

func _paint_outskirts(canvas: Node2D, art, layout: Dictionary, desert: bool, ground: Color) -> void:
	canvas.draw_rect(OUTSKIRTS, ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	for side: float in [-1.0, 1.0]:
		var x0: float = OUTSKIRTS.position.x if side < 0 else MAP_SIZE.x
		var width: float = -OUTSKIRTS.position.x
		for i: int in range(220):
			var p := Vector2(x0 + rng.randf() * width, rng.randf_range(-60, 1460))
			canvas.draw_rect(Rect2(p, Vector2(4, 2)), Color("cdb27a") if desert else Color("91af7e"))
		for i: int in range(26):
			var foot := Vector2(x0 + 30 + rng.randf() * (width - 60), rng.randf_range(20, 1440))
			if layout.has("river") and Rect2(0, Rect2(layout.river).position.y - 30, 1, Rect2(layout.river).size.y + 60).has_point(Vector2(0, foot.y)): continue
			if desert: _cactus(canvas, foot, i % 3)
			else: art.tree(foot, 16.0 + i % 6, i % 3)
	# Coast (or dunes) and the river continue past the town's edges.
	if desert:
		canvas.draw_rect(Rect2(OUTSKIRTS.position.x, 1470, OUTSKIRTS.size.x, OUTSKIRTS.end.y - 1470), Color("e3c98f"))
	else:
		canvas.draw_rect(Rect2(OUTSKIRTS.position.x, 1473, OUTSKIRTS.size.x, OUTSKIRTS.end.y - 1473), Color("4f8f98"))
		canvas.draw_rect(Rect2(OUTSKIRTS.position.x, 1484, OUTSKIRTS.size.x, OUTSKIRTS.end.y - 1484), Color("367f8e"))
	if layout.has("river"):
		var river: Rect2 = layout.river
		canvas.draw_rect(Rect2(OUTSKIRTS.position.x, river.position.y - 10, OUTSKIRTS.size.x, river.size.y + 20), Color("d9ccaa"))
		canvas.draw_rect(Rect2(OUTSKIRTS.position.x, river.position.y, OUTSKIRTS.size.x, river.size.y), Color("468997"))

func _shade_outskirts(canvas: Node2D) -> void:
	var shade := Color(0.03, 0.10, 0.12, 0.38)
	canvas.draw_rect(Rect2(OUTSKIRTS.position, Vector2(-OUTSKIRTS.position.x, OUTSKIRTS.size.y)), shade)
	canvas.draw_rect(Rect2(MAP_SIZE.x, OUTSKIRTS.position.y, OUTSKIRTS.end.x - MAP_SIZE.x, OUTSKIRTS.size.y), shade)
	canvas.draw_rect(Rect2(0, OUTSKIRTS.position.y, MAP_SIZE.x, -OUTSKIRTS.position.y), shade)
	canvas.draw_rect(Rect2(0, MAP_SIZE.y, MAP_SIZE.x, OUTSKIRTS.end.y - MAP_SIZE.y), shade)
	canvas.draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.95, 0.9, 0.75, 0.35), false, 3.0)

func _in_water(layout: Dictionary, point: Vector2, margin: float) -> bool:
	for water: Rect2 in layout.get("water", []):
		if water.grow(margin).has_point(point): return true
	return false

# A lake (Lights Out) or an oasis (Dune Springs), drawn in code like the rest of the town.
func _draw_lake(canvas: Node2D, art, water: Rect2, name: String, desert: bool) -> void:
	var center: Vector2 = water.get_center()
	var radii: Vector2 = water.size * 0.5
	var shore := PackedVector2Array()
	var deep := PackedVector2Array()
	var pool := PackedVector2Array()
	for i: int in range(48):
		var angle: float = TAU * i / 48.0
		var wobble: float = 1.0 + 0.05 * sin(angle * 5.0) + 0.03 * cos(angle * 3.0)
		var dir := Vector2(cos(angle), sin(angle))
		shore.append(center + dir * radii * wobble + dir * 16.0)
		pool.append(center + dir * radii * wobble)
		deep.append(center + dir * radii * wobble * 0.62)
	canvas.draw_colored_polygon(shore, Color("e2cf9c") if desert else Color("c9c39b"))
	canvas.draw_colored_polygon(pool, Color("4f9aa3") if desert else Color("3f7f8d"))
	canvas.draw_colored_polygon(deep, Color("3d8792") if desert else Color("2f6c7c"))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(water.position.x) * 7 + 3
	for i: int in range(70):
		var angle: float = rng.randf() * TAU
		var p: Vector2 = center + Vector2(cos(angle), sin(angle)) * radii * rng.randf_range(0.1, 0.85)
		canvas.draw_rect(Rect2(p, Vector2(rng.randi_range(8, 18), 2)), Color("74a8a7"))
	if desert:
		# Palms around the oasis.
		for i: int in range(14):
			var angle: float = TAU * i / 14.0 + 0.2
			_palm(canvas, center + Vector2(cos(angle), sin(angle)) * (radii + Vector2(34, 30)))
	else:
		# Reeds, a jetty and the moon's reflection.
		for i: int in range(26):
			var angle: float = TAU * i / 26.0
			var p: Vector2 = center + Vector2(cos(angle), sin(angle)) * (radii * 0.98)
			for blade: int in range(3):
				canvas.draw_line(p + Vector2(blade * 3 - 3, 0), p + Vector2(blade * 3 - 4, -10 - blade * 2), Color("5f8a5c"), 2.0)
		canvas.draw_rect(Rect2(center + Vector2(radii.x * 0.55, -6), Vector2(radii.x * 0.5, 12)), Color("8a6d4f"))
		art._boat(center + Vector2(-radii.x * 0.35, radii.y * 0.25), 2, false)
		art._boat(center + Vector2(radii.x * 0.15, -radii.y * 0.45), 0, false)
		canvas.draw_circle(center + Vector2(-radii.x * 0.2, -radii.y * 0.15), 26, Color(1.0, 0.97, 0.82, 0.25))
		canvas.draw_circle(center + Vector2(-radii.x * 0.2, -radii.y * 0.15), 15, Color(1.0, 0.97, 0.85, 0.35))
	if not name.is_empty():
		var font: Font = ThemeDB.fallback_font
		var width: float = font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		canvas.draw_string_outline(font, center + Vector2(-width * 0.5, radii.y * 0.62), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0.1, 0.2, 0.25, 0.6))
		canvas.draw_string(font, center + Vector2(-width * 0.5, radii.y * 0.62), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.95, 0.88, 0.85))

func _palm(canvas: Node2D, foot: Vector2) -> void:
	canvas.draw_line(foot, foot + Vector2(4, -30), Color("8a6a43"), 5.0)
	var top: Vector2 = foot + Vector2(4, -32)
	for angle: float in [-2.6, -2.0, -1.2, -0.5, 0.1]:
		canvas.draw_line(top, top + Vector2(cos(angle), sin(angle) * 0.6) * 20.0, Color("4f8a4a"), 5.0)
		canvas.draw_line(top, top + Vector2(cos(angle), sin(angle) * 0.6) * 15.0, Color("6fab5d"), 2.0)

func _cactus(canvas: Node2D, foot: Vector2, variant: int) -> void:
	var h: float = 22.0 + variant * 5.0
	canvas.draw_rect(Rect2(foot + Vector2(-3, 0), Vector2(10, 3)), Color(0.4, 0.3, 0.2, 0.25))
	canvas.draw_rect(Rect2(foot + Vector2(-4, -h), Vector2(8, h)), Color("5f9a5a"))
	canvas.draw_rect(Rect2(foot + Vector2(-2, -h), Vector2(2, h)), Color("7fbb6d"))
	canvas.draw_rect(Rect2(foot + Vector2(-12, -h * 0.65), Vector2(8, 5)), Color("5f9a5a"))
	canvas.draw_rect(Rect2(foot + Vector2(-12, -h * 0.85), Vector2(5, 12)), Color("5f9a5a"))
	if variant != 1:
		canvas.draw_rect(Rect2(foot + Vector2(4, -h * 0.5), Vector2(8, 5)), Color("5f9a5a"))
		canvas.draw_rect(Rect2(foot + Vector2(7, -h * 0.72), Vector2(5, 13)), Color("5f9a5a"))

# Desert edge of the map: rolling dunes instead of the sea.
func _draw_dune_band(canvas: Node2D) -> void:
	canvas.draw_rect(Rect2(0, 1470, MAP_SIZE.x, MAP_SIZE.y - 1470), Color("e3c98f"))
	for i: int in range(0, int(MAP_SIZE.x) + 200, 180):
		var base := Vector2(i - 60, 1536)
		var hump := PackedVector2Array([base, base + Vector2(90, -58 - (i / 180) % 3 * 10), base + Vector2(240, 0)])
		canvas.draw_colored_polygon(hump, Color("d4b273"))
		canvas.draw_line(base + Vector2(90, -58 - (i / 180) % 3 * 10), base + Vector2(240, 0), Color("bf9a5c"), 3.0)

# Sand dunes that have buried a stretch of road for good (Dune Springs).
func _draw_dunes(canvas: Node2D, layout: Dictionary) -> void:
	for piece: Array in layout.blocked:
		var horizontal: bool = bool(piece[0])
		var a := Vector2(ROAD_X[int(piece[1])], ROAD_Y[int(piece[2])])
		var b: Vector2 = Vector2(ROAD_X[int(piece[1]) + 1], a.y) if horizontal else Vector2(a.x, ROAD_Y[int(piece[2]) + 1])
		var from: Vector2 = a.lerp(b, 0.16)
		var to: Vector2 = a.lerp(b, 0.84)
		var across: Vector2 = Vector2(0, 1) if horizontal else Vector2(1, 0)
		var along: Vector2 = (to - from)
		var dune := PackedVector2Array()
		for i: int in range(17):
			var t: float = i / 16.0
			dune.append(from + along * t - across * (40.0 * sin(t * PI) + 8.0))
		for i: int in range(16, -1, -1):
			var t: float = i / 16.0
			dune.append(from + along * t + across * (34.0 * sin(t * PI) + 8.0))
		canvas.draw_colored_polygon(dune, Color("d9b878"))
		var ridge := PackedVector2Array()
		for i: int in range(17):
			var t: float = i / 16.0
			ridge.append(from + along * t - across * (10.0 * sin(t * PI * 2.0)))
		canvas.draw_polyline(ridge, Color("bc9758"), 3.0)
		for i: int in range(5):
			var p: Vector2 = from + along * (0.2 + i * 0.15) + across * (14.0 if i % 2 else -18.0)
			canvas.draw_line(p, p + along.normalized() * 22.0, Color("ecd7a5"), 2.0)

func _draw_basin(canvas: Node2D,area: Rect2) -> void:
	canvas.draw_rect(area.grow(7),Color("d9ccaa"))
	canvas.draw_rect(area.grow(3),Color("76978c"))
	canvas.draw_rect(area,Color("468997"))
	for y: int in range(int(area.position.y+8),int(area.end.y),18):
		for x: int in range(int(area.position.x+8),int(area.end.x-8),40):
			canvas.draw_rect(Rect2(x,y,14,2),Color("74a8a7"))

func _draw_roads(canvas: Node2D, layout: Dictionary = {}) -> void:
	# Soft, narrow streets preserve the original village scale. Road endpoints
	# exactly match the simulation's graph, including the outer districts.
	var desert: bool = str(layout.get("theme","")) == "desert"
	for layer: int in range(3):
		var width: float = [54.0,48.0,36.0][layer]
		var color: Color = [Color("7b967b"),Color("d0cbaa"),Color("7b9190")][layer]
		if desert: color = [Color("b39661"),Color("e6d3a3"),Color("a08c6c")][layer]
		for x: float in ROAD_X:
			canvas.draw_line(Vector2(x,0),Vector2(x,1475),color,width,false)
		for y: float in ROAD_Y:
			canvas.draw_line(Vector2(0,y),Vector2(MAP_SIZE.x,y),color,width,false)
	for x: float in ROAD_X:
		for y: int in range(12,1470,28):
			var junction := false
			for cross_y: float in ROAD_Y:
				if absf(y-cross_y)<30: junction=true
			if not junction: canvas.draw_rect(Rect2(x-1,y,2,9),Color("d8d9b5"))
	for y: float in ROAD_Y:
		for x: int in range(12,int(MAP_SIZE.x),28):
			var junction := false
			for cross_x: float in ROAD_X:
				if absf(x-cross_x)<30: junction=true
			if not junction: canvas.draw_rect(Rect2(x,y-1,9,2),Color("d8d9b5"))
	for x: float in ROAD_X:
		for y: float in ROAD_Y:
			for stripe: int in range(4):
				canvas.draw_rect(Rect2(x-13+stripe*7,y-29,3,7),Color("e7dfbf"))
				canvas.draw_rect(Rect2(x-13+stripe*7,y+22,3,7),Color("e7dfbf"))
	# Harbor bridge railings.
	if not str(layout.get("theme","")) in ["", "river"]: return
	for y: int in [907,949]:
		canvas.draw_rect(Rect2(1172,y,428,3),Color("d7cfac"))
		for x: int in range(1174,1600,14): canvas.draw_rect(Rect2(x,y-1,3,5),Color("8a9680"))

func _draw() -> void:
	_draw_water()
	if sim != null and not title_mode:
		_draw_level_hazards()
		_draw_road_scenes()
	if sim != null:
		_draw_routes()
		for incident: Dictionary in sim.incidents:
			_draw_hazard(incident)
		for unit: Dictionary in sim.units:
			_draw_unit(unit)
	_draw_weather()
	_draw_celebrations()

# Level 3 river with banks, three bridges and a few boats (drawn in code, like the rest of the town).
func _draw_river(canvas: Node2D, art, layout: Dictionary) -> void:
	var river: Rect2 = layout.river
	canvas.draw_rect(river.grow_individual(0, 10, 0, 10), Color("d9ccaa"))
	canvas.draw_rect(river.grow_individual(0, 4, 0, 4), Color("76978c"))
	canvas.draw_rect(river, Color("468997"))
	canvas.draw_rect(Rect2(river.position + Vector2(0, river.size.y * 0.35), Vector2(river.size.x, river.size.y * 0.3)), Color("3f7f8d"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for i: int in range(120):
		var p := Vector2(rng.randf_range(0, river.size.x), rng.randf_range(river.position.y + 8, river.end.y - 8))
		canvas.draw_rect(Rect2(p, Vector2(rng.randi_range(10, 22), 2)), Color("74a8a7"))
	for x: float in [300.0, 900.0, 1500.0, 2050.0]:
		art._boat(Vector2(x, river.get_center().y + (12.0 if int(x) % 2 == 0 else -14.0)), 1, false)
	for column: int in layout.bridges:
		var x: float = ROAD_X[column]
		var deck := Rect2(x - 30, river.position.y - 12, 60, river.size.y + 24)
		canvas.draw_rect(deck.grow(4), Color("5d6f69"))
		canvas.draw_rect(deck, Color("7b9190"))
		canvas.draw_rect(Rect2(x - 22, deck.position.y, 44, deck.size.y), Color("8a9b98"))
		for y: int in range(int(deck.position.y) + 6, int(deck.end.y) - 4, 26):
			canvas.draw_rect(Rect2(x - 1, y, 2, 10), Color("d8d9b5"))
		for side: float in [-1.0, 1.0]:
			canvas.draw_rect(Rect2(x + side * 30 - 2, deck.position.y, 4, deck.size.y), Color("d7cfac"))
			for y: int in range(int(deck.position.y), int(deck.end.y), 14):
				canvas.draw_rect(Rect2(x + side * 30 - 3, y, 6, 4), Color("8a9680"))

func _draw_water() -> void:
	for i: int in range(40):
		var x: float = fposmod(i*71.0+elapsed*3.0,MAP_SIZE.x)
		var y: float = 1500+sin(i*3.2)*15
		draw_rect(Rect2(Vector2(x,y).floor(),Vector2(10,2)),Color("87b4b080"))
func _draw_routes() -> void:
	if selected_id < 0:
		return
	for unit: Dictionary in sim.units:
		if int(unit.get("target",-2)) != selected_id or unit.get("state","idle") != "travel":
			continue
		var start: Vector2 = _unit_position(unit)
		var path: Array = unit.get("path",[])
		for waypoint: int in range(int(unit.get("path_index",0)),path.size()):
			var finish: Vector2 = path[waypoint] * MAP_SIZE
			draw_line(start,finish,Color("f4d18188"),2.0,true)
			var distance: float = start.distance_to(finish)
			for i: int in range(int(distance / 16.0)):
				var p: Vector2 = start.lerp(finish,minf(1.0,(i * 16.0 + fposmod(elapsed * 22.0,16.0)) / maxf(1.0,distance)))
				draw_circle(p,2.5,CREAM,true,-1,true)
			start = finish

func _draw_vehicle(point: Vector2, kind: String, heading: Vector2, active: bool, _ident: int) -> void:
	if _pixel != null:
		_pixel.vehicle(point,kind,heading,active,elapsed,2.0)

func _draw_unit(unit: Dictionary) -> void:
	var point: Vector2 = _unit_position(unit)
	var kind: String = str(unit.get("kind","fire"))
	var state: String = str(unit.get("state","idle"))
	var heading: Vector2 = unit.get("heading",Vector2.RIGHT) if state in ["travel","return"] else Vector2.RIGHT
	if state == "working":
		var department: int = maxi(0,["fire","medic","engineer","police"].find(kind))
		var offset := Vector2(-48.0 + department * 31.0,29.0 + int(unit.id) % 3 * 9.0)
		_draw_vehicle((point+offset).clamp(Vector2(30,30),MAP_SIZE-Vector2(30,30)),kind,Vector2.RIGHT,true,int(unit.id))
		Responders.draw_person(self,point+Vector2(-32+department*23,8),kind,int(unit.get("appearance",0)),str(unit.get("work_phase","act")),elapsed,1,1.8)
	elif state == "clearing":
		# A crew clearing a road event: vehicle on the road, one responder at work beside it.
		_draw_vehicle(point,kind,Vector2.RIGHT,true,int(unit.id))
		Responders.draw_person(self,point+Vector2(22,10),kind,int(unit.get("appearance",0)),"act",elapsed,1,1.8)
	else:
		if state == "travel" and not reduced_motion:
			# Dust trail behind a crew on its way.
			for i in range(4):
				var back: Vector2 = point - heading * (16.0 + i * 9.0) + Vector2(0, 6)
				var puff: float = fposmod(elapsed * 3.0 + i * 0.25 + int(unit.id) * 0.13, 1.0)
				draw_circle(back + Vector2(0, -puff * 4.0), 3.0 + i * 1.2 + puff * 2.0, Color(0.93, 0.88, 0.74, 0.30 * (1.0 - i * 0.22)))
		_draw_vehicle(point,kind,heading,state == "travel",int(unit.id))
		if state == "travel" and not reduced_motion:
			# Flashing siren: red / blue.
			var blink: bool = fposmod(elapsed * 6.0 + int(unit.id) * 0.37, 1.0) < 0.5
			draw_circle(point + Vector2(0, -15), 7.0, Color(1.0, 0.25, 0.2, 0.35) if blink else Color(0.3, 0.45, 1.0, 0.35))
			draw_circle(point + Vector2(0, -15), 3.2, Color(1.0, 0.35, 0.3) if blink else Color(0.45, 0.6, 1.0))

func _draw_hazard(incident: Dictionary) -> void:
	if incident.get("status","active") not in ["active","working"] or not bool(incident.get("discovered",true)):
		return
	var point: Vector2 = incident.pos * MAP_SIZE
	var progress: float = float(incident.get("progress",0.0))
	var kind: String = str(incident.get("kind","fire"))
	if kind == "fire":
		Responders.draw_flames(self,point+Vector2(0,-26),float(incident.get("hazard",0.3)),progress,elapsed,2.2)
	elif kind == "flood":
		draw_set_transform(point,0,Vector2(1.0,0.3))
		draw_circle(Vector2.ZERO,48.0*(1.0-progress*0.4),Color("48a5b2a8"),true,-1,true)
		draw_arc(Vector2.ZERO,36,0.2,PI,18,Color("cef1da"),2.0,true)
		draw_set_transform(Vector2.ZERO)
	elif kind == "power":
		if reduced_motion or int(elapsed * 4.0 + int(incident.id)) % 4 < 2:
			var bolt := PackedVector2Array([point+Vector2(2,-42),point+Vector2(-8,-25),point+Vector2(0,-25),point+Vector2(-3,-13),point+Vector2(11,-30),point+Vector2(3,-30)])
			draw_colored_polygon(bolt,Color("f9d969"))
	elif kind == "police":
		for i: int in range(4):
			var cone: Vector2 = point+Vector2(-24+i*16,12)
			draw_colored_polygon(PackedVector2Array([cone+Vector2(-4,0),cone+Vector2(0,-10),cone+Vector2(4,0)]),Color("e97d4f"))
			draw_line(cone+Vector2(-2,-4),cone+Vector2(2,-4),CREAM,2)
	if not tactical_mode:
		var color: Color = Responders.uniform({"medical":"medic","flood":"engineer","power":"engineer"}.get(kind,kind))
		draw_circle(point+Vector2(0,-40),13,INK,true,-1,true)
		draw_circle(point+Vector2(0,-40),10,color,true,-1,true)

# Blackouts darken a district, storms sweep sand or rain over a third of the
# town, and both are previewed a few seconds before they arrive.
func _draw_level_hazards() -> void:
	if not sim.has_method("upcoming_hazards"): return
	for item: Dictionary in sim.upcoming_hazards():
		var area := Rect2(Vector2(item.position) * MAP_SIZE, Vector2(item.size) * MAP_SIZE)
		var near: float = 1.0 - clampf(float(item["in"]) / BeaconCampaign.HAZARD_WARNING_SECONDS, 0.0, 1.0)
		match str(item.type):
			"blackout":
				# The lights start to flicker.
				var flicker: float = 0.0 if reduced_motion else float(int(elapsed * 9.0 + area.position.x) % 5 == 0)
				draw_rect(area, Color(0.03, 0.05, 0.14, 0.10 + 0.25 * near * flicker))
			"sandstorm", "squall":
				# A wall of sand / rain closes in on the district.
				var color: Color = Color(0.86, 0.68, 0.40) if item.type == "sandstorm" else Color(0.45, 0.55, 0.65)
				# Eastward storms come in over the west edge of the district.
				var from_left: bool = bool(item.get("eastward", true))
				var depth: float = 40.0 + 160.0 * near
				var wall := Rect2(area.position.x, 0, depth, MAP_SIZE.y)
				if not from_left: wall.position.x = area.end.x - depth
				for i: int in range(8):
					var strip := Rect2(wall.position.x + (wall.size.x * i / 8.0 if from_left else wall.size.x * (7 - i) / 8.0), 0, wall.size.x / 8.0, MAP_SIZE.y)
					draw_rect(strip, Color(color, 0.05 + 0.05 * near * (8 - i) / 8.0 * 4.0))
			"flood":
				var pulse: float = 0.5 if reduced_motion else (sin(elapsed * 5.0) + 1.0) * 0.5
				draw_rect(area, Color(0.3, 0.6, 0.95, 0.15 + 0.3 * near * pulse))
	for event: Dictionary in sim.active_road_events():
		if not bool(event.get("hazard", false)): continue
		var area := Rect2(Vector2(event.position) * MAP_SIZE, Vector2(event.size) * MAP_SIZE)
		var fade: float = clampf((float(event.expires_at) - sim.elapsed) / 3.0, 0.0, 1.0) * clampf((sim.elapsed - float(event.started_at)) / 2.0, 0.0, 1.0)
		match str(event.type):
			"blackout":
				draw_rect(area, Color(0.01, 0.02, 0.07, 0.62 * fade))
				# Only a few torches and car lights in the dark.
				var rng := RandomNumberGenerator.new()
				rng.seed = int(event.id) * 31
				for i: int in range(24):
					var p := area.position + Vector2(rng.randf() * area.size.x, rng.randf() * area.size.y)
					var on: bool = reduced_motion or fposmod(elapsed * 0.7 + i * 0.37, 1.0) < 0.6
					if on: draw_circle(p, 3.0, Color(1.0, 0.85, 0.5, 0.45 * fade))
				var station: Vector2 = Vector2(event.get("target", area.get_center() / MAP_SIZE)) * MAP_SIZE
				draw_circle(station, 46.0, Color(1.0, 0.85, 0.35, 0.10 * fade))
			"sandstorm", "squall":
				var sand: bool = event.type == "sandstorm"
				draw_rect(area, Color(0.86, 0.66, 0.38, 0.46 * fade) if sand else Color(0.26, 0.36, 0.48, 0.40 * fade))
				# Darker leading and trailing edges make the storm's front easy to spot.
				for edge_x: float in [area.position.x, area.end.x - 36.0]:
					draw_rect(Rect2(edge_x, 0, 36.0, MAP_SIZE.y), Color(0.70, 0.50, 0.26, 0.30 * fade) if sand else Color(0.18, 0.26, 0.38, 0.30 * fade))
				if reduced_motion: continue
				var drift: float = elapsed * (260.0 if sand else 120.0) * (1.0 if bool(event.get("eastward", true)) else -1.0)
				for i: int in range(170):
					var x: float = area.position.x + fposmod(i * 97.0 + drift, area.size.x)
					var y: float = fposmod(i * 61.0 + (elapsed * 340.0 if not sand else i * 13.0), MAP_SIZE.y)
					if sand:
						draw_line(Vector2(x, y), Vector2(x + 34.0, y + 4.0), Color(0.98, 0.88, 0.66, 0.60 * fade), 3.0)
					else:
						draw_line(Vector2(x, y), Vector2(x - 7.0, y + 22.0), Color(0.82, 0.92, 0.98, 0.55 * fade), 2.0)
				if sand:
					for i: int in range(14):
						var c := Vector2(area.position.x + fposmod(i * 173.0 + drift * 0.5, area.size.x), fposmod(i * 211.0, MAP_SIZE.y))
						draw_circle(c, 46.0 + (i % 3) * 16.0, Color(0.93, 0.76, 0.50, 0.20 * fade))

# What blocks the road, drawn on the street itself: a burning car (Fire puts
# it out) or a pile-up with injured people (Medical takes them away).
func _draw_road_scenes() -> void:
	for event: Dictionary in sim.active_road_events():
		var type: String = str(event.type)
		if type not in ["road_fire", "accident"]: continue
		var area := Rect2(Vector2(event.position) * MAP_SIZE, Vector2(event.size) * MAP_SIZE)
		var center: Vector2 = area.get_center()
		var left: float = 1.0 - clampf(float(event.get("clear_progress", 0.0)), 0.0, 1.0)
		if type == "road_fire":
			_draw_vehicle(center + Vector2(-120, 4), "wreck", Vector2(1, 0.15).normalized(), false, 0)
			for offset: Vector2 in [Vector2(-120, -6), Vector2(-170, 2), Vector2(-75, -2), Vector2(80, 2), Vector2(130, -4), Vector2(175, 3)]:
				Responders.draw_flames(self, center + offset, 0.75 * left, 1.0 - left, elapsed + offset.x * 0.01, 1.8)
			if not reduced_motion:
				for i: int in range(6):
					var rise: float = fposmod(elapsed * 0.6 + i / 6.0, 1.0)
					draw_circle(center + Vector2(-120 + sin(i * 2.1) * 10.0, -24 - rise * 70.0), 8.0 + rise * 14.0, Color(0.25, 0.25, 0.27, 0.35 * (1.0 - rise) * left))
		else:
			_draw_vehicle(center + Vector2(-130, -4), "wreck", Vector2(1, 0.45).normalized(), false, 0)
			_draw_vehicle(center + Vector2(-86, 6), "wreck", Vector2(-1, 0.6).normalized(), false, 1)
			# Warning triangle and the injured waiting for the medics.
			var t: Vector2 = center + Vector2(-185, 8)
			draw_colored_polygon(PackedVector2Array([t + Vector2(-9, 8), t + Vector2(0, -9), t + Vector2(9, 8)]), Color("e8573f"))
			draw_colored_polygon(PackedVector2Array([t + Vector2(-5, 5), t + Vector2(0, -4), t + Vector2(5, 5)]), Color("f4e9d2"))
			var people: int = ceili(3.0 * left)
			for i: int in range(people):
				var p: Vector2 = center + Vector2(80 + i * 22, -10 + (i % 2) * 16)
				draw_circle(p + Vector2(0, -8), 4.0, Color("e9c39b"))
				draw_rect(Rect2(p + Vector2(-4, -4), Vector2(8, 10)), Color("6b84a0") if i % 2 else Color("b56a4f"))
			if not reduced_motion and fposmod(elapsed * 2.0, 1.0) < 0.5:
				draw_circle(center + Vector2(-130, -20), 4.0, Color(1.0, 0.75, 0.2, 0.9))

func _draw_weather() -> void:
	if theme_index == 3 and not reduced_motion:
		for i: int in range(85):
			var point := Vector2(fposmod(i*173+elapsed*56,MAP_SIZE.x),fposmod(i*89+elapsed*175,MAP_SIZE.y))
			draw_line(point,point+Vector2(-4,12),Color(0.77,0.88,0.92,0.3),1.0,true)
	if theme_index == 1:
		var dark: Array[Rect2] = []
		if sim != null:
			for event: Dictionary in sim.active_road_events():
				if str(event.type) == "blackout": dark.append(Rect2(event.position, event.size))
		for place: Dictionary in BeaconCampaign.locations():
			if not BeaconCampaign.site_open(shift_theme, place.pos): continue
			var lit: bool = true
			for area: Rect2 in dark:
				if area.has_point(place.pos): lit = false
			if not lit: continue
			var point: Vector2 = place.pos * MAP_SIZE + Vector2(15,-28)
			draw_circle(point,4,Color("efc573aa"),true,-1,true)

func _draw_celebrations() -> void:
	for effect: Dictionary in _celebrations:
		var age: float = float(effect.time)
		var fade: float = clampf((1.8-age)/0.5,0,1)
		var point: Vector2 = effect.pos + Vector2(0,-42-age*16)
		var label: String = "%d SAFE" % int(effect.people)
		var width: float = ThemeDB.fallback_font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		draw_rect(Rect2(point+Vector2(-width*0.5-7,-18),Vector2(width+14,25)),Color(0.12,0.20,0.23,0.94*fade))
		draw_string(ThemeDB.fallback_font,point-Vector2(width*0.5,0),label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(0.82,0.98,0.81,fade))

