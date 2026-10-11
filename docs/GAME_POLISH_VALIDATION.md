# Game improvement validation

Revised and built 12 October 2026 from `main` commit `6aa6a644db324576bcc8b7d739fe956bcd1f3c8d`, which contains the agreed `Andrei's-New-Branch` gameplay (`515146b6f7c12114d597445fbc7c893a8a6436ae`) plus Azure support. Work is isolated in `BeaconBay-Game`, branch `feature/game-polish`. Existing local working changes in `Holistic_Game` were not modified.

## Scope delivered

- Version 0.8 restores the original native pixel buildings, vehicles, responders and action animations, with muted colours, clearer streets, gardens, an orchard, harbor bridge and new districts. The original coastline title and friendly tutorial portraits return. Version 0.7's illustrated assets are excluded from playable packages.
- Map v4: 2304x1536, 48 playable sites. The existing 32 sites stay at the same physical positions; 16 new sites and their streets extend east and south beyond version 0.7's boundaries. Travel runs at 120 world pixels/second. Migration supports v1/v2/v3 saves and keeps v3 physical positions and paths intact.
- Fixed the overview navigation trap: a fitted map previously clamped all pan requests back to center. Overview drag, wheel, keyboard and minimap now return to exploration; ordinary zoom-out stops at a movable view. New/resumed sessions start around the main stations. Real viewport input was tested in full-size and resized windows; see `MAP_NAVIGATION_VALIDATION.md`.
- New soft, drum-free score at 72 BPM, music bus reduced from -8 to -20 dB, four-second fade-in and two-second fade-out. Emergency pressure no longer selects tense/panic music layers. Voice and sound-effect bus levels are unchanged.
- Versioned fixed normal/high/low phase timing and arrival opportunities; private research events only; no phase announcement UI/audio.
- Local-only full delivered mouse motion plus button/down/up/wheel JSONL, game-time and local monotonic timing.
- In-game push-to-talk and mixed local WAV per shift, independent microphone/sharing/saving controls, recording status, bounded jitter buffering, silence/gap metadata, checkpointed WAV and interrupted-file recovery.
- Linux Server export preset, packaged Azure resource pack and service example; repeat sessions without restarting server; protocol version checks.
- No classifier, model training, inference or mandatory survey.

## Executed checks

`tests/test_simulation.gd`: passes fixed phases under different action streams/RNG usage and frame cadence; capped arrivals logged without moving later phases; save/network continuation; all 48 sites, complete routes and all-four-department rescues in each added district. All 15 tutorial stages finish with exactly five authored calls rescued and no ambient phase/arrival events. Six no-upgrade automated campaign runs reach their targets.

`tests/test_music_audio.gd`: measured actual AudioServer output with the new stream: normal peak -26.59 dBFS/RMS -38.42 dBFS; busy peak -27.14/RMS -38.19. Verified audible music, fades, mute/restart, looping, no pressure layers and unchanged voice/SFX bus levels.

`tests/test_map_navigation.gd`: passes drag across crew/call without dispatch, small-movement release-click exactly once, offscreen pin culling, minimap jump, overview/return, zoom anchoring, middle-drag, HUD input and exactly-once mouse logging.

`tests/test_player_capture.gd`: passes all mouse buttons/releases, wheel and motion logged once before input is consumed; research phase metadata creates no visible message; recording opt-ins and tutorial exclusion; solo pause/shared menu time behavior; camera bounds.

`tests/test_session_lifecycle.gd`: passes guest commands while the host opens pause/help/settings; host snapshots preserve guest menus; rejected tutorial does not split recordings; replay creates fresh files; disconnect finalizes local WAV and events.

`tests/run_main_network_tests.py`: the actual game scene passes dedicated-server/client lobby, first-player start, menus during active simulation, results, replay and server disconnection. Tutorial camera reset/restoration also passes. A disconnect-time voice RPC race found during this test was corrected and the test rerun successfully.

`tests/test_snapshot_transport.gd`: passes stale/duplicate rejection across reliable and unreliable snapshot channels, invalid payload rejection and reconnect sequence reset. Oversized compressed snapshots now use a separate reliable channel; the actual game network test was rerun without oversized-packet or unknown-peer warnings.

Both exported resource packs are checked during packaging. The portable Windows executable rendered the expanded map from its packaged resources; the Linux Server pack started headlessly using the local Windows Godot runtime. This checks pack contents and startup, not Linux VM deployment.

`tests/run_voice_tests.py`: passes synthetic microphone PCM through real ENet, dedicated server with four clients and desktop host with three clients, late joining and departure, mixed local+remote voices, speaker consent filtering, no loopback/duplication, legacy protocol rejection. Mixer tests cover missing-packet silence, clipping, bounded queues; file tests cover pause/resume in one file, valid WAV headers, recovery and flushing final buffered speech.

Rendered version 0.8 screenshots of the default close view, full-world overview, minimap navigation, selected calls, zoom, tutorial, Settings, lobby and new title were inspected. A separate rendered atlas preview covers pixel crew actions, portraits and the pixel incident close-up. The graphical run reports no script/runtime errors. The host environment emits a Windows certificate-store warning unrelated to game networking. Earlier headless tests exposed MP3 cleanup warnings; the final scripted graphical run exits cleanly aside from the certificate warning.

## Limits

Automated voice tests use synthetic signals, not physical microphones or a listening panel. Real headset input/output, separate computers, WAN conditions and the client Azure subscription remain to be checked by the team. Automated dispatch policies establish software playability, not human enjoyment or difficulty calibration. Files are not uploaded and no live Azure resources were changed.

Wave phases are identical at active session times. Resolutions and active-call caps can produce different backlogs and skipped arrivals between teams; the logs distinguish those events. Ordinary solo pauses stop the game clock, and restored games continue their saved phase.
