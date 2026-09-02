# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Latest dated proof boundary.

## Current verification snapshot

**Environment:** 2026-09-02 complete integration snapshot with 2026-09-03
focused Agent Changes evidence, Xcode 27 beta toolchain
(`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`).

The 2026-09-02 Agent Changes integration established automated evidence for the
fixed MCP contract, exact machine-local Before/After payloads,
current-versus-earlier revision classification, byte-identical direct Update
Undo, and the Changed-since-settlement rail action. The 2026-09-03 presentation
change has focused evidence for its unified line model and semantic
removal/insertion palettes; the complete integration gate was not rerun for
that single-owner interface change.

Completed automated checks in this worktree:

- Web editor TypeScript checking and 208 tests in 38 files passed. Reader, editor,
  mathematics, and Mermaid bundles were rebuilt through the repository
  toolchain, and bundle reproducibility passed.
- Swift package tests passed: Core 341 tests in 35 suites, Core performance 3
  tests in 1 suite, Contracts 62 tests in 11 suites, Application 121 tests in
  16 suites, and the Application architecture measurement 1 test in 1 suite.
- The complete App suite passed after final localization cleanup: 544 tests in
  42 suites. Focused coverage also proved that exact Agent Change evidence
  survives store reopening, that sequential updates remain independent rather
  than cumulative, that a body update exposes the removed blank line and
  inserted text, that direct Undo restores each byte-identical Before source,
  and that a superseded or undone ending is an Earlier Revision.
- The public-symbol graph boundary, documentation authority and local-link
  validator, interface localization validator, bundled-Skill validator,
  resource and retired-surface residue guards, and `git diff --check` passed.
- The Release product build passed in 123.96 seconds.
- On 2026-09-03 the two exact-comparison presentation tests and the focused
  palette snapshot/contrast and semantic-role architecture tests passed.
  `build-qa-app.sh` syntax validation and `git diff --check` passed. A fresh
  disposable fixture opened one coherent workspace instead of the former
  settings-only Bootstrap failure.
- The affected macOS UI-test journey entered its test method and completed
  Settlement plus one MCP update. After synthetic Agent Changes activation,
  XCTest observed a disabled main window but neither rendered nor exposed the
  attached sheet, so the journey failed before comparison and Undo assertions.
  Exploratory Computer Use on the same isolated build rendered the red/green
  unified comparison and exposed change kind, exact line content, blank-line,
  line-number, and line-ending accessibility semantics. This observation is
  neither a deterministic UI pass nor human acceptance.

## Evidence boundary

No clean-account Codex or Claude Code smoke, packaged-artifact bridge smoke,
successful Agent Changes UI journey, VoiceOver, Full Keyboard Access,
Simplified Chinese IME, Finder, notarization, distribution, or other human
acceptance has run for this cutover. Passing local automated tests does not
establish those claims.
