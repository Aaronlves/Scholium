# Specification: Agent Collaboration and Research Workflows

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 8–8.6 and 9–11.

## 8. Agent collaboration

### 8.1 Ownership and authority

The researcher converses with an Agent in an external MCP host or in the
optional in-app Chat (§8.7). External hosts retain their conversation ownership.
Scholium provides a native client for supported runtimes; authentication and
the Agent execution loop remain runtime-owned. The researcher's
current instruction supplies the task, scope, and any permission to create,
modify, rename, move, undo a named change, or move a Note to system Trash.

Scholium separates three instruction owners:

1. **Scholium MCP** is the application adapter. It exposes current Triptych
   state and exact Note operations while preserving containment, revision,
   conflict, atomic-write, readback, and recovery rules.
2. The release-bundled **Scholium Core Protocol** is a protected, concise
   System Skill. It tells an Agent how to retrieve and use Scholium material
   without confusing source, inference, permission, or researcher authorship.
3. Researcher-owned method Skills are optional instructions installed and
   selected in the Agent host. They may refine philosophical method but cannot
   create evidence, expand write scope, weaken source fidelity, or override the
   Core Protocol.

Scholium creates no academic task type, profile, method registration, or philosophical
result/completion state. Chat execution and input-delivery state are software
operations, never research acceptance. MCP tool availability is not permission. For an
external host, Scholium neither reconstructs nor independently validates its
conversation; the Core Protocol requires researcher authority for every Note mutation,
including question and discussion writing under §8.6.

The authority stack is:

1. protected source-safety and MCP facts;
2. the researcher's current request and declared scope;
3. the Core Protocol;
4. an optional researcher-owned method Skill; and
5. primary texts, Analyses, Topics, Works, Search results, Metadata, links, and
   prior research history in their actual evidential roles.

Evidence never becomes instruction, permission, or researcher commitment.
Conflicts among instructions or evidence are reported rather than silently
averaged.

### 8.2 MCP server and installation

The installed `scholium` executable exposes one local stdio server through
`scholium mcp serve`. It adapts the Agent host to the currently running
Scholium App. The App remains the sole owner of live editors, workspace
coordination, current source, and derived indexes. The adapter never opens a
second workspace, reads the Triptych filesystem directly, starts the App, or
falls back to headless access.

The local App bridge is current-user-only and authenticates the live Scholium
process. Its transport credential proves the local peer; it is not research
permission, Agent identity, or durable authority. App absence,
missing open Triptych, and unavailable current state remain explicit tool
failures.

Codex and Claude receive the same server name, tool names, schemas, results,
and errors. Settings → Integrations → **Agents & Chat** shows App,
bridge, and CLI availability and provides:

- **Copy Codex Setup Command**;
- **Copy Claude Setup Command**; and
- **Show Core Protocol in Finder…**.

The copied commands register the same local stdio server at user scope using
the verified absolute CLI path. Scholium does not edit either host's settings,
install Skills, or claim that configuration succeeded. The Core Protocol ships
as an ordinary `scholium-core-protocol` Skill folder; researchers may install
it alongside their own method Skills.

MCP initialization carries only the entry/currentness, source-authority and
mutation facts needed to use the tools. It references the Core Protocol boundary
in §8.5 instead of becoming a second philosophical instruction source.

### 8.3 Tool contract

The local tool surface supports bounded knowledge-base operations. Tool availability
never expands the current researcher request. The following contracts are shared
by external hosts and in-app Chat:

| Tool | Input | Result |
| --- | --- | --- |
| `scholium_workspace_status` | optional `triptych_id` | open Triptych candidates or one reconciled current Triptych with three-vault, source, Search, and graph generations |
| `scholium_browse` | `triptych_id`; optional `role`, `directory`, `limit`, `offset`, `expected_listing_fingerprint` | bounded role roots or immediate directory/Note children, stable identities, exact source fingerprints, totals and listing fingerprint |
| `scholium_search` | `triptych_id`, `query`; optional `roles`, `limit`, and `offset` | Note candidates with totals, continuation, freshness, identities, match reasons, snippets, and exact source fingerprints |
| `scholium_read_note` | `triptych_id`, `note_id`; optional `start_line`, `line_count`, `include_context` | an exact current Markdown slice, continuation and full Note fingerprint; requested local Metadata, Zotero binding and attachment pointers separately |
| `scholium_list_attachments` | `triptych_id`, `note_id`; optional `offset`, `limit`, `expected_listing_fingerprint` | paged existing document relationships and registered authored images, availability and Note/listing fingerprints; metadata only |
| `scholium_read_attachment` | `triptych_id`, `note_id`, `attachment_id`, `expected_note_fingerprint`, `mode`; optional `expected_fingerprint`, `page`, `start_utf8`, `max_utf8` | bounded current text or one image/PDF page, exact file fingerprint and explicit extraction/rendering coverage |
| `scholium_show_note` | `triptych_id`, `note_id`, `expected_fingerprint`; optional `window_id` and complete `start_utf8`, `end_utf8`, `expected_text` range | named live-window navigation and exact passage-location request; no Note mutation or claim of rendered/assistive-technology arrival |
| `scholium_list_links` | `triptych_id`, `note_id`, `direction`; optional `limit`, `offset` | raw incoming/outgoing authored occurrences with source/destination identities, exact link and optional annotation markup/text, local context, fingerprints, and whole/link/annotation source locators |
| `scholium_create_note` | `triptych_id`, `role`, `relative_path`, `body`; optional `summary`, `keywords` | created stable Note identity, path, fingerprint, and `change_id` |
| `scholium_update_note` | `triptych_id`, `note_id`, `expected_fingerprint`, `mode`; mode-specific `content` or `edits` | before/after fingerprints, path, readback state, and `change_id` |
| `scholium_update_metadata` | `triptych_id`, `note_id`, `expected_fingerprint`, explicit nullable `expected_metadata_fingerprint`; `set` and/or `remove` | targeted managed-field changes, record comparison fingerprints, readback and `change_id` |
| `scholium_update_attachment` | `triptych_id`, `note_id`, `expected_fingerprint`, `expected_listing_fingerprint`, `action`, `attachment_id`; `source` for add/replace | one document relationship added/replaced/removed, record comparison fingerprints, readback and `change_id` |
| `scholium_preview_move` | `triptych_id`, `note_id`, `expected_fingerprint`, `relative_path`; optional `offset`, `limit`, `expected_plan_fingerprint` | paged paths, identities, source revisions, link counts, blockers and plan fingerprint |
| `scholium_move_note` | `triptych_id`, `note_id`, `expected_fingerprint`, `relative_path`, `expected_plan_fingerprint` | identity-preserving same-role move with exact linked-source effects, one Agent Change, readback and recovery details |
| `scholium_list_changes` | `triptych_id`; optional `note_id`, `limit`, `offset`, `expected_listing_fingerprint` | bounded machine-local mutation receipts and revision-bound continuation; no source bodies |
| `scholium_read_change` | `triptych_id`, `change_id`; optional `note_id`, `offset`, `limit`, `effect_offset`, `effect_limit` | receipt, selected affected Note comparison, paged move effects, current/earlier/unavailable ending and current Undo eligibility |
| `scholium_undo_change` | `triptych_id`, `note_id`, `change_id`, `expected_fingerprint` | the named eligible update or move restored through ordinary source recovery, exact restored fingerprints and original receipt; no new fabricated update |
| `scholium_trash_note` | `triptych_id`, `note_id`, `expected_fingerprint` | the exact Note moved to macOS system Trash, original location, and `change_id` |

External role values are only `analyses`, `topics`, and `works`. A Note is
addressed by stable UUID; path is location and presentation, never mutation
identity. An unresolved or ambiguous identity blocks identity-dependent
mutation. Every fingerprint contains canonical SHA-256 and byte count.

`scholium_workspace_status` may select automatically only when exactly one
Triptych is open. With several open Triptychs it returns the candidates and
requires an explicit `triptych_id`; foreground or recent-window state never
chooses research scope.

Search reuses §13's parser, ordering, match reasons, and generation. Query text
never changes scope; `roles` selects the three-vault Note subset. Each request
defaults to 20 results and permits at most 100. Results are discovery leads, not
philosophical relevance, evidential support, confidence, consensus, or truth scores.

Read defaults to 200 logical source lines and permits at most 1,000 per call,
subject to a bounded response size. It preserves exact source bytes and reports
the next line when more remains. Every slice also returns zero-based full-source
`start_utf8` and exclusive `end_utf8`, including BOM and YAML, so exact edits
can use the returned version and location. Repeated reads can retrieve the complete Note.

`include_context` defaults to false (`context: null`). When requested, context
separates validated managed Metadata fields and their own fingerprint from the
exact Markdown/YAML source; absent records return null. It returns only the
selected Analysis's local Zotero library/item binding and canonical reference,
with the binding-catalog fingerprint even when no binding exists. Other roles
have no Zotero binding or binding fingerprint. It does not contact Zotero, infer
a match, refresh bibliography or read paper content. Saved bibliography is not
primary-text evidence. Context also returns the first 20 attachment pointers in
the ordinary attachment-list shape; continue with that listing's fingerprint
through `scholium_list_attachments`. No attachment text enters this read.
The Application rechecks Note identity/source and these local records before
returning; detected drift or invalid records fail explicitly, never masquerading
as absence. Context is bounded to 128 KiB without truncating field values;
oversized context can be omitted to read source and list attachments separately.
These observations grant no Metadata, binding, attachment or Note write authority.

Link results expose one row per authored occurrence. Each row states requested
and occurrence direction, source and destination identity/role/path when
resolved, `link_markup`, nullable `annotation_markup` and `annotation_text`,
`authored_target`, `local_context`, source fingerprint, and separate locators
for the whole occurrence, Wikilink, and annotation content. Incoming results
retain the source Note's fingerprint and locators. They do not add an inferred
predicate, convert a transitive path into evidence, or reinterpret annotation
prose.

Create accepts one exact relative `.md` path inside the selected role vault.
Absolute paths, traversal, collision, and automatic renaming are invalid. It
uses the common managed New Note scaffold; omitted `summary` and `keywords`
remain empty authored values. It creates no bibliographic Metadata.

Update has three mutually exclusive payload modes:

- `body` replaces the Markdown body while preserving the complete YAML
  envelope and every other out-of-scope source byte; and
- `source` replaces complete Markdown/YAML and is used only when the researcher
  explicitly requests complete source or YAML modification; and
- `edits` applies 1–100 exact insertions, replacements or deletions against the
  same complete source revision. Each edit supplies zero-based `start_utf8`,
  `end_utf8` (exclusive), exact `expected_text`, and `replacement`. Ranges must
  be UTF-8 scalar boundaries, nonoverlapping and unambiguous; coincident
  insertion points are rejected. Empty ranges insert; empty replacements delete.
  All ranges refer to the original revision, never an intermediate edit.
  Unchanged bytes, including BOM, newline spelling and YAML, stay exact. An
  edit touching YAML requires explicit researcher authority for that change.
  No fuzzy relocation or permanent block identity is introduced. Invalid ranges,
  mismatched old text or an invalid complete result reject the entire call.
  Preview and execution use the same transformation and ordinary Agent Change
  comparison and Undo. `content` and `edits` cannot be combined.

One update call targets one Note. A request covering several named Notes uses
separate calls and separate outcomes. No call automatically propagates to
destination Notes, Metadata, links, or Settlement. Editing a link
annotation is an ordinary source-Note update guarded by that Note's current
fingerprint.

Metadata writes patch only named managed fields, preserve other values and every
Markdown/YAML byte, and use the shared role catalog and archived-field rules.
`set` is a typed field mapping; `remove` lists keys. Their disjoint union permits
at most 128 edits and the request is bounded to 128 KiB. A current Metadata
fingerprint is required; explicit null asserts record absence. Invalid fields,
wrong shapes, stale records and no-op edits cause no write or receipt.

Attachment writes manage document relationships, never inline image markup or
original-file bytes. Add takes a new relationship UUID; replace/remove take an
existing one owned by the named Note. Add/replace select `source.note_id`,
`source.attachment_id`, its `expected_listing_fingerprint` and exact file
`expected_fingerprint` from prior attachment reads. Only existing registered
document material in the selected Triptych is admitted. External material first
uses the App's file-selection attachment route; arbitrary caller paths and URLs
provide no file authority. Source bytes are bounded to 20 MiB and checked through
the existing access/containment owner. Same-vault contained files may be shared;
cross-vault or externally referenced files are copied from the verified snapshot
without overwriting a file. Source relationships and target revisions are
rechecked at admission. Duplicate relationships and stale targets are refused.
Remove only unlinks; replace preserves the earlier file. Neither rewrites source,
loses editor state, nor deletes originals or retained copies. These are individual
operations, not a cross-Note atomic transaction.

Each successful Metadata or attachment operation produces one Agent Change.
Its fingerprints and comparison identify the serialized managed record, not
Markdown; null denotes record absence. Ask uses the same preview and scoped
permission as source edits. Undo restores the retained record values or absence
only while the current record equals the ending; it never deletes attachment
files. Invalid preimages or ambiguous identities cannot authorize recovery.
Uncertain write/readback retains evidence and forbids blind replay.

Knowledge-base construction also provides bounded, paginated role/directory/Note
browsing through the current Library inventory; identity-preserving Note move
and rename through §5.3; and Note-related attachment listing and scoped reads.
Browse defaults to 20 entries, at most 100, and exposes role roots when no role
is supplied. A role selects its root or exact relative directory, including
empty directories. It lists immediate children only, using the Library's
attachment-storage visibility rule. Continuation requires the returned listing
fingerprint; a changed inventory rejects continuation rather than silently
skipping or repeating entries. A missing/inaccessible role or directory is an
explicit failure; paths never select another vault or provide filesystem access.
A move preview identifies affected resolved links, validates the current source,
path occupancy and associated identities, and exposes a fingerprint of the complete
planned effects. Pages contain at most 100 effects or blockers; continuation uses
the same plan fingerprint and rejects changed effects. Preview moves nothing,
creates no Agent Change and grants no execution authority. Execution rechecks
that reviewed plan and reports actual per-item outcomes. A changed plan requires
a fresh preview; it cannot silently add linked Notes to the approved effect set.
Cross-role moves remain prohibited. It never simulates a move with create/trash.
Attachment access proves the Note relationship and permitted file scope, returns
exact version and text/page/image coverage, and reports missing, changed or
unreadable content without substituting metadata for reading. Explicit Chat
material permission and vault-related access remain separate.

Attachment listing defaults to 20 entries (at most 100); later pages require
its listing fingerprint. No catalog scan grants unrelated-file access. Reads
require the current Note revision and an existing document relationship or an
exact authored reference to a registered image in that Note's vault. Relative
files remain inside the vault without following symbolic links; absolute originals
require the existing exact-path read-only bookmark, with no access prompt.
Each call reads at most 20 MiB, returning its file fingerprint. Text mode uses
exact UTF-8 offsets (default 16 KiB, maximum 64 KiB); continuations require that
file fingerprint. PDF text is extracted from one explicit one-based page, and
its offsets belong to that extraction rather than the PDF bytes. Image mode
returns a bounded PNG derivative (at most 1,024 pixels per edge and 512 KiB),
with a PDF page required for page rendering. A rendered page is not extracted
text or OCR; `text_available` explicitly describes whether the returned text slice
contains readable text, without inferring a blank original page. Original bytes
remain authoritative. Missing relationships,
stale versions, locked/unsupported/unreadable files and out-of-range locators
fail explicitly, preserving source and without staging a second material store.

Session-bound Note/passage display validates identity, revision and location and
uses existing tabs/navigation. Workspace status lists live window identities;
external hosts must name one current key window. Chat captures its visible
window at turn admission and cannot redirect display to another window or a
newly selected conversation. Display never foregrounds a window. Hidden,
closed, switched, dirty or composing contexts reject navigation; invalid versions
and complete UTF-8 ranges reject before activation. Queued delivery rechecks
window, conversation, source and reading context. Existing tabs and Document
mode remain owned by navigation. Success confirms activation/location dispatch,
not pixels, focus, selection painting or assistive-technology acceptance.
Agent Change queries and comparisons reuse §8.4; restoration requires the current
request, exact eligible change and unchanged ending revision. Completed writes
are not replayed, and another task's changes are not automatically undone.

Link explanations, merges and splits compose these general operations. Authored
prose retains its philosophical meaning; Connections never infer support. A
multi-Note plan exposes its targets and effects before mutation, returns separate
outcomes and a continuation path after partial failure, and promises no cross-Note
atomicity or automatic rollback.

Trash accepts one current Note and uses only macOS system Trash. It has no
permanent-delete, recursive-folder, or application-Trash variant.

Each definition publishes closed input and output schemas. Successful
structured content is an object with `schema_version` and `status: "ok"`, and
the same JSON is available as text for compatible hosts. Expected domain
failures return `isError: true` with
`{schema_version, status: "failed", code, message, recovery}`. Stable codes are:

- `app_unavailable`, `workspace_selection_required`, and
  `workspace_not_ready`;
- `not_found`, `ambiguous`, and `path_occupied`;
- `stale_revision`, `conflict`, `no_changes`, and `invalid_request`; and
- `operation_uncertain` and `internal_error`.

An identical update returns `no_changes` before writing or preparing an Agent
Change. It warrants no edit claim or automatic retry.

Protocol parsing and unknown-method failures remain JSON-RPC errors. Tool
annotations identify retrieval tools as read-only, local, and
idempotent; Note create is non-idempotent, while Note
update/trash are destructive and non-idempotent. An
annotation is a host hint, never authorization.

The first release exposes no MCP Resources, Prompts, Sampling, Roots,
Elicitation, long-running Tasks, dynamic tool list, or provider-specific tool
variant. MCP Tasks must not recreate an application-owned research lifecycle
under another name.

### 8.4 Currentness, mutation evidence, and recovery

Before the first knowledge-base operation in one external research task, the
Core Protocol calls `scholium_workspace_status`. The App completes already
pending editor saves, reconciles observed external changes, and requires the
Search and graph generations to correspond to the same complete source manifest
before returning `current: true`. Mechanical reconciliation
creates no research history and grants no mutation permission.

Status is not a frozen task snapshot. Search, read, and link calls recheck their
own currentness and return the generation/fingerprint actually used. A later
external or researcher edit therefore appears in the next result rather than
being hidden behind the opening status.

Create proves path absence. Update and trash use compare-and-swap against the
exact expected Note fingerprint. Workspace generation is not a Triptych-wide
write lock. The App retains its ordinary dirty-editor, external-change,
multiwindow, containment, atomic replacement, exact readback, and conflict
owners.

Every successful MCP Note, Metadata or attachment mutation creates one
machine-local **Agent Change** with a stable `change_id`, operation, Note identity and location, exact
before/after evidence where applicable, and recovery state. It exists only to
support accurate comparison, Earlier Revision presentation, and eligible
direct Undo; it is not a research task, review state, completion
marker, philosophical summary, or researcher acceptance. Created Notes have
no fabricated empty preimage. A separate machine-local viewed marker records only
an explicit Mark as Viewed action for that receipt. Opening or closing a comparison
never marks it. Mark as Unviewed restores the pending entry; new receipts are
unviewed. This marker grants no permission, confirms no philosophical judgment,
and changes neither evidence, recovery state nor Settlement. Prepared and uncertain
outcomes cannot be hidden by it; undone receipts remain in history.

Change listing defaults to 20 receipts (at most 100), optionally filtered by
stable Note identity, including linked Notes affected by a move; continuation
binds the returned listing fingerprint. Move reads select a comparison by affected
`note_id` and independently page effects (20 by default, at most 100).
Comparison reads default to 200 rows (at most 1,000) under the bounded response
size, retaining exact line text, endings, Before/After positions and BOM state.
Create and Trash retain their actual evidence without invented empty comparisons.
Historical source is not the current Note or proof of researcher acceptance.

The Undo tool requires one explicitly requested Note and Change identity plus
the recorded ending fingerprint. Chat uses its current conversation/turn and
mutation permission; Ask shows the exact reverse comparison. Querying or reading
history never initiates Undo, selects another task's change or authorizes repair.
Undo transitions its original receipt rather than inventing a second source
edit record. A completed Undo is never executed again. Cancellation before source admission
leaves bytes unchanged; uncertain source or evidence confirmation reports an
uncertain outcome and does not automatically resend.

A move records its primary Note plus the exact before/after bytes, identities
and locations of every linked-source rewrite in the same Agent Change. It is
one bounded operation, not a multi-Note workflow engine. Ask exposes the source
and destination and all affected source comparisons before execution. Confirmed
source and identity results remain distinct from delayed derived refresh.
Move evidence is bounded to 1,000 affected Notes and 16 MiB of aggregate
Before/After source, retaining the ordinary per-Note source limit.

Direct Undo restores an eligible update only while current source still equals
its final fingerprint. A move inverse additionally requires the recorded final
locations and all affected Note identities/revisions, vacant original path, no
new unreviewed link rewrites and unchanged link resolution under the restored
exact source. It restores the original bytes through the same move coordinator;
it does not approximate Undo by a newly canonicalized reverse rename. Any later
source edit, path/identity drift or unsafe restored link refuses the whole inverse.
The original move receipt becomes undone only after all readback succeeds.
Partial failure retains the existing per-file Recovery evidence and exposes its
actual outcomes through `recovery_details`: Recovery identity, total count and
at most 100 file paths, roles, Before/intended/observed fingerprints and states.
Remaining entries stay in the existing Recovery record. Neither move nor inverse
promises cross-vault atomicity. Separate calls remain separate
transactions; one failure never rolls back a confirmed sibling. Creation and
system-Trash operations retain their own recovery contracts and do not acquire
a fabricated source restore through Agent Changes.

If the helper cannot determine an already-sent mutation's outcome, it returns
`operation_uncertain` and must not retry automatically. The Agent rechecks
workspace status and the target's current identity, path, and fingerprint
before deciding whether any new request is warranted.

### 8.5 Core Protocol

The Core Protocol is a thin application workflow Skill, not a complete or
universal philosophical method. It requires an Agent to:

1. obtain current workspace status before first access and after any explicit
   stale, conflict, external-change, or unavailable-state recovery;
2. form a multilingual conceptual neighborhood from the research question,
   issue several bounded queries, read relevant passages, revise retrieval, and
   follow direct links where warranted;
3. treat Search, Metadata, filenames, tags, and links as candidates and
   locators, never as substitutes for reading or philosophical judgment;
4. distinguish primary text, source-reported view, Analysis reconstruction,
   Topic synthesis, Work commitment, prior research history, charitable repair,
   and the Agent's own inference or evaluation;
5. never infer philosophical identity, irrelevance, invalidity, support, or
   truth merely from shared vocabulary, conceptual difference, conflict,
   popularity, Search rank, or an authored link;
6. default to read-only discussion, mutate Notes only within the exact target
   and scope named by an explicit researcher request;
7. preserve unrelated source and avoid automatic maintenance of related Notes,
   Metadata, links, or Settle;
8. return to an accessible primary source when Topic and Analysis materially
   conflict about a paper's attribution or argument, and otherwise state the
   unresolved evidential limit;
9. re-read after stale/conflict and verify uncertain mutation outcomes before
   any retry; and
10. after Note mutation, report the affected file and location, the academic
    change as the Agent understands it, and any unresolved risk.

The Core Protocol does not prescribe one philosophical genre, fixed sequence,
output template, number of sources, or preferred conclusion. A researcher-owned
method Skill may guide those judgments without changing the application or
permission contract.

### 8.6 Question-centered Works Notes

Continuing research questions and selected discussion belong in ordinary Works
Notes under §4. They have no separate record type, mandatory chronology,
completion state, or automatic recording operation. Researchers edit the prose
directly; external Agents use the ordinary, explicitly authorized Note operations.
A substantive conversation alone does not authorize creating or updating a Note.
Authored attribution and version references are research content, not authenticated
history or researcher acceptance. Agent Changes retain their distinct operation-
evidence role under §8.4.

The [In-app Agent Chat](12-agent-chat.md) chapter owns §8.7.

## 9. Analyses workflow

Analyses reconstruct and assess identifiable papers or other sources. They are
evidence about what a source has been understood to say, not automatic evidence
that the source says it and not evidence of the researcher's own position.

The Agent may discuss an Analysis directly from its current body while naming
that evidential layer. A source-specific claim that matters to the answer is
checked against the available primary text when the Analysis is incomplete,
uncertain, internally unsupported, or materially conflicts with a Topic or
another Analysis. Inaccessible, partial, OCR-dependent, edition-dependent, or
otherwise limited source access narrows the claim.

An explicit create/update request may establish, correct, extend, reorganize,
or leave an Analysis unchanged. Reconstruction precedes criticism. Source
claims, reported views, reconstruction, objections, replies, implications,
charitable repair, and Agent evaluation remain distinct. Scholium never creates
one Analysis per reading stage merely because an Agent task was separate.

## 10. Topics workflow

Topics organize philosophical questions, concepts, distinctions, arguments,
positions, objections, and debates across sources. They synthesize material
without becoming a fixed truth hierarchy or a complete statement of the
researcher's view.

The Agent searches conceptually across languages and neighboring vocabularies,
then reads the passages that actually bear on the question. It preserves live
disagreement, methodological asymmetry, conceptual variation, minority views,
limitations, and uncertainty. Conflict or difference never supplies an
automatic verdict, and a broad keyword neighborhood never establishes that two
sources address the same claim.

Topics change only under an explicit request naming the target. Adding or
changing an Analysis never automatically updates a Topic. Discovery that new
material may alter an older synthesis is a separate researcher-invoked task.

## 11. Works

### 11.1 Researcher-governed Works

Works contain the researcher's plans, arguments, drafts, and finished writing.
They are the primary durable evidence of the researcher's position, together
with explicit current conversation and later adopted research history. An
older Work that conflicts with a current statement is not automatically
overridden by recency: the Agent identifies both positions, reconstructs their
reasons, evaluates the more viable account, and asks the researcher to decide
whether durable revision is wanted.

Agents may discuss, criticize, develop, or edit a Work. Direct editing requires
an explicit target and preserves the intended thesis unless the researcher asks
for an alternative argument. Philosophical adequacy governs the result; the
Agent need not imitate the researcher's sentence-level style.

### 11.2 Discussion and assessment

Assessment follows the ordinary conversation and explicitly authorized Note
operations in §8. Reports are ordinary researcher-controlled Notes, with no
reserved directory, special read-only document type, registered action, result
schema, or round-completion state. Agent assessments remain attributed and do
not establish researcher acceptance or automatically change a Work or Settle.
