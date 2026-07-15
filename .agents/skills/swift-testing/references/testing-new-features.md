# Newer Swift Testing patterns

Verify the installed Swift and Swift Testing version before using these APIs. Keep existing project conventions unless a change materially improves the suite.

## Raw test identifiers

Swift 6.2 permits human-readable function identifiers in backticks:

```swift
@Test
func `Saving a stale revision reports a conflict`() async throws {
    // ...
}
```

Suggest this style when it removes a duplicated display name and the suite welcomes sentence-like identifiers. Do not rename an established suite merely for novelty.

## Range-based confirmation

Use a range when an asynchronous event has a legitimate bounded count:

```swift
await confirmation(expectedCount: 1...3) { confirm in
    // Exercise work that may coalesce notifications.
    confirm()
}
```

Use a lower-bounded range such as `2...` for “at least.” Do not use an upper-only range because whether zero is allowed is ambiguous. Prefer an exact count when the contract is exact.

## Test-scoping traits

Use `TestScoping` for opt-in, concurrency-safe setup around individual tests or suites, especially when configuration is carried through `@TaskLocal`. Prefer ordinary suite initialization for simple value fixtures. Never use a scope to hide shared mutable global state.

A scope must invoke the supplied body exactly once and clean up on both success and failure. Confirm its current protocol signature against the installed toolchain before writing it because Swift Testing evolves independently of most application APIs.

## Returned thrown errors

Current `#expect(throws:)` and `#require(throws:)` forms can return the checked error, allowing validation to remain separate from the expectation:

```swift
let error = #expect(throws: VaultError.self) {
    try repository.writeStaleRevision()
}
#expect(error.isConflict)
```

Use `#require` when later assertions cannot proceed without the expected error. Prefer an exact error value when the type is `Equatable`; inspect properties only when that expresses the behavior more clearly.

## Condition traits

Use condition traits on `@Test` or `@Suite` for test availability and environment requirements. Evaluate a condition trait programmatically only when production-independent test support code needs the same decision. Do not move product feature flags into the testing framework.
