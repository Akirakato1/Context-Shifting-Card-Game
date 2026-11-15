# Joker Submission Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one rank-zero Joker half to every context pile and make its temporary staged context/suit choices authoritative, private, scoreable, serializable, and safe to reveal.

**Architecture:** Joker identity belongs to immutable half-card state, while context/suit choices belong only to each staged submission entry. A pure `SubmissionEvaluator` validates a draft and produces selected faces, resolved public card faces, context counts, and the score breakdown; the controller and later View preview both consume that single rules service.

**Tech Stack:** Godot 4.7.2 stable, typed GDScript, current deterministic core model, recipient-projected snapshots/events, custom headless test runner.

**Spec:** `docs/superpowers/specs/2026-11-15-functional-2d-table-joker-design.md`

## Global Constraints

- Each A/B/C pile contains the existing 90 normal halves plus exactly one Joker half.
- A Joker has immutable rank `0`, origin-pile ownership, no persistent suit/context override, and is eligible in every active context.
- Every staged Joker half defaults in the View to context `A` and suit `ONE`, but the host requires an explicit valid choice in the submitted command.
- Choices are independent for both halves of a double-Joker card and exist only while that full card is staged.
- Persistent manipulation overrides and temporary Joker choices must remain separate.
- Opponents and spectators never receive private staged choices; resolution reveals sanitized effective faces.
- Do not change the current A/B/C or ONE/TWO/THREE placeholder names.

## Review Focus

- Missing, duplicate, out-of-range, or non-integer Joker choices must reject the command without mutating the previous draft; Task 2 pins this.
- A double-Joker full card must carry two independent choices and use the selected half's suit with rank zero; Task 2 pins this.
- Unstaging, replacing a draft, resolving a hand, or removing a card from hand must leave no stale Joker choice; Task 3 pins this.
- Canonical restore and owner reconnect must preserve current private choices without leaking them to another role; Task 4 pins this.
- Ordinary cards containing persistent overrides must score exactly as before when mixed with Jokers; Task 2 pins this.

---

### Task 1: Joker Identity, Pile Construction, and Card Serialization

**Files:**
- Modify: `src/core/common/game_types.gd`
- Modify: `src/core/cards/half_card_state.gd`
- Modify: `src/core/cards/full_card_state.gd`
- Modify: `src/core/match/match_state.gd`
- Modify: `src/core/match/snapshot_projector.gd`
- Modify: `tests/core/cards/context_pile_test.gd`
- Modify: `tests/core/cards/card_factory_test.gd`
- Test: `tests/core/cards/joker_half_test.gd`

**Interfaces:**
- Produces: `GameTypes.HalfKind { NORMAL, JOKER }`.
- Produces: `HalfCardState._init(id: StringName, origin_context: int, rank: int, suit: int, kind: int = GameTypes.HalfKind.NORMAL)`; normal callers remain source-compatible.
- Produces: `HalfCardState.is_joker() -> bool` and `HalfCardState.NO_SUIT := -1`.
- Produces: `FullCardState.half_at(index: int) -> HalfCardState` and Joker-aware `eligible_half_indexes(active_context: int)`.
- Produces: serialized/private half DTO field `kind`; a Joker DTO uses rank `0`, suit `NO_SUIT`, and its origin context.

- [ ] **Step 1: Write failing Joker identity and pile tests**

Add `test_joker_has_origin_identity_without_effective_override`, `test_joker_is_eligible_in_every_context`, and `test_match_builds_ninety_one_halves_with_one_joker_per_pile`. Assert each pile totals `91`, exactly one card has `kind == JOKER`, and its origin matches the pile.

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/cards/joker_half_test.gd tests/core/cards/context_pile_test.gd`

Expected: FAIL because Joker identity and the 91st half do not exist.

- [ ] **Step 3: Implement the immutable Joker representation**

Keep `base_context` as origin-pile ownership for compatibility. Accept `(rank == 0 and suit == NO_SUIT)` only for `HalfKind.JOKER`; reject manipulation overrides on a Joker so temporary staging can never enter the persistent layer.

- [ ] **Step 4: Add exactly one Joker to each pile and round-trip its kind**

Use opaque IDs `joker-<context>` inside `_build_piles()`. Include `kind` in canonical/private serialization and default missing legacy data to `NORMAL` during deserialization.

- [ ] **Step 5: Run card, setup, and snapshot tests**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/cards tests/core/match/match_setup_test.gd tests/core/match/snapshot_projector_test.gd`

Expected: all selected tests PASS and ordinary opening/replenishment behavior remains deterministic.

- [ ] **Step 6: Commit**

```powershell
git add src/core/common/game_types.gd src/core/cards src/core/match/match_state.gd src/core/match/snapshot_projector.gd tests/core/cards tests/core/match/match_setup_test.gd tests/core/match/snapshot_projector_test.gd
git commit -m "feat: add joker half cards"
```

### Task 2: Pure Submission Validation and Scoring

**Files:**
- Modify: `src/core/scoring/scoring_types.gd`
- Modify: `src/core/scoring/context_hand_evaluator.gd`
- Create: `src/core/scoring/submission_evaluator.gd`
- Test: `tests/core/scoring/submission_evaluator_test.gd`
- Modify: `tests/core/scoring/context_and_score_test.gd`

**Interfaces:**
- Consumes: hand `Array[FullCardState]`, active context, definitions, modifiers, and wire-safe selection dictionaries.
- Selection shape: `{ "card_id": String|StringName, "half_index": int, "joker_choices": Array[Dictionary] }`; each choice is `{ "half_index": 0|1, "context": A|B|C, "suit": ONE|TWO|THREE }`.
- Produces: `ScoringTypes.SubmissionResult` with `is_valid: bool`, `error_code: StringName`, `submitted_cards: Array[FullCardState]`, `selected_faces: Array[SelectedCardFace]`, `resolved_cards: Array[Dictionary]`, `normal_result`, `context_result`, and `score_breakdown`.
- Produces: `SubmissionEvaluator.evaluate(hand, selections, active_context, normal_definitions, context_definitions, modifiers) -> ScoringTypes.SubmissionResult`.
- Produces: `ContextHandEvaluator.evaluate_contexts(contexts: PackedInt32Array, definitions) -> ContextHandResult`; existing `evaluate(cards, definitions)` delegates to it.

- [ ] **Step 1: Write failing valid-submission tests**

Cover a selected Joker in each active context, A/ONE and non-default choices, a double-Joker full card with independent choices, rank-zero normal-hand participation, both Joker contexts contributing to context counts, and a mixed ordinary/overridden/Joker submission.

- [ ] **Step 2: Write failing malformed-input and no-mutation tests**

Cover missing choice, duplicate half choice, choice for a normal half, unknown half index, invalid context/suit types and bounds, duplicate cards, missing card, illegal ordinary selected half, and more than six cards. Assert each exact stable error and unchanged cards/selections.

- [ ] **Step 3: Run the focused test and verify failure**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/scoring/submission_evaluator_test.gd`

Expected: FAIL because `SubmissionEvaluator` and `SubmissionResult` do not exist.

- [ ] **Step 4: Implement `SubmissionResult` and context-list evaluation**

`resolved_cards` contains only `{card_id, selected_half_index, halves}`; each half contains `{context, rank, suit, joker}`. Never mutate `HalfCardState` while resolving a Joker choice.

- [ ] **Step 5: Implement `SubmissionEvaluator.evaluate(...)`**

Use one validation pass to canonicalize selections, then evaluate normal/context hands and `ScoreCalculator`. An empty selection is a valid pass with the existing empty-hand results.

- [ ] **Step 6: Run scoring and submission tests**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/scoring`

Expected: all scoring tests PASS.

- [ ] **Step 7: Commit**

```powershell
git add src/core/scoring tests/core/scoring
git commit -m "feat: evaluate staged joker submissions"
```

### Task 3: Authoritative Staging, Locking, Reset, and Reveal

**Files:**
- Modify: `src/core/match/player_state.gd`
- Modify: `src/core/match/match_controller.gd`
- Modify: `src/core/match/match_state.gd`
- Modify: `src/core/match/snapshot_projector.gd`
- Modify: `tests/core/match/hand_play_controller_test.gd`
- Test: `tests/core/match/joker_submission_controller_test.gd`

**Interfaces:**
- Consumes: `SubmissionEvaluator.evaluate(...)` from Task 2.
- Produces: canonical `PlayerState.staged_submission` entries using the selection shape above.
- Produces: `PlayerState.submitted_card_views: Array[Dictionary]` for already-resolved sanitized reveal data.
- Produces: `HAND_REVEALED.payload.cards` from `submitted_card_views`; no persistent half state is changed by Joker choices.

- [ ] **Step 1: Write failing controller tests**

Assert valid Joker staging/locking, host-side default rejection when a client omits choices, invalid replacement preserving the prior draft, double-Joker resolution, and locked-hand immutability.

- [ ] **Step 2: Write failing reset and reveal tests**

Assert replacing a staged Joker card with another card removes its choices, pass clears the staged choice set, round cleanup clears submitted resolved views, and public reveal includes chosen context/suit/rank zero but not origin IDs or a choice history.

- [ ] **Step 3: Run the focused tests and verify failure**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/match/joker_submission_controller_test.gd tests/core/match/hand_play_controller_test.gd`

Expected: FAIL because the controller does not accept or resolve Joker choices.

- [ ] **Step 4: Replace duplicate hand-validation logic with `SubmissionEvaluator`**

`_stage_hand` evaluates without mutation and stores only its canonical selection on success. `_lock_player_hand` re-evaluates the stored draft, copies its cards/faces/resolved views/results/score, and never trusts cached client preview data.

- [ ] **Step 5: Emit sanitized authoritative reveal data and clear it with round state**

Keep the existing event kinds and audiences. Ensure timeout lock uses the same evaluator and cannot preserve an incomplete Joker draft.

- [ ] **Step 6: Run all core match tests**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/match`

Expected: all match tests PASS.

- [ ] **Step 7: Commit**

```powershell
git add src/core/match tests/core/match
git commit -m "feat: resolve joker choices on hand lock"
```

### Task 4: Persistence, Recipient Privacy, and Network Contract

**Files:**
- Modify: `src/core/match/match_state.gd`
- Modify: `src/core/match/snapshot_projector.gd`
- Modify: `tests/core/match/review_hardening_test.gd`
- Modify: `tests/core/match/snapshot_projector_test.gd`
- Modify: `tests/network/lobby_sync_test.gd`
- Modify: `tests/network/network_session_test.gd`

**Interfaces:**
- Consumes: canonical staged choices and submitted resolved views from Task 3.
- Produces: owner-only `private_staging.staged_submission` including Joker choices.
- Produces: public `revealed_submission.cards` only after resolution, using sanitized resolved halves.
- Produces: canonical state round-trip of Joker kind, private choices, and resolved reveal data.

- [ ] **Step 1: Write failing canonical round-trip tests**

Round-trip a Hand Play state with a staged Joker and a Main 2 state with a resolved Joker. Assert restored controller execution produces the same canonical state and result.

- [ ] **Step 2: Write failing role-projection privacy tests**

Assert the owner receives current choices, another active player and spectator cannot find their card ID/choice/context/suit before reveal, and all roles see the same sanitized values after reveal.

- [ ] **Step 3: Run focused persistence/network tests and verify failure**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/match/review_hardening_test.gd tests/core/match/snapshot_projector_test.gd tests/network/lobby_sync_test.gd tests/network/network_session_test.gd`

Expected: FAIL until new canonical and projection fields are implemented.

- [ ] **Step 4: Implement canonical and recipient-safe round trips**

Treat absent `kind`, `joker_choices`, and `submitted_card_views` as legacy normal/empty values when loading; never project `copy_id` or Joker origin in a public reveal.

- [ ] **Step 5: Run the complete Godot and signaling suites**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1`

Run: `npm --prefix service/signaling test`

Expected: Godot and Node suites report zero failures.

- [ ] **Step 6: Commit**

```powershell
git add src/core/match tests/core/match tests/network
git commit -m "feat: sync private joker staging"
```

## Completion Gate

- Every context pile contains 91 halves and recycles its one Joker to the correct origin pile.
- The host accepts only complete, legal per-half Joker assignments and calculates the same preview/result service used by the View.
- Staged choices survive owner resync, never enter persistent card overrides, and never leak before reveal.
- Rank zero, chosen suit, and both chosen contexts affect the appropriate normal/context calculations.
- The full Godot and signaling test suites pass with zero engine errors.

