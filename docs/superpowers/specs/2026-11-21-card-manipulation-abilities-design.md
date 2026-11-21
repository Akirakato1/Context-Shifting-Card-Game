# Card-Manipulation Abilities Design

**Status:** Draft for approval  
**Date:** 2026-11-21  
**Scope:** The first finalized ability category: Hand Manipulation

## Intent

Replace the single-half manipulation prototype and runtime no-op ability deck with a data-driven catalogue of the fourteen approved Hand Manipulation designs. These abilities are private, playable only during Hand Play, validated and resolved by the authoritative host, and represented by two physical copies of each design by default.

This design finalizes targeting, randomization, Joker behavior, consumption, persistence, privacy, and the model/controller/UI boundary for this category. Names are descriptive working names; the printed rules text is authoritative.

## Goals

- Implement all fourteen approved manipulation designs as real ability definitions.
- Put two copies of every design into the shared runtime deck: twenty-eight cards total.
- Keep ability behavior data-driven so names, copy counts, ranges, and fixed values can be adjusted without adding a command type per card.
- Validate every target and choice against the host's canonical private hand.
- Use host RNG for every random result and allow a random roll to equal the current value.
- Allow Joker-containing cards and Joker half targets; skip only the operation that does not apply to the Joker half.
- Preserve completed modifications until the affected full card leaves the hand.
- Reveal the consumed manipulation card names at hand resolution without revealing targets or transformations.
- Support fixed and variable-size selection workflows in the functional 2D UI.

## Non-goals

- Final copy-count balance beyond the initial two copies per design.
- Final artwork, icons, animation, or audio for ability cards.
- Implementing the Field, Hand Buff/Nerf, or Sabotage catalogues.
- Adding rerolls, undoing completed effects, or refunding abilities that produce no change.
- Giving manipulation effects authority to the client.
- Changing normal-hand, context-hand, or multiplier balance data.

## Existing constraints

- A full card owns exactly two half-card states.
- Context, rank, and suit modifications use effective overrides and reset only when the full card leaves the player's hand.
- A Joker remains rank `0`, has no ordinary suit, and is eligible in every context. Its submission context and suit are chosen only while the card is staged.
- Hand Manipulation is legal only during Hand Play and before the player's hand is locked.
- Starting an ability is cancellable; completing all required fixed choices or explicitly activating a variable selection consumes it.
- Completed ability IDs are public only when hands resolve. Exact targets and results remain owner-private.
- The host owns the canonical model, RNG, validation, and ability deck.

## Approaches considered

### Selected: declarative definitions with a generic manipulation resolver

Each ability definition carries display text, a target schema, an operation identifier, and fixed parameters. A generic resolver validates the definition plus submitted choices, resolves host randomness, and applies the operation atomically.

This centralizes hand ownership checks, selection counts, duplicate rejection, Joker behavior, consumption, persistence, and privacy. New manipulation cards can normally reuse an operation or add one isolated operation rather than adding a new network command and UI flow.

### Rejected: one custom controller path per card

Separate commands or handlers would be initially direct but would duplicate the same targeting and lifecycle rules fourteen times. It would also make copy-count and content changes unnecessarily coupled to controller code.

### Rejected: unrestricted scripted effect expressions

A general expression language would be more flexible than the current catalogue requires and would expand validation and security risk. A small, closed operation vocabulary is sufficient.

## Shared terminology and targeting rules

- **Full-card target:** a `card_id` owned by the acting player. Unless stated otherwise, the operation considers both halves independently.
- **Half-card target:** a pair of `card_id` plus `half_index` (`0` or `1`) owned by the acting player.
- Targets must be unique within a selection.
- Cards on the submission shelf remain part of the hand and are legal targets.
- A fixed-size workflow commits immediately when its final required choice is selected.
- A variable-size workflow allows target toggling and requires an explicit **Activate** action after its minimum is met.
- Cancelling before activation clears pending targeting and does not consume the ability.
- Once activation begins, the command either rejects without mutation or succeeds atomically and consumes the ability.
- A successful ability is consumed even when every selected operation becomes a no-op.

## Global randomization rule

A pure random roll is uniform over every value written by the effect, including the value the half currently has. Every applicable half rolls independently unless card text explicitly introduces a shared roll.

Examples:

- Random Context rolls uniformly from Rise, Flourish, and Fall.
- Low Roll rolls uniformly from `1, 2, 3, 4, 5`.
- High Roll rolls uniformly from `6, 7, 8, 9, 10`.
- Even Roll rolls uniformly from `2, 4, 6, 8, 10`.
- Odd Roll rolls uniformly from `1, 3, 5, 7, 9`.

The host performs these rolls only after the complete command passes validation. Rejection must not advance the RNG.

## Joker rule

Jokers are legal selections. When an operation does not meaningfully apply to a Joker half, that half stays unchanged while other applicable halves still resolve.

- Rank, suit, and context setters or randomizers skip the Joker half.
- Cycle shifts skip the Joker half because it is already every context.
- Mirror Rank skips the Joker half because its rank remains `0`.
- Context Exchange requires two ordinary effective contexts; a Joker-containing target produces no swap.
- Context Convergence produces no change when its selected target half or its source half is a Joker.

The ability is still consumed after a valid activation that partially or completely does nothing because of Jokers.

## Initial catalogue

Every row creates two physical copies in the shared deck.

| ID / working name | Selection | Authoritative effect | Printed rules text |
| --- | --- | --- | --- |
| `context_exchange` / Context Exchange | Exactly one full card | If both halves are ordinary, exchange their current effective contexts. Preserve ranks and suits. | Select 1 full card. Swap the contexts of its two halves. |
| `context_convergence` / Context Convergence | Exactly one full card, then choose half `0` or `1` as target | If both halves are ordinary, set the selected half's context to the other half's current effective context. Preserve both ranks and suits. | Select 1 full card, then select 1 of its halves. That half becomes the same context as the other half. |
| `context_roulette` / Context Roulette | Select 1–12 individual halves | Each selected ordinary half independently receives a uniformly random context. | Select any number of half-cards in your hand. Randomize each selected context. The current context can be rolled again. |
| `suit_imprint` / Suit Imprint | Exactly one full card, then choose one of the three suits | Set both ordinary halves to the selected suit. Preserve contexts and ranks. | Select 1 full card and 1 suit. Change both halves to that suit. Joker halves are unchanged. |
| `rise_infusion` / Rise Infusion | Exactly one full card | Set both ordinary halves to Rise. Preserve ranks and suits. | Select 1 full card. Change both halves to Rise. Joker halves are unchanged. |
| `flourish_infusion` / Flourish Infusion | Exactly one full card | Set both ordinary halves to Flourish. Preserve ranks and suits. | Select 1 full card. Change both halves to Flourish. Joker halves are unchanged. |
| `fall_infusion` / Fall Infusion | Exactly one full card | Set both ordinary halves to Fall. Preserve ranks and suits. | Select 1 full card. Change both halves to Fall. Joker halves are unchanged. |
| `low_roll` / Low Roll | Select 1–6 full cards | Independently reroll every ordinary half of each selected card from ranks 1–5. | Select any number of full cards. Randomize both halves of each card to ranks 1–5. Current ranks can be rolled again. |
| `high_roll` / High Roll | Select 1–6 full cards | Independently reroll every ordinary half of each selected card from ranks 6–10. | Select any number of full cards. Randomize both halves of each card to ranks 6–10. Current ranks can be rolled again. |
| `even_roll` / Even Roll | Select 1–6 full cards | Independently reroll every ordinary half of each selected card from ranks 2, 4, 6, 8, or 10. | Select any number of full cards. Randomize both halves of each card to an even rank. Current ranks can be rolled again. |
| `odd_roll` / Odd Roll | Select 1–6 full cards | Independently reroll every ordinary half of each selected card from ranks 1, 3, 5, 7, or 9. | Select any number of full cards. Randomize both halves of each card to an odd rank. Current ranks can be rolled again. |
| `ride_the_cycle` / Ride the Cycle | Select 1–6 full cards | Move every ordinary half one context step in the context clock's current direction at activation time. | Select any number of full cards. Advance both halves one step in the context clock's current direction. |
| `against_the_cycle` / Against the Cycle | Select 1–6 full cards | Move every ordinary half one context step opposite the context clock's current direction at activation time. | Select any number of full cards. Move both halves one step against the context clock's current direction. |
| `mirror_rank` / Mirror Rank | Exactly one full card | For each ordinary half, set effective rank to `11 - current effective rank`. Preserve contexts and suits. | Select 1 full card. Mirror both ranks: 1↔10, 2↔9, 3↔8, 4↔7, and 5↔6. |

This catalogue contains fourteen designs and twenty-eight physical cards. Other ability categories will extend the same shared deck later.

## Definition and catalogue model

Add a central ability catalogue responsible for constructing the production definitions and expanding their default copy counts. The catalogue must not own live ability state.

An ability definition needs player-facing metadata in addition to its existing timing, tags, effect identifier, parameters, and choice schema:

- Stable ID
- Display name
- Printed rules text
- Timing category
- Closed manipulation operation ID
- Fixed effect parameters
- Declarative target schema

The target schema describes scope and cardinality rather than embedding live card IDs. Supported manipulation steps are:

- `full_card`: authoritative `card_id`, with fixed count or minimum/maximum count
- `half_card`: authoritative `{card_id, half_index}`, with fixed count or minimum/maximum count
- `half_index`: `0` or `1` constrained to the previously selected full card
- `context`: one of Rise, Flourish, Fall
- `suit`: one of the three suit enum values

Definitions and display metadata must survive config and match snapshot round trips. Physical copies continue to receive unique `ability-copy-*` IDs from `MatchState`.

## Controller and resolver flow

The existing `stage_manipulation`, `cancel_manipulation`, and `commit_manipulation` command kinds remain stable.

### Stage

The host verifies that:

- The acting player is active, connected, and unlocked in Hand Play.
- The requested physical ability is in that player's hand.
- Its timing is Hand Manipulation.
- No other manipulation is pending.

The pending state stores only the ability copy ID. Staging starts the phase clock but does not consume the card.

### Commit validation

`commit_manipulation` carries a structured `choices` dictionary. Before RNG or mutation, the host verifies:

- A pending ability exists and is still held by the player.
- Submitted choice keys exactly match the ability schema.
- Every value has the correct JSON-safe type.
- Counts satisfy fixed or minimum/maximum cardinality.
- Targets are unique.
- Every `card_id` currently belongs to the acting player's hand.
- Every half index is `0` or `1` and belongs to its referenced card.
- Additional suit, context, or half choices are allowed by the definition.
- No choice is accepted merely because the client claimed it was eligible.

On validation failure, return a stable error, preserve the pending ability, consume nothing, change no card, and do not advance RNG.

### Atomic resolution

After successful validation:

1. Resolve all required random values from the match RNG.
2. Calculate the complete set of effective replacements from pre-effect values. This prevents a two-half swap from reading a value already changed by the same effect.
3. Apply all non-Joker changes.
4. Remove the ability from the player's hand and place it in the shared used pile.
5. Append its definition ID to the player's completed manipulation list.
6. Clear pending manipulation.
7. Publish a refreshed owner-private snapshot; send no target information to opponents or spectators.

If the operation is valid but affects no halves, steps 4–7 still occur.

## UI workflow

The ability drawer displays the definition's name and printed rules text. Activating a legal Hand Manipulation card stages it with the host before accepting target input.

The targeting overlay resolves the declarative schema against the current private hand:

- Full-card steps highlight all six owned cards in both the hand row and submission shelf.
- Half-card steps highlight and accept clicks on the individual upper or lower half of each full card.
- Fixed choices such as suits render as buttons.
- Selected cards use the existing yellow target treatment; selected halves receive a half-specific yellow treatment.
- The rest of the interface remains dimmed while targeting is active.
- Fixed-size workflows automatically commit after their final required choice.
- Variable-size workflows show the current selection count, allow toggling targets, enable **Activate** after the minimum, and cap selection at the maximum.
- Cancel remains available only before commit is sent.
- A rejected commit keeps the ability pending and shows the authoritative error so the player can correct or cancel.

The client sends only choices. It never sends proposed random results or replacement effective values.

## Staged submissions

Cards already placed in the submission box remain legal manipulation targets. A successful modification does not silently change the player's selected active half or Joker submission choice.

After the owner snapshot updates, the UI recomputes the submission preview. If the existing staged submission becomes invalid, it remains visibly staged for correction but cannot be locked until restaged validly. Hand Play timeout follows the existing rule: an invalid staged result becomes a pass.

## Persistence and reconnects

Effective overrides already serialize with canonical match state. All new operations must use that same layer rather than changing immutable base context, rank, suit, or half identity.

A reconnecting owner receives:

- The modified effective values in their private hand snapshot
- The pending ability copy ID if targeting was staged but not committed
- Completed manipulation IDs needed for eventual reveal

Opponents and spectators receive none of the private targets or transformations before hand resolution.

## Failure and timeout behavior

- Timeout cancels an incomplete pending manipulation without consuming it.
- A commit received after Hand Play's deadline is rejected without mutation.
- Locking a hand while targeting is pending remains forbidden.
- Duplicate, foreign, missing, malformed, or out-of-range targets reject atomically.
- A valid random result equal to the current value is a successful result, not a failure.
- A valid all-Joker or otherwise no-op target consumes the ability normally.

## Verification

Tests must cover:

- Catalogue size, stable IDs, display text, and exactly two copies of all fourteen designs.
- Definition/config/deck/snapshot round trips for metadata and schemas.
- Correct phase and hand-lock restrictions.
- Every effect's ordinary-half behavior and persistence.
- Context Exchange using pre-effect values.
- Context Convergence target-half semantics.
- Independent random rolls restricted to the written value set, including a deterministic case that rolls an unchanged value.
- Cycle movement in both normal and reversed clock directions.
- Mirror Rank for all five pairs.
- Partial and complete Joker no-ops that still consume the card.
- Fixed and variable selection cardinality, duplicate rejection, foreign-card rejection, malformed half references, unexpected keys, and invalid suit choices.
- Rejection leaving hand state, ability zones, pending state, and RNG unchanged.
- Fixed-choice auto-commit and variable-choice explicit activation in the UI.
- Full-card selection from both hand row and submission shelf.
- Individual half-card highlighting and selection.
- Cancel-before-completion and timeout cancellation without consumption.
- Owner-private updated values and absence of target/result leakage to opponents and spectators.
- Reconnect round trips with pending and completed manipulation state.

The existing full core, UI, signaling, and multi-process network suites must remain green.

## Deferred decisions

- Copy counts after playtesting; the initial value is two for every design.
- Final art-facing names, typography, icons, and animation.
- Whether later ability categories introduce effects that explicitly transform Joker identity.
- The final total shared-deck size after the remaining three categories are designed.
