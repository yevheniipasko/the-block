# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Native SwiftUI iOS app for the OPENLANE "The Block" coding challenge: the **buyer side of a vehicle auction platform** (browse/search inventory, vehicle detail, place bids with visible updated state). Full brief in `Resources/README.md` (root `README.md` is the submission README, currently a stub); walkthrough expectations in `Resources/WALKTHROUGH.md`; README template for the final submission in `Resources/SUBMISSION.md`.

Constraints from the brief that should shape decisions:
- Prototype, ~3–4 h timebox. Judgment and polish over surface area. No auth, accounts, backend, seller/checkout/payments needed — frontend-only is fine.
- Repo must be clone-and-run from the README (README must contain run instructions + notable decisions/assumptions).
- Author must be able to explain every part of the code in the walkthrough — keep code readable, avoid clever abstractions.

Current state: fresh Xcode template (`ContentView`, `The_BlockApp`, empty test targets). The app is to be built from here.

## Workflow

Feature work happens in separate git worktrees under `.claude/worktrees/` — see `.claude/rules/worktrees.md`.

Architecture: MVVM + Repository + DataSource, Swinject container owned by a single top-level `AppModule` (no per-feature modules; nothing else touches the container), protocol-injected dependencies, pure Domain rules, Service layer only when the triggers in the rule apply — see `.claude/rules/architecture.md`.

Spec-driven: read `docs/SPEC.md` before any feature work; acceptance criteria IDs drive tests — see `.claude/rules/spec-driven.md`.

Independent features may run in parallel (subagents or a Workflow, ≤ 4 agents, one worktree each) once spec + data/domain are on `main` — see `.claude/rules/parallel-work.md`.

Log decisions, time, and AI usage in `docs/DECISIONS.md` as you go — see `.claude/rules/decisions-log.md`. Commit conventions in `.claude/rules/commits.md`.

UI flows are tested with Maestro (`maestro/flows/`), logic with Swift Testing; no XCUITest — see `.claude/rules/maestro-testing.md`.

## Build / run / test

Project: `The Block.xcodeproj`, single scheme `The Block`. Targets: `The Block`, `The BlockTests` (Swift Testing), `The BlockUITests`.

Prefer XcodeBuildMCP tools (`session_show_defaults` → `build_run_sim` / `test_sim`), then Xcode native MCP, then `xcodebuild` — see `.claude/rules/build-run.md`. CLI equivalents:

```sh
xcodebuild -project "The Block.xcodeproj" -scheme "The Block" \
  -destination 'platform=iOS Simulator,name=<sim name>' build

xcodebuild -project "The Block.xcodeproj" -scheme "The Block" \
  -destination 'platform=iOS Simulator,name=<sim name>' test

# single test (Swift Testing: Target/Suite/testFunction)
xcodebuild ... test -only-testing:"The BlockTests/The_BlockTests/example"
```

Module name is `The_Block` (`@testable import The_Block`).

## Project settings that matter

- Deployment target iOS 27.0, Swift 5 language mode.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (app target only; test targets are nonisolated by default) and `SWIFT_APPROACHABLE_CONCURRENCY = YES` (all targets): app types are implicitly `@MainActor` unless marked `nonisolated`. Mark pure model/decoding/helper types `nonisolated` when they must be used off the main actor.
- Targets use `PBXFileSystemSynchronizedRootGroup`: files added under `The Block/`, `The BlockTests/`, `The BlockUITests/` are picked up automatically — do not edit `project.pbxproj` to add sources/resources.

## Data (`Resources/data/vehicles.json`)

200 synthetic vehicles, generated deterministically by `Resources/scripts/generate_vehicles.mjs` (seeded PRNG; `node Resources/scripts/generate_vehicles.mjs` regenerates). `Resources/` is not part of any target — copy/bundle the JSON into `The Block/` to ship it in the app.

Shape: snake_case keys (decode with `.convertFromSnakeCase` or explicit `CodingKeys`). Gotchas:
- Nullable: `reserve_price` (60 null), `buy_now_price` (161 null), `current_bid` (112 null — no bids yet; `bid_count` then 0).
- `auction_start` is ISO-8601 **without timezone** (`2026-04-05T14:00:00`), range 2026-03-31…2026-04-06. Standard `.iso8601` decoding fails — use a custom formatter. Brief explicitly allows normalizing these relative to "now" for countdowns/live states.
- `damage_notes` is a string array, empty for 68 vehicles; `images` are `placehold.co` URLs (network-loaded placeholders).
- Enumerated string fields: `body_style` (SUV/coupe/hatchback/sedan/truck), `transmission` (automatic/manual/CVT/single-speed), `drivetrain` (4WD/AWD/FWD/RWD), `fuel_type` (gasoline/diesel/hybrid/electric), `title_status` (clean/rebuilt/salvage). Prices are whole CAD dollars; locations are Canadian provinces.
