# Specification: Connect, Search, and Recovery

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 12–14.

## 12. Connect and Connection syntax

| Markdown in A | Meaning |
| --- | --- |
| `[[B]]` | neutral, undirected A—B |
| `+[[B]]` | A supports B |
| `-[[B]]` | A opposes B |
| `?[[B]]` | undirected incompatibility A—B |

Support and opposition state the containing Note's authored argumentative
direction. Incompatibility states that both Notes cannot be retained together in
the researcher's current account without deciding which is false or rejected.
No relation certifies evidence, truth, success, or acceptance.

These are the only Vector-Link forms; aliases, headings, and fragments remain
valid. Scholium preserves exact bytes and never infers a relation from
keywords, proximity, folders, or multi-hop paths. Incoming and Outgoing are
projections over the same direct graph. Neutral and Incompatible appear in both
directions with the same source anchor and an explicit undirected explanation.
There is no Combined or All direction.

## 13. Search and Attention

Search has three visible Note scopes:

- **This Note** searches the open Note's unsaved buffer;
- **This Vault** searches present Notes in the selected role vault; and
- **Triptych** searches all present Notes.

Search owns known-Note navigation but not Recents, Quick Open, or navigation
history. It is one compact command surface with visible scope and a bounded
result list. Opening it retains the workspace; dismissal cancels work and
clears query/results while retaining ordinary scope and Saved Searches.

During live workspace opening, **This Note** performs exact lexical Search over
the current unsaved buffer. **This Vault** may reuse only lexical matches from
the last complete compatible index whose source fingerprint still equals the
authoritative opening snapshot and whose indexed stable identity, when present,
still resolves there; it reports **Limited**, excludes new, changed, deleted,
retargeted, or unverifiable Notes, and never publishes a partial generation.
Triptych scope, the Record provider, managed-property and structured clauses,
direct relations, and operations requiring complete Search remain unavailable
until the complete generation publishes. Completion replaces the limitation
without moving focus or invalidating already usable Library content.

Document Find is a separate inline editor operation over the current unsaved
buffer. It supports literal text, case and whole-word options, count,
Previous/Next, and standard keyboard routes. Edit and Source add Replace
Current/All as single Undo transactions. Find creates no Search provider,
index, saved query, or navigation history.

Search currently has one available **Note** provider. Omitted `kind:` means
`kind:note`; the reserved `kind:record` clause returns **Unavailable** until
§22 defines and activates the replacement Record contract. Query text never
changes the visible scope, and App, CLI, and Scholium MCP share one parser and
ordered response.

The Note provider uses one deterministic present-source corpus. It returns each
occurrence for This Note and one row per Note for broader scopes. Its finite
grammar supports:

- space-as-AND, exact phrases, a trailing prefix `*`, and clause exclusion;
- lexical fields `title`, `alias`, `heading`, `summary`, `body`, `author`,
  `publication_date`, `keyword`, `footnote`, and `path`;
- `callout` and `has:broken-link`;
- canonical `property:<key>` presence or exact whole-value equality; and
- exactly one direct `from-note` or `to-note` anchor with one
  `relation:supports|opposes|neutral|incompatible`.

Structured fields use canonical Metadata or authored `summary`/`keywords` only.
Authored YAML matches retain source ranges; managed Metadata matches retain
record revision without claiming a Markdown range. Relation queries preserve
direction, remain direct, and require a current complete graph.

The Record provider remains unavailable until §22's replacement Research
Record contract defines its canonical fields, pagination, and ordering. Search
must not preserve superseded workflow fields or infer a new Record schema from
existing implementation bytes.

Unknown fields or values, malformed syntax, provider mismatch, unsupported
grouping/OR/regex/fuzzy/range syntax, CJK prefix use, and unsafe structured
exclusion produce an inline diagnostic and never broaden retrieval. Queries
are bounded before execution.

Every Note result identifies its provider object, stable identity, exact source
fingerprint, matched field/reason, and available locator/range. No current
result or stored index entry masquerades as a Research Record.

Search indexes visible semantic text and canonical fields, not raw delimiters
or link destinations. Exact title, alias, filename, and path identity outrank
body matches; normalized title, role order, and path provide stable ties.
Results explain matched field and rank reason without exposing internal scores.
CJK uses deterministic projection and substring verification.

The versioned **Related-Content Retrieval** contract is an internal,
nonpersistent discovery operation over exact current Notes and optional passage
or request focus. It returns bounded Analysis/Topic candidates through separate
direct-Connection, exact-identity, and lexical channels, preserving typed
reasons and source fingerprints. It never synthesizes a relation, score,
summary, or evidence claim. Search and Graph must share one complete source
manifest before Connection candidates are executable.

Ordinary Search returns bounded slices. If the replacement Research Record
contract later activates a provider, it must define its own fields, identity,
pagination, exact filtered totals, and ordering while reusing this parser.

Every response binds contract version, provider, authorized scope, source
generation, and freshness. **Building**, **Limited**, **Partial**, **Stale**,
**Unavailable**, **Invalid**, and **Cancelled** remain distinct. A failed
refresh may retain only a last complete compatible generation. Derived indexes
remain disposable and never writable authority.

The parser exposes one typed capability description used by completion,
**Explain Query**, CLI help, and the MCP tool schema. Completion edits only
visible query text.
Saved Searches store only raw query, visible scope, and contract version; they
store no AST, resolved identity, result, or generation. Changed semantics
require **Needs Editing** rather than silent rewrite or execution. Invalid saved
bytes remain unchanged and nonexecuting; a damaged Saved Search store has a
confirmed archive-and-reset route that never changes vault content.

App, CLI, and Scholium MCP consume the same ordered result identity, reasons,
provenance, availability, and freshness. Presentation may reword but never
reparse, reorder, broaden, or change relation direction.

Authored YAML `summary` participates as an explainable Note field with its exact
scalar range. A hit opens the complete current Note and is only a discovery
lead. Missing or unbounded values receive no generated substitute. Search never
writes or reconstructs YAML or managed Metadata.

New providers or fields require a versioned typed clause, discriminated result
identity, capability entry, source/freshness contract, and App/CLI/MCP parity.
Vector search, embeddings, AI interpretation/ranking, automatic relation
extraction, multi-hop expansion, arbitrary structured paths, and chat-style
Search remain outside the target.

Scholium MCP reuses this owner under
[§8.3](03-agent-collaboration-and-workflows.md#83-tool-contract) and adds no
second parser, resolver, index, or confidence score.

**Notifications** combines Agent Changes, derived Settlement reminders, and
Triptych-wide structural Attention. These remain separate owners and dismissal
semantics. Structural Attention may report:

- **Possible Orphan** only when a Note has no resolved incoming or outgoing
  Connection;
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
