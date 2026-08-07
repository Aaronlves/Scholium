# Implementation Status: Reachable Capabilities

Part of the dated status set rooted at [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md).
This chapter records product capabilities reachable in the current build. It
does not define target behavior, explain module ownership, list completed
migrations, or claim acceptance. Open work belongs in [Open Work](03-open-work.md)
and dated proof belongs in [Verification Evidence](04-verification.md).

## Workspace and source authority

- Multiple registered Triptychs can use independently selected Analyses,
  Topics, and Works vaults. Each window belongs to one Triptych. Portable
  control state stays in `.scholium`; machine-local and derived state stays in
  Application Support.
- Production validates its real Application Support root before constructing a
  workspace. Failure presents Storage Unavailable with Retry, Details, and
  Quit; there is no temporary workspace fallback.
- Exact Markdown bytes remain authoritative. Reads, fingerprints, precommit
  checks, writes, readback, and recovery use descriptor-relative containment,
  no-follow file access, regular-file verification, coordinated access,
  revision checks, atomic replacement, metadata preservation, and retained
  recovery evidence when an outcome is uncertain.
- Targeted frontmatter edits preserve unrelated bytes and fail closed when a
  unique, semantically valid edit boundary cannot be proven.
- One serialized source-mutation and refresh boundary coordinates Scholium,
  external editors, watchers, and derived publication. A proven source commit
  remains successful when later Search, graph, identity, or snapshot refresh
  needs recovery; the interface does not invite a repeated mutation.

## Notes, folders, lifecycle, and recovery

- New Note, New Folder, duplicate, UTF-8 Markdown import, rename, move, Set
  Aside, Move to Trash, Put Back, and permanent deletion are reachable through
  shared Application capabilities. Batch import reports committed files and
  exact per-file failures independently.
- Stable Note identity follows confirmed moves and reconciled external renames.
  Identity-dependent commands carry vault, stable identity, path, and revision
  together and reject path reuse or ambiguous identity.
- Folder moves preserve non-Markdown content, preflight descendant Note
  revisions, rewrite only identically resolved incoming links, and publish a
  source-ahead hierarchy while one derived generation converges.
- Editor Undo, researcher-created Triptych checkpoints, Before Agent Work
  versions, settled-revision pins, and interrupted-write candidates remain
  distinct recovery layers. Recovery compares exact revisions before restore
  and keeps candidates when a safe replacement cannot be proven.
- Settle stores one replaceable researcher judgment for an exact saved
  revision and pins its bytes for recovery. A Work retains one attributed
  current Critique with separate Accept, Reject, Rebut, and Complete Round
  decisions.

## Search, Connections, and Attention

- One Search owner serves GUI, CLI, Research Records, and authenticated
  Research Context. It supports This Note, This Vault, and Triptych scope;
  lexical, Property, direct-relation, and portable Record queries; typed match
  reasons; Saved Searches; completion; and deterministic Explain Query data.
- This Note Search reads the unsaved editor snapshot. Other Search results are
  bound to provider, generation, fingerprint, session, and revision freshness.
- One graph owner resolves neutral, support, opposition, and undirected
  incompatibility Vector Links. Neutral links and transitive paths remain
  Connections rather than philosophical evidence.
- Attention derives bounded structural, identity, metadata, connection,
  currency, and reliance conditions. Dismiss, Resynthesize, and Leave
  Unchanged affect presentation or create an explicit Action; they do not
  silently change research content or assert a verdict.

## Documents and editing

- Review, Edit, and Source share one retained document session. Review renders
  sanitized committed semantics; Edit provides source-preserving Live Preview;
  Source exposes exact text. Autosave, mode convergence, selection, focus,
  scroll, composition, Undo, conflict, and recovery remain bound to the same
  source session.
- The editor supports the locked Markdown dialect, semantic Callouts, tables,
  footnotes, mathematics, Wiki and Vector Links, comments, task items,
  formatting actions, caret-anchored Wikilink and slash-command suggestions,
  and nonmutating Search-result reveal.
- Empty source, whitespace, loading, unavailable source, rendering failure,
  conflict, and recovery are distinct states. A dirty, conflicted, in-flight,
  or recovery-owning tab is not discarded by external deletion or refresh.
- Named Appearance configurations, shared line width, semantic document
  typography, and sanitized managed CSS snippets update Review and Edit without
  changing Markdown or reconstructing the retained editor. Source receives
  only the shared line-width layout change.

## Research Actions and local Agent collaboration

- The closed Platform catalog exposes Discuss, Analyze, Synthesize, Write,
  Critique, Check Fidelity, and the hidden Manuscript boundary where allowed.
  Preparation freezes the exact target, source and focal materials, registered
  Method and Practices, academic Profile, Result Contract, collaboration
  policy, read scope, and initial Bounded Write Set member.
- The Action sheet and active Discussion expose one complete Copy Handoff route
  for the researcher to paste into Codex or another Agent application. The
  handoff contains the Run route and one-time Pairing Code; the code is not
  exposed as a separate field. Copy New Handoff invalidates the prior code.
- Pairing through the installed CLI creates a process-bound local Connection
  Session. Pairing is the only unauthenticated operation; context, reads,
  write-set extension, mutation, result, continuation, Method improvement,
  status, and End require the protected Session credential.
- The authenticated Core Protocol owns the Agent's Run workflow. Installed CLI
  help owns current syntax; typed command contracts own fields and allowed
  values; registered Methods and Practices own the academic procedure.
- The Application Research Context composes current Search, exact Note reads,
  direct graph relations, Properties, Records, source references, and explicit
  researcher state while preserving owner, revision, locator, scope,
  currentness, evidential layer, retrieval reason, and limitation.
- Research Context accepts closed typed clauses and returns a separate visible
  outcome for each clause. Exact Note or section bytes are source-range pages
  with stateless continuation binding; no source-kind/purpose fallback remains.
- Context Use is validated against the authorized Run scope and each current
  owner, revision, locator, and provenance field. There is no separate
  delivered-reference registry or Agent-owned parser, index, ranker, or context
  store.
- A Run owns one bounded expandable write set. Each approved document mutation
  still receives a nonreusable short-lived capability and one idempotent
  operation identity, then uses the sole exact repository transaction. One
  member's conflict does not widen authority or roll back confirmed siblings.
- Result submission validates the frozen academic fields and Context Use;
  Application adds machine facts from actual transactions. Finalization is
  idempotent and waits until initiated writes and recovery duties have known
  outcomes. Continue Research creates a separate Run.
- Prepared Actions expose End Action; active Discussions expose End Discussion.
  Closing leaves the Run or exchange active. Failed background cleanup of an
  undelivered preparation does not block later Actions, while an interrupted
  explicit End remains visible and retryable until cancellation converges.

## Records, Discussions, recommendations, and evaluation

- A Comment stores one exact Note revision and inclusive line range without
  starting an Agent Run. Discuss combines saved Comments, whole-note turns,
  optional focal Notes, and attributed replies in one portable active
  exchange. Finish produces one neutral Research Record.
- Completed Action Records retain the immutable finalized result, minimal
  Method provenance, participating revisions, Context Use, confirmed changes,
  discrepancies, Fidelity completion, and Analyze-only Literature
  Recommendations. Machine paths, credentials, prompts, raw transport logs,
  and token counts are excluded.
- The independent Triptych-keyed Research Records window uses the same Record
  provider as Search and CLI. Recommendations are rebuilt from parent Records;
  occurrence handling and researcher notes update that one portable owner.
- Action return and Record detail share one current Researcher Evaluation
  partition with exact Record revision and finalized-result fingerprint checks.
  An explicit Method-feedback action can start one separately paired,
  one-target Method-improvement Run with ordinary Method or Practice recovery.

## Research Guidance and integrations

- Research Guidance exposes Methods, Profiles & Practices, Collaboration,
  Sources & Integrations, and Recovery & Technical. It supports exact Markdown
  Method and Practice editing, one previous-edit recovery point, app-default
  restoration, simple or external Method registration, academic Profile
  editing, one Triptych collaboration policy, citation-style selection, and
  settled-version retention.
- Portable Method registration stores only a relative location or opaque
  machine-local marker. Absolute paths and security-scoped bookmarks remain in
  private Triptych-bound Application Support state.
- The built-in Zotero integration reads exact bibliographic metadata through
  Zotero Desktop's localhost API and can open a keyed Analysis in Zotero. An
  Analyze source may be a researcher-selected local regular file or exact
  Zotero attachment under a separately validated read boundary.
- The optional first-party Zotero MCP transport is separate from the built-in
  reader. Retrieval is read-only; guarded BibTeX/RIS import requires explicit
  request, exact dry run, one-shot confirmation, unchanged destination, and
  readback.
- The native app and CLI share Application capabilities and trust rules.
  Existing-note CLI mutation requires the current SHA-256; each invocation uses
  one snapshot runtime. The CLI cannot bypass Action, source, recovery, or
  Agent-session authority.
