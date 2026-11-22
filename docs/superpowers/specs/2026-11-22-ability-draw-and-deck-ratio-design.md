# Ability Draw and Deck Ratio Design

**Date:** 2026-11-22
**Status:** Implemented

## Intent

Change the shared ability deck to the approved category ratio and let every active player draw two ability cards at the start of each turn. The three-card end-of-turn hand limit remains unchanged.

## Chosen ratio

The category ratio is:

**Manipulation : Buff/Nerf : Sabotage : Field = 15 : 6 : 4 : 5**

The provisional physical deck contains 90 cards:

| Category | Cards | Share | Expected cards per turn with two draws |
| --- | ---: | ---: | ---: |
| Manipulation | 45 | 50.00% | 1.000 |
| Buff/Nerf | 18 | 20.00% | 0.400 |
| Sabotage | 12 | 13.33% | 0.267 |
| Field | 15 | 16.67% | 0.333 |

Buff/Nerf plus Sabotage therefore supplies 0.667 interaction cards per turn on average. Field supplies one card every three turns on average. The earlier goal of one manipulation plus one interaction plus one-third field per turn would require 2⅓ draws and cannot be sustained by a fixed two-card draw.

## Per-design recipe

Every designed card remains present. Extra copies are assigned without changing card behavior:

- Manipulation: three copies of every design, with a fourth copy of Context Roulette, Ride the Cycle, and Against the Cycle. Total: 45.
- Buff/Nerf: one copy of every design, with a second High Card Buff and High Card Nerf to preserve buff/nerf symmetry. Total: 18.
- Sabotage: one copy of every design, with a second Suit Scramble, Rank Scramble, and Context Scramble. These are the mildest general disruptions. Total: 12.
- Field: one copy of every design. Total: 15.

Copy counts remain data in `AbilityCatalog.provisional_deck_recipe()` and can be tuned later without changing effect implementations.

## Draw and hand rules

- Opening ability hand remains two cards.
- At the start of every turn, each active player draws two ability cards instead of one.
- The player may play any legal number of abilities during the turn.
- At end of turn, a player with more than three ability cards chooses discards down to three; timeout still chooses randomly.
- The shared used pile reshuffles normally when the draw pile runs out.
- Late-joining players still receive the normal two-card opening ability hand when activated.

## Approaches considered

- Exact `10:3:2:5` ratio: satisfied the newer ratio statement but produced one field every two turns and only one interaction every two turns.
- Exact cadence through a bonus third draw every third turn: supplied 2⅓ cards per turn but contradicted the requested fixed two-card draw.
- `15:6:4:5` with two draws — chosen: preserves a manipulation per turn and a field every three turns while keeping Buff/Nerf and Sabotage at the requested 3:2 ratio.

## Verification

- Catalogue tests assert the exact 45/18/12/15 category counts and 90-card total.
- Deck-state tests assert two-card start-of-turn draw and unchanged two-card opening/three-card limit.
- Runtime configuration tests assert that the live match uses the same 90-card recipe.
- Start and end phase tests confirm two cards are drawn and excess cards are still discarded down to three.
- Serialization tests confirm the new draw count survives reconnect and state restoration.
