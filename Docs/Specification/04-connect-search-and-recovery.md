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

Search has three visible scopes whose meaning depends on the selected provider:

- **This Note** searches the open Note's unsaved buffer or Records in which the
  Note participates;
- **This Vault** searches present Notes in the selected role vault or Records
  with at least one participant there; and
- **Triptych** searches all present Notes or all Records.

Search owns known-Note navigation but not Recents, Quick Open, or navigation
history. It is one compact command surface with visible scope and a bounded
result list. Opening it retains the workspace; dismissal cancels work and
clears query/results while retaining ordinary scope and Saved Searches.

Document Find is a separate inline editor operation over the current unsaved
buffer. It supports literal text, case and whole-word options, count,
Previous/Next, and standard keyboard routes. Edit and Source add Replace
Current/All as single Undo transactions. Find creates no Search provider,
index, saved query, or navigation history.

Search has a closed **Note / Record** provider contract. Omitted `kind:` means
`kind:note`; `kind:record` selects Records. Query text never changes the visible
scope, and App and CLI share one parser and ordered response.

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

The Record provider supports unfielded terms plus `note`, `action`, `skill`,
`participant:researcher|agent`, and `date:today|7d|30d`. It searches frozen
Record Title, Action, Skill display name, participant Note titles, and
attributed statements. Results sort by finished time then stable identity unless
the Records collection requests another provider-owned order.

Unknown fields or values, malformed syntax, provider mismatch, unsupported
grouping/OR/regex/fuzzy/range syntax, CJK prefix use, and unsafe structured
exclusion produce an inline diagnostic and never broaden retrieval. Queries
are bounded before execution.

Every result identifies its provider object, stable identity, exact source
fingerprint, matched field/reason, and available locator/range. Note and Record
results never masquerade as each other. One unreadable Record yields
**Partial** availability while valid Records remain usable; operations needing
a complete corpus still fail closed.

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

Authenticated Runs may request related content for exact unambiguous seed Notes.
Application excludes the seeds, combines per-seed typed reasons, and exposes no
reading history. Stale, invalid, or unavailable generation yields no executable
candidate.

Ordinary Search returns bounded slices. Research Records and Reading Leads may
request provider-owned pagination, exact filtered totals, and ordering without
creating another parser or query language.

Every response binds contract version, provider, authorized scope, source
generation, and freshness. **Building**, **Partial**, **Stale**, **Unavailable**,
**Invalid**, and **Cancelled** remain distinct. A failed refresh may retain only
a last complete compatible generation. Derived indexes remain disposable and
never writable authority.

The parser exposes one typed capability description used by completion,
**Explain Query**, and CLI help. Completion edits only visible query text.
Saved Searches store only raw query, visible scope, and contract version; they
store no AST, resolved identity, result, or generation. Changed semantics
require **Needs Editing** rather than silent rewrite or execution. Invalid saved
bytes remain unchanged and nonexecuting; a damaged Saved Search store has a
confirmed archive-and-reset route that never changes vault content.

App and CLI consume the same ordered result identity, reasons, provenance,
availability, and freshness. Presentation may reword but never reparse, reorder,
broaden, or change relation direction.

Authored YAML `summary` participates as an explainable Note field with its exact
scalar range. A hit opens the complete current Note and is only a discovery
lead. Missing or unbounded values receive no generated substitute. Search never
writes or reconstructs YAML or managed Metadata.

New providers or fields require a versioned typed clause, discriminated result
identity, capability entry, source/freshness contract, and App/CLI parity.
Vector search, embeddings, AI interpretation/ranking, automatic relation
extraction, multi-hop expansion, arbitrary structured paths, and chat-style
Search remain outside the target.

Research Context reuses this owner under
[§8.2](03-research-actions-and-workflows.md#82-agent-entry-local-pairing-layered-delivery-and-research-context)
and adds no second parser, resolver, index, or confidence score.

**Notifications** combines persistent Action activities with derived
Triptych-wide structural Attention. These remain separate owners and dismissal
semantics. Structural Attention may report:

- **Possible Orphan** only when a Note has no resolved incoming or outgoing
  Connection;
- Changed Since Settled, Broken/Ambiguous Connections, malformed Metadata, or
  unresolved identity; and
- **Synthesis Material Changed** only when a completed Synthesize Record proves
  an exact Analysis participant and recorded revision that later changed.

Attention never declares a Note wrong, outdated, Superseded, accepted, or
philosophically deficient. Warnings are dismissible against their exact
identity/revision and may recur after a later change.

## 14. Save, Agent changes, and recovery

Autosave creates no visible version history, Checkpoint product, whole-Triptych
rollback, or settled-version store.

Run-bound Agent change evidence stores only exact starting and final revisions
for diff and direct Undo under §8.4. It grants no authority and uses the
ordinary repository save path.

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
Finder destinations, receipts, Discussions, and Records. When every move is
proven, Retry performs only pending cleanup. An unknown native outcome permits
**Retain Records and Resolve** after researcher inspection; that releases the
gate and removes only the Scholium plan. It never restores or erases source.

Watchers and sync observations are refresh evidence only. External absence or
restoration passes through ordinary identity and exact-byte reconciliation and
never authorizes Record deletion or recreation.

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
