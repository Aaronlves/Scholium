---
name: scholium-markdown-editor-integration
description: "Implement, diagnose, or test Scholium CodeMirror/WKWebView editing, reader projection, and native text-session integration."
---

# Scholium Markdown Editor Integration

Preserve one exact Markdown buffer across editing, persistence, and
presentation. Rendered or decorated forms never become writable source.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).

## Find the first divergent state

Follow one input through native event delivery, CodeMirror transaction, exact
source mapping, bridge message, checked native mirror, persistence, and reader
projection. Compare identity, generation, offsets, and bytes at the first
mismatch instead of forcing a reload to hide it.

Keep normalized editor text distinct from line-ending-preserving source.
A DOM range, editor UTF-16 offset, source UTF-16 offset, and UTF-8 byte offset
are not interchangeable. Check the existing mapping with BOM, CRLF, a non-BMP
character, and a decomposed character when the defect concerns ranges; do not
normalize source to make coordinates agree.

For text loss or save mismatch, inspect the exact-source snapshot and generation
admission. For selection, Undo, or IME defects, inspect transaction origin,
composition lifetime, and replacement of the persistent editor session. For
reader defects, inspect committed revision and source-locator projection rather
than routing reader state back into the editor.

Load the [bridge checklist](references/webkit-bridge-checklist.md) only for the
affected boundary. Keep a fix at its owner, regenerate changed bundled assets
through repository scripts, and verify both exact source and the affected
interaction. A passing JavaScript transformation does not establish native
focus or composition behavior.

## Invariants

- One editing session owns text history; native code may hold only a checked
  mirror. Never reconstruct Markdown from HTML, decorations, parsed metadata,
  or semantic nodes.
- Bridge changes are versioned, bounded, ordered, and bound to document,
  session, and starting revision. Reject stale, repeated, skipped, or invalid
  messages.
- Reconcile the live full buffer before persistence and keep unexplained
  mismatch visible and dirty. Reconciliation never authorizes overwriting an
  external change.
- Presentation changes preserve source, selection, scroll, undo, focus,
  composition, marked text, and current identity. Decorations do not enter
  history.
- Reader output is derived from the committed revision and cannot grant
  mutation authority.
- Keep the Web boundary local, typed, size-bounded, navigation-controlled, and
  free of ambient network or filesystem access.
- Do not replace text or force selection during composition. Preserve standard
  keyboard, accessibility, clipboard, spelling, find, and text-service paths.

## Evidence

Use disposable documents spanning the affected source and Unicode boundaries,
then exercise ordering, switching, mismatch, save failure, conflict, process
recovery, composition, undo, focus, and accessibility as applicable. Run the
current editor asset checks and focused suites; use isolated UI automation for
runtime-only claims. Apply the verification cadence in `AGENTS.md`; do not
infer a complete repository or UI gate from editor scope. Report any input path
not exercised.
