# Suit Names and Context-Hand Balance Design

**Date:** 2026-11-22
**Status:** Implemented

## Intent

Lock the three suits as Mountain, Cloud, and Sea throughout the game, and replace the runtime context-hand placeholders with a complete initial priority and multiplier catalogue derived from relative rarity. This produces playable balance data now while leaving normal-hand balance for the user's forthcoming catalogue.

## Goals

- Use Mountain, Cloud, and Sea as the canonical internal and displayed suit names.
- Preserve the existing serialized/network suit values `0`, `1`, and `2`.
- Give every planned context-hand definition a deterministic priority and exact rational multiplier.
- Keep symmetric context variants identical in priority and multiplier.
- Make the balance assumptions explicit so playtesting can tune values later without changing evaluator logic.

## Non-goals

- Define or rebalance normal hands.
- Change context-hand qualification rules, inclusive thresholds, or highest-priority-only scoring.
- Change rank distribution, context-pile construction, Joker behavior, field-factor rules, or scoring arithmetic.
- Model ability-assisted hands as if their live frequency were already known.

## Suit migration

Replace the placeholder enum identifiers with stable semantic identifiers while preserving their integers:

| Suit | Enum | Wire value |
| --- | --- | ---: |
| Mountain | `GameTypes.Suit.MOUNTAIN` | 0 |
| Cloud | `GameTypes.Suit.CLOUD` | 1 |
| Sea | `GameTypes.Suit.SEA` | 2 |

`GameTypes.suit_name()` becomes the central presentation mapping. Card/Joker selectors, card debug text, ability rules text, fixture data, tests, and active documentation use the semantic names. Numeric snapshots and network payloads remain compatible.

The three field definitions become `mountain_favor`, `cloud_favor`, and `sea_favor`, displayed as Mountain Favor, Cloud Favor, and Sea Favor. This is an intentional development-time definition-ID migration; no released save format depends on the numbered placeholder IDs.

## Rarity model

Use a transparent neutral baseline rather than pretending to know future live play rates:

- each submitted full card contributes two context halves;
- each half is independently Rise, Flourish, or Fall with probability `1/3`;
- calculate the exact probability that a specific labelled threshold qualifies;
- average that probability equally across submissions of one through six full cards;
- symmetric variants share the same result;
- use the probability only to order definitions and seed multipliers.

The model deliberately does not treat player-selected replenishment, persistent manipulation, Jokers, or valid-normal-hand constraints as random. Those systems will change empirical rates, so the catalogue remains balance data that can be tuned from playtest telemetry.

## Priority and multiplier rule

Rarer qualifying shapes receive higher priority. Priorities use gaps of ten so future patterns can be inserted without renumbering the entire catalogue. When several inclusive thresholds qualify, the existing evaluator locks only the highest-priority definition.

Initial multipliers follow the rarity information content, rounded upward to quarter steps and capped at five:

```text
information bits = -log2(average qualification probability)
multiplier = min(5, ceil_to_quarter(1 + 0.20 × information bits))
```

The stored values use exact `Rational` fractions, not floating-point values.

| Pattern family | Threshold | Average probability | Priority | Exact multiplier |
| --- | ---: | ---: | ---: | ---: |
| All Contexts | ×1 | 66.5583% | 10 | `5/4` |
| All Contexts | ×2 | 35.0681% | 20 | `3/2` |
| Two Contexts | ×3 | 21.8484% | 30 | `3/2` |
| All Contexts | ×3 | 11.5977% | 40 | `7/4` |
| Single Context | ×5 | 11.4564% | 50 | `7/4` |
| Two Contexts | ×4 | 6.8899% | 60 | `2/1` |
| Single Context | ×6 | 4.5887% | 70 | `2/1` |
| Single Context | ×7 | 1.4783% | 80 | `9/4` |
| All Contexts | ×4 | 1.0867% | 90 | `5/2` |
| Two Contexts | ×5 | 1.0191% | 100 | `5/2` |
| Single Context | ×8 | 0.3719% | 110 | `11/4` |
| Single Context | ×9 | 0.0702% | 120 | `13/4` |
| Two Contexts | ×6 | 0.0290% | 130 | `7/2` |
| Single Context | ×10 | 0.0093% | 140 | `15/4` |
| Single Context | ×11 | 0.0008% | 150 | `9/2` |
| Single Context | ×12 | approximately 0.00003% | 160 | `5/1` |

Every named variant in a row uses the same values. For example, Rise ×7, Flourish ×7, and Fall ×7 are all priority 80 with multiplier `9/4`; every named two-context pair ×5 is priority 100 with multiplier `5/2`.

## Runtime catalogue and presentation

Replace `_placeholder_context_hands()` with a production default catalogue. Definition IDs remain semantic and deterministic:

- `all_contexts_1` through `all_contexts_4`;
- `rise_5` through `rise_12`, and equivalent Flourish/Fall IDs;
- `rise_flourish_3` through `rise_flourish_6`, and equivalent Rise/Fall and Flourish/Fall IDs.

The UI formats these IDs into readable context-hand names and displays the detected exact multiplier. Match configuration serialization continues carrying definitions as authoritative data, so hosts and reconnecting clients use the same catalogue.

## Approaches considered

### Full semantic migration plus probability-derived balance — chosen

Canonical names exist in code and presentation, and the rarity calculation provides an auditable starting point. This is appropriate before release, when placeholder-ID compatibility has little value.

### Presentation-only rename

Keep `ONE/TWO/THREE` and numbered field IDs internally while only changing labels. This reduces edits but preserves misleading vocabulary throughout model code and future content authoring.

### Manually tier every context hand

Choose multipliers entirely by feel. This is easy to adjust but gives no reproducible reason for the initial ordering and makes close cases harder to resolve consistently.

## Verification

- Tests pin suit enum values and all three suit names.
- Ability-catalogue tests pin semantic Favor IDs, labels, rules text, and suit parameters.
- Card/Joker view tests confirm selector and displayed suit names.
- Context-catalogue tests assert all 40 definitions, symmetric variants, exact priorities, and rational multipliers.
- Evaluator tests cover overlapping thresholds whose rarity order matters, including All Contexts ×3 versus Single Context ×5, All Contexts ×4 versus Two Contexts ×4, and Two Contexts ×5 versus Single Context ×5.
- Configuration round trips preserve every context definition.
- The complete core, network, and relevant view/runtime suites remain green.
