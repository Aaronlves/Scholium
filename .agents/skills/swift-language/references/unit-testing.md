# Swift unit and integration testing

Before implementation, establish the relevant setup, action, and observable
outcome from the owning contract or reported failure. For existing code, recover
that expectation independently of its implementation. Given/When/Then is useful
when it clarifies a scenario, not a mandatory name or syntax.

## Choose the evidence

- Assert results, persisted bytes, errors, recovery, or externally meaningful
  effects. Assert a collaborator interaction only when it is itself a contract.
  Source-text matching can enforce a named structural rule; it cannot prove that
  a save, refusal, or UI transition actually occurred. Keep that evidence named
  and reported as structural rather than duplicating it as a behavior test.
- Follow `AGENTS.md` for the evidence layer and execution scope. A public API
  with real persistence can prove a behavior without a full UI journey; it does
  not prove editor capture, interface wiring, or an external host connection.
- Prefer real dependencies when fast, deterministic, and isolated. Otherwise
  use a focused fake or stub at an existing boundary; mocks remain useful for
  hard-to-trigger failures or meaningful interactions. Check the substituted
  contract against the real implementation or protocol fixtures. State gaps;
  a fake agreeing with the test does not establish integration fidelity.

## Make failures informative

- Use `#require` for prerequisites that make later operations valid; use
  independent `#expect` assertions to retain useful failures. Check the specific
  error or exposed failure meaning, not merely that any error occurred.
- Parameterize cases of the same behavior with distinguishable inputs and
  boundary outcomes. Avoid accidental Cartesian products or merging distinct
  workflows merely to reduce test count.
- Prefer per-test isolated state. Swift Testing parallelism includes parameterized
  cases; `.serialized` controls its annotated scope, not unrelated suites or
  processes sharing files, defaults, or other global resources.

## Control asynchronous work

Control time, randomness, services, and event delivery at existing boundaries.
Use a controllable clock for time logic and explicit events/barriers for ordering;
sleep is a deadline mechanism, not evidence that another operation completed.
Subscribe before triggering an event and account for initial state and whether
publication occurs before or after mutation. In Swift Testing, `confirmation`
checks events during its closure; it does not itself wait for a later callback.
Await the operation's lifetime or an appropriate event bridge within that scope.

Design barriers to fail under the tested regression rather than hang: a rejected
second request must not join the first request's release barrier. Give waits a
bounded failure or completion path. Clean up tasks, subscriptions, continuations,
and disposable state after failure and cancellation as well as success.

## Verify the test's value

When practical, show the regression test fails before a fix, or use one bounded
fault injection to check a consequential assertion. Preserve unrelated work,
restore changed source exactly, then verify the restored implementation. Do not
make mutation testing a new gate for every edit. Coverage can reveal unexecuted
branches, especially failures; it cannot prove assertions are correct. Inspect
meaningful gaps rather than imposing an arbitrary percentage or adding filler.
Automate mechanically decidable constraints; lint cannot establish business intent.

Use current [Swift Testing](https://developer.apple.com/documentation/testing)
and [XCTest](https://developer.apple.com/documentation/xctest) evidence for APIs.
Keep existing effective tests; framework novelty alone warrants no conversion.
For an authorized migration, convert one independent suite, remove superseded
tests, and allow XCTest and Swift Testing to coexist without mixing their APIs
within a test. Retain UI and performance mechanisms for their distinct claims.

Report the behavior proven, substituted boundaries, executed checks, and limits.
UI/assistive-technology proof belongs to Xcode workflow; measurement methodology
belongs to the performance owner.

## Sources and applicability

Swift Testing details were checked against Apple's
[expectations](https://developer.apple.com/documentation/testing/expectations),
[parameterization](https://developer.apple.com/documentation/testing/parameterizedtesting),
[parallelization](https://developer.apple.com/documentation/testing/parallelization),
and the [confirmation implementation](https://github.com/swiftlang/swift-testing/blob/9573bcec302e1290bfc32f4d18c8a32690883713/Sources/Testing/Issues/Confirmation.swift).
Antoine van der Lee's [Testing references](https://github.com/AvdLee/Swift-Testing-Agent-Skill/tree/798e9b1a2bcac164d4f0c781908199e754f0bab6/swift-testing-expert/references)
informed the focused framework guidance (reviewed 2026-09-23); they do not impose
framework migration or architectural defaults. Dependency-fidelity and coverage
tradeoffs also draw on Google's [test-double guidance](https://testing.googleblog.com/2024/02/increase-test-fidelity-by-avoiding-mocks.html)
and [coverage guidance](https://testing.googleblog.com/2020/08/code-coverage-best-practices.html).
