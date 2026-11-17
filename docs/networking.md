# Direct multiplayer networking

Shift uses a host-authoritative star topology. One player's Godot process owns the controller, RNG, decks, hidden information, scoring, and timers. Each other player or spectator opens one reliable, ordered WebRTC data channel directly to that host.

```text
remote player ─┐
remote player ─┼── WebRTC game-v1 ── direct when possible ── player-host
remote player ─┤                    └─ Cloudflare TURN fallback ─┘
spectator(s)  ─┘

all participants ── WSS setup only ── signaling service
```

Remote participants do not connect to each other. There is no host migration: losing the host's direct channel ends the client session.

## Configuration

The application coordinator supplies:

- Signaling URL: a local `ws://127.0.0.1:<port>` URL for development or the deployed `wss://` URL.
- ICE server dictionaries: passed to `WebRTCPeerTransport` with `urls` plus paired `username`/`credential` fields for TURN. Empty is valid for loopback tests.
- Protocol version: game and signaling envelopes currently use integer version `1`.
- Direct-connect timeout: 15 seconds by default.
- Heartbeat interval/timeout: 2 seconds / 6 seconds by default.
- Reconnect grace: locked in the lobby configuration; the current integration fixture uses 30 seconds.

The native dependency is the pinned official `godotengine/webrtc-native` 1.2.2 GDExtension. Windows x64 is the first supported export target.

## Lobby and connection flow

1. The host opens a signaling socket and receives a six-character code, a private host token, and a short-lived ICE configuration. Without relay configuration this is the public STUN fallback.
2. A joiner submits the code and requests `active` or `spectator`.
3. The host approves the server-issued join nonce after capacity and role checks. Only then does the joiner receive its own short-lived ICE configuration.
4. The signaling service routes the offer, answer, and ICE candidates.
5. ICE selects a direct candidate when possible and a Cloudflare TURN candidate when direct traversal is unavailable.
6. A negotiated binary `game-v1` channel opens with channel ID `1`, reliable ordered delivery, and protocol label `shift-game-v1`.
7. The host admits the peer through `HostNetworkSession` and sends the recipient-safe snapshot.
8. Gameplay commands and projected events use the WebRTC channel; the signaling service is not in this path. TURN forwards the encrypted channel and is not authoritative.

The host counts toward the four-player maximum, leaving three remote active seats. Four additional spectator slots are available. A player who joins during a match is pending until the next Start phase; spectators receive the current public snapshot immediately.

## Authority, ordering, and privacy

Clients submit commands but never author snapshots or event batches. The host validates player identity, phase legality, payload shape, command deduplication, and reconnect credentials before mutating the controller.

Events are projected per recipient:

- Public events reach active players, pending players, and spectators.
- Owner-private events reach only that active player.
- Host-only or unknown audiences never leave the host.
- Spectator snapshots contain no `private_*` data.

Per-recipient sequence numbers detect gaps. Small out-of-order batches buffer within a fixed bound; larger gaps request a fresh snapshot. Blocked outbound queues are capped rather than growing without limit.

## Heartbeats, disconnects, and reconnects

The host sends heartbeats and tracks the last valid peer message. A missed timeout removes the direct peer and enters the controller's disconnect grace exactly once. The whole match freezes while any active player's grace is unresolved; overlapping disconnects keep independent deadlines.

An active player's owner snapshot contains a random reconnect token. The client stores an account-free record in `user://shift-reconnect.json` containing the room code, player ID, token, and wall-clock expiry. Heartbeats refresh that expiry through the host detection window plus lobby reconnect grace.

After relaunch, the client:

1. joins the lobby to create a new direct channel;
2. sends a `reconnect` command with the stored token before normal peer registration;
3. receives an authoritative owner snapshot if the token and deadline are valid.

Successful reclaim rotates the token. The host remains authoritative, so an expired local record or stolen/incorrect token cannot claim a seat. Grace expiry causes an authoritative forfeit, cleanup events, and last-player-standing victory when applicable.

A transient signaling outage does not close established game channels. The host-side coordinator should call `SignalingClient.reconnect()` with the retained code and host token so late joins remain possible. An explicit room close or 30 seconds without host signaling re-registration invalidates the code.

## Failure behavior and relay fallback

- ICE or channel setup that misses the bound reports `direct_connection_failed`.
- Host channel loss reports `host_lost`; clients do not elect or migrate to a new host.
- Malformed or unauthorized envelopes are rejected and may disconnect the sender.
- There is no WebSocket gameplay relay.

Cloudflare Realtime TURN supplies the relay fallback. The permanent TURN key exists only in signaling-service environment secrets; each accepted participant receives expiring credentials. If Cloudflare is unconfigured or credential issuance fails, signaling returns the public STUN fallback and the lobby still works for direct-capable networks. If both direct traversal and the available relay route fail, the session reports `direct_connection_failed`.

WebRTC data-channel encryption remains end-to-end between the participant and player-host while TURN forwards packets. TURN availability improves reachability but adds provider bandwidth cost and cannot provide host migration or protect a match from the host process disappearing.

## Verification and logs

Set `SHIFT_GODOT_BIN` to Godot 4.7.2 or pass `-GodotBin`, then run:

```powershell
Set-Location service/signaling
npm test
Set-Location ../..
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_network.ps1
```

`scripts/test_network.ps1` enforces a two-minute total bound and starts:

- one loopback signaling process;
- one headless authoritative host;
- three headless remote active players;
- one headless spectator;
- one relaunched client process for seat reclaim.

It verifies code-based joining, direct command/result flow, spectator-safe public projection, disconnect freeze, token reconnect, and controlled zero-status shutdown. The automated fixture is self-contained and deliberately does not request live Cloudflare credentials. Each process receives a separate stdout/stderr log under the printed temporary run directory. The host log includes `DIRECT_GAMEPLAY_RECEIVED ... kind=command`, proving the gameplay envelope reached Godot over WebRTC rather than passing through the signaling service.

Before a public release, also run two exported clients on separate real networks. Repeat with direct traversal blocked but TURN/TLS on TCP 443 allowed, confirm the game connects, and confirm Cloudflare Realtime analytics records relay traffic. Review the [signaling deployment instructions](../service/signaling/README.md#cloudflare-turn-setup) and enable a billing alert.

For deployed signaling configuration and free-tier cautions, see [the signaling service README](../service/signaling/README.md).

