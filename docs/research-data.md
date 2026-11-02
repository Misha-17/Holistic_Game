# Research files

Collection starts only after the player enables it (asked once per session, at
the first level). Disabling collection stops writing observations immediately.
Solo: files are written on the player's computer. Co-op (from 02.11): only the
session leader's computer writes files; see "Collecting the files" below.
Mouse input belongs to that local player; shared game actions identify their
actor separately with `data.actor_peer`. Voice consent and speaker files are
managed by the voice recorder.

Behavioral records use schema version 4 (3 up to build 0.9.1) and live under Godot's user data folder:

```text
research/<session_id>/
  manifest.json
  session_events.jsonl
  levels/<level_run_id>_events.jsonl
  levels/<level_run_id>_samples_60hz.csv   (schema 4)
```

`session_events.jsonl` is the authoritative timeline for the whole play session.
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
(`after_last_level` or `title_button`), `last_level_number`, `last_level_won`,
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

## Collecting the files (02.11: session leader only)

In co-op only the **session leader's** computer stores study files: the LAN
host, or on the Azure server the first player who joined (while they are
disconnected the next player stands in). Nothing is stored on the server and
nothing is uploaded. Collect everything from the leader's
`research/` folder (Settings > Research > OPEN RECORDINGS):

```text
research/<session_id>/
  session_events.jsonl, levels/<level_run_id>_events.jsonl,
  levels/<level_run_id>_samples_60hz.csv, manifest.json   leader: all game events + own input
  questionnaires/                                         leader's answers
  players/<player_key>/                                   one folder per other player
    player.json                                           name, departments, every peer id
    session_events.jsonl, levels/..., manifest.json       that player's own input only
    questionnaires/
research/voice/team_<session_id>_<id>/                    all speakers, one track per person
```

A non-leader's files hold only rows about that player's own input and view
(`mouse_motion`, `mouse_button`, `key_input`, `ui_action`, `crew_selected`,
`crew_deselected`, `department_filter`, `inspection`, `command_requested`,
`task_state`, `context`, `display`, consent/briefing/microphone rows, plus the
capture/level/sampler lifecycle) and their 60 Hz samples. Calls, dispatches,
hazards and outcomes are recorded once, in the leader's files; join on
`level_run_id` and `level_elapsed_s` (`analysis/beacon_logs.py` merges them
automatically). Their `manifest.json` has `"own_input_only": true`.

`player_key` is a random id stored on each computer (`user://player_key.txt`)
and stays the same across reconnects; `peer_id` in the rows is the network id
at that moment and changes when a player reconnects.

If the leader cannot be reached, a player's data waits in memory (up to 64 MB)
and is sent when they are back. If the leader leaves for good, the next player
becomes leader and stores files from then on.

## Reconnects (02.11)

Departments are fixed while a level runs (and on the results screen). A player
who drops out keeps their seat and departments until the next level starts; on
rejoin they get them back, and nobody else's departments change. Players who
did not return are dropped from the split when the next level starts. A new
player who arrives mid-level has no department until then. The capture of a
reconnecting player continues in the same level file (same `level_run_id`).
