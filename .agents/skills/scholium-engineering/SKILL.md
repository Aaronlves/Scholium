---
name: scholium-engineering
description: "Implement Scholium changes that cross subsystem owners, change state ownership, or are an explicit final integration. Use architecture-cutover or cross-layer-integration mode; route documentation, design, audits, and single-owner work elsewhere."
---

# Scholium Engineering

Own actual cross-layer implementation or explicit final integration. Work
fully owned by one specialist does not need this capability.
Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Start at the specification, architecture, and status manifests and follow only
the affected responsibility routes.

## Modes and methods

- **Cross-layer integration:** connect one complete vertical slice through
  existing owners, or close an identified stabilized integration. Follow the
  [integration loop](references/backend-integration-loop.md).
- **Architecture cutover:** change ownership, dependency direction, or runtime
  composition using the [cutover method](references/architecture-cutover.md).
  Move every affected consumer and remove the superseded owner in the same patch.

File movement, broad reading, or the word “final” alone selects neither a
cutover nor a complete gate. Final integration is not a new product-work mandate.

For structural questions use [architecture classification](references/architecture-classification-and-decomposition.md).
For a new mechanism or dependency use [backend decision research](references/backend-decision-research.md).
Use [service-boundary testing](references/service-boundary-testing.md) only when
existing targets cannot exercise deterministic service behavior, and
[release verification](references/release-verification.md) only for release work.

Delivery adapters preserve application/domain semantics. Do not split an atomic
state transition, durable transaction, or single-writer invariant. Derived
state never becomes writable research source. Update affected contracts,
construction, callers, failure/recovery paths, tests, and architecture/status
evidence together.

Follow `AGENTS.md` for owning tests during iteration and the complete gate once
the qualifying integration stabilizes. Report transferred ownership, resulting
behavior, actual proof, and remaining uncertainty.
