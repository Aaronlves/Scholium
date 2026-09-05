# Swift unit and integration testing

Name the behavior and failure the test must detect. Inspect the production API,
existing framework, toolchain, fixture ownership, and adjacent coverage first.
Use current [Swift Testing](https://developer.apple.com/documentation/testing)
and [XCTest](https://developer.apple.com/documentation/xctest) evidence for APIs.

- Reuse effective tests. Add regression coverage when it can detect the reported
  failure; reversible low-impact changes do not require implementation-mirroring tests.
- Use Swift Testing for supported direct behavior; retain established UI and
  performance mechanisms for those distinct claims. Framework novelty is not
  a reason to rewrite a passing suite.
- When conversion is requested, migrate an independent test suite at a time.
  XCTest and Swift Testing may coexist in a target during this work; remove
  superseded duplicate tests and do not mix framework APIs within one test.
- Control time, randomness, locale, paths, services, and event delivery without
  sleep-based synchronization. Give parallel tests isolated disposable state
  and cleanup. Keep private data out of fixtures, logs, and attachments.
- Separate prerequisites from independent expectations. Prefer small fixtures
  and injected collaborators over test-only architecture or global state.

Run the owning suite and, when practical, demonstrate the intended regression
fails before the correction. Report the behavior proven and relevant limits.
Route app interaction/assistive-technology verification to Xcode workflow;
measurement methodology remains with the performance owner.
