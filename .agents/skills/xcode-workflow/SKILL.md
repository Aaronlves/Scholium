---
name: xcode-workflow
description: "Build, test, or diagnose Apple-platform projects and isolated Scholium QA. Use for Xcode/toolchain builds, SDK docs, keyboard/focus/accessibility journeys, feedback builds, human acceptance, or release-artifact checks; route unit-test design to Swift."
---

# Xcode Workflow

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Use the live repository build and QA rules. Identify the actual workspace,
project, or `Package.swift`; do not invent a project wrapper.

## Select the requested work

- **Build and diagnose:** use the toolchain and execution workflow below.
- **Automated:** verify one app interaction through
  [interaction verification](references/interaction-verification.md).
- **Human acceptance:** use that same reference to stage the irreducible human
  judgment, preserving its distinction from automated evidence.

Read-only verification planning does not require a build or toolchain preflight.
Unit-only execution does not require app launch or the interaction references.

## Choose the execution surface

- Use callable Xcode MCP for active project, scheme, destination, issue, build,
  test-list, or SDK-documentation state.
- Use explicit toolchain shell commands for SwiftPM, repository scripts, and
  reproducible builds when active Xcode state is not required.
- Use isolated Debug/QA and authorized Computer Use for runtime visual evidence.
- Use the repository release workflow only for explicitly requested packaging
  or release-specific validation. Debug success does not prove release behavior.

## Bind the intended toolchain and project

Run `scripts/preflight.sh` from this skill directory with the selected Xcode
app or developer directory. Without an explicit selection, inspect the active
`xcode-select` result; do not assume a beta installation. Carry the resolved
`DEVELOPER_DIR` on shell build/test commands. Do not change the machine-wide
selection or install/repair tooling without authorization.

If the required toolchain is unavailable, report the affected operation and
continue independent diagnosis. Never silently substitute another installation.
Keep SwiftPM scratch and Xcode DerivedData under the repository's ignored `.build/`.

For MCP, callable tools are decisive; configuration alone is not a connection.
Probe with the available window-list tool, then bind the intended project,
scheme, and destination from live results. Never invent tool names, tab IDs,
or stale identifiers. Resolve ambiguity from the request and checkout first;
ask only if the intended project remains unclear. Inspect the test list before
selecting tests. If MCP is unavailable, identify that limit and use shell only
when it can establish the requested claim; do not call that an MCP build.

## Execute and verify

Confirm configuration and SDK, then use the narrowest build or test covering
the claim. Retain full logs/result bundles and inspect relevant diagnostics.
Separate product failure from runner, permission, destination, fixture, or
toolchain failure. Follow `AGENTS.md` for verification scope and cadence.

For a reported defect, reproduce once and inspect retained evidence before
rerunning an unchanged failure. Add regression coverage when it can detect the
failure; do not require a new test for every visual adjustment. Use current SDK
documentation for API questions, with the selected environment stated.

Read [feedback and QA](references/feedback-and-qa.md) when the user wants to try
a development build or iterate on observed bugs. It owns session setup,
reproduction, retesting, and cleanup; do not duplicate that loop here.

For authorized release work, verify the delivered artifact under the live
release protocol, including applicable resources, signatures, entitlements,
and installation behavior. A change to signed contents invalidates prior
release proof; rebuild and repeat the required workflow.

Report the outcome, selected toolchain and surface, exact checks, useful
artifacts, and remaining limits. Tool invocation alone establishes no pass.
