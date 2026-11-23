# Shift

**Shift** is a work-in-progress competitive card game built with Godot 4 and typed GDScript. Players combine context-specific half-cards, preserve useful cards for future contexts, and simultaneously submit hands to compete for the highest score.

The three contexts advance in a predictable cycle:

```text
Rise (興) → Flourish (盛) → Fall (衰) → Rise
```

The English names are used in code and the current placeholder interface. The traditional Chinese characters guide the visual direction.

## Current scope

- Two to four active players and up to four spectators.
- Host-authoritative multiplayer entered through a six-character lobby code.
- Direct WebRTC gameplay between each participant and the player-host.
- Cloudflare TURN fallback for networks that cannot establish a direct route.
- Simultaneous timed phases, reconnect grace, late player entry, and spectator-safe public state.
- Deterministic, rendering-independent model and controller with a functional 2D interface.
- Persistent card modifications, Joker half-cards, normal-hand evaluation, context-hand evaluation, abilities, fields, and two victory modes.
- Windows x64 as the initial game-jam and itch.io target.

The suits are finalized as Mountain, Cloud, and Sea. The 40-pattern context-hand catalogue and 18-pattern normal-hand catalogue have rarity-derived priorities and exact initial multipliers. Ability copy-count tuning, artwork, animation, sound, and music remain open to playtesting and production work.

## Technology

- [Godot 4.7.2](https://godotengine.org/) with typed GDScript
- [`godotengine/webrtc-native` 1.2.2](https://github.com/godotengine/webrtc-native) for desktop WebRTC
- Node.js 22.12+ for local signaling and Cloudflare Workers deployment
- Cloudflare Realtime TURN for optional connection relay

The signaling service exchanges connection information and temporary ICE credentials only. It does not run the match or store cards, scores, deck order, or other authoritative game state.

## Getting started on Windows

1. Install Godot 4.7.2 stable.
2. Clone the repository and open `project.godot` in Godot.
3. Install the verified Windows x64 WebRTC extension:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install_webrtc.ps1
   ```

4. Install and start the local signaling service in a separate terminal:

   ```powershell
   Set-Location service/signaling
   npm install
   npm start
   ```

5. For local signaling, set `SHIFT_SIGNALING_URL=ws://127.0.0.1:8080` in the environment that launches Godot. The project setting supplies the public signaling endpoint by default.

Permanent Cloudflare TURN credentials belong only in the signaling host's encrypted environment settings. Never place them in `project.godot`, a game export, or source control.

### Optional audio assets

The project can run without the third-party sound packs. To enable card interaction sounds and table ambience in local builds, download the packs from their creators and place the WAV files in these folders.

- [Card Game SFX Lite by Willosuna](https://willosuna.itch.io/card-game-sfx-lite) goes in `assets/sound_effects/Card Game SFX Lite (Free)/` with the original `wav/oneshots/` and `wav/loops/` subfolders.
- [Tabletop Games Sound Effect Pack by JDSherbert](https://jdsherbert.itch.io/tabletop-games-sfx-pack) goes in `assets/sound_effects/Tabletop Games SFX Pack/`. The game uses the WAV files for Deck Deal 2, Dice Pickup 2, and Piece Impact 2 with their original filenames.

## Tests

Set `SHIFT_GODOT_BIN` when Godot is not available on `PATH`, then run:

```powershell
$env:SHIFT_GODOT_BIN = 'C:\path\to\Godot_v4.7.2-stable_win64.exe'

Set-Location service/signaling
npm test
Set-Location ../..

powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_ui.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_network.ps1
```

The network fixture starts a local signaling process, one authoritative host, three remote active players, one spectator, and a relaunched client that reclaims its seat.

## Windows export

Install the pinned Godot 4.7.2 Windows export template, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/export_windows.ps1
```

The release archive is written to `build/shift-windows-x64.zip`. See the [release checklist](docs/release-checklist.md) before publishing to itch.io.

## Repository layout

| Path | Purpose |
| --- | --- |
| `src/core/` | Deterministic cards, abilities, match rules, scoring, and controller |
| `src/network/` | WebRTC transport, protocol, host authority, reconnects, and projections |
| `src/view/` | Menus, lobby, match table, phase controls, and results UI |
| `service/signaling/` | Lobby-code and WebRTC signaling service |
| `tests/` | Core, network, integration, and UI test suites |
| `assets/` | Artwork, sound effects, music, and animation resources |
| `scripts/` | Dependency installation, tests, and Windows export automation |
| `docs/` | Design, networking, art requirements, and release documentation |

The model, authoritative controller, network transport, and View are intentionally separated. UI animation and presentation never decide rules or block authoritative phase progress.

## Documentation

- [Game design](docs/superpowers/specs/2026-11-15-shift-card-game-design.md)
- [Functional 2D table and Joker design](docs/superpowers/specs/2026-11-15-functional-2d-table-joker-design.md)
- [Networking architecture](docs/networking.md)
- [Figma component kit and texture handoff](design/shift-figma/README.md)
- [Signaling and Cloudflare TURN setup](service/signaling/README.md)
- [Art, UI, animation, and audio checklist](docs/art-ui-audio-asset-checklist.md)
- [Asset organization](assets/README.md)
- [Windows x64 and itch.io release checklist](docs/release-checklist.md)

## License

This project is available under the [MIT License](LICENSE).
