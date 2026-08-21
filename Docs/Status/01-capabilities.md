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
- Editor Undo, Run-bound Agent change evidence, direct Record Undo, and
  interrupted-write candidates remain distinct. Direct Undo and candidate
  restore each recheck the current revision and preserve evidence when
  replacement cannot be proven safe.
- Settle stores one replaceable researcher judgment for an exact saved revision.
  A Work can retain one attributed current Critique without changing the Work.

## Search, Connections, and Attention

- One Search capability serves the app, CLI, Research Records, and authenticated
  Research Context. It supports This Note, This Vault, and Triptych scope;
  Note and Record providers; lexical, Property, and direct-relation clauses;
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
- `agent start` additionally accepts the strict Analyze-only `new_analysis`
  shape. It supplies one exact path and typed Analysis creation metadata, with
  either an explicit Zotero library/item relationship or the
  `researcher_provided` source route. The Application uses the common managed
  creator, reads back source plus stable identity, establishes the Zotero
  relationship when present, and then enters the ordinary target-based Analyze
  Run. The researcher-provided route carries no local-file path or source bytes
  through Scholium and performs no title/keyword merge; the same explicit route
  is available when starting Analyze from an existing Analysis.
  The complete request owns deterministic reserved Note and Run identities:
  exact replay resumes the same unfinished Run with a replacement Session,
  while changed input, a terminal Run, or a changed researcher-owned Zotero
  relationship cannot reuse it. A request-owned machine-local creation phase
  makes a binding write retryable only when the portable owner proved no commit;
  otherwise replay accepts exact readback or returns `replay_conflict` without
  writing. A stale derived projection preserves the source/identity commit and
  returns a structured non-duplication recovery result.
- Bridge failures distinguish replay conflict, true `stale_run`, stale
  projection, missing source evidence, expired Session, permission refusal,
  timeout, and outcome unknown. Authenticated reload revalidates exact Target,
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
  Properties, Records, the current Run's explicitly selected path-free source
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
  authored Markdown source; `modify_properties` changes only exact approved
  top-level keys. GUI, researcher CLI, and Agent creation use the same managed
  creator. Run-bound Agent `create_note` remains idempotent for one request and forms a
  preimage-free `created` Record mutation only after source and identity
  jointly read back; partial or unreadable outcomes retain a durable creation
  recovery duty instead of guessing absence. Recovery may add or remove only
  the exact reserved identity; any other identity at the path, a binding on an
  identity that would be removed, or moved, changed, or unreadable state stops
  for separate researcher resolution.
- The `agent start` `new_analysis` route is a bounded creation preflight before
  the ordinary Analyze Run rather than a second parallel Run lifecycle. An
  unrelated or changed request is rejected once the path has a portable
  identity; exact request replay resumes that identity and Run. The
  route does not claim a Run-bound `create_note` Record mutation for that
  preflight. External packaged-Agent, restart, conflict/recovery, and source-
  fidelity trials remain open.
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
  authored metadata. The Fidelity Run forms its own schema-11 Record with
  explicit unverified evidence rather than a fabricated source claim; Analyze
  records the same limitation through its bounded self-check without creating
  a parent/child Fidelity pair.
- Authenticated Discuss Runs expose their frozen Dialogue Response Contract and
  the `agent discuss-reply` command. A stable Agent statement ID makes an
  outcome-unknown retry idempotent; the route appends only an attributed Agent
  turn to the active portable Discussion and grants no Note/Property mutation,
  Finish, evaluation, Undo, recovery, cross-Run, or arbitrary filesystem
  authority.
- Closing an Action presentation leaves unfinished work active. End cancels a
  no-write Action; confirmed changes require Result submission so their Record
  and Review cannot be lost, while unresolved recovery blocks End.

## Records, guidance, and integrations

- Comments, attributed Discussion turns, completed Action results, Context Use,
  confirmed effects, discrepancies, Fidelity outcome, Literature
  Recommendations, and atomic Researcher Response persist through strict
  schema-11 Records. Analyze Records retain one explicit Scholium-source,
  external-Zotero, or researcher-provided route without inventing source
  evidence. One cumulative schema-1 portable Note Review per Note owns
  exact observed revision, time, and covered `(Record ID, Note ID)` activities.
  Schema-11 Records reject schemas 1 through 10 rather than migrating them. Credentials,
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
- Once a portable Record exists, schema-16 Local Execution compacts to a
  terminal receipt and deletes its prepared instructions, Bounded Write Set,
  extensions, write ledgers, and conflict rows. Diff and direct Undo use the
  portable Record plus `(Run ID, Note ID)` Agent evidence instead.
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
- The first-launch preparation prompt uses a CLI read-only Skill-source
  manifest and deterministic workspace-bootstrap candidate. The manifest
  exposes only the installed Core Protocol and enabled Triptych-managed Method
  folders, excluding machine-local registrations. The Agent creates only its
  supported host's project-level directory symlinks, reuses exact links, and
  stops on every conflicting path; Scholium neither detects the host nor
  creates or verifies those links.
