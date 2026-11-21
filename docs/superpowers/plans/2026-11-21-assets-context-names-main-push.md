# Asset Library, Context Names, and Main-Branch Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Organize the game asset library, replace A/B/C with the finalized Rise/Flourish/Fall development vocabulary without changing protocol values, and publish the verified project to the supplied GitHub repository's `main` branch.

**Architecture:** `GameTypes.Context` remains the single numeric domain source with explicit values `0`, `1`, and `2`, while a central context-name helper supplies UI text. Static visual sources, sound effects, music, and Godot animation resources live in separate tracked asset areas. GitHub publication preserves the existing remote `main` commit through a normal merge and push; force-push is forbidden.

**Tech Stack:** Godot 4.7.2 / GDScript, PowerShell test harnesses, Node.js 22 signaling tests, Git/GitHub

**Spec:** `docs/superpowers/specs/2026-11-21-assets-context-names-main-push-design.md`

## Global Constraints

- Work natively in the current repository; do not use implementation subagents.
- Preserve context wire/save values exactly: `RISE = 0`, `FLOURISH = 1`, `FALL = 2`.
- Preserve the cycle order `Rise -> Flourish -> Fall -> Rise` and reverse it only through the existing direction mechanic.
- Use English context names in active source, tests, node names, and placeholder UI; use `興`, `盛`, and `衰` only as documented art-direction concepts.
- Do not invent abilities, hand shapes, suits, multipliers, artwork, audio, or animation content.
- Do not change networking message shapes, serialized context integers, or gameplay rules.
- Preserve the target repository's existing `main` history; never force-push.
- Use the pinned official Godot 4.7.2 executable for verification. If it is absent, obtain it in ignored task scratch space and verify its version before running tests.

## Review Focus

- Serialized snapshots created before the rename still contain integers `0..2`; round-trip tests must prove those values retain the same Rise/Flourish/Fall meaning.
- Inclusive range checks formerly bounded by A/C can silently become wrong; the focused type test and full controller suite must exercise `RISE..FALL` boundaries.
- Player-facing context selectors can retain placeholder labels even when the enum changes; view tests must assert the clock, pile names, joker choices, and replenishment selectors use finalized English names.
- The remote `main` branch already has a commit that may be unrelated to local history; publication must fetch, inspect, merge without force, and rerun verification after the merge.
- Empty asset directories are not tracked by Git; each required area must contain a guidance file and `git ls-files assets` must prove all four areas are present.

---

### Task 1: Tracked Asset Library

**Files:**
- Create: `assets/README.md`
- Create: `assets/artwork/README.md`
- Create: `assets/sound_effects/README.md`
- Create: `assets/music/README.md`
- Create: `assets/animations/README.md`
- Delete: `assets/placeholder/README.md`

**Interfaces:**
- Consumes: the approved four-area asset structure.
- Produces: stable tracked paths `res://assets/artwork`, `res://assets/sound_effects`, `res://assets/music`, and `res://assets/animations` for future imports.

- [ ] **Step 1: Replace the placeholder asset note with the asset-library guidance files**

Document these exact ownership boundaries:

- artwork: UI, buttons, card frames/faces, table and tray textures, icons, context motifs, static VFX artwork, and source/export notes;
- sound effects: short UI, card, ability, phase, reveal, and score sounds;
- music: background tracks, loops, stems, and source/export notes;
- animations: Godot animation resources and event/interaction timing; rendered frames or sprite-sheet images remain artwork.

Include the art-direction mapping `Rise / 興`, `Flourish / 盛`, and `Fall / 衰` in `assets/artwork/README.md` without using the Chinese characters as code identifiers.

- [ ] **Step 2: Verify the tracked structure**

Run:

```powershell
git ls-files assets
Get-ChildItem -Directory assets | Sort-Object Name | Select-Object -ExpandProperty Name
```

Expected: tracked README files exist for `artwork`, `sound_effects`, `music`, and `animations`; the obsolete `placeholder` path is absent.

- [ ] **Step 3: Commit Task 1**

```powershell
git add assets
git commit -m "chore: organize game asset library"
```

---

### Task 2: Rise, Flourish, and Fall Domain Vocabulary

**Files:**
- Create: `tests/core/common/game_types_test.gd`
- Modify: `src/core/common/game_types.gd`
- Modify: `src/core/abilities/effect_registry.gd`
- Modify: `src/core/cards/card_factory.gd`
- Modify: `src/core/cards/context_pile.gd`
- Modify: `src/core/cards/half_card_state.gd`
- Modify: `src/core/match/match_controller.gd`
- Modify: `src/core/match/match_state.gd`
- Modify: `src/core/scoring/context_hand_definition.gd`
- Modify: `src/core/scoring/context_hand_evaluator.gd`
- Modify: `src/core/scoring/submission_evaluator.gd`
- Modify: `src/view/app/runtime_game_session.gd`
- Modify: `src/view/match/card_widget.gd`
- Modify: `src/view/match/match_screen.gd`
- Modify: `src/view/match/match_screen.tscn`
- Modify: `src/view/match/phase_controls.gd`
- Modify: `src/view/match/phase_controls.tscn`
- Modify: `tests/core/abilities/ability_state_test.gd`
- Modify: `tests/core/cards/card_factory_test.gd`
- Modify: `tests/core/cards/context_pile_test.gd`
- Modify: `tests/core/cards/joker_half_test.gd`
- Modify: `tests/core/match/command_validation_test.gd`
- Modify: `tests/core/match/end_phase_controller_test.gd`
- Modify: `tests/core/match/hand_play_controller_test.gd`
- Modify: `tests/core/match/joker_submission_controller_test.gd`
- Modify: `tests/core/match/main_one_controller_test.gd`
- Modify: `tests/core/match/match_setup_test.gd`
- Modify: `tests/core/match/review_hardening_test.gd`
- Modify: `tests/core/match/snapshot_projector_test.gd`
- Modify: `tests/core/match/start_phase_controller_test.gd`
- Modify: `tests/core/scoring/context_and_score_test.gd`
- Modify: `tests/core/scoring/submission_evaluator_test.gd`
- Modify: `tests/network/lobby_sync_test.gd`
- Modify: `tests/network/network_session_test.gd`
- Modify: `tests/view/match_screen_test.gd`
- Modify: `tests/view/phase_controls_test.gd`

**Interfaces:**
- Consumes: existing integer context fields in commands, events, snapshots, saved state, and scoring definitions.
- Produces: `GameTypes.Context.RISE/FLOURISH/FALL` with values `0/1/2`; `GameTypes.context_name(context: int) -> String`; unchanged serialized integers; English placeholder UI labels.

- [ ] **Step 1: Write failing context-domain tests**

Create tests named:

- `test_context_values_preserve_protocol_order_and_names`: assert enum values are `0/1/2`, `context_name()` returns `Rise/Flourish/Fall`, and invalid values return `Unknown`.
- `test_context_integer_snapshot_round_trip_preserves_final_meaning`: create/serialize/restore a match at each context integer and assert the restored value and name match.

Extend existing view tests to assert:

- the forward clock reads `Rise -> Flourish -> Fall` and reverse clock reads `Fall <- Flourish <- Rise` using the existing arrow glyph style;
- center piles are named Rise, Flourish, and Fall;
- Joker context choices display Rise, Flourish, and Fall;
- replenishment SpinBoxes have Rise, Flourish, and Fall suffixes while still emitting integer keys `0/1/2`.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 tests/core/common/game_types_test.gd tests/view/match_screen_test.gd tests/view/phase_controls_test.gd
```

Expected: FAIL because finalized enum members, names, and UI labels do not yet exist.

- [ ] **Step 3: Implement the domain rename**

In `game_types.gd`, define explicit numeric members and the central name helper. Replace every active `GameTypes.Context.A/B/C` reference with `RISE/FLOURISH/FALL`, including range bounds and tests. Preserve all integer payloads and cycle arithmetic.

Rename active placeholder identifiers that encode the old vocabulary, including context-hand fixture IDs such as `abc_*`, to semantic English IDs such as `all_contexts_*`. Do not rename unrelated identifiers merely containing the letters a, b, or c.

- [ ] **Step 4: Implement finalized placeholder UI labels**

Use `GameTypes.context_name()` in `card_widget.gd` and `match_screen.gd`. Rename scene nodes `PileA/B/C` to `PileRise/Flourish/Fall`, rename replenishment nodes and variables to the finalized names, and set the three SpinBox suffixes accordingly. Keep request dictionary keys integer `0/1/2`.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the Step 2 command.

Expected: all focused tests PASS with no engine errors.

- [ ] **Step 6: Search for active placeholder identifiers**

Run:

```powershell
rg -n "GameTypes\.Context\.[ABC]|CONTEXT_NAMES.*A.*B.*C|Pile[ABC]|A  →  B  →  C|A/B/C" src tests
```

Expected: no context-placeholder matches in active source or tests.

- [ ] **Step 7: Run the complete Godot and UI suites**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_ui.ps1
```

Expected: all tests PASS with no engine errors.

- [ ] **Step 8: Commit Task 2**

```powershell
git add src tests
git commit -m "refactor: name contexts rise flourish and fall"
```

---

### Task 3: Current Documentation and Full Regression

**Files:**
- Modify: `docs/art-ui-audio-asset-checklist.md`
- Modify: `docs/superpowers/specs/2026-11-15-shift-card-game-design.md`
- Modify: `docs/superpowers/specs/2026-11-15-functional-2d-table-joker-design.md`

**Interfaces:**
- Consumes: Task 1's asset paths and Task 2's finalized context vocabulary.
- Produces: current design and art guidance using Rise/Flourish/Fall and `興/盛/衰`, while explicitly leaving abilities, hand shapes, multipliers, and suits unfinished.

- [ ] **Step 1: Update current design references**

Replace context placeholders in the three current documents with the finalized names and cycle. Update the asset checklist introduction so only suits, hands, abilities, and multipliers remain undecided. Preserve historical implementation plans unchanged.

- [ ] **Step 2: Verify documentation and asset references**

Run:

```powershell
rg -n "A/B/C|A -> B -> C|A→B→C|A  →  B  →  C|theme names for A/B/C" docs/art-ui-audio-asset-checklist.md docs/superpowers/specs/2026-11-15-shift-card-game-design.md docs/superpowers/specs/2026-11-15-functional-2d-table-joker-design.md
rg -n "Rise|Flourish|Fall|興|盛|衰" assets docs/art-ui-audio-asset-checklist.md docs/superpowers/specs/2026-11-15-shift-card-game-design.md
```

Expected: the placeholder search has no matches; finalized names and art concepts are documented.

- [ ] **Step 3: Run the complete pre-publication matrix**

Run:

```powershell
Set-Location service/signaling
npm test
Set-Location ../..
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_ui.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_network.ps1
git diff --check
```

Expected: signaling, full Godot, UI, and multi-process network suites exit `0`; whitespace check has no output.

- [ ] **Step 4: Commit Task 3**

```powershell
git add docs
git commit -m "docs: adopt finalized context names"
```

---

### Task 4: Preserve Remote History and Publish Main

**Files:**
- Git metadata only; no planned source-file edits.

**Interfaces:**
- Consumes: verified local commits from Tasks 1-3 and remote repository `https://github.com/Akirakato1/Context-Shifting-Card-Game.git`.
- Produces: local and remote branch `main` at the same verified commit with the prior remote `main` commit retained in ancestry.

- [ ] **Step 1: Commit the approved design and implementation plan before product work begins**

This documentation commit is performed before Task 1 during execution:

```powershell
git add docs/superpowers/specs/2026-11-21-assets-context-names-main-push-design.md docs/superpowers/plans/2026-11-21-assets-context-names-main-push.md
git commit -m "docs: plan asset library and context naming"
```

- [ ] **Step 2: Configure and inspect the target remote**

If `origin` is absent, add it; if it exists with another URL, stop rather than overwrite it. Fetch `origin/main`, inspect its tree and commit message, and verify whether it shares ancestry with local history.

```powershell
git remote add origin https://github.com/Akirakato1/Context-Shifting-Card-Game.git
git fetch origin main
git show --stat --oneline origin/main
git merge-base HEAD origin/main
```

- [ ] **Step 3: Rename the local branch and merge remote history**

Rename `master` to `main`. Merge `origin/main` normally; use `--allow-unrelated-histories` only if Step 2 proves the histories are unrelated. Stop on any non-trivial conflict and resolve it without discarding either side.

```powershell
git branch -M main
git merge --no-edit origin/main
# or, only for proven unrelated histories:
git merge --allow-unrelated-histories --no-edit origin/main
```

- [ ] **Step 4: Re-run verification on the merged `main` tree**

Run the complete Task 3 Step 3 matrix again. Expected: every suite passes and `git status --short` is clean.

- [ ] **Step 5: Push normally and verify the remote tip**

```powershell
git push -u origin main
git ls-remote --heads origin main
git rev-parse HEAD
```

Expected: push succeeds without `--force`; the remote `refs/heads/main` SHA equals local `HEAD`.

- [ ] **Step 6: Perform the native whole-change review**

Review the range from the pre-plan commit through final `HEAD` against the approved spec. Critical and Important findings must be fixed test-first and reverified before reporting completion. Minor findings may be documented for handoff. Confirm the final worktree is clean and no credentials, generated builds, or ignored scratch files were pushed.
