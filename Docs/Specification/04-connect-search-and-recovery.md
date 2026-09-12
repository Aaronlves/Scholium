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
combines occurrences, infers argumentative predicates, creates an undirected
edge, or expands a multi-hop path.

## 13. Search and Attention

Search has three visible scopes:

- **This Note** searches the open Note's unsaved buffer;
- **This Vault** searches present Notes in the selected role vault; and
- **Triptych** searches all present Notes.

Search owns known-Note retrieval. §18.3 owns quick/advanced presentation and
session dismissal; neither presentation creates Recents or navigation history.

During live workspace opening, **This Note** performs exact lexical Search over
the current unsaved buffer. **This Vault** may reuse only lexical Note matches
from the last complete compatible index whose source fingerprint still equals
the authoritative opening snapshot and whose indexed stable identity, when
present, still resolves there; it reports **Limited**, excludes new, changed,
deleted, retargeted, or unverifiable Notes, and never publishes a partial
generation. Triptych Note scope, managed-property and structured clauses,
direct links, and operations requiring complete Note Search remain unavailable
until that complete generation publishes. Completion replaces the limitation
without moving focus or invalidating usable results.

Document Find is a separate document-local operation over the current unsaved
buffer. It supports literal text, case and whole-word options, count,
Previous/Next, and standard keyboard routes. Edit and Source add Replace
Current/All as single Undo transactions. Find creates no Search provider,
index, saved query, or navigation history.

Search operates on Notes. Optional `kind:note` makes that target explicit;
unsupported kinds are invalid and never broaden retrieval. Query text never
changes visible scope. App, CLI, and Scholium MCP share one parser.

The Note provider uses one deterministic present-source corpus. It returns each
occurrence for This Note and one row per Note for broader scopes. Its finite
grammar supports:

- space-as-AND, exact phrases, a trailing prefix `*`, and clause exclusion;
- lexical fields `title`, `alias`, `heading`, `summary`, `body`, `author`,
  `publication_date`, `keyword`, `footnote`, `link_annotation`, and `path`;
- `callout` and `has:broken-link`;
- `property:<key>` presence or exact scalar/list-member text equality; and
- exactly one direct `from-note` or `to-note` anchor.

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
YAML keys are ambiguous and excluded. Invalid YAML creates no authored-property hits.
Authored YAML matches retain exact key/value source ranges. Query, indexing,
completion and source navigation share that read-only projection.

Unknown fields or values, malformed syntax, unsupported
grouping/OR/regex/fuzzy/range syntax, CJK prefix use, and unsafe structured
exclusion produce an inline diagnostic and never broaden retrieval. Queries
are bounded before execution.

Every Note result identifies its provider object, stable identity, exact source
fingerprint, matched field/reason, and available locator/range.

Search indexes visible semantic text, valid link-annotation content, and canonical
fields, not raw delimiters or link destinations. Annotation hits use the distinct
`link_annotation` field, identify the owning occurrence and source range, and remain
discovery candidates only: annotation prose never creates a predicate or a second edge.
Exact filename Note title, alias, and path identity outrank lexical matches. An Analysis
academic title remains a weighted `title` lexical match, not Note identity; normalized
Note title, role order, and path provide stable ties. Results explain matched field and
rank reason without exposing internal scores. CJK uses deterministic projection and
substring verification.

The versioned **Related-Content Retrieval** contract is an internal,
nonpersistent discovery operation over exact current Notes and optional passage
or request focus. It returns bounded Analysis/Topic candidates through separate
direct-link, exact-identity, and lexical channels, preserving typed
reasons and source fingerprints. It never synthesizes a relation, score,
summary, or evidence claim. Search and Graph must share one complete source
manifest before direct-link candidates are executable.
Its paragraph stage reads fingerprint-matched candidate Notes and ranks authored
paragraphs through the same normalization, seed terms and lexical matcher. An
explicit focus must match the paragraph itself. Paragraphs retain exact source
ranges and bytes plus a separate readable-text projection. Search also supplies a
bounded excerpt around a focused match and checked UTF-16 highlight ranges within
that excerpt; these never substitute for exact source locators. Bounded per-Note and
overall results preserve useful diversity without collapsing distinct passages.
Repeated visible paragraphs in one Note appear once. A multi-term focus requires
more than one matching term, avoiding incidental single-word filler. This creates
no persistent paragraph IDs, embeddings or inferred relations.

Ordinary Search returns bounded slices, filtered totals and continuations.

Every provider response binds contract version, provider, authorized scope,
its own generation, and freshness. **Building**, **Limited**, **Partial**,
**Stale**, **Unavailable**, **Invalid**, and **Cancelled** remain distinct. A
failed refresh may retain only that provider's last complete compatible
generation. Derived indexes remain disposable and never writable authority.

The parser exposes one typed capability description used by completion, **Explain
Query**, CLI help, and the MCP tool schema. Completion edits only visible query text.
Saved Searches store only raw query, visible scope, and contract version; they store no
AST, resolved identity, result, or generation. Changed semantics require **Needs
Editing** rather than silent rewrite or execution. Invalid saved bytes remain unchanged
and nonexecuting; a damaged Saved Search store has a confirmed archive-and-reset route
that never changes vault content.

App, CLI, and Scholium MCP consume the same result identity,
reasons, provenance, availability, and freshness. Presentation may reword but
never reparse, reorder, broaden, combine rankings, or change link direction.

Authored YAML `summary` participates as an explainable Note field with its exact
scalar range, including bounded literal and folded block scalars. `keywords`
retains its string-list lexical projection. These projections require no profile
registration; they never rename or interpret other custom keys. A hit opens the complete current Note and is only a discovery
lead. Missing or unbounded values receive no generated substitute. Search never
writes or reconstructs YAML.

New providers or fields require a versioned typed clause, discriminated result
identity, capability entry, source/freshness contract, and App/CLI/MCP parity.
Vector search, embeddings, AI interpretation/ranking, automatic classification
extraction, multi-hop expansion, arbitrary structured paths, and chat-style
Search remain outside the target.

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

System-Trash receipt semantics are owned by §6 and recovery presentation by
§18.6; neither restore-candidate handling nor source recovery may reuse its
forward plan as source-replacement authority.

Watchers and sync observations are refresh evidence only. External absence or
restoration passes through ordinary identity and exact-byte reconciliation and
never authorizes changes to research prose.

After Saving, a writable Document has exactly three outcomes:

- **Saved** only when canonical Markdown readback exactly matches the validated
  candidate; success is silent;
- **Conflict** when the expected revision differs, retaining the buffer and
  routing to comparison; or
- **Autosave Failed** when commit or exact readback cannot be proven, retaining
  the buffer and any useful recovery candidate.

Filesystem metadata, temporary replacement entries, directory synchronization,
and app-owned housekeeping are not Document success predicates. Once exact
readback proves the source, they do not create a warning or invite another
write. Settle stores only its portable fingerprint marker and is never recovery
source.
