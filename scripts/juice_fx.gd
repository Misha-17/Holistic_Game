class_name JuiceFx
extends Node2D

# Feel-good feedback layer (Oct 2026): confetti, pop-ups, flying rescue icons,
# banners, route draw-in, road-open tape, screen shake and a red flash.
# Purely cosmetic: it never touches the simulation, so every session still
# plays out identically. Respects the "Reduced motion" setting.

const INK := Color("142e3b")
const CREAM := Color("f5e7c5")
const GOLD := Color("f1cf7e")
const TEAL := Color("6fd3bd")
const CORAL := Color("f09a7b")
const RED := Color("ff6b57")
const KIND_COLOR := {"fire": Color("f2a27f"), "medic": Color("9be0c4"), "engineer": Color("f1cf7e"), "police": Color("aab4f7")}

var game: Node2D
var reduced_motion := false
var effects: Array[Dictionary] = []
var card_pulse: Dictionary = {}      # unit id -> seconds left
var counter_punch := 0.0             # 0..1, makes the RESCUED counter jump
var displayed_rescued := 0.0         # counts up towards the real number
var shake_left := 0.0
var shake_power := 0.0
var flash_left := 0.0
var view_rect := Rect2(0, 0, 1600, 900)
var _rng := RandomNumberGenerator.new()

# Banners, flying icons and the red flash sit above the HUD; everything that
# belongs to the map (confetti, routes, pop-ups) sits below it.
class TopLayer extends Node2D:
	var fx
	func _draw() -> void:
		fx._draw_top(self)

var _top: Node2D

func _ready() -> void:
	_rng.randomize()
	z_index = 9
	_top = TopLayer.new()
	_top.fx = self
	_top.z_as_relative = false
	_top.z_index = 12
	add_child(_top)

func reset() -> void:
	effects.clear()
	card_pulse.clear()
	counter_punch = 0.0
	shake_left = 0.0
	flash_left = 0.0

func _process(delta: float) -> void:
	for effect in effects:
		effect.t = float(effect.t) + delta
	effects = effects.filter(func(e: Dictionary) -> bool: return float(e.t) < float(e.dur) + float(e.get("delay", 0.0)))
	for id in card_pulse.keys():
		card_pulse[id] = float(card_pulse[id]) - delta
		if float(card_pulse[id]) <= 0.0: card_pulse.erase(id)
	counter_punch = maxf(0.0, counter_punch - delta * 2.4)
	shake_left = maxf(0.0, shake_left - delta)
	flash_left = maxf(0.0, flash_left - delta)
	if game != null and game.sim != null:
		var target: float = float(game.sim.rescued)
		if target < displayed_rescued: displayed_rescued = target
		else: displayed_rescued = move_toward(displayed_rescued, target, maxf(6.0, (target - displayed_rescued) * 5.0) * delta)
	queue_redraw()
	if _top != null: _top.queue_redraw()

func shake_offset() -> Vector2:
	if shake_left <= 0.0 or reduced_motion: return Vector2.ZERO
	var strength: float = shake_power * shake_left / 0.35
	return Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * strength

func _screen(normalized: Vector2) -> Vector2:
	var map: Rect2 = game._map_rect()
	return map.position + normalized * map.size

# ---------------------------------------------------------------- triggers

func rescue(pos: Vector2, people: int, counter: Vector2) -> void:
	var pieces: Array = []
	var count: int = 10 if reduced_motion else 34
	for i in range(count):
		pieces.append({"v": Vector2.from_angle(_rng.randf_range(-PI, 0.0)) * _rng.randf_range(90, 260), "spin": _rng.randf_range(-9, 9),
			"color": [TEAL, GOLD, CORAL, CREAM, Color("aab4f7")][i % 5], "size": Vector2(_rng.randf_range(4, 8), _rng.randf_range(3, 5))})
	effects.append({"type": "confetti", "pos": pos, "pieces": pieces, "t": 0.0, "dur": 1.5})
	effects.append({"type": "pop", "pos": pos, "text": "+%d SAFE" % people, "color": TEAL, "size": 26, "t": 0.0, "dur": 1.5})
	var icons: int = clampi(people, 1, 6)
	for i in range(icons):
		effects.append({"type": "fly", "from": _screen(pos) + Vector2(_rng.randf_range(-18, 18), -10), "to": counter,
			"t": 0.0, "dur": 0.75, "delay": 0.25 + i * 0.08, "last": i == icons - 1})

func banner(text: String, color: Color, big := true) -> void:
	# Only one banner at a time: a newer one replaces the old.
	effects = effects.filter(func(e: Dictionary) -> bool: return e.type != "banner")
	effects.append({"type": "banner", "text": text, "color": color, "size": 40 if big else 30, "t": 0.0, "dur": 1.9})

func dispatched(unit: Dictionary) -> void:
	card_pulse[int(unit.get("id", -1))] = 0.7
	var points: Array = [unit.get("pos", Vector2.ZERO)]
	for point in unit.get("path", []): points.append(point)
	if points.size() > 1:
		effects.append({"type": "route", "points": points, "color": KIND_COLOR.get(str(unit.get("kind", "")), CREAM), "t": 0.0, "dur": 1.2})

func road_open(pos: Vector2, color: Color) -> void:
	effects.append({"type": "tape", "pos": pos, "color": color, "t": 0.0, "dur": 0.9})
	effects.append({"type": "ring", "pos": pos, "color": color, "t": 0.0, "dur": 0.7})
	effects.append({"type": "pop", "pos": pos, "text": "ROAD OPEN", "color": GOLD, "size": 22, "t": 0.0, "dur": 1.4})

func failed(pos: Vector2) -> void:
	shake_left = 0.35
	shake_power = 7.0
	flash_left = 0.6
	effects.append({"type": "pop", "pos": pos, "text": "MISSED", "color": RED, "size": 24, "t": 0.0, "dur": 1.3})

func pulse_counter() -> void:
	counter_punch = 1.0

# ---------------------------------------------------------------- drawing

func _ease_back(x: float) -> float:
	# Overshoots slightly past 1 before settling: the "bouncy" pop.
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3) + c * pow(x - 1.0, 2)

func _draw() -> void:
	if game == null or game.screen not in ["game", "pause", "results", "help"]: return
	var font: Font = game.font
	for effect in effects:
		var t: float = float(effect.t) - float(effect.get("delay", 0.0))
		if t < 0.0: continue
		var k: float = clampf(t / float(effect.dur), 0.0, 1.0)
		match str(effect.type):
			"confetti":
				var origin: Vector2 = _screen(effect.pos)
				for piece in effect.pieces:
					var p: Vector2 = origin + piece.v * t + Vector2(0, 420.0 * t * t)
					draw_set_transform(p, float(piece.spin) * t, Vector2.ONE)
					draw_rect(Rect2(-piece.size * .5, piece.size), Color(piece.color, 1.0 - k * k))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			"pop":
				var at: Vector2 = _screen(effect.pos) + Vector2(0, -46 - 34.0 * k)
				var scale: float = 1.0 if reduced_motion else _ease_back(clampf(t / 0.35, 0.0, 1.0))
				var alpha: float = clampf((1.0 - k) * 3.0, 0.0, 1.0)
				var size: int = int(effect.size)
				var width: float = font.get_string_size(effect.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				draw_set_transform(at, 0, Vector2.ONE * maxf(0.05, scale))
				draw_string_outline(font, Vector2(-width * .5, 0), effect.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 7, Color(INK, alpha))
				draw_string(font, Vector2(-width * .5, 0), effect.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(effect.color, alpha))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			"route":
				var pts: Array = effect.points
				var total: float = 0.0
				for i in range(1, pts.size()): total += _screen(pts[i - 1]).distance_to(_screen(pts[i]))
				var shown: float = total * clampf(t / 0.55, 0.0, 1.0)
				var alpha: float = clampf((1.0 - k) * 2.5, 0.0, 1.0)
				var walked: float = 0.0
				for i in range(1, pts.size()):
					var a: Vector2 = _screen(pts[i - 1])
					var b: Vector2 = _screen(pts[i])
					var length: float = a.distance_to(b)
					if walked >= shown: break
					var end: Vector2 = b if walked + length <= shown else a.lerp(b, (shown - walked) / maxf(0.001, length))
					draw_line(a, end, Color(INK, .6 * alpha), 9, true)
					draw_line(a, end, Color(effect.color, alpha), 5, true)
					walked += length
					if walked >= shown: draw_circle(end, 7, Color(CREAM, alpha))
			"tape":
				var c: Vector2 = _screen(effect.pos)
				var spread: float = 70.0 * k
				for side in [-1, 1]:
					draw_set_transform(c + Vector2(side * (14 + spread), 12.0 * k * k * 6), side * 1.4 * k, Vector2.ONE)
					var rect := Rect2(Vector2(-26, -5), Vector2(52, 10))
					draw_rect(rect, Color(GOLD, 1.0 - k))
					for x in range(-26, 26, 10): draw_rect(Rect2(Vector2(x, -5), Vector2(5, 10)), Color(INK, 1.0 - k))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			"ring":
				var c2: Vector2 = _screen(effect.pos)
				draw_arc(c2, 16 + 90 * k, 0, TAU, 48, Color(effect.color, 1.0 - k), 5, true)

func _draw_top(canvas: Node2D) -> void:
	if game == null or game.screen not in ["game", "pause", "results", "help"]: return
	var font: Font = game.font
	for effect in effects:
		var t: float = float(effect.t) - float(effect.get("delay", 0.0))
		if t < 0.0: continue
		var k: float = clampf(t / float(effect.dur), 0.0, 1.0)
		match str(effect.type):
			"fly":
				var from: Vector2 = effect.from
				var to: Vector2 = effect.to
				var e: float = k * k * (3.0 - 2.0 * k)
				var control: Vector2 = from.lerp(to, .5) + Vector2(0, -160)
				var p: Vector2 = from.lerp(control, e).lerp(control.lerp(to, e), e)
				canvas.draw_circle(p, 9, Color(INK, .85))
				canvas.draw_circle(p, 7, TEAL)
				canvas.draw_rect(Rect2(p - Vector2(1.5, 4), Vector2(3, 8)), INK)
				canvas.draw_rect(Rect2(p - Vector2(4, 1.5), Vector2(8, 3)), INK)
				if k >= 0.98 and not bool(effect.get("landed", false)):
					effect.landed = true
					counter_punch = 1.0
			"banner":
				var center: Vector2 = Vector2(view_rect.get_center().x, 214)
				var grow: float = 1.0 if reduced_motion else _ease_back(clampf(t / 0.3, 0.0, 1.0))
				var alpha: float = clampf((1.0 - k) * 4.0, 0.0, 1.0)
				var size: int = int(effect.size)
				var width: float = font.get_string_size(effect.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				canvas.draw_set_transform(center, 0, Vector2.ONE * maxf(0.05, grow))
				canvas.draw_rect(Rect2(Vector2(-width * .5 - 26, -size - 8), Vector2(width + 52, size + 26)), Color(INK, .82 * alpha))
				canvas.draw_rect(Rect2(Vector2(-width * .5 - 26, -size - 8), Vector2(width + 52, size + 26)), Color(effect.color, alpha), false, 3)
				canvas.draw_string_outline(font, Vector2(-width * .5, 0), effect.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(INK, alpha))
				canvas.draw_string(font, Vector2(-width * .5, 0), effect.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(effect.color, alpha))
				canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if flash_left > 0.0:
		var a: float = flash_left / 0.6 * 0.30
		var v: Rect2 = view_rect
		for i in range(3):
			var w: float = 14.0 + i * 14.0
			var col := Color(RED, a * (1.0 - i * 0.3))
			canvas.draw_rect(Rect2(v.position, Vector2(v.size.x, w)), col)
			canvas.draw_rect(Rect2(Vector2(v.position.x, v.end.y - w), Vector2(v.size.x, w)), col)
			canvas.draw_rect(Rect2(v.position, Vector2(w, v.size.y)), col)
			canvas.draw_rect(Rect2(Vector2(v.end.x - w, v.position.y), Vector2(w, v.size.y)), col)
