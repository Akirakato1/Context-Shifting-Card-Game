# Asset Library, Context Names, and Main-Branch Publication Design

**Date:** 2026-11-21
**Status:** Approved approach, pending implementation

## Intent

Prepare the project for its first publication to the supplied GitHub repository, give future artwork/audio/animation files clear homes, and replace the temporary A/B/C context vocabulary with the finalized English development names `Rise`, `Flourish`, and `Fall`. The traditional Chinese concepts `興`, `盛`, and `衰` remain art-direction references rather than internal identifiers.

## Goals

- Publish the complete existing project to `https://github.com/Akirakato1/Context-Shifting-Card-Game` on `main` without force-pushing or discarding its existing remote commit.
- Rename internal context identifiers to `RISE`, `FLOURISH`, and `FALL` while retaining integer values `0`, `1`, and `2` so serialized state and network messages remain compatible.
- Show `Rise`, `Flourish`, and `Fall` in the current placeholder UI and keep the fixed cycle `Rise -> Flourish -> Fall -> Rise`.
- Create tracked asset areas for artwork, sound effects, music, and animations, each with concise placement and format guidance.
- Update current project documentation and tests that describe the context names. Historical implementation plans may retain their original A/B/C terminology as records of earlier work.

## Asset Structure

```text
assets/
  artwork/         Static visual assets and texture sources: UI, buttons, card frames/faces,
                   table/trays, icons, context motifs, and visual-effect artwork.
  sound_effects/   Short interaction, ability, phase, reveal, score, and UI sounds.
  music/           Background music, loops, stems, and source/export notes.
  animations/      Godot animation resources and event/interaction timing definitions.
```

Artwork supplies textures and static visual material used by game objects and UI. Animation resources describe how those elements move, transform, reveal, or transition. If a future animation uses rendered frames or a sprite sheet, the image source belongs under artwork and the playback/timing resource belongs under animations.

## Context Vocabulary

| Numeric value | Internal enum | Placeholder UI | Art-direction concept |
| --- | --- | --- | --- |
| 0 | `RISE` | Rise | `興` |
| 1 | `FLOURISH` | Flourish | `盛` |
| 2 | `FALL` | Fall | `衰` |

The rename is semantic only. Numeric protocol values, pile keys, saved-state representation, joker choices, scoring data, and context-cycle arithmetic remain unchanged.

## Approaches Considered

1. **Full semantic rename — selected.** Replace A/B/C identifiers throughout active source and tests, preserving the numeric values. This produces a clean vocabulary now that the theme is decided.
2. **Compatibility aliases.** Add new enum aliases while retaining A/B/C. This reduces mechanical churn but leaves two names for each concept and invites inconsistent future code.
3. **Display-only rename.** Change UI labels while keeping A/B/C internally. This is smallest but contradicts the requirement to use English context names during development.

## Git Publication

The local repository currently uses `master` and has no configured remote. The target repository already has a `main` commit. Implementation will add the target as `origin`, fetch `origin/main`, inspect it, merge its history into the local work without overwriting either side, rename the local branch to `main`, run verification, and push normally. Any non-trivial merge conflict stops the push until it is resolved and reverified; force-push is out of scope.

## Non-goals

- No finalized ability catalogue, hand catalogue, multipliers, suits, artwork, audio, or animation content is invented here.
- No gameplay rule, network protocol value, or saved-state schema changes.
- No binary placeholder assets are generated.
- No release build or itch.io upload is performed.

## Verification

- Search active source and tests for remaining `Context.A`, `Context.B`, `Context.C`, and player-facing A/B/C context labels.
- Run the full Godot, UI, and signaling test suites plus the multi-process network fixture.
- Confirm numeric context serialization remains `0/1/2` and the default cycle remains ordered.
- Confirm the final branch is `main`, the worktree is clean, remote history is retained, and `origin/main` points to the verified local commit after the normal push.
