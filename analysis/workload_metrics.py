"""Behavioural workload metrics per player in fixed level-time windows."""
from __future__ import annotations

import numpy as np
import pandas as pd

from beacon_logs import PlayerLevel, frame_rate, mouse_grid, phases, task_load

GRID_HZ = 30.0      # common grid for schema-3 and schema-4 data
IDLE_PX = 2.0       # movement below this per grid step counts as still
PAUSE_S = 0.1       # stillness shorter than this is not a pause
LOAD_COLUMNS = ["active_incidents", "own_needed", "own_not_needed", "own_dispatched", "own_pending",
                "own_pending_known", "own_pending_urgent", "urgent", "critical", "unconfirmed", "other_pending"]
METRICS = ["mouse_speed_px_s", "mouse_idle_share", "mouse_moves_per_s", "mouse_turns_per_s",
           "clicks_per_min", "inter_click_s", "denied_per_min", "dispatches_per_min",
           "inspections_per_min", "hover_switches_per_min", "speech_share"]


def window_metrics(level: PlayerLevel, window_s: float = 10.0, speech: list[tuple[float, float]] | None = None,
                   timeline: pd.DataFrame | None = None) -> pd.DataFrame:
    grid = mouse_grid(level, GRID_HZ)
    xy = grid[["x", "y"]].to_numpy(float)
    step = np.r_[0.0, np.hypot(*np.diff(xy, axis=0).T)]
    # "Still" = no movement for at least PAUSE_S. A single unchanged grid step is
    # not a pause: on a PC below the grid rate it is just a frame the game did
    # not render (schema 3), and counting it would inflate pauses on slow PCs.
    raw_moving = step >= IDLE_PX
    moving = raw_moving.copy()
    run = int(np.ceil(PAUSE_S * GRID_HZ))
    i = 0
    while i < len(raw_moving):
        if raw_moving[i]:
            i += 1
            continue
        j = i
        while j < len(raw_moving) and not raw_moving[j]:
            j += 1
        if j - i < run:
            moving[i:j] = True
        i = j
    heading = np.r_[0.0, np.arctan2(*np.diff(xy, axis=0).T[::-1])]
    turn = np.r_[0.0, np.abs(np.angle(np.exp(1j * np.diff(heading))))] > np.pi / 2
    turns = turn & raw_moving & np.r_[False, raw_moving[:-1]]
    onsets = moving & ~np.r_[False, moving[:-1]]
    hover = np.where(grid.hover_type.values == "call", grid.hover_id.values, -1)
    hover_switch = np.r_[False, (hover[1:] != hover[:-1]) & (hover[1:] >= 0)]
    load = task_load(level, rate_hz=1.0)
    fps = frame_rate(level)
    raw_motion = np.array([r["level_elapsed_s"] for r in level.rows if r["event"] == "mouse_motion"])
    me = level.peer_id

    def times(event: str, test=lambda r: True) -> np.ndarray:
        return np.array([r["level_elapsed_s"] for r in level.rows if r["event"] == event and test(r)])

    clicks = times("mouse_button", lambda r: bool(r["data"].get("pressed")) and int(r["data"].get("button", 0)) in (1, 2, 3))
    denied = times("command_result", lambda r: int(r["data"].get("actor_peer", 0)) == me and not r["data"].get("accepted", True))
    dispatches = times("dispatch", lambda r: int(r["data"].get("actor_peer", 0)) == me)
    inspections = times("inspection")
    phase_table = phases(level)
    rows = []
    for t0 in np.arange(0.0, level.duration_s - window_s + 1e-6, window_s):
        t1 = t0 + window_s
        g = (grid.t.values >= t0) & (grid.t.values < t1)
        row = {"player": level.label, "peer_id": me, "departments": "+".join(level.departments),
               "level": level.level_number, "t0": t0, "t1": t1,
               "mouse_speed_px_s": step[g].sum() / window_s,
               "mouse_idle_share": float((~moving[g]).mean()),
               "mouse_moves_per_s": onsets[g].sum() / window_s,
               "mouse_turns_per_s": turns[g].sum() / window_s,
               "clicks_per_min": ((clicks >= t0) & (clicks < t1)).sum() * 60 / window_s,
               "denied_per_min": ((denied >= t0) & (denied < t1)).sum() * 60 / window_s,
               "dispatches_per_min": ((dispatches >= t0) & (dispatches < t1)).sum() * 60 / window_s,
               "inspections_per_min": ((inspections >= t0) & (inspections < t1)).sum() * 60 / window_s,
               "hover_switches_per_min": hover_switch[g].sum() * 60 / window_s,
               "held_share": float(grid.held.values[g].mean()),
               "raw_motion_rows_per_s": ((raw_motion >= t0) & (raw_motion < t1)).sum() / window_s}
        in_window = clicks[(clicks >= t0) & (clicks < t1)]
        row["inter_click_s"] = float(np.median(np.diff(in_window))) if len(in_window) > 2 else np.nan
        f = fps[(fps.t >= t0) & (fps.t < t1)].fps
        row["fps"] = float(f.median()) if len(f) >= 10 else np.nan
        lw = load[(load.t >= t0) & (load.t < t1)]
        for col in LOAD_COLUMNS:
            row[col] = float(lw[col].mean()) if col in lw and len(lw) else np.nan
        if speech is not None:
            spoken = sum(max(0.0, min(b, t1) - max(a, t0)) for a, b in speech)
            row["speech_share"] = spoken / window_s
        else:
            row["speech_share"] = np.nan
        mid = (t0 + t1) / 2
        hit = phase_table[(phase_table.start <= mid) & (phase_table.end > mid)] if len(phase_table) else phase_table
        row["phase"] = str(hit.phase.iloc[0]) if len(hit) else ""
        if timeline is not None and len(timeline):
            done = timeline[(timeline.dispatched_s >= t0) & (timeline.dispatched_s < t1)] if "dispatched_s" in timeline else timeline.iloc[0:0]
            for col in ("decision_time_s", "execution_time_s", "response_time_s"):
                row[col] = float(done[col].mean()) if len(done) and col in done and done[col].notna().any() else np.nan
        rows.append(row)
    return pd.DataFrame(rows)
