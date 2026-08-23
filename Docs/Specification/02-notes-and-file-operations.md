# Specification: Notes and File Operations

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 5–7.

## 5. Common note capabilities

Analysis, Topic, and ordinary Work notes support:

- Review, Edit, and Source over one exact Markdown buffer;
- autosaved editing without an ordinary Save button;
- create, duplicate, import, rename, move, Reveal in Finder, and move to the
  macOS system Trash;
- exact-source preservation, conflict detection, atomic writes, and external
  coordination;
- source-located Connect relations, passage Comments inside Discussion, and
  authoritative Markdown annotation including semantic Callouts;
- role-aware Metadata and the closed Platform Research Actions with
  researcher-configured academic Profiles;
- Search in **This Note**, **This Vault**, or **Triptych**, plus Attention;
- lightweight Document Find in every mode, with Replace in Edit and Source; and
- Research Record, exact Agent diff and direct Undo, and interrupted-save recovery.

Critique bodies are read-only in Scholium but remain ordinary externally
editable Markdown; Scholium does not set filesystem read-only permissions.

### 5.1 Document modes and YAML

- **Review** renders committed content for reading, selection, navigation, and
  commenting.
- **Edit** edits the exact body through a visual projection, shares
  Review's semantic render components, typography, callout presentation,
  document measure, and theme variables, reveals syntax only around the active
  construct, and shows neither YAML nor line numbers. Inactive content should
  match Review; caret, selection, marked-text composition, and the active
  construct are the permitted editing differences.
- **Source** edits complete Markdown and YAML, shows logical source-line
  numbers, and retains the same document session, viewport, measure, and
  semantic colors while using exact-source typography. Exact text soft-wraps
  within the available measure: visual continuation rows never insert or
  remove source line breaks and never acquire independent line numbers. The
  active-line treatment belongs only to a collapsed caret; a nonempty
  selection never paints an unselected following logical line as active.

All three modes consume the selected Appearance's one shared line-width value.
It changes only layout in Source: Victor Mono and the exact-source typography
contract remain unchanged. The CSS `ch` unit resolves against each mode's
current font and is a character-width unit, not an exact characters-per-line
promise.

Edit activation remains construct-scoped. A plain pointer click on projected
inline syntax or projected block content places one collapsed editor caret
at its mapped source position during pointer-down; it never first paints a
caret at the projected range boundary or constructs a text range as a side
effect of revealing syntax. Pointer-drag selection updates the authoritative
selection continuously but holds the visual Markdown projection stable until
pointer release; a discrete triple-click paragraph selection may reveal its
selected constructs immediately. A direct click on a rendered link reveals
that link's source with the collapsed caret immediately after its exact closing
marker. The first keyboard move into an inactive rendered link lands at that
same trailing boundary; one further backward move enters the now-visible exact
syntax. Control-click and Command-click instead activate the target without
moving the caret.

Typing a valid ATX opening marker—one to six `#` characters followed by its
required space or tab—immediately applies that heading level's Edit
presentation even before title text exists. The active line keeps the exact
marker reachable at the caret; inserting the first title character does not
trigger a second style or geometry transition.

Review and Edit use one stable marker track and nesting step for unordered,
ordered, and task lists. Edit keeps the semantic marker projected while the
caret edits list-item prose; it reveals the exact list prefix only when the
selection enters that prefix. Left Arrow from the first prose position enters
the prefix at its trailing edge. Neither projected versus exact presentation
nor checked versus unchecked task state may move the prose start or change its
indentation. Review task controls are read-only. Edit's task checkbox is a
redundant pointer action that changes only `[ ]` to `[x]` or back in one Undo
transaction without moving the document selection; the caret-line **Toggle
Task** command remains the keyboard/menu route. Source always exposes the exact
prefix and task bytes.

Edit alone owns three caret-triggered input suggestion lists. Typing `[[` opens
the current Workspace note catalog and filters it again as the researcher types;
each insertable result shows its resolved title and quiet path context. Titles,
paths, and authored aliases participate in matching. Accepting a title or path
inserts the canonical target as `[[Target]]`; accepting an authored alias inserts
`[[Target|Alias]]`. When the researcher has already entered `|Visible Text`,
completion replaces only the target and preserves that exact visible text.
Accepting one unique result completes exactly one Wikilink, reusing rather than
duplicating any auto-inserted closing brackets and never rewriting an existing
link elsewhere. Ambiguous cross-vault targets remain nonauthorizing and are not
offered as insertable results.

Typing `@` at a text boundary opens **Analysis Reference** completion over only
the active Analyses vault. It searches the current Analysis identity and
available author, publication-date, and source-title projections, shows author,
year, title, and quiet path when present, and performs no Zotero read. Accepting
one result inserts a neutral Wikilink to the canonical Analysis target with a
short visible author/year label when those fields permit one, otherwise its
resolved title. It never invents or inserts a citation key, citation processor
syntax, evidential relation, or bibliography entry. The candidate set and
derived display labels are read-only, cancellable, and nonpersistent.

Typing `/` at the start of a line or after whitespace opens structured
insertion. A bare slash on a block-safe line shows only **Callout**, **Date**,
**Inline Math**, and **Mermaid**; further characters fuzzy-match the complete
bounded set: **Callout**, **Date**, **Inline Math**, **Display Math**,
**Mermaid**, **Table**, **Footnote**, **Code Block**, and **Divider**. In
ordinary prose, the bare slash offers only Date, Inline Math, and Footnote. Date
inserts the local calendar date as `YYYY-MM-DD`; Callout continues into the
canonical role chooser. These lists never run during marked-text composition or
inside frontmatter, code, raw HTML, comments, mathematics, or another protected
construct. Source owns none of the input lists. Each accepted suggestion is one
editor transaction and one Undo event; it never creates another buffer,
selection, focus owner, or writable projection.

Document statistics are derived from the current unsaved body and never stored.
A nonempty selection changes the scope to that selection; clearing it returns to
the complete body. **English words** are Unicode letter-or-number runs in Latin
script, retaining internal apostrophes or hyphens. **Chinese characters** count
each Han character. **Characters** count Unicode extended grapheme clusters in
visible authored text. YAML, Markdown delimiters, code-fence delimiters, and
link destinations are excluded; visible link labels, image alternative text,
code content, and punctuation remain in the character total. Other scripts
remain in Characters without being mislabeled as English words or Chinese
characters. Statistics never retain history or claim an exact source-byte
count.

Spelling and grammar use the installed macOS text services. Scholium exposes the
standard Edit-menu and contextual routes and does not ship a dictionary,
language detector, correction model, or persistent spelling profile.

Image attachment management has exactly two explicit routes. **Import Image…**
copies one researcher-selected supported image into the current vault at
`Attachments/<attachment-uuid>/<original-filename>` without replacement,
records its stable identity and vault-relative path, and inserts one ordinary
relative Markdown image link into the current Edit or Source buffer. Pasting
image bytes or a copied image file always uses this Import route.

**Index Image…** validates but does not copy the selected image, records its
stable identity and standardized absolute Finder path, and inserts that
percent-encoded absolute path as the ordinary Markdown image destination. A
read-only security-scoped bookmark may be retained only in machine-local
Application Support so Scholium can check access after relaunch; bookmark bytes
never enter `.scholium` or Markdown and never replace the authored absolute path
as location authority. If the path later becomes missing, inaccessible, moved,
or stale, Scholium reports that the indexed attachment is unavailable and does
not search for, relink, repair, copy, move, or delete it.

In both routes the source link remains authoritative and meaningful in other
Markdown editors; the catalog never regenerates or silently repairs it. Import,
Index, catalog, bookmark, stale-source, or editor failure inserts no link and
rolls back only state exactly created by that failed operation. Scholium never
uploads, deletes, moves, or rewrites an attachment as a side effect of editing
or deleting a Note.

Rendered callouts hide generated role names visually but retain them for
accessibility. A supplied title inherits the role heading style; an untitled
callout adds no heading. Ordinary Body prose uses the selected Appearance's
alignment; the canonical default is justified without hyphenation. Callout,
table, code, mathematics, footnote, and ordinary-quotation composition remains
owned by each protected object rule rather than inheriting Body alignment
indiscriminately.

A title-only Callout remains visibly rendered rather than disappearing when a
following line is created or the caret leaves it. Because **Orient** has no
visible role heading, an author-supplied Orient title becomes its Body prose
when no authored Body exists; it is neither duplicated nor replaced by the
generated role name. In Edit, an active Callout retains one quiet block surface.
Only the physical line containing a collapsed caret exposes its exact quote and
role markers; a nonempty selection exposes only the physical lines it intersects.
Every other line keeps its construct-scoped projection.

Return on a nonempty Callout line inserts a newline with that line's exact
quote prefix. When that line is a list item, the same transaction additionally
continues its current indentation, list kind, task form, and ordered-list
sequence inside the Callout. Return on an empty quoted list item removes only
its list prefix and leaves the empty quoted line; Return on that line containing
only `>` plus optional spacing then removes the quote prefix and exits the
Callout. Each operation is one editor transaction and one Undo event.
Source remains ordinary exact text and applies neither continuation rule nor
Edit projection.

An inactive Edit callout atomically projects one half-open source range, but
the insertion point immediately after its last content character remains
editable Callout content. Down Arrow or Right Arrow from above enters at the
range start; Up Arrow from below or a pointer press on its rendered title/body
enters at that content-end insertion point. One further horizontal move enters
the real authored separator line. Nested inline constructs inside an active
Callout retain the same construct-scoped projection rules as ordinary prose.
Only the disclosure mark changes fold state by pointer; the focused summary
retains keyboard disclosure.

Review and Edit support Obsidian-compatible inline `$…$` and display
`$$…$$` mathematics outside YAML, code, raw HTML, comments, and escaped
delimiters. The immutable editing dialect owns exact delimiter behavior.
Malformed or unsupported mathematics stays visible as exact source with a
diagnostic; rendering never rewrites it.

Review and Edit render a fenced code block whose case-insensitive info-string
token is exactly `mermaid` as an authored diagram. The exactly pinned, local
Mermaid runtime determines the supported built-in diagram families; Scholium
does not maintain a narrower diagram-type list. Review renders on document
load. In Edit, an inactive block renders once, a direct pointer or keyboard
entry reveals its complete exact fenced source in the same editor state, and
the opening delimiter and info string, complete body, and closing delimiter all
remain visible while any selection intersects the block. The latest source
renders again only after the selection leaves the complete block. Mermaid never
renders incrementally while the researcher is typing in that block. Source
always exposes the exact fence, info string, and content.

Rendered Mermaid retains its intrinsic size when it is narrower than the
document measure and scales down proportionally when it is wider or exceeds the
bounded diagram viewport height; it does not force a narrow diagram to fill the
measure or require document-level horizontal scrolling. Diagram fills, labels,
borders, and relationship lines derive only from Scholium's protected semantic
document palette rather than Mermaid's independent multicolor scales. Review
and inactive Edit use the same projection geometry and styling.

Mermaid is a static illustration projection, not evidence, a Connection, an
argument endorsement, or a second source authority. It uses no network or
remote resources and cannot activate links, callbacks, scripts, arbitrary
initialization directives, diagram-local executable behavior, or injectable
custom styles. Unsupported, malformed, over-limit, or prohibited input keeps
its source visible with a textual diagnostic and is never repaired or
rewritten. Authored `accTitle` and `accDescr` supply the diagram's nonvisual
account. Their absence is a visible accessibility diagnostic; Scholium retains
the exact source as an assistive alternative and never invents an
interpretation of the philosophical structure. Review retains ordinary
selection and copying for the diagram, but a selection intersecting either a
rendered Mermaid projection or its visible source fallback is not a passage
Comment target and exposes no Comment bar.
The projection does not broaden, replace, or remap a precise selection in
surrounding Review prose. In Edit, activating the block preserves ordinary
UTF-16 source selection over the exact fence and body rather than selecting the
generated SVG or a whole-block surrogate.

Review and inactive Edit render an Obsidian-compatible `![[Target]]` embed as
one finite-height embedded Note rather than as inline link text. The embedded
surface presents the target Note's complete committed body through the same
fingerprint-bound, read-only Markdown projection, document typography,
semantic components, Appearance, and accessibility rules as its containing
Document. Its bounded viewport scrolls independently, exposes a named route to
open the target Note, and never becomes editable, writable source or another
rendering owner. A heading or block fragment may identify the target but does
not truncate the embedded Note; an alias affects only its visible identity.
The active Edit construct and Source expose the exact embed syntax. Missing,
ambiguous, stale, or unavailable targets remain source-located and visibly
diagnosed rather than displaying invented content. An embed creates no
philosophical relationship edge and never recursively transcludes embeds found
inside its projected target.

Internal links and Vector Links provide bounded previews without becoming
evidence or another source authority. A Note preview presents its title once,
omits the link type, and renders target content through the same protected
Document styles as Review and inactive Edit. Its content may scroll inside the
bounded preview; moving the pointer from the link into that preview keeps it
available, and a brief exit grace prevents the gap between them from dismissing
it before the pointer arrives. Escape, viewport exit, and explicit navigation
remain immediate dismissal routes. Review additionally previews footnote
references on ordinary hover; a footnote preview contains only the referenced
definition. Footnote preview and return controls belong to Review, with
keyboard and accessibility-equivalent routes. Edit projects an inactive
reference as a numbered locator; activating it moves the caret to that named
definition. Its definition marker remains exact and directly editable at that
one source position; its body uses the same construct-scoped Edit projection as
ordinary Markdown and reveals only the active construct's exact syntax. It is
never copied into a second rendered editable block. Inserting a
named footnote appends one definition without renumbering existing identifiers
and places the Edit selection in that definition. Undefined and duplicate
forms remain exact source rather than being silently repaired. Source exposes
and edits the same exact reference and definition text.

Review and Edit have a direct keyboard toggle. Source is entered through
the mode menu. It may alter protected or machine-facing YAML; the researcher
accepts responsibility, while Scholium still performs targeted, byte-preserving
validation and never reserializes the whole frontmatter.

Modes add no floating Metadata surface over the text. Initial
top clearance belongs to the scrolling document.

### 5.2 Authored YAML and Scholium Metadata

[Appendix A](11-metadata-and-critique.md#shared-authored-yaml) owns the closed
authored-YAML allowlist, value shapes, and managed-new-note scaffold. Every
other YAML key is custom source: its exact bytes, comments, order, quoting,
multiline style, newlines, and delimiters remain preserved, but it grants no
title, About, Search-field, linking, Agent, or creation semantics. Scholium
does not alias, reinterpret, or automatically convert noncanonical keys.

`summary` and `keywords` remain visible and editable in Source and may
participate in About and Search. Their use creates no source abstract, Skill,
unified stance, completeness claim, Researcher State, acceptance, or writer
proof. Literal `property:` Search addressability does not grant any other YAML
key canonical meaning.

All other canonical structured values are **Scholium Metadata**. The
researcher owns every value; Scholium owns the role-aware schema, storage
format, validation, and compare-and-swap transaction. One portable JSON record
at `.scholium/note-metadata/v1/<stable-note-uuid>.json` belongs to one stable
Note identity. It is neither Markdown nor a writable projection of Markdown,
and it never reconstructs or rewrites source. A missing record means no managed
values. Damaged, future, orphaned, wrong-role, or concurrently changed records
fail closed and retain their exact bytes for recovery. A damaged record blocks
publication until the researcher confirms archiving that one filename and
fingerprint to a non-record sibling. A changed record cancels recovery; valid
neighboring records, source, and the remaining portable-control owner are never
archived with it.

[Appendix A](11-metadata-and-critique.md#appendix-a-metadata-catalogs-and-settings)
owns built-in catalogs, source-type applicability, researcher-defined fields,
About order, and Agent preferences. The workspace resolves them into one
role-specific catalog for validation, editing, Search, Library filters, About,
and Agent field plans. A definition creates no value or authored content.
Scholium validates shape and structural safety, never bibliographic or
philosophical truth.

Analysis managed `title` resolves display identity before the first H1 and
filename. Topic and Work resolve first H1, then filename. YAML `title` never
resolves identity. Rename never synchronizes managed title or H1. One resolver
supplies Workspace, Search, Link Graph, and Research Actions.

New Note YAML and Zotero binding are separate contracts and are never inferred
from managed Metadata. Identity, fingerprints, provenance, bindings,
timestamps, permissions, and app facts are not researcher-managed fields.

The **Metadata** sheet edits only the current Note's Scholium-managed record.
It offers fields from the current resolved role catalog on demand, validates
the complete candidate, and
saves against the exact loaded metadata revision. Creating the first field
does not create YAML; editing metadata remains available when authored YAML is
absent or malformed. A concurrent metadata change preserves the draft and
requires a reload instead of overwriting. About composes selected managed
values with authored `summary` and `keywords`, omits absent or empty values,
and preserves semantic group names for assistive technology.

The researcher CLI uses the same Application-owned record operation:
`note metadata-read` returns source and Metadata fingerprints plus natural JSON
values; `note metadata-set` and `note metadata-remove` require the exact current
Metadata fingerprint (or explicit `absent` creation) and never use the source
fingerprint as Metadata authority. They do not open or rewrite YAML.

This metadata boundary imposes no body schema. Scholium never inserts,
migrates, requires, or interprets body sections such as detailed summaries,
source basis, limitations, or research notes. The researcher decides what the
Markdown body contains.

Opening, copying, or exporting one Markdown file carries only that authored
file; Scholium Metadata is not injected for convenience. Moving or synchronizing
the complete Triptych carries the portable `.scholium/note-metadata/` records
with their stable identities. Any future flattened export that includes
managed fields requires an explicit destination format and remains a derived,
non-round-trippable export rather than a new source authority.

### 5.3 Create, duplicate, rename, and identity

**New Note** and **New Folder** are immediate, nonmodal actions. The
Library-header Add menu and **File → New Note** create at the current vault
root. Folder-row creation targets that exact vault-relative folder. Section
18.3 owns the equivalent pointer, menu, and accessibility routes.

An ordinary folder context menu is compact and ordered by semantic group:

1. **New Note**, **New Folder**, **Rename Folder…**, and **Move Folder…**;
2. **Expand All** or **Collapse All** when the folder has descendants;
3. **Copy Relative Path** and **Reveal in Finder**;
4. destructive **Move Folder and Notes to Trash…** at the bottom.

Expansion mutates only window-local disclosure state. Copy and Reveal expose
the exact existing vault-relative folder without changing research source.
An ordinary note row exposes **Rename…** rather than combining naming and
placement in one command. It is a direct one-item drag source: dropping it on
an ordinary Folder moves it into that exact folder, while dropping it on the
Library header moves it to the current vault root. The drop target
highlights only while it can accept the note; a successful move keeps that note
selected at its destination. Collision, stale revision, unresolved identity,
cross-vault placement, managed Critique placement, or source mutation failure
changes nothing and reports the reason. **File → Move Note…** and the named
accessibility action remain the non-drag placement routes; drag is never the
only way to move a note. Copy Relative Path and Reveal in Finder remain beside
the existing open and file actions, while Open in New Tab, Rename, Move,
Copy, and Reveal remain available without secondary click.

An ordinary mutable Folder is likewise a direct one-item drag source. Dropping
it on another ordinary Folder moves the complete source folder inside that
destination; dropping it on the Library header moves it to the current
vault root. The process-private payload contains only its exact vault and path,
and a target advertises Move only after rejecting cross-vault placement, the
current parent, the source itself, and every source descendant. Completion uses
the same flush-and-recheck folder Move transaction described below. A rejected
or failed drop changes no source or disclosure. **Move Folder…** and the named
accessibility action remain the non-drag route.

A folder is only a vault-relative filesystem location used for classification.
It has no UUID, Metadata, Research Record, recovery identity, or independent
application identity. Empty folders remain visible in Library. **New Folder**
immediately and atomically claims `Untitled Folder`, `Untitled Folder 2`, and so
on inside the clicked folder; it opens no sheet. Once that directory claim is
durable, the exact window installs it immediately and the Workspace completes
folder inventory and disposable derived projections in its owned background
refresh. Creation never waits for graph, Search, or research-state assembly.
Rename and Move use one scoped sheet only because the researcher must supply a
name or destination.

A confirmed folder rename or move flushes every open editor in the Triptych,
rechecks the complete descendant Markdown path-and-fingerprint inventory, and
then renames the directory entry once without replacement. Each descendant note
retains its stable identity; all identity paths are rebound in one portable
state write, app-owned path projections resume idempotently, and only exact
already-resolved incoming links are rewritten against one future graph.
Ambiguous links, a changed inventory, a symlink boundary, moving into the
source subtree, or any destination collision aborts the operation. A failed
link transaction rolls back or leaves durable recovery evidence. Non-Markdown
contents move with the same directory without being parsed or rewritten.

**Move Folder and Notes to Trash…** requires the system-Trash confirmation in
section 6. It submits the source directory as one native filesystem item and
includes the complete hidden, non-Markdown, empty-directory, and Markdown
descendant manifest in preflight. A managed Critique outside the folder is a
separate disclosed source item. The folder itself has no stable identity.
Managed Critiques and ambiguous folder projections omit all source-mutating
folder actions. Every contextual operation has an equivalent accessibility
action; secondary click is never the only path.

Scholium atomically claims the first available path in the sequence
`Untitled.md`, `Untitled 2.md`, `Untitled 3.md`, and so on. It never replaces an
existing or comparison-equivalent path. A concurrent collision advances to the
next name; another error stops without creating a substitute elsewhere.
Successful creation selects and opens the note. Creation never presents a
sheet, popover, naming form, or required-metadata step; naming and Metadata
remain later explicit edits.

GUI, researcher CLI, and authenticated Agent creation share one
Application-owned managed creator. It composes the fixed authored-YAML scaffold
and complete source candidate once, atomically
claims the path, commits source, stable identity, and any typed managed metadata,
and jointly reads them back before publishing.
Import, Duplicate, Restore, external discovery, and managed Critique creation
retain their own complete-source contracts and do not inject the scaffold.

GUI New Note writes exactly `---\nsummary: null\nkeywords: []\n---\n`, then the
body with no inserted blank line. It opens directly in Edit,
places the caret at the exact body start, and gives the editor focus after mode
acknowledgement. `Untitled` is only the claimed path; no H1 or YAML title is
generated. A header-only note has an exact empty body even though source is
nonempty; later Review uses the body boundary, never raw byte count, for Empty
Note and does not start an empty renderer. Malformed frontmatter is never empty.

Typed Agent Analysis creation carries an `AnalysisSourceType` routing
discriminator plus zero or more valid applicable managed values. Application
derives managed `type` from that discriminator and writes managed values only
to the new identity-keyed metadata record. The Agent may also supply typed
`summary` and `keywords` values; omission retains the fixed unfilled scaffold.
No managed field is Agent-required. The Agent cannot send YAML fragments,
govern the body, or use create authority after the new identity exists.

Only after the source commit and latest authoritative Library projection are
available, successful creation clears active Library filters, expands only the
created note's folder ancestors, preserves every unrelated disclosure, and
reveals the selected row without moving keyboard focus into Library. Ordinary
sort order remains unchanged. A failure before
this presentation transition preserves the prior filters, disclosure, sort,
selection, and visible source.

Paths are locations; notes have stable app-owned identities. Duplication creates
a new identity, copies the exact source and current managed metadata values,
and inherits neither Settlement nor Research Records. A metadata-copy failure
is a committed-operation recovery warning, never a reason to repeat the source
duplication. Rename keeps
the current containing folder; Move changes placement by drag or the explicit
File/accessibility route. Confirmed moves and renames preserve records and
update resolved incoming links. Ambiguous
external rename keeps the note readable but blocks identity-dependent mutation,
Settle, record attachment, and Discussion anchor attachment until confirmation.

## 6. System Trash deletion and application cleanup

Scholium has one Library file tree. It owns no secondary holding area,
application Trash, restore command, or file-level erase command. **Move to
Trash…** and **Move Folder and Notes to Trash…** use the macOS system Trash.
Finder owns source restoration and final emptying. Cancel changes nothing.

Moving source and deleting Scholium application state are deliberately not one
atomic claim. Confirmation discloses two ordered boundaries:

1. every listed source item is moved with Foundation's native system-Trash
   operation; and
2. only after all source receipts are durable does Scholium discard affected
   active Discussions and delete every associated finished Research Record.

Preparation flushes every dirty editor in the Triptych, then freezes exact
vault-qualified paths, stable Note identities, fingerprints, complete folder
manifests, separately located managed Critiques, affected active Discussion
IDs, and finished Record IDs plus exact portable-byte fingerprints. A relevant
active Agent Run, unresolved write recovery, invalid local-execution authority
envelope,
identity ambiguity, source change, folder-manifest change, symlink or special
file, or Record/Discussion participation change blocks the operation before a
source move. The confirmation names each finished Record and warns when an
unaffected Note participates in a Record that will nevertheless be deleted.

Local execution files expose one stable, fingerprint-bound authority envelope
containing Run, Triptych, complete Note participation, and whether authority is
live, recovery-required, or terminal. System Trash depends on that envelope,
not on decoding the evolving private Run payload. An unsupported payload can
therefore block only a participating Note when its envelope retains live or
recovery authority; it never makes unrelated Notes undeletable. If that
participating payload cannot be decoded, the valid envelope scopes an explicit
**Archive and Continue** alert to the selected Notes. If an older, damaged, or
changed file has no valid envelope, the same alert covers the complete opaque
store set because narrower participation cannot be established. Cancel changes
nothing. Confirmation rechecks the exact scoped set, copies the fingerprinted
bytes into protected machine-local unsupported-data storage, removes only those
exact originals, disables the affected Runs, and retries preparation. It never
decodes, migrates, repairs, or rewrites those bytes and changes no research Note
or portable Research Record.

A finished Record is the indivisible provenance object. If any participating
Note is affected, the complete Record is deleted; participants are never
rewritten into placeholders. Record IDs are deduplicated across Note, Folder,
and Critique targets. Active Discussions touching an affected Note are
explicitly discarded after all source moves. The same cleanup prunes deleted
Record references from Note Review and removes machine-local execution and
Agent-change evidence only after finished Record deletion commits.

Settlement, stable Note identity, source-access provenance, Zotero binding, and
Critique association remain. They identify the researcher-governed Note and can
converge if Finder restores exact source. Finder restore does not restore a
deleted Research Record. A restored original path is reconciled against its
retained stable identity and exact bytes; a collision, ambiguous same-content
copy, or changed source requires the ordinary identity/conflict route rather
than silent reassignment. If the system Trash has been emptied, Scholium cannot
recreate the source.

Before the first native move, Scholium installs a Note-deletion gate and writes
one durable forward plan. Each source item has its own pending, moved, or
outcome-unknown receipt and the machine-local resulting Trash URL when known.
The native operation is bound to the exact checked directory entry before
Foundation receives it. A replacement that reaches the original path before
that binding is detected and preserved rather than retargeted into Trash. If
the process stops after binding but before a native result, the pending plan
resumes that same exact bound item; original-path absence alone does not turn a
known Scholium binding into an unknown Finder outcome.
For a Work whose managed Critique is elsewhere, or a Folder with an external
managed Critique, partial native success is representable: no Discussion or
Record cleanup begins until every disclosed source receipt is moved.

| Observed failure | Required outcome |
| --- | --- |
| Dirty save, external modification, identity drift, folder inventory drift, active Run, or portable-store issue before the plan | No source move and no application-state deletion. |
| Native move fails while the original path is still proven present | Retain the durable plan for retry; Records and Discussions remain. |
| Process stops after Scholium binds the exact directory entry but before Foundation returns | Resume the same bound item from the pending plan; do not accept or trash a replacement at the original path. |
| Process stops after a native move and its resulting URL is durable | Resume forward from that receipt; do not move the same item again. |
| The original path disappears without either a recoverable Scholium binding or a durable native result | Mark outcome unknown; do not infer success and do not delete Records. The researcher may inspect Finder and explicitly retain Records, which clears only the deletion gate and plan. |
| All source receipts exist but Discussion or Record deletion fails | Source remains under Finder ownership; restart resumes exact-fingerprint Record cleanup idempotently. |
| A Record was deleted but Note Review or local evidence cleanup fails | The durable Record-deletion marker proves the irreversible step; retry only the remaining cleanup. |
| Finder or a sync tool deletes or moves source without a Scholium plan | Refresh Search, Attention, open documents, and identity diagnostics only. Never infer Discussion or Record deletion. |
| Finder restores source after Record cleanup | Reconcile the retained Note identity and source state; do not recreate or fabricate Records. |

Watchers publish source absence, arrival, and rename observations but have no
authority to create a deletion plan. Multiple windows converge through the
workspace mutation lease and generation-bound refresh. The initiating window
flushes all editors before preparation and execution; committed source absence
closes only pages for missing documents while preserving unrelated tabs and
focus. Search and Attention remove absent source on the next owned refresh and
may surface identity or recovery diagnostics; they do not become deletion
authority.

## 7. Settlement, annotation, and Discussion

### 7.1 Settle

Settle is available for every active Analysis, Topic, and Work as a quiet
current-note action. It binds to the exact saved fingerprint, accepts an
optional rationale, records date and researcher identity, and never blocks on
an agent response or Fidelity warning. Repeating Settle for the current
fingerprint may update the rationale, date, or researcher judgment.
Save failure, dirty conflict, unknown stable identity, or a revision mismatch
blocks Settle. A later saved fingerprint keeps the prior statement, offers
**Settle Again**, and may produce **Changed Since Settled** in Attention. Settle
is neither a Research Record list row nor an activity-history node. Each Note
has one portable Settlement marker; Settle replaces that marker and stores no
Markdown bytes, historical versions, restore source, retention policy, or
pruning state. It remains useful as current research-state metadata and as the
basis for **Changed Since Settled**.

### 7.2 Discussion, Comment, and written annotation

Review exposes **Comment** for a nonempty passage selection; Edit and Source do
not. Review selection reveals one compact contextual Comment bar near the
text. Edit selection instead reveals only the common formatting commands valid
for that exact selection. A pointer-created Comment or formatting bar remains
hidden throughout selection and appears only after the primary-button gesture
finishes; a completed keyboard selection may reveal it immediately. The Format
menu and keyboard retain equivalent formatting routes. The editor's
secondary-click menu consumes that same finalized editor selection and
starts with **Cut**, **Copy**, **Paste**, and **Select All**; it then adds only
operations whose meaning depends on one collapsed clicked construct. It does
not duplicate common formatting, inherit generic Autofill or Services
hierarchies, or contain a Preview command or Preview submenu. Footnote hover,
focus, and navigation belong to Review only; Edit retains only the ordinary
cursor-placement needed to reach the underlying Markdown, and Source exposes
the exact text. Markdown has no bundled underline command.

A Review selection intersecting a protected Mermaid projection, including its
visible failure fallback, does not expose Comment or publish a passage target.
The selection and ordinary copying remain available; surrounding authored prose
remains commentable. Scholium never guesses a line anchor from generated SVG
text or converts a diagram-node selection into a whole-fence Comment.

Comment expands the contextual bar in place into a bounded multiline field.
Return saves and closes it, Shift-Return inserts a line break, and Escape
cancels. Return enters a brief saving state; the field closes only after
Scholium confirms the portable write. A failed write keeps the exact Comment
text in place for retry, while a committed write with stale derived views is
reported as saved rather than invited to duplicate. Saving creates or appends a researcher-authored line Comment inside
the current note's active Discussion without copying instructions, opening an
agent application, or presenting a sheet. A line Comment records only the
stable Note, the exact Note fingerprint, and its one-based inclusive starting
and ending lines; selection text, quotation, surrounding context, and exact
byte or UTF-16 offsets are neither stored in that Comment nor sent to an agent.
Review may use the current rendered selection transiently to resolve its actual
Markdown source lines before discarding the selection payload. The submission
remains bound to the original stable Note and exact fingerprint; changing the
Note, revision, mode, or editor generation cannot redirect it.
If the Note later changes, the original revision-bound line location remains
truthful and is not guessed or reattached.

**Discuss** is the deliberate agent-interaction boundary. It automatically
includes the current Note's existing line Comments, permits an optional
unanchored whole-note turn and focal notes, and opens the one active Discussion
when it already has a resolved Discuss Action. A Comment-only draft first opens
the ordinary Discuss Action. Every new Discuss Action begins with a concise,
editable request to discuss the Note including any existing Comments, so the
researcher need not restate this routine collection rule; preparation freezes
the registered primary Skill text, resolved Practices, optional folder-path
string, and Result Contract for that same Discussion and preserves every
Comment before any Agent handoff. Later handoffs reload those Run-frozen
contracts rather than constructing an application-owned substitute prompt.
Comments and Discuss remain one Discussion model, not
parallel archives, but adding a Comment never initiates Discuss or an agent
handoff.

Discussion begins without source mutation. It remains resumable through
researcher turns, attributed Agent replies, and any separately authorized
next Action. Closing its sheet retains the draft. **Finish Discussion** moves
the complete exchange into one portable Research Record; Finish means only
that the exchange is no longer active and implies no approval, rejection,
truth, failure, or settlement.

Scholium has no app-owned Annotation record, marginal-note store, Annotation
action, or overlay. A researcher annotates a document authoritatively by
editing its Markdown, including an ordinary semantic Callout when a visibly
separate note is useful.
