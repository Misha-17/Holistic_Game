# Beacon Bay 0.8

A cooperative pixel-art rescue game for one to four players. Fire, Medical, Engineering and Police each have three crews; calls need several departments working together.

## Play

In the Windows package, double-click **Play.cmd**. Keep BeaconBay.exe and BeaconBay.pck together. For source, open project.godot with **Godot 4.7 stable**.

Choose **Meet the crew** for practice, **Play solo**, or **Play with friends**. Host a room on your LAN or join the Azure server address. All players and the server must use this build (network protocol 8).

- Pick a crew, then click a call. Or hover a call and press **1–4** for the nearest available crew in that department.
- **Q:** scout. **E:** supply a crew on scene. **Space:** coffee boost.
- **Left-drag:** pan (middle-drag also works). **Wheel:** zoom toward the pointer. **WASD / arrows:** pan.
- **Minimap:** click or drag to jump to another district. **OVERVIEW:** see the whole town; **EXPLORE:** return to a movable close view. Dragging, arrow keys, wheel input and minimap clicks also leave overview automatically.
- Zooming out during play stops before the map fills the window, so you can always keep panning.
- **Right-click / Esc:** clear selection. **F:** rescue close-up.
- Enable **Microphone** in Settings; hold **V** to talk. Use headphones.
- **Esc:** menu. Solo pauses; a shared shift continues while personal menus are open.

Departments split automatically between connected players. The campaign has six 5:30 shifts. The world is **2304 by 1536**, with **48 playable locations**. Sixteen new locations and streets extend beyond the previous eastern and southern boundaries; the existing 32 sites remain in their original positions. The game starts in a close, movable view. A click selects or dispatches on release; dragging across a crew or call never dispatches it. Travel is calibrated to keep the more distant districts practical to reach. Original crew rules, joint calls, upgrades and campaign remain.

## Softer music

A new gentle, drum-free score uses soft keys and sustained chords at 72 BPM. Music is 12 dB quieter than version 0.7, fades in over four seconds, and stays calm during busy periods. Voice and sound-effect levels are unchanged.

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
