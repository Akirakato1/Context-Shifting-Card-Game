# Functional 2D Table and Joker Design

**Status:** Approved  
**Date:** 2026-11-15  
**Parent specification:** `docs/superpowers/specs/2026-11-15-shift-card-game-design.md`

## Intent

Create the first playable View for Shift as a functional, scalable 2D tabletop interface. It should make the complete four-player flow understandable with placeholder visuals, support the private interactions needed to form and target hands, and remain a viable final presentation if the jam has no time for 3D assets.

At the same time, add one Joker half-card to each context pile. Jokers have rank zero and temporarily choose a context and suit only while their full card is staged for submission.

## Goals

- Provide a working four-seat gameplay table rather than a static mockup.
- Preserve the existing Model–View–Controller and host-authority boundaries.
- Make hand building, card orientation, ability targeting, Joker assignment, locking, and resolution visually legible.
- Show a live, transparent scoring preview while a submission is being formed.
- Use placeholder shapes, colors, labels, and card backs that can later be replaced with final art.
- Scale cleanly from a 1920×1080 design baseline down to a practical 1280×720 minimum.
- Keep 3D optional; no rules, controller, or network code may depend on 3D presentation.

## Non-goals

- Final illustration, typography, shaders, particle effects, audio, or music.
- 3D card meshes, a perspective camera, physics-based card movement, or skeletal animation.
- Final context names, suit names, normal-hand catalogue, multipliers, or ability catalogue.
- A mobile or portrait layout.
- Replacing the authoritative controller with UI-side validation.

## Anti-goals

- Do not put scoring rules, Joker validation, ability effects, or phase authority in scene scripts.
- Do not network local card ordering, local card orientation, drawer state, hover state, or animation progress.
- Do not expose private hands, staged targets, Joker choices, or ability selections before their normal reveal point.
- Do not block phase progress while waiting for an animation to finish.
- Do not make placeholder art structure so rigid that card textures cannot replace it later.

## Approaches considered

### 1. Godot Control-based 2D interface — selected

Build the table and cards from anchored `Control` scenes. Use containers for stable regions and explicit positioned card layers inside those regions. Use Godot tweens for movement, flipping, dimming, selection glow, drawer expansion, and resolution reveals.

This is the fastest path to a playable jam build, handles resizing well, and keeps input behavior straightforward. Card visuals remain isolated in a reusable component, so a later 3D renderer can consume the same presentation data.

### 2. Hybrid Control HUD plus Node3D cards

Use `Control` for the HUD but render the table, hands, and submissions in 3D. This gives natural perspective and flips, but requires camera composition, ray picking, 2D/3D overlay alignment, and more export testing before the game is playable.

Not selected because the project may remain 2D and the additional work does not improve the rules prototype.

### 3. Custom Node2D canvas

Draw most of the screen through custom `_draw` methods and manually perform hit testing and layout. This offers complete control but would recreate capabilities already provided by Godot UI controls and make accessibility and resizing harder.

Not selected because it increases implementation cost without a corresponding jam benefit.

## Screen composition

The baseline is a landscape 16:9 window.

### Persistent table region

- A large central table occupies the upper portion of the screen.
- The local player is always at the bottom.
- Three opponent seat zones occupy the left, top, and right edges.
- An opponent zone shows name, score/progress, connection/readiness state, hidden hand count, ability count, and its reveal area.
- Opponent hands use card backs and may curve or fan toward their seat edge.
- The Rise, Flourish, and Fall piles sit near the center, using distinct temporary treatments and showing only public information permitted by the lobby visibility setting.
- Active field effects, the current phase, phase timer, round, active context, and direction remain visible without opening another panel.

### Local cockpit

- The local six-card hand runs across the bottom center.
- A submission shelf sits directly above the hand and can hold zero to six full cards.
- A context-clock control occupies the lower-left region and shows Rise/Flourish/Fall plus current direction.
- The lower-right region contains the collapsed Ability button and sorting controls.
- Sort controls offer context, rank, and suit arrangements. Sorting affects only local display order.
- The Ability button expands a vertical drawer upward. The drawer can be collapsed without cancelling already committed effects.

### Score preview

While cards are staged, the submission shelf displays:

- submitted base-value sum;
- detected best normal hand and its multiplier;
- detected best context hand and its multiplier;
- visible score modifiers;
- projected rounded score;
- a clear invalid or incomplete reason when locking is unavailable.

All preview calculations call pure domain/presenter services using the same definitions as the host. The host still revalidates the lock command.

## Card presentation component

Each `CardView` presents one full card as two half-card regions separated diagonally or through the final art mask.

It supports these presentation states:

- in local hand;
- staged submission;
- hidden opponent card back;
- revealed opponent submission;
- eligible/ineligible targeting;
- selected target;
- locked;
- resolving;
- disabled or disconnected overlay.

Right-clicking a local card reverses its visual half orientation. This is a private View preference and does not swap the immutable halves in the model. The visual orientation determines the default half highlighted for normal-hand selection, but the staged command still carries an explicit half index.

Cards can be dragged to reorder within the hand or submission shelf. Clicking a hand card moves it to the submission shelf; clicking a staged card returns it to the hand. Reordering and orientation are not networked because they do not change game rules.

## Submission interaction

The View keeps a private draft submission containing:

- ordered full-card IDs;
- selected normal-hand half index for each card;
- temporary Joker context and suit choices for every Joker half present on each staged full card.

Every draft change updates the preview. A lock command is enabled only when:

- the draft has at most six cards;
- every submitted card is eligible under the active-context rules;
- every selected half is legal;
- every staged Joker half has a context and suit assignment;
- no ability selection is incomplete;
- the host has not already locked the hand.

The host validates the complete staged payload and remains authoritative. Locking makes the draft immutable until resolution.

## Joker half-card rules

### Identity and piles

- Each of the Rise, Flourish, and Fall piles gains exactly one Joker half-card, increasing each pile from 90 to 91 half-cards.
- A Joker retains an origin pile context solely for ownership, discard, recycling, serialization, and card counting.
- Its immutable rank is `0`.
- It has no immutable gameplay suit or context choice.
- It resets like every other half-card when its full card leaves the hand; staged choices reset sooner as described below.

### Eligibility and temporary assignment

- A Joker half is eligible during every active context.
- Every Joker half on a full card moved into the submission shelf receives a submission-local context and suit assignment.
- Defaults are context Rise and suit ONE, the first entries in the current enumerations.
- Context and suit prompts appear directly on the Joker half while it is staged.
- The player may change either choice before locking.
- Assignments reset immediately when the full card leaves the submission shelf, when the draft is replaced or cancelled, or after resolution.
- Assignments never enter the persistent half-card override layer.
- If a full card contains two Joker halves, each half has an independent context and suit choice.

### Scoring behavior

- A submitted Joker contributes base value `0`.
- Its chosen temporary context contributes to context-hand tallies.
- If the Joker is the selected normal-hand face, it uses rank `0` and its chosen temporary suit.
- Context and suit are wild only through the player's explicit staged choices; rank is never wild.
- With multiple selected Jokers, ordinary normal-hand definitions see repeated rank-zero values normally. This follows from rank zero being a real selected value and can be revisited when the final normal-hand catalogue is balanced.

### Serialization and privacy

- `HalfCardState` gains an explicit normal/Joker identity rather than overloading persistent overrides.
- Staged Joker assignments live in the player's private staging state and round-trip through snapshots/reconnects.
- Opponents and spectators do not receive staged Joker assignments.
- Resolution events reveal the chosen context and suit with the rest of the submitted effective face data.

## Ability interaction mode

Right-clicking an ability begins its local targeting workflow when legal.

- The table and unrelated HUD regions dim.
- Eligible card regions receive a luminous backdrop.
- Ineligible cards remain visible but non-interactive.
- Clicking an eligible card marks it with a yellow selection tint.
- The targeting prompt explains the current step and remaining selections.
- Multi-step abilities advance through their declared selection steps.
- The screen remains in the dimmed modal state until all required choices are committed or the player cancels.
- Cancellation is allowed before the effect's final commit, matching the controller rule that incomplete local selection is reversible.
- After commit, the UI exits targeting mode and cannot undo the authoritative action.

The generic workflow is driven by ability choice-schema data. Specific effects remain controller handlers, not View callbacks.

## Resolution presentation

When hand play resolves:

- local and remote submissions move from their shelves into seat-specific reveal areas;
- cards flip or pivot face-up like revealing mahjong tiles;
- the animation uses authoritative revealed-event data;
- score components appear beside each submission;
- ties and nil rounds are represented explicitly;
- late or skipped animations may catch up immediately without delaying the phase controller.

The initial implementation may use scale/rotation tweens and z-order changes. No skeletal or 3D animation is required.

## View architecture

Suggested boundaries:

- `GameTableView`: root layout and phase-level presentation.
- `SeatView`: reusable local/opponent seat status and reveal region.
- `CardView`: reusable full-card visual and input surface.
- `HandView`: local hand ordering and card movement.
- `SubmissionView`: draft construction, Joker prompts, and lock affordance.
- `AbilityDrawerView`: collapsed/expanded ability inventory.
- `TargetingOverlay`: modal dimming, eligibility, prompt, and selection feedback.
- `ScorePreviewView`: renders a domain-produced preview result.
- `ContextClockView`: active context and direction.
- `GameTablePresenter`: translates snapshots/domain events into view data and translates UI intent into commands.

Scene scripts emit intent signals and render supplied data. They do not mutate `MatchState` or execute ability effects.

## State and network boundaries

### Local-only View state

- card display order;
- visual half orientation;
- hover/focus state;
- ability drawer expanded state;
- in-progress uncommitted ability choices;
- animation positions and progress.

### Private authoritative state

- staged card IDs and selected half indexes;
- staged Joker context/suit assignments;
- completed private manipulation results;
- local ability hand and legal targeting information.

### Public authoritative state

- locked/revealed submissions at the normal reveal time;
- public ability plays and field effects;
- scores, phase, timers, context clock, readiness, and connection status.

## Error and interruption handling

- A host rejection returns the affected card or control to its authoritative state and displays the stable error reason.
- A snapshot/reconnect replaces authoritative staging data while preserving harmless local preferences where matching card IDs still exist.
- Phase timeout cancels incomplete local targeting and follows the controller's existing default action.
- Disconnect freeze is visible and prevents new authoritative actions while still allowing inspection and local reordering.
- Resolution can skip directly to its final arrangement if reconnecting after the reveal animation began.

## Testing and acceptance

### Domain tests

- 91 half-cards per context pile with one unique Joker per pile.
- Joker recycling preserves origin-pile ownership.
- Joker eligibility in Rise, Flourish, and Fall.
- independent context/suit assignment for one or two Joker halves on a full card;
- default Rise/ONE assignment on staging;
- reset on unstage, draft replacement, resolution, and leaving hand;
- private snapshot round-trip without opponent leakage;
- rank-zero/suit-choice participation in normal and context evaluation;
- lock rejection for missing or malformed Joker assignments.

### Presenter/View tests

- four-seat layout instantiates at 1920×1080 and 1280×720;
- hand-to-submission movement and reordering;
- right-click visual orientation without model mutation;
- ability drawer expansion/collapse;
- targeting dimmer, eligibility glow, yellow selection, cancellation, and commit;
- score-preview updates and invalid reasons;
- Joker prompt defaults and edits;
- locked-state input suppression;
- authoritative resolution reveal and animation skip.

### Acceptance walkthrough

With four players represented, a local player can arrange six cards, move any subset into the submission shelf, orient and reorder them, assign every staged Joker, see the current scoring components, use and cancel a targeting ability, lock a valid hand, and watch all locked hands reveal without any private information appearing early.

## Deferred decisions

- Final colors, textures, typeface, iconography, and card aspect treatment.
- Whether final rank-zero pairs or other Joker-specific normal patterns should receive special balance rules.
- Final ability targeting schemas beyond the representative cards supplied later.
- Whether future 3D presentation replaces only `CardView` or the whole table surface.
