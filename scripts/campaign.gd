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
		{"title": "FIRST LIGHT", "subtitle": "A small town. A very big heart.", "weather": "clear", "target": 30, "introduction": "Select a call. Send the matching crew. Bring everyone home.", "accent": "66dbc0", "interval": 23.0, "max_active": 4, "weights": [4, 5, 1, 2, 3], "disruptions": [{"at": 112.0, "type": "market", "duration": 35.0, "text": "Morning market • busy streets slow travel"}, {"at": 224.0, "type": "clear", "duration": 25.0, "text": "Neighbors lend a hand • crews work faster"}]},
		{"title": "MARKET DAY", "subtitle": "The festival is counting on you.", "weather": "golden", "target": 42, "introduction": "Some calls need two teams. Scout a call for extra breathing room.", "accent": "ffd17b", "interval": 20.5, "max_active": 4, "weights": [4, 5, 2, 3, 5], "disruptions": [{"at": 95.0, "type": "roadworks", "duration": 48.0, "text": "Bridge works • crews are taking a detour"}, {"at": 205.0, "type": "festival", "duration": 48.0, "text": "Festival rush • extra calls from the square"}]},
		{"title": "RISING WATER", "subtitle": "Keep the harbor's lights alive.", "weather": "rain", "target": 44, "introduction": "Flood calls need engineers and medics. Supplies buy precious time.", "accent": "7bc8f0", "interval": 19.0, "max_active": 4, "weights": [2, 3, 7, 3, 2], "disruptions": [{"at": 85.0, "type": "rain", "duration": 58.0, "text": "Cloudburst • flood calls intensify"}, {"at": 211.0, "type": "shortage", "duration": 45.0, "text": "Supply delay • supply replenishment paused"}]},
		{"title": "AFTER DARK", "subtitle": "Be the calm in the blackout.", "weather": "night", "target": 60, "introduction": "Unconfirmed calls reward scouting. Keep an engineer in reserve.", "accent": "bda6ff", "interval": 17.5, "max_active": 5, "weights": [3, 4, 2, 7, 3], "disruptions": [{"at": 93.0, "type": "blackout", "duration": 56.0, "text": "Grid failure • scout unconfirmed calls for a clear picture"}, {"at": 213.0, "type": "comms", "duration": 44.0, "text": "Radio interference • incoming reports need a closer look"}]},
		{"title": "STORMFRONT", "subtitle": "Different teams. One heartbeat.", "weather": "storm", "target": 64, "introduction": "Use the coffee boost when calls pile up. It speeds every crew for twenty seconds.", "accent": "8cceef", "interval": 16.0, "max_active": 5, "weights": [4, 4, 6, 5, 3], "disruptions": [{"at": 82.0, "type": "storm", "duration": 62.0, "text": "Storm surge • travel slows; every second matters"}, {"at": 202.0, "type": "shortage", "duration": 40.0, "text": "Warehouse flooded • make the supplies you have count"}]},
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
		scenarios[index].traffic = [
			{"at": 12.0, "duration": 55.0, "name": "School crossing", "position": Vector2(364, 178) / MAP_SIZE, "size": Vector2(40, 240) / MAP_SIZE, "speed_factor": 0.45},
			{"at": 154.0, "duration": 46.0, "name": "Harbor deliveries", "position": Vector2(876, 684) / MAP_SIZE, "size": Vector2(390, 40) / MAP_SIZE, "speed_factor": 0.50}
		]
	return scenarios

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
		"engineer": [["Tess", "Niko"], ["Olavi", "Zara"], ["Esme", "Otto"]],
		"police": [["Nova", "Juno"], ["Mika", "Remy"], ["Sol", "Ines"]]
	}
	var kind_index: int = ["fire", "medic", "engineer", "police"].find(kind)
	var pair: Array = profiles.get(kind, profiles.fire)[clampi(crew_index, 0, 2)]
	return {"crew_name": str(pair[0]), "partner_name": str(pair[1]), "appearance": maxi(0, kind_index) * 3 + clampi(crew_index, 0, 2)}

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
		{"name": "Outer Ferry Terminal", "pos": Vector2(2048, 1310) / MAP_SIZE}
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

