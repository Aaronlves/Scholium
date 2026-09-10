---
name: scholium-vault-file-coordination
description: "Implement, diagnose, or test Scholium coordination with external editors, sync tools, and multiple windows. Use for watchers, scans, rename/delete, autosave, stale buffers, conflicts, atomic replacement, bookmarks, cloud placeholders, or lifecycle."
---

# Scholium Vault File Coordination

Treat the filesystem as concurrently mutable. Events invalidate assumptions;
only a fresh authorized read establishes current content.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).

## Method

1. Reopen current ownership, construction, identity, write, watcher, cache, and
   window-lifecycle evidence.
2. Trace disk bytes, open buffers, starting revisions, vault identity, watcher
   generation, and derived generations separately.
3. Model the relevant race before editing. Use the
   [event and race matrix](references/event-race-matrix.md) for watcher,
   autosave, bookmark, or cache changes.
4. Make the smallest change at the single owning boundary; do not add a second
   watcher, writer, cache authority, or conflict lifecycle.
5. Verify the final bytes and every affected clean, dirty, cancelled, failed,
   and recovered participant with disposable vaults.

For substantial mechanism changes, apply the shared
[backend decision research](../scholium-engineering/references/backend-decision-research.md)
before custom implementation.

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
