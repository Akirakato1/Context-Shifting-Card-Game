# Normal Hand Catalogue and Initial Balance Design

## Intent

Replace the runtime placeholder normal hands with a complete initial catalogue for a game with ranks 1–10, three suits, duplicate faces, and submissions of one through six cards. The catalogue is poker-inspired rather than bound to poker hierarchy: relative rarity determines priority and seeds multipliers, while the existing category vocabulary remains High Card, Family, Group, Straight, and Flush.

This is initial balance data. Player-selected replenishment, persistent manipulation, abilities, context eligibility, and deliberate card retention will change live play rates, so playtest telemetry may tune the values without changing the evaluator architecture.

## Rules and scope

- A submission contains one through six eligible full cards.
- Rank structures are found in any subset of the submitted cards; extra cards remain legal and still add to base value.
- Exactly one rank structure contributes: High Card, Family, Group, or Straight.
- Flush is an independent additive card-hand component and applies only when every submitted scoring face has the same suit.
- Straights and Flushes begin at three cards. Two-card Straights and Flushes are omitted because they are too automatic to create an interesting scoring identity.
- Straights are linear within ranks 1–10. They do not wrap from 10 to 1.
- Duplicate rank/suit faces are legal because the physical pools contain copies.
- A Joker contributes rank zero for High Card fallback, so a Joker-only submission remains legal, but rank zero is excluded from Family, Group, and Straight matching. Its staged suit selection may let it participate in a Flush.
- Suits never break ties.

## Complete catalogue

The catalogue is complete in the best-subset sense. For example, a submitted `3+2+1` rank partition contains a Full House subset, while `4+1+1` contains Four of a Kind. Those kicker-bearing partitions do not require duplicate definitions. The only additional six-card Group not contained by a stronger listed rank pattern is Four House (`4+2`).

| Priority | Hand | ID | Category | Required shape | Hybrid probability | Multiplier |
| ---: | --- | --- | --- | --- | ---: | ---: |
| 10 | High Card | `high_card` | High Card | Any one face, including a rank-zero Joker; fallback | 100.000000% | `1/1` |
| 20 | Pair | `pair` | Family | `2` | 58.539632% | `5/4` |
| 30 | Three-card Straight | `straight_3` | Straight | Three consecutive distinct ranks | 25.311036% | `3/2` |
| 40 | Two Pair | `two_pair` | Group | `2+2` | 14.193690% | `7/4` |
| 50 | Three-card Flush | `flush_3` | Flush | Three submitted cards, one suit | 12.740597% | `7/4` |
| 60 | Three of a Kind | `three_kind` | Family | `3` | 8.730743% | `7/4` |
| 70 | Four-card Straight | `straight_4` | Straight | Four consecutive distinct ranks | 6.682037% | `2/1` |
| 80 | Four-card Flush | `flush_4` | Flush | Four submitted cards, one suit | 4.306265% | `2/1` |
| 90 | Full House | `full_house` | Group | `3+2` | 2.030908% | `9/4` |
| 100 | Five-card Straight | `straight_5` | Straight | Five consecutive distinct ranks | 1.314534% | `9/4` |
| 110 | Five-card Flush | `flush_5` | Flush | Five submitted cards, one suit | 1.049181% | `5/2` |
| 120 | Four of a Kind | `four_kind` | Family | `4` | 0.622374% | `5/2` |
| 130 | Three Pair | `three_pair` | Group | `2+2+2` | 0.440908% | `11/4` |
| 140 | Six-card Flush | `flush_6` | Flush | Six submitted cards, one suit | 0.168003% | `3/1` |
| 150 | Six-card Straight | `straight_6` | Straight | Six consecutive distinct ranks | 0.146969% | `3/1` |
| 160 | Four House | `four_house` | Group | `4+2` | 0.055114% | `13/4` |
| 170 | Double Triple | `double_triple` | Group | `3+3` | 0.036742% | `7/2` |
| 180 | Five of a Kind | `five_kind` | Family | `5` | 0.024410% | `7/2` |
| 190 | Six of a Kind | `six_kind` | Family | `6` | 0.000408% | `19/4` |

Flush priority values are recorded consistently with global rarity, although Flush is evaluated independently and added to the selected rank structure. A Six-card Straight Flush therefore contributes `3 + 3 = 6` to the card-hand multiplier factor before buffs and nerfs.

## Probability model

The neutral baseline treats each ordinary scoring face as having:

- one independently uniform rank from 1 through 10;
- one independently uniform suit from Mountain, Cloud, and Sea.

For each exact hand shape, calculate two probabilities:

1. `random_submission`: the probability that the shape qualifies, averaged equally across random submission sizes one through six;
2. `six_card_availability`: the probability that the shape can be constructed from six random scoring faces.

The hybrid probability is their geometric mean:

```text
hybrid probability = sqrt(random_submission × six_card_availability)
```

The first term prevents six-card subset searching from making small patterns appear almost automatic. The second term acknowledges that players choose subsets and do not submit random cards blindly. The geometric mean keeps both effects meaningful without pretending to model optimal strategy.

Jokers, finite-pile depletion, context eligibility, retained cards, player-selected draw distributions, and abilities are deliberately excluded. Their influence belongs in later empirical tuning.

## Priority and multiplier rule

Rarer hybrid probabilities receive higher priority. Priorities use gaps of ten so later shapes can be inserted without renumbering the catalogue.

The multiplier curve matches the approved context-hand method:

```text
information bits = -log2(hybrid probability)
multiplier = min(5, ceil_to_quarter(1 + 0.20 × information bits))
```

High Card is the explicit neutral exception at `1/1`. Stored values use exact `Rational` fractions.

## Deterministic tie-breaking

- High Card and Family: higher repeated/selected rank wins.
- Straight: higher terminal rank wins.
- Group: compare the largest group rank first, then subsequent group ranks. Full House therefore compares the triple before the pair; Four House compares the four before the pair.
- Flush: compare all submitted ranks from highest to lowest, not only the single highest card.
- Identical rank vectors tie; suits do not break the tie.

The final match winner is still decided by the complete score. These rules make selection deterministic when multiple subsets satisfy the same definition.

## Approaches considered

### Hybrid exact probability — chosen

Combine exact random-submission frequency with six-card constructability. This acknowledges both the rules engine and deliberate player selection while remaining reproducible and inexpensive to recalculate.

### Random submissions only

Average exact qualification probability across submission sizes one through six, matching the context-hand calculation directly. This overstates the rarity of small selectable subsets and Flushes because players deliberately choose how many cards to submit.

### Full strategic simulation

Simulate piles, merging, active contexts, retention, manipulation, and player decisions. This could eventually give the best empirical model, but any result today would mostly measure invented strategy assumptions. It is better reserved for bot development or real playtest data.

## Implementation boundary

After approval:

- add a production `NormalHandCatalog` and replace `_placeholder_normal_hands()`;
- add the `4+2`, `3+3`, and `2+2+2` group definitions and all Family/Straight/Flush tiers;
- allow Joker rank zero as High Card fallback, exclude it from Family/Group/Straight matching, and preserve staged Joker suit participation in Flush;
- improve Flush tie-breaking to compare the complete descending rank vector;
- serialize the authoritative catalogue through existing match configuration paths;
- add exhaustive catalogue, evaluator, scoring, runtime, and reconnect tests;
- update player-facing names and the balancing worksheet/documentation.
