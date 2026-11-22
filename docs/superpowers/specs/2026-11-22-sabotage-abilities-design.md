# Sabotage Abilities Design

**Date:** 2026-11-22
**Status:** Implemented
**Scope:** Sabotage catalogue, authoritative resolution, persistence, privacy, and public-history contract

## Intent

Sabotage abilities disrupt one opponent's hand during Main 1 without giving the attacker deterministic control over that hand. They are deliberately weaker and less precise than self-targeted card-manipulation abilities. Their strategic value comes from disturbing a plan, not from guaranteeing that a hand becomes unplayable.

Sabotage is distinct from Hand Buff/Nerf:

- Hand Buff/Nerf changes scoring factors and never changes cards.
- Sabotage changes, replaces, re-pairs, or temporarily restricts cards in one opponent's hand.

## Goals

- Provide nine initial, data-driven sabotage definitions.
- Require exactly one eligible opponent target for every sabotage.
- Resolve all randomness on the authoritative host.
- Permit repeated sabotage of the same player and repeated selection of the same card.
- Preserve hidden hand information while publishing the played ability and target player.
- Make lasting changes persist until the affected full card leaves its owner's hand.
- Reset every half-card to its printed values before it returns to a context pile.
- Make the catalogue easy to rebalance and extend without adding a custom handler for every card.
- Produce sanitized events suitable for a public history of the latest 32 events.

## Non-goals

- Multi-target or all-opponent sabotage.
- Attacker-selected cards or half-cards in an opponent's hand.
- Revealing the affected card, its values, its Joker status, or the random result to the attacker.
- Reducing a player's hand below six cards after an immediate replacement effect resolves.
- Final copy-count balancing.
- Implementing every future sabotage mechanic through a completely generic instruction language.
- Retaining a complete match-long event history.

The sabotage resolver must produce the privacy-safe event contract described here. The history view retains only the latest 32 public events.

## Constraints Already Established

- Sabotage is legal only during Main 1.
- The source chooses one opponent; the host chooses all hidden random targets and outcomes.
- The target must be active, connected, non-pending, non-spectating, and different from the source.
- Any number of sabotage abilities may target the same opponent in one round.
- Effects resolve one at a time in host-accepted play order against the latest authoritative hand state.
- A card already affected or temporarily locked remains eligible for later random selection.
- A repeated random result may equal the current value; this is a legitimate outcome.
- Once the source has selected the target and committed the ability, the card is consumed even if the random outcome changes nothing.
- Exact remaining counts in all three context piles are always public.
- When context-draw distribution is public under the lobby information setting, it is announced only as a draw event. It is not maintained as a calculated display of the player's current holdings.
- A draw from a pile never reveals whether its Joker was drawn.

## Approaches Considered

### One handler per ability

Every sabotage definition could have a dedicated effect handler. This is explicit, but it duplicates opponent validation, random selection, Joker behavior, persistent mutation, and privacy-event construction.

### Shared data-driven sabotage resolver — chosen

Definitions use one `sabotage_cards` effect and provide an `operation` plus validated parameters. A shared resolver owns random selection and card mutation. Forced Mulligan remains a specialized `force_redraw` effect because it crosses card, pile, discard, reshuffle, and replacement-draw boundaries.

This follows the existing self-manipulation catalogue and resolver without allowing clients to author hidden targets or effect parameters.

### Fully composable primitive pipeline

Definitions could contain steps such as `pick_random_card`, `pick_random_half`, and `apply_override`. This is maximally extensible but requires a much larger validation language than the initial game-jam catalogue needs.

## Catalogue

All cards use `Timing.SABOTAGE`, carry the tags `sabotage` and `single_target`, and use this choice schema:

```gdscript
{
    "steps": [{
        "key": "target_player_id",
        "kind": "player",
        "count": 1,
        "prompt": "Select an opponent",
    }]
}
```

The live eligible-player list is derived by the host and UI. It is never embedded as authoritative IDs in the definition.

| Definition ID | Name | Rules text | Effect | Operation/parameters |
|---|---|---|---|---|
| `forced_mulligan` | Forced Mulligan | Target opponent replaces 1 random full card. The game randomly chooses both replacement context piles; both choices may be the same. | `force_redraw` | Specialized handler |
| `crossed_wires` | Crossed Wires | The game chooses 2 distinct random full cards in the target's hand. On each card, swap the contexts of its two halves. | `sabotage_cards` | `exchange_contexts`, `card_count = 2` |
| `suit_scramble` | Suit Scramble | Randomize the suit of 1 random non-Joker half in the target's hand. Its current suit can be rolled again. | `sabotage_cards` | `randomize_suit`, `half_count = 1` |
| `rank_scramble` | Rank Scramble | Randomize the rank of 1 random non-Joker half in the target's hand from 1–10. Its current rank can be rolled again. | `sabotage_cards` | `randomize_rank`, `half_count = 1`, `ranks = [1..10]` |
| `context_scramble` | Context Scramble | Randomize the context of 1 random non-Joker half in the target's hand. Its current context can be rolled again. | `sabotage_cards` | `randomize_context`, `half_count = 1`, `contexts = [Rise, Flourish, Fall]` |
| `rank_nudge` | Rank Nudge | Move the rank of 1 random non-Joker half up or down by 1 at random. Rank movement wraps between 1 and 10. | `sabotage_cards` | `nudge_rank`, `amount = 1`, `wrap_min = 1`, `wrap_max = 10` |
| `context_nudge` | Context Nudge | Move the context of 1 random non-Joker half one step with or against the current context-clock direction, chosen at random. | `sabotage_cards` | `nudge_context`, `amount = 1`, `direction_mode = random_relative` |
| `loose_pairing` | Loose Pairing | The game chooses 2 distinct random full cards in the target's hand and swaps 1 random complete half-card between them. | `sabotage_cards` | `swap_halves`, `card_count = 2`, `half_from_each = 1` |
| `momentary_lock` | Momentary Lock | Lock 1 random full card in the target's hand. That card cannot be submitted this round. | `sabotage_cards` | `lock_card`, `card_count = 1`, `expires = round_end` |

Names are presentation data and may be changed without changing operation IDs.

## Detailed Resolution Rules

### Common target validation

Before consuming the ability, the controller validates that:

1. The command contains only the allowed public-ability keys.
2. The ability copy is in the source player's ability hand.
3. The definition is legal in Main 1.
4. `target_player_id` matches the single player choice.
5. The target is an active, connected, non-pending opponent and is not a spectator.
6. The target has enough cards for operations that require two distinct full cards.

The client supplies only the ability copy and target player. It never supplies a card ID, half index, random direction, rolled value, or effect parameter.

### Random selection

- Selection is uniform over the operation's eligible collection.
- Separate sabotage plays sample the full eligible collection again.
- Previously modified or locked cards are not removed from the collection.
- Operations requiring two cards choose two distinct cards within that one resolution.
- Random half operations build an eligible list of non-Joker halves and sample from it.
- If a validated operation has no eligible half because future content creates an all-Joker hand, the ability resolves as a consumed no-op with safe events.

### Crossed Wires

For each of two distinct selected full cards:

- If both halves are normal, exchange only their effective context values. Ranks and suits stay with their current halves.
- If either half is a Joker, that selected card is unchanged because a Joker has no mutable effective context. The other selected card still resolves independently.

This is different from Loose Pairing: Crossed Wires changes context overrides inside each card, while Loose Pairing moves complete half-card objects between cards.

### Random scrambles and nudges

- Suit, rank, and context scrambles operate on current effective values and replace only the named property.
- Scrambles include the current value in their random domain.
- Rank Nudge chooses `-1` or `+1` with equal probability and wraps `1 ↔ 10`.
- Context Nudge chooses with-clock or against-clock movement with equal probability and uses the direction active when the ability resolves.
- Later effects operate on the effective state left by earlier effects.

### Loose Pairing

- Choose two distinct full cards.
- Independently choose one half index from each.
- Exchange the complete `HalfCardState` references, including printed identity and any existing overrides.
- Jokers may be exchanged because moving a complete Joker half is meaningful and does not modify the Joker.
- Full-card IDs remain attached to their card containers. Locks remain attached to full-card IDs.
- A moved half resets only when the full card currently containing it later leaves the hand.

### Forced Mulligan

1. Choose one random full card from the target's current hand, including a modified or locked card.
2. Remove it from the hand.
3. Reset both halves to printed values via `leave_hand()`.
4. Discard each half to its printed source-context pile.
5. Independently roll two contexts uniformly from Rise, Flourish, and Fall. Both rolls may match.
6. Draw one half from each selected pile, using normal reshuffle-on-empty behavior.
7. Randomly merge the two halves into one new full card and append it to the target's hand.
8. Remove any stale lock referring to the departed full-card ID.

The public context distribution describes source piles only. It reveals neither the drawn half identities nor whether either half is a Joker.

### Momentary Lock

- Choose one random full card from the entire target hand, including cards already locked this round.
- Record its full-card ID in owner-private round state.
- Submission staging and locking must reject that card ID for the current round.
- Selecting an already locked card is a valid consumed no-op; it does not reroll.
- The owner sees which card is locked. The attacker, other players, and spectators do not.
- The lock does not prevent sorting, viewing, or targeting the card with the owner's later hand-manipulation abilities.
- Locks clear after round resolution when advancing to the next round. A lock also disappears immediately if that full card leaves the hand.

## Persistence and Reset

Suit, rank, and context overrides use the existing effective-value layer on `HalfCardState`. Crossed Wires uses those same overrides. Loose Pairing moves halves with their overrides intact.

These changes persist across phases, rounds, snapshots, reconnects, and serialization until the full card containing the half leaves the hand. `FullCardState.leave_hand()` resets both halves before they enter used piles. Therefore persistent sabotage cannot contaminate the canonical context piles.

Momentary Lock is not a half-card override. It is owner-private per-round state and expires after the affected round even if the card remains in hand.

## Data Model

### Catalogue definition

The eight shared-resolver definitions use:

```gdscript
AbilityDefinition.new(
    definition_id,
    AbilityDefinition.Timing.SABOTAGE,
    [&"sabotage", &"single_target"],
    &"sabotage_cards",
    0,
    &"",
    {"operation": operation_id, ...trusted_parameters},
    target_opponent_schema,
    display_name,
    rules_text
)
```

`forced_mulligan` uses the same timing, tags, choices, and display fields with `effect_id = force_redraw`.

### Lock state

`PlayerState` gains an owner-private collection of locked full-card IDs for the current round. It must:

- serialize for host persistence;
- deserialize on restore;
- project only to the affected active player;
- reconcile against the current hand after replacement or card departure;
- clear at round transition.

The private hand projection may mark each card with `submission_locked` so the UI never needs the raw lock list outside its private model.

### Deck recipe

Definitions remain separate from copy counts. The provisional recipe adds one copy of each sabotage card. Copy counts are balance data and can be changed without changing definitions or resolver behavior.

## Event and Privacy Contract

Every sabotage produces a public event containing only:

- event kind;
- ability definition ID;
- source player ID;
- target player ID;
- round and phase metadata needed by history presentation;
- public replacement context counts for Forced Mulligan when the lobby information mode exposes draw distributions.

The target receives an owner-private event containing the affected card IDs, half indexes, effective results, and lock status needed to animate and reconcile their own hand.

The attacker receives only success/consumed status. They do not receive hidden card IDs, half indexes, values, Joker information, whether a reroll matched the prior value, or whether a repeated lock changed state.

Other players and spectators receive only the public event. Sanitization happens before network routing; private values must never be placed in hidden controls, metadata, logs, or public history entries.

## Public Match History

The authoritative public history retains the latest 32 privacy-safe events and is identical for active players and spectators. Late joiners and reconnecting clients receive the current 32-entry window, including entries that predate their connection when they remain in that window.

History entries may include:

- played ability, source, and target;
- public choices;
- public context-draw distribution;
- counts of cards replaced or discarded;
- revealed submissions and score breakdowns;
- field activation, overwrite, and expiration;
- round and phase.

History never includes hidden card targets, private faces, Joker identity, hidden manipulation results, or cancelled/uncommitted choices.

The history records that a sabotage resolved, not whether its hidden random result produced a meaningful value change. It does not maintain or infer a player's current context holdings.

The existing 32-event presentation cache is cleared by snapshots and therefore is not sufficient for reconnecting or late-joining spectators. Match state owns the authoritative 32-entry public-history window and includes it in every recipient-safe snapshot. The UI presents that window in a scrollable view grouped by round and phase when useful.

## Information Visibility

- The number of half-cards remaining in each live context draw pile is always projected publicly, independent of hand privacy. Used/discard counts and card identities are not exposed.
- The public lobby mode exposes context-source counts when cards enter a hand. These are draw-event facts, not a current-hand ledger.
- Private mode may suppress the explicit draw-distribution entry, although players can still observe public pile-count changes.
- Neither mode reveals which half-card identities were drawn or whether a source pile supplied its Joker.

## UI Behavior

- Every sabotage card displays its name, full rules text, `SABOTAGE · MAIN 1`, and one opponent-selection step.
- The target overlay lists only currently eligible opponents.
- After target confirmation, the card commits immediately; there is no opponent-card selection UI.
- The affected player receives an animation/highlight on the privately affected card or half.
- Momentary Lock visibly marks the affected owner's card and prevents staging it.
- Opponents see only the played sabotage, source, and target presentation.
- Public history is scrollable, newest-first within round groups, with older rounds collapsible.

## Failure and Edge Cases

- If the target disconnects or becomes ineligible before authoritative resolution, reject without consuming the ability.
- If the target becomes ineligible after one sabotage but before the next, validate the next against the latest state.
- If a two-card operation has fewer than two cards, reject before consumption.
- If a random eligible collection is unexpectedly empty after successful validation, consume as a safe no-op and emit no hidden detail.
- If Forced Mulligan triggers a pile reshuffle, discarded halves are reset before participating.
- If a locked card leaves through Forced Mulligan, remove its lock immediately.
- Multiple locks can leave several cards unavailable; this is allowed. Re-selecting the same locked card is also allowed.
- If every otherwise eligible submission card is locked, the player may submit no hand for that round.

## Testing Strategy

### Catalogue

- All nine IDs are unique and legal only in Main 1.
- Every definition contains display text, sabotage tags, and exactly one player-target step.
- The provisional recipe is separate from definitions.

### Validation and authority

- Self, spectator, pending, inactive, and disconnected targets are rejected.
- Active opponents are accepted.
- Client-authored card IDs, half indexes, operations, random results, or parameters are rejected.
- Multiple sabotages may target one player and resolve in accepted order.

### Resolution

- Deterministic seeds prove every operation and repeated selection behavior.
- Scrambles may reproduce current values.
- Nudges wrap correctly and operate on effective values.
- Crossed Wires differs from Loose Pairing and handles Joker cards safely.
- Loose Pairing preserves half identity and overrides.
- Forced Mulligan rolls its two contexts independently, permits matching contexts, resets the removed card, and preserves hand size.
- Momentary Lock blocks submission, permits repeated selection, survives reconnect, and expires at round transition.

### Privacy and history

- Target-private events contain needed detail.
- Attacker, opponent, spectator, and public snapshots contain no hidden card or half identifiers.
- Public Forced Mulligan history contains source-context counts but no identity or Joker data when visibility permits.
- Late-joining spectators and reconnecting players receive the same latest-32 public history window.
- Pile counts remain visible in both lobby information modes.

### Persistence

- Effective sabotage changes survive serialization and reconnect.
- Overrides follow moved halves after Loose Pairing.
- Leaving the hand resets all overrides before discard.
- Locks serialize privately and clear after the round or card departure.

## Acceptance Criteria

- The nine-card catalogue matches the table and rule text above.
- All sabotage is single-opponent, Main 1 only, host-random, and host-authoritative.
- Persistent changes last until card departure; Momentary Lock lasts only for the round.
- Repeated targeting and repeated random card selection are allowed.
- Public events and history expose no private card information.
- Context-pile counts remain public, while draw distributions never reveal identities or Jokers.
- The implementation is data-driven, covered by deterministic tests, and leaves copy counts adjustable.
