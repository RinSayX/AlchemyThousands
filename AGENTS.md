# Alchemy Thousands - Codex Project Instructions

## Project Context

Build a fully offline 2D single-player alchemy game using Godot 4.5 stable (see .godot-version) and GDScript.
The first run should target 4–8 hours; later runs should target 2–3 hours.
The core is probability-based alchemy, resource economy, gear builds, and rebirth.

## Read First

Before changing game logic, inspect:
- docs/GAME_DESIGN.md
- docs/TECHNICAL_DESIGN.md
- docs/DEVELOPMENT_PLAN.md
- docs/BALANCE.md (if present)

## Architecture Rules

- Keep gameplay logic separate from Control/UI scenes.
- Use data-driven content in data/ with stable string IDs.
- UI never directly mutates inventory, money, rank, or quest state.
- Validate transactions before committing state changes.
- No negative currency or item quantities.
- Do not introduce external dependencies/addons without approval.
- Keep the implementation small and readable; avoid premature abstractions.

## Randomness

- Use dedicated RNG streams for alchemy, exploration, and world generation.
- Preview calculations must never advance RNG state.
- Never secretly manipulate displayed probabilities.
- Same seed + same game state + same action sequence must replay identically
  for the locked engine version.
- Do not use UI animation randomness to decide gameplay outcomes.

## Saving and Rebirth

- Separate meta-progress from current-run progress logically.
- Do not clear meta-progress during normal rebirth.
- Persist RNG states and schema versions.
- Failed saves must not destroy the previous valid save.

## Workflow

For each phase:
1. Inspect existing code and the specification.
2. Summarize the smallest safe implementation plan.
3. Implement only the requested phase.
4. Add/update focused tests.
5. Run Godot validation and tests when the executable is available.
6. Fix observed failures.
7. Report files changed, commands run, results, and limitations.

Do not claim tests passed without running them.
Do not implement later phases unless explicitly requested.
Use placeholder art and focus on working gameplay first.
Use English IDs/code identifiers and Chinese player-facing text.
