# Cloudflare TURN Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Cloudflare Realtime TURN as an ICE fallback while preserving Shift's player-hosted, host-authoritative WebRTC gameplay and direct-connection preference.

**Architecture:** The Node signaling service owns the permanent Cloudflare key, requests bounded short-lived ICE credentials, and attaches a sanitized configuration to the existing authorized `room_created` and `join_approved` messages. The Godot client validates those dictionaries and updates `WebRTCPeerTransport` before any peer is created; WebRTC then chooses a direct candidate when possible and a relay candidate only when needed. Provider errors degrade to the checked-in STUN server instead of blocking lobby flow.

**Tech Stack:** Node.js 22 built-in `fetch`, `node:test`, `ws`, Godot 4.7 GDScript, WebRTC Native 1.2.2, PowerShell test harnesses

**Spec:** `docs/superpowers/specs/2026-11-17-cloudflare-turn-fallback-design.md`

## Global Constraints

- Work natively on the current `master` branch as explicitly approved; do not use implementation or review subagents.
- Use strict RED→GREEN TDD for production behavior and commit each task independently.
- Keep permanent Cloudflare key IDs and API tokens out of the repository, game export, client messages, health response, and logs.
- Default `TURN_CREDENTIAL_TTL_SECONDS` to `14400`; clamp configured values to `60..172800` seconds.
- Prefer direct WebRTC; do not add a gameplay WebSocket relay, SFU, dedicated authoritative server, or forced-relay policy.
- Preserve protocol version `1`, lobby authorization, capacity, reconnect, privacy, and existing recipient-specific snapshots.
- The automated suite must not require network access or live Cloudflare credentials.
- When Cloudflare is missing, slow, rejects the request, or returns invalid data, complete the lobby operation with the checked-in STUN configuration and `relay_available: false`.
- Canonical ICE entries contain only `urls`, optional `username`, and optional `credential`; credentials must appear as a pair.
- No new runtime dependency is needed; use Node 22's built-in `fetch` and `AbortSignal.timeout`.

## Review Focus

- A Cloudflare request that never settles must hit the five-second provider timeout and allow the signaling flow to fall back; Task 1 tests the timeout signal and Task 2 tests provider rejection fallback.
- Malformed or oversized provider/client ICE data must not reach `WebRTCPeerConnection.initialize()`; Tasks 1 and 3 test URL counts, lengths, credential pairing, and unknown-field removal.
- Legacy signaling messages without relay fields must retain the project's static STUN configuration; Task 3 tests the omitted-field path.
- Host re-registration and participant reconnection must receive fresh short-lived credentials rather than replaying an expired payload; Task 2 tests repeated issuance.
- Asynchronous credential lookup must preserve per-socket message order and must not produce unhandled rejections after a socket closes; Task 2 tests serialized dispatch and safe fallback delivery.

---

### Task 1: Cloudflare Credential Provider

**Files:**
- Create: `service/signaling/src/ice_server_provider.js`
- Create: `service/signaling/test/ice_server_provider.test.js`

**Interfaces:**
- Consumes: environment keys `CLOUDFLARE_TURN_KEY_ID`, `CLOUDFLARE_TURN_API_TOKEN`, and optional `TURN_CREDENTIAL_TTL_SECONDS`.
- Produces: `createIceServerProvider({ env, fetchImpl, requestTimeoutMs }) -> { name, configured, getIceServers() }`, `fallbackIceServers() -> Array`, and `normalizeIceServers(value) -> Array`.
- `getIceServers()` resolves to a canonical array; provider/network/response failures reject without including secrets in error text.
- Canonical limits: at most 8 server records, at most 8 URLs per record, URL length `1..2048`, username/credential length `1..1024`, and paired credentials only.

- [ ] **Step 1: Write the provider tests first**

Add literal-fixture tests named:

- `unconfigured provider returns the STUN fallback without calling fetch`
- `cloudflare provider posts bounded TTL and normalizes its ICE response`
- `cloudflare provider clamps TTL to the supported range`
- `cloudflare provider rejects HTTP and malformed responses without exposing secrets`
- `normalization rejects oversized URL collections and unpaired credentials`
- `cloudflare request carries a five-second abort signal`

The successful request must assert the exact endpoint, `Authorization: Bearer <token>`, JSON body `{ "ttl": 14400 }`, and canonical output containing Cloudflare STUN/TURN URLs plus the temporary username/credential. Expected values must be hand-written literals.

- [ ] **Step 2: Run the focused provider test and verify RED**

Run from `service/signaling`:

```powershell
node --test test/ice_server_provider.test.js
```

Expected: FAIL because `../src/ice_server_provider.js` does not exist.

- [ ] **Step 3: Implement the minimal provider module**

Implement:

```js
export function fallbackIceServers()
export function normalizeIceServers(value)
export function createIceServerProvider({ env = process.env, fetchImpl = globalThis.fetch, requestTimeoutMs = 5_000 } = {})
```

Use `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(keyId)}/credentials/generate-ice-servers`, `POST`, bearer authorization, `content-type: application/json`, and `AbortSignal.timeout(requestTimeoutMs)`. Require at least one valid `turn:` or `turns:` URL from a configured Cloudflare response. Return defensive copies from the unconfigured fallback.

- [ ] **Step 4: Run provider tests and syntax checks**

Run:

```powershell
node --test test/ice_server_provider.test.js
node --check src/ice_server_provider.js
```

Expected: all provider tests PASS; syntax check exits `0`.

- [ ] **Step 5: Run the complete signaling suite**

Run:

```powershell
npm test
```

Expected: all signaling tests PASS with no live Cloudflare request.

- [ ] **Step 6: Commit Task 1**

```powershell
git add service/signaling/src/ice_server_provider.js service/signaling/test/ice_server_provider.test.js
git commit -m "feat: add Cloudflare TURN credential provider"
```

---

### Task 2: Authorized Signaling Credential Delivery

**Files:**
- Modify: `service/signaling/src/server.js`
- Modify: `service/signaling/test/server.test.js`

**Interfaces:**
- Consumes: Task 1's provider object and `fallbackIceServers()`.
- Produces: `createSignalingServer({ iceServerProvider, ...existingOptions })`; health field `relay: { provider: String, configured: bool }`; and optional protocol fields `ice_servers: Array`, `relay_available: bool` on `room_created` and `join_approved`.
- Provider issuance occurs only for a created/reconnected host or an approved joiner; pending and rejected joins receive none.

- [ ] **Step 1: Write failing signaling integration tests**

Extend `server.test.js` with real WebSocket behavior tests named:

- `health reports relay configuration without identifiers or secrets`
- `host and approved joiner receive distinct temporary ICE credentials`
- `host reconnect and re-approved player obtain fresh ICE credentials`
- `provider rejection or malformed output falls back to STUN without blocking room creation or approval`
- `asynchronous credential issuance preserves message order and handles a closed socket`

Inject small fake providers whose `getIceServers()` returns literal arrays, rejects, or resolves controlled promises. Assert that `join_pending` contains no credentials, permanent fake secrets never occur in serialized messages/health, and fallback payloads equal the literal STUN entry with `relay_available: false`.

- [ ] **Step 2: Run focused signaling tests and verify RED**

Run from `service/signaling`:

```powershell
node --test test/server.test.js
```

Expected: FAIL because the server does not inject or deliver ICE credentials and health has no relay status.

- [ ] **Step 3: Make message dispatch asynchronous and ordered**

In `createSignalingServer`, construct `options.iceServerProvider ?? createIceServerProvider()`. Serialize each socket's decoded messages through a promise chain so an asynchronous `host_room` or `approve_join` finishes before that socket's next message. Route both synchronous `RoomRegistryError` and promise rejections through the existing safe error response without allowing an unhandled rejection.

- [ ] **Step 4: Attach sanitized ICE payloads at authorized boundaries**

Make `handleMessage` asynchronous. For `host_room` (new or reconnect) and `approve_join`, await a helper that calls `provider.getIceServers()`, normalizes the result, and returns `{ ice_servers, relay_available }`. On any failure, return `fallbackIceServers()` and `false`. Do not issue credentials for `join_room`, `join_pending`, or `join_requested`.

- [ ] **Step 5: Update the health response**

Return the existing fields plus `relay: { provider: provider.name, configured: provider.configured }`. Do not call the provider from `/health`, and expose neither key IDs nor tokens.

- [ ] **Step 6: Run focused and complete signaling tests**

Run:

```powershell
node --test test/server.test.js
npm test
node --check src/server.js
```

Expected: all commands exit `0`; all legacy routing/authorization tests remain green.

- [ ] **Step 7: Commit Task 2**

```powershell
git add service/signaling/src/server.js service/signaling/test/server.test.js
git commit -m "feat: deliver TURN credentials through signaling"
```

---

### Task 3: Godot ICE Validation and WebRTC Configuration

**Files:**
- Modify: `src/network/signaling_client.gd`
- Modify: `src/network/webrtc_peer_transport.gd`
- Modify: `tests/network/signaling_client_test.gd`
- Modify: `tests/network/webrtc_transport_test.gd`

**Interfaces:**
- Consumes: Task 2's optional `ice_servers` and `relay_available` signaling fields.
- Produces: `SignalingClient.ice_servers_received(servers: Array, relay_available: bool)` emitted before `room_created` or `join_approved`; `WebRTCPeerTransport.set_ice_servers(servers: Array) -> Error`; `WebRTCPeerTransport.relay_available: bool`; and an optional constructor `peer_factory: Callable` used only to replace the external native boundary in tests.
- `WebRTCPeerTransport` stores canonical dictionaries and passes them unchanged as `{ "iceServers": canonicalServers }` to `WebRTCPeerConnection.initialize()`.

- [ ] **Step 1: Write failing signaling-client validation tests**

Add tests named:

- `host accepts canonical ICE servers before announcing the room`
- `joiner accepts TURN credentials before announcing approval`
- `legacy signaling payload without ICE fields remains compatible`
- `malformed oversized or unpaired ICE data fails the signaling client`

Use the existing `FakeSocket`. Assert ordering by appending markers from `ice_servers_received` and `room_created`/`join_approved`. Assert unknown provider fields are removed and the input is defensively copied.

- [ ] **Step 2: Run signaling-client tests and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/network/signaling_client_test.gd
```

Expected: FAIL because `ice_servers_received` and ICE payload validation do not exist.

- [ ] **Step 3: Implement signaling payload normalization**

Add the signal and a private normalizer using the same limits as Task 1. Accept a missing pair of relay fields for backward compatibility. If either relay field is present, require both, require `relay_available` to be a bool, normalize only `urls`/`username`/`credential`, and fail with `malformed_signaling_message` before emitting room/join readiness when invalid.

- [ ] **Step 4: Run signaling-client tests and verify GREEN**

Run the Step 2 command.

Expected: all signaling-client tests PASS.

- [ ] **Step 5: Write failing transport boundary tests**

Add a minimal fake peer connection that records the real initialize argument and returns `null` from `create_data_channel`. Add tests named:

- `transport passes complete STUN and TURN dictionaries to peer initialization`
- `transport replaces static STUN after signaling credential delivery`
- `transport rejects malformed replacement without losing prior ICE configuration`

The first test must catch the current dictionary-to-string regression by asserting literal dictionaries, username, and credential in the recorded initialize configuration.

- [ ] **Step 6: Run transport tests and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/network/webrtc_transport_test.gd
```

Expected: FAIL because the transport stringifies dictionaries, lacks replacement, and lacks the peer factory boundary.

- [ ] **Step 7: Implement canonical transport storage and signaling update**

Rename constructor input conceptually from URL strings to ICE server dictionaries, normalize it, and add the optional peer factory as the final argument. Wire `ice_servers_received` before the existing readiness handlers. `set_ice_servers()` must reject an invalid whole replacement atomically, reject replacement after any peer exists with `ERR_BUSY`, and update `relay_available` only after a valid replacement. `_create_peer()` must initialize with a deep copy of the canonical dictionaries.

- [ ] **Step 8: Run focused and full Godot tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/network/signaling_client_test.gd tests/network/webrtc_transport_test.gd tests/network/webrtc_plugin_smoke_test.gd
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

Expected: focused network tests and the full Godot suite PASS with no engine errors.

- [ ] **Step 9: Commit Task 3**

```powershell
git add src/network/signaling_client.gd src/network/webrtc_peer_transport.gd tests/network/signaling_client_test.gd tests/network/webrtc_transport_test.gd
git commit -m "feat: configure WebRTC TURN fallback"
```

---

### Task 4: Deployment Documentation and End-to-End Regression

**Files:**
- Create: `service/signaling/.env.example`
- Modify: `service/signaling/README.md`
- Modify: `docs/networking.md`
- Modify: `docs/release-checklist.md`

**Interfaces:**
- Consumes: Tasks 1-3's exact environment names, health shape, fallback behavior, and test commands.
- Produces: operator steps for generating a Cloudflare TURN key, storing the permanent secrets on the signaling host, confirming relay configuration, and testing across restrictive networks.

- [ ] **Step 1: Write the deployment configuration example**

Create `.env.example` with placeholders only:

```text
PORT=8080
CLOUDFLARE_TURN_KEY_ID=
CLOUDFLARE_TURN_API_TOKEN=
TURN_CREDENTIAL_TTL_SECONDS=14400
```

State explicitly that the Node service does not load this file automatically; the deployment platform must set these values as environment secrets.

- [ ] **Step 2: Document setup and failure behavior**

Update the signaling README and networking guide with:

- the Cloudflare Realtime TURN dashboard/key creation step;
- the three supported environment variables and four-hour default;
- direct-first ICE behavior and encrypted relayed data channels;
- `relay.configured` health interpretation without secret exposure;
- STUN-only degradation when configuration or credential issuance fails;
- free-tier/bandwidth caveat and a recommendation to enable Cloudflare usage/billing alerts;
- a real two-network/restrictive-firewall smoke test.

Replace the obsolete statement that no TURN fallback exists. Keep the explicit statement that there is no WebSocket gameplay relay.

- [ ] **Step 3: Update the release checklist**

Add checks for deployment secrets, sanitized health output, separate-network direct play, restrictive-network relayed play, provider analytics, and billing alerts.

- [ ] **Step 4: Run the complete verification matrix**

Run:

```powershell
Set-Location service/signaling
npm test
Set-Location ../..
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_ui.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_network.ps1
git diff --check
```

Expected: signaling, Godot, UI, and multi-process network suites all exit `0`; `git diff --check` has no output. The multi-process suite remains self-contained and uses STUN/direct loopback rather than contacting Cloudflare.

- [ ] **Step 5: Commit Task 4**

```powershell
git add service/signaling/.env.example service/signaling/README.md docs/networking.md docs/release-checklist.md
git commit -m "docs: document Cloudflare TURN deployment"
```

- [ ] **Step 6: Perform the native whole-branch review**

Generate the executing-plans review package from the commit before Task 1 through `HEAD`. Because the user explicitly required a native, non-subagent workflow, read the reviewer brief and perform the review as a separate author pass. Record any Critical/Important finding, add a failing regression test, fix it once, rerun the full suite, and commit the fix. Record Minor findings for the final handoff rather than expanding scope.
