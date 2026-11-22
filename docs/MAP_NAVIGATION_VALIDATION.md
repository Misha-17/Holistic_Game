# Map navigation regression, 0.8.0

The 0.7.0 whole-town view could look stuck. Drag, arrow keys, and minimap clicks changed the requested camera position, but the map already fitted inside the viewport, so the camera bounds immediately centered it again. Wheel zoom could enter that view without an explicit overview action. The `BACK` label did not explain that it was the way to restore exploration.

This was reproduced through `Input.parse_input_event` in a rendered desktop window, with the real viewport converting physical window positions into game coordinates. Normal close-view dragging and resized-window input already worked; six overview navigation checks failed before the fix. The before/after camera positions and screenshots are generated under `test_output/navigation-baseline*` and `test_output/navigation-fixed*`.

## Current controls

- New, resumed, and newly joined/replayed sessions start in the close exploration view around the four main stations, with useful crews visible immediately.
- Hold the left mouse button and drag to pan. A movement of at least 6 game pixels becomes a camera gesture and never selects or dispatches the underlying crew/call.
- Scroll to zoom around the cursor. Exploration stops at a movable zoom level, with room to pan in both directions.
- `OVERVIEW` deliberately fits the whole town. `EXPLORE` restores the previous camera.
- Dragging, scrolling, clicking the minimap, or using the arrow/WASD keys in overview returns to exploration automatically. Clicking a district in overview opens that district.
- Middle-button pan and minimap dragging remain available. Releasing over tutorial controls ends the gesture safely.

The map dimensions come from the campaign. At 2304×1536, default zoom is 1.5, the exploration zoom floor is 1.0, and deliberate overview is approximately 0.542. Routine multiplayer snapshots preserve each player's camera; session replays start close again.

## Reproduce

From the project root, using Godot 4.7:

```powershell
godot --path . --script res://tests/test_map_viewport_input.gd --resolution 1600x900
godot --headless --path . --script res://tests/test_map_navigation.gd
godot --headless --path . --script res://tests/test_player_capture.gd
godot --headless --path . --script res://tests/test_session_lifecycle.gd
```

`test_map_viewport_input.gd` exercises the actual input pipeline at 1600×900, resizes the desktop window to 1100×700 with letterboxing, and verifies transformed pointer coordinates, visible camera movement, overview escape, minimap travel, wheel limits, rendered button hitboxes, and tutorial releases. Its rendered run writes camera evidence to `test_output/navigation-fixed.json` and before/after PNGs. It also runs headlessly without screenshots.

`test_map_navigation.gd` now uses `Input.parse_input_event` instead of calling the game's input handler directly. It verifies release-only dispatch, drag suppression over calls and crews, offscreen marker rejection, zoom anchoring, HUD input, and exactly one local recording entry per delivered mouse event. Capture and lifecycle suites cover camera bounds, tutorial restoration, replay resets, menu continuity, and disconnect cleanup.

To render the final title, default camera, dragged camera, full overview, southeast minimap destination, calls, zoom, settings, lobby, and tutorial:

```powershell
godot --path . --script res://tests/capture_screens.gd --resolution 1600x900
```

These screenshots are written to `test_output/*-v8.png`. The minimap capture enters the southeast extension directly from overview through a real viewport click.

## Verified result

On 12 October 2026, the rendered viewport regression passed at both window sizes with the 2304×1536 map and restored native pixel renderer. The drag-versus-click, player capture, and session lifecycle suites also passed. The actual ENet main client/server suite passed lobby, start, menus, results, replay, local recording, and disconnect checks. Screenshots were reviewed for default station visibility, changed streets after dragging, southeast district travel, full overview, title, calls, and tutorial controls.
# 0.9.1: camera stays in the selected view

Selection no longer switches out of overview or recentres the map. Navigation regression coverage now includes call/crew/station selection, unconfirmed calls, scouting, dispatch, department keys, crew-bar actions, Tab cycling and focus panels in both views. Dragging, middle-drag and arrow keys retain zoom; wheel and EXPLORE/OVERVIEW are the explicit view controls.

`test_map_navigation.gd` and `test_map_viewport_input.gd` passed headlessly. The viewport suite also passed with the Windows rendering driver, including resized-window input. The new ordered level-card menu and practice map without its title/subtitle were rendered and visually inspected using `tests/capture_level_entry.gd`.

