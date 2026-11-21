# Card-Manipulation Abilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one-half manipulation prototype and no-op runtime deck with fourteen data-driven Hand Manipulation designs, two copies each, with authoritative validation, host RNG, Joker no-ops, persistent overrides, and functional full-card/half-card targeting UI.

**Architecture:** A central `AbilityCatalog` constructs immutable definitions and copy-expanded runtime input. A closed `ManipulationResolver` validates structured choices against the canonical hand and applies operations using the match RNG; `MatchController` retains lifecycle authority and consumes cards only after successful atomic resolution. The View resolves declarative schemas against its owner-private hand, while network snapshots preserve current privacy boundaries.

**Tech Stack:** Godot 4.7.2, typed GDScript, existing custom Godot test runner, existing host-authoritative WebRTC protocol, PowerShell verification scripts.

**Spec:** `docs/superpowers/specs/2026-11-21-card-manipulation-abilities-design.md`

## Global Constraints

- Hand Manipulation remains legal only during Hand Play and before hand lock.
- The fourteen stable IDs and rules text come from the approved spec; default copy count is exactly two, producing twenty-eight physical cards.
- Random rolls are host-authoritative, independent per applicable half, uniform over the written values, and may equal the current value.
- Invalid commands must not mutate cards, consume abilities, clear pending state, or advance RNG.
- Joker selections are legal; inapplicable Joker operations are no-ops and successful activation still consumes the ability.
- Completed effective changes persist until the affected full card leaves the hand; immutable base values never change.
- Fixed-size targeting commits on its final choice; variable targeting requires explicit activation after meeting its minimum.
- Exact targets, transformations, and random results remain owner-private until the existing effective card reveal; only consumed ability IDs become public at Hand Play resolution.
- Keep command kinds and the reliable ordered `game-v1` transport stable; clients submit choices, never results.
- No new third-party dependency.

## Review Focus

- A stale, foreign, duplicate, malformed, or over-limit target must reject atomically without consuming the ability or advancing RNG; Task 2 adds controller and resolver assertions for each class.
- A Joker-only valid selection must consume the card while changing nothing, and a mixed Joker/ordinary card must change only its ordinary half; Tasks 2 and 3 pin both cases.
- A staged submission card must remain targetable without changing its staged active half, and a rejected commit must reopen targeting for correction or cancellation rather than strand an invisible pending ability; Task 5 adds UI coverage.
- Advance/Reverse must read the authoritative direction exactly once at activation, including a reversed field direction, with no later retroactive movement; Task 3 covers both directions and persistence.
- Pending, completed, and modified owner state must survive snapshots/reconnects without leaking target choices to opponents or spectators; Task 4 adds round-trip and projection tests.

---

### Task 0: Commit the approved design and implementation plan

**Files:**
- Create: `docs/superpowers/specs/2026-11-21-card-manipulation-abilities-design.md`
- Create: `docs/superpowers/plans/2026-11-21-card-manipulation-abilities.md`

**Interfaces:**
- Consumes: user-approved design decisions from the current conversation.
- Produces: the committed spec and this executable task plan.

- [ ] **Step 1: Verify the documents**

Run:

```powershell
git diff --check -- docs/superpowers/specs/2026-11-21-card-manipulation-abilities-design.md docs/superpowers/plans/2026-11-21-card-manipulation-abilities.md
```

Expected: exit `0` with no whitespace errors.

- [ ] **Step 2: Commit the approved documents**

```powershell
git add docs/superpowers/specs/2026-11-21-card-manipulation-abilities-design.md docs/superpowers/plans/2026-11-21-card-manipulation-abilities.md
git commit -m "docs: design card manipulation abilities"
```

---

### Task 1: Add definition metadata and the fourteen-card catalogue

**Files:**
- Create: `src/core/abilities/ability_catalog.gd`
- Modify: `src/core/abilities/ability_definition.gd`
- Modify: `src/core/abilities/ability_deck_state.gd`
- Modify: `src/core/match/match_config.gd`
- Test: `tests/core/abilities/ability_catalog_test.gd`
- Test: `tests/core/abilities/ability_state_test.gd`

**Interfaces:**
- Consumes: existing `AbilityDefinition` constructor, timing enum, effect parameters, and choice schema.
- Produces: `AbilityCatalog.manipulation_definitions(copies_per_design: int = 2) -> Array[AbilityDefinition]`; read-only `AbilityDefinition.display_name: String` and `AbilityDefinition.rules_text: String`; serialized metadata in config/deck dictionaries.

- [ ] **Step 1: Write failing catalogue tests**

Add tests named:

- `test_manipulation_catalog_has_fourteen_unique_designs_and_two_copies_each`
- `test_manipulation_catalog_defines_exact_target_shapes_and_rules_text`
- `test_ability_display_metadata_survives_config_and_deck_round_trip`

Assert twenty-eight returned definitions, fourteen stable IDs appearing twice, Hand Manipulation timing for every entry, non-empty display/rules text, and the exact approved schema cardinalities: Context Roulette `1..12` halves, four rank rolls and two cycle cards `1..6` full cards, all other fixed steps exactly one. Assert metadata and schemas remain equal after `MatchConfig` and `AbilityDeckState` serialization round trips.

- [ ] **Step 2: Run the focused tests to verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/ability_catalog_test.gd tests/core/abilities/ability_state_test.gd
```

Expected: FAIL because `AbilityCatalog`, `display_name`, and `rules_text` do not exist.

- [ ] **Step 3: Extend `AbilityDefinition` metadata**

Append optional constructor parameters `definition_display_name: String = ""` and `definition_rules_text: String = ""`; expose copied immutable strings through `display_name` and `rules_text`. Update `AbilityDeckState._serialize_card()`/`load_dict()` and `MatchConfig.to_dict()`/`from_dict()` to retain both fields without changing existing call sites.

- [ ] **Step 4: Implement the catalogue**

Create:

```gdscript
class_name AbilityCatalog
extends RefCounted

static func manipulation_definitions(copies_per_design: int = 2) -> Array[AbilityDefinition]
```

Reject `copies_per_design <= 0` by assertion. Build the fourteen definitions from the spec with `effect_id = &"manipulate_cards"`, closed `operation` parameters, exact printed rules text, and declarative steps using `full_card`, `half_card`, `half_index`, and `suit`. Expand each design exactly `copies_per_design` times.

- [ ] **Step 5: Run the focused tests to verify GREEN**

Run the Step 2 command.

Expected: all catalogue and ability-state tests pass.

- [ ] **Step 6: Commit**

```powershell
git add src/core/abilities/ability_catalog.gd src/core/abilities/ability_definition.gd src/core/abilities/ability_deck_state.gd src/core/match/match_config.gd tests/core/abilities/ability_catalog_test.gd tests/core/abilities/ability_state_test.gd
git commit -m "feat: define card manipulation catalogue"
```

---

### Task 2: Add canonical target validation and deterministic resolution

**Files:**
- Create: `src/core/abilities/manipulation_resolver.gd`
- Modify: `src/core/match/match_controller.gd`
- Test: `tests/core/abilities/manipulation_resolver_test.gd`
- Test: `tests/core/match/manipulation_controller_test.gd`
- Modify: `tests/core/match/hand_play_controller_test.gd`
- Modify: `tests/core/match/review_hardening_test.gd`

**Interfaces:**
- Consumes: Task 1 `effect_parameters.operation`, declarative choice schemas, stable IDs, `FullCardState`, and `HalfCardState.apply_overrides()`.
- Produces: `ManipulationResolver.validate(definition: AbilityDefinition, hand: Array, choices: Dictionary) -> StringName`; `ManipulationResolver.apply(definition: AbilityDefinition, hand: Array, choices: Dictionary, rng: RandomSource, context_direction: int) -> void`; `commit_manipulation` payload shape `{choices: Dictionary}` with all step values stored as arrays.

- [ ] **Step 1: Write failing resolver tests for deterministic operations**

Add tests named:

- `test_context_exchange_swaps_pre_effect_contexts_and_preserves_rank_suit`
- `test_context_convergence_changes_only_the_selected_half`
- `test_suit_imprint_changes_both_ordinary_halves`
- `test_fixed_context_infusions_change_both_ordinary_halves`
- `test_deterministic_operations_skip_jokers_and_valid_noop_still_resolves`

Use cards with existing overrides so assertions prove operations read effective values rather than base values. For exchange, assert both replacements are calculated before either mutation.

- [ ] **Step 2: Write failing validation/controller tests**

Add tests named:

- `test_commit_requires_exact_schema_unique_owned_targets_and_valid_options`
- `test_rejected_manipulation_preserves_cards_ability_pending_state_and_rng`
- `test_success_consumes_ability_clears_pending_and_persists_override`
- `test_cancel_and_timeout_keep_uncommitted_ability`
- `test_locked_or_out_of_phase_manipulation_rejects`

Exercise missing/extra keys, non-array choices, duplicate card IDs, duplicate half references, invalid half indexes, foreign/missing card IDs, zero targets, too many targets, and invalid suit. Capture `state.rng.state_token()`, ability zone/count, pending dictionary, and every effective value before each rejection and assert exact equality afterward.

- [ ] **Step 3: Run the focused tests to verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/manipulation_resolver_test.gd tests/core/match/manipulation_controller_test.gd tests/core/match/hand_play_controller_test.gd tests/core/match/review_hardening_test.gd
```

Expected: FAIL because `ManipulationResolver` and structured manipulation choices do not exist.

- [ ] **Step 4: Implement exact schema and ownership validation**

Implement `ManipulationResolver.validate(...)` with exact-key checking, JSON-safe type checks, fixed/min/max cardinality, uniqueness, canonical hand lookup, half-index bounds, and definition-approved option checks. It must derive legality from the host hand rather than client-provided eligible values.

- [ ] **Step 5: Implement deterministic operations**

Implement `context_exchange`, `context_convergence`, `suit_imprint`, and `set_context` in `ManipulationResolver.apply(...)`. Read all pre-effect values before applying replacements; skip Joker halves according to the spec.

- [ ] **Step 6: Refactor controller commit lifecycle**

Replace the hard-coded `card_id`/`half_index`/`context`/`rank`/`suit` payload with `{choices}`. In `_commit_manipulation`, validate pending/held state and resolver choices, check the authoritative deadline, call the resolver, then consume/discard the ability, append the definition ID, and clear pending state. Remove `_manipulation_choice_allowed()` after all callers migrate.

- [ ] **Step 7: Run focused tests to verify GREEN**

Run the Step 3 command.

Expected: all resolver, manipulation-controller, hand-play, and hardening tests pass.

- [ ] **Step 8: Commit**

```powershell
git add src/core/abilities/manipulation_resolver.gd src/core/match/match_controller.gd tests/core/abilities/manipulation_resolver_test.gd tests/core/match/manipulation_controller_test.gd tests/core/match/hand_play_controller_test.gd tests/core/match/review_hardening_test.gd
git commit -m "feat: validate card manipulation choices"
```

---

### Task 3: Implement random ranks, context roulette, cycle shifts, and Mirror Rank

**Files:**
- Modify: `src/core/abilities/manipulation_resolver.gd`
- Test: `tests/core/abilities/manipulation_resolver_test.gd`
- Test: `tests/core/match/manipulation_controller_test.gd`

**Interfaces:**
- Consumes: Task 2 validated `choices`, canonical hand lookup, and `apply(...)` signature.
- Produces: operation support for `random_context`, `random_rank`, `shift_context`, and `mirror_rank` using authoritative `RandomSource` and `GameTypes.ContextDirection`.

- [ ] **Step 1: Write failing randomization tests**

Add tests named:

- `test_context_roulette_rolls_each_selected_ordinary_half_independently`
- `test_rank_rolls_use_exact_low_high_even_and_odd_sets`
- `test_random_roll_may_equal_the_current_value`
- `test_random_effect_skips_joker_but_changes_ordinary_partner_and_consumes`

Use deterministic seeds or a controlled `RandomSource` sequence to assert every output belongs to the exact written set and at least one pinned case returns its existing value. Assert selected halves roll independently and unselected halves are unchanged.

- [ ] **Step 2: Write failing cycle and mirror tests**

Add tests named:

- `test_ride_and_against_cycle_follow_normal_and_reversed_direction`
- `test_cycle_direction_is_read_once_and_changes_persist_without_retroactivity`
- `test_mirror_rank_maps_all_five_pairs_on_both_halves`
- `test_cycle_and_mirror_allow_complete_joker_noop_and_consume`

For context shifting, assert `posmod(current_context + context_direction * delta, 3)` where `delta` is `+1` for Ride the Cycle and `-1` for Against the Cycle.

- [ ] **Step 3: Run the focused tests to verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/manipulation_resolver_test.gd tests/core/match/manipulation_controller_test.gd
```

Expected: new operation tests fail with unsupported operations or unchanged values.

- [ ] **Step 4: Implement host-random operations**

Add `random_context` and `random_rank` operation branches. Use only the supplied match RNG after validation, roll each selected applicable half independently, include current values in the candidate arrays, and preserve non-target attributes.

- [ ] **Step 5: Implement cycle and mirror operations**

Add `shift_context` with definition parameter `relative_direction` (`1` or `-1`) and `mirror_rank` using `11 - effective_rank`. Skip Jokers and preserve all unrelated attributes.

- [ ] **Step 6: Run the focused tests to verify GREEN**

Run the Step 3 command.

Expected: all manipulation resolver/controller tests pass.

- [ ] **Step 7: Commit**

```powershell
git add src/core/abilities/manipulation_resolver.gd tests/core/abilities/manipulation_resolver_test.gd tests/core/match/manipulation_controller_test.gd
git commit -m "feat: resolve manipulation ability effects"
```

---

### Task 4: Integrate the real deck, presentation metadata, privacy, and reconnect state

**Files:**
- Modify: `src/view/app/runtime_game_session.gd`
- Modify: `src/core/match/snapshot_projector.gd`
- Modify: `tests/view/runtime_game_session_test.gd`
- Modify: `tests/core/match/snapshot_projector_test.gd`
- Modify: `tests/core/match/review_hardening_test.gd`
- Modify: `tests/network/network_session_test.gd`
- Modify: `docs/superpowers/specs/2026-11-15-shift-card-game-design.md`

**Interfaces:**
- Consumes: Task 1 catalogue/metadata and Tasks 2–3 authoritative completed/pending behavior.
- Produces: runtime `MatchConfig` with twenty-eight real manipulation definitions; `ability_catalog` entries containing `label`, `rules_text`, `timing`, and schema; privacy-safe owner/reconnect snapshots.

- [ ] **Step 1: Write failing runtime and serialization tests**

Add or extend tests named:

- `test_runtime_config_uses_twenty_eight_real_manipulation_cards`
- `test_ability_catalog_projects_name_rules_text_timing_and_schema`
- `test_pending_completed_and_modified_manipulation_state_round_trips`

Assert the runtime config has fourteen IDs twice and no `placeholder_ability_*`; catalog text matches definitions; pending copy ID, completed IDs, effective overrides, and RNG survive canonical round trip.

- [ ] **Step 2: Write failing privacy tests**

Add or extend tests named:

- `test_manipulation_targets_and_random_results_are_owner_private`
- `test_reconnect_owner_receives_modified_values_without_public_target_history`

Project the same state to owner, opponent, and spectator. Assert only the owner sees effective private hand state and pending copy ID; no projection or public event contains choice keys, target card IDs, original-to-effective history, or random-roll history. Assert Hand Play resolution still exposes only consumed ability definition IDs plus the normal revealed effective faces.

- [ ] **Step 3: Run focused tests to verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/runtime_game_session_test.gd tests/core/match/snapshot_projector_test.gd tests/core/match/review_hardening_test.gd tests/network/network_session_test.gd
```

Expected: FAIL because runtime still builds no-op placeholders and display metadata is not projected.

- [ ] **Step 4: Replace the runtime placeholder deck**

Preload `AbilityCatalog` in `runtime_game_session.gd`, replace `_placeholder_abilities()` with `_default_abilities()` returning `AbilityCatalog.manipulation_definitions(2)`, and keep placeholder normal/context hand definitions unchanged.

- [ ] **Step 5: Project metadata without leaking choices**

Update `_ability_catalog()` to use serialized `display_name` and `rules_text`. Keep `SnapshotProjector._private_abilities()` limited to physical copy ID, definition ID, and phase legality. Add `completed_manipulation_ids` beside `pending_manipulation` in owner-only `private_staging`; private hand and all staging history remain absent from opponent and spectator projections.

- [ ] **Step 6: Update the main design status**

In the shared ability-deck and unresolved-content sections, state that the fourteen-card Hand Manipulation catalogue is finalized at two initial copies per design, while the other three category catalogues and later copy-count balance remain unresolved. Link the detailed manipulation spec.

- [ ] **Step 7: Run focused tests to verify GREEN**

Run the Step 3 command.

Expected: all runtime, snapshot, hardening, and network privacy tests pass.

- [ ] **Step 8: Commit**

```powershell
git add src/view/app/runtime_game_session.gd src/core/match/snapshot_projector.gd tests/view/runtime_game_session_test.gd tests/core/match/snapshot_projector_test.gd tests/core/match/review_hardening_test.gd tests/network/network_session_test.gd docs/superpowers/specs/2026-11-15-shift-card-game-design.md
git commit -m "feat: use the manipulation ability deck"
```

---

### Task 5: Implement full-card, half-card, fixed, and variable targeting UI

**Files:**
- Modify: `src/view/match/targeting_overlay.gd`
- Modify: `src/view/match/targeting_overlay.tscn`
- Modify: `src/view/match/ability_panel.gd`
- Modify: `src/view/match/card_widget.gd`
- Modify: `src/view/match/phase_controls.gd`
- Modify: `src/view/match/match_screen.gd`
- Modify: `tests/view/ability_and_privacy_test.gd`
- Modify: `tests/view/phase_controls_test.gd`
- Modify: `tests/view/match_screen_test.gd`
- Modify: `src/view/app/ui_fixture.gd`

**Interfaces:**
- Consumes: Task 1 catalog schemas/metadata and Task 2 commit payload `{choices}`.
- Produces: `TargetingOverlay.begin(workflow: Dictionary, private_hand: Array = [])`; target values for full cards as card-ID strings and halves as `{card_id, half_index}` dictionaries; `PhaseControls.set_targeting(kind: StringName, eligible: Array, selected: Array = [])`; `CardWidget.half_target_requested(card_id: StringName, half_index: int)`.

- [ ] **Step 1: Write failing overlay behavior tests**

Extend `ability_and_privacy_test.gd` with:

- `test_fixed_targeting_auto_commits_after_final_required_choice`
- `test_variable_targeting_toggles_one_to_max_and_requires_activate`
- `test_targeting_cancel_before_activation_does_not_commit`
- `test_ability_drawer_displays_name_and_rules_text`
- `test_rejected_manipulation_commit_restores_targeting_for_retry_or_cancel`

Assert fixed one-card Mirror Rank commits on its card click; Suit Imprint advances from its card click to suit and commits on suit choice; variable selection can add/remove targets, rejects a seventh full card or thirteenth half, enables Activate at one, and does not commit merely because the minimum is reached. After an authoritative commit rejection, assert the prior workflow reopens with its choices recoverable and Cancel can clear the still-pending ability.

- [ ] **Step 2: Write failing card/half interaction tests**

Extend phase/match tests with:

- `test_full_card_targeting_includes_hand_row_and_submission_shelf`
- `test_half_targeting_selects_individual_halves_without_changing_staged_half_choice`
- `test_targeting_marks_selected_halves_and_dims_non_targets`
- `test_commit_payload_contains_only_structured_choices`

Stage at least one card before targeting and assert both shelf and hand cards remain eligible. Click each visual half separately and assert distinct `{card_id, half_index}` values while the staged submission selection stays unchanged.

- [ ] **Step 3: Run UI tests to verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/ability_and_privacy_test.gd tests/view/phase_controls_test.gd tests/view/match_screen_test.gd
```

Expected: FAIL because the overlay only supports fixed counts/card IDs and the commit adapter emits hard-coded effective values.

- [ ] **Step 4: Generalize `TargetingOverlay`**

Resolve live eligible card and half values from `private_hand`. Support `count` or `min_count`/`max_count`, target toggling for variable steps, maximum caps, fixed-step auto-advance/auto-commit, and explicit Activate for any variable workflow. Retain Cancel and selection-change signals.

- [ ] **Step 5: Add half-specific card interaction**

Add `half_target_requested`, a targeting kind, and per-half eligible/selected visual state to `CardWidget`. In targeting mode, clicking a half emits the half target rather than staging/changing the submission; ordinary behavior resumes when targeting closes.

- [ ] **Step 6: Wire phase controls and match screen**

Pass private hand data into the overlay, route full-card and half-card target values, display definition name/rules text in `AbilityPanel`, and emit `commit_manipulation` with only `{choices: choices.duplicate(true)}`. Keep the active ability/workflow until commit acceptance; on rejection, reopen it for correction or cancellation. Preserve stage-before-target, phase-change cancellation, and input-lock behavior.

- [ ] **Step 7: Update the UI fixture**

Replace its manipulation fixture entry with one real schema/metadata shape and retain representative entries for the other timing categories.

- [ ] **Step 8: Run UI tests to verify GREEN**

Run the Step 3 command, then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_ui.ps1
```

Expected: all focused and full UI tests pass; the headless UI fixture exits without engine or script errors.

- [ ] **Step 9: Commit**

```powershell
git add src/view/match/targeting_overlay.gd src/view/match/targeting_overlay.tscn src/view/match/ability_panel.gd src/view/match/card_widget.gd src/view/match/phase_controls.gd src/view/match/match_screen.gd src/view/app/ui_fixture.gd tests/view/ability_and_privacy_test.gd tests/view/phase_controls_test.gd tests/view/match_screen_test.gd
git commit -m "feat: add manipulation ability targeting UI"
```

---

### Task 6: Verify the complete model, controller, UI, and network integration

**Files:**
- Modify only if verification exposes a regression in an in-scope file.

**Interfaces:**
- Consumes: Tasks 1–5 complete implementation.
- Produces: release-quality verification evidence for the complete manipulation category.

- [ ] **Step 1: Run core and network Godot tests**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

Expected: all discovered tests pass with zero `SCRIPT ERROR` or `ERROR:` lines.

- [ ] **Step 2: Run UI tests**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_ui.ps1
```

Expected: all View tests pass and the headless fixture exits `0`.

- [ ] **Step 3: Run signaling tests**

```powershell
Push-Location service/signaling
npm test
Pop-Location
```

Expected: every Node signaling test passes.

- [ ] **Step 4: Run the multi-process direct-WebRTC fixture**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_network.ps1
```

Expected: host, three remote players, spectator, command/event exchange, and relaunch reconnect all pass and shut down cleanly.

- [ ] **Step 5: Check repository hygiene**

```powershell
git diff --check
rg -n "placeholder_ability_|joker_manipulation_not_allowed|manipulate_half" src tests
git status --short
```

Expected: no diff errors; no active runtime placeholder deck or obsolete single-half manipulation path; status contains only intended changes, or is clean after the task commits.

- [ ] **Step 6: Commit any verification-only correction**

Only if Steps 1–5 required an in-scope correction:

```powershell
git add <corrected-files>
git commit -m "fix: harden manipulation ability integration"
```

If no correction was needed, do not create an empty commit.
