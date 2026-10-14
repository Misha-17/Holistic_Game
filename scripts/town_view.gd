class_name TownView
extends Node2D

signal incident_clicked(id: int)
signal map_clicked(pos: Vector2)

const Responders = preload("res://scripts/responder_art.gd")
const MAP_SIZE := BeaconCampaign.MAP_SIZE
const PixelArt = preload("res://scripts/pixel_town_art.gd")
const INK := Color("30474e")
const CREAM := Color("f1dfb4")
const ROAD_X := [128.0,384.0,640.0,896.0,1152.0,1408.0,1664.0,1920.0,2176.0]
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
	theme_index = [0,2,3,1,3,2][shift_theme]
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
	var grass := Color("9fbd87") if theme_index != 2 else Color("b7bc88")
	canvas.draw_rect(Rect2(Vector2.ZERO,MAP_SIZE),grass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 29401
	# Subtle patches and tiny grass clusters keep the original handmade pixel feel.
	for i: int in range(1500):
		var point := Vector2(rng.randi_range(0,int(MAP_SIZE.x)),rng.randi_range(0,1470))
		canvas.draw_rect(Rect2(point,Vector2(3,2)),Color("91af7e") if i%3 else Color("b3ca96"))
	for district: Dictionary in [
		{"area":Rect2(1438,214,452,454),"color":Color("a4bf8b")},
		{"area":Rect2(1950,214,194,454),"color":Color("9bb895")},
		{"area":Rect2(162,980,710,164),"color":Color("a8c493")},
		{"area":Rect2(930,1216,1220,190),"color":Color("b0bf96")}
	]:
		canvas.draw_rect(district.area,district.color)
	# Harbor basin in the original district, plus an extended southern waterfront.
	_draw_basin(canvas,Rect2(948,856,428,106))
	canvas.draw_rect(Rect2(0,1473,MAP_SIZE.x,MAP_SIZE.y-1473),Color("4f8f98"))
	canvas.draw_rect(Rect2(0,1484,MAP_SIZE.x,MAP_SIZE.y-1484),Color("367f8e"))
	for x: int in range(0,int(MAP_SIZE.x),24):
		canvas.draw_rect(Rect2(x,1470+(x/24)%3*2,24,8),Color("ded2ac"))
		canvas.draw_rect(Rect2(x,1478+(x/24)%3*2,24,3),Color("809889"))
	_draw_roads(canvas)
	# New outer blocks contain local streets, orchards, parks and waterfront lots.
	for x: float in ROAD_X:
		for y: float in [126.0,348.0,610.0,798.0,1118.0,1374.0]:
			for side: int in [-1,1]:
				var foot := Vector2(x+side*54,y)
				if Rect2(Vector2(18,18),MAP_SIZE-Vector2(36,100)).has_point(foot):
					art.tree(foot,14.0+int(x+y)%6,(int(x+y)/32)%3)
					if int(x+y)%2==0:
						art._lamp(x+side*32,y+20)
	var sites: Array[Dictionary] = BeaconCampaign.locations()
	# House groups fill empty city blocks without changing the playable sites.
	for column: int in range(8):
		for row: int in range(6):
			var point := Vector2(250+column*256,[120,330,585,815,1075,1330][row])
			var free := true
			for site: Dictionary in sites:
				if point.distance_to(site.pos*MAP_SIZE)<112: free=false
			if not free or Rect2(922,820,480,160).has_point(point): continue
			canvas.draw_set_transform(point-Vector2(65,55),0,Vector2.ONE*1.5)
			art._building(0,0,32,30,(column+row)%3,"house")
			art._building(43,4,30,27,(column+row+1)%3,"house")
			art._fence(0,34,70)
			canvas.draw_set_transform(Vector2.ZERO)
	for i: int in range(sites.size()):
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
			art.tree(Vector2(1720+col*32,70+row*27),12.0,(row+col)%3)
	for x: int in range(100,800,54):
		art._flowerbed(x,1230,30,8)
		art._bench(x+3,1248)
	for point: Vector2 in [Vector2(978,885),Vector2(1320,887),Vector2(1690,1508),Vector2(490,1509)]:
		art._boat(point,1,false)
	if theme_index == 1:
		canvas.draw_rect(Rect2(Vector2.ZERO,MAP_SIZE),Color(0.08,0.18,0.26,0.20))
	elif theme_index == 3:
		canvas.draw_rect(Rect2(Vector2.ZERO,MAP_SIZE),Color(0.12,0.22,0.28,0.06))

func _draw_basin(canvas: Node2D,area: Rect2) -> void:
	canvas.draw_rect(area.grow(7),Color("d9ccaa"))
	canvas.draw_rect(area.grow(3),Color("76978c"))
	canvas.draw_rect(area,Color("468997"))
	for y: int in range(int(area.position.y+8),int(area.end.y),18):
		for x: int in range(int(area.position.x+8),int(area.end.x-8),40):
			canvas.draw_rect(Rect2(x,y,14,2),Color("74a8a7"))

func _draw_roads(canvas: Node2D) -> void:
	# Soft, narrow streets preserve the original village scale. Road endpoints
	# exactly match the simulation's graph, including the outer districts.
	for layer: int in range(3):
		var width: float = [54.0,48.0,36.0][layer]
		var color: Color = [Color("7b967b"),Color("d0cbaa"),Color("7b9190")][layer]
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
	for y: int in [907,949]:
		canvas.draw_rect(Rect2(948,y,428,3),Color("d7cfac"))
		for x: int in range(950,1376,14): canvas.draw_rect(Rect2(x,y-1,3,5),Color("8a9680"))

func _draw() -> void:
	_draw_water()
	if sim != null:
		_draw_routes()
		for incident: Dictionary in sim.incidents:
			_draw_hazard(incident)
		for unit: Dictionary in sim.units:
			_draw_unit(unit)
	_draw_weather()
	_draw_celebrations()

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
		_draw_vehicle(point,kind,heading,state == "travel",int(unit.id))

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

func _draw_weather() -> void:
	if theme_index == 3 and not reduced_motion:
		for i: int in range(85):
			var point := Vector2(fposmod(i*173+elapsed*56,MAP_SIZE.x),fposmod(i*89+elapsed*175,MAP_SIZE.y))
			draw_line(point,point+Vector2(-4,12),Color(0.77,0.88,0.92,0.3),1.0,true)
	if theme_index == 1:
		for place: Dictionary in BeaconCampaign.locations():
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

