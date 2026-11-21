# Shift Card Game Design

**Status:** Draft for approval  
**Date:** 2026-11-15  
**Working title:** Shift

## Intent

Build a downloadable, competitive, host-authoritative card game for itch.io. The first version prioritizes a correct, testable game model, controller, and direct peer-to-peer networking. It uses simple placeholder visuals. The eventual presentation may become a 2.5D tabletop game with textured card meshes, lighting, camera movement, animation, sound, and music without changing the game rules.

The central decision is how many cards to commit now versus preserve for later contexts. Players assemble full cards from context-specific half-cards, submit up to six cards simultaneously, score the best normal hand contained in that submission, and multiply it by the best context pattern formed by every submitted card.

## Goals

- Keep model, controller, network transport, and View clearly separated.
- Make the authoritative rules deterministic and testable without rendering a scene.
- Support two to four active players and up to four spectators.
- Support direct host-authoritative P2P matches entered through a short lobby code.
- Preserve hidden information while publishing enough information for strategic play.
- Keep ranks, suits, hand categories, multipliers, ability definitions, and phase timings data-driven.
- Permit a placeholder 2D View now and a 2.5D View later without changing the rules engine.
- Permit future bots to submit the same commands as humans without special rules access.

## Non-goals for the first version

- Final card art, 3D models, animations, audio, music, and presentation polish.
- Final normal-hand catalogue, multiplier balance, ability catalogue, or suit theme/names.
- Dedicated authoritative servers, accounts, matchmaking, progression, or ranked play.
- Host migration.
- TURN relay fallback when a direct P2P route cannot be established.
- AI players or automatic bot replacement.
- More than four active seats or four spectator connections.
- Linux and macOS exports for the first jam release; Windows x64 is the initial required build.

## Anti-goals

- Do not put scoring or validation logic in UI nodes.
- Do not let clients authoritatively mutate match state.
- Do not permanently mutate the immutable identity of a half-card.
- Do not expose private hands, manipulation targets, hidden discards, or random pairings to ordinary opponents or spectators.
- Do not hard-code exactly four players into the model even though the first View has four seats.
- Do not make phase progress depend on client animation completion.

## Selected approaches

### Engine and language

Considered:

1. **Godot 4.x with GDScript:** fast iteration, strong 2D/3D mixing, open source, built-in UI and multiplayer abstractions, and a straightforward glTF/Blender asset path.
2. **Unity with C#:** strong 3D tooling and ecosystem, but heavier project and package overhead for a game jam.
3. **Phaser with TypeScript:** excellent browser-first 2D workflow, but Phaser is deliberately 2D and genuine 2.5D would require another renderer and integration layer.

Selected: **Godot 4.x with typed GDScript**. Blender/glTF may be added for future 3D assets. The initial View may remain entirely 2D.

### Network transport

Considered:

1. **ENet with UPnP and an endpoint registry:** simple inside Godot, but Internet hosts may require port forwarding and some NAT configurations remain unreachable.
2. **WebSocket relay:** the most reliable join-code experience, but all match traffic takes an extra route through the relay.
3. **WebRTC direct P2P with signaling and STUN:** direct gameplay traffic with a small online service used to exchange connection information; some NAT configurations still require TURN.

Selected: **WebRTC direct P2P**. A lightweight signaling service issues/resolves lobby codes and exchanges WebRTC session/ICE data. After connection, gameplay traffic flows directly between each client and the host. The jam version uses STUN but no TURN fallback. Failure to establish a direct route produces a clear error. TURN or another relay may be added after testing.

Godot desktop exports require the native WebRTC GDExtension plugin.

### Authority model

The lobby creator is both a player and the authoritative match host. Every non-host player sends commands to the host. The host validates commands, owns RNG, advances phases and timers, mutates the canonical model, and distributes public or private event projections.

This is sufficient for a jam and friend matches. It does not protect against a malicious host inspecting hidden data or modifying the program. Production anti-cheat may require dedicated authoritative match servers later.

## Architecture

### Model

Pure domain state and rules data, independent of scenes and rendering:

- Match and lobby configuration
- Player and spectator records
- Half-card immutable identities and effective overrides
- Full-card pairings and hands
- Draw and used piles
- Ability deck, player ability hands, and active fields
- Phase, timers, ready state, context clock, scores, and victory state
- Public and per-player private projections

Model objects should not call RPCs or animate UI. They should be serializable enough to create snapshots for reconnects and late joins.

### Controller

The authoritative controller accepts typed commands, validates them against the current phase and private player state, mutates the model, and emits ordered domain events. Example commands include:

- Submit replenishment request
- Ready or lock a phase
- Play a public ability
- Begin, cancel, or complete a private manipulation ability
- Submit a hand or pass
- Choose ability discards
- Join as active player or spectator

Example events include:

- Context advanced
- Replenishment requested/revealed/resolved
- Ability drawn/played/discarded
- Ready state cleared
- Hand submitted/revealed/classified
- Provisional score changed
- Round finalized
- Field replaced/expired
- Player entered/forfeited/reconnected
- Match ended

### Network layer

The WebRTC transport carries commands, events, snapshots, readiness, and liveness messages. It must not contain card-rule decisions. Godot RPC-facing code may use Nodes, while the model and controller remain ordinary domain classes.

The network layer creates a sanitized projection per recipient:

- Host receives and stores canonical state.
- A player receives public state plus their own private hand and choices.
- A spectator receives public state only.

### View

The View subscribes to controller/network events and renders them. It owns card positioning, menus, prompts, phase clocks, transitions, animation, audio, and eventual 3D presentation. The controller does not wait for an animation to finish. A client that animates slowly catches up to the current event sequence.

The future 2.5D View may use a 3D table, camera, lights, thin card meshes with the user's textures, and Godot Control nodes for menus and text.

### Future bot boundary

Human and future bot agents submit the same `GameCommand` forms. A bot may see only public state plus its own private state. Bot logic is not part of the first version.

## Terminology

- A **round** is the one global Start -> Main 1 -> Hand Play -> Main 2 -> End sequence shared by all players.
- A **half-card** has one context, one rank, one suit, and one immutable copy identity.
- A **full card** is a persistent pairing of two half-cards while it remains in a player's hand.
- The **active context** determines which half of each submitted full card supplies its normal rank and suit.
- A **normal hand** is the highest-ranked poker-inspired category present in a subset of the submitted cards.
- A **context hand** is the highest-ranked inclusive context-count threshold satisfied by all submitted full cards.

## Card model

### Context half-card piles

There are three finalized development contexts in fixed protocol order:

- Rise / `興` (`0`)
- Flourish / `盛` (`1`)
- Fall / `衰` (`2`)

The English names are used in code and player-facing placeholder UI. The traditional Chinese characters are art-direction concepts rather than code identifiers.

Each context begins with 90 half-cards:

```text
10 ranks x 3 suits x 3 copies = 90 half-cards per context
270 half-cards total
```

Each context owns a draw pile and a used pile. In Public information mode, the UI exposes only the number of halves in each pile. In Private information mode, exact per-context pile counts are hidden because count deltas could reveal a player's replacement request. Neither mode exposes used identities, ranks, suits, copy IDs, or restored base values.

When a draw pile empties during a draw, shuffle that context's used pile into a new draw pile and continue. Half-cards still held by players are not available for recycling.

### Immutable and effective identity

Every half-card has immutable base fields:

- Stable copy ID
- Original context
- Original rank
- Original suit

It also has effective fields used by current gameplay. Abilities may override context, rank, or suit. All validation, base-value calculation, normal-hand classification, and context counting use effective fields.

A modification persists across rounds while its full card remains in the player's hand. When the full card leaves the hand by being played or by an ability, its halves reset during cleanup and enter used piles according to their original contexts.

### Full cards and hand size

Two half-cards form one full card. Full-card hand size is capped at six.

At initial setup, each player draws four Rise, four Flourish, and four Fall halves. These are randomly paired within the constraint:

```text
Rise-Flourish, Rise-Flourish,
Rise-Fall, Rise-Fall,
Flourish-Fall, Flourish-Fall
```

Later replenishment has no pairing constraint. Requested halves are drawn privately, uniformly shuffled, and paired randomly. Same-context and mixed-context pairs are legal.

If both halves match the active context, the player chooses which half supplies the rank and suit for normal evaluation. The full card still counts as one submitted card, while both effective contexts count for context-hand evaluation.

## Match setup and lobby

- Minimum active players: 2
- Maximum active players in the first View: 4
- Maximum spectators: 4
- Round 1 active context: Rise
- Every initial player receives the standard six-card opening hand.
- Every initial player receives two ability cards during setup and the normal one-card ability draw during Round 1 Start, entering Main 1 with three abilities.

The model stores a dynamic player collection. Four is a View and connection limit, not a rule-engine assumption.

### Locked lobby settings

The host configures settings before starting. They become immutable until the match ends:

- Victory mode
- Victory target
- Information visibility
- Timer for each interactive phase
- Public-ability reaction window and overall phase hard limit
- Reconnection grace duration

Exact default/minimum/maximum values remain balance and usability decisions.

### Information visibility setting

One setting applies consistently to strategic request/discard information.

**Public** (default):

- At Start resolution, reveal every player's requested Rise/Flourish/Fall replenishment quantities.
- Reveal the identities of ability cards discarded to the End hand limit.
- Show exact Rise/Flourish/Fall draw-pile and used-pile counts.

**Private:**

- Hide replenishment context quantities.
- Hide End hand-limit ability discard identities.
- Hide exact per-context draw-pile and used-pile counts so their deltas cannot reveal replacement choices.

In both modes, the number of cards being replenished or discarded is public. Played hands and publicly activated abilities are always visible. There is no ordinary voluntary full-card discard/cycle action.

## Victory modes

The lobby chooses one mode and a target `X`.

### Score race

The unique round winner adds their finalized round score to their cumulative match score. The first player whose cumulative score is at least `X` wins the match.

### Round-win race

The unique round winner gains one match point. The first player whose match points are at least `X` wins the match.

### Tied round

If two or more active players share the highest finalized score, the round is nil:

- No round winner
- No cumulative score awarded
- No round-win point awarded
- Normal cleanup occurs and the match advances

## Context clock

- Round 1 begins at Rise.
- Default order is Rise -> Flourish -> Fall -> Rise.
- From Round 2 onward, Start advances the context before replenishment.
- The model stores current context and direction separately.
- Field effects may change current context, jump the clock, or reverse future advancement.
- Exact context-control ability cards are future content.

## Global round sequence

Every active player participates in the same global sequence. There is no first-player marker.

### 1. Start

Resolve in this order:

1. Advance and reveal the active context (except Round 1, which begins at Rise).
2. Activate any pending mid-match players.
3. Determine every active player's missing full-card count.
4. Collect required half-card replenishment requests.
5. Reveal request distributions simultaneously if Information Visibility is Public.
6. Draw and randomly pair replacement halves privately.
7. Draw one ability card for every active player.
8. Enter Main 1.

For each missing full card, a player requests two halves. No request may contain more than five halves from one context. A player missing `N` full cards requests exactly `2N` halves.

If the player supplies only part of the request before timeout, preserve that partial choice and randomly fill missing context slots while respecting the five-per-context limit. If they supply nothing, choose the complete legal distribution randomly. Drawn ranks, suits, copy IDs, and pairings are always private.

### 2. Main 1

Main 1 is a shared real-time public ability window. Players may play permitted public abilities while the phase is open. The host validates and resolves actions atomically in receipt order and broadcasts sanitized results.

Permitted categories:

- Field abilities
- Targeted hand-shape buffs/nerfs
- Opponent sabotage

There is no input batching. Most effects stack or do not conflict, the response window permits reactions, and sabotage resolves one action at a time against the latest authoritative state.

### 3. Hand Play

Hand Play is a private construction window.

A player may:

- Complete zero or more hand-manipulation abilities.
- Select zero to six full cards.
- For every selected card, choose an effective half matching the active context.
- Lock the submission when satisfied.

Every submitted full card must contain at least one effective half matching the active context. Submitting zero cards is a legal pass that scores zero, preserves the hand and its modifications, and creates no next-round replenishment.

#### Private manipulation staging

Beginning a manipulation ability does not consume it. The player may cancel while required targets or choices remain incomplete. Confirming the final required choice commits and consumes the ability immediately; its effect cannot then be undone, even before hand lock.

Completed modifications become authoritative private hand state and may be saved for later rounds. If the player ultimately passes or fails to stage a hand, completed abilities remain spent.

At timeout:

- Automatically submit the currently staged valid hand.
- Cancel incomplete ability targeting.
- If no valid hand is staged, submit a pass.

At shared Hand Play resolution, reveal:

- Each final submitted hand and its effective displayed values
- Manipulation ability cards consumed during the phase
- Locked normal and context categories
- Provisional scores

Do not reveal exact manipulation targets, original-to-effective transformations, or intermediate steps.

### 4. Main 2

Main 2 is a shared real-time public reaction window. Players may play targeted hand-shape buffs/nerfs against the now-revealed submissions and provisional scores. Effects update provisional scoring but do not reclassify the already locked normal or context category.

### 5. End

Resolve in this order:

1. Apply remaining score effects.
2. Clamp each raw score to at least zero.
3. Apply one final ceiling operation to produce an integer score.
4. Determine a unique round winner or nil tie.
5. Award match progress according to the selected victory mode.
6. Reset and split played full cards into original-context used piles.
7. Leave modifications on unplayed cards intact.
8. Decrement active field durations and expire zero-duration fields.
9. Require players above three ability cards to discard down to three.
10. Check match victory; otherwise begin the next round.

End's ability-discard timer is expected to be relatively short and remains a lobby setting. If a player fails to confirm a complete discard choice before timeout, the host randomly discards enough abilities to reach three.

## Ready state, timers, and reactions

Every interactive phase has an adjustable timer and player completion state. A phase may advance early once all required active players are ready/locked.

For public ability windows:

- Playing a public ability clears every active player's Ready state.
- A short reaction window begins after the ability resolves.
- Readiness cannot close the phase during that reaction window.
- Repeated actions may extend the practical window only up to an overall hard phase limit.
- At the hard limit, finish resolving actions already accepted by the host, then close the phase.

Spectators and pending players never participate in readiness.

## Hand scoring

### Submission and normal category

A player may submit one to six eligible full cards. Extra eligible cards are legal even when they do not improve the normal hand.

Normal evaluation:

1. Examine every valid normal-hand subset within the submitted cards.
2. Classify using a fixed poker-style hierarchy.
3. Lock the highest category before buffs and nerfs.
4. Use that category's configured normal multiplier.

High Card is an exact one-card category. Because every non-empty eligible submission contains at least a High Card subset, a selection such as ranks `3, 8, 9` is legal and classifies as Nine High if it contains no higher category.

The final normal-hand catalogue, hierarchy, and multipliers are intentionally unresolved content. Definitions must include required subset size and a deterministic predicate. The system must support categories for submissions up to six cards.

### Base value

The base value is the sum of the selected active-context effective rank from **every submitted full card**, including cards outside the winning normal subset.

Example:

```text
Submitted active-context ranks: 3, 8, 9
Normal category: Nine High
Base value: 20
```

### Context category

Count both effective context halves of every submitted full card. Context shapes use inclusive thresholds: extra contexts do not invalidate a pattern.

Planned pattern families:

- `No Context Pattern x1`: neutral fallback when no threshold below qualifies
- `Rise + Flourish + Fall x 1..4`: at least `N` of every context
- `Rise`, `Flourish`, or `Fall x 5..12`: at least `N` of one context
- `Rise + Flourish`, `Rise + Fall`, or `Flourish + Fall x 3..6`: at least `N` of both named contexts

For totals Rise 4 / Flourish 3 / Fall 1, both `Rise + Flourish + Fall x1` and `Rise + Flourish x3` qualify. Lock only the highest-ranked qualifying context category. Lower contained categories do not also score. If no listed threshold qualifies, lock `No Context Pattern x1`; this category supplies no bonus and may be targeted only by effects that explicitly name it. The remaining context hierarchy and multipliers remain balance data.

### Formula and rounding

```text
base value = sum of all submitted selected active-context ranks

raw score =
    base value
    x locked normal-hand multiplier
    x locked context-hand multiplier
    then modified by ability effects

final score = ceil(max(0, raw score))
```

Keep exact fractional arithmetic through every modifier and round upward exactly once at finalization. Implementation should avoid binary floating-point disagreement; fixed-point integers or rational values are appropriate.

Normal and context classifications are locked before buffs/nerfs. An effect may alter the score or multiplier of the locked category but cannot cause the evaluator to fall back to a contained category.

## Ability system

### Shared deck

All players draw from one shared shuffled ability deck.

Zones:

- Shared draw pile
- Private player ability hands
- Active field area
- Shared used-ability pile

Every player receives two at setup and one at each Start. There is no per-turn play-count limit. At End, players discard down to three.

When a draw cannot be completed, shuffle the used-ability pile into a new draw pile and continue. Cards in player hands or active on the field are not recycled.

If both the draw and used piles are empty after recycling, the draw is short: do not generate a substitute card. This applies to ordinary Start draws and late entrants. The eventual ability deck should be sized so this is exceptional.

The final deck list and counts are future content.

### Four timing categories

1. **Hand manipulation** — Hand Play only. Used privately, committed after completing all choices, and revealed by card name at Hand Play resolution. Exact targets and steps remain private.
2. **Field** — Main 1 only. Public, global, and possibly persistent.
3. **Hand-shape buff/nerf** — Main 1 or Main 2. Public, targeted, and round-scoped unless its definition says otherwise.
4. **Opponent sabotage** — Main 1 only. Public activation with ability-defined private consequences.

### Sabotage privacy

Sabotage definitions declare target rules, random/chosen selection, result visibility, and replacement behavior.

For the example "random opponent card is forced to redraw":

- Everyone sees the ability and target player.
- The host randomly chooses against canonical private state.
- Only the target sees which full card was removed.
- The attacker learns that the effect succeeded but not the card identity.
- The removed card resets because it left the hand.

### Field coexistence and conflicts

Multiple fields coexist by default. Each field definition may declare:

- Duration
- Effect hooks
- Duplicate stacking policy
- Optional conflict group

Fields in the same contradiction/conflict group use newest-wins replacement. The replaced field immediately enters the used pile and the new field starts with its full duration.

A field lasting `X` rounds counts its played round as the first. It activates during Main 1, remains through that round's scoring, decrements during End, and expires at zero. A two-round field affects its played round and the following round.

Fields remain active through normal expiration even if the player who played them disconnects or forfeits.

## Joining, spectators, reconnects, and forfeits

### Mid-match active join

The lobby remains joinable while seats are open. A new active player:

- Occupies an empty seat but remains pending for the current round.
- Observes as a spectator until the next Start.
- Enters at that Start with zero match progress.
- Draws the default four Rise/four Flourish/four Fall opening halves from current shared piles and receives the constrained six-card opening hand.
- Draws two setup abilities from the current shared deck plus the normal Start ability, entering with three.

### Spectators

Up to four spectators may join at any time. They receive an authoritative public snapshot and then public events. They never receive private hands or hidden operations and never affect timers or readiness.

### Non-host disconnect

- Freeze gameplay and pause phase timers for the configurable reconnect grace period. Reject new gameplay commands and readiness changes while frozen.
- Permit the same authenticated player to reconnect and receive a private snapshot.
- Persist an account-free reconnect token locally for the active match so the player may relaunch the game and reclaim their seat within grace.
- If grace expires, that player forfeits.
- Remove their readiness requirement and match progress.
- Reset their full cards and return halves to original-context used piles.
- Move their ability hand to the used pile, applying Information Visibility to revealed identities.
- Leave fields they previously played active until normal expiration.
- Continue if at least two active players remain.
- If only one active player remains, that player wins immediately by forfeit.

Each disconnected player has an independent grace deadline. With overlapping disconnects, remain frozen until every disconnected player has either reconnected or forfeited. Resolve expired forfeits, then resume only when no unresolved disconnect remains.

End finalization is an atomic controller transaction. A disconnect noticed while End is calculating scores, awarding progress, cleaning up, and checking victory is processed only after that transaction commits. Do not rescore or void an already committed round because its winner subsequently forfeits.

No bot replacement occurs in the first version.

### Host disconnect

Host migration is out of scope. If the host disconnects:

- End the match.
- Award no progress from the interrupted round.
- Notify remaining clients and return them to the menu/lobby failure flow.

## Match completion and rematch

After a normal match victory:

- Show the winner and final standings.
- Keep active players and spectators connected.
- Return everyone to the same lobby.
- Unlock settings for the host.
- Reset scores, decks, hands, fields, context clock, and match state.
- Preserve occupied seats unless participants leave or change roles.
- Begin a rematch only after the lobby meets its start conditions again.

## Randomness and determinism

The authoritative host owns all random operations:

- Shuffling half-card and ability piles
- Initial constrained pairing
- Replenishment pairing
- Timeout fallback selections
- Random sabotage targets

Use stable IDs and a seedable RNG interface so model/controller tests can reproduce outcomes. Clients render authoritative results rather than independently reproducing random draws.

## Verification expectations

The eventual implementation plan should include automated coverage for at least:

- Pile sizes, recycling, and immutable reset behavior
- Initial constrained pairing and random later pairing
- Replenishment caps and partial-timeout completion
- Persistent effective modifications and reset on leaving hand
- Normal subset classification with extra submitted cards
- Inclusive context thresholds and best-category-only selection
- Exact score arithmetic, zero floor, and one final ceiling
- Nil tied rounds and both victory modes
- Every phase's legal/illegal commands and timeout behavior
- Public/private event projections
- Field duration, coexistence, replacement, and post-forfeit persistence
- Late active joins, spectators, reconnect, forfeit, and host loss
- Snapshot/resync consistency across host and clients

## Deliberately unresolved content

These decisions do not block the rules architecture and will be supplied after playtesting/design work:

- Final suit theme and names
- Complete normal-hand catalogue and hierarchy for up to six submitted cards
- Normal-hand multipliers
- Context-hand hierarchy and multipliers
- Ability-card catalogue, copy counts, detailed effects, and modifier ordering where card text requires it
- Exact phase timer, response-window, hard-limit, and reconnect-grace defaults
- Final UI layout, animation timing, art, 3D models, audio, and music
- Signaling/STUN hosting provider and TURN fallback decision after connectivity tests
- Linux and macOS export timing after the Windows x64 jam build is stable

## Builder calls

The builder may choose these without changing product behavior, but must document the choice:

- Exact internal serialization format for data definitions and snapshots
- Test framework and file layout
- Fixed-point versus rational implementation for exact fractional scores
- Stable command/event naming and versioning
- Signaling service implementation language and free-tier provider
- Reasonable technical limits for packet size, rate limiting, timeouts, and invalid-command handling

