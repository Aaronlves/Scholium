---
name: scholium-research-action-collaboration
description: "Implement, diagnose, or test Scholium Research Action and local Agent collaboration lifecycles. Use for Action preparation, Run or Session state, pairing, direct start or handoff, Research Context, bounded mutation, Result and Record finalization, continuation, End, or operation-specific recovery; exclude academic method content, interface-only work, ordinary source or index bugs, and release acceptance."
---

# Scholium Research Action Collaboration

Keep every Research Action on one Application-owned lifecycle from preparation
through determined completion or explicit recovery. Delivery routes expose that
lifecycle; they do not create another workflow or authority.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Read the specification and architecture manifests, then follow their declared
Research Action and execution chapters at the depth required by the task.

## Responsibility boundary

Use this skill for functional Action, Run, local Agent, CLI, Context, mutation,
result, continuation, and recovery behavior. Keep these neighbors separate:

- Academic Method content, Skill reference/lens content, and philosophical-
  content quality remain outside the developer toolkit and this skill.
- Researcher authorization, containment, credential secrecy, privacy, and
  adversarial hardening add the trust-boundary owner.
- Exact Markdown mutation, filesystem races, Search semantics, interface
  presentation, interaction acceptance, and release decisions retain their
  existing specialist owners.

## Method

1. Bind one live request from its GUI or direct-Agent entry through the Run's
   current terminal, cancellation, or recovery state. Identify the owner of
   preparation, Session authority, Context, each mutation, durable result, and
   delivery separately.
2. Trace stable identity, request identity, revision, capability, idempotency,
   cancellation, failure, unknown outcome, restart, and cleanup before changing
   the functional owner.
3. Preserve one delivery-neutral Application contract. Keep CLI, bridge, and
   interface adapters as typed transports and projections rather than workflow
   owners.
4. Change the smallest owning boundary and update every affected contract,
   caller, recovery branch, and focused test without retaining a superseded
   retry or compatibility route.
5. Verify the exact lifecycle and adjacent stale, cancelled, failed, replayed,
   unknown, and recovered states. Route genuine interaction or release-artifact
   claims to their distinct evidence owner.

## Invariants

- One Action attempt has one Run and one canonical durable result. A Session,
  handoff, Context response, adapter, or projection never becomes a second Run
  or persistence authority.
- Restart, re-pairing, revocation, and delivery failure may change connection
  authority but never erase confirmed writes, conflicts, recovery duties, or
  the Run's identity.
- Research Context is read-only, Run-scoped, current-owner-checked evidence.
  Retrieval grants no mutation authority and establishes no philosophical
  support, relevance truth, use, or researcher acceptance.
- Every mutation remains bound to one explicit member, operation, stable
  identity, current revision or proven absence, and nonreusable capability.
  One member's outcome does not create a batch rollback or widen siblings.
- Finalization waits for every initiated write and recovery duty to become
  determined. End and cancellation cannot discard confirmed or unknown work.
- Retry behavior follows the operation's actual idempotency and exact request
  identity. Never invent a fallback destination, replacement identity, generic
  retry, or hidden compatibility path.

Report the functional owner, lifecycle change, App and CLI parity, exact
failure and recovery evidence, and every interaction, philosophical-quality,
packaging, or human-acceptance claim left to another owner.
