# Specification: Notes and File Operations

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 5–7.

## 5. Common note capabilities

Analysis, Topic, and ordinary Work Notes support Review, Edit, and Source over
one exact Markdown buffer; autosave; create, duplicate, import, rename, move,
Reveal in Finder, and system-Trash deletion; Search, Find/Replace, Connect,
Metadata, Agent Changes, conflicts, and recovery.
Critique bodies are read-only in Scholium but remain ordinary externally
editable Markdown.

### 5.1 Document modes and YAML

- **Review** renders committed content for reading, navigation, and selection.
- **Edit** modifies the exact body through a reversible semantic projection. It
  shares Review typography and components, reveals syntax only for the active
  construct, and shows neither YAML nor line numbers.
- **Source** edits complete Markdown and YAML with logical source-line numbers
  and exact-source typography. Soft wrapping never changes source lines.

All modes share one document session, selection, Undo history, viewport,
appearance, and line-width setting. A mode change must preserve dirty source,
selection, focus, marked text, scroll, and recovery authority. Review and Edit
may differ only where editing requires caret, selection, composition, or active
syntax. Source accepts researcher responsibility for protected YAML while still
using targeted, byte-preserving validation.

Edit activation is construct-scoped. Pointer and keyboard entry place the caret
at the corresponding exact source location without an intermediate false
selection. Drag selection keeps projection stable until release. Link
activation remains distinct from caret placement and has keyboard and
accessibility equivalents.

List projection preserves one marker track and prose indentation. Task
checkboxes change only the exact task marker in one Undo transaction; a
keyboard/menu Toggle Task route remains. Source always exposes exact prefixes.

Edit provides three caret-owned suggestion lists:

- `[[` completes an unambiguous Note or authored alias and inserts canonical
  Wikilink syntax without rewriting other links.
- `@` completes an Analysis reference from the Analyses vault and inserts a
  neutral Wikilink with an available author/year label or Note title. It does
  not invent citation keys or evidential relations.
- `/` offers a bounded set of structured insertions, including Callout, date,
  mathematics, Mermaid, table, footnote, code block, and divider where valid.

Suggestions do not run inside protected constructs or marked-text composition.
They retain document focus, alter only the current buffer, and create one Undo
event.

Statistics are derived from the current unsaved body or selection and are never
stored. They distinguish Latin-script word runs, Han characters, and Unicode
grapheme clusters while excluding YAML, delimiters, and link destinations.
Spelling and grammar use installed macOS text services.

**Import Image…** copies a supported image without replacement to
`Attachments/<uuid>/<filename>`, records its stable vault-relative location,
and inserts an ordinary relative Markdown image link. Pasting image data uses
this route. **Index Image…** keeps the Finder-owned file in place, records its
stable identity and absolute path, and inserts that percent-encoded path.
Security-scoped bookmark data is machine-local only. Both operations are
explicit and transactional: failure leaves source unchanged and rolls back only
new state from that attempt. The catalog never regenerates authored links, and
Scholium does not move or delete attachments as a side effect of Note editing
or deletion.

Review and Edit preserve exact Markdown while presenting semantic Callouts,
lists, quotations, tables, footnotes, mathematics, code, links, and Mermaid.
Protected constructs follow these rules:

- Callout role, title, body, nesting, continuation, and fold state remain
  source-controlled. Edit reveals only active exact markers.
- Mathematics and Mermaid use a pinned local, network-free renderer. Malformed,
  unsupported, prohibited, or over-limit content remains visible as exact
  source with a diagnostic and is never rewritten.
- Mermaid is a static illustration, not evidence or a Connection. Authored
  `accTitle` and `accDescr` provide its nonvisual account; absent descriptions
  are diagnosed.
- A Note embed is a bounded, read-only projection of the target's committed
  body with an explicit open route. It is not recursively transcluded, editable,
  or a relationship edge.
- Link and footnote previews are bounded read-only projections with keyboard,
  pointer, accessibility, dismissal, and source-navigation routes. Missing or
  ambiguous destinations remain exact source.

### 5.2 Authored YAML and Scholium Metadata

[Appendix A](11-metadata-and-critique.md#shared-authored-yaml) owns the authored
YAML allowlist. `summary` and `keywords` remain authored source, editable in
Source and usable by About and Search. Every other key is preserved exactly but
has no canonical product semantics.

All other canonical structured values are **Scholium Metadata**. One portable,
schema-checked JSON record belongs to each stable Note identity. It is separate
from Markdown, never reconstructs source, and uses compare-and-swap writes.
Missing means no managed values. Damaged, future, wrong-role, orphaned, or
concurrently changed records fail closed and preserve exact bytes for bounded,
confirmed recovery.

[Appendix A](11-metadata-and-critique.md#appendix-a-metadata-catalogs-and-settings)
owns catalogs, applicability, custom fields, and About order. One role-specific
resolved catalog serves validation, Metadata, Search, Library filters, and
About. A definition creates no value.
Scholium validates shape and structural safety, not bibliographic or
philosophical truth.

Analysis display identity resolves managed `title`, then first H1, then
filename. Topic and Work resolve first H1, then filename. YAML `title` has no
identity semantics. Rename never synchronizes Metadata or H1.

About is the current Note's primary Metadata view and ordinary editing surface.
It always shows the role's configured core managed fields even when empty,
automatically adds every other present managed value, and keeps authored
`summary` and `keywords` visible. A field edit remains bound to its real owner:
managed values use the loaded Metadata revision, while authored values use an
exact source revision and a targeted YAML patch after the current editor is
safely flushed. File and Settlement facts are read-only. The Metadata sheet
remains the Add Field and multi-field editing route; it preserves drafts on
conflict and never creates or changes YAML. CLI metadata read/set/remove
operations use the same managed owner and Metadata fingerprint, never the
source fingerprint.

Metadata imposes no Markdown body schema. A standalone Markdown copy contains
only authored source; moving the complete Triptych carries its identity-keyed
portable Metadata. Any future flattened export is explicit and
non-round-trippable.

### 5.3 Create, duplicate, rename, and identity

**New Note** and **New Folder** are immediate nonmodal actions at the selected
vault root or exact selected folder. New paths are atomically claimed as
`Untitled.md` or `Untitled Folder` with the next available ordinal and never
replace an existing comparison-equivalent path.

A managed New Note uses one Application-owned creator shared by GUI, CLI, and
Scholium MCP. GUI and MCP creation write exactly:

```yaml
---
summary: null
keywords: []
---
```

It then opens Edit at the exact body start. It adds no H1, title, required
Metadata, naming sheet, or classification step. Import, Duplicate, Restore,
external discovery, and managed Critique creation keep their own exact-source
contracts and do not inject this scaffold.

MCP creation accepts only exact role/path, body, and optional authored
`summary`/`keywords`. It accepts no YAML fragment, creates no bibliographic
Metadata, and grants no continuing create authority after the identity exists.

A successful source-and-identity commit appears immediately in Library; derived
indexes refresh afterward without blocking writing. Presentation failure must
not invite duplicate creation.

Paths are locations; Notes have stable app-owned identities. Duplicate creates
a new identity and copies exact source plus current managed values, but not
Settlement. Rename and Move preserve identity and exact resolved incoming-link
updates. Ambiguous external rename keeps source readable
but blocks identity-dependent mutation until resolved.

Folders are vault-relative filesystem locations with no UUID, Metadata, Record,
or recovery identity. Empty folders remain visible. Rename or Move flushes
open editors, rechecks the complete descendant inventory, performs one
nonreplacing directory operation, preserves descendant identities, and updates
only unambiguous already-resolved incoming links. Symlink boundaries,
collisions, stale inventories, or ambiguous links abort without partial source
reinterpretation. Non-Markdown contents move without parsing.

Note and Folder drag-and-drop are redundant Move routes using process-private
identity/path payloads. File menu and named accessibility actions remain
available. Cross-vault moves, managed Critique placement, stale revisions,
invalid descendants, and self/descendant folder targets fail without source
change.

## 6. System Trash deletion and recovery

Scholium has no application Trash, erase command, or source restore command.
**Move to Trash…** and **Move Folder and Notes to Trash…** use the macOS system
Trash; Finder owns restoration and final deletion.

Folder deletion confirmation lists every source item that will move to system
Trash. Preparation flushes dirty editors and freezes exact paths, identities,
fingerprints, folder contents, and separately located managed Critiques. An
in-flight or uncertain MCP mutation, unresolved write recovery, identity
ambiguity, source or manifest drift, or unsafe filesystem entry blocks the
move.

A Research Record, when present under its separately approved contract, is
independent historical research content. Moving its participant source to
system Trash does not alter or delete it. Stable Note identity, Settlement,
Zotero binding, source-access provenance, and Critique association also remain
so Finder restoration can reconcile exact source.

Before the first move Scholium installs a deletion gate and durable forward
plan with one receipt per source item. It binds each native operation to the
exact checked filesystem object, never a replacement that later appears at the
same path. Partial success is representable.

Recovery follows these rules:

| Condition | Required outcome |
| --- | --- |
| Preflight or first-move failure | Preserve all source and application state. |
| Proven native move | Resume from its receipt; never move the item again. |
| Bound operation with unknown native outcome | Preserve recovery state; require researcher inspection before releasing the plan. |
| External move or deletion without a Scholium plan | Refresh projections only; never invent a mutation or cascade. |
| Finder restores source | Reconcile retained identity and bytes without fabricating another mutation. |

Watchers report filesystem observations but cannot create deletion authority.
Multiple windows converge through shared workspace coordination. A committed
absence closes only affected pages and refreshes derived projections while
preserving unrelated tabs and focus.

## 7. Settlement

Settle binds an optional rationale, date, and researcher identity to the exact
saved fingerprint of any Analysis, Topic, or Work. Save failure, conflict,
unknown identity, or revision mismatch blocks it. Repeating Settle replaces the
current marker. **Mark Unsettled** is a separate explicit researcher action.
Neither a researcher edit, external edit, MCP mutation, Agent Change, index
refresh, nor elapsed time changes Settled/Unsettled automatically.

When current source differs from the fingerprint at which Settle was last
affirmed, Scholium derives **Changed Since Settle** without changing the
Settlement judgment. A dismissible reminder may invite the researcher to
review the current Note and choose Settle Again, Mark Unsettled, or no status
change. When exact Agent Changes are available, **Review Changes** opens their
temporary comparisons; a non-Agent save never fabricates one. Opening,
closing, or dismissing any presentation has no Settlement effect.

Each Note has one portable Settlement judgment and no separate reviewed
marker. It is not a Record, verdict, source version, restore point, retention
policy, or Agent requirement.

Authoritative written annotation remains Markdown, including semantic
Callouts. Selection creates no separate portable comment object.
