# Asset credits

Version 0.8 uses the original Beacon Bay pixel drawing code for its buildings, vehicles, responders and rescue animations, with softer colours, improved street details and an expanded world. Shared native drawing is in `scripts/pixel_town_art.gd` and `scripts/responder_art.gd`. The original pixel coastline title and friendly tutorial portrait sheet are used again; those images were generated for the original project.

Version 0.7's illustrated experiments remain in `assets/illustrated/` in the source history. They are excluded from the playable version 0.8 packages. Their generation prompts are retained alongside them. No frames from the user's supplied Parasoul animation are included in the game.

The new original soft score is `assets/audio/beacon_bay_soft_v080.wav`, reproducibly synthesized by `assets/audio/generate_soft_music_v080.py`. It uses soft keys and sustained chords at 72 BPM, without sampled instruments or percussion. Original music and sound effects were synthesized by `assets/audio/generate_audio.py`; earlier tracks remain in the source. The lighthouse SVG icon is original project content.

The project runs in Godot, which is MIT licensed. The Windows package includes the official Godot 4.7 runtime and notices in `licenses/`. The game uses the engine's bundled fallback font.
