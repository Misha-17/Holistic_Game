# Beacon Bay

A cooperative pixel-art rescue game for one to four players. Fire, Medical, Engineering and Police each have three crews; calls need several departments working together.

## Play
- Pick a crew, then click a call. Or hover a call and press **1–4** for the nearest available crew in that department.
- **Q:** scout. **E:** supply a crew on scene. **Space:** coffee boost. **F:** whole-town overview on/off. **C:** rescue close-up. **R:** ping.
- **Left-drag:** pan (middle-drag also works). **Wheel:** zoom toward the pointer. **WASD / arrows:** pan.
- **Minimap:** click or drag to jump to another district. **OVERVIEW:** see the whole town; **EXPLORE:** return to a movable close view. Dragging, arrow keys, wheel input and minimap clicks also leave overview automatically.
- Zooming out during play stops before the map fills the window, so you can always keep panning.
- **Right-click / Esc:** clear selection.
- Enable **Microphone** in Settings; hold **V** to talk. Use headphones.
- **Esc:** menu. Solo pauses; a shared shift continues while personal menus are open.

Departments split automatically between connected players. The campaign has six 5:30 shifts. The world is **2304 by 1536**, with **48 playable locations**. Sixteen new locations and streets extend beyond the previous eastern and southern boundaries; the existing 32 sites remain in their original positions. The game starts in a close, movable view. A click selects or dispatches on release; dragging across a crew or call never dispatches it. Travel is calibrated to keep the more distant districts practical to reach. Original crew rules, joint calls and campaign remain; the upgrade workshop was removed (Oct 2026).

## Road events (traffic rework, `andrei-traffic-events`)

The old slow zones (school crossing, harbor deliveries, market queues, bridge works, flooded road) are gone. In playtests they only cost travel time and never changed a decision. They are replaced by **road events**: closures that one department must clear for everyone else.

- **Traffic jam** (crash, crowd, stalled bus…): **only Police** drive through it and can clear it (7 s on site).
- **Debris** (fallen tree, burst water main, flooding…): **only Engineering** drive through it and can clear it (9 s on site).
- Every other department crawls through a closed street (6% speed) or takes a detour. Each closure is two blocks long, so it also closes the crossing in the middle. Buildings are reached from the road in front of them, so a closure cuts off up to four buildings.
- Each shift's four closures are in four different parts of town (north, centre, east, south).
- Each road event comes with a **call on the closed street** (e.g. injured drivers at Community Hall behind a crash). The team either asks Police/Engineering to open the road first, or crawls in and risks the deadline. That call follows the normal active-call limit.
- **To clear:** pick a Police crew (jam) or an Engineering crew (debris), then click the striped road, its POL/ENG badge or its label (the badge and label are always clickable, even when a call marker sits on the road). Or hover the road and press **4** (Police) / **3** (Engineering). A crew clearing a road is off calls until it's done; the coffee boost speeds clearing too.
- A road nobody clears reopens by itself after 95 s.
- **Fixed script:** four road events per shift, at the same times and places for every group. They start a few seconds into high-chaos phases (sometimes in a normal phase), never in a low phase. Deadlines are calculated as if roads were open, so a closure is a real problem rather than something the countdown silently absorbs.
- Closures show as striped bars in the colour of the department that can clear them, plus red bars on the minimap.
- **Research log:** `road_event_started`, `road_event_clear_dispatched`, `road_event_cleared`, `road_event_expired` (with times, who cleared it, and the chaos phase at the start), plus `road_call_capacity_skipped`.
- **Co-op:** only the player who commands Police (or Engineering) can clear; the host checks the crew really belongs to that department.
- Tests: `godot --headless --path . --script tests/test_road_events.gd`. A bot with human-like delays misses 6 calls in shift 1 when it ignores road events and 3 when it clears them; in shift 5 it loses when it ignores them and wins (112/104) when it clears them.

## Map spread, extra crews, early finish (`andrei-traffic-events`)

- **Stations spread over the town:** each department has a main station and a second station in another district. Fire: north-west centre + south-east. Medical: north centre-east + south-west. Engineering: east + west. Police: south centre + north-east.
- **Police and Engineering have 4 crews** (Fire and Medical 3; 14 in total), because they also clear road events.
- **Calls spread over the whole town:** 11 new sites in the south and east (59 in total), and calls pick one of nine districts evenly before picking a site. Over all six shifts with a bot: 40 calls in the north third, 70 in the middle, 52 in the south.
- **Shifts end early** once the last scheduled call has arrived, every road event has happened, no call is open and no crew is still out ("Every call handled • shift complete"). Calls keep arriving until about 4:45, so this saves up to ~40 s.
- Disruption texts no longer promise slower travel (only road events slow traffic now).

## Workshop removed, co-op level picker (Oct 2026)

- **No more upgrades.** The Equipment Workshop is gone from the shift list and the results screen, and crews are never upgraded (old saved upgrades are ignored). Every session plays with the same crews. The results screen shows calls resolved and roads cleared instead of credits, and "Choose another level" replaces "Visit the workshop".
- **Co-op level picker.** In the co-op lobby the host (or, on the Azure server, the first player) picks any of the six levels; all are open in co-op. On the results screen, "Choose another level" takes a LAN host back to the lobby; on the Azure server the first player gets a row of level buttons next to Next shift / Play again.

## Every role equally busy (`andrei-traffic-events`)

Before, each level leaned on some departments (shift 1 was mostly Medical and Police; later shifts mostly Engineering), so some players had little to do. Now:
- **Who leads a call** comes from a fixed per-level order in which Fire, Medical, Engineering and Police each lead once in every block of four calls (`campaign.gd`, `lead_order()`), identical every session.
- **Partners** (the other departments a call needs) rotate with every call, so each department is a partner equally often too.
- The calls that come with road events are led by Fire or Medical, because Police and Engineering already have the road to clear.
- A level's theme now only decides whether an Engineering call is a flood or a power problem (rain and storms: more floods; blackout: more power). Market and festival texts no longer promise extra police calls.
- Result with a bot over all six levels: each department gets 21-29% of the work, counting road clearing (before: 17-35%).

## Softer music

## Local recordings

Use **Settings** or the in-game **AUDIO** button. All capture switches start off each launch.

| Setting | Effect |
| --- | --- |
| Microphone | Enables in-game push-to-talk on V. |
| Allow team recording | Allows teammates to include your transmitted voice in their local files. |
| Save team voice | Saves your own voice plus consenting teammates in one mixed WAV per shift on your computer. |
| Record my mouse | Saves your own in-game movements, every mouse button press/release and wheel input in a local JSONL file. |

**Open recordings** opens the game data folder. Mouse/game logs are under `research/`; audio and its timing sidecar are under `research/voice/`. No recordings upload to Azure. The server relays voice but does not record. Only speech sent using in-game voice is captured; Discord/Teams calls and system audio are not included. Teammates' mouse input is never collected on your computer.

Files begin when a shift starts, including when joining late; tutorials are excluded. Turning saving off pauses capture; turning it back on during the same shift keeps one WAV and inserts silence in the paused interval. End-of-shift, disconnect and normal exit finalize files. WAV headers checkpoint every second and interrupted files can recover on the next launch. Disk failures stop saving without stopping play.

## Repeatable emergency waves

A fixed, versioned normal/high/low sequence and seeded arrival opportunities repeat at the same **active gameplay times** for every group. Phase boundaries never depend on team performance. Solo pause stops the active clock; shared menus do not. All play uses normal speed.

Wave names, transition times and skipped arrivals appear only in local logs when logging is enabled. There are no wave banners, countdowns or phase sound cues. If a group has filled the active-call limit, an arrival opportunity is skipped and logged; later phases retain their original times. Team actions can still change which calls remain unresolved and their outcomes.

The game contains no classifier, workload model, adaptive assistance or required questionnaire.

## Build and verification

Run `powershell -ExecutionPolicy Bypass -File tools/package.ps1` on Windows; pass `-GodotConsole` and `-GodotGui` for other engine paths. It builds the Windows portable package, Linux-server resource pack and clean source ZIP under `artifacts/`. The portable build includes the official Godot runtime because export templates were unavailable locally; its license texts are in `licenses/`.

Tests:

```
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_road_events.gd
godot --headless --path . --script tests/test_player_capture.gd
godot --headless --path . --script tests/test_map_navigation.gd
godot --path . --script tests/test_map_viewport_input.gd
godot --headless --path . --script tests/test_music_audio.gd
godot --headless --path . --script tests/test_session_lifecycle.gd
godot --headless --path . --script tests/test_snapshot_transport.gd
python tests/run_voice_tests.py --godot /path/to/godot
python tests/run_main_network_tests.py --godot /path/to/godot
```

Simulation tests cover all six shifts, tutorial progression, map routes, hidden phases under divergent player decisions, arrival caps and save/network continuity. Voice tests use synthetic PCM and real loopback ENet sessions with four clients. Physical microphones, separate computers and the live Azure subscription still require a real-team smoke test.

See [Azure server setup](azure-connect.md), [validation notes](docs/GAME_POLISH_VALIDATION.md), [navigation evidence](docs/MAP_NAVIGATION_VALIDATION.md), and [asset credits](ASSET_CREDITS.md).
