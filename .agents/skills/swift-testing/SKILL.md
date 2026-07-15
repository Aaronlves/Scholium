---
name: swift-testing
description: "Write and migrate Swift tests with the Swift Testing framework, including @Test, @Suite, #expect, #require, confirmation, traits, known issues, attachments, exit tests, cancellation, issue recording, async patterns, parameterization, fixtures, and test doubles. Use when adding or reviewing Swift unit and integration tests or migrating XCTest assertions; keep XCTest/XCUITest for UI automation and XCTest performance measurement, and use dedicated tooling for visual snapshot tests."
---

# Swift Testing

Use Swift Testing for new Swift unit and integration tests that call code directly. Preserve XCTest/XCUITest for macOS UI automation and XCTest performance tests. A test target may contain both frameworks during migration, but do not mix their APIs in the same test.

Primary Apple guidance: [Swift Testing](https://developer.apple.com/documentation/testing), [Adding tests to an Xcode project](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project), and [XCTest](https://developer.apple.com/documentation/xctest).

## Inspect before writing tests

1. Identify the behavior, boundary, regression, and failure mode the test must prove.
2. Inspect the production API, existing test target, selected Xcode/Swift toolchain, deployment target, test-plan settings, fixtures, and framework already used by neighboring tests.
3. Choose the lowest layer that proves the behavior deterministically.
4. Keep test-only architecture proportional. Prefer small value fixtures and injected collaborators over global mutable test state.

## Choose the test mechanism

| Need | Default mechanism |
|---|---|
| Pure logic, parsing, repository contract, async service, or integration called directly | Swift Testing |
| Callback or async event count | Swift Testing `confirmation` or structured concurrency |
| End-to-end macOS interaction, focus, keyboard, menus, accessibility | XCTest with XCUITest; use `scholium-ui-automation` for Scholium workflows |
| Repeatable performance metrics and baselines | XCTest performance APIs; use `scholium-performance-audit` for benchmark protocol |
| Pixel or rendered visual regression | Approved snapshot tooling plus explicit visual QA |
| Objective-C or C-based test code | XCTest unless the live project proves a better supported boundary |

Do not describe every new test as Swift Testing. The rule applies to new unit and integration tests, not UI, performance, or snapshot tests.

## Load only the needed reference

- Read [references/testing-patterns.md](references/testing-patterns.md) for suites, assertions, parameterization, fixtures, confirmation, known issues, tags, migration, doubles, async tests, UI page objects, performance, snapshots, and organization.
- Read [references/testing-advanced.md](references/testing-advanced.md) for warning-severity issues, programmatic cancellation, exit-test captures, image attachments, and version gates.
- Read [references/testing-new-features.md](references/testing-new-features.md) only when the selected toolchain supports the newer identifiers, range confirmation, scoping traits, thrown-error results, or condition traits.

Do not copy version-sensitive syntax without compiling it under the selected Xcode.

## Review discipline

- Report only issues tied to behavior, isolation, flakiness, supported API, or test maintenance; do not rewrite passing tests for syntax novelty.
- For asynchronous cancellation, use a controllable signal, `confirmation`, or an injected clock; never use sleeping as synchronization.
- Keep diagnostics and attachments free of private research text.

## Core Swift Testing patterns

```swift
import Testing

@Suite("Frontmatter parsing")
struct FrontmatterParsingTests {
    @Test("Preserves a body without frontmatter")
    func preservesPlainBody() throws {
        let source = "# Note\n"
        let document = try NoteDocument(source: source)
        #expect(document.body == source)
    }
}
```

- Use `#expect` for independent expectations whose failure should not prevent later checks.
- Use `#require` when later code requires the value or condition, including optional unwrapping.
- Use `Issue.record` for an unconditional test issue rather than importing `XCTFail` into a Swift Testing test.
- Use parameterized tests for the same behavior across a fixture matrix.
- Use `confirmation` for bounded event counts. Avoid sleeps and timing guesses.
- Mark an understood temporary failure with `withKnownIssue` and a removal condition; do not conceal unrelated failures.
- Put availability on the individual `@Test` function when only that test requires the API. Avoid making an entire containing type disappear unintentionally.

## Fixtures and isolation

- Construct fresh mutable fixtures per test or per suite instance. Never use a shared mutable singleton to replace `setUp`/`tearDown`.
- Make filesystem tests use private disposable copies, canonical fixture generators, and explicit cleanup. Never point a destructive test at a research vault.
- Keep time, randomness, locale, file paths, and external services controlled or injected.
- Let tests run in parallel unless they truly share a serialized resource; make that constraint visible with the narrowest supported trait or target boundary.
- Record diagnostics without including private research text.

## XCTest migration

- Convert `XCTestCase` methods to free `@Test` functions or methods in a Swift Testing suite; do not retain inheritance in migrated unit tests.
- Translate assertion intent, not spelling: `XCTAssert*` usually becomes `#expect`, while `XCTUnwrap` and fatal prerequisites become `#require`.
- XCTest and Swift Testing may coexist in the same target during staged migration. Keep framework-specific APIs within their own tests and organize files clearly.
- Preserve existing XCTest UI and performance tests. Migrate stable unit tests incrementally instead of rewriting the entire suite at once.
- If the active SwiftPM/Xcode toolchain exposes an interoperability mode, set it intentionally and document the migration choice; verify the exact current mode names in the selected toolchain.

## Advanced and beta-era APIs

Exit-test macros, captured exit-test values, test cancellation, warning severity, attachments, and newly proposed traits have toolchain and runtime constraints. Use the advanced references as a starting point, then confirm exact spelling and availability by compiling a focused test. Do not retarget Scholium or introduce beta-only syntax merely to modernize a test.

## Verify the test change

1. Run the focused test repeatedly and once with the surrounding suite.
2. Run it under the repository's selected Xcode and strict Swift settings.
3. Confirm it fails for the intended regression when practical, then passes with the fix.
4. Check parallel execution, fixture cleanup, and privacy of attachments/logs.
5. Report any UI, performance, snapshot, availability, or migration work intentionally kept outside this skill.

Prefer a small test that proves one contract over a broad test whose result is hard to diagnose.
