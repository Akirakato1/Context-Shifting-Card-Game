# Game assets

This directory separates source assets by how the game consumes them:

- `artwork/`: static visual assets, texture sources, and visual source/export notes.
- `sound_effects/`: short sounds for UI and gameplay events.
- `music/`: background tracks, loops, stems, and their source/export notes.
- `animations/`: Godot animation resources and event or interaction timing definitions.

Use Godot paths rooted at `res://assets/`. Keep editable source files beside concise export notes when the shipped file is produced from a separate working format.

Rendered frames and sprite-sheet images belong in `artwork/`; the Godot resources that control their playback and timing belong in `animations/`.
