# Placeholder Godot Client and Windows Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a functional placeholder client that exposes every approved lobby and match interaction, renders authoritative state without owning rules, and exports as a downloadable Windows x64 itch.io build.

**Architecture:** Godot Control scenes subscribe to client-session events and render a presentation model. Inputs create commands through a single UI gateway; Views never mutate core state directly. A skippable event-presentation queue separates later animation/audio work from controller and network timing.

**Tech Stack:** Godot 4.7.2 stable, typed GDScript, Control nodes, Theme resources, current core/network plans, Windows x64 export templates.

**Spec:** `docs/superpowers/specs/2026-11-15-shift-card-game-design.md`

## Global Constraints

- Complete the core plan before starting; network-dependent tasks require the networking plan.
- Use placeholder shapes, colors, labels, and card backs only; do not create final art or audio.
- Do not calculate legality, categories, scores, random draws, or timers in the View.
- Never place opponent-private or spectator-forbidden values in scene metadata, tooltips, logs, or hidden Controls.
- Animations may delay presentation but never authoritative phase progression.
- Support 1280×720 minimum and scalable 16:9 desktop windows.
- First export target is Windows x64 portable folder/ZIP for itch.io.
- Every task ends with headless scene tests passing and a user-authored commit.

## Review Focus

- Double-clicks and input arriving during a phase transition must emit at most one command and display authoritative rejection safely; Task 4 pins this.
- A slow presentation queue must fast-forward without losing the latest authoritative state; Task 1 pins this.
- Spectator/opponent scenes must not retain private card values in nonvisible nodes; Task 5 pins this.
- Timer expiry while a targeting modal is open must close/cancel it and render the authoritative fallback; Task 4 pins this.
- Resize, long player names, four seats, four spectators, and maximum six-card hands must not overlap required controls; Task 6 pins this.

---

## Planned File Structure

```text
src/view/
  app/app_controller.gd
  app/app_root.tscn
  common/presentation_queue.gd
  common/presentation_state.gd
  common/ui_command_gateway.gd
  lobby/lobby_screen.gd
  lobby/lobby_screen.tscn
  match/match_screen.gd
  match/match_screen.tscn
  match/card_widget.gd
  match/card_widget.tscn
  match/player_seat.gd
  match/player_seat.tscn
  match/ability_panel.gd
  match/ability_panel.tscn
  match/phase_controls.gd
  match/phase_controls.tscn
  results/results_screen.gd
  results/results_screen.tscn
assets/placeholder/
themes/placeholder_theme.tres
tests/view/**/*_test.gd
scripts/test_ui.ps1
scripts/export_windows.ps1
export_presets.cfg
```

### Task 1: Application Shell and Authoritative Presentation Queue

**Files:**
- Create: `src/view/app/app_root.tscn`
- Create: `src/view/app/app_controller.gd`
- Create: `src/view/common/presentation_state.gd`
- Create: `src/view/common/presentation_queue.gd`
- Create: `src/view/common/ui_command_gateway.gd`
- Create: `themes/placeholder_theme.tres`
- Test: `tests/view/presentation_queue_test.gd`

**Interfaces:**
- Consumes: client-session `snapshot_received`, `event_batch_received`, `connection_state_changed`; local/offline adapter with the same signals.
- Produces: `PresentationState.apply_snapshot(Dictionary)`, `apply_event(Dictionary)`, immutable getters for Views; `PresentationQueue.enqueue(events)`, `skip_to_latest()`, `is_busy()`; `UICommandGateway.send(kind, payload)` with input lock/deduplication.

- [ ] **Step 1: Write failing presentation tests**

Assert ordered application, no rule calculation, snapshot replacement after a sequence gap, skip-to-latest applying every state mutation while omitting delays, and stale animation callbacks unable to overwrite newer state.

- [ ] **Step 2: Run targeted tests and verify failure**

- [ ] **Step 3: Implement presentation state and queue**

Use signals for presentation cues. Placeholder event durations live in View configuration, not domain events.

- [ ] **Step 4: Implement the application shell and command gateway**

- [ ] **Step 5: Run all tests**

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add src/view/app src/view/common themes tests/view
git commit -m "feat: add client presentation shell"
```

### Task 2: Lobby, Join Code, Roles, and Locked Settings UI

**Files:**
- Create: `src/view/lobby/lobby_screen.tscn`
- Create: `src/view/lobby/lobby_screen.gd`
- Test: `tests/view/lobby_screen_test.gd`

**Interfaces:**
- Consumes: lobby projection, signaling/session status, host/non-host role.
- Produces: commands for host room, join code, active/spectator role, ready, start, and pre-match setting changes.

- [ ] **Step 1: Write failing scene tests**

Instantiate the scene headlessly. Assert host sees generated code and editable victory/visibility/timer/reconnect settings before start; non-host sees read-only values; settings lock after start; seat/spectator counts display; invalid/full/connection-failed states show actionable messages.

- [ ] **Step 2: Add command-emission tests**

Assert one command per confirmed action, trimmed/case-normalized code, no start command with fewer than two active players, and no setting commands after lock.

- [ ] **Step 3: Implement lobby screen with placeholder theme**

Do not expose IP addresses or WebRTC internals in normal UI; place diagnostics behind an expandable connection-details panel.

- [ ] **Step 4: Run all tests**

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add src/view/lobby tests/view/lobby_screen_test.gd
git commit -m "feat: add multiplayer lobby screen"
```

### Task 3: Table, Seats, Cards, Piles, Context, and Scores

**Files:**
- Create: `src/view/match/match_screen.tscn`
- Create: `src/view/match/match_screen.gd`
- Create: `src/view/match/card_widget.tscn`
- Create: `src/view/match/card_widget.gd`
- Create: `src/view/match/player_seat.tscn`
- Create: `src/view/match/player_seat.gd`
- Create: `assets/placeholder/README.md`
- Test: `tests/view/match_screen_test.gd`

**Interfaces:**
- Consumes: recipient-safe `PresentationState`.
- Produces: four fixed seat positions, local six-card hand, public played areas, A/B/C piles, active-context clock/direction, phase/timer, match progress, spectators list.

- [ ] **Step 1: Write failing projection/render tests**

Assert local cards render both effective halves; opponent hidden cards render backs/count only; revealed hands render effective values; selected active half is marked; Public mode shows requests/pile counts; Private mode hides them; spectators receive no local-hand widget.

- [ ] **Step 2: Add score/context display tests**

Assert provisional versus final labels, normal/context category names, neutral `No Context Pattern x1`, nil-round result, both victory-progress modes, field duration/conflict indicators, and active A→B→C/reversed clock.

- [ ] **Step 3: Implement responsive placeholder table**

Use containers/anchors rather than absolute pixel assumptions inside each seat. Seat artwork is placeholder geometry but position names remain stable for later art replacement.

- [ ] **Step 4: Run all tests**

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add src/view/match assets/placeholder tests/view/match_screen_test.gd
git commit -m "feat: render placeholder card table"
```

### Task 4: Phase Inputs, Replenishment, Hand Building, and Timeouts

**Files:**
- Create: `src/view/match/phase_controls.tscn`
- Create: `src/view/match/phase_controls.gd`
- Modify: `src/view/match/card_widget.gd`
- Modify: `src/view/match/match_screen.gd`
- Test: `tests/view/phase_controls_test.gd`

**Interfaces:**
- Consumes: current phase, legal-action projection, remaining host time, private hand/staging state.
- Produces: replenishment request, ready, begin/cancel/complete manipulation, selected cards/halves, lock/pass, and End discard commands.

- [ ] **Step 1: Write failing Start UI tests**

Assert required half count, A/B/C steppers capped at five, total validation, partial selection display, confirm lock, timer fallback result display, and simultaneous reveal only from authoritative event.

- [ ] **Step 2: Write failing Hand Play tests**

Assert 0–6 selection, ineligible card disabled, double-active half choice required, category/base/context preview labeled non-authoritative until lock, pass, completed manipulation becoming irreversible, incomplete targeting cancel, timeout closing modal and reflecting auto-submit/pass.

- [ ] **Step 3: Write failing duplicate/transition tests**

Double-click lock/ready emits one command. An event that changes phase disables stale controls immediately. A late rejection restores controls only if the authoritative phase still permits them.

- [ ] **Step 4: Write failing End tests**

Assert short timer, discard-down-to-three count, identity visibility behavior, and random-timeout result sourced only from event.

- [ ] **Step 5: Implement phase controls**

- [ ] **Step 6: Run all tests**

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add src/view/match tests/view/phase_controls_test.gd
git commit -m "feat: add round phase controls"
```

### Task 5: Ability Windows, Privacy, Reactions, and Reconnect States

**Files:**
- Create: `src/view/match/ability_panel.tscn`
- Create: `src/view/match/ability_panel.gd`
- Modify: `src/view/match/match_screen.gd`
- Test: `tests/view/ability_and_privacy_test.gd`

**Interfaces:**
- Consumes: private ability hand for owner, public ability events, legal target projection, ready/reaction/hard-deadline state, connection freeze state.
- Produces: public ability play/target commands and private manipulation workflow commands.

- [ ] **Step 1: Write ability timing tests**

Assert Field/Sabotage only Main 1, Buff/Nerf Main 1 or 2, Manipulation only Hand Play, unlimited valid plays, readiness cleared on public play, and reaction window disabling early phase close.

- [ ] **Step 2: Write privacy-tree tests**

Recursively inspect instantiated Controls and metadata. Opponent/spectator trees must not contain private card/ability IDs, manipulation targets, hidden discards, base identities, or Private-mode pile quantities.

- [ ] **Step 3: Write connection-state tests**

During reconnect grace, disable all gameplay inputs and show paused status/deadline. Successful reconnect replaces state from snapshot. Forfeit, host loss, direct-connect failure, and room closure each show distinct actions/messages.

- [ ] **Step 4: Implement ability and reconnect presentation**

Show sabotage ability and target publicly but removed-card identity only to the owner projection.

- [ ] **Step 5: Run all tests**

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add src/view/match tests/view/ability_and_privacy_test.gd
git commit -m "feat: present abilities and connection states"
```

### Task 6: Results, Rematch, Responsive Layout, and Presentation Smoke Test

**Files:**
- Create: `src/view/results/results_screen.tscn`
- Create: `src/view/results/results_screen.gd`
- Create: `scripts/test_ui.ps1`
- Test: `tests/view/results_screen_test.gd`
- Test: `tests/view/layout_smoke_test.gd`

**Interfaces:**
- Consumes: match-complete/forfeit projection and rematch lobby projection.
- Produces: winner/final standings, return-to-lobby transition, preserved occupants, unlocked host settings.

- [ ] **Step 1: Write result/rematch tests**

Cover normal winner, last-player-standing winner, nil final round preceding later victory, final standings, host disconnect failure path, same-lobby rematch, and reset values.

- [ ] **Step 2: Write responsive layout smoke tests**

Instantiate at 1280×720, 1600×900, 1920×1080, and 2560×1440 with four long player names, six local cards, four played areas, maximum fields, and four spectators. Assert required controls remain inside viewport and interactive rects do not overlap.

- [ ] **Step 3: Implement results and layout fixes**

- [ ] **Step 4: Add UI smoke script**

Run all headless View tests, then launch a deterministic local fixture scene for a human visual check without network dependencies.

- [ ] **Step 5: Run all tests**

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add src/view/results scripts/test_ui.ps1 tests/view
git commit -m "feat: complete placeholder match flow"
```

### Task 7: Windows x64 Export and itch.io Package

**Files:**
- Create: `export_presets.cfg`
- Create: `scripts/export_windows.ps1`
- Create: `docs/release-checklist.md`
- Modify: `project.godot`

**Interfaces:**
- Consumes: Godot 4.7.2 Windows export templates and native WebRTC Windows binary.
- Produces: `build/windows/Shift.exe` plus required data/native libraries and `build/shift-windows-x64.zip`.

- [ ] **Step 1: Configure a Windows Desktop x86_64 preset**

Use a portable build folder, include the native WebRTC extension, and exclude tests/service/source-only documentation from exported resources where safe.

- [ ] **Step 2: Implement the export script**

Fail clearly when Godot/export templates/plugin binaries are missing. Delete/recreate only the explicit `build/windows` and final ZIP paths after validating they are inside the repository.

- [ ] **Step 3: Export the Windows x64 build**

- [ ] **Step 4: Run a process smoke test**

Launch the exported executable with a test-only argument that loads the lobby, writes `startup_ok`, and exits. Assert exit code 0 and required WebRTC library loaded.

- [ ] **Step 5: Verify package contents and document itch upload**

Checklist covers clean-machine launch, firewall prompt expectations, lobby/signaling configuration, two-machine direct connection, four-player table, reconnect, host loss, and butler/ZIP upload.

- [ ] **Step 6: Run complete verification**

```powershell
npm --prefix service/signaling test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_network.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_ui.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/export_windows.ps1
```

Expected: all commands exit 0 and the Windows ZIP is produced.

- [ ] **Step 7: Commit**

```bash
git add export_presets.cfg scripts/export_windows.ps1 docs/release-checklist.md project.godot
git commit -m "build: add Windows itch export"
```

## Client Plan Completion Gate

- A host can create a code, two to four active players can join directly, and four spectators can observe.
- Every global phase and timeout path is operable with placeholder UI.
- Privacy-tree tests prove recipient-safe rendering.
- Presentation may be skipped/caught up without changing state.
- A clean Windows x64 package launches and completes the direct-connect smoke checklist.
