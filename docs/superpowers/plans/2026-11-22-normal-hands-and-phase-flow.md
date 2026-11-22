# Normal Hands and Phase Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved 19-entry normal-hand catalogue and correct opening-turn, automatic replenishment readiness, and manual end-discard behavior.

**Architecture:** Add a focused production `NormalHandCatalog` beside the existing context catalogue and keep `NormalHandEvaluator` data-driven. Add an explicit controller transition that begins round one in Main 1 without executing Start effects; subsequent rounds retain Start for replenishment and two-card ability draws. Make Start readiness derive from replenishment need, and test end discards through the authoritative runtime snapshot/command path before changing the already-passing isolated controls.

**Tech Stack:** Godot 4.7.2, typed GDScript, the repository's custom headless test runner, exact `Rational` multipliers.

**Spec:** `docs/superpowers/specs/2026-11-22-normal-hand-catalog-balance-design.md`

## Global Constraints

- Normal hands use ranks 1–10, Mountain/Cloud/Sea suits, and submissions of one through six cards.
- Exactly one High Card/Family/Group/Straight component contributes; Flush is independently additive.
- Straights and Flushes begin at three cards and straights do not wrap between 10 and 1.
- Joker rank zero is a legal High Card fallback, is excluded from Family/Group/Straight rules, and may join Flush through its staged suit.
- Initial hands remain six full cards plus two abilities; round one begins directly in Main 1 with no replenishment and no two-card Start draw.
- Starting with round two, Start replenishes missing full cards and draws two abilities per active player.
- A player needing zero replenishment is automatically Ready during Start.
- Players above three abilities at End choose the exact excess; timeout remains the only random-discard path.
- Preserve host authority, deterministic serialization, hidden information, and existing reconnect behavior.

## Review Focus

- A Joker-only submission must remain valid High Card zero without allowing two Jokers to become a Pair.
- An all-same-suit submission must add exactly one size-matched Flush component alongside exactly one rank component.
- Starting the match must not emit replenishment or ability-draw events and must not advance Rise.
- A later Start with all hands full must automatically draw abilities and advance to Main 1 without waiting for commands.
- End must remain open when any active player has excess abilities, expose the exact private choices, reject wrong counts, and randomize only on timeout.

---

### Task 1: Production normal-hand catalogue

**Files:**
- Create: `src/core/scoring/normal_hand_catalog.gd`
- Create: `tests/core/scoring/normal_hand_catalog_test.gd`

**Interfaces:**
- Consumes: `NormalHandDefinition.new(...)`, `Rational.new(...)`, and `ScoringCategories`.
- Produces: `NormalHandCatalog.definitions() -> Array[NormalHandDefinition]` containing the approved 19 exact definitions.

- [ ] **Step 1: Write the failing catalogue test**

Assert 19 unique IDs, exact priorities/multipliers from the approved table, correct subset sizes, rules, group parameters, broad categories, and rank/suit component groups.

- [ ] **Step 2: Run the catalogue test and verify it fails because `NormalHandCatalog` does not exist**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/scoring/normal_hand_catalog_test.gd`

- [ ] **Step 3: Implement `NormalHandCatalog.definitions()`**

Return High Card; Family sizes 2–6; Groups `2+2`, `3+2`, `2+2+2`, `4+2`, and `3+3`; Straight sizes 3–6; and Flush sizes 3–6 with the approved exact rational values.

- [ ] **Step 4: Run the catalogue test and verify it passes**

- [ ] **Step 5: Commit**

```text
git add src/core/scoring/normal_hand_catalog.gd tests/core/scoring/normal_hand_catalog_test.gd
git commit -m "feat: add balanced normal hand catalog"
```

### Task 2: Joker-safe evaluation and complete tie-breaking

**Files:**
- Modify: `src/core/scoring/normal_hand_evaluator.gd`
- Modify: `tests/core/scoring/normal_hand_evaluator_test.gd`

**Interfaces:**
- Consumes: the existing `evaluate(faces, definitions)` API and catalog definitions from Task 1.
- Produces: rank-zero filtering for Family/Group/Straight and full descending-rank Flush tie vectors.

- [ ] **Step 1: Add failing evaluator tests**

Cover every approved exact shape, contained-subset priority, `4+2` versus contained Full House/Four of a Kind, Joker High Card zero, repeated Jokers not forming a Family/Group, Joker exclusion from Straights, Joker suit participation in Flush, and lexicographic Flush tie-breaking.

- [ ] **Step 2: Run the evaluator tests and confirm the Joker/group and Flush tie tests fail**

- [ ] **Step 3: Update evaluator matching and tie-breaking**

Keep rank zero available to `high_card`; filter it from grouped-rank counts and straight candidates; return all descending ranks for Flush tie-breaking.

- [ ] **Step 4: Run the evaluator and catalogue tests and verify they pass**

- [ ] **Step 5: Commit**

```text
git add src/core/scoring/normal_hand_evaluator.gd tests/core/scoring/normal_hand_evaluator_test.gd
git commit -m "fix: evaluate complete normal hand rules"
```

### Task 3: Runtime catalogue integration

**Files:**
- Modify: `src/view/app/runtime_game_session.gd`
- Modify: `tests/view/runtime_game_session_test.gd`
- Modify: `tests/core/match/match_setup_test.gd`

**Interfaces:**
- Consumes: `NormalHandCatalog.definitions()` from Task 1.
- Produces: every hosted match carries the production normal-hand catalogue in authoritative `MatchConfig` data.

- [ ] **Step 1: Add failing runtime assertions**

Assert 19 normal definitions, representative IDs/priorities/fractions, all five broad categories, and absence of placeholder all-`1/1` data.

- [ ] **Step 2: Run the runtime tests and verify the placeholder assertions fail**

- [ ] **Step 3: Replace `_placeholder_normal_hands()` with `NormalHandCatalog.definitions()`**

Preload the catalogue and remove the placeholder builder.

- [ ] **Step 4: Run runtime/config serialization tests and verify they pass**

- [ ] **Step 5: Commit**

```text
git add src/view/app/runtime_game_session.gd tests/view/runtime_game_session_test.gd tests/core/match/match_setup_test.gd
git commit -m "feat: use production normal hands at runtime"
```

### Task 4: Skip round-one Start effects

**Files:**
- Modify: `src/core/match/match_controller.gd`
- Modify: `src/view/app/runtime_game_session.gd`
- Modify: `tests/core/match/start_phase_controller_test.gd`
- Modify: `tests/view/runtime_game_session_test.gd`

**Interfaces:**
- Produces: `MatchController.begin_match(now_msec: int) -> Array[DomainEvent]`, the only transition from the open lobby into round-one Main 1.
- Consumes: runtime host start action and existing phase/state clock fields.

- [ ] **Step 1: Add failing controller and runtime tests**

Assert `begin_match` transitions round one from Start to Main 1, leaves each player at six cards/two abilities, leaves Rise active, emits only the Main 1 phase change, starts the Main 1 deadline, and rejects repeated starts. Assert `RuntimeGameSession.start_match()` publishes that authoritative transition and a round-one Start command is no longer accepted.

- [ ] **Step 2: Run the focused tests and confirm current code remains in Start**

- [ ] **Step 3: Implement `begin_match` and route `RuntimeGameSession.start_match()` through it**

Set `config.match_started`, mark round-one Start setup/draw as consumed, clear readiness and Start requests, enter Main 1, initialize its hard deadline, and publish the returned event batch.

- [ ] **Step 4: Run focused controller/runtime tests and verify they pass**

- [ ] **Step 5: Commit**

```text
git add src/core/match/match_controller.gd src/view/app/runtime_game_session.gd tests/core/match/start_phase_controller_test.gd tests/view/runtime_game_session_test.gd
git commit -m "fix: begin opening round in main one"
```

### Task 5: Automatically ready players with no replenishment

**Files:**
- Modify: `src/core/match/match_controller.gd`
- Modify: `tests/core/match/start_phase_controller_test.gd`
- Modify: `tests/core/match/player_lifecycle_test.gd`

**Interfaces:**
- Consumes: `_prepare_start_phase()`, `_all_active_ready()`, and `_finish_start(now_msec)`.
- Produces: readiness derived from `replenishment_needed == 0` and automatic Start completion when every active player is already ready.

- [ ] **Step 1: Add failing Start tests**

Cover mixed hands (full-hand player auto-ready, missing-card player not ready), all-full hands (first tick completes Start, draws exactly two abilities, enters Main 1), late-player activation, and a player who replenishes then causes all-ready completion.

- [ ] **Step 2: Run the Start/lifecycle tests and confirm current readiness is false for full hands**

- [ ] **Step 3: Set automatic readiness during Start preparation and finish on all-ready tick**

Do not auto-ready players who still owe any full cards. Preserve random request completion at timeout or explicit Ready.

- [ ] **Step 4: Run focused tests and verify they pass**

- [ ] **Step 5: Commit**

```text
git add src/core/match/match_controller.gd tests/core/match/start_phase_controller_test.gd tests/core/match/player_lifecycle_test.gd
git commit -m "fix: skip unnecessary replenishment waits"
```

### Task 6: Prove and harden player-chosen End discards

**Files:**
- Modify: `src/core/match/snapshot_projector.gd`
- Modify: `src/view/match/phase_controls.gd`
- Modify: `tests/core/match/end_phase_controller_test.gd`
- Modify: `tests/core/match/snapshot_projector_test.gd`
- Modify: `tests/view/phase_controls_test.gd`
- Modify: `tests/view/runtime_game_session_test.gd`

**Interfaces:**
- Produces: owner-private `required_ability_discards: int` in authoritative snapshots; End controls render and validate against that value; `choose_ability_discards` remains the authoritative command.

- [ ] **Step 1: Reproduce the reported behavior through the runtime path**

Add a failing end-to-end test that gives the host five abilities, resolves Main 2, observes an End snapshot containing five private abilities and `required_ability_discards == 2`, submits two chosen copy IDs, and observes the chosen copies removed and the round advancing. Also assert an incorrect count is rejected without mutation.

- [ ] **Step 2: Run the runtime, snapshot, controller, and UI tests to identify the first broken boundary**

If the new end-to-end test already passes, retain it as a regression and limit code changes to authoritative discard-count projection/UI use; do not rewrite the passing discard resolver.

- [ ] **Step 3: Project and consume the authoritative discard requirement**

Expose the count only to the owning active player. Render all held ability choices at End, require exactly that count, preserve the player's selected copy IDs, and keep timeout as the only random path.

- [ ] **Step 4: Run all End/runtime/UI tests and verify chosen cards—not random cards—are discarded on confirmation**

- [ ] **Step 5: Commit**

```text
git add src/core/match/snapshot_projector.gd src/view/match/phase_controls.gd tests/core/match/end_phase_controller_test.gd tests/core/match/snapshot_projector_test.gd tests/view/phase_controls_test.gd tests/view/runtime_game_session_test.gd
git commit -m "fix: require player-selected end discards"
```

### Task 7: Documentation and full verification

**Files:**
- Modify: `docs/superpowers/specs/2026-11-15-shift-card-game-design.md`
- Modify: `docs/art-ui-audio-asset-checklist.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: final implemented catalog and phase rules.
- Produces: current player/developer documentation without placeholder-normal-hand language.

- [ ] **Step 1: Update the rules and asset guidance**

Document the 19 hands, additive Flush behavior, round-one Main 1 entry, later Start draw/replenishment, automatic no-replenishment readiness, and manual End discards with timeout fallback.

- [ ] **Step 2: Run focused tests**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/scoring tests/core/match/start_phase_controller_test.gd tests/core/match/end_phase_controller_test.gd tests/core/match/snapshot_projector_test.gd tests/view/phase_controls_test.gd tests/view/runtime_game_session_test.gd`

- [ ] **Step 3: Run the complete suite**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1`

Expected: every test passes with zero `SCRIPT ERROR`/`ERROR` lines.

- [ ] **Step 4: Run network regression verification**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_network.ps1`

Expected: host, remote players, spectator, reconnect, command transport, and controlled shutdown all pass.

- [ ] **Step 5: Review the final diff for private-data leakage and placeholder references**

- [ ] **Step 6: Commit**

```text
git add README.md docs/superpowers/specs/2026-11-15-shift-card-game-design.md docs/art-ui-audio-asset-checklist.md
git commit -m "docs: finalize hands and round phase rules"
```

