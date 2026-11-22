# Hand Buff/Nerf Abilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize scoring into additive multiplier factors and implement the sixteen data-driven Hand Buff/Nerf abilities.

**Architecture:** Exact hand definitions produce authoritative multiplier components instead of one opaque multiplier. The score calculator sums components and matching signed modifiers inside the card-hand, context-hand, and field factors, floors each factor at `1`, multiplies them by base value, and ceilings once. Public abilities add immutable factor modifiers; ability definitions remain separate from a tunable deck recipe.

**Tech Stack:** Godot 4.7.2, typed GDScript, exact `Rational` arithmetic, host-authoritative controller/events/snapshots, headless Godot tests, Node signaling tests, native WebRTC fixture.

**Spec:** `docs/superpowers/specs/2026-11-22-hand-buff-nerf-abilities-design.md`

## Global Constraints

- Score formula: `ceil(base × max(1, card-hand factor) × max(1, context-hand factor) × max(1, field factor))`.
- Base value is not floored; a pass remains score `0`.
- A valid non-pass hand has exactly one rank component: High Card, Straight, Family, or Group.
- Flush is an optional orthogonal component and may stack with the selected rank component.
- The selected context definition has exactly one category: Single Context, Two Context, or Three Context.
- Each physical buff/nerf contributes at most once per submitted hand; separate physical cards stack additively.
- Card-hand, context-hand, and field factors are floored independently after all additions and subtractions.
- Hand Buff/Nerf abilities are public, target self or another active player, work in Main 1 and Main 2, and expire after End scoring.
- Main 2 recalculates provisional score without reclassifying locked hand results.
- `+3` and `-3` are placeholder deltas; exact values and physical copy counts remain data.
- Clients never author factor IDs, categories, deltas, applicability, or score results.
- Exact rational arithmetic performs no intermediate rounding and one final ceiling.
- Mountain King Regular is the general UI font and ships with CC BY 4.0 attribution; card ranks use the supplied number artwork instead of font glyphs.

## Review Focus

- A Flush definition must match the entire submitted hand, never a same-suit subset hidden among off-suit submitted cards; Task 2 pins this.
- A Full House or Three Pairs must receive one Group component and one Group modifier hit, not contained Family hits; Tasks 2 and 3 pin this.
- A Main 1 modifier whose target later passes or plays a nonmatching hand must be consumed but contribute zero; Task 5 pins this.
- Opposing modifiers that push a factor below zero must floor that factor to exactly `1` without changing other factors; Task 3 pins this.
- A forged player target, category, delta, or claimed applicability must reject without consuming the card, clearing Ready state, moving the deadline, or changing the score; Task 5 pins this.

---

### Task 0: Commit the approved design and implementation plan

**Files:**
- Add: `docs/superpowers/specs/2026-11-22-hand-buff-nerf-abilities-design.md`
- Add: `docs/superpowers/plans/2026-11-22-hand-buff-nerf-abilities.md`

**Interfaces:**
- Consumes: the approved conversation decisions.
- Produces: the authoritative spec and task interfaces used by Tasks 1–7.

- [ ] **Step 1: Verify document status and repository hygiene**

Assert the spec says `Status: Approved`, names all sixteen designs, excludes physical copy counts from effect definitions, and contains no trailing whitespace.

Run:

```powershell
git diff --check -- docs/superpowers/specs/2026-11-22-hand-buff-nerf-abilities-design.md docs/superpowers/plans/2026-11-22-hand-buff-nerf-abilities.md
```

Expected: no output.

- [ ] **Step 2: Commit**

```powershell
git add docs/superpowers/specs/2026-11-22-hand-buff-nerf-abilities-design.md docs/superpowers/plans/2026-11-22-hand-buff-nerf-abilities.md
git commit -m "docs: design hand buff and nerf abilities"
```

---

### Task 1: Add factor categories, scoring components, and definition metadata

**Files:**
- Create: `src/core/scoring/scoring_categories.gd`
- Modify: `src/core/scoring/scoring_types.gd`
- Modify: `src/core/scoring/normal_hand_definition.gd`
- Modify: `src/core/scoring/context_hand_definition.gd`
- Modify: `src/core/match/match_config.gd`
- Test: `tests/core/scoring/scoring_definition_test.gd`
- Modify: `tests/core/match/match_setup_test.gd`

**Interfaces:**
- Consumes: existing `Rational`, `NormalHandDefinition`, `ContextHandDefinition`, and `MatchConfig` round trips.
- Produces: `ScoringCategories` constants/validators; `ScoringTypes.MultiplierComponent`; `ScoringTypes.FactorModifier`; categorized hand definitions serialized by `MatchConfig`.

- [ ] **Step 1: Write failing category and definition tests**

Create tests named:

- `test_scoring_category_vocabulary_accepts_only_known_factor_category_pairs`
- `test_normal_definition_retains_component_group_category_and_rule_parameters`
- `test_context_definition_retains_broad_category`
- `test_scoring_definition_metadata_survives_config_round_trip`

Assert the closed IDs are:

- Factors: `card_hand`, `context_hand`, `field`
- Normal categories: `high_card`, `straight`, `family`, `group`, `flush`
- Context categories: `single_context`, `two_context`, `three_context`
- Normal groups: `rank`, `suit`

- [ ] **Step 2: Run the tests to verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/scoring/scoring_definition_test.gd tests/core/match/match_setup_test.gd
```

Expected: FAIL because categorized definitions and component/modifier types do not exist.

- [ ] **Step 3: Implement the scoring vocabulary and immutable value types**

In `scoring_categories.gd`, expose constants plus:

```gdscript
static func category_allowed(factor_id: StringName, category_id: StringName) -> bool
static func component_group_allowed(group_id: StringName) -> bool
```

In `scoring_types.gd`, add the new value types alongside the legacy `ScoreModifier`; Task 3 removes the legacy type only after every production caller and fixture has migrated:

```gdscript
class MultiplierComponent extends RefCounted
class FactorModifier extends RefCounted
```

`MultiplierComponent` stores `factor_id`, `category_id`, `source_definition_id`, and exact `value`. `FactorModifier` stores `factor_id`, `category_id`, exact signed `delta`, `source_copy_id`, and `source_definition_id`.

- [ ] **Step 4: Extend hand definitions and config serialization**

Extend `NormalHandDefinition` with `broad_category_id`, `component_group`, and copied `rule_parameters`. Extend `ContextHandDefinition` with `broad_category_id`. Keep the new constructor arguments optional for existing call sites, but normalize legacy `pair`, `three_kind`, and `full_house` rules into `grouped_ranks` plus explicit `group_sizes`; infer omitted broad metadata deterministically from the normalized rule or context-minimum key count. Serialized definitions must always contain explicit normalized values. Validate the closed vocabularies and serialize all fields through `MatchConfig.to_dict()`/`from_dict()`.

- [ ] **Step 5: Run focused tests to verify GREEN**

Run the Step 2 command.

Expected: all definition and config round-trip tests pass.

- [ ] **Step 6: Commit**

```powershell
git add src/core/scoring/scoring_categories.gd src/core/scoring/scoring_types.gd src/core/scoring/normal_hand_definition.gd src/core/scoring/context_hand_definition.gd src/core/match/match_config.gd tests/core/scoring/scoring_definition_test.gd tests/core/match/match_setup_test.gd
git commit -m "feat: define additive scoring factors"
```

---

### Task 2: Produce independent rank, Flush, and context components

**Files:**
- Modify: `src/core/scoring/normal_hand_evaluator.gd`
- Modify: `src/core/scoring/context_hand_evaluator.gd`
- Modify: `src/core/scoring/scoring_types.gd`
- Modify: `tests/core/scoring/normal_hand_evaluator_test.gd`
- Modify: `tests/core/scoring/context_and_score_test.gd`

**Interfaces:**
- Consumes: Task 1 categorized definitions and `MultiplierComponent`.
- Produces: `NormalHandResult.components: Array[MultiplierComponent]` with one rank plus optional Flush; `ContextHandResult.broad_category_id` and `component: MultiplierComponent`.

- [ ] **Step 1: Write failing rank/group classification tests**

Add tests named:

- `test_rank_result_selects_exactly_one_high_straight_family_or_group_component`
- `test_grouped_rank_parameters_cover_two_pairs_two_triples_three_pairs_and_full_house`
- `test_full_house_is_group_only_and_does_not_emit_contained_family_components`
- `test_high_card_uses_one_card_subset_when_extra_cards_are_submitted`

Use `rule_id = grouped_ranks` with `rule_parameters.group_sizes` for Family and Group shapes. Assert priority/tie-break selects one authoritative rank definition.

- [ ] **Step 2: Write failing Flush component tests**

Add tests named:

- `test_straight_family_and_group_may_each_stack_one_flush_component`
- `test_flush_requires_every_submitted_face_to_share_one_suit`
- `test_flush_definition_does_not_match_a_same_suit_subset_with_off_suit_extras`

Assert components retain separate source definition IDs and exact rational values.

- [ ] **Step 3: Write failing context-category tests**

Add tests named:

- `test_context_result_uses_selected_definition_broad_category`
- `test_lower_priority_context_shapes_do_not_emit_extra_components`
- `test_no_context_fallback_is_neutral_and_has_no_buffable_category`

- [ ] **Step 4: Run evaluator tests to verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/scoring/normal_hand_evaluator_test.gd tests/core/scoring/context_and_score_test.gd
```

Expected: new component and category assertions fail.

- [ ] **Step 5: Generalize normal rules and select components**

Support the closed rule IDs `high_card`, `straight`, `grouped_ranks`, and `flush`. `grouped_ranks` compares sorted rank-count groups with the definition's `group_sizes`. Select the highest-priority/tie-break rank definition independently from the highest-priority qualifying Flush definition. Only a Flush definition whose `subset_size` equals the complete submitted face count may qualify.

- [ ] **Step 6: Attach the selected context component**

Return the selected exact definition ID, its broad category, and one `context_hand` component. Preserve the neutral `no_context` fallback without a matchable broad category.

- [ ] **Step 7: Run evaluator tests to verify GREEN**

Run the Step 4 command.

Expected: all normal and context evaluator tests pass.

- [ ] **Step 8: Commit**

```powershell
git add src/core/scoring/normal_hand_evaluator.gd src/core/scoring/context_hand_evaluator.gd src/core/scoring/scoring_types.gd tests/core/scoring/normal_hand_evaluator_test.gd tests/core/scoring/context_and_score_test.gd
git commit -m "feat: classify additive hand components"
```

---

### Task 3: Replace ordered score operations with clamped additive factors

**Files:**
- Modify: `src/core/scoring/score_calculator.gd`
- Modify: `src/core/scoring/scoring_types.gd`
- Modify: `src/core/scoring/submission_evaluator.gd`
- Modify: `src/core/abilities/effect_registry.gd`
- Modify: `src/core/events/event_kinds.gd`
- Modify: `src/core/match/match_controller.gd`
- Modify: `src/core/match/player_state.gd`
- Modify: `src/core/match/match_state.gd`
- Modify: `tests/core/scoring/context_and_score_test.gd`
- Modify: `tests/core/scoring/submission_evaluator_test.gd`
- Modify: `tests/core/match/main_one_controller_test.gd`
- Modify: `tests/core/match/end_phase_controller_test.gd`
- Modify: `tests/core/match/review_hardening_test.gd`
- Modify: `tests/network/network_session_test.gd`

**Interfaces:**
- Consumes: Task 2 evaluator components and Task 1 `FactorModifier`.
- Produces: `ScoreCalculator.calculate(faces, normal, context, modifiers, field_components = []) -> ScoreBreakdown`; `PlayerState.factor_modifiers`; `factor_modifier` effect handling; complete factor/component serialization.

- [ ] **Step 1: Write failing factor-calculation tests**

Add tests named:

- `test_score_adds_components_and_matching_modifiers_inside_each_factor`
- `test_straight_flush_uses_sum_of_both_normal_components`
- `test_one_modifier_hits_matching_group_once_even_with_several_rank_groups`
- `test_multiple_same_category_modifiers_stack_once_each`
- `test_opposing_modifiers_are_order_independent`
- `test_each_multiplier_factor_floors_to_one_independently`
- `test_pass_stays_zero_with_neutral_factor_floors`
- `test_exact_rationals_receive_one_final_ceiling_only`

Pin a representative calculation such as `10 × (6 + 4 + 3 - 2) × (5 - 3) × 1 = 220`.

- [ ] **Step 2: Write failing state round-trip tests**

Assert factor modifiers, normal/context components, unclamped values, clamped factor values, and final score survive `MatchState.to_dict()`/`from_dict()` without ordered-operation fields. Update public-ability fixtures to use authoritative `factor_id`, `category_id`, `numerator`, and `denominator` parameters.

- [ ] **Step 3: Run focused tests to verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/scoring/context_and_score_test.gd tests/core/scoring/submission_evaluator_test.gd tests/core/match/main_one_controller_test.gd tests/core/match/end_phase_controller_test.gd tests/core/match/review_hardening_test.gd tests/network/network_session_test.gd
```

Expected: FAIL because the calculator still applies ordered final-score operations.

- [ ] **Step 4: Implement factor aggregation**

Calculate base value, then aggregate components and matching modifiers by factor/category. A modifier matches when the locked factor contains a component with the same category; apply the modifier once even if malformed duplicate components are present. Card/context factors start from their component sums; field starts at neutral `1`. Floor each to `Rational(1, 1)`, multiply, and ceiling once.

Update `ScoreBreakdown` to retain component arrays, applied modifiers, each unclamped/clamped factor, raw exact score, and final integer score.

- [ ] **Step 5: Migrate the effect handler, player state, and fixtures atomically**

Register `factor_modifier` and emit `FACTOR_MODIFIER_APPLIED`. Rename round-only `score_modifiers` to `factor_modifiers`; update `SubmissionEvaluator`, controller call sites, cleanup, canonical serialization, and every existing public-ability/scoring fixture in the focused suite. Remove `ScoreModifier`, the `score_modifier` effect ID, and the legacy `add`/`multiply` representation only after `rg` confirms no active caller remains.

- [ ] **Step 6: Run focused tests to verify GREEN**

Run the Step 3 command.

Expected: all score, submission, and round-trip tests pass.

- [ ] **Step 7: Commit**

```powershell
git add src/core/scoring/score_calculator.gd src/core/scoring/scoring_types.gd src/core/scoring/submission_evaluator.gd src/core/abilities/effect_registry.gd src/core/events/event_kinds.gd src/core/match/match_controller.gd src/core/match/player_state.gd src/core/match/match_state.gd tests/core/scoring/context_and_score_test.gd tests/core/scoring/submission_evaluator_test.gd tests/core/match/main_one_controller_test.gd tests/core/match/end_phase_controller_test.gd tests/core/match/review_hardening_test.gd tests/network/network_session_test.gd
git commit -m "feat: calculate clamped additive score factors"
```

---

### Task 4: Add the sixteen definitions and a separate deck recipe

**Files:**
- Modify: `src/core/abilities/ability_catalog.gd`
- Modify: `src/view/app/runtime_game_session.gd`
- Modify: `tests/core/abilities/ability_catalog_test.gd`
- Modify: `tests/view/runtime_game_session_test.gd`

**Interfaces:**
- Consumes: Task 1 factor/category vocabulary and existing `AbilityDefinition` metadata/schema.
- Produces: `AbilityCatalog.manipulation_designs()`, `hand_shape_designs()`, `all_designs()`, `provisional_deck_recipe()`, and `build_deck(recipe)`.

- [ ] **Step 1: Write failing catalogue tests**

Add tests named:

- `test_hand_shape_catalog_has_sixteen_unique_factor_category_sign_combinations`
- `test_hand_shape_cards_use_public_player_target_schema_and_placeholder_three`
- `test_definition_data_is_independent_from_physical_copy_recipe`
- `test_custom_recipe_supports_different_counts_per_definition`
- `test_unknown_noninteger_or_nonpositive_recipe_entries_reject`

Assert ten card-hand designs and six context-hand designs, with `+3/1` buffs and `-3/1` nerfs.

- [ ] **Step 2: Run catalogue tests to verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/ability_catalog_test.gd tests/view/runtime_game_session_test.gd
```

Expected: FAIL because Hand Buff/Nerf designs and recipe expansion do not exist.

- [ ] **Step 3: Refactor catalogue designs from deck composition**

Make `manipulation_designs()` return one definition per design. Add all sixteen Hand Buff/Nerf definitions with `HAND_SHAPE` timing, `factor_modifier` effect ID, fixed authoritative factor/category/delta parameters, and one dynamic `player` choice step.

`build_deck(recipe: Dictionary)` expands definition IDs into repeated physical definition entries. Use a provisional recipe of two copies per manipulation design and one copy per Hand Buff/Nerf design solely to keep the current runtime playable; tests must prove every count is independently overrideable.

- [ ] **Step 4: Use the recipe in the runtime**

Replace the direct `manipulation_definitions(2)` call with `build_deck(provisional_deck_recipe())`. Preserve all definition display metadata in the projected ability catalogue.

- [ ] **Step 5: Run catalogue tests to verify GREEN**

Run the Step 2 command.

Expected: all catalogue/runtime tests pass.

- [ ] **Step 6: Commit**

```powershell
git add src/core/abilities/ability_catalog.gd src/view/app/runtime_game_session.gd tests/core/abilities/ability_catalog_test.gd tests/view/runtime_game_session_test.gd
git commit -m "feat: define hand buff and nerf catalogue"
```

---

### Task 5: Resolve authoritative factor modifiers in both Main phases

**Files:**
- Modify: `src/core/abilities/effect_registry.gd`
- Modify: `src/core/events/event_kinds.gd`
- Modify: `src/core/match/match_controller.gd`
- Modify: `tests/core/match/main_one_controller_test.gd`
- Modify: `tests/core/match/end_phase_controller_test.gd`
- Modify: `tests/core/match/review_hardening_test.gd`
- Modify: `tests/network/network_session_test.gd`

**Interfaces:**
- Consumes: Task 4 `factor_modifier` definitions and Task 3 `PlayerState.factor_modifiers`/calculator.
- Produces: authoritative public target validation, `FACTOR_MODIFIER_APPLIED` event, Main 1 deferred applicability, and Main 2 provisional-score recalculation.

- [ ] **Step 1: Write failing lifecycle tests**

Add tests named:

- `test_hand_shape_modifier_targets_self_or_active_opponent_in_both_main_phases`
- `test_main_one_modifier_waits_for_locked_hand_then_applies_once`
- `test_main_one_unmatched_or_passed_hand_consumes_card_and_contributes_zero`
- `test_main_two_modifier_recalculates_score_without_reclassifying_hand`
- `test_multiple_buff_and_nerf_cards_stack_in_any_receipt_order`
- `test_round_end_clears_factor_modifiers_after_final_scoring`

- [ ] **Step 2: Write failing authority and privacy tests**

Add tests that forge target IDs, `factor_id`, `category_id`, `delta`, or an applicability flag. Assert exact rejection and no mutation of ability zones, modifiers, Ready state, reaction deadline, RNG, or provisional score. Assert Main 1 public output reveals the played card/source/target but no private hand or predicted match result.

- [ ] **Step 3: Run controller/network tests to verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/match/main_one_controller_test.gd tests/core/match/end_phase_controller_test.gd tests/core/match/review_hardening_test.gd tests/network/network_session_test.gd
```

Expected: new factor-handler and lifecycle tests fail.

- [ ] **Step 4: Harden the factor-modifier effect handler for the production catalogue**

Validate target activity and the authoritative definition's factor/category/rational delta against `ScoringCategories`. Append exactly one `FactorModifier` with both source IDs and emit `FACTOR_MODIFIER_APPLIED` without private classification data. Reject all client-authored effect fields before this handler is reached.

- [ ] **Step 5: Make public player choices dynamic and authoritative**

Extend `_validate_public_ability_choices(...)` so a `kind = player` step accepts exactly one identifier from the current active, non-pending players rather than definition-embedded live IDs. Require it to equal `target_player_id`. Continue using static `eligible` lists for fixed non-player choices.

- [ ] **Step 6: Recalculate Main 2 and preserve Main 1 classification privacy**

Use locked components plus `factor_modifiers` for Main 2 provisional scoring. Main 1 stores only the modifier; no applicability result is calculated or published before Hand Play resolution.

- [ ] **Step 7: Run controller/network tests to verify GREEN**

Run the Step 3 command.

Expected: all lifecycle, authority, and privacy tests pass.

- [ ] **Step 8: Commit**

```powershell
git add src/core/abilities/effect_registry.gd src/core/events/event_kinds.gd src/core/match/match_controller.gd tests/core/match/main_one_controller_test.gd tests/core/match/end_phase_controller_test.gd tests/core/match/review_hardening_test.gd tests/network/network_session_test.gd
git commit -m "feat: resolve hand factor modifiers"
```

---

### Task 6: Add player targeting and factor breakdown presentation

**Files:**
- Add: `assets/fonts/mountain_king/MountainKingRegular.ttf`
- Add: `assets/fonts/mountain_king/ATTRIBUTION.md`
- Add: `assets/fonts/mountain_king/source-info.txt`
- Modify: `themes/placeholder_theme.tres`
- Modify: `src/view/match/card_widget.gd`
- Modify: `src/view/match/card_widget.tscn`
- Modify: `src/view/match/targeting_overlay.gd`
- Modify: `src/view/match/match_screen.gd`
- Modify: `src/view/match/ability_panel.gd`
- Modify: `src/view/match/phase_controls.gd`
- Modify: `src/view/match/player_seat.gd`
- Modify: `src/core/match/snapshot_projector.gd`
- Modify: `src/view/app/ui_fixture.gd`
- Modify: `tests/view/ability_and_privacy_test.gd`
- Modify: `tests/view/match_screen_test.gd`
- Modify: `tests/view/phase_controls_test.gd`
- Add: `tests/view/typography_and_card_art_test.gd`
- Modify: `tests/core/match/snapshot_projector_test.gd`
- Modify: `docs/superpowers/specs/2026-11-15-shift-card-game-design.md`

**Interfaces:**
- Consumes: Task 4 dynamic `player` choice schema and Task 3 factor breakdown.
- Produces: `TargetingOverlay.begin(workflow, private_hand = [], player_targets = [])`; public score-breakdown projection; readable ability and factor UI.

- [ ] **Step 1: Write failing dynamic player-target tests**

Add tests named:

- `test_player_targeting_lists_active_self_and_opponents_but_not_spectators_or_pending_players`
- `test_player_target_selection_commits_matching_target_and_choices`
- `test_hand_shape_card_displays_category_delta_and_both_legal_phases`

Add typography/art tests named:

- `test_placeholder_theme_uses_mountain_king_as_default_font`
- `test_card_rank_uses_number_art_and_ten_composes_one_then_zero`
- `test_joker_rank_uses_zero_art_while_other_card_text_uses_theme_font`

- [ ] **Step 2: Write failing score-breakdown projection and UI tests**

Assert revealed/provisional score models include base value, rank/Flush components, context component, applied modifiers, unclamped/clamped factor values, and final score. Assert a Straight Flush with a buff and nerf renders additive normal details rather than the legacy opaque `normal × context` text. Assert private Main 1 classification remains absent.

- [ ] **Step 3: Run focused UI/projection tests to verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/ability_and_privacy_test.gd tests/view/match_screen_test.gd tests/view/phase_controls_test.gd tests/view/typography_and_card_art_test.gd tests/core/match/snapshot_projector_test.gd
```

Expected: player choice resolution and factor breakdown assertions fail.

- [ ] **Step 4: Resolve and render player targets**

Pass active player IDs and display names from `MatchScreen` into `TargetingOverlay.begin(...)`. Resolve `kind = player` steps locally for presentation only; the host remains authoritative. Render one choice button per active player and submit only the selected player ID.

- [ ] **Step 5: Install the licensed font and render rank artwork**

Add the unmodified Mountain King Regular TTF plus attribution naming Michael W. Moss, the FontSpace source URL, and the CC BY 4.0 license URL. Set it as `default_font` in `placeholder_theme.tres`. Replace font-rendered rank digits inside `CardWidget` with one or two texture nodes loaded from `assets/artwork/card_number/png/card_number_0.png` through `card_number_9.png`; preserve text labels for context, suit, Joker wording, accessibility/debug text, and existing click/target behavior.

- [ ] **Step 6: Project and render factor breakdowns**

Add a sanitized public score-breakdown adapter in `SnapshotProjector`. Update phase preview/seat presentation and the UI fixture to show additive card-hand components, context contribution, matching signed adjustments, field factor, floors when invoked, and the final score. Do not expose unrevealed hands or Main 1 applicability.

- [ ] **Step 7: Reconcile the main design document**

Replace the obsolete opaque multiplier/ordered modifier language with the approved four-layer formula, broad categories, one-hit modifier rule, independent factor floors, and deferred balance/copy counts. Link the detailed Hand Buff/Nerf spec.

- [ ] **Step 8: Run focused and full UI tests to verify GREEN**

Run the Step 3 command, then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_ui.ps1
```

Expected: focused tests pass; every View test passes; the headless UI fixture exits `0` without script errors.

- [ ] **Step 9: Commit**

```powershell
git add assets/fonts/mountain_king/MountainKingRegular.ttf assets/fonts/mountain_king/ATTRIBUTION.md assets/fonts/mountain_king/source-info.txt themes/placeholder_theme.tres src/view/match/card_widget.gd src/view/match/card_widget.tscn src/view/match/targeting_overlay.gd src/view/match/match_screen.gd src/view/match/ability_panel.gd src/view/match/phase_controls.gd src/view/match/player_seat.gd src/core/match/snapshot_projector.gd src/view/app/ui_fixture.gd tests/view/ability_and_privacy_test.gd tests/view/match_screen_test.gd tests/view/phase_controls_test.gd tests/view/typography_and_card_art_test.gd tests/core/match/snapshot_projector_test.gd docs/superpowers/specs/2026-11-15-shift-card-game-design.md
git commit -m "feat: present hand factor modifiers"
```

---

### Task 7: Verify complete scoring, UI, and network integration

**Files:**
- Modify only if verification exposes an in-scope regression.

**Interfaces:**
- Consumes: Tasks 1–6 complete implementation.
- Produces: release-quality evidence for the generalized scoring system and Hand Buff/Nerf category.

- [ ] **Step 1: Run the complete Godot suite**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

Expected: all discovered tests pass with no `SCRIPT ERROR` or unexpected `ERROR:` lines.

- [ ] **Step 2: Run the complete UI suite and fixture**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_ui.ps1
```

Expected: all View tests pass and the fixture exits `0`.

- [ ] **Step 3: Run signaling tests**

```powershell
Push-Location service/signaling
npm test
Pop-Location
```

Expected: every Node signaling test passes.

- [ ] **Step 4: Run the five-process direct-WebRTC fixture**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_network.ps1
```

Expected: host, three remote players, spectator, command/event exchange, and relaunch reconnect all pass and shut down cleanly.

- [ ] **Step 5: Check repository hygiene and obsolete paths**

```powershell
git diff --check
rg -n "ScoreModifier|score_modifiers|effect_id.*score_modifier|after_each_modifier|before_modifiers" src tests
git status --short
```

Expected: no diff errors, no active legacy ordered-score paths, and only intended changes before task commits or a clean tree afterward.

- [ ] **Step 6: Commit a verification correction only if required**

If Steps 1–5 required an in-scope fix:

```powershell
git add <corrected-files>
git commit -m "fix: harden hand factor scoring"
```

If no correction was required, do not create an empty commit.
