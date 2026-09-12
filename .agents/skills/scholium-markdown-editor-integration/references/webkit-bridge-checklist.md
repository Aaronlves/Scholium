# Web-based editor and reader bridge checklist

Use this checklist only when live construction confirms a web-based editor or
reader boundary. Derive current mode names, handler names, envelope fields, and
adapter symbols from the implementation architecture and live protocol.

## Source and synchronization

- Resolve the current session, revision, generation, and range contract from
  the typed bridge. Do not infer field names or initialization values here.
- Distinguish CodeMirror's normalized editing representation from the exact
  source mirror and its full-source snapshot. Reading the editor's normalized
  text alone cannot establish preserved CRLF bytes.
- Follow the existing offset map between editor and exact-source coordinates;
  validate deltas against the same generation and declared coordinate system.
- Compare accepted changes with the checked native mirror; reject stale,
  repeated, skipped, invalid, or out-of-bounds messages under the live protocol.
- Before persistence, obtain the boundary's exact-source snapshot and reconcile
  it against the native mirror while preserving dirty state on mismatch.
  Do not rebuild source from rendered output or a normalized text dump.
- Preserve the transactional save's expected-revision checks after successful
  reconciliation; editor agreement does not prove current disk agreement.
- Exercise the smallest representative edit across each implicated conversion,
  comparing exact bytes and mapped source ranges, not only displayed text.

## Configuration and lifetime

- Construct configuration, nonpersistent data store, preferences, content controller, handlers, and scripts before the web view.
- Centralize handler names and remove them during dismantle or coordinator teardown.
- Cancel startup, focus, save, and synchronization work when vault, document, fingerprint, or session changes.
- Require delayed callbacks to match the active session and document before changing Swift or JavaScript state.
- Keep Source and Live Preview on one persistent CodeMirror state; do not reload the page to switch modes.

## Message validation

- Accept only registered message names and known message types.
- Decode typed payloads; reject unexpected types, missing fields, unknown versions, and oversized data.
- Require the active session ID, document ID, starting fingerprint, and a valid document version for state, edit, and save messages.
- Distinguish edit deltas, selection/status changes, save requests, ready state, and errors.
- Treat JavaScript dirty state as user-interface state, never as filesystem authorization.

## Swift-to-JavaScript calls

- Encode source, CSS, identifiers, completion items, and modes as JSON values rather than script fragments assembled from unescaped text.
- Propagate evaluation and load failures to visible recoverable state.
- Coalesce redundant source pushes and reject callbacks for replaced documents or sessions.
- Do not call `setDocument` during active IME composition unless the current buffer is first preserved and the interruption is explicitly recoverable.

## Projection and interaction

- Limit Live Preview decoration work to visible ranges plus required structural context.
- Reveal exact syntax when the insertion point or selection enters a projected construct.
- Exclude literal, escaped, comment, code, HTML, and frontmatter regions
  consistently with the live semantic Markdown projection.
- Preserve CodeMirror selection, scroll, history, marked text, focus, find/replace, and completion behavior.
- Give semantic widgets accurate accessible labels and keep the underlying source reachable for editing.
- Keep Read output fingerprint-bound and source-located; never allow Read JavaScript to mutate Markdown.

## Navigation and content security

- Start with `default-src 'none'`; allow only the minimum inline bundled script/style and data/font resources needed by the reviewed surface.
- Keep network connections and remote subresources disabled.
- Allow only the controlled initial in-memory navigation. Cancel unexpected `javascript:`, `file:`, `data:`, custom-scheme, and redirected navigation.
- Route explicitly approved external links through native policy and validate internal-link payloads before opening a note.
- Sanitize Markdown and user CSS before insertion; never allow research text to become executable markup.

## Behavioral tests

Select the affected boundary and a neighboring case; this is a menu, not a
requirement to run every journey for every bridge change. For a range defect,
use a minimal Unicode/CRLF fixture before a full app journey. For lifetime or
focus claims, preserve the native runtime evidence requirement.

- initial handshake, source load, and missing/stale bundle failure;
- exact UTF-16 deltas with emoji, combining marks, CJK, and CRLF;
- dropped, repeated, out-of-order, oversized, and stale-session messages;
- full-buffer reconciliation before manual and debounced saves;
- rapid A -> B -> A switching and teardown/recreation;
- Source, Live Preview, and Read transitions with pending edits;
- cursor, multi-range selection, scroll, undo, focus, find, and IME composition;
- internal, external, broken, and malicious links and navigation;
- failed save and external conflict without buffer loss;
- large documents, viewport projection, VoiceOver, and keyboard-only operation.
