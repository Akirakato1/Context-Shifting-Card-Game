# Hand Buff/Nerf Abilities Design

**Status:** Approved
**Date:** 2026-11-22
**Scope:** Generalized scoring factors and the sixteen Hand Buff/Nerf ability designs

## Intent

Replace the current ordered final-score modifier prototype with a generalized factor-based scoring model. A score consists of four multiplicative layers, while every contribution inside a layer combines additively:

```text
final score = ceil(
    base value
    × max(1, card-hand factor)
    × max(1, context-hand factor)
    × max(1, field factor)
)
```

Hand Buff/Nerf abilities add a signed value to one named category inside the card-hand or context-hand factor. Each played ability contributes at most once to a submitted hand. The category catalogue and signed values are data, so exact hand definitions, balance values, and physical copy counts can change without adding card-specific controller paths.

## Goals

- Generalize scoring into additive contributions within four multiplicative layers.
- Keep a valid non-pass hand's rank structure mutually exclusive: High Card, Straight, Family, or Group.
- Detect Flush as an orthogonal card-hand component that can stack with any rank structure.
- Classify the selected context-hand definition as Single Context, Two Context, or Three Context.
- Implement one buff and one nerf for every category: sixteen designs total.
- Apply each ability once per submitted hand, regardless of how many pairs, triples, contexts, or cards occur inside the matched shape.
- Let separate played abilities stack additively in any receipt order.
- Clamp the card-hand, context-hand, and field factors independently to a minimum of `1` after all additions and subtractions.
- Keep exact hand shapes, base multipliers, modifier values, and deck copy counts data-driven.
- Preserve host-authoritative validation, public ability resolution, reconnect serialization, and deterministic scoring.

## Non-goals

- Final exact normal-hand definitions or their multiplier values.
- Final context-hand multiplier values.
- Final buff/nerf values; `+3` and `-3` are placeholders.
- Final physical copy counts for any ability design.
- A finalized score-changing Field ability catalogue. This design provides the field-factor structure only.
- Final ability names, artwork, icons, animation, or audio.
- Reclassifying an already locked hand in Main 2.
- Applying one ability repeatedly for each pair, triple, card, or context inside a matching hand.

## Existing constraints

- Hand Buff/Nerf abilities are public targeted abilities.
- They may be played during Main 1 or Main 2.
- They may target the source player or another active player.
- They last for the current round and are cleared during normal End cleanup.
- Main 1 effects wait for the target's eventual locked hand classification.
- Main 2 effects operate on the classification locked during Hand Play and update the provisional score immediately.
- Public abilities resolve atomically in host receipt order, clear every active player's Ready state, and open the existing reaction window.
- Multiple non-conflicting buffs and nerfs stack; no newest-wins replacement rule applies.
- A pass has base value `0` and scores `0` regardless of neutral factor floors.
- Final score uses one ceiling operation after all exact rational arithmetic.

## Approaches considered

### Selected: independent data-driven scoring components

The hand evaluators return explicit multiplier components. A valid non-pass normal result contains exactly one rank-structure component and may also contain one Flush component. A context result contains the one category attached to the selected exact context-hand definition. The score calculator aggregates component values and matching signed modifiers inside their factor, clamps each multiplier factor to at least `1`, multiplies the layers, then applies one final ceiling.

This keeps classification authoritative, supports Straight Flush and other rank-plus-Flush combinations naturally, and lets unfinished exact hand catalogues be added later without changing ability behavior.

### Rejected: combined definition for every category combination

Every exact hand could store a combined multiplier such as Straight Flush. This would require explicit definitions for every rank/suit combination and would couple future balance changes to a growing combination table.

### Rejected: re-detect categories inside the score calculator

The calculator could inspect submitted faces again when applying modifiers. That would duplicate evaluator logic and allow classification and scoring to disagree.

## Scoring terminology

### Base value

Base value is the additive sum of every selected effective rank in the submitted hand, plus any future effects explicitly assigned to the base-value layer. It is not clamped to `1`; a pass or an all-zero submission may score `0`.

### Card-hand factor

The card-hand factor contains:

1. The multiplier contribution of exactly one selected rank-structure hand.
2. The Flush multiplier contribution when every submitted selected face has the same suit and the Flush rule is satisfied.
3. Every Hand Buff/Nerf modifier whose category matches one of those components.

Before clamping:

```text
card-hand factor = rank component + optional Flush component + matching modifiers
```

Examples:

- A six-card Straight without Flush has the six-card Straight contribution.
- A six-card Straight Flush has the six-card Straight contribution plus the applicable Flush contribution.
- A Family Flush has its selected Family contribution plus the Flush contribution.
- A Group such as Full House receives the Group contribution, not separate Pair and Triple contributions.

### Context-hand factor

Every exact context-hand definition declares one broad category:

- Single Context
- Two Context
- Three Context

The selected highest-priority context-hand definition contributes its own multiplier once. Matching context buffs and nerfs are added once each. Contained or lower-priority context shapes do not contribute separately.

```text
context-hand factor = selected context-hand contribution + matching modifiers
```

### Field factor

The field factor starts at neutral `1`. Future score-changing Field effects may add signed contributions to it. Existing non-score Field effects contribute nothing.

```text
field factor = 1 + active score-changing field contributions
```

The factor is included now so the generalized formula does not need another structural rewrite when those Field cards are designed.

### Factor floors and final rounding

After all contributions are summed:

- `card-hand factor = max(1, card-hand factor)`
- `context-hand factor = max(1, context-hand factor)`
- `field factor = max(1, field factor)`

The exact rational factors multiply the integer base value. The game performs one ceiling operation on the final product. There is no intermediate rounding.

## Normal-hand category model

The exact normal-hand catalogue remains unfinished, but every definition must map to one of four mutually exclusive rank categories:

| Broad category | Included exact shapes |
| --- | --- |
| High Card | A one-card matched subset used as the rank structure, even when the submission contains additional cards |
| Straight | A consecutive sequence of the required length |
| Family | Pair, Three of a Kind, Four of a Kind, Five of a Kind, Six of a Kind |
| Group | Two Pairs, Two Triples, Three Pairs, Full House, and future grouped rank structures |

Flush is an independent suit component rather than a fifth mutually exclusive rank category. It is present only when the eventual Flush rule accepts the entire submitted hand. A normal hand therefore exposes:

- Exactly one rank-category component for a valid non-pass submission.
- Zero or one Flush component.

The evaluator continues to choose the authoritative rank shape by definition priority and tie-break rules. Score effects never reclassify that choice.

## Context-hand category model

Every exact context-hand definition stores one category tag:

| Broad category | Existing shape family |
| --- | --- |
| Single Context | One named context reaches its definition's required count |
| Two Context | A named pair of contexts reaches the definition's required counts |
| Three Context | Rise, Flourish, and Fall all reach the definition's required counts |

The broad category comes from the selected exact definition, not merely from counting how many distinct contexts happen to appear anywhere in the submission. This preserves the rule that only the highest-priority context hand contributes.

## Modifier data model

A round score modifier is immutable data with:

- `factor_id`: `card_hand` or `context_hand` for this catalogue; `field` is reserved.
- `category_id`: one of the approved broad category IDs.
- `delta`: an exact signed rational number.
- `source_copy_id`: the physical ability copy that created it.
- `source_definition_id`: the ability design ID for display and audit.

The modifier does not contain a calculated score, client-proposed applicability result, or hand target. Applicability is derived from the target's authoritative locked scoring components.

Each modifier is considered once. Multiple physical abilities with the same factor and category each contribute once and therefore stack.

## Initial ability catalogue

The following are working names. Every value is provisional. Physical copy counts are deliberately excluded from these definitions and belong to the separately configurable deck recipe.

### Card-hand factor

| ID / working name | Category | Placeholder delta | Printed rules text |
| --- | --- | ---: | --- |
| `high_card_buff` / High Card Buff | High Card | `+3` | Target player gets +3 Card Hand multiplier if their rank hand is High Card this round. |
| `high_card_nerf` / High Card Nerf | High Card | `-3` | Target player gets -3 Card Hand multiplier if their rank hand is High Card this round. |
| `straight_buff` / Straight Buff | Straight | `+3` | Target player gets +3 Card Hand multiplier if their rank hand is a Straight this round. |
| `straight_nerf` / Straight Nerf | Straight | `-3` | Target player gets -3 Card Hand multiplier if their rank hand is a Straight this round. |
| `family_buff` / Family Buff | Family | `+3` | Target player gets +3 Card Hand multiplier if their rank hand is a Family this round. |
| `family_nerf` / Family Nerf | Family | `-3` | Target player gets -3 Card Hand multiplier if their rank hand is a Family this round. |
| `group_buff` / Group Buff | Group | `+3` | Target player gets +3 Card Hand multiplier if their rank hand is a Group this round. |
| `group_nerf` / Group Nerf | Group | `-3` | Target player gets -3 Card Hand multiplier if their rank hand is a Group this round. |
| `flush_buff` / Flush Buff | Flush | `+3` | Target player gets +3 Card Hand multiplier if their hand is a Flush this round. |
| `flush_nerf` / Flush Nerf | Flush | `-3` | Target player gets -3 Card Hand multiplier if their hand is a Flush this round. |

### Context-hand factor

| ID / working name | Category | Placeholder delta | Printed rules text |
| --- | --- | ---: | --- |
| `single_context_buff` / Single Context Buff | Single Context | `+3` | Target player gets +3 Context Hand multiplier if their context hand is Single Context this round. |
| `single_context_nerf` / Single Context Nerf | Single Context | `-3` | Target player gets -3 Context Hand multiplier if their context hand is Single Context this round. |
| `two_context_buff` / Two Context Buff | Two Context | `+3` | Target player gets +3 Context Hand multiplier if their context hand is Two Context this round. |
| `two_context_nerf` / Two Context Nerf | Two Context | `-3` | Target player gets -3 Context Hand multiplier if their context hand is Two Context this round. |
| `three_context_buff` / Three Context Buff | Three Context | `+3` | Target player gets +3 Context Hand multiplier if their context hand is Three Context this round. |
| `three_context_nerf` / Three Context Nerf | Three Context | `-3` | Target player gets -3 Context Hand multiplier if their context hand is Three Context this round. |

## Definition and deck composition

Every Hand Buff/Nerf definition carries:

- Stable definition ID
- Working display name and printed rules text
- `HAND_SHAPE` timing
- Public target-player choice schema
- Closed factor/category identifiers
- Exact rational signed delta

Ability behavior and physical deck composition are separate. A deck recipe maps definition IDs to provisional copy counts. Changing the number of copies must not require editing an effect definition or controller code. No copy count in this design is final.

## Controller lifecycle

### Targeting and validation

The existing public ability command is retained. The client sends the physical `copy_id`, one target player ID, and the choices dictated by the definition. Before mutation, the host verifies:

- The source is active and the command is legal in Main 1 or Main 2.
- The physical ability is still held by the source.
- Its timing is Hand Buff/Nerf.
- The target exists, is active, and is not pending entry.
- Self-targeting is allowed.
- Factor, category, and delta come exclusively from the authoritative definition.
- The factor/category combination belongs to the closed approved vocabulary.
- The phase deadline has not passed.

The client never submits a delta, factor, category, claimed hand type, or calculated score.

### Resolution

On successful validation, the host atomically:

1. Removes the physical ability from the source's hand.
2. Places it in the shared used pile.
3. Appends one immutable factor modifier to the target player.
4. Publishes the ability ID, source, and target.
5. Clears every active player's Ready state and refreshes the public reaction window.
6. During Main 2, recalculates and publishes the target's provisional score without changing locked classifications.

Receipt order is retained for event presentation, but additive modifier results are order-independent.

### End cleanup

All Hand Buff/Nerf modifiers remain active through final End scoring, then are cleared with the existing round-only score state. They never persist into the next round.

## Scoring flow

For every active non-pending player:

1. Resolve selected effective faces and calculate base value.
2. Use the locked normal result to obtain one rank component and optional Flush component.
3. Sum those normal component multipliers.
4. Add every matching `card_hand` modifier once.
5. Clamp the result to at least `1`.
6. Read the locked context definition's category and multiplier.
7. Add every matching `context_hand` modifier once.
8. Clamp the result to at least `1`.
9. Start the field factor at `1`, add future score-changing Field contributions, and clamp to at least `1`.
10. Multiply base value and all three factors using exact rational arithmetic.
11. Apply one final ceiling to obtain the integer round score.

A pass bypasses normal/context classification and remains score `0`.

## UI behavior

- Mountain King Regular is the general interface typeface. It is licensed under CC BY 4.0 by Michael W. Moss and must ship with attribution and the license link.
- Card-rank faces are the exception to the general typeface: ranks `0` through `10` render from the supplied `assets/artwork/card_number` images, with rank `10` composed from the `1` and `0` artwork.
- The ability drawer shows the card's name, target category, signed value, and printed rules text.
- Right-clicking or otherwise activating the card enters the existing public target-player selection flow.
- Every active player, including the source, is a legal target.
- Played cards are public immediately in both Main phases.
- Main 1 may display the modifier as pending applicability because the target has not locked a hand.
- Main 2 shows the recalculated provisional score immediately.
- The score breakdown should show base value, card-hand components and adjustments, context-hand component and adjustments, field adjustments, factor floors, and the final ceiling.
- Art, animation, and audio remain separate View work.

## Serialization, privacy, and reconnects

Factor modifiers and scoring components must survive canonical match-state serialization and reconnect round trips. Their values are not secret after the public ability resolves, but private cards and unrevealed hands remain private.

Public snapshots and events may expose:

- Played ability definition ID
- Source player
- Target player
- Signed modifier value described by the public card definition
- Updated provisional score after Hand Play

They must not expose the target's unrevealed Main 1 hand or predict whether the modifier will eventually match.

## Failure behavior

- A malformed, foreign, duplicate, inactive-target, out-of-phase, or late command rejects without consuming the ability or adding a modifier.
- A valid ability is consumed even if the target's eventual hand does not match its category.
- An unmatched modifier contributes `0`; it is not refunded.
- A matched ability contributes once even if multiple internal structures satisfy the broad category.
- Multiple matching abilities stack, including opposing buffs and nerfs.
- Factor floors are applied after all matching additions and subtractions.

## Verification

Tests must cover:

- Sixteen unique stable definitions with all factor/category/delta combinations.
- Definition metadata and deck-recipe copy counts surviving config round trips independently.
- Exact-hand definitions carrying authoritative broad-category data.
- One mutually exclusive rank component plus optional Flush.
- Straight Flush, Family Flush, and Group Flush additive component scoring.
- Full House contributing Group only, not Pair and Triple separately.
- Context definitions mapping to Single, Two, or Three Context by definition metadata.
- One-hit application for every ability, including Group shapes with several pairs or triples.
- Multiple same-category abilities stacking once each.
- Opposing buff and nerf additions being order-independent.
- Independent minimum-`1` clamps for card-hand, context-hand, and field factors.
- A pass remaining score `0`.
- One final ceiling with no intermediate rounding.
- Main 1 applicability waiting for locked classification.
- Main 2 immediate provisional-score recalculation without reclassification.
- Self-targeting and opponent targeting.
- Rejection preserving ability zones, modifiers, Ready state, reaction deadline, and score.
- Public event/snapshot safety before hand reveal.
- Modifier and component serialization/reconnect round trips.
- Existing core, UI, signaling, and multi-process network suites remaining green.

## Deferred decisions

- Exact normal-hand list, priorities, tie-breaks, and multipliers.
- Exact context-hand multipliers.
- Final signed values for each buff and nerf; values need not remain symmetric.
- Final per-design physical copy counts and total deck composition.
- Final score-changing Field effect cards and their field-factor contributions.
- Final card names and presentation assets.
