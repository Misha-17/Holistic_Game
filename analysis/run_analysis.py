"""Workload analysis for Beacon Bay sessions.

    python analysis/run_analysis.py --level <events.jsonl> [--level ...] \
        [--voice <voice session folder> ...] [--dywa <questionnaire json> ...] --out <folder>

Writes CSV tables, PNG figures and summary.md to --out:

  windows.csv            10 s windows per player and level: metrics, task load, phase, fps
  decision_timeline.csv  one row per call that needed the player's department
  level_summary.csv      player x level means (group-level level differences)
  phase_effects.csv      researcher-defined phases (low/normal/high) per metric
  associations.csv       metric ~ task load, player fixed effects (group-level drivers)
  individual.csv         per player: rank correlation with own pending calls, AUC high vs low phase
  fps_confound.csv       which measures follow the frame rate instead of the player
  subjective.csv         metric vs DYWA curve per player (only with --dywa files)

Small samples: with 4 players and one session, every inferential number here is
descriptive. Windows are autocorrelated, so the model CIs are too narrow.
"""
from __future__ import annotations

import argparse
import json
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from beacon_logs import PlayerLevel, load_player_level, speech_activity  # noqa: E402
from decision_timeline import decision_timeline  # noqa: E402
from workload_metrics import METRICS, window_metrics  # noqa: E402

# Reference palette (dataviz skill), categorical slots in fixed order.
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
INK, INK2, MUTED, GRID, AXIS, SURFACE = "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7", "#fcfcfb"


def spearman(a: pd.Series, b: pd.Series) -> float:
    ok = a.notna() & b.notna()
    if ok.sum() < 6 or a[ok].nunique() < 2 or b[ok].nunique() < 2:
        return np.nan
    return float(a[ok].rank().corr(b[ok].rank()))


def auc(scores: pd.Series, labels: pd.Series) -> float:
    """Probability that a high-load window scores higher than a low-load one."""
    ok = scores.notna()
    pos, neg = scores[ok & labels], scores[ok & ~labels]
    if len(pos) < 3 or len(neg) < 3:
        return np.nan
    greater = (pos.values[:, None] > neg.values[None, :]).mean()
    ties = (pos.values[:, None] == neg.values[None, :]).mean()
    return float(greater + 0.5 * ties)


def find_speech(level: PlayerLevel, voice_dirs: list[Path]) -> list[tuple[float, float]] | None:
    """Speech of this player from any recorder that had their consent. None
    means no usable recording (no consent or no recorder), not silence."""
    for folder in voice_dirs:
        session = json.loads((folder / "session.json").read_text(encoding="utf-8"))
        own_recorder = int(session.get("peer_id", 0)) == level.peer_id
        consent = session.get("permissions", {}).get(str(level.peer_id), {}).get("consent", False)
        has_track = any(level.peer_id in [int(p) for p in t.get("peer_ids", [t.get("peer_id", 0)])] for t in session.get("tracks", []))
        in_level = any(s.get("level_run_id") == level.level_run_id for s in session.get("level_segments", []))
        if has_track and in_level and (own_recorder or consent):
            return speech_activity(folder, level.level_run_id).get(level.peer_id, [])
    return None


def load_dywa(paths: list[Path]) -> pd.DataFrame:
    """DYWA curves saved by study/questionnaires (one JSON per player and level)."""
    rows = []
    for path in paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        for item in data.get("responses", [data]):
            dywa = item.get("dywa")
            if not dywa:
                continue
            curve = pd.DataFrame(dywa["curve"], columns=["progress", "workload"])
            rows.append({"participant": item.get("participant_id"), "role": item.get("role"),
                         "level": int(item.get("level_number", 0)), "duration_s": float(dywa.get("task_duration_s", 330.0)),
                         "curve": curve})
    return pd.DataFrame(rows)


def style(ax, title: str, xlabel: str, ylabel: str) -> None:
    ax.set_facecolor(SURFACE)
    ax.set_title(title, loc="left", color=INK, fontsize=11, pad=10)
    ax.set_xlabel(xlabel, color=INK2, fontsize=9)
    ax.set_ylabel(ylabel, color=INK2, fontsize=9)
    ax.grid(True, color=GRID, linewidth=0.6)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(AXIS)
    ax.tick_params(colors=MUTED, labelsize=8)


def figures(levels: list[PlayerLevel], windows: pd.DataFrame, individual: pd.DataFrame, out: Path) -> list[str]:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    made = []
    players = sorted({lv.label.split(" ")[0] for lv in levels})
    color = {p: SERIES[i % len(SERIES)] for i, p in enumerate(players)}
    # 1. Frame rate against the number of open calls, per player PC.
    fig, ax = plt.subplots(figsize=(7.2, 4.0), dpi=150)
    fig.patch.set_facecolor(SURFACE)
    ends = []
    for p in players:
        sub = windows[(windows.player.str.split(" ").str[0] == p) & windows.fps.notna()]
        if sub.empty:
            continue
        sub = sub.assign(calls=sub.active_incidents.round()).groupby("calls").fps.median()
        ax.plot(sub.index, sub.values, color=color[p], linewidth=2, marker="o", markersize=4, label=p)
        ends.append([float(sub.values[-1]), float(sub.index[-1]), p])
    # Direct labels at line ends, nudged apart so they never overlap.
    ends.sort()
    span = ax.get_ylim()[1] - ax.get_ylim()[0]
    for i in range(1, len(ends)):
        ends[i][0] = max(ends[i][0], ends[i - 1][0] + span * 0.05)
    for y, x, p in ends:
        ax.annotate(p, (x, y), xytext=(8, 0), textcoords="offset points", va="center", fontsize=8, color=INK2)
    ax.set_xlim(right=ax.get_xlim()[1] + 0.6)
    style(ax, "Frame rate drops as calls pile up (all levels, median per window)", "Open calls", "Frames per second")
    ax.legend(frameon=False, fontsize=8, loc="upper right", labelcolor=INK2)
    fig.tight_layout()
    fig.savefig(out / "fig_fps_vs_calls.png")
    plt.close(fig)
    made.append("fig_fps_vs_calls.png")
    # 2. Per-player correlation of each metric with own pending calls (diverging, gray midpoint).
    if not individual.empty:
        from matplotlib.colors import LinearSegmentedColormap
        pivot = individual.pivot_table(index="metric", columns="player", values="r_own_pending")
        pivot = pivot.reindex([m for m in METRICS + ["response_time_s", "decision_time_s", "execution_time_s"] if m in pivot.index])
        cmap = LinearSegmentedColormap.from_list("div", ["#2a78d6", "#f0efec", "#e34948"])
        fig, ax = plt.subplots(figsize=(7.2, 0.42 * len(pivot) + 1.4), dpi=150)
        fig.patch.set_facecolor(SURFACE)
        image = ax.imshow(pivot.values, cmap=cmap, vmin=-0.8, vmax=0.8, aspect="auto")
        ax.set_xticks(range(len(pivot.columns)), pivot.columns, fontsize=8, color=INK2, rotation=0)
        ax.set_yticks(range(len(pivot.index)), pivot.index, fontsize=8, color=INK2)
        for i in range(pivot.shape[0]):
            for j in range(pivot.shape[1]):
                v = pivot.values[i, j]
                if np.isfinite(v):
                    ax.text(j, i, f"{v:+.2f}", ha="center", va="center", fontsize=7, color=INK)
        ax.set_title("Which metric follows each player's own pending calls (Spearman r, 10 s windows)", loc="left", fontsize=10, color=INK)
        for side in ax.spines.values():
            side.set_visible(False)
        cbar = fig.colorbar(image, ax=ax, fraction=0.03, pad=0.02)
        cbar.ax.tick_params(labelsize=7, colors=MUTED)
        cbar.outline.set_visible(False)
        fig.tight_layout()
        fig.savefig(out / "fig_individual_correlations.png")
        plt.close(fig)
        made.append("fig_individual_correlations.png")
    return made


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--level", action="append", required=True, help="a level events.jsonl file (one per player and level)")
    parser.add_argument("--voice", action="append", default=[], help="a voice session folder (session.json + timeline.jsonl)")
    parser.add_argument("--dywa", action="append", default=[], help="questionnaire JSON saved by study/questionnaires")
    parser.add_argument("--window", type=float, default=10.0)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    voice_dirs = [Path(v) for v in args.voice]
    levels = [load_player_level(p) for p in args.level]
    all_windows, all_timelines = [], []
    for level in levels:
        timeline = decision_timeline(level)
        speech = find_speech(level, voice_dirs) if voice_dirs else None
        windows = window_metrics(level, args.window, speech, timeline)
        all_windows.append(windows)
        all_timelines.append(timeline)
        print(f"{level.label}: schema {level.schema}, {level.duration_s:.0f} s, {len(windows)} windows, "
              f"{timeline.get('dispatched_s', pd.Series(dtype=float)).notna().sum()} own dispatches, speech {'yes' if speech is not None else 'no'}")
    windows = pd.concat(all_windows, ignore_index=True)
    timelines = pd.concat(all_timelines, ignore_index=True)
    windows.to_csv(out / "windows.csv", index=False)
    timelines.to_csv(out / "decision_timeline.csv", index=False)
    metrics = [m for m in METRICS + ["response_time_s", "decision_time_s", "execution_time_s"] if m in windows and windows[m].notna().sum() > 10]

    # Group level: level means per player.
    level_summary = windows.groupby(["player", "departments", "level"])[metrics + ["fps", "own_pending", "active_incidents"]].mean().reset_index()
    level_summary.to_csv(out / "level_summary.csv", index=False)

    # Researcher-defined phases: high vs low, standardized within player and level.
    z = windows.copy()
    for m in metrics:
        z[m] = z.groupby(["peer_id", "level"])[m].transform(lambda s: (s - s.mean()) / s.std(ddof=0) if s.std(ddof=0) > 0 else s * 0)
    phase_rows = []
    for m in metrics:
        per_player = z[z.phase.isin(["high", "low"])].groupby(["departments", "phase"])[m].mean().unstack()
        diffs = (per_player.get("high") - per_player.get("low")).dropna() if {"high", "low"} <= set(per_player.columns) else pd.Series(dtype=float)
        phase_rows.append({"metric": m, "mean_z_high_minus_low": float(diffs.mean()) if len(diffs) else np.nan,
                           "players_up": int((diffs > 0).sum()), "players_down": int((diffs < 0).sum()), "players": int(len(diffs)),
                           **{f"z_{p}": float(z[z.phase == p][m].mean()) for p in ["low", "normal", "high"]}})
    phase_effects = pd.DataFrame(phase_rows)
    phase_effects.to_csv(out / "phase_effects.csv", index=False)

    # Group-level drivers: metric ~ task load + player fixed effects.
    assoc_rows = []
    try:
        import statsmodels.formula.api as smf
        data = z.dropna(subset=["own_pending", "own_not_needed", "critical"]).copy()
        data["player_level"] = data.player
        for m in metrics:
            d = data.dropna(subset=[m])
            if len(d) < 30:
                continue
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                fit = smf.ols(f"{m} ~ own_pending + own_dispatched + own_not_needed + critical + C(player_level)", data=d).fit()
            for term in ["own_pending", "own_dispatched", "own_not_needed", "critical"]:
                lo, hi = fit.conf_int().loc[term]
                assoc_rows.append({"metric": m, "term": term, "beta_sd_per_call": fit.params[term], "ci_low": lo, "ci_high": hi,
                                   "p": fit.pvalues[term], "n_windows": int(fit.nobs), "r2": fit.rsquared})
    except ImportError:
        print("statsmodels not installed: associations.csv skipped (pip install statsmodels)")
    associations = pd.DataFrame(assoc_rows)
    associations.to_csv(out / "associations.csv", index=False)

    # Individual level: does a metric follow this player's own load?
    ind_rows = []
    for (player, level_number), g in windows.groupby(["player", "level"]):
        high = g.phase == "high"
        for m in metrics:
            ind_rows.append({"player": player.split(" ")[0], "level": level_number, "metric": m,
                             "r_own_pending": spearman(g[m], g.own_pending), "r_active": spearman(g[m], g.active_incidents),
                             "auc_high_vs_low_phase": auc(g[m][g.phase.isin(["high", "low"])], high[g.phase.isin(["high", "low"])])})
    individual = pd.DataFrame(ind_rows)
    individual_mean = individual.groupby(["player", "metric"])[["r_own_pending", "r_active", "auc_high_vs_low_phase"]].mean().reset_index()
    individual_mean.to_csv(out / "individual.csv", index=False)

    # Frame-rate confound.
    fps_rows = []
    for player, g in windows.groupby("player"):
        for m in ["raw_motion_rows_per_s", "held_share"] + metrics + ["own_pending", "active_incidents"]:
            fps_rows.append({"player": player, "measure": m, "r_with_fps": spearman(g[m], g.fps)})
    fps_confound = pd.DataFrame(fps_rows)
    fps_confound.to_csv(out / "fps_confound.csv", index=False)

    # Subjective alignment (DYWA), when curves are supplied.
    subjective = pd.DataFrame()
    if args.dywa:
        curves = load_dywa([Path(p) for p in args.dywa])
        rows = []
        for _, c in curves.iterrows():
            match = windows[(windows.level == c.level) & (windows.departments.str.contains(str(c.role or ""), regex=False))]
            for player, g in match.groupby("player"):
                mid = ((g.t0 + g.t1) / 2) / c.duration_s
                curve = np.interp(mid, c.curve.progress, c.curve.workload)
                for m in metrics + ["own_pending"]:
                    rows.append({"participant": c.participant, "player": player, "level": c.level, "measure": m,
                                 "r_with_dywa": spearman(g[m].reset_index(drop=True), pd.Series(curve))})
        subjective = pd.DataFrame(rows)
        subjective.to_csv(out / "subjective.csv", index=False)

    made = figures(levels, windows, individual_mean, out)
    write_summary(out, levels, windows, timelines, phase_effects, associations, individual_mean, fps_confound, made)
    print(f"Wrote {out}")
    return 0


def write_summary(out: Path, levels, windows, timelines, phase_effects, associations, individual, fps_confound, figs) -> None:
    lines = ["# Beacon Bay workload analysis", "",
             f"{len(levels)} player levels, {windows.player.nunique()} player-level series, {len(windows)} windows of "
             f"{windows.t1.iloc[0] - windows.t0.iloc[0]:.0f} s.", ""]
    lines += ["## Decision timeline (own-department calls)", ""]
    done = timelines[timelines.dispatched_s.notna()] if "dispatched_s" in timelines else timelines.iloc[0:0]
    if len(done):
        cols = [c for c in ["response_time_s", "decision_time_s", "execution_time_s", "field_time_s"] if c in done]
        table = done.groupby(["player"])[cols].median().round(2)
        table["commit_observed"] = done.groupby("player").commit_s.apply(lambda s: int(s.notna().sum())) if "commit_s" in done else 0
        missed = timelines[timelines.dispatched_s.isna()].groupby("player").size() if "dispatched_s" in timelines else pd.Series(dtype=int)
        table["own_calls"] = timelines.groupby("player").size()
        table["never_dispatched"] = missed.reindex(table.index).fillna(0).astype(int)
        lines += [table.to_markdown(), ""]
    lines += ["## Researcher-defined phases (high minus low, z within player and level)", "",
              phase_effects.round(2).to_markdown(index=False), ""]
    if len(associations):
        piv = associations.pivot_table(index="metric", columns="term", values="beta_sd_per_call").round(2)
        lines += ["## Task-load drivers (SD change per extra call, player fixed effects)", "", piv.to_markdown(), ""]
    if len(individual):
        piv = individual.pivot_table(index="metric", columns="player", values="r_own_pending").round(2)
        lines += ["## Individual: Spearman r with own pending calls", "", piv.to_markdown(), ""]
        piv = individual.pivot_table(index="metric", columns="player", values="auc_high_vs_low_phase").round(2)
        lines += ["## Individual: AUC high vs low phase (0.5 = chance)", "", piv.to_markdown(), ""]
    piv = fps_confound.pivot_table(index="measure", columns="player", values="r_with_fps").round(2)
    lines += ["## Frame-rate confound: Spearman r with fps", "", piv.to_markdown(), ""]
    lines += [f"![]({f})" for f in figs]
    (out / "summary.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
