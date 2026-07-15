# Adversarial and fidelity fixtures

`Docs/PRODUCT_GUIDE.md` owns target behavior. Proposal and Research Session fixtures below preserve current-build migration safety; target additions must cover Dialogue identity, app-owned replies, Triptych checkpoints, and direct-external-edit conflicts.

## Paths and filesystem

- `../`, absolute paths, repeated separators, `.` components, and percent-like text that must not be decoded unexpectedly;
- symlink inside the vault pointing outside, symlinked parent, replaced symlink after validation, and dangling symlink;
- nonexistent target, directory with `.md` suffix, device/socket where constructible, unreadable file, and read-only parent;
- Unicode normalization collisions, case-only differences, leading/trailing spaces, emoji, CJK, combining marks, and very long names;
- atomic-write failure and snapshot-directory failure.

## Exact Markdown and frontmatter

- UTF-8 BOM; LF and CRLF; no final newline and multiple final newlines;
- no frontmatter, empty frontmatter, malformed YAML, comments, anchors, aliases, tags, quoted scalars, block scalars, nested mappings, sequences, duplicate-looking legacy keys, and `---` in the body;
- large notes, empty bodies, NUL rejection, unusual Unicode, and wikilinks inside code or comments;
- body-only edit, one-property edit, save timestamp update, restoration, and conflict after external modification.

## Identity and proposals

- two vaults with the same folder name, note title, and relative path;
- moved or renamed vault with stable identity expectations made explicit;
- proposal with wrong vault ID, wrong path, stale fingerprint, malformed frontmatter, missing target, and changed target type;
- proposal replay and double approval;
- proposal that attempts to create a file, write generated state into the vault, or modify more content than previewed.

## Web, CSS, export, and external data

- Markdown containing scripts, event-handler attributes, `javascript:` links, remote resources, file URLs, data URLs, and malformed internal links;
- JavaScript messages with wrong name, type, document identity, version, missing fields, oversized payload, stale session, unexpected extra data, and delivery after navigation or WebView restart;
- an editor or reader document that attempts network fetch, filesystem navigation, popup creation, or message delivery outside the declared CSP and Swift navigation policy;
- CSS containing imports, URLs, protected selectors, app-chrome selectors, cascade escape, unsafe layout, misleading evidence/status decoration, malformed comments, and oversized input;
- cancelled, failed, or partially written HTML/PDF export; hostile titles/paths; unselected review material; remote media; raw HTML; and provenance inclusion toggles;
- Zotero localhost API unavailable, disabled, malformed, or returning the wrong key; confirm Scholium does not enumerate children or attachments, crawl unrelated items, or open a write connection.

## Workflow and agent-facing state

- saved searches, research sessions, and workflow bridges with wrong vault identity, stale note fingerprint, unknown role, widened privacy, cross-vault replay, or malformed persistence;
- Agent Review request with a changed target revision, unsupported vault role, copied private text, or attempted direct apply;
- topic reference with multiline input, duplicate content, wrong vault role, stale revision, YAML-free CRLF source, malformed callout, or CLI direct-write attempt;
- proposal/session combinations in which an agent-created task attempts bounded-write permission or an unauthorized durability checkpoint.

For every fixture, state whether the expected result is acceptance with exact preservation, visible diagnostic, conflict, or rejection.
