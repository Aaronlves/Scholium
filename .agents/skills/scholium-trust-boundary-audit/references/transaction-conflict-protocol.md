# Transaction and conflict protocol

This protocol remains binding for Scholium-mediated writes and current legacy Proposal application. Under `Docs/PRODUCT_GUIDE.md`, direct external-agent edits enter through file coordination and conflict detection rather than an app Proposal authorization flow.

This is the sole numbered transaction-phase authority for Scholium vault writes. Other skills may repeat high-level safety invariants, but must link here instead of maintaining a second phase list.

A shorter transaction overview in `README.md` is non-authoritative and must not omit the recheck, readback, or provisional-history reconciliation when guiding implementation. Trace live code and tests first. If they do not implement this protocol, report the gap, implement and verify the missing behavior through `scholium-development` plus the narrow owners, and only then update the overview to describe the reachable behavior.

## State record

Before reviewing a mutation, record the vault UUID, canonical root, relative path, starting fingerprint, current disk fingerprint, proposed fingerprint, snapshot location, and editor/proposal session identity.

## Required phases

1. Authorize an existing regular target inside the canonical vault.
2. Read exact bytes and verify the expected fingerprint.
3. Build and validate the complete proposal without mutating disk.
4. Persist the exact pre-write bytes and a provisional version-index entry that is not yet presented as committed history.
5. Recheck revision and path facts exposed to time-of-check/time-of-use substitution.
6. Atomically replace the target.
7. Read back and verify the committed fingerprint.
8. Mark the version entry committed, acknowledge the matching self-write event, and either publish one complete derived-state generation or explicitly mark projections stale for rebuild.

## Failure behavior

- Authorization or revision failure before phase 4: do not snapshot or write.
- Proposal validation failure before phase 4: keep the editor or proposal open, leave disk unchanged, and do not snapshot.
- Snapshot or snapshot-index failure during phase 4: do not write. Remove any incomplete index entry and delete incomplete snapshot bytes. If deletion fails, quarantine the bytes outside visible history and emit a cleanup diagnostic that the next startup reconciliation must resolve.
- Authorization, path, or revision failure during the phase-5 recheck: do not write. Remove the provisional version-index entry and delete its snapshot bytes so neither can appear as committed history. If deletion fails, quarantine the bytes outside visible history and emit the same startup-cleanup diagnostic.
- Replacement failure after phase 4: do not assume disk is unchanged. Read back the target. If its fingerprint still matches the pre-write bytes, remove the provisional version-index entry and delete its snapshot bytes. If disk changed or cannot be verified, promote the exact pre-write snapshot to recovery history and surface the uncertain commit state.
- Readback mismatch after replacement: do not announce success. Promote the exact pre-write snapshot to a recovery version because disk may have changed, reload current disk state, and preserve recoverable user work.
- Cancellation before phase 4: do not snapshot or write. Cancellation after a provisional snapshot but before replacement: do not write, remove the provisional index entry, and delete or quarantine its bytes under the same cleanup rule. Cancellation once replacement may have begun: finish readback reconciliation, retain the pre-write snapshot as committed or recovery history according to the observed disk state, and never report an unverified success.
- Derived refresh failure: do not revoke the authoritative save. Keep the committed disk revision explicit and mark projections stale until rebuilt.

## Adversarial interleavings

- Replace the target with an outside-vault symlink after initial validation.
- Edit the file after fingerprint comparison but before snapshot and before replacement.
- Delete and recreate the same path with a new inode.
- Deliver self-write and external-write FSEvents in either order.
- Approve the same proposal twice or after switching vaults.
- Cancel during snapshot, replace, readback, and derived refresh.
- Fail version-file write, version-index write, replacement, and readback independently.

## Conflict UI contract

- Show the starting user buffer, current disk bytes, and proposed buffer as distinct states.
- Reload must be explicit and must not silently discard unsaved text.
- Keep Editing preserves the local buffer but does not weaken the next fingerprint check.
- Compare, when implemented, is a three-way aid; it does not auto-merge YAML or authorize a write.
