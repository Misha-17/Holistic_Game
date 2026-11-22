# Research files

Collection starts only after the player enables it (asked once per session, at
the first level). Disabling collection stops writing observations immediately.
Every player's files are written on that player's own computer (solo and
co-op; from 09.11 again, after the 02.11-04.11 "session leader only" builds).
See "Collecting the files" below.
Mouse input belongs to that local player; shared game actions identify their
actor separately with `data.actor_peer`. Voice consent and speaker files are
managed by the voice recorder.

Behavioral records use schema version 4 (3 up to build 0.9.1) and live under Godot's user data folder:

```text
research/<date>_<time>_<name>/                     e.g. 2026-11-07_19-30_Andrei (= session_id)
  READ ME - what these files are.txt
  <name>_session-info.json                         (was manifest.json)
  <name>_all-levels_events.jsonl                   (was session_events.jsonl)
  <name>_level-<N>_events.jsonl                    (was levels/<level_run_id>_events.jsonl)
  <name>_level-<N>_try-<k>_events.jsonl            second and later tries of a level in one session
  <name>_level-<N>_mouse-and-taskload-60hz.csv     (was levels/<level_run_id>_samples_60hz.csv, schema 4)
  <name>_nasa-tlx.json                             (was questionnaires/nasa_tlx_<unix_ms>.json; more: _2, _3)
  <name>_voice/                                    (was research/voice/team_<session_id>_<id>/)
    <name>_voice.wav, <name>_voice.jsonl, session.json, timeline.jsonl, listen.html
```

`<name>` is the name typed in the lobby with spaces turned into hyphens and
other characters dropped (blank: `Player-2` by seat in co-op, `Player` solo).
The level number in a file name is the level's number; the level attempt's
`level_run_id` is inside every row and in the session info. Builds before 09.11
used the older names in brackets.

`<name>_all-levels_events.jsonl` is the authoritative timeline for the whole play session.
Each level file mirrors that level attempt's rows, with the same sequence IDs.
Do not concatenate both sources when counting observations. The manifest lists
the level files and documents this relationship.

Each line is a JSON object. Join records with `(session_id, sequence)` and join
voice artifacts with `(capture_session_id, level_run_id)`. The manifest records
these keys. The voice recorder's speaker index identifies its participant and
role; use that identity with behavioral `peer_id` and game-action `actor_peer`.

## Levels and time

Every level-scoped row includes `level_number` (the number shown to the player),
`level_index` (the internal simulation index), `level_name`, `level_run_id`, and
`level_attempt`. Level 0 currently has internal index 6. A retry has a new run ID;
turning collection off and on within an attempt retains its existing run ID.

Three clocks serve different purposes:

| Field | Meaning |
| --- | --- |
| `level_elapsed_s` | Active simulation seconds within this attempt; pauses do not advance it. |
| `session_elapsed_s` | Actual elapsed simulation time summed over captured level attempts, including retries. It does not assume every level lasts 330 seconds. |
| `local_elapsed_us` | Monotonic wall time since this recorder first began capturing the session; includes pauses and collection gaps. |

`utc` provides a readable UTC timestamp. Source simulation lifecycle data has
`started_at`, `ended_at`, and `at` in level seconds; prefer those authoritative
times to the local observation time when a network event arrives late.

Session boundary rows can have null level identifiers. `capture_segment`
increments when capture resumes. `capture_stopped` and `capture_resumed` mark
gaps; no input or game events occurring while disabled are saved. Snapshot
observations on resume describe the state then visible to the player. They do
not reconstruct missing mouse input or invent missing outcomes.

## Mouse and game events

`mouse_motion` preserves every delivered position and relative movement.
`mouse_button` preserves button down/up, wheel events, coordinates, double-click
flags, and inter-click intervals. Inter-click timing resets at level boundaries
and capture gaps. Each input row has participant/departments, current UI context
(including selected call/crew when supplied by the game), and `active_event_ids`.

Raw simulation records retain their event types, actor, incident/road IDs, and
available dispatch, arrival, supply, scouting, failure, and completion details.
The following normalized records make lifecycle analysis consistent:

| Event | Meaning |
| --- | --- |
| `event_started` | An incident, road event, flood, or disruption starts during capture. |
| `event_observed` | An already-existing event is first observed in a snapshot. |
| `event_ended` | The event ends, with `event_instance_id`, source times, duration, and outcome. |
| `level_started` / `level_ended` | The attempt boundary, result and local input totals. |

An event instance ID contains the level run ID, so reused incident numbers cannot
be confused across levels or retries. Road presentation notifications do not
create duplicate normalized endings. Event outcomes distinguish repaired roads,
expired unresolved tasks, failed calls, practice handoffs, and unfinished tasks
at the end of a level. Passive weather and floods have `solved: null`; they are
not scored as player failures. Unknown outcomes after a capture gap are also
null and explicitly censored. Abandoned attempts mark unfinished observations as
censored so they can be distinguished from ordinary completed levels.

`start_observed` and `end_observed` distinguish live observations from state
recovery. A snapshot can confirm a completed event still in simulation state;
an old incident absent from a pruned network snapshot gets
`outcome: no_longer_present_in_snapshot`, not a fabricated success or failure.

Personal player names, messages, chat, email/IP/address fields and transcripts
are excluded from behavioral metadata. Speaker audio and its participant labels
are separate artifacts governed by voice-recording consent.

## Additions 30.10

Every row now has `unix_ms` (wall clock, milliseconds) next to the game clock.

- `clock_correction` - a guest's clock was ahead of the host's snapshot by
  `behind_s` (logged once per correction, when at least 0.25 s). The logged
  level clock holds at `held_at_s` until the game catches up, so it never goes
  back. `level_ended` reports `clock_corrections` and `clock_held_total_s`.
- `display` - at level start and every 10 s: window and viewport size, scaling,
  window mode, screen size/scale/refresh rate, vsync, `fps_measured`,
  `frame_time_ms_mean/max`, `mouse_motion_events_per_s`, `embedded_in_editor`.
- `microphone_check` - result of the level-entry mic check: `verdict`
  (good / too_quiet / too_loud / no_signal / waiting / microphone_off),
  `speech_level_db` (90th percentile of speech frames), `clipped_frames`.
- `pc_check` - summary of a Settings > Research study PC check; the full result
  is in `research/pc_checks/pc_check_<unix_ms>.json`.

NASA-TLX (raw, six subscales 0-100 in steps of 5, `raw_tlx` = mean) is saved as
`research/<session>/questionnaires/nasa_tlx_<unix_ms>.json` with `source`
(`after_last_level`, `title_button`, or `leaving_session` when the player chose YES on leaving from the results screen, 04.11), `last_level_number`, `last_level_won`,
`departments` and `seconds_to_complete`.

## Additions 01.11 (schema 4, build 0.9.2)

Client feedback 01.11. Full definitions of every variable: [VARIABLES.md](VARIABLES.md).

- `levels/<level_run_id>_samples_60hz.csv`: a fixed 60 Hz stream. A separate
  thread reads the operating-system cursor every 16.667 ms, whatever the frame
  rate, so every PC writes 60 rows per second, including when nothing happens.
  Each row also carries the selection, the object under the cursor, the frame
  rate and the task load below. `held = 1` marks a slot the thread missed.
- Task load per player (in every sample and in a 1 Hz `task_state` row):
  calls that need the player's own department vs not, own calls dispatched vs
  decision pending, urgent and critical calls, own idle crews, own road
  closures, calls waiting for other departments.
- `crew_selected`, `crew_deselected`, `department_filter`: every crew
  selection, whatever the input, so decision time (until the crew is chosen)
  and execution time (until the dispatch is accepted) can be separated.
- `sampler_started` / `sampler_stopped`, and a `sampler` block in `display`
  rows: achieved rate, missed slots, read latency, and how far the sampled
  cursor is from the mouse events (mapping check).
- `mouse_motion` rows are unchanged. They follow the frame rate; use the
  60 Hz file for anything rate-based.

## Collecting the files (09.11: every player)

Each player sends the session folder(s) from their own `research/` folder to
the researcher (Settings > Research > **OPEN MY STUDY FILES**; Windows:
`%APPDATA%\Godot\app_userdata\Beacon Bay\research`). Nothing is stored on the
server and nothing is uploaded. Every player's events file has the shared game
events (calls, dispatches, hazards, outcomes) plus that player's own input and
view; the voice folder has only that player's microphone. To put a team back
together, join the players' files on `level_run_id` (the same for every player
of one level attempt) and `level_elapsed_s`; `player_key` (in the session info,
the survey and the voice track) identifies a person across sessions.

`player_key` is a random id stored on each computer (`user://player_key.txt`)
and stays the same across reconnects; `peer_id` in the rows is the network id
at that moment and changes when a player reconnects.

A player who drops out and rejoins the same room within 15 minutes continues the
same session folder and level file. Their voice continues in a second folder,
`<name>_voice_2/` (its own `timeline.jsonl` aligns it to level time).

Levels always run their full time (from 09.11). When nothing is left to do, a
research-only row `all_calls_handled` (`shift`, `at`, `seconds_left`) is logged
and the team sees "Every call handled • stay ready until the shift ends". Older
builds ended the level there instead (`shift_ended_early`, `seconds_saved`).

### 02.11-04.11 builds: session leader only

In those builds only the session leader's computer stored files: its own
`research/<session_id>/` with all game events and its own input, plus
`players/<player_key>/` per other player (that player's own input only,
`"own_input_only": true`, with `player.json`) and `research/voice/team_<session_id>_<id>/`
with every speaker. `analysis/beacon_logs.py` still merges the leader's shared
game events into such a player file.

## Reconnects (02.11)

Departments are fixed while a level runs (and on the results screen). A player
who drops out keeps their seat and departments until the next level starts; on
rejoin they get them back, and nobody else's departments change. Players who
did not return are dropped from the split when the next level starts. A new
player who arrives mid-level has no department until then. The capture of a
reconnecting player continues in the same level file (same `level_run_id`).

## Consent and withdrawal (04.11; storage 09.11)

- Consent is asked on the first screen at launch (placeholder study text in
  `scripts/study_info.gd`, `TEXT_VERSION` "placeholder-2026-11-09"). Each
  recorded session logs a `study_consent` row: `agreed`, `source`
  (`launch_screen`), `text_version`, `placeholder_text`.
- WITHDRAW MY DATA (main menu, results screen, Settings > Research; always
  asks to confirm first) deletes the session folder of the session just played
  from this computer, including its voice folder. Files the player already sent
  are deleted by the researcher.
- `research/withdrawals.jsonl` (one line per withdrawal, on that computer):
  `utc`, `unix_ms`, `session_id`, `player_key`, `text_version`, `deleted`
  (file names only). 04.11 builds also wrote `role` (`solo`, `leader`,
  `teammate`) and handled leader/teammate withdrawals on the leader's computer.
