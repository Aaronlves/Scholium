---
name: scholium-ui-automation
description: Design, implement, run, or diagnose automated macOS interaction tests for Scholium. Use for the isolated QA-app XCUITest harness, release-app smoke tests, keyboard and focus workflows, accessibility identifiers, launch-state isolation, independent windows, Search, research sessions, attention queues, proposal or conflict UI, CSS and export journeys, canvas and Zotero failures, clean-account checks, or regression coverage crossing SwiftUI, AppKit, and active WebKit surfaces. Do not use for ScholiumCore-only unit tests or ordinary visual design review.
---

# Scholium UI Automation

Automate user-visible behavior without turning implementation details into the product contract. Preserve the vault trust boundary and use only synthetic disposable fixtures.

## Locate the checkout

Do not infer the checkout from this installed skill. Bind one repository root containing `AGENTS.md`, `Package.swift`, `ScholiumCore/`, and `Scholium/`. If no unique root is in scope, stop and request the checkout. Resolve paths and run commands from the repository root.

Pair this skill with `scholium-development` for repository changes and final verification, `scholium-apple-design` for interaction semantics, accessibility, and the canonical UI state/action contract, `scholium-markdown-editor-integration` for reader/editor journeys, and `scholium-trust-boundary-audit` for proposals, conflicts, sandbox access, bookmarks, or any workflow that could expose or mutate research material.

## Choose the smallest valid test layer

1. If the behavior does not require a running app, route out of this skill to `scholium-development` and the Swift Testing skill for document, repository, relationship, or service coverage.
2. If the behavior is CLI-only, route out of this skill to `scholium-development` for black-box `scholium` tests with isolated `SCHOLIUM_HOME` state.
3. Use Scholium's isolated QA app and XCUITest harness for real menus, windows, keyboard focus, SwiftUI/AppKit bridges, active CodeMirror and Read-mode WKWebViews, and deterministic application-state journeys. The harness is `ScholiumUITests.xcodeproj` with tests in `UITests/ScholiumUITests.swift`.
4. Use the signed release app only when the requirement is specifically release packaging, entitlements, signing, persisted sandbox access, first-launch behavior, or a release-build performance/smoke result. Do not substitute the Debug QA app for a release artifact, or package a release app for routine UI iteration.
5. `swift test` alone does not run XCUITest. Invoke the real harness through the repository scripts below.
6. Use Computer Use only for exploratory app validation when no deterministic harness exists or for a complementary visual/accessibility-tree observation. It does not replace XCUITest, deterministic assertions, or actual assistive-technology testing. Convert stable high-value flows into automation where practical.

Read [references/ui-test-matrix.md](references/ui-test-matrix.md) before choosing coverage.

## Isolate state

- Use only synthetic fixtures from `/Users/jacuqeas73/Desktop/TestVaults` or a generated synthetic equivalent. Never open a private research vault for automated or exploratory UI validation.
- Run `./Tools/Scripts/build-qa-app.sh` to copy `SCHOLIUM_TEST_VAULTS`—defaulting to `~/Desktop/TestVaults`—to `/tmp/scholium-workbench-qa` and build `/tmp/Scholium-QA.app` with bundle identifier `com.kbmanager.qa`.
- Run `./Tools/Scripts/run-ui-tests.sh` to stage only that QA bundle temporarily at `~/Applications/Scholium-Codex-QA-Do-Not-Use.app`. The script verifies the identifier before replacement and unregisters, terminates, and removes the test-owned copy on exit.
- Keep exactly one QA run and at most one QA process active. Never launch a second suite or exploratory QA copy while one is running. The runner lock must reject concurrent runs, and every completed or failed journey must terminate and remove its test-owned app before another begins.
- Keep the UI-test launch environment isolated at `SCHOLIUM_HOME=/tmp/scholium-workbench-home` and `SCHOLIUM_UI_TEST_WORKSPACE_ROOT=/tmp/scholium-workbench-qa`, or use equally explicit test-owned paths when extending the harness.
- Give any supporting CLI setup in a mixed GUI journey its own test-owned `SCHOLIUM_HOME`; route CLI-only coverage out as specified above.
- Remove only QA-bundle preferences, Application Support, derived data, and fixture copies whose ownership is established by the current run. Never broaden cleanup to a production Scholium bundle identifier or state root.
- Record the app build, fixture, launch arguments, macOS version, and window size.
- Do not delete real bookmarks, preferences, versions, or proposals during cleanup.
- Before launch, ensure the test app cannot restore a private vault or private window state. Never record private note bodies, titles, paths, citations, or accessibility values in screenshots, videos, logs, or hierarchy dumps.

## Build stable automation contracts

- Add accessibility identifiers only to controls or regions that need stable automation lookup. Keep visible and VoiceOver labels meaningful; identifiers do not replace semantics.
- Prefer menu commands, keyboard shortcuts, roles, and labelled controls over coordinate clicks.
- Wait for observable state, not fixed sleeps. Use bounded timeouts with failure artifacts.
- Assert outcomes at the user boundary and use the exact state meanings and lifecycle labels in Section 10 of `Docs/DESIGN_HANDBOOK.md` in the bound checkout.
- Keep helpers page- or workflow-oriented, not coupled to the SwiftUI view hierarchy.
- Capture screenshots and relevant logs on failure only from synthetic fixtures and test-owned state.

## Cover failure states

Exercise loading, empty, malformed, stale, conflict, unavailable Zotero, broken link, save failure, and proposal validation states. Verify that editors stay open and user work remains recoverable.

Give current product surfaces explicit coverage priorities:

- Search Workspace scope, query fields, saved searches, result provenance, keyboard selection, and opening an exact source location;
- independent Command-N windows with separate tabs, navigation, modes, scroll positions, inspectors, and canvases while shared repository/index commits converge safely;
- research-session permission and durability gates plus derived Attention Queues that never imply epistemic settlement;
- Read and Live Preview rendering, CSS safe mode, self-contained HTML/PDF export, and cancellation or render/write failures;
- named-canvas persistence, canvas-only annotations, keyboard alternatives, and vault non-mutation;
- Zotero unavailable, disabled-local-API, missing-item, and failed Open-in-Zotero states without blocking unrelated research work. Verify that Topics and Works expose only directly linked Analyses and that Scholium never enumerates attachments or unrelated library items.

## Verify

- Run the narrow workflow during iteration.
- Run `./Tools/Scripts/verify.sh` for code changes.
- Build the isolated QA app with `./Tools/Scripts/build-qa-app.sh`, then run the macOS harness with `./Tools/Scripts/run-ui-tests.sh`.
- Use `./Tools/Scripts/package-app.sh` only when a signed/release-app behavior is itself under test. Record which artifact was exercised.
- Report which checks were deterministic, which were exploratory, and which remained manual.
- Treat the current two XCUITests—document modes/inspector/Search reachability and Command-N independent-window creation—as the automated baseline, not proof that the broader matrix is covered.
- If a chronological visual-QA log exists in the checkout, use it as build-specific evidence only; do not require it or treat it as the interaction contract.
- Do not call a smoke test an end-to-end suite or claim clean-account coverage unless the account/state was actually clean.
