# Workload analysis

Python scripts that read the research files the game writes and compute the
metrics the client asked for (feedback 01.11). They are not part of the game.

```bash
pip install pandas numpy matplotlib statsmodels tabulate
python analysis/run_analysis.py \
  --level research/<session>/levels/<level_run_id>_events.jsonl   # one per player and level
  --voice research/voice/team_<session>_<id>                       # optional, any recorder folders
  --dywa  study_responses/<file>.json                              # optional, from study/questionnaires
  --out   analysis_out
```

Pass every player's level file (each player has their own copy of the shared
events plus their own mouse and selection rows). Schema 3 files (builds up to
0.9.1) and schema 4 files (0.9.2, with the 60 Hz sample CSV next to them) both
work. The CSV is found automatically when it sits next to its `_events.jsonl`.

| File | Contents |
| --- | --- |
| `beacon_logs.py` | Loading, level slicing, fixed-grid mouse, frame rate, task load (live in schema 4, reconstructed from events in schema 3), phases, speech intervals |
| `decision_timeline.py` | Per call that needed the player's department: onset, first look, commit, dispatch, arrival; decision, execution, field and response time |
| `workload_metrics.py` | 10 s windows: mouse, clicks, dispatches, attention switching, speech share, task load, phase, fps |
| `run_analysis.py` | Tables, figures and `summary.md` for the four questions below |

The four analyses map to the client's list:

1. Group-level differences between levels and researcher-defined phases
   (`level_summary.csv`, `phase_effects.csv`). The phases are the hidden
   low/normal/high schedule in `campaign.gd` (`chaos_phase_changed` rows).
2. Group-level drivers: each metric against own pending calls, own dispatched
   calls, calls that do not need the player, and critical calls, with player
   fixed effects (`associations.csv`).
3. Individual detection: per player, rank correlation with their own pending
   calls and AUC for high vs low phase windows (`individual.csv`,
   `fig_individual_correlations.png`).
4. Subjective alignment: correlation of each metric with the player's DYWA curve
   for that level (`subjective.csv`, needs `--dywa`).

`fps_confound.csv` shows which measures follow the PC's frame rate. Raw
`mouse_motion` row counts do (schema 3); measures on the fixed grid mostly do not.

Read the numbers as descriptive: one session, four players, autocorrelated
windows. Decision and execution time can only be split where the crew selection
was logged (schema 3: crew cards only; schema 4: every selection).
