# Implementation Status: Reachable Capabilities

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Current product reachability.

## Workspace and source authority

- Multiple registered Triptychs use independently selected Analyses, Topics,
  and Works vaults. Each window belongs to one Triptych; portable control state
  stays in `.scholium`, while machine-local and derived state stays in
  Application Support.
- Production validates Application Support plus one workspace registration
  before constructing a runtime. That owner contains Triptych membership,
  vault paths/bookmarks, and portable-container access. Damaged current data can
  be preserved and relinked, while unsupported schema, unsafe type, and I/O
  failures remain nonauthorizing. No temporary workspace fallback is reachable.
- An unavailable Triptych can remove only its machine-local registration
  without opening missing vaults or decoding an incompatible portable schema.
  Research folders, portable bytes, and unrelated registrations remain
  unchanged; an active runtime blocks removal.
- Existing portable control receives a read-only whole-bundle preflight before
  registration writes. A confirmed recovery archives the complete unsupported
  `.scholium` directory as one verified filesystem object, leaves all three
  vaults byte-unchanged, rebuilds current control state, and reopens the same
  Triptych; an active runtime blocks the archive.
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
  the same source claim. The seed accepts only optional `summary` and
  `keywords`; adding Metadata never inserts a YAML envelope.
- Portable Metadata Profile settings independently own each role's exact New
  Note YAML and About order plus per-source-type Analysis
  Agent requirements. One strict candidate validation and exact settings
  target identity plus revision guard the atomic save; uncertain or
  committed-with-refresh-warning outcomes are authoritatively reconciled.
  Unavailable or invalid settings remain nonauthorizing for managed creation,
  Agent requirements, and About rather than exposing defaults.
- Complete Metadata reads and compare-and-swap edits one identity-keyed
  `.scholium/note-metadata/v1/<uuid>.json` record, offers only role-valid
  managed fields, supports structured CreatorLists and date text, and leaves
  every Markdown byte unchanged. Record identity, role catalog, canonical
  readback, conflict, and uncertain commit are checked. Authored `summary` and
  `keywords` remain Source-owned; unknown YAML is preserved but nonsemantic.

## Notes, documents, and file operations

- New Note, New Folder, duplicate, UTF-8 Markdown import, rename, move, and
  native system-Trash deletion are reachable through shared Application
  capabilities. Stable Note identity follows confirmed moves, remains after
  system-Trash deletion, and reconciles external renames or Finder restoration.
- Note and Folder deletion prepare exact source/folder inventories, associated
  Critiques, active Discussions, and whole finished Records before confirmation.
  All source items move first; durable recovery then resumes Discussion, exact-
  fingerprint Record, Note Review, and machine-local evidence cleanup. A
  multi-Note Record is deleted as one object when any participant is affected.
- Settlement, source access, stable identity, Zotero binding, and Critique
  association are retained. External source absence without a Scholium plan
  refreshes source projections but does not delete Discussions or Records.
- The researcher CLI exposes the same Note system-Trash preparation and execute
  path with exact revision and explicit associated-Record consent. No prior
  holding-location or application-owned restore/delete command is reachable.
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
- Editor Undo, Run-bound Agent change evidence, direct Record Undo, and
  interrupted-write candidates remain distinct. Direct Undo and candidate
  restore each recheck the current revision and preserve evidence when
  replacement cannot be proven safe.
- Settle stores one replaceable researcher judgment for an exact saved revision.
  A Work can retain one attributed current Critique without changing the Work.

## Search, Connections, and Attention

- One Search capability serves the app, CLI, Research Records, and authenticated
  Research Context. It supports This Note, This Vault, and Triptych scope;
  Note and Record providers; lexical, structured-field, and direct-relation clauses;
  typed match reasons; Saved Searches; completion; and Explain Query.
- An undecodable Saved Search file can be explicitly archived byte-exactly and
  reset without changing a valid concurrent replacement or any vault.
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
- GUI Copy Handoff and Copy New Handoff deliver one Run locator and one-use
  Pairing Code for the installed CLI. The CLI also exposes `agent start`, which
  resolves a selected Triptych and current Analysis/Action directly, stores a
  process-bound Session credential locally, and requires no Pairing Code.
  A healthy CLI registry resolves UUID or unique-name selectors, including a
  UUID-shaped name; if that projection is absent or lacks a UUID, Application
  validates the UUID directly. First use creates and validates the current-user-
  only CLI home and Session directory. Both routes use the same protected
  Session for subsequent operations.
- A staged Analyze or other write Result completes after the Action's own
  transaction and Method checks. Analyze performs one bounded fidelity
  self-check inside its Method and records unresolved or unavailable limits in
  its Result; this does not create a Check Fidelity child or formal Fidelity
  evidence. Check Fidelity remains a separate read-only Action prepared only
  when the researcher explicitly requests an audit for an exact revision.
- `agent preflight-analysis` now resolves Analyze-only creation before the
  first consequential start. It returns the current Analyses vault and Settings
  revision, applicable and Agent-required Metadata fields, application-owned
  seed keys, exact destination, and path/identity/source/Trash state. Managed
  default places one strict filename at the Analyses root; the Agent wire has
  no subfolder selector. Researcher-selected placement uses an existing
  researcher-created Analysis. Only `ready` returns the exact
  `new_analysis` payload consumed by `agent start`; the CLI supplies no creation
  vault ID and creates no fallback name. The researcher-provided route carries
  no local-file path or source bytes and performs no title/keyword merge; the
  same route remains available when starting Analyze from an existing Analysis.
  Triptych plus `request_id` owns deterministic reserved Note and Run identities,
  while a separate logical-payload fingerprint rejects changed input after the
  portable creation phase. A machine-local reservation with no identity,
  source, or Run does not fabricate a Trash state or freeze old Settings; after
  current preflight, its request/creation/start fingerprint tuple can advance
  by exact CAS only while destination, route/binding, source type, existing
  metadata values, and academic purpose remain frozen; only newly required
  fields may be added. That reservation exists for both Zotero and researcher-
  provided creation. Exact
  replay resumes the frozen confirmed source/identity revision and same Run;
  it also requires the complete frozen start payload, including Settings
  revision and academic purpose. Concurrent identical starts coalesce, while
  changed committed input, terminal state, changed Zotero relationship, or
  missing source cannot reuse it as a new write.
- Bridge and preflight results distinguish `missing_required_fields`, path and
  identity occupation, identity with missing/system-Trash source,
  `settings_changed`, replay conflict, true `stale_run`, stale projection,
  missing source evidence, expired Session, permission refusal, timeout, and
  outcome unknown. Each structured result carries retry safety, request-
  identity reuse, and one next step; missing/trashed source exposes only the
  researcher-controlled Restore or explicitly distinct-new-destination
  branches, each with its own identity-reuse and next-step contract. These
  owner states no longer fall through to `operation_failed`.
  Outcome-unknown recovery is operation-specific and executable; it no longer
  points to a nonexistent generic request-status command. End response loss is
  non-retryable because the acknowledged Session may already be revoked; the
  Agent stops and reports for researcher inspection.
  Authenticated reload revalidates exact Target,
  Materials, and formal source state instead of returning a false-current
  packet. App
  restart still invalidates Session authority; Copy New Handoff re-pairs the
  unchanged unfinished Run instead of persisting a bearer credential. Parent
  re-pair or direct-Session replacement also revokes every child locator
  derived from that parent's old Session without revoking independent Runs.
- Action inspection revalidates an Agent-written target against the Run-owned
  current write/completion revision. A later unrelated external revision still
  fails stale, while ordinary Agent continuation remains available within the
  authenticated Run lifecycle.
- Research Context composes current Search, exact Note reads, direct Relations,
  Metadata, Records, the current Run's explicitly selected path-free source
  Material and frozen Zotero bibliographic snapshot, and explicitly proven
  researcher state. It does not search Materials or copy source bytes. Each
  returned item preserves owner, revision, locator, scope, currentness,
  evidential layer, retrieval reason, and limitation.
- An Analyze Run with a Zotero relationship can proceed without Scholium source
  access. The Run freezes bounded Zotero bibliographic context and the optional
  adapter; the external Agent may retrieve the paper through its own Zotero/MCP
  capability, while Scholium does not proxy or cache paper content.
  An explicit `researcher_provided` Run freezes no Zotero context or adapter even
  when the Analysis retains a portable relationship; it does not alter that
  relationship.
- A Run owns one bounded, expandable write set. Every mutation still requires a
  nonreusable operation capability and the exact repository transaction. One
  member's conflict does not widen authority or roll back confirmed siblings.
- Authenticated `create_note` freezes proven absence, Settings revision,
  reserved identity, and a seed-free Analysis field/shape/required plan.
  `modify_markdown` changes body only; `modify_source` accepts the complete
  authored Markdown source; `modify_metadata` changes only exact approved
  managed fields at the portable record revision and does not change source.
  GUI, researcher CLI, and Agent creation use the same managed
  creator. Run-bound Agent `create_note` remains idempotent for one request and forms a
  preimage-free `created` Record mutation only after source and identity
  jointly read back; partial or unreadable outcomes retain a durable creation
  recovery duty instead of guessing absence. Recovery may add or remove only
  the exact reserved identity; any other identity at the path, a binding on an
  identity that would be removed, or moved, changed, or unreadable state stops
  for separate researcher resolution.
- The `agent start` `new_analysis` route remains a bounded managed creation
  before the ordinary Analyze Run rather than a second lifecycle, while the
  new public preflight itself is read-only and claims no Run-bound
  `create_note` Record mutation. A portable identity with absent source is not
  silently rebuilt, overwritten, removed, or routed to a retry file. External
  packaged-Agent, full Finder Restore, and human conflict/recovery trials remain
  open.
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
- An explicitly researcher-started `researcher_provided` Check Fidelity Run
  exposes the exact checks plus a typed Citation constraint. Without a formal
  source envelope, Citation must be `unavailable`; Note YAML URLs remain
  authored metadata. The Fidelity Run forms its own schema-12 Record with
  explicit unverified evidence rather than a fabricated source claim; Analyze
  records the same limitation through its bounded self-check without creating
  a parent/child Fidelity pair.
- Authenticated Discuss Runs expose their frozen Dialogue Response Contract and
  the `agent discuss-reply` command. A stable Agent statement ID makes an
  outcome-unknown retry idempotent; the route appends only an attributed Agent
  turn to the active portable Discussion and grants no Note/Metadata mutation,
  Finish, evaluation, Undo, recovery, cross-Run, or arbitrary filesystem
  authority.
- Closing an Action presentation leaves unfinished work active. End cancels a
  no-write Action; confirmed changes require Result submission so their Record
  and Review cannot be lost, while unresolved recovery blocks End.

## Records, guidance, and integrations

- Comments, attributed Discussion turns, completed Action results, Context Use,
  confirmed effects, discrepancies, Fidelity outcome, Literature
  Recommendations, and atomic Researcher Response persist through strict
  schema-12 Records. Analyze Records retain one explicit Scholium-source,
  external-Zotero, or researcher-provided route without inventing source
  evidence. One cumulative schema-1 portable Note Review per Note owns
  exact observed revision, time, and covered `(Record ID, Note ID)` activities.
  Schema-12 Records reject every other schema, including schema 11; unsupported
  files remain byte-unchanged, unread, and nonauthorizing. Credentials,
  prompts, absolute paths, raw transport logs, and token counts are excluded.
- Confirmed Agent change comparison uses one exact byte-diff owner shared with
  Document conflict input. Application safely undoes complete selected
  documents from the first committed Agent baseline, including after a stable-
  identity rename. Undo is independent of Note Review; each document uses an
  independent ordinary revision-checked repository transaction.
- Workspace research snapshots derive Waiting, Running, and Needs Attention
  activities plus Note Review state and one-shot Result arrivals without
  persisting a second workflow owner or
  projecting credentials, source bytes, or tool traces.
- Local Execution now stores a stable Run/Triptych/Note-participation/authority
  envelope around its evolving private payload. System Trash can scope valid
  envelopes without decoding an unsupported payload; a fingerprint-bound alert
  archives exact unreadable payload or unwrapped legacy bytes before retrying
  preparation. Valid-envelope recovery is limited to selected participating
  Notes while an unscoped opaque file still fails closed store-wide. Once a
  portable Record exists, the payload compacts to a terminal receipt and the
  envelope becomes terminal. Diff and direct Undo use the portable Record plus
  `(Run ID, Note ID)` Agent evidence instead.
- The Triptych-keyed Research Records window and Search consume the same Record
  provider. Reading Leads are a rebuildable projection of recommendation
  occurrences; handling and researcher notes update the parent Record.
- Research Guidance supports Method and Practice registration and exact
  expected-revision editing, explicit default restoration, academic
  Profiles, one Triptych collaboration policy, citation style, external
  locators, and installed CLI controls.
- Invalid machine-local Method locators expose an exact archive-and-reset
  operation; portable research configuration and vault files remain unchanged.
- Built-in Zotero access reads local bibliographic metadata, searches exact
  user/group library items for researcher selection, revision-checks portable
  Analysis set/rebind/clear, and opens a keyed Analysis in Zotero. An eligible authenticated Analysis Run with frozen Zotero
  context receives the exact release-managed Zotero Integration Adapter; Runs
  without that context receive none, and adapter delivery grants no capability
  or write authority. Separately authorized Agent
  `set_zotero_binding`/`clear_zotero_binding` use their own strict intent,
  bridge/CLI route, one-use capability, binding-revision check, and Local
  Execution ledger; they cannot write Markdown, Metadata, or Zotero. The optional Zotero MCP is a separate Agent transport;
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
  The installed CLI now owns explicit `scholium update --check` and
  `scholium update` commands; they verify the official archive, checksum,
  release provenance, architecture, and signature before a recoverable
  user-local replacement, and never edit PATH or shell profiles.
- The first-launch preparation prompt uses a CLI read-only Skill-source
  manifest and deterministic workspace-bootstrap candidate. The manifest
  exposes only the installed Core Protocol and enabled Triptych-managed Method
  folders, excluding machine-local registrations. The Agent creates only its
  supported host's project-level directory symlinks, reuses exact links, and
  stops on every conflicting path; Scholium neither detects the host nor
  creates or verifies those links.
