# Shift signaling service

This service creates temporary lobby codes and routes WebRTC setup messages. It does not host gameplay or store match state, cards, hands, scores, deck order, or RNG state. After WebRTC connects, gameplay travels directly between each remote participant and the player-host.

## Run locally

Requirements:

- Node.js 22.11 or newer
- The dependencies locked in `package-lock.json`

From this directory:

```powershell
npm install
npm test
$env:PORT = '8080'
npm start
```

The default listener binds to `0.0.0.0`. `PORT` defaults to `8080`. In production, place the service behind a provider that terminates HTTPS/WSS and configure the game with its public `wss://` URL.

The service reads configuration from its process environment; it does not load `.env` files itself. [`.env.example`](.env.example) is a names-only deployment template. Set real values through the hosting provider's encrypted environment/secret settings, never by committing a populated file.

## Cloudflare TURN setup

1. In the Cloudflare dashboard, open **Realtime** → **TURN**, create a TURN key, and securely record its Token ID and API token. Cloudflare's [credential guide](https://developers.cloudflare.com/realtime/turn/generate-credentials/) explains why this permanent key stays on the backend and must be exchanged for short-lived client credentials.
2. Configure the deployed signaling service with:

   ```text
   CLOUDFLARE_TURN_KEY_ID=<TURN Token ID>
   CLOUDFLARE_TURN_API_TOKEN=<TURN API token>
   TURN_CREDENTIAL_TTL_SECONDS=14400
   ```

   The TTL defaults to four hours and is bounded to 60–172800 seconds. Do not put either permanent value in `project.godot`, the Godot export, itch.io metadata, client logs, or chat.
3. Restart/redeploy the signaling service and request `GET /health`. Confirm `relay.provider` is `cloudflare` and `relay.configured` is `true`. This reports configuration presence only and intentionally exposes no key identifier, token, or temporary credential.
4. Test one exported client as host and another client on a separate network. Then repeat behind a network/firewall that blocks direct traversal while allowing TURN/TLS on TCP 443, and confirm the lobby still connects.

Each successful host registration and approved join receives a separate short-lived ICE credential over the existing authorized WebSocket. WebRTC still prefers a viable direct host↔participant candidate; Cloudflare TURN forwards the encrypted WebRTC data channel only when direct traversal is unavailable. The relay never becomes game authority and the signaling service never carries gameplay messages.

If the permanent variables are absent, Cloudflare times out, rejects a request, or returns malformed data, lobby creation and joining continue with the checked-in public STUN fallback and `relay_available: false`. Those users may still connect directly, but restrictive networks can fail with `direct_connection_failed`.

## Health and protocol

- Health: `GET /health`
- Healthy response without TURN configuration: `{"ok":true,"service":"shift-signaling","v":1,"relay":{"provider":"none","configured":false}}`
- Healthy response with Cloudflare variables present: `relay` becomes `{"provider":"cloudflare","configured":true}`; the endpoint does not contact Cloudflare or reveal secrets.
- Signaling protocol version: `1`
- Maximum client message: 64 KiB
- Default rate limit: 120 messages per socket per 10 seconds
- Lobby codes: six case-insensitive, unambiguous uppercase characters

The host must approve a join nonce before the service routes offers, answers, or ICE candidates. A code alone never grants a seat.

## Lobby lifetime and capacity

- The host counts as one of four active-player seats.
- A lobby supports up to three remote active players and four spectators.
- Pending joins reserve capacity.
- An explicit host close invalidates the code immediately.
- A dropped host signaling socket leaves the code detached for 30 seconds so the same host token can re-register it. Expiry invalidates the code and notifies pending peers.
- Established WebRTC gameplay can continue during a signaling outage; signaling is still needed for late joins and new reconnect channels.

Room records are in memory only. Restarting or sleeping the service invalidates every current code.

## Hosting notes

A free or hobby WebSocket service is suitable for jam testing, but it is not guaranteed to support a production audience of thousands. Check the provider's limits for concurrent WebSocket connections, idle timeouts, memory, outbound traffic, and sleeping instances.

TURN bandwidth is separate from the tiny signaling payload. Cloudflare's [current TURN pricing and free-tier FAQ](https://developers.cloudflare.com/realtime/turn/faq/) must be checked before release; enable Realtime usage monitoring and a billing alert even when expected card-game traffic is small. A hobby signaling tier does not make relayed bandwidth unlimited.

On a sleeping free tier, the first connection may hit a cold start and exceed the game's signaling timeout. Show a retryable “signaling unavailable” state rather than treating it as a gameplay loss. A provider restart also removes the in-memory room map; already-connected direct games can continue, but their old lobby codes cannot accept late joins until the host creates or re-registers a room.

## Logs and secrets

The standalone service currently logs its listening address. Use the hosting provider's process and WebSocket logs for restarts, connection failures, and rate-limit investigations. Do not log host tokens, join nonces, SDP bodies, ICE candidates, or reconnect tokens in production.

`npm test` covers protocol validation, authorization, capacity, routing, transient host re-registration, per-participant ICE issuance, provider fallback, and room cleanup without contacting Cloudflare.

## TURN is not a gameplay server

The service forwards only WebRTC setup messages and short-lived ICE configuration. It never relays gameplay over WebSocket and stores no canonical match state. When TURN is selected by ICE, Cloudflare forwards the encrypted player↔host WebRTC transport; authority, validation, hidden information, and simulation remain on the player-host.

