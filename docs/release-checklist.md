# Windows x64 / itch.io release checklist

## Build

- Install the exact Godot 4.7.2 stable Windows x64 export template.
- Prefer `scripts/install_windows_export_template.ps1`; it verifies the pinned official template SHA-256 before installing it.
- Set `SHIFT_GODOT_BIN` to the Godot 4.7.2 console executable when Godot is not on `PATH`.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/export_windows.ps1`.
- Confirm the script reports `export_ok` and creates `build/shift-windows-x64.zip`.
- Extract the ZIP into a new folder on a clean Windows x64 machine and launch `Shift.exe`.
- Expect an unsigned-app warning until a signing certificate is added. Allow the Windows Firewall prompt for the host on private networks; do not require public-network access for local testing.

## Multiplayer smoke test

- Set `shift/network/signaling_url` in `project.godot` before export. For temporary local testing, `SHIFT_SIGNALING_URL` overrides the project URL at runtime.
- Configure the intended secure WebSocket signaling URL for the release environment; the checked-in URL points to a local signaling service for development only. Keep the checked-in ICE configuration as a public STUN fallback and never embed permanent TURN credentials in the project or export.
- Create a Cloudflare Realtime TURN key. Store `CLOUDFLARE_TURN_KEY_ID` and `CLOUDFLARE_TURN_API_TOKEN` only in the signaling host's encrypted secret settings; set `TURN_CREDENTIAL_TTL_SECONDS=14400` unless a different bounded lifetime is intentional.
- Request signaling `GET /health`. Confirm `relay.provider` is `cloudflare`, `relay.configured` is `true`, and the response contains no key ID, API token, temporary username, or temporary credential.
- On machine 1, host a lobby and verify the six-character room code is shown without exposing its IP address.
- On machine 2, join by room code over a different home/mobile network when possible and confirm gameplay uses a direct WebRTC route.
- Block direct traversal on a test network while allowing TURN/TLS on TCP 443; repeat the join and confirm gameplay connects through Cloudflare TURN.
- Confirm Cloudflare Realtime analytics records the relay smoke test, review current free-tier/pricing limits, and enable usage plus billing alerts before publishing.
- Repeat with four active players and, separately, up to four spectators.
- Start a match and exercise every phase: start, Main 1, simultaneous hand play, reveal/resolution, Main 2, and turn end.
- Verify a disconnected non-host freezes appropriately, can reconnect inside the grace period, and forfeits after the deadline.
- Verify host loss closes the match for all remaining participants with the distinct host-disconnected result.
- Temporarily remove/disable the Cloudflare secrets and verify signaling health reports relay unconfigured while direct-capable clients can still use STUN. On a restrictive network where neither direct nor relay is available, verify the actionable `direct_connection_failed` result.

## itch.io upload

- Create or update an itch.io project of kind **Downloadable** for Windows.
- Upload `build/shift-windows-x64.zip`, mark it for Windows, and describe it as the Windows x64 build.
- For manual uploads, keep the ZIP structure flat so `Shift.exe`, `Shift.pck`, and the exported WebRTC DLL are together as produced.
- For Butler, run `butler push build/shift-windows-x64.zip <account>/<game>:windows-x64` after installing and authenticating Butler.
- Download the uploaded build through the itch.io app or browser and repeat the clean-machine launch plus a two-machine direct-connect check.
