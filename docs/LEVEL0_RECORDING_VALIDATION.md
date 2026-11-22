# Level 0 and recording validation — 21 October 2026

Validated with Godot 4.7 on Windows.

Passed simulation suites: `test_practice_level`, `test_simulation`, `test_levels`, `test_road_events`. Practice is exactly 150 active seconds, idle play cannot fail, scripted events repeat, and a relaxed simulated player completes every clearable exercise. Existing campaign, route, tutorial and save behavior passes.

Passed integration suites: `test_level_entry`, `test_player_capture`, `test_session_lifecycle`, `test_research_lifecycle`, `test_capture_event_order`, `test_playtest_19_10`, `test_role_assignment`, `test_map_navigation`, `test_remote_route`, `test_snapshot_transport`.

Research tests cover level files and attempts, actual clocks, consent gaps, snapshot observation, resolved/expired/passive/unfinished outcomes, and event correlation. Ordering tests deliberately deliver a results snapshot before its reliable completion event, and a new-level snapshot before its transition marker. Old outcomes remain in their original run and final clocks/totals remain authoritative.

The main client/server ENet suite passes both normal operation and `--briefings`, which uses the real collection prompt and ready handshake. Shared time stays at zero through consent and instructions; menu behavior, following-level readiness and disconnect finalization pass.

The voice runner passes synthetic sample tests and four-player ENet scenarios with overlapping signals, player arrivals/departures, consent changes, isolated speaker tracks, equal timelines, recovery, file headers and disk errors. The offline player was checked in headless Edge for named tracks, WAV loading, shared seeking/play/pause and mute/solo. The existing open-voice and playback-continuity tests pass.

Rendered screenshots were inspected for collection, Engineering instructions and the new Training Harbor overview. Capture scripts are `tests/capture_level_entry.gd`; generated evidence remains under `.tools/level-entry/` locally.

Physical microphones, human listening, separate computers and the deployed Azure server require a team playtest. No Azure deployment was performed. All clients/server require protocol 13. The sandbox environment reports a Windows certificate-store warning during headless runs; some UI harnesses also report two references retained at process exit. No GDScript parse/runtime errors remain in the validation runs.
