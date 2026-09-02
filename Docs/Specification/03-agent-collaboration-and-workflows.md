# Specification: Agent Collaboration and Research Workflows

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 8–11.

## 8. External agent collaboration

### 8.1 Ownership and authority

The researcher converses with an external Agent in Codex, Claude, or another
compatible MCP host. Scholium does not embed chat, choose a model, store model
credentials, supervise an Agent, or own the conversation. The researcher's
current instruction supplies the task, scope, and any permission to create,
modify, or move a Note to system Trash.

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

Scholium creates no application task type, academic profile, method
registration, per-task credential, write ledger, result schema, or completion
state for Agent work. MCP tool availability is not permission. Scholium neither
reconstructs nor independently validates the external conversation; the Core
Protocol requires the Agent to act only on the researcher's explicit
instruction.

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
and errors. Settings → Research Guidance → **Agent Integration** shows App,
bridge, and CLI availability and provides:

- **Copy Codex Setup Command**;
- **Copy Claude Setup Command**; and
- **Show Core Protocol in Finder…**.

The copied commands register the same local stdio server at user scope using
the verified absolute CLI path. Scholium does not edit either host's settings,
install Skills, or claim that configuration succeeded. The Core Protocol ships
as an ordinary `scholium-core-protocol` Skill folder; researchers may install
it alongside their own method Skills.

MCP initialization contains only compact tool facts: begin with current
workspace status, Markdown source is authoritative, Search/Metadata/links are
retrieval aids, mutations require current fingerprints, and Scholium does not
decide whether the chat authorized a write. It does not duplicate the Core
Protocol's philosophical method.

### 8.3 Tool contract

The first release exposes exactly these tools:

| Tool | Input | Result |
| --- | --- | --- |
| `scholium_workspace_status` | optional `triptych_id` | open Triptych candidates or one reconciled current Triptych with three-vault, source, and Search generations |
| `scholium_search_notes` | `triptych_id`, `query`; optional `roles`, `limit`, `offset` | ordered candidate passages with Note identity, role, path, fingerprint, match reason, snippet, and source locator |
| `scholium_read_note` | `triptych_id`, `note_id`; optional `start_line`, `line_count` | an exact current Markdown slice, complete/continuation state, and full Note fingerprint |
| `scholium_list_links` | `triptych_id`, `note_id`, `direction`; optional `limit`, `offset` | raw incoming/outgoing authored occurrences with source/destination identities, exact link and optional annotation markup/text, local context, fingerprints, and whole/link/annotation source locators |
| `scholium_create_note` | `triptych_id`, `role`, `relative_path`, `body`; optional `summary`, `keywords` | created stable Note identity, path, fingerprint, and `change_id` |
| `scholium_update_note` | `triptych_id`, `note_id`, `expected_fingerprint`, `mode`, `content` | before/after fingerprints, path, readback state, and `change_id` |
| `scholium_trash_note` | `triptych_id`, `note_id`, `expected_fingerprint` | the exact Note moved to macOS system Trash, original location, and `change_id` |

External role values are only `analyses`, `topics`, and `works`. A Note is
addressed by stable UUID; path is location and presentation, never mutation
identity. An unresolved or ambiguous identity blocks identity-dependent
mutation. Every fingerprint contains canonical SHA-256 and byte count.

`scholium_workspace_status` may select automatically only when exactly one
Triptych is open. With several open Triptychs it returns the candidates and
requires an explicit `triptych_id`; foreground or recent-window state never
chooses research scope.

Search reuses §13's sole parser, ordering, match reasons, and current source
generation. Query text never changes scope; `roles` selects the three-vault
subset. The default is 20 results and the maximum is 100. Results are discovery
leads, not philosophical relevance, evidential support, confidence, consensus,
or truth scores.

Read defaults to 200 logical source lines and permits at most 1,000 per call,
subject to a bounded response size. It preserves exact source bytes and reports
the next line when more remains. Repeated reads can retrieve the complete Note.

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

Update has exactly two modes:

- `body` replaces the Markdown body while preserving the complete YAML
  envelope and every other out-of-scope source byte; and
- `source` replaces complete Markdown/YAML and is used only when the researcher
  explicitly requests complete source or YAML modification.

One update call targets one Note. A request covering several named Notes uses
separate calls and separate outcomes. No call automatically propagates to
destination Notes, Metadata, links, Records, or Settlement. Editing a link
annotation is an ordinary source-Note update guarded by that Note's current
fingerprint.

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
- `stale_revision`, `conflict`, and `invalid_request`; and
- `operation_uncertain` and `internal_error`.

Protocol parsing and unknown-method failures remain JSON-RPC errors. Tool
annotations identify the four retrieval tools as read-only, local, and
idempotent; create is non-idempotent, and update/trash are destructive and
non-idempotent. An annotation is a host hint, never authorization.

The first release exposes no MCP Resources, Prompts, Sampling, Roots,
Elicitation, long-running Tasks, dynamic tool list, or provider-specific tool
variant. MCP Tasks must not recreate an application-owned research lifecycle
under another name.

### 8.4 Currentness, mutation evidence, and recovery

Before the first knowledge-base operation in one external research task, the
Core Protocol calls `scholium_workspace_status`. The App completes already
pending editor saves, reconciles observed external changes, and requires the
Search generation to correspond to the same complete source manifest before
returning `current: true`. Mechanical reconciliation creates no research
history and grants no mutation permission.

Status is not a frozen task snapshot. Search, read, and link calls recheck their
own currentness and return the generation/fingerprint actually used. A later
external or researcher edit therefore appears in the next result rather than
being hidden behind the opening status.

Create proves path absence. Update and trash use compare-and-swap against the
exact expected Note fingerprint. Workspace generation is not a Triptych-wide
write lock. The App retains its ordinary dirty-editor, external-change,
multiwindow, containment, atomic replacement, exact readback, and conflict
owners.

Every successful MCP mutation creates one machine-local **Agent Change** with a
stable `change_id`, operation, Note identity and location, exact before/after
evidence where applicable, and recovery state. It exists only to support
accurate comparison, Earlier Revision presentation, and eligible direct Undo;
it is not a research task, Record, review state, completion marker,
philosophical summary, or researcher acceptance. Created Notes have no
fabricated empty preimage.

Direct Undo restores one eligible updated Note only while current source still
equals that Agent Change's final fingerprint. Separate calls remain separate
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
6. default to read-only discussion and mutate only the exact target and scope
   named by an explicit researcher request;
7. preserve unrelated source and avoid automatic maintenance of related Notes,
   Metadata, links, Records, or Settle;
8. return to an accessible primary source when Topic and Analysis materially
   conflict about a paper's attribution or argument, and otherwise state the
   unresolved evidential limit;
9. re-read after stale/conflict and verify uncertain mutation outcomes before
   any retry; and
10. after mutation, report the affected file and location, the academic change
    as the Agent understands it, and any unresolved risk.

The Core Protocol does not prescribe one philosophical genre, fixed sequence,
output template, number of sources, or preferred conclusion. A researcher-owned
method Skill may guide those judgments without changing the application or
permission contract.

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

## 11. Works and Critique

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

### 11.2 Critique target and storage

A Critique is an attributed Agent assessment of one Work or selected passage.
Broader dialogue remains in the external Agent conversation. Each Work has at
most one current Critique document under `Critiques/`; later rounds update it.
Critique source is read-only in Scholium but remains ordinary externally
editable Markdown.

### 11.3 Critique method and form

Critique has no fixed product operation, academic profile, result schema, or
registered method. The researcher may select a personal method Skill.
Whole-Work assessment may
address material claims, arguments, method fit, coverage, contribution,
objections, implications, alternatives, and revision priorities as warranted
by genre and inspected evidence. Passage assessment remains bounded.

A Critique can include Overall Assessment, Strengths, Major Concerns, Source
Support, Objections and Alternatives, Revision Priorities, Specific Findings,
and Evidence Limits when useful; this is not a required schema. **Traced**,
**Untraced**, **Disputed**, and **Beyond Sources** are attributed Agent
judgments, not Scholium statuses. Critique never certifies maturity,
originality, publication readiness, or researcher competence and never
modifies the Work unless that separate edit is explicitly requested.
