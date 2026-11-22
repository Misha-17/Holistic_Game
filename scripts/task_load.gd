class_name BeaconTaskLoad
extends RefCounted

## Task load from one player's point of view (client feedback 01.11, Anja).
## "Own" means a department this player commands. An incident needs the own
## unit when its needs list one of those departments. The decision is pending
## while fewer own crews are assigned than it needs; assigned crews count from
## the moment they are dispatched (en route), not only when they arrive.
## "_known" variants only count calls the player can read: an unconfirmed call
## (discovered = false) hides its needs until it is scouted or a crew confirms it.

const URGENT_S := 20.0 # main.gd uses the same threshold for "urgent_incidents"

## Column order of the numeric task-load block in the 60 Hz sample file.
const KEYS: Array[String] = ["active_incidents", "unconfirmed", "own_needed", "own_needed_known",
	"own_not_needed", "own_not_needed_known", "own_dispatched", "own_pending", "own_pending_known",
	"own_pending_urgent", "urgent", "critical", "own_min_deadline_s", "own_crews_idle", "own_crews_busy",
	"own_road_pending", "other_pending"]

static func compute(sim, departments: Array) -> Dictionary:
	var result := {}
	for key: String in KEYS: result[key] = 0
	result["own_min_deadline_s"] = -1.0
	if sim == null: return result
	var unit_kind := {}
	for unit: Dictionary in sim.units:
		unit_kind[int(unit.id)] = str(unit.kind)
		if str(unit.kind) in departments:
			if str(unit.state) == "idle": result.own_crews_idle += 1
			elif str(unit.state) in ["travel", "working", "clearing"]: result.own_crews_busy += 1
	for incident: Dictionary in sim.incidents:
		if str(incident.get("status", "")) not in ["active", "working"]: continue
		result.active_incidents += 1
		var known := bool(incident.get("discovered", true))
		if not known: result.unconfirmed += 1
		var deadline := float(incident.get("deadline", 0.0))
		var urgent := deadline < URGENT_S
		if urgent: result.urgent += 1
		if bool(incident.get("critical_sent", false)): result.critical += 1
		var own_missing := 0
		var own_needed := 0
		var other_missing := 0
		var needs: Dictionary = incident.get("needs", {})
		for kind: String in needs:
			var needed := int(needs[kind])
			if needed <= 0: continue
			var assigned := 0
			for unit_id in incident.get("assigned", []):
				if unit_kind.get(int(unit_id), "") == kind: assigned += 1
			var missing := maxi(0, needed - assigned)
			if kind in departments:
				own_needed += needed
				own_missing += missing
			else:
				other_missing += missing
		if other_missing > 0: result.other_pending += 1
		if own_needed == 0:
			result.own_not_needed += 1
			if known: result.own_not_needed_known += 1
			continue
		result.own_needed += 1
		if known: result.own_needed_known += 1
		if own_missing == 0:
			result.own_dispatched += 1
			continue
		result.own_pending += 1
		if known: result.own_pending_known += 1
		if urgent: result.own_pending_urgent += 1
		if result.own_min_deadline_s < 0.0 or deadline < result.own_min_deadline_s: result.own_min_deadline_s = deadline
	for road: Dictionary in sim.road_events:
		if str(road.get("status", "")) == "active" and str(road.get("clear_kind", "")) in departments and int(road.get("assigned_unit", -1)) < 0:
			result.own_road_pending += 1
	return result

## Per-call view for the 1 Hz "task_state" row: what each open call needs from
## this player and whether the player has acted on it.
static func incidents(sim, departments: Array) -> Array:
	var rows: Array = []
	if sim == null: return rows
	var unit_kind := {}
	for unit: Dictionary in sim.units: unit_kind[int(unit.id)] = str(unit.kind)
	for incident: Dictionary in sim.incidents:
		if str(incident.get("status", "")) not in ["active", "working"]: continue
		var needs: Dictionary = incident.get("needs", {})
		var own_needed := 0
		var own_assigned := 0
		var other_missing := 0
		for kind: String in needs:
			var needed := int(needs[kind])
			var assigned := 0
			for unit_id in incident.get("assigned", []):
				if unit_kind.get(int(unit_id), "") == kind: assigned += 1
			if kind in departments:
				own_needed += needed
				own_assigned += mini(assigned, needed)
			else:
				other_missing += maxi(0, needed - assigned)
		rows.append({"incident_id": int(incident.id), "kind": str(incident.kind),
			"status": str(incident.status), "discovered": bool(incident.get("discovered", true)),
			"own_needed": own_needed, "own_assigned": own_assigned,
			"own_state": "not_needed" if own_needed == 0 else ("dispatched" if own_assigned >= own_needed else "pending"),
			"other_missing": other_missing, "deadline_s": float(incident.get("deadline", 0.0)),
			"urgent": float(incident.get("deadline", 0.0)) < URGENT_S, "critical": bool(incident.get("critical_sent", false)),
			"hazard_stage": int(incident.get("hazard_stage", 0)), "age_s": float(sim.elapsed) - float(incident.get("created_at", sim.elapsed))})
	return rows
