class_name ResponderArt
extends RefCounted


const OUTLINE := Color("233c47")
const SKINS: Array[Color] = [Color("e5bc91"), Color("b88162"), Color("805949"), Color("eecbac"), Color("c89970"), Color("986c54")]
const HAIR: Array[Color] = [Color("453f3b"), Color("b97142"), Color("654839"), Color("d6bb75"), Color("383d46"), Color("857773")]

static func _r(canvas: CanvasItem, origin: Vector2, scale: float, x: float, y: float, w: float, h: float, color: Color) -> void:
	canvas.draw_rect(Rect2((origin + Vector2(x, y) * scale).floor(), Vector2(maxf(1.0, w * scale), maxf(1.0, h * scale)).floor()), color)

static func _line(canvas: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float = 1.0) -> void:
	canvas.draw_line(a.floor(), b.floor(), color, maxf(1, floorf(width)), false)

static func uniform(kind: String) -> Color:
	return {"fire": Color("cf7253"), "medic": Color("66b29d"), "engineer": Color("d7ae55"), "police": Color("4f63b0"), "civilian": Color("a39cbd")}.get(kind, Color("81a4a1"))

static func draw_portrait(canvas: CanvasItem, position: Vector2, kind: String, appearance: int, scale: float = 1.0) -> void:
	var variant: int = absi(appearance)
	var skin: Color = SKINS[variant % SKINS.size()]
	var hair: Color = HAIR[(variant * 5 + variant / 6) % HAIR.size()]
	var suit: Color = uniform(kind)
	_r(canvas, position, scale, 0, 0, 16, 18, Color("18313b"))
	_r(canvas, position, scale, 1, 1, 14, 16, suit.darkened(.5))
	_r(canvas, position, scale, 1, 14, 14, 3, Color("2b5057"))
	_r(canvas, position, scale, 3, 12, 10, 5, suit)
	_r(canvas, position, scale, 11, 13, 2, 4, suit.darkened(.2))
	_r(canvas, position, scale, 4, 15, 8, 1, Color("e7d596"))
	_r(canvas, position, scale, 7, 11, 3, 2, skin.darkened(.15))
	_r(canvas, position, scale, 5, 5, 7, 7, skin)
	_r(canvas, position, scale, 4, 5, 2, 6, hair)
	_r(canvas, position, scale, 5, 4, 7, 2, hair)
	_r(canvas, position, scale, 10, 8, 1, 1, OUTLINE)
	_r(canvas, position, scale, 12, 9, 1, 1, skin)
	if variant % 3 == 0:
		_r(canvas, position, scale, 5, 10, 3, 2, hair)
	if variant % 4 == 1:
		_r(canvas, position, scale, 3, 7, 2, 6, hair)
	if variant % 5 == 2:
		_r(canvas, position, scale, 8, 8, 4, 1, Color("718a84"))
	if kind in ["fire", "engineer"]:
		var helmet: Color = Color("e5d7b2") if variant % 3 == 1 else Color("e8bc68")
		_r(canvas, position, scale, 4, 2, 8, 4, helmet)
		_r(canvas, position, scale, 3, 5, 11, 1, helmet.darkened(.18))
		_r(canvas, position, scale, 6, 2, 1, 3, helmet.lightened(.2))
		_r(canvas, position, scale, 8, 4, 2, 1, Color("ae7155"))
	elif kind == "police":
		_r(canvas, position, scale, 4, 2, 9, 3, Color("27346a"))
		_r(canvas, position, scale, 3, 5, 11, 1, Color("1d2852"))
		_r(canvas, position, scale, 7, 3, 2, 1, Color("e7d596"))
		_r(canvas, position, scale, 9, 13, 2, 2, Color("e7d596"))
	elif kind == "medic":
		if variant % 2 == 0:
			_r(canvas, position, scale, 4, 3, 8, 3, Color("e3ead0"))
			_r(canvas, position, scale, 8, 3, 1, 3, Color("bd6e64"))
		_r(canvas, position, scale, 6, 13, 1, 3, Color("e7ecd4"))
		_r(canvas, position, scale, 5, 14, 3, 1, Color("e7ecd4"))

static func draw_person(canvas: CanvasItem, position: Vector2, kind: String, appearance: int, action: String, time: float, facing: int = 1, scale: float = 1.0) -> void:
	var variant: int = absi(appearance)
	var skin: Color = SKINS[variant % SKINS.size()]
	var hair: Color = HAIR[(variant * 5 + variant / 6) % HAIR.size()]
	var suit: Color = uniform(kind)
	var boots := Color("2c3e47")
	var pants := Color("365565")
	var stripe := Color("d8ecce") if kind == "medic" else (Color("c9d8ef") if kind == "police" else Color("efcf80"))
	var kneeling: bool = action in ["treat", "repair", "sandbag", "cpr"]
	var walking: bool = action in ["walk", "carry"]
	var beat: int = int(time * 7.0 + variant * .7) % 4
	var dy: int = 4 if kneeling else 0
	if walking and beat % 2 == 0:
		dy -= 1
	_r(canvas, position, scale, -4, -1, 9, 2, Color("203d4655"))
	
	if kneeling:
		_r(canvas, position, scale, -3, -3, 3, 3, pants)
		_r(canvas, position, scale, 0, -2, 5, 2, pants)
		_r(canvas, position, scale, -4, -1, 3, 1, boots)
		_r(canvas, position, scale, 3, -1, 3, 1, boots)
	else:
		var stride: int = (1 if beat < 2 else -1) if walking else 0
		_r(canvas, position, scale, -3 - stride, -5, 3, 5, pants)
		_r(canvas, position, scale, 1 + stride, -5, 3, 5, pants.lightened(.08))
		_r(canvas, position, scale, -4 - stride, -1, 4, 2, boots)
		_r(canvas, position, scale, 1 + stride, -1, 4, 2, boots)
		if kind == "fire":
			_r(canvas, position, scale, -3 - stride, -3, 3, 1, stripe)
			_r(canvas, position, scale, 1 + stride, -3, 3, 1, stripe)
	
	if kind == "fire":
		_r(canvas, position, scale, -5 * facing, -10 + dy, 2, 6, Color("d3cda9"))
		_r(canvas, position, scale, -5 * facing, -9 + dy, 2, 1, Color("7e887e"))
	elif kind == "medic":
		_r(canvas, position, scale, -5 * facing, -9 + dy, 3, 5, Color("cce1c0"))
		_r(canvas, position, scale, -4 * facing, -8 + dy, 1, 3, Color("c16a62"))
	elif kind == "engineer":
		_r(canvas, position, scale, -5 * facing, -8 + dy, 2, 5, Color("806744"))
	_r(canvas, position, scale, -4, -10 + dy, 8, 7 - dy / 2, OUTLINE)
	_r(canvas, position, scale, -3, -10 + dy, 6, 6 - dy / 2, suit)
	_r(canvas, position, scale, 1, -9 + dy, 2, 5 - dy / 2, suit.darkened(.18))
	_r(canvas, position, scale, -3, -6 + dy, 6, 1, stripe)
	if kind == "medic":
		_r(canvas, position, scale, -1, -9 + dy, 1, 3, Color("e8f0d5"))
		_r(canvas, position, scale, -2, -8 + dy, 3, 1, Color("e8f0d5"))
	elif kind == "engineer":
		_r(canvas, position, scale, -2, -9 + dy, 1, 4, stripe)
		_r(canvas, position, scale, 1, -9 + dy, 1, 4, stripe)
	_r(canvas, position, scale, -1, -11 + dy, 2, 2, skin.darkened(.10))
	_r(canvas, position, scale, -3, -15 + dy, 6, 5, OUTLINE)
	_r(canvas, position, scale, -2, -15 + dy, 5, 4, skin)
	_r(canvas, position, scale, -2, -15 + dy, 5, 1, hair)
	_r(canvas, position, scale, -3, -14 + dy, 2, 2, hair)
	_r(canvas, position, scale, 2 * facing, -13 + dy, 1, 1, OUTLINE)
	_r(canvas, position, scale, 3 * facing, -12 + dy, 1, 1, skin)
	if variant % 3 == 0:
		_r(canvas, position, scale, -2, -12 + dy, 2, 2, hair)
	if variant % 4 == 1:
		_r(canvas, position, scale, -4, -13 + dy, 1, 4, hair)
	if variant % 5 == 2:
		_r(canvas, position, scale, 0, -13 + dy, 3, 1, Color("728b86"))
	if kind in ["fire", "engineer"]:
		var helmet := Color("ecd18a") if kind == "fire" else Color("edbe61")
		if variant % 3 == 1:
			helmet = Color("e8d8aa")
		_r(canvas, position, scale, -3, -17 + dy, 6, 3, helmet)
		_r(canvas, position, scale, -4, -15 + dy, 9, 1, helmet.darkened(.18))
		_r(canvas, position, scale, -2, -17 + dy, 1, 2, helmet.lightened(.20))
		_r(canvas, position, scale, 0, -16 + dy, 2, 1, Color("a87155") if kind == "fire" else Color("e7dcac"))
	elif kind == "police":
		_r(canvas, position, scale, -3, -17 + dy, 6, 2, Color("27346a"))
		_r(canvas, position, scale, -4, -15 + dy, 8, 1, Color("1d2852"))
		_r(canvas, position, scale, -1, -17 + dy, 2, 1, Color("e7d596"))
	elif kind == "medic" and variant % 2 == 0:
		_r(canvas, position, scale, -3, -16 + dy, 6, 2, Color("e4ead0"))
		_r(canvas, position, scale, 0, -16 + dy, 1, 2, Color("be655b"))
	elif kind == "civilian":
		_r(canvas, position, scale, -3, -16 + dy, 5, 2, hair)
	
	match action:
		"hose":
			_r(canvas, position, scale, 2, -9, 4, 2, suit)
			_r(canvas, position, scale, 5, -9, 2, 2, skin)
			_r(canvas, position, scale, 5, -10, 4, 2, Color("566f77"))
			_r(canvas, position, scale, 8, -10, 2, 1, Color("c0d3ca"))
			_r(canvas, position, scale, -4, -9, 2, 4, suit)
		"treat", "cpr":
			var pump: int = 1 if beat < 2 else 0
			_r(canvas, position, scale, 2 if facing > 0 else -5, -5, 3, 2 + pump, suit)
			_r(canvas, position, scale, 4 if facing > 0 else -7, -3 + pump, 3, 2, Color("dce7d0"))
			_r(canvas, position, scale, -4 if facing > 0 else 3, -5, 2, 3, suit)
		"repair":
			var lift: int = 2 if beat < 2 else 0
			_r(canvas, position, scale, 2 if facing > 0 else -6, -5 - lift, 4, 2, suit)
			_r(canvas, position, scale, 5 if facing > 0 else -7, -6 - lift, 2, 3, skin)
			_r(canvas, position, scale, 6 if facing > 0 else -7, -9 - lift, 1, 4, Color("aabac0"))
			_r(canvas, position, scale, 5 if facing > 0 else -8, -10 - lift, 3, 2, Color("d4ded2"))
		"radio":
			_r(canvas, position, scale, 3, -12, 2, 5, suit)
			_r(canvas, position, scale, 3, -12, 2, 2, skin)
			_r(canvas, position, scale, 4, -14, 1, 4, OUTLINE)
		"sandbag":
			_r(canvas, position, scale, 2, -5, 4, 2, suit)
			_r(canvas, position, scale, 3, -3, 6, 3, Color("c7b17c"))
			_r(canvas, position, scale, 4, -3, 4, 1, Color("e2cd98"))
		"carry":
			_r(canvas, position, scale, 3 if facing > 0 else -8, -8, 5, 2, suit)
			_r(canvas, position, scale, 7 if facing > 0 else -9, -8, 2, 2, skin)
		"wave":
			_r(canvas, position, scale, 3, -12, 2, 5, suit)
			_r(canvas, position, scale, 4, -15 + beat % 2, 2, 4, skin)
		_:
			var swing: int = 1 if walking and beat % 2 == 0 else 0
			_r(canvas, position, scale, -5, -9 + swing, 2, 4, suit)
			_r(canvas, position, scale, 3, -9 - swing, 2, 4, suit.darkened(.08))
			_r(canvas, position, scale, -5, -5 + swing, 2, 2, skin)
			_r(canvas, position, scale, 3, -5 - swing, 2, 2, skin)
	if kind == "medic" and action in ["walk", "radio", "portrait"]:
		_r(canvas, position, scale, 4, -5, 5, 4, Color("d9e5cc"))
		_r(canvas, position, scale, 6, -4, 1, 3, Color("b7645d"))
		_r(canvas, position, scale, 5, -3, 3, 1, Color("b7645d"))

static func draw_casualty(canvas: CanvasItem, position: Vector2, appearance: int, recovered: bool, time: float, scale: float = 1.0) -> void:
	if recovered:
		draw_person(canvas, position, "civilian", appearance, "wave", time, 1, scale)
		return
	var skin: Color = SKINS[absi(appearance) % SKINS.size()]
	_r(canvas, position, scale, -1, -1, 17, 3, Color("243e4855"))
	_r(canvas, position, scale, 0, -3, 5, 4, skin)
	_r(canvas, position, scale, 0, -3, 2, 4, HAIR[absi(appearance) % HAIR.size()])
	_r(canvas, position, scale, 3, -2, 1, 1, OUTLINE)
	_r(canvas, position, scale, 5, -3, 10, 4, Color("b7cba8"))
	_r(canvas, position, scale, 5, -3, 9, 1, Color("d7e2ba"))
	_r(canvas, position, scale, 6, -1, 8, 1, Color("87a595"))
	_r(canvas, position, scale, 14, -2, 3, 3, Color("526573"))

static func draw_stretcher(canvas: CanvasItem, position: Vector2, appearance: int, time: float, scale: float = 1.0) -> void:
	_r(canvas, position, scale, -3, -2, 24, 2, Color("d7dac8"))
	_r(canvas, position, scale, -1, 0, 2, 3, Color("566a70"))
	_r(canvas, position, scale, 16, 0, 2, 3, Color("566a70"))
	_r(canvas, position, scale, 1, -3, 16, 2, Color("809e8c"))
	draw_casualty(canvas, position + Vector2(0, -3) * scale, appearance, false, time, scale)

static func draw_water(canvas: CanvasItem, start: Vector2, finish: Vector2, time: float, scale: float = 1.0) -> void:
	var previous: Vector2 = start
	for i in range(1, 13):
		var t: float = i / 12.0
		var next: Vector2 = start.lerp(finish, t) + Vector2(0, -sin(t * PI) * 7 * scale)
		_line(canvas, previous, next, Color("a9e2df") if i % 3 else Color("e0f0d7"), scale)
		previous = next
	for i in range(3):
		var t: float = fposmod(time * 2 + i * .31, 1)
		var droplet: Vector2 = finish + Vector2((i - 1) * 3 * scale, t * 4 * scale)
		_r(canvas, droplet, scale, 0, 0, 1, 2, Color("b8e0d7"))

static func draw_flames(canvas: CanvasItem, position: Vector2, hazard: float, progress: float, time: float, scale: float = 1.0) -> void:
	var strength: float = clampf((.45 + hazard * .65) * (1 - progress * .92), .06, 1.2)
	for i in range(7):
		var flame: float = (5 + hazard * 8 + sin(time * 8 + i * 2) * 2) * strength
		var x: int = i * 3 - 9
		_r(canvas, position, scale, x, -flame, 4, flame, Color("b9503c"))
		_r(canvas, position, scale, x + 1, -flame + 2, 2, maxf(1, flame - 2), Color("ed9350"))
		_r(canvas, position, scale, x + 1, -flame * .4, 2, maxf(1, flame * .4), Color("f4d788"))
	for i in range(4):
		var rise: float = fposmod(time * 8 + i * 7, 27)
		var smoke := Color(.24, .31, .34, (1 - rise / 27) * strength * .6)
		_r(canvas, position, scale, -5 + sin(rise * .15 + i) * 6, -13 - rise, 5 + rise * .2, 3 + rise * .14, smoke)

static func draw_team(canvas: CanvasItem, origin: Vector2, kind: String, incident_kind: String, appearance: int, phase: String, progress: float, work_elapsed: float, time: float, scale: float = 1.0) -> void:
	var deploy: float = clampf(work_elapsed / 1.6, 0, 1)
	if phase == "deploy" or work_elapsed < 1.6:
		draw_person(canvas, origin + Vector2(-8 + deploy * 8, 1) * scale, kind, appearance, "walk", time, 1, scale)
		draw_person(canvas, origin + Vector2(-16 + deploy * 8, 3) * scale, kind, appearance + 9, "walk", time + .4, 1, scale)
		return
	if kind == "fire":
		if incident_kind in ["medical", "flood"]:
			draw_person(canvas, origin, kind, appearance, "radio", time, 1, scale)
			draw_person(canvas, origin + Vector2(-11, 3) * scale, kind, appearance + 9, "carry" if incident_kind == "medical" else "sandbag", time + .3, 1, scale)
			if incident_kind == "medical":
				_r(canvas, origin, scale, -7, -4, 15, 2, Color("b8c6af"))
				_r(canvas, origin, scale, -6, -3, 1, 3, Color("657f80"))
				_r(canvas, origin, scale, 6, -3, 1, 3, Color("657f80"))
		elif incident_kind == "power":
			draw_person(canvas, origin, kind, appearance, "hose", time, 1, scale)
			draw_person(canvas, origin + Vector2(-11, 3) * scale, kind, appearance + 9, "radio", time + .3, 1, scale)
			_r(canvas, origin, scale, 3, -6, 4, 6, Color("b86252"))
			for i in range(5):
				var drift: float = fposmod(time * 10 + i * 4, 19)
				_r(canvas, origin, scale, 10 + drift, -11 + sin(i * 2 + time * 3) * (1 + drift * .12), 2 + drift * .1, 2, Color(.91, .92, .79, .8 - drift * .025))
		elif phase == "secure":
			draw_person(canvas, origin, kind, appearance, "radio", time, 1, scale)
			draw_person(canvas, origin + Vector2(-11, 3) * scale, kind, appearance + 9, "walk", time, 1, scale)
		else:
			_line(canvas, origin + Vector2(-13, 2) * scale, origin + Vector2(6, -7) * scale, Color("ac8663"), 2 * scale)
			draw_person(canvas, origin + Vector2(-11, 3) * scale, kind, appearance + 9, "hose", time + .3, 1, scale)
			draw_person(canvas, origin, kind, appearance, "hose", time, 1, scale)
			draw_water(canvas, origin + Vector2(9, -10) * scale, origin + Vector2(30, -9) * scale, time, scale)
	elif kind == "medic":
		if progress >= .8:
			origin += Vector2((progress - .8) * 30, 0) * scale
			draw_person(canvas, origin + Vector2(-5, -1) * scale, kind, appearance, "carry", time, 1, scale)
			draw_person(canvas, origin + Vector2(23, 0) * scale, kind, appearance + 9, "carry", time + .5, -1, scale)
			draw_stretcher(canvas, origin + Vector2(3, -4) * scale, appearance + 4, time, scale)
		else:
			draw_casualty(canvas, origin + Vector2(5, 0) * scale, appearance + 4, false, time, scale)
			draw_person(canvas, origin, kind, appearance, "treat" if phase in ["assess", "hold"] else "cpr", time, 1, scale)
			draw_person(canvas, origin + Vector2(21, -2) * scale, kind, appearance + 9, "radio" if phase in ["assess", "hold"] else "treat", time + .4, -1, scale)
			_r(canvas, origin, scale, -7, -3, 5, 4, Color("e2e8cd"))
			_r(canvas, origin, scale, -5, -2, 1, 2, Color("bf7065"))
	elif kind == "police":
		# Cordon of cones and tape; one officer directs, the partner reports in.
		for i in range(4):
			_r(canvas, origin, scale, -14 + i * 9, 1, 3, 3, Color("ee8a52"))
			_r(canvas, origin, scale, -14 + i * 9, 2, 3, 1, Color("f4e3c0"))
		_line(canvas, origin + Vector2(-13, -2) * scale, origin + Vector2(15, -2) * scale, Color("efd36b"), scale)
		draw_person(canvas, origin, kind, appearance, "wave" if phase in ["act", "assess", "hold"] else "radio", time, 1, scale)
		draw_person(canvas, origin + Vector2(19, 1) * scale, kind, appearance + 9, "radio" if phase != "secure" else "walk", time + .5, -1, scale)
	else:
		if incident_kind == "flood":
			_r(canvas, origin, scale, 4, -5, 7, 6, Color("749ca1"))
			_r(canvas, origin, scale, 5, -4, 5, 3, Color("a3beb5"))
			_line(canvas, origin + Vector2(10, -1) * scale, origin + Vector2(24, 4) * scale, Color("c8c5a2"), 2 * scale)
			_r(canvas, origin, scale, 6, -3, 2, 2, Color("d9b868"))
			draw_person(canvas, origin, kind, appearance, "repair", time, 1, scale)
			draw_person(canvas, origin + Vector2(16, 2) * scale, kind, appearance + 9, "sandbag", time + .4, 1, scale)
			for i in range(1 + int(progress * 4)):
				_r(canvas, origin, scale, 25 + i % 3 * 6, 3 - i / 3 * 3, 6, 3, Color("c5b487"))
				_r(canvas, origin, scale, 26 + i % 3 * 6, 3 - i / 3 * 3, 4, 1, Color("e3cfa1"))
		else:
			_r(canvas, origin, scale, 9, -14, 10, 14, Color("3e5b64"))
			_r(canvas, origin, scale, 10, -13, 8, 12, Color("829e9a"))
			_r(canvas, origin, scale, 11, -11, 6, 7, Color("344e5c"))
			for wire in range(3):
				_r(canvas, origin, scale, 12 + wire * 2, -10, 1, 5, [Color("d99465"), Color("b4c47a"), Color("6baab4")][wire])
			_r(canvas, origin, scale, 11, -3, 2, 1, Color("92d8a3") if progress > .8 else Color("e7b363"))
			draw_person(canvas, origin, kind, appearance, "radio" if phase == "secure" else "repair", time, 1, scale)
			draw_person(canvas, origin + Vector2(23, 1) * scale, kind, appearance + 9, "radio" if phase in ["assess", "hold"] else "repair", time + .6, -1, scale)
			if int(time * 9) % 5 == 0 and phase == "act":
				_r(canvas, origin, scale, 8, -11, 2, 1, Color("ffe7a4"))
				_r(canvas, origin, scale, 7, -14, 1, 2, Color("ffe7a4"))
				_r(canvas, origin, scale, 11, -15, 1, 1, Color("ffe7a4"))
