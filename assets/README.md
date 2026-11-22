# Game assets

This directory separates source assets by how the game consumes them:

- `artwork/`: static visual assets, texture sources, and visual source/export notes.
- `sound_effects/`: short sounds for UI and gameplay events.
- `music/`: background tracks, loops, stems, and their source/export notes.
- `animations/`: Godot animation resources and event or interaction timing definitions.

Use Godot paths rooted at `res://assets/`. Keep editable source files beside concise export notes when the shipped file is produced from a separate working format.

Rendered frames and sprite-sheet images belong in `artwork/`; the Godot resources that control their playback and timing belong in `animations/`.

## Match UI artwork

The match scene is authored at 1920 × 1080. Assign textures in the inspector on `MatchScreen/TableScenery` and leave transparent space in the artwork outside its visible silhouette. Export separate textures for the three context backdrops, table surface, lower bar, hand tray, score bar, clock housing and clock face. Export the clock pointer and cycle arrow pointing right on a transparent canvas. Godot places and rotates them, so keep the pointer's pivot at the left-center edge.

`MatchScreen` exposes texture-backed styles for the phase badge, player score, opponent seats and reveal panel, plus three context-sort textures. Disable **Show Placeholder Guides** once the corresponding art is in place. The table and clock guides disappear, and the layout and input regions still work. Skin the remaining native controls with texture-backed styleboxes in the game theme.

The playing-card frame uses the panel style in `card_widget.tscn`, with a separate **Selected Panel Style**. The landscape card in `ability_card.tscn` has separate backgrounds and frame styles for Manipulation, Field, Buff / Nerf, and Sabotage. Card text remains editable by the game.
