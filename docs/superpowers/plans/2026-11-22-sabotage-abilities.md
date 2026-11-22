# Sabotage Abilities Implementation Plan

**Goal:** Complete the nine-card sabotage catalogue and make its hidden, host-authoritative results survive round flow, serialization, reconnects, and network snapshots without leaking hand data.

## Task 1: Catalogue and shared resolver

- Add the nine approved sabotage definitions and one-copy provisional recipe entries.
- Add deterministic resolver tests before implementation.
- Implement the eight data-driven card operations; retain Forced Mulligan as the specialized pile-crossing handler.

## Task 2: Controller integration and lock lifecycle

- Validate exactly one active, connected opponent and reject client-authored hidden choices.
- Add owner-private per-round submission locks.
- Reject locked cards during staging and locking, remove stale locks on card departure, and clear locks after round resolution.
- Serialize and restore lock state.

## Task 3: Event privacy and public draw facts

- Emit public, target-private, and attacker-private sabotage events.
- Keep card IDs, half indexes, values, Joker identity, and no-op outcomes out of public and attacker payloads.
- Publish Forced Mulligan source-pile counts only when lobby visibility permits it.

## Task 4: Authoritative bounded history and snapshots

- Store the latest 32 public events in MatchState with round/phase metadata.
- Include the identical sanitized history window in active-player and spectator snapshots.
- Mark locked cards only in the affected player's private hand projection.
- Cover serialization, reconnect, and late-spectator projection.

## Task 5: Full-system verification

- Run focused sabotage, match, snapshot, and persistence tests.
- Run the complete core, UI-regression, direct WebRTC network, and Windows export checks.
- Report remaining design-data gaps separately from implementation completeness.
