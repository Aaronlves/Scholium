---
name: scholium-trust-boundary-audit
description: "Audit or harden Scholium authorization, containment, privacy, revision, and recovery safety; ordinary subsystem work stays with its owner."
---

# Scholium Trust Boundary Audit

Treat researcher control, exact-source preservation, and current-revision
checks as security properties. Reject an ambiguous consequential action.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
The functional subsystem retains its semantics; this capability adds the trust boundary.

## Modes

- **Audit:** inspect, test when authorized, and report without editing source.
- **Harden:** after the request authorizes a fix, correct the violated trust
  boundary and add executable regression evidence.

## Find the consequential boundary

Trace one untrusted input to the action it could authorize, the durable state
it could change, or the private content it could expose. Identify the first
check and the last point where identity, revision, scope, or path can change.
Validation at dispatch is insufficient if a suspension or filesystem race can
invalidate it before use.

Write a concrete violating interleaving and its observable consequence. Use
[adversarial fixtures](references/adversarial-fixtures.md) for the applicable
attack class and the [transaction checklist](references/transaction-conflict-protocol.md)
for writes or recovery. Check both rejection and absence of prohibited effects;
a returned error does not prove that bytes, access, or evidence stayed unchanged.

In Harden mode, enforce the invariant in the functional owner so all callers
receive it, then exercise the violating case and a valid neighboring operation.
Do not replace a loss-prevention defect with universal denial. In Audit mode,
report the reachable violation, evidence limits, and smallest regression proof.
Use [backend research](../scholium-engineering/references/backend-decision-research.md)
only for a new mechanism or dependency.

## Invariants

- Resolve and contain paths before use, then defend against substitution at the
  consequential operation.
- Bind every Scholium-mediated mutation to stable identity, explicit scope,
  current revision, attribution, and recoverable exact bytes.
- Preserve the specification's current authorization model; do not restore a
  retired approval layer or broaden permission through UI or persistence state.
- Treat editor, reader, external-data, and agent-facing inputs as untrusted.
  Validate type, size, identity, session, revision, transport, and scope at the
  owning boundary.
- Keep active content local and constrained. External navigation, networking,
  presentation policy, and consequential actions require explicit native
  authorization.
- Generated, recovery, and workflow state goes only to its live assigned
  location and never becomes research authority. Unsupported pre-production
  data remains exact source and grants no workflow or write authority.
- Links, search results, and imported metadata do not become philosophical
  evidence by proximity or transitivity.
- Cancellation, failure, conflict, and replay must not lose source, widen
  authority, or apply work to another vault or revision.

## Evidence and reporting

Separate proven defects from plausible risks. For each finding state the
violated invariant, minimal proof, consequence, owner, and regression test;
rank by actual loss or authorization impact, not a copied severity table. Run
focused owning tests. Never claim safety from inspection alone when an
executable fixture can test it.
