class_name BeaconCampaign
extends RefCounted


static func shifts() -> Array[Dictionary]:
	var scenarios: Array[Dictionary] = [
		{"title": "FIRST LIGHT", "subtitle": "A small town. A very big heart.", "weather": "clear", "target": 30, "introduction": "Select a call. Send the matching crew. Bring everyone home.", "accent": "66dbc0", "interval": 23.0, "max_active": 4, "weights": [4, 5, 1, 2], "disruptions": [{"at": 112.0, "type": "market", "duration": 35.0, "text": "Morning market • busy streets slow travel"}, {"at": 224.0, "type": "clear", "duration": 25.0, "text": "Neighbors lend a hand • crews work faster"}]},
		{"title": "MARKET DAY", "subtitle": "The festival is counting on you.", "weather": "golden", "target": 42, "introduction": "Some calls need two teams. Scout a call for extra breathing room.", "accent": "ffd17b", "interval": 20.5, "max_active": 4, "weights": [4, 5, 2, 3], "disruptions": [{"at": 95.0, "type": "roadworks", "duration": 48.0, "text": "Bridge works • crews are taking a detour"}, {"at": 205.0, "type": "festival", "duration": 48.0, "text": "Festival rush • extra calls from the square"}]},
		{"title": "RISING WATER", "subtitle": "Keep the harbor's lights alive.", "weather": "rain", "target": 44, "introduction": "Flood calls need engineers and medics. Supplies buy precious time.", "accent": "7bc8f0", "interval": 19.0, "max_active": 4, "weights": [2, 3, 7, 3], "disruptions": [{"at": 85.0, "type": "rain", "duration": 58.0, "text": "Cloudburst • flood calls intensify"}, {"at": 211.0, "type": "shortage", "duration": 45.0, "text": "Supply delay • supply replenishment paused"}]},
		{"title": "AFTER DARK", "subtitle": "Be the calm in the blackout.", "weather": "night", "target": 60, "introduction": "Unconfirmed calls reward scouting. Keep an engineer in reserve.", "accent": "bda6ff", "interval": 17.5, "max_active": 5, "weights": [3, 4, 2, 7], "disruptions": [{"at": 93.0, "type": "blackout", "duration": 56.0, "text": "Grid failure • scout unconfirmed calls for a clear picture"}, {"at": 213.0, "type": "comms", "duration": 44.0, "text": "Radio interference • incoming reports need a closer look"}]},
		{"title": "STORMFRONT", "subtitle": "Different teams. One heartbeat.", "weather": "storm", "target": 64, "introduction": "Use Rally when calls pile up. It speeds every crew for twenty seconds.", "accent": "8cceef", "interval": 16.0, "max_active": 5, "weights": [4, 4, 6, 5], "disruptions": [{"at": 82.0, "type": "storm", "duration": 62.0, "text": "Storm surge • travel slows; every second matters"}, {"at": 202.0, "type": "shortage", "duration": 40.0, "text": "Warehouse flooded • make the supplies you have count"}]},
		{"title": "BEACON NIGHT", "subtitle": "A whole town, looking out for each other.", "weather": "sunset", "target": 72, "introduction": "Your final watch. Use every lesson, every upgrade, every teammate.", "accent": "ffa784", "interval": 14.5, "max_active": 5, "weights": [5, 5, 5, 5], "disruptions": [{"at": 75.0, "type": "comms", "duration": 44.0, "text": "Radio interference • trust your field reports"}, {"at": 167.0, "type": "storm", "duration": 51.0, "text": "One last squall • the bay needs all of us"}, {"at": 254.0, "type": "clear", "duration": 60.0, "text": "The beacon shines • neighbors help finish the watch"}]}
	]
	var intervals: Array[float] = [18.5, 16.7, 15.5, 14.3, 13.2, 12.2]
	var capacities: Array[int] = [4, 5, 5, 6, 6, 6]
	
	var rescue_targets: Array[int] = [60, 72, 78, 90, 104, 116]
	var wave_names: Array[String] = ["School bell rush", "Festival overflow", "Harbor rescue wave", "Citywide grid failure", "Storm emergency wave", "All-stations response"]
	for index: int in range(scenarios.size()):
		scenarios[index].interval = intervals[index]
		scenarios[index].max_active = capacities[index]
		scenarios[index].target = rescue_targets[index]
		scenarios[index].surges = []
		scenarios[index].traffic = [
			{"at": 12.0, "duration": 55.0, "name": "School crossing", "position": Vector2(0.375, 0.19), "size": Vector2(0.05, 0.28), "speed_factor": 0.45},
			{"at": 154.0, "duration": 46.0, "name": "Harbor deliveries", "position": Vector2(0.62, 0.425), "size": Vector2(0.30, 0.05), "speed_factor": 0.50}
		]
		var wave_times: Array = [42.0, 112.0, 182.0, 246.0] if index == 0 else [32.0, 94.0, 166.0, 239.0]
		for wave: int in range(wave_times.size()):
			scenarios[index].surges.append({"at": wave_times[wave], "name": wave_names[index], "calls": 2 if index < 2 else 3, "duration": 18.0 + index, "breather": 9.0 if index < 3 else 12.0})
	return scenarios

static func shift_data(index: int) -> Dictionary:
	return shifts()[clampi(index, 0, 5)].duplicate(true)

static func upgrades() -> Array[Dictionary]:
	return [
		{"id": "engines", "name": "Quick wheels", "description": "Crews travel 14% faster per level.", "cost": 65, "max_level": 3, "icon": "speed", "kind": "fleet"},
		{"id": "training", "name": "Steady hands", "description": "Rescue work is 12% faster per level.", "cost": 80, "max_level": 3, "icon": "heart", "kind": "team"},
		{"id": "radio", "name": "Clear signal", "description": "Every new call gets 7 extra seconds per level.", "cost": 70, "max_level": 2, "icon": "radio", "kind": "support"},
		{"id": "supplies", "name": "Ready supplies", "description": "Carry one more supply; deliveries arrive 5 seconds sooner.", "cost": 60, "max_level": 3, "icon": "box", "kind": "support"},
		{"id": "fire_crew", "name": "Ember brigade", "description": "Add a permanent fire crew to your fleet.", "cost": 115, "max_level": 1, "icon": "fire", "kind": "fleet"},
		{"id": "medic_crew", "name": "Kindred care", "description": "Add a permanent medical crew to your fleet.", "cost": 115, "max_level": 1, "icon": "medic", "kind": "fleet"},
		{"id": "engineer_crew", "name": "Harbor hands", "description": "Add a permanent engineering crew to your fleet.", "cost": 115, "max_level": 1, "icon": "engineer", "kind": "fleet"},
		{"id": "rest", "name": "Good coffee", "description": "Crews recover sooner and tire 35% less per level.", "cost": 55, "max_level": 2, "icon": "coffee", "kind": "team"},
		{"id": "rally", "name": "Town spirit", "description": "Rally recharges 15 seconds sooner per level.", "cost": 85, "max_level": 2, "icon": "star", "kind": "support"},
		{"id": "scouting", "name": "Local knowledge", "description": "Scouting grants 6 more seconds and 10% faster work.", "cost": 60, "max_level": 2, "icon": "eye", "kind": "team"}
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
		"engineer": [["Tess", "Niko"], ["Olavi", "Zara"], ["Esme", "Otto"]]
	}
	var kind_index: int = ["fire", "medic", "engineer"].find(kind)
	var pair: Array = profiles.get(kind, profiles.fire)[clampi(crew_index, 0, 2)]
	return {"crew_name": str(pair[0]), "partner_name": str(pair[1]), "appearance": maxi(0, kind_index) * 3 + clampi(crew_index, 0, 2)}

static func locations() -> Array[Dictionary]:
	return [
		{"name": "Willow Cottage", "pos": Vector2(64, 44) / Vector2(532, 316)},
		{"name": "Moonrise Bakery", "pos": Vector2(171, 41) / Vector2(532, 316)},
		{"name": "Little Lantern School", "pos": Vector2(268, 199) / Vector2(532, 316)},
		{"name": "North Pier", "pos": Vector2(355, 286) / Vector2(532, 316)},
		{"name": "The Corner Store", "pos": Vector2(128, 115) / Vector2(532, 316)},
		{"name": "Magnolia House", "pos": Vector2(411, 34) / Vector2(532, 316)},
		{"name": "Sunflower Apartments", "pos": Vector2(488, 35) / Vector2(532, 316)},
		{"name": "Harbor Workshop", "pos": Vector2(384, 117) / Vector2(532, 316)},
		{"name": "Juniper Gardens", "pos": Vector2(53, 199) / Vector2(532, 316)},
		{"name": "Pelican Cafe", "pos": Vector2(174, 119) / Vector2(532, 316)},
		{"name": "Beacon Clinic", "pos": Vector2(268, 121) / Vector2(532, 316)},
		{"name": "Old Lighthouse", "pos": Vector2(514, 201) / Vector2(532, 316)},
		{"name": "Harbor Warehouse", "pos": Vector2(487, 111) / Vector2(532, 316)},
		{"name": "Seabreeze Cottages", "pos": Vector2(366, 201) / Vector2(532, 316)},
		{"name": "Market Square", "pos": Vector2(153, 254) / Vector2(532, 316)},
		{"name": "Juniper Library", "pos": Vector2(179, 201) / Vector2(532, 316)}
	]

static func incident_title(kind: String, severity: int, variant: int) -> String:
	var titles: Dictionary = {
		"fire": ["Kitchen smoke", "Sparking fuse", "Workshop fire", "Chimney blaze", "Rooftop fire"],
		"medical": ["A neighbor needs help", "Bicycle tumble", "Heat exhaustion", "First aid needed", "Urgent care"],
		"flood": ["Basement rising", "Stranded neighbors", "Burst water main", "Overflowing harbor", "Flooded walkway"],
		"power": ["Lights out", "Fallen power line", "Lift stopped", "Signal failure", "Generator trouble"]
	}
	var list: Array = titles.get(kind, titles.medical)
	return str(list[(variant + severity - 1) % list.size()])

