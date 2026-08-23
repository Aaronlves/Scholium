# Specification: Connect, Search, and Recovery

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 12–14.

## 12. Connect and Connection syntax

| Markdown in A | Meaning |
| --- | --- |
| `[[B]]` | neutral, undirected A—B |
| `+[[B]]` | A supports B |
| `-[[B]]` | A opposes B |
| `?[[B]]` | undirected incompatibility A—B |

`+` and `-` describe the containing Note's stance toward the target: support
is favorable argumentative direction, while opposition is an authored
negative stance without a claim of strict contradiction. `?` instead records
one mutual incompatibility: both Notes cannot be retained together in the
researcher's current account, without asserting which should be rejected or
that either is false. None certifies that the relation succeeds, counts as
evidence, or is accepted beyond its explicit authoring. The inverse phrases
**Supports This Note** and **Opposes This Note** are derived only when the
current Note is the object; incompatibility has no direction or inverse label.

These are the only Vector-Link forms. Aliases, headings, and fragments remain
valid. Scholium has no reverse-support or directed-question relation. Preserve
research-file bytes and never rewrite or reinterpret a marker through
heuristics. Never infer support, opposition, or incompatibility from keywords,
proximity, folders, or multi-hop paths. Incoming and Outgoing views show
direction and exact source without permanent badge clutter. The two views are
presentation projections over the same direct graph: Outgoing contains edges
whose containing Note is the current Note, while Incoming contains edges whose
target is the current Note. Neutral and Incompatible are undirected, so they
appear in both views with the same source anchor and a clear accessible
explanation that the relation is shown in both directions. No third Combined or
All direction is exposed.

## 13. Search and Attention

One Search field has exactly three visible scopes. Their meaning is specific to
the selected provider:

- **This Note** searches occurrences in the open Note, or Research Records in
  which that Note is a participant;
- **This Vault** searches active Notes in the selected Analyses, Topics, or
  Works vault, or each Research Record with at least one participant in that
  vault, returned once; and
- **Triptych** searches all active Notes or all Research Records in the
  Triptych.

There is no All Workspace, Selected Roles, advanced Search workspace, Quick
Open, Recents, or Back/Forward history. Exact title, alias, filename, and path
matches rank above body matches, so Search also owns known-note navigation.
Library, Document tabs, and windows support ordinary or parallel navigation.

Search is a centered, compact Spotlight-style command surface. Scope is visible
before typing; empty Search shows no results sheet. Text expands a bounded
native result list vertically, not into a workspace-scale panel. It follows
appearance and accessibility settings without copying Spotlight categories or
Finder actions. Opening Search does not dim, tint, or blur the retained
workspace or native toolbar. A transparent outside-click target may cover the
workspace content; the opaque Search surface, focus, boundary, and restrained
elevation establish its foreground hierarchy.

The transient keyboard or pointer result target is not document selection. It
uses one full-width warm opaque row with a narrow accent leading rule, exposes
the native selected accessibility trait, and retains native scrolling, focus,
and keyboard mechanics. Search never layers a partial dark system-selection
slab behind only part of a result row.

Each window remembers its ordinary scope. **Search…** uses `Shift-Command-F`.
Dismissal cancels work, rejects stale results, and clears query/results while
retaining scope and saved searches.

Document Find is a separate lightweight editor operation rather than a Search
provider, result, index, saved query, or navigation owner. `Command-F` opens one
inline Find bar for the current unsaved buffer. It supports literal text,
case-sensitive and whole-word options, a current/total match count, Previous and
Next, and `Command-E`, `Command-G`, `Shift-Command-G`, and Escape with their
standard meanings. Review exposes Find only. Edit and Source additionally expose
Replace Current and Replace All; each accepted replacement is one editor
transaction and one Undo event. A mode change retains the query but immediately
recomputes against the same buffer and disables replacement in Review. Closing
the bar restores focus and selection to the editor without changing Search
scope, saving source, or creating history.

Search has a closed **Note / Record** provider contract. Omitting `kind:` means
`kind:note`; `kind:record` selects Research Records. There is no `kind:any`,
mixed-provider ranking, dynamic provider registration, or hidden corpus state.
Application authorizes the visible scope before routing the parsed query. Scope
is never changed by query text, and adapters do not strip clauses or implement
a second parser.

The Note provider has one deterministic present-source Triptych corpus. **This Vault**
restricts that corpus to the selected role; **Triptych** does not. **This Note**
instead searches the current editor revision and returns each non-overlapping
occurrence without saving it. Vault and Triptych return one row per present Note.

The shared finite grammar is space-as-AND, escaped exact phrases, trailing
prefix `*`, clause exclusion, Note lexical fields `title`, `alias`, `heading`,
`summary`, `body`, `author`, `publication_date`, `keyword`, `footnote`, and
`path`, Note structured fields `callout` and `has:broken-link`, and the clauses
below. `keyword` addresses authored `keywords`. Structured filter-only
queries are valid. A query containing only excluded free text is invalid.
`status` remains unsupported. Unknown fields or canonical values, `vault`,
`role`, or `metadata`, malformed escapes, CJK prefix `*`, structured clause
exclusion, and unsupported OR, grouping, NEAR, regular-expression, fuzzy,
range, or nested syntax produce an inline diagnostic and never broaden
retrieval. One query is bounded to 16,384 UTF-16 code units and 64 tokens before
provider execution; exceeding either bound returns an editable diagnostic.

The Note provider adds only these structured clauses:

- `property:<key>` is the stable query spelling for one canonical structured
  field. It matches a Scholium Metadata field for the Note's role or one of the
  authored YAML fields `summary` and `keywords`; unknown or retired YAML keys
  are never query candidates. `property:<key>=<value>` matches an entire
  normalized string value or one complete string-sequence member. Authored
  YAML matches retain exact key and value source ranges. Managed Metadata
  matches name their portable record revision and never claim a Markdown
  source range. Key identity is canonical-Unicode normalized and
  case-sensitive. Presence includes an empty or nonstring canonical value but
  explains that condition; equality excludes nulls, mappings, nested values,
  and mixed sequences without coercion. The query spelling grants no
  philosophical meaning or researcher judgment.
- A direct relation query contains exactly one `from-note:<anchor>` or
  `to-note:<anchor>` plus exactly one
  `relation:supports|opposes|neutral|incompatible`. `supports` and `opposes`
  preserve containing-Note direction; `neutral` and `incompatible` are
  undirected, so from/to return the same set and explain that fact. Resolution
  uses the ordinary stable identity/title/alias/path rules and reports
  ambiguity rather than guessing. Relation queries do not expand transitively.

Structured-field and relation clauses apply only to the Note provider in **This Vault**
or **Triptych**. A relation clause is ANDed with any lexical clauses over the
direct-neighbor set. If the current Graph cannot answer it, the complete query
fails closed rather than returning a broader lexical substitute. Relation
presence remains a retrieval reason, never evidence, truth, importance, or
researcher acceptance. Direct Connections use these clauses rather than a
second Search region or parser.

The Record provider accepts unfielded lexical clauses plus `note`, `action`,
`skill`, `participant:researcher|agent`, and
`date:today|7d|30d`. Dates use `finishedAt` and the current local-calendar day:
`today` is that day, while `7d` and `30d` include that day plus the preceding
six or twenty-nine local calendar days. `note` resolves the ordinary stable
Note identity; `action` matches the retained public Action identity and `skill`
matches only the exact retained Method display name; `participant` requires an
attributed statement from that speaker.
Unfielded terms search the frozen Record Title, Action, Skill, participant Note titles,
attributed statements, and Application-validated actually-used Material
titles. Note-only fields, Metadata, and relation clauses fail with a provider-
mismatch diagnostic.

One result row always represents one provider object. Record results are one
row per complete Research Record, sorted by `finishedAt` descending and UUID by
default;
lexical matching does not invent a cross-object relevance
score. A Record hit identifies the exact Record source fingerprint, matched
field, and, when applicable, statement UUID, speaker, and snippet. Opening it
uses the existing Triptych-keyed Research Records window and locates the Record
or statement. A Note hit retains vault-qualified identity, matched field,
reason, exact source range, and Note fingerprint. Neither provider may present
itself as the other.

Search projects visible semantic text and identity/filter fields, never raw
Markdown source or link destinations. Title, alias, heading, author,
publication date, tag,
path, `summary`, Callout, footnote, and residual body remain distinguishable;
links contribute displayed text and images contribute alt text. Source mappings
retain exact ranges. CJK uses the same deterministic projection and contiguous-
substring verification at index and query time.

Complete title, alias, filename, and path identity precede lexical ranking;
normalized title, fixed Analyses/Topics/Works order, and normalized path break
ties. Exact identity candidates cannot be lost to a lexical cutoff. Public
results explain the matched field and rank reason without exposing internal
scores.
Ordinary cross-provider Search caps at 100 rows and reports only `N Results` or
`N+ Results`; it does not perform an expensive exact total count. The dedicated
Research Records collection is a bounded exception within the same parser and
provider ownership: it requests 100-row slices, receives the exact filtered
Record total, and may request provider-owned Record, Action, or finished-date
ordering before slicing. Reading Leads applies the same 100-row presentation
slices to its already-complete derived occurrence set. Neither collection
creates a second query language, parser, or retrieval owner.

Each response binds the query contract, authorized scope, provider-specific
source identity, and freshness. Note and Record generations never mix. A stale
result refreshes rather than navigating. Building, refreshing, stale, failed,
provider-mismatch, ambiguous, not-applicable, query-invalid, and cancellation
remain distinct. A failed refresh may retain only its last complete compatible
generation; no disposable index stores writable research authority.

The parser exposes one typed capability description shared by field
completion, **Explain Query**, and CLI help. Baseline completion exposes only
fields and canonical values supported by the current contract; after an
explicit provider clause, it exposes only that provider's legal capabilities.
Completion edits only visible query text and creates no hidden token or chip.
The Application supplies bounded scope-first Metadata-key candidates only from
the currently authorized Note provider and visible scope. After
`property:<key>=`, a controlled-value field supplies its current allowed values.
Scope-first Note-identity candidates remain an optional extension. All such
candidates edit only visible query text and never create hidden state, a second
AST, or a second parser.
The Application response carries the typed explanation used by App and CLI.
Presentation may format that response but must not parse the query again or
construct a second interpretation. Explain reports provider, scope, clauses,
direction, normalization, ordering, and limitations without executing an
alternate query.

Saved Searches persist only raw query, visible scope, and query-contract
version; they store no AST, resolved identity, result, or generation and are
re-evaluated against current authority. A saved definition remains executable
when its current query grammar, interpretation and explanation, ordering,
response compatibility, and security boundary are unchanged. A contract
version change requires **Needs Editing** only when one of those semantics
would change; a purely additive capability is compatible only when the current
contract explicitly declares that the existing definition is unaffected. No
definition is silently rewritten or executed under changed semantics. An
invalid, ambiguous, or undecodable definition remains byte-unchanged and
nonexecuting. Revoked scope or a deleted source never permits a retained old
result. If the machine-local Saved Search document itself is undecodable,
Search exposes a confirmed archive-and-reset action. It atomically preserves
the exact file under a unique sibling recovery name before returning to an
empty Saved Searches list; it never replaces a valid concurrent file or
changes vault content.

App and CLI consume the same ordered Search response. CLI text and JSONL retain
the response contract version, provider, authorized scope, availability,
discriminated source identity, retrieval-lead classification, match reasons,
locator or source range, fingerprint, and freshness. Presentation wording may
differ, but adapters cannot change the result set or order, relation direction,
attribution, diagnostic meaning, or availability.

The optional authored YAML `summary` is an independently explainable Note
field in this same projection, parser, ranking, source-range, freshness,
completion, Saved Search, App, CLI, incremental-update, and clean-rebuild
contract. Unfielded Note Search includes it; `summary:<text>` restricts lexical
matching to it. A summary hit returns the complete Note identity and exact
summary scalar range and opens the current Note, never a summary-only object.
It is a discovery lead that requires current-body/source inspection before a
substantive claim. Missing or source-unbounded summary values do not block the
Note or acquire a machine-generated fallback. Search never writes or
reconstructs the YAML field. Search contract v9 adds managed Metadata values
with nullable Markdown source ranges; old disposable index schemas are rebuilt
instead of entering a compatibility path.

Future fields or providers require a versioned typed clause, discriminated
result identity, provider capability-table entry, source/freshness contract,
and App/CLI parity. This is an extension boundary, not a plugin framework.
Structured-field contains/ranges/nested paths, Record arbitrary ranges, `section:`,
OR, vector search, embeddings, AI query interpretation or ranking,
automatic relation extraction, multi-hop expansion, context assembly, and
chat-style Search remain deferred. **Vector-Link** means only the explicit
researcher-visible relation markers in §12.

Research Context reuses this Search owner under the scope and provenance rules
in [§8.2](03-research-actions-and-workflows.md#82-agent-entry-local-pairing-layered-delivery-and-research-context).
It retains Search's typed Metadata provenance and direct-relation predicate,
direction, anchor, target, and Markdown occurrences. It creates no second
parser, ranker, Metadata/Relation resolver, persistent response, hidden Agent
index, confidence score, or writable source.

Attention is one Triptych-owned queue. Presentation may open the complete
Triptych queue or add an exact current-Note subset; those views create no
Vault-owned queue, diagnostic owner, or philosophical status. Attention may
report a **Possible Orphan** only when a Note has no resolved incoming or
outgoing connection. A neutral, same-vault, or cross-vault connection is
sufficient to prevent that condition; Attention does not require an explicit
Vector Link or cross-vault relation. It may also report Changed Since Settled,
Broken Connections, malformed metadata, unresolved identity, or **Material
Changed Since Use**.
The latter requires one completed Synthesize record whose
agent-reported actually used Analysis set and exact recorded revision were
validated; selecting a Material is insufficient. If that Analysis later
changes, Attention may offer **Inspect**, **Resynthesize**, and **Leave
Unchanged**. Dismissal binds the material identity and revision pair, so a later
change may appear again.

Attention never says the Topic is wrong, outdated, or Superseded; uses age
alone; or issues an automatic philosophical verdict. Warnings are dismissible;
Settings controls duration, default seven days. The researcher retains
judgment.

## 14. Save, Agent changes, and recovery

Autosaves create no visible version history. Scholium has no Triptych
Checkpoint product, whole-Triptych rollback, or settled-version store.
Document, HTML, PDF, and DOCX export is deferred, not permanently prohibited.

For a writable Run, machine-local Agent change evidence retains only each
modified Note's exact starting and final Agent revisions. It exists solely for
the Record's exact diff and direct Undo, is bound to that Run and stable Note
identity, and grants no write authority. Direct Undo follows §10.5 and uses the
ordinary repository save path rather than a second history system.

Ordinary pre-write recovery state remains invisible and supports exact
save/conflict recovery for the Notes actually written; it is not an
application-authored account of the research. When startup verifies that an
interrupted save left the expected revision canonical and retained a distinct
candidate, the existing **Recovery** surface lists that one vault-qualified
candidate with its Note path, expected and candidate revisions, reason, and
read-only exact source. The researcher may copy it or reveal its machine-local
file without granting write authority. **Restore Candidate…** first flushes
every open editor in the Triptych, then revalidates the exact transaction
identity and current source revision through the repository. It replaces source
only while the canonical Note still equals the recorded expected revision,
using the ordinary prewrite-protected save path. A changed, missing, unsafe, or
unverifiable source is never overwritten or recreated; the candidate remains
available for inspection and copying. If the candidate is already canonical,
Recovery verifies that fact and removes only the completed machine-local
record.

Portable Metadata recovery is separate from Markdown save recovery and
whole-control recovery. Workspace preflight identifies one invalid record by
its direct filename, exact byte fingerprint, optional embedded Note identity,
and failure class. After confirmation, Scholium archives only that unchanged
regular file to a unique non-record sibling and retries ordinary preflight. A
missing, replaced, or changed file stops the operation for reload; no
source, valid neighboring Metadata record, settings file, identity file, or
complete `.scholium` directory is moved.

System-Trash deletion recovery is a separate visible forward plan, not a save
candidate or source backup. It shows the original source items, known resulting
system-Trash paths, per-item receipt state, affected active Discussions, and
associated finished Records. When every source receipt is proven moved, Retry
continues only pending Discussion, exact-fingerprint Record, Note Review, and
machine-local evidence cleanup. When a native result is outcome-unknown and no
Discussion or Record cleanup has committed, **Retain Records and Resolve**
releases the deletion gate and removes only Scholium's plan after researcher
inspection; it does not move, restore, or erase source. A system-Trash plan
never exposes a Scholium restore or file-erasure control.

Filesystem watchers and sync observations are refresh evidence only. Source
absence without an Application-authored deletion plan closes or refreshes
affected source projections and may surface identity diagnostics, but it never
authorizes active Discussion or finished Record deletion. Finder restoration
is likewise an external arrival that must pass ordinary identity and exact-byte
reconciliation; it cannot recreate a deleted Record.

An ordinary Note save has exactly three terminal Document outcomes after
Saving: **Saved**, **Conflict**, or **Autosave Failed**. Saved requires the
current canonical Markdown to read back exactly as the validated candidate and
is otherwise silent. Conflict means the expected revision no longer matches;
Scholium preserves the editor buffer and routes to comparison rather than
overwriting the external revision. Autosave Failed means replacement did not
complete or exact canonical readback cannot prove the candidate; Scholium
retains the editor buffer and any independently useful recovery candidate.

There is no fourth "saved with a technical warning" outcome. Exact source,
containment, regular-file identity, expected revision, replacement, and
canonical readback remain save authority. Filesystem metadata equality,
parent-directory synchronization, temporary replacement entries, and
machine-local recovery cleanup are not Document success predicates and never
turn a readback-proven commit into a warning or invite another write. Redundant
machine-local housekeeping remains invisible and automatic; it may remove only
an exact app-owned artifact and never canonical source or an unknown file by
guesswork.

Settle stores one portable fingerprint-bound marker per Note and no source
bytes. It is not a recovery source, version, or retention policy. Storage and
projection mechanics belong to [Source Storage and Read Models](../Architecture/05-source-storage-and-read-models.md).
