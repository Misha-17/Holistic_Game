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
const ROLES: Array[String] = ["fire", "medic", "engineer", "police"]
const ROLE_COLOR := {"fire": Color("f2a27f"), "medic": Color("9be0c4"), "engineer": Color("f1cf7e"), "police": Color("aab4f7")}
const ROLE_SHORT := {"fire": "FIRE", "medic": "MED", "engineer": "ENG", "police": "POL"}

var sim = null
var options_provider: Callable
var selected_id: int = -1
var selected_unit_id: int = -1
var tutorial_active: bool = false
var occlusions: Array[Rect2] = []
var map_rect := Rect2(24, 146, 1064, 632)
# The part of the map that is actually visible; markers are kept inside it.
var view_rect := Rect2(24, 146, 1064, 632)
# Co-op: which player commands the departments you don't (kind -> "P2").
var owner_labels: Dictionary = {}
var reduced_motion: bool = false
var hovered_incident_id: int = -1
var hovered_unit_id: int = -1
var hovered_base_kind: String = ""
var role_filter: String = ""
var focused_unit_id: int = -1
var dispatch_enabled: bool = true
# Departments this player commands. Other departments stay visible but are drawn dimmer.
var owned_kinds: Array = ["fire", "medic", "engineer", "police"]

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
var _preview_target: int = -1

# Heavier, outlined text for everything that has to be read at a glance on the map.
var _bold: FontVariation
const KEY_OF := {"fire": "1", "medic": "2", "engineer": "3", "police": "4"}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Plain font (artificial bolding looked broken with this font's rendering mode).
	_bold = FontVariation.new()
	_bold.base_font = ThemeDB.fallback_font

func _btext(value: String, pos: Vector2, size: int, color: Color, centered: bool = false) -> void:
	var at: Vector2 = pos
	if centered:
		at.x -= _bold.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * .5
	draw_string_outline(_bold, at.floor(), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(INK, .95))
	draw_string(_bold, at.floor(), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

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
	else:
		_follow_moving_crews()
	queue_redraw()

# The full layout is rebuilt 10x a second; vehicles on the road are moved every
# frame in between so they glide instead of stepping.
func _follow_moving_crews() -> void:
	for item in _crews:
		if bool(item.get("base", true)): continue
		var unit: Dictionary = _unit(int(item.unit.id))
		if unit.is_empty(): continue
		var point: Vector2 = _world(unit.pos)
		var marker := Rect2(point - Vector2(15, 15), Vector2(30, 30))
		item.unit = unit
		item.point = point
		item.rect = marker
		item.marker = marker
		if item.has("hit"): item.hit.rect = marker.grow(8)

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
				# The game decides: with a crew selected, clicking a call sends it there.
				"call": incident_selected.emit(int(hit.id))
				"unit": unit_selected.emit(int(hit.id))
				"base":
					var pick: int = _station_pick(str(hit.base_key))
					if pick >= 0:
						unit_selected.emit(pick)
					elif not (hit.get("units", []) as Array).is_empty():
						unit_selected.emit(int(hit.units[0]))
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
	# Route preview: the selected crew to the call under the mouse (or the selected call).
	var target: int = hovered_incident_id if selected_unit_id >= 0 and hovered_incident_id >= 0 else selected_id
	_preview_target = target
	if target >= 0 and sim.has_method("dispatch_options"):
		_options = options_provider.call(target) if options_provider.is_valid() else sim.dispatch_options(target)
		for option in _options:
			if int(option.get("unit_id", -1)) == selected_unit_id:
				_selected_option = option
		_preview = _selected_option
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
		var footprint := Rect2(pin - Vector2(34, 54), Vector2(68, 112))
		if _pin_positions.has(id) and _rect_free(_pin_positions[id]):
			footprint = _pin_positions[id]
		else:
			footprint = _place_rect([footprint.position, footprint.position + Vector2(70, 0), footprint.position - Vector2(70, 0), footprint.position + Vector2(0, 80)], footprint.size)
			_pin_positions[id] = footprint
		pin = footprint.position + Vector2(34, 54)
		var estimate: Dictionary = sim.incident_estimate(id) if sim.has_method("incident_estimate") else {}
		_calls.append({"incident": incident, "point": point, "pin": pin, "rect": footprint, "card": Rect2(), "estimate": estimate, "expanded": id == selected_id or id == hovered_incident_id})
		_occupied.append(footprint.grow(5))
		_hits.append({"rect": footprint, "type": "call", "id": id})
	_layout_bases()
	_layout_call_cards()
	_layout_mobile_crews()
	_layout_roads()

func _layout_call_cards() -> void:
	var ordered: Array = _calls.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.incident.id) == selected_id and int(b.incident.id) != selected_id)
	for item in ordered:
		if not item.expanded: continue
		var size := Vector2(262, 82)
		var pin: Vector2 = item.pin
		var choices: Array[Vector2] = [pin + Vector2(34, -26), pin + Vector2(-size.x - 34, -26), pin + Vector2(34, -size.y + 20), pin + Vector2(-size.x - 34, -size.y + 20), pin + Vector2(-size.x * .5, 48)]
		var rect: Rect2 = _place_rect(choices, size)
		item.card = rect
		_occupied.append(rect.grow(6))
		_hits.append({"rect": rect, "type": "call", "id": int(item.incident.id)})

func _layout_roads() -> void:
	if not sim.has_method("road_conditions"):
		return
	for zone in sim.road_conditions():
		var area := Rect2(_world(zone.get("position", Vector2.ZERO)), zone.get("size", Vector2.ZERO) * map_rect.size)
		area = area.intersection(view_rect)
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
		var size := Vector2(58, 32)
		var choices: Array[Vector2] = [point + Vector2(14, 13), point + Vector2(-72, 13), point + Vector2(14, -44), point + Vector2(-72, -44)]
		var rect: Rect2 = _base_positions.get(group.key, Rect2())
		if not rect.has_area() or not _rect_free(rect):
			rect = _place_rect(choices, size)
			_base_positions[group.key] = rect
		var ready: int = 0
		var chosen: bool = false
		var pick: int = -1
		var pick_eta: float = INF
		var ids: Array = []
		for unit in group.units:
			ids.append(int(unit.id))
			if _available(unit):
				ready += 1
				var option: Dictionary = _option(int(unit.id))
				var eta: float = float(option.get("eta", 0.0)) if not option.is_empty() else float(unit.get("fatigue", 0.0))
				if eta < pick_eta:
					pick_eta = eta
					pick = int(unit.id)
			if int(unit.id) == selected_unit_id: chosen = true
		_stations.append({"key": group.key, "kind": group.kind, "rect": rect, "popup": Rect2(), "point": point, "ready": ready, "units": group.units, "expanded": false, "pick": pick, "chosen": chosen})
		_occupied.append(rect.grow(5))
		_hits.append({"rect": rect.grow(5), "type": "base", "base_key": group.key, "kind": group.kind, "units": ids})

# The crew a click on a station picks: the fastest free crew there (or the most rested one).

func _station_pick(key: String) -> int:
	for station in _stations:
		if station.key == key:
			return int(station.get("pick", -1))
	return -1

func _available(unit: Dictionary) -> bool:
	return unit.get("state", "") in ["idle", "return"] and float(sim.elapsed) >= float(unit.get("divert_after", 0)) and float(sim.elapsed) >= float(unit.get("dispatch_guard_until", 0))

func _option(id: int) -> Dictionary:
	for option in _options:
		if int(option.unit_id) == id: return option
	return {}

func _rect_free(rect: Rect2) -> bool:
	for occupied in _occupied:
		if rect.intersects(occupied): return false
	return true



func _layout_mobile_crews() -> void:
	# Vehicles on the road: the click target sits exactly on the moving vehicle and is generous.
	for unit in sim.units:
		if _station_members.has(int(unit.id)): continue
		var id: int = int(unit.id)
		var point: Vector2 = _world(unit.pos)
		var marker := Rect2(point - Vector2(15, 15), Vector2(30, 30))
		var hit := {"rect": marker.grow(8), "type": "unit", "id": id}
		_crews.append({"unit": unit, "rect": marker, "point": point, "base": false, "expanded": false, "marker": marker, "hit": hit})
		_hits.append(hit)

func _safe_pin(point: Vector2) -> Vector2:
	var result: Vector2 = point.clamp(view_rect.position + Vector2(28, 50), view_rect.end - Vector2(28, 50))
	for pass_index in range(3):
		for area in occlusions:
			if area.grow(26).has_point(result):
				var expanded: Rect2 = area.grow(29)
				var candidates: Array[Vector2] = [Vector2(expanded.position.x, result.y), Vector2(expanded.end.x, result.y), Vector2(result.x, expanded.position.y), Vector2(result.x, expanded.end.y)]
				var best: Vector2 = result
				var distance: float = INF
				for candidate in candidates:
					if view_rect.grow(-26).has_point(candidate) and not _occluded(candidate) and candidate.distance_to(point) < distance:
						best = candidate
						distance = candidate.distance_to(point)
				result = best
	return result

func _place_rect(candidates: Array[Vector2], size: Vector2) -> Rect2:
	var chosen := Rect2(view_rect.position + Vector2(8, 8), size)
	var best_score: float = INF
	var chosen_overlap: float = INF
	var expanded: Array[Vector2] = candidates.duplicate()
	if not candidates.is_empty():
		for displacement in [Vector2(0, -84), Vector2(0, 84), Vector2(0, -150), Vector2(0, 150), Vector2(220, 0), Vector2(-220, 0)]:
			expanded.append(candidates[0] + displacement)
	for i in range(expanded.size()):
		var pos: Vector2 = expanded[i].clamp(view_rect.position + Vector2(7, 7), view_rect.end - size - Vector2(7, 7))
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
		var anchor: Vector2 = candidates[0] if not candidates.is_empty() else view_rect.position
		for y in range(int(view_rect.position.y + 8), int(view_rect.end.y - size.y - 7), 36):
			for x in range(int(view_rect.position.x + 8), int(view_rect.end.x - size.x - 7), 48):
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
		var relevant: bool = id in [hovered_unit_id, focused_unit_id] or (int(unit.get("target", -1)) in [selected_id, hovered_incident_id] and int(unit.get("target", -1)) >= 0)
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
	if not _owned(str(item.kind)):
		color = Color(color.darkened(.25), .75)
	var point: Vector2 = item.point
	draw_line(point, rect.get_center(), Color(color, .32), 1, false)
	var chosen: bool = bool(item.get("chosen", false))
	var hovered: bool = str(item.key) == _hovered_base_key
	var bright: bool = chosen or hovered or role_filter == item.kind
	_panel(rect, Color("234851f0") if bright else Color("17363dda"), GOLD if chosen else (color if bright else Color("5a7473")), 3 if chosen else (2 if bright else 1))
	_role_icon(str(item.kind), rect.position + Vector2(16, 16), color)
	_text(str(item.ready), rect.position + Vector2(34, 22), 17, CREAM if int(item.ready) > 0 else MUTED)
	if chosen:
		var pulse: float = 0.0 if reduced_motion else (sin(_elapsed * 6.0) + 1.0) * 2.0
		draw_rect(rect.grow(4 + pulse), GOLD, false, 2)

func _owned(kind: String) -> bool:
	return owned_kinds.is_empty() or owned_kinds.has(kind)

func _role_icon(kind: String, center: Vector2, color: Color, k: float = 1.0) -> void:
	match kind:
		"police":
			draw_rect(Rect2(center + Vector2(-6, -7) * k, Vector2(12, 9) * k), color)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-6, 2) * k, center + Vector2(6, 2) * k, center + Vector2(0, 8) * k]), color)
			draw_rect(Rect2(center + Vector2(-2, -4) * k, Vector2(4, 4) * k), INK if color != INK else CREAM)
		"medic":
			draw_rect(Rect2(center + Vector2(-2, -7) * k, Vector2(4, 14) * k), color)
			draw_rect(Rect2(center + Vector2(-7, -2) * k, Vector2(14, 4) * k), color)
		"engineer":
			draw_line(center + Vector2(-5, 6) * k, center + Vector2(4, -3) * k, color, 4 * k, false)
			draw_line(center + Vector2(4, -3) * k, center + Vector2(1, -7) * k, color, 3 * k, false)
			draw_line(center + Vector2(4, -3) * k, center + Vector2(8, -1) * k, color, 3 * k, false)
		_:
			draw_colored_polygon(PackedVector2Array([center + Vector2(1, -8) * k, center + Vector2(6, -1) * k, center + Vector2(5, 6) * k, center + Vector2(-5, 6) * k, center + Vector2(-6, 0) * k, center + Vector2(-2, -4) * k, center + Vector2(-1, 1) * k]), color)
			draw_rect(Rect2(center + Vector2(-1, 1) * k, Vector2(3, 5) * k), INK if color != INK else CREAM)

func _pin_color(incident: Dictionary) -> Color:
	if not bool(incident.get("discovered", true)):
		return Color("c3cbd8")
	return {"fire": ROLE_COLOR.fire, "medical": ROLE_COLOR.medic, "power": ROLE_COLOR.engineer, "flood": Color("95cee5"), "police": ROLE_COLOR.police}.get(incident.get("kind", ""), CREAM)

func _draw_pin(point: Vector2, incident: Dictionary) -> void:
	var selected: bool = int(incident.id) == selected_id
	var color: Color = _pin_color(incident)
	var known: bool = bool(incident.get("discovered", true))
	var severity: int = int(incident.get("severity", 1)) if known else 1
	var deadline: float = maxf(0.0, float(incident.get("deadline", 0)))
	var ratio: float = clampf(deadline / maxf(1.0, float(incident.get("max_deadline", deadline))), 0.0, 1.0)
	var urgent: bool = deadline < 20.0
	var waiting: bool = _missing(incident) > 0
	var age: float = float(sim.elapsed) - float(incident.get("created_at", -99.0))
	# Attention pulses, readable from across the map:
	# new calls flash twice a second, calls still missing crews pulse, and they turn red and fast when time runs low.
	if not reduced_motion:
		if age >= 0.0 and age < 5.0:
			var wave: float = fposmod(age * 2.0, 1.0)
			draw_arc(point, 30 + wave * 44, 0, TAU, 40, Color(GOLD, 1.0 - wave), 5, false)
		elif urgent and waiting:
			var wave: float = fposmod(_elapsed * 1.4, 1.0)
			draw_arc(point, 30 + wave * 60, 0, TAU, 40, Color(RED, 1.0 - wave), 6, false)
			draw_arc(point, 30 + fposmod(wave + .5, 1.0) * 60, 0, TAU, 40, Color(RED, (1.0 - fposmod(wave + .5, 1.0)) * .6), 3, false)
		elif waiting:
			var wave: float = fposmod(_elapsed * 0.45 + int(incident.id) * 0.37, 1.0)
			draw_arc(point, 30 + wave * 34, 0, TAU, 36, Color(color, 0.75 * (1.0 - wave)), 3, false)
	# Shadow + countdown ring around the marker.
	draw_circle(point + Vector2(3, 4), 30, Color(0, 0, 0, .35))
	draw_circle(point, 30, Color(INK, .92))
	var ring: Color = GREEN if ratio > .5 else (GOLD if ratio > .25 else RED)
	draw_arc(point, 26, -PI / 2, -PI / 2 + TAU * ratio, 48, ring, 6, false)
	var k: float = 1.0
	if urgent and waiting and not reduced_motion:
		k = 1.0 + 0.07 * sin(_elapsed * 12.0)
	var half: float = 15 * k
	var shape := PackedVector2Array()
	if severity == 2:
		shape = PackedVector2Array([point + Vector2(0, -19) * k, point + Vector2(19, 0) * k, point + Vector2(0, 19) * k, point + Vector2(-19, 0) * k])
	elif severity >= 3:
		shape = PackedVector2Array([point + Vector2(-8, -18) * k, point + Vector2(8, -18) * k, point + Vector2(18, -8) * k, point + Vector2(18, 8) * k, point + Vector2(8, 18) * k, point + Vector2(-8, 18) * k, point + Vector2(-18, 8) * k, point + Vector2(-18, -8) * k])
	else:
		shape = PackedVector2Array([point + Vector2(-half, -half), point + Vector2(half, -half), point + Vector2(half, half), point + Vector2(-half, half)])
	draw_colored_polygon(shape, color)
	var closed: PackedVector2Array = shape.duplicate()
	closed.append(shape[0])
	draw_polyline(closed, CREAM, 2, false)
	if known:
		_role_icon(_incident_icon(str(incident.get("kind", ""))), point, INK, 1.3)
	else:
		_btext("?", point + Vector2(0, 9), 26, INK, true)
	if selected:
		draw_arc(point, 36, 0, TAU, 40, CREAM, 3, false)
	# Time left, big and outlined, above the marker.
	_btext("%d" % ceili(deadline), point + Vector2(0, -42), 21, RED if urgent else CREAM, true)
	if age >= 0.0 and age < 6.0:
		_btext("NEW", point + Vector2(28, -24), 13, GOLD)

# How many crews this call still needs (unknown calls count as needing help until a crew arrives).
func _missing(incident: Dictionary) -> int:
	if not bool(incident.get("discovered", true)):
		return 0 if not (incident.get("assigned", []) as Array).is_empty() else 1
	var count: int = 0
	for kind in ROLES:
		count += maxi(0, int(incident.get("needs", {}).get(kind, 0)) - _assigned(incident, kind))
	return count

func _incident_icon(kind: String) -> String:
	return {"fire": "fire", "medical": "medic", "flood": "engineer", "power": "engineer", "police": "police"}.get(kind, "")

# Needed crews as a row of icons under the pin; a crew already sent shows as a filled chip.
func _draw_needs(center: Vector2, incident: Dictionary) -> void:
	if not bool(incident.get("discovered", true)):
		return
	var needs: Dictionary = incident.get("needs", {})
	var kinds: Array[String] = []
	for kind in ROLES:
		if int(needs.get(kind, 0)) > 0: kinds.append(kind)
	var width: float = kinds.size() * 22.0
	var x: float = center.x - width * .5
	for kind in kinds:
		var covered: bool = _assigned(incident, kind) >= int(needs.get(kind, 0))
		var chip := Rect2(Vector2(x + 1, center.y), Vector2(20, 20))
		draw_rect(chip, ROLE_COLOR[kind] if covered else INK)
		draw_rect(chip, ROLE_COLOR[kind], false, 2)
		_role_icon(kind, chip.get_center(), INK if covered else ROLE_COLOR[kind])
		x += 22

func _assigned(incident: Dictionary, kind: String) -> int:
	var count: int = 0
	for unit in sim.units:
		if int(unit.get("target", -1)) == int(incident.id) and unit.get("kind", "") == kind and unit.get("state", "") in ["travel", "working"] and bool(unit.get("assignment_suitable", true)):
			count += 1
	return count

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
	_draw_needs(pin + Vector2(0, 34), incident)
	var progress: float = float(incident.get("progress", 0))
	if progress > 0:
		draw_rect(Rect2(pin + Vector2(-22, 57), Vector2(44, 4)), INK)
		draw_rect(Rect2(pin + Vector2(-22, 57), Vector2(44 * progress, 4)), GREEN)
	if not item.expanded: return
	draw_line(pin, rect.get_center(), Color(color, .7), 1, false)
	_panel(rect, Color("173741f5"), GOLD if selected else color, 2 if selected else 1)
	draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), color)
	_btext(_fit(str(incident.get("name", "Incoming report")), rect.size.x - 20, 17), rect.position + Vector2(10, 23), 17, CREAM)
	# Second line: what a crew would achieve here, or what is still missing.
	var line: String = ""
	var line_color: Color = MUTED
	if not known:
		line = "Unknown needs · Q to scout"
		line_color = GOLD
	elif int(_preview_target) == int(incident.id) and not _preview.is_empty():
		var name: String = str(_preview.get("name", "Crew"))
		if not bool(_preview.get("suitable", true)):
			line = "%s can't help here" % name
			line_color = RED
		else:
			line = "%s: %s" % [name, _margin_text(_preview)]
			line_color = _risk_color(_preview)
	else:
		line = _margin_text(item.estimate) if float(item.estimate.get("finish_eta", -1)) >= 0 else _team_status(incident)
		line_color = _risk_color(item.estimate) if float(item.estimate.get("finish_eta", -1)) >= 0 else color
	_btext(_fit(line, rect.size.x - 20, 15), rect.position + Vector2(10, 48), 15, line_color)
	var hint: String = ""
	if selected_unit_id >= 0 and hovered and known:
		hint = "CLICK TO SEND"
	elif known and _missing(incident) > 0:
		var keys: Array[String] = []
		for kind in ROLES:
			if _assigned(incident, kind) < int(incident.get("needs", {}).get(kind, 0)) and _owned(kind):
				keys.append("%s %s" % [KEY_OF[kind], ROLE_SHORT[kind]])
		if not keys.is_empty(): hint = "PRESS  " + "   ".join(keys)
	elif selected and _crew_on_scene(incident) and int(incident.get("supply_count", 0)) < 2:
		hint = "E  SUPPLIES (%d LEFT)" % int(sim.supplies)
	if not known:
		hint = "Q  SCOUT"
	if hint != "":
		_btext(hint, rect.position + Vector2(10, 71), 12, GOLD)

func _crew_on_scene(incident: Dictionary) -> bool:
	for unit in sim.units:
		if int(unit.get("target", -1)) == int(incident.id) and unit.get("state", "") == "working" and bool(unit.get("assignment_suitable", true)):
			return true
	return false

func _margin_text(estimate: Dictionary) -> String:
	if estimate.is_empty() or float(estimate.get("finish_eta", -1)) < 0:
		var call: Dictionary = _call(_preview_target if _preview_target >= 0 else selected_id)
		var missing: Array[String] = []
		if not call.is_empty():
			for kind in ROLES:
				if _assigned(call, kind) < int(call.get("needs", {}).get(kind, 0)) and not (not estimate.is_empty() and str(estimate.get("kind", "")) == kind):
					missing.append(ROLE_SHORT[kind])
		return "also needs " + " + ".join(missing) if not missing.is_empty() else "waiting for crews"
	var margin: float = float(estimate.get("margin", 0))
	return ("IN TIME  +%ds" % floori(margin)) if margin >= 0 else ("TOO LATE  -%ds" % ceili(-margin))

func _team_status(incident: Dictionary) -> String:
	if not bool(incident.get("discovered", true)):
		return "Unknown needs · Q to scout"
	var missing: Array[String] = []
	for kind in ROLES:
		if _assigned(incident, kind) < int(incident.get("needs", {}).get(kind, 0)):
			missing.append(ROLE_SHORT[kind] + (" (%s)" % owner_labels[kind] if owner_labels.has(kind) else ""))
	if not missing.is_empty():
		return "Needs " + " + ".join(missing)
	return "Crews on the way" if float(incident.get("progress", 0)) <= 0 else "At work · %d%%" % roundi(float(incident.get("progress", 0)) * 100)

func _risk_color(estimate: Dictionary) -> Color:
	if estimate.is_empty() or not bool(estimate.get("known", true)) or bool(estimate.get("team_incomplete", false)) or float(estimate.get("finish_eta", -1)) < 0:
		return RED if bool(estimate.get("known", false)) and not bool(estimate.get("suitable", true)) else MUTED
	if not bool(estimate.get("suitable", true)):
		return RED
	var margin: float = float(estimate.get("margin", 0))
	return RED if margin < 0 else GOLD if margin < 10 else GREEN

func _draw_crew(item: Dictionary) -> void:
	var unit: Dictionary = item.unit
	var color: Color = ROLE_COLOR.get(unit.get("kind", "fire"), CREAM)
	var owned: bool = _owned(str(unit.get("kind", "")))
	if not owned:
		color = Color(color.darkened(.25), .7)
	var selected: bool = int(unit.id) == selected_unit_id
	var hovered: bool = int(unit.id) == hovered_unit_id
	var available: bool = _available(unit)
	var center: Vector2 = item.point
	var marker: Rect2 = item.marker
	if selected:
		var pulse: float = 0.0 if reduced_motion else (sin(_elapsed * 6.0) + 1.0) * 2.0
		draw_arc(center, 19 + pulse, 0, TAU, 28, GOLD, 4, false)
		draw_arc(center, 25 + pulse, 0, TAU, 28, Color(GOLD, .35), 2, false)
	else:
		draw_arc(center, 15, 0, TAU, 24, Color(color, .8) if (available or hovered) else Color(color, .35), 3 if hovered else 2, false)
	# Small department badge above the vehicle.
	var badge := Rect2(center + Vector2(8, -24), Vector2(16, 16))
	draw_rect(badge, INK)
	draw_rect(badge, color, false, 1)
	_role_icon(str(unit.kind), badge.get_center(), color)
	if selected or hovered:
		var name: String = str(unit.get("crew_name", unit.get("name", "Crew")))
		var state: String = str(unit.get("state", "idle"))
		var tag: String = name if available else ("%s · busy" % name if state in ["travel", "working"] else "%s · resting" % name)
		var tw: float = ThemeDB.fallback_font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var tag_rect := Rect2(center + Vector2(-tw * .5 - 6, 22), Vector2(tw + 12, 18))
		draw_rect(tag_rect, INK)
		draw_rect(tag_rect, GOLD if selected else color, false, 1)
		_text(tag, tag_rect.position + Vector2(6, 14), 12, GOLD if selected else CREAM)



