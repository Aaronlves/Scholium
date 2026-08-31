# Specification: Notes and File Operations

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 5–7.

## 5. Common note capabilities

Analysis, Topic, and ordinary Work Notes support Review, Edit, and Source over
one exact Markdown buffer; autosave; create, duplicate, import, rename, move,
Reveal in Finder, and system-Trash deletion; Search, Find/Replace, Connect,
Comments, Metadata, Research Actions, Records, conflicts, and recovery.
Critique bodies are read-only in Scholium but remain ordinary externally
editable Markdown.

### 5.1 Document modes and YAML

- **Review** renders committed content for reading, navigation, selection, and
  Comment.
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
  are diagnosed. Generated diagram content is not a passage Comment target.
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
owns catalogs, applicability, custom fields, About order, and Agent field
preferences. One role-specific resolved catalog serves validation, Metadata,
Search, Library filters, About, and Agent plans. A definition creates no value.
Scholium validates shape and structural safety, not bibliographic or
philosophical truth.

Analysis display identity resolves managed `title`, then first H1, then
filename. Topic and Work resolve first H1, then filename. YAML `title` has no
identity semantics. Rename never synchronizes Metadata or H1.

The Metadata sheet edits only the current Note's managed record at its loaded
revision. It preserves drafts on conflict and never creates or changes YAML.
About shows only selected nonempty managed values plus authored `summary` and
`keywords`. CLI metadata read/set/remove operations use the same owner and
Metadata fingerprint, never the source fingerprint.

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
authenticated Agent routes. GUI creation writes exactly:

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

Agent Analysis creation supplies a typed source discriminator plus optional
applicable managed and authored values. The Application derives managed
`type`, accepts no YAML fragments, and grants no continuing create authority
after the identity exists.

A successful source-and-identity commit appears immediately in Library; derived
indexes refresh afterward without blocking writing. Presentation failure must
not invite duplicate creation.

Paths are locations; Notes have stable app-owned identities. Duplicate creates
a new identity and copies exact source plus current managed values, but not
Settlement or Records. Rename and Move preserve identity, Records, and exact
resolved incoming-link updates. Ambiguous external rename keeps source readable
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

## 6. System Trash deletion and application cleanup

Scholium has no application Trash, erase command, or source restore command.
**Move to Trash…** and **Move Folder and Notes to Trash…** use the macOS system
Trash; Finder owns restoration and final deletion.

Confirmation discloses two ordered boundaries:

1. move every listed source item to system Trash; then
2. after all move receipts are durable, discard affected active Discussions and
   delete each complete Research Record involving an affected Note.

Preparation flushes dirty editors and freezes exact paths, identities,
fingerprints, folder contents, separately located managed Critiques,
Discussions, Records, and portable-byte fingerprints. Active Agent work,
unresolved write recovery, identity ambiguity, source or manifest drift,
unsafe filesystem entries, or changing Record participation blocks the move.

A finished Record is indivisible provenance: if any participant is deleted,
the complete Record is deleted. Stable Note identity, Settlement, Zotero
binding, source-access provenance, and Critique association remain so Finder
restoration can reconcile exact source; deleted Records are never recreated.

Before the first move Scholium installs a deletion gate and durable forward
plan with one receipt per source item. It binds each native operation to the
exact checked filesystem object, never a replacement that later appears at the
same path. Partial success is representable; Record and Discussion cleanup
waits for every source receipt.

Recovery follows these rules:

| Condition | Required outcome |
| --- | --- |
| Preflight or first-move failure | Preserve all source and application records. |
| Proven native move | Resume from its receipt; never move the item again. |
| Bound operation with unknown native outcome | Preserve Records; require researcher inspection before releasing the plan. |
| All source moved but cleanup failed | Resume exact-fingerprint cleanup idempotently. |
| External move or deletion without a Scholium plan | Refresh projections only; never cascade Record or Discussion deletion. |
| Finder restores source | Reconcile retained identity and bytes; never fabricate Records. |

Watchers report filesystem observations but cannot create deletion authority.
Multiple windows converge through shared workspace coordination. A committed
absence closes only affected pages and refreshes derived projections while
preserving unrelated tabs and focus.

## 7. Settlement, annotation, and Discussion

### 7.1 Settle

Settle binds an optional rationale, date, and researcher identity to the exact
saved fingerprint of any Analysis, Topic, or Work. Save failure, conflict,
unknown identity, or revision mismatch blocks it. Repeating Settle replaces the
current marker. The marker also covers every confirmed Agent-change activity
for that Note that exists when Settle commits. A later saved fingerprint or a
later confirmed Agent change preserves the prior judgment but makes the current
revision **Not Settled** and exposes **Settle Again**.

A persistent in-app Settlement reminder appears only after a confirmed Agent
source change or after a previously Settled Note changes. It remains until
Settle succeeds for the exact current saved revision. Opening Records, viewing
or closing a Diff, editing, restoring, changing windows, or dismissing another
notification never clears it. A never-Settled Note with no confirmed Agent
source change has no reminder.

Each Note has one portable Settlement marker and no separate reviewed marker.
It is not a Record, verdict, source version, restore point, retention policy,
or Agent requirement.

### 7.2 Discussion, Comment, and written annotation

Review exposes **Comment** for a nonempty commentable passage selection; Edit
exposes formatting instead, and Source exposes neither contextual surface.
Menu and keyboard routes remain equivalent. Protected generated Mermaid content
is selectable and copyable but not commentable.

A Comment field remains bound to the original stable Note, exact fingerprint,
and one-based inclusive source-line range. It stores the researcher's bounded
selected passage but no surrounding context or exact-offset reattachment
promise. Return saves, Shift-Return inserts a newline, Escape cancels, and a
failed portable write preserves the draft. A later source revision marks the
locator **Earlier revision** rather than guessing a new anchor.

Current-revision active Comments project as keyboard-reachable line markers.
Comments in the same Discussion and line range share one counted marker. The
marker opens the Discussion; the Discussion locator returns to Review. The
first successful Agent response removes active markers and retains the exchange
in its Record.

**Discuss** opens the one active Discussion for the current Note, includes its
Comments, and permits a whole-note request plus focal Notes. Comments may be
added until Agent handoff, never initiate an Agent on their own, and survive
sheet closure. Preparation freezes the Action configuration and Result
Contract. The first attributed Agent reply atomically creates one Record and
ends the active presentation. Explicit End preserves an unanswered exchange.
Neither route implies approval, truth, or Settlement.

Authoritative annotation remains Markdown, including semantic Callouts.
Scholium owns no separate writable Annotation store; Comment markers are
temporary projections of active Discussion.
