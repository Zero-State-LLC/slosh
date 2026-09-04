# Agent contract — Slosh

You are working in **Slosh** (`Zero-State-LLC/slosh`).
This file is the canonical contract for Cursor, Claude, Codex, Grok, and OpenClaw.
Harness adapters (`CLAUDE.md`) only point here.

## Intent

Read the active intent for this change (`intent/`) before editing.
Next stage is specify — do not skip to code.

If the change is non-trivial and no intent exists, draft from
[`intent/_TEMPLATE.md`](intent/_TEMPLATE.md) and wait for a human to accept it.
Do not invent product work. Open product questions stay in existing issues.

## Commands

Named in `README.md` / `CONTRIBUTING.md`. Do not invent others.

| Task | Command |
|---|---|
| Engine checks | `cd OceanCore && swift run oceancheck` |
| Hydro checks | `cd OceanCore && swift run hydrocheck` |
| Provider checks (offline) | `cd OceanCore && swift run providercheck` |
| Engine build | `cd OceanCore && swift build` |
| Watch simulator build | see `CONTRIBUTING.md` |

## Invariants

- `OceanCore` imports no UI framework (not SwiftUI, SpriteKit, CoreMotion, or WatchKit).
- Do not create product Places or geographic discovery. Research NOAA/USGS adapters never appear in normal UI (`docs/REAL_WATER.md`).
- The app has never run on a physical watch. Do not claim tilt, frame rate, battery, or haptics as observed (`docs/ROADMAP.md` Phase 0).
- Do not invent product behavior the existing docs do not name.
- Do not put secrets, tokens, or live credentials in the tree.

## Docs

This repo has no `graft/`. Start at `README.md`, then `docs/ARCHITECTURE.md`,
`docs/DECISIONS.md`, and `CONTRIBUTING.md`. Shader work: read the SpriteKit
contract in `docs/ARCHITECTURE.md` first.

Environment notes (simulator motion, white-screen shader fallback) stay in
`README.md` and `CONTRIBUTING.md`. Do not copy them here.

## Escalation

If CI, tests, or validators look wrong — missing coverage, silent skips,
green-but-inert checks, or a suite that contradicts the docs:

1. Open a defect issue (use the bug report template).
2. Do **not** patch tests, fixtures, or CI to force green.
3. Do **not** weaken an assertion to match a broken implementation.

A red honest check is better than a green lie.

## Team context

Org and partner status is not this repo. Load `Zero-State-LLC/agent-context`:

1. `HANDOFF.md`
2. `STATUS.md`
3. `DECISIONS.md` only if a prior choice affects this task

Clone: `gh repo clone Zero-State-LLC/agent-context ~/agent-context`.
Pull `--ff-only` before trusting a local copy.
Canonical pack: `templates/` in that repo.

## Skills

Name only skills that already exist. Do not invent skills or bots.

## Size

Keep this file short (about 80 lines; hard ceiling 12 KB).
