class_name PixelTownArt
extends RefCounted

# Original Beacon Bay pixel shapes, shared by the enlarged town and field view.
const INK := Color("30464d")
const CREAM := Color("eee0ba")
const GRASS := Color("9dbb84")
const SHADOW := Color("30474b38")
var _painter: CanvasItem
var _rng := RandomNumberGenerator.new()
var theme_index := 0
var elapsed := 0.0

func _init(canvas: CanvasItem) -> void:
	_painter = canvas
	_rng.seed = 29401

static func kind_for_site(index: int) -> String:
	var places: Array[Dictionary] = BeaconCampaign.locations()
	var name: String = str(places[clampi(index,0,places.size()-1)].name).to_lower()
	if "lighthouse" in name: return "lighthouse"
	if "garden" in name or "park" in name or "stadium" in name: return "park"
	if "market" in name: return "market"
	if "clinic" in name: return "clinic"
	if "school" in name or "academy" in name: return "school"
	if "library" in name or "museum" in name or "hall" in name: return "library"
	if "bakery" in name: return "bakery"
	if "cafe" in name: return "cafe"
	if "store" in name: return "shop"
	if "rescue" in name or "lifeboat" in name: return "fire"
	if "coastguard" in name: return "police"
	if "work" in name or "substation" in name or "pump" in name: return "power"
	if "apartment" in name or "hotel" in name: return "apartment"
	if "warehouse" in name or "terminal" in name or "depot" in name or "quay" in name or "pier" in name or "marina" in name: return "warehouse"
	return "house"

func site(foot: Vector2, index: int, scale: float = 2.0, fit_lot: bool = false) -> void:
	var kind: String = kind_for_site(index)
	var size: Vector2 = {"house":Vector2(38,32),"clinic":Vector2(67,43),"school":Vector2(59,39),
		"fire":Vector2(70,40),"power":Vector2(75,40),"apartment":Vector2(39,48),
		"warehouse":Vector2(60,34),"library":Vector2(46,36),"park":Vector2(58,36),
		"market":Vector2(58,32)}.get(kind,Vector2(39,35))
	if fit_lot:
		var previous_road := -32.0
		for road_y: float in [192.0,448.0,704.0,928.0,1184.0,1440.0]:
			if road_y < foot.y: previous_road = road_y
		if previous_road > 0 and foot.y-previous_road < 100: foot.y += 20
		scale = minf(scale,(foot.y-maxf(8,previous_road+32))/(size.y+5))
		if index == 20: scale=minf(scale,1.12)
	_painter.draw_set_transform((foot-Vector2(size.x*.5,size.y)*scale).round(),0,Vector2.ONE*scale)
	if kind == "lighthouse":
		_lighthouse(19,20)
	elif kind == "park":
		_r(0,0,58,39,Color("87aa7a"))
		_r(4,19,50,6,Color("d4c9a3"))
		_poly([Vector2(20,5),Vector2(37,5),Vector2(44,11),Vector2(40,17),Vector2(22,17),Vector2(17,12)],Color("518a91"))
		_r(23,8,14,2,Color("8ebeb2"))
		_tree(7,18,9,index%3)
		_tree(49,15,11,(index+1)%3)
		_bench(8,30)
		_flowerbed(31,30,20,5)
		_fence(0,37,58)
	elif kind == "market":
		_r(-3,5,65,29,Color("cfbf99"))
		for i: int in range(3):
			_r(i*20,10,17,18,INK)
			_r(i*20+1,12,15,15,Color("b79b73"))
			_r(i*20-1,5,19,7,Color("e6d8ac"))
			for stripe: int in range(3): _r(i*20+stripe*6,5,3,8,Color("b97660") if i%2==0 else Color("6a9c91"))
			_r(i*20+2,20,13,3,Color("81a76e"))
			_r(i*20+4,19,3,3,Color("e6bf75"))
		_flowerbed(5,30,45,3)
	elif kind == "warehouse":
		_r(3,5,size.x,size.y,SHADOW)
		_r(0,9,size.x,25,INK)
		_r(2,10,size.x-4,22,Color("bbbdac"))
		_poly([Vector2(-2,10),Vector2(8,0),Vector2(size.x-8,0),Vector2(size.x+2,10)],Color("607c85"))
		for x: int in range(6,55,8): _r(x,3,1,6,Color("91a7a5"))
		_r(21,14,19,20,INK)
		_r(23,15,15,18,Color("7c8d8a"))
		for y: int in range(18,32,4): _r(23,y,15,1,Color("b1b9a7"))
		for x: int in [4,44]:
			_r(x,27,9,8,Color("9c835f"))
			_r(x+1,28,7,1,CREAM)
			_r(x+3,29,1,6,Color("6d735d"))
	else:
		_building(0,0,int(size.x),int(size.y),index%3,"house" if kind=="apartment" else kind)
		_flowerbed(3,size.y+2,10,2)
		_fence(size.x-15,size.y+2,14)
	_painter.draw_set_transform(Vector2.ZERO)

func tree(foot: Vector2, size: float, variant: int) -> void:
	_tree(foot.x,foot.y,size,variant%3)

func vehicle(point: Vector2, kind: String, heading: Vector2, active: bool, time: float, scale: float = 2.0) -> void:
	elapsed = time
	_painter.draw_set_transform(point.round(),0,Vector2.ONE*scale)
	var color: Color = {"fire":Color("cc8066"),"medic":Color("e9e2c7"),"engineer":Color("d9b875"),"police":Color("6b84a0")}.get(kind,CREAM)
	var vertical := absf(heading.y)>absf(heading.x)
	_car(Vector2.ZERO,color,vertical,active,1 if kind=="medic" else 0)
	if kind == "fire" and not vertical:
		_r(-5,-3,9,1,CREAM)
		for x: int in range(-4,5,3): _r(x,-3,1,3,Color("e7d7ae"))
	_painter.draw_set_transform(Vector2.ZERO)

func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	_painter.draw_rect(Rect2(floorf(x), floorf(y), maxf(1, floorf(w)), maxf(1, floorf(h))), c)

func _poly(points: Array, color: Color) -> void:
	var packed := PackedVector2Array()
	for p in points:
		packed.append(Vector2(floorf(p.x), floorf(p.y)))
	_painter.draw_colored_polygon(packed, color)

func _line(a: Vector2, b: Vector2, color: Color, width: float = 1.0) -> void:
	_painter.draw_line(a.floor(), b.floor(), color, width, false)

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
			_cross(x + 31, y + 4, Color("548a77"), 7)
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
				_cross(x - 4, y - 1, Color("548a77"), 3)
