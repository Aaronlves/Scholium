# Transaction and conflict verification checklist

The canonical manifests rooted at `Docs/SCHOLIUM_SPEC.md` and
`Docs/IMPLEMENTATION_ARCHITECTURE.md` route target write/conflict/recovery rules
and their current structural owners. Live construction and tests establish
reachability. This reference supplies stable safety questions; it is not a
second transaction protocol and must not preserve current phase names or
ordering as authority.

## Establish the live contract

Before reviewing a mutation, locate the authoritative repository path and
record the vault identity, canonical root, document identity, starting
revision, current disk revision, candidate revision, recovery/history state,
and editor or mutation-session identity required by the current contract.

Trace the exact implemented sequence and confirm that it preserves all of
these invariants:

- authorize a contained existing regular target before treating bytes as
  writable;
- read exact current bytes and verify the expected revision;
- build and validate complete candidate bytes without mutating disk;
- establish the recovery or history state required by current authority before
  an irreversible replacement;
- recheck containment, identity, target type, and revision at the last safe
  point before replacement;
- replace atomically without routing around the authoritative repository;
- read back and verify the committed bytes before announcing success; and
- reconcile history, watcher acknowledgement, derived projections, and visible
  save state with the verified result.

If the documentation, architecture, code, and tests disagree about the exact
sequence, report the divergence at its owning layer. Do not use this checklist
to choose silently among them.

## Failure and cancellation questions

For every fallible step, verify:

- whether disk may have changed;
- which exact pre-write or candidate bytes remain recoverable;
- whether provisional history is hidden, removed, quarantined, or promoted
  according to the current documented policy;
- whether cancellation is still safe or must finish readback reconciliation;
- whether the UI reports success, conflict, uncertainty, or recovery truthfully;
- whether a derived refresh failure leaves the authoritative save intact while
  marking projections accurately stale; and
- whether startup reconciliation can resolve interrupted cleanup without
  touching unrelated research files.

## Adversarial interleavings

- Substitute a symlink or different target after initial validation.
- Edit, rename, delete, or recreate the file between read, recovery-state
  creation, final recheck, replacement, and readback.
- Deliver self-write and external-write events in either order.
- Submit the same mutation twice or after changing vault/window identity.
- Cancel or inject failure at every externally visible boundary.

## Conflict presentation

Derive exact labels and actions from the current specification. Always keep the
starting user buffer, current disk bytes, and proposed bytes distinguishable;
never discard unsaved text silently, weaken the next revision check, or imply
that comparison itself authorizes a write.
