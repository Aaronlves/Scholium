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

- **This Note** searches the open Note's unsaved buffer and Records that
  reference its stable identity;
- **This Vault** searches present Notes in the selected role vault and Records
  that reference at least one present Note in that vault; and
- **Triptych** searches all present Notes and all valid Records.

The provider control is **All**, **Notes**, or **Records**. All is the default
and issues the same visible query to both providers, but the providers retain
separate result groups, rankings, totals, continuations, generations, and
freshness. Notes appear before Records; no cross-provider score interleaves
them. Notes or Records supplies the dedicated provider path without changing
the query or visible scope.

Search owns known-Note navigation but not Recents, Quick Open, or navigation
history. It is one compact command surface with visible scope and a bounded
result list. Opening it retains the workspace; dismissal cancels work and
clears query/results while retaining ordinary scope and Saved Searches.

During live workspace opening, **This Note** performs exact lexical Search over
the current unsaved buffer. **This Vault** may reuse only lexical Note matches
from the last complete compatible index whose source fingerprint still equals
the authoritative opening snapshot and whose indexed stable identity, when
present, still resolves there; it reports **Limited**, excludes new, changed,
deleted, retargeted, or unverifiable Notes, and never publishes a partial
generation. Triptych Note scope, managed-property and structured clauses,
direct links, and operations requiring complete Note Search remain unavailable
until that complete generation publishes. The Record provider independently
requires one complete validated Record generation; All may therefore present
one provider while naming the other's unavailable or stale state. Completion
replaces the limitation without moving focus or invalidating usable results.

Document Find is a separate inline editor operation over the current unsaved
buffer. It supports literal text, case and whole-word options, count,
Previous/Next, and standard keyboard routes. Edit and Source add Replace
Current/All as single Undo transactions. Find creates no Search provider,
index, saved query, or navigation history.

Search has **Note** and **Record** providers. Omitted `kind:` means both;
`kind:note` and `kind:record` select one provider and agree with the visible
provider control. Query text never changes visible scope, and App, CLI, and
Scholium MCP share one parser and provider-separated response.

The Note provider uses one deterministic present-source corpus. It returns each
occurrence for This Note and one row per Note for broader scopes. Its finite
grammar supports:

- space-as-AND, exact phrases, a trailing prefix `*`, and clause exclusion;
- lexical fields `title`, `alias`, `heading`, `summary`, `body`, `author`,
  `publication_date`, `keyword`, `footnote`, `link_annotation`, and `path`;
- `callout` and `has:broken-link`;
- canonical `property:<key>` presence or exact whole-value equality; and
- exactly one direct `from-note` or `to-note` anchor.

Structured fields use canonical Metadata or authored `summary`/`keywords` only.
Authored YAML matches retain source ranges; managed Metadata matches retain
record revision without claiming a Markdown range. `from-note:A` returns the
resolved destinations of occurrences authored in A; `to-note:B` returns Notes
whose authored occurrences resolve to B. These queries preserve occurrence
direction, remain direct, and require a current complete graph.

The Record provider reads only strict §8.6 files and returns one row per Record.
Unqualified text searches current `question` and current projected
`body_markdown`; provider-specific `question:` and `step:` fields select those
two corpora. Original bodies replaced by clerical corrections remain
provenance, not Search text. Exact or prefix question matches outrank question
lexical matches, which outrank step matches. Last substantive step time,
normalized question, and Record UUID provide deterministic ties without a
cross-provider score. Legacy action, method, Run, Result, participant, status,
or completion fields never participate.

Unknown fields or values, malformed syntax, provider mismatch, unsupported
grouping/OR/regex/fuzzy/range syntax, CJK prefix use, and unsafe structured
exclusion produce an inline diagnostic and never broaden retrieval. Queries
are bounded before execution.

Every Note result identifies its provider object, stable identity, exact source
fingerprint, matched field/reason, and available locator/range. Every Record
result identifies Record ID, current question, exact Record-file fingerprint,
last substantive step time, matched question or step, matched step ID when
applicable, reason, and bounded snippet. Neither result type masquerades as the
other or changes its evidential role.

Search indexes visible semantic text, valid link-annotation content, and
canonical fields, not raw delimiters or link destinations. Annotation hits use
the distinct `link_annotation` field, identify the owning occurrence and source
range, and remain discovery candidates only: annotation prose never creates a
predicate or a second edge. Exact filename Note title, alias, and path identity
outrank lexical matches. An Analysis academic title remains a weighted `title`
lexical match, not Note identity; normalized Note title, role order, and path provide stable ties.
Results explain matched field and rank reason without exposing internal scores.
CJK uses deterministic projection and substring verification.

The Record index is a separate rebuildable provider projection over validated
portable files. It stores no writable Record authority and never joins Note and
Record rankings or generations. A Record Note reference filters scope and
supports navigation but contributes no unqualified lexical text or inferred
evidential relation.

The versioned **Related-Content Retrieval** contract is an internal,
nonpersistent discovery operation over exact current Notes and optional passage
or request focus. It returns bounded Analysis/Topic candidates through separate
direct-link, exact-identity, and lexical channels, preserving typed
reasons and source fingerprints. It never synthesizes a relation, score,
summary, or evidence claim. Search and Graph must share one complete source
manifest before direct-link candidates are executable.

Ordinary Search returns bounded slices. All returns independent Note and Record
slices, exact filtered totals, and continuations; the dedicated provider path
continues only its own result set. The Record provider has its own identity,
generation, fields, and ordering while reusing this parser.

Every provider response binds contract version, provider, authorized scope,
its own generation, and freshness. **Building**, **Limited**, **Partial**,
**Stale**, **Unavailable**, **Invalid**, and **Cancelled** remain distinct. A
failed refresh may retain only that provider's last complete compatible
generation. Derived indexes remain disposable and never writable authority.

The parser exposes one typed capability description used by completion,
**Explain Query**, CLI help, and the MCP tool schema. Completion edits only
visible query text.
Saved Searches store only raw query, visible scope, visible provider selection,
and contract version; they store no AST, resolved identity, result, or
generation. Changed semantics require **Needs Editing** rather than silent
rewrite or execution. Invalid saved bytes remain unchanged and nonexecuting; a
damaged Saved Search store has a confirmed archive-and-reset route that never
changes vault or Record content.

App, CLI, and Scholium MCP consume the same provider-separated result identity,
reasons, provenance, availability, and freshness. Presentation may reword but
never reparse, reorder, broaden, combine rankings, or change link direction.

Authored YAML `summary` participates as an explainable Note field with its exact
scalar range. A hit opens the complete current Note and is only a discovery
lead. Missing or unbounded values receive no generated substitute. Search never
writes or reconstructs YAML or managed Metadata.

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
- Broken/Ambiguous Connections, malformed Metadata, or unresolved identity;
  and
- source/index drift or failure that has an exact mechanical basis and safe
  repair.

Attention never declares a Note wrong, outdated, Superseded, accepted, or
philosophically deficient. Warnings are dismissible against their exact
identity/revision and may recur after a later change.

Changed Since Settle reminders are not structural Attention. Dismiss hides the
reminder without changing Settlement; a later source change may produce a new
reminder under §7.1.

## 14. Save, Agent changes, and recovery

Autosave creates no visible version history, Checkpoint product, whole-Triptych
rollback, or settled-version store.

Each MCP mutation stores one machine-local Agent Change under §8.4. An update
retains only exact starting and final revisions needed for comparison and
eligible direct Undo. Creation and system-Trash operations retain their own
operation receipts and recovery. Agent Change evidence grants no authority and
uses the ordinary repository save path.

Interrupted-save recovery remains machine-local and source-specific. When
startup proves a distinct retained candidate, **Recovery** shows its Note,
expected and candidate revisions, reason, and read-only exact source. The
researcher may copy or reveal it. **Restore Candidate…** flushes open editors
and replaces canonical source only if the current revision still equals the
recorded expectation. Changed, missing, unsafe, or unverifiable source is never
overwritten or recreated.

Invalid portable Metadata recovery archives only the confirmed unchanged
record to a unique non-record sibling, then retries preflight. It never moves
source, valid neighbor records, settings, identity state, or the complete
`.scholium` directory.

System-Trash recovery is a separate forward plan showing source items, known
Finder destinations, and receipts. An unknown native outcome permits
**Resolve** after researcher inspection; that releases the gate and removes
only the Scholium plan. It never restores or erases source, and neither route
reads or changes Research Record bytes.

Watchers and sync observations are refresh evidence only. External absence or
restoration passes through ordinary identity and exact-byte reconciliation and
never authorizes Research Record deletion or recreation.

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
