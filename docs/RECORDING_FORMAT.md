# Collection and playback (0.9.0)

Choose **Enable collection** on first level entry, or use Settings > Research. The entry choice is remembered for this launch; nothing is collected by default on the next launch. Mouse/gameplay saving, permission for teammates to save your voice, and local voice saving remain separate switches. The microphone requires **Voice chat** under Sounds. Collection never records Discord, Teams, other apps or system audio.

One local session spans levels, retries and the results screens between them. Disconnecting, leaving to the title screen or exiting ends that session. Each new level attempt has its own `level_run_id`; co-op players share the host's run ID. A resumed saved game starts a new attempt and records the state when observation begins. The old guided tutorial is excluded; Level 0 is included when enabled.

## Mouse and game events

Use **Open recordings**, then `research/<session_id>/`:

- `session_events.jsonl`: the authoritative session timeline, one JSON object per line.
- `levels/<level_run_id>_events.jsonl`: the same rows grouped by level attempt.
- `manifest.json`: level numbers, names, attempts, file paths and clock descriptions.

Do not concatenate the session file and level files: the level files mirror the session's sequence IDs. Every input row includes the level, active gameplay clock, monotonic local clock, local player/departments and current event IDs. Mouse records include motion, all button presses/releases and wheel input; context identifies the selection, map position and UI target. Game actions identify the actor; remote actions never manufacture local mouse records.

`event_started`, `event_observed` and `event_ended` correlate incidents, road events, blackouts, bridge floods, storms and disruptions. End records include `solved`, outcome and elapsed times. Unclear outcomes after a capture gap are marked unknown/censored. `solved: null` distinguishes passive hazards that players cannot clear. Practice helper handoffs are not counted as player rescues. Raw lifecycle records retain the authoritative simulation details. See [research schema details](research-data.md).

## Voice

Under `research/voice/`, open a `team_<session_id>_…` folder:

- **`listen.html`**: offline session player. Play/pause/seek the whole conversation, jump to a level, and mute or solo individual speakers. Labels and activity indicators help identify who is speaking.
- **`session.json`**: speaker identities, departments, WAV filenames, common frame clock and level segments.
- **`peer_<id>.wav`**: isolated mono PCM16 audio for each recorded speaker, 16 kHz. Import all tracks at time zero in an audio editor for the complete synchronized session.
- **`timeline.jsonl`**: recording changes, level markers and consent/timing metadata.

Overlapping voices stay on separate tracks; no speech separation or transcription model is used. Every track starts at frame zero and ends at the same frame. Late joins, disabled saving, results screens, nonconsent and missing packets become silence on the shared timeline. Activity indicators describe audio energy, not guaranteed speech recognition. Only consenting remote players are saved. Capture may include background sound transmitted through their in-game microphones.

The gameplay and voice metadata share `capture_session_id` and `level_run_id`. Gameplay seconds stop on a solo pause; audio uses wall time, with level clock markers to align the two. During a level, voice continues in personal menus. Between levels it is silent. Files stay on each recording player's computer; the relay server does not record them.

WAV headers and manifests checkpoint during recording. Interrupted sessions recover on next launch. File errors turn saving off without stopping the game. For a finalized offline player and complete final metadata, leave the game normally or disconnect before opening the folder.

## Validation

Godot tests cover Level 0's fixed schedule and low-pressure rules, first-entry choices, per-role instructions, multiplayer readiness, replay/session continuity, event outcomes and capture gaps. Voice tests use distinct overlapping synthetic signals and real ENet clients to verify isolated samples, consent filtering, timing alignment and interrupted-file recovery. Real microphones and separate computers still need an end-to-end team playtest.
