---
name: swift-language
description: "Apply modern Swift language patterns and idioms for non-concurrency, non-SwiftUI code. Covers if/switch expressions, typed throws, result builders, property wrappers, opaque and existential types, guard patterns, Never, Regex builders, basic Codable shaping, collection APIs, FormatStyle, string interpolation, and current interoperability attributes. Use when writing or reviewing core Swift code involving generics, protocols, enums, closures, Codable basics, or modern language features; use swift-api-design-guidelines for API naming and swift-concurrency for isolation or Sendable work."
---

# Swift Language

Use current Swift features when they make the code clearer or safer without changing behavior accidentally. Treat the repository's manifest, build settings, deployment target, and selected Xcode toolchain as the source of truth.

## Inspect before changing code

1. Read the declaration, call sites, tests, serialized formats, and public API boundary.
2. Record the selected compiler, Swift language mode, package tools version, SDK, and deployment target separately. None implies all the others.
3. Preserve observable behavior, evaluation order, error identity, wire formats, and source compatibility unless the task authorizes a change.
4. Prefer the smallest language-level improvement. Do not turn a syntax cleanup into an architecture, concurrency, localization, or persistence redesign.

## Load only the needed reference

- Read [references/swift-patterns-extended.md](references/swift-patterns-extended.md) for advanced Codable examples, result builders, property wrappers, Regex builders, custom `FormatStyle`, collection helpers, typed-throws protocols, interpolation, and `Never`.
- Read [references/swift-attributes-interop.md](references/swift-attributes-interop.md) for C interoperability, module selectors, specialization, inlining, symbol visibility, and layout attributes. Gate these against the active compiler and SDK because several are toolchain-sensitive.
- Use `swift-api-design-guidelines` for names, argument labels, documentation comments, and mutating/nonmutating pairs.
- Use `swift-concurrency` for actor isolation, `Sendable`, tasks, synchronization, or strict-concurrency diagnostics.
- Use `scholium-swiftui-implementation` for SwiftUI scenes, views, state ownership, identity, lifecycle, navigation, presentation, layout, AppKit mounting, and Liquid Glass.

Do not load an extended reference for a routine `guard`, collection, or expression refactor.

## Core decisions

### Expressions and control flow

- Use `guard` for required preconditions and early exits when it leaves the success path flat.
- Use `if` or `switch` expressions when every branch produces one value and removing a mutable temporary improves clarity.
- Keep statements when branches perform multiple effects, require complex control flow, or an expression would conceal work.
- Preserve exhaustiveness and make newly added enum cases a deliberate compiler-visible decision.

### Errors and types

- Use typed throws when callers benefit from one closed, stable error domain. Keep untyped `throws` when errors are intentionally heterogeneous or cross a broad abstraction boundary.
- Use `some Protocol` when the implementation returns one hidden concrete type and callers need not choose it.
- Use `any Protocol` for runtime heterogeneity or storage of values with different conforming types, after checking existential limitations.
- Use generics when the caller's concrete type must be preserved or related across parameters and results.
- Treat `Never` as an uninhabited type useful for nonreturning functions and expression composition; do not assume it conforms to arbitrary protocols.

### Data shaping and text

- Prefer collection operations such as `map`, `filter`, `compactMap`, `reduce(into:)`, `first(where:)`, and `count(where:)` when they express intent and preserve ordering and cost expectations.
- Use Swift Regex or Regex Builder when typed captures and composition materially improve correctness; keep simple literals simple.
- Keep Codable changes bounded to the live external contract. Never rename keys, alter date strategies, or make decoding lossy without fixtures proving the intended compatibility.
- Use `FormatStyle` for presentation, but route locale-sensitive product policy to project localization guidance and locale-matrix tests.
- Use custom interpolation, builders, and property wrappers only when they remove repeated policy rather than hide important effects.

## Availability and beta features

- Verify compiler syntax with the selected Xcode toolchain and verify framework API availability against the deployment target.
- Do not infer feature availability from the current calendar, SDK name, or package tools version.
- For beta-only syntax or attributes, cite the exact active toolchain evidence in the task report. Scholium does not require a pre-macOS 26 path, but it still cannot use syntax or framework APIs absent from the selected compiler and SDK.

## Verify the result

1. Compile the affected targets with the repository's selected Xcode and Swift settings.
2. Run focused tests, including serialization fixtures and boundary cases when data formats are involved.
3. Compare representative before/after behavior and call sites.
4. Report any source break, wire-format change, availability guard, or adjacent concern left for another skill.

Use the reference files as examples and edge-case guidance, not as permission to deploy every modern feature at once.
