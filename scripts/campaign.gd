class_name BeaconCampaign
extends RefCounted

const BASE_MAP_SIZE := Vector2(532, 316)
const PREVIOUS_MAP_SIZE := Vector2(664, 396)
const MAP_V3_SIZE := Vector2(1536, 1024)
# Oct 2026 (playtest 15.10): one new road column on each side, so the
# whole-town view fills a 16:9 screen. The old town moved 224 px east.
const MAP_V4_SIZE := Vector2(2304, 1536)
const MAP_SIZE := Vector2(2752, 1536)
const TOWN_SHIFT_X := 224.0
const MAP_VERSION := 5
const CHAOS_SCHEDULE_VERSION := "beacon-chaos-v1"
const SHIFT_SECONDS := 330.0

# The order looks irregular to a player, but is an immutable study protocol.
# Times are active seconds since this shift started, never wall-clock time.
# Keep old versions available if a future study changes this protocol.
static func chaos_schedule(index: int) -> Array[Dictionary]:
	var starts: Array = [
		[0, 42, 73, 106, 142, 174, 204, 244, 278],
		[0, 37, 68, 101, 137, 172, 211, 246, 280],
		[0, 45, 79, 109, 143, 176, 209, 242, 279],
		[0, 39, 72, 103, 139, 173, 206, 241, 280],
		[0, 43, 76, 107, 141, 176, 210, 245, 280],
		[0, 35, 68, 101, 136, 170, 205, 244, 279]
	]
	var orders: Array = [
		["normal", "high", "low", "normal", "high", "low", "high", "normal", "low"],
		["normal", "high", "low", "high", "normal", "low", "normal", "high", "low"],
		["normal", "high", "low", "normal", "high", "normal", "low", "high", "low"],
		["normal", "high", "low", "high", "normal", "high", "low", "normal", "low"],
		["normal", "high", "low", "normal", "low", "high", "normal", "high", "low"],
		["normal", "high", "low", "high", "normal", "low", "high", "normal", "low"]
	]
	var shift: int = clampi(index, 0, 5)
	var result: Array[Dictionary] = []
	for phase_index: int in range(starts[shift].size()):
		var begins: float = float(starts[shift][phase_index])
		var ends: float = float(starts[shift][phase_index + 1]) if phase_index + 1 < starts[shift].size() else SHIFT_SECONDS
		result.append({"at": begins, "until": ends, "phase": orders[shift][phase_index], "index": phase_index})
	return result

static func arrival_schedule(index: int, base_interval: float) -> Array[Dictionary]:
	# A dedicated seed is used once to prepare arrival opportunities. Gameplay,
	# occupied locations and random art can never consume this random stream.
	var timing_rng := RandomNumberGenerator.new()
	timing_rng.seed = 141307 + clampi(index, 0, 5) * 117
	var result: Array[Dictionary] = []
	for phase: Dictionary in chaos_schedule(index):
		var multiplier: float = {"normal": 1.0, "high": 0.58, "low": 1.85}[phase.phase]
		var offset: float = {"normal": 3.5, "high": 1.8, "low": 11.0}[phase.phase]
		var at: float = float(phase.at) + (2.8 if int(phase.index) == 0 else offset)
		while at < minf(float(phase.until), SHIFT_SECONDS - 45.0):
			result.append({"at": snappedf(at, 0.001), "phase_index": phase.index})
			at += base_interval * multiplier * timing_rng.randf_range(0.92, 1.08)
	return result

static func shifts() -> Array[Dictionary]:
	var scenarios: Array[Dictionary] = [
		{"title": "FIRST LIGHT", "subtitle": "A small town. A very big heart.", "weather": "clear", "target": 30, "introduction": "Select a call. Send the matching crew. Bring everyone home.", "accent": "66dbc0", "interval": 23.0, "max_active": 4, "weights": [4, 5, 1, 2, 3], "disruptions": [{"at": 112.0, "type": "market", "duration": 35.0, "text": "Morning market • the whole town is out"}, {"at": 224.0, "type": "clear", "duration": 25.0, "text": "Neighbors lend a hand • crews work faster"}]},
		{"title": "MARKET DAY", "subtitle": "The festival is counting on you.", "weather": "golden", "target": 42, "introduction": "Some calls need two teams. Scout a call for extra breathing room.", "accent": "ffd17b", "interval": 20.5, "max_active": 4, "weights": [4, 5, 2, 3, 5], "disruptions": [{"at": 205.0, "type": "festival", "duration": 48.0, "text": "Festival rush • the whole town is out"}]},
		{"title": "TWO BANKS", "subtitle": "One river. Three bridges. Don't get caught on the wrong side.", "weather": "rain", "target": 44, "introduction": "A river splits the town and only three bridges cross it. Watch the forecast: when a bridge floods, find another way across.", "accent": "7bc8f0", "interval": 19.0, "max_active": 4, "weights": [2, 3, 7, 3, 2], "disruptions": []},
		{"title": "LIGHTS OUT", "subtitle": "Moon Lake. A dark town. Keep the lights on.", "weather": "night", "target": 60, "introduction": "Districts lose power one by one. Calls in the dark can't be seen and crews drive slowly. Send an engineer to the substation to bring the lights back.", "accent": "bda6ff", "interval": 17.5, "max_active": 5, "weights": [3, 4, 2, 7, 3], "disruptions": []},
		{"title": "DUNE SPRINGS", "subtitle": "A desert town. Here comes the sand.", "weather": "desert", "target": 64, "introduction": "Sandstorms sweep across the town. Inside a storm everyone drives slowly and calls are hard to see. Get crews out before it arrives.", "accent": "f0b36b", "interval": 16.0, "max_active": 5, "weights": [4, 4, 3, 6, 3], "disruptions": []},
		{"title": "BEACON NIGHT", "subtitle": "A whole town, looking out for each other.", "weather": "sunset", "target": 72, "introduction": "Your final watch: the river, a blackout and a squall. Use every lesson and every teammate.", "accent": "ffa784", "interval": 14.5, "max_active": 5, "weights": [5, 5, 5, 5, 5], "disruptions": [{"at": 286.0, "type": "clear", "duration": 44.0, "text": "The beacon shines • neighbors help finish the watch"}]}
	]
	var intervals: Array[float] = [18.5, 16.7, 15.5, 11.8, 11.4, 10.8]
	var capacities: Array[int] = [4, 5, 5, 7, 7, 8]
	
	var rescue_targets: Array[int] = [60, 72, 78, 104, 108, 116]
	for index: int in range(scenarios.size()):
		scenarios[index].interval = intervals[index]
		scenarios[index].max_active = capacities[index]
		scenarios[index].target = rescue_targets[index]
		scenarios[index].surges = []
		scenarios[index].chaos_phases = chaos_schedule(index)
		scenarios[index].arrival_schedule = arrival_schedule(index, intervals[index])
		# Road events replace the old passive slow zones (kept under the "traffic"
		# key so saved games and map migrations keep working).
		scenarios[index].traffic = road_events(index)
	return scenarios

# ROAD EVENTS (traffic rework, Oct 2026)
# A road event blocks one stretch of road between two junctions. Other
# departments crawl through it (or detour); only the department that can deal
# with it drives through at full speed and can clear it:
#   jam       -> Police clears it (crash, crowd, stalled traffic)
#   debris    -> Engineering clears it (fallen tree, burst main, flooding)
#   road_fire -> Fire puts it out (burning car, grass fire by the road)
#   accident  -> Medical clears it (pile-up: paramedics treat and take away the injured)
# Since 15.10 (4-player playtest: Police and Engineering had more to do) every
# department clears roads, about equally often in every level.
# Clearing takes a crew off calls for a while, so the team has to decide
# together whether to open the road or take the next call. Events are part of
# the fixed per-shift script: same time, same place, every session. Most land
# a few seconds into a high-chaos phase; none starts in a low phase.
const ROAD_EVENT_SPEED := 0.06
const ROAD_EVENT_MAX_SECONDS := 95.0
const ROAD_CLEAR_SECONDS := {"jam": 7.0, "debris": 9.0, "road_fire": 8.0, "accident": 9.0}
const ROAD_CLEAR_KIND := {"jam": "police", "debris": "engineer", "road_fire": "fire", "accident": "medic"}
const ROAD_X_PX: Array[float] = [96.0, 352.0, 608.0, 864.0, 1120.0, 1376.0, 1632.0, 1888.0, 2144.0, 2400.0, 2656.0]
const ROAD_Y_PX: Array[float] = [192.0, 448.0, 704.0, 928.0, 1184.0, 1440.0]

# Named stretches of road: [street name, road row, from column, to column, buildings on it].
# Each runs along ROAD_Y[row] from ROAD_X[from] to ROAD_X[to] and is two blocks
# long, so it also closes the crossing in the middle. Buildings are always
# reached from the horizontal road in front of them, so a closure cuts off the
# buildings on that street for every department except the one that clears it.
# Spread over the whole map: north, centre, east, south and the far south.
const ROAD_STRETCHES := {
	"corner_road": ["Corner Road", 0, 1, 3, ["Willow Cottage", "The Corner Store", "Moonrise Bakery", "Pelican Cafe"]],
	"north_avenue": ["North Avenue", 0, 4, 6, ["Sunflower Apartments", "Harbor Workshop", "Eastwood Homes", "Harbor Warehouse"]],
	"harbor_road": ["Harbor Road", 1, 3, 5, ["Community Hall", "Bay Stadium", "Power Substation", "Seabreeze Cottages"]],
	"orchard_road": ["Orchard Road", 1, 6, 8, ["Orchard Hall", "East Library", "Orchard Market"]],
	"market_street": ["Market Street", 2, 2, 4, ["Civic Apartments", "Harbor Hotel"]],
	"ferry_road": ["Ferry Road", 2, 5, 7, ["Ferry Terminal", "Cargo Terminal"]],
	"east_hill_road": ["East Hill Road", 2, 7, 9, ["Hillside Bakery", "Eastside Pump House"]],
	"marina_road": ["Marina Road", 3, 2, 4, ["Lifeboat Station", "Marina Apartments", "Dune Cottages", "Botanical Gardens"]],
	"quay_road": ["Quay Road", 3, 5, 7, ["East Quay", "Old Lighthouse", "Maritime Academy", "Southgate School"]],
	"dock_road": ["Dock Road", 3, 7, 9, ["Dockside Warehouse", "Fisherman's Pier", "East Rescue Station", "Cliffside Homes"]],
	"seawall_road": ["Seawall Road", 4, 1, 3, ["Kelp Street Store", "South Marina"]],
	"island_road": ["Island Road", 4, 4, 6, ["Pier Market", "Island Clinic"]]
}

static func road_stretch(key: String) -> Dictionary:
	var spec: Array = ROAD_STRETCHES[key]
	var margin: float = 30.0
	var half: float = 30.0
	var y: float = ROAD_Y_PX[int(spec[1])]
	var x1: float = ROAD_X_PX[int(spec[2])]
	var x2: float = ROAD_X_PX[int(spec[3])]
	var area := Rect2(x1 + margin, y - half, x2 - x1 - margin * 2.0, half * 2.0)
	return {"street": str(spec[0]), "position": area.position / MAP_SIZE, "size": area.size / MAP_SIZE, "sites": spec[4]}

static func location_index(name: String) -> int:
	if name.is_empty(): return -1
	var places: Array[Dictionary] = locations()
	for index: int in range(places.size()):
		if str(places[index].name) == name: return index
	return -1

static func road_events(index: int) -> Array[Dictionary]:
	# [at, type, title, stretch, which building on it, call kind at that building]
	# Each shift's closures land in different parts of town.
	# The call that comes with a closure is led by another department than the
	# one that clears it, so a closure always involves at least two players.
	var plans: Array = [
		# Level 1 has no road events (playtest 15.10): it's for learning the basics.
		[],
		[[41.0, "accident", "Fender-bender", "ferry_road", 0, "police"], [104.0, "debris", "Bridge works", "quay_road", 0, "fire"], [213.0, "jam", "Festival crowd", "market_street", 1, "medical"], [250.0, "road_fire", "Grass fire", "north_avenue", 2, "power"]],
		[[49.0, "jam", "Stalled bus", "orchard_road", 1, "fire"], [112.0, "accident", "Bus crash", "seawall_road", 1, "police"], [147.0, "road_fire", "Burning truck", "harbor_road", 3, "medical"], [246.0, "debris", "Flooded underpass", "dock_road", 2, "flood"]],
		# Lights Out: blackouts already keep Engineering busy, so no debris here.
		[[60.0, "road_fire", "Car fire", "corner_road", 1, "medical"], [140.0, "jam", "Dark junction", "marina_road", 2, "fire"], [150.0, "accident", "Crash", "harbor_road", 0, "fire"], [200.0, "accident", "Crash in the dark", "dock_road", 2, "police"], [250.0, "road_fire", "Brush fire", "east_hill_road", 0, "police"]],
		[[60.0, "jam", "Stalled truck", "quay_road", 3, "medical"], [112.0, "road_fire", "Brush fire", "corner_road", 0, "police"], [186.0, "accident", "Pile-up in the dust", "north_avenue", 1, "fire"], [252.0, "debris", "Sand drift", "seawall_road", 0, "medical"]],
		[[110.0, "jam", "Crash", "dock_road", 2, "medical"], [150.0, "road_fire", "Car fire", "corner_road", 2, "police"], [236.0, "accident", "Crash", "market_street", 0, "fire"]]
	]
	var result: Array[Dictionary] = []
	var number: int = 1
	for plan: Array in plans[clampi(index, 0, 5)]:
		var stretch: Dictionary = road_stretch(str(plan[3]))
		var type: String = str(plan[1])
		result.append({"id": number, "at": float(plan[0]), "duration": ROAD_EVENT_MAX_SECONDS,
			"type": type, "clear_kind": str(ROAD_CLEAR_KIND[type]),
			"clear_time": float(ROAD_CLEAR_SECONDS[type]),
			"name": "%s on %s" % [str(plan[2]), stretch.street], "street": stretch.street,
			"position": stretch.position, "size": stretch.size, "speed_factor": ROAD_EVENT_SPEED,
			"call_site": str(stretch.sites[mini(int(plan[4]), stretch.sites.size() - 1)]), "call_kind": str(plan[5])})
		number += 1
	# Level hazards (blackouts, sandstorms, squalls) use the same machinery as
	# road events, so they are scripted, saved and sent to co-op guests alike.
	for hazard: Dictionary in level_hazards(index):
		hazard["id"] = number
		result.append(hazard)
		number += 1
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.at) < float(b.at))
	return result

# Which department leads each call, by call number. Every block of four calls
# has each department lead exactly once (shuffled with a fixed seed), so every
# role is needed equally in every level and the order is the same every session.
static func lead_order(index: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 271829 + clampi(index, 0, 5) * 131
	var result: Array = []
	for block: int in range(30):
		var departments: Array = ["fire", "medic", "engineer", "police"]
		for i: int in range(departments.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var swap = departments[i]
			departments[i] = departments[j]
			departments[j] = swap
		result.append_array(departments)
	return result

# LEVEL LAYOUTS (Oct 2026). Levels 1-2 use the normal full grid of roads (an
# empty layout). Levels 3-6 each have their own map and one signature hazard:
#   3 TWO BANKS    a river with three bridges; scripted floods close a bridge
#   4 LIGHTS OUT   night, Moon Lake in the middle; districts black out and an
#                  engineer at the substation turns the lights back on
#   5 DUNE SPRINGS desert, an oasis and sand dunes over some streets;
#                  sandstorms sweep across the town in three steps
#   6 BEACON NIGHT the river again, plus a blackout and a squall (finale)
# Everything happens at fixed times, so every session plays out the same.
#   water:   areas with no roads and no buildings (rivers, lakes, oases)
#   bridges: road column -> name; the only roads that cross the river
#   blocked: extra missing road pieces [horizontal?, column, row] (dunes);
#            horizontal pieces run column -> column+1, vertical row -> row+1
#   floods:  [bridge column, starts at (s), lasts (s)]
const RIVER_TOP := 736.0
const RIVER_BOTTOM := 896.0
# Every bridge flood, blackout and storm is announced this many seconds ahead.
const HAZARD_WARNING_SECONDS := 12.0

# Nine districts (3 x 3) used to name blackouts.
const DISTRICTS := {
	"lantern_hill": ["Lantern Hill", 0, 0], "north_end": ["North End", 1, 0], "orchard_heights": ["Orchard Heights", 2, 0],
	"westside": ["Westside", 0, 1], "old_town": ["Old Town", 1, 1], "east_docks": ["East Docks", 2, 1],
	"saltmarsh": ["Saltmarsh", 0, 2], "south_harbour": ["South Harbour", 1, 2], "cliffside": ["Cliffside", 2, 2]
}

static func layout(index: int) -> Dictionary:
	match clampi(index, 0, 5):
		2:
			return {"name": "two_banks", "theme": "river",
				"water": [Rect2(0.0, RIVER_TOP, MAP_SIZE.x, RIVER_BOTTOM - RIVER_TOP)],
				"river": Rect2(0.0, RIVER_TOP, MAP_SIZE.x, RIVER_BOTTOM - RIVER_TOP),
				"river_row": 2,          # the gap is between ROAD_Y[2] and ROAD_Y[3]
				"bridges": {2: "West Bridge", 5: "Town Bridge", 8: "East Bridge"},
				# Each starts in a high-chaos phase.
				"floods": [[8, 50.0, 45.0], [5, 146.0, 60.0], [2, 245.0, 45.0]]}
		3:
			return {"name": "lights_out", "theme": "night",
				"water": [Rect2(1154.0, 480.0, 700.0, 420.0)], "lake_name": "MOON LAKE"}
		4:
			return {"name": "dune_springs", "theme": "desert",
				"water": [Rect2(1204.0, 600.0, 380.0, 220.0)], "lake_name": "PALM OASIS",
				# Sand dunes have buried a few streets for good.
				"blocked": [[false, 2, 3], [false, 8, 1], [true, 6, 4], [true, 3, 0], [false, 4, 4]]}
		5:
			return {"name": "beacon_night", "theme": "river",
				"water": [Rect2(0.0, RIVER_TOP, MAP_SIZE.x, RIVER_BOTTOM - RIVER_TOP)],
				"river": Rect2(0.0, RIVER_TOP, MAP_SIZE.x, RIVER_BOTTOM - RIVER_TOP),
				"river_row": 2,
				"bridges": {2: "West Bridge", 5: "Town Bridge", 8: "East Bridge"},
				"floods": [[5, 104.0, 50.0], [8, 208.0, 40.0]]}
	return {}

# Blackouts and storms, as road-event records (see road_events()).
#   blackout: one district; everyone but Engineering drives slowly (40%) and
#             new calls there are unconfirmed; an engineer at the substation
#             (8 s) restores power, otherwise it lasts 70 s.
#   sandstorm / squall: a third of the town at a time, everyone drives slowly
#             and new calls there are unconfirmed; nobody can clear it. Three
#             steps in a row make the storm sweep across the town.
static func level_hazards(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match clampi(index, 0, 5):
		3:
			result.append(_blackout(42.0, "lantern_hill", Vector2(608, 448)))
			result.append(_blackout(106.0, "east_docks", Vector2(2144, 704)))
			result.append(_blackout(176.0, "saltmarsh", Vector2(608, 1184)))
		4:
			result.append_array(_storm(46.0, "sandstorm", true, 28.0, 22.0))
			result.append_array(_storm(178.0, "sandstorm", false, 28.0, 22.0))
		5:
			result.append(_blackout(38.0, "orchard_heights", Vector2(2144, 448)))
			result.append_array(_storm(140.0, "squall", true, 28.0, 22.0))
	return result

static func district_rect(key: String) -> Rect2:
	var spec: Array = DISTRICTS[key]
	var size: Vector2 = MAP_SIZE / 3.0
	return Rect2(Vector2(float(spec[1]), float(spec[2])) * size, size)

static func _blackout(at: float, district: String, substation: Vector2) -> Dictionary:
	var area: Rect2 = district_rect(district)
	var name: String = str(DISTRICTS[district][0])
	return {"at": at, "duration": 70.0, "type": "blackout", "clear_kind": "engineer", "clear_time": 8.0,
		"name": "Blackout in %s" % name, "street": name, "position": area.position / MAP_SIZE, "size": area.size / MAP_SIZE,
		"speed_factor": 0.4, "call_site": "", "call_kind": "", "target": substation / MAP_SIZE, "hazard": true}

# A storm in three steps across the map (west -> east, or east -> west).
static func _storm(at: float, type: String, eastward: bool, step_seconds: float, step_gap: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var names: Array[String] = ["the west", "the centre", "the east"]
	var label: String = "Sandstorm" if type == "sandstorm" else "Squall"
	for step: int in range(3):
		var column: int = step if eastward else 2 - step
		var area := Rect2(column * MAP_SIZE.x / 3.0, 0.0, MAP_SIZE.x / 3.0, MAP_SIZE.y)
		result.append({"at": at + step * step_gap, "duration": step_seconds, "type": type, "clear_kind": "", "clear_time": 0.0,
			"name": "%s over %s" % [label, names[column]], "street": names[column],
			"position": area.position / MAP_SIZE, "size": area.size / MAP_SIZE,
			"speed_factor": 0.65, "call_site": "", "call_kind": "",
			"target": area.get_center() / MAP_SIZE, "hazard": true, "eastward": eastward})
	return result

# Whether a piece of road is missing on this layout (under water or a dune).
# Bridges are open here; their floods are timed and handled by the simulation.
static func edge_blocked(data: Dictionary, horizontal: bool, ix: int, iy: int) -> bool:
	if data.is_empty(): return false
	for piece: Array in data.get("blocked", []):
		if bool(piece[0]) == horizontal and int(piece[1]) == ix and int(piece[2]) == iy: return true
	if not horizontal and data.has("bridges") and iy == int(data.get("river_row", -1)) and data.bridges.has(ix): return false
	if horizontal and ix + 1 >= ROAD_X_PX.size(): return true
	if not horizontal and iy + 1 >= ROAD_Y_PX.size(): return true
	var a := Vector2(ROAD_X_PX[ix], ROAD_Y_PX[iy])
	var b: Vector2 = Vector2(ROAD_X_PX[ix + 1], a.y) if horizontal else Vector2(a.x, ROAD_Y_PX[iy + 1])
	var piece_area := Rect2(a, b - a).abs().grow(1.0)
	for water: Rect2 in data.get("water", []):
		if water.grow(-2.0).intersects(piece_area): return true
	return false

static func is_hazard_type(type: String) -> bool:
	return type in ["blackout", "sandstorm", "squall"]

# Sites in the water, or on a street that a dune has buried, can't have calls.
static func site_open(index: int, site_pos_normalized: Vector2) -> bool:
	var data: Dictionary = layout(index)
	if data.is_empty(): return true
	var point: Vector2 = site_pos_normalized * MAP_SIZE
	for water: Rect2 in data.get("water", []):
		if water.grow(20.0).has_point(point): return false
	var row: int = 0
	for i: int in range(ROAD_Y_PX.size()):
		if absf(ROAD_Y_PX[i] - point.y) < absf(ROAD_Y_PX[row] - point.y): row = i
	var left: int = -1
	for i: int in range(ROAD_X_PX.size()):
		if ROAD_X_PX[i] <= point.x: left = i
	if left >= 0 and left + 1 < ROAD_X_PX.size() and edge_blocked(data, true, left, row): return false
	return true

static func shift_data(index: int) -> Dictionary:
	return shifts()[clampi(index, 0, 5)].duplicate(true)

static func upgrades() -> Array[Dictionary]:
	return [
		{"id": "engines", "name": "Quick wheels", "description": "Crews travel 14% faster per level.", "cost": 65, "max_level": 3, "icon": "speed", "kind": "fleet"},
		{"id": "training", "name": "Steady hands", "description": "Rescue work is 12% faster per level.", "cost": 80, "max_level": 3, "icon": "heart", "kind": "team"},
		{"id": "radio", "name": "Clear signal", "description": "Every new call gets 7 extra seconds per level.", "cost": 70, "max_level": 2, "icon": "radio", "kind": "support"},
		{"id": "supplies", "name": "Ready supplies", "description": "Carry one more supply; deliveries arrive 5 seconds sooner.", "cost": 60, "max_level": 3, "icon": "box", "kind": "support"},
		{"id": "rest", "name": "Good coffee", "description": "Crews recover sooner and tire 35% less per level.", "cost": 55, "max_level": 2, "icon": "coffee", "kind": "team"},
		{"id": "rally", "name": "Town spirit", "description": "The coffee boost recharges 15 seconds sooner per level.", "cost": 85, "max_level": 2, "icon": "star", "kind": "support"},
		{"id": "scouting", "name": "Local knowledge", "description": "The scout team is ready 2.5 seconds sooner per level.", "cost": 60, "max_level": 2, "icon": "eye", "kind": "team"}
	]

static func upgrade_data(id: String) -> Dictionary:
	for entry: Dictionary in upgrades():
		if entry.id == id:
			return entry.duplicate(true)
	return {}

static func upgrade_cost(id: String, level: int) -> int:
	var entry := upgrade_data(id)
	return int(round(float(entry.get("cost", 0)) * (1.0 + 0.65 * level)))

# Crews per department, the same for every department and every level
# (playtest 19.10: four crews for each department in all six levels;
# before that it was 3 in levels 1-3 and 4 in levels 4-6).
static func crews_per_department(_index: int) -> int:
	return 4

static func responder_profile(kind: String, crew_index: int) -> Dictionary:
	var profiles: Dictionary = {
		"fire": [["Bram", "Finn"], ["Kai", "Rosa"], ["Idris", "Piper"], ["Hugo", "Maya"]],
		"medic": [["Elio", "Theo"], ["Noor", "Bea"], ["Ada", "Elias"], ["Lena", "Omar"]],
		"engineer": [["Tess", "Niko"], ["Olavi", "Zara"], ["Esme", "Otto"], ["Rune", "Lila"]],
		"police": [["Nova", "Juno"], ["Mika", "Remy"], ["Sol", "Ines"], ["Arlo", "Vera"]]
	}
	var kind_index: int = ["fire", "medic", "engineer", "police"].find(kind)
	var crews: Array = profiles.get(kind, profiles.fire)
	var pair: Array = crews[clampi(crew_index, 0, crews.size() - 1)]
	return {"crew_name": str(pair[0]), "partner_name": str(pair[1]), "appearance": (maxi(0, kind_index) * 3 + clampi(crew_index, 0, 3)) % 12}

static func locations() -> Array[Dictionary]:
	# Stable indices preserve existing incident identities across map revisions.
	return [
		{"name": "Willow Cottage", "pos": Vector2(480, 84) / MAP_SIZE},
		{"name": "Moonrise Bakery", "pos": Vector2(736, 84) / MAP_SIZE},
		{"name": "Little Lantern School", "pos": Vector2(736, 540) / MAP_SIZE},
		{"name": "North Pier", "pos": Vector2(1248, 836) / MAP_SIZE},
		{"name": "The Corner Store", "pos": Vector2(480, 276) / MAP_SIZE},
		{"name": "Magnolia House", "pos": Vector2(992, 84) / MAP_SIZE},
		{"name": "Sunflower Apartments", "pos": Vector2(1248, 84) / MAP_SIZE},
		{"name": "Harbor Workshop", "pos": Vector2(1248, 276) / MAP_SIZE},
		{"name": "Juniper Gardens", "pos": Vector2(480, 540) / MAP_SIZE},
		{"name": "Pelican Cafe", "pos": Vector2(736, 276) / MAP_SIZE},
		{"name": "Beacon Clinic", "pos": Vector2(992, 276) / MAP_SIZE},
		{"name": "Old Lighthouse", "pos": Vector2(1694, 836) / MAP_SIZE},
		{"name": "Harbor Warehouse", "pos": Vector2(1504, 276) / MAP_SIZE},
		{"name": "Seabreeze Cottages", "pos": Vector2(1248, 540) / MAP_SIZE},
		{"name": "Market Square", "pos": Vector2(480, 406) / MAP_SIZE},
		{"name": "Juniper Library", "pos": Vector2(736, 406) / MAP_SIZE},
		{"name": "Eastwood Homes", "pos": Vector2(1504, 84) / MAP_SIZE},
		{"name": "Bay Transit Depot", "pos": Vector2(1504, 406) / MAP_SIZE},
		{"name": "Harbor Market", "pos": Vector2(1248, 670) / MAP_SIZE},
		{"name": "East Quay", "pos": Vector2(1504, 836) / MAP_SIZE},
		{"name": "South Park", "pos": Vector2(290, 836) / MAP_SIZE},
		{"name": "Lifeboat Station", "pos": Vector2(736, 836) / MAP_SIZE},
		{"name": "Marina Apartments", "pos": Vector2(992, 836) / MAP_SIZE},
		{"name": "Ferry Terminal", "pos": Vector2(1504, 670) / MAP_SIZE},
		{"name": "Community Hall", "pos": Vector2(992, 406) / MAP_SIZE},
		{"name": "Power Substation", "pos": Vector2(1248, 406) / MAP_SIZE},
		{"name": "Bay Stadium", "pos": Vector2(992, 540) / MAP_SIZE},
		{"name": "Seaport Museum", "pos": Vector2(1504, 540) / MAP_SIZE},
		{"name": "West Pump House", "pos": Vector2(480, 670) / MAP_SIZE},
		{"name": "Civic Apartments", "pos": Vector2(736, 670) / MAP_SIZE},
		{"name": "Harbor Hotel", "pos": Vector2(992, 670) / MAP_SIZE},
		{"name": "Coastguard Station", "pos": Vector2(480, 836) / MAP_SIZE},
		{"name": "Eastgate Homes", "pos": Vector2(1760, 276) / MAP_SIZE},
		{"name": "Orchard School", "pos": Vector2(2016, 276) / MAP_SIZE},
		{"name": "Hillcrest Clinic", "pos": Vector2(2272, 276) / MAP_SIZE},
		{"name": "East Library", "pos": Vector2(1760, 540) / MAP_SIZE},
		{"name": "Orchard Market", "pos": Vector2(2016, 540) / MAP_SIZE},
		{"name": "Reservoir Works", "pos": Vector2(2272, 540) / MAP_SIZE},
		{"name": "Cargo Terminal", "pos": Vector2(1760, 670) / MAP_SIZE},
		{"name": "Dockside Warehouse", "pos": Vector2(2016, 836) / MAP_SIZE},
		{"name": "Fisherman's Pier", "pos": Vector2(2272, 836) / MAP_SIZE},
		{"name": "South Harbor Homes", "pos": Vector2(480, 1050) / MAP_SIZE},
		{"name": "Botanical Gardens", "pos": Vector2(992, 1050) / MAP_SIZE},
		{"name": "Maritime Academy", "pos": Vector2(1504, 1050) / MAP_SIZE},
		{"name": "East Rescue Station", "pos": Vector2(2016, 1050) / MAP_SIZE},
		{"name": "South Marina", "pos": Vector2(736, 1310) / MAP_SIZE},
		{"name": "Island Clinic", "pos": Vector2(1504, 1310) / MAP_SIZE},
		{"name": "Outer Ferry Terminal", "pos": Vector2(2272, 1310) / MAP_SIZE},
		# Added Oct 2026 so calls also happen in the south and east, not mostly up north.
		{"name": "Dune Cottages", "pos": Vector2(736, 1050) / MAP_SIZE},
		{"name": "Saltmarsh Cafe", "pos": Vector2(1248, 1050) / MAP_SIZE},
		{"name": "Southgate School", "pos": Vector2(1760, 1050) / MAP_SIZE},
		{"name": "Cliffside Homes", "pos": Vector2(2272, 1050) / MAP_SIZE},
		{"name": "Kelp Street Store", "pos": Vector2(480, 1310) / MAP_SIZE},
		{"name": "Pier Market", "pos": Vector2(1248, 1310) / MAP_SIZE},
		{"name": "Tidewater Clinic", "pos": Vector2(2016, 1310) / MAP_SIZE},
		{"name": "Hillside Bakery", "pos": Vector2(2016, 670) / MAP_SIZE},
		{"name": "Eastside Pump House", "pos": Vector2(2272, 670) / MAP_SIZE},
		{"name": "Orchard Hall", "pos": Vector2(1760, 406) / MAP_SIZE},
		{"name": "Ridge Cottages", "pos": Vector2(2272, 406) / MAP_SIZE},
		# Added 15.10 with the new west and east edge of town (16:9 map).
		{"name": "Westwind Farm", "pos": Vector2(224, 84) / MAP_SIZE},
		{"name": "Pinecrest Cabins", "pos": Vector2(224, 406) / MAP_SIZE},
		{"name": "Old Mill", "pos": Vector2(224, 670) / MAP_SIZE},
		{"name": "Heron Marsh Homes", "pos": Vector2(224, 1050) / MAP_SIZE},
		{"name": "West Beach Huts", "pos": Vector2(224, 1310) / MAP_SIZE},
		{"name": "Summit Lodge", "pos": Vector2(2528, 276) / MAP_SIZE},
		{"name": "Quarry Works", "pos": Vector2(2528, 540) / MAP_SIZE},
		{"name": "Seal Point Homes", "pos": Vector2(2528, 836) / MAP_SIZE},
		{"name": "Cape Clinic", "pos": Vector2(2528, 1050) / MAP_SIZE},
		{"name": "East Beach Cafe", "pos": Vector2(2528, 1310) / MAP_SIZE}
	]

static func incident_title(kind: String, severity: int, variant: int) -> String:
	var titles: Dictionary = {
		"fire": ["Kitchen smoke", "Sparking fuse", "Workshop fire", "Chimney blaze", "Rooftop fire"],
		"medical": ["A neighbor needs help", "Bicycle tumble", "Heat exhaustion", "First aid needed", "Urgent care"],
		"flood": ["Basement rising", "Stranded neighbors", "Burst water main", "Overflowing harbor", "Flooded walkway"],
		"power": ["Lights out", "Fallen power line", "Lift stopped", "Signal failure", "Generator trouble"],
		"police": ["Car collision", "Lost child", "Crowd at the square", "Break-in reported", "Blocked junction"]
	}
	var list: Array = titles.get(kind, titles.medical)
	return str(list[(variant + severity - 1) % list.size()])

