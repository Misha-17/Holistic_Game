class_name TacticalMapOverlay
extends Node2D



signal unit_selected(id: int)
signal incident_selected(id: int)
signal dispatch_requested()

const INK := Color("142e3b")
const PANEL := Color("183c46")
const CREAM := Color("f5e7c5")
const MUTED := Color("a6bbb5")
const GOLD := Color("f1cf7e")
const GREEN := Color("9cdbba")
const RED := Color("f09a7b")
const ROLES: Array[String] = ["fire", "medic", "engineer"]
const ROLE_COLOR := {"fire": Color("f2a27f"), "medic": Color("9be0c4"), "engineer": Color("f1cf7e")}
const ROLE_SHORT := {"fire": "FIRE", "medic": "MED", "engineer": "ENG"}

var sim = null
var selected_id: int = -1
var selected_unit_id: int = -1
var tutorial_active: bool = false
var occlusions: Array[Rect2] = []
var map_rect := Rect2(24, 146, 1064, 632)
var reduced_motion: bool = false
var hovered_incident_id: int = -1
var hovered_unit_id: int = -1
var hovered_base_kind: String = ""
var role_filter: String = ""
var focused_unit_id: int = -1
var dispatch_enabled: bool = true

var _calls: Array[Dictionary] = []
var _crews: Array[Dictionary] = []
var _stations: Array[Dictionary] = []
var _roads: Array[Dictionary] = []
var _hits: Array[Dictionary] = []
var _occupied: Array[Rect2] = []
var _options: Array = []
var _preview: Dictionary = {}
var _elapsed: float = 0.0
var _layout_clock: float = 1.0
var _last_selection := Vector2i(-999, -999)
var _hovered_base_key: String = ""
var _pointer := Vector2(-1000, -1000)
var _pointer_valid: bool = false
var _hover_grace: float = 0.0
var _last_context: String = ""
var _send_rect := Rect2()
var _selected_option: Dictionary = {}
var _preview_id: int = -1
var _station_members: Dictionary = {}
var _base_positions: Dictionary = {}
var _pin_positions: Dictionary = {}
var _base_origins: Dictionary = {}
var _pin_origins: Dictionary = {}
var _layout_bounds_key: String = ""

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta: float) -> void:
	if not reduced_motion:
		_elapsed += minf(delta, .1)
	_layout_clock += delta
	_hover_grace = maxf(0.0, _hover_grace - delta)
	if _pointer_valid and _hover_grace <= 0 and not _hovered_base_key.is_empty():
		_update_hover(_pointer)
	var context: String = "%s:%s:%s:%s" % [role_filter, focused_unit_id, selected_id, selected_unit_id]
	if _layout_clock >= .10 or context != _last_context:
		_layout_clock = 0.0
		_last_selection = Vector2i(selected_id, selected_unit_id)
		_last_context = context
		_refresh_layout()
	queue_redraw()

func refresh() -> void:
	_refresh_layout()
	queue_redraw()

func clear_hover() -> void:
	_pointer_valid = false
	_hover_grace = 0
	_hovered_base_key = ""
	hovered_base_kind = ""
	hovered_unit_id = -1
	hovered_incident_id = -1
	refresh()

func hit_regions() -> Array[Dictionary]:
	return _hits.duplicate(true)

func _rect_for(type: String, id: int = -1, kind: String = "") -> Rect2:
	for hit in _hits:
		if hit.type == type and (id < 0 or int(hit.get("id", -1)) == id) and (kind.is_empty() or hit.get("kind", "") == kind):
			return hit.rect
	return Rect2()

func unit_hit_rect(id: int) -> Rect2:
	return _rect_for("unit", id)

func call_hit_rect(id: int) -> Rect2:
	return _rect_for("call", id)

func base_hit_rect(kind: String) -> Rect2:
	return _rect_for("base", -1, kind)

func send_hit_rect() -> Rect2:
	return _send_rect if _can_send() else Rect2()

func _can_send() -> bool:
	return dispatch_enabled and selected_id >= 0 and not _selected_option.is_empty() and selected_unit_id >= 0

func _world(position_normalized: Vector2) -> Vector2:
	return map_rect.position + position_normalized * map_rect.size

func _unit(id: int) -> Dictionary:
	if sim != null:
		for item in sim.units:
			if int(item.get("id", -1)) == id:
				return item
	return {}

func _call(id: int) -> Dictionary:
	if sim != null:
		for item in sim.incidents:
			if int(item.get("id", -1)) == id:
				return item
	return {}

func _primary_home(kind: String) -> Vector2:
	for unit in sim.units:
		if str(unit.get("kind", "")) == kind:
			return unit.get("home", Vector2.ZERO)
	return Vector2.ZERO

func _occluded(point: Vector2) -> bool:
	for area in occlusions:
		if area.has_point(point):
			return true
	return false

func _hit_at(point: Vector2) -> Dictionary:
	if not is_visible_in_tree() or sim == null or _occluded(point):
		return {}
	for i in range(_hits.size() - 1, -1, -1):
		if _hits[i].rect.has_point(point):
			return _hits[i]
	return {}

func _update_hover(point: Vector2) -> void:
	_pointer = point
	_pointer_valid = true
	var hit: Dictionary = _hit_at(point)
	var previous_key: String = _hovered_base_key
	var next_key: String = str(hit.get("base_key", ""))
	if next_key.is_empty() and not previous_key.is_empty():
		for station in _stations:
			if station.key == previous_key and station.expanded:
				
				
				var corridor: Rect2 = station.rect.merge(station.popup).grow(5)
				if corridor.has_point(point) and not _occluded(point):
					next_key = previous_key
					_hover_grace = .20
	if next_key.is_empty() and _hover_grace > 0 and not _occluded(point):
		next_key = previous_key
	_hovered_base_key = next_key
	hovered_base_kind = ""
	for station in _stations:
		if station.key == next_key: hovered_base_kind = str(station.kind)
	var next_call: int = int(hit.get("id", -1)) if hit.get("type", "") in ["call", "send"] else -1
	if next_call < 0 and hit.is_empty() and hovered_incident_id >= 0 and not _occluded(point):
		for item in _calls:
			if int(item.incident.id) == hovered_incident_id and item.card.has_area() and item.rect.merge(item.card).grow(4).has_point(point):
				next_call = hovered_incident_id
	var next_unit: int = int(hit.get("id", -1)) if hit.get("type", "") == "unit" else -1
	var changed: bool = hovered_incident_id != next_call or hovered_unit_id != next_unit or previous_key != next_key
	hovered_incident_id = next_call
	hovered_unit_id = next_unit
	if changed:
		_refresh_layout()
		queue_redraw()

func blocks_point(global_position: Vector2) -> bool:
	var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * global_position
	return not _hit_at(local_position).is_empty()

func handle_input(event: InputEvent) -> bool:
	if not is_visible_in_tree() or sim == null:
		return false
	if event is InputEventMouseMotion:
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		_update_hover(point)
		var hit: Dictionary = _hit_at(point)
		if not hit.is_empty():
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
			get_viewport().set_input_as_handled()
			queue_redraw()
			return true
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var hit: Dictionary = _hit_at(point)
		if not hit.is_empty():
			get_viewport().set_input_as_handled()
			match str(hit.type):
				"call": incident_selected.emit(int(hit.id))
				"unit": unit_selected.emit(int(hit.id))
				"send":
					if _can_send(): dispatch_requested.emit()
				"base":
					_hovered_base_key = str(hit.base_key)
					hovered_base_kind = str(hit.kind)
					_hover_grace = .35
					refresh()
			return true
	return false

func _refresh_layout() -> void:
	_calls.clear()
	_crews.clear()
	_stations.clear()
	_roads.clear()
	_hits.clear()
	_occupied.clear()
	_preview = {}
	_selected_option = {}
	_preview_id = -1
	_send_rect = Rect2()
	_options = []
	_station_members.clear()
	if sim == null:
		return
	for area in occlusions:
		_occupied.append(area.grow(7))
	var bounds_key: String = str(map_rect) + str(occlusions)
	if bounds_key != _layout_bounds_key:
		_layout_bounds_key = bounds_key
		_base_positions.clear()
		_pin_positions.clear()
		_base_origins.clear()
		_pin_origins.clear()
	_occupied.append(_legend_rect().grow(5))
	if selected_id >= 0 and sim.has_method("dispatch_options"):
		_options = sim.dispatch_options(selected_id)
		for option in _options:
			if int(option.get("unit_id", -1)) == selected_unit_id:
				_selected_option = option
		_preview = _selected_option
		if _preview.is_empty():
			for option in _options:
				if int(option.get("unit_id", -1)) == hovered_unit_id:
					_preview = option
		if not _preview.is_empty(): _preview_id = int(_preview.unit_id)
	var active: Array[Dictionary] = []
	for incident in sim.incidents:
		if incident.get("status", "") in ["active", "working"]:
			active.append(incident)
	
	active.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	for incident in active:
		var id: int = int(incident.id)
		var point: Vector2 = _world(incident.get("pos", Vector2.ZERO))
		if _pin_origins.get(id, Vector2(INF, INF)) != point:
			_pin_positions.erase(id)
			_pin_origins[id] = point
		var pin: Vector2 = _safe_pin(point + Vector2(0, -39))
		var footprint := Rect2(pin - Vector2(24, 22), Vector2(48, 59))
		if _pin_positions.has(id) and _rect_free(_pin_positions[id]):
			footprint = _pin_positions[id]
		else:
			footprint = _place_rect([footprint.position, footprint.position + Vector2(48, 0), footprint.position - Vector2(48, 0)], footprint.size)
			_pin_positions[id] = footprint
		pin = footprint.position + Vector2(24, 22)
		var estimate: Dictionary = sim.incident_estimate(id) if sim.has_method("incident_estimate") else {}
		_calls.append({"incident": incident, "point": point, "pin": pin, "rect": footprint, "card": Rect2(), "estimate": estimate, "expanded": id == selected_id or id == hovered_incident_id})
		_occupied.append(footprint.grow(5))
		_hits.append({"rect": footprint, "type": "call", "id": id})
	_layout_bases()
	_layout_call_cards()
	_layout_base_popups()
	_layout_mobile_crews()
	_layout_roads()
	
	if _can_send() and _send_rect.has_area():
		_hits.append({"rect": _send_rect, "type": "send", "id": selected_id})

func _layout_call_cards() -> void:
	var ordered: Array = _calls.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.incident.id) == selected_id and int(b.incident.id) != selected_id)
	for item in ordered:
		if not item.expanded: continue
		var selected: bool = int(item.incident.id) == selected_id
		var size := Vector2(250, 153) if selected else Vector2(225, 90)
		var pin: Vector2 = item.pin
		var choices: Array[Vector2] = [pin + Vector2(33, -24), pin + Vector2(-size.x - 33, -24), pin + Vector2(33, -size.y + 25), pin + Vector2(-size.x - 33, -size.y + 25), pin + Vector2(-size.x * .5, 45)]
		var rect: Rect2 = _place_rect(choices, size)
		item.card = rect
		_occupied.append(rect.grow(6))
		_hits.append({"rect": rect, "type": "call", "id": int(item.incident.id)})
		if selected: _send_rect = Rect2(rect.position + Vector2(9, 116), Vector2(rect.size.x - 18, 29))

func _layout_roads() -> void:
	if not sim.has_method("road_conditions"):
		return
	for zone in sim.road_conditions():
		var area := Rect2(_world(zone.get("position", Vector2.ZERO)), zone.get("size", Vector2.ZERO) * map_rect.size)
		area = area.intersection(map_rect)
		if area.size.x <= 0 or area.size.y <= 0:
			continue
		var speed: float = float(zone.get("speed_factor", 1.0))
		var label: String = "%s · %d%% speed · %ds" % [zone.get("name", "Slow road"), roundi(speed * 100), ceili(float(zone.get("remaining", 0)))]
		var width: float = minf(310, ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 26)
		var size := Vector2(width, 24)
		var choices: Array[Vector2] = [Vector2(area.position.x, area.position.y - 30), Vector2(area.position.x, area.end.y + 7), area.get_center() + Vector2(22, -38), Vector2(area.position.x - width - 8, area.get_center().y - 12), Vector2(area.end.x + 8, area.get_center().y - 12)]
		var rect: Rect2 = _place_rect(choices, size)
		_roads.append({"area": area, "rect": rect, "text": label})
		_occupied.append(rect.grow(5))

func _layout_bases() -> void:
	var groups: Array[Dictionary] = []
	for unit in sim.units:
		var kind: String = str(unit.kind)
		var home: Vector2 = unit.get("home", Vector2.ZERO)
		var group: Dictionary = {}
		for candidate in groups:
			if candidate.kind == kind and Vector2(candidate.home).distance_to(home) < .035:
				group = candidate
				break
		if group.is_empty():
			group = {"kind": kind, "home": home, "key": "%s:%d" % [kind, int(unit.id)], "units": []}
			groups.append(group)
		if unit.state in ["idle", "rest"] and Vector2(unit.pos).distance_to(home) < .04:
			group.units.append(unit)
			_station_members[int(unit.id)] = str(group.key)
	for group in groups:
		var point: Vector2 = _world(group.home)
		if _base_origins.get(group.key, Vector2(INF, INF)) != point:
			_base_positions.erase(group.key)
			_base_origins[group.key] = point
		var size := Vector2(54, 28)
		var choices: Array[Vector2] = [point + Vector2(14, 13), point + Vector2(-68, 13), point + Vector2(14, -40), point + Vector2(-68, -40)]
		var rect: Rect2 = _base_positions.get(group.key, Rect2())
		if not rect.has_area() or not _rect_free(rect):
			rect = _place_rect(choices, size)
			_base_positions[group.key] = rect
		var ready: int = 0
		var chosen: bool = false
		for unit in group.units:
			if _available(unit): ready += 1
			if int(unit.id) in [selected_unit_id, focused_unit_id]: chosen = true
		var expanded: bool = str(group.key) == _hovered_base_key or chosen or (role_filter == group.kind and not group.units.is_empty())
		_stations.append({"key": group.key, "kind": group.kind, "rect": rect, "popup": Rect2(), "point": point, "ready": ready, "units": group.units, "expanded": expanded})
		_occupied.append(rect.grow(5))
		_hits.append({"rect": rect, "type": "base", "base_key": group.key, "kind": group.kind})

func _available(unit: Dictionary) -> bool:
	if selected_id >= 0:
		for option in _options:
			if int(option.unit_id) == int(unit.id): return true
		return false
	return unit.get("state", "") in ["idle", "return"] and float(sim.elapsed) >= float(unit.get("divert_after", 0)) and float(sim.elapsed) >= float(unit.get("dispatch_guard_until", 0))

func _option(id: int) -> Dictionary:
	for option in _options:
		if int(option.unit_id) == id: return option
	return {}

func _rect_free(rect: Rect2) -> bool:
	for occupied in _occupied:
		if rect.intersects(occupied): return false
	return true

func _layout_base_popups() -> void:
	for station in _stations:
		if not station.expanded: continue
		var badge: Rect2 = station.rect
		var size := Vector2(175, 27 + maxi(1, station.units.size()) * 34)
		var choices: Array[Vector2] = [Vector2(badge.position.x, badge.end.y + 7), Vector2(badge.position.x, badge.position.y - size.y - 7), Vector2(badge.end.x + 7, badge.position.y), Vector2(badge.position.x - size.x - 7, badge.position.y)]
		var rect: Rect2 = _place_rect(choices, size)
		station.popup = rect
		_occupied.append(rect.grow(5))
		_hits.append({"rect": rect, "type": "popover", "base_key": station.key, "kind": station.kind})
		for index in range(station.units.size()):
			var unit: Dictionary = station.units[index]
			var row := Rect2(rect.position + Vector2(5, 25 + index * 34), Vector2(rect.size.x - 10, 30))
			_crews.append({"unit": unit, "rect": row, "point": _world(unit.pos), "base": true, "expanded": true, "marker": Rect2(), "base_key": station.key})
			_hits.append({"rect": row, "type": "unit", "id": int(unit.id), "base_key": station.key, "kind": station.kind})

func _layout_mobile_crews() -> void:
	for unit in sim.units:
		if _station_members.has(int(unit.id)): continue
		var id: int = int(unit.id)
		var point: Vector2 = _world(unit.pos)
		var marker := Rect2(_safe_pin(point) - Vector2(12, 12), Vector2(24, 24))
		marker = _place_rect([marker.position, marker.position + Vector2(0, 25), marker.position + Vector2(25, 0)], marker.size)
		_occupied.append(marker.grow(3))
		var relevant: bool = id in [selected_unit_id, hovered_unit_id, focused_unit_id] or (role_filter == str(unit.kind) and _available(unit))
		var rect: Rect2 = marker
		if relevant:
			var size := Vector2(174, 32)
			rect = _place_rect([marker.position + Vector2(31, -4), marker.position - Vector2(size.x + 7, 4), marker.position + Vector2(-60, 32)], size)
			_occupied.append(rect.grow(4))
			_hits.append({"rect": rect, "type": "unit", "id": id})
		_crews.append({"unit": unit, "rect": rect, "point": point, "base": false, "expanded": relevant, "marker": marker})
		_hits.append({"rect": marker, "type": "unit", "id": id})

func _safe_pin(point: Vector2) -> Vector2:
	var result: Vector2 = point.clamp(map_rect.position + Vector2(28, 28), map_rect.end - Vector2(28, 28))
	for pass_index in range(3):
		for area in occlusions:
			if area.grow(26).has_point(result):
				var expanded: Rect2 = area.grow(29)
				var candidates: Array[Vector2] = [Vector2(expanded.position.x, result.y), Vector2(expanded.end.x, result.y), Vector2(result.x, expanded.position.y), Vector2(result.x, expanded.end.y)]
				var best: Vector2 = result
				var distance: float = INF
				for candidate in candidates:
					if map_rect.grow(-26).has_point(candidate) and not _occluded(candidate) and candidate.distance_to(point) < distance:
						best = candidate
						distance = candidate.distance_to(point)
				result = best
	return result

func _place_rect(candidates: Array[Vector2], size: Vector2) -> Rect2:
	var chosen := Rect2(map_rect.position + Vector2(8, 8), size)
	var best_score: float = INF
	var chosen_overlap: float = INF
	var expanded: Array[Vector2] = candidates.duplicate()
	if not candidates.is_empty():
		for displacement in [Vector2(0, -84), Vector2(0, 84), Vector2(0, -150), Vector2(0, 150), Vector2(220, 0), Vector2(-220, 0)]:
			expanded.append(candidates[0] + displacement)
	for i in range(expanded.size()):
		var pos: Vector2 = expanded[i].clamp(map_rect.position + Vector2(7, 7), map_rect.end - size - Vector2(7, 7))
		var rect := Rect2(pos, size)
		var score: float = i * 6.0 + pos.distance_to(expanded[i]) * .6
		var overlap_area: float = 0.0
		for occupied in _occupied:
			if occupied.intersects(rect):
				var overlap: Rect2 = occupied.intersection(rect)
				score += overlap.get_area() * 9.0
				overlap_area += overlap.get_area()
		if score < best_score:
			best_score = score
			chosen = rect
			chosen_overlap = overlap_area
	
	
	if chosen_overlap > 0:
		var nearest_free: float = INF
		var anchor: Vector2 = candidates[0] if not candidates.is_empty() else map_rect.position
		for y in range(int(map_rect.position.y + 8), int(map_rect.end.y - size.y - 7), 36):
			for x in range(int(map_rect.position.x + 8), int(map_rect.end.x - size.x - 7), 48):
				var candidate := Rect2(Vector2(x, y), size)
				var available: bool = true
				for occupied in _occupied:
					if occupied.intersects(candidate):
						available = false
						break
				if available and candidate.position.distance_to(anchor) < nearest_free:
					nearest_free = candidate.position.distance_to(anchor)
					chosen = candidate
	return chosen

func _legend_rect() -> Rect2:
	return Rect2(map_rect.position + Vector2(map_rect.size.x - 288, 8), Vector2(280, 23))

func _panel(rect: Rect2, fill: Color, border: Color = Color("577c7c"), width: int = 1) -> void:
	draw_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color("09222c75"))
	draw_rect(rect, fill)
	draw_rect(rect, border, false, width)

func _text(value: String, pos: Vector2, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos.floor(), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _fit(value: String, width: float, size: int) -> String:
	var result: String = value
	if ThemeDB.fallback_font.get_string_size(result, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return result
	while result.length() > 1 and ThemeDB.fallback_font.get_string_size(result + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		result = result.left(-1)
	return result + "…"

func _draw() -> void:
	if sim == null:
		return
	_draw_roads()
	_draw_routes()
	_draw_road_labels()
	for item in _stations:
		_draw_station(item)
	for item in _calls:
		_draw_call(item)
	for item in _crews:
		_draw_crew(item)
	_draw_legend()

func _draw_roads() -> void:
	for item in _roads:
		var rect: Rect2 = item.area
		draw_rect(rect, Color(1.0, .66, .29, .15))
		draw_rect(rect, Color("daa763"), false, 1)
		for x in range(int(rect.position.x), int(rect.end.x), 18):
			draw_line(Vector2(x, rect.position.y), Vector2(minf(x + 6, rect.end.x), minf(rect.position.y + 6, rect.end.y)), Color("e6bf7990"), 2, false)

func _draw_road_labels() -> void:
	for item in _roads:
		var rect: Rect2 = item.rect
		var area: Rect2 = item.area
		var anchor: Vector2 = rect.get_center().clamp(area.position, area.end)
		draw_line(anchor, rect.get_center(), Color("e6bf79aa"), 1, false)
		_panel(rect, Color("493e2df5"), Color("b88f5d"))
		draw_rect(Rect2(rect.position + Vector2(6, 7), Vector2(8, 10)), GOLD)
		draw_line(rect.position + Vector2(6, 14), rect.position + Vector2(13, 8), INK, 2, false)
		_text(_fit(item.text, rect.size.x - 24, 11), rect.position + Vector2(20, 17), 11, GOLD)

func _remaining_route(unit: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = [_world(unit.get("pos", Vector2.ZERO))]
	var path: Array = unit.get("path", [])
	for i in range(int(unit.get("path_index", 0)), path.size()):
		result.append(_world(path[i]))
	return result

func _draw_routes() -> void:
	for unit in sim.units:
		var state: String = unit.get("state", "idle")
		if state not in ["travel", "return"]:
			continue
		var id: int = int(unit.id)
		var relevant: bool = id in [selected_unit_id, hovered_unit_id, focused_unit_id] or (int(unit.get("target", -1)) in [selected_id, hovered_incident_id] and int(unit.get("target", -1)) >= 0)
		if not relevant: continue
		var route: Array[Vector2] = _remaining_route(unit)
		var color: Color = ROLE_COLOR.get(unit.get("kind", "fire"), CREAM)
		if state == "return": color = Color(color, .55)
		_draw_route(route, color, false, int(unit.id) == selected_unit_id)
	if not _preview.is_empty():
		var route: Array[Vector2] = [_world(_preview.get("pos", Vector2.ZERO))]
		for point in _preview.get("path", []):
			route.append(_world(point))
		_draw_route(route, GOLD, true, true)

func _draw_route(points: Array[Vector2], color: Color, dashed: bool, emphasis: bool) -> void:
	if points.size() < 2:
		return
	for i in range(points.size() - 1):
		var start: Vector2 = points[i]
		var finish: Vector2 = points[i + 1]
		if start.distance_to(finish) < 1:
			continue
		var width: float = 3 if emphasis else 2
		draw_line(start, finish, Color("0c293caa"), width + 4, false)
		if dashed:
			var length: float = start.distance_to(finish)
			var offset: float = 0 if reduced_motion else fposmod(_elapsed * 9, 15)
			var t: float = offset
			while t < length:
				draw_line(start.lerp(finish, t / length), start.lerp(finish, minf(1, (t + 8) / length)), color, width, false)
				t += 15
		else:
			draw_line(start, finish, color, width, false)
			if start.distance_to(finish) > 55:
				var center: Vector2 = start.lerp(finish, .55)
				var direction: Vector2 = (finish - start).normalized()
				var perpendicular := Vector2(-direction.y, direction.x)
				draw_colored_polygon(PackedVector2Array([center + direction * 6, center - direction * 4 + perpendicular * 4, center - direction * 4 - perpendicular * 4]), color)
	var origin: Vector2 = points[0]
	draw_rect(Rect2(origin - Vector2(4, 4), Vector2(8, 8)), INK)
	draw_rect(Rect2(origin - Vector2(2, 2), Vector2(4, 4)), color)

func _draw_station(item: Dictionary) -> void:
	var rect: Rect2 = item.rect
	var color: Color = ROLE_COLOR.get(item.kind, CREAM)
	var point: Vector2 = item.point
	draw_line(point, rect.get_center(), Color(color, .32), 1, false)
	var bright: bool = item.expanded or role_filter == item.kind
	_panel(rect, Color("234851f0") if bright else Color("17363dda"), color if bright else Color("5a7473"), 2 if bright else 1)
	_role_icon(str(item.kind), rect.position + Vector2(14, 14), color)
	_text(str(item.ready), rect.position + Vector2(32, 19), 15, CREAM if int(item.ready) > 0 else MUTED)
	if not item.expanded: return
	var popup: Rect2 = item.popup
	draw_line(rect.get_center(), popup.get_center(), Color(color, .5), 1, false)
	_panel(popup, Color("173741f8"), color)
	_text("%s CREWS" % ROLE_SHORT.get(item.kind, "BASE"), popup.position + Vector2(9, 17), 10, color)
	_text("%d READY" % int(item.ready), popup.position + Vector2(111, 17), 9, MUTED)
	if item.units.is_empty():
		_text("Crews are on the road", popup.position + Vector2(9, 45), 12, MUTED)

func _role_icon(kind: String, center: Vector2, color: Color) -> void:
	match kind:
		"medic":
			draw_rect(Rect2(center + Vector2(-2, -7), Vector2(4, 14)), color)
			draw_rect(Rect2(center + Vector2(-7, -2), Vector2(14, 4)), color)
		"engineer":
			draw_line(center + Vector2(-5, 6), center + Vector2(4, -3), color, 4, false)
			draw_line(center + Vector2(4, -3), center + Vector2(1, -7), color, 3, false)
			draw_line(center + Vector2(4, -3), center + Vector2(8, -1), color, 3, false)
		_:
			draw_colored_polygon(PackedVector2Array([center + Vector2(1, -8), center + Vector2(6, -1), center + Vector2(5, 6), center + Vector2(-5, 6), center + Vector2(-6, 0), center + Vector2(-2, -4), center + Vector2(-1, 1)]), color)
			draw_rect(Rect2(center + Vector2(-1, 1), Vector2(3, 5)), INK)

func _pin_color(incident: Dictionary) -> Color:
	if not bool(incident.get("discovered", true)):
		return Color("c3cbd8")
	return {"fire": ROLE_COLOR.fire, "medical": ROLE_COLOR.medic, "power": ROLE_COLOR.engineer, "flood": Color("95cee5")}.get(incident.get("kind", ""), CREAM)

func _draw_pin(point: Vector2, incident: Dictionary) -> void:
	var selected: bool = int(incident.id) == selected_id
	var color: Color = _pin_color(incident)
	var known: bool = bool(incident.get("discovered", true))
	var severity: int = int(incident.get("severity", 1)) if known else 1
	if selected:
		draw_rect(Rect2(point - Vector2(24, 24), Vector2(48, 48)), Color("f4daa78c"), false, 2)
	var half: float = 17
	var shape := PackedVector2Array()
	if severity == 2:
		shape = PackedVector2Array([point + Vector2(0, -22), point + Vector2(22, 0), point + Vector2(0, 22), point + Vector2(-22, 0)])
	elif severity >= 3:
		shape = PackedVector2Array([point + Vector2(-10, -21), point + Vector2(10, -21), point + Vector2(21, -10), point + Vector2(21, 10), point + Vector2(10, 21), point + Vector2(-10, 21), point + Vector2(-21, 10), point + Vector2(-21, -10)])
	else:
		shape = PackedVector2Array([point + Vector2(-half, -half), point + Vector2(half, -half), point + Vector2(half, half), point + Vector2(-half, half)])
	draw_colored_polygon(shape, color)
	var closed: PackedVector2Array = shape.duplicate()
	closed.append(shape[0])
	draw_polyline(closed, INK, 3, false)
	var number: String = "%02d" % int(incident.id)
	var text_width: float = ThemeDB.fallback_font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_text(number, point + Vector2(-text_width * .5, 6), 16, INK)
	if not known:
		draw_rect(Rect2(point + Vector2(11, -23), Vector2(16, 17)), INK)
		_text("?", point + Vector2(15, -10), 13, CREAM)
	else:
		for i in range(severity):
			draw_rect(Rect2(point + Vector2(-severity * 3 + i * 6, 11), Vector2(4, 3)), INK)

func _draw_call(item: Dictionary) -> void:
	var incident: Dictionary = item.incident
	var rect: Rect2 = item.card
	var pin: Vector2 = item.pin
	var point: Vector2 = item.point
	var known: bool = bool(incident.get("discovered", true))
	var selected: bool = int(incident.id) == selected_id
	var hovered: bool = int(incident.id) == hovered_incident_id
	var color: Color = _pin_color(incident)
	draw_line(point, pin, Color("e1d5af99"), 1, false)
	draw_rect(Rect2(point - Vector2(3, 3), Vector2(6, 6)), INK, false, 1)
	_draw_pin(pin, incident)
	var deadline: float = maxf(0, float(incident.get("deadline", 0)))
	var estimate: Dictionary = item.estimate
	var critical: bool = deadline < 20 or (bool(estimate.get("known", false)) and float(estimate.get("finish_eta", -1)) >= 0 and float(estimate.get("margin", 0)) < 0)
	var timer_rect := Rect2(pin + Vector2(-22, 21), Vector2(44, 17))
	draw_rect(timer_rect, INK)
	_text("%ds%s" % [ceili(deadline), "!" if critical else ""], timer_rect.position + Vector2(5, 13), 11, RED if critical else CREAM)
	if not item.expanded: return
	draw_line(pin, rect.get_center(), Color(color, .7), 1, false)
	_panel(rect, Color("173741f5"), GOLD if selected else color if hovered else Color("577b7c"), 2 if selected else 1)
	draw_rect(Rect2(rect.position + Vector2(0, 0), Vector2(3, rect.size.y)), color)
	_text(_fit(str(incident.get("name", "Incoming report")), rect.size.x - 17, 14), rect.position + Vector2(9, 18), 14, CREAM)
	var detail: String = "%ds · %d neighbors" % [ceili(deadline), int(incident.get("people", 0))] if known else "%ds · UNVERIFIED REPORT" % ceili(deadline)
	_text(detail, rect.position + Vector2(9, 34), 12, RED if deadline < 20 else MUTED)
	_text(_fit(_team_status(incident), rect.size.x - 16, 12), rect.position + Vector2(9, 49), 12, color)
	if selected and not _preview.is_empty():
		var name: String = str(_preview.get("name", "Crew"))
		var prefix: String = "PLAN" if _preview_id == selected_unit_id else "PREVIEW"
		var preview_text: String = "%s  %s · %ds to scene" % [prefix, name, ceili(float(_preview.get("eta", 0)))]
		_text(_fit(preview_text, rect.size.x - 16, 12), rect.position + Vector2(9, 76), 12, GOLD)
		_text(_fit(_risk_text(_preview, true), rect.size.x - 16, 11), rect.position + Vector2(9, 94), 11, _risk_color(_preview))
		_text("Route locked · choose another crew to compare" if _preview_id == selected_unit_id else "Click this crew to choose their route", rect.position + Vector2(9, 109), 10, MUTED)
	elif selected:
		_text(_fit(_risk_text(estimate, false), rect.size.x - 16, 11), rect.position + Vector2(9, 76), 11, _risk_color(estimate))
		var underway: bool = float(estimate.get("finish_eta", -1)) >= 0 and not bool(estimate.get("team_incomplete", true))
		_text("Crew response underway" if underway else "Hover a base or crew to compare routes", rect.position + Vector2(9, 94), 11, MUTED)
		_text("Follow route and rescue progress" if underway else "1 / 2 / 3 highlights each crew type", rect.position + Vector2(9, 109), 10, MUTED)
	else:
		_text(_fit(_risk_text(estimate, false), rect.size.x - 16, 11), rect.position + Vector2(9, 65), 11, _risk_color(estimate))
		_text("Click to plan a response", rect.position + Vector2(9, 81), 10, MUTED)
	if selected:
		draw_line(rect.position + Vector2(9, 59), rect.position + Vector2(rect.size.x - 9, 59), Color("577b7c"), 1, false)
		var active: bool = _can_send()
		var caption: String = "CHOOSE A CREW ON THE MAP"
		if float(estimate.get("finish_eta", -1)) >= 0 and not bool(estimate.get("team_incomplete", true)): caption = "CREW RESPONSE UNDERWAY"
		if not _selected_option.is_empty(): caption = "SEND %s · ENTER" % str(_selected_option.get("name", "CREW")).to_upper() if active else "DISPATCH UNAVAILABLE"
		draw_rect(_send_rect, GREEN if active else Color("264b55"))
		var caption_width: float = ThemeDB.fallback_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_text(caption, _send_rect.position + Vector2((_send_rect.size.x - caption_width) * .5, 19), 11, INK if active else MUTED)
	var progress: float = float(incident.get("progress", 0))
	if progress > 0:
		draw_rect(Rect2(rect.position + Vector2(1, rect.size.y - 3), Vector2((rect.size.x - 2) * progress, 2)), GREEN)

func _team_status(incident: Dictionary) -> String:
	if not bool(incident.get("discovered", true)):
		return "Q to scout · unconfirmed need"
	var missing: Array[String] = []
	var en_route: int = 0
	var working: int = 0
	for kind in ROLES:
		var count: int = int(incident.get("needs", {}).get(kind, 0))
		for unit in sim.units:
			if unit.get("target", -1) == incident.id and unit.get("kind", "") == kind and unit.get("state", "") in ["travel", "working"] and bool(unit.get("assignment_suitable", true)) and int(incident.get("needs", {}).get(kind, 0)) > 0:
				count -= 1
				if unit.state == "travel": en_route += 1
				else: working += 1
		if count > 0:
			missing.append("%s ×%d" % [ROLE_SHORT[kind], count])
	if not missing.is_empty():
		return "Need " + " · ".join(missing)
	if en_route > 0:
		return "%d crew%s arriving%s" % [en_route, "s" if en_route > 1 else "", " · %d working" % working if working > 0 else ""]
	return "CREWS AT WORK · %d%%" % roundi(float(incident.get("progress", 0)) * 100)

func _risk_text(estimate: Dictionary, preview: bool) -> String:
	if estimate.is_empty():
		return "Awaiting a response plan"
	if not bool(estimate.get("known", true)):
		return "Unverified · arrival ETA only"
	if preview and not bool(estimate.get("suitable", true)):
		return "Wrong crew · inspection trip only"
	if bool(estimate.get("team_incomplete", false)):
		return "Another crew needed before rescue" if preview else "Awaiting a complete team"
	var margin: float = float(estimate.get("margin", -1))
	var finish: float = float(estimate.get("finish_eta", -1))
	if finish < 0:
		return "Assign the required team"
	return "%s %+ds margin · finish %ds" % ["Plan:" if preview else "Est:", floori(margin), ceili(finish)]

func _risk_color(estimate: Dictionary) -> Color:
	if estimate.is_empty() or not bool(estimate.get("known", true)) or bool(estimate.get("team_incomplete", false)) or float(estimate.get("finish_eta", -1)) < 0:
		return RED if bool(estimate.get("known", false)) and not bool(estimate.get("suitable", true)) else MUTED
	if not bool(estimate.get("suitable", true)):
		return RED
	var margin: float = float(estimate.get("margin", 0))
	return RED if margin < 0 else GOLD if margin < 10 else GREEN

func _draw_crew(item: Dictionary) -> void:
	var unit: Dictionary = item.unit
	var rect: Rect2 = item.rect
	var color: Color = ROLE_COLOR.get(unit.get("kind", "fire"), CREAM)
	var selected: bool = int(unit.id) == selected_unit_id
	var hovered: bool = int(unit.id) == hovered_unit_id
	var focused: bool = int(unit.id) == focused_unit_id
	var available: bool = _available(unit)
	if not bool(item.base):
		var marker: Rect2 = item.marker
		var center: Vector2 = marker.get_center()
		if center.distance_to(item.point) > 12: draw_line(item.point, center, Color(color, .38), 1, false)
		var highlighted: bool = selected or hovered or focused or (role_filter == str(unit.kind) and available)
		draw_rect(marker.grow(2), GOLD if selected or focused else color if highlighted else Color("16333a99"), false, 2 if highlighted else 1)
		draw_rect(marker.grow(-2), Color("153b45d9"))
		_role_icon(str(unit.kind), center, color if available or highlighted else Color(color, .65))
		if not item.expanded: return
		draw_line(center, rect.get_center(), Color(color, .45), 1, false)
	_panel(rect, Color("365a60") if selected else Color("1b414b"), GOLD if selected or focused else color if hovered else Color("547579"), 2 if selected or focused else 1)
	draw_rect(Rect2(rect.position + Vector2(5, 8), Vector2(3, 12)), color)
	var name: String = str(unit.get("crew_name", unit.get("name", "Crew")))
	var state: String = unit.get("state", "idle")
	var status: String = ""
	if state in ["travel", "return"]:
		var eta: float = sim.unit_eta(unit) if sim.has_method("unit_eta") else float(unit.get("remaining", 0))
		status = "#%02d · %ds" % [int(unit.get("target", 0)), ceili(eta)] if state == "travel" else "HOME %ds" % ceili(eta)
	elif state == "working":
		status = "#%02d WORKING" % int(unit.get("target", 0))
	elif state == "rest":
		status = "REST"
	else:
		var option: Dictionary = _option(int(unit.id))
		status = "%ds arrival" % ceili(float(option.eta)) if not option.is_empty() else "READY" if available else "WAIT"
	var status_width: float = ThemeDB.fallback_font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	_text(_fit(name, rect.size.x - status_width - 26, 13), rect.position + Vector2(12, 20), 13, CREAM if available or state in ["travel", "working"] else MUTED)
	_text(status, rect.position + Vector2(rect.size.x - status_width - 7, 20), 10, GOLD if selected else MUTED)

func _draw_legend() -> void:
	var rect: Rect2 = _legend_rect()
	if _occluded(rect.get_center()):
		return
	_panel(rect, Color("173640e6"), Color("496b72"))
	if selected_id < 0:
		_text("CLICK A NUMBERED CALL TO PLAN", rect.position + Vector2(15, 16), 10, MUTED)
	elif _preview.is_empty():
		_text("HOVER A BASE · CHOOSE A SPECIFIC CREW", rect.position + Vector2(10, 16), 10, MUTED)
	else:
		draw_line(rect.position + Vector2(8, 12), rect.position + Vector2(29, 12), GREEN, 2, false)
		_text("COMMITTED", rect.position + Vector2(35, 16), 9, MUTED)
		for i in range(3):
			draw_line(rect.position + Vector2(128 + i * 8, 12), rect.position + Vector2(132 + i * 8, 12), GOLD, 2, false)
		_text("SELECTED ROUTE" if selected_unit_id >= 0 else "HOVER PREVIEW", rect.position + Vector2(158, 16), 9, GOLD)
