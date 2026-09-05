# Architecture classification and decomposition

Use this for architecture audits, decomposition decisions, and structural
cutovers. Classify the live system before prescribing a pattern or split.
`AGENTS.md` and `Docs/` remain Scholium authority; architecture literature
provides comparison concepts only.

## Avoid category errors

A file is not automatically a component, a target is not a service, an actor is
not an architecture, and an event or separate read/write function does not by
itself establish an architectural style. Record current and target separately.
When a label is unsupported, describe owners, dependencies, state, and flow.

Name the abstraction level: ecosystem, runtime/deployment unit, component, or
code element. Recommend a cut at the level where the violated boundary exists.

## Classify only relevant axes

- **Capability:** what researcher or technical responsibility and language the
  unit owns.
- **Dependency:** which policy, ports, adapters, and delivery mechanisms may
  know about one another.
- **Runtime:** actual process, deployment, failure, and security boundaries.
- **State authority:** authoritative source, sole writer, identity, lifetime,
  transaction, readers, projections, conflicts, and recovery.
- **Coordination:** ordering, cancellation, delivery, idempotency, teardown,
  and reconciliation across calls, actors, streams, events, or transactions.
- **Presentation:** intent, durable state, derived presentation, side effects,
  focus, selection, and window lifetime.
- **Cutover:** the superseded owner, every repository-owned consumer, enforced
  replacement boundary, and proof required for direct removal.

Trace construction, representative calls, mutations, failure, cancellation,
and recovery. Imports, protocols, history, file size, churn, and diagrams are
leads, never sufficient proof.

## Decide whether to split

A coherent boundary has one intelligible responsibility, owner, identity,
lifetime, invariant set, failure model, and narrow testable contract. Keep
transactions together when they must remain all-or-nothing.

Distinguish:

- responsibility atomicity;
- in-memory state-transition atomicity;
- durable-transaction atomicity; and
- cutover atomicity with one valid owner in the resulting construction.

Choose the smallest cut that enforces the needed boundary: narrower facets,
file organization, internal component, compiler-enforced module, or separate
runtime. Reject cuts that create circular ownership, pass-through facades,
chatty coordination, duplicated validation, shared mutable state, distributed
transactions, or two sources of truth.

## Findings and cutover

Name the result precisely: declared-boundary violation, ownership collision,
cohesion fracture, dependency leakage, coordination fracture,
superseded-path residue, supported opportunity, or evidence gap.
Maintainability alone is not a correctness defect.

For an approved change, define preserved invariants, introduce the narrow
contract, move one coherent responsibility and every repository-owned consumer,
prove the new owner and transaction boundary, delete the old path in the same
bounded change, and reconcile architecture/status evidence.

Report level, current and target classification, concrete evidence, consequence,
smallest justified cut, invariant that stays together, proof required, and
uncertainty. Relevant primary concepts include the
[C4 abstractions](https://c4model.com/abstractions),
[Hexagonal Architecture](https://alistair.cockburn.us/hexagonal-architecture).
