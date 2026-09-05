---
name: scholium-ui-verification
description: "Design, run, or diagnose Scholium macOS interaction verification and bounded human acceptance. Use for QA XCUITest, launch isolation, keyboard, focus, accessibility, multiwindow, document or conflict journeys, release smoke tests, assistive technologies, speech, or IME; exclude unit and CLI-only tests."
---

# Scholium UI Verification

Turn one user-visible claim into the smallest trustworthy automated journey or
human handoff. The researcher need not choose testing mechanics.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).

## Modes

- **Automated:** design, run, or diagnose one deterministic interaction journey
  and report only what its assertions establish.
- **Human acceptance:** automate safe setup and observable postconditions, then
  ask for the smallest irreducible human perception, speech, input-method, or
  assistive-technology judgment.

Load the [coverage derivation guide](references/ui-test-matrix.md) before adding
or broadening a journey. For genuine human judgment, also load the
[human-acceptance protocol](references/human-acceptance.md).

## Method

1. Reopen the affected workflow, current reachability, existing tests, QA
   identity, fixture ownership, and release requirements.
2. Choose the lowest layer that can invalidate the claim: owning tests, CLI,
   isolated application automation, release artifact, or human acceptance.
3. Reuse one representative journey per distinct interaction boundary. Add a
   new dimension only for a concrete independent failure mode.
4. Assert researcher-visible outcomes and the adjacent source, authorship,
   focus, cancellation, failure, conflict, accessibility, or recovery boundary.
5. Clean up test-owned state and report unverified conditions.

## Invariants

- Use only approved synthetic fixtures and isolated application state; never
  open or capture a private research vault.
- Keep at most one QA application process and follow current repository cleanup
  ownership.
- Prefer semantic controls, menus, shortcuts, roles, labels, and stable
  accessibility identifiers over coordinates or timing guesses.
- Wait for observable state with bounded failure. Do not synchronize by sleep.
- Exploratory computer control can supply observations, not deterministic proof
  or human acceptance.
- A release artifact is required only for release-specific packaging, signing,
  entitlement, persisted-access, or first-launch claims.

## Evidence

Report the build, fixture, claim, journey, assertions, captured test-owned
artifacts, human-only gate, and limitations. Run owning checks during iteration;
reserve broad UI and release suites for their explicit gates. Passing evidence
applies only to the exact build, inputs, states, and layer exercised.
