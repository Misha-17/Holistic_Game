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

## Department prototype (branch idea, Oct 2026)

This copy tests a "one role for everyone" model instead of the four specialist roles (Dispatcher, Resource manager, Field coordinator, Support lead).

- There are four departments: Fire, Medical, Engineering and **Police** (new).
- Every player has the same job: send the crews of the departments they command. Departments split automatically by player count:
  - 1 player: all four
  - 2 players: Fire + Engineering / Medical + Police
  - 3 players: host gets Fire + Police, the others Medical / Engineering
  - 4 players: one department each
- If someone leaves, departments reshuffle for the remaining players.
- Everyone sees the whole map and can scout, use supplies, rally and ping. You cannot send another player's crews (the host also enforces this), so calls that need two crew types force players to talk.
- The dispatch cooldown is now per department, so four players can send crews at the same moment.
- Police calls: car collision, lost child, crowd at the square, break-in, blocked junction. Police also back up severe floods (evacuation) and power cuts (traffic lights out). Market and festival disruptions bring more police calls.
- Keys 1-4 highlight Fire / Medical / Engineering / Police crews.
- The tutorial still teaches only the original three crews.

### Changes from 4 Oct 2026

- **Sending a crew:** pick a crew first (click a station, a vehicle on the road, a crew card, or press 1-4), then click the call. The selected crew gets a pulsing gold ring. Hover a call to see the route and whether they make it in time. Right-click or ESC clears the selection. There are no crew pop-up menus any more.
- **Teams:** every call needs 2-4 departments (no single-department calls since 7.10.2026). Severity 1 = two departments, 2 = three, 3 = all four. All-four calls appear in every shift, including shift 1, after the first minute: 10% of calls in shift 1, 12% / 14% / 16% / 16% / 20% in shifts 2-6, and every shift is guaranteed at least one by its 8th call and two by its 16th. Three-department calls are slightly less common in later shifts (28% + 4% per shift instead of 30% + 5%) to keep shift 5 fair. Icons under each call show which crews it still needs. The tutorial still uses one-crew calls to teach one thing at a time.
- Balance check (bot with human-like delays): wins all six shifts. Shift 1 has 3 four-department calls, 0 failures (116/60). Shift 5 is the tightest: 114/104 with community at 56 against a 50 minimum. Four-department calls fail no more often than smaller ones, so deadlines were not changed.
- **3 crews per department** (12 in total) so team calls stay winnable.
- **Scouting** only reveals what a "?" call needs. It no longer adds time.
- **Supplies** only work once a crew is on scene.
- **Upgrades** that add extra crews are gone; the other upgrades stay for now.
- **Full HD:** the game canvas is 1600x900 (16:9), so fullscreen (F11) fills 1920x1080 exactly and everything is 20% bigger and crisp.
- **Less text:** the game name, level name, map labels, hint line, workshop credits and the "watch crew" button are gone from the game screen. The top bar shows rescued / target, community, time, and a flashing warning before each wave. New calls pulse on the map and in the list.
- The tutorial follows the new flow (scout, send Bram, supply once he arrives).
- **Full-screen map (later on 4 Oct):** the town now fills the whole window at an exact 3x pixel scale. The top bar (rescued, community, time, rally, help, pause) floats over the map, see-through and click-through except its buttons, and call markers are pushed out from under it. The crew strip at the bottom is also see-through. The call list, the crew/call side panel and the crew-updates ticker are gone; the selected call's map card shows what it still needs, who to ask in co-op, and the Q/E hints. North Pier's call spot moved slightly inland so it never sits under the crew strip.
- **Attention and readability (4 Oct, later):** every call has a countdown ring (green, yellow, red) with the seconds in big outlined numbers. New calls flash gold with a NEW tag; calls still missing crews pulse; calls under 20 s that still need crews throb with big red rings. Map text uses a heavier outlined font; the call card says IN TIME +12s / TOO LATE -5s. Vehicle rings are quieter so they don't look like calls.
- **Temporary send shortcut:** hover a call (or select one) and press 1 / 2 / 3 / 4 to send the nearest free fire / medic / engineer / police crew there. The call card shows which keys it still needs ("PRESS 1 FIRE 2 MED").
- "Rally" is now **Coffee Boost** (SPACE).
- **Font:** back to the normal font (the artificially bolded version rendered with holes); map text keeps its larger size and dark outline.
- **Countdowns are real seconds now.** Before, a call's timer slowed to about a quarter speed once crews arrived and sped up as danger rose. Now it always ticks one second per second; each deadline includes the crews' work time instead (balance re-checked with the bot).
- **Sound:** drop-in sound folder `assets/audio/custom/` (see SOUND_LIST.txt there). New sound slots: new_call, tick (every second while a call is about to fail without its crews), select, boost, win, lose. With custom music the game crossfades calm -> tense -> panic as the town's pressure rises.

### Playing on two or more computers

The host clicks PLAY WITH FRIENDS > HOST A ROOM. The lobby shows the addresses to share.

- **Same Wi-Fi / LAN (easiest):** others type the "Same network" address (e.g. 192.168.1.23) and press JOIN.
  - The first time, Windows asks whether Godot / Beacon Bay may use the network: tick **Private networks** and allow. If you clicked away, allow `Godot` (or the exported game) in Windows Defender Firewall, or allow UDP port 24680.
  - Your Wi-Fi must be set to a *Private* network in Windows. Campus or guest Wi-Fi often blocks devices from seeing each other; use a phone hotspot or Tailscale instead.
- **Over the internet:** the host's game asks the router to open UDP port 24680 (UPnP). If it works, the lobby shows "friends can join <public IP>". Many routers and mobile networks don't allow this.
- **Reliable fallback (no router settings):** install Tailscale (free) on every computer, sign in to the same account/tailnet, and join using the host's 100.x.x.x address, which also appears in the lobby. ZeroTier or Radmin VPN work the same way.
- A join gives up after ~9 seconds with a hint instead of hanging.
- Smooth guests (laptop lag fix): the host now sends a lean network copy of the game state (no save-file encoding, no shift plan, no event log, settled calls dropped after 8 s): about 5x smaller and about 4x faster for the guest to apply. Between updates the guest runs the same simulation itself, so crews glide and countdowns tick every frame; each host update corrects it (measured error under 2 px, timers within 0.02 s). A guest's own dispatch moves the crew immediately instead of waiting for the host. Crew markers on the road now move every frame (also on the host), and the town backdrop is no longer repainted on every update.
- Press **F3** in game to show FPS, ping to the host and how often host updates arrive. Low FPS = the computer is slow at drawing; high ping or long update gaps = the network.
- The IP box in the lobby was hidden behind the menu panel after the full-screen change; it is visible again.

To test multiplayer on one computer: in the Godot editor choose Debug > Customize Run Instances, enable multiple instances (2-4), press F5, host in one window and join 127.0.0.1 in the others.

A backup of the code before this change is in `_backup_before_departments/` (ignored by Godot).

## Data and multiplayer

Progress saves locally. Research logging is optional, off on each launch, and stays on the player's computer. No microphone recording or automatic data upload is implemented. LAN play supports up to four players; separate-machine LAN compatibility has not been verified.

## Export

Install the matching Godot export templates, open Project > Export, and use Windows Desktop. Create the local `build` folder if needed. Compiled builds and generated caches are excluded from Git.

See `ASSET_CREDITS.md` for asset provenance.
