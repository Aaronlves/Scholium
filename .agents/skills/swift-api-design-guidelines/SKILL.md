---
name: swift-api-design-guidelines
description: "Design, review, or refactor Swift API names, labels, and documentation using Swift API Design Guidelines. Use for call-site grammar, side-effect and mutating-pair naming, protocol names, defaults, casing, complexity comments, or terminology."
---

# Swift API Design Guidelines

Design for clarity at representative call sites. Preserve behavior that the
current task does not replace; source compatibility is not an independent goal.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Use the current official
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
as detailed authority rather than duplicating their rulebook here.

## Method

1. Read the declaration, representative call sites, protocol requirements,
   public documentation, tests, and project terminology.
2. Identify the receiver, each argument's semantic role, side effects, returned
   value, and any mutating/nonmutating relationship.
3. Propose the smallest naming change that makes the complete call grammatical
   and unambiguous in context.
4. Check overload resolution, protocol conformance, documentation, and every
   repository-owned caller before applying a rename.
5. Compile and run focused tests; report source breaks or intentionally coupled
   serialized names separately.

## Invariants

- Prefer clarity over brevity; include role words that disambiguate and omit
  words that merely repeat type information.
- Name side-effecting and value-returning operations so callers can distinguish
  them, and keep mutating pairs grammatically related.
- Label parameters by semantic role when types do not communicate enough.
- Prefer a natural receiver and a coherent defaulted API over redundant method
  families.
- Document non-obvious purpose, safety, effects, errors, results, and cost; do
  not add commentary that only restates the declaration.
- Route type-system, concurrency, lint configuration, and architecture changes
  to their owning capability or live tool documentation.
- Do not retain an obsolete name as an alias or forwarding overload; update
  every repository-owned caller and remove the superseded declaration.

Judge names in the product's language and actual call sites, not in isolation.
