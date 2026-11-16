# Windows x64 / itch.io release checklist

## Build

- Install the exact Godot 4.7.2 stable Windows x64 export template.
- Set `SHIFT_GODOT_BIN` to the Godot 4.7.2 console executable when Godot is not on `PATH`.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/export_windows.ps1`.
- Confirm the script reports `export_ok` and creates `build/shift-windows-x64.zip`.
- Extract the ZIP into a new folder on a clean Windows x64 machine and launch `Shift.exe`.
- Expect an unsigned-app warning until a signing certificate is added. Allow the Windows Firewall prompt for the host on private networks; do not require public-network access for local testing.

## Multiplayer smoke test

- Configure the intended secure WebSocket signaling URL and STUN URLs for the release environment.
- On machine 1, host a lobby and verify the six-character room code is shown without exposing its IP address.
- On machine 2, join by room code over a different home/mobile network when possible and confirm gameplay uses a direct WebRTC route.
- Repeat with four active players and, separately, up to four spectators.
- Start a match and exercise every phase: start, Main 1, simultaneous hand play, reveal/resolution, Main 2, and turn end.
- Verify a disconnected non-host freezes appropriately, can reconnect inside the grace period, and forfeits after the deadline.
- Verify host loss closes the match for all remaining participants with the distinct host-disconnected result.
- Verify a network that cannot establish the direct route gets the actionable direct-connect failure; the jam build intentionally has no TURN/relay fallback.

## itch.io upload

- Create or update an itch.io project of kind **Downloadable** for Windows.
- Upload `build/shift-windows-x64.zip`, mark it for Windows, and describe it as the Windows x64 build.
- For manual uploads, keep the ZIP structure flat so `Shift.exe`, `Shift.pck`, and the exported WebRTC DLL are together as produced.
- For Butler, run `butler push build/shift-windows-x64.zip <account>/<game>:windows-x64` after installing and authenticating Butler.
- Download the uploaded build through the itch.io app or browser and repeat the clean-machine launch plus a two-machine direct-connect check.
