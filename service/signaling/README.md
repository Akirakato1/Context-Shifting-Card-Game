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

## Health and protocol

- Health: `GET /health`
- Healthy response: `{"ok":true,"service":"shift-signaling","v":1}`
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

On a sleeping free tier, the first connection may hit a cold start and exceed the game's signaling timeout. Show a retryable “signaling unavailable” state rather than treating it as a gameplay loss. A provider restart also removes the in-memory room map; already-connected direct games can continue, but their old lobby codes cannot accept late joins until the host creates or re-registers a room.

## Logs and secrets

The standalone service currently logs its listening address. Use the hosting provider's process and WebSocket logs for restarts, connection failures, and rate-limit investigations. Do not log host tokens, join nonces, SDP bodies, ICE candidates, or reconnect tokens in production.

`npm test` covers protocol validation, authorization, capacity, routing, transient host re-registration, and room cleanup.

## No gameplay relay

This service forwards only WebRTC signaling. It does not provide TURN and never relays gameplay over WebSocket. Some NAT or firewall combinations therefore cannot connect. The game must report `direct_connection_failed`; adding TURN or a gameplay relay is a separate future decision.

