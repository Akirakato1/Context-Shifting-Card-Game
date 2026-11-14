# Core Rules and Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the deterministic, headless-tested card model and authoritative round controller without networking or presentation dependencies.

**Architecture:** Typed GDScript domain objects hold canonical state; a single `MatchController` accepts commands and emits domain events. Randomness, time, content definitions, and visibility projections are injected or serialized so tests can reproduce every outcome and the later network layer can transport commands/events without owning rules.

**Tech Stack:** Godot 4.7.2 stable, typed GDScript, built-in `RandomNumberGenerator`, custom headless test runner with no third-party test dependency.

**Spec:** `docs/superpowers/specs/2026-11-15-shift-card-game-design.md`

## Global Constraints

- Use Godot 4.7.2 stable, not the 4.8 beta line.
- First shipping target is Windows x64; core tests must run with `--headless`.
- Keep model/controller code free of `Control`, `Node2D`, `Node3D`, animation, audio, and RPC calls.
- Treat the host as authoritative for state, clocks, validation, and RNG.
- Preserve immutable half-card base identity; abilities change effective state only.
- Use exact rational or fixed-point arithmetic and apply one final `ceil(max(0, raw_score))`.
- Keep normal-hand definitions, context thresholds, multipliers, and ability definitions data-driven.
- Do not implement final balance content; tests use explicit fixture definitions.
- Every task ends with the complete headless suite passing and a commit authored only as the user.

## Review Focus

- Malformed or out-of-phase commands must return a stable error and leave canonical state byte-for-byte unchanged; Task 8 pins this.
- A draw request that exhausts both draw and used piles must return a short draw without duplicating cards; Task 2 pins this.
- A valid one-card hand with no context threshold must lock `no_context` at x1 and score normally; Task 5 pins this.
- An ability received at a reaction/hard-deadline boundary must be accepted or rejected deterministically from host time; Task 9 pins this.
- Public and spectator snapshots must never contain private hands, manipulation targets, restored base identities, or hidden discards; Task 12 pins this.

---

## Planned File Structure

```text
project.godot
scripts/test.ps1
src/core/
  abilities/
    ability_deck_state.gd
    ability_definition.gd
    ability_state.gd
    effect_registry.gd
    field_state.gd
  cards/
    card_factory.gd
    context_pile.gd
    full_card_state.gd
    half_card_state.gd
  commands/
    command_kinds.gd
    command_result.gd
    game_command.gd
  common/
    game_types.gd
    rational.gd
    random_source.gd
  events/
    domain_event.gd
    event_kinds.gd
  match/
    match_config.gd
    match_controller.gd
    match_state.gd
    player_state.gd
    snapshot_projector.gd
  scoring/
    context_hand_definition.gd
    context_hand_evaluator.gd
    normal_hand_definition.gd
    normal_hand_evaluator.gd
    score_calculator.gd
    scoring_types.gd
tests/
  test_case.gd
  test_runner.gd
  core/**/_test.gd
```

### Task 1: Godot Project, Test Harness, Core Types, and Seeded RNG

**Files:**
- Create: `project.godot`
- Create: `scripts/test.ps1`
- Create: `tests/test_case.gd`
- Create: `tests/test_runner.gd`
- Create: `src/core/common/game_types.gd`
- Create: `src/core/common/random_source.gd`
- Test: `tests/core/common/random_source_test.gd`

**Interfaces:**
- Consumes: Godot executable from `SHIFT_GODOT_BIN` or `godot` on `PATH`.
- Produces: `GameTypes` enums for `Context`, `Suit`, `Phase`, `VictoryMode`, `InformationVisibility`, `ContextDirection`, and `RecipientRole`; `RandomSource.new(seed: int)` with `shuffle(values: Array) -> Array`, `pick_index(size: int) -> int`, and `state_token() -> int`; one-command headless test execution.

- [ ] **Step 1: Create the project metadata and a failing deterministic RNG test**

`random_source_test.gd` must assert that two `RandomSource` instances created with seed `8675309` produce identical shuffles and that a different seed produces a different order for an eight-element fixture.

- [ ] **Step 2: Create the minimal test runner contract**

`tests/test_runner.gd` extends `SceneTree`, discovers `*_test.gd`, invokes methods beginning with `test_`, prints one line per result, and exits nonzero on any failure. `tests/test_case.gd` provides `assert_eq`, `assert_true`, `assert_false`, and `assert_ne`.

- [ ] **Step 3: Run the test and verify the intended failure**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1`

Expected: nonzero exit identifying missing `RandomSource`.

- [ ] **Step 4: Implement `GameTypes` and `RandomSource`**

`RandomSource.shuffle` returns a shuffled duplicate and never mutates the caller's array. Seed access must be deterministic and must not call global random functions.

- [ ] **Step 5: Run the complete suite**

Expected: exit 0 and `random_source_test` PASS.

- [ ] **Step 6: Commit**

```bash
git add project.godot scripts/test.ps1 tests src/core/common
git commit -m "build: bootstrap Godot core tests"
```

### Task 2: Immutable Half-Cards and Recyclable Context Piles

**Files:**
- Create: `src/core/cards/half_card_state.gd`
- Create: `src/core/cards/context_pile.gd`
- Test: `tests/core/cards/context_pile_test.gd`

**Interfaces:**
- Consumes: `GameTypes.Context`, `GameTypes.Suit`, `RandomSource`.
- Produces: `HalfCardState.new(copy_id: StringName, base_context: int, base_rank: int, base_suit: int)`; effective getters; `apply_overrides(context: int, rank: int, suit: int) -> void`; `reset_effective() -> void`; `ContextPile.new(context: int, draw_cards: Array[HalfCardState])`; `draw(count: int, rng: RandomSource) -> Array[HalfCardState]`; `discard(card: HalfCardState) -> void`; count accessors.

- [ ] **Step 1: Write failing card-identity and pile tests**

Cover 90 unique IDs per generated context fixture, ranks 1–10, three suits, three copies, effective overrides without base mutation, reset, draw without replacement, recycle only after draw exhaustion, and short draw when draw/used are both empty.

- [ ] **Step 2: Run the targeted test and verify failure**

Run: `scripts/test.ps1 tests/core/cards/context_pile_test.gd`

Expected: missing `HalfCardState` or `ContextPile`.

- [ ] **Step 3: Implement `HalfCardState`**

Reject invalid base rank outside 1–10 and invalid base context/suit. Use sentinel values only internally; callers read effective values through methods.

- [ ] **Step 4: Implement `ContextPile`**

When a draw empties the draw array, shuffle the used array into draw and continue. Never duplicate or silently fabricate a card.

- [ ] **Step 5: Run all tests**

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add src/core/cards tests/core/cards
git commit -m "feat: add half cards and context piles"
```

### Task 3: Full Cards, Opening Hands, and Replenishment Pairing

**Files:**
- Create: `src/core/cards/full_card_state.gd`
- Create: `src/core/cards/card_factory.gd`
- Test: `tests/core/cards/card_factory_test.gd`

**Interfaces:**
- Consumes: `HalfCardState`, `ContextPile`, `RandomSource`.
- Produces: `FullCardState.new(card_id: StringName, first: HalfCardState, second: HalfCardState)`; `eligible_half_indexes(active_context: int) -> PackedInt32Array`; `reset_effective() -> void`; `CardFactory.build_opening_hand(piles: Dictionary, rng: RandomSource) -> Array[FullCardState]`; `CardFactory.draw_replenishment(piles: Dictionary, request: Dictionary, rng: RandomSource) -> Array[FullCardState]`; `CardFactory.complete_request(partial: Dictionary, needed_halves: int, rng: RandomSource) -> Dictionary`.

- [ ] **Step 1: Write failing hand-construction tests**

Assert opening hands draw exactly four halves from A/B/C and pair as two AB, two AC, two BC; later requests pair all drawn halves randomly and permit AA/BB/CC; returned full-card IDs are stable and unique; completing a partial request preserves selected quantities, totals `2 * missing_cards`, and never exceeds five from one context.

- [ ] **Step 2: Add invalid-request cases**

Assert rejection for odd total, total not matching missing cards, negative quantity, more than five of one context, or unknown context key.

- [ ] **Step 3: Run the targeted test and verify failure**

Expected: missing `FullCardState`/`CardFactory`.

- [ ] **Step 4: Implement full cards and opening-hand construction**

Opening pairing is constrained; later pairing shuffles the combined drawn halves once and pairs adjacent values.

- [ ] **Step 5: Implement partial request completion and validation**

Randomly fill only missing slots while respecting the cap. Return a stable validation error rather than partially drawing on invalid input.

- [ ] **Step 6: Run all tests**

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/cards tests/core/cards
git commit -m "feat: add full card dealing and replenishment"
```

### Task 4: Data-Driven Normal-Hand Evaluation

**Files:**
- Create: `src/core/common/rational.gd`
- Create: `src/core/scoring/scoring_types.gd`
- Create: `src/core/scoring/normal_hand_definition.gd`
- Create: `src/core/scoring/normal_hand_evaluator.gd`
- Test: `tests/core/scoring/normal_hand_evaluator_test.gd`

**Interfaces:**
- Consumes: selected effective rank/suit faces from `FullCardState`.
- Produces: `SelectedCardFace(card_id: StringName, half_index: int, rank: int, suit: int)`; `ScoreModifier(operation: StringName, value: Rational, source_id: StringName)`; `NormalHandDefinition(id: StringName, priority: int, subset_size: int, rule_id: StringName, multiplier: Rational)`; `NormalHandResult`; `NormalHandEvaluator.evaluate(faces: Array[SelectedCardFace], definitions: Array[NormalHandDefinition]) -> NormalHandResult`.

- [ ] **Step 1: Write failing evaluator tests with fixture definitions**

Assert `Rational` construction normalizes signs and reduces fractions. Use test-only definitions for `high_card`, `pair`, `three_kind`, `straight`, and `full_house`. Assert exact subset sizes, fixed priority selection, highest tie-break within a category, and that ranks `3,8,9` classify as Nine High while retaining all three faces for later base summation.

- [ ] **Step 2: Add classification-before-buff coverage**

Assert that a full-house submission locks `full_house` even when a contained pair fixture has a numerically larger modified multiplier supplied after classification.

- [ ] **Step 3: Run the targeted test and verify failure**

Expected: missing evaluator types.

- [ ] **Step 4: Implement normalized `Rational` values and scoring data types**

- [ ] **Step 5: Implement combination enumeration and rule registry**

Expose rule handlers by stable `rule_id`; do not embed production balance values. Select by definition priority, then by rule-specific deterministic tie-break.

- [ ] **Step 6: Run all tests**

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/common/rational.gd src/core/scoring tests/core/scoring
git commit -m "feat: evaluate normal hand subsets"
```

### Task 5: Context Evaluation and Exact Score Arithmetic

**Files:**
- Create: `src/core/scoring/context_hand_definition.gd`
- Create: `src/core/scoring/context_hand_evaluator.gd`
- Create: `src/core/scoring/score_calculator.gd`
- Test: `tests/core/scoring/context_and_score_test.gd`

**Interfaces:**
- Consumes: submitted `FullCardState` values, `NormalHandResult`, ordered score modifiers.
- Produces: normalized `Rational`; `ContextHandDefinition(id: StringName, priority: int, minimums: Dictionary, multiplier: Rational)`; `ContextHandEvaluator.evaluate(cards: Array[FullCardState], definitions: Array[ContextHandDefinition]) -> ContextHandResult`; `ScoreCalculator.calculate(faces: Array[SelectedCardFace], normal: NormalHandResult, context: ContextHandResult, modifiers: Array[ScoreModifier]) -> ScoreBreakdown`.

- [ ] **Step 1: Write failing rational and context tests**

Assert reduction, multiply/add, comparison, zero floor, and ceiling. Assert A4/B3/C1 qualifies for `abc_1` and `ab_3` but locks only the higher-priority category. Assert one AB card locks `no_context` with multiplier 1/1.

- [ ] **Step 2: Write the scoring example test**

For submitted ranks `3,8,9`, assert base value 20; apply fixture normal/context multipliers and ordered modifiers; assert exact intermediate rational and one final upward rounding only.

- [ ] **Step 3: Run the targeted test and verify failure**

Expected: missing `Rational`/context evaluator/calculator.

- [ ] **Step 4: Implement rational arithmetic, inclusive thresholds, and score calculation**

`ScoreModifier` applies in the already-resolved array order; card-specific ordering remains content/controller responsibility.

- [ ] **Step 5: Run all tests**

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add src/core/common/rational.gd src/core/scoring tests/core/scoring
git commit -m "feat: add context and score evaluation"
```

### Task 6: Ability Zones, Effective Card Changes, and Fields

**Files:**
- Create: `src/core/abilities/ability_deck_state.gd`
- Create: `src/core/abilities/ability_definition.gd`
- Create: `src/core/abilities/ability_state.gd`
- Create: `src/core/abilities/field_state.gd`
- Create: `src/core/abilities/effect_registry.gd`
- Create: `src/core/events/event_kinds.gd`
- Create: `src/core/events/domain_event.gd`
- Test: `tests/core/abilities/ability_state_test.gd`

**Interfaces:**
- Consumes: card state, `Rational`, game types.
- Produces: four ability timing categories; shared draw/used zone operations; effect handler contract `validate(context: Dictionary) -> StringName` and `apply(context: Dictionary) -> Array[DomainEvent]`; field duration/conflict-group operations.

- [ ] **Step 1: Write failing ability-zone tests**

Cover shared draw/recycle, short draw when all cards are held/active, player hand limit data, completed effective overrides persisting across rounds, reset only when a full card leaves hand, and active fields excluded from recycling.

- [ ] **Step 2: Write failing field tests**

Cover simultaneous unrelated fields, newest-wins replacement in one conflict group, played round counting as duration one, End decrement, expiry to used pile, and persistence after source-player removal.

- [ ] **Step 3: Run the targeted tests and verify failure**

Expected: missing ability state classes.

- [ ] **Step 4: Implement ability definitions, runtime cards, and shared deck zones**

Definitions contain stable IDs/tags; runtime states contain copy ID and zone. Keep concrete card catalogue out of this task.

- [ ] **Step 5: Implement domain event types and effect registry**

- [ ] **Step 6: Implement persistent field state and conflict handling**

- [ ] **Step 7: Run all tests**

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add src/core/abilities src/core/events tests/core/abilities
git commit -m "feat: add ability and field state"
```

### Task 7: Match Configuration, Players, Setup, and Victory Progress

**Files:**
- Create: `src/core/match/match_config.gd`
- Create: `src/core/match/player_state.gd`
- Create: `src/core/match/match_state.gd`
- Test: `tests/core/match/match_setup_test.gd`

**Interfaces:**
- Consumes: piles, card factory, ability zones, scoring definitions.
- Produces: immutable-after-start `MatchConfig`; dynamic `PlayerState`; `MatchState.create(config: MatchConfig, seed: int)`; `MatchState.to_dict() -> Dictionary`; `MatchState.from_dict(data: Dictionary) -> MatchState`; setup for 2–4 active players and 0–4 spectators; score-race and round-win-race progress methods.

- [ ] **Step 1: Write failing config validation tests**

Reject fewer than two or more than four initial active players, more than four spectators, nonpositive victory targets/timers, and setting changes after `match_started`.

- [ ] **Step 2: Write failing setup and victory tests**

Assert Round 1 context A, six-card constrained hands, two setup abilities plus one Start draw, score/round-win thresholds using `>=`, nil ties awarding nothing, and immediate last-player-standing victory.

- [ ] **Step 3: Run targeted tests and verify failure**

- [ ] **Step 4: Implement match configuration and setup state**

Store players in a dictionary keyed by stable player ID plus a seat-order array; never encode four named player fields.

- [ ] **Step 5: Run all tests**

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add src/core/match tests/core/match
git commit -m "feat: add match setup and victory state"
```

### Task 8: Command/Event Protocol and Start Phase Controller

**Files:**
- Create: `src/core/commands/command_kinds.gd`
- Create: `src/core/commands/game_command.gd`
- Create: `src/core/commands/command_result.gd`
- Create: `src/core/match/match_controller.gd`
- Test: `tests/core/match/start_phase_controller_test.gd`
- Test: `tests/core/match/command_validation_test.gd`

**Interfaces:**
- Consumes: `MatchState`, host monotonic `now_msec`, commands.
- Produces: `MatchController.new(state: MatchState)`; `submit(command: GameCommand, now_msec: int) -> CommandResult`; `tick(now_msec: int) -> Array[DomainEvent]`; stable `CommandResult.accepted`, `.error_code`, `.events`.

- [ ] **Step 1: Write failing Start-phase command tests**

Assert Round 1 stays A, Round 2 advances A→B, partial replenishment is completed at timeout, Public mode emits distribution/count events, Private mode suppresses them, cards pair privately, ability draw follows replenishment, and all-ready advances early.

- [ ] **Step 2: Write invalid-command immutability tests**

Serialize state before malformed, wrong-player, duplicate-ID, and out-of-phase commands; assert stable rejection code and identical serialization afterward.

- [ ] **Step 3: Run targeted tests and verify failure**

- [ ] **Step 4: Implement command kinds, command values, and command results**

- [ ] **Step 5: Implement the Start controller paths**

Deduplicate accepted command IDs per player. Controller methods are the only mutation entry points after setup.

- [ ] **Step 6: Run all tests**

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/commands src/core/match/match_controller.gd tests/core/match
git commit -m "feat: control start phase commands"
```

### Task 9: Main 1 Public Actions, Reactions, Fields, and Sabotage

**Files:**
- Modify: `src/core/match/match_controller.gd`
- Modify: `src/core/abilities/effect_registry.gd`
- Test: `tests/core/match/main_one_controller_test.gd`

**Interfaces:**
- Consumes: `PLAY_PUBLIC_ABILITY`, `SET_READY`, host timestamps, effect registry.
- Produces: atomic host-receipt-order resolution, readiness reset, reaction deadline, hard deadline, sanitized sabotage events.

- [ ] **Step 1: Write failing timing and ordering tests**

Assert public actions resolve in host receipt order; each accepted action clears all readiness; all-ready cannot close during reaction grace; actions received at or before the hard deadline are accepted; actions after it are rejected; accepted actions finish before phase closure.

- [ ] **Step 2: Write failing ability behavior tests**

Cover unrelated fields coexisting, conflicting newest field replacing old, buff/nerf stacking, a context jump changing the current round immediately, a direction reversal affecting the next Start advancement without changing the current context, and two sabotage actions resolving sequentially against the latest hand.

- [ ] **Step 3: Write sabotage privacy assertions**

Public event names ability and target; owner-private event contains removed card; attacker event confirms success without card identity.

- [ ] **Step 4: Run targeted tests and verify failure**

- [ ] **Step 5: Implement Main 1 controller paths**

- [ ] **Step 6: Run all tests**

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/match src/core/abilities tests/core/match/main_one_controller_test.gd
git commit -m "feat: resolve main phase abilities"
```

### Task 10: Private Hand-Play Staging, Commitment, and Reveal

**Files:**
- Modify: `src/core/match/player_state.gd`
- Modify: `src/core/match/match_controller.gd`
- Test: `tests/core/match/hand_play_controller_test.gd`

**Interfaces:**
- Consumes: begin/cancel/complete manipulation commands, staged selection, face choices, lock/pass, timeout.
- Produces: private staging state; irreversible completed manipulation; auto-submit of valid staged hand; public sanitized reveal and private exact result.

- [ ] **Step 1: Write failing manipulation transaction tests**

Assert incomplete targeting may cancel without consumption; completing final choice consumes ability and persists override; completed effect cannot undo; a spent effect remains spent even if player passes; unplayed modified card persists into next round.

- [ ] **Step 2: Write failing submission tests**

Assert zero-card pass, 1–6 eligible cards, rejection of any card lacking active context, explicit half choice for double-active card, timeout auto-lock of valid staging, incomplete manipulation cancellation at timeout, and no staging becoming pass.

- [ ] **Step 3: Write reveal/scoring tests**

Assert all submitted ranks enter base sum, best normal subset locks, all submitted effective contexts enter context evaluation, manipulation ability ID is public, and exact target/change history is absent from public events.

- [ ] **Step 4: Run targeted tests and verify failure**

- [ ] **Step 5: Implement staging and reveal paths**

- [ ] **Step 6: Run all tests**

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/match tests/core/match/hand_play_controller_test.gd
git commit -m "feat: add private hand play submission"
```

### Task 11: Main 2, Atomic End, Cleanup, and Match Completion

**Files:**
- Modify: `src/core/match/match_controller.gd`
- Test: `tests/core/match/end_phase_controller_test.gd`

**Interfaces:**
- Consumes: locked provisional results, Main 2 score modifiers, End ability discard choices/timeouts.
- Produces: integer finalized scores, unique winner/nil tie, progress award, cleanup, field ticks, match completion/rematch reset.

- [ ] **Step 1: Write failing Main 2 tests**

Assert only permitted buff/nerf categories play; score changes but normal/context classification does not; public reaction rules match Main 1.

- [ ] **Step 2: Write failing End transaction tests**

Assert one ceiling after all modifiers, zero floor, unique winner award in both modes, tied highest score producing nil, played cards resetting/splitting by original context, kept cards retaining overrides, and fields decrementing after scoring.

- [ ] **Step 3: Write ability hand-limit timeout tests**

Assert confirmed discard choices reach three; unconfirmed timeout randomly discards enough; identity visibility follows match setting.

- [ ] **Step 4: Write atomic disconnect and rematch tests**

Inject a disconnect notification during End and assert the committed round is not rescored/voided. Assert normal victory returns to unlocked lobby state and rematch reset clears scores/decks/fields/context while preserving occupants.

- [ ] **Step 5: Implement Main 2 and End**

- [ ] **Step 6: Run all tests**

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/match tests/core/match/end_phase_controller_test.gd
git commit -m "feat: finalize rounds and matches"
```

### Task 12: Late Join, Reconnect/Forfeit State, and Sanitized Snapshots

**Files:**
- Create: `src/core/match/snapshot_projector.gd`
- Modify: `src/core/match/match_controller.gd`
- Test: `tests/core/match/player_lifecycle_test.gd`
- Test: `tests/core/match/snapshot_projector_test.gd`

**Interfaces:**
- Consumes: join/spectate/disconnect/reconnect/forfeit commands and recipient ID/role.
- Produces: pending active entry at next Start, spectator state, frozen reconnect state with independent deadlines, forfeiture cleanup, `SnapshotProjector.for_recipient(state: MatchState, recipient_id: StringName, role: int) -> Dictionary`.

- [ ] **Step 1: Write failing late-entry and spectator tests**

Assert seat/spectator caps; pending player does not affect current readiness; next Start grants zero progress, constrained opening hand, two setup abilities plus one Start draw; short ability draw is legal; spectator never affects phase progression.

- [ ] **Step 2: Write failing reconnect/forfeit tests**

Assert gameplay freezes on first disconnect; all gameplay commands reject while frozen; independent grace deadlines; reconnect restores private state; expiry resets/discards cards and abilities, retains fields, resumes only after every disconnect resolves, and awards last-player-standing victory.

- [ ] **Step 3: Write private-data leak tests**

Recursively scan projected dictionaries. Public/spectator projections must omit private full-card identities, ability hands, manipulation target history, hidden discards, base identities, RNG state, and Private-mode pile/request counts. A player projection contains only that player's private values.

- [ ] **Step 4: Run targeted tests and verify failure**

- [ ] **Step 5: Implement lifecycle controller paths and projector**

- [ ] **Step 6: Run the complete core suite**

Expected: exit 0 with every test PASS and no Godot parser warnings.

- [ ] **Step 7: Commit**

```bash
git add src/core/match tests/core/match
git commit -m "feat: add player lifecycle and snapshots"
```

## Core Plan Completion Gate

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

Expected: all core tests pass headlessly. No network plugin, signaling service, UI scene, or export template is required for this gate.
