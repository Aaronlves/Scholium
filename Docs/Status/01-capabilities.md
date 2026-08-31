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
- Managed New Note always writes `summary: null` then `keywords: []` in one
  fixed authored-YAML scaffold. Typed GUI/CLI/Agent creation may populate those
  values; adding Metadata never changes the YAML envelope.
- Portable Metadata settings own stable custom field definitions for Analyses,
  Topics, and Works. Key and value shape are permanent; labels, descriptions,
  append-only controlled choices, and reversible active/archived lifecycle are
  manageable. Archived fields retain existing values and Search while leaving
  new-value, About, and Agent selection. The current workspace-scoped resolved catalog combines those
  definitions with built-ins and governs Metadata validation, Search, Library
  filters, About, Complete Metadata, and Agent field plans. About visibility
  and per-source-type Analysis Agent preferences are separate selections;
  definitions do not select either one and every field remains optional. One
  strict candidate validation and exact settings
  target identity plus revision guard the atomic save; uncertain or
  committed-with-refresh-warning outcomes are authoritatively reconciled.
  Unavailable or invalid settings remain nonauthorizing for custom fields,
  preferences, and About, but fixed managed creation does not consume them as
  authority.
- Complete Metadata reads and compare-and-swap edits one identity-keyed
  `.scholium/note-metadata/v1/<uuid>.json` record, offers only role-valid
  managed fields, supports structured CreatorLists and date text, and leaves
  every Markdown byte unchanged. Record identity, role catalog, canonical
  readback, conflict, and uncertain commit are checked. Authored `summary` and
  `keywords` remain Source-owned; unknown YAML is preserved but nonsemantic.
- Researcher CLI Metadata read/set/remove uses those same public Application
  capabilities and its own exact record fingerprint. A Metadata-only commit
  carries one record delta through the existing refresh owner with zero source
  enumeration/read/parse/projection and zero portable Metadata catalog reads.
  Invalid portable records expose a confirmed exact-file archive bound to one
  unchanged filename and fingerprint; neighbors and source remain untouched.

## Notes, documents, and file operations

- New Note, New Folder, duplicate, UTF-8 Markdown import, rename, move, and
  native system-Trash deletion are reachable through shared Application
  capabilities. Stable Note identity follows confirmed moves, remains after
  system-Trash deletion, and reconciles external renames or Finder restoration.
- Per-window Library mutation state, import cancellation, Trash retry, Workspace
  access recovery, and Zotero operations now have separate bounded owners.
  `WindowModel` composes their capabilities and publishes committed
  cross-feature effects; it no longer proxies their operation APIs or recovery
  state.
- Note and Folder deletion prepare exact source/folder inventories, associated
  Critiques, active Discussions, and whole finished Records before confirmation.
  All source items move first; durable recovery then resumes Discussion, exact-
  fingerprint Record, and machine-local evidence cleanup. A
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
- Settle stores one replaceable researcher judgment for an exact saved revision
  and the current confirmed Agent-change activities. A Work can retain one
  attributed current Critique without changing the Work.

## Search, Connections, and Attention

- One Search capability serves the app, CLI, Research Records, and authenticated
  Research Context. It supports This Note, This Vault, and Triptych scope;
  Note and Record providers; lexical, structured-field, and direct-relation clauses;
  typed match reasons; Saved Searches; completion; and Explain Query.
  Note completion receives scope-authorized property keys and controlled values
  without creating a second query interpretation.
- Related-Content Retrieval contract 3 accepts an ephemeral exact Triptych Note
  plus bounded selected-passage and research-request focuses. Search returns
  separate exact title/alias and lexical Analysis/Topic channels; lexical
  ordering prefers selected-passage matches, then research-request matches,
  then whole-Note matches before existing field and BM25 ordering. A typed role
  restriction makes Topic Synthesize Analysis-only. Graph owns a separate
  direct-Connection channel. Invalid, partial, stale, unavailable,
  and empty results remain distinct; no seed, response, score, source text, or
  recommendation cache is persisted.
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
- Unknown valid YAML remains exact authored Source but contributes no Search
  field, Library filter, Link/Relation behavior, Agent context, identity,
  workflow role, title, alias, or other Scholium semantic projection.
- One graph owner resolves neutral, support, opposition, and undirected
  incompatibility relations. Neutral links and transitive paths remain
  Connections rather than philosophical evidence.
- Attention derives recoverable structural and source-currency conditions.
  Its actions affect presentation or begin an explicit Research Action; they do
  not silently alter research content or assert a philosophical verdict.

## Research Actions and local Agent collaboration

- The closed Platform catalog exposes the role-valid Discuss, Analyze,
  Synthesize, Write, Critique, and Check Fidelity Actions. Preparation freezes
  the target, request, source and focal material,
  Action Skill registration revision and resolved folder path, Profile, Result
  Contract, read scope, and initial Run Activity Ledger member.
- Run requests, completions, and required snapshots use that same exact Action
  identity. No compressed Function enum, mapping adapter, optional snapshot
  fallback, or old-shape decoder remains reachable.
- GUI Copy Handoff and Copy New Handoff deliver one nonauthorizing Triptych
  selector, Run locator, one-use Pairing Code, and concise conditional
  first-workspace Skill-registration instruction for the installed CLI.
  `scholium agent` is the only external-
  Agent Action lifecycle; the prior public `action` preparation family is no
  longer reachable. `agent start`
  resolves a selected Triptych and current Analysis/Action directly, stores a
  process-bound Session credential locally, and requires no Pairing Code.
  It carries the complete typed academic-input map and validates every current
  custom required Profile field before creating a Run or new Analysis.
  A healthy CLI registry resolves UUID or unique-name selectors, including a
  UUID-shaped name; if that projection is absent or lacks a UUID, Application
  validates the UUID directly. First use creates and validates the current-user-
  only the machine-state parent and protected `Agent Sessions` directory before
  Session creation or Pairing. If credential persistence then fails, the CLI asks Application to authenticate
  and revoke that exact Session while retaining the Run; confirmed cleanup
  returns a same-Run re-pair route, while unknown cleanup stops and reports.
  Both routes use the same protected Session for subsequent operations. `start`
  returns its receipt with initial authenticated Action context; `pair` returns
  that Action context selected by the Application-owned Run owner. The public
  `agent context` command is removed; `reload`
  remains recovery and current-state revalidation. Authenticated Context
  supplies the minimum project-discovered `required_skills`, frozen Action
  registration revision, and no Skill prose or path. That set is not an allowlist for
  other non-Scholium Skills. Context also supplies fillable typed
  `next_actions` for all six Actions: required exact-
  Target/Fidelity reads, bounded Search and supporting-evidence queries when
  needed, Discuss reply/finish, each ready bounded write when needed, and every
  non-Discuss Result submission. Result templates omit optional academic fields
  while the frozen Result Contract retains them. Calling a query does not itself
  prove reliance or support and creates no reading history or source-use testimony.
- Research Context request/response schema 7 removes Agent-authored eligibility
  from every query clause. Application derives each response item's
  `research_evidence` or `reference_only` status from exact content kind and
  currentness; old request fields and earlier schemas fail closed. The
  single-clause `inspect_materials` route carries bounded path-free base64
  pages from the exact Run-frozen binary source, with whole-source/page
  fingerprints and prior-page-bound continuation.
- Authenticated Context schema 18 gives Work Write and Critique Runs
  a non-evidential `recommended_reading` directory computed from their exact
  current Work source, selected passage, and research request. Application
  merges direct Connection, exact title/alias mention, and weighted lexical
  channels in fixed order while retaining every typed reason. Current
  Analysis/Topic candidates receive chunked, ready-to-send exact-read queries;
  stale or unavailable recommendation retains ordinary Search and no executable
  candidate. Topic Synthesize receives Analysis-only candidates. Search-capable
  Runs can call `agent related` with one to four exact names; Application
  dynamically combines per-seed channel ranks and returns typed reasons without
  source or score. There is no Works consumer or UI.
- A confirmed Agent write advances the Activity Ledger member's current
  revision. Synthesize and Write reload, Recommended Reading, and the supplied
  exact-Target reread use that self-written revision before Result finalization;
  an untracked external edit still returns `stale_run`.
- A staged Analyze or other write Result completes after the Action's own
  transaction and Method checks. Analyze performs one bounded fidelity
  self-check inside its Method and records unresolved or unavailable limits in
  its Result; this does not create a Check Fidelity child or formal Fidelity
  evidence. Check Fidelity remains a separate read-only Action prepared only
  when the researcher explicitly requests an audit for an exact revision.
- `agent preflight-analysis` now resolves Analyze-only creation before the
  first consequential start. It returns the current Analyses vault, applicable
  managed fields, optional Settings-preferred fields, fixed YAML fields, exact
  destination, and path/identity/source/Trash state. Managed
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
  source, or Run does not fabricate a Trash state; after current preflight, its
  request/creation/start fingerprint tuple can advance by exact CAS only while
  destination, route/binding, authored YAML, source type, managed values, and
  typed academic inputs remain frozen. Settings preference changes grant no
  authority. That reservation exists for both Zotero and researcher-
  provided creation in its own machine-local store and lock, independently of
  the Run-only Local Execution store and system-Trash authority. Exact
  replay resumes the frozen confirmed source/identity revision and same Run;
  it also requires the complete frozen start payload, including academic
  inputs. Concurrent identical starts coalesce, while
  changed committed input, terminal state, changed Zotero relationship, or
  missing source cannot reuse it as a new write.
- App and standalone CLI now communicate over `127.0.0.1` only after a mutual
  nonce-bound HMAC handshake using a rotated secret in one `0700` per-user
  bridge directory and `0600` regular file. Both sides validate current-user
  ownership and mode, the secret never crosses the transport, and Application
  decodes no request before authentication. The App creates and rotates this
  process-generation secret; a CLI or Agent-created value is not trusted. The
  packaging boundary requires the declared sandbox privileges, accepts only
  Apple-injected signing identity metadata, and retains the network-server
  entitlement proved necessary for that listener. XPC remains a possible future topology only with an
  explicitly installed helper/Mach service rather than the current standalone
  CLI packaging.
- Bridge and preflight results distinguish path and identity occupation,
  identity with missing/system-Trash source, replay conflict, true `stale_run`, stale projection,
  missing source evidence, expired Session, unsupported or stale activity, timeout, and
  outcome unknown. Each structured result carries retry safety, request-
  identity reuse, and one next step; missing/trashed source exposes only the
  researcher-controlled Restore or explicitly distinct-new-destination
  branches, each with its own identity-reuse and next-step contract. These
  owner states no longer fall through to `operation_failed`.
  Outcome-unknown recovery is operation-specific and executable; it no longer
  points to a nonexistent generic request-status command. End or Discussion-
  Finish response loss is non-retryable because the acknowledged Session may
  already be revoked; the Agent stops and reports for researcher inspection.
  Authenticated reload revalidates exact Target,
  Materials, and formal source state instead of returning a false-current
  packet. App
  restart still invalidates Session authority; Copy New Handoff re-pairs the
  unchanged unfinished Run instead of persisting a bearer credential. Parent
  re-pair or direct-Session replacement also revokes every child locator
  derived from that parent's old Session without revoking independent Runs.
  Credentials carry the Application-issued Session expiry. The protected CLI
  store automatically prunes only exact expired current-schema files and leaves
  unknown or unsafe entries untouched and nonauthorizing. Finalized Results
  need no `end`: write authority is revoked immediately while the original
  Session expiry bounds idempotent confirmation and Continue Research. A
  created Continue response attaches the child to that Session and returns the
  child's complete authenticated Context and fresh `required_skills` without
  another pair or initial reload.
- Researcher **Follow Up…** is a separate continuation owner. It starts from a
  finalized Record or Result Ready notification, re-resolves a normal current
  Action request, creates a fresh Run/handoff, and persists `.followUp` lineage
  without inheriting the parent Session, Skill/Profile, or Activity Ledger,
  Research Context, or Agent judgment. Agent autonomous Continue Research and
  its authenticated Session path remain unchanged.
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
- A Run owns one bounded, automatically expandable Activity Ledger. Registering
  another valid target records it without a researcher permission sheet. Every
  mutation still requires a nonreusable transaction lease and the exact
  repository transaction. Ledger schema 7 gives members no independent
  wall-clock expiry, so Session rotation or re-pairing preserves the unfinished
  Run's tracked activity while every operation still revalidates its current
  revision. One member's conflict does not roll back confirmed siblings.
- Authenticated `create_note` freezes proven absence, reserved identity, the
  fixed YAML scaffold, and an optional Analysis field/shape/preference plan.
  `modify_markdown` changes body only; `modify_source` accepts the complete
  authored Markdown source; `modify_metadata` changes only exact approved
  managed fields at the portable record revision and does not change source.
  Body authority now accepts a closed, diagnostically invalid YAML envelope
  because its body boundary is exact and preserves those frontmatter bytes;
  an unclosed delimiter still fails closed.
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
- Result submission validates the frozen academic contract and any formal
  Fidelity outcomes;
  Application adds machine facts from actual transaction outcomes. Finalization
  is idempotent and waits for writes and recovery duties to converge. Continue
  Research creates a separate Run, rechecks selected source Materials as
  current, changed, missing, or unavailable. Parent-Run Researcher State
  references are stripped from the child handoff; a typed flag requires the
  child to query current researcher-owned facts in its own Run scope.
- An explicitly researcher-started `researcher_provided` Check Fidelity Run
  exposes the exact checks plus a typed Citation constraint. Without a formal
  source envelope, Citation must be `unavailable`; Note YAML URLs remain
  authored metadata. The Fidelity Run forms its own schema-18 Record with
  explicit unverified evidence rather than a fabricated source claim; Analyze
  records the same limitation through its bounded self-check without creating
  a parent/child Fidelity pair.
- Authenticated Discuss Runs expose their frozen Dialogue Response Contract and
  one `agent discuss-reply` completion command. A stable Agent statement ID
  makes outcome-unknown retry idempotent. The first successful reply atomically
  retains the attributed Agent response, forms the portable Discussion Record,
  completes the same Run, and finalizes the Session. There is no separate
  Finish or Result body. The route grants no Note/Metadata mutation,
  evaluation, Undo, recovery, cross-Run, or arbitrary filesystem authority and
  implies no researcher acceptance.
- Closing an Action presentation leaves unfinished work active. End cancels a
  no-write Action; confirmed changes require Result submission so their Record
  and Review cannot be lost, while unresolved recovery blocks End.

## Records, guidance, and integrations

- Comments, attributed Discussion turns, completed Action results, explicit
  frozen Material participants, confirmed effects, discrepancies, Fidelity outcome, Literature
  Recommendations, and parent-owned Method Feedback persist through strict
  schema-18 Records. Dynamic reading and source-use testimony are not persisted;
  the Action identity retains only Application-established frozen Material Note
  IDs so selected Materials remain distinct from confirmed-change-only
  participants. In-text citations remain optional academic content. Analyze Records retain one explicit Scholium-source,
  external-Zotero, or researcher-provided route without inventing source
  evidence. One schema-2 portable Settlement per Note owns exact saved revision,
  time, researcher judgment, and covered `(Record ID, Note ID)` Agent-change
  activities. Schema-18 Records reject every earlier schema; unsupported
  files remain byte-unchanged, unread, and nonauthorizing. Schema 18 also
  retains each terminal Agent activity's exact portable target, operation,
  outcome, and typed source, managed-Metadata, or Zotero-binding revisions after
  the machine-local write ledgers compact. Credentials,
  prompts, absolute paths, raw transport logs, and token counts are excluded.
- Confirmed Agent change comparison uses one exact byte-diff owner shared with
  Document conflict input. Application safely undoes complete selected
  documents from the first committed Agent baseline, including after a stable-
  identity rename. Undo is independent of Settlement; each document uses an
  independent ordinary revision-checked repository transaction.
- Workspace research snapshots derive Waiting, Running, Needs Attention,
  Result Ready, and Recovery Required activity inputs plus Settlement requirements
  and one-shot Result arrivals without
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
- Strict schema-18 prose strings now remain byte-for-byte opaque through
  submission, validation, storage, hashing, Search, and CLI reading while a
  disposable Contracts projection recognizes the closed Record scholarly-
  markup subset. Navigation reuses current fail-closed Note/heading/block
  lookup without emitting Connections or another durable relation owner.
- The standalone CLI can list every readable finished Record related to one
  exact stable Note UUID and read one readable complete Record by UUID. Both
  routes use the immutable Application projection and return exact portable-byte
  fingerprints. List output names complete versus partial corpus state and
  omits only unreadable Record files; an unresolved target in a partial corpus
  and completeness-sensitive operations still fail closed instead of scanning
  `.scholium` or guessing.
- Research Guidance supports one Action-to-user-Skill-folder registration,
  folder reveal/assignment, bundled one-time user-copy provisioning, academic
  Profiles, citation style, external
  locators, and installed CLI controls. Scholium does not read, validate, edit,
  restore, or revision-track user Skill files. Machine-local folders retain one
  read-only bookmark for availability and external project discovery.
- Invalid machine-local Skill locators expose an exact archive-and-reset
  operation; portable research configuration and vault files remain unchanged.
- Built-in Zotero access reads local bibliographic metadata, searches exact
  user/group library items for researcher selection, keeps same-key libraries
  distinct, and opens a keyed Analysis in Zotero. A complete item-key query
  uses only exact item endpoints and never falls through to item-collection
  search. Its explicit Link and Fill
  operation binds one reviewed local server/library/item read, source revision,
  binding revision, and Metadata revision; it writes the portable relationship,
  then fills only absent applicable managed fields while retaining conflicts.
  Abstract and tags never become authored `summary` or `keywords`, and the
  operation writes neither Markdown nor Zotero. A bound-item refresh reads
  only its exact user/group item, previews absent and differing mapped fields,
  then fills or updates only those displayed nonempty values without deleting
  omitted fields or replacing the effective source type. Set/rebind/clear remain
  independently revision-checked. An eligible authenticated Analysis Run with frozen Zotero
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
- Application owns vault-qualified Link/Relationship membership, diagnostics,
  and bounded Graph traversal. The CLI only resolves selectors and formats
  results; same relative paths in different vaults cannot enter a fallback
  join. Its text `read` is exact-source, and one registry supplies command
  validation plus help; an unknown help topic fails.
- First-launch Agent preparation and Research Guidance Settings copy the same
  fixed official installation instruction for the independently packaged CLI.
  The App has no CLI installer or machine-status owner and never embeds,
  inspects, executes, updates, or removes the CLI. The external Agent may place
  only the release executable and resource bundle under `~/.local/bin`, then
  verifies the required version fields while ignoring unrelated JSON fields.
  The installed CLI now owns explicit `scholium update --check` and
  `scholium update` commands; they verify the official archive, checksum,
  release provenance, architecture, and signature before a recoverable
  user-local replacement, and never edit PATH or shell profiles. The updater
  recursively synchronizes and promotes a complete durable transaction before
  replacement. Updater and packaged installer share one protected lock; the
  installer uses no-clobber publication for first installation or an exact
  partial first install only and refuses a complete pair.
- The first-launch preparation prompt and every first-workspace handoff use a
  CLI read-only Skill-source manifest and deterministic workspace-bootstrap
  candidate. The manifest exposes every installed Protocol and enabled current
  Action Skill folder, including an explicitly registered machine-local
  folder. The Agent registers those exact sources through its host's
  project-level Skill mechanism; Scholium neither detects the host nor creates
  or verifies that registration.
