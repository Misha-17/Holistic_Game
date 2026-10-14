class_name BeaconCampaign
extends RefCounted

const BASE_MAP_SIZE := Vector2(532, 316)
const PREVIOUS_MAP_SIZE := Vector2(664, 396)
const MAP_V3_SIZE := Vector2(1536, 1024)
const MAP_SIZE := Vector2(2304, 1536)
const MAP_VERSION := 4
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
		{"title": "RISING WATER", "subtitle": "Keep the harbor's lights alive.", "weather": "rain", "target": 44, "introduction": "Flood calls need engineers and medics. Supplies buy precious time.", "accent": "7bc8f0", "interval": 19.0, "max_active": 4, "weights": [2, 3, 7, 3, 2], "disruptions": [{"at": 85.0, "type": "rain", "duration": 58.0, "text": "Cloudburst • flood calls intensify"}, {"at": 211.0, "type": "shortage", "duration": 45.0, "text": "Supply delay • supply replenishment paused"}]},
		{"title": "AFTER DARK", "subtitle": "Be the calm in the blackout.", "weather": "night", "target": 60, "introduction": "Unconfirmed calls reward scouting. Keep an engineer in reserve.", "accent": "bda6ff", "interval": 17.5, "max_active": 5, "weights": [3, 4, 2, 7, 3], "disruptions": [{"at": 93.0, "type": "blackout", "duration": 56.0, "text": "Grid failure • scout unconfirmed calls for a clear picture"}, {"at": 213.0, "type": "comms", "duration": 44.0, "text": "Radio interference • incoming reports need a closer look"}]},
		{"title": "STORMFRONT", "subtitle": "Different teams. One heartbeat.", "weather": "storm", "target": 64, "introduction": "Use the coffee boost when calls pile up. It speeds every crew for twenty seconds.", "accent": "8cceef", "interval": 16.0, "max_active": 5, "weights": [4, 4, 6, 5, 3], "disruptions": [{"at": 82.0, "type": "storm", "duration": 62.0, "text": "Storm surge • flood calls rise; every second matters"}, {"at": 202.0, "type": "shortage", "duration": 40.0, "text": "Warehouse flooded • make the supplies you have count"}]},
		{"title": "BEACON NIGHT", "subtitle": "A whole town, looking out for each other.", "weather": "sunset", "target": 72, "introduction": "Your final watch. Use every lesson, every upgrade, every teammate.", "accent": "ffa784", "interval": 14.5, "max_active": 5, "weights": [5, 5, 5, 5, 5], "disruptions": [{"at": 75.0, "type": "comms", "duration": 44.0, "text": "Radio interference • trust your field reports"}, {"at": 167.0, "type": "storm", "duration": 51.0, "text": "One last squall • the bay needs all of us"}, {"at": 254.0, "type": "clear", "duration": 60.0, "text": "The beacon shines • neighbors help finish the watch"}]}
	]
	var intervals: Array[float] = [18.5, 16.7, 15.5, 14.3, 13.2, 12.2]
	var capacities: Array[int] = [4, 5, 5, 6, 6, 6]
	
	var rescue_targets: Array[int] = [60, 72, 78, 90, 104, 116]
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
#   jam    -> Police clears it (crash, crowd, stalled traffic)
#   debris -> Engineering clears it (fallen tree, burst main, flooding)
# Clearing takes a crew off calls for a while, so the team has to decide
# together whether to open the road or take the next call. Events are part of
# the fixed per-shift script: same time, same place, every session. Most land
# a few seconds into a high-chaos phase; none starts in a low phase.
const ROAD_EVENT_SPEED := 0.06
const ROAD_EVENT_MAX_SECONDS := 95.0
const ROAD_CLEAR_SECONDS := {"jam": 7.0, "debris": 9.0}
const ROAD_X_PX: Array[float] = [128.0, 384.0, 640.0, 896.0, 1152.0, 1408.0, 1664.0, 1920.0, 2176.0]
const ROAD_Y_PX: Array[float] = [192.0, 448.0, 704.0, 928.0, 1184.0, 1440.0]

# Named stretches of road: [street name, road row, from column, to column, buildings on it].
# Each runs along ROAD_Y[row] from ROAD_X[from] to ROAD_X[to] and is two blocks
# long, so it also closes the crossing in the middle. Buildings are always
# reached from the horizontal road in front of them, so a closure cuts off the
# buildings on that street for every department except the one that clears it.
# Spread over the whole map: north, centre, east, south and the far south.
const ROAD_STRETCHES := {
	"corner_road": ["Corner Road", 0, 0, 2, ["Willow Cottage", "The Corner Store", "Moonrise Bakery", "Pelican Cafe"]],
	"north_avenue": ["North Avenue", 0, 3, 5, ["Sunflower Apartments", "Harbor Workshop", "Eastwood Homes", "Harbor Warehouse"]],
	"harbor_road": ["Harbor Road", 1, 2, 4, ["Community Hall", "Bay Stadium", "Power Substation", "Seabreeze Cottages"]],
	"orchard_road": ["Orchard Road", 1, 5, 7, ["Orchard Hall", "East Library", "Orchard Market"]],
	"market_street": ["Market Street", 2, 1, 3, ["Civic Apartments", "Harbor Hotel"]],
	"ferry_road": ["Ferry Road", 2, 4, 6, ["Ferry Terminal", "Cargo Terminal"]],
	"east_hill_road": ["East Hill Road", 2, 6, 8, ["Hillside Bakery", "Eastside Pump House"]],
	"marina_road": ["Marina Road", 3, 1, 3, ["Lifeboat Station", "Marina Apartments", "Dune Cottages", "Botanical Gardens"]],
	"quay_road": ["Quay Road", 3, 4, 6, ["East Quay", "Old Lighthouse", "Maritime Academy", "Southgate School"]],
	"dock_road": ["Dock Road", 3, 6, 8, ["Dockside Warehouse", "Fisherman's Pier", "East Rescue Station", "Cliffside Homes"]],
	"seawall_road": ["Seawall Road", 4, 0, 2, ["Kelp Street Store", "South Marina"]],
	"island_road": ["Island Road", 4, 3, 5, ["Pier Market", "Island Clinic"]]
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
	# Each shift's four closures land in four different parts of town.
	var plans: Array = [
		[[46.0, "jam", "Crash", "harbor_road", 0, "medical"], [112.0, "jam", "Market crowd", "marina_road", 1, "fire"], [146.0, "debris", "Fallen tree", "east_hill_road", 1, "medical"], [208.0, "debris", "Burst water main", "island_road", 0, "fire"]],
		[[41.0, "jam", "Fender-bender", "ferry_road", 0, "medical"], [104.0, "debris", "Bridge works", "quay_road", 0, "fire"], [213.0, "jam", "Festival crowd", "market_street", 1, "medical"], [250.0, "debris", "Fallen tree", "north_avenue", 2, "fire"]],
		[[49.0, "jam", "Stalled bus", "orchard_road", 1, "medical"], [112.0, "debris", "Flooded underpass", "seawall_road", 1, "fire"], [147.0, "debris", "Burst water main", "harbor_road", 3, "medical"], [246.0, "jam", "Crash", "dock_road", 2, "fire"]],
		[[43.0, "jam", "Crash", "corner_road", 1, "medical"], [106.0, "debris", "Downed power line", "ferry_road", 1, "fire"], [177.0, "jam", "Dark junction", "marina_road", 2, "medical"], [243.0, "debris", "Fallen tree", "east_hill_road", 0, "fire"]],
		[[47.0, "jam", "Stalled truck", "quay_road", 3, "medical"], [110.0, "debris", "Storm debris", "island_road", 1, "fire"], [180.0, "jam", "Crash", "orchard_road", 0, "medical"], [249.0, "debris", "Flooded underpass", "seawall_road", 0, "fire"]],
		[[39.0, "jam", "Crash", "dock_road", 0, "medical"], [105.0, "debris", "Fallen tree", "corner_road", 2, "fire"], [168.0, "debris", "Storm debris", "harbor_road", 1, "medical"], [209.0, "jam", "Crowd at the market", "market_street", 0, "fire"]]
	]
	var result: Array[Dictionary] = []
	var number: int = 1
	for plan: Array in plans[clampi(index, 0, 5)]:
		var stretch: Dictionary = road_stretch(str(plan[3]))
		var type: String = str(plan[1])
		result.append({"id": number, "at": float(plan[0]), "duration": ROAD_EVENT_MAX_SECONDS,
			"type": type, "clear_kind": "police" if type == "jam" else "engineer",
			"clear_time": float(ROAD_CLEAR_SECONDS[type]),
			"name": "%s on %s" % [str(plan[2]), stretch.street], "street": stretch.street,
			"position": stretch.position, "size": stretch.size, "speed_factor": ROAD_EVENT_SPEED,
			"call_site": str(stretch.sites[mini(int(plan[4]), stretch.sites.size() - 1)]), "call_kind": str(plan[5])})
		number += 1
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

static func responder_profile(kind: String, crew_index: int) -> Dictionary:
	var profiles: Dictionary = {
		"fire": [["Bram", "Finn"], ["Kai", "Rosa"], ["Idris", "Piper"]],
		"medic": [["Elio", "Theo"], ["Noor", "Bea"], ["Ada", "Elias"]],
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
		{"name": "Willow Cottage", "pos": Vector2(256, 84) / MAP_SIZE},
		{"name": "Moonrise Bakery", "pos": Vector2(512, 84) / MAP_SIZE},
		{"name": "Little Lantern School", "pos": Vector2(512, 540) / MAP_SIZE},
		{"name": "North Pier", "pos": Vector2(1024, 836) / MAP_SIZE},
		{"name": "The Corner Store", "pos": Vector2(256, 276) / MAP_SIZE},
		{"name": "Magnolia House", "pos": Vector2(768, 84) / MAP_SIZE},
		{"name": "Sunflower Apartments", "pos": Vector2(1024, 84) / MAP_SIZE},
		{"name": "Harbor Workshop", "pos": Vector2(1024, 276) / MAP_SIZE},
		{"name": "Juniper Gardens", "pos": Vector2(256, 540) / MAP_SIZE},
		{"name": "Pelican Cafe", "pos": Vector2(512, 276) / MAP_SIZE},
		{"name": "Beacon Clinic", "pos": Vector2(768, 276) / MAP_SIZE},
		{"name": "Old Lighthouse", "pos": Vector2(1470, 836) / MAP_SIZE},
		{"name": "Harbor Warehouse", "pos": Vector2(1280, 276) / MAP_SIZE},
		{"name": "Seabreeze Cottages", "pos": Vector2(1024, 540) / MAP_SIZE},
		{"name": "Market Square", "pos": Vector2(256, 406) / MAP_SIZE},
		{"name": "Juniper Library", "pos": Vector2(512, 406) / MAP_SIZE},
		{"name": "Eastwood Homes", "pos": Vector2(1280, 84) / MAP_SIZE},
		{"name": "Bay Transit Depot", "pos": Vector2(1280, 406) / MAP_SIZE},
		{"name": "Harbor Market", "pos": Vector2(1024, 670) / MAP_SIZE},
		{"name": "East Quay", "pos": Vector2(1280, 836) / MAP_SIZE},
		{"name": "South Park", "pos": Vector2(66, 836) / MAP_SIZE},
		{"name": "Lifeboat Station", "pos": Vector2(512, 836) / MAP_SIZE},
		{"name": "Marina Apartments", "pos": Vector2(768, 836) / MAP_SIZE},
		{"name": "Ferry Terminal", "pos": Vector2(1280, 670) / MAP_SIZE},
		{"name": "Community Hall", "pos": Vector2(768, 406) / MAP_SIZE},
		{"name": "Power Substation", "pos": Vector2(1024, 406) / MAP_SIZE},
		{"name": "Bay Stadium", "pos": Vector2(768, 540) / MAP_SIZE},
		{"name": "Seaport Museum", "pos": Vector2(1280, 540) / MAP_SIZE},
		{"name": "West Pump House", "pos": Vector2(256, 670) / MAP_SIZE},
		{"name": "Civic Apartments", "pos": Vector2(512, 670) / MAP_SIZE},
		{"name": "Harbor Hotel", "pos": Vector2(768, 670) / MAP_SIZE},
		{"name": "Coastguard Station", "pos": Vector2(256, 836) / MAP_SIZE},
		{"name": "Eastgate Homes", "pos": Vector2(1536, 276) / MAP_SIZE},
		{"name": "Orchard School", "pos": Vector2(1792, 276) / MAP_SIZE},
		{"name": "Hillcrest Clinic", "pos": Vector2(2048, 276) / MAP_SIZE},
		{"name": "East Library", "pos": Vector2(1536, 540) / MAP_SIZE},
		{"name": "Orchard Market", "pos": Vector2(1792, 540) / MAP_SIZE},
		{"name": "Reservoir Works", "pos": Vector2(2048, 540) / MAP_SIZE},
		{"name": "Cargo Terminal", "pos": Vector2(1536, 670) / MAP_SIZE},
		{"name": "Dockside Warehouse", "pos": Vector2(1792, 836) / MAP_SIZE},
		{"name": "Fisherman's Pier", "pos": Vector2(2048, 836) / MAP_SIZE},
		{"name": "South Harbor Homes", "pos": Vector2(256, 1050) / MAP_SIZE},
		{"name": "Botanical Gardens", "pos": Vector2(768, 1050) / MAP_SIZE},
		{"name": "Maritime Academy", "pos": Vector2(1280, 1050) / MAP_SIZE},
		{"name": "East Rescue Station", "pos": Vector2(1792, 1050) / MAP_SIZE},
		{"name": "South Marina", "pos": Vector2(512, 1310) / MAP_SIZE},
		{"name": "Island Clinic", "pos": Vector2(1280, 1310) / MAP_SIZE},
		{"name": "Outer Ferry Terminal", "pos": Vector2(2048, 1310) / MAP_SIZE},
		# Added Oct 2026 so calls also happen in the south and east, not mostly up north.
		{"name": "Dune Cottages", "pos": Vector2(512, 1050) / MAP_SIZE},
		{"name": "Saltmarsh Cafe", "pos": Vector2(1024, 1050) / MAP_SIZE},
		{"name": "Southgate School", "pos": Vector2(1536, 1050) / MAP_SIZE},
		{"name": "Cliffside Homes", "pos": Vector2(2048, 1050) / MAP_SIZE},
		{"name": "Kelp Street Store", "pos": Vector2(256, 1310) / MAP_SIZE},
		{"name": "Pier Market", "pos": Vector2(1024, 1310) / MAP_SIZE},
		{"name": "Tidewater Clinic", "pos": Vector2(1792, 1310) / MAP_SIZE},
		{"name": "Hillside Bakery", "pos": Vector2(1792, 670) / MAP_SIZE},
		{"name": "Eastside Pump House", "pos": Vector2(2048, 670) / MAP_SIZE},
		{"name": "Orchard Hall", "pos": Vector2(1536, 406) / MAP_SIZE},
		{"name": "Ridge Cottages", "pos": Vector2(2048, 406) / MAP_SIZE}
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

