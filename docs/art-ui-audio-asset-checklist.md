# Art, UI, animation, and audio asset checklist

The context names are finalized as Rise / `興`, Flourish / `盛`, and Fall / `衰`; the suits are finalized as Mountain, Cloud, and Sea. Use the English names for development identifiers and placeholder UI, and use the traditional Chinese context concepts to inspire visual motifs. The initial context-hand priorities and multipliers are implemented; normal-hand definitions and balance, ability copy counts, and final art treatments remain open to iteration.

## Priority key

- **P0 — jam-critical:** required for a readable, shippable functional 2D build.
- **P1 — polish:** materially improves clarity, feedback, and identity after the full loop works.
- **P2 — optional/future:** 2.5D presentation, expanded animation, and content-specific luxury work.

## Minimum jam art pack

This is the smallest coherent pack worth producing first:

- [ ] P0 — 1 table/playmat background with four readable seat regions.
- [ ] P0 — 3 context emblems plus 3 distinct patterns/color families.
- [ ] P0 — 3 suit icons.
- [ ] P0 — number/rank treatment for 0–10.
- [ ] P0 — 1 normal half-card face template, assembled from context/rank/suit elements.
- [ ] P0 — 1 diagonal full-card merge frame/divider.
- [ ] P0 — 1 normal card back and 1 ability card back.
- [ ] P0 — 1 Joker half illustration plus Rise/Flourish/Fall selected overlays or tints.
- [ ] P0 — 4 ability-type icons/frames: manipulation, field, buff/nerf, sabotage.
- [ ] P0 — context clock/dial with forward and reverse arrows.
- [ ] P0 — three pile/deck markers and a shared recycle/shuffle marker.
- [ ] P0 — submission shelf/box, selected glow, disabled treatment, target glow, and locked treatment.
- [ ] P0 — approximately 20 reusable UI glyphs/states; most can be Godot shapes or vectors.
- [ ] P0 — 12–18 core sound effects listed in the “Minimum jam sound pack” section.
- [ ] P1 — game logo/title treatment and itch.io cover art.
- [ ] P1 — 1 seamless match music loop; menu/lobby may share it during the jam.

Avoid drawing a unique illustration for every rank/suit/context combination. Build normal cards from layered reusable pieces so one face template, three context treatments, three suit icons, and the rank glyphs produce the whole deck. Reserve unique illustrations for Joker halves and, later, individual abilities.

## Gameplay card artwork

| Priority | Asset | Variants/count | Production notes |
| --- | --- | ---: | --- |
| P0 | Normal half-card face template | 1 | Safe areas for context, rank, suit, and future effect markers. |
| P0 | Context visual language | 3 | Emblem + pattern + color for Rise (`興`), Flourish (`盛`), and Fall (`衰`); never rely on color alone. |
| P0 | Suit icons | 3 | Legible at small card size and in monochrome. |
| P0 | Rank glyph treatment | 11 | 0–10; 0 is primarily for Joker display. Prefer font/vector assembly. |
| P0 | Full-card merge frame | 1 | Diagonal or otherwise clear division between the two halves. |
| P0 | Normal card back | 1 | Used for hidden opponent hands and face-down/reveal states. |
| P0 | Joker half | 1 base + 3 selections | Neutral “every context” state; Rise/Flourish/Fall choice appears only while staged. |
| P0 | Active-half indicator | 2 states | Shows which half supplies rank/suit for the current context. |
| P0 | Card state overlays | 6 | Hover, selected, staged, targeting-eligible, targeting-selected, disabled/locked. |
| P1 | Modified-half marker | 1–3 | Clearly communicates a persistent overwrite while the card remains in hand. |
| P1 | Submission/reveal frame | 1 | Supports the “flip up like mahjong tiles” reveal presentation. |
| P1 | Hand-category badge frame | 1 | Dynamic text for the detected normal hand. |
| P1 | Context-pattern badge frame | 1 | Dynamic text for the detected context hand. |
| P1 | Multiplier and base-value badges | 3 | Base, normal multiplier, context multiplier; values remain dynamic text. |
| P2 | Card edge/depth art | 1 set | Only if the final build uses 2.5D cards. |

## Ability and field artwork

| Priority | Asset | Variants/count | Production notes |
| --- | --- | ---: | --- |
| P0 | Ability card back | 1 | Visually distinct from normal cards. |
| P0 | Ability front template | 1 | Areas for name, timing, type, rules text, and optional illustration. |
| P0 | Ability-type identity | 4 | Icon/frame treatment for manipulation, field, buff/nerf, sabotage. |
| P0 | Timing icons | 3–4 | Main 1, hand play, Main 2, and both-main-phases treatment. |
| P0 | Generic ability illustration | 4 | One per type is enough until unique card art is possible. |
| P1 | Unique ability illustrations | final unique ability count | Produce after the ability list is locked; reuse art for mechanical variants if needed. |
| P1 | Field-effect panel/token | 1 template | Dynamic name, owner, and remaining-turn count. |
| P1 | Field duration counter | digits + frame | Must remain readable over table art. |
| P1 | Add-context field overlays | 3 | “Also activate Rise/Flourish/Fall” without moving the clock; lasts one turn. |
| P1 | Reverse-cycle field marker | 1 | Visually changes context-clock direction. |
| P1 | Current-context shift marker | 3 | Clock jump/fast-forward to Rise/Flourish/Fall. |
| P1 | Buff/nerf status markers | expandable | Generic positive/negative frames until the final list is known. |
| P1 | Sabotage marker | 1 | Shows that a hidden/random card was affected without revealing which card. |

## Table and gameplay environment

- [ ] P0 — table/playmat background with clean central scoring space.
- [ ] P0 — four fixed seat frames: bottom/local, top, left, right.
- [ ] P0 — player nameplate, score/wins panel, ready/thinking/reconnecting/pending status area.
- [ ] P0 — three context pile bases with visible remaining-count area.
- [ ] P0 — central context clock with active-context marker and forward/reverse direction.
- [ ] P0 — submission shelf/box above the local hand.
- [ ] P0 — central reveal/resolution zone for all players’ played hands.
- [ ] P0 — ability drawer/tab background that expands upward.
- [ ] P1 — avatar/crest frame; use a generic silhouette until portraits exist.
- [ ] P1 — spectator-count treatment and spectator badge.
- [ ] P1 — discard/recycle/shuffle visual near the piles.
- [ ] P1 — field-effect rail with duration counters.
- [ ] P1 — round winner, nil round, and match winner presentation panels.
- [ ] P1 — subtle table vignette/lighting that preserves card readability.
- [ ] P2 — alternate table skins or themed room backgrounds.

## Menus and common UI elements

### Main menu

- [ ] P0 — title/logo placeholder or final logo.
- [ ] P0 — menu background.
- [ ] P0 — player-name text field and validation state.
- [ ] P0 — Host Game button.
- [ ] P0 — room-code field and Join button.
- [ ] P0 — Player/Spectator role selector.
- [ ] P0 — connection progress, error banner, and retry/return actions.
- [ ] P1 — settings, credits, quit, and accessibility icons if those screens are added.

### Lobby

- [ ] P0 — room-code display and copy/share icon.
- [ ] P0 — four player rows and four spectator rows/slots.
- [ ] P0 — host crown, ready check, disconnected, reconnecting, pending, player, and spectator icons.
- [ ] P0 — Ready, Start Match, Leave, Retry, and Details buttons.
- [ ] P0 — victory mode, victory target, visibility, phase timer, reaction window, hard limit, and reconnect grace controls.
- [ ] P0 — checkbox/toggle, dropdown, spin/stepper, slider if used, and disabled/locked states.
- [ ] P1 — invite/copy confirmation toast.
- [ ] P1 — join/leave notifications.

### Match HUD

- [ ] P0 — five phase banners/tabs: Start, Main 1, Hand Play, Main 2, End.
- [ ] P0 — round number, timer, local race progress, and spectator count.
- [ ] P0 — timer normal/warning/expired states.
- [ ] P0 — Ready, Confirm Draw, Lock Hand, Pass, Confirm Discard, Cancel, Commit buttons.
- [ ] P0 — Rise/Flourish/Fall replacement-request steppers and total/required indicator.
- [ ] P0 — public/private request visibility indicator.
- [ ] P0 — ability tab, count badge, expanded drawer, legal/illegal/used states.
- [ ] P0 — dim overlay for targeting mode.
- [ ] P0 — glowing card-area backdrop plus eligible and yellow selected treatments.
- [ ] P0 — target prompt, remaining-choice count, option buttons, Commit and Cancel.
- [ ] P0 — card move-left/move-right icons and orientation/flip hint.
- [ ] P0 — Joker context and suit selectors shown only on staged Joker halves.
- [ ] P0 — base-value, normal-hand multiplier, context-hand multiplier, projected score, and invalid-reason areas.
- [ ] P0 — connection freeze/reconnect overlay with countdown.
- [ ] P1 — ability-history feed with public information only.
- [ ] P1 — timeout/autoselection notice.
- [ ] P1 — tooltip frame and contextual help icon.

### Results

- [ ] P0 — winner/match-ended title treatment.
- [ ] P0 — standings rows with rank, name, score, and round wins.
- [ ] P0 — nil-round note.
- [ ] P0 — Start Rematch, Return to Lobby, and Return to Menu buttons.
- [ ] P0 — non-host “waiting for host” state.
- [ ] P1 — victory/defeat background treatments or character splashes.

### Reusable control states

Every interactive control should have normal, hover, pressed, keyboard-focus, disabled, and selected states. Prefer scalable `StyleBoxFlat`, nine-slice panels, SVG icons, or vector source rather than separate bitmaps for every state.

## Animation and visual effects

Most P0 motion can be built with Godot tweens, transforms, modulate colors, and simple shaders rather than frame-by-frame animation.

### P0 functional feedback

- [ ] Card hover/lift and click selection.
- [ ] Move card between hand and submission shelf.
- [ ] Local reorder slide.
- [ ] Card orientation flip/rotate.
- [ ] Lock-in confirmation pulse.
- [ ] Targeting dim, eligible glow, and yellow selected glow.
- [ ] Ability drawer expand/collapse.
- [ ] Draw/deal/replenish movement.
- [ ] Hand reveal/mahjong-style flip-up.
- [ ] Context-clock tick to next context.
- [ ] Timer warning pulse and timeout flash.
- [ ] Score count-up and multiplier application.
- [ ] Reconnect/frozen spinner or pulse.

### P1 polish

- [ ] Merge two half cards into one full card.
- [ ] Joker neutral-to-selected-context transformation.
- [ ] Modified-half shimmer or persistent marker transition.
- [ ] Ability play travel from drawer to field/target.
- [ ] Four ability-type effect signatures.
- [ ] Sabotage hit without revealing the affected card.
- [ ] Field activation, remaining-turn tick, and expiration.
- [ ] Context direction reversal and fast-forward/jump.
- [ ] Temporary additional-context activation overlay.
- [ ] Pile recycle/shuffle animation.
- [ ] Round winner, tied/nil round, match victory, and defeat stingers.

### P2 optional 2.5D

- [ ] Simple beveled card mesh with consistent UV layout.
- [ ] Card-front, card-back, and edge materials.
- [ ] Table/playmat mesh and material.
- [ ] Orthographic/perspective camera preset that preserves 2D readability.
- [ ] Key/fill lighting, soft shadows, and restrained depth of field if any.
- [ ] 3D deal, tilt, flip, and reveal animations.
- [ ] 2D UI overlay remains the source of truth for text and controls.

## Sound effects

### Minimum jam sound pack

Aim for 12–18 short sounds, with small pitch variation where repetition is likely:

- [ ] P0 — primary UI click/confirm.
- [ ] P0 — back/cancel.
- [ ] P0 — invalid/error.
- [ ] P0 — card pick up/select.
- [ ] P0 — card place/stage.
- [ ] P0 — card flip/orientation.
- [ ] P0 — draw/deal.
- [ ] P0 — discard.
- [ ] P0 — shuffle/recycle.
- [ ] P0 — hand lock-in.
- [ ] P0 — simultaneous reveal.
- [ ] P0 — ability select/play.
- [ ] P0 — targeting choice/complete.
- [ ] P0 — context-clock tick/change.
- [ ] P0 — timer warning/timeout.
- [ ] P0 — score tally/multiplier.
- [ ] P0 — round win or nil/tie stinger.
- [ ] P0 — connection lost/reconnected.

### Expanded SFX library

| Group | Sounds/variants |
| --- | --- |
| Common UI | hover, click, confirm, cancel/back, toggle, drawer open/close, error, disabled action, notification. |
| Cards | hover, pickup, place, reorder slide, flip, deal, draw, discard, shuffle, pile recycle, merge halves, lock, reveal. |
| Abilities | select, cancel, commit, generic play, manipulation signature, field signature, buff, nerf, sabotage, target tick, targeting complete. |
| Context clock | normal tick, context change, reverse direction, jump/fast-forward, temporary extra-context activation, extra-context expiry. |
| Timers/readiness | player ready, all ready, warning pulse, final countdown ticks, timeout/autoselect. |
| Scoring | base-value tally, normal multiplier, context multiplier, modifier application, final score, round win, tied/nil round. |
| Match outcome | victory stinger, defeat stinger, last-player-standing result, host-loss stop. |
| Lobby/network | room created, join accepted, player entered, player left, spectator joined, disconnect, reconnect attempt, reconnect success. |

Do not use a separate sound for every card rank or context unless it contributes meaningfully. Variants of a small coherent family will sound more polished than many unrelated clips.

## Music and ambience

- [ ] P1 — main menu/lobby loop.
- [ ] P1 — match loop with enough space for UI and card sounds.
- [ ] P1 — subtle pressure layer for the final timer seconds, if adaptive music is feasible.
- [ ] P1 — results/victory cue; defeat may be a shorter alternate ending.
- [ ] P2 — table ambience, room tone, or themed environmental loop.
- [ ] P2 — alternate tracks for long sessions.

Keep music optional for the jam if time is tight. Functional sound feedback is more important than a full score.

## Technical delivery specifications

### Images and UI

- Keep editable source files for every asset; export PNG/WebP for raster art and SVG where Godot imports it cleanly.
- Export transparent elements with clean alpha and no baked background fringe.
- Author at 2× the intended 1280×720 display size when practical, then test downscaling.
- Mark nine-slice margins for panels, buttons, banners, input fields, and nameplates.
- Keep dynamic names, room codes, scores, timers, hand names, multipliers, and ability rules as live text; do not bake them into art.
- Leave safe space for long player names and later localization.
- Use context icon + pattern + color together so color-vision differences do not hide game state.
- Check contrast at actual card size, not only in the large source canvas.
- Suggested naming: `category_element_variant_state.ext`, for example `card_context_rise_selected.svg`.

### Audio

- Deliver lossless WAV masters at 44.1 or 48 kHz; import OGG for longer in-game music/ambience as appropriate.
- Trim silence and clicks, define clean music loop points, and keep a little tail for effects that need it.
- Use mono for positional/short UI and card effects unless stereo width is intentional; music and ambience can be stereo.
- Normalize within each family and test through separate Godot buses: Master, Music, SFX, UI, and Ambience.
- Leave headroom so simultaneous reveal/score sounds do not clip.
- Every essential audio cue should also have a visual equivalent.

## Content-dependent counts to fill later

- Unique ability illustrations: **one per finalized unique ability**, or one per mechanic family for the jam.
- Ability icons/status markers: **one per distinct persistent effect** that players must recognize without opening rules text.
- Normal hand badges: **one reusable badge frame** plus dynamic names; optional unique emblems per finalized hand category.
- Context hand badges: **one reusable badge frame** plus dynamic names; optional unique emblems per finalized context pattern family.
- Context/suit names: Rise/Flourish/Fall are locked; replace Suit 1/2/3 labels after the suit theme is decided, without changing the underlying numeric identifiers.

## Recommended production order

1. Lock the context and suit visual language, card face/back templates, Joker, and table readability.
2. Produce P0 UI states and the minimum sound pack while final ability data is still being written.
3. Apply the final hand/context names and multipliers using dynamic text.
4. Add unique ability illustrations only after the ability list stabilizes.
5. Add P1 reveal/scoring/clock effects and music.
6. Treat 2.5D meshes and animation as a separate optional milestone after the complete 2D multiplayer loop survives external playtests.
