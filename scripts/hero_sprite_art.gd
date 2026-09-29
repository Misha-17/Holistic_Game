class_name HeroSpriteArt
extends RefCounted



const HEROES: Array[String] = ["nova", "bram", "elio", "tess"]
const ANIMATIONS: Array[String] = ["idle", "walk_down", "walk_side", "walk_up", "work", "celebrate"]
const CELL_SIZE := Vector2i(64, 64)
const FEET := Vector2(32, 57)
const INK := Color("253440")
const LIGHT := Color("f3dfb3")
const METAL := Color("92a6aa")

class PixelBrush extends RefCounted:
	var canvas: CanvasItem
	var origin: Vector2
	var scale: float
	func _init(target: CanvasItem, at: Vector2, pixel_scale: float) -> void:
		canvas = target
		origin = at
		scale = pixel_scale
	func r(x: float, y: float, w: float, h: float, color: Color) -> void:
		canvas.draw_rect(Rect2((origin + Vector2(roundf(x), roundf(y)) * scale).floor(), Vector2(maxf(1, roundf(w) * scale), maxf(1, roundf(h) * scale))), color)
	func poly(points: Array, color: Color) -> void:
		var packed := PackedVector2Array()
		for point in points:
			var p: Vector2 = point if point is Vector2 else Vector2(point[0], point[1])
			packed.append((origin + p.round() * scale).floor())
		canvas.draw_colored_polygon(packed, color)
	func line(a: Vector2, b: Vector2, color: Color, width: int = 1) -> void:
		
		var x: int = roundi(a.x)
		var y: int = roundi(a.y)
		var end_x: int = roundi(b.x)
		var end_y: int = roundi(b.y)
		var dx: int = absi(end_x - x)
		var dy: int = -absi(end_y - y)
		var sx: int = 1 if x < end_x else -1
		var sy: int = 1 if y < end_y else -1
		var err: int = dx + dy
		for i in range(128):
			r(x - width / 2, y - width / 2, width, width, color)
			if x == end_x and y == end_y:
				break
			var twice: int = err * 2
			if twice >= dy:
				err += dy
				x += sx
			if twice <= dx:
				err += dx
				y += sy

static func draw_hero(canvas: CanvasItem, hero_id: String, animation: String, frame: int, origin: Vector2 = Vector2.ZERO, pixel_scale: float = 1.0) -> void:
	var p := PixelBrush.new(canvas, origin + FEET * pixel_scale, pixel_scale)
	var f: int = posmod(frame, 6)
	var walking: bool = animation.begins_with("walk_")
	var pose: Dictionary = {
		"frame": f, "side": animation == "walk_side", "back": animation == "walk_up",
		"walking": walking, "work": animation == "work", "celebrate": animation == "celebrate",
		"dy": [-1, 0, 0, -1, 0, 0][f] if walking else [0, 0, -1, -1, 0, 0][f],
		"swing": [-2, -1, 1, 2, 1, -1][f] if walking else 0,
		"left_lift": [0, 1, 2, 0, 0, 0][f] if walking else 0,
		"right_lift": [0, 0, 0, 0, 1, 2][f] if walking else 0,
		"blink": animation == "idle" and f == 5
	}
	match hero_id.to_lower():
		"nova": _nova(p, pose)
		"bram": _bram(p, pose)
		"elio": _elio(p, pose)
		"tess": _tess(p, pose)

static func _legs(p: PixelBrush, q: Dictionary, trousers: Color, boot: Color, sturdy: bool = false, kneeled: bool = false) -> void:
	var width: int = 8 if sturdy else 6
	var left: int = -10 if sturdy else -8
	var right: int = 3 if sturdy else 2
	if q.side:
		left = -5 + int(q.swing) * 2
		right = 1 - int(q.swing) * 2
	if kneeled:
		p.poly([[-8, -12], [-1, -12], [0, -4], [-6, -3], [-8, -6]], INK)
		p.r(-7, -11, 5, 7, trousers)
		p.r(-7, -4, 6, 3, boot)
		p.poly([[1, -10], [7, -10], [9, -5], [14, -4], [14, -1], [4, -1], [1, -4]], INK)
		p.r(2, -9, 5, 6, trousers)
		p.r(5, -4, 7, 2, trousers.darkened(.15))
		p.r(10, -2, 6, 2, boot)
		p.r(-9, -1, 9, 1, INK)
		return
	for leg in range(2):
		var x: int = left if leg == 0 else right
		var lift: int = int(q.left_lift) if leg == 0 else int(q.right_lift)
		p.r(x - 1, -14, width + 2, 12 - lift, INK)
		p.r(x, -13, width, 10 - lift, trousers.darkened(.10) if leg == 0 else trousers)
		p.r(x + 1, -12, 2, 7 - lift, trousers.lightened(.12))
		p.r(x + width - 2, -8, 2, 4 - lift, trousers.darkened(.20))
		p.r(x - 1, -4 - lift, width + 3, 4, INK)
		p.r(x, -4 - lift, width + 1, 3, boot)
		p.r(x + 1, -4 - lift, width - 1, 1, boot.lightened(.2))
		p.r(x - 1, -1 - lift, width + 3, 1, INK)
		if sturdy:
			p.r(x, -7 - lift, width, 2, Color("c4b776"))
			p.r(x + 1, -7 - lift, width - 2, 1, Color("ecd799"))

static func _face(p: PixelBrush, x: int, y: int, w: int, h: int, skin: Color, side: bool, blink: bool, happy: bool = false) -> void:
	p.poly([[x + 2, y], [x + w - 3, y], [x + w - 1, y + 3], [x + w, y + h - 5], [x + w - 3, y + h], [x + 3, y + h], [x, y + h - 4], [x, y + 3]], INK)
	p.poly([[x + 2, y + 1], [x + w - 3, y + 1], [x + w - 2, y + 4], [x + w - 1, y + h - 5], [x + w - 3, y + h - 1], [x + 3, y + h - 1], [x + 1, y + h - 4], [x + 1, y + 3]], skin)
	p.r(x + 2, y + h - 4, 3, 2, skin.darkened(.12))
	p.r(x + 2, y + 4, 2, 3, skin.lightened(.12))
	if side:
		p.r(x + w - 1, y + 6, 2, 3, skin)
		_eye(p, x + w - 5, y + 4, blink)
		p.r(x + w - 7, y + 2, 4, 1, Color("654736"))
		p.r(x + w - 5, y + h - 4, 3, 1, Color("8d4f38"))
	else:
		_eye(p, x + 3, y + 4, blink)
		_eye(p, x + w - 6, y + 4, blink)
		p.r(x + 2, y + 2, 4, 1, Color("654736"))
		p.r(x + w - 6, y + 2, 4, 1, Color("654736"))
		p.r(x + w / 2, y + 8, 2, 1, skin.darkened(.16))
		p.r(x + w / 2 - 2, y + h - 4, 5, 1 if not happy else 2, Color("8d4f38"))
		if happy:
			p.r(x + w / 2 - 2, y + h - 4, 4, 1, LIGHT)

static func _eye(p: PixelBrush, x: int, y: int, blink: bool) -> void:
	if blink:
		p.r(x, y + 2, 3, 1, Color("302e31"))
	else:
		p.r(x, y, 3, 3, Color("f3e7cb"))
		p.r(x + 1, y, 2, 3, Color("312f32"))
		p.r(x + 1, y, 1, 1, Color("fbf1da"))

static func _radio(p: PixelBrush, x: int, y: int, active: bool) -> void:
	p.r(x + 4, y - 7, 2, 8, INK)
	p.r(x + 4, y - 7, 1, 3, Color("667172"))
	p.r(x, y, 8, 13, INK)
	p.r(x + 1, y + 1, 6, 11, Color("42515a"))
	p.r(x + 2, y + 2, 4, 3, Color("7b9b8b"))
	p.r(x + 2, y + 2, 2, 1, Color("d1d3a4"))
	for i in range(3):
		p.r(x + 2, y + 6 + i * 2, 4, 1, Color("293a46"))
	p.r(x + 6, y + 1, 1, 1, Color("e8b869") if active else Color("b56b51"))

static func _clipboard(p: PixelBrush, x: int, y: int, turned: bool = false) -> void:
	if turned:
		p.r(x, y, 3, 15, INK)
		p.r(x + 1, y + 1, 1, 13, Color("c7b28a"))
		return
	p.poly([[x, y], [x + 11, y - 1], [x + 13, y + 15], [x + 2, y + 16]], INK)
	p.poly([[x + 1, y + 1], [x + 10, y], [x + 11, y + 13], [x + 3, y + 14]], Color("746b5d"))
	p.r(x + 3, y + 2, 6, 10, Color("dcd2ad"))
	p.r(x + 4, y, 4, 2, METAL)
	for i in range(3):
		p.r(x + 4, y + 4 + i * 3, 4, 1, Color("8f9b8a"))

static func _star(p: PixelBrush, x: int, y: int, color: Color) -> void:
	p.r(x + 1, y, 1, 5, color)
	p.r(x - 1, y + 2, 5, 1, color)

static func _nova(p: PixelBrush, q: Dictionary) -> void:
	var skin := Color("b8754d")
	var hair := Color("3b2c30")
	var cream := Color("e7d6af")
	var sage := Color("849476")
	var coral := Color("e57d55")
	var dy: int = int(q.dy)
	_legs(p, q, sage.darkened(.17), Color("c7b591"))
	
	var pony_sway: int = int(q.swing) / 2
	p.poly([[-13 + pony_sway, -50 + dy], [-7 + pony_sway, -50 + dy], [-5, -47 + dy], [-2, -45 + dy], [-2, -34 + dy], [-7, -31 + dy], [-8, -27 + dy], [-14, -28 + dy], [-17, -32 + dy], [-18, -40 + dy], [-16, -44 + dy]], INK)
	p.r(-15 + pony_sway, -45 + dy, 9, 13, hair)
	p.r(-13 + pony_sway, -49 + dy, 6, 7, hair)
	p.r(-17, -40 + dy, 4, 7, hair)
	for curl in [Vector2(-12, -47), Vector2(-15, -41), Vector2(-10, -36), Vector2(-14, -32), Vector2(-8, -43)]:
		p.r(curl.x, curl.y + dy, 3, 2, Color("58403b"))
		p.r(curl.x - 1, curl.y + dy + 2, 2, 2, Color("2b282e"))
	if q.side:
		p.poly([[-7, -29 + dy], [5, -30 + dy], [11, -25 + dy], [10, -12], [-8, -11], [-11, -19]], INK)
		p.r(-6, -28 + dy, 13, 16, cream)
		p.r(3, -27 + dy, 5, 13, sage)
		p.r(-6, -27 + dy, 3, 14, Color("c3b997"))
		p.r(-4, -16, 12, 2, Color("665e4c"))
		p.r(5, -16, 3, 2, Color("cfb875"))
		var arm_y: int = -24 + dy + int(q.swing)
		p.r(-3, arm_y, 6, 12, INK)
		p.r(-2, arm_y + 1, 4, 9, cream)
		p.r(-1, arm_y + 9, 4, 3, skin)
		_clipboard(p, 0, -18 + int(q.swing), true)
	else:
		p.poly([[-9, -29 + dy], [8, -29 + dy], [13, -25 + dy], [14, -15], [9, -10], [-9, -10], [-13, -15], [-13, -24 + dy]], INK)
		p.r(-8, -28 + dy, 16, 16, sage)
		p.r(-6, -27 + dy, 12, 5, Color("667b67"))
		p.r(-5, -24 + dy, 10, 8, sage.lightened(.1))
		p.r(-4, -21 + dy, 8, 5, sage.darkened(.15))
		p.r(-3, -20 + dy, 6, 3, sage)
		p.r(-8, -28 + dy, 3, 16, cream)
		p.r(6, -28 + dy, 4, 16, cream)
		p.poly([[-8, -28 + dy], [-4, -30 + dy], [-3, -25 + dy], [-6, -22 + dy]], LIGHT)
		p.poly([[6, -29 + dy], [3, -28 + dy], [5, -24 + dy], [9, -25 + dy]], LIGHT)
		p.r(-6, -25 + dy, 1, 11, Color("bbae8a"))
		p.r(7, -20 + dy, 2, 4, Color("c97d57"))
		p.r(7, -21 + dy, 2, 1, Color("344955"))
		p.r(-8, -13, 17, 2, Color("5c5d4e"))
		p.r(-1, -14, 5, 4, Color("d2b66f"))
		p.r(0, -13, 3, 2, Color("6c745f"))
		if q.back:
			p.r(-7, -27 + dy, 14, 12, cream)
			p.r(-6, -28 + dy, 12, 3, Color("c5bc9b"))
			p.r(-2, -24 + dy, 5, 7, Color("324b59"))
			p.r(0, -24 + dy, 1, 6, Color("dfbd75"))
			p.r(-1, -18 + dy, 3, 1, Color("dfbd75"))
			p.r(-11, -24 + dy + int(q.swing), 4, 13, cream)
			p.r(8, -24 + dy - int(q.swing), 4, 13, cream)
			p.r(-10, -12 + int(q.swing), 3, 3, skin)
			p.r(9, -12 - int(q.swing), 3, 3, skin)
	
	p.r(-2, -32 + dy, 6, 5, skin.darkened(.1))
	if q.back:
		p.poly([[-7, -45 + dy], [3, -46 + dy], [9, -41 + dy], [8, -32 + dy], [3, -29 + dy], [-5, -30 + dy], [-9, -35 + dy]], INK)
		p.r(-6, -44 + dy, 12, 12, hair)
		p.r(-4, -44 + dy, 7, 2, Color("5c413d"))
		p.r(-7, -45 + dy, 12, 2, coral)
		p.r(-9, -42 + dy, 3, 10, coral)
		p.r(6, -41 + dy, 3, 9, coral)
		p.r(-9, -40 + dy, 1, 6, Color("f2a271"))
		return
	_face(p, -6 if not q.side else -3, -44 + dy, 15 if not q.side else 12, 15, skin, q.side, q.blink, q.celebrate)
	p.poly([[-7, -40 + dy], [-6, -45 + dy], [-2, -47 + dy], [5, -46 + dy], [10, -42 + dy], [6, -41 + dy], [3, -43 + dy], [0, -40 + dy], [-3, -38 + dy]], hair)
	p.r(-2, -45 + dy, 5, 1, Color("62433b"))
	p.r(-6, -43 + dy, 3, 5, hair)
	p.r(-7, -46 + dy, 12, 2, coral)
	p.r(-9, -43 + dy, 3, 10, INK)
	p.r(-10, -41 + dy, 5, 8, coral)
	p.r(-9, -40 + dy, 2, 6, Color("f49c6a"))
	p.r(-6, -40 + dy, 1, 6, Color("a95647"))
	p.r(8, -40 + dy, 3, 7, INK)
	p.r(9, -39 + dy, 2, 5, coral)
	p.line(Vector2(10, -34 + dy), Vector2(7, -31 + dy), INK)
	p.r(5, -32 + dy, 3, 2, INK)
	if q.side:
		return
	if q.celebrate:
		var lift: int = [0, 3, 7, 7, 5, 2][int(q.frame)]
		p.poly([[9, -26 + dy], [13, -24 + dy], [17, -30 - lift], [13, -33 - lift], [10, -28 + dy]], INK)
		p.r(10, -27 - lift / 2, 5, 9, cream)
		p.r(13, -32 - lift, 4, 6, skin)
		p.r(13, -34 - lift, 1, 3, skin)
		p.r(16, -33 - lift, 1, 3, skin)
		_clipboard(p, -13, -24 + dy)
		p.r(-12, -18 + dy, 5, 5, skin)
		if int(q.frame) in [2, 3, 4]:
			_star(p, -18, -49, Color("e8bd66"))
			_star(p, 16, -48, Color("e8bd66"))
	else:
		var lift: int = [0, 3, 6, 6, 4, 1][int(q.frame)] if q.work else 0
		p.r(-12, -26 + dy + int(q.swing), 5, 12, cream)
		p.r(-12, -17 + dy + int(q.swing), 4, 5, skin)
		_clipboard(p, -13, -24 + dy + int(q.swing))
		p.r(-11, -19 + dy + int(q.swing), 5, 5, skin)
		p.r(9, -26 + dy - lift / 2, 5, 12 - lift / 2, cream)
		_radio(p, 10, -29 + dy - lift, q.work)
		p.r(10, -22 + dy - lift, 5, 5, skin)
		p.r(11, -22 + dy - lift, 3, 1, skin.lightened(.18))
		p.line(Vector2(13, -15 - lift), Vector2(10, -8), INK)
		p.r(8, -11, 5, 5, Color("46535a"))

static func _bram(p: PixelBrush, q: Dictionary) -> void:
	var skin := Color("db9e6e")
	var beard := Color("654632")
	var coat := Color("d77652")
	var gold := Color("e7b74e")
	var dy: int = int(q.dy)
	_legs(p, q, Color("52605a"), Color("48494a"), true)
	
	p.poly([[-15, -31 + dy], [12, -32 + dy], [17, -26 + dy], [17, -12], [-16, -12]], INK)
	p.r(-15, -28 + dy, 6, 14, Color("4c4d48"))
	p.r(11, -28 + dy, 5, 15, Color("586158"))
	if q.side:
		p.r(-13, -31 + dy, 9, 20, Color("505b55"))
		p.r(-12, -29 + dy, 3, 16, Color("7a8571"))
		p.poly([[-6, -29 + dy], [7, -30 + dy], [13, -25 + dy], [12, -11], [-7, -10]], INK)
		p.r(-5, -28 + dy, 16, 16, coat)
		p.r(8, -26 + dy, 3, 13, Color("b85646"))
		p.r(-5, -17, 16, 3, LIGHT)
		p.r(-2, -28 + dy, 3, 16, Color("34414a"))
		p.r(-4, -25 + dy + int(q.swing), 8, 14, INK)
		p.r(-3, -24 + dy + int(q.swing), 6, 10, coat.lightened(.06))
		p.r(-3, -17 + int(q.swing), 6, 2, LIGHT)
		p.r(-2, -13 + int(q.swing), 6, 5, Color("3b3e43"))
	else:
		p.poly([[-11, -31 + dy], [10, -31 + dy], [16, -26 + dy], [16, -15], [12, -10], [-12, -10], [-17, -16], [-16, -25 + dy]], INK)
		p.r(-11, -30 + dy, 22, 19, coat)
		p.r(-14, -25 + dy, 4, 13, coat)
		p.r(11, -25 + dy, 4, 13, Color("bd604b"))
		p.r(-10, -27 + dy, 5, 7, coat.lightened(.13))
		p.r(-11, -16, 23, 3, LIGHT)
		p.r(-11, -14, 23, 1, Color("aaa789"))
		p.r(-7, -29 + dy, 3, 18, Color("303f49"))
		p.r(6, -29 + dy, 3, 18, Color("303f49"))
		p.r(-8, -24 + dy, 5, 4, Color("b39965"))
		p.r(-7, -23 + dy, 3, 2, Color("39454a"))
		p.r(5, -20 + dy, 5, 4, Color("b39965"))
		p.r(6, -19 + dy, 3, 2, Color("39454a"))
		p.r(-1, -28 + dy, 2, 17, Color("efb66a"))
		p.r(0, -23 + dy, 1, 10, Color("a35c45"))
		p.r(-12, -11, 25, 3, Color("35414a"))
		p.r(-2, -12, 5, 4, Color("899390"))
		p.r(-1, -11, 3, 2, Color("3e4648"))
		if q.back:
			p.r(-8, -30 + dy, 16, 20, Color("3c494d"))
			p.r(-7, -29 + dy, 7, 18, Color("9b9d84"))
			p.r(1, -29 + dy, 6, 18, Color("929a83"))
			p.r(-6, -28 + dy, 2, 15, Color("c7c5a0"))
			p.r(2, -28 + dy, 2, 15, Color("b4b89a"))
			p.r(-8, -23 + dy, 16, 3, Color("3b494c"))
			p.r(-8, -15, 16, 3, Color("3b494c"))
			p.r(-16, -23 + int(q.swing), 4, 11, coat)
			p.r(12, -23 - int(q.swing), 4, 11, coat)
			p.r(-16, -14 + int(q.swing), 5, 4, Color("3b3e43"))
			p.r(12, -14 - int(q.swing), 5, 4, Color("3b3e43"))
	
	p.r(-4, -32 + dy, 9, 6, skin)
	if q.back:
		p.r(-8, -42 + dy, 17, 13, beard)
		p.r(-9, -36 + dy, 3, 5, Color("4b3830"))
		p.r(7, -36 + dy, 3, 5, Color("4b3830"))
	else:
		_face(p, -8 if not q.side else -4, -42 + dy, 18 if not q.side else 14, 16, skin, q.side, q.blink, true)
		p.r(-8 if not q.side else -3, -35 + dy, 3, 3, Color("db7f5d"))
		p.r(7, -35 + dy, 3, 3, Color("db7f5d"))
		p.poly([[-9, -34 + dy], [-6, -31 + dy], [-4, -34 + dy], [0, -35 + dy], [5, -34 + dy], [8, -31 + dy], [11, -34 + dy], [10, -28 + dy], [6, -25 + dy], [1, -24 + dy], [-5, -26 + dy], [-9, -29 + dy]], beard)
		p.r(-5, -32 + dy, 5, 2, Color("875a39"))
		p.r(5, -31 + dy, 3, 3, Color("875a39"))
		p.r(-3, -32 + dy, 8, 2, LIGHT)
		p.r(-2, -30 + dy, 6, 1, Color("3f3230"))
		p.r(0, -35 + dy, 4, 2, Color("e9a274"))
		p.r(1, -35 + dy, 2, 1, Color("f4bd82"))
		p.r(-5, -28 + dy, 2, 2, Color("4e372c"))
		p.r(2, -26 + dy, 2, 1, Color("976841"))
	
	p.poly([[-12, -39 + dy], [-10, -46 + dy], [-5, -50 + dy], [3, -51 + dy], [10, -47 + dy], [13, -40 + dy], [16, -38 + dy], [14, -36 + dy], [-13, -36 + dy], [-15, -38 + dy]], INK)
	p.poly([[-11, -40 + dy], [-9, -45 + dy], [-4, -49 + dy], [3, -50 + dy], [9, -46 + dy], [12, -39 + dy]], gold)
	p.r(-12, -39 + dy, 27, 2, Color("e6b456"))
	p.r(-10, -40 + dy, 22, 1, Color("f5d784"))
	p.line(Vector2(-6, -46 + dy), Vector2(-7, -40 + dy), Color("bd883b"))
	p.line(Vector2(6, -46 + dy), Vector2(8, -40 + dy), Color("bd883b"))
	if not q.back:
		p.poly([[-3, -48 + dy], [3, -48 + dy], [5, -41 + dy], [-4, -41 + dy]], Color("34424c"))
		p.r(0, -46 + dy, 1, 4, LIGHT)
		p.r(-1, -43 + dy, 3, 1, LIGHT)
		p.r(0, -47 + dy, 1, 1, LIGHT)
	else:
		p.r(-5, -40 + dy, 11, 2, Color("f5de97"))
	if q.side or q.back:
		return
	if q.work:
		var pump: int = 1 if int(q.frame) in [1, 2, 4] else 0
		p.poly([[-14, -26 + dy], [-8, -24 + dy], [-4, -21 + pump], [8, -21 + pump], [9, -16 + pump], [-5, -16 + pump], [-15, -20]], INK)
		p.r(-13, -25 + dy, 6, 7, coat.lightened(.05))
		p.r(-9, -21 + pump, 10, 4, coat)
		p.r(0, -21 + pump, 6, 5, Color("3c4145"))
		p.r(10, -26 + dy, 5, 9, coat)
		p.r(13, -23 + pump, 5, 5, Color("3c4145"))
		p.line(Vector2(2, -18 + pump), Vector2(12, -22 + pump), Color("ae9470"), 3)
		p.line(Vector2(4, -16 + pump), Vector2(10, -10), Color("7c755d"), 3)
		p.line(Vector2(10, -10), Vector2(17, -8), Color("7c755d"), 3)
		p.r(13, -24 + pump, 9, 4, INK)
		p.r(14, -23 + pump, 7, 2, METAL)
		p.r(20, -25 + pump, 3, 5, Color("566b71"))
		for i in range(3):
			p.r(24 + i * 2, -24 + pump - ((int(q.frame) + i) % 2), 2, 1, Color("a6d7d6") if i != 1 else Color("e0eee0"))
	elif q.celebrate:
		var lift: int = [1, 6, 11, 11, 7, 3][int(q.frame)]
		p.r(-15, -24 + dy, 5, 12, coat)
		p.r(-15, -14, 6, 5, Color("3b3e43"))
		p.poly([[10, -27], [16, -27 - lift], [21, -25 - lift], [17, -17], [12, -18]], INK)
		p.r(12, -25 - lift / 2, 6, 8, coat)
		p.r(16, -30 - lift, 7, 7, Color("3b3e43"))
		p.r(17, -29 - lift, 5, 2, Color("69716b"))
		if int(q.frame) in [2, 3]:
			_star(p, -18, -48, Color("eac66d"))
	else:
		p.r(-16, -24 + dy + int(q.swing), 5, 12, coat)
		p.r(12, -24 + dy - int(q.swing), 5, 12, coat)
		p.r(-16, -17 + int(q.swing), 5, 2, LIGHT)
		p.r(12, -17 - int(q.swing), 5, 2, LIGHT)
		p.r(-16, -13 + int(q.swing), 6, 5, Color("3b3e43"))
		p.r(12, -13 - int(q.swing), 6, 5, Color("3b3e43"))

static func _medical_bag(p: PixelBrush, x: int, y: int, width: int = 13, height: int = 14) -> void:
	p.r(x + 3, y - 3, width - 6, 3, INK)
	p.r(x + 4, y - 2, width - 8, 1, Color("a79573"))
	p.r(x, y, width, height, INK)
	p.r(x + 1, y + 1, width - 2, height - 2, Color("356f75"))
	p.r(x + 2, y + 2, width - 4, 2, Color("548e8c"))
	p.r(x + width - 3, y + 3, 2, height - 5, Color("2b5964"))
	var cx: int = x + width / 2
	var cy: int = y + height / 2
	p.r(cx - 1, cy - 4, 3, 8, LIGHT)
	p.r(cx - 4, cy - 1, 9, 3, LIGHT)
	p.r(x + 2, y + height - 3, 2, 2, Color("be9d64"))
	p.r(x + width - 4, y + height - 3, 2, 2, Color("be9d64"))

static func _elio(p: PixelBrush, q: Dictionary) -> void:
	var skin := Color("cb8a58")
	var teal := Color("4d9d98")
	var hair := Color("302f37")
	var dy: int = int(q.dy) + (5 if q.work else 0)
	_legs(p, q, Color("3c5361"), Color("48535a"), false, q.work)
	_medical_bag(p, -12 if q.side else -14, -30 + dy, 15 if q.side else 28, 21)
	if q.back:
		p.r(-10, -29 + dy, 20, 17, teal)
		_medical_bag(p, -9, -29 + dy, 19, 19)
		p.r(-13, -25 + dy + int(q.swing), 5, 13, teal)
		p.r(10, -25 + dy - int(q.swing), 5, 13, teal)
		p.r(-12, -13 + int(q.swing), 4, 4, skin)
		p.r(11, -13 - int(q.swing), 4, 4, skin)
	elif q.side:
		p.poly([[-5, -31 + dy], [5, -31 + dy], [10, -26 + dy], [9, -12], [-6, -10]], INK)
		p.r(-4, -29 + dy, 12, 16, teal)
		p.r(5, -27 + dy, 3, 14, Color("367b80"))
		p.r(-3, -27 + dy + int(q.swing), 7, 14, INK)
		p.r(-2, -26 + dy + int(q.swing), 5, 11, teal.lightened(.12))
		p.r(-1, -15 + int(q.swing), 4, 4, skin)
		p.r(-1, -25 + int(q.swing), 3, 5, LIGHT)
		p.r(-2, -23 + int(q.swing), 5, 2, LIGHT)
	else:
		p.poly([[-9, -31 + dy], [8, -31 + dy], [13, -25 + dy], [12, -11], [-11, -11], [-14, -23 + dy]], INK)
		p.r(-9, -30 + dy, 18, 18, teal)
		p.r(-4, -28 + dy, 8, 15, Color("eaddb9"))
		p.r(-2, -27 + dy, 4, 8, Color("bdc2a6"))
		p.r(-9, -29 + dy, 4, 15, teal.lightened(.09))
		p.r(5, -29 + dy, 4, 16, Color("3c8588"))
		p.r(-7, -29 + dy, 2, 16, Color("303f49"))
		p.r(6, -29 + dy, 2, 16, Color("303f49"))
		p.r(-8, -24 + dy, 4, 3, Color("b59b65"))
		p.r(-7, -23 + dy, 2, 1, Color("34464d"))
		p.r(5, -21 + dy, 4, 3, Color("b59b65"))
		p.r(6, -20 + dy, 2, 1, Color("34464d"))
		p.r(-7, -14 + dy, 6, 3, Color("397d7f"))
		p.r(-6, -14 + dy, 4, 1, METAL)
		p.r(3, -14 + dy, 6, 3, Color("397d7f"))
		p.r(-5, -12, 11, 2, Color("34434c"))
		p.r(-1, -13, 4, 3, Color("baaa7e"))
		
		p.line(Vector2(-2, -27 + dy), Vector2(-3, -20 + dy), Color("3b505b"))
		p.line(Vector2(-3, -20 + dy), Vector2(1, -18 + dy), Color("3b505b"))
		p.line(Vector2(1, -18 + dy), Vector2(3, -23 + dy), Color("3b505b"))
		p.r(2, -24 + dy, 2, 2, METAL)
	p.r(-2, -33 + dy, 6, 6, skin)
	if not q.back:
		_face(p, -7 if not q.side else -3, -46 + dy, 15 if not q.side else 12, 16, skin, q.side, q.blink, q.celebrate)
		p.r(0, -32 + dy, 4, 1, Color("654435"))
		
		if q.side:
			p.r(3, -42 + dy, 6, 1, Color("4f3c2f"))
			p.r(2, -41 + dy, 1, 4, Color("4f3c2f"))
			p.r(8, -41 + dy, 1, 4, Color("4f3c2f"))
			p.r(3, -37 + dy, 5, 1, Color("4f3c2f"))
			p.r(-2, -41 + dy, 4, 1, Color("4f3c2f"))
		else:
			for x in [-6, 2]:
				p.r(x + 1, -42 + dy, 5, 1, Color("4f3c2f"))
				p.r(x, -41 + dy, 1, 4, Color("4f3c2f"))
				p.r(x + 6, -41 + dy, 1, 4, Color("4f3c2f"))
				p.r(x + 1, -37 + dy, 5, 1, Color("4f3c2f"))
				p.r(x + 1, -41 + dy, 1, 1, Color("eddcbb"))
			p.r(0, -40 + dy, 2, 1, Color("4f3c2f"))
	p.poly([[-9, -38 + dy], [-10, -43 + dy], [-7, -46 + dy], [-6, -49 + dy], [-1, -49 + dy], [1, -51 + dy], [6, -49 + dy], [9, -45 + dy], [7, -42 + dy], [4, -43 + dy], [2, -46 + dy], [-1, -43 + dy], [-5, -41 + dy], [-6, -36 + dy]], INK)
	p.r(-7, -44 + dy, 6, 4, hair)
	p.r(-5, -47 + dy, 7, 3, hair)
	p.r(1, -49 + dy, 5, 5, hair)
	p.r(-5, -46 + dy, 5, 1, Color("585054"))
	p.r(2, -47 + dy, 4, 1, Color("585054"))
	p.r(-8, -42 + dy, 2, 5, Color("46404a"))
	if q.back:
		p.r(-7, -43 + dy, 14, 12, hair)
		p.r(-6, -44 + dy, 11, 3, Color("3e3941"))
		p.r(-5, -33 + dy, 10, 2, skin.darkened(.2))
		return
	if q.side:
		return
	if q.work:
		var reach: int = [0, 1, 3, 4, 3, 1][int(q.frame)]
		p.r(-12, -21 + dy, 5, 9, teal)
		p.r(-10, -14 + dy, 5, 4, Color("d8dfc6"))
		p.poly([[8, -25 + dy], [13, -21 + dy], [15 + reach, -12], [11 + reach, -9], [7, -16]], INK)
		p.r(9, -23 + dy, 5, 8, teal.lightened(.09))
		p.r(11, -16 + dy, 4 + reach, 4, Color("e4e4c9"))
		p.r(13 + reach, -13 + dy, 3, 3, Color("d6dcc4"))
		_medical_bag(p, -20, -10, 12, 10)
		p.r(-18, -11, 8, 1, METAL)
	elif q.celebrate:
		var lift: int = [0, 3, 7, 7, 4, 1][int(q.frame)]
		p.r(-13, -25 + dy, 5, 13, teal)
		p.r(-12, -13, 4, 4, skin)
		p.r(9, -27 - lift / 2, 5, 12, teal)
		p.r(12, -31 - lift, 4, 6, skin)
		p.r(12, -34 - lift, 1, 4, skin)
		p.r(15, -33 - lift, 1, 4, skin)
		if int(q.frame) in [2, 3]:
			p.r(17, -45, 2, 2, Color("de9c74"))
			p.r(20, -45, 2, 2, Color("de9c74"))
			p.r(18, -43, 3, 2, Color("de9c74"))
			p.r(19, -41, 1, 1, Color("de9c74"))
	else:
		for i in range(2):
			var x: int = -13 if i == 0 else 9
			var swing: int = int(q.swing) if i == 0 else -int(q.swing)
			p.r(x, -26 + dy + swing, 5, 13, teal)
			p.r(x + 1, -25 + dy + swing, 3, 7, teal.lightened(.12))
			p.r(x + 1, -14 + swing, 4, 4, skin)
		p.r(10, -25 + dy - int(q.swing), 2, 5, LIGHT)
		p.r(9, -23 + dy - int(q.swing), 4, 2, LIGHT)

static func _wrench(p: PixelBrush, handle: Vector2, angle: float, length: float = 19) -> void:
	var axis := Vector2(cos(angle), sin(angle))
	var across := Vector2(-axis.y, axis.x)
	var tip: Vector2 = handle + axis * length
	p.line(handle, tip, INK, 4)
	p.line(handle, tip, METAL, 2)
	var shape: Array = []
	for coord in [Vector2(4, -3), Vector2(1, -3), Vector2(0, -1), Vector2(0, 1), Vector2(1, 3), Vector2(4, 3), Vector2(2, 5), Vector2(-2, 4), Vector2(-4, 1), Vector2(-4, -1), Vector2(-2, -4), Vector2(2, -5)]:
		shape.append(tip + axis * coord.x + across * coord.y)
	p.poly(shape, INK)
	var inner: Array = []
	for coord in [Vector2(3, -3), Vector2(1, -2), Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 2), Vector2(3, 3), Vector2(1, 4), Vector2(-2, 3), Vector2(-3, 0), Vector2(-2, -3), Vector2(1, -4)]:
		inner.append(tip + axis * coord.x + across * coord.y)
	p.poly(inner, METAL)
	p.r(handle.x - 1, handle.y - 1, 2, 2, Color("ccd0b9"))

static func _tess(p: PixelBrush, q: Dictionary) -> void:
	var skin := Color("deaa77")
	var hair := Color("704b36")
	var mustard := Color("dcaf4f")
	var navy := Color("3b5263")
	var dy: int = int(q.dy)
	_legs(p, q, navy, Color("685744"))
	if not q.work and not q.celebrate:
		_wrench(p, Vector2(14, -25 + dy), -2.65, 27)
	if q.side:
		p.poly([[-6, -29 + dy], [6, -29 + dy], [12, -24 + dy], [9, -12], [-9, -11], [-11, -23 + dy]], INK)
		p.r(-7, -28 + dy, 15, 16, mustard)
		p.r(3, -26 + dy, 5, 15, navy)
		p.r(-5, -15, 14, 3, Color("77573f"))
		p.r(-3, -27 + dy + int(q.swing), 7, 13, INK)
		p.r(-2, -26 + dy + int(q.swing), 5, 10, mustard.lightened(.1))
		p.r(-1, -16 + int(q.swing), 4, 4, skin)
		p.r(-8, -13, 5, 6, Color("987047"))
		p.r(-7, -12, 3, 1, Color("c39861"))
	else:
		p.poly([[-10, -29 + dy], [8, -29 + dy], [14, -25 + dy], [14, -14], [9, -10], [-10, -10], [-14, -15], [-14, -24 + dy]], INK)
		p.r(-11, -28 + dy, 22, 17, mustard)
		p.r(-9, -27 + dy, 4, 11, mustard.lightened(.18))
		p.r(8, -27 + dy, 4, 14, Color("b8883d"))
		p.r(-5, -27 + dy, 11, 16, navy)
		p.r(-5, -28 + dy, 2, 14, Color("243c4c"))
		p.r(5, -28 + dy, 2, 14, Color("243c4c"))
		p.r(-4, -28 + dy, 8, 5, LIGHT)
		p.r(-4, -23 + dy, 9, 8, navy)
		p.r(-3, -21 + dy, 7, 4, Color("304856"))
		p.r(-2, -21 + dy, 5, 1, Color("587081"))
		p.r(-5, -24 + dy, 2, 2, Color("efcb78"))
		p.r(4, -24 + dy, 2, 2, Color("efcb78"))
		p.r(-11, -14, 23, 3, Color("785740"))
		p.r(-1, -15, 5, 5, Color("dbb96e"))
		p.r(0, -14, 3, 3, Color("594a3c"))
		p.r(-10, -12, 6, 6, Color("8d653f"))
		p.r(-9, -11, 4, 1, Color("c39760"))
		p.r(7, -12, 5, 6, Color("987047"))
		p.r(8, -11, 3, 1, Color("c39760"))
		p.r(-7, -16, 2, 5, METAL)
		p.r(-8, -17, 4, 2, Color("b4bbb0"))
		if q.back:
			p.r(-9, -27 + dy, 18, 12, mustard)
			p.poly([[-8, -28 + dy], [7, -28 + dy], [6, -23 + dy], [2, -21 + dy], [-3, -22 + dy]], Color("ba903f"))
			p.r(-6, -22 + dy, 2, 9, Color("344954"))
			p.r(5, -22 + dy, 2, 9, Color("344954"))
			p.r(-13, -23 + int(q.swing), 5, 12, mustard)
			p.r(9, -23 - int(q.swing), 5, 12, mustard)
			p.r(-12, -13 + int(q.swing), 4, 4, skin)
			p.r(10, -13 - int(q.swing), 4, 4, skin)
	
	p.poly([[-10, -41 + dy], [-6, -44 + dy], [6, -44 + dy], [11, -40 + dy], [12, -31 + dy], [8, -27 + dy], [5, -30 + dy], [-7, -28 + dy], [-12, -31 + dy], [-13, -35 + dy]], INK)
	p.r(-10, -39 + dy, 20, 10, hair)
	p.r(-12, -35 + dy, 4, 5, hair)
	p.r(9, -35 + dy, 4, 5, hair)
	p.r(-10, -31 + dy, 4, 1, Color("9a6a43"))
	p.r(9, -33 + dy, 2, 3, Color("9a6a43"))
	p.r(-2, -31 + dy, 6, 5, skin)
	if not q.back:
		_face(p, -6 if not q.side else -2, -42 + dy, 15 if not q.side else 12, 14, skin, q.side, q.blink, true)
		p.poly([[-7, -40 + dy], [-2, -44 + dy], [5, -42 + dy], [7, -39 + dy], [3, -40 + dy], [-1, -38 + dy], [-4, -35 + dy], [-6, -34 + dy]], hair)
		p.r(-2, -41 + dy, 5, 1, Color("a07449"))
		p.r(5, -32 + dy, 3, 1, Color("edaf7c"))
	else:
		p.r(-7, -40 + dy, 15, 11, hair)
		p.r(-6, -32 + dy, 4, 3, Color("543e32"))
		p.r(3, -32 + dy, 4, 3, Color("543e32"))
	p.poly([[-11, -40 + dy], [-10, -45 + dy], [-5, -48 + dy], [4, -48 + dy], [10, -44 + dy], [12, -41 + dy], [15, -40 + dy], [14, -38 + dy], [2, -38 + dy], [-3, -40 + dy]], INK)
	p.poly([[-10, -42 + dy], [-8, -45 + dy], [-4, -47 + dy], [4, -47 + dy], [9, -44 + dy], [10, -41 + dy], [-9, -41 + dy]], Color("344954"))
	p.r(-9, -42 + dy, 8, 1, Color("59707b"))
	p.r(1, -41 + dy, 12, 2, Color("425362"))
	if not q.back:
		p.poly([[0, -46 + dy], [4, -46 + dy], [7, -42 + dy], [-1, -42 + dy]], Color("e8b851"))
		p.r(2, -45 + dy, 2, 3, Color("40535e"))
		p.r(1, -44 + dy, 4, 1, Color("40535e"))
	if q.back or q.side:
		return
	if q.work:
		var angle: float = [-1.4, -1.05, -.65, -.25, -.65, -1.05][int(q.frame)]
		p.r(-14, -25 + dy, 6, 11, mustard)
		p.r(-12, -15, 5, 4, skin)
		p.r(9, -25 + dy, 5, 9, mustard.lightened(.09))
		_wrench(p, Vector2(12, -22), angle, 13)
		p.r(10, -23, 6, 5, skin)
		p.r(11, -23, 4, 1, skin.lightened(.15))
		if int(q.frame) == 3:
			p.r(24, -16, 3, 1, Color("f1d793"))
			p.r(28, -19, 1, 3, Color("f1d793"))
			p.r(22, -13, 1, 2, Color("f1d793"))
	elif q.celebrate:
		var lift: int = [0, 2, 5, 5, 3, 1][int(q.frame)]
		p.r(-14, -25 + dy, 6, 11, mustard)
		p.r(-14, -15, 5, 5, skin)
		p.r(-15, -17, 2, 4, skin)
		p.r(10, -29 - lift, 5, 13, mustard)
		_wrench(p, Vector2(14, -30 - lift), -1.75, 14)
		p.r(12, -31 - lift, 5, 5, skin)
		if int(q.frame) in [2, 3]:
			_star(p, -17, -46, Color("e7c366"))
	else:
		p.r(-14, -25 + dy + int(q.swing), 6, 12, mustard)
		p.r(-13, -14 + int(q.swing), 5, 4, skin)
		p.r(10, -26 + dy - int(q.swing), 5, 10, mustard)
		p.r(12, -27 + dy, 5, 5, skin)
		p.r(-12, -24 + dy + int(q.swing), 3, 4, Color("405663"))
		p.r(-13, -23 + dy + int(q.swing), 5, 2, Color("405663"))
