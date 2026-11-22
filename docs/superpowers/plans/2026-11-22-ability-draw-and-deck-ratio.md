# Ability Draw and Deck Ratio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the provisional ability recipe with the approved 90-card `15:6:4:5` category ratio and draw two ability cards at every turn start while retaining the two-card opening hand and three-card end limit.

**Architecture:** Keep physical copy counts in `AbilityCatalog.provisional_deck_recipe()` so effects remain independent from balance data. Change `AbilityDeckState.start_draw_count` from one to two; existing start-phase, discard, recycling, serialization, late-entry, and network snapshot paths consume that value without introducing a second draw rule.

**Tech Stack:** Godot 4.7.2, typed GDScript, existing custom Godot test runner.

**Spec:** `docs/superpowers/specs/2026-11-22-ability-draw-and-deck-ratio-design.md`

## Global Constraints

- Exact category counts: 45 manipulation, 18 buff/nerf, 12 sabotage, 15 field; 90 total.
- Opening ability hand remains two cards.
- Start-of-turn ability draw becomes two cards.
- End-of-turn ability hand limit remains three cards, with player choice or timeout random discard.
- All 54 ability definitions remain represented in the physical deck.
- Existing shared used-pile recycling, serialization, reconnect, and late-player activation behavior remains authoritative.
- Do not modify the user's concurrent UI/display work.

## Review Focus

- Recipe drift: tests must classify every physical copy by timing and assert all four exact category totals plus 90 overall.
- Per-design drift: tests must pin the named fourth/second copies and ensure every other definition retains its specified base count.
- Draw-rule drift: tests must distinguish the unchanged two-card opening hand from the new two-card turn-start draw.
- Exhaustion: drawing two must still short-draw safely rather than fabricate held or active-field cards.
- Persistence: `start_draw_count = 2` must survive `AbilityDeckState.to_dict()` and `load_dict()` for reconnect/state restoration.

---

### Task 1: Exact 90-card ability recipe

**Files:**
- Modify: `src/core/abilities/ability_catalog.gd`
- Modify: `tests/core/abilities/ability_catalog_test.gd`
- Modify: `tests/view/runtime_game_session_test.gd`

**Interfaces:**
- Consumes: `AbilityCatalog.manipulation_designs()`, `hand_shape_designs()`, `sabotage_designs()`, `field_designs()`.
- Produces: `AbilityCatalog.provisional_deck_recipe() -> Dictionary` with exact per-definition integer counts; `build_deck(recipe) -> Array[AbilityDefinition]` remains unchanged.

- [ ] **Step 1: Write failing catalogue tests for exact category totals**

Update `test_definition_data_is_independent_from_physical_copy_recipe` to classify `AbilityCatalog.build_deck(recipe)` by `AbilityDefinition.Timing` and assert 45 manipulation, 18 hand-shape, 12 sabotage, 15 field, 90 total, and 54 recipe entries.

- [ ] **Step 2: Write failing per-design count assertions**

Assert manipulation count four for `context_roulette`, `ride_the_cycle`, and `against_the_cycle`, three for every other manipulation; count two for `high_card_buff`, `high_card_nerf`, `suit_scramble`, `rank_scramble`, and `context_scramble`; count one for every other buff/nerf and sabotage; count one for every field.

- [ ] **Step 3: Run focused tests and verify the old 77-card recipe fails**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/ability_catalog_test.gd tests/view/runtime_game_session_test.gd`

Expected: FAIL on total and category/copy assertions.

- [ ] **Step 4: Implement the exact recipe in `provisional_deck_recipe()`**

Build category base counts first, then overwrite only the eight named extra-copy definitions. Keep recipe data separate from `AbilityDefinition.effect_parameters`.

- [ ] **Step 5: Update live runtime recipe assertions and rerun focused tests**

Update `test_runtime_config_uses_recipe_with_all_four_ability_categories` to assert 90 definitions, 54 unique definitions, and the same category totals. Rerun the Task 1 command; expected: PASS.

- [ ] **Step 6: Commit**

Commit message: `feat: rebalance shared ability deck`

### Task 2: Two-card turn-start draw

**Files:**
- Modify: `src/core/abilities/ability_deck_state.gd`
- Modify: `tests/core/abilities/ability_state_test.gd`
- Modify: `tests/core/match/start_phase_controller_test.gd`
- Modify: `tests/core/match/player_lifecycle_test.gd`

**Interfaces:**
- Consumes: `AbilityDeckState.draw(player_id, count, rng)` and its existing short-draw/recycle behavior.
- Produces: `AbilityDeckState.start_draw_count == 2`; `starting_hand_size == 2` and `end_hand_limit == 3` remain unchanged.

- [ ] **Step 1: Write failing deck metadata and round-trip tests**

Update `test_deck_exposes_setup_draw_and_end_hand_limit_data` to assert `2, 2, 3`. Add a round-trip assertion that a deck serialized through `to_dict()`/`load_dict()` restores `start_draw_count == 2`.

- [ ] **Step 2: Write failing start-phase controller assertion**

In the timeout/start draw test, record each active player's ability-hand count before `_finish_start`, then assert it increases by two when enough cards are available and that two owner-private `ABILITY_DRAWN` events are emitted per player.

- [ ] **Step 3: Pin unchanged late-entry opening behavior**

Ensure lifecycle tests continue to assert that a newly activated late player receives exactly two opening ability cards, not four; retain the existing short-draw test for deck exhaustion.

- [ ] **Step 4: Run focused tests and verify the one-card turn draw fails**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/ability_state_test.gd tests/core/match/start_phase_controller_test.gd tests/core/match/player_lifecycle_test.gd`

Expected: FAIL on `start_draw_count` and turn-start draw/event counts.

- [ ] **Step 5: Change `AbilityDeckState.start_draw_count` to two**

Modify only the default metadata value. Existing controller calls must continue using `state.ability_deck.start_draw_count` rather than a duplicated literal.

- [ ] **Step 6: Rerun focused tests**

Run the Task 2 command; expected: PASS, including unchanged opening hand, discard limit, short draw, and serialization.

- [ ] **Step 7: Commit**

Commit message: `feat: draw two abilities each turn`

### Task 3: End-of-turn limit and full-system verification

**Files:**
- Modify only if assertions need correction: `tests/core/match/end_phase_controller_test.gd`
- Modify: `docs/superpowers/specs/2026-11-22-ability-draw-and-deck-ratio-design.md`

**Interfaces:**
- Consumes: the 90-card recipe and `start_draw_count == 2` from Tasks 1–2.
- Produces: verified end-to-end match configuration with no change to the three-card limit.

- [ ] **Step 1: Strengthen end-phase limit assertions if necessary**

Confirm both explicit and timeout discard tests begin above three cards and end at exactly three. Do not change controller behavior unless a failing test exposes a regression.

- [ ] **Step 2: Run the complete core and network suites**

Run all `*_test.gd` files under `tests/core` and `tests/network` through `scripts/test.ps1`.

Expected: all pass; no UI/display files are included in the change.

- [ ] **Step 3: Run the real direct-WebRTC integration fixture**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test_network.ps1 -GodotBin $env:SHIFT_GODOT_BIN -TimeoutSeconds 120`

Expected: host + three remote players + spectator connect, command/event flow succeeds, and a relaunched player reclaims its seat.

- [ ] **Step 4: Mark the design implemented and inspect the final diff**

Change the spec status to `Implemented`. Run `git diff --check` and verify no user-owned UI/display files are staged.

- [ ] **Step 5: Commit and push main**

Commit message: `test: verify ability draw rebalance`

Push the completed commits to `origin/main` using the configured SSH remote.

## Self-Review Result

- **Spec coverage:** Exact ratio, per-design distribution, opening hand, turn draw, end limit, recycling, late entry, serialization, runtime configuration, and network verification all have an owning task.
- **Step scan:** Each task follows failing test, implementation, passing verification, and scoped commit boundaries.
- **Type consistency:** The plan changes only existing `Dictionary`, `Array[AbilityDefinition]`, and integer metadata interfaces.
- **Review focus coverage:** Category totals, named extras, opening-versus-turn draw, short draw, and round-trip persistence are explicitly tested.
- **Proportion:** The plan pins decisions and assertions without transcribing implementation bodies.
