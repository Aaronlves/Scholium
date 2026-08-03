# Implementation Status: Reachable Behavior

Part of the canonical document set rooted at [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md).
This chapter owns reachable behavior, boundaries awaiting acceptance, and retired product surfaces; sibling chapters do not restate it.

## Reachable target behavior

### Triptych and storage

**Current reachable boundary**

Multiple registered Triptychs use independently chosen Analyses, Topics, and Works; each window
belongs to one Triptych. Portable control state stays beside Works in `.scholium`; machine/derived
state stays in Application Support. The atomic v2 registry does not import the retired
single-workspace registry.

### Application storage bootstrap

**Current reachable boundary**

D-104 is reachable: production composition validates the real per-user Application Support root
before constructing `WorkspaceStore` or `WorkspaceRuntime`, has no temporary or implicit read-only
fallback, and disables workspace commands in Storage Unavailable. The nonmodal app-root failure page
provides default Retry, selectable Details, and Quit. Debug/QA isolation requires an explicit root.

### Exact source

**Current reachable boundary**

`VaultDescriptorAccess` now holds a root descriptor per operation, walks parents with no-follow
`openat`, opens leaves nonblocking/no-follow, and accepts only immediately `fstat`-verified regular
files. Loads, fingerprints, precommit checks, readback, and recovery verification use this boundary.
Existing-file commits hold the original FD, copy and verify metadata, preserve advancing content
mtime, synchronize staging and parent, and use inode-guarded swap-back plus retained evidence on
uncertainty. ACL and ordinary xattr/Finder-tag values remain exact; the system-managed quarantine
attribute may normalize only its agent and forward-moving timestamp while flags and event identity
remain fixed. Focused Core tests reject quarantine authority changes. A real `NSFilePresenter`
coordination proxy proves that a provider-side replacement before writer grant
becomes a conflict with exact expected/candidate recovery. `SIGKILL` subprocess fixtures at staged
and post-swap boundaries prove deterministic repository reopen, one canonical revision, exact
prewrite recovery, hidden staging exclusion from Library inventory, pre-swap candidate-journal
retention or post-swap journal completion, and a subsequent save. Startup replay now reads canonical
source through the descriptor boundary and no longer deletes a distinct uncommitted candidate merely
because the old expected revision remains canonical. The existing Recovery sheet now lists each
exact-valid retained candidate with vault/path/revisions and read-only source, Copy, Finder reveal,
and revision-checked Restore. Core revalidates the displayed transaction fields and no-follow
recovery bytes; Window flushes every Triptych editor before Application invokes the ordinary
repository save, and a changed/missing/unverifiable source fails closed without consuming the
candidate. Focused Core and Application fixtures pass; direct human, real File Provider domain,
packaged-process termination, and assistive-technology recovery acceptance remain open.
`FilePresence` treats only `ENOENT` as absence. `FrontmatterPatchPlanner` validates complete Yams
semantics and requires a unique bounded plain key: scalar edits change only the value token, the
role-aware Research Unit uses bounded member/array replacements, and missing keys append only at a
proven block-mapping boundary. Ambiguous YAML returns a typed Source-directed refusal without byte
changes.

### Refresh and disposable projections

**Current reachable boundary**

One `WorkspaceRefreshCoordinator` serializes prepare → Search transaction → snapshot publication;
monotonic request IDs, merged request payloads, and waiter-scoped cancellation prevent overlapping
builders. One actor-isolated `WorkspaceSourceOperationGate` gives source mutations and refresh
cycles mutually exclusive leases, removes a cancelled pre-acquisition waiter without granting later
authority, and buffers watcher invalidations across file/identity migration. It does not revoke an
acquired transaction or add an actor hop. Each pooled vault owns one rebuildable
`VaultSourceCatalog` of exact documents, descriptor-observed metadata, source versions, semantics,
and source-bound Search projections. Ordinary changes reread/reparse affected notes; event loss/root
discontinuity requests full reconcile. Three independent catalog actors may prepare immutable
generations concurrently inside the one cycle; Graph, Search, and publish remain ordered. Snapshot
assembly reuses the same generation's fail-closed resolved identity and fingerprint-bound title
projection. Graph still rebuilds completely, `WorkspaceSnapshot` remains intact, and Search v4
applies a transactionally persisted, generation-checked delta in one database per Triptych; stale
generations remain rejected after reopen. UTF-16 projection cursors are linear, and privacy-safe
counters cover enumeration/read/parse, graph, Search, snapshot/source size, Application publication,
and MainActor delivery.

### Lifecycle and deletion

**Current reachable boundary**

Direct New Note creation, duplicate, move/rename, Set Aside, Trash, exact-path Put Back, and
permanent deletion route through Application and `VaultRepository`. Library Add/File/keyboard create
an empty untitled note at the current vault root; an ordinary folder context action creates in that
folder. Creation claims the first unoccupied default path atomically, refreshes and selects it
within one serialized document transition, and opens no sheet. Identity-dependent interface commands
now carry one `NoteLifecycleTarget` containing the vault-qualified document ID, stable Note ID, and
exact revision through the complete call chain; Application re-resolves that identity under the
source mutation lease and rejects a reused path. Put Back is a direct reversible row command with no
sheet and no unrelated editor flush. A committed category move removes the moved Note's document
page and clears its current presentation; selecting it explicitly in Library, Set Aside, or Trash
still opens the exact content. Deletion removes the Note, current Critique, machine-local prewrite
recovery and execution, stable identity, active Discussions, and affected checkpoints; finished
portable records retain a tombstoned participant instead of being silently erased. A durable
higher-level deletion journal restores pre-commit state or completes post-commit privacy cleanup;
concurrent path recreation is preserved for explicit recovery. The focused Application
identity-drift test and QA journeys cover reused-path rejection, current-note Trash to empty
Document, lifecycle browsing, hover-native exact-path Put Back without a sheet, stale-hover
teardown, and current-note Set Aside to empty Document followed by explicit Set Aside browsing.

### Move and import

**Current reachable boundary**

Confirmed moves preflight destination and incoming-link revisions and rewrite only identically
resolved links. Stable identity/records follow confirmed moves or reconciled external renames;
ambiguity requires confirmation. Proven source commits return their committed value with separate
derived-refresh and identity-recovery warnings across Application, GUI, and CLI, so post-commit
repair never invites a repeated mutation; identity-dependent window actions remain unavailable when
identity migration needs recovery. Create, import, and duplicate no longer discard an exact rollback
failure after identity setup fails: a proven retained source becomes a committed identity-recovery
outcome, while unreadable presence is reported as explicitly uncertain. D-132 imports regular UTF-8
Markdown directly into the current Scope's vault root, preserves exact source bytes and the external
original, and resolves collisions without replacement. Multi-file import attempts each selected
source independently, reports exact partial failures, aggregates derived-refresh and
identity-recovery warnings across committed files, identifies already committed imports as
nonretryable, and stops remaining files if the owning window closes or switches Triptych instead of
routing them through replacement capabilities. Root-level Notes are ordinary Library Notes; the
former staging/classification APIs, UI, CLI alias, and transaction roles are absent. Existing legacy
staging bytes are left untouched and invisible. Focused contract, fault-injected refresh,
creation-rollback, CLI-boundary, exact-byte, collision, batch-presentation, and window-lifecycle
tests pass; direct multi-file UI acceptance remains open.

### Settlement, Discussion, and Critique

**Current reachable boundary**

Settle is a researcher-owned, fingerprint-bound, replaceable current judgment stored as one portable
file per Note; it is not an application-authored event history. Before that portable state commits,
the current Note's exact bytes are pinned in machine-local recovery; the same stable Note and
fingerprint reuse one pin. Repeating Settle can update rationale/date and backfill a missing pin
without duplicating identical bytes. Changed Since Settled is derived directly from the current
Markdown revision during snapshot assembly; the unused `PendingResearchState` delivery contract and
projection are absent. Review alone saves a selected-range Comment directly as one researcher turn
containing only the stable Note, current fingerprint, and inclusive line range; Edit and Source have
no Comment route. The composer closes only after write acknowledgement and retains its text on
failure. Comment opens no sheet or agent handoff. The first Discuss on a Comment-only draft resolves
the editable Discuss Method/Profile into the same Discussion and Local-v2 run; later handoffs reload
those frozen machine-local instructions. Bound Discussion reopens directly, and no duplicate
active-Discussion row appears in Actions. Finished Discussions remain Research Records and are not
silently injected as Critique evidence. Written annotation remains authoritative Markdown or a
semantic Callout. D-105 cleanly removes Human Review, Qualification, ResearcherComment, app-owned
Annotation, pre-Function Dialogue, and their stores, decoders, migrations, recovery, Search, and UI
paths. A Work retains one attributed current Critique under `Works/Critiques`; Action-backed
Critique execution uses a recoverable Local-v2 handoff and idempotently reconciles actionable
findings, while Accept/Reject/Rebut and researcher Complete Round remain separate scholarly
decisions.

### Research Action contract foundation

**Current reachable boundary**

Contracts expose bounded Action IDs, a collision-free researcher-owned creation route, public
execution kinds, Action-specific Target roles, the frozen default role matrix, a unified native
parameter model, fail-closed schema-v2 snapshots, and a separate record identity that permits only
schema version plus Action ID. Action Profile schema 1 adds bounded presentation, applicable roles,
visibility/order, seven closed native module kinds, source and feedback requirements, readable-role
declarations, direct-write role ceilings, two existing-note write operations, and exact property
boundaries. A Triptych-portable, revision-checked Profile document stores those Profiles and their
exact Skill-package binding; direct and explicit multi-Triptych copies remain independent.
Application resolves role-valid default and researcher Actions, rechecks every preparation, and
freezes exact Target, Method/resource revisions, Profile/document revisions, parameters, and
concrete read/write authority without exposing the protected Function ID. Profile storage remains
nonexecuting and a Profile cannot grant authority. Machine-local standing policy is now a separate
bounded decision factor with exact Skill/Profile-envelope invalidation. Property-only custom
mutation fails closed until its delta can be enforced.

### Agent change request coordination

**Current reachable boundary**

Schema-v1 requests bind one idempotent request ID to the exact Triptych, authenticated Local
Execution v2 parent, parent and requested Skill/Profile revisions, stable Note identities, expected
fingerprints, bounded existing-note operations, and attributed agent reason. Every new local Action
run stores a short-lived coordination-key digest bound to the exact Triptych, parent run, and Action
revision, while the plaintext key remains only in its live delivery packet. The App-wide AF_UNIX
bridge retains its private ownership, same-UID, bounded-frame, timeout, and uncertain-outcome rules.
One MainActor claim coordinator assigns each pending request to at most one exact matching Workspace
window, prefers that Triptych's key window, safely transfers an unresolved claim when a window
closes, and lets `show_note_change_request` focus only the existing sheet. One controller per exact
window owns the transient request, display identity and retry, expiry refresh, decision task, and
sheet route; asynchronous results are request-identity checked and teardown cancels every task
family. The native sheet derives current titles, roles, and revision state; resolves current Action
and Skill display names; shows operations and Method/Profile revisions; exposes subset selection,
Allow These Notes Once, Continue Without Changes, and Cancel the Run; keeps stale/expired state
readable; and restores the prior responder after dismissal. Allow stays disabled if display identity
is loading or unavailable, while raw package ID remains separately labeled; bounded identity retry
and later exact replay/refresh can recover a transient failure. An authenticated bridge submit binds
the request before an App-wide Triptych editor flush. Manual and automatic decisions then revalidate
parent, Action, Skill, Profile, standing policy, roles, lifecycle, identity, operation, and
fingerprints; the automatic path additionally requires matching repeated policy evaluation bound to
the frozen package and Action/Profile role revisions, followed by one final complete request
revalidation. Active Working Method, Action Profile, Skill content/maintenance, and policy writes
share that decision gate, so an in-App mutation cannot interleave before the durable decision write.
At request expiry the sheet removes decision controls immediately and performs bounded durable-state
retries before retaining a contract-derived expired state. A currently qualifying standing policy
records the exact allowed subset without a sheet. Every result remains non-authorizing coordination
state and never widens the parent snapshot or grant. An allowed schema-v2 record now stores a
versioned correlation plan for the exact approved subset; Application re-resolves live Action,
Profile, Method, identity, and fingerprints before preparing one independent single-Target Local
Execution v2 child per approved Note. Each child owns its reserved run ID, frozen snapshot,
exact-Note continuation recovery checkpoint outside rolling automatic retention, activity grant,
completion validation, final-revision Fidelity route, cancellation/conflict recovery, and
parent/request/group lineage. The bridge returns live `child_preparations` only when every packet
matches that durable plan; keys stay delivery-only. Analyze to Synthesize, Critique to Write, and
activated Manuscript to Write use the same mechanism. Synthetic UI evidence cannot certify genuine
VoiceOver, Full Keyboard Access, installed IME, localization quality, or researcher visual
acceptance.

### Analyze source access

**Current reachable boundary**

`ResearchSourceReference` schema 1 retains only route, stable source identity, exact Zotero
item/attachment keys where applicable, display filename, and fingerprint. A per-Triptych single-link
mode-0600 Application Support file alone retains read-only bookmark and canonical path;
descriptor-relative traversal rejects owned-path symlink, hard-link, nonregular, permission, and
substitution attacks. Source hashing is bounded to the opened starting size and rejects concurrent
change. The exact Zotero route refuses redirects, requires its original loopback response URL and
absolute query-free file URL, and rechecks parent, attachment, selected path, source revision, and
current nonempty Analysis key. Prepared and legacy Analyze runs fail closed on delivery and
completion when exact source authority is absent. Permanent deletion preflights store health and
removes its machine-local locator through the deletion recovery boundary. The production Analyze
sheet now keeps a source-repair Action reachable while execution is disabled, accepts one
researcher-selected local regular file through the native Open panel, re-resolves availability after
binding, and shows only the safe filename. Packaged-sandbox reopen of a researcher-selected external
source and an in-sheet Zotero attachment chooser remain unverified.

### Research Actions and protected execution

**Current reachable boundary**

One per-window Inspector exposes Overview, Connect, and Actions; Document has no Research Strip. The
Inspector, Research menu, focused keyboard route, common modular sheet, CLI, and delivery contracts
use public Action identity only. New-Target checks clear and bind availability to the exact Target;
same-Target checks retain visible rows in a disabled state, and late results cannot become
actionable. Opening saves only the current Target editor, presents the already-visible Profile
immediately, and loads declared Note/Source data inside the sheet; preparation still rejects any
change to the presented execution kind, complete Profile semantic revision, or Profile-document
revision without flushing unrelated Notes. Current Actions create no automatic whole-Triptych
checkpoint; mediated writes preserve exact displaced bytes per Note, while manual checkpoints remain
available. Action preparation freezes the exact Action snapshot before delegating to the internal
protected coordinator and persists protected state, instructions, grant digest, static Discuss
transport contract, and completion evidence as independent Local Execution v2 files; a write report,
grant completion, completion, and submission digest commit in one run-file replacement. Every
current Action completion requires explicit actually-used Material testimony: `[]` means none,
omission fails closed, and selection alone is not use. The Application persists each exact validated
revision and role together with the primary Target. Portable record schema 3 also derives
`not_required`, `completed`, or `unverified` Fidelity completion from Application evidence; it
records no pass, truth, quality, or acceptance verdict. Unsupported pre-production stores and schema
1/2 portable records remain byte-unchanged, invisible, and nonauthorizing, with no dedicated reveal
entry. Analyze resolves and rechecks one exact source before and after Method resolution; Synthesize
does not. The durable snapshot stores only the safe source reference, while the assembled packet may
carry its absolute path as a transient locator. The internal coordinator continues to own completion
keys, revision/write validation, containment, conflicts, and recovery; Function-named public routes,
controllers, panels, settings, record projection, and CLI are deleted.

### Action write scope and Fidelity

**Current reachable boundary**

Current Analyze, Synthesize, and Write preparation fixes the exact current Note as the sole write
Target. The common Action sheet presents the Target, current fingerprint prefix, declared candidate
authority, and revalidation/checkpoint/conflict/recovery boundary before its Profile modules.
Contract validation rejects multi-target write payloads before checkpoint or grant creation.
Write-report and Fidelity details remain protected execution data; independently authorized child
phases are the only route to another Note.

### Recovery and chronology

**Current reachable boundary**

Researcher-created self-contained checkpoints support comparison, selective/full restore, and Finder
access; retained legacy automatic checkpoints remain recoverable but are not created by current
Actions. Core keeps a non-delivery SQLite/immutable-object prewrite ledger with v1 preservation,
corruption quarantine/rebuild, remap, temporary retention, deletion tombstones, and settled-version
pins. Durable pin manifests own exact-byte identity and per-Note monotonic order; a common advisory
lock and unique index coordinate allocation, while one-transaction UPSERT replaces a derived SQLite
row when any manifest field differs. Exact-valid manifests protect bytes even when projection is
ambiguous; that condition blocks new recovery writes and all automatic cleanup. Portable replacement
distinguishes proved pre-rename failure from commit uncertainty, so only the former can roll back a
new pin. Machine-local per-Triptych policy retains 10, 30, 50, or no automatic limit per stable
Note, defaults to 30, and requires an exact-ID preview before a lower limit removes older pins. The
approved set remains in a bounded 8 MiB journal until cleanup completes. Terminal validated
nonconversational Action runs create one whitelisted portable record under
`.scholium/research-records/v1/records/`; it records the Action rather than its protected Function
and recursively rejects undeclared fields and path-shaped nested values while excluding prompts, raw
keys, bookmarks, absolute paths, diffs, token counts, transport logs, and window state. Portable
active Discussion now uses one file under `active/`, and Finish creates exactly one neutral finished
record with interruption reconciliation. Corrupt peer files are isolated. The independent
list/detail window now provides confirmed direct record deletion and disposable exact-byte
comparison; settled-version restore UI remains later work.

### Application and CLI

**Current reachable boundary**

GUI and CLI share Application capabilities and trust rules. Each CLI invocation uses one snapshot
runtime; existing-note mutations require current SHA-256. App/CLI import only Contracts and
Application, Core remains internal, one live app runtime has one accepted event subscription, and
per-window controllers own independent presentation state.

### Connections, Search, and Attention

**Current reachable boundary**

One workspace `GraphSnapshot` owns Vector-Link v3 resolution: bare links remain neutral, `+` and `-`
mean the containing Note supports or opposes the target, and `?` records undirected incompatibility.
Graph contract 5 preserves exact markers and anchors, derives only support/opposition inverse views,
and invalidates the retired directed-Questions projection. Connect groups each Triptych-role section
by relationship, shows one direct SF Symbol per cluster rather than per Note, and keeps both the
major heading and bounded current-cluster symbol sticky in its single scroll owner. Major headings alone
carry counts; rows retain pointer help, keyboard activation, VoiceOver relationship names, and the
named source-anchor alternative. Neutral/transitive paths never become evidence and retired syntax
remains exact with diagnostics. Search contract v4 uses one normal-content SQLite FTS5 corpus per
Triptych for GUI/CLI Vault and Triptych retrieval, while This Note searches the unsaved editor
snapshot by occurrence. The removed `status` and `review` fields have no projection, index column,
filters, or ordering; `status:` and `review:` fail explicitly without affecting ordinary lexical
search. Attention is limited to specified structural, currency, connection, reliance, metadata, and
identity conditions. Material Changed Since Use is rebuilt only from the latest completed Synthesize
record for each Topic/Material pair whose fully cross-validated actually-used Analysis revision
differs from the current active resolved revision; unused, deleted-record, tombstoned, deleted,
contradictory, and unresolved inputs do not qualify. D-129 presents the existing derived queue in
one transient native popover owned by the exact Workspace, grouped by Identity & Metadata, Structure
& Connections, and Revision & Reliance. Sidebar and Inspector route to the same session without
showing statistics in ScopeIndex or the Document toolbar; Inspect dismisses before opening the Note
in the owning Workspace without global search or notification. Timed Dismiss,
latest-record-revalidated Resynthesize, and revision-pair-bound Leave Unchanged express no verdict
and never mutate the Topic or record. Revision-bound keys include Triptych identity, and Settings
can restore timed or revision-bound machine-local presentation decisions.

### Editor

**Current reachable boundary**

CodeMirror-backed Edit/Source and sanitized Review share one checked semantic projection and the
same callout, table, footnote, math, preview, font, and presentation contracts. Generated callout
roles are accessibility-only; supplied titles inherit role styling. One retained Host keeps Review
and one CodeMirror state mounted; stable internal identifiers remain `read`, `livePreview`, and
`source`. One atomic Document state now separates active mode from restoration intent and
retained-surface lifetime; the Web bridge accepts only the editor-specific Edit/Source type.
`MarkdownEditorSession` publishes one readiness/document-phase snapshot, serializes mode
convergence, and stages initial input without publishing during WebView construction. Its adapter
retains only a one-way input diff cache and no longer initializes or recovers mode from a parallel
field. Bridge v9 preserves exact source, identity, recovery, focus, scroll, and nonmutating UTF-16
Search-result reveal while coalescing selection reports. An established editor remains visible
during Edit/Source reconfiguration, and CodeMirror applies the complete mode compartment atomically.
Source retains exact-source typography without semantic rich styling; explicit selection no longer
highlights matching text elsewhere, and adjacent Markdown brackets no longer acquire a
selection-like match background. Its active-line treatment now applies only to a collapsed caret,
so a triple-click selection ending after a line break does not paint the following logical line;
losing window focus no longer rebuilds Live Preview from a hidden viewport. Edit's compact selection toolbar exposes the approved common Markdown hierarchy through a
neutral separator boundary, shallow shared floating-control elevation, and direct, quiet monochrome
SF Symbols; its custom menus use the deeper bounded-panel role. Both it and Review's separate direct
line-only Comment bar remain hidden until pointer selection finishes. Review remeasures the retained
Comment selection into a document-coordinate anchor so its bar or open field remains attached to the
passage while scrolling, and remeasures that anchor on viewport resize. Leaving Review now
deactivates that surface explicitly: an empty composer clears, while an authored or pending draft is
suspended in the retained page without focus and can resume on return. Saving remains read-only and
live-announced rather than disabling the focused field. Edit separates toolbar content equality from
geometry equality, so scroll and viewport changes remeasure an unchanged selection; one pure geometry
owner centers, clamps, and flips the bar, and is also reused by the separately dismissed Edit preview.
Shared Read/Edit previews now use one opaque bounded-panel surface and close on scroll, resize, or blur.
Edit now also mounts one CodeMirror-owned bounded-panel suggestion surface:
`[[` queries the generation-owned Workspace catalog as characters are typed,
shows title plus bounded path context, excludes ambiguous noninsertable targets,
and consumes existing closing brackets without duplication. A bare block-safe
`/` shows only Callout, Date, Inline Math, and Mermaid; further input fuzzy-filters
the complete nine-command insertion catalog, while prose limits the initial list
to Date, Inline Math, and Footnote. Source, marked-text composition, and protected
syntax own no suggestion overlay. The same Arrow/Return/Escape and pointer paths
retain the CodeMirror caret; each accepted result is one Undo transaction.
Edit and Source hide WebKit's native caret and use one CodeMirror cursor layer,
while source-character marks remain the only range paint; deleting a
structurally inserted line cannot leave a second caret at its obsolete Live
Preview baseline.
Inactive Edit lists retain their semantic marker while the caret edits prose
and reveal exact source only inside the indexed physical-line prefix. Review
and Edit share the same marker track, nesting step, and task-control geometry;
checked, unchecked, projected, and exact-prefix states keep one prose column.
Review renders disabled task controls. Edit's pointer checkbox and the
caret-line Toggle Task command share one exact-marker transition and one Undo
event across supported list markers. Left Arrow from the prose start enters
the prefix at its trailing edge without jumping to the physical line start.
Return saves, Shift-Return inserts a line, Escape cancels, and Edit/Source have no Review Comment
surface. The editor's one DOM-to-AppKit secondary-click path preserves a clicked selection, moves an
outside click through CodeMirror, and presents Cut, Copy, Paste, and Select All before any available
collapsed-construct action; the retired local right-mouse monitor, private-view menu query, Autofill,
Services, common formatting, and Preview routes are absent. Review alone owns footnote hover preview,
navigation, and
return. Edit projects inactive references as locators; one composite definition remains at its
authoritative source, keeps its marker exact, and applies ordinary construct-scoped projection only
to its body. Paragraph separator lines remain real measured source lines rather than collapsed
geometry; an authored separator now owns any larger adjacent semantic block spacing and its complete
visible area maps to that exact empty line, while source-less gap widgets remain only where no
authored separator exists. Inline clicks place one caret before delimiter exposure; a projected
Callout click commits that exact source caret and removes its widget during pointer-down, so no
intermediate boundary caret is painted below the block. Activation derives from the shared
Live-selection snapshot and keeps one quiet block surface over the complete Callout. Only the
caret-owning or selected physical lines expose exact structural markers; the other lines and nested
constructs remain projected. Return continues the exact quote prefix, while Return on an empty
quoted line removes that prefix and exits. Title-only Callouts stay visible, and a title-only Orient
projects its author-supplied title as Body without rewriting source. Source remains exact text and
owns none of these Edit-only continuation or projection behaviors.
Automated TypeScript, Swift, and real-WKWebView checks cover implemented semantics; human visual,
assistive-technology, IME, retained-memory, sustained-performance, and the current post-migration
mode-handoff experience remain open.

### Properties and Zotero

**Current reachable boundary**

Contracts now separate canonical vocabulary/ownership, default About profiles, and empty creation
requirements. Analysis uses Completion/Limitations and retains hidden title plus protected
`zotero_item_key`; Topic/Work use Scope/Limitations and H1→filename identity, with Work labelled
Research Scope. `status`, Work `deadline`, required markers, About Customize, and default disclosure
state are removed. Inspector exposes only one exact-item **Open in Zotero** action for a current
Analysis with a normalized key; it exposes no key, fetched metadata, matching, or confirmation. An
eligible Analyze Action reads the exact item once, attaches the protected Zotero integration Skill,
and stores labelled bibliographic metadata or a nonblocking warning in its immutable run snapshot;
resume reuses it and a new run rereads without cross-task cache. Bibliographic metadata remains
nonblocking, but a Zotero attachment selected as Analyze's required source is independently exact
and blocking. D-133 presents one Settings **Check Connection** action in place of the duplicate
Test/Refresh controls; **Clear Connection History** still resets only the in-memory last-successful
timestamp.

### Product Skills

**Current reachable boundary**

Catalog schema 4 separates protected mechanism from seven Action-addressed bundled Method
references. A new Triptych now installs six independent editable working packages before its
manifest, writes explicit Action-keyed binding v2 states, and records Manuscript as disabled.
Analyze and Synthesize resolve independently over retained Develop; every current Action's primary
Method uses only v2 and fails closed for missing, malformed, disabled, invalid, incompatible,
dependency-broken, or Method-dependent state. Bundled Methods are read-only installation/restore
references, never runtime fallback. Protected System mechanism remains independently seeded, exact
Method resources are coherently fingerprinted, and direct edit/restore publish displaced packages
through the existing machine-local maintenance snapshot lifecycle. Verified cross-volume copy
retains and reports the hidden portable inode instead of deleting possible late writes. Source
Analyzer, APA 7 verification, Philosophical Practices, and Prose Control remain opt-in Researcher
templates.

### Researcher Skill installation

**Current reachable boundary**

An app-wide staged installer accepts one researcher-selected local directory, retains exact UTF-8
bytes only in an expiring Core preparation, and exposes a nonexecuting inventory that contains no
source path or file contents while showing purpose, declared metadata, proposed Action placement,
and the explicit requirement for a later Action Profile. Descriptor-relative traversal accepts only
`SKILL.md` plus one-level regular `references`, `templates`, and `evals`; bounded enumeration
rejects the 129th file without first collecting an unbounded listing, and input also fails closed
for network URLs, archives/non-directories, symlinks, hard links, executable or scripted files,
unsupported/nested resources, malformed metadata, files over 1 MiB, and packages over 8 MiB.
Application resolves explicitly selected Triptychs; Core preflights all destinations, rejects
dangling current bindings or the retained citation/bibliography bindings that can still execute,
uses no-replace publication for each independent copy, and repeats bounded validation after
publication. Ignored legacy Function/Skill/Practice fields cannot authorize or block new
installation. A later-destination failure moves proved task-owned directories into hidden
nonexecuting recovery quarantine without deleting possible late writes; moved/replaced or otherwise
unprovable identities return recovery-required. The installer writes no Profile, binding, permission
approval, or execution state, so an unbound package starts disabled.

### Research Guidance

**Current reachable boundary**

Production Settings presents one restrained categorized list-detail surface for Methods, Researcher
Skills, Permissions, Sources and Integrations, and Recovery and Technical. It exposes explicit
Working Method installation for established Triptychs; revision-checked direct edit, disable,
compatible replacement, bundled comparison and restore; hidden Manuscript activation and direct
edit; staged local-directory installation; local Skill creation, structural validation and
recoverable guarded deletion; and Action Profile creation, confirmed deletion, global reordering,
all seven declarative modules, capability declaration, nonexecuting preview, deliberate Show in
Actions, and explicit independent copying to selected Triptychs. Recovery and Technical exposes the
per-Note settled-version policy with a destructive confirmation only when lowering the limit
enumerates older versions, machine-local Skill snapshots, and **Reveal Skills Folder**. Skill and
Action Profile drafts are isolated by Triptych, package, and Action identity, survive category and
Settings-tab navigation until saved or discarded, and cannot cross a Triptych switch; cancellation
and identity checks also prevent stale Methods, Skills, Recovery, or Permissions reloads from
repopulating a new Triptych. One Skill cannot silently claim an Action ID already configured by
another. Function-keyed Settings are deleted and cannot enter Action resolution. Citation Fidelity
and Recommended Bibliography each own a strict capability document; a retained
`research-skill-bindings.json` is byte-preserved, read only for bounded lazy migration or explicit
repair, and never supplies Function-keyed behavior or package-use constraints. Permissions edits the
machine-local Triptych default and exact-envelope per-Skill overrides, exposes invalidation without
broad fallback, and states the boundary around Scholium-mediated operations. Sources reuses current
CLI/Zotero controls. Superseded flat Settings, maintenance Proposal, and legacy-data reveal source
are deleted.

### Retained research workflow proofs

**Current reachable boundary**

One synthetic Debug-only PreviewCatalog remains for the modular Skill-run sheet, staged
local-directory installer, responsibility-based Research Guidance categories, Agent-requested
additional Notes, and fixed secondary Research Record utility layout. It is suppressed by default
and its single QA command is available only to the Debug `com.scholium.qa` bundle with an explicit
launch argument. It owns no Workspace, Triptych, document, Skill, permission, execution, record, or
source authority and is not a production surface. Completed Sidebar, Attention, Inspector,
Action-list, generic-state, complete-window, Editorial Parchment, and paired-window proofs have no
active route or compatibility alias.

### Discuss and MCP

**Current reachable boundary**

Line Comment, whole-note Discuss, and optional focal Notes now use one `PortableResearchDiscussion`;
older exact-passage turns remain readable. A new Comment stores only its Note fingerprint and
inclusive line range, never starts an agent run, and is collected when Discuss opens the active
exchange. New runs keep only their static response transport contract in Local Execution v2;
attributed turns live in the portable active exchange. Close has no storage effect. Agent reply
evidence is required before a Discuss run can complete, while researcher Finish is a separate
neutral transition into one portable Research Record and creates no legacy Discussed event. External
Zotero MCP remains separate from the built-in reader; only explicit `--probe` performs its read-only
initialization lifecycle.


## Implemented boundaries awaiting acceptance

### Localization

**Implemented evidence**

English default; complete zh-Hans string catalogs, compiler-synchronized formats,
coverage/placeholder/state/compilation validation, and outer-bundle language declaration. Current
lifecycle and Sidebar UI use 搁置、纸篓、移至纸篓…、放回 plus localized Scope, Location, Attention, and note
counts, while `Trash/`, researcher titles, paths, exact Markdown, and Skill names remain verbatim.
The catalog validator and six focused localization tests pass; packaged QA also covered Bootstrap,
vault/Library/Attention labels, and native accessibility localization.

**Still open**

Researcher terminology review, long labels, and broader manual accessibility.

### Beta app handoff

**Implemented evidence**

Copies immutable instructions before explicit app choice, persists one app-wide bookmark, opens
without research arguments, and offers Copy Only, Choose Another, and Forget. Focused tests cover
ordering, cancel/failure, replacement, forgetting, and persistence.

**Still open**

Packaged sandbox launch, Full Keyboard Access, VoiceOver, localization, and visual acceptance.

### Properties and Research Unit

**Implemented evidence**

The role-aware targeted editor preserves absent/declared/invalid states and unrelated bytes.
Analysis accepts binary or represented-ratio Completion and/or Limitations; Topic/Work accept Scope
and/or Limitations. All fields are optional at creation, deleting one member retains the others, and
focused contract/source-fidelity tests pass. The native comparison catalog includes mixed/all-serif,
320pt/narrow, light/dark, contrast, mixed-script, long-text, empty-Connect, direct-action, and
unavailable-Fidelity cases.

**Still open**

Researcher catalog review must approve or revise the provisional typography and spacing before those
values are treated as visually settled. Complete pointer/keyboard/focus/VoiceOver, installed-IME,
and human visual acceptance remain open.

### Time and Analysis metadata

**Implemented evidence**

Creation/modification times stay in app History; existing timestamp keys remain custom YAML. Debate
Importance is an optional 0–10 whole number paired with exact Debate Scope and replaces Project
Relevance only in typed defaults.

**Still open**

No migration or normalization of existing custom keys.

### Long-source analysis

**Implemented evidence**

One source-level Analysis may record represented Completion such as `6/11`; this is a quiet reminder
rather than a chapter ledger or adequacy claim. Source Analyzer remains an independent
copy-on-adoption Skill, not a Research Action; mutation remains separately authorized.

**Still open**

Final Completion control and reminder presentation require human review.

### Recommended Bibliography

**Implemented evidence**

D-121/D-122/D-124 present one Triptych-owned portable result as a fixed, intrinsic-height Sidebar
utility below and outside the Library source scroll. One `RecommendedBibliographyScope` freezes the
Triptych plus exact revisions of selected active Analyses, Topics, or Works as focal source context.
The store exposes one overview and at most one active request for the Triptych, so Scope, Location,
Note selection, and window changes neither replace nor hide the durable result. Completion echoes
the exact selected-Note revision set; Application rereads source bytes before preparation and
completion. Goals/purpose, prior-result retention, zero results, conservative discrimination, and no
Markdown/Zotero mutation remain. The Analysis-only target/error/store index and schema-1 projection
are removed; unsupported old bytes remain unchanged and nonauthorizing.

**Still open**

Philosophical value, final visual acceptance, and genuine spoken VoiceOver remain researcher-owned
acceptance.

### Recommended Bibliography compact entry

**Implemented evidence**

D-126 replaces the compact horizontal candidate scroller and diagonal-open glyph with one full-band
native Button. The fixed band now shows its heading, nonzero count, quiet forward chevron, and
either a purpose-named 10pt empty state or one static first-candidate citation preview. D-131
removes direct Zotero navigation from the complete candidate surface; rows retain **Open Analysis**
when matched and **Dismiss**. The compact Button exposes one Open label and count/empty value while
the surrounding group retains Triptych ownership.

**Still open**

Focused contract/build and isolated Light QA evidence exist for the compact entry and exact Zotero
routing; populated-candidate visual review, genuine spoken VoiceOver, physical Full Keyboard Access,
Dark/Increase Contrast/inactive-window review, and researcher visual acceptance remain open.

### Protected Skill IDs

**Implemented evidence**

A colliding Triptych package stays visible, invalid, and recoverable while the bundled package
remains authoritative.

**Still open**

Researcher must rename or delete the collision.

### Architecture stability cutover

**Implemented evidence**

Focused automated suites pass descriptor and special-file rejection, inode/path races, metadata
preservation, three-state deletion, fail-closed YAML, single-flight refresh, stale Search
generation, shared-vault/per-Triptych-index isolation, incremental/full-rebuild equivalence,
multiwindow identity migration, noncooperative lifecycle completion, storage failure/retry,
research-data/Researcher-Skill injection boundaries, and the clean record-model cutover. Complete
repository verification and the current disposable Complete UI baseline are recorded below.

**Still open**

G7 approval/packaged sampling, G9 release provenance, G10 field trials, and genuine
accessibility/IME/visual acceptance remain separate gates.


## Retired product surfaces

- Proposal/Revision review sheets, Research Task/Session, Agent Assessment, and
  the former Agent Review surface.
- Human Review, Qualification, ResearcherComment, app-owned Annotation, and
  pre-Function Dialogue archives and compatibility paths.
- Active-note HTML/PDF export and Canvas.
- Zotero data-folder/SQLite access, additional-vault/All Notes presentation,
  and generated `_index.md`, `_agent-index.json`, or `_agent-context.json`.
- The inline Attention queue, Library lifecycle footer and Back route, Sidebar
  Settings destination, duplicate Folder leading symbols, and hover-only Put
  Back presentation.
- Obsolete Proposal, Research Session, workflow-bridge/readiness/lint,
  pre-release Review-store, and Add Dated Reference implementations.

Unsupported pre-release state is not read into the current interface. The
clean cutover never authorizes deleting or rewriting researcher Markdown,
unknown YAML, or unrecognized Triptych files.
