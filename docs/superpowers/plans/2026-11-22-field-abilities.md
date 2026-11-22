# Field Abilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the fifteen approved data-driven field abilities across lifecycle, scoring, submission eligibility, serialization, networking projections, and the functional 2D UI.

**Architecture:** Keep immediate clock mutations in the existing effect registry and add a focused `FieldEffectResolver` that derives the union of active contexts and exact field multiplier components from active `FieldState` objects. Extend the existing duration integer with named instant and persistent values, then route staging, reveal, Main 2 rescoring, final scoring, snapshots, and UI eligibility through the same resolver-backed rules.

**Tech Stack:** Godot 4, typed GDScript, existing custom test runner, WebRTC recipient-safe snapshots, PowerShell verification scripts

**Spec:** `docs/superpowers/specs/2026-11-22-field-abilities-design.md`

## Global Constraints

- The live catalogue contains fifteen field designs; Prime Rank Favor does not exist.
- Field cards are legal only during Main 1 and require no private target selection.
- Shift cards are instant, Resonance lasts one round, scoring fields last three rounds, and Reverse Cycle is persistent without a timer.
- The round played counts against every positive timed duration.
- The provisional recipe has four copies of each Resonance and one copy of every other field design.
- All active scoring-field copies contribute separately and add within the single field multiplier.
- Resonance adds contexts without changing the base clock context, direction, or next clock step.
- A selected Joker's chosen suit counts for Suit Favor; Joker rank `0` never counts for Even or Odd Rank Favor.
- Ascendancy uses the resolved two-half context tally of every submitted full card and requires a strict, untied maximum.
- Clients never author field rule parameters; the authoritative host validates definition parameters before consuming a card.
- Preserve public/private snapshot boundaries and existing reconnect behavior.
- Use no `Co-Authored-By` commit trailers.

## Review Focus

- A malformed persistent or instant field duration must reject safely rather than enter an impossible active-field state; Task 1 pins lifecycle validation and round-trip behavior.
- Playing a direction conflict must discard the replaced card and leave exactly one active direction field while applying the new direction once; Task 4 pins replacement order.
- Duplicate Resonance copies must deduplicate contexts, while duplicate scoring fields must stack separately; Task 2 tests both cases.
- Empty/pass submissions and zero-match fields must remain valid zero scores without phantom field components; Tasks 2 and 4 test this boundary.
- Reconnected players and spectators must receive identical public active-context and persistent-field data without private hand leakage; Task 5 tests recipient projections.

---

### Task 1: Instant, Timed, and Persistent Field Lifecycles

**Files:**
- Modify: `src/core/abilities/ability_definition.gd`
- Modify: `src/core/abilities/field_state.gd`
- Modify: `src/core/abilities/ability_deck_state.gd`
- Test: `tests/core/abilities/ability_state_test.gd`

**Interfaces:**
- Produces: `AbilityDefinition.FIELD_DURATION_INSTANT := 0`
- Produces: `AbilityDefinition.FIELD_DURATION_PERSISTENT := -1`
- Produces: `AbilityDefinition.is_instant_field() -> bool`
- Produces: `AbilityDefinition.is_persistent_field() -> bool`
- Produces: `FieldState.is_persistent() -> bool`
- Preserves: `AbilityDeckState.play_field(card, source_player_id) -> Dictionary` for timed and persistent fields only

- [ ] **Step 1: Write failing lifecycle tests**

Add `test_field_definition_accepts_instant_timed_and_persistent_modes()` asserting that field durations `0`, `1`, `3`, and `FIELD_DURATION_PERSISTENT` construct with the expected predicates. Add `test_persistent_field_never_ticks_and_round_trips()` asserting five end ticks leave the card active, `remaining_rounds` remains the persistent constant, and `AbilityDeckState.to_dict()/load_dict()` preserves it. Add an assertion that `play_field()` is never used for an instant definition.

- [ ] **Step 2: Run the lifecycle test and verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/ability_state_test.gd`

Expected: FAIL because instant/persistent lifecycle constants and predicates do not exist and the current definition assertion rejects non-positive field duration.

- [ ] **Step 3: Implement named lifecycle semantics**

In `AbilityDefinition`, permit field duration `FIELD_DURATION_PERSISTENT` or any value `>= FIELD_DURATION_INSTANT`; keep non-field durations nonnegative. Implement the two predicates using timing plus the named constants.

In `FieldState`, implement `is_persistent()` from the definition and make `tick_end()` return `false` without decrementing persistent fields. Preserve current positive-duration ticking.

In `AbilityDeckState.play_field()`, assert the card is not an instant field so instant consumption must be explicit in the controller.

- [ ] **Step 4: Run lifecycle tests**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/ability_state_test.gd`

Expected: all tests pass.

- [ ] **Step 5: Commit the lifecycle unit**

```powershell
git add src/core/abilities/ability_definition.gd src/core/abilities/field_state.gd src/core/abilities/ability_deck_state.gd tests/core/abilities/ability_state_test.gd
git commit -m "feat: support persistent field lifecycles"
```

### Task 2: Data-Driven Active Context and Field Score Resolver

**Files:**
- Create: `src/core/abilities/field_effect_resolver.gd`
- Modify: `src/core/cards/full_card_state.gd`
- Test: `tests/core/abilities/field_effect_resolver_test.gd`
- Test: `tests/core/cards/card_factory_test.gd`

**Interfaces:**
- Consumes: lifecycle-capable `FieldState` from Task 1
- Produces: `FieldEffectResolver.validate_rule(parameters: Dictionary) -> StringName`
- Produces: `FieldEffectResolver.active_contexts(base_context: int, fields: Array) -> PackedInt32Array`
- Produces: `FieldEffectResolver.score_components(faces: Array[ScoringTypes.SelectedCardFace], context_counts: Dictionary, fields: Array) -> Array[ScoringTypes.MultiplierComponent]`
- Produces: `FullCardState.eligible_half_indexes_for_contexts(active_contexts: PackedInt32Array) -> PackedInt32Array`
- Preserves: `FullCardState.eligible_half_indexes(active_context: int)` as a one-context wrapper

- [ ] **Step 1: Write failing resolver tests**

Create tests covering:

- base Rise plus Flourish and duplicate Flourish Resonance returns `[Rise, Flourish]` without mutating a clock value;
- one Suit 1 field with three matching selected faces returns one `field/field` component equal to `3/10`;
- a selected Joker face with rank `0` and chosen Suit 1 contributes to Suit Favor but not Even or Odd Favor;
- Even and Odd fields use exact parity sets and never overlap for ranks `1..10`;
- duplicate Suit Favor copies produce two separate `3/10` components;
- Rise Ascendancy contributes `1/4` for counts `{Rise: 4, Flourish: 2, Fall: 2}` and contributes nothing for a tied maximum;
- zero-match fields produce no components;
- unknown rules, invalid suits/contexts/ranks, zero denominators, and missing parameters return stable validation errors.

Add a card test proving `eligible_half_indexes_for_contexts([Rise, Flourish])` accepts either matching half and the old one-context method is unchanged.

- [ ] **Step 2: Run resolver tests and verify they fail**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/field_effect_resolver_test.gd tests/core/cards/card_factory_test.gd`

Expected: FAIL because the resolver and multi-context eligibility method do not exist.

- [ ] **Step 3: Implement the resolver**

Support exactly these `field_rule` values:

- `additional_context` with a valid `context`;
- `per_selected_suit` with a valid `suit` and nonzero rational delta;
- `per_selected_rank_set` with unique ranks inside `1..10` and nonzero rational delta;
- `strict_context_majority` with a valid `context` and nonzero rational delta.

`active_contexts()` must sort and deduplicate. `score_components()` must emit exact `Rational` values, omit zero contributions, preserve one component per contributing active copy, and use each source definition ID.

Implement the new `FullCardState` method and delegate the old method through a one-element packed array.

- [ ] **Step 4: Run resolver and card tests**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/field_effect_resolver_test.gd tests/core/cards/card_factory_test.gd`

Expected: all tests pass.

- [ ] **Step 5: Commit the resolver unit**

```powershell
git add src/core/abilities/field_effect_resolver.gd src/core/cards/full_card_state.gd tests/core/abilities/field_effect_resolver_test.gd tests/core/cards/card_factory_test.gd
git commit -m "feat: resolve active field scoring rules"
```

### Task 3: Fifteen-Card Field Catalogue and Trusted Rule Validation

**Files:**
- Modify: `src/core/abilities/ability_catalog.gd`
- Modify: `src/core/abilities/effect_registry.gd`
- Modify: `tests/core/abilities/ability_catalog_test.gd`
- Modify: `tests/core/abilities/ability_state_test.gd`
- Modify: `tests/view/runtime_game_session_test.gd`

**Interfaces:**
- Consumes: lifecycle constants from Task 1
- Consumes: `FieldEffectResolver.validate_rule()` from Task 2
- Produces: `AbilityCatalog.field_designs() -> Array[AbilityDefinition]`
- Extends: `AbilityCatalog.all_designs()` to 45 unique designs
- Extends: `AbilityCatalog.provisional_deck_recipe()` to 68 physical cards
- Produces: registered `field_rule` effect handler that validates trusted definition parameters and applies no immediate mutation

- [ ] **Step 1: Write failing catalogue and validation tests**

Assert fifteen unique field IDs, no `prime_rank_favor`, Main 1-only timing, public display text, no choice steps, and these lifecycles:

- three Shift definitions: duration `0`, `context_jump`;
- Reverse Cycle: persistent duration, `reverse_direction`, conflict group `direction`;
- three Resonances: duration `1`, `field_rule/additional_context`;
- three Suit Favor, two Rank Favor, and three Ascendancy: duration `3`, validated field rules.

Assert the provisional recipe gives four copies to each Resonance and one to every other field. Update existing design-count and runtime-deck assertions to 45 designs and 68 cards. Add effect-registry assertions that malformed field rules reject and valid rules return no immediate events.

- [ ] **Step 2: Run catalogue tests and verify they fail**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/ability_catalog_test.gd tests/core/abilities/ability_state_test.gd tests/view/runtime_game_session_test.gd`

Expected: FAIL because field definitions and the `field_rule` handler are absent.

- [ ] **Step 3: Implement field definitions and recipe counts**

Add catalogue helpers for instant Shift, persistent Reverse, one-round Resonance, per-suit Favor, parity Favor, and Ascendancy. Use exact `1/10` and `1/4` rational parameters and Suit 1/2/3 placeholder presentation names. Append field designs from `all_designs()` and their independent counts from `provisional_deck_recipe()`.

Register `field_rule` in `EffectRegistry`; its `validate()` delegates to `FieldEffectResolver.validate_rule(context.effect)` and its `apply()` returns an empty event array.

- [ ] **Step 4: Run catalogue and runtime tests**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/ability_catalog_test.gd tests/core/abilities/ability_state_test.gd tests/view/runtime_game_session_test.gd`

Expected: all tests pass.

- [ ] **Step 5: Commit the catalogue unit**

```powershell
git add src/core/abilities/ability_catalog.gd src/core/abilities/effect_registry.gd tests/core/abilities/ability_catalog_test.gd tests/core/abilities/ability_state_test.gd tests/view/runtime_game_session_test.gd
git commit -m "feat: add field ability catalogue"
```

### Task 4: Authoritative Play, Resonance Eligibility, and Scoring Integration

**Files:**
- Modify: `src/core/scoring/submission_evaluator.gd`
- Modify: `src/core/match/match_controller.gd`
- Create: `tests/core/match/field_ability_controller_test.gd`
- Modify: `tests/core/scoring/submission_evaluator_test.gd`
- Modify: `tests/core/match/end_phase_controller_test.gd`

**Interfaces:**
- Consumes: `FieldEffectResolver.active_contexts()` and `score_components()` from Task 2
- Extends: `SubmissionEvaluator.evaluate(..., modifiers, active_fields: Array = []) -> ScoringTypes.SubmissionResult`
- Produces: `MatchController._calculate_player_score(player) -> ScoringTypes.ScoreBreakdown`
- Preserves: existing callers that omit `active_fields`

- [ ] **Step 1: Write failing controller and submission tests**

Cover these authoritative flows:

- Shift to Flourish consumes into used, changes the base context immediately, and creates no active field;
- Reverse Cycle flips direction, remains active after repeated end ticks, and a later direction conflict replaces/discards it before applying the new effect once;
- Flourish Resonance lets a Flourish-only card stage and lock while the base context remains Rise;
- multiple Resonances allow either context and expire after the round played;
- Suit Favor, Even/Odd Favor, and Ascendancy appear in provisional and finalized score breakdowns with exact rational values;
- Main 2 hand-shape buffs recalculate while retaining the same field components;
- a pass remains zero with neutral field factor and no phantom components;
- malformed field rules reject before the ability leaves hand.

- [ ] **Step 2: Run controller tests and verify they fail**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/match/field_ability_controller_test.gd tests/core/scoring/submission_evaluator_test.gd tests/core/match/end_phase_controller_test.gd`

Expected: FAIL because the controller always activates field cards and scoring omits active fields.

- [ ] **Step 3: Integrate fields into submission and score calculation**

In `SubmissionEvaluator.evaluate()`, derive the active-context union, validate the selected half against it, derive field components from selected faces plus `context_result.counts`, and pass them to `ScoreCalculator.calculate()`.

In `MatchController`:

- consume instant fields directly into the used pile instead of calling `play_field()`;
- activate timed/persistent fields before applying their immediate effect so conflict replacement events retain current ordering;
- pass `state.ability_deck.active_fields()` to staging and locking;
- centralize Main 2 and end-phase recalculation in `_calculate_player_score()` using the same field resolver;
- preserve existing readiness, reaction-window, event, and expiration behavior.

- [ ] **Step 4: Run controller and scoring tests**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/match/field_ability_controller_test.gd tests/core/scoring/submission_evaluator_test.gd tests/core/match/end_phase_controller_test.gd`

Expected: all tests pass.

- [ ] **Step 5: Commit the authoritative integration**

```powershell
git add src/core/scoring/submission_evaluator.gd src/core/match/match_controller.gd tests/core/match/field_ability_controller_test.gd tests/core/scoring/submission_evaluator_test.gd tests/core/match/end_phase_controller_test.gd
git commit -m "feat: apply field effects to submissions"
```

### Task 5: Recipient-Safe Projection and Functional 2D UI

**Files:**
- Modify: `src/core/match/snapshot_projector.gd`
- Modify: `src/view/match/match_screen.gd`
- Modify: `src/view/match/phase_controls.gd`
- Modify: `src/view/match/card_widget.gd`
- Modify: `src/view/app/ui_fixture.gd`
- Modify: `tests/core/match/snapshot_projector_test.gd`
- Modify: `tests/view/match_screen_test.gd`
- Modify: `tests/view/phase_controls_test.gd`
- Modify: `tests/view/layout_smoke_test.gd`

**Interfaces:**
- Consumes: active-context union from Task 2
- Extends public snapshot: `active_contexts: Array[int]`
- Extends each active-field projection: `persistent: bool`, with `remaining_rounds` retained
- Extends card rendering options with `active_contexts` while retaining the base `active_context` for the clock

- [ ] **Step 1: Write failing projection and UI tests**

Assert that host/player/spectator projections share the same sorted public `active_contexts`, expose persistent Reverse without a fake round count, and reveal no private hand data to spectators. Assert the local private hand's `eligible_half_indexes` includes Resonance-only halves.

Add UI assertions that:

- the clock still identifies the base context and also names additional active contexts;
- a persistent field row says `Persistent`;
- a timed field row retains singular/plural round text;
- Resonance-only half cards are highlighted and selectable in hand and staging controls.

- [ ] **Step 2: Run projection and UI tests and verify they fail**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/match/snapshot_projector_test.gd tests/view/match_screen_test.gd tests/view/phase_controls_test.gd tests/view/layout_smoke_test.gd`

Expected: FAIL because snapshots and widgets only understand one active context and numeric durations.

- [ ] **Step 3: Implement projections and UI consumption**

Project the resolver-derived active-context array once per snapshot and reuse it for private eligibility. Add an explicit persistent flag to active-field DTOs.

Keep `active_context` as the clock position. Update `MatchScreen`, `PhaseControls`, and `CardWidget` to consume `active_contexts` for labels, highlighting, and selection checks, defaulting to `[active_context]` for old fixtures. Render persistent duration as text rather than `-1 rounds`.

- [ ] **Step 4: Run projection and UI tests**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/match/snapshot_projector_test.gd tests/view/match_screen_test.gd tests/view/phase_controls_test.gd tests/view/layout_smoke_test.gd`

Expected: all tests pass.

- [ ] **Step 5: Commit the projection/UI unit**

```powershell
git add src/core/match/snapshot_projector.gd src/view/match/match_screen.gd src/view/match/phase_controls.gd src/view/match/card_widget.gd src/view/app/ui_fixture.gd tests/core/match/snapshot_projector_test.gd tests/view/match_screen_test.gd tests/view/phase_controls_test.gd tests/view/layout_smoke_test.gd
git commit -m "feat: display active field contexts"
```

### Task 6: Catalogue Workbook Synchronization and Full Verification

**Files:**
- Modify: `outputs/2026-11-22-ability-catalogue/build_ability_catalogue.mjs`
- Regenerate: `outputs/2026-11-22-ability-catalogue/Shift_Game_Ability_Catalogue.xlsx`
- Regenerate: `outputs/2026-11-22-ability-catalogue/preview_top.png`
- Regenerate: `outputs/2026-11-22-ability-catalogue/preview_bottom.png`
- Modify if needed: `README.md`

**Interfaces:**
- Consumes: the exact fifteen-card live catalogue and provisional counts from Tasks 3–5
- Produces: workbook field section with no Prime Rank Favor and summary totals of 54 ability designs and 15 field designs

- [ ] **Step 1: Remove Prime Rank Favor from the workbook builder**

Update expected counts and dynamic category row boundaries. Preserve existing workbook structure and formatting. The field section must match the live definition IDs, durations, stacking rules, exact values, and provisional Resonance copy count.

- [ ] **Step 2: Regenerate, recalculate, inspect, and render the workbook**

Run the existing artifact-tool builder through the bundled workspace dependency runtime. Verify the formula-error scan matches zero entries, inspect the field rows, and visually review both generated previews for clipping and category-color boundaries.

Expected: workbook summary reports `54` total designs, `15` fields, and no Prime Rank Favor row.

- [ ] **Step 3: Run the complete core and UI suites**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -ExecutionPolicy Bypass -File scripts/test_ui.ps1
```

Expected: zero failed tests and no `SCRIPT ERROR`/`ERROR:` lines.

- [ ] **Step 4: Run the five-process networking fixture**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test_network.ps1`

Expected: signaling tests pass and the host, three clients, spectator, command/result flow, privacy projection, and reconnect reclaim fixture completes successfully.

- [ ] **Step 5: Export the Windows build**

Run: `powershell -ExecutionPolicy Bypass -File scripts/export_windows.ps1`

Expected: Windows x86-64 export completes with the native WebRTC extension included.

- [ ] **Step 6: Review the final diff for scope and secrets**

Confirm there is no Prime Rank Favor in code, tests, workbook, or docs; no TURN credentials or local absolute paths entered tracked product files; no unrelated user changes were overwritten; and every public field DTO remains privacy-safe.

- [ ] **Step 7: Commit final synchronized artifacts and documentation**

```powershell
git add README.md docs/superpowers/specs/2026-11-22-field-abilities-design.md docs/superpowers/plans/2026-11-22-field-abilities.md
git add -f outputs/2026-11-22-ability-catalogue/build_ability_catalogue.mjs outputs/2026-11-22-ability-catalogue/Shift_Game_Ability_Catalogue.xlsx outputs/2026-11-22-ability-catalogue/preview_top.png outputs/2026-11-22-ability-catalogue/preview_bottom.png
git commit -m "docs: synchronize field ability catalogue"
```

## Self-Review Result

- **Spec coverage:** Every catalogue, lifecycle, conflict, context eligibility, scoring, serialization, projection, UI, and verification requirement maps to Tasks 1–6.
- **Step scan:** Each task has one failing-test step, one implementation boundary, targeted verification, and a scoped commit.
- **Type consistency:** `FieldEffectResolver`, lifecycle predicates, `SubmissionEvaluator` optional field argument, snapshot DTO keys, and UI option names remain consistent across tasks.
- **Review focus coverage:** Lifecycle corruption, conflict ordering, duplicate behavior, empty submissions, and reconnect/spectator projections each have an owning test task.
- **Proportion:** The plan specifies interfaces, fixed values, test assertions, and commands without transcribing implementation bodies.
