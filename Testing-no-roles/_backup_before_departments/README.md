# Beacon Bay

A 2D pixel rescue coordination game made with Godot. Six 5:30 shifts provide 33 minutes of active campaign time, plus a character-led tutorial and equipment upgrades.

## Run the game

Open `project.godot` in Godot 4.7 and press F5. The project uses the Compatibility renderer. The source and assets are included; no external add-ons are required.

## Controls

Select a numbered call, then choose a specific responder on the map. Hover over a station or vehicle to inspect its crew. Click the crew, review the route, then press Enter or the map's Send button.

- 1 / 2 / 3: highlight fire / medical / engineering crews
- Q: scout the selected call
- E: use supplies
- Space: Rally the team
- F: show the live rescue close-up
- Tab: cycle calls
- Escape: pause
- F11: fullscreen

Crew cards locate responders on the map. Different starting positions and road conditions affect response time. A wrong specialist spends the trip without completing the rescue. Play Meet the Crew to learn the controls through five practice rescues.

## Project contents

- `scripts/`: game and character showcase code
- `scenes/`: main game and separate character showcase
- `assets/art/`: game art and concept studies
- `assets/characters/`: transparent boards, pixel sprite atlases and animation resources
- `assets/audio/`: original music, effects and their Python generator

The separate character showcase can be run from `scenes/character_showcase.tscn` with F6.

## Data and multiplayer

Progress saves locally. Research logging is optional, off on each launch, and stays on the player's computer. No microphone recording or automatic data upload is implemented. LAN play supports up to four players; separate-machine LAN compatibility has not been verified.

## Export

Install the matching Godot export templates, open Project > Export, and use Windows Desktop. Create the local `build` folder if needed. Compiled builds and generated caches are excluded from Git.

See `ASSET_CREDITS.md` for asset provenance.
