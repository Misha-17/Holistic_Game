# Research files

Collection starts only after the player enables it. Disabling collection stops
writing observations immediately. Files are local to each recorder's computer.
Mouse input belongs to that local player; shared game actions identify their
actor separately with `data.actor_peer`. Voice consent and speaker files are
managed by the voice recorder.

Behavioral records use schema version 3 and live under Godot's user data folder:

```text
research/<session_id>/
  manifest.json
  session_events.jsonl
  levels/<level_run_id>_events.jsonl
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
