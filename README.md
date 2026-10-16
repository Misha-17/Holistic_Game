# Beacon Bay

A cooperative pixel-art rescue game for one to four players. Fire, Medical, Engineering and Police each have three crews; calls need several departments working together.

## Play
- Pick a crew, then click a call. Or hover a call and press **1–4** for the nearest available crew in that department.
- **Withdraw a crew from a scene:** click its crew card in the bottom bar, then **WITHDRAW** (or **V**). It leaves the incident and returns to standby; you can send it to another call while it returns, once the normal dispatch cooldown has passed. This also cancels a crew en route or clearing a road. Other crews keep working, and the incident still needs a replacement for the withdrawn department.
- **Change roles between levels:** in the co-op lobby or results screen, click **SWAP** beside a teammate to exchange your department assignments. With two or three players, this swaps the entire department bundle. Roles stay fixed during a level; the host/session leader remains the same player. Joining or leaving redistributes departments to keep every role covered. Solo players already command every department.
- **Q:** scout. **E:** supply a crew on scene. **Space:** coffee boost. **C:** rescue close-up. **R:** ping.
- **Two views only** (playtest 15.10): every level **starts on the whole town**. Click anywhere, scroll up or press **EXPLORE** to open the **drag view** there (5% closer than the old most-zoomed-out level); scroll down or press **OVERVIEW** to return to the whole town. There is no further zooming in (no +/- buttons, no F shortcut). Switching to the whole town closes an open call card.
- In the drag view: **left-drag** pans (middle-drag too), **WASD / arrows** pan, the **minimap** (bottom right, drag view only) jumps; **M** or its HIDE button hides it (music is switched in Settings).
- The map fills the whole screen; the top bar and crew cards float over it, see-through. Markers are kept out from under them.
- Crews and stations are picked the moment you press on them, so a press that turns into a drag still selects the crew. Moving vehicles never steal a click meant for a call or station under them. Station buttons are 20% bigger. A crew's route preview is drawn in its department's colour.
- With a crew selected, clicking a **?** call does **not** send the crew: it opens the call's card with a **SCOUT** button, and the crew stays selected. 1–4 over a ? call also asks you to scout first.
- The clicked call's card has a **CLOSE** button. The whole-town view shows the countryside around the town instead of empty side bars. The pause menu is compact. The results screen shows the rescue goal and says exactly why a level gave no (or fewer) stars.
- **Right-click / Esc:** clear selection.
- Enable **Voice chat** in Settings for an open microphone; turn it off there to mute. No key needs to be held. Use headphones.
- **Esc:** menu. Solo pauses; a shared shift continues while personal menus are open.

Departments split automatically between connected players. The campaign has six 5:30 shifts. The world is **2752 by 1536** (16:9, so the whole-town view fills the screen), with **69 playable locations**. In Oct 2026 (playtest 15.10) one road column with five call sites was added on each side (west: Westwind Farm, Pinecrest Cabins, Old Mill, Heron Marsh Homes, West Beach Huts; east: Summit Lodge, Quarry Works, Seal Point Homes, Cape Clinic, East Beach Cafe); the old town and its stations moved 224 px east unchanged. To keep the balance, crews drive ~8% faster (130 world px/s), every call gets 2 s more decision time, and the finale's rescue goal is 100. Old saves are converted (map version 5); the network protocol is now 11 (including role swaps and withdrawal), so everyone in a co-op game needs this version. A click selects or dispatches on release; dragging across a crew or call never dispatches it. Travel is calibrated to keep the more distant districts practical to reach. Original crew rules, joint calls and campaign remain; the upgrade workshop was removed (Oct 2026).

## Road events (traffic rework, `andrei-traffic-events`)

The old slow zones (school crossing, harbor deliveries, market queues, bridge works, flooded road) are gone. In playtests they only cost travel time and never changed a decision. They are replaced by **road events**: closures that one department must clear for everyone else.

- **Traffic jam** (crash, crowd, stalled bus…): **only Police** drive through it and can clear it (7 s on site).
- **Debris** (fallen tree, burst water main, flooding…): **only Engineering** drive through it and can clear it (9 s on site).
- **Road fire** (burning car, grass fire by the road): **only Fire** drive through it and put it out (8 s). The burning car and smoke are drawn on the road.
- **Accident** (pile-up): **only Medical** drive through it and clear it by treating and taking away the injured (9 s). Wrecked cars, a warning triangle and the injured are drawn on the road.
- Fire and Medical events were added after the 4-player playtest of 15.10 (Police and Engineering had more special jobs). Every level now has about one closure per department (Lights Out: two each for Fire and Medical, one for Police, plus three blackouts for Engineering; the North End blackout was dropped). The call that comes with a closure is always led by a different department than the one that clears it.
- Every other department crawls through a closed street (6% speed) or takes a detour. Each closure is two blocks long, so it also closes the crossing in the middle. Buildings are reached from the road in front of them, so a closure cuts off up to four buildings.
- Each shift's four closures are in four different parts of town (north, centre, east, south).
- Each road event comes with a **call on the closed street** (e.g. injured drivers at Community Hall behind a crash). The team either asks Police/Engineering to open the road first, or crawls in and risks the deadline. That call follows the normal active-call limit.
- **To clear:** pick a crew of the department on the badge (POL jam, ENG debris, FIRE road fire, MED accident), then click the striped road, its badge or its label (the badge and label are always clickable, even when a call marker sits on the road). Or hover the road and press that department's number (**1** Fire, **2** Medical, **3** Engineering, **4** Police). A crew clearing a road is off calls until it's done; the coffee boost speeds clearing too.
- A road nobody clears reopens by itself after 95 s.
- **Fixed script:** four road events per shift, at the same times and places for every group. They start a few seconds into high-chaos phases (sometimes in a normal phase), never in a low phase. Deadlines are calculated as if roads were open, so a closure is a real problem rather than something the countdown silently absorbs.
- Closures show as striped bars in the colour of the department that can clear them, plus red bars on the minimap.
- **Research log:** `road_event_started`, `road_event_clear_dispatched`, `road_event_cleared`, `road_event_expired` (with times, who cleared it, and the chaos phase at the start), plus `road_call_capacity_skipped`.
- **Co-op:** only the player who commands that department can clear; the host checks the crew really belongs to that department.
- Tests: `godot --headless --path . --script tests/test_road_events.gd`. A bot with human-like delays misses 6 calls in shift 1 when it ignores road events and 3 when it clears them; in shift 5 it loses when it ignores them and wins (112/104) when it clears them.

## Map spread, extra crews, early finish (`andrei-traffic-events`)

- **Stations spread over the town:** each department has a main station and a second station in another district. Fire: north-west centre + south-east. Medical: north centre-east + south-west. Engineering: east + west. Police: south centre + north-east.
- **Every department has the same number of crews** (playtest 15.10: every player must carry the same load for the data): **3 each in levels 1–3, 4 each in levels 4–6**. With 4 crews the last three levels have more calls at once (up to 7, 8 in the finale), calls come more often (every 11.8 / 11.4 / 10.8 s on average) and the rescue goals are 104 / 108 / 116. **Level 1 has no road events** (it's for learning the basics). Tested with simulated four-player teams: decent teams win every level with 1–2 stars on levels 4–6; a slow team wins levels 1–4 and usually loses 5–6.
- **Calls spread over the whole town:** 11 new sites in the south and east (59 in total), and calls pick one of nine districts evenly before picking a site. Over all six shifts with a bot: 40 calls in the north third, 70 in the middle, 52 in the south.
- **Shifts end early** once the last scheduled call has arrived, every road event has happened, no call is open and no crew is still out ("Every call handled • shift complete"). Calls keep arriving until about 4:45, so this saves up to ~40 s.
- Disruption texts no longer promise slower travel (only road events slow traffic now).

## Levels 3-6: a map and a hazard each (Oct 2026)

Levels 1-2 keep the normal town. Every later level has its own map and one signature hazard. All of it is scripted (same time, same place, every session), so research data stays comparable.

| Level | Map | Hazard |
|---|---|---|
| 3 **Two Banks** (rain) | A river splits the town; only West, Town and East Bridge cross it. Every department has a station on each bank. | **Bridge floods**: East Bridge 0:50 for 45 s, Town Bridge 2:26 for 60 s, West Bridge 4:05 for 45 s. Nobody can clear a flood; crews reroute over another bridge. |
| 4 **Lights Out** (night) | Moon Lake fills the middle of town; no roads cross it. | **Blackouts** in Lantern Hill (0:42), East Docks (1:46) and Saltmarsh (2:56). In the dark everyone except Engineering drives at 40% and new calls come in unconfirmed. An engineer at the district's substation (yellow ENG badge, 8 s) turns the lights back on; otherwise it lasts 70 s. |
| 5 **Dune Springs** (desert) | Sand town with the Palm Oasis and five streets buried under dunes. | **Sandstorms** sweep across the town in three steps (west → centre → east at 0:46, back east → west at 2:58). Inside the storm everyone drives at 65% and new calls are unconfirmed. Nobody can clear a storm. |
| 6 **Beacon Night** (finale) | The river again. | Everything once: a blackout (Orchard Heights 0:38), two bridge floods (Town 1:44, East 3:28) and a squall sweeping west → east from 2:20. |

- **Forecast:** every flood, blackout and storm step is announced 12 s ahead: a strip under the top bar ("BLACKOUT IN NORTH END IN 7s", then what is active and how long it lasts), a dashed outline with a countdown on the map, a blinking outline on the minimap, a banner and a horn sound. When it hits, a big banner and its own sound (wind, power-down); "LIGHTS BACK ON!" when an engineer restores power. Playtest 14.10: the bridge floods were easy to miss when playing alone.
- **Visuals** are drawn in code like the rest of the town (no image assets): the night town and lake, the dark districts with a few torches, the desert palette with cacti, palms, dunes and the oasis, moving sand / rain over storm districts, and the wall of sand creeping in before it arrives.
- **Sounds** for the hazards (`hazard`, `power_down`, `power_up`, `wind`) are synthesised by `assets/audio/generate_level_cues.py`; drop your own file with the same name into `assets/audio/custom/` to replace one.
- **Rules:** call deadlines assume roads that can be cleared are open (road events, blackouts) and that bridges are open, but include storms (nobody can clear them). Lights Out has no debris closures, because blackouts already keep Engineering busy. Levels 5-6 have a slightly slower call rate (they have more going on) and rescue targets 92 / 108.
- **Under the hood:** `campaign.gd` `layout()` holds each map (water, bridges, buried streets, floods), `level_hazards()` the blackouts and storms. Blackouts and storms reuse the road-event machinery (saved games, co-op guests, the `clear_road` action and research logging all work unchanged). Routes on these levels are found over the real road network. Research log adds `hazard_forecast` plus the existing `road_event_*` records (type `blackout` / `sandstorm` / `squall`) and `bridge_flood_started` / `bridge_flood_ended`.
- Tests: `tests/test_levels.gd` (maps connected, every hazard announced, blackouts restorable, storms, guests in sync, a four-player bot wins levels 3-6) and `tests/test_two_banks.gd`.

## Juicier feedback (Oct 2026)

All cosmetic (in `scripts/juice_fx.gd`); the simulation is untouched, and "Reduced motion" tones it down.
- **Rescue:** confetti burst, a bouncy "+N SAFE" pop-up, little icons flying into the RESCUED counter, which counts up and jumps.
- **Close calls:** "CLUTCH SAVE! 2s LEFT" banner when a call is saved with 5 s or less left.
- **Chains:** "x3 CHAIN!" banners with a rising chime for back-to-back rescues.
- **Sending a crew:** the crew card flashes, the route draws itself on the map, and vehicles on the way have a flashing siren and a dust trail.
- **Road cleared / bridge reopened:** barrier tape snaps apart, a ring and a "ROAD OPEN" pop-up.
- **New call:** the marker drops in with a bounce and sends out a shockwave ring.
- **Missed call:** short screen shake, red edge flash and a "MISSED" pop-up.
- **End of level:** stars pop in one by one with a rising chime; the numbers count up.

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
| Voice chat | Keeps the microphone open until disabled, including in menus. Starts off each launch. |
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

Unit withdrawal and role changes use network protocol **11**. All co-op clients and the server must use this updated build.

Run `powershell -ExecutionPolicy Bypass -File tools/package.ps1` on Windows; pass `-GodotConsole` and `-GodotGui` for other engine paths. It builds the Windows portable package, Linux-server resource pack and clean source ZIP under `artifacts/`. The portable build includes the official Godot runtime because export templates were unavailable locally; its license texts are in `licenses/`.

Tests:

```
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_withdrawal.gd
godot --headless --path . --script tests/test_crew_controls.gd
godot --headless --path . --script tests/test_role_assignment.gd
godot --headless --path . --script tests/test_road_events.gd
godot --headless --path . --script tests/test_levels.gd
godot --headless --path . --script tests/test_two_banks.gd
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
