---
name: scholium-vault-file-coordination
description: "Implement, diagnose, or test Scholium filesystem observation, concurrent saves, external edits, and cross-window convergence."
---

# Scholium Vault File Coordination

Treat the filesystem as concurrently mutable. Events invalidate assumptions;
only a fresh authorized read establishes current content.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).

## Reconstruct the interleaving

Keep three contents separate: the editor's starting revision A, current disk B,
and unsaved buffer C. Determine whether the recipient was clean or dirty when
the event was applied, rather than when the notification was sent. A path alone
cannot establish that a recreated file is the same document.

Trace observation, read, validation, replacement, and publication with vault
identity and generation. Locate the first stale assumption: an event can be
coalesced, a read can finish after switching vaults, and a self-write notification
can arrive after a newer external write. Cancellation is not proof that an
already scheduled callback cannot publish.

Use the [race matrix](references/event-race-matrix.md) for diagnosis or changes
to observation, saves, access, or convergence. Reproduce the implicated ordering
with barriers at the existing boundary, not timing sleeps. Compare final bytes,
buffer recoverability, and participant state with a fresh read or rebuild.

Fix the stale check or publication owner and remove any competing path in the
bounded change. A debounce, blind reload, or self-event time window needs evidence
that it preserves a later external edit. For substantial mechanism changes,
use [backend research](../scholium-engineering/references/backend-decision-research.md).

## Invariants

- Stable vault identity and canonical path are distinct; metadata refresh must
  not silently remint identity.
- Cross-window messages are invalidation hints, not source bytes. A clean peer
  may reload after validation; a dirty peer enters explicit conflict.
- Atomic replacement prevents partial files, not stale overwrites. Preserve
  revision checks, containment, snapshot, read-back, and recovery ordering.
- Observe before scanning can create a blind interval, reconcile afterward,
  and use bounded rescans when the event stream cannot prove completeness.
- Suppress self-events only with exact committed identity and generation, not
  path or timing guesses.
- Bind asynchronous work to the current vault generation and release old
  observation exactly once when ownership changes.
- Derived state remains disposable and outside research vaults. Unavailable
  cloud content is I/O state, not an empty document.

## Evidence

Exercise controlled external edits, replacement, rename or deletion, rapid
switching, cancellation, permission loss, conflict, and recovery as applicable.
Compare event-driven state with a fresh scan or rebuild. Run focused owning
tests. Use an actual release artifact only for release-specific claims, and
report unexercised races.
