# Field Abilities Design

**Date:** 2026-11-22
**Status:** Implemented
**Scope:** Field catalogue, lifecycle modes, Resonance eligibility, field scoring, snapshots, UI, and deterministic tests

## Intent

Implement the fifteen designed Field Effect cards as authoritative, data-driven abilities. Field effects are public global state. Unrelated effects coexist, score-producing effects stack additively inside the single field multiplier, and only logically conflicting clock-direction effects replace one another.

## Goals

- Add all fifteen field definitions to the live ability catalogue and provisional deck.
- Support instant, timed, and persistent field lifecycles.
- Keep the base clock context separate from temporary Resonance contexts.
- Make card eligibility, staging, reveal, rescoring, snapshots, and UI agree on every active context.
- Calculate Suit Favor, Rank Favor, and Context Ascendancy as field multiplier components.
- Preserve host authority, serialization, reconnect behavior, and spectator-safe public information.
- Keep field definitions and copy counts independently adjustable.

## Non-goals

- Final balance of copy counts or multiplier values.
- Final names for Suit 1, Suit 2, and Suit 3.
- New artwork or field animations.
- Sabotage implementation.
- Host migration or dedicated-server authority.

## Approaches Considered

### Hardcoded card IDs in `MatchController`

The controller could switch on every definition ID. This is quick for the first cards but couples catalogue content, eligibility, scoring, lifecycle, and UI projection to one large controller.

### Data-driven field rules — chosen

Definitions carry trusted rule parameters. A shared field resolver derives the active-context set and field multiplier components from active `FieldState` objects. Existing effect handlers continue to perform immediate clock mutations.

This matches the project's data-driven manipulation and hand-shape catalogues, produces inspectable score components, and lets later field cards reuse rule types without controller branches.

### Materialize player modifiers when a field is played

Each field could copy modifiers onto all players. This makes expiration, late joining, reconnects, and submissions formed after activation harder to reconcile, so it is rejected.

## Catalogue

All cards use `Timing.FIELD`, are legal only in Main 1, target all players, and require no private target selection.

| Definition IDs | Cards | Lifecycle | Rule |
|---|---|---|---|
| `shift_to_rise`, `shift_to_flourish`, `shift_to_fall` | Shift to Rise/Flourish/Fall | Instant | Set the base clock context immediately without changing direction. |
| `reverse_cycle` | Reverse Cycle | Persistent | Reverse direction immediately and remain publicly active until a later conflicting direction effect replaces it. |
| `rise_resonance`, `flourish_resonance`, `fall_resonance` | Context Resonance | 1 round | Add the named context to the active-context set without moving the clock. |
| `suit_1_favor`, `suit_2_favor`, `suit_3_favor` | Suit Favor | 3 rounds | Add `+0.1` per submitted card whose selected scoring face has that suit. |
| `even_rank_favor`, `odd_rank_favor` | Rank Favor | 3 rounds | Add `+0.1` per selected non-Joker scoring face with the named parity. |
| `rise_ascendancy`, `flourish_ascendancy`, `fall_ascendancy` | Context Ascendancy | 3 rounds | Add `+0.25` when the named context's full submitted-hand tally is strictly greater than each other context tally. Ties give no bonus. |

The provisional recipe uses one copy of every Shift, Reverse, Favor, and Ascendancy card, and four copies of each Resonance card. These are balance values, not behavior.

## Lifecycle Representation

`AbilityDefinition.field_duration` keeps one named convention:

- `0`: instant field; consume into the used pile after applying its immediate effect;
- positive integer: active for that many rounds, counting the round played;
- `FIELD_DURATION_PERSISTENT`: active with no timer.

The persistent value is exposed as a named constant rather than repeated as a magic number. `FieldState.tick_end()` never decrements persistent fields. Timed fields retain current end-of-round ticking behavior.

Instant fields emit the normal public ability and field-played events but do not enter `active_fields` and do not later emit expiration. Persistent fields serialize and reconnect with their persistent state intact. Public snapshots identify persistence explicitly, while retaining `remaining_rounds` for timed fields. The field UI displays `Persistent` instead of a negative or zero round count.

## Conflict and Clock Semantics

- Unrelated active fields coexist.
- Duplicate score fields also coexist; each active copy contributes separately.
- Resonance fields form a set union, so duplicate Resonance copies do not create duplicate contexts.
- Reverse Cycle uses the direction conflict group. A later conflicting direction card replaces the currently active direction field before applying its own immediate direction change.
- Shift cards are instant clock-position changes and therefore leave no active conflict record.
- Resonance never changes `active_context`, `context_direction`, or the next clock step.

## Active Contexts and Submission Eligibility

The active-context set is the base `MatchState.active_context` plus every context supplied by an active Resonance field. It is sorted and deduplicated.

A full card is eligible when either half is a Joker or at least one normal half's effective context belongs to this active set. The submitted `half_index` must identify a Joker or a normal half in the active set. When both halves are eligible, the player chooses which scoring face to use, as with a same-context card today.

Joker rules remain staged-only:

- a Joker is eligible in every active context;
- its staged context choice contributes to the full two-half context tally;
- if its half is selected as the scoring face, its staged suit counts for Suit Favor and Flush;
- its rank remains `0`, so it never qualifies for even or odd Rank Favor.

Snapshots expose `active_contexts` publicly and calculate owner-private `eligible_half_indexes` from the same set. The clock continues to display the base context, with Resonance represented through active fields and the additional-context display state.

## Field Scoring

A shared `FieldEffectResolver` receives:

- active fields;
- selected scoring faces;
- the resolved full submitted-hand context counts.

It emits zero or more `MultiplierComponent` objects with `factor_id = field`, `category_id = field`, the source definition ID, and an exact `Rational` contribution.

The score calculator already treats field components as `1 + sum(component values)` and floors the resulting factor to `1`. Therefore:

- one Suit Favor matching three selected faces contributes `+0.3`, for a `1.3x` field factor by itself;
- two matching Favor copies each contribute and stack;
- independent Suit, Rank, and Ascendancy cards add within the same factor;
- the field factor then multiplies base value, card-hand factor, and context-hand factor once.

Zero-contribution fields are omitted from score components. This keeps public score breakdowns concise without changing the result.

## Data-Driven Rule Parameters

Resonance and scoring definitions use a common non-mutating field effect handler with trusted parameters such as:

```gdscript
{"field_rule": &"additional_context", "context": GameTypes.Context.RISE}
{"field_rule": &"per_selected_suit", "suit": GameTypes.Suit.ONE,
 "numerator": 1, "denominator": 10}
{"field_rule": &"per_selected_rank_set", "ranks": [2, 4, 6, 8, 10],
 "numerator": 1, "denominator": 10}
{"field_rule": &"strict_context_majority", "context": GameTypes.Context.RISE,
 "numerator": 1, "denominator": 4}
```

The handler validates known rule IDs, context/suit/rank domains, and nonzero rational denominators before a card is consumed. Clients still submit only the held ability copy; they cannot author effect parameters.

## Controller Integration

- Staging and locking call `SubmissionEvaluator` with the derived active-context set and active fields.
- `SubmissionEvaluator` resolves cards once, evaluates the normal hand and context hand, derives field components, and calculates the score.
- Main 2 buff/nerf recalculation and final end-phase calculation reuse the player's already resolved faces/context result plus currently active fields.
- Field cards are Main 1 only, so no scoring field can be introduced after reveal. Recalculation is still centralized to prevent divergence.
- End-of-round ticking expires one-round Resonance immediately after it affected that round and decrements three-round score fields from `3` to `2`.

## Serialization, Network, and UI

- Ability definitions serialize all field parameters and lifecycle values through existing config serialization.
- Active timed and persistent fields serialize through `AbilityDeckState`.
- Recipient-safe snapshots expose definition ID, source player, persistence, and remaining timed rounds.
- `active_contexts` is public because active fields and the base clock are public.
- Public score breakdowns already carry field components and field factors; the new components use that existing contract.
- The match screen renders persistent duration correctly and uses `active_contexts` for card eligibility/highlighting while leaving the base clock position unchanged.

No private card information is added to field events or public snapshots.

## Testing Strategy

### Catalogue and validation

- Fifteen unique field IDs with correct timing, tags, parameters, names, and rules text.
- Provisional recipe has the intended independent copy counts.
- Malformed field rules are rejected before consumption.

### Lifecycle

- Instant Shift cards enter the used pile without entering active fields.
- Timed fields count the played round and expire at the correct end phase.
- Reverse Cycle survives arbitrary round ticks and save/restore.
- A later direction conflict replaces the prior persistent card.

### Context eligibility

- Each Resonance adds its context without moving the base clock.
- Multiple Resonances union correctly.
- A card eligible only through Resonance can stage, lock, serialize, and reveal.
- Client projections and UI use the same eligible half indexes.

### Scoring

- Suit Favor counts selected faces, including a selected Joker's chosen suit.
- Rank Favor counts only its exact rank set and excludes Joker rank `0`.
- Ascendancy uses both resolved halves of every submitted card and rejects ties.
- Duplicate and unrelated field copies stack additively.
- Provisional, Main 2 recalculated, serialized, projected, and finalized score breakdowns agree.

### Regression

- Existing manipulation, hand buff/nerf, phase, reconnect, privacy, UI, and network fixtures remain green.

## Acceptance Criteria

- All fifteen field cards are playable from the live deck during Main 1.
- Shift, Reverse, Resonance, and the nine scoring fields match the rules above.
- Reverse Cycle is persistent without a timer.
- Resonance lasts exactly the round played and has four provisional copies per context.
- Score fields last three rounds including the round played.
- Multiple fields and duplicate score fields stack correctly.
- Joker, serialization, network projection, reconnect, and UI behavior are deterministic and covered by tests.
