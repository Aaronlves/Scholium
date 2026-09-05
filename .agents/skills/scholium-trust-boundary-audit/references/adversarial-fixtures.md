# Adversarial and fidelity fixtures

The canonical specification manifest routes target behavior. Derive the
current writable, agent-facing, recovery, and external-data surfaces from only
its owning chapters, implementation status, live construction, and tests before
selecting fixtures. Unsupported source forms may be tested only for exact
preservation, visible rejection, and absence of current authority.

## Paths and filesystem

- `../`, absolute paths, repeated separators, `.` components, and percent-like text that must not be decoded unexpectedly;
- symlink inside the vault pointing outside, symlinked parent, replaced symlink after validation, and dangling symlink;
- nonexistent target, directory with `.md` suffix, device/socket where constructible, unreadable file, and read-only parent;
- Unicode normalization collisions, case-only differences, leading/trailing spaces, emoji, CJK, combining marks, and very long names;
- atomic-write failure and snapshot-directory failure.

## Exact Markdown and frontmatter

- UTF-8 BOM; LF and CRLF; no final newline and multiple final newlines;
- no frontmatter, empty frontmatter, malformed YAML, comments, anchors, aliases, tags, quoted scalars, block scalars, nested mappings, sequences, duplicate-looking unsupported keys, and `---` in the body;
- large notes, empty bodies, NUL rejection, unusual Unicode, and wikilinks inside code or comments;
- body-only edit, one-property edit, exact preservation of unsupported timestamps during ordinary saves, restoration, and conflict after external modification.

## Identity and mutations

- two vaults with the same folder name, note title, and relative path;
- moved or renamed vault with stable identity expectations made explicit;
- mutation with wrong vault ID, wrong path, stale fingerprint, malformed frontmatter, missing target, and changed target type;
- duplicate submission and cross-window replay;
- mutation that attempts to create an unauthorized file, write generated state into the vault, or modify more content than requested.

## Web, styles, and external data

- Markdown containing scripts, event-handler attributes, `javascript:` links, remote resources, file URLs, data URLs, and malformed internal links;
- JavaScript messages with wrong name, type, document identity, version, missing fields, oversized payload, stale session, unexpected extra data, and delivery after navigation or WebView restart;
- an editor or reader document that attempts network fetch, filesystem navigation, popup creation, or message delivery outside the declared CSP and Swift navigation policy;
- CSS containing imports, URLs, protected selectors, app-chrome selectors, cascade escape, unsafe layout, misleading evidence/status decoration, malformed comments, and oversized input;
- the currently documented external-data transport unavailable, disabled,
  malformed, overbroad, or returning mismatched identity; confirm the live
  adapter does not exceed its documented scope or write policy.

## Workflow and agent-facing state

- each current saved, agent-facing, review, or recovery record with wrong
  identity, stale revision, unknown role, widened privacy, cross-vault replay,
  or malformed persistence;
- agent request with a changed target revision, unsupported vault role, copied private text, or attempted unbounded mutation;
- each current recovery operation targeting the wrong revision, crossing vault
  identity, or claiming source support or researcher authorization.

## Unsupported pre-production data

Verify that unsupported data remains byte-unchanged and nonauthorizing. A
removed form must not regain a decoder, UI route, write permission, re-encoding
path, fallback, or historical workflow merely to make the fixture readable.

For every fixture, state whether the expected result is acceptance with exact preservation, visible diagnostic, conflict, or rejection.
