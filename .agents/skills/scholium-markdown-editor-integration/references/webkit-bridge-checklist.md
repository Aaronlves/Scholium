# Active CodeMirror and WKWebView bridge checklist

Use this checklist for the active CodeMirror Source/Live Preview surface and sanitized WKWebView Read projection.

## Source and synchronization

- Load the exact source into CodeMirror with a new session ID, document ID, starting fingerprint, and document version zero.
- Send every edit as bounded UTF-16 `from`, `to`, and insertion values with one contiguous document-version increment.
- Apply deltas to the same Swift mirror and reject stale, repeated, skipped, overlapping-invalid, or out-of-bounds changes.
- Before save or autosave, request the complete CodeMirror text and compare it with the mirror.
- On mismatch, reconcile to the complete editor text while retaining dirty state; never save a stale mirror or synthesize source from rendered content.
- Run the reconciled string through expected-revision conflict detection and the transactional repository save path.

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
- Exclude literal, escaped, comment, code, HTML, and frontmatter regions consistently with `MarkdownSemanticDocument`.
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
