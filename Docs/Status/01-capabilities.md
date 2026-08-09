# Implementation Status: Reachable Capabilities

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Current product reachability.

## Workspace and source authority

- Multiple registered Triptychs use independently selected Analyses, Topics,
  and Works vaults. Each window belongs to one Triptych; portable control state
  stays in `.scholium`, while machine-local and derived state stays in
  Application Support.
- Production validates Application Support and the workspace registry before
  constructing a runtime. Malformed current-schema registry data can be
  preserved and relinked; unsupported schema and I/O failures remain
  nonauthorizing. No temporary workspace fallback is reachable.
- Exact Markdown bytes remain authoritative. Repository reads and mutations
  enforce containment, regular-file identity, expected revisions, atomic
  replacement, metadata preservation, readback, conflict, and recoverable
  uncertainty. Derived refresh failure cannot turn a proven source commit into
  a failed mutation.
- Frontmatter edits are bounded to a uniquely proven range and preserve all
  unrelated bytes. Unsupported source shapes remain editable in Source.

## Notes, documents, and lifecycle

- New Note, New Folder, duplicate, UTF-8 Markdown import, rename, move, Set
  Aside, Move to Trash, Put Back, and permanent deletion are reachable through
  shared Application capabilities. Stable Note identity follows confirmed
  moves and reconciled external renames.
- Review, Edit, and Source share one retained document session. Autosave,
  selection, focus, scroll, composition, Undo, conflict, external-change
  handling, and recovery remain bound to the same exact source.
- The editor supports the declared Markdown dialect, semantic Callouts, tables,
  footnotes, mathematics, Wiki and Vector Links, task items, formatting,
  caret-anchored suggestions, and nonmutating search-result reveal.
- Editor Undo, Triptych checkpoints, Before Agent Work recovery, settled
  revision pins, and interrupted-write candidates remain distinct. Restore
  rechecks the current revision and preserves evidence when replacement cannot
  be proven safe.
- Settle stores one replaceable researcher judgment for an exact saved revision.
  A Work can retain one attributed current Critique without changing the Work.

## Search, Connections, and Attention

- One Search capability serves the app, CLI, Research Records, and authenticated
  Research Context. It supports This Note, This Vault, and Triptych scope;
  Note and Record providers; lexical, Property, and direct-relation clauses;
  typed match reasons; Saved Searches; completion; and Explain Query.
- This Note searches the live editor snapshot. Other results remain bound to
  provider, generation, fingerprint, and source freshness. Stale or incompatible
  results do not navigate.
- One graph owner resolves neutral, support, opposition, and undirected
  incompatibility relations. Neutral links and transitive paths remain
  Connections rather than philosophical evidence.
- Attention derives recoverable structural and source-currency conditions.
  Its actions affect presentation or begin an explicit Research Action; they do
  not silently alter research content or assert a philosophical verdict.

## Research Actions and local Agent collaboration

- The closed Platform catalog exposes the role-valid Discuss, Analyze,
  Synthesize, Write, Critique, Check Fidelity, and optional hidden Manuscript
  Actions. Preparation freezes the target, request, source and focal material,
  Method, Practices, Profile, Result Contract, collaboration policy, read scope,
  and initial Bounded Write Set member.
- Copy Handoff and Copy New Handoff deliver one Run locator and one-use Pairing
  Code for the installed CLI. Pairing creates a process-bound local Connection
  Session; protected operations require that Session.
- Research Context composes current Search, exact Note reads, direct Relations,
  Properties, Records, source references, and explicitly proven researcher
  state. Each returned item preserves owner, revision, locator, scope,
  currentness, evidential layer, retrieval reason, and limitation.
- A Run owns one bounded, expandable write set. Every mutation still requires a
  nonreusable operation capability and the exact repository transaction. One
  member's conflict does not widen authority or roll back confirmed siblings.
- Result submission validates the frozen academic contract and Context Use;
  Application adds machine facts from actual transaction outcomes. Finalization
  is idempotent and waits for writes and recovery duties to converge. Continue
  Research creates a separate Run.
- Closing an Action presentation leaves unfinished work active. Explicit End
  Action or End Discussion revokes new authority while retaining confirmed
  changes, conflicts, Records, and recovery duties.

## Records, guidance, and integrations

- Comments, attributed Discussion turns, completed Action results, Context Use,
  confirmed effects, discrepancies, Fidelity outcome, Literature
  Recommendations, and Researcher Evaluation persist through their declared
  portable Record owners. Credentials, prompts, absolute paths, raw transport
  logs, and token counts are excluded.
- The Triptych-keyed Research Records window and Search consume the same Record
  provider. Reading Leads are a rebuildable projection of recommendation
  occurrences; handling and researcher notes update the parent Record.
- Research Guidance supports Method and Practice registration and exact editing,
  one recovery point per edited file, explicit default restoration, academic
  Profiles, one Triptych collaboration policy, citation style, external
  locators, and settled-version retention.
- Built-in Zotero access reads local bibliographic metadata and opens a keyed
  Analysis in Zotero. The optional Zotero MCP is a separate Agent transport;
  guarded imports require an exact request, dry run, confirmation, unchanged
  destination, and readback.
- The native app and CLI share Application capabilities. CLI delivery cannot
  bypass source, Action, Session, recovery, or Record authority.
