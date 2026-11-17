# Cloudflare TURN fallback design

**Date:** 2026-11-17
**Status:** Awaiting final approval
**Selected approach:** Cloudflare Realtime TURN with server-issued short-lived credentials

## Intent

Keep Shift's player-hosted, host-authoritative WebRTC architecture while allowing players behind restrictive NATs or firewalls to connect through a TURN relay. Direct peer-to-host transport remains preferred. TURN is an ICE fallback, not a replacement game server and not a gameplay WebSocket relay.

## Goals

- Preserve direct WebRTC whenever a direct candidate pair works.
- Add TURN/UDP, TURN/TCP, and TURN/TLS candidates for networks where direct traversal fails.
- Keep the permanent Cloudflare TURN key and API token exclusively on the signaling service.
- Give each accepted participant short-lived credentials suitable for one play session.
- Continue in STUN/direct-only mode when the TURN provider is unavailable.
- Preserve the current lobby-code, host approval, privacy, reconnect, and spectator flows.
- Test the provider boundary without requiring live Cloudflare credentials in the normal test suite.

## Non-goals

- No dedicated authoritative game server.
- No host migration.
- No general WebSocket gameplay relay.
- No Cloudflare SFU or RealtimeKit integration.
- No permanent TURN credentials embedded in `project.godot` or an exported game.
- No forced relay mode in normal play; ICE chooses the best viable path.

## Approaches considered

### 1. Cloudflare managed TURN — selected

Cloudflare operates the relay network, supports UDP/TCP/TLS endpoints, and generates short-lived ICE credentials through a server-side API. This minimizes game-jam operations and currently provides a large free usage allowance suitable for a low-bandwidth card game.

### 2. Self-hosted coturn

This offers full control and open-source infrastructure but requires a public VPS, a large relay port range, TLS certificates, firewall configuration, monitoring, upgrades, abuse protection, and bandwidth planning. It is unnecessary operational work for the jam build.

### 3. Twilio Network Traversal Service

This is a credible managed alternative but has materially higher usage pricing than Cloudflare for the expected deployment. The code will keep the ICE-server boundary provider-neutral so another provider can be adopted later.

## Runtime connection flow

```text
Godot host/client ── WSS ── Shift signaling service ── HTTPS ── Cloudflare credential API
       │                         │
       └──── WebRTC ICE ─────────┴──── direct path preferred
                         └──────────── TURN relay used only if needed
```

1. The signaling service starts with Cloudflare TURN configuration in environment variables.
2. A host opens a room. The service obtains a short-lived credential and includes a sanitized `ice_servers` array in `room_created`.
3. A joining player or spectator waits for normal host approval. The service obtains that participant's credential and includes `ice_servers` in `join_approved`.
4. `SignalingClient` validates and stores the ICE server dictionaries before emitting the room-created or join-approved signal.
5. `WebRTCPeerTransport` receives complete ICE server dictionaries rather than converting them to strings.
6. Each `WebRTCPeerConnection` is initialized with STUN plus Cloudflare TURN URLs, username, and credential.
7. ICE normally selects a direct candidate. If direct traversal is impossible, ICE selects a relayed candidate without changing the game protocol or host authority.
8. Host signaling re-registration and player seat reconnection obtain fresh short-lived credentials.

The default credential lifetime will be four hours, configurable by environment variable and bounded to Cloudflare's supported range. A credential is generated per signaling participant rather than shared among an entire room.

## Signaling service changes

Add a provider-neutral credential provider with two implementations:

- Cloudflare provider: calls the credential-generation API using server-only secrets.
- Static fallback provider: returns the checked-in STUN configuration and reports relay unavailable.

Environment variables:

```text
CLOUDFLARE_TURN_KEY_ID
CLOUDFLARE_TURN_API_TOKEN
TURN_CREDENTIAL_TTL_SECONDS=14400
```

The service must:

- never send or log the permanent API token;
- validate the Cloudflare response before forwarding it;
- forward only `urls`, `username`, and `credential` fields;
- cap URL and string counts/lengths;
- preserve existing WebSocket message-size and rate limits;
- fall back to STUN-only when credentials cannot be generated;
- expose relay readiness in `/health` without exposing secrets;
- allow dependency injection so tests use a fake provider and never contact Cloudflare.

`host_room` and `approve_join` handling become asynchronous while preserving authorization and join-capacity checks. A provider timeout prevents a stalled Cloudflare request from blocking a signaling socket indefinitely.

## Godot changes

`WebRTCPeerTransport` will store a normalized array of complete ICE server dictionaries. Valid entries require a non-empty `urls` string/array; `username` and `credential` must either both be strings or both be absent. Unknown fields are removed.

`SignalingClient` will validate optional `ice_servers` and `relay_available` fields on `room_created` and `join_approved`. It updates transport configuration before the transport creates an offer or accepts a peer.

The checked-in project setting remains a STUN-only development fallback. No Cloudflare credential or API secret is stored in the project or export.

If TURN credential delivery fails, the player may still connect directly. A direct connection failure remains actionable, but diagnostics will distinguish `relay_unavailable` from a failure where relay credentials were supplied.

## Security and privacy

- Permanent Cloudflare credentials live only in deployment environment secrets.
- Exported clients receive temporary TURN usernames/passwords, which is expected for WebRTC TURN.
- Credentials are issued only after the socket has passed the corresponding room flow; there is no public unauthenticated credential HTTP endpoint.
- Credential responses are never written to logs.
- The existing host-authoritative validation and recipient-specific snapshots are unchanged.
- WebRTC data-channel encryption remains in effect when packets traverse TURN; TURN forwards the encrypted transport rather than becoming game authority.
- Rate limits and short expiry limit abuse exposure; provider usage monitoring and a billing alert are operational requirements.

## Failure behavior

- Provider not configured: signaling operates normally with STUN/direct-only ICE.
- Provider timeout or invalid response: return STUN/direct-only ICE and `relay_available: false`; do not prevent room creation or joining.
- TURN candidate fails but direct works: play continues directly.
- Direct candidates fail but TURN works: play continues over the relayed WebRTC channel.
- All candidates fail: retain `direct_connection_failed`, with UI wording explaining that neither direct nor relay could establish a route when relay was available.
- Existing established data channels are unaffected by a later credential-provider outage.

## Testing

### Signaling service

- Cloudflare request URL, headers, TTL, timeout, and response normalization.
- Permanent token never appears in a client message or health response.
- Host and approved joiner each receive their own ICE credentials.
- Host reconnect and player reconnect receive fresh credentials.
- Provider failure and malformed response fall back to STUN-only without blocking lobby flow.
- Existing authorization, capacity, routing, payload, and rate-limit tests remain green.

### Godot

- Full ICE dictionaries survive signaling validation and transport normalization.
- TURN username/credential reach `WebRTCPeerConnection.initialize()` unchanged.
- The current dictionary-to-string STUN bug is covered by a regression test.
- STUN-only and empty-server configurations remain supported for local tests.
- Existing direct WebRTC, privacy, reconnect, and multi-process tests remain green.

### Deployment smoke test

- Deploy the signaling service with Cloudflare secrets.
- Verify `/health` reports relay configured without exposing identifiers or tokens.
- Test exported clients on separate real networks.
- Test at least one restrictive network or firewall scenario where a relayed route is required.
- Confirm Cloudflare usage analytics and billing alerts before public release.

## External provisioning boundary

Implementation, automated tests, service configuration support, and deployment documentation can be completed in the repository without live secrets. Activating the real relay requires the user-owned Cloudflare account to create a TURN key and securely configure its key ID/API token on the deployed signaling host. Account terms, billing authorization, and secret creation remain user-authorized actions.

## Acceptance criteria

- Normal direct connections still work and remain preferred.
- A participant can connect through Cloudflare TURN when direct traversal is unavailable.
- No permanent TURN secret exists in the repository, game export, logs, or client-visible messages.
- Cloudflare failure degrades to the current STUN-only behavior rather than breaking lobby creation.
- All current tests pass, new TURN tests pass, and the multi-process network fixture remains deterministic without external Cloudflare access.
