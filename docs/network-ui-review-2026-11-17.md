# Network and UI review — 2026-11-17

## Scope and outcome

This review covered the signaling service, WebRTC transport, host/client sessions, runtime coordinator, lobby/match/results screens, scene signal wiring, privacy projection, and the existing automated tests.

The core architecture is appropriate for the game: the player-host is authoritative, every remote participant has a direct reliable WebRTC channel to that host, hidden information is projected per recipient, and the small signaling service is used only to establish connections. Hand staging, Joker choices, local card orientation/order, ability targeting, spectator privacy, heartbeat handling, reconnect tokens, and disconnect grace all have implementation and test coverage.

The build is not ready for an internet multiplayer playtest until the high-priority findings below are fixed. In particular, the checked-in STUN setting is not passed to Godot in the shape the transport expects, and the post-match buttons do not reset authoritative state.

## Findings

### High — checked-in STUN configuration is malformed by the transport

- `project.godot:26` configures Godot-style ICE server dictionaries: `[{"urls": ["stun:..."]}]`.
- `src/view/app/runtime_game_session.gd:673` returns that array unchanged.
- `src/network/webrtc_peer_transport.gd:26` converts each dictionary to a string.
- `src/network/webrtc_peer_transport.gd:203` then wraps that string as a URL in another ICE dictionary.

Loopback tests do not require STUN, so they pass while hiding this failure. Direct connections across separate home/mobile networks can consequently fail even when signaling is healthy.

Recommended correction: choose one canonical representation. Prefer storing and accepting complete Godot ICE-server dictionaries, passing them directly to `WebRTCPeerConnection.initialize()`, and adding a test that captures the exact initialization dictionary. Plain URL strings are also viable if `project.godot`, documentation, validation, and tests all use that representation consistently.

### High — rematch and return-to-lobby are only local screen changes

- The controller already provides `reset_for_rematch()` at `src/core/match/match_controller.gd:674`.
- The runtime exposes no rematch/reset operation.
- `src/view/app/app_controller.gd:333` and `src/view/app/app_controller.gd:338` only construct a local lobby model and swap screens.
- No reset is sent to the host controller and no reset snapshot is published to clients or spectators.

The host can see a lobby after a completed match, but the authoritative match remains complete. Other occupants remain on the results screen, and a new match cannot proceed correctly.

The reset path also needs a small state-routing correction: `reset_for_rematch()` places the fresh state in `SETUP`, while `src/view/app/runtime_game_session.gd:434-458` treats every phase other than `START` as an active match. Lobby/match routing should use `config.match_started` plus explicit completed/setup states rather than `phase != START`.

Recommended correction: add a host-only runtime rematch/reset method, call `MatchController.reset_for_rematch()`, restore/validate the occupant roles and readiness, publish a decorated lobby snapshot to every occupant, and make Start transition the reset state into gameplay. Cover host, active client, pending player, and spectator screens in an integration test.

### High — visible Lobby Retry button has no application handler

- `src/view/lobby/lobby_screen.gd:8` declares `retry_requested`, and `src/view/lobby/lobby_screen.gd:185` emits it.
- `src/view/lobby/lobby_screen.tscn:258` connects the visible button to that emitter.
- `src/view/app/app_controller.gd:214-230` wires the other lobby signals but never connects `retry_requested`.

The button appears for direct-connect, signaling-timeout, and room-not-found errors but does nothing when clicked.

Recommended correction: connect it to an application-level retry flow. A room-not-found retry should return to the join form or reuse the entered join data; a direct/reconnect retry should invoke the runtime retry operation only when saved identity and room state make that safe. Add an application-flow test that presses the actual button and observes the runtime call or screen transition.

### Medium — live snapshots do not feed several implemented UI elements

The match UI expects these presentation keys:

- `recent_public_abilities` at `src/view/match/match_screen.gd:203`;
- `last_round_nil` at `src/view/match/match_screen.gd:119` and `src/view/results/results_screen.gd:30`;
- `timeout_notice` at `src/view/match/phase_controls.gd:84`;
- `submission_preview` at `src/view/match/phase_controls.gd:372`.

They are populated by `src/view/app/ui_fixture.gd` and unit-test models, but not by `SnapshotProjector` or `RuntimeGameSession`. Public domain events are immediately followed by a fresh snapshot, and the snapshot does not retain an ability history or timeout/nil metadata. Consequently:

- non-field abilities are not kept visibly revealed in live play;
- nil-round and automatic-timeout explanations do not appear in live play;
- the live score preview falls back to base value and “multipliers pending final catalogue.”

The last item is partly expected until final hand definitions and multipliers arrive. The other three should be derived from authoritative state/events now. Keep only public ability identifiers and targets in the shared history; never include manipulation choices or other private effect details.

### Medium — Main timer and public hard limit are presented as independent settings but are coupled

- Lobby UI exposes both controls in `src/view/lobby/lobby_screen.tscn`.
- `src/view/app/runtime_game_session.gd:574-579` changes both Main phase timers and the public hard limit when `main_timer_msec` changes.
- `src/view/app/runtime_game_session.gd:595` reads the Main timer back from `public_hard_limit_msec` rather than the Main phase timer.
- The controller uses the hard limit as the Main 1/Main 2 deadline at `src/core/match/match_controller.gd:236-239`.

As a result, the two lobby controls do not represent independent behavior. Either collapse them into one clearly named Main-phase hard deadline for the jam build, or implement separate soft timer and hard limit semantics end to end.

### Medium — per-player duplicate-response cache has no bound

`src/network/host_network_session.gd:326-329` replays cached responses for duplicate message IDs, while `src/network/host_network_session.gd:403` stores every new response. Entries remain for the lifetime of an active player connection and have no count or age cap.

A buggy or malicious connected client can continuously submit unique message IDs and grow host memory. Payload validation and the bounded outbound queue do not bound this dictionary.

Recommended correction: retain only a fixed recent window per player (for example 256–512 message IDs), evict oldest entries, and apply a modest inbound command rate limit. Preserve enough history for normal retransmission/deduplication.

### Low — one unexpected peer can fail the host's whole runtime

At `src/view/app/runtime_game_session.gd:326-328`, a connected peer absent from `_peer_assignments` calls `_fail("unapproved_peer")`. Signaling authorization should normally prevent this, but a race, bug, or hostile signaling path would take down the entire host UI instead of isolating the peer.

Recommended correction: disconnect only the unapproved peer, log the reason, and keep the host session alive.

### Low — mouse-only secondary actions need discoverability/accessibility

Right-clicking is intentionally used for ability activation (`src/view/match/ability_panel.gd:73`) and card orientation (`src/view/match/card_widget.gd:96`). The card reorder controls are visible buttons, which is good, but the two right-click actions have no visible tooltip, alternate button, keyboard shortcut, or controller path.

This matches the current mouse-first jam design, but a short on-screen hint and a keyboard-accessible alternate activation would reduce confusion and support trackpads/controllers. The current layout smoke test covers the 1280×720 target only; smaller windows and unusual aspect ratios still need a manual pass.

## What is already solid

- Host-authoritative star topology and direct WebRTC gameplay channels.
- Signaling join nonce, host approval, capacity reservations, host token, payload limits, rate limiting, and transient host re-registration.
- Game-envelope validation, sender identity checks, per-recipient sequencing, bounded out-of-order buffering, snapshot recovery, and bounded outbound queues.
- Recipient-safe public/private projections for active players, pending players, and spectators.
- Heartbeats, match freeze during reconnect grace, reconnect token rotation, and last-player-standing resolution.
- Functional 2D hand builder: stage/unstage, choose a card half, default and change staged Joker choices, local orientation, local ordering, pass, and lock-after-stage acknowledgment.
- Four ability timings, cancelable incomplete targeting, committed effect choices, dimmed targeting UI, and private manipulation details.
- Menu, lobby, match, results, reconnect, and failure screen states exist and are covered by scene-level tests.

## Verification gaps to close before an internet playtest

1. Add a test for the exact ICE configuration passed into a peer connection.
2. Test two exported clients on different real networks; loopback cannot validate NAT traversal.
3. Add an end-to-end rematch test with host, active client, and spectator.
4. Add an application test that presses Lobby Retry.
5. Add live-runtime tests for public ability history, nil round, and timeout notices rather than injecting fixture-only keys.
6. Test 1280×720, 1920×1080, ultrawide, and the smallest supported window with long player/ability names.

## Verification performed during this review

- Full Godot core/network/view suite: **185 passed, 0 failed**.
- Focused UI tests plus headless fixture launch: **42 passed, 0 failed**.
- Signaling service Node suite: **12 passed, 0 failed**.
- Multi-process direct-network test: host + three remote players + spectator connected; command/result and spectator-safe event traveled over direct WebRTC; relaunched player reclaimed the seat; all processes shut down cleanly.

These are strong localhost regression checks. They do not exercise the malformed checked-in STUN dictionary across real NATs, nor do the current fixture-driven UI tests prove the missing live presentation fields or authoritative rematch transition.
