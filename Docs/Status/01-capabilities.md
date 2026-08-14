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
- Live app activation can publish the selected Vault's authoritative source,
  metadata, and stable identities first, then replace that explicit opening
  phase with one complete three-Vault generation through the existing refresh
  owner. Document reads are usable immediately; Search and Research Actions
  fail closed until Graph, Search, and research projections are complete.
- Exact Markdown bytes remain authoritative. Repository reads and mutations
  enforce containment, regular-file identity, expected revisions, coordinated
  system replacement, exact canonical readback, conflict, and recoverable
  uncertainty. Filesystem metadata and machine-local housekeeping are not save
  predicates. Derived refresh failure cannot turn a proven source commit into a
  failed mutation.
- Frontmatter edits are bounded to a uniquely proven range and preserve all
  unrelated bytes. Unsupported source shapes remain editable in Source.
- Managed New Note copies the selected role's exact validated Settings seed in
  the same source claim. YAML-free first-Property insertion is a separate
  explicit expected-revision transaction and never writes empty delimiters.
- Portable Properties settings independently own each role's exact New Note
  YAML and About order plus per-source-type Analysis
  Agent requirements. One strict candidate validation and exact settings
  target identity plus revision guard the atomic save; uncertain or
  committed-with-refresh-warning outcomes are authoritatively reconciled.
  Unavailable or invalid settings remain nonauthorizing for managed creation,
  Agent requirements, and About rather than exposing defaults.
- Complete Properties retains every safely bounded present top-level value,
  derives direct editability from exact source rather than Settings, marks
  unsupported shapes read-only, recommends only applicable missing canonical
  keys, supports structured CreatorLists and authored date text, and
  removes a property only through the same targeted expected-revision write.

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
  caret-anchored Wikilink and Analysis Reference suggestions, Document
  Find/Replace, Document statistics, native spelling routes, and nonmutating
  search-result reveal.
- Image Import copies selected or pasted bytes exactly into the current
  vault's UUID-scoped `Attachments` folder and inserts a relative Markdown
  destination. Image Index retains the selected absolute path without copying;
  its read-only bookmark is machine-local, and a moved, missing, stale,
  or inaccessible path produces a reminder without repair or mutation.
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
- Plain and quoted canonical `summary` scalars enter the same Note Search with
  exact match ranges; block, folded, duplicate, or range-ambiguous values remain
  absent from that projection. Research Context identifies the current Note
  revision's writer as unknown unless a separate existing operation or Record
  owner proves an actor; it does not infer attribution or keep writer history.
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
  Properties, Records, the current Run's explicitly selected path-free source
  Material and frozen Zotero bibliographic snapshot, and explicitly proven
  researcher state. It does not search Materials or copy source bytes. Each
  returned item preserves owner, revision, locator, scope, currentness,
  evidential layer, retrieval reason, and limitation.
- A Run owns one bounded, expandable write set. Every mutation still requires a
  nonreusable operation capability and the exact repository transaction. One
  member's conflict does not widen authority or roll back confirmed siblings.
- Authenticated `create_note` freezes proven absence, Settings revision,
  reserved identity, and a seed-free Analysis field/shape/required plan.
  `modify_markdown` changes body only; `modify_properties` changes only exact
  approved top-level keys. GUI, researcher CLI, and Agent creation use the same
  managed creator. Agent creation is idempotent for one request and forms a
  checkpoint-free `created` Record mutation only after source and identity
  jointly read back; partial or unreadable outcomes retain a durable creation
  recovery duty instead of guessing absence. Recovery may add or remove only
  the exact reserved identity; any other identity at the path, a binding on an
  identity that would be removed, or moved, changed, or unreadable state stops
  for separate researcher resolution.
  Linked reconciliation coordinates source mutation, performs a final joint
  readback, and treats an already-settled write as cleanup-only. Unlinked
  records never claim Agent reconciliation.
- Result submission validates the frozen academic contract and Context Use;
  Application adds machine facts from actual transaction outcomes. Finalization
  is idempotent and waits for writes and recovery duties to converge. Continue
  Research creates a separate Run, rechecks selected source Materials as
  current, changed, missing, or unavailable. Parent-Run Researcher State
  references are stripped from the child handoff; a typed flag requires the
  child to query current researcher-owned facts in its own Run scope.
- Closing an Action presentation leaves unfinished work active. End cancels a
  no-write Action; confirmed changes require Result submission so their Record
  and Review cannot be lost, while unresolved recovery blocks End.

## Records, guidance, and integrations

- Comments, attributed Discussion turns, completed Action results, Context Use,
  confirmed effects, discrepancies, Fidelity outcome, Literature
  Recommendations, and atomic Researcher Response persist through strict
  schema-9 Records. One cumulative schema-1 portable Note Review per Note owns
  exact observed revision, time, and covered `(Record ID, Note ID)` activities.
  Schema-9 Records reject schemas 1 through 8 rather than migrating them. Credentials,
  prompts, absolute paths, raw transport logs, and token counts are excluded.
- Confirmed Agent change comparison uses one exact byte-diff owner shared with
  Document conflict input. Application safely undoes complete selected
  documents from the first committed Agent baseline, including after a stable-
  identity rename. Undo is independent of Note Review; each restore remains an
  independent checkpointed source transaction.
- Workspace research snapshots derive Waiting, Running, and Needs Attention
  activities plus Note Review state and one-shot Result arrivals without
  persisting a second workflow owner or
  projecting credentials, checkpoint IDs, source bytes, or tool traces.
- The Triptych-keyed Research Records window and Search consume the same Record
  provider. Reading Leads are a rebuildable projection of recommendation
  occurrences; handling and researcher notes update the parent Record.
- Research Guidance supports Method and Practice registration and exact editing,
  one recovery point per edited file, explicit default restoration, academic
  Profiles, one Triptych collaboration policy, citation style, external
  locators, and settled-version retention.
- Built-in Zotero access reads local bibliographic metadata, searches exact
  user/group library items for researcher selection, revision-checks portable
  Analysis set/rebind/clear, and opens a keyed Analysis in Zotero. An eligible authenticated Analysis Run with frozen Zotero
  context receives the exact release-managed Zotero Integration Adapter; Runs
  without that context receive none, and adapter delivery grants no capability
  or write authority. Separately authorized Agent
  `set_zotero_binding`/`clear_zotero_binding` use their own strict intent,
  bridge/CLI route, one-use capability, binding-revision check, and Local
  Execution ledger; they cannot write Markdown, Properties, or Zotero. The optional Zotero MCP is a separate Agent transport;
  guarded imports require an exact request, dry run, confirmation, unchanged
  destination, and readback.
- The native app and CLI share Application capabilities. CLI delivery cannot
  bypass source, Action, Session, recovery, or Record authority.
- First-launch Agent preparation and Research Guidance Settings copy the same
  fixed official installation instruction for the independently packaged CLI.
  The App has no CLI installer or machine-status owner and never embeds,
  inspects, executes, updates, or removes the CLI. The external Agent may place
  only the release executable and resource bundle under `~/.local/bin`, then
  verifies the required version fields while ignoring unrelated JSON fields.
