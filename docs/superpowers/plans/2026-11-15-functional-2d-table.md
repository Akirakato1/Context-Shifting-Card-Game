# Functional 2D Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a playable Control-based four-seat table with local hand building, Joker prompts, score preview, ability targeting, and authoritative hand reveals using replaceable placeholder art.

**Architecture:** Recipient-safe snapshots and events feed a `GameTablePresenter`, which owns presentation data and sends intents through a command gateway. Focused `Control` scenes render cards, seats, the submission shelf, ability drawer, and targeting overlay; scene scripts never mutate core state or calculate rules independently.

**Tech Stack:** Godot 4.7.2 stable, typed GDScript, Control scenes, Tween animation, current core/network sessions, custom headless scene tests.

**Spec:** `docs/superpowers/specs/2026-11-15-functional-2d-table-joker-design.md`

## Global Constraints

- Complete `docs/superpowers/plans/2026-11-15-joker-submission-model.md` first.
- Use a 1920×1080 composition baseline and support 1280×720 minimum landscape desktop layout.
- Use placeholder geometry, labels, colors, card backs, and tweens only; no 3D, final art, audio, or particles.
- The View may manage order, orientation, hover, drawer, targeting, and animation state but never authoritative game rules.
- Right-click orientation, drag order, and incomplete ability choices are local-only and are never networked.
- Joker A/ONE defaults are applied only when a Joker enters the submission shelf and reset when it leaves.
- Animations may be skipped and must never block phase progression.

## Review Focus

- A resize with four seats, six hand cards, six staged cards, and an expanded ability drawer must keep all required controls reachable; Task 5 pins this.
- Phase/snapshot replacement during targeting or drag must cancel stale interaction without emitting a command; Tasks 2 and 4 pin this.
- A rejected or duplicate lock command must leave the View consistent with the latest authoritative private staging; Task 1 pins this.
- Opponent and spectator node trees must never contain private card/Joker/ability values in hidden Controls or metadata; Task 5 pins this.
- Reveal animation interruption or reconnect must snap to the final authoritative arrangement without replaying stale callbacks; Task 5 pins this.

---

### Task 1: Presentation State, Command Gateway, and Table Presenter

**Files:**
- Create: `src/view/common/presentation_state.gd`
- Create: `src/view/common/ui_command_gateway.gd`
- Create: `src/view/common/private_card_adapter.gd`
- Create: `src/view/match/game_table_presenter.gd`
- Test: `tests/view/presentation_state_test.gd`
- Test: `tests/view/game_table_presenter_test.gd`

**Interfaces:**
- Consumes: `ClientNetworkSession.snapshot_applied`, `events_applied`, `command_result_received`, and `session_failed`; tests may drive the same methods directly.
- Produces: `PresentationState.replace_snapshot(snapshot: Dictionary, sequence: int)`, `apply_events(events: Array, sequence: int)`, `public_state() -> Dictionary`, and `private_state() -> Dictionary` returning duplicates.
- Produces: `UICommandGateway.submit(kind: StringName, payload: Dictionary) -> String` with one in-flight lock command and monotonically unique message/command IDs.
- Produces: `PrivateCardAdapter.to_full_cards(private_hand: Array) -> Array[FullCardState]`; it reconstructs preview-only card values from the owner projection and never enters `MatchState`.
- Produces: `GameTablePresenter.table_changed(model: Dictionary)`, `presentation_cue_requested(cue: Dictionary)`, `interaction_cancelled(reason: StringName)`, and intent methods for staging, lock, ability targeting, sorting, and orientation.

- [ ] **Step 1: Write failing snapshot/event sequence tests**

Assert snapshot replacement, ordered event application, stale sequence rejection, private-state replacement, and a reveal cue that cannot overwrite a newer snapshot.

- [ ] **Step 2: Write failing command/draft tests**

Assert one lock command while pending, authoritative rejection restoring the latest private staging, card order/orientation never entering payloads, and snapshot/phase change cancelling drag or targeting without sending.

- [ ] **Step 3: Run focused tests and verify failure**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/presentation_state_test.gd tests/view/game_table_presenter_test.gd`

Expected: FAIL because the presentation layer does not exist.

- [ ] **Step 4: Implement presentation state and the command gateway**

Store only recipient-projected dictionaries. Implement `PrivateCardAdapter` as the sole projected-DTO-to-domain-card conversion boundary. Build `STAGE_HAND` payloads with the exact canonical selection/Joker-choice shape from the Joker plan and use `LOCK_HAND` separately.

- [ ] **Step 5: Implement `GameTablePresenter`**

Presenter methods update harmless local draft state, call `SubmissionEvaluator` for previews using `PrivateCardAdapter.to_full_cards(...)`, and emit immutable table models to Views.

- [ ] **Step 6: Run tests and commit**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/presentation_state_test.gd tests/view/game_table_presenter_test.gd`

Expected: all selected tests PASS.

```powershell
git add src/view/common src/view/match/game_table_presenter.gd tests/view
git commit -m "feat: add table presentation model"
```

### Task 2: Reusable Card, Hand, and Submission Controls

**Files:**
- Create: `src/view/match/card_view.gd`
- Create: `src/view/match/card_view.tscn`
- Create: `src/view/match/hand_view.gd`
- Create: `src/view/match/hand_view.tscn`
- Create: `src/view/match/submission_view.gd`
- Create: `src/view/match/submission_view.tscn`
- Create: `src/view/match/score_preview_view.gd`
- Create: `src/view/match/score_preview_view.tscn`
- Test: `tests/view/card_and_submission_view_test.gd`

**Interfaces:**
- Consumes: card DTOs and preview dictionaries produced by `GameTablePresenter`.
- Produces: `CardView.render(model: Dictionary)`, signals `primary_clicked(card_id)`, `orientation_requested(card_id)`, `drag_requested(card_id, target_index)` and `joker_choice_changed(card_id, half_index, context, suit)`.
- Produces: `HandView.render(cards: Array, local_order: Array[StringName], orientations: Dictionary)`.
- Produces: `SubmissionView.render(cards: Array, preview: Dictionary, locked: bool)` and ordered draft intent signals.
- Produces: `ScorePreviewView.render(preview: Dictionary)` showing base sum, both categories/multipliers, modifiers, projected rounded score, and invalid reason.

- [ ] **Step 1: Write failing card-state tests**

Cover local, staged, hidden, revealed, targeting eligible/ineligible, yellow selected, locked, and resolving states. Assert opponent hidden cards never receive face DTOs.

- [ ] **Step 2: Write failing interaction tests**

Assert click moves between hand/shelf, drag reorder is local, right-click flips visual halves without changing the selected half payload, and a phase replacement cancels active drag.

- [ ] **Step 3: Write failing Joker and preview tests**

When a card with one or two Jokers enters the shelf, assert each receives A/ONE, prompts render on the matching half, changes update only that choice, unstage/removal clears choices, and incomplete/invalid preview disables lock with a reason.

- [ ] **Step 4: Run focused tests and verify failure**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/card_and_submission_view_test.gd`

Expected: FAIL because the controls do not exist.

- [ ] **Step 5: Implement the reusable controls**

Use a two-region `CardView` with placeholder colors/labels and an input-transparent overlay for tint/glow. Use explicit positioned card layers inside responsive shelf/hand containers so reordering can tween without changing game state.

- [ ] **Step 6: Run tests and commit**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/card_and_submission_view_test.gd`

Expected: all selected tests PASS.

```powershell
git add src/view/match tests/view/card_and_submission_view_test.gd
git commit -m "feat: add interactive hand builder"
```

### Task 3: Four-Seat Table, Context Clock, and Ability Drawer

**Files:**
- Create: `src/view/match/seat_view.gd`
- Create: `src/view/match/seat_view.tscn`
- Create: `src/view/match/context_clock_view.gd`
- Create: `src/view/match/context_clock_view.tscn`
- Create: `src/view/match/ability_drawer_view.gd`
- Create: `src/view/match/ability_drawer_view.tscn`
- Create: `src/view/match/game_table_view.gd`
- Create: `src/view/match/game_table_view.tscn`
- Create: `themes/placeholder_theme.tres`
- Test: `tests/view/game_table_view_test.gd`

**Interfaces:**
- Consumes: complete table model and cues from Task 1 plus controls from Task 2.
- Produces: a stable four-seat layout with local seat at bottom and opponent seats left/top/right.
- Produces: `GameTableView.bind_presenter(presenter: GameTablePresenter)` and `render(model: Dictionary)`.
- Produces: `AbilityDrawerView.ability_activated(copy_id: StringName)` on right-click and local `expanded` state.

- [ ] **Step 1: Write failing idle-table tests**

Instantiate four players and assert local hand/shelf, three opponent hidden hands, names, scores, readiness/connection states, A/B/C pile regions, phase/timer/round, active fields, clock direction, sort buttons, and collapsed ability tab.

- [ ] **Step 2: Write failing drawer and sort tests**

Assert drawer expands upward and collapses without cancelling committed effects; right-click emits only legal ability activation; context/rank/suit sorting changes local order only.

- [ ] **Step 3: Run the scene tests and verify failure**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/game_table_view_test.gd`

Expected: FAIL because the table scenes do not exist.

- [ ] **Step 4: Implement the table composition and placeholder theme**

Use anchors/containers for major regions and preserve named card/reveal layers for later art replacement. Piles show only fields present in the recipient projection.

- [ ] **Step 5: Run tests and commit**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/game_table_view_test.gd`

Expected: all selected tests PASS.

```powershell
git add src/view/match themes/placeholder_theme.tres tests/view/game_table_view_test.gd
git commit -m "feat: render functional four-seat table"
```

### Task 4: Generic Ability Targeting Overlay

**Files:**
- Create: `src/view/match/targeting_overlay.gd`
- Create: `src/view/match/targeting_overlay.tscn`
- Modify: `src/view/match/game_table_presenter.gd`
- Modify: `src/view/match/game_table_view.gd`
- Test: `tests/view/ability_targeting_view_test.gd`

**Interfaces:**
- Consumes: ability `choice_schema`, legal target projection, and current phase from the presenter.
- Produces: `TargetingOverlay.begin(workflow: Dictionary)`, `advance(selection: Variant)`, `cancel()`, `commit_requested(choices: Dictionary)`, and `closed`.
- Produces: dimmed unrelated UI, luminous eligible card regions, yellow selected cards, prompt/current-step/remaining-count display, and input capture until cancel or commit.

- [ ] **Step 1: Write failing single- and multi-step targeting tests**

Cover one card, multiple cards, half selection, player target, and enum choice steps. Assert ineligible clicks do nothing, selections tint yellow, and incomplete workflows cannot commit.

- [ ] **Step 2: Write failing cancel/commit/interruption tests**

Assert cancel before final commit sends nothing; final commit sends exactly one command and cannot undo; phase timeout, snapshot replacement, ability removal, or disconnect closes the overlay and clears all dim/glow state.

- [ ] **Step 3: Run focused tests and verify failure**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/ability_targeting_view_test.gd`

Expected: FAIL because the targeting overlay does not exist.

- [ ] **Step 4: Implement schema-driven targeting**

Keep effect execution in the controller. The overlay only collects schema-declared choices and the presenter maps them to the existing public-ability or manipulation command payload.

- [ ] **Step 5: Run tests and commit**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/ability_targeting_view_test.gd`

Expected: all selected tests PASS.

```powershell
git add src/view/match tests/view/ability_targeting_view_test.gd
git commit -m "feat: add ability targeting mode"
```

### Task 5: Resolution Animation, Responsive Layout, and Runnable Scene

**Files:**
- Create: `src/view/common/presentation_queue.gd`
- Create: `src/view/app/app_root.gd`
- Create: `src/view/app/app_root.tscn`
- Create: `src/view/dev/local_match_session.gd`
- Create: `src/view/dev/local_match_fixture.gd`
- Create: `src/view/dev/local_match_fixture.tscn`
- Modify: `src/view/match/game_table_view.gd`
- Modify: `project.godot`
- Test: `tests/view/resolution_presentation_test.gd`
- Test: `tests/view/layout_smoke_test.gd`
- Test: `tests/view/privacy_tree_test.gd`

**Interfaces:**
- Consumes: `presentation_cue_requested` and authoritative table models.
- Produces: `PresentationQueue.enqueue(cue)`, `skip_to_latest()`, `cancel_stale(snapshot_sequence: int)`, and `is_busy() -> bool`.
- Produces: `LocalMatchSession.submit_command(message_id: String, command: Dictionary) -> Error`, `poll()`, and the same four client-facing signals consumed in Task 1; accepted local commands emit recipient-projected snapshots/events through `MatchController`.
- Produces: runnable `app_root.tscn`; the development fixture supplies deterministic four-player projected state through `LocalMatchSession`.

- [ ] **Step 1: Write failing reveal/catch-up tests**

Assert all seat submissions move into reveal regions, use scale/pivot tweens to flip face-up, display score components/tie/nil results, and `skip_to_latest()` reaches the same final model without waiting.

- [ ] **Step 2: Write failing responsive layout tests**

At 1280×720 and 1920×1080, render four long names, six hand cards, six staged cards, two Joker prompts, expanded abilities, fields, and score preview. Assert required controls stay inside the viewport and their essential input rectangles do not overlap.

- [ ] **Step 3: Write failing privacy-tree tests**

Recursively inspect opponent and spectator Controls, metadata, tooltips, and labels. Before reveal, assert they contain no private card IDs/faces, Joker choices, ability copy IDs, or hidden discard identities.

- [ ] **Step 4: Run focused tests and verify failure**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/resolution_presentation_test.gd tests/view/layout_smoke_test.gd tests/view/privacy_tree_test.gd`

Expected: FAIL until the queue/root/fixture and final layout behavior exist.

- [ ] **Step 5: Implement skippable presentation and the runnable root**

Set `run/main_scene` to `app_root.tscn`. In development mode the deterministic local fixture opens the approved four-player idle table through `LocalMatchSession`; production `ClientNetworkSession` injection uses the same presenter/view without fixture-only state in exported node metadata.

- [ ] **Step 6: Run the complete verification suite**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1`

Run: `npm --prefix service/signaling test`

Expected: zero Godot/Node failures and no `SCRIPT ERROR` or `ERROR:` output.

- [ ] **Step 7: Launch the scene for a visual smoke check**

Run: `& $env:SHIFT_GODOT_BIN --path . --editor project.godot`

Expected: the four-seat functional table opens at 1280×720; card staging, orientation, reordering, Joker choices, ability drawer/targeting, lock, and reveal can be exercised with placeholder visuals.

- [ ] **Step 8: Commit**

```powershell
git add src/view project.godot tests/view
git commit -m "feat: complete functional 2d table"
```

## Completion Gate

- The runnable game displays the approved four-player idle composition at 1280×720 and 1920×1080.
- The local player can reorder/orient cards, stage any subset, edit per-half Joker choices, see authoritative-equivalent preview components, and lock once.
- The ability drawer and generic targeting overlay implement dimming, eligibility glow, yellow selection, cancellation, and irreversible commit.
- Authoritative resolution reveals all seats with skippable 2D motion and no private information appears early.
- The full Godot and signaling suites pass with zero engine errors.

