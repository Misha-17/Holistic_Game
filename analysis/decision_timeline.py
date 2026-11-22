"""Decision making vs decision execution per call and player.

Definitions (see docs/VARIABLES.md, "Derived: decision timeline"):

  onset          the player can know the call needs their department: the call
                 appears already confirmed, or it is confirmed later (scout,
                 field report, mismatched crew).
  first_look     first time the cursor rests on the call (pin or card) after
                 onset. Schema 4: 60 Hz samples (hover_type == "call"); schema 3:
                 pointer target of the event rows.
  first_inspect  first time the player selected the call (information gathering).
  commit         the player commits a resource: selects the crew that is then
                 sent, after their previous command. A number-key dispatch
                 (1-4 over a call) commits and sends in one input, so commit =
                 command and execution is ~0 by design (dispatch_input = "key").
  command        the player's dispatch request (command_requested).
  dispatched     the game accepted it (dispatch event by this player).
  arrived        the crew reached the call (crew_arrived for that crew).

  decision_time_s   = commit     - onset   (noticing, reading, choosing a crew)
  execution_time_s  = dispatched - commit  (acting the decision out in the UI)
  field_time_s      = arrived    - dispatched   (travel; not a human measure)
  response_time_s   = dispatched - onset   (= decision + execution)

Schema 3 logged crew selection only from the crew cards. A crew picked on the
map left no record, so there the commit time is unknown: dispatch_input =
"unknown", execution_time_s is empty and only response_time_s is valid.
Schema 4 logs every crew selection (crew_selected), whatever the input.

Calls the player never dispatched to keep onset and outcome with empty times
(censored), so they are not lost from "pending" analyses.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from beacon_logs import PlayerLevel, _incident_table, mouse_grid


def _selections(level: PlayerLevel) -> list[tuple[float, str, int]]:
    """Local selection inputs as (level_s, kind, id); kind is crew/call/command."""
    out: list[tuple[float, str, int]] = []
    me = level.peer_id
    for r in level.rows:
        e, d, t = r["event"], r["data"], r["level_elapsed_s"]
        if e == "crew_selected":
            out.append((t, "crew", int(d.get("unit_id", -1))))
        elif e == "ui_action" and str(d.get("action", "")).startswith("unit:") and level.schema < 4:
            out.append((t, "crew", int(str(d["action"]).split(":", 1)[1])))
        elif e == "inspection":
            out.append((t, "call", int(d.get("incident_id", -1))))
        elif e == "command_requested" and int(d.get("actor_peer", me)) == me:
            payload = d.get("payload") or {}
            out.append((t, "command", int(payload.get("incident_id", payload.get("road_event_id", -1)))))
    return out


def decision_timeline(level: PlayerLevel) -> pd.DataFrame:
    own = set(level.departments)
    calls = _incident_table(level)
    picks = _selections(level)
    me = level.peer_id
    grid = mouse_grid(level, rate_hz=30.0)
    hover_t = grid.t.values
    hover_call = np.where(grid.hover_type.values == "call", grid.hover_id.values, -1)
    commands = [r for r in level.rows if r["event"] == "command_requested" and int(r["data"].get("actor_peer", me)) == me
                and r["data"].get("action") == "dispatch"]
    keys = np.array([r["level_elapsed_s"] for r in level.rows if r["event"] == "key_input" and r["data"].get("pressed")])
    arrivals = [(float(r["data"].get("at", r["level_elapsed_s"])), int(r["data"].get("unit_id", -1)), int(r["data"].get("incident_id", -1)))
                for r in level.rows if r["event"] == "crew_arrived"]
    rows = []
    for c in calls.values():
        own_needs = {k: n for k, n in c["needs"].items() if k in own}
        if not own_needs:
            continue
        onset = c["discovered_at"]
        row = {"player": level.label, "peer_id": me, "level": level.level_number, "incident_id": c["id"], "kind": c["kind"],
               "own_crews_needed": sum(own_needs.values()), "created_s": c["created"], "onset_s": onset,
               "ended_s": c["ended"], "outcome": c["outcome"]}
        if onset is not None:
            looks = np.nonzero((hover_call == c["id"]) & (hover_t >= onset))[0]
            row["first_look_s"] = float(hover_t[looks[0]]) if len(looks) else None
        mine = [a for a in c["assign"] if a[3] > 0 and a[2] in own and a[4] == me]
        if mine:
            dispatched, unit = mine[0][0], mine[0][1]
            command = next((r for r in commands if int(r["data"]["payload"].get("incident_id", -1)) == c["id"]
                            and r["level_elapsed_s"] <= dispatched + 0.5), None)
            command_s = command["level_elapsed_s"] if command else dispatched
            previous = max([t for t, kind, _ in picks if kind == "command" and t < command_s - 1e-6], default=-1.0)
            commits = [t for t, kind, ident in picks if previous < t <= command_s and kind == "crew" and ident == unit]
            inspects = [t for t, kind, ident in picks if kind == "call" and ident == c["id"] and t >= (onset or c["created"])]
            key_near = bool(len(keys)) and bool(np.any((keys <= command_s + 1e-6) & (keys >= command_s - 0.25)))
            if commits:
                commit, how = min(commits), "click"
            elif key_near:
                commit, how = command_s, "key"
            else:
                commit, how = None, "unknown"
            arrived = next((t for t, u, i in arrivals if u == unit and i == c["id"] and t >= dispatched), None)
            row.update({"first_inspect_s": min(inspects) if inspects else None, "commit_s": commit, "command_s": command_s,
                        "dispatched_s": dispatched, "arrived_s": arrived, "unit_id": unit, "dispatch_input": how})
            if onset is not None:
                row["response_time_s"] = max(0.0, dispatched - onset)
                if commit is not None:
                    row["decision_time_s"] = max(0.0, commit - onset)
            if commit is not None:
                row["execution_time_s"] = max(0.0, dispatched - commit)
            row["field_time_s"] = (arrived - dispatched) if arrived is not None else None
        rows.append(row)
    return pd.DataFrame(rows)
