---
name: swift-language
description: "Apply modern Swift idioms to non-concurrency, non-SwiftUI code. Use for generics, protocols, enums, closures, Codable, typed throws, builders, wrappers, existential or opaque types, Regex, formatting, collections, or interoperability; route naming and isolation to their dedicated capabilities."
---

# Swift Language

Use the smallest language-level change that makes current code clearer or
safer without silently changing behavior.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
The repository manifest, selected toolchain, SDK, deployment target, source,
tests, and current official Swift documentation are live authority. Do not use
this skill as a copied Swift handbook.

## Method

1. Read the declaration, representative callers, tests, serialization or ABI
   boundary, and actual compiler settings.
2. State the behavior and external contracts that remain in scope.
3. Choose the simplest expression, control flow, type abstraction, protocol
   boundary, or data transformation that communicates that behavior.
4. Verify toolchain and platform availability from primary sources and by
   compiling the focused change.
5. Run owning tests and report any intentional source, wire-format, ordering,
   error, or availability change.

## Boundaries

- Route call-site naming and documentation to the API-design capability.
- Route actor isolation, task lifetime, synchronization, and `Sendable` to the
  concurrency capability.
- Route view, scene, state, navigation, and native presentation ownership to
  the interface capability.
- Do not turn syntax cleanup into architecture, persistence, localization, or
  an obsolete-path preservation task.

## Invariants

- Prefer surrounding code idiom and obvious control flow over novelty.
- Preserve evaluation order, error identity, data representation, collection
  ordering, and external contracts unless the task changes them explicitly.
- Choose generics, opaque results, or existentials from caller needs and runtime
  heterogeneity, not fashion.
- Use builders, wrappers, interpolation, regexes, and custom formatting only
  when they remove repeated policy without hiding consequential effects.
- Treat attributes, interoperability, and beta or newer syntax as
  toolchain-sensitive; confirm exact live support instead of recording versions here.

Use official Swift references and focused compiler evidence for detailed syntax.
Do not modernize adjacent code merely because it is reachable.
