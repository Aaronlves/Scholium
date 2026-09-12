---
name: swift-language
description: "Implement, review, or test Swift language and API behavior; native interface work and Xcode build/QA have separate owners."
---

# Swift Language

Make the smallest Swift change that satisfies the request and preserves
unaffected behavior. A language cleanup does not authorize adjacent refactoring.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Inspect the declaration, callers, tests, serialization or ABI boundary, selected
toolchain, and relevant official Swift/SDK evidence before changing behavior.

## Load only the affected guidance

- API names, argument labels, or public documentation: [API naming](references/api-naming.md).
- Isolation, Sendable, tasks, cancellation, callbacks, or shared mutable state:
  [concurrency](references/concurrency.md).
- Writing or converting direct unit/integration tests:
  [unit testing](references/unit-testing.md).

A synchronous helper correction needs none of these references unless it changes
one of their contracts. Do not load all three simply because the file is Swift.

## Implementation and proof

For a compiler error, reduce it to the failing declaration and real caller;
distinguish a type mismatch from an isolation, availability, or lifetime problem.
A compiling cast, default value, or unchecked annotation is not a correction if
it discards an error or weakens the existing contract. For asynchronous code,
load concurrency guidance before choosing the owner of values crossing `await`.

Choose types and abstractions from actual callers and runtime heterogeneity.
Preserve evaluation order, errors, representation, collection ordering, and
external contracts unless explicitly replaced. Prefer the surrounding idiom;
use builders, wrappers, existentials, or generics only when they clarify owned
behavior. Verify toolchain-sensitive features against the selected environment.

Run owning checks under `AGENTS.md`. UI interaction and performance require
their own evidence; a direct unit test cannot establish either. Report the
behavior changed, focused proof, and any intentional source or wire-format break.
