# Specification: Notes and File Operations

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 5–7.

## 5. Common note capabilities

Analysis, Topic, and ordinary Work Notes support Review, Edit, and Source over
one exact Markdown buffer; autosave; create, duplicate, import, rename, move,
Reveal in Finder, and system-Trash deletion; Search, Find/Replace, Connect,
source properties, Agent Changes, conflicts, and recovery.

### 5.1 Document modes and YAML

- **Review** renders committed content for reading, navigation, and selection.
- **Edit** modifies source through a reversible semantic projection; Frontmatter
  remains directly source-editable above the title under §18.4.
- **Source** edits complete Markdown and YAML with logical source-line numbers.

All modes share one document session. A mode change preserves dirty source,
selection, focus, marked text, Undo, scroll and recovery authority. §18.4 owns
mode presentation, syntax visibility, typography and layout. Source editing
retains targeted, byte-preserving validation.

Edit activation is construct-scoped. Pointer and keyboard entry place the caret
at the corresponding exact source location without an intermediate false
selection. Drag selection keeps projection stable until release. Link
activation remains distinct from caret placement and has keyboard and
accessibility equivalents.

Syntax presentation groups by editing behavior rather than by visual similarity:

| Family | Edit behavior |
| --- | --- |
| Emphasis, strong, strike, highlight, inline code | Retain styled prose; reveal only the active delimiters locally. |
| ATX headings and quotation prefixes | Expand exact prefixes within the measure, with the bounded whitespace exception in §18.4. |
| Setext headings and thematic breaks | Preserve their source row; do not treat a whole delimiter line as an inline prefix. |
| Lists and tasks | Keep their semantic marker track; prefix editing and task toggling remain distinct. |
| Callouts | Retain expanded editable prose, a quiet role label and header/body structure; reveal markers only on active lines. Folding is a separate accessible disclosure, and selection inside a folded body exposes it. |
| Links, Wikilinks and annotations | Keep the label readable; long destinations and annotation source use local wrapping, with preview and navigation distinct from editing. |
| Tables, mathematics, Mermaid, footnote references and embeds | Retain object-specific source mapping, preview and bounded layout; never apply prose-pushing to a whole object. |
| Code blocks, raw HTML, comments, escapes, YAML and unsupported syntax | Preserve literal source and its input behavior; no decorative conversion or motion during typing. |

List projection preserves one marker track and prose indentation. Task
checkboxes change only the exact task marker in one Undo transaction; a
keyboard/menu Toggle Task route remains. Source always exposes exact prefixes.

Edit provides three caret-owned suggestion lists:

- `[[` completes an unambiguous Note or authored alias and inserts canonical
  Wikilink syntax without rewriting other links.
- `@` completes an Analysis reference from the Analyses vault and inserts a
  Wikilink with an available author/year label or Note title. It does
  not invent citation keys or evidential relations.
- `/` offers a bounded set of structured insertions, including Callout, date,
  mathematics, Mermaid, table, footnote, code block, and divider where valid.

Suggestions do not run inside protected constructs or marked-text composition.
They retain document focus, alter only the current buffer, and create one Undo
event.

The Insert menu and configurable shortcuts provide **Footnote** and **Inline
Footnote** as distinct authoring commands. Footnote allocates the first unused
numeric identifier, inserts its reference, appends one exact definition, and
places the selection in that definition without renumbering existing forms.
Inline Footnote inserts `^[…]` at each selection and retains selected text as
its content. Each invocation is one source transaction and one Undo event.

Statistics are derived from the current unsaved body or selection and are never stored.
Their interface entry is currently withdrawn (§18.4). They report language-aware word tokens, Han
characters, and Unicode grapheme clusters with and without whitespace while excluding
YAML, delimiters, and link destinations. Word counts use the platform tokenizer rather
than treating every script as Latin. Spelling and grammar use installed macOS text
services.

**Import Image…** copies a supported image without replacement to
`Attachments/<uuid>/<filename>`, records its stable vault-relative location,
and inserts an ordinary relative Markdown image link. Pasting image data uses
this route. **Index Image…** keeps the Finder-owned file in place, records its
stable identity and neutral filename in portable control state, and inserts
that percent-encoded absolute path into authored Markdown. The selected path
and security-scoped bookmark remain machine-local. Both operations are explicit
and transactional: failure leaves source unchanged and rolls back only new
state from that attempt. The catalog never regenerates authored links, and
Scholium does not move or delete attachments as a side effect of Note editing
or deletion.

Document attachments are ordinary authored Markdown links. **Attach a Copy…**
copies one regular non-media file without replacement to
`Attachments/<uuid>/<filename>`; **Reference Original…** retains its Finder
location and acquires machine-local scoped access. Both insert a link at the
current editing selection through the normal source transaction and Undo.
Preparation alone creates no Note relationship. Failed insertion rolls back only
new, exactly verified preparation state. Removing a link removes the derived
relationship and never deletes the file. Images retain their inline routes.
File links open through bounded native Quick Look; unavailable files report an
error without substituting a different path or filename match.

Review and Edit preserve exact Markdown while presenting semantic Callouts,
lists, quotations, tables, footnotes, mathematics, code, links, occurrence-owned
link annotations, and Mermaid.
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
  and adds no authored link annotation.
- Link and footnote previews are bounded read-only projections with keyboard,
  pointer, accessibility, dismissal, and source-navigation routes. Missing or
  ambiguous destinations remain exact source.
- §18.4 owns the shared reading presentation and activation of named/inline
  footnotes and annotated Wikilinks. These projections create no separate Note,
  Comment, Metadata field or writable annotation authority.

### 5.2 Authored YAML and source properties

[Appendix A](11-source-properties.md#shared-authored-yaml) owns source properties.
YAML and body share one exact Markdown authority, source fingerprint, revision
checks, Undo and recovery. There is no separate managed Metadata record or
form. User-defined properties need no catalog registration.

Every Analysis, Topic and Work uses its filename without `.md` as its Note
title. YAML titles, aliases and body headings never replace this identity.
Rename does not synchronize authored property values or headings. Duplicate
and standalone Markdown copy carry the same authored properties in their exact
source; no separate metadata export is required.

### 5.3 Create, duplicate, rename, and identity

**New Note** and **New Folder** are immediate nonmodal actions at the selected
vault root or exact selected folder. New paths are atomically claimed as
`Untitled.md` or `Untitled Folder` with the next available ordinal and never
replace an existing comparison-equivalent path.

A managed New Note uses one Application-owned creator shared by GUI, CLI, and
Scholium MCP. Without explicitly supplied source values, it creates an empty,
YAML-free document and opens Edit at the exact body start. It adds no YAML
scaffold, H1, title, required Metadata, naming sheet, or classification step.
Import, Duplicate, Restore, and external discovery
keep their own exact-source contracts.

MCP creation accepts exact role/path and complete Markdown `content`, including
optional YAML. It preserves the supplied bytes and grants no continuing create
authority after the reserved identity exists.

A successful source-and-identity commit appears immediately in Library; derived
indexes refresh afterward without blocking writing. Presentation failure must
not invite duplicate creation.

Paths are locations; Notes have stable app-owned identities. Duplicate creates
a new identity and copies exact source, but not
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
available. Cross-vault moves, stale revisions,
invalid descendants, and self/descendant folder targets fail without source
change.

## 6. System Trash deletion and recovery

Scholium has no application Trash, erase command, or source restore command.
**Move to Trash…** and **Move Folder and Notes to Trash…** use the macOS system
Trash; Finder owns restoration and final deletion.

Folder deletion confirmation lists every source item that will move to system
Trash. Preparation flushes dirty editors and freezes exact paths, identities,
fingerprints and folder contents. An
in-flight or uncertain MCP mutation, unresolved write recovery, identity
ambiguity, source or manifest drift, or unsafe filesystem entry blocks the
move.

Deleting a Note does not delete independent linked Notes. Stable Note identity,
Settlement remains so Finder restoration can reconcile exact source.

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
Callouts and the occurrence-owned link annotations defined by §12. Selection
creates no separate portable comment object.
