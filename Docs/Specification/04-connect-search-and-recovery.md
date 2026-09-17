# Specification: Connect, Search, and Recovery

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 12–14.

## 12. Connect and annotated-link syntax

| Markdown in A | Meaning |
| --- | --- |
| `[[B]]` | one unannotated authored occurrence from A to B |
| `[[B]]{{annotation}}` | the same occurrence with a source-owned annotation |

The annotation opener is the exact unescaped ASCII `{{` immediately adjacent
to the closing `]]` of an ordinary Wikilink; whitespace between them starts
ordinary Markdown instead. The first unescaped `}}` closes the annotation.
Annotation content may span lines and is authored Markdown. `\{{` and `\}}`
prevent delimiter recognition and preserve the exact authored bytes. Unescaped
nesting is invalid. An unclosed annotation, nested opener, or annotation with no
visible non-whitespace content produces a malformed-link-annotation diagnostic;
the ordinary Wikilink remains a link and every source byte remains visible and
editable. Literal delimiter text inside annotation content must be escaped.
Aliases, headings, and fragments remain valid ordinary Wikilink targets.

For example, `[[B|claim B]]{{why this passage matters}}` is one occurrence
whose link text is `claim B`, destination is B, and annotation belongs to its
source location in A. Moving or copying the syntax moves or copies the
annotation. Editing the destination Note never edits that annotation.

Every occurrence is directed by authorship: **Outgoing** from the containing
Note and **Incoming** at the resolved destination. Connect presents the same
source occurrence, annotation, and local context in either projection. An
Incoming annotation is read-only at the destination; editing it navigates to
the source occurrence. Only the source Note is modified. Scholium never
combines occurrences, infers argumentative predicates, or creates an undirected
edge. Connect and explicit Search predicates remain direct-link operations;
Related-Content may traverse the bounded paths specified in §13.

## 13. Search and Attention

The quick and advanced Search menus offer two scopes:

- **This Vault** searches present Notes in the selected role vault; and
- **Triptych** searches all present Notes.

The bounded **This Note** provider searches the open Note's unsaved buffer but
is not a selectable Search-menu scope. Document Find remains its separate
document-local operation below.

Search owns known-Note retrieval. §18.3 owns quick/advanced presentation and
session dismissal; neither presentation creates Recents or navigation history.

During live workspace opening, **This Note** performs exact lexical Search over
the current unsaved buffer. **This Vault** may reuse only lexical Note matches
from the last complete compatible index whose source fingerprint still equals
the authoritative opening snapshot and whose indexed stable identity, when
present, still resolves there; it reports **Limited**, excludes new, changed,
deleted, retargeted, or unverifiable Notes, and never publishes a partial
generation. Triptych Note scope, authored-property and structured clauses,
direct links, and operations requiring complete Note Search remain unavailable
until that complete generation publishes. Completion replaces the limitation
without moving focus or invalidating usable results.

Document Find is a separate document-local operation over the current unsaved
buffer. It supports literal text, case and whole-word options, count,
Previous/Next, and standard keyboard routes. Edit and Source add Replace
Current/All as single Undo transactions. Find creates no Search provider,
index, saved query, or navigation history.

Search operates on Notes. Optional leading `kind:note` makes that target explicit;
unsupported kinds are invalid and never broaden retrieval. Query text never
changes visible scope. App and Scholium MCP share one parser.

The Note provider uses one deterministic present-source corpus. It returns each
occurrence for This Note and one row per Note for broader scopes. Its finite
grammar supports:

- uppercase `AND`, `OR`, unary `NOT` or `-`, and parentheses, with precedence
  NOT > AND > OR; whitespace between conditions means AND;
- exact phrases and a trailing prefix `*`; quoted operators are literal text,
  while lowercase operator words remain ordinary search terms;
- lexical fields `title`, `alias`, `heading`, `summary`, `body`, `author`,
  `publication_date`, `keyword`, `footnote`, `link_annotation`, and `path`;
- `callout` and `has:broken-link`;
- `property:<key>` presence or exact scalar/list-member text equality; and
- independently resolved direct `from-note` and `to-note` predicates.

Lexical and canonical fields accept groups, such as `title:(意向性 OR intentionality)`
and `callout:(cite OR flag)`. Every leaf inherits that field; an inner field override
is invalid. Property and link alternatives combine complete predicates, for example
`(property:status=draft OR property:status=revised) AND NOT to-note:Objection`.
`kind:note` is a single global prefix, never a Boolean operand or scope override.

Broad scopes allow pure exclusion. This Note admits lexical predicates and paragraph groups only and
requires a positive lexical condition in every alternative after resolving negation.
It returns all distinct positive occurrences from successful alternatives, ordered by
exact source position; exclusions supply no invented occurrence.

`paragraph:(E)` requires at least one ordinary top-level body paragraph satisfying E.
The canonical Markdown parser supplies paragraph boundaries; visual wrapping and fixed
text windows do not. Headings, lists, quotations, code, HTML, display mathematics,
YAML, footnotes and embedded Note contents are outside this paragraph corpus. A link's
own annotation text participates in its owning paragraph using the existing source
projection. Inside a paragraph group, only unfielded text and Boolean composition are
allowed, and every alternative must contain a positive text condition. Nested paragraph
groups and Note-level fields are invalid. `paragraph:(A NOT B)` and
`NOT paragraph:(A AND B)` retain their distinct existential meanings. Every predicate
is checked against the complete paragraph, including its tail; excerpts never prove
absence. Unprovable body boundaries yield unknown. This Note can return positive
occurrences inside successful paragraph groups. Broader scopes retain one Note row
with all distinct successful paragraph ranges and reveal locations in bounded batches.
MCP pages those locators per returned Note independently of Note pagination.

Term groups are researcher-owned input helpers stored locally with Search preferences,
not inside research vaults. A named group contains 1–24 single-line literal alternatives;
Insert Term Group writes an explicit quoted OR expression at a valid query caret.
The entire insertion must parse before replacing the draft. Changing or deleting a
group never changes existing query text or Saved Searches. The app neither infers
synonymy from aliases nor translates or expands terms automatically. Names and terms
are bounded to 80 and 512 UTF-16 units respectively; the collection holds at most 128
groups. Edits compare the stored group with the version opened for editing; a changed
or unreadable collection preserves its bytes and offers reload rather than overwrite.

Property Search reads user-authored top-level YAML fields without requiring a
field catalog, schema profile, or reserved research meaning. It never migrates
or edits source.
Keys are case-sensitive after canonical Unicode normalization. Identifier keys
may be unquoted; other nonempty single-line string keys use double quotes, for
example `property:"研究 问题"="行动理由"`. A quoted dot is a literal key character,
not a nested path. Values use the shared text normalization and whole-value
matching, including direct scalar members of mixed lists. Numeric and Boolean
scalars match their decoded text spelling, not arithmetic or inferred dates.
Nulls and containers support presence; mappings, aliases, nested members and
unbounded scalars do not acquire invented equality values. Repeated decoded
YAML keys are ambiguous. Invalid or unclosed YAML, unbounded keys, and ambiguous
requested keys yield unknown, not absence. Unbounded values yield unknown equality
unless a known list member already proves a match.
Authored YAML matches retain exact key/value source ranges. Query, indexing,
completion and source navigation share that read-only projection.

Predicates evaluate to true, false or unknown. NOT preserves unknown; AND is false
when any operand is false, otherwise unknown when any is unknown; OR is true when
any operand is true, otherwise unknown when any is unknown. Only true Notes enter
results. The response separately counts indeterminate authorized, eligible Notes;
this is distinct from incomplete index availability. Unresolved authored links cannot
prove the absence of a direct relation. Missing or ambiguous query anchor identities,
or a Graph/Search manifest mismatch, reject the complete query, including OR branches.

Unknown fields or canonical values, malformed syntax, regex/fuzzy/range syntax and
CJK prefixes produce an inline diagnostic and never broaden retrieval. Queries are
bounded to 16,384 UTF-16 units, 64 lexer tokens, and eight nested groups. A field/value
clause is one token; operators and each parenthesis are separate tokens. Conditions
require whitespace or explicit operators between them; quoted delimiters stay literal.

Every Note result identifies its provider object, stable identity, exact source
fingerprint, matched field/reason, and available locator/range.

Search indexes visible semantic text, valid link-annotation content, and canonical
fields, not raw delimiters or link destinations. Annotation hits use the distinct
`link_annotation` field, identify the owning occurrence and source range, and remain
discovery candidates only: annotation prose never creates a predicate or a second edge.
For conjunctive queries, exact filename Note title, alias, and path identity outrank
lexical matches. An OR expression does not concatenate alternatives into a fake identity.
An Analysis academic title remains a weighted `title` lexical match, not Note identity.
Only predicates from successful alternatives contribute match reasons, highlights and
lexical rank; duplicate normalized predicates add no boost. Lexical contributions use
one corpus and are summed before global limiting and pagination. Role-specific
field weighting emphasizes source titles and summaries in Analyses, concept
titles, aliases, tags and headings in Topics, and headings and prose in Works.
This changes lexical ordering only: exact identity tiers, query truth, scope,
source locators and explicit field predicates remain authoritative. No whole
vault receives a universal relevance or evidential-authority bonus.
Normalized Note title,
role order, and path provide stable ties. Results explain matched field and rank reason
without exposing internal scores. Exclusion-only results have no invented source range. CJK uses deterministic projection and
substring verification.

The versioned **Related-Content Retrieval** contract is an internal,
nonpersistent discovery operation over exact current Notes and optional passage
or request focus. It returns bounded Analysis, Topic and Work candidates through separate
one- and two-step connection, exact-identity, and lexical channels, preserving typed
reasons and source fingerprints. It never synthesizes a relation, summary or
evidence claim; internal ranking values are not confidence. Search and Graph must share one complete source
manifest before connection candidates are executable. The exact unsaved seed
replaces its saved outgoing links for this request only. Paths retain each
authored occurrence and traversal direction, including incoming traversal;
unresolved, ambiguous and unauthorized nodes are never traversed.
Short paths refine locally relevant material with bounded proximity. Distinct
intermediates may contribute, but high-degree intermediates are discounted and
repeated or reciprocal links do not multiply a connection's contribution.
Lexical candidates remain available independently of connectivity. Graph
context cannot replace paragraph relevance or imply support, opposition or
evidence; results expose the direct connection or intermediate Note in Help
and accessibility without displaying scores or creating new source relations.
Related-Content ranks Notes by authored context and selects paragraphs within
those Notes. Field-normalized BM25F treats authored annotations and Wikilink
labels as explicit context. Role-specific field weighting emphasizes source
titles, summaries and annotations in Analyses; concept titles, keywords and
headings in Topics; and headings and prose in Works. Works remain researcher
writing and arguments, never external-source evidence by virtue of retrieval.
The current seed Note is excluded, including its saved revision while its unsaved
buffer supplies context. Every role still requires a locally matching paragraph.
Role weighting grants neither philosophical truth nor an inferred dialectical
role, and cannot substitute for focus coverage.
`summary`, `keywords`, `title` and `aliases` inform Note ranking; YAML values
are never standalone recommended material. Author, date, path and unknown
properties do not contribute to default topic ranking. Explicit Search fields
retain their existing semantics. Incoming annotation text is never transferred
to its target, and each authored occurrence contributes once.
An explicit focus supplies scoring terms rather than unrelated source-Note terms.
Bounded term selection spans the complete focus, retains adjacent term pairs,
and gives explicitly quoted wording a bounded share of the query. Quoted phrase
order and negation remain authored text; extraction invents no synonym or thesis.
Local relevance combines information-weighted distinct-term coverage, normalized
paragraph BM25F and explicitly quoted phrase matches. Repetition and metadata
cannot independently manufacture local relevance. Multi-term focuses normally
require multiple locally matching terms; a distinctive single term may qualify
when it supplies most of the focus's lexical information. Negation alone cannot
qualify through that exception. These are lexical features, not conceptual or
argumentative judgments. Note context refines this local relevance through
separately normalized Note scores. Explicitly naming a Note in the focus supplies
bounded identity context, never a role-wide authority bonus. Raw Note and paragraph
scores are never added.
Every eligible lexical source is checked before paragraphs are selected; bounded
Note channels never truncate this source set. A Note is eligible for display
only when it contains an actual locally matching paragraph, including authored
link-annotation wording. Property-only matches do not manufacture a paragraph.
Without an explicit focus, BM25F supplies relevance. A bounded final rerank favors
unrepresented research roles and reduces near-duplicate concentration only among
comparably relevant material. Roles receive no mandatory slots or inferred
philosophical status. Canonically identical readable passages, ignoring whitespace,
appear once across Notes; the retained passage keeps one exact source identity.
Near copies receive a bounded ranking penalty, never rewritten text or a merged
source identity. Opposing claims remain distinct materials. Results first offer
one paragraph per Note, then additional paragraphs within per-Note and overall
bounds. Research diversity is not inferred agreement, opposition or evidence.
Paragraphs retain exact source ranges and bytes, separate readable text, bounded
match-centered excerpts and checked UTF-16 highlight ranges. These projections
never substitute for source locators. Retrieval creates no paragraph identities, embeddings,
argumentative predicates or inferred evidence. Authored paragraph anchors follow §5.4
and are excluded from searchable prose.
Research usefulness is evaluated by whether results help the researcher clarify
concepts, examine arguments, compare alternatives or investigate objections.
Lexical ranking does not certify any of those roles or the correctness of a Note.

Ordinary Search returns bounded slices, filtered totals and continuations.

Every provider response binds contract version, provider, authorized scope,
its own generation, and freshness. **Building**, **Limited**, **Partial**,
**Stale**, **Unavailable**, **Invalid**, and **Cancelled** remain distinct. A
failed refresh may retain only that provider's last complete compatible
generation. Derived indexes remain disposable and never writable authority.

The parser exposes one typed capability description used by completion, **Explain
Query** and the MCP tool schema. Completion edits only visible query text.
Saved Searches store only raw query, visible scope, and contract version; they store no
AST, resolved identity, result, or generation. Only the current definition format is
accepted; there is no compatibility, migration, or version-review workflow. Saved
queries use the ordinary current parser and execution path. Unsupported or invalid
saved bytes remain unchanged and nonexecuting; a damaged Saved Search store has a confirmed archive-and-reset route
that never changes vault content.

App and Scholium MCP consume the same result identity,
reasons, provenance, availability, and freshness. Presentation may reword but
never reparse, reorder, broaden, combine rankings, or change link direction.

Authored YAML `summary` participates as an explainable Note field with its exact
scalar range, including bounded literal and folded block scalars. `keywords`
retains its string-list lexical projection. These projections require no profile
registration; they never rename or interpret other custom keys. A hit opens the complete current Note and is only a discovery
lead. Missing or unbounded values receive no generated substitute. Search never
writes or reconstructs YAML.

New providers or fields require a versioned typed clause, discriminated result
identity, capability entry, source/freshness contract, and App/MCP parity.
Vector search, embeddings, AI interpretation/ranking, automatic classification
extraction, arbitrary-depth graph expansion, arbitrary structured paths, and
chat-style Search remain outside the target. Bounded Related-Content paths do
not change explicit Search predicates or add automatic source links.

Scholium MCP reuses this owner under
[§8.3](03-agent-collaboration-and-workflows.md#83-tool-contract) and adds no
second parser, resolver, index, or confidence score.

**Notifications** combines Agent Changes, derived Settlement reminders, and
Triptych-wide structural Attention. These remain separate owners and dismissal
semantics. Structural Attention may report:

- **Possible Orphan** only when a Note has no resolved incoming or outgoing
  link occurrence;
- Broken/Ambiguous Connections, malformed YAML, or unresolved identity;
  and
- source/index drift or failure that has an exact mechanical basis and safe
  repair.

Attention never declares a Note wrong, outdated, Superseded, accepted, or
philosophically deficient. Warnings are dismissible against their exact
identity/revision and may recur after a later change.

Changed Since Settle reminders are not structural Attention. Dismiss hides the
reminder without changing Settlement; a later source change may produce a new
reminder under §7.

## 14. Save, Agent changes, and recovery

Autosave creates no visible version history, Checkpoint product, whole-Triptych
rollback, or settled-version store.

§8.4 owns Agent Change retention and eligible direct Undo; §6 owns system-Trash
receipts and Finder recovery. Neither is an autosave version history.

Interrupted-save recovery remains machine-local and source-specific. When
startup proves a distinct retained candidate, **Recovery** shows its Note,
expected and candidate revisions, reason, and read-only exact source. The
researcher may copy or reveal it. **Restore Candidate…** flushes open editors
and replaces canonical source only if the current revision still equals the
recorded expectation. Changed, missing, unsafe, or unverifiable source is never
overwritten or recreated.

If another writer changes the source during final replacement, preserve the
displaced bytes before releasing replacement evidence. This is **Autosave Failed**
with Recovery, even when the attempted source is now canonical. Recovery identifies
the displaced revision as its candidate and the attempted revision as its restore
precondition; both remain inspectable. Neither interruption nor restart may silently
discard the displaced version or automatically overwrite a further external edit.

System-Trash receipt semantics are owned by §6 and recovery presentation by
§18.6; neither restore-candidate handling nor source recovery may reuse its
forward plan as source-replacement authority.

Watchers and sync observations are refresh evidence only. External absence or
restoration passes through ordinary identity and exact-byte reconciliation and
never authorizes changes to research prose.

After Saving, a writable Document has exactly three outcomes:

- **Saved** only when canonical Markdown readback exactly matches the validated
  candidate and the replaced source is accounted for; success is silent;
- **Conflict** when the expected revision differs, retaining the buffer and
  routing to comparison; or
- **Autosave Failed** when commit, exact readback, or displaced-source safety
  cannot be proven, retaining the buffer and any useful recovery candidate.

Filesystem metadata, temporary replacement entries, directory synchronization,
and app-owned housekeeping are not Document success predicates. Once exact
readback and displaced-source reconciliation prove the source, they do not
create a warning or invite another write. Settle stores only its portable fingerprint marker and is never recovery
source.
