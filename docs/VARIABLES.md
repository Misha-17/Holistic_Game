# Variables manual

Every variable the game records for research, what it captures, its unit, and how
the derived measures (decision time, execution time, workload metrics) are
computed. Schema 4 = build 0.9.2 and later. Rows marked *(4)* are new in schema 4;
everything else exists in schema 3 too.

Contents: 1 Files · 2 Clocks · 3 Row envelope · 4 Context · 5 60 Hz samples ·
6 Task load · 7 Player input rows · 8 Game event rows · 9 Lifecycle rows ·
10 Session, capture and quality rows · 11 Questionnaires · 12 Voice ·
13 Derived measures · 14 Limits of schema-3 data

## 1. Files

Per player, per computer, under `research/<session_id>/`:

| File | One row per | Rate |
| --- | --- | --- |
| `session_events.jsonl` | event (whole session, authoritative) | event-driven |
| `levels/<level_run_id>_events.jsonl` | the same rows for one level attempt | event-driven |
| `levels/<level_run_id>_samples_60hz.csv` *(4)* | fixed time slot | exactly 60 per second |
| `manifest.json` | session | levels, file paths, join keys |
| `questionnaires/nasa_tlx_<unix_ms>.json` | NASA-TLX answer | after the last level |

Join keys: rows `(session_id, sequence)`; voice `(capture_session_id, level_run_id)`;
players across computers by `peer_id` (behaviour) and `actor_peer` (game actions).
All players in one team share the host's `level_run_id`.

Event rows are written when something happens (a mouse movement, a click, a
dispatch). Their spacing is not a sampling rate. Use the 60 Hz file for anything
rate-based (speed, idle time, time series alignment).

## 2. Clocks

| Field | Unit | Meaning |
| --- | --- | --- |
| `level_elapsed_s` (= `shift_elapsed_s`) | s | Active level time, 0 at shift start. Stops in a solo pause. Never goes backwards inside an attempt. The briefing before the shift is at 0. |
| `session_elapsed_s` | s | Sum of captured level time over the session, including retries. |
| `local_elapsed_us` | µs | Monotonic wall clock since this recorder started the session. Includes pauses and menus. |
| `unix_ms` | ms | Wall clock (UTC epoch). Use it to align computers, voice, video, eye trackers. |
| `utc` | ISO text | Same moment, second resolution, readable. |
| `at`, `started_at`, `ended_at` (inside `data`) | s | Level time when the simulation produced the event. On guests this is the host's time; prefer it over the row's own clock for game events. |

## 3. Row envelope (every JSONL row)

| Field | Meaning |
| --- | --- |
| `schema` | 3 or 4 |
| `session_id`, `capture_session_id` | Recording session (one per computer; same value) |
| `sequence` | Row number in the session, starts at 1, no gaps |
| `capture_segment` | Increments each time recording is switched back on |
| `level_id`, `level_number` | Level shown to the player (0 = Training Harbor, 1-6) |
| `level_index` | Internal index (Level 0 = 6) |
| `level_name`, `level_run_id`, `level_attempt` | Level title, attempt ID (shared by the team), attempt counter |
| `peer_id` | This computer's player |
| `departments` | Departments this player commands (fire, medic, police, engineer) |
| `role` | Network role number |
| `active_event_ids` | Lifecycle IDs (calls, road events, floods, disruptions) open at this moment |
| `context` | Latest UI context, see 4 |
| `event`, `data` | Row type and its fields (7-10) |

## 4. Context (`context` object, also written as a `context` row at most once per second)

| Field | Meaning |
| --- | --- |
| `screen` | game, pause, results, settings, ... |
| `selected_incident_id`, `selected_unit_id` | Call and crew currently selected (-1 = none) |
| `map_zoom`, `map_center` | Camera zoom (0.58 = whole town, 1.05 = drag view, up to 3) and centre (0-1 of the map) |
| `world_position` | Map point under the cursor (0-1 of the map) |
| `pointer_target` | Map object under the cursor: `type` (call, crew, base, road) and `id` |
| `ui_button` | HUD button under the cursor (e.g. `unit:5` = crew card 5) |
| `active_incidents`, `urgent_incidents` | Open calls; calls with less than 20 s left (refreshed every second) |
| `reputation`, `shift`, `build`, `map_pixels` | Community meter, level index, game build, map size |

## 5. 60 Hz samples *(4)* (`<level_run_id>_samples_60hz.csv`)

A separate thread reads the operating-system cursor on a fixed 60 Hz grid. The
grid does not depend on the frame rate, so every PC produces 60 rows per second
and the time between rows is always 16.667 ms. Game state in a row is the newest
state a rendered frame published; `frame_age_ms` says how old it was.

| Column | Unit | Meaning |
| --- | --- | --- |
| `segment` | | Capture segment (same as JSONL `capture_segment`) |
| `sample` | | Row index in the segment, no gaps |
| `local_elapsed_us` | µs | Scheduled sample time on the JSONL `local_elapsed_us` clock |
| `unix_ms` | ms | Scheduled sample time, wall clock |
| `level_elapsed_s` | s | Level time at the sample (latest frame plus time since it, if the clock runs) |
| `read_late_us` | µs | How late the cursor was read after the scheduled time; -1 when `held` |
| `held` | 0/1 | 1 = the thread missed this slot; cursor values repeat the previous row |
| `x`, `y` | px | Cursor in the 1600 x 900 view, same space as `mouse_button` rows. Can be outside 0-1600/0-900 when the cursor leaves the game area |
| `in_window` | 0/1 | Cursor inside the game window |
| `buttons` | bitmask | Mouse buttons held: 1 left, 2 right, 4 middle |
| `window_focused` | 0/1 | Game window has keyboard focus (0 = player is in another program) |
| `frame_age_ms` | ms | Age of the game state in this row |
| `frame_ms`, `fps` | ms, 1/s | Last frame time; engine frames per second |
| `screen` | | As in context; `entry` = consent/briefing popup |
| `clock_running` | 0/1 | Level clock advancing (0 in solo pause, briefing, results) |
| `selected_incident_id`, `selected_unit_id` | | Current selection |
| `hover_type`, `hover_id` | | Object under the cursor: `call`, `crew`, `base`, `road`, or `ui:<button>` (e.g. `ui:unit` with id 5) |
| task-load columns | count | See 6 (one column per variable) |

## 6. Task load *(4: live in samples and `task_state`; schema 3: reconstructed by `analysis/beacon_logs.py`)*

From this player's point of view. "Own" = a department the player commands.
Assigned crews count from dispatch (en route), not only on arrival.

| Variable | Meaning |
| --- | --- |
| `active_incidents` | Open calls (active or being worked) |
| `unconfirmed` | Open calls whose needs are hidden until scouted ("?" calls) |
| `own_needed` | Open calls that need at least one own crew |
| `own_not_needed` | Open calls that need no own crew |
| `own_dispatched` | Own-needed calls with every needed own crew assigned (decision made) |
| `own_pending` | Own-needed calls still missing at least one own crew (decision pending) |
| `own_needed_known`, `own_not_needed_known`, `own_pending_known` | Same, counting only calls the player can read (confirmed) |
| `own_pending_urgent` | Pending own calls with less than 20 s left |
| `own_min_deadline_s` | Seconds left on the most urgent pending own call (-1 = none) |
| `urgent` | Open calls with less than 20 s left |
| `critical` | Open calls the game declared critical (hazard stage 3 or under 12 s) |
| `own_crews_idle`, `own_crews_busy` | Own crews at the station; travelling, working or clearing |
| `own_road_pending` | Road closures only the player's department can clear, not yet assigned |
| `other_pending` | Open calls still waiting for another department's crew |

Identities: `own_needed + own_not_needed = active_incidents`;
`own_dispatched + own_pending = own_needed`.

`task_state` *(4)* JSONL row, once per second: `counts` (the table above) and
`calls`, one entry per open call: `incident_id`, `kind`, `status`, `discovered`,
`own_needed`, `own_assigned`, `own_state` (not_needed / pending / dispatched),
`other_missing`, `deadline_s`, `urgent`, `critical`, `hazard_stage`, `age_s`.

## 7. Player input rows (only the local player; teammates' input is never logged here)

| Event | Fields | Meaning |
| --- | --- | --- |
| `mouse_motion` | `x`, `y`, `dx`, `dy`, `distance_px` | A movement the game received. One or more per rendered frame while the mouse moves, none while it is still: the spacing follows the PC's frame rate. Kept for exact event positions; use the 60 Hz file for rates |
| `mouse_button` | `x`, `y`, `button` (1 left, 2 right, 3 middle, 4/5 wheel), `pressed`, `double_click`, `factor`, `inter_click_ms` | Every press and release; `inter_click_ms` = time since the previous press in this level |
| `key_input` | `keycode`, `physical_keycode`, `pressed` | Keys (Q scout, E supply, Space coffee boost, 1-4 quick dispatch, Esc) |
| `ui_action` | `action`, `screen` | HUD button activated (`unit:5` crew card, `select:12` call card, `scout`, ...) |
| `inspection` | `incident_id` | Player selected a call without a crew selected (looking at it) |
| `crew_selected` *(4)* | `unit_id`, `kind`, `unit_state`, `selected_incident_id`, `replaced_unit_id`, `at` | Player picked a crew, by card, map or number key. This is the commit point in the decision timeline |
| `crew_deselected` *(4)* | `unit_id`, `kind`, `reason` (toggled, department_filter), `selected_incident_id`, `at` | Selection dropped without sending |
| `department_filter` *(4)* | `kind`, `selected_incident_id`, `at` | Player filtered the map to one department |
| `command_requested` | `action` (dispatch, clear_road, scout, supply, special, withdraw, ping), `payload`, `actor_peer` | Player asked the game to do something |
| `command_result` | `action`, `payload`, `actor_peer`, `accepted`, `reason`, `at` | The host's answer: accepted, unavailable_or_invalid_target, department_not_owned, level_not_active. Logged for every player's commands |
| `action_denied` | `text`, `actor_peer` | Message shown when a teammate's command failed |

## 8. Game event rows (shared: every player's file has them; `actor_peer` = who caused it, 0 = the game)

Calls: `incident_spawned` (`incident_id`, `kind`, `severity`, `pos`),
`incident_started` / `incident_ended` (full record: `needs` per department,
`discovered`, `scouted`, `max_deadline` s, `people`, `outcome`, `seconds_open`,
`assigned_units`, `highest_hazard_stage`), `escalated` (`hazard`, `hazard_stage`),
`urgent` (time running short), `critical`, `scout` (`time_added`),
`field_report` (crew confirms needs), `dispatch` (`unit_id`, `kind`, `eta` s,
`from`, `diverted`), `dispatch_mismatch` (crew of the wrong department sent
back), `unit_withdrawn`, `crew_arrived`, `arrival` (all needed crews on scene),
`rapid_response` (dispatched within 8 s: faster work), `supply` (`time_added`,
`hazard_reduced`, `work_seconds_saved`), `resolved` (`people`, `points`,
`time_left`), `failed`, `crew_ready`.

Road events: `road_event` / `road_event_started` (`clear_kind` = department
that can clear it, `linked_incident`), `road_clear_dispatched`,
`road_event_clear_dispatched`, `road_crew_arrived`, `road_cleared` /
`road_event_cleared`, `road_event_expired`, `road_event_end` / `road_event_ended`.

Hazards and environment: `hazard_forecast` (12 s ahead, `starts_at`),
`hazard_warning`, `hazard_started`, `hazard_ended` (sandstorm, blackout,
storm), `bridge_flooded`, `bridge_open`, `bridge_flood_started` /
`bridge_flood_ended`, `disruption` / `disruption_end`.

Researcher-defined load phases: `chaos_phase_changed` (`phase` = low / normal /
high, `phase_index`, `at`, `until`; fixed per level in `campaign.gd`, hidden
from players), `chaos_state_at_capture_start`, `arrival_capacity_skipped`,
`road_call_capacity_skipped` (a scheduled call was skipped because the map was
full).

Score and level: `shift_started` (`duration` 330 s), `combo`, `combo_supply`,
`rally` (coffee boost), `supply_ready`, `target_reached`, `final_minute`,
`all_clear`, `shift_ended_early`, `shift_complete` (`rescued`, `target`,
`resolved`, `missed`, `dispatches`, `wrong_dispatches`, `escalations`, `scouts`,
`supplies_used`, `peak_calls`, `stars`, `won`).

## 9. Lifecycle rows (normalised, one per call / road event / flood / disruption)

| Event | Meaning |
| --- | --- |
| `event_started` | Started while recording; `event_instance_id` = `<level_run_id>/<kind>:<id>` |
| `event_observed` | Already running when recording started (from a snapshot) |
| `event_ended` | `outcome` (resolved, failed, expired_unsolved, elapsed, level_ended_unsolved, no_longer_present_in_snapshot), `solved` (true/false; null for passive hazards and unknown outcomes), `duration_s`, `censored`, `start_observed`, `end_observed` |

## 10. Session, capture and quality rows

| Event | Meaning |
| --- | --- |
| `capture_started` / `capture_resumed` / `capture_stopped` | Recording on, back on (with gap length), off |
| `collection_choice`, `briefing_completed` | Consent choice at level entry; player closed the briefing |
| `level_started` / `level_ended` | Attempt boundaries; `level_ended` has `reason`, `clicks`, `pointer_distance_px`, `capture_duration_s`, `clock_corrections` |
| `state_observed` | Score, reputation, rescued, supplies at capture start and end |
| `display` | At level start and every 10 s: window, viewport, scaling, screen refresh rate, vsync, `fps_measured`, `frame_time_ms_mean/max`, `mouse_motion_events_per_s`; *(4)* `sampler` = `achieved_hz`, `rows`, `held_share`, `late_p95_us`, `late_max_us`, `map_check_px_median` (distance between the sampled cursor and the mouse events; a few px is normal, a large constant value means the window mapping is wrong) |
| `sampler_started` / `sampler_stopped` / `sampler_error` *(4)* | Sample file path, rate, column list; run statistics at the end |
| `clock_correction` | A guest's clock was ahead of the host; the logged clock held for `behind_s` |
| `microphone_check`, `pc_check` | Level-entry mic test; study PC check summary |
| `voice_recording` | Voice file opened or closed |

## 11. Questionnaires

- NASA-TLX (in game, after the last level or from the title screen): six raw
  subscales 0-100 in steps of 5 and `raw_tlx` (mean), with `source`,
  `last_level_number`, `departments`, `seconds_to_complete`.
- DYWA and DLR-WAT (`study/questionnaires/index.html`, outside the game): see
  `study/README.md`. DYWA: 101-point curve over level progress on 1-5 (3 =
  optimal), raw drawing points, event annotations with time, direction and cause.
  DLR-WAT: eight scales, 0-200 with 100 = personal optimum (frustration 100-200,
  task accomplishment 0-100), mental and overall means.

## 12. Voice (`research/voice/team_<session>_<id>/`)

`player_<key>.wav` (16 kHz mono per person, stable across reconnects, all
tracks start at frame 0; before 02.11 `peer_<id>.wav` per connection),
`session.json` (tracks, consent per peer, `level_segments` with start/end
frames, `audio_activity` = speech intervals per speaker in frames, with the
`peer_id` at that moment),
`timeline.jsonl` (`clock_sync` rows pair `audio_frame` with `level_elapsed_s`
about once a second; use them to put speech on the level clock).

## 13. Derived measures (`analysis/`)

### Decision timeline (per call that needed the player's department)

Human-factors split between decision making (how long until the decision) and
decision execution (how long until it is acted out):

| Point | Definition |
| --- | --- |
| onset | The player can know the call needs them: spawn time if confirmed, otherwise when it is confirmed (scout, field report, mismatched crew) |
| first_look | First 60 Hz sample after onset with the cursor on the call (pin or card) |
| first_inspect | First `inspection` of the call |
| commit | `crew_selected` for the crew that is then sent, after the player's previous command. For a number-key dispatch, commit = command |
| command | `command_requested` (dispatch) for the call |
| dispatched | `dispatch` event with `actor_peer` = this player |
| arrived | `crew_arrived` for that crew at that call |

| Measure | Formula | Captures |
| --- | --- | --- |
| `decision_time_s` | commit - onset | Noticing, reading the call, choosing a crew |
| `execution_time_s` | dispatched - commit | Acting the decision out in the interface (clicks to the call, confirmation) |
| `response_time_s` | dispatched - onset | Both together |
| `field_time_s` | arrived - dispatched | Travel; set by the game, not the player |
| `dispatch_input` | click / key / unknown | How the dispatch was entered |

Calls never dispatched keep their onset and outcome with empty times (censored).

### Window metrics (10 s windows of level time, per player)

| Metric | Definition |
| --- | --- |
| `mouse_speed_px_s` | Cursor path length / window length, on a fixed 30 Hz grid |
| `mouse_idle_share` | Share of grid steps inside a pause (no movement of 2 px or more for at least 100 ms) |
| `mouse_moves_per_s` | Movement onsets (pause to movement) per second |
| `mouse_turns_per_s` | Direction changes over 90° between consecutive moving steps |
| `clicks_per_min`, `inter_click_s` | Left/right/middle presses; median time between presses |
| `denied_per_min` | Own commands the game refused |
| `dispatches_per_min`, `inspections_per_min` | Own dispatches; calls looked at |
| `hover_switches_per_min` | Changes of the call under the cursor (attention switching) |
| `speech_share` | Share of the window the player was speaking (voice activity) |
| task load | Window mean of each variable in 6 |
| `phase` | Researcher-defined phase at the window centre |
| `fps`, `held_share`, `raw_motion_rows_per_s` | Data-quality covariates |

## 14. Limits of schema-3 data (builds up to 0.9.1, playtest 22.10)

- No fixed-rate stream: `mouse_motion` rows follow the PC's frame rate (playtest
  22.10: 28-36 fps on two PCs, 67-82 on two, every PC slower with more calls).
  The analysis resamples them to 30 Hz; a slow PC still has fewer real positions.
- Crew selection was only logged from crew cards (`ui_action unit:N`). A crew
  picked on the map left no row, so decision and execution time cannot be split
  for those dispatches; response time is still valid.
- Task load is reconstructed from events; deadlines ignore rapid-response and
  storm effects.
- A guest-clock bug could split one level into two captures with the same
  `level_run_id` (fixed 30.10). The analysis joins them.
