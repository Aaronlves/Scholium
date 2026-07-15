---
name: swift-api-design-guidelines
description: "Apply Swift API Design Guidelines to name, label, and document Swift APIs. Covers argument label rules (prepositional phrase rule, grammatical phrase rule, first-label omission), mutating/nonmutating pair naming (-ed/-ing participle pattern, form- prefix, sort/sorted, formUnion/union), side-effect naming (noun for pure, verb for mutating), documentation comment structure (summary by declaration kind, O(1) complexity rule), clarity at call site, role-based naming, protocol naming (-able/-ible/-ing), default arguments over method families, casing conventions, and terminology. Use when designing new Swift APIs, reviewing naming and argument labels, writing documentation comments, or refactoring for call site clarity."
---

# Swift API Design Guidelines

Design APIs for clarity at the call site. Preserve behavior and source compatibility unless the task explicitly authorizes a breaking change.

## Inspect before renaming

1. Read the declaration, representative call sites, protocol requirements, public documentation, and tests.
2. Identify the receiver, semantic role of every argument, side effects, return value, and whether a mutating/nonmutating pair exists.
3. Check the current Swift compiler and project conventions. Do not modernize names merely because a newer spelling exists.
4. Separate API naming from language, concurrency, lint, or architecture work. Use `swift-language` for type-system syntax and `swift-concurrency` for isolation or `Sendable`; inspect live lint configuration or official tool documentation for lint rules.

## Load only the needed reference

- Read [references/argument-labels-and-parameters.md](references/argument-labels-and-parameters.md) for first-label omission, prepositional and grammatical rules, conversions, parameter roles, and default arguments.
- Read [references/side-effects-and-mutating-pairs.md](references/side-effects-and-mutating-pairs.md) for verb/noun side-effect naming, `-ed` versus `-ing`, `form` pairs, and `make` factories.
- Read [references/naming-and-clarity.md](references/naming-and-clarity.md) for call-site grammar, role-based naming, weak type information, protocols, and terminology.
- Read [references/conventions-and-special-rules.md](references/conventions-and-special-rules.md) for documentation comments, complexity, casing, overloads, tuples, closures, and free-function exceptions.

Do not load every reference for a narrow naming question.

## Apply the core decision rules

### Argument labels

Apply these in order:

1. Omit the first label when the base name and first argument form a grammatical phrase, for a value-preserving conversion, or when peer arguments cannot be usefully distinguished.
2. Use a preposition as the label when the first argument completes a prepositional phrase.
3. Fold the preposition into the base name when multiple arguments form one abstraction and each component needs a label.
4. Label remaining arguments by semantic role.

Judge the complete call site, not the declaration in isolation.

### Side effects and pairs

- Use imperative verbs for mutating or otherwise side-effecting operations.
- Name side-effect-free results as noun or descriptive phrases.
- For verb operations, use the imperative form for mutation and a grammatical `-ed` or `-ing` form for the returned copy.
- For noun operations, use the noun for the nonmutating form and `form` plus the noun for mutation.
- Use `make` for factories that create a distinct value.
- Make Boolean APIs read as assertions about the receiver.

### Clarity and documentation

- Prefer clarity over brevity; include role words needed to remove ambiguity and omit words that merely repeat type information.
- Name variables and parameters by role, especially when their types are `String`, `Int`, `Any`, or another weak semantic signal.
- Prefer methods and properties when there is a natural receiver; use free functions only when no receiver is natural or domain notation requires one.
- Prefer a clear defaulted parameter over a redundant method family, without forcing a label that makes the call ungrammatical.
- Document public API purpose, parameters, results, thrown errors, safety, and non-obvious complexity. State the complexity of a computed property when it is not O(1).

## Verify the change

1. Show representative before/after declarations and call sites.
2. Update all call sites, tests, documentation, serialization names only when intentionally coupled, and compatibility shims when required.
3. Compile and run focused tests. Check overload resolution and protocol conformance at real call sites.
4. Report any source break, semantic uncertainty, or adjacent concern that remains outside this skill.

Use the reference decision trees as the detailed authority. Do not duplicate their examples or invent a second naming rule in a task report.
