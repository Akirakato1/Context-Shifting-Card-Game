# Direct P2P Networking and Lobby Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the authoritative Godot controller to 2–4 players and up to four spectators through join-code signaling and direct WebRTC data channels, including snapshots, late joins, reconnect grace, and clean failure without relay fallback.

**Architecture:** A tiny stateless-in-practice Node signaling service maps short codes to live host/joiner signaling sockets only long enough to exchange WebRTC offers, answers, and ICE candidates. Godot uses one reliable ordered WebRTC data channel from each remote participant directly to the host; the host transports validated commands and per-recipient event/snapshot projections from the core controller.

**Tech Stack:** Godot 4.7.2 stable, official `godotengine/webrtc-native` v1.2.2 GDExtension, GDScript, WebRTC/STUN, WSS signaling, Node.js >=22.11.0, ECMAScript modules, `ws` v8, built-in `node:test`.

**Spec:** `docs/superpowers/specs/2026-11-15-shift-card-game-design.md`

## Global Constraints

- Complete `docs/superpowers/plans/2026-11-15-core-rules-controller.md` first.
- Gameplay traffic must be direct peer-to-host after signaling; do not add TURN or a gameplay relay in this plan.
- The signaling service stores no canonical match state, cards, scores, or private hands.
- Keep the host signaling control socket registered for the room so late joins and reconnects remain possible; established gameplay never traverses it.
- Host controller remains the only rules authority and RNG owner.
- Use reliable, ordered data channels; card-game traffic does not need unreliable position updates.
- Never broadcast one player's private snapshot/event to another player or spectator.
- Lobby codes are temporary, case-insensitive, and invalidated when the host closes or disconnects.
- First required native target is Windows x64.
- Every task ends with both relevant test suites passing and a user-authored commit.

## Review Focus

- Malformed, oversized, or unknown-version signaling/game envelopes must be rejected without crashing or forwarding them; Tasks 1 and 2 pin this.
- A guessed lobby code must not grant a seat without a host-issued join nonce and capacity check; Task 1 pins this.
- Duplicate or replayed game commands after reconnect must produce at most one authoritative mutation; Task 5 pins this.
- Recipient routing must make it impossible for spectators/opponents to receive owner-private events or snapshots; Task 5 pins this.
- Direct-connect failure, signaling loss, host loss, and overlapping reconnects must end in bounded, visible states rather than hanging; Tasks 4 and 7 pin this.

---

## Planned File Structure

```text
addons/webrtc/                         # extracted official v1.2.2 archive structure
service/signaling/
  package.json
  package-lock.json
  src/protocol.js
  src/room_registry.js
  src/server.js
  test/*.test.js
src/network/
  game_protocol.gd
  signaling_client.gd
  peer_transport.gd
  webrtc_peer_transport.gd
  host_network_session.gd
  client_network_session.gd
  reconnect_store.gd
tests/network/
  fake_peer_transport.gd
  *_test.gd
scripts/
  install_webrtc.ps1
  test_network.ps1
```

### Task 1: Join-Code Signaling Service

**Files:**
- Create: `service/signaling/package.json`
- Create: `service/signaling/src/protocol.js`
- Create: `service/signaling/src/room_registry.js`
- Create: `service/signaling/src/server.js`
- Test: `service/signaling/test/room_registry.test.js`
- Test: `service/signaling/test/server.test.js`

**Interfaces:**
- Consumes: HTTPS/WSS termination supplied by hosting provider or local HTTP in tests.
- Produces: `RoomRegistry.createHost(socket) -> { code, hostToken }`; `requestJoin(code, role, socket) -> { joinNonce }`; routed `offer`, `answer`, and `ice_candidate` messages; `room_closed`; HTTP `/health`.

- [ ] **Step 1: Initialize the service and write failing registry tests**

Use ESM and Node's built-in test runner. Tests must assert six-character unambiguous codes, case-insensitive lookup, active-player cap four, spectator cap four, pending joins counting toward capacity, host close invalidation, and no game-state fields in room records.

- [ ] **Step 2: Write failing protocol/security tests**

Reject unknown message types/versions, payloads over 64 KiB, malformed JSON, joins without a valid role, signaling sent with the wrong join nonce, and a non-host attempting to close a room. Add bounded per-socket message-rate checks with a deterministic clock fixture.

- [ ] **Step 3: Run tests and verify failure**

Run: `npm --prefix service/signaling test`

Expected: FAIL because registry/server modules do not exist.

- [ ] **Step 4: Implement protocol validation and ephemeral room registry**

Protocol version is integer `1`. Code records contain only sockets/tokens/role/capacity/last-activity metadata.

- [ ] **Step 5: Implement HTTP health and WebSocket signaling server**

On host socket close, send `room_closed` to pending peers and delete the room. Do not proxy gameplay data.

- [ ] **Step 6: Run tests**

Expected: all signaling tests PASS.

- [ ] **Step 7: Commit**

```bash
git add service/signaling
git commit -m "feat: add lobby signaling service"
```

### Task 2: Versioned Game Envelope and Cross-Runtime Fixtures

**Files:**
- Create: `src/network/game_protocol.gd`
- Create: `service/signaling/test/fixtures/game_envelopes.json`
- Test: `tests/network/game_protocol_test.gd`

**Interfaces:**
- Consumes: core `GameCommand`, `DomainEvent`, and projected snapshot dictionaries.
- Produces: envelope `{v, kind, message_id, match_id, sender_id, payload}`; `GameProtocol.encode(envelope: Dictionary) -> PackedByteArray`; `decode(bytes: PackedByteArray) -> ProtocolResult`; kinds `command`, `command_result`, `event_batch`, `snapshot`, `heartbeat`, `heartbeat_ack`, `disconnect_notice`.

- [ ] **Step 1: Write failing protocol fixture tests**

Round-trip Unicode names, empty payloads, maximum legal payload, all message kinds, and stable key/value types. Reject unknown version/kind, missing IDs, invalid UTF-8/JSON, and payload above 256 KiB.

- [ ] **Step 2: Run the Godot test and verify failure**

Run: `scripts/test.ps1 tests/network/game_protocol_test.gd`

- [ ] **Step 3: Implement encode/decode and stable error codes**

JSON is acceptable for the jam protocol. Do not serialize Godot Objects or Callables.

- [ ] **Step 4: Run both Godot and Node fixture tests**

The Node test parses the same fixture file to catch accidental nonstandard JSON assumptions.

- [ ] **Step 5: Commit**

```bash
git add src/network/game_protocol.gd tests/network service/signaling/test
git commit -m "feat: define network message protocol"
```

### Task 3: Pin and Verify the Native WebRTC Dependency

**Files:**
- Create: `scripts/install_webrtc.ps1`
- Create: `tests/network/webrtc_plugin_smoke_test.gd`
- Modify: `.gitignore`
- Create/Modify: official archive files under `addons/webrtc/`

**Interfaces:**
- Consumes: official `godot-extension-webrtc_native.zip` for v1.2.2.
- Produces: reproducible local installation; registered `WebRTCPeerConnection` implementation in Windows headless/editor runs.

- [ ] **Step 1: Write a failing plugin smoke test**

Instantiate `WebRTCPeerConnection`, call `initialize({"iceServers": []})`, and assert `OK` rather than the unavailable-native implementation error.

- [ ] **Step 2: Run and verify failure before installation**

- [ ] **Step 3: Implement the pinned installer**

Download only from the official GitHub v1.2.2 release, verify a pinned SHA-256 recorded in the script, and extract with the archive's directory structure into the project. Do not download from an unversioned `latest` URL.

- [ ] **Step 4: Run the smoke test and verify pass**

- [ ] **Step 5: Commit dependency metadata and required plugin files**

```bash
git add scripts/install_webrtc.ps1 addons .gitignore tests/network/webrtc_plugin_smoke_test.gd
git commit -m "build: pin native WebRTC extension"
```

### Task 4: Signaling Client and Direct Star Transport

**Files:**
- Create: `src/network/signaling_client.gd`
- Create: `src/network/peer_transport.gd`
- Create: `src/network/webrtc_peer_transport.gd`
- Test: `tests/network/signaling_client_test.gd`
- Test: `tests/network/webrtc_transport_test.gd`

**Interfaces:**
- Consumes: signaling WSS URL, STUN URL list, room code, role, join nonce.
- Produces: abstract `PeerTransport` signals `peer_connected(peer_id)`, `peer_disconnected(peer_id, reason)`, `message_received(peer_id, bytes)`; methods `host_room()`, `join_room(code, role)`, `send(peer_id, bytes)`, `close_peer(peer_id)`, `poll()`.

- [ ] **Step 1: Write failing signaling state-machine tests with a fake socket**

Cover host code receipt, join request, offer/answer/ICE routing, code rejection, room full, host close, signaling timeout, and reconnect signaling.

- [ ] **Step 2: Write a local direct-transport test**

Create host and client peer connections on loopback with no TURN, open one reliable ordered `game-v1` channel, exchange two payloads, and close cleanly. Assert remotes connect only to host, never to each other.

- [ ] **Step 3: Run targeted tests and verify failure**

- [ ] **Step 4: Implement signaling client and abstract transport**

- [ ] **Step 5: Implement one `WebRTCPeerConnection`/data-channel pair per remote participant**

The host manages up to seven remotes (three other active players plus four spectators). Include bounded connect timeout and a distinct `direct_connection_failed` result when ICE cannot connect.

- [ ] **Step 6: Run all tests**

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add src/network tests/network
git commit -m "feat: connect peers through WebRTC"
```

### Task 5: Host Command Replication and Recipient-Safe Events

**Files:**
- Create: `src/network/host_network_session.gd`
- Create: `src/network/client_network_session.gd`
- Create: `tests/network/fake_peer_transport.gd`
- Test: `tests/network/network_session_test.gd`

**Interfaces:**
- Consumes: `PeerTransport`, `GameProtocol`, `MatchController`, `SnapshotProjector`.
- Produces: host command intake/deduplication; `command_result` to sender; public/owner/spectator event routing; client-side ordered event stream; snapshot request/apply hooks.

- [ ] **Step 1: Write failing host-authority tests with fake transport**

Assert clients cannot send events/snapshots, invalid commands do not broadcast, valid commands mutate once, duplicated `message_id` after reconnect returns cached result without mutation, and commands claiming another player ID reject.

- [ ] **Step 2: Write recipient-leak routing tests**

Send one event batch containing public, owner-private, attacker-private, and host-only data. Assert byte-decoded outbound envelopes contain exactly the permitted projection for each active player and spectator.

- [ ] **Step 3: Write ordering/backpressure tests**

Assert per-peer sequence numbers are monotonic, out-of-order client events buffer within a small bound, gaps trigger snapshot resync, and a peer exceeding queue/payload limits disconnects with a stable reason.

- [ ] **Step 4: Implement host and client sessions**

Clients update Views from authoritative events; they never execute commands locally as authority.

- [ ] **Step 5: Run all tests**

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add src/network tests/network
git commit -m "feat: replicate authoritative match events"
```

### Task 6: Lobby Roles, Late Join, and Spectator Synchronization

**Files:**
- Modify: `src/network/host_network_session.gd`
- Modify: `src/network/client_network_session.gd`
- Test: `tests/network/lobby_sync_test.gd`

**Interfaces:**
- Consumes: signaling role/capacity result, core join/pending/spectator commands, snapshot projector.
- Produces: seat claims, pending-player status, spectator public snapshot, next-Start activation, lobby settings snapshot.

- [ ] **Step 1: Write failing role/capacity tests**

Assert active join rejected at four seats, spectator rejected at four spectators, role cannot change by client assertion, and pending player receives public-only state until Start activation.

- [ ] **Step 2: Write late-player snapshot tests**

At activation, assert owner receives default private hand and three abilities while all other recipients receive only public join events. Lobby settings are locked and identical on all clients.

- [ ] **Step 3: Write spectator tests**

Assert spectator can join mid-phase, receives current public snapshot plus subsequent sequence, and is never included in readiness or private sends.

- [ ] **Step 4: Implement lobby role and synchronization paths**

- [ ] **Step 5: Run all suites**

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add src/network tests/network/lobby_sync_test.gd
git commit -m "feat: sync late players and spectators"
```

### Task 7: Heartbeats, Relaunch Reconnect, Forfeit, and Host Loss

**Files:**
- Create: `src/network/reconnect_store.gd`
- Modify: `src/network/host_network_session.gd`
- Modify: `src/network/client_network_session.gd`
- Test: `tests/network/reconnect_session_test.gd`

**Interfaces:**
- Consumes: heartbeat timestamps, reconnect grace from locked config, local `user://` storage, signaling rejoin.
- Produces: random reconnect token, persisted `{room_code, player_id, token, expires_at}`, full gameplay freeze, private snapshot resume, forfeit command, host-loss result.

- [ ] **Step 1: Write failing liveness tests**

Use a fake clock. Assert missed heartbeat enters disconnect grace exactly once, freezes commands/timers, overlapping disconnects keep freeze active, and transient signaling loss after established WebRTC does not itself end gameplay. Assert the host can re-register the same room code with its host token after signaling reconnect so late joins remain available.

- [ ] **Step 2: Write relaunch-token tests**

Persist, reload, verify, expire, and delete the account-free reconnect record. Assert wrong token cannot claim the seat and successful reclaim rotates the token.

- [ ] **Step 3: Write forfeit/host-loss tests**

Grace expiry submits authoritative forfeit, distributes cleanup projections, resumes only after all unresolved disconnects finish, and awards last-player-standing victory. Host channel loss ends the match and never attempts migration.

- [ ] **Step 4: Write bounded direct-connect failure tests**

When ICE does not reach connected state before timeout, emit a clear `direct_connection_failed` outcome; do not silently attempt TURN or WebSocket relay.

- [ ] **Step 5: Implement heartbeat, reconnect, forfeit, and host-loss paths**

- [ ] **Step 6: Run all suites**

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add src/network tests/network/reconnect_session_test.gd
git commit -m "feat: handle reconnects and network loss"
```

### Task 8: Multi-Process Network Integration and Operations Documentation

**Files:**
- Create: `tests/network/fixtures/host_runner.gd`
- Create: `tests/network/fixtures/client_runner.gd`
- Create: `scripts/test_network.ps1`
- Create: `service/signaling/README.md`
- Create: `docs/networking.md`

**Interfaces:**
- Consumes: built signaling service, pinned plugin, completed network sessions.
- Produces: repeatable local host + three players + spectator integration run; deployment/configuration instructions.

- [ ] **Step 1: Add a failing multi-process scenario**

The script starts signaling on a random loopback port, launches one headless host, three headless clients, and one spectator, then asserts join code flow, a command/event round trip, spectator projection, one reconnect, and clean shutdown.

- [ ] **Step 2: Implement fixture runners and orchestration**

Capture each process log separately and enforce a two-minute total timeout. Any process nonzero exit fails the script.

- [ ] **Step 3: Document configuration**

Document WSS URL, STUN URL list, protocol version, health endpoint, free-tier cold start expectations, code lifetime, capacity, rate limits, logs, and the explicit absence of TURN fallback.

- [ ] **Step 4: Run all verification**

```powershell
npm --prefix service/signaling test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_network.ps1
```

Expected: all three commands exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/network scripts/test_network.ps1 service/signaling/README.md docs/networking.md
git commit -m "test: cover direct multiplayer flow"
```

## Networking Plan Completion Gate

- Signaling tests pass under the repository's supported Node version.
- All Godot core/network tests pass headlessly.
- Multi-process loopback WebRTC flow passes without TURN.
- Logs demonstrate that gameplay envelopes travel directly between Godot peers after signaling.
- No recipient leak test fails and no host migration/relay code exists.
