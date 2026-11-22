# Study materials

Things the researcher uses around a session. They are not part of the game.

## Questionnaires (`questionnaires/index.html`)

One offline page, opened in any browser (double-click the file). Fill it in right
after each level, on the study PC or a tablet next to it. Nothing is sent over the
network; answers stay in the browser until exported.

1. **Setup** (researcher): participant ID, department, level, level length, and
   optionally the capture session ID and level run ID from the game's results
   screen or `manifest.json`. With the run ID the answers join the game logs
   exactly.
2. **DYWA** (Gampe, Hamann & Carstengerdes, 2026; DLR-IB-FL-BS-2026-89; GUI
   DOI 10.5281/zenodo.22890862). The participant draws one continuous workload
   curve over the level (x = level time with minute ticks, y = 1 very low, 3
   optimal, 5 very high), then clicks on the curve to mark moments where workload
   went up or down, with a category and optional free text. Saved as 101 curve
   points (`[progress, workload]`), the raw pen/mouse points and the annotations
   (`progress`, `time_s`, `workload`, `direction`, `categories`, `text`).
3. **DLR-WAT** (Brandenburger, Dressler & Grippenkoven; Grippenkoven &
   Brandenburger, 2018). Eight continuous scales: information intake, knowledge
   retrieval, decision making, motor/physical, temporal, effort (0-200, 100 =
   personal optimum, so underload and overload are both measurable),
   frustration (100-200) and task accomplishment (0-100). Mental workload = mean
   of the first three; overall = mean of all eight.

The in-game NASA-TLX (after the last level) is unchanged.

**Check before the study:** the DLR-WAT item texts on this page are written for
Beacon Bay from the published structure (subscale names, ranges, optimum at
100). The official item wording and anchors were not available. Replace the
`q` and `hint` texts in `WAT_ITEMS` with the official wording when you have it;
the stored values and scoring do not change. The DYWA event categories
(`DYWA_CATEGORIES`) are game-specific; DYWA allows predefined categories or free
text, and this page offers both.

Export with **Export all (JSON)** after each session and keep the file next to
the game's `research/` folder. `analysis/run_analysis.py --dywa <file>` reads
it. **Export all (CSV)** gives one row per response with the DLR-WAT scores and
the DYWA curve at every 10% of the level.

## Session protocol additions (client feedback 01.11)

- Record levels 1 and 2 as well as the hard levels: they are the low-load
  baseline for the per-player comparisons.
- Run Settings > Research > CHECK THIS STUDY PC on every PC before the session
  and keep the saved check. The `display` rows now also report the sampler rate
  and how well the sampled cursor matches the mouse events.
