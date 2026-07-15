---
name: scholium-vault-file-coordination
description: Implement, diagnose, review, or test Scholium's coordination with externally edited vault files and multiple app windows. Use for FSEvents, initial scans, rename/delete/recreate handling, autosave acknowledgement, stale buffers, cross-window commits, shared repository/index/watcher ownership, conflict detection, atomic replacement, snapshots, caches, VaultIdentityRegistry and WorkspaceRegistry reconciliation, security-scoped bookmarks, cloud placeholders, watcher lifecycle, or any race among Scholium windows, Obsidian, sync software, and filesystem changes.
---

# Scholium Vault File Coordination

Treat the filesystem as concurrently mutable. File events invalidate assumptions; only a fresh authorized read establishes current content.

## Locate the checkout

Do not derive the project path from this installed skill. Bind one repository root containing `AGENTS.md`, `Package.swift`, `ScholiumCore/`, and `Scholium/`. If no unique root is in scope, stop and request the checkout. Resolve paths below from the repository root.

Pair this skill with `scholium-development` for implementation and final verification and with `scholium-trust-boundary-audit` when authorization, path containment, proposal approval, or data-loss risk is involved. Add `scholium-markdown-yaml-fidelity` when save preparation changes document bytes or frontmatter. Add `scholium-derived-index-integrity` when cache contents, search/link semantics, or derived-index publication changes.

## Model the state before changing code

Trace these separately:

- authoritative bytes currently on disk;
- the open editor buffer and its starting fingerprint;
- stable vault identity and security-scoped access lifetime;
- `VaultIdentityRegistry` identity/bookmark state and `WorkspaceRegistry` role/name/three-slot state;
- pre-write version history;
- parsed note, search, link, review, and rendering projection freshness, while each specialist remains authoritative for its projection's contents;
- watcher generation and pending invalidations;
- the originating window/session, cross-window commit revision, and every other window's clean or dirty buffer state;
- the owner actor for the repository, watcher, lexical index, and vault-derived catalog.

Read `ScholiumCore/VaultRepository.swift`, `VaultIdentity.swift`, `WorkspaceRegistry.swift`, `Scholium/Services/VaultService.swift`, `WindowSession.swift`, the watcher/save logic in `Scholium/App/ScholiumApp.swift`, and the directly affected cache or bookmark code. Inspect the live ownership before claiming that repository, watcher, or index services are shared; cross-window commit notification alone does not establish shared ownership.

## Coordinate registries and windows

Scholium currently has two complementary registry records:

- `VaultIdentityRegistry` binds canonical path to stable UUID and security-scoped bookmark.
- `WorkspaceRegistry` binds that UUID to display name, workflow role, canonical path, and the mandatory three-vault slot assignment.

Reconcile them by stable UUID plus canonical path before opening a vault. A refreshed bookmark must preserve identity. A role or display-name change must not remint identity. Never accept a matching path with a mismatched UUID, silently drop a missing workspace record, or let a partial two-registry update retarget an existing window. Make repair explicit and test interruption between registry writes.

Prefer one actor-owned `VaultRepository`, watcher, catalog, and mutable lexical index per opened vault, shared by window sessions. Keep tabs, history, selection, mode, scroll, inspector, proposal presentation, and dirty editor buffers per window. If the live implementation still constructs vault-derived services per `AppState`, treat that as an ownership gap to measure and migrate, not as proof of a shared design.

A cross-window commit envelope must carry origin session, vault UUID, relative path, and committed revision. Ignore only the exact originating session. For another window, validate the vault identity and read disk afresh: reload a clean view after fingerprint verification, but put a dirty buffer into an explicit conflict without discarding either version. The notification is an invalidation hint, never the authority for file bytes.

## Keep writes transactional

Read the trust skill's [transaction and conflict protocol](../scholium-trust-boundary-audit/references/transaction-conflict-protocol.md) before changing any write, save, snapshot, conflict, or recovery path. It is the sole numbered authority for transaction phases and pre- versus post-snapshot failure reconciliation. This skill owns watcher acknowledgement and projection invalidation after the protocol establishes the committed readback fingerprint; it does not define a second transaction order.

Atomic replacement prevents partial files; it does not by itself prevent lost updates. Keep conflict checks, symlink containment, and snapshot failure handling explicit. Never route an app, CLI, cache, or watcher write around `VaultRepository`.

## Treat FSEvents as advisory

- Start observation early enough that the initial scan has no blind window, then reconcile a post-scan snapshot.
- Coalesce notifications for work efficiency, not for correctness. Multiple flags and repeated paths are normal.
- Handle rename as invalidation of both old and new inventories; do not rely on paired or ordered rename events.
- Trigger a bounded full rescan when the stream reports dropped events, wrapped IDs, root changes, or `MustScanSubDirs`.
- Bind async parsing and refresh results to a vault identity and generation so stale work cannot replace newer state.
- Cancel and release the previous stream exactly once before opening another vault.
- Ensure one physical vault is not watched and indexed independently by multiple windows after shared ownership is introduced. During migration, duplicate observers must still converge by vault ID and committed fingerprint without suppressing external edits.

Self-write suppression must recognize the exact committed fingerprint and generation. A path-only or time-window heuristic can hide a real external edit. After acknowledgement, the normal watcher path must remain able to observe later edits to the same file.

Read [references/event-race-matrix.md](references/event-race-matrix.md) before changing watcher, autosave, cache, or bookmark behavior.

## Keep derived state disposable

This skill owns filesystem-driven invalidation, cache identity, refresh generations, and publication timing. `scholium-derived-index-integrity` owns search/link/index contents, query semantics, and full/incremental equivalence; pair the skills whenever a change crosses that boundary.

- Never hydrate a writable note from partial metadata or rendered-content caches.
- Key cache entries with enough identity to detect same-timestamp or atomic-replacement changes; modification time alone is not a correctness token.
- Rebuild missing or corrupt caches from vault bytes without writing generated state into the vault.
- Treat zero-byte or unavailable cloud placeholders as an I/O state to diagnose, not as valid empty notes.
- Preserve case and Unicode spelling in display paths while using filesystem-appropriate collision checks for identity.

## Verify race behavior

Use temporary vaults and controllable failure injection. Assert final disk bytes, snapshot state, editor recoverability, derived generation, and watcher lifecycle. Cover external edits before save, during preparation, after replacement, and during refresh; delete/recreate; case-only rename; symlink substitution; permission loss; cancellation; dropped events; and rapid vault switching.

Run focused tests, then `./Tools/Scripts/verify.sh`. During development, use the isolated QA app and disposable fixtures for window and watcher journeys; do not call that Debug harness a release package. Use a deliberately built release artifact only when making release claims about security-scoped bookmarks or real FSEvents behavior. Report which races were executed and which remain code-review risks.

## Primary references

Use Apple's [File System Events Programming Guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html) and [File System Programming Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/) for platform behavior. Evaluate file coordination or replacement APIs in the checked deployment target; do not assume they replace Scholium's fingerprint and authorization protocol.
