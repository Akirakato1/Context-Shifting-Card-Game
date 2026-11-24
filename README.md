# Zeitklus: The Cycle of Ages

**Zeitklus: The Cycle of Ages** is a competitive card game built with Godot 4 and typed GDScript. Submit a hand using the current context, save cards for later rounds, and use abilities to reshape your hand, affect the table, or disrupt an opponent.

The three contexts advance in a predictable cycle.

```text
Rise (興) → Flourish (盛) → Fall (衰) → Rise
```

The clock tracks the current context. Abilities can change which contexts are active or reverse the cycle. The suits are Mountain, Cloud, and Sea.

## Play the game

- **Tutorial** is an untimed, scripted first-to-three match against Mika. Follow the in-game lessons to learn the controls, build scoring hands, and play every category of ability.
- **Practice** starts an untimed round-win match against three bots.
- **Create Lobby** hosts a match for two to four active players and up to four spectators. Share the six-character code so others can use **Join Lobby**. Each guest player must select **Ready** before the host can start.
- During **Hand Play**, use the live score breakdown to compare submissions. In **Main Phase 2**, review the revealed hands and play any final buffs or nerfs. The score counter pulses and changes color at every 100-point milestone.
- During the Main Phases, each seat shows whether that player is ready. The **Ready** button sits beside the total ready count.
- Open **Abilities** and right-click a playable card to begin. Use the eye on a card to expand its description, or the eye beside **Abilities** to switch the entire tray between concise and expanded views.
- If the match continues and you have more than two abilities at **End**, the ability tray opens. Select exactly two cards to keep and confirm. Everyone can choose at the same time.

## Current scope

- Host-authoritative multiplayer over direct WebRTC, with Cloudflare TURN fallback.
- Simultaneous timed phases, reconnect grace, late player entry, and spectator-safe public state.
- Joker half-cards, separate card and context hand scoring, and score-race or round-win victory modes.
- Illustrated cards and piles, context backgrounds and clock, animated draws, and adjustable hotkeys, audio levels, and animation speed.
- Playtest builds for Windows x64 and native macOS on Apple Silicon and Intel.

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

4. Run the project. Online matches use the hosted signaling service by default.

### Optional local signaling

Start the signaling service in a separate terminal.

```powershell
Set-Location service/signaling
npm install
npm start
```

Set `SHIFT_SIGNALING_URL=ws://127.0.0.1:8080` in the environment that launches Godot.

Permanent Cloudflare TURN credentials belong only in the signaling host's encrypted environment settings. Never place them in `project.godot`, a game export, or source control.

### Optional audio assets

The project can run without the third-party sound packs. To enable card interaction sounds and table ambience in local builds, download the packs from their creators and place the WAV files in these folders.

- Card Game SFX Lite provides card sounds, the table ambience, and the dice shake at score milestones. Place it in `assets/sound_effects/Card Game SFX Lite (Free)/` with the original `wav/oneshots/` and `wav/loops/` subfolders. [Card Game SFX Lite by Willosuna](https://willosuna.itch.io/card-game-sfx-lite)
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

## Playtest exports

Export both platforms from the same game revision for each playtest build.

### Windows x64

Install the pinned Godot 4.7.2 Windows export template, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/export_windows.ps1
```

The release archive is written to `build/zeitklus-windows-x64.zip`. See the [release checklist](docs/release-checklist.md) before publishing to itch.io.

### Native macOS

Use the Godot 4.7.2 macOS export template and the matching macOS WebRTC framework from `webrtc-native` 1.2.2. Export a universal macOS ZIP with **High Res** enabled to `build/zeitklus-macos.zip`. The extracted `.app` runs directly on Apple Silicon and Intel Macs.

### Report a display issue in Wineskin

1. Launch `Zeitklus.exe` in your Wineskin wrapper. In **Settings**, select the mode that looks pixelated, such as **2560 × 1440**.
2. Reproduce the issue. In the same session, click **Settings → Copy display diagnostics**.
3. Share the pasted report and a screenshot of the affected screen.

The game starts a fresh `display-diagnostics.log` in its data folder each launch. The report includes the selected resolution, the window and screen sizes the game sees through Wine, Godot’s render size, and the reported DPI and scale. It stays local until you share it.

### Report a disconnect

Copy the lines starting with `[network]` from `logs/godot.log` soon after the disconnect. If you relaunched the game, check the newest dated log in that folder. Logs are kept under `%APPDATA%/Godot/app_userdata/Shift` on Windows and `~/Library/Application Support/Godot/app_userdata/Shift` on native macOS. If possible, include both the host and disconnected player’s logs and the approximate time. The network entries omit player names, room codes, and credentials.

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
