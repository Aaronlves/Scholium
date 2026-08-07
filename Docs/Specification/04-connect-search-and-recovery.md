# Specification: Connect, Search, and Recovery

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Sections 12–14: Connections, Search, Attention, checkpoints, versions, and recovery; sibling chapters do not restate it.

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
direction and exact source without permanent badge clutter.

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

There is no All Workspace, Selected Roles, separate in-note Find, advanced
Search workspace, Quick Open, Recents, or Back/Forward history. Exact title,
alias, filename, and path matches rank above body matches, so Search also owns
known-note navigation. Library, Document tabs, and windows support ordinary or
parallel navigation.

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

Each window remembers its ordinary scope. `Command-F` requires an open note and
temporarily selects **This Note**. Dismissal restores the prior scope unless the
researcher explicitly changed it, cancels work, rejects stale results, and
clears query/results while retaining scope and saved searches.

Search has a closed **Note / Record** provider contract. Omitting `kind:` means
`kind:note`; `kind:record` selects Research Records. There is no `kind:any`,
mixed-provider ranking, dynamic provider registration, or hidden corpus state.
Application authorizes the visible scope before routing the parsed query. Scope
is never changed by query text, and adapters do not strip clauses or implement
a second parser.

The Note provider uses one deterministic local SQLite FTS5 corpus for the
active Triptych. **This Vault** is a predicate over that corpus and
**Triptych** uses it without a vault predicate, so BM25 statistics remain
comparable across Analyses, Topics, and Works. **This Note** instead searches
the current editor's exact in-memory revision and returns one row per
non-overlapping occurrence after the complete query is satisfied; invoking
Search never saves or indexes that buffer. Vault and Triptych results remain
one row per active Note. Set Aside and Trash are excluded from the persisted
corpus but remain searchable while they are the open **This Note**.

The shared finite grammar is space-as-AND, escaped exact phrases, trailing
prefix `*`, clause exclusion, Note lexical fields `title`, `alias`, `heading`,
`summary`, `body`, `author`, `year`, `tag`, `footnote`, and `path`, Note structured fields
`callout` and `has:broken-link`, and the clauses below. Structured filter-only
queries are valid. A query containing only excluded free text is invalid.
`status` remains unsupported. Unknown fields or canonical values, `vault`,
`role`, or `metadata`, malformed escapes, CJK prefix `*`, structured clause
exclusion, and unsupported OR, grouping, NEAR, regular-expression, fuzzy,
range, or nested syntax produce an inline diagnostic and never broaden
retrieval. One query is bounded to 16,384 UTF-16 code units and 64 tokens before
provider execution; exceeding either bound returns an editable diagnostic.

The Note provider adds only these structured clauses:

- `property:<key>` matches explicit presence of one literal top-level YAML key;
  `property:<key>=<value>` matches an entire source-bounded plain or quoted
  string scalar, or one entire source-bounded string sequence member, after
  versioned canonical Unicode, case, and whitespace normalization while
  preserving diacritic distinctions. Key identity is
  canonical-Unicode normalized and case-sensitive. Presence includes empty or
  nonstring values but explains that condition; equality excludes numbers,
  booleans, dates, nulls, mappings, nested keys, and mixed sequences without
  coercion. Literal addressability of an unknown YAML key grants it no
  canonical Property semantics, validation, philosophical meaning, or
  researcher judgment.
- A direct relation query contains exactly one `from-note:<anchor>` or
  `to-note:<anchor>` plus exactly one
  `relation:supports|opposes|neutral|incompatible`. `supports` and `opposes`
  preserve containing-Note direction; `neutral` and `incompatible` are
  undirected, so from/to return the same set and explain that fact. Resolution
  uses the ordinary stable identity/title/alias/path rules and reports
  ambiguity rather than guessing. Relation queries do not expand transitively.

Property and relation clauses apply only to the Note provider in **This
Vault** or **Triptych**. A complete query that includes a relation clause is an
AND query over the direct-neighbor set and any lexical clauses. If Graph is
unavailable, stale, or manifest-incompatible, that whole structured query
fails closed; its lexical clauses are not returned as a broader substitute.
An ordinary lexical query remains available from its last complete compatible
Note generation. Relation presence remains only a retrieval reason: it does
not certify evidence, successful support or opposition, truth, importance, or
researcher acceptance.

Search has no separately loaded direct-connection region. Researchers query
direct resolved Connections through the explicit relation clauses above, so
Graph compatibility, direction, explanation, failure, and App/CLI parity remain
part of one versioned Search contract rather than a parallel retrieval path.

The Record provider accepts unfielded lexical clauses plus `note`, `action`,
`skill`, `participant:researcher|agent`, and
`date:today|7d|30d`. Dates use `finishedAt` and the current local-calendar day:
`today` is that day, while `7d` and `30d` include that day plus the preceding
six or twenty-nine local calendar days. `note` resolves the ordinary stable
Note identity; `action` matches the retained public Action identity and `skill`
matches only the exact retained Method display name; `participant` requires an
attributed statement from that speaker.
Unfielded terms search context, Action, Skill, participant Note titles,
attributed statements, and Application-validated actually-used Material
titles. Note-only fields, Property, and relation clauses fail with a provider-
mismatch diagnostic.

One result row always represents one provider object. Record results are one
row per complete Research Record, sorted pinned first, then `finishedAt`
descending and UUID; lexical matching does not invent a cross-object relevance
score. A Record hit identifies the exact Record source fingerprint, matched
field, and, when applicable, statement UUID, speaker, and snippet. Opening it
uses the existing Triptych-keyed Research Records window and locates the Record
or statement. A Note hit retains vault-qualified identity, matched field,
reason, exact source range, and Note fingerprint. Neither provider may present
itself as the other.

Search indexes only visible semantic text and derived identity/filter fields,
never raw Markdown source or link destinations. Title, alias, heading, author,
year, tag, path, canonical `summary`, callout, footnote, and residual body text are
separate projections; the same heading, callout, or footnote content is not
also weighted as body. Links contribute displayed text and images contribute
alt text. Source mappings preserve exact UTF-16 ranges through Unicode
normalization. Production CJK retrieval uses the same deterministic
character-and-overlapping-bigram projection at index and query time, followed
by contiguous-substring verification; Apple language tokenization is not a
persisted Search contract.

Complete normalized title, alias, filename stem, and relative-path identity
precede one-corpus BM25, then normalized title, fixed Analyses/Topics/Works
order, and normalized path break ties. Exact identity candidates come directly
from ordinary tables and cannot be lost to a lexical candidate cutoff. Public
results explain matched field and rank reason without exposing raw BM25. The
interface caps at 100 rows and reports only `N Results` or `N+ Results`; Search
does not perform an expensive exact total count.

Each response binds a versioned query contract, Triptych generation, sorted
source-manifest hash, provider-specific source fingerprints, and freshness.
Note and Record generations remain distinct and never mix in one response. A
stale result must refresh rather than navigate. Building, refreshing, stale,
failed, provider-mismatch, ambiguous, not-applicable, and query-invalid are
distinct states; cancellation is not a failure. A failed routine refresh may
serve only its last complete compatible generation. One generation publishes
atomically or not at all, and no disposable index stores writable research
authority.

The parser exposes one typed capability description shared by field
completion, **Explain Query**, and CLI help. Baseline completion exposes only
fields and canonical values supported by the current contract; after an
explicit provider clause, it exposes only that provider's legal capabilities.
Completion edits only visible query text and creates no hidden token or chip.
Scope-first Property-key and Note-identity candidates are optional, not a
Foundation requirement. The Application may provide them only from the
currently authorized provider, scope, and authority after representative use
shows that the static capability description is insufficient for query
discovery. Such candidates remain bounded, edit only visible query text, and
never create hidden state, a second AST, or a second parser.
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
result.

App and CLI consume the same ordered Search response. CLI text and JSONL retain
the response contract version, provider, authorized scope, availability,
discriminated source identity, retrieval-lead classification, match reasons,
locator or source range, fingerprint, and freshness. Presentation wording may
differ, but adapters cannot change the result set or order, relation direction,
attribution, diagnostic meaning, or availability.

The optional canonical YAML `summary` is an independently explainable Note
field in this same projection, parser, ranking, source-range, freshness,
completion, Saved Search, App, CLI, incremental-update, and clean-rebuild
contract. Unfielded Note Search includes it; `summary:<text>` restricts lexical
matching to it. A summary hit returns the complete Note identity and exact
summary scalar range and opens the current Note, never a summary-only object.
It is a discovery lead that requires current-body/source inspection before a
substantive claim. Missing or source-unbounded summary values do not block the
Note or acquire a machine-generated fallback. Search never writes or
reconstructs the YAML field.

Future fields or providers require a versioned typed clause, discriminated
result identity, provider capability-table entry, source/freshness contract,
and App/CLI parity. This is an extension boundary, not a plugin framework.
Property contains/ranges/nested paths, Record arbitrary ranges, `section:`,
OR, vector search, embeddings, AI query interpretation or ranking,
automatic relation extraction, multi-hop expansion, context assembly, and
chat-style Search remain deferred. **Vector-Link** means only the explicit
researcher-visible relation markers in §12.

Research Context is one versioned, read-only Application capability over this
same Search owner, exact Note/section reading, explicit direct Relations,
canonical Properties, Research Records, and narrow researcher-state views
defined in Section 8. It authorizes Run and Triptych scope before provider
execution and returns only closed Source Reference Envelopes with owner,
identity, actor or unknown, role, exact revision, locator, authorized scope,
currentness, evidential layer, retrieval reason, and material limitation.
Current, Partial, Stale, Unavailable, and Invalid Query remain distinct.
The versioned Research Context response carries each Note result's typed
Foundation match reasons as well: a direct relation retains predicate, direction, anchor,
target, and exact Markdown occurrences, while a Property match retains its
key/value source ranges. These are Search-owner facts, not Agent-generated
explanations or a second Graph/Property interpretation.

Research Context creates no second parser, ranker, Property or relation
resolver, JSON scanner, persistent response, hidden Agent index, Researcher
State store, confidence score, or writable source. Record queries call the
same Application Record provider and preserve Record identity; Notes and
Records are not co-ranked. A Run may report which verified references actually
affected its result, but query, candidate, rank, provider ID, response, prompt,
and interaction telemetry never become a Research Record. A next Run resolves
and queries current owners again rather than inheriting an old response or
cache.

Attention may report possible-orphan conditions, Changed Since Settled, Broken
Connections, malformed metadata, unresolved identity, or **Material Changed
Since Use**. The latter requires one completed Synthesize record whose
agent-reported actually used Analysis set and exact recorded revision were
validated; selecting a Material is insufficient. If that Analysis later
changes, Attention may offer **Inspect**, **Resynthesize**, and **Leave
Unchanged**. Dismissal binds the material identity and revision pair, so a later
change may appear again.

Attention never says the Topic is wrong, outdated, or Superseded; uses age
alone; or issues an automatic philosophical verdict. Warnings are dismissible;
Settings controls duration, default seven days. The researcher retains
judgment.

## 14. Checkpoints, versions, and recovery

Autosaves create no visible versions. Current Actions create no automatic
whole-Triptych checkpoint. The researcher may choose **Create Checkpoint…** at
any time when a self-contained Triptych milestone is genuinely useful.

Every checkpoint is self-contained; includes all vaults and portable control
state needed to interpret them; lives outside the vaults; and never depends on
another checkpoint, even if filesystem cloning is used internally. Manual
checkpoints remain until the researcher deletes them.

File offers **Create Checkpoint…**, **Restore from Checkpoint…**, and **Reveal
Checkpoints in Finder**. Restore compares created, changed, moved, and deleted
files and supports selected-note or whole-Triptych restore. A full rollback
moves post-checkpoint files to Trash instead of permanently deleting them.
Restore writes new current source through the conflict-aware repository path;
Undo remains editor-session only.

There is no checkpoint-management screen or proprietary backup format. Finder
manages folders. Document, HTML, PDF, and DOCX export is deferred, not
permanently prohibited.

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

The completed source may still have a cleanup-only staging task when the swap
and readback succeeded but removal of the displaced preimage was unavailable.
That condition remains a committed save with a visible cleanup warning, not a
retryable source failure. On vault reopen, Scholium retries only after the
candidate is still canonical and the recorded staging name resolves to the
same regular-file device/inode and exact bytes. Cleanup first isolates that
exact entry inside a restricted same-parent directory and never deletes the
original spelling after isolation. An absent staging and isolated entry marks
the task complete; a substituted, changed, unsafe, or inaccessible path is
retained with a health diagnostic rather than treated as the recorded
preimage.
If a pre-swap authorization or atomic replacement fails, the same durable task
authorizes cleanup of only the unchanged staged candidate and remains available
for recovery when that cleanup cannot complete. A staging name that reappears
after isolation is likewise retained with the cleanup task and a health
diagnostic.

Settle may pin an exact entry as a researcher-selected settled
version without turning it into a truth claim. Temporary write recovery and
settled-version retention remain separate references over verified immutable
bytes. Invalid recovery metadata must not cause unrelated recoverable bytes to
be deleted or silently attributed to a note. Durable settled-pin
manifests, not the derived SQLite row, own pin identity and ordering; a missing
or field-mismatched row is rebuilt only from a fully validated manifest. Pin
order allocation is coordinated across local processes. If a validated
manifest cannot be projected unambiguously, its exact bytes remain protected
and automatic cleanup stops until the recovery authority is repaired.
