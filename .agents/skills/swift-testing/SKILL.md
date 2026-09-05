---
name: swift-testing
description: "Write or convert Swift unit and integration tests with Swift Testing. Use for @Test, @Suite, assertions, confirmation, traits, issues, async tests, parameterization, fixtures, doubles, attachments, cancellation, or exit tests; retain XCTest and XCUITest for UI and performance tests."
---

# Swift Testing

Choose the lowest deterministic test that proves one behavior. Framework
modernization is not itself a reason to rewrite a passing suite.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Use current [Swift Testing](https://developer.apple.com/documentation/testing)
and [XCTest](https://developer.apple.com/documentation/xctest) documentation,
the selected toolchain, and neighboring tests as detailed authority.

## Method

1. Name the behavior, boundary, regression, and failure mode to prove.
2. Inspect the production API, existing test target and framework, toolchain,
   test plan, fixture ownership, and adjacent coverage.
3. Use Swift Testing for direct unit or integration behavior when supported;
   retain the established UI, performance, and approved visual-regression tools
   for those distinct evidence classes.
4. Control time, randomness, paths, locale, services, event delivery, and
   mutable fixtures without sleeps or shared private state.
5. Check that the test detects the intended regression when practical, then
   run the owning suite. Repeat only to investigate nondeterminism or a failure.

## Invariants

- Keep prerequisites distinct from independent expectations so failures remain
  diagnostic.
- Prefer small value fixtures and injected collaborators over test-only
  architecture or global mutable setup.
- Parallel tests own isolated disposable state and deterministic cleanup.
- Preserve private research content outside fixtures, logs, and attachments.
- Confirm toolchain-sensitive assertions, traits, cancellation, attachments,
  and process behavior by compiling and running under the selected environment.
- Different frameworks may coexist only for distinct current evidence classes.
  Convert a bounded test target completely and remove superseded duplicate
  tests; do not mix framework APIs inside one test or claim one framework covers
  every evidence layer.

Report the exact behavior proven, focused and surrounding suites run,
availability limits, cleanup/privacy checks, and any UI, performance, visual,
or human-acceptance work intentionally left to another capability.
