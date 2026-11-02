"""Loaders for Beacon Bay research files (schema 3 and 4).

From 2.11 only the session leader's computer stores files in co-op. The other
players' own input is in research/<session>/players/<player key>/ with the same
file names; load_player_level() merges the leader's shared game events into it.

One "player level" = one level attempt as recorded on one player's computer:
`research/<session>/levels/<level_run_id>_events.jsonl` (all schemas) plus, from
schema 4 on, `<level_run_id>_samples_60hz.csv` next to it.

Time axis used everywhere: level seconds (`level_elapsed_s`), 0 = shift start.
The briefing before the shift has level time 0 and is cut off.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd

OWN_KEYS = ["active_incidents", "unconfirmed", "own_needed", "own_needed_known", "own_not_needed",
            "own_not_needed_known", "own_dispatched", "own_pending", "own_pending_known",
            "own_pending_urgent", "urgent", "critical", "own_min_deadline_s", "own_crews_idle",
            "own_crews_busy", "own_road_pending", "other_pending"]
URGENT_S = 20.0


@dataclass
class PlayerLevel:
    path: Path
    rows: list[dict]
    peer_id: int
    departments: list[str]
    level_number: int
    level_name: str
    level_run_id: str
    session_id: str
    schema: int
    duration_s: float
    samples: pd.DataFrame | None = None
    meta: dict = field(default_factory=dict)

    @property
    def label(self) -> str:
        return f"{'+'.join(self.departments)} L{self.level_number}"

    def events(self, *names: str) -> list[dict]:
        wanted = set(names)
        return [r for r in self.rows if r["event"] in wanted]


def read_jsonl(path: Path) -> list[dict]:
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def load_player_level(path: str | Path, attempt: int = -1) -> PlayerLevel:
    """Rows from shift start to the end of one level run (default: the last run
    in the file that reached level_ended). Rows are grouped by level_run_id, so
    a capture that was split inside one run (the 0.9.1 guest-clock bug logged a
    second level_started mid-level) is joined back into one series."""
    path = Path(path)
    rows = read_jsonl(path)
    rows = _with_leader_events(path, rows)
    runs: dict[str, list[dict]] = {}
    for row in rows:
        runs.setdefault(str(row.get("level_run_id") or ""), []).append(row)
    order = [key for key in runs if key and any(r["event"] == "level_ended" for r in runs[key])]
    chosen = runs[(order or list(runs))[attempt]]
    start = next((i for i, r in enumerate(chosen) if r["event"] == "shift_started"), 0)
    chosen = chosen[start:]
    # A split capture repeats a few seconds; keep the clock non-decreasing.
    kept, clock = [], -1.0
    for row in chosen:
        if row["event"] in ("level_started", "collection_choice") and kept:
            continue
        if row["event"] == "level_ended" and row is not chosen[-1] and any(r["event"] == "level_ended" for r in chosen[chosen.index(row) + 1:]):
            continue
        if row["level_elapsed_s"] + 1e-9 < clock and row["event"] in ("mouse_motion", "mouse_button", "context"):
            continue
        clock = max(clock, row["level_elapsed_s"])
        kept.append(row)
    chosen = kept
    first = chosen[0]
    end = next((r for r in chosen if r["event"] == "level_ended"), chosen[-1])
    level = PlayerLevel(path=path, rows=chosen, peer_id=int(first.get("peer_id", 0)),
                        departments=list(first.get("departments") or []),
                        level_number=int(first.get("level_number") or 0),
                        level_name=str(first.get("level_name") or ""),
                        level_run_id=str(first.get("level_run_id") or ""),
                        session_id=str(first.get("session_id") or ""), schema=int(first.get("schema", 3)),
                        duration_s=float(end.get("level_elapsed_s", 0.0)))
    samples = path.with_name(path.name[: -len("_events.jsonl")] + "_samples_60hz.csv") if path.name.endswith("_events.jsonl") else None
    if samples is not None and samples.exists():
        frame = pd.read_csv(samples)
        level.samples = frame[(frame.level_elapsed_s > 0) & (frame.level_elapsed_s <= level.duration_s)].reset_index(drop=True)
    return level


# Rows a player's own game records when it is not the session leader (2.11):
# its input and view. Everything else (calls, dispatches, hazards, state) is
# recorded once, in the leader's file for the same level.
LOCAL_EVENTS = {"mouse_motion", "mouse_button", "key_input", "ui_action", "crew_selected", "crew_deselected",
                "department_filter", "inspection", "command_requested", "task_state", "context", "display",
                "collection_choice", "briefing_completed", "microphone_check", "pc_check", "voice_recording",
                "clock_correction", "chaos_state_at_capture_start"}
LIFECYCLE = {"capture_started", "capture_resumed", "capture_stopped", "level_started", "level_ended",
             "sampler_started", "sampler_stopped", "sampler_error", "shift_end"}


def _with_leader_events(path: Path, rows: list[dict]) -> list[dict]:
    """A file stored by the session leader for another player
    (research/<session>/players/<key>/levels/<run>_events.jsonl) holds only
    that player's own input. Add the shared game events of the same level from
    the leader's file (research/<session>/levels/<run>_events.jsonl), in level
    time order, so per-player analysis sees the calls and dispatches too."""
    if len(path.parents) < 4 or path.parents[2].name != "players":
        return rows
    leader_file = path.parents[3] / "levels" / path.name
    if not leader_file.exists():
        return rows
    shared = [r for r in read_jsonl(leader_file) if r["event"] not in LOCAL_EVENTS and r["event"] not in LIFECYCLE]
    for r in shared:
        r["from_leader_file"] = True
    merged = rows + shared
    merged.sort(key=lambda r: (str(r.get("level_run_id") or ""), float(r.get("level_elapsed_s") or 0.0), 0 if r.get("from_leader_file") else 1))
    return merged


# ----------------------------------------------------------------- mouse

def mouse_grid(level: PlayerLevel, rate_hz: float = 30.0) -> pd.DataFrame:
    """Cursor position on a fixed level-time grid.

    Schema 4: the 60 Hz sample file (decimated to rate_hz if lower).
    Schema 3: sample-and-hold of the event rows. Those rows only exist on frames
    where the mouse moved, so their spacing follows each PC's frame rate; the
    grid removes the different row counts but cannot add detail a slow PC never
    recorded. Use 30 Hz or less for schema-3 data (the slowest PCs ran ~25-35 fps).
    """
    grid = np.arange(0.0, level.duration_s, 1.0 / rate_hz)
    if level.samples is not None and len(level.samples):
        s = level.samples
        idx = np.searchsorted(s.level_elapsed_s.values, grid, side="right") - 1
        idx = np.clip(idx, 0, len(s) - 1)
        out = pd.DataFrame({"t": grid, "x": s.x.values[idx], "y": s.y.values[idx],
                            "buttons": s.buttons.values[idx], "held": s.held.values[idx],
                            "hover_type": s.hover_type.fillna("").values[idx], "hover_id": s.hover_id.values[idx]})
        return out
    moves = [(r["level_elapsed_s"], r["data"]["x"], r["data"]["y"], r["context"].get("pointer_target", {}))
             for r in level.rows if r["event"] in ("mouse_motion", "mouse_button")]
    if not moves:
        return pd.DataFrame({"t": grid, "x": np.nan, "y": np.nan, "buttons": 0, "held": 1, "hover_type": "", "hover_id": -1})
    t = np.array([m[0] for m in moves])
    idx = np.clip(np.searchsorted(t, grid, side="right") - 1, 0, len(moves) - 1)
    fresh = np.r_[True, idx[1:] != idx[:-1]]
    hover_type = np.array([str(moves[i][3].get("type", "")) for i in idx])
    hover_id = np.array([int(moves[i][3].get("id", -1)) for i in idx])
    return pd.DataFrame({"t": grid, "x": np.array([m[1] for m in moves])[idx], "y": np.array([m[2] for m in moves])[idx],
                         "buttons": 0, "held": (~fresh).astype(int), "hover_type": hover_type, "hover_id": hover_id})


def frame_rate(level: PlayerLevel) -> pd.DataFrame:
    """Frames per second over level time.

    Schema 4 logs fps in every sample and in the 10 s `display` rows. For schema
    3 it is estimated from mouse rows: rows written in the same frame share a
    level-clock value, so consecutive distinct values during continuous movement
    are one frame apart."""
    if level.samples is not None and len(level.samples):
        s = level.samples
        return pd.DataFrame({"t": s.level_elapsed_s, "fps": s.fps})
    mm = [(r["level_elapsed_s"], r["local_elapsed_us"]) for r in level.rows if r["event"] == "mouse_motion"]
    if len(mm) < 3:
        return pd.DataFrame({"t": [], "fps": []})
    g = np.array([m[0] for m in mm])
    w = np.array([m[1] for m in mm]) / 1e6
    keep = np.r_[True, g[1:] != g[:-1]]
    g, w = g[keep], w[keep]
    dw = np.diff(w) * 1000
    ok = (dw < 100) & (np.diff(g) > 0)
    return pd.DataFrame({"t": g[:-1][ok], "fps": 1000.0 / dw[ok]})


# ----------------------------------------------------------------- task load

def _incident_table(level: PlayerLevel) -> dict[int, dict]:
    """Lifecycle of every call from the shared game events in this file."""
    calls: dict[int, dict] = {}
    for r in level.rows:
        d, e = r["data"], r["event"]
        iid = int(d.get("incident_id", -1)) if isinstance(d, dict) else -1
        if e == "incident_started" and iid >= 0:
            calls[iid] = {"id": iid, "kind": d.get("event_type"), "created": float(d.get("started_at", d.get("at", r["level_elapsed_s"]))),
                          "needs": {k: int(v) for k, v in (d.get("needs") or {}).items() if int(v) > 0},
                          "max_deadline": float(d.get("max_deadline", 60.0)), "discovered_at": None if not d.get("discovered", True) else float(d.get("started_at", d.get("at", 0.0))),
                          "ended": None, "outcome": None, "assign": [], "time_added": [], "critical_at": None}
        if iid not in calls:
            continue
        c = calls[iid]
        at = float(d.get("at", r["level_elapsed_s"])) if isinstance(d, dict) else r["level_elapsed_s"]
        if e == "dispatch":
            c["assign"].append((at, int(d.get("unit_id", -1)), str(d.get("kind", "")), +1, int(d.get("actor_peer", 0))))
        if e in ("unit_withdrawn", "dispatch_mismatch"):
            c["assign"].append((at, int(d.get("unit_id", -1)), str(d.get("kind", "")), -1, int(d.get("actor_peer", 0))))
        # Scouting, a crew's field report or a mismatched crew reveal the needs.
        if e in ("scout", "field_report", "dispatch_mismatch") and c["discovered_at"] is None:
            c["discovered_at"] = at
        if e in ("scout", "supply") and float(d.get("time_added", 0.0)) > 0:
            c["time_added"].append((at, float(d["time_added"])))
        if e == "critical" and c["critical_at"] is None:
            c["critical_at"] = at
        if e == "incident_ended":
            c["ended"] = float(d.get("ended_at", at))
            c["outcome"] = d.get("outcome")
    return calls


def task_load(level: PlayerLevel, rate_hz: float = 1.0) -> pd.DataFrame:
    """Anja's task-load variables on a fixed grid, from this player's point of view.

    Schema 4: read from the sample file (computed live in the game).
    Schema 3: reconstructed from the shared event stream (incident needs,
    dispatches, withdrawals, discovery, deadlines). Deadlines are approximate:
    they ignore rapid-response and storm effects.
    """
    grid = np.arange(0.0, level.duration_s, 1.0 / rate_hz)
    if level.samples is not None and len(level.samples):
        s = level.samples
        idx = np.clip(np.searchsorted(s.level_elapsed_s.values, grid, side="right") - 1, 0, len(s) - 1)
        out = s.iloc[idx][[k for k in OWN_KEYS if k in s.columns]].reset_index(drop=True)
        out.insert(0, "t", grid)
        return out
    own = set(level.departments)
    calls = _incident_table(level)
    rows = []
    for t in grid:
        v = dict.fromkeys(OWN_KEYS, 0)
        v["own_min_deadline_s"] = -1.0
        for c in calls.values():
            if c["created"] > t or (c["ended"] is not None and c["ended"] <= t):
                continue
            v["active_incidents"] += 1
            known = c["discovered_at"] is not None and c["discovered_at"] <= t
            if not known:
                v["unconfirmed"] += 1
            deadline = c["max_deadline"] - (t - c["created"]) + sum(a for at, a in c["time_added"] if at <= t)
            urgent = deadline < URGENT_S
            v["urgent"] += urgent
            v["critical"] += c["critical_at"] is not None and c["critical_at"] <= t
            assigned: dict[str, set] = {}
            for at, unit, kind, sign, _ in c["assign"]:
                if at > t:
                    continue
                crews = assigned.setdefault(kind, set())
                if sign > 0:
                    crews.add(unit)
                else:
                    crews.discard(unit)
            own_need = sum(n for k, n in c["needs"].items() if k in own)
            own_missing = sum(max(0, n - len(assigned.get(k, ()))) for k, n in c["needs"].items() if k in own)
            other_missing = sum(max(0, n - len(assigned.get(k, ()))) for k, n in c["needs"].items() if k not in own)
            v["other_pending"] += other_missing > 0
            if own_need == 0:
                v["own_not_needed"] += 1
                v["own_not_needed_known"] += known
                continue
            v["own_needed"] += 1
            v["own_needed_known"] += known
            if own_missing == 0:
                v["own_dispatched"] += 1
                continue
            v["own_pending"] += 1
            v["own_pending_known"] += known
            v["own_pending_urgent"] += urgent
            if v["own_min_deadline_s"] < 0 or deadline < v["own_min_deadline_s"]:
                v["own_min_deadline_s"] = deadline
        v["t"] = t
        rows.append(v)
    return pd.DataFrame(rows)[["t"] + OWN_KEYS]


def phases(level: PlayerLevel) -> pd.DataFrame:
    """Researcher-defined load phases from the hidden chaos schedule
    (`chaos_phase_changed`: normal / high / ...)."""
    rows = [(float(r["data"].get("at", r["level_elapsed_s"])), str(r["data"].get("phase"))) for r in level.events("chaos_phase_changed")]
    rows.sort()
    out = []
    for i, (at, phase) in enumerate(rows):
        until = rows[i + 1][0] if i + 1 < len(rows) else level.duration_s
        out.append({"start": at, "end": until, "phase": phase})
    return pd.DataFrame(out)


# ----------------------------------------------------------------- voice

def speech_activity(voice_dir: str | Path, level_run_id: str) -> dict[int, list[tuple[float, float]]]:
    """Speaking intervals per peer in level seconds, from a voice session folder.
    Audio frames map to level time through the recorder's clock_sync markers."""
    voice_dir = Path(voice_dir)
    session = json.loads((voice_dir / "session.json").read_text(encoding="utf-8"))
    sync = [(r["audio_frame"], float(r["data"]["level_elapsed_s"])) for r in read_jsonl(voice_dir / "timeline.jsonl")
            if r["event"] == "clock_sync" and r["data"].get("level_run_id") == level_run_id]
    if len(sync) < 2:
        return {}
    frames = np.array([s[0] for s in sync], dtype=float)
    level_s = np.array([s[1] for s in sync])
    result: dict[int, list[tuple[float, float]]] = {}
    for a in session.get("audio_activity", []):
        start, end = float(a["start_frame"]), float(a["end_frame"])
        if end < frames[0] or start > frames[-1]:
            continue
        # 2.11: speaker_id is the player ("player_<key>"), stable across
        # reconnects; peer_id is the network id at that moment.
        peer = int(a["peer_id"]) if "peer_id" in a else int(str(a["speaker_id"]).replace("peer_", ""))
        t0, t1 = np.interp([start, end], frames, level_s)
        if t1 > t0:
            result.setdefault(peer, []).append((float(t0), float(t1)))
    return result
