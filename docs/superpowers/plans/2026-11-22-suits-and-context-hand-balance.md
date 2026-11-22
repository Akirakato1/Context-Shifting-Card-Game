# Suit Names and Context-Hand Balance Implementation Plan

**Status:** Implemented and verified on 2026-11-22.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Mountain, Cloud, and Sea the canonical suits and ship the complete rarity-derived context-hand priority and multiplier catalogue.

**Architecture:** Preserve suit integers across serialization and networking while replacing placeholder enum identifiers and presentation strings with semantic names. Move production context-hand balance out of the runtime view class into a focused core catalogue that returns `ContextHandDefinition` values consumed unchanged by match configuration, scoring, snapshots, and reconnect restoration.

**Tech Stack:** Godot 4.7.2, typed GDScript, exact `Rational` arithmetic, existing custom Godot test runner.

**Spec:** `docs/superpowers/specs/2026-11-22-suits-and-context-hand-balance-design.md`

## Global Constraints

- Canonical suit order and wire values are Mountain `0`, Cloud `1`, Sea `2`.
- Numeric snapshot/network suit values remain compatible; no wire schema changes.
- Numbered suit identifiers and active numbered presentation copy are removed from production code.
- All 40 context definitions use the exact priorities and rational multipliers in the spec.
- Qualification remains inclusive and only the highest-priority qualifying context hand contributes.
- Normal-hand definitions and multipliers remain untouched.
- Preserve the user's concurrent UI/art work; for already-dirty UI or documentation files, stage only this plan's exact hunks.
- Do not modify partial user-owned `graphify-out/` contents.

## Review Focus

- Wire compatibility: renamed suit constants must still serialize as integers `0/1/2`; pin this in Task 1.
- Range assumptions: every suit loop and randomizer must include exactly Mountain through Sea after the enum rename; exercise factory, manipulation, sabotage, scoring, and networking tests in Task 1.
- Definition-ID drift: Favor IDs, recipe entries, runtime ability catalogue, and field resolution must all use the same semantic IDs; pin this in Task 2.
- Catalogue completeness: there must be exactly 40 unique context definitions with all symmetric variants and no duplicate IDs; pin this in Task 3.
- Inclusive collisions: priority must select the intended rarest shape for `5/3/3`, `4/4/4`, and `5/5/2`; pin this in Task 3.

---

### Task 1: Canonical suit domain vocabulary

**Files:**
- Modify: `src/core/common/game_types.gd`
- Modify: all production and test files currently referencing `GameTypes.Suit.ONE`, `.TWO`, or `.THREE`
- Test: `tests/core/common/game_types_test.gd`
- Test: existing card, ability-resolver, scoring, match, and network tests containing suit fixtures

**Interfaces:**
- Consumes: existing integer suit payloads and range-based suit generation.
- Produces: `GameTypes.Suit.MOUNTAIN == 0`, `.CLOUD == 1`, `.SEA == 2`; `GameTypes.suit_name(suit: int) -> String`.

- [ ] **Step 1: Write failing semantic-name and wire-value tests**

Extend `test_context_values_preserve_protocol_order_and_names` or add `test_suit_values_preserve_protocol_order_and_names` asserting the three exact integers, `suit_name(0..2)`, and `"Unknown"` for `-1` and `3`.

- [ ] **Step 2: Run the focused domain test and verify RED**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/common/game_types_test.gd`

Expected: FAIL because semantic enum members and `suit_name()` do not exist.

- [ ] **Step 3: Implement the semantic enum and central name function**

In `GameTypes`, define `MOUNTAIN = 0`, `CLOUD = 1`, `SEA = 2` and `static func suit_name(suit: int) -> String`. Mechanically replace every production/test reference to the old constants without changing values, ranges, random selection, fixture intent, or payload shapes.

- [ ] **Step 4: Run suit-sensitive core and network tests**

Run all test files changed by the constant migration plus `tests/core/common/game_types_test.gd`.

Expected: all selected tests PASS and no parser reference to `GameTypes.Suit.ONE/TWO/THREE` remains.

- [ ] **Step 5: Commit the domain migration**

```powershell
git add src/core/common/game_types.gd src/core tests/core tests/network
git commit -m "refactor: name mountain cloud and sea suits"
```

### Task 2: Suit-aware abilities and card presentation

**Files:**
- Modify: `src/core/abilities/ability_catalog.gd`
- Modify: `src/view/match/card_widget.gd`
- Modify: `tests/core/abilities/ability_catalog_test.gd`
- Modify: `tests/core/scoring/submission_evaluator_test.gd`
- Modify: `tests/view/match_screen_test.gd`
- Modify: `tests/view/phase_controls_test.gd`

**Interfaces:**
- Consumes: `GameTypes.suit_name(int) -> String` and semantic suit constants from Task 1.
- Produces: field definitions `mountain_favor`, `cloud_favor`, `sea_favor`; card and Joker suit UI showing Mountain, Cloud, Sea.

- [ ] **Step 1: Write failing Favor catalogue tests**

Assert the field catalogue contains the three semantic IDs, each definition's display name and rules text contains the matching suit name, and its `effect_parameters.suit` equals the corresponding semantic enum value. Assert numbered Favor IDs are absent.

- [ ] **Step 2: Write failing card/Joker presentation tests**

Update match-screen face expectations to Mountain/Cloud/Sea and extend the phase-controls Joker test to assert the suit `OptionButton` contains exactly those three labels in wire order.

- [ ] **Step 3: Run the focused tests and verify RED**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/abilities/ability_catalog_test.gd tests/core/scoring/submission_evaluator_test.gd tests/view/match_screen_test.gd tests/view/phase_controls_test.gd`

Expected: FAIL on numbered Favor IDs and `ONE/TWO/THREE` UI labels.

- [ ] **Step 4: Implement semantic Favor generation and suit presentation**

Generate Favor IDs, display names, and rules text from the ordered suit metadata while retaining exact suit parameters and durations. Replace `CardWidget.SUIT_NAMES` placeholders with values sourced from `GameTypes.suit_name()`.

- [ ] **Step 5: Run focused ability and presentation tests**

Expected: all four focused test files PASS, the ability catalogue still contains 15 field definitions and the full physical deck remains 90 cards.

- [ ] **Step 6: Commit only scoped hunks**

Stage the complete clean ability/test files. Because `card_widget.gd` may contain unrelated user work, stage only the suit-label hunk rather than the entire dirty file.

```powershell
git commit -m "feat: propagate semantic suit names"
```

### Task 3: Production context-hand catalogue

**Files:**
- Create: `src/core/scoring/context_hand_catalog.gd`
- Create: `tests/core/scoring/context_hand_catalog_test.gd`
- Modify: `src/view/app/runtime_game_session.gd`
- Modify: `tests/view/runtime_game_session_test.gd`

**Interfaces:**
- Consumes: `ContextHandDefinition.new(id, priority, minimums, Rational, broad_category_id)` and the approved table.
- Produces: `ContextHandCatalog.definitions() -> Array[ContextHandDefinition]`; runtime matches consume this instead of `_placeholder_context_hands()`.

- [ ] **Step 1: Write failing catalogue completeness tests**

Add assertions for 40 unique definitions: four All Contexts, 24 Single Context, and 12 Two Context definitions. Pin representative semantic IDs and require every symmetric variant at one threshold to share priority, multiplier, and broad category.

- [ ] **Step 2: Pin every approved tier**

Use a compact expected table keyed by family and threshold to assert priorities `10..160` and exact rational values `5/4`, `3/2`, `7/4`, `2/1`, `9/4`, `5/2`, `11/4`, `13/4`, `7/2`, `15/4`, `9/2`, and `5/1` exactly as specified.

- [ ] **Step 3: Write failing collision and immutability tests**

Evaluate context counts `5/3/3`, `4/4/4`, and `5/5/2`; expect `single_context ×5`, `all_contexts_4`, and the matching `two_contexts ×5` respectively. The first case intentionally exercises the count-only evaluator with eleven halves to isolate the All Contexts ×3 versus Single Context ×5 priority collision; the other two are valid six-card distributions. Mutating one returned array or definition minimums must not alter a later fresh `definitions()` result.

- [ ] **Step 4: Run the new test and verify RED**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/scoring/context_hand_catalog_test.gd`

Expected: FAIL because `ContextHandCatalog` does not exist.

- [ ] **Step 5: Implement `ContextHandCatalog.definitions()`**

Construct fresh definitions from compact immutable tier data. IDs are `all_contexts_N`, `{rise|flourish|fall}_N`, and `{rise_flourish|rise_fall|flourish_fall}_N`; minimums use semantic context constants; broad categories are explicit.

- [ ] **Step 6: Wire the runtime to the production catalogue**

Preload `ContextHandCatalog`, replace `_placeholder_context_hands()` at match creation, and remove the placeholder builder. Add runtime assertions for count, representative priorities/multipliers, and absence of placeholder-only ×1 values.

- [ ] **Step 7: Run catalogue, evaluator, configuration, and runtime tests**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/scoring/context_hand_catalog_test.gd tests/core/scoring/context_and_score_test.gd tests/core/match/match_setup_test.gd tests/view/runtime_game_session_test.gd`

Expected: all selected tests PASS.

- [ ] **Step 8: Commit the production catalogue**

```powershell
git add src/core/scoring/context_hand_catalog.gd src/view/app/runtime_game_session.gd tests/core/scoring/context_hand_catalog_test.gd tests/view/runtime_game_session_test.gd
git commit -m "feat: balance production context hands"
```

### Task 4: Context-hand presentation and current documentation

**Files:**
- Modify: `src/view/match/player_seat.gd`
- Modify: `tests/view/match_screen_test.gd`
- Modify: `README.md`
- Modify: `docs/art-ui-audio-asset-checklist.md`
- Modify: `docs/superpowers/specs/2026-11-22-suits-and-context-hand-balance-design.md`

**Interfaces:**
- Consumes: semantic context-hand IDs and exact multiplier values from Task 3.
- Produces: readable names for every context-hand family and current project documentation that records finalized suits and context balance.

- [ ] **Step 1: Write failing readable-name view assertions**

Cover All Contexts, one Single Context ID, and one Two Context ID in player-seat score summaries, including the exact displayed multiplier supplied by the score breakdown.

- [ ] **Step 2: Run the match-screen test and verify RED**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/match_screen_test.gd`

Expected: semantic IDs outside All Contexts are rendered by generic capitalization rather than the intended readable pattern names.

- [ ] **Step 3: Implement context-hand display formatting**

Extend `PlayerSeat._context_name(id: String) -> String` to render `Rise ×N`, `Flourish ×N`, `Fall ×N`, and the three named pairs as `Rise + Flourish ×N`, etc.; retain All Contexts and neutral fallback behavior.

- [ ] **Step 4: Update only current-state documentation**

State that suits and context-hand balance are finalized in README and the asset checklist. Do not rewrite historical implementation plans; mark the new design `Implemented` only after verification.

- [ ] **Step 5: Run view tests and commit scoped hunks**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test.ps1 tests/view/match_screen_test.gd tests/view/phase_controls_test.gd`

Expected: both PASS. Stage only this task's exact hunks in already-dirty UI/documentation files.

```powershell
git commit -m "docs: finalize suit and context terminology"
```

### Task 5: Full verification and integration

**Files:**
- Modify: `docs/superpowers/specs/2026-11-22-suits-and-context-hand-balance-design.md`
- Test: complete core/network suite and relevant view/runtime suite

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: verified implementation ready for `main`.

- [ ] **Step 1: Verify placeholder vocabulary is absent from active production code**

Run searches for old suit enum members, `Suit 1/2/3`, numbered Favor IDs, `_placeholder_context_hands`, and context definitions still using blanket `Rational.new(1, 1)`. Historical documents may retain chronological wording.

- [ ] **Step 2: Run complete core and network tests**

Enumerate every `tests/core/**/*_test.gd` and `tests/network/**/*_test.gd` path and pass them to `scripts/test.ps1` with the repository's Godot 4.7.2 binary.

Expected: zero failures.

- [ ] **Step 3: Run relevant view/runtime tests**

Run runtime-session, match-screen, phase-controls, and typography/card-art tests.

Expected: zero failures; unrelated concurrent layout work is not staged or rewritten.

- [ ] **Step 4: Run the real WebRTC fixture**

Run: `scripts/test_network.ps1 -GodotBin $env:SHIFT_GODOT_BIN -TimeoutSeconds 120`

Expected: host, three remote players, spectator, command/event transport, reconnect, and shutdown all PASS.

- [ ] **Step 5: Final audit**

Run `git diff --check`, inspect every commit and staged path, confirm no user-owned UI/art or partial `graphify-out` files were accidentally included, then mark the spec `Implemented`.

- [ ] **Step 6: Commit verification metadata and push**

```powershell
git add docs/superpowers/specs/2026-11-22-suits-and-context-hand-balance-design.md docs/superpowers/plans/2026-11-22-suits-and-context-hand-balance.md
git commit -m "test: verify suit and context balance"
git push origin main
```
