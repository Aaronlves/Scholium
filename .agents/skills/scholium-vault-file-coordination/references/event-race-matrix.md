# Vault event and race matrix

Use the trust skill's [transaction-conflict-protocol.md](../../scholium-trust-boundary-audit/references/transaction-conflict-protocol.md) as the sole transaction-phase and failure-reconciliation authority. This matrix adds filesystem-event interleavings and watcher assertions; it does not redefine the write order.

For every scenario, record the starting disk fingerprint, editor fingerprint, event generation, final disk fingerprint, and visible recovery state.

| Scenario | Injected sequence | Required result |
|---|---|---|
| Initial-open window | event arrives while initial scan runs | Post-scan reconciliation includes the newest disk state |
| External edit | read A, external writes B, user saves C | Reject overwrite; keep C recoverable; show B as current disk state |
| Preparation race | fingerprint passes, target changes before replacement | Detect or explicitly document the remaining race; never claim atomic write solves it |
| Phase-5 recheck failure | external edit or path substitution occurs after provisional snapshot | Abort before replacement; preserve external bytes and delete or quarantine provisional history outside the visible version index |
| Self write | app commits B and receives its FSEvent | Acknowledge B once without discarding a later external C |
| Rapid edits | A -> B -> C before coalesced callback | Final model and indexes represent C |
| Delete/recreate | delete path, recreate new inode at same path | Reauthorize and reload; do not attach stale buffer silently |
| Rename | old path removed, new path appears | Reconcile both paths even when notifications are unpaired or reordered |
| Case-only rename | `Note.md` -> `note.md` | Preserve display spelling and avoid duplicate identity |
| Unicode collision | NFC and NFD spellings refer to colliding names | Diagnose ambiguity deterministically |
| Symlink substitution | validated path becomes link outside vault | Reject access; do not follow the replacement |
| Permission loss | access disappears during read or save | Leave original bytes and editor work recoverable |
| Snapshot failure | history bytes or index cannot persist | Do not mutate the vault file; delete incomplete history or quarantine it outside the visible version index for startup cleanup |
| Replacement failure | atomic replacement throws after snapshot | Read back rather than assuming no commit; reconcile the provisional snapshot as discarded or recovery history from observed disk state |
| Readback mismatch | post-write bytes differ from proposal | Surface failure and refresh from disk; never announce success |
| Event drop | dropped flags or `MustScanSubDirs` | Perform a bounded full rescan and advance generation once complete |
| Root change | watched root moves or disappears | Terminate old stream and require explicit recovery/reselection |
| Vault switch | late event from vault A arrives after opening B | Generation and vault identity prevent mutation of B's state |
| Cross-window clean view | window A commits B while window B has no local edit | Window B verifies vault/path/revision against disk and refreshes without treating the notification payload as source bytes |
| Cross-window dirty view | window A commits B while window B edits C from A | Keep C recoverable and enter conflict against committed B; never silently reload or weaken the next fingerprint check |
| Duplicate per-window observer | two windows currently observe the same physical vault | Both converge on the committed fingerprint without duplicate publication hiding a later external edit; migrate toward one shared owner |
| Registry repair | identity bookmark refreshes while workspace role/name remains current | Preserve the stable UUID, reconcile both registry records, and keep open windows bound to the same vault identity |
| Registry interruption | failure occurs between identity and workspace registry persistence | Do not retarget a window or mint a second logical vault silently; surface recoverable reconciliation on the next open |
| Cancellation | scan or parse is cancelled mid-batch | Do not publish a partial generation as complete |
| Cloud placeholder | file is unavailable or unexpectedly zero bytes | Diagnose availability; do not index or overwrite as an empty note |

## Failure-injection assertions

- Use a disposable vault and deterministic barriers around read, snapshot, replace, and publish phases.
- Assert exact disk bytes after every injected failure.
- Assert bookmark access start/stop symmetry and event-stream release on success, error, cancellation, and vault switch.
- Assert a full rebuild and the event-driven result converge to the same note inventory and fingerprints.
- Assert cross-window commits are keyed by origin session, vault UUID, path, and revision, and that dirty and clean recipient windows diverge only in their explicit recovery state.
- Assert `VaultIdentityRegistry` and `WorkspaceRegistry` converge on one UUID/path pair after bookmark refresh, role change, interrupted persistence, and restart.
