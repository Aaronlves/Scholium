---
name: scholium-trust-boundary-audit
description: Audit, test, or harden Scholium's trust-sensitive filesystem, presentation, external-data, and researcher-control boundaries. Use as a security overlay when VaultRepository writes, canonical paths, symlinks, checkpoints, conflicts, FSEvents or save races, bookmarks, Triptych identity, frontmatter mutation, CodeMirror or WKWebView messages and CSP, CSS snippets, read-only Zotero access, Dialogue, Critique, comments, saved searches, legacy proposal migration, generated-state placement, or another subsystem could overwrite, misattribute, expose, or silently reinterpret research material. Pair it with the subsystem's narrow owner rather than using it as a substitute for fidelity, file-coordination, editor, index, workflow, or interface semantics.
---

# Scholium Trust Boundary Audit

Treat lossless source handling and human authorization as security properties. Prefer a rejected operation over an ambiguous write.

## Locate the checkout

Do not infer the checkout from this installed skill. Bind one repository root containing `AGENTS.md`, `Package.swift`, `ScholiumCore/`, and `Scholium/`. If no unique root is in scope, stop and request the checkout. Resolve paths below from the repository root.

## Route through the narrow owner

Use `scholium-development` as the repository base and final verification layer. Pair this trust overlay with:

- `scholium-markdown-yaml-fidelity` for frontmatter boundaries, parsing, patching, or exact-source mutation;
- `scholium-vault-file-coordination` for FSEvents, bookmarks, external edits, transaction races, watcher acknowledgement, or recovery;
- `scholium-derived-index-integrity` for relation semantics, index contents, query behavior, or generated-index correctness;
- `scholium-markdown-editor-integration` for CodeMirror deltas, full-buffer reconciliation, rendered Markdown, JavaScript messages, CSP, navigation, or editor/reader WebKit mechanics;
- `scholium-apple-design` for the visible approval, conflict, privacy, export, and recovery workflow.

This skill owns authorization, containment, approval, privacy, and loss-prevention consequences. The paired specialist owns the subsystem's functional semantics.

## Establish the boundary

1. Read `AGENTS.md`, `Docs/PRODUCT_GUIDE.md`, `README.md`, `ScholiumCore/VaultRepository.swift`, and the directly affected identity, Dialogue, Critique, checkpoint, legacy-proposal, document, or service code. Treat README/source as current reachability and the Product Guide as target behavior.
2. State the authoritative input, derived state, intended writer, revision token, and storage location.
3. Trace the operation from untrusted input to the final filesystem, WebKit, SQLite, or approval action.
4. Resolve the canonical non-production fixture root identified by the package `README.md` and use only disposable copies, generated fixtures, or temporary vaults. Never use a research vault.

## Audit invariants

- Resolve and standardize paths before authorization; reject traversal, missing targets, non-regular files, and symlink escape.
- Bind every Scholium-mediated write and legacy proposal to a stable vault identity, relative path, and starting fingerprint. Treat general external-agent writes as concurrent filesystem inputs outside Scholium's authorization boundary.
- Snapshot exact current bytes before mutation and fail closed when snapshot or validation fails.
- Preserve BOM, line endings, comments, ordering, unknown YAML, quoting, multiline values, and final newline outside the edited range.
- Store indexes, caches, reviews, Dialogue replies, checkpoints, and legacy proposal state in the Product Guide's assigned locations rather than inside research vaults.
- Audit the implemented direct-edit model through explicit paths, containment, fresh fingerprints, checkpoints, conflicts, attribution, and recovery. Do not invent hidden app authorization or reintroduce Proposal as an authorization layer.
- Treat links and transitive paths as neutral unless explicit relation syntax supplies the substantive role.
- Treat CodeMirror and reader messages as untrusted: accept only known handlers and typed payloads bound to the current document, editor session, version, and expected size; reject stale, malformed, cross-document, or navigation-origin messages.
- Keep editor and reader content local under a restrictive CSP. Disable ambient network and filesystem reach, constrain navigation, and reauthorize every explicitly opened external URL in Swift.
- Constrain CSS to documented document selectors and safe properties. Reject imports, URLs, cascade escape, protected research signals, and any attempt to restyle app chrome or encode evidence through presentation.
- Export only the explicitly selected note, review material, provenance, and destination. Sanitize HTML, keep temporary artifacts and embedded resources bounded, and never treat an export preview or file as a writable note authority.
- Keep Zotero access read-only and loopback-only. Resolve exact item metadata for the current Analysis or directly linked Analyses; never enumerate or download attachments, crawl the wider library, or treat Zotero metadata as verified citation support.
- Store app-owned comments, Dialogue replies, saved searches, and current compatibility records with stable Triptych/note/revision identity. Respect privacy and never widen the researcher's instruction through UI state or persistence defaults.
- Route a researcher-approved dated topic reference through the transactional repository; the CLI equivalent remains proposal-only. Validate the exact target role, revision, single-line reference, and source mutation before authorization.

Read [references/adversarial-fixtures.md](references/adversarial-fixtures.md) for the required attack and fidelity matrix.
Read [references/transaction-conflict-protocol.md](references/transaction-conflict-protocol.md) when the change touches save sequencing, snapshots, conflicts, watcher acknowledgement, or recovery.

## Look for race windows

- Check path substitution between validation and write.
- Check external edits between read, preview, snapshot, and apply.
- Check FSEvents arriving during self-writes, renames, or atomic replacement.
- Check bookmark access start/stop symmetry on success, cancellation, and failure.
- Check same relative paths and titles across different vault identities.
- Check proposal replay, duplicate approval, stale status, and cross-vault application.
- Check stale editor messages after navigation, oversized bridge payloads, WebView process restart, CSS safe-mode bypass, export cancellation or partial files, saved-search leakage, bridge/session replay, stale Agent Review requests, and topic-reference races.

## Report and fix

Rank findings:

- **P0:** unauthorized overwrite, vault escape, proposal bypass, or data loss.
- **P1:** stale or cross-vault confusion, fidelity corruption, unsafe rendered content, or missing recovery path.
- **P2:** defense-in-depth, diagnostic clarity, or fixture coverage.

Separate proven defects from plausible risks. For each finding, identify the violated invariant, smallest proof, affected files, and focused regression test. Do not broaden an audit into a rewrite.

## Verify

Run the narrow regression test, then `./Tools/Scripts/verify.sh`. For write-path changes, verify both the expected new bytes and the unchanged surrounding bytes. Never claim safety from code inspection alone when an executable fixture can prove the boundary.
