---
name: scholium-trust-boundary-audit
description: "Audit or harden Scholium researcher-control and loss-prevention boundaries. Use only when authorization, containment, privacy, current-revision enforcement, credential handling, or recovery safety could permit loss, disclosure, or a misapplied consequential action; select audit or harden mode. Ordinary source semantics, file observation, Agent lifecycle, and recovery presentation stay with their functional owners unless this trust contract changes."
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

## Method

1. Reopen the target contract and live path from untrusted input through its
   authorizer, writer or action, persisted record, and recovery path.
2. Name the authoritative input, derived state, intended owner, revision token,
   containment boundary, and storage location.
3. Test the boundary with disposable fixtures and adversarial interleavings.
   Load the [adversarial fixture guide](references/adversarial-fixtures.md) for
   the relevant attack classes.
4. For writes, snapshots, conflicts, or recovery, also load the
   [transaction and conflict protocol](references/transaction-conflict-protocol.md).
5. In Harden mode, fix the violated boundary and add an executable regression
   proof. In Audit mode, stop with the finding, consequence, owner, and required
   proof.

For a new mechanism or dependency, apply the shared
[backend decision research](../scholium-engineering/references/backend-decision-research.md).

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
